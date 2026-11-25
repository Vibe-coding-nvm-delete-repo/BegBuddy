// BegBuddy Copilot — DeepSeek (OpenAI-compatible) reply generator + instant intent fallback

import { sanitizeWhisperReply, shortName } from "./parser.mjs";

const DECLINE_RE = /\b(no\b|nope|nah|fuck|fck|stfu|scam|beggar|get a job|grind|earn it|blocked|ignored|reported|broke|poor myself|cant|can't|sorry no)\b/i;
const WHERE_RE   = /\b(where|location|wher|u at|you at|meet|come to|at ah|at bank|stormwind|ironforge|orgrimmar|sw|if|org)\b/i;
const INVITE_RE  = /\b(inv|invite|party|group)\b/i;
const AMOUNT_RE  = /\b(how much|how many|what do u need|what u need|need\?|silver|gold|bags?|wand)\b/i;
const TRADE_RE   = /\b(trade|here|omw|on my way|coming|mail|sent|mailed)\b/i;

export function detectIntent(text) {
  const t = String(text || "");
  if (DECLINE_RE.test(t)) return "decline";
  if (INVITE_RE.test(t)) return "invite";
  if (WHERE_RE.test(t)) return "location";
  if (TRADE_RE.test(t)) return "trade";
  if (AMOUNT_RE.test(t)) return "amount";
  return "general";
}

export function fallbackReply(sender, text, config) {
  const loc = (config.location || "right outside the Stormwind AH steps").trim();
  const intent = detectIntent(text);
  if (intent === "decline") {
    return { reply: "all good no worries, gl out there!", intent, skip: true, source: "fallback" };
  }
  if (intent === "invite") {
    return { reply: `tysm!! inv sent, im ${loc}`, intent, skip: false, source: "fallback" };
  }
  if (intent === "location") {
    return { reply: `tysm! im ${loc}, can i inv u so u can see me?`, intent, skip: false, source: "fallback" };
  }
  if (intent === "trade") {
    return { reply: "tysm!! youre literally the best, appreciate it so much!", intent, skip: false, source: "fallback" };
  }
  if (intent === "amount") {
    return { reply: "honestly even a couple silver or a spare bag helps a ton, tysm!", intent, skip: false, source: "fallback" };
  }
  return { reply: `haha tysm ${shortName(sender)}! im ${loc} if u have a sec`, intent, skip: false, source: "fallback" };
}

export function buildMessages(sender, history, config) {
  const loc = (config.location || "right outside the Stormwind AH steps").trim();
  const persona = (config.persona || "Friendly brand-new WoW Classic player trying to get their first bags and wand. Casual lowercase gamer style (like 'tysm', 'im', 'u', 'haha'). Warm, appreciative, never pushy.").trim();

  const system = [
    "You are drafting a single WoW in-game whisper reply for a human player to copy-paste.",
    `Persona: ${persona}`,
    `Current character location: ${loc}.`,
    "Strict rules:",
    "- Output ONLY the exact whisper text to send. No quotes, no explanations, no prefixes.",
    "- Keep it 1 short sentence (6 to 22 words, strictly under 200 characters).",
    "- Sound 100% like a real casual WoW player, never robotic or formal, never say you are an AI.",
    "- If they ask where you are, give your exact current location and offer a party invite.",
    "- If they say no / hostile / broke, reply politely in 3-5 words like 'all good gl out there!'.",
    "- If they already sent gold/mail or traded, thank them warmly.",
  ].join("\n");

  const msgs = [{ role: "system", content: system }];
  const recent = (history || []).slice(-10);
  for (const h of recent) {
    msgs.push({
      role: h.dir === "out" ? "assistant" : "user",
      content: h.dir === "out" ? h.text : `${shortName(sender)} whispers: ${h.text}`,
    });
  }
  return msgs;
}

export async function generateReply({ sender, text, history, config, fetchImpl = fetch }) {
  const intent = detectIntent(text);
  const apiKey = (config.apiKey || process.env.DEEPSEEK_API_KEY || "").trim();
  if (!apiKey) {
    const fb = fallbackReply(sender, text, config);
    return { ...fb, error: "No DeepSeek API key set — using smart fallback." };
  }

  const baseUrl = (config.baseUrl || "https://api.deepseek.com").replace(/\/+$/, "");
  const model = config.model || "deepseek-chat";
  const messages = buildMessages(sender, history, config);
  const t0 = Date.now();

  try {
    const res = await fetchImpl(`${baseUrl}/chat/completions`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model,
        temperature: 0.75,
        max_tokens: 70,
        messages,
      }),
    });

    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      const msg = data?.error?.message || `HTTP ${res.status}`;
      const fb = fallbackReply(sender, text, config);
      return { ...fb, latencyMs: Date.now() - t0, error: `DeepSeek error (${res.status}): ${msg}` };
    }

    const raw = data?.choices?.[0]?.message?.content || "";
    const reply = sanitizeWhisperReply(raw, 240, sender);
    if (!reply) {
      const fb = fallbackReply(sender, text, config);
      return { ...fb, latencyMs: Date.now() - t0, error: "DeepSeek returned empty text — using fallback." };
    }

    return {
      reply,
      intent,
      skip: intent === "decline",
      source: model,
      latencyMs: Date.now() - t0,
      error: null,
    };
  } catch (err) {
    const fb = fallbackReply(sender, text, config);
    return { ...fb, latencyMs: Date.now() - t0, error: `Network error: ${err.message}` };
  }
}
