-- BegBuddy: the guards that decide whether an opener may go to a contact right now, and what the game's
-- answers to a send (offline, ignored, restricted, a failure line, a hidden confirm) do to the contact.
local _, ns = ...

local function ClosedReason(contact, status)
  -- Archiving someone who answered does not make them a stranger again.
  if status == ns.STATUS.REPLIED or (status == ns.STATUS.ARCHIVED and contact.repliedAt) then
    return "They already replied - use the reply box, not the opener."
  end
  if status == ns.STATUS.DECLINED or status == ns.STATUS.BLOCKED then
    return "That one is closed out."
  end
  if status == ns.STATUS.FUNDED then
    return "They already funded you."
  end
end

-- Double-click guard on the row button.
local function DoubleClickReason(contact)
  if ns.lastLoadedKey == contact.key and ns.lastLoadedAt
     and (GetTime() - ns.lastLoadedAt) < 5 then
    if ns.MailMode and ns.MailMode() then
      return "Just mailed " .. tostring(contact.name) .. "."
    end
    if BegDB.settings.oneClickSend then
      return "Just whispered " .. tostring(contact.name) .. "."
    end
    return "Already loaded for " .. tostring(contact.name) .. " - press Enter, or pick someone else."
  end
end

-- Sent a moment ago but not confirmed yet: the card still says Queued, so
-- without this a fast second click could pick the same person again.
local function UnconfirmedReason(contact, status)
  local sentAt = ns.sentAt and ns.sentAt[contact.key]
  if sentAt and status ~= ns.STATUS.CONTACTED then
    local mins = tonumber(BegDB.settings.rewhisperMinutes) or 30
    -- Still Queued means the game never confirmed the send (throttled or
    -- failed), so only hold them for a minute. Otherwise fast Auto clicks
    -- lock everyone out for the full cooldown and grey the button. A confirm
    -- the game hid (sentHeld) may well have been delivered: full cooldown.
    local held = ns.sentHeld and ns.sentHeld[contact.key]
    local hold = (status == ns.STATUS.QUEUED and not held) and 60 or (mins * 60)
    if (GetTime() - sentAt) < hold then
      return "Already sent to " .. tostring(contact.name) .. " this session."
    end
  end
end

-- Re-asking the same person too soon is the thing that gets reported. Saved on the card, so it still holds
-- after a /reload and for a name archived since it was asked. Requeue is the player's own choice to ask again.
local function TooSoonReason(contact, status)
  if contact.contactedAt and status ~= ns.STATUS.QUEUED then
    local mins = tonumber(BegDB.settings.rewhisperMinutes) or 30
    local elapsed = math.max(0, time() - contact.contactedAt) / 60
    if elapsed < mins then
      return string.format("Already messaged %s %.0f min ago. Wait another %d min.",
        tostring(contact.name), elapsed, math.ceil(mins - elapsed))
    end
  end
end

-- Spacing out outreach per guild prevents two members of the same guild from
-- receiving the same opener back-to-back and calling it out in /g.
local function GuildCooldownReason(contact, status)
  if status ~= ns.STATUS.QUEUED then return nil end
  local guild = contact.guild
  if type(guild) ~= "string" or guild == "" then return nil end
  local mins = tonumber(BegDB.settings and BegDB.settings.guildCooldownMinutes) or 0
  if mins <= 0 then return nil end
  local map = BegDB.guildContactedAt
  if type(map) ~= "table" then return nil end
  local lastAt = map[ns.StrLower(guild)]
  if not lastAt then return nil end
  local elapsed = math.max(0, time() - lastAt) / 60
  if elapsed < mins then
    return string.format("Already messaged <%s> %.0f min ago. Wait another %d min.",
      guild, elapsed, math.ceil(mins - elapsed))
  end
end

