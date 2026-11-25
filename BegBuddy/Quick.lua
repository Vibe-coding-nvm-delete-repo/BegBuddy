-- BegBuddy / Quick.lua
-- Quick messages: short messages sent with one click, to the chat box's channel when the cursor is in it, else as
-- a whisper to the person open in the detail pane. The list is the player's own (BegDB.quickMessages), kept apart
-- from BegDB.settings so a settings reset and Clear all leave it be.

local _, ns = ...

ns.QUICK_MAX = 24 -- messages the list holds
ns.QUICK_LEN = 255 -- the most a whisper can carry

-- The starting set. A message is { text = "...", hidden = true } once the player hides it.
ns.DEFAULT_QUICK_MESSAGES = {
  "Tysm!",
  "Tysm!!! You're the best!",
  "Yes please!",
  "I'm in front of the AH!",
  "I'm in front of the bank!",
  "I'm rich!!!",
  "Fuck yes tysm!",
  "Thank you so much!",
  "Please!",
  "Where are you?",
  "One moment please!",
  "On my way!",
  "Sorry, I can't right now.",
  "No thanks, I'm good!",
  "What do you need?",
}

local function Trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

local function DefaultList()
  local out = {}
  for i, text in ipairs(ns.DEFAULT_QUICK_MESSAGES) do out[i] = { text = text } end
  return out
end

-- The first run gets the starting set. After that the list is the player's: deleting every message leaves
-- it empty, and a damaged entry is dropped.
function ns.EnsureQuick()
  if type(BegDB.quickMessages) ~= "table" then
    BegDB.quickMessages = DefaultList()
    return
  end
  local q = BegDB.quickMessages
  for i = #q, 1, -1 do
    if type(q[i]) ~= "table" or type(q[i].text) ~= "string" then table.remove(q, i) end
  end
end

