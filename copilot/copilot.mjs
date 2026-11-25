// BegBuddy Copilot — Safe Human-in-the-Loop /chatlog Watcher + DeepSeek Drafter + Local HTTP API
// NEVER injects keystrokes, NEVER clicks WoW, NEVER reads WoW memory.
// Reads WoWChatLog.txt -> drafts reply via DeepSeek -> copies to clipboard -> you press R, Ctrl+V, Enter.

import fs from "node:fs";
import path from "node:path";
import http from "node:http";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { parseChatLogLine, shortName } from "./parser.mjs";
import { generateReply, MODEL_PRESETS } from "./llm.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const LOCAL_CONFIG_PATH = path.join(__dirname, "config.local.json");

const DEFAULT_WOW_ROOT = "C:\\Program Files (x86)\\World of Warcraft";
const WOW_FLAVORS = ["_forever_", "_classic_era_", "_classic_beta_", "_anniversary_", "_classic_", "_retail_"];

export function loadLocalConfig(configPath = LOCAL_CONFIG_PATH) {
  const defaults = {
    location: "right outside the Stormwind AH steps",
    persona: "Friendly brand-new WoW Classic player trying to get their first bags and wand. Casual lowercase gamer style ('tysm', 'im', 'u', 'haha'). Warm, appreciative, never pushy.",
    autoCopy: true,
    preset: "cf-llama-fast",
    provider: "cloudflare",
    model: "@cf/meta/llama-3.1-8b-instruct-fp8-fast",
    cfAccountId: "",
    baseUrl: "https://api.deepseek.com",
    apiKeys: { cloudflare: "", deepseek: "" },
    wowRoot: DEFAULT_WOW_ROOT,
  };
  try {
    if (fs.existsSync(configPath)) {
      const saved = JSON.parse(fs.readFileSync(configPath, "utf8"));
      const merged = { ...defaults, ...saved };
      merged.apiKeys = { ...defaults.apiKeys, ...(saved.apiKeys || {}) };
      if (saved.apiKey && !merged.apiKeys[merged.provider || "cloudflare"]) {
        merged.apiKeys[merged.provider || "cloudflare"] = saved.apiKey;
      }
      delete merged.apiKey;
      return merged;
    }
  } catch { /* ignore corrupt config */ }
  return defaults;
}

export function saveLocalConfig(cfg, configPath = LOCAL_CONFIG_PATH) {
  fs.writeFileSync(configPath, JSON.stringify(cfg, null, 2) + "\n", "utf8");
}

export function copyToClipboard(text) {
  return new Promise((resolve) => {
    if (process.platform !== "win32") return resolve(false);
    // Use PowerShell Set-Clipboard via stdin to preserve UTF-8 without shell escaping bugs
    const ps = spawn("powershell.exe", [
      "-NoProfile", "-NonInteractive", "-Command",
      "$t = [Console]::In.ReadToEnd(); if ($t) { Set-Clipboard -Value $t }",
    ], { stdio: ["pipe", "ignore", "ignore"] });
    ps.on("error", () => resolve(false));
    ps.on("close", (code) => resolve(code === 0));
    ps.stdin.end(String(text || ""), "utf8");
  });
}

export function findActiveChatLog(wowRoot = DEFAULT_WOW_ROOT, customLog = null) {
  if (customLog) {
    return fs.existsSync(customLog) ? customLog : null;
  }
  let best = null;
  let bestMtime = 0;
  for (const flavor of WOW_FLAVORS) {
    const p = path.join(wowRoot, flavor, "Logs", "WoWChatLog.txt");
    try {
      const st = fs.statSync(p);
      if (st.mtimeMs > bestMtime) {
        bestMtime = st.mtimeMs;
        best = p;
      }
    } catch { /* not present */ }
  }
  return best;
}

export function redactKey(key) {
  const k = String(key || "").trim();
  if (!k) return "";
  if (k.length <= 6) return "****";
  return "****" + k.slice(-4);
}