-- Record that we just messaged someone in this guild so other guildmates are
-- held for guildCooldownMinutes.
function ns.MarkGuildContacted(contact)
  if not contact or type(contact.guild) ~= "string" or contact.guild == "" then return end
  BegDB.guildContactedAt = type(BegDB.guildContactedAt) == "table" and BegDB.guildContactedAt or {}
  BegDB.guildContactedAt[ns.StrLower(contact.guild)] = time()
end

-- Guards the ways this goes wrong: double-clicking the same name by accident,
-- re-sending the opener to somebody already asked, or hitting two members of
-- the same guild back-to-back.
function ns.CanWhisper(contact)
  if not contact then return false, "No contact selected." end

  local status = contact.status
  local why = ClosedReason(contact, status) or DoubleClickReason(contact)
    or UnconfirmedReason(contact, status) or TooSoonReason(contact, status)
    or GuildCooldownReason(contact, status)
  if why then return false, why end
  return true
end

----------------------------------------------------------------------
-- The game's answers to a send
----------------------------------------------------------------------

-- The game confirmed a whisper but hid its text or target (WoW: Forever, in chat lockdown). If BegBuddy had
-- just sent an opener, it may well have arrived: hold that name for the full re-whisper wait, not one minute.
function ns.OnHiddenWhisperOut()
  local p = ns.pending
  if not (p and p.at and (GetTime() - p.at) <= 3) then return end
  ns.sentHeld = ns.sentHeld or {}
  ns.sentHeld[p.key] = true
  ns.pending = nil
  if ns.RefreshUI then ns.RefreshUI() end
end

-- "X is ignoring you": the whisper never arrived and never will. Close the name out instead of retrying it.
function ns.OnIgnored(name)
  local c = type(name) == "string" and name ~= "" and ns.FindContact(name) or nil
  if not c then return end
  if ns.pending and ns.pending.key == c.key then ns.pending = nil end
  if ns.lastSendKey == c.key then ns.lastSendAt = nil end
  local fmt = _G.CHAT_IGNORED
  local line = (type(fmt) == "string" and fmt:find("%s", 1, true)) and fmt:format(tostring(c.name))
    or (tostring(c.name) .. " is ignoring you.")
  ns.PushHistory(c, "sys", line)
  local s = c.status
  if s ~= ns.STATUS.FUNDED and s ~= ns.STATUS.BLOCKED and s ~= ns.STATUS.DECLINED then
    ns.SetStatus(c, ns.STATUS.DECLINED, "ignores you")
  elseif ns.RefreshUI then
    ns.RefreshUI()
  end
  ns.Print(string.format("%s is ignoring you - moved to Declined.", tostring(c.name)))
  ns.CountWarning()
end

-- The game will not let this character whisper (a trial or new-account chat limit). Every opener would fail
-- the same way, so stop them until the player resumes.
function ns.OnRestricted()
  ns.pending = nil
  if not BegDB.paused then
    BegDB.paused = true
    ns.Print("The game says this character cannot send that whisper (a chat limit on the account), so sending is paused. /beg resume when the limit is gone.")
  end
  if ns.RefreshUI then ns.RefreshUI() end
end

-- Only formats that name the player are usable. A name-less variant cannot be
-- tied to a pending contact, so matching it would archive whoever happened to
-- be pending when the player hand-whispered some other offline character.
local OFFLINE_FORMATS = {
  "ERR_CHAT_PLAYER_NOT_FOUND_S",
}

local PENDING_TTL = 60   -- seconds a loaded-but-unsent whisper stays armed

local function IsOfflineComplaintFor(msg, contact)
  if not contact then return false end
  local candidates = { contact.full, contact.name }
  for _, key in ipairs(OFFLINE_FORMATS) do
    local fmt = _G[key]
    if type(fmt) == "string" and fmt:find("%%s") then
      for _, n in ipairs(candidates) do
        if type(n) == "string" and n ~= "" then
          local ok, expected = pcall(string.format, fmt, n)
          if ok and expected == msg then return true end
        end
      end
    end
  end
  return false
end

