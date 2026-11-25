-- BegBuddy / Scan.lua
-- The /who side. Every SendWho call must originate from a real click or
-- keypress: the API is flagged #hwevent since 8.2.5 as an anti-gold-spam
-- measure, so there is deliberately no timer-driven scanning here.

local ADDON, ns = ...

ns.scan = { busy = false, token = 0 }

----------------------------------------------------------------------
-- Slice plan
----------------------------------------------------------------------

-- The slices ARE the level range, cut into bands small enough to stay under
-- the client's per-query result cap. There is no separate "plan" any more: a
-- second source of truth for the same thing caused the range fields to look
-- dead whenever the plan had been pinned.
local planCache = { key = nil }

function ns.BuildSlices()
  local s = BegDB.settings
  local lo   = tonumber(s.minLevel) or 1
  local hi   = tonumber(s.maxLevel) or 60
  local step = tonumber(s.bandSize) or 5

  if lo < 1 then lo = 1 end
  if step < 1 then step = 1 end
  if hi < lo then hi = lo end
  if hi > 200 then hi = 200 end   -- a typo must not build a million slices

  local key = string.format("%d|%d|%d", lo, hi, step)
  if planCache.key == key then return planCache.slices end

  local slices = {}
  local a = lo
  while a <= hi do
    local b = math.min(a + step - 1, hi)
    slices[#slices + 1] = { a, b }
    a = b + 1
  end

  planCache.key = key
  planCache.slices = slices
  return slices
end

-- Progress is stored against the plan it was made on. Without this, changing
-- Min / Max kept the old slice count, so a fresh range showed as already done
-- or started halfway through.
function ns.PlanKey()
  ns.BuildSlices()
  -- A class pick is part of the plan: each class has its own progress and its
  -- own extra scans. With no class picked the key is the same as it always was,
  -- so saved progress carries over.
  local cls = ns.ScanClassKey()
  return cls and (planCache.key .. "|" .. cls) or planCache.key
end

function ns.GetProgress(city)
  if not city then return 0 end
  local entry = BegDB.progress[city]
  if type(entry) == "number" then
    -- Saved before plans were tracked: assume it belongs to the current plan.
    entry = { plan = ns.PlanKey(), done = entry }
    BegDB.progress[city] = entry
  end
  if type(entry) ~= "table" or entry.plan ~= ns.PlanKey() then return 0 end
  return tonumber(entry.done) or 0
end

function ns.SetProgress(city, done, plan)
  if not city then return end
  BegDB.progress[city] = { plan = plan or ns.PlanKey(), done = done }
end

-- Kept for callers that want the whole state in one go.
function ns.SlicePlanState()
  return ns.BuildSlices(), nil, false
end

function ns.SlicePlanText()
  local parts = {}
  for _, sl in ipairs(ns.BuildSlices()) do
    parts[#parts + 1] = string.format("%d-%d", sl[1], sl[2])
  end
  return table.concat(parts, ", ")
end

function ns.SliceQuery(zone, slice, className)
  -- Strip double quotes: they would break the z-"..." syntax.
  local safe = tostring(zone or ""):gsub('"', "")
  local q = string.format('z-"%s"', safe)
  if slice then
    q = q .. string.format(" %d-%d", slice[1], slice[2])
  end
  if className then
    q = q .. string.format(' c-"%s"', (tostring(className):gsub('"', "")))
  end
  return q
end

----------------------------------------------------------------------
-- Extra scans for bands over the server's 50-name cap
----------------------------------------------------------------------

-- A /who answers with at most 50 names. When a band comes back full, the rest
-- of that band is split into smaller queries (single levels, then one per
-- class) and those run on the next clicks, before the plan moves on. That way
-- a busy city is covered completely instead of stopping at 50.
local FALLBACK_CLASSES = { "WARRIOR", "PALADIN", "PRIEST", "SHAMAN", "DRUID",
                           "ROGUE", "MAGE", "WARLOCK", "HUNTER" }

-- Class names this player's /who can actually find: Horde never sees
-- Paladins and Alliance never sees Shamans on this client, so asking would
-- waste a click.
function ns.WhoClassNames()
  local order = type(CLASS_SORT_ORDER) == "table" and CLASS_SORT_ORDER or FALLBACK_CLASSES
  local names = type(LOCALIZED_CLASS_NAMES_MALE) == "table" and LOCALIZED_CLASS_NAMES_MALE or {}
  local faction = UnitFactionGroup and UnitFactionGroup("player")
  local out = {}
  for _, token in ipairs(order) do
    local skip = (faction == "Horde" and token == "PALADIN")
              or (faction == "Alliance" and token == "SHAMAN")
    if not skip then
      local n = names[token] or (token:sub(1, 1) .. token:sub(2):lower())
      out[#out + 1] = n
    end
  end
  return out
end

-- Pending extra scans live for this session only, for one city on one level
-- range. Changing either drops them, the same way progress is kept per range.
local function SplitQueue(city)
  local sp = ns.scan.splits
  if sp and sp.city == city and sp.plan == ns.PlanKey() then return sp.queue end
  return nil
end

ns.SplitQueue = SplitQueue

function ns.PendingSplits(city)
  local q = SplitQueue(city or ns.GetSelectedCity())
  return q and #q or 0
end

local function QueueSplits(city, list)
  local q = SplitQueue(city)
  if not q then
    q = {}
    ns.scan.splits = { city = city, plan = ns.PlanKey(), queue = q }
  end
  -- Newest first, in their own order, so a split band finishes before the
  -- rest of an older split carries on.
  for i = #list, 1, -1 do table.insert(q, 1, list[i]) end
end

ns.QueueSplits = QueueSplits

function ns.ClearSplits()
  ns.scan.splits = nil
end

----------------------------------------------------------------------
-- City selection
----------------------------------------------------------------------

function ns.GetCities()
  return BegDB.cities or {}
end

-- The zone the next scan runs in: the stored one while it is still picked,
-- otherwise the first picked zone. selectedCity keeps its old name so saved
-- progress carries over.
function ns.GetSelectedCity()
  local list = ns.SelectedZones()
  local sel = BegDB.selectedCity

  -- Only honour the stored zone if it is still picked, otherwise the panel
  -- and the scan target can disagree.
  if sel then
    for _, z in ipairs(list) do
      if z == sel then return sel end
    end
  end

  BegDB.selectedCity = list[1]
  return BegDB.selectedCity
end

function ns.SetSelectedCity(name)
  if name then ns.SetZoneSelected(name, true) end
  BegDB.selectedCity = name
  if ns.RefreshUI then ns.RefreshUI() end
end

-- The picked zone after this one, wrapping round. With one zone picked that
-- is the same zone again.
function ns.ZoneAfter(zone)
  local list = ns.SelectedZones()
  if #list == 0 then return nil end
  for i, z in ipairs(list) do
    if z == zone then return list[(i % #list) + 1] end
  end
  return list[1]
end

-- Moves the scan on to the next picked zone. A zone that already finished
-- its pass starts a fresh one, so people who logged in since get found.
function ns.NextZone(quiet)
  local cur = ns.GetSelectedCity()
  local nxt = ns.ZoneAfter(cur)
  if not nxt then
    ns.Print("No zones picked. Click Zones in the window.")
    return nil
  end
  if ns.GetProgress(nxt) >= #ns.BuildSlices() then ns.SetProgress(nxt, 0) end
  BegDB.selectedCity = nxt
  if not quiet then ns.Print("Scanning moves on to " .. ns.Sanitize(nxt) .. ".") end
  if ns.RefreshUI then ns.RefreshUI() end
  return nxt
end

-- A zone counts as finished once every band is done and no extra scans for
-- full bands are left.
local function ZoneFinished(city)
  local q = SplitQueue(city)
  return ns.GetProgress(city) >= #ns.BuildSlices() and not (q and q[1])
end

function ns.AddCurrentZone()
  local zone = GetRealZoneText and GetRealZoneText() or nil
  if not zone or zone == "" then
    ns.Print("Couldn't read your current zone.")
    return
  end
  local had = ns.IsZoneSelected(zone)
  if not ns.IsBuiltInZone(zone) then ns.AddCity(zone, nil) end
  ns.Print((had and "Already picked: " or "Picked zone: ") .. ns.Sanitize(zone))
  ns.SetSelectedCity(zone)
end

function ns.AddCityByName(raw)
  local name = tostring(raw or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then
    ns.Print("Type a zone name first.")
    return false
  end
  if not ns.IsBuiltInZone(name) and ns.AddCity(name, nil) then
    ns.Print("Added zone: " .. ns.Sanitize(name))
  end
  ns.SetSelectedCity(name)
  return true
end

-- Walks every uiMapID this client knows and keeps anything that looks like a
-- capital. This does not care which map set the game type uses, so it works
-- even when the built-in map IDs mean nothing.
function ns.FindCities()
  if not (C_Map and type(C_Map.GetMapInfo) == "function") then
    ns.Print("C_Map.GetMapInfo is missing on this client, so I cannot scan. Use Add this zone instead.")
    return 0
  end

  local known = {}
  for _, n in ipairs(ns.DEFAULT_CITY_NAMES or {}) do known[n] = true end

  local seen, added = 0, 0
  for id = 1, 3000 do
    local ok, info = pcall(C_Map.GetMapInfo, id)
    if ok and type(info) == "table" and type(info.name) == "string" then
      seen = seen + 1
      local isCity = info.name:lower():find("city", 1, true) ~= nil or known[info.name]
      if isCity and ns.AddCity(info.name, id) then added = added + 1 end
    end
  end

  ns.Print(string.format("Scanned %d map entries, added %d new city name(s).", seen, added))
  if seen == 0 then
    ns.Print("The map API returned nothing at all, so use Add this zone or type a name in settings.")
  end
  if ns.RefreshUI then ns.RefreshUI() end
  return added
end

function ns.ResetSlices()
  local city = ns.GetSelectedCity()
  if not city then return end
  ns.SetProgress(city, 0)
  ns.ClearSplits()
  ns.Print("Slice plan reset for " .. city .. ".")
  if ns.RefreshUI then ns.RefreshUI() end
end

----------------------------------------------------------------------
-- Who window suppression
----------------------------------------------------------------------

-- The Who switch must stay ON for our queries: switched off, a query with 1-3
-- results is printed to chat and WHO_LIST_UPDATE never fires, so quiet level
-- bands were lost and timed out. Instead the Blizzard Friends window is kept
-- shut by pausing its WHO_LIST_UPDATE listener for our query only, and the
-- listener is handed back afterwards so the player's own /who is untouched.
local function SetWhoToUi(flag)
  if C_FriendList and type(C_FriendList.SetWhoToUi) == "function" then
    pcall(C_FriendList.SetWhoToUi, flag and true or false)
  end
end


local function FriendsWhoListener()
  local ff = _G.FriendsFrame
  if type(ff) == "table" and type(ff.IsEventRegistered) == "function"
     and type(ff.UnregisterEvent) == "function" and type(ff.RegisterEvent) == "function" then
    return ff
  end
end

function ns.SuppressWhoWindow()
  SetWhoToUi(true)
  if BegDB.settings.showBlizzardWho then return end
  local ff = FriendsWhoListener()
  if ff and ff:IsEventRegistered("WHO_LIST_UPDATE") then
    ff:UnregisterEvent("WHO_LIST_UPDATE")
    ns.scan.pausedFriends = true
  end
end

function ns.RestoreWhoWindow()
  if not ns.scan.pausedFriends then return end
  ns.scan.pausedFriends = false
  -- Next frame: re-registering inside the event that is being handled could
  -- still deliver this same result to the Friends window and pop it open.
  local function Give()
    local ff = FriendsWhoListener()
    if ff then ff:RegisterEvent("WHO_LIST_UPDATE") end
  end
  if C_Timer and C_Timer.After then C_Timer.After(0, Give) else Give() end
end

----------------------------------------------------------------------
-- Scanning
----------------------------------------------------------------------

-- Prints why and returns true when a scan cannot start right now.
local function ScanBlocked()
  if ns.inCombat or (InCombatLockdown and InCombatLockdown()) then
    ns.Print("Can't scan during combat.")
    return true
  end
  if ns.scan.busy then
    ns.Print("Still waiting on the previous query.")
    return true
  end

  -- The last query timed out but may still answer. Sending now would let that
  -- late answer be credited to the new slice, so wait it out briefly.
  if ns.scan.stale then
    local left = 10 - (GetTime() - (ns.scan.staleAt or 0))
    if left > 0 then
      ns.Print(string.format("The last query may still answer. Try again in %d s.", math.ceil(left)))
      return true
    end
    ns.scan.stale = false
  end
  return false
end

-- This zone is done: carry on in the next picked one. With a single zone
-- picked this lands on the same zone and starts a new pass, as before.
local function MoveOnIfFinished(city)
  if ZoneFinished(city) then
    local nxt = ns.ZoneAfter(city)
    if nxt and nxt ~= city then
      ns.Print(string.format("%s done. Moving on to %s.", ns.Sanitize(city), ns.Sanitize(nxt)))
      if ZoneFinished(nxt) then ns.SetProgress(nxt, 0) end
      BegDB.selectedCity = nxt
      return nxt
    end
  end
  return city
end

-- Picks what to scan next. Returns idx (nil for an extra scan), slice, query, sub, pending.
-- With classes picked, a band becomes one queued scan per class; those carry the
-- band's number (sub.main), so answering one moves the plan on like a plain band.
local function ChooseSlice(city, slices)
  -- Extra scans for a band that came back full go first.
  local pending = SplitQueue(city)
  if not (pending and pending[1]) then
    local idx = ns.GetProgress(city) + 1
    if idx > #slices then
      -- Every band is done: start another pass. People log in and out all
      -- the time, so a new pass keeps finding new names. No Reset needed.
      ns.SetProgress(city, 0)
      idx = 1
      ns.Print(string.format("All %d bands done for %s. Starting a new pass to catch new arrivals.",
        #slices, city))
    end
    local slice = slices[idx]
    local classes = ns.ScanClasses()
    if not classes then
      return idx, slice, ns.SliceQuery(city, slice), nil, pending
    end
    local list = {}
    for _, name in ipairs(classes) do
      list[#list + 1] = { lo = slice[1], hi = slice[2], class = name, main = idx }
    end
    QueueSplits(city, list)
    pending = SplitQueue(city)
  end
  local sub = pending[1]
  local slice = { sub.lo, sub.hi }
  return sub.main, slice, ns.SliceQuery(city, slice, sub.class), sub, pending
end

function ns.ScanNextSlice()
  if ScanBlocked() then return end

  local city = ns.GetSelectedCity()
  if not city then
    ns.Print("Pick at least one zone first (Zones in the window), or use /beg addzone.")
    return
  end

  local slices = ns.BuildSlices()
  if #slices == 0 then
    ns.Print("Level range is empty. Check the level range in settings.")
    return
  end

  city = MoveOnIfFinished(city)
  local idx, slice, query, sub, pending = ChooseSlice(city, slices)

  local api = C_FriendList and C_FriendList.SendWho
  if type(api) ~= "function" then
    ns.Print("C_FriendList.SendWho is missing on this client. Run /beg probe.")
    return
  end

  ns.scan.busy  = true
  ns.scan.check = nil
  ns.scan.slice = idx          -- nil for an extra scan: it never moves the plan
  ns.scan.sub   = sub
  ns.scan.band  = slice
  ns.scan.city  = city
  ns.scan.query = query
  ns.scan.plan  = ns.PlanKey()

  ns.SuppressWhoWindow()
  local ok, err = pcall(api, query)
  if not ok then
    ns.scan.busy = false
    ns.RestoreWhoWindow()
    ns.Print("Who query refused: " .. tostring(err))
    ns.Print("This call requires a hardware event and is rate limited. Use the Scan button in the window.")
    return
  end

  if sub and not idx then
    ns.Print(string.format("Scanning %s extra scan (%d left)  [%s]", city, #pending, query))
  else
    ns.Print(string.format("Scanning %s slice %d/%d  [%s]", city, idx, #slices, query))
  end
  ns.StartScanWatchdog()
end

-- The server can just not answer (documented cooldown). Without this the
-- addon would sit on a stuck "busy" flag forever.
function ns.StartScanWatchdog()
  ns.scan.token = (ns.scan.token or 0) + 1
  local myToken = ns.scan.token
  if C_Timer and C_Timer.After then
    C_Timer.After(6, function()
      if ns.scan.token ~= myToken then return end
      if not ns.scan.busy then return end
      ns.scan.busy = false
      ns.scan.stale = true
      ns.scan.staleAt = GetTime()
      ns.RestoreWhoWindow()
      local chk = ns.scan.check
      ns.scan.check = nil
      if chk then
        ns.checkState[chk.key] = nil
        ns.Print("No answer to the online check (/who is rate limited). You can still just send.")
        if ns.RefreshUI then ns.RefreshUI() end
        return
      end
      ns.Print("No response from the server (Who queries are rate limited). Wait a moment and click Scan again.")
      if ns.RefreshUI then ns.RefreshUI() end
    end)
  end
end
