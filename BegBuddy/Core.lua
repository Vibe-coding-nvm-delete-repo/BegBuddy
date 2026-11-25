-- BegBuddy / Core.lua
-- Namespace, saved variables, zone picks and the boot events.
-- No Blizzard frames are hooked anywhere in this addon: zero taint risk.

local ADDON, ns = ...

ns.ADDON   = ADDON
ns.ICON    = "Interface/Icons/INV_Misc_Coin_01"

----------------------------------------------------------------------
-- State model
----------------------------------------------------------------------

ns.STATUS = {
  QUEUED    = "queued",
  CONTACTED = "contacted",
  REPLIED   = "replied",
  FUNDED    = "funded",
  DECLINED  = "declined",
  ARCHIVED  = "archived",
  BLOCKED   = "blocked",
}

ns.TABS = {
  { id = "queued",    label = "Queued"    },
  { id = "contacted", label = "Contacted" },
  { id = "replied",   label = "Replied"   },
  { id = "funded",    label = "Funded"    },
  { id = "declined",  label = "Declined"  },
  { id = "archived",  label = "Archived"  },
  { id = "blocked",   label = "Blocked"   },
}

-- One colour per pipeline state, used on the tabs, the counters and the
-- detail pane so a state reads the same everywhere.
ns.STATUS_COLOR = {
  queued    = "d8d8dc",
  contacted = "5cc8ff",
  replied   = "7fe07f",
  funded    = "ffd100",
  declined  = "ff9933",
  archived  = "8f8f96",
  blocked   = "ff6060",
}

function ns.StatusText(status, text)
  local hex = ns.STATUS_COLOR[status] or "cccccc"
  return "|cff" .. hex .. tostring(text or status or "") .. "|r"
end

-- States that must never be re-queued, even if a later scan finds the name.
ns.TERMINAL = { declined = true, blocked = true, funded = true }

----------------------------------------------------------------------
-- Defaults
----------------------------------------------------------------------

-- Default message. Older defaults are listed so a saved copy that was never
-- edited gets upgraded, while a template the player has customised is left
-- strictly alone.
local DEFAULT_TEMPLATE = "Hi {name}! I'm completely new to wow and trying to scrape together enough for my first bag. Could you spare 1-2 silver pretty plz? Totally fine if not, thanks either way!"

local LEGACY_DEFAULT_TEMPLATES = {
  "Hi {name}! I'm brand new here and trying to scrape together enough for my first bag. Could you spare 1-2 silver? Totally fine if not, thanks either way!",
}

ns.DEFAULT_TEMPLATE = DEFAULT_TEMPLATE

local DEFAULTS = {
  version = 1,
  settings = {
    template = DEFAULT_TEMPLATE,
    minLevel = 1,
    -- maxLevel has no fixed default: InitDB sets it to this client's level cap.
    bandSize = 5,
    replyGap = 2,            -- seconds between sends (replies and one-click sends)
    whoCapWarning = 50,      -- warn when a slice returns this many (likely truncated)
    rewhisperMinutes = 30,   -- do not re-ask the same person inside this window
    showBlizzardWho = false, -- true = let the Blizzard Who window open on scans
    maxHistory = 40,         -- messages kept per contact
    trackUnknownWhispers = false, -- true = a stranger who whispers first becomes a Replied contact
    skipNonLatin = true,     -- do not queue names we would struggle to write to
    autoArchiveOffline = true, -- archive anyone the client says is not playing
    oneClickSend = false,    -- true = the whisper button sends; false = load into chat, press Enter
    listSort = "found",      -- list order: "found" (order scanned), "name" or "level"
    listSortDesc = false,    -- reverse the list order
    mailOpenWindow = true,   -- opening a mailbox opens this window too
    successStage = "funded", -- Stats tab: what counts as a success - "replied", "funded" or "gold"
    successGold = 1000,      -- copper a person must send for "gold" (10 silver)
    statsMinSample = 30,     -- asks a row needs before its rate is trusted
    statsView = "template",  -- the Stats tab's breakdown
  },
  cities = {},     -- zones the player added by hand (plus the old seeded capitals)
  zoneSel = nil,   -- [zone name] = true for every zone picked for scanning
  zoneCollapsed = {}, -- [group id] = true when that group is folded in the picker
  progress = {},   -- [zoneString] = highest slice index completed
  contacts = {},   -- [lowercased full name] = contact
  order = {},      -- insertion order of contact keys
  templates = {},  -- ordered list of { name, text, sent, replied, funded }
  mailTemplates = {}, -- ordered list of { name, subject, body, sent, replied, funded }
  paused = false,
}