-- They are not playing, so the whisper never left. Archive and move on -
-- retrying an offline player is pure wasted clicks.
local function HandleOffline(pending, msg)
  ns.pending = nil
  -- Nothing was delivered, so the next send need not wait out the gap.
  if ns.lastSendKey == pending.key then ns.lastSendAt = nil end
  if ns.checkState then ns.checkState[pending.key] = "offline" end
  ns.PushHistory(pending, "sys", msg)
  if BegDB.settings.autoArchiveOffline then
    ns.SetStatus(pending, ns.STATUS.ARCHIVED, "not playing")
    ns.Print(string.format("%s is not playing - archived. Requeue if they come back.",
      tostring(pending.name)))
  elseif ns.RefreshUI then
    ns.RefreshUI()
  end
end

-- The game's own whisper-failure lines, by global string name, so they match in any language. A name missing
-- on a client is skipped. Login notices, AFK lines and the rest are never taken for a failed send.
local FAILURE_FORMATS = {
  "ERR_CHAT_PLAYER_AMBIGUOUS_S", "ERR_CHAT_THROTTLED", "ERR_CHAT_RESTRICTED", "ERR_CHAT_WRONG_FACTION",
  "ERR_PLAYER_WRONG_FACTION", "ERR_CHAT_WHILE_DEAD", "ERR_ACCOUNT_SILENCED", "ERR_USER_SQUELCHED",
  "ERR_RESTRICTED_ACCOUNT_TRIAL", "ERR_FEATURE_RESTRICTED_TRIAL", "ERR_GENERIC_THROTTLE", "CHAT_RESTRICTED_TRIAL",
}

local function IsSendFailure(msg, contact)
  for _, key in ipairs(FAILURE_FORMATS) do
    local fmt = _G[key]
    if type(fmt) == "string" and fmt ~= "" then
      if fmt == msg then return true end
      if contact and fmt:find("%s", 1, true) then
        for _, n in ipairs({ contact.full, contact.name }) do
          if type(n) == "string" and n ~= "" then
            local ok, expected = pcall(string.format, fmt, n)
            if ok and expected == msg then return true end
          end
        end
      end
    end
  end
  return false
end

-- A whisper-failure line arriving within a few seconds of a send is the server rejecting it. It is logged
-- verbatim on the card, so the reason shows in the player's own language.
function ns.OnSystem(msg)
  if type(msg) ~= "string" or msg == "" then return end
  local now = GetTime()

  -- They are not playing, so the whisper never left. Archive and move on -
  -- retrying an offline player is pure wasted clicks.
  local pending = ns.pending and BegDB.contacts[ns.pending.key]
  local armed = pending and ns.pending.at and (now - ns.pending.at) <= PENDING_TTL
  if armed and IsOfflineComplaintFor(msg, pending) then
    HandleOffline(pending, msg)
    return
  end

  if not ns.lastSendAt or (now - ns.lastSendAt) > 3 then return end

  -- Log it on whoever was actually messaged, not whoever is open on screen.
  local c = ns.lastSendKey and BegDB.contacts[ns.lastSendKey]
  if not IsSendFailure(msg, c) then return end
  if c then ns.PushHistory(c, "sys", msg) end

  ns.CountWarning()
  if ns.RefreshUI then ns.RefreshUI() end
end

-- Whisper rejections and failed mails both land here. Three in a minute
-- pauses all sending until the player resumes it.
function ns.CountWarning()
  local now = GetTime()
  -- Start a fresh minute once the old one has run out.
  if not ns.firstWarnAt or (now - ns.firstWarnAt) > 60 then
    ns.firstWarnAt = now
    ns.warnCount = 0
  end
  ns.warnCount = (ns.warnCount or 0) + 1
  if not BegDB.paused and ns.warnCount >= 3 and (now - ns.firstWarnAt) <= 60 then
    BegDB.paused = true
    ns.Print("Three server warnings in a minute, so sending is paused. /beg resume when you decide to continue.")
  end
end