export function createCopilot({
  configPath = LOCAL_CONFIG_PATH,
  customLog = null,
  fetchImpl = fetch,
  clipboardFn = copyToClipboard,
  pollMs = 500,
} = {}) {
  let config = loadLocalConfig(configPath);
  const threads = new Map(); // lower(sender) -> [{ dir, text, at }]
  const drafts = [];         // newest first, max 30
  let nextId = 1;
  let watchedFile = null;
  let fileOffset = 0;
  let partialLine = "";
  let pollTimer = null;
  let polling = false;
  let lastClipboardText = "";

  function pushThread(sender, dir, text) {
    const key = sender.toLowerCase();
    let list = threads.get(key);
    if (!list) { list = []; threads.set(key, list); }
    list.push({ dir, text, at: Date.now() });
    if (list.length > 20) list.splice(0, list.length - 20);
    return list;
  }

  function onAccountResolved(acctId) {
    if (acctId && acctId !== config.cfAccountId) {
      config.cfAccountId = acctId;
      try { saveLocalConfig(config, configPath); } catch { /* ignore */ }
    }
  }

  async function handleIncoming(sender, text) {
    const history = pushThread(sender, "in", text);
    const res = await generateReply({ sender, text, history, config, fetchImpl, onAccountResolved });
    const entry = {
      id: nextId++,
      at: Date.now(),
      sender,
      shortName: shortName(sender),
      incoming: text,
      reply: res.reply,
      intent: res.intent,
      skip: !!res.skip,
      source: res.source,
      latencyMs: res.latencyMs || 0,
      error: res.error || null,
      copied: false,
    };
    drafts.unshift(entry);
    if (drafts.length > 30) drafts.length = 30;

    if (config.autoCopy && !entry.skip && entry.reply) {
      const ok = await clipboardFn(entry.reply);
      entry.copied = !!ok;
      if (ok) lastClipboardText = entry.reply;
    }
    return entry;
  }

  async function processLine(line) {
    const parsed = parseChatLogLine(line);
    if (!parsed) return null;
    if (parsed.dir === "out") {
      pushThread(parsed.sender, "out", parsed.text);
      return null;
    }
    return handleIncoming(parsed.sender, parsed.text);
  }

  async function pollLog() {
    if (polling) return;
    polling = true;
    try {
      const active = findActiveChatLog(config.wowRoot, customLog);
      if (!active) {
        watchedFile = null;
        return;
      }
      if (active !== watchedFile) {
        watchedFile = active;
        try {
          fileOffset = fs.statSync(watchedFile).size; // tail from EOF on attach
        } catch { fileOffset = 0; }
        partialLine = "";
        return;
      }
      let st;
      try { st = fs.statSync(watchedFile); } catch { return; }
      if (st.size < fileOffset) {
        // Log rotated or truncated
        fileOffset = 0;
        partialLine = "";
      }
      if (st.size === fileOffset) return;

      const len = st.size - fileOffset;
      const buf = Buffer.alloc(len);
      const fd = fs.openSync(watchedFile, "r");
      try {
        fs.readSync(fd, buf, 0, len, fileOffset);
      } finally {
        fs.closeSync(fd);
      }
      fileOffset = st.size;

      const chunk = partialLine + buf.toString("utf8");
      const lines = chunk.split(/\r?\n/);
      partialLine = lines.pop() || "";
      for (const line of lines) {
        if (line.trim()) await processLine(line);
      }
    } finally {
      polling = false;
    }
  }

  function startWatching() {
    if (pollTimer) return;
    pollLog().catch(() => {});
    pollTimer = setInterval(() => { pollLog().catch(() => {}); }, pollMs);
  }

  function stopWatching() {
    if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
  }

  function getState() {
    const provider = config.provider || "cloudflare";
    const localKey = (config.apiKeys && config.apiKeys[provider]) || "";
    const envKey = provider === "cloudflare" ? process.env.CLOUDFLARE_API_TOKEN : process.env.DEEPSEEK_API_KEY;
    const activeKey = (localKey || envKey || "").trim();
    return {
      status: watchedFile ? "watching" : "waiting_for_chatlog",
      watchedFile,
      lastClipboardText,
      presets: MODEL_PRESETS,
      config: {
        location: config.location,
        persona: config.persona,
        autoCopy: !!config.autoCopy,
        preset: config.preset || "cf-llama-fast",
        provider,
        model: config.model,
        cfAccountSet: !!(config.cfAccountId || process.env.CLOUDFLARE_ACCOUNT_ID),
        baseUrl: config.baseUrl,
        apiKeySet: !!activeKey,
        apiKeyMasked: redactKey(activeKey),
        apiKeySource: localKey ? "local_config" : (envKey ? "env" : "none"),
      },
      drafts,
    };
  }

  async function regenerate(id) {
    const item = drafts.find((d) => d.id === Number(id));
    if (!item) return null;
    const history = threads.get(item.sender.toLowerCase()) || [{ dir: "in", text: item.incoming, at: item.at }];
    const res = await generateReply({ sender: item.sender, text: item.incoming, history, config, fetchImpl, onAccountResolved });
    item.reply = res.reply;
    item.source = res.source;
    item.latencyMs = res.latencyMs || 0;
    item.error = res.error || null;
    if (config.autoCopy && item.reply) {
      const ok = await clipboardFn(item.reply);
      item.copied = !!ok;
      if (ok) lastClipboardText = item.reply;
    }
    return item;
  }

  function createServer() {
    return http.createServer(async (req, res) => {
      const url = new URL(req.url, "http://127.0.0.1");
      const json = (code, obj) => {
        res.writeHead(code, { "Content-Type": "application/json; charset=utf-8" });
        res.end(JSON.stringify(obj));
      };
      const readBody = () => new Promise((resolve) => {
        let b = "";
        let done = false;
        const finish = (v) => { if (!done) { done = true; resolve(v); } };
        req.on("data", (c) => {
          b += c;
          if (b.length > 65536) { req.destroy(); finish({}); }
        });
        req.on("error", () => finish({}));
        req.on("end", () => { try { finish(JSON.parse(b || "{}")); } catch { finish({}); } });
      });

      if (req.method === "GET" && url.pathname === "/api/state") {
        return json(200, getState());
      }
      if (req.method === "POST" && url.pathname === "/api/config") {
        const body = await readBody();
        if (typeof body.location === "string") config.location = body.location.trim();
        if (typeof body.persona === "string") config.persona = body.persona.trim();
        if (typeof body.autoCopy === "boolean") config.autoCopy = body.autoCopy;
        if (typeof body.preset === "string" && MODEL_PRESETS[body.preset]) {
          config.preset = body.preset;
          config.provider = MODEL_PRESETS[body.preset].provider;
          config.model = MODEL_PRESETS[body.preset].model;
        }
        if (typeof body.provider === "string" && (body.provider === "cloudflare" || body.provider === "deepseek")) {
          config.provider = body.provider;
        }
        if (typeof body.model === "string" && body.model.trim()) config.model = body.model.trim();
        if (typeof body.cfAccountId === "string") config.cfAccountId = body.cfAccountId.trim();
        if (typeof body.baseUrl === "string" && /^https:\/\/|^http:\/\/(127\.0\.0\.1|localhost)(:\d+)?\b/i.test(body.baseUrl.trim())) {
          config.baseUrl = body.baseUrl.trim();
        }
        if (typeof body.apiKey === "string") {
          config.apiKeys = config.apiKeys || { cloudflare: "", deepseek: "" };
          const targetProvider = config.provider || "cloudflare";
          config.apiKeys[targetProvider] = body.apiKey.trim();
        }
        saveLocalConfig(config, configPath);
        return json(200, getState());
      }
      if (req.method === "POST" && url.pathname === "/api/copy") {
        const body = await readBody();
        const text = typeof body.text === "string" ? body.text : "";
        if (!text) return json(400, { error: "empty text" });
        const ok = await clipboardFn(text);
        if (ok) lastClipboardText = text;
        if (body.id) {
          const item = drafts.find((d) => d.id === Number(body.id));
          if (item) item.copied = !!ok;
        }
        return json(200, { ok, text });
      }
      if (req.method === "POST" && url.pathname === "/api/regenerate") {
        const body = await readBody();
        const item = await regenerate(body.id);
        if (!item) return json(404, { error: "draft not found" });
        return json(200, { item });
      }
      if (req.method === "POST" && url.pathname === "/api/test-whisper") {
        const body = await readBody();
        const sender = (body.sender || "Shadow Dru").trim();
        const text = (body.text || "lol sure where are you at?").trim();
        const item = await handleIncoming(sender, text);
        return json(200, { item, state: getState() });
      }
      if (req.method === "GET" && url.pathname === "/") {
        res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
        return res.end(HTML_UI);
      }
      res.writeHead(404);
      res.end("Not found");
    });
  }

  return { startWatching, stopWatching, pollLog, processLine, handleIncoming, regenerate, getState, createServer };
}

