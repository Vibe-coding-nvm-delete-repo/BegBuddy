-- BegBuddy / Comms.lua
-- Template rendering, the assisted-send path, reply capture, conversation log.

local ADDON, ns = ...

ns.pending       = nil   -- { key, text, at } while a pre-filled whisper is waiting
ns.activeContact = nil   -- contact currently open in the detail pane
ns.lastSendAt    = nil
ns.warnCount     = 0
ns.firstWarnAt   = nil

----------------------------------------------------------------------
-- Template
----------------------------------------------------------------------

-- Deliberately not string.format: the template is user-authored text and a
-- stray "%" would throw or mangle the output.
function ns.RenderTemplate(contact, template)
  local t = template or (BegDB.settings.template or "")
  if not contact then return t end
  local name  = tostring(contact.name or "?")
  local level = contact.level and tostring(contact.level) or ""
  local safeName  = name:gsub("%%", "%%%%")
  local safeLevel = level:gsub("%%", "%%%%")
  local out = t:gsub("{name}", safeName)
  out = out:gsub("{level}", safeLevel)
  -- A whisper is one line. A line break would cut the message in the chat box.
  out = out:gsub("%s*[\r\n]+%s*", " ")
  return out
end

----------------------------------------------------------------------
-- Assisted send: we pre-fill, the player presses Enter
----------------------------------------------------------------------

-- The chat frame API moved in 12.0, so try each known door in turn and fail
-- loudly rather than silently doing nothing.
function ns.OpenChatWith(text)
  if type(ChatFrame_OpenChat) == "function" then
    local ok = pcall(ChatFrame_OpenChat, text)
    if ok then return true end
  end
  local util = _G.ChatFrameUtil
  if type(util) == "table" and type(util.OpenChat) == "function" then
    local ok = pcall(util.OpenChat, text)
    if ok then return true end
  end
  local eb = type(ChatFrame1) == "table" and ChatFrame1.editBox
  if eb and type(ChatEdit_ActivateChat) == "function" then
    local ok = pcall(function()
      ChatEdit_ActivateChat(eb)
      eb:SetText(text)
    end)
    if ok then return true end
  end
  return false
end

-- Global on Classic; newer clients moved it under C_ChatInfo.
local function SendWhisper(text, target)
  if ns.ChatLocked() then
    ns.Print(ns.CHAT_LOCKED_TEXT)
    return false
  end
  local send = _G.SendChatMessage
  if type(send) ~= "function" and C_ChatInfo then send = C_ChatInfo.SendChatMessage end
  if type(send) ~= "function" then
    ns.Print("This client has no whisper send call. Run /beg probe.")
    return false
  end
  local ok, err = pcall(send, text, "WHISPER", nil, target)
  if not ok then
    ns.Print("The game refused the whisper: " .. tostring(err))
    return false
  end
  return true
end