-- Mail limits on this client: the subject box takes 64 characters and the
-- body 500. Anything longer is cut before it is sent.
ns.MAIL_SUBJECT_MAX = 64
ns.MAIL_BODY_MAX    = 500

local DEFAULT_MAIL_SUBJECT = "Hi {name}, quick favor?"
local DEFAULT_MAIL_BODY = "Hi {name}!\n\nI'm completely new to wow and trying to scrape together enough for my first bag. If you could spare 1-2 silver I'd be really grateful.\n\nTotally fine if not, thanks either way and good luck out there!"
ns.DEFAULT_MAIL_SUBJECT = DEFAULT_MAIL_SUBJECT
ns.DEFAULT_MAIL_BODY    = DEFAULT_MAIL_BODY

-- Every zone the picker offers, grouped the way the world map is. English
-- names, which is what /who matches on an English client; anything else
-- (another language, a new zone) can still be added by hand.
ns.ZONE_GROUPS = {
  { id = "cities", label = "Capital cities", color = "ffd100", zones = {
    "Orgrimmar", "Thunder Bluff", "Undercity",
    "Stormwind City", "Ironforge", "Darnassus",
  } },
  -- Where every new character starts, so a brand new player is easy to find.
  -- These zones are also listed under their continent below.
  { id = "starting", label = "Starting zones", color = "b48cff", zones = {
    "Elwynn Forest", "Dun Morogh", "Teldrassil", "Durotar", "Mulgore", "Tirisfal Glades",
    "Eversong Woods", "Azuremyst Isle",
  } },
  { id = "kalimdor", label = "Kalimdor", color = "ff9933", zones = {
    "Ashenvale", "Azshara", "Darkshore", "Desolace", "Durotar", "Dustwallow Marsh",
    "Felwood", "Feralas", "Moonglade", "Mulgore", "Silithus", "Stonetalon Mountains",
    "Tanaris", "Teldrassil", "The Barrens", "Thousand Needles", "Un'Goro Crater",
    "Winterspring",
  } },
  { id = "eastern", label = "Eastern Kingdoms", color = "7fe07f", zones = {
    "Alterac Mountains", "Arathi Highlands", "Badlands", "Blasted Lands",
    "Burning Steppes", "Deadwind Pass", "Dun Morogh", "Duskwood",
    "Eastern Plaguelands", "Elwynn Forest", "Hillsbrad Foothills", "Loch Modan",
    "Redridge Mountains", "Searing Gorge", "Silverpine Forest", "Stranglethorn Vale",
    "Swamp of Sorrows", "The Hinterlands", "Tirisfal Glades", "Western Plaguelands",
    "Westfall", "Wetlands",
  } },
  { id = "pvp", label = "Battlegrounds", color = "ff6060", zones = {
    "Warsong Gulch", "Arathi Basin", "Alterac Valley",
  } },
}

-- Capital cities. First choice is the uiMapID, resolved through C_Map so the
-- strings are always this client's own localized zone names. Classic Era and
-- Hardcore use the 1453-1458 map set, modern clients the later IDs; whichever
-- set this client knows wins, and a name is only added once. If neither set
-- resolves we fall back to plain names.
local DEFAULT_CITY_MAPS = {
  1453, -- Stormwind City (Classic)
  1454, -- Orgrimmar (Classic)
  1455, -- Ironforge (Classic)
  1457, -- Darnassus (Classic)
  1458, -- Undercity (Classic)
  1456, -- Thunder Bluff (Classic)
  1519, -- Stormwind City
  1637, -- Orgrimmar
  1537, -- Ironforge
  1657, -- Darnassus
  1497, -- Undercity
  1638, -- Thunder Bluff
  3557, -- The Exodar
  3487, -- Silvermoon City
}

local DEFAULT_CITY_NAMES = {
  "Stormwind City", "Orgrimmar", "Ironforge", "Darnassus",
  "Undercity", "Thunder Bluff", "The Exodar", "Silvermoon City",
}

ns.DEFAULT_CITY_NAMES = DEFAULT_CITY_NAMES

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------

-- Doubles the pipe so chat escape sequences inside user data render literally
-- instead of being interpreted as links or textures. Never run this over
-- markup the addon added itself.
function ns.Sanitize(s)
  return (tostring(s or ""):gsub("%|", "||"))
end

local function DeepCopy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = DeepCopy(x) end
  return out
end
ns.DeepCopy = DeepCopy

local function StrLower(s)
  if type(s) ~= "string" then return s end
  if strlower then return strlower(s) end
  return string.lower(s)
end
ns.StrLower = StrLower

function ns.Print(msg)
  print("|cff5cc8ffBegBuddy|r " .. tostring(msg))
end

