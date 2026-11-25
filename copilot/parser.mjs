// BegBuddy Copilot — WoWChatLog.txt parser & whisper sanitizer
// Supports WoW Classic Era, Hardcore, and WoW Forever (including spaces in character names).

// Matches timestamps like:
//   "11/25 05:27:10.123  "
//   "11/25/2026 05:27:10.123-5  "
const TS_PREFIX = /^\s*\d{1,2}\/\d{1,2}(?:\/\d{2,4})?\s+\d{1,2}:\d{2}:\d{2}(?:\.\d+)?(?:[+-]\d+)?\s+/;

// Incoming whisper: "[Shadow Dru] whispers: msg" or "Shadow Dru whispers: msg" (Unicode-safe)
const IN_BRACKET  = /^\[([^\]]+)\]\s+whispers:\s*(.+)$/;
const IN_PLAIN    = /^(\p{L}[\p{L}\p{N} '\-]{1,40}?)\s+whispers:\s*(.+)$/u;

// Outgoing whisper: "To [Shadow Dru]: msg" or "To Shadow Dru: msg" (Unicode-safe)
const OUT_BRACKET = /^To\s+\[([^\]]+)\]:\s*(.+)$/;
const OUT_PLAIN   = /^To\s+(\p{L}[\p{L}\p{N} '\-]{1,40}?):\s*(.+)$/u;

/**
 * Parses a single line from WoWChatLog.txt.
 * Returns { dir: "in"|"out", sender: string, text: string } or null if not a whisper.
 */
export function parseChatLogLine(rawLine) {
  if (typeof rawLine !== "string" || !rawLine.trim()) return null;
  const line = rawLine.replace(/[\r\n]+/g, "").replace(TS_PREFIX, "");
  if (!line) return null;

  let m = line.match(IN_BRACKET) || line.match(IN_PLAIN);
  if (m) {
    const sender = m[1].trim();
    const text = m[2].trim();
    if (!sender || !text) return null;
    return { dir: "in", sender, text };
  }

  m = line.match(OUT_BRACKET) || line.match(OUT_PLAIN);
  if (m) {
    const sender = m[1].trim();
    const text = m[2].trim();
    if (!sender || !text) return null;
    return { dir: "out", sender, text };
  }

  return null;
}

/**
 * Strips realm suffix ("Alice-Dreamscythe" -> "Alice") while preserving WoW Forever spaces.
 */
export function shortName(sender) {
  if (typeof sender !== "string") return "";
  return sender.replace(/-.+$/, "").trim();
}

function escapeRegex(s) {
  return String(s).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/**
 * Sanitizes an LLM reply so it is always a valid single-line WoW whisper <= maxBytes UTF-8 bytes.
 * Strips accidental "/r " or "/w <sender> " prefixes (preserving WoW Forever space names)
 * and trims on whole Unicode code points so surrogate pairs are never split.
 */
export function sanitizeWhisperReply(raw, maxBytes = 240, sender = "") {
  let s = String(raw || "")
    .replace(/[\r\n]+/g, " ")
    .replace(/\s{2,}/g, " ")
    .trim();

  // Strip surrounding quotation marks if the model wrapped the reply
  if ((s.startsWith('"') && s.endsWith('"')) || (s.startsWith("'") && s.endsWith("'"))) {
    s = s.slice(1, -1).trim();
  }

  // Strip accidental "/r " or "/w <sender> " / "/whisper <name> " prefix
  if (/^\/r\s+/i.test(s)) {
    s = s.replace(/^\/r\s+/i, "").trim();
  } else if (/^\/(?:w|whisper)\s+/i.test(s)) {
    s = s.replace(/^\/(?:w|whisper)\s+/i, "").trim();
    const candidates = [sender, shortName(sender)].filter(Boolean);
    let stripped = false;
    for (const c of candidates) {
      const re = new RegExp(`^\\[?${escapeRegex(c)}\\]?\\s+`, "i");
      if (re.test(s)) { s = s.replace(re, "").trim(); stripped = true; break; }
    }
    if (!stripped) {
      s = s.replace(/^\[[^\]]+\]\s+|^\S+\s+/, "").trim();
    }
  }

  // Trim safely to maxBytes UTF-8 bytes on whole Unicode code points
  if (Buffer.byteLength(s, "utf8") <= maxBytes) return s;
  const chars = Array.from(s);
  while (chars.length > 0 && Buffer.byteLength(chars.join(""), "utf8") > maxBytes) {
    chars.pop();
  }
  return chars.join("").trim();
}