function ns.AssistedSend(contact)
  if not contact then return false end
  if BegDB.paused then
    ns.Print("Sending is paused. /beg resume")
    return false
  end
  if ns.inCombat or (InCombatLockdown and InCombatLockdown()) then
    ns.Print("Not during combat.")
    return false
  end
  -- While chat is locked the game hides the confirm, the reply and the offline notice, so an opener could
  -- neither be recorded nor told apart from a failed one.
  if ns.ChatLocked() then
    ns.Print(ns.CHAT_LOCKED_TEXT)
    return false
  end

  local allowed, why = ns.CanWhisper(contact)
  if not allowed then
    ns.Print(why or "Not allowed.")
    return false
  end

  local text = ns.RenderTemplate(contact, ns.TemplateText())
  if text == "" then
    ns.Print("The active template is empty. Write something in Settings > Message.")
    return false
  end
  if #text > 255 then
    ns.Print(string.format("Template is %d characters. The client truncates at 255.", #text))
  end

  local target  = contact.full or contact.name
  local payload = "/w " .. target .. " " .. text

  if not ns.OpenChatWith(payload) then
    ns.Print("This client would not open the chat box, so here is the text to copy instead.")
    if ns.UI and ns.UI.ShowCopy then ns.UI.ShowCopy(payload) end
    return false
  end

  ns.lastLoadedKey = contact.key
  ns.lastLoadedAt  = GetTime()
  ns.lastSendKey   = contact.key

  -- Nothing is recorded yet. It only becomes a 'contacted' card when the
  -- CHAT_MSG_WHISPER_INFORM event confirms you actually pressed Enter.
  ns.pending = { key = contact.key, text = text, at = GetTime() }
  return true
end

-- The checks before any opener goes out. Prints why and returns true when it is blocked.
local function SendBlocked(contact, skipGap)
  if BegDB.paused then
    ns.Print("Sending is paused. /beg resume")
    return true
  end
  if ns.inCombat or (InCombatLockdown and InCombatLockdown()) then
    ns.Print("Not during combat.")
    return true
  end
  if ns.ChatLocked() then
    ns.Print(ns.CHAT_LOCKED_TEXT)
    return true
  end

  local allowed, why = ns.CanWhisper(contact)
  if not allowed then
    ns.Print(why or "Not allowed.")
    return true
  end

  local now = GetTime()
  local gap = tonumber(BegDB.settings.replyGap) or 2
  if not skipGap and ns.lastSendAt and (now - ns.lastSendAt) < gap then
    ns.Print(string.format("Hold on, %.1fs before the next send.", gap - (now - ns.lastSendAt)))
    return true
  end
  return false
end

-- One click, one whisper: the same checks as loading it into chat, but the
-- click itself sends it. Still one human click per person, never a loop.
-- It is only recorded as contacted when the client confirms the send.
function ns.QuickSend(contact, skipGap)
  if not contact or SendBlocked(contact, skipGap) then return false end
  local now = GetTime()

  local text = ns.RenderTemplate(contact, ns.TemplateText())
  if text == "" then
    ns.Print("The active template is empty. Write something in Settings > Message.")
    return false
  end
  -- The server cuts at 255 bytes anyway; cutting here keeps whole characters.
  text = ns.TrimToBytes(text, 255)

  ns.lastLoadedKey = contact.key
  ns.lastLoadedAt  = now
  ns.lastSendKey   = contact.key
  ns.pending = { key = contact.key, text = text, at = now }
  if not SendWhisper(text, contact.full or contact.name) then
    ns.pending = nil
    return false
  end
  ns.lastSendAt = now
  ns.sentAt = ns.sentAt or {}
  ns.sentAt[contact.key] = now
  if ns.sentHeld then ns.sentHeld[contact.key] = nil end
  -- Nothing else redraws when the unconfirmed-send hold ends, which would leave Auto greyed.
  if C_Timer and C_Timer.After then
    C_Timer.After(60.5, function() if ns.RefreshUI then ns.RefreshUI() end end)
  end
  return true
end

-- The next person the Auto button would whisper: top of Queued, in the order
-- the list is sorted on screen, skipping anyone a check found offline.
function ns.NextToSend()
  local list = ns.SortedList(ns.STATUS.QUEUED)
  local n, first = 0, nil
  for _, c in ipairs(list) do
    local offline = ns.CheckState and ns.CheckState(c.key) == "offline"
    if not offline and ns.CanWhisper(c) then
      n = n + 1
      first = first or c
    end
  end
  return first, n
end

-- Auto: every click whispers the next person, one click one whisper. The Send gap applies the same as for
-- the whisper buttons (an offline answer clears it, so a name that is not playing costs no wait), and
-- CanWhisper (sentAt) blocks a double-send per person.
function ns.SendNext()
  -- At a mailbox the same button mails the next name instead.
  if ns.MailMode and ns.MailMode() then return ns.MailNext() end
  ns.autoWaitUntil = nil
  -- The game confirms a send (or reports the person offline) within a moment, and only one
  -- send can be tracked at a time. A click before that answer would overwrite it and lose the
  -- offline check and the template stats, so it is ignored; a lost answer times out after 1.5s.
  local pend = ns.pending
  if pend and pend.at and (GetTime() - pend.at) < 1.5 then return false end
  local c, n = ns.NextToSend()
  if not c then
    ns.Print("Nobody left to whisper in Queued. Scan for more.")
    return false
  end
  if ns.QuickSend(c) then
    -- "Sent" is only said once the game confirms it (OnWhisperOut): an ignored or restricted whisper never leaves.
    if ns.pending and ns.pending.key == c.key then ns.pending.auto = true end
    ns.Print(string.format("Whispering %s...", tostring(c.name)))
    return true
  end
  return false
end

-- What the whisper buttons call: one click sends, or (setting off) loads it
-- into the chat box for you to press Enter.
function ns.WhisperContact(contact)
  if ns.MailMode and ns.MailMode() then return ns.MailContact(contact) end
  if BegDB.settings.oneClickSend then return ns.QuickSend(contact) end
  if ns.AssistedSend(contact) then
    ns.Print("Loaded whisper for " .. tostring(contact.name) .. " - press Enter.")
    return true
  end
  return false
end

function ns.SendReply(contact, text)
  if not contact or type(text) ~= "string" or text == "" then return false end
  -- Deliberately not blocked by Pause: Pause stops the openers (Auto and the
  -- whisper buttons), while a reply is a message you typed to someone talking to you.
  if ns.inCombat or (InCombatLockdown and InCombatLockdown()) then
    ns.Print("Not during combat.")
    return false
  end

  local now = GetTime()
  local gap = tonumber(BegDB.settings.replyGap) or 2
  if ns.lastSendAt and (now - ns.lastSendAt) < gap then
    ns.Print(string.format("Hold on, %.1fs before the next send.", gap - (now - ns.lastSendAt)))
    return false
  end

  if #text > 255 then
    ns.Print("Message is over 255 characters; it will be truncated.")
  end

  if not SendWhisper(text, contact.full or contact.name) then return false end
  ns.lastSendAt  = now
  ns.lastSendKey = contact.key
  return true
end

-- Party invite and friend list, for people worth keeping in touch with.
-- Both are plain client calls; the game prints its own result line
-- ("X is already your friend", "X is already in a group") so no guessing here.
function ns.InviteContact(contact)
  if not contact then return false end
  local target = contact.full or contact.name
  local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or _G.InviteUnit
  if type(invite) ~= "function" then
    ns.Print("This client has no party invite call. Run /beg probe.")
    return false
  end
  invite(target)
  ns.Print("Invited " .. tostring(contact.name) .. " to your group.")
  return true
end

-- One click out of a party or raid, from the window's header or /beg leave.
-- Saves the two clicks and the menu the default unit frame asks for, which is
-- what you want right after a trade or a pity invite.
function ns.LeaveGroup()
  if not (IsInGroup and IsInGroup()) then
    ns.Print("You are not in a group.")
    return false
  end
  local leave = (C_PartyInfo and C_PartyInfo.LeaveParty) or _G.LeaveParty
  if type(leave) ~= "function" then
    ns.Print("This client has no leave party call. Use the party menu, or run /beg probe.")
    return false
  end
  leave()
  ns.Print("Left the group.")
  return true
end

function ns.AddFriendContact(contact)
  if not contact then return false end
  local target = contact.full or contact.name
  local add = (C_FriendList and C_FriendList.AddFriend) or _G.AddFriend
  if type(add) ~= "function" then
    ns.Print("This client has no add friend call. Run /beg probe.")
    return false
  end
  add(target)
  ns.Print("Added " .. tostring(contact.name) .. " to your friends list.")
  return true
end

----------------------------------------------------------------------
-- Incoming / outgoing whispers
----------------------------------------------------------------------

-- Lower-case short name -> GetTime() of the player's own last whisper to someone BegBuddy does not know.
ns.recentOut = {}
local RECENT_OUT = 30 * 60

local function ShortKey(name)
  local short = ns.ShortName(name)
  return short and ns.StrLower(short) or nil
end

-- True for people the player already knows: friends, guild members, the group, and anyone they whispered
-- themselves in the last half hour (a group leader answering a GroupBoard whisper, say). Never begging leads.
-- Each check is a client call that may be missing; a missing one just says no.
local function Asks(fn, arg) return type(fn) == "function" and fn(arg) and true or false end

function ns.IsKnownPlayer(name)
  local short = ShortKey(name)
  if not short then return false end
  local at = ns.recentOut[short]
  if at and (GetTime() - at) < RECENT_OUT then return true end
  local bare = ns.ShortName(name)
  return Asks(C_FriendList and C_FriendList.GetFriendInfo, bare)
    or Asks(C_GuildInfo and C_GuildInfo.MemberExistsByName, bare)
    or Asks(_G.UnitInParty, bare) or Asks(_G.UnitInRaid, bare)
end

function ns.OnWhisperOut(text, target)
  if type(text) ~= "string" or text == "" then return end
  local c = ns.FindContact(target)
  if not c then
    local short = ShortKey(target)
    if short then ns.recentOut[short] = GetTime() end
    return
  end

  -- Only an opener the addon actually loaded counts as a template send.
  -- Replies and hand-typed whispers fire this same event, and counting them
  -- would inflate `sent` and re-stamp which template opened the conversation.
  local wasLoaded = ns.pending and ns.pending.key == c.key
  local fromAuto = wasLoaded and ns.pending.auto

  ns.PushHistory(c, "out", text)
  ns.lastSendAt  = GetTime()
  ns.lastSendKey = c.key
  ns.pending = nil
  if wasLoaded then ns.RecordSent(c) end

  -- An opener (or a first hand-typed whisper to someone queued) counts as an
  -- ask: it bumps attempts and restarts the re-whisper cooldown, and it brings
  -- an archived name back into Contacted. Replied / closed states stay put.
  local st = c.status
  local isAsk = st == ns.STATUS.QUEUED
    or (wasLoaded and (st == ns.STATUS.CONTACTED or st == ns.STATUS.ARCHIVED))
  if isAsk then
    c.attempts = (c.attempts or 0) + 1
    ns.SetStatus(c, ns.STATUS.CONTACTED)
  else
    if ns.RefreshUI then ns.RefreshUI() end
  end
  if fromAuto then
    ns.Print(string.format("Sent to %s. %d left.", tostring(c.name), select(2, ns.NextToSend())))
  end
end

-- A whisper from someone BegBuddy does not know: a new Replied contact, only when the player turned that on.
local function TrackStranger(text, sender)
  if not BegDB.settings.trackUnknownWhispers or ns.IsKnownPlayer(sender) then return end
  local c = ns.EnsureContact(sender)
  if not c then return end
  ns.PushHistory(c, "in", text)
  ns.SetStatus(c, ns.STATUS.REPLIED)
  ns.Print(string.format("Reply from %s (not from a scan, added to Replied).", c.name))
end

function ns.OnWhisperIn(text, sender)
  if type(text) ~= "string" or text == "" then return end
  if type(sender) ~= "string" or sender == "" then return end

  local c = ns.FindContact(sender)
  if not c then return TrackStranger(text, sender) end

  ns.PushHistory(c, "in", text)

  -- Never drag someone out of a closed state you put them in. Archived is not
  -- closed: it is mostly "was offline", and a reply from them must not be
  -- buried in a tab nobody watches.
  local s = c.status
  if s ~= ns.STATUS.BLOCKED and s ~= ns.STATUS.FUNDED
     and s ~= ns.STATUS.DECLINED then
    ns.SetStatus(c, ns.STATUS.REPLIED)
  else
    if ns.RefreshUI then ns.RefreshUI() end
  end

  ns.unread = ns.unread or {}
  if ns.activeContact ~= c then
    ns.unread[c.key] = true
  end
  if ns.UI then ns.UI.OnNewReply(c) end
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("CHAT_MSG_WHISPER")
f:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
f:RegisterEvent("CHAT_MSG_SYSTEM")
f:RegisterEvent("CHAT_MSG_IGNORED")
f:RegisterEvent("CHAT_MSG_RESTRICTED")
f:SetScript("OnEvent", function(_, event, arg1, arg2)
  if not ns.Readable(arg1, arg2) then -- a hidden line or name is skipped, never matched to a contact
    if event == "CHAT_MSG_WHISPER_INFORM" then ns.OnHiddenWhisperOut() end
    return
  end
  if event == "CHAT_MSG_WHISPER" then
    ns.OnWhisperIn(arg1, arg2)
  elseif event == "CHAT_MSG_WHISPER_INFORM" then
    ns.OnWhisperOut(arg1, arg2)
  elseif event == "CHAT_MSG_SYSTEM" then
    ns.OnSystem(arg1)
  elseif event == "CHAT_MSG_IGNORED" then
    ns.OnIgnored(arg2)
  elseif event == "CHAT_MSG_RESTRICTED" then
    ns.OnRestricted()
  end
end)