-- True when none of the values are hidden by the game. WoW: Forever hides some chat text, names and /who answers
-- from addons: a hidden value can be shown but not compared, matched or stored, so the caller skips it.
function ns.Readable(...)
  if not issecretvalue then return true end
  for i = 1, select("#", ...) do
    if issecretvalue((select(i, ...))) then return false end
  end
  return true
end

-- True while the game locks chat for addons (WoW: Forever, in instances, battlegrounds and encounters). Then
-- whispers and their confirms are hidden, so nothing is sent. Classic Era has the call too and returns false.
ns.CHAT_LOCKED_TEXT = "Chat is locked for addons here (instance, battleground or encounter), so nothing was sent."
function ns.ChatLocked()
  local fn = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
  if type(fn) ~= "function" then return false end
  local ok, locked = pcall(fn)
  return ok and locked == true
end

-- Strip the realm suffix for display. Ambiguate handles the weird cases
-- (the alt-code no-break space, connected-realm suffixes) that a gsub does not.
function ns.ShortName(full)
  if type(full) ~= "string" or full == "" then return nil end
  if Ambiguate then
    local ok, short = pcall(Ambiguate, full, "short")
    if ok and type(short) == "string" and short ~= "" then return short end
  end
  return (full:gsub("%-.*$", ""))
end

-- The unique key. Keeps the realm on purpose: two players named Bob on two
-- connected realms must not collapse into one contact.
function ns.KeyFor(full)
  if type(full) ~= "string" or full == "" then return nil end
  return StrLower(full)
end

----------------------------------------------------------------------
-- Database
----------------------------------------------------------------------

-- Upgrades a template that is still one of our old defaults. A template the
-- player has edited will not match any of them, so it is never overwritten.
function ns.MigrateTemplate()
  local s = BegDB.settings
  local current = s.template
  if type(current) ~= "string" or current == "" then
    s.template = DEFAULT_TEMPLATE
    return
  end
  for _, old in ipairs(LEGACY_DEFAULT_TEMPLATES) do
    if current == old then
      s.template = DEFAULT_TEMPLATE
      return
    end
  end
end

-- This client's level cap, the default for the Max level setting.
local function LevelCap()
  local cap = type(GetMaxPlayerLevel) == "function" and tonumber(GetMaxPlayerLevel())
  return cap or 60
end

-- A fresh settings table as InitDB would make it, for a profile reset.
function ns.SettingsDefaults()
  local s = DeepCopy(DEFAULTS.settings)
  s.maxLevel = LevelCap()
  return s
end

local function FillDefaults()
  for k, v in pairs(DEFAULTS) do
    if BegDB[k] == nil then BegDB[k] = DeepCopy(v) end
  end
  for k, v in pairs(DEFAULTS.settings) do
    if BegDB.settings[k] == nil then BegDB.settings[k] = v end
  end
  if BegDB.settings.maxLevel == nil then BegDB.settings.maxLevel = LevelCap() end
end

local function EnsureTables()
  for _, key in ipairs({ "contacts", "order", "progress", "cities", "zoneCollapsed" }) do
    if type(BegDB[key]) ~= "table" then BegDB[key] = {} end
  end
end

function ns.InitDB()
  if type(BegDB) ~= "table" then BegDB = {} end
  ns.ResetContactIndex()
  FillDefaults()
  EnsureTables()
  ns.MigrateTemplate()
  ns.MigrateTemplates()
  ns.MigrateMailTemplates()
  ns.EnsureQuick()
  -- The old "scan plan" was a second source of truth for the level range and
  -- would silently override the Min/Max fields. Purge it.
  if BegDB.settings.slicePlan ~= nil then BegDB.settings.slicePlan = nil end
  ns.SeedCities()
  ns.ResolveCityNames()
  -- Before zones could be multi-picked there was one selected city. Carry it
  -- over as the only pick, so an existing setup scans exactly what it did.
  if type(BegDB.zoneSel) ~= "table" then
    BegDB.zoneSel = {}
    local first = BegDB.selectedCity or (BegDB.cities[1] and BegDB.cities[1].name)
    if first then BegDB.zoneSel[first] = true end
  end
end

function ns.ResolveCityNames()
  if not (C_Map and C_Map.GetMapInfo) then return end
  for _, c in ipairs(BegDB.cities) do
    if c.id then
      local info = C_Map.GetMapInfo(c.id)
      if info and info.name then c.name = info.name end
    end
  end
end

