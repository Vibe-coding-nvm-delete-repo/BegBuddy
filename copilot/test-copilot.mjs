// BegBuddy Copilot — Comprehensive $0 unit & integration tests
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { parseChatLogLine, shortName, sanitizeWhisperReply } from "./parser.mjs";
import { detectIntent, generateReply } from "./llm.mjs";
import { createCopilot, redactKey } from "./copilot.mjs";

let passed = 0;
async function test(name, fn) {
  await fn();
  console.log("  PASS", name);
  passed++;
}

// 1. Parser tests
await test("parses bracketed WoW Forever space-name incoming whisper", () => {
  const r = parseChatLogLine("11/25 05:27:10.123  [Shadow Dru] whispers: haha sure where are you?");
  assert.deepEqual(r, { dir: "in", sender: "Shadow Dru", text: "haha sure where are you?" });
});

await test("parses year+tz timestamp and realm suffix", () => {
  const r = parseChatLogLine("11/25/2026 05:27:10.123-5  [Alice-Dreamscythe] whispers: come to AH");
  assert.deepEqual(r, { dir: "in", sender: "Alice-Dreamscythe", text: "come to AH" });
  assert.equal(shortName(r.sender), "Alice");
});

await test("parses unbracketed incoming and outgoing whispers", () => {
  const r1 = parseChatLogLine("11/25 05:27:10.123  Egg Sucka whispers: inv me");
  assert.deepEqual(r1, { dir: "in", sender: "Egg Sucka", text: "inv me" });
  const r2 = parseChatLogLine("11/25 05:27:05.000  To [Shadow Dru]: Hi Shadow Dru! need 2s");
  assert.deepEqual(r2, { dir: "out", sender: "Shadow Dru", text: "Hi Shadow Dru! need 2s" });
  const r3 = parseChatLogLine("11/25 05:27:05.000  To Bob: hello there");
  assert.deepEqual(r3, { dir: "out", sender: "Bob", text: "hello there" });
});

await test("ignores non-whisper chat lines (Trade, Say, Guild, System)", () => {
  assert.equal(parseChatLogLine("11/25 05:27:10.123  [2. Trade - City] [Bob]: WTS Linen Bag"), null);
  assert.equal(parseChatLogLine("11/25 05:27:10.123  Bob says: hello"), null);
  assert.equal(parseChatLogLine("11/25 05:27:10.123  [Guild] [Bob]: gz!"), null);
  assert.equal(parseChatLogLine("11/25 05:27:10.123  You receive loot: [Linen Cloth]."), null);
});

await test("parses unbracketed Unicode names cleanly", () => {
  const r1 = parseChatLogLine("11/25 05:27:10.123  Café whispers: sure come ah");
  assert.deepEqual(r1, { dir: "in", sender: "Café", text: "sure come ah" });
  const r2 = parseChatLogLine("11/25 05:27:05.000  To Søren: hey there");
  assert.deepEqual(r2, { dir: "out", sender: "Søren", text: "hey there" });
});

await test("sanitizes LLM reply (single line, no quotes, strips /w <sender>, UTF-8 & surrogate-safe)", () => {
  assert.equal(sanitizeWhisperReply('  "/w Bob tysm!!\nsee u at AH"  ', 240, "Bob"), "tysm!! see u at AH");
  assert.equal(sanitizeWhisperReply('/w Shadow Dru tysm! im at SW AH', 240, "Shadow Dru"), "tysm! im at SW AH");
  assert.equal(sanitizeWhisperReply('/r tysm!!', 240, "Shadow Dru"), "tysm!!");
  assert.equal(sanitizeWhisperReply('"tysm!! im right by AH"'), "tysm!! im right by AH");
  const emojis = "😀".repeat(80);
  const trimmed = sanitizeWhisperReply(emojis, 20);
  assert.ok(Buffer.byteLength(trimmed, "utf8") <= 20);
  assert.equal(trimmed, "😀".repeat(5));
});

// 2. LLM client & fallback tests
await test("DeepSeek 200 OK returns sanitized reply with multi-turn context", async () => {
  let capturedBody = null;
  const mockFetch = async (_url, opts) => {
    capturedBody = JSON.parse(opts.body);
    return {
      ok: true,
      status: 200,
      json: async () => ({ choices: [{ message: { content: '"tysm!! im right outside stormwind AH"' } }] }),
    };
  };
  const res = await generateReply({
    sender: "Shadow Dru",
    text: "sure where r u",
    history: [
      { dir: "out", text: "hey Shadow Dru! new to wow" },
      { dir: "in", text: "sure where r u" },
    ],
    config: { apiKey: "sk-test-123456", location: "Stormwind AH" },
    fetchImpl: mockFetch,
  });
  assert.equal(res.reply, "tysm!! im right outside stormwind AH");
  assert.equal(res.source, "deepseek-chat");
  assert.equal(res.error, null);
  assert.equal(res.skip, false);
  assert.equal(capturedBody.messages.length, 3); // system + out + in
});