-- What the main window shows: every message that is not hidden and has some text. Each row keeps its place
-- in the saved list as `index`.
function ns.QuickShown()
  local out = {}
  for i, m in ipairs(BegDB.quickMessages or {}) do
    if not m.hidden and Trim(m.text) ~= "" then out[#out + 1] = { index = i, text = m.text } end
  end
  return out
end

function ns.AddQuick(text)
  ns.EnsureQuick()
  text = Trim(text):gsub("[\r\n]+", " ")
  if text == "" then return nil, "Type the message first." end
  if #BegDB.quickMessages >= ns.QUICK_MAX then
    return nil, string.format("The list holds %d messages. Delete one first.", ns.QUICK_MAX)
  end
  local m = { text = ns.TrimToBytes(text, ns.QUICK_LEN) }
  BegDB.quickMessages[#BegDB.quickMessages + 1] = m
  return m
end

function ns.RemoveQuick(index)
  local q = BegDB.quickMessages or {}
  if not q[index] then return false end
  table.remove(q, index)
  return true
end

-- Moves a message one place up (-1) or down (1).
function ns.MoveQuick(index, step)
  local q = BegDB.quickMessages or {}
  local to = index + step
  if not (q[index] and q[to]) then return false end
  q[index], q[to] = q[to], q[index]
  return true
end

function ns.ResetQuick() BegDB.quickMessages = DefaultList() end

----------------------------------------------------------------------
-- Where a quick message goes: the chat box when the cursor is in it, else the person open
----------------------------------------------------------------------

-- The chat edit box the cursor is in, or nil when the chat box is closed. Classic keeps it behind
-- ChatEdit_GetActiveWindow; 12.0 moved that under ChatFrameUtil. Clicking a button does not close it.
local function ActiveChatBox()
  local get = _G.ChatEdit_GetActiveWindow
  if type(get) ~= "function" then
    local util = _G.ChatFrameUtil
    get = type(util) == "table" and util.GetActiveWindow or nil
  end
  if type(get) ~= "function" then return nil end
  local ok, eb = pcall(get)
  if ok and type(eb) == "table" and type(eb.GetAttribute) == "function" then return eb end
  return nil
end

-- What the chat box is set to: its kind ("PARTY", "WHISPER", ...) and, for a whisper or a numbered channel,
-- its target. nil when the chat box is closed.
function ns.ChatBoxChannel()
  local eb = ActiveChatBox()
  if not eb then return nil end
  local kind = eb:GetAttribute("chatType")
  if not ns.Readable(kind) or type(kind) ~= "string" or kind == "" then return nil end
  local target
  if kind == "WHISPER" or kind == "BN_WHISPER" then
    target = eb:GetAttribute("tellTarget")
  elseif kind == "CHANNEL" then
    target = eb:GetAttribute("channelTarget")
  end
  -- A /reply target taken from a hidden whisper (WoW: Forever) cannot be trimmed or looked up: treat it as unset.
  if not ns.Readable(target) then target = nil end
  return kind, target
end

-- The kinds SendChatMessage takes without a name. A whisper has its own path (through the contact) and a
-- Battle.net whisper needs the friend's id.
local CHANNEL_KINDS = {
  SAY = true, YELL = true, PARTY = true, RAID = true, RAID_WARNING = true, GUILD = true, OFFICER = true,
  INSTANCE_CHAT = true, BATTLEGROUND = true, EMOTE = true, CHANNEL = true,
}

local function InCombat() return ns.inCombat or (InCombatLockdown and InCombatLockdown()) end

local function SendToBNetFriend(target, text)
  local id = type(target) == "string" and type(BNet_GetBNetIDAccount) == "function" and BNet_GetBNetIDAccount(target)
  if id and type(BNSendWhisper) == "function" then
    BNSendWhisper(id, text)
    return true
  end
  ns.Print("That Battle.net friend was not found. Whisper them by character name instead.")
  return false
end

-- Sends `text` to a channel the chat box is set to, the way Enter would. Not a whisper: those go through
-- SendReply so the wait between sends and the thread on the card are kept.
local function SendToChannel(kind, target, text)
  if InCombat() then
    ns.Print("Not during combat.")
    return false
  end
  if ns.ChatLocked() then
    ns.Print(ns.CHAT_LOCKED_TEXT)
    return false
  end
  if kind == "BN_WHISPER" then return SendToBNetFriend(target, text) end
  if not CHANNEL_KINDS[kind] then
    ns.Print(string.format("The chat box is set to %s, which a quick message cannot use.", tostring(kind)))
    return false
  end
  if kind == "CHANNEL" and not tonumber(target) then
    ns.Print("The chat box is set to a channel that is not open.")
    return false
  end
  local send = _G.SendChatMessage
  if type(send) ~= "function" and C_ChatInfo then send = C_ChatInfo.SendChatMessage end
  if type(send) ~= "function" then
    ns.Print("This client has no chat send call. Run /beg probe.")
    return false
  end
  local ok, err
  if kind == "CHANNEL" then ok, err = pcall(send, text, kind, nil, tonumber(target)) else ok, err = pcall(send, text, kind) end
  if not ok then
    ns.Print("The game refused the message: " .. tostring(err))
    return false
  end
  return true
end

-- Sends `text` where the player's cursor is: to the chat box's channel when the cursor is in it (Party, Say,
-- Guild, a whisper to someone, ...), else as a whisper to the person open in the detail pane. With neither,
-- nothing is sent. It goes out like a reply you typed: Pause does not stop it, combat and the wait between
-- whispers do. {name} and {level} are the person it goes to, or the person open for a channel.
function ns.SendQuick(text)
  local c = ns.activeContact
  if not (c and BegDB.contacts[c.key]) then c = nil end
  local kind, target = ns.ChatBoxChannel()
  if kind == "WHISPER" then
    if type(target) ~= "string" or Trim(target) == "" then kind = nil end
  end
  if not kind and not c then
    ns.Print("Open someone first, or put your cursor in the chat box, then click a quick message.")
    return false
  end
  local who = c
  if kind == "WHISPER" then who = ns.FindContact(target) or { name = ns.ShortName(target) or target, full = target } end
  local out = ns.TrimToBytes(ns.RenderTemplate(who, tostring(text or "")), ns.QUICK_LEN)
  if Trim(out) == "" then return false end
  if kind == "WHISPER" then return ns.SendReply(who, out) end
  if kind then return SendToChannel(kind, target, out) end
  return ns.SendReply(c, out)
end