function ns.SeedCities()
  if #BegDB.cities > 0 then return end

  -- First pass: real uiMapIDs, so the name is whatever this client calls it.
  for _, mapID in ipairs(DEFAULT_CITY_MAPS) do
    local name
    if C_Map and type(C_Map.GetMapInfo) == "function" then
      local ok, info = pcall(C_Map.GetMapInfo, mapID)
      if ok and type(info) == "table" and type(info.name) == "string" then
        name = info.name
      end
    end
    if name then ns.AddCity(name, mapID) end
  end

  -- Second pass: only if the map IDs meant nothing to this client. Without this
  -- an unrecognised map set leaves the dropdown with zero entries, which reads
  -- as a dead control.
  if #BegDB.cities == 0 then
    for _, name in ipairs(DEFAULT_CITY_NAMES) do
      BegDB.cities[#BegDB.cities + 1] = { name = name, byname = true }
    end
  end
end

function ns.AddCity(name, id)
  if type(name) ~= "string" or name == "" then return false end
  for _, c in ipairs(BegDB.cities) do
    if c.name == name then return false end
  end
  BegDB.cities[#BegDB.cities + 1] = { id = id, name = name }
  return true
end

function ns.RemoveCity(name)
  for i, c in ipairs(BegDB.cities) do
    if c.name == name then
      table.remove(BegDB.cities, i)
      BegDB.progress[name] = nil
      -- A zone that is also in a built-in group stays pickable there.
      if not ns.IsBuiltInZone(name) and BegDB.zoneSel then BegDB.zoneSel[name] = nil end
      return true
    end
  end
  return false
end

----------------------------------------------------------------------
-- Zone picks
----------------------------------------------------------------------

local builtIn
function ns.IsBuiltInZone(name)
  if not builtIn then
    builtIn = {}
    for _, g in ipairs(ns.ZONE_GROUPS) do
      for _, z in ipairs(g.zones) do builtIn[z] = true end
    end
  end
  return builtIn[name] == true
end

-- The groups the picker shows: the built-in ones, then every zone the player
-- added that is not already in one of them.
function ns.ZoneGroups()
  local out = {}
  for _, g in ipairs(ns.ZONE_GROUPS) do out[#out + 1] = g end
  local custom = {}
  for _, c in ipairs(BegDB.cities or {}) do
    if c.name and not ns.IsBuiltInZone(c.name) then custom[#custom + 1] = c.name end
  end
  if #custom > 0 then
    out[#out + 1] = { id = "custom", label = "Added by you", color = "5cc8ff", zones = custom }
  end
  return out
end

function ns.IsZoneSelected(name)
  return BegDB.zoneSel and BegDB.zoneSel[name] == true
end

function ns.SetZoneSelected(name, on)
  if type(name) ~= "string" or name == "" then return end
  BegDB.zoneSel = BegDB.zoneSel or {}
  BegDB.zoneSel[name] = on and true or nil
  if ns.RefreshUI then ns.RefreshUI() end
end

-- Every picked zone, in the picker's order. Scanning walks this list.
function ns.SelectedZones()
  local out, seen = {}, {}
  for _, g in ipairs(ns.ZoneGroups()) do
    for _, z in ipairs(g.zones) do
      if not seen[z] and ns.IsZoneSelected(z) then
        seen[z] = true
        out[#out + 1] = z
      end
    end
  end
  return out
end

----------------------------------------------------------------------
-- Save (honest version)
----------------------------------------------------------------------

function ns.SaveNow(quiet)
  local api = C_AddOns and C_AddOns.SaveAddOnsData
  if type(api) == "function" then
    local ok = pcall(api)
    if ok then
      if not quiet then ns.Print("Saved.") end
      return true
    end
  end
  if not quiet then
    ns.Print("This client has no runtime save call. WoW only writes SavedVariables on exit or /reload, so run /reload to force a write.")
  end
  return false
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------

ns.inCombat = false

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_REGEN_ENABLED")
boot:RegisterEvent("PLAYER_REGEN_DISABLED")
boot:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    ns.InitDB()
    if ns.Settings then ns.Settings.Register() end
  elseif event == "PLAYER_LOGIN" then
    ns.selfName = ns.ShortName((UnitName("player")))
    -- Older builds left this switch permanently off, which silently stopped the
    -- player's own /who window from ever populating. Put it back to normal;
    -- scans suppress it only for the duration of their own query.
    if C_FriendList and type(C_FriendList.SetWhoToUi) == "function" then
      pcall(C_FriendList.SetWhoToUi, true)
    end
    if ns.UI then ns.UI.OnLogin() end
    ns.Print("Loaded. Type /beg")
  elseif event == "PLAYER_REGEN_DISABLED" then
    ns.inCombat = true
    if ns.RefreshUI then ns.RefreshUI() end
  elseif event == "PLAYER_REGEN_ENABLED" then
    ns.inCombat = false
    if ns.RefreshUI then ns.RefreshUI() end
  end
end)
