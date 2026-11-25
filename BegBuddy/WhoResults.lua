-- BegBuddy / WhoResults.lua
-- Reading the /who answer: harvesting names, the online check, next-step text, diagnostics.

local _, ns = ...
local SplitQueue = ns.SplitQueue
local QueueSplits = ns.QueueSplits

----------------------------------------------------------------------
-- Harvest
----------------------------------------------------------------------

-- Returns name, level, classToken, classStr, zone. Nil when there is no such entry, and false when the game
-- hides part of it (the caller must not read that as "not there").
-- Handles both the modern table-shaped WhoInfo and the legacy multi-return,
-- because a beta client can be either.
local function ReadWho(index)
  local C = C_FriendList
  local fn
  if C and type(C.GetWhoInfo) == "function" then
    fn = C.GetWhoInfo
  elseif type(_G.GetWhoInfo) == "function" then
    fn = _G.GetWhoInfo
  end
  if not fn then return nil end

  local a, b, c, d, e, f = fn(index)
  if a == nil then return nil end

  if type(a) == "table" then
    -- A hidden field means the whole entry is skipped (it cannot be matched or stored).
    if not ns.Readable(a.fullName, a.name, a.level, a.classStr, a.class, a.area, a.zone, a.classFile,
      a.filename, a.classToken, a.raceStr, a.classID) then return false end
    -- WhoInfo: fullName, fullGuildName, level, raceStr, classStr, area, ...
    local name  = a.fullName or a.name
    local zone  = a.area or a.zone
    local cls   = a.classStr or a.class
    local token = ns.ClassToken(a.classFile, a.classToken, a.filename, cls, a.classID)
    local guild = ns.Readable(a.fullGuildName, a.guild) and (a.fullGuildName or a.guild) or nil
    if guild == "" then guild = nil end
    local race  = ns.Readable(a.raceStr, a.race) and (a.raceStr or a.race) or nil
    if race == "" then race = nil end
    return name, tonumber(a.level), token, cls, zone, guild, race
  end

  -- legacy: name, guild, level, race, class, zone
  if not ns.Readable(a, c, e, f) then return false end
  local guild = ns.Readable(b) and type(b) == "string" and b ~= "" and b or nil
  local race  = ns.Readable(d) and type(d) == "string" and d ~= "" and d or nil
  return a, tonumber(c), ns.ClassToken(e), e, f, guild, race
end

-- Adds one /who result to the contacts. Returns "added", "skipped" (filtered
-- out by non-Latin, known-player, or guildless rules) or nil.
local function HarvestOne(i, selfShort)
  local name, level, classToken, classStr, zone, guild, race = ReadWho(i)
  if not name or name == "" then return nil end
  local short = ns.ShortName(name)
  local isSelf = selfShort and short and ns.StrLower(short) == selfShort
  if isSelf then return nil end
  if BegDB.settings.skipNonLatin and ns.IsNonLatinName(short) then return "skipped" end
  if BegDB.settings.skipKnownPlayers and ns.IsKnownPlayer and ns.IsKnownPlayer(name) then return "skipped" end
  if BegDB.settings.skipGuildless and (not guild or guild == "") then return "skipped" end
  -- EnsureContact leaves existing status alone, so anyone already
  -- declined / blocked / funded is never resurrected into the queue.
  local _, created = ns.EnsureContact(name, {
    level = level, classToken = classToken, class = classStr, zone = zone,
    guild = guild, race = race,
  })
  return created and "added" or nil
end

function ns.Harvest()
  local C = C_FriendList
  if not (C and type(C.GetNumWhoResults) == "function") then return 0, 0, nil end

  -- GetNumWhoResults returns TWO values (shown, total matched). A bare call
  -- passed into tonumber() expands both of them, so the second arrives as
  -- tonumber's base argument and throws "base out of range". Capture them
  -- explicitly and use the second as the real truncation signal.
  local shownRaw, matchedRaw = C.GetNumWhoResults()
  if not ns.Readable(shownRaw, matchedRaw) then return 0, 0, nil end -- hidden counts: nothing to read
  local shown   = tonumber(shownRaw) or 0
  local matched = tonumber(matchedRaw)
  -- Truncation means the server matched MORE than it returned. Equal is a
  -- complete result set, not a truncated one.
  if matched and matched <= shown then matched = nil end

  local added = 0
  local skipped = 0
  local selfShort = ns.selfName and ns.StrLower(ns.selfName) or nil

  for i = 1, shown do
    local result = HarvestOne(i, selfShort)
    if result == "added" then added = added + 1
    elseif result == "skipped" then skipped = skipped + 1 end
  end
  return added, shown, matched, skipped
end