const HTML_UI = `<!doctype html><html><head><meta charset="utf-8"><title>BegBuddy Copilot</title>
<style>
  body{margin:0;background:#111216;color:#e6e6eb;font:13px/1.4 -apple-system,Segoe UI,sans-serif;padding:10px}
  .bar{display:flex;gap:6px;align-items:center;margin-bottom:8px;flex-wrap:wrap}
  .pill{padding:3px 8px;border-radius:12px;font-size:11px;font-weight:600;background:#1d2420;color:#7fe07f}
  .pill.wait{background:#2d2414;color:#ffd100}
  input{background:#1a1b22;color:#fff;border:1px solid #2e313d;border-radius:4px;padding:4px 7px;font-size:12px}
  button{background:#1b4d2a;color:#fff;border:1px solid #35a858;border-radius:4px;padding:4px 9px;cursor:pointer;font-weight:600;font-size:12px}
  button.sec{background:#22242e;border-color:#3a3d4d;color:#d0d2dc}
  .card{background:#181a22;border:1px solid #2a2d3a;border-radius:6px;padding:8px;margin-bottom:8px}
  .who{color:#5cc8ff;font-weight:700}.inc{color:#b0b3c0;margin:3px 0}.rep{color:#7fe07f;font-size:14px;font-weight:600;margin:4px 0}
  .err{color:#ff8080;font-size:11px}
</style></head><body>
<div class="bar"><b>BegBuddy Copilot</b> <span id="st" class="pill wait">Loading...</span>
<button class="sec" onclick="testW()">Test Whisper</button></div>
<div class="bar">
  <select id="preset" onchange="save()" style="flex:1;background:#1a1b22;color:#fff;border:1px solid #2e313d;border-radius:4px;padding:4px 6px;font-size:12px">
    <option value="cf-llama-fast">Cloudflare: Llama 3.1 8B Fast (~5,900 free/day)</option>
    <option value="cf-gemma4">Cloudflare: Gemma 4 26B (~4,000 free/day)</option>
    <option value="cf-granite-micro">Cloudflare: Granite 4 Micro (~17,700 free/day)</option>
    <option value="deepseek">DeepSeek Chat</option>
  </select>
</div>
<div class="bar">
  <input id="loc" style="flex:1" placeholder="My location (e.g. Stormwind AH steps)">
  <input id="key" type="password" style="width:150px" placeholder="Cloudflare / DeepSeek token">
  <button onclick="save()">Save</button>
</div>
<div class="bar">
  <textarea id="persona" rows="2" style="width:100%;background:#1a1b22;color:#e6e6eb;border:1px solid #2e313d;border-radius:4px;padding:4px 7px;font:11.5px/1.35 -apple-system,Segoe UI,sans-serif;resize:vertical" placeholder="AI reply prompt / persona guidance..."></textarea>
</div>
<div id="list"></div>
<script>
let loaded=false;
let latestDrafts={};
function escHtml(s){return String(s??'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;');}
async function load(){
  const s=await (await fetch('/api/state')).json();
  const st=document.getElementById('st');
  st.textContent=s.status==='watching'?'Watching WoWChatLog.txt':'Type /chatlog in WoW';
  st.className='pill'+(s.status==='watching'?'':' wait');
  if(!loaded){document.getElementById('loc').value=s.config.location||'';document.getElementById('preset').value=s.config.preset||'cf-llama-fast';document.getElementById('persona').value=s.config.persona||'';loaded=true;}
  latestDrafts={};
  for(const d of s.drafts){latestDrafts[d.id]=d.reply;}
  document.getElementById('list').innerHTML=s.drafts.map(d=>\`<div class="card">
    <div class="who">\${escHtml(d.shortName)} <span style="color:#888;font-weight:400">(\${escHtml(d.source)}\${d.copied?' · COPIED':''})</span></div>
    <div class="inc">"\${escHtml(d.incoming)}"</div>
    <div class="rep">\${escHtml(d.reply)}</div>
    \${d.error?\`<div class="err">\${escHtml(d.error)}</div>\`:''}
    <div class="bar" style="margin:6px 0 0"><button onclick="cp(\${Number(d.id)})">Copy (R -> Ctrl+V -> Enter)</button>
    <button class="sec" onclick="regen(\${Number(d.id)})">Retry</button></div></div>\`).join('') || '<div class="inc">Waiting for incoming whispers... (Click AI Copilot in BegBuddy or type /chatlog once in WoW)</div>';
}
async function save(){
  const body={location:document.getElementById('loc').value,preset:document.getElementById('preset').value,persona:document.getElementById('persona').value};
  const k=document.getElementById('key').value.trim(); if(k) body.apiKey=k;
  await fetch('/api/config',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
  document.getElementById('key').value=''; load();
}
async function cp(id){const text=latestDrafts[id]||''; if(!text)return; await fetch('/api/copy',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id,text})});load();}
async function regen(id){await fetch('/api/regenerate',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id})});load();}
async function testW(){await fetch('/api/test-whisper',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({})});load();}
load(); setInterval(load, 1000);
</script></body></html>`;

// CLI entry point
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  const portIdx = args.indexOf("--port");
  const port = portIdx >= 0 ? Number(args[portIdx + 1]) : 4789;
  const logIdx = args.indexOf("--log");
  const customLog = logIdx >= 0 ? args[logIdx + 1] : null;

  const copilot = createCopilot({ customLog });
  copilot.startWatching();
  const server = copilot.createServer();
  server.listen(port, "127.0.0.1", () => {
    const addr = server.address();
    console.log(`BegBuddy Copilot listening on http://127.0.0.1:${addr.port}`);
  });
}