await test("DeepSeek 401 falls back cleanly with actionable error message", async () => {
  const mockFetch = async () => ({
    ok: false,
    status: 401,
    json: async () => ({ error: { message: "Authentication Fails" } }),
  });
  const res = await generateReply({
    sender: "Shadow Dru",
    text: "where are you?",
    history: [{ dir: "in", text: "where are you?" }],
    config: { apiKey: "sk-bad", location: "Stormwind AH steps" },
    fetchImpl: mockFetch,
  });
  assert.equal(res.source, "fallback");
  assert.match(res.reply, /Stormwind AH steps/);
  assert.match(res.error, /401/);
});

await test("Hostile/decline whisper is flagged skip=true", () => {
  assert.equal(detectIntent("no get a job"), "decline");
  assert.equal(detectIntent("sorry no im broke"), "decline");
  assert.equal(detectIntent("where are you at?"), "location");
});

// 3. End-to-end file tailing, clipboard & HTTP API test
await test("File tailing + auto-copy + HTTP API work end-to-end", async () => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "begbuddy-copilot-"));
  const logFile = path.join(tmpDir, "WoWChatLog.txt");
  const cfgFile = path.join(tmpDir, "config.local.json");
  // Seed old line before attaching (must be ignored by EOF tailing)
  fs.writeFileSync(logFile, "11/25 04:00:00.000  [OldGuy] whispers: old message\n", "utf8");

  const copied = [];
  const mockFetch = async () => ({
    ok: true,
    status: 200,
    json: async () => ({ choices: [{ message: { content: "tysm! im at stormwind AH steps, can i inv?" } }] }),
  });

  const copilot = createCopilot({
    configPath: cfgFile,
    customLog: logFile,
    fetchImpl: mockFetch,
    clipboardFn: async (t) => { copied.push(t); return true; },
  });

  // First poll attaches at EOF
  await copilot.pollLog();
  assert.equal(copilot.getState().status, "watching");
  assert.equal(copilot.getState().drafts.length, 0);

  // Append outgoing + incoming whisper
  fs.appendFileSync(logFile,
    "11/25 05:27:05.000  To [Shadow Dru]: hey Shadow Dru! new to wow\n" +
    "11/25 05:27:10.000  [Shadow Dru] whispers: sure where are you?\n", "utf8");
  await copilot.pollLog();

  const st1 = copilot.getState();
  assert.equal(st1.drafts.length, 1);
  assert.equal(st1.drafts[0].sender, "Shadow Dru");
  assert.equal(st1.drafts[0].copied, true);
  assert.equal(copied.length, 1);

  // Append decline -> must NOT overwrite clipboard
  fs.appendFileSync(logFile, "11/25 05:27:20.000  [Grumpy] whispers: no get a job\n", "utf8");
  await copilot.pollLog();
  assert.equal(copilot.getState().drafts.length, 2);
  assert.equal(copilot.getState().drafts[0].skip, true);
  assert.equal(copied.length, 1); // unchanged!

  // HTTP API check
  const server = copilot.createServer();
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  const { port } = server.address();
  const base = `http://127.0.0.1:${port}`;
  try {
    const cfgRes = await (await fetch(`${base}/api/config`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ location: "Ironforge Bank", apiKey: "sk-secret-9999" }),
    })).json();
    assert.equal(cfgRes.config.location, "Ironforge Bank");
    assert.equal(cfgRes.config.apiKeyMasked, "****9999");
    assert.ok(!JSON.stringify(cfgRes).includes("sk-secret-9999")); // never leaks full key!

    const testRes = await (await fetch(`${base}/api/test-whisper`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ sender: "TestPal", text: "inv me" }),
    })).json();
    assert.equal(testRes.item.sender, "TestPal");

    const html = await (await fetch(`${base}/`)).text();
    assert.match(html, /BegBuddy Copilot/);
  } finally {
    server.close();
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
});

assert.equal(redactKey("sk-1234567890abcd"), "****abcd");
console.log(`All ${passed} copilot tests passed.`);