-- Dumps what this client actually gives us for one Who entry, so the field
-- names can be confirmed rather than assumed.
function ns.DumpWho()
  local C = C_FriendList
  local fn
  if C and type(C.GetWhoInfo) == "function" then fn = C.GetWhoInfo
  elseif type(_G.GetWhoInfo) == "function" then fn = _G.GetWhoInfo end

  if not fn then
    ns.Print("No GetWhoInfo on this client. Run /beg probe.")
    return
  end

  local first = fn(1)
  if first == nil then
    ns.Print("GetWhoInfo(1) is empty. Run a scan first, then try again.")
    return
  end

  if type(first) == "table" then
    ns.Print("WhoInfo table fields:")
    local lines = {}
    for k, v in pairs(first) do
      lines[#lines + 1] = string.format("   %s = %s", tostring(k), tostring(v))
    end
    table.sort(lines)
    for _, line in ipairs(lines) do ns.Print(line) end
  else
    local a, b, c, d, e, f = fn(1)
    ns.Print(string.format("legacy: name=%s guild=%s level=%s race=%s class=%s zone=%s",
      tostring(a), tostring(b), tostring(c), tostring(d), tostring(e), tostring(f)))
  end

  local name, level, token, cls, zone = ReadWho(1)
  ns.Print(string.format("resolved -> name=%s  level=%s  classToken=%s  classStr=%s  zone=%s",
    tostring(name), tostring(level), tostring(token), tostring(cls), tostring(zone)))
end

----------------------------------------------------------------------
-- Online check for one name
----------------------------------------------------------------------

-- Session-only answers, by contact key: "pending", "online" or "offline".
ns.checkState = ns.checkState or {}

function ns.CheckState(key)
  return key and ns.checkState[key] or nil
end

-- One click, one /who for one name. Uses the same busy flag as scanning, so a
-- check and a scan can never be confused with each other's answer.
function ns.CheckContact(c)
  if not c then return false end
  if ns.inCombat or (InCombatLockdown and InCombatLockdown()) then
    ns.Print("Can't check during combat.")
    return false
  end
  if ns.scan.busy then
    ns.Print("Still waiting on the previous /who.")
    return false
  end
  if ns.scan.stale then
    local left = 10 - (GetTime() - (ns.scan.staleAt or 0))
    if left > 0 then
      ns.Print(string.format("The last /who may still answer. Try again in %d s.", math.ceil(left)))
      return false
    end
    ns.scan.stale = false
  end
  local api = C_FriendList and C_FriendList.SendWho
  if type(api) ~= "function" then
    ns.Print("C_FriendList.SendWho is missing on this client. Run /beg probe.")
    return false
  end

  local short = ns.ShortName(c.full or c.name) or c.name
  local query = string.format('n-"%s"', tostring(short):gsub('"', ""))
  ns.scan.busy  = true
  ns.scan.slice, ns.scan.sub, ns.scan.band, ns.scan.city = nil, nil, nil, nil
  ns.scan.query = query
  ns.scan.check = { key = c.key, short = ns.StrLower(short), status = c.status }
  ns.checkState[c.key] = "pending"

  ns.SuppressWhoWindow()
  local ok, err = pcall(api, query)
  if not ok then
    ns.scan.busy, ns.scan.check = false, nil
    ns.checkState[c.key] = nil
    ns.RestoreWhoWindow()
    ns.Print("Who query refused: " .. tostring(err))
    return false
  end
  ns.StartScanWatchdog()
  return true
end

-- How many names the answer shows and matched, or nil when the game hides the counts.
local function ResultCounts()
  local shownRaw, matchedRaw = C_FriendList.GetNumWhoResults()
  if not ns.Readable(shownRaw, matchedRaw) then return nil end
  local shown = tonumber(shownRaw) or 0
  return shown, tonumber(matchedRaw) or shown
end

-- Looks for the contact in the answer. Returns found, level, zone, and whether any entry was hidden.
local function FindInAnswer(shown, chk)
  local hidden = false
  for i = 1, shown do
    local name, level, _, _, zone = ReadWho(i)
    if name == false then hidden = true end
    local short = name and ns.ShortName(name)
    if short and ns.StrLower(short) == chk.short then return true, level, zone, hidden end
  end
  return false, nil, nil, hidden
end

-- The answer to a check. Offline means archived right away (if that setting
-- is on). No answer, or too many similar names to tell, changes nothing.
local function FinishCheck(chk)
  local c = BegDB.contacts[chk.key]
  if not c then return end
  local shown, matched = ResultCounts()
  if not shown then -- hidden counts: no answer, so the check changes nothing
    ns.checkState[c.key] = nil
    return
  end

  local found, level, zone, hidden = FindInAnswer(shown, chk)
  if found then
    ns.checkState[c.key] = "online"
    if level then c.level = level; ns.TouchList() end
    if zone then c.zone = zone end
    ns.Print(string.format("%s is online%s.", tostring(c.name),
      zone and (" in " .. tostring(zone)) or ""))
    return
  end

  if hidden then -- an answer the game partly hides cannot prove they are offline
    ns.checkState[c.key] = nil
    return
  end

  if matched > shown then
    ns.checkState[c.key] = nil
    ns.Print(string.format("Too many names like %s online to tell. Just send.", tostring(c.name)))
    return
  end

  ns.checkState[c.key] = "offline"
  -- A whisper that went through in the meantime proves they are online.
  if c.status ~= chk.status then return end
  ns.PushHistory(c, "sys", "/who: not online")
  if BegDB.settings.autoArchiveOffline then
    ns.SetStatus(c, ns.STATUS.ARCHIVED, "not playing")
    ns.Print(string.format("%s is not online - archived. Requeue if they come back.", tostring(c.name)))
  else
    ns.Print(string.format("%s is not online.", tostring(c.name)))
  end
end

-- Queues the smaller scans for a band that came back full and says what comes next.
-- A scan for one class keeps that class when it is cut into levels.
local function QueueBandSplits(city, band, sub)
  local list = {}
  local note
  local class = sub and sub.class
  if band[1] < band[2] then
    for lvl = band[1], band[2] do list[#list + 1] = { lo = lvl, hi = lvl, class = class } end
    note = string.format(" Over 50, so levels %d-%d get one scan each next.", band[1], band[2])
  elseif not class then
    for _, cls in ipairs(ns.WhoClassNames()) do
      list[#list + 1] = { lo = band[1], hi = band[2], class = cls }
    end
    note = string.format(" Over 50 at level %d, so it gets one scan per class next.", band[1])
  else
    note = string.format(" Still over 50 for level %d %s. The server hides the rest of those.",
      band[1], tostring(class))
  end
  if #list > 0 then QueueSplits(city, list) end
  return note
end

local function ScanLabel(idx, band, sub)
  return idx and string.format("Slice %d%s", idx, sub and sub.class and (" " .. sub.class) or "")
    or (band and string.format("Extra scan %d-%d%s", band[1], band[2],
      sub and sub.class and (" " .. sub.class) or ""))
    or "Scan"
end

-- Only credit the slice if the range was not changed while it was running.
-- An extra scan is done once it has answered.
local function CreditSlice(city, idx, sub, samePlan)
  if city and idx and samePlan then
    if idx > ns.GetProgress(city) then ns.SetProgress(city, idx) end
  end
  local q = city and SplitQueue(city)
  if sub and q and q[1] == sub then table.remove(q, 1) end
end

local function ScanMessage(label, total, added, skipped, splitNote)
  local msg = string.format("%s: %d result(s), %d new name(s).", label, total or 0, added or 0)
  if skipped and skipped > 0 then
    msg = msg .. string.format(" Skipped %d non-Latin name(s).", skipped)
  end
  if splitNote then msg = msg .. splitNote end
  return msg
end

function ns.OnWhoListUpdate()
  -- A /who the player ran by hand also fires this, and so does a late answer
  -- to a query that already timed out. Neither is ours to harvest. The late
  -- answer has now arrived, so the next scan no longer needs to wait for it.
  if not ns.scan.busy then
    ns.scan.stale = false
    return
  end

  ns.scan.token = (ns.scan.token or 0) + 1 -- cancels the watchdog
  ns.scan.busy = false
  ns.RestoreWhoWindow()

  local chk = ns.scan.check
  if chk then
    ns.scan.check = nil
    FinishCheck(chk)
    if ns.RefreshUI then ns.RefreshUI() end
    return
  end

  local idx  = ns.scan.slice
  local sub  = ns.scan.sub
  local band = ns.scan.band
  local city = ns.scan.city
  local samePlan = ns.scan.plan == ns.PlanKey()

  local added, total, matched, skipped = ns.Harvest()

  CreditSlice(city, idx, sub, samePlan)

  -- Full answer: queue smaller scans for the rest of this band.
  local cap = tonumber(BegDB.settings.whoCapWarning) or 50
  local full = matched or (total or 0) >= cap
  local splitNote
  if full and city and band and samePlan then splitNote = QueueBandSplits(city, band, sub) end

  ns.lastScan = {
    added = added, total = total, matched = matched, skipped = skipped,
    city = city, slice = idx, at = time(),
  }

  ns.Print(ScanMessage(ScanLabel(idx, band, sub), total, added, skipped, splitNote))

  if ns.RefreshUI then ns.RefreshUI() end
end

-- ", zone 2 of 3" when more than one zone is ticked.
local function ZoneNumber(city)
  local zones = ns.SelectedZones()
  if #zones > 1 then
    for i, z in ipairs(zones) do
      if z == city then return string.format(", zone %d of %d", i, #zones) end
    end
  end
  return ""
end

-- What the next click does when scans are waiting in the queue, or nil.
local function QueuedText(q, where, slices, zoneNo)
  local sub = q and q[1]
  if not sub then return nil end
  if sub.main then
    local left = 0
    for _, e in ipairs(q) do if e.main == sub.main then left = left + 1 end end
    return string.format("Scan levels %d-%d %s in %s   (slice %d of %d, %d class%s left in it%s)",
      sub.lo, sub.hi, ns.Sanitize(sub.class or ""), where, sub.main, #slices, left, left == 1 and "" or "es", zoneNo)
  end
  return string.format("Extra scan: level %s%s in %s   (%d extra left, that band was over 50)",
    sub.lo == sub.hi and tostring(sub.lo) or (sub.lo .. "-" .. sub.hi),
    sub.class and (" " .. ns.Sanitize(sub.class)) or "", where, #q)
end

-- What the next click does once every band of this zone is done.
local function PassDoneText(city, where, slices)
  local nxt = ns.ZoneAfter(city)
  if nxt and nxt ~= city then
    return string.format("%s done. Next click moves to |cffffd100%s|r, levels %d-%d.",
      where, ns.Sanitize(nxt), slices[1][1], slices[1][2])
  end
  return string.format("All %d bands done for %s. Next click starts a new pass at levels %d-%d.",
    #slices, where, slices[1][1], slices[1][2])
end

-- One line describing exactly what the next click will do.
function ns.NextStepText()
  local slices = ns.BuildSlices()
  if #slices == 0 then
    return "No level range set. Set Min and Max in Settings, then click Scan."
  end
  local city = ns.GetSelectedCity()
  if not city then
    return "Pick zones with the Zones button, or click Add this zone."
  end
  local where = "|cffffd100" .. ns.Sanitize(city) .. "|r"
  local zoneNo = ZoneNumber(city)
  local queued = QueuedText(SplitQueue(city), where, slices, zoneNo)
  if queued then return queued end
  local done = ns.GetProgress(city)
  if done >= #slices then return PassDoneText(city, where, slices) end
  local s = slices[done + 1]
  return string.format("Scan levels %d-%d in %s   (slice %d of %d%s)",
    s[1], s[2], where, done + 1, #slices, zoneNo)
end

function ns.ScanProgress()
  local city = ns.GetSelectedCity()
  local slices = ns.BuildSlices()
  local done = ns.GetProgress(city)
  return done, #slices
end

----------------------------------------------------------------------
-- Diagnostics
----------------------------------------------------------------------

function ns.Probe()
  local C = C_FriendList
  ns.Print(string.format("SendWho=%s  GetWhoInfo=%s  GetNumWhoResults=%s  SetWhoToUi=%s",
    type(C and C.SendWho), type(C and C.GetWhoInfo),
    type(C and C.GetNumWhoResults), type(C and C.SetWhoToUi)))
  ns.Print(string.format("ChatFrame_OpenChat=%s  SendChatMessage=%s  Ambiguate=%s  SaveAddOnsData=%s",
    type(ChatFrame_OpenChat), type(SendChatMessage), type(Ambiguate),
    type(C_AddOns and C_AddOns.SaveAddOnsData)))
  ns.Print(string.format("C_Map.GetMapInfo=%s  GetRealZoneText=%s",
    type(C_Map and C_Map.GetMapInfo), type(GetRealZoneText)))
  ns.Print(string.format("InviteUnit=%s  AddFriend=%s",
    type((C_PartyInfo and C_PartyInfo.InviteUnit) or _G.InviteUnit),
    type(C and C.AddFriend)))

  -- City diagnostics: these two lines say whether the dropdown has anything to
  -- show and, if not, why.
  ns.Print(string.format("Cities in list: %d   selected: %s",
    #(BegDB.cities or {}), tostring(ns.GetSelectedCity())))
  if C_Map and type(C_Map.GetMapInfo) == "function" then
    local ok, info = pcall(C_Map.GetMapInfo, 1519)
    local desc
    if not ok then
      desc = "threw " .. tostring(info)
    elseif type(info) ~= "table" then
      desc = "returned " .. type(info)
    else
      desc = "name=" .. tostring(info.name)
    end
    ns.Print("GetMapInfo(1519) -> " .. desc)
  end
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("WHO_LIST_UPDATE")
f:SetScript("OnEvent", function()
  ns.OnWhoListUpdate()
end)
