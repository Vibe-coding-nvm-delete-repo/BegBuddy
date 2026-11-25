-- BegBuddy / Classes.lua
-- Class names, tokens and colours.

local _, ns = ...

----------------------------------------------------------------------
-- Class identity
----------------------------------------------------------------------

local CLASS_TOKENS = {
  WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true,
  DEATHKNIGHT = true, SHAMAN = true, MAGE = true, WARLOCK = true, MONK = true,
  DRUID = true, DEMONHUNTER = true, EVOKER = true,
}

local classByLocalized

local function BuildClassLookup()
  classByLocalized = {}
  local sources = { LOCALIZED_CLASS_NAMES_MALE, LOCALIZED_CLASS_NAMES_FEMALE }
  for _, src in ipairs(sources) do
    if type(src) == "table" then
      for token, localized in pairs(src) do
        if type(localized) == "string" then classByLocalized[localized] = token end
      end
    end
  end
end

-- Accepts any mix of class token, localized class name, or classID, and returns
-- the uppercase token that RAID_CLASS_COLORS and C_ClassColor both key on.
function ns.ClassToken(...)
  if classByLocalized == nil then BuildClassLookup() end
  local n = select("#", ...)

  for i = 1, n do
    local v = select(i, ...)
    if type(v) == "string" and v ~= "" then
      local up = v:upper()
      if CLASS_TOKENS[up] then return up end
    end
  end

  for i = 1, n do
    local v = select(i, ...)
    if type(v) == "string" and classByLocalized[v] then return classByLocalized[v] end
  end

  if type(_G.GetClassInfo) == "function" then
    for i = 1, n do
      local v = select(i, ...)
      if type(v) == "number" then
        local ok, _, file = pcall(_G.GetClassInfo, v)
        if ok and type(file) == "string" and CLASS_TOKENS[file:upper()] then
          return file:upper()
        end
      end
    end
  end

  return nil
end

-- r, g, b for a class token, or a neutral grey when it cannot be resolved.
local function ClientClassColor(token)
  if C_ClassColor and type(C_ClassColor.GetClassColor) == "function" then
    local ok, col = pcall(C_ClassColor.GetClassColor, token)
    if ok and type(col) == "table" then
      if col.r and col.g and col.b then return col.r, col.g, col.b end
      if type(col.GetRGB) == "function" then return col:GetRGB() end
    end
  end
end

local function RaidClassColor(token)
  local t = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
  if type(t) == "table" then
    return t.r or t.colorR or 0.8, t.g or t.colorG or 0.8, t.b or t.colorB or 0.8
  end
end

function ns.ClassColor(token)
  if token then
    local r, g, b = ClientClassColor(token)
    if r then return r, g, b end
    r, g, b = RaidClassColor(token)
    if r then return r, g, b end
  end
  return 0.80, 0.80, 0.80
end

local function Hex(r, g, b)
  local function clamp(v)
    v = math.floor((tonumber(v) or 1) * 255 + 0.5)
    if v < 0 then return 0 end
    if v > 255 then return 255 end
    return v
  end
  return string.format("|cff%02x%02x%02x", clamp(r), clamp(g), clamp(b))
end

-- Cached: the contact list asks for this once per visible row on every redraw,
-- and resolving a class colour means a pcall into C_ClassColor.
local classHexCache = {}

function ns.ClassHex(token)
  if not token then return "|cffcccccc" end
  local cached = classHexCache[token]
  if cached then return cached end
  local hex = Hex(ns.ClassColor(token))
  classHexCache[token] = hex
  return hex
end

-- Colour escape for a contact. Prefers the stored token, but falls back to the
-- stored localized class name so contacts scanned before this was added still
-- colour in without needing a rescan.
function ns.ClassHexFor(contact)
  if not contact then return "|cffcccccc" end
  return ns.ClassHex(contact.classToken or ns.ClassToken(contact.class))
end

----------------------------------------------------------------------
-- Scan class picks (tick as many as you like)
----------------------------------------------------------------------

-- The classes this player's /who can find, with the token that colours them.
function ns.WhoClasses()
  local out = {}
  for _, name in ipairs(ns.WhoClassNames()) do
    out[#out + 1] = { name = name, token = ns.ClassToken(name) or name:upper() }
  end
  return out
end

-- The picks are stored as { [CLASS_TOKEN] = true }. ScanClasses turns them into
-- the names /who matches on and is called on every scan lookup, so the answer
-- is built once and kept until a pick changes or the settings table is replaced.
local cache = { ver = 0, built = -1 }

local function PickTable()
  local s = BegDB and BegDB.settings
  local sel = s and s.scanClasses
  if type(sel) == "table" and next(sel) ~= nil then return sel end
end

-- Picked class names in class order, or nil for every class.
function ns.ScanClasses()
  local sel = PickTable()
  if not sel then return nil end
  if cache.sel ~= sel or cache.built ~= cache.ver then
    local list, tokens = {}, {}
    for _, c in ipairs(ns.WhoClasses()) do
      if sel[c.token] then list[#list + 1] = c.name; tokens[#tokens + 1] = c.token end
    end
    cache.sel, cache.built = sel, cache.ver
    cache.list = #list > 0 and list or nil
    cache.key = #list > 0 and table.concat(tokens, ",") or nil
  end
  return cache.list
end

-- Part of the scan plan's key: each set of classes has its own progress.
function ns.ScanClassKey()
  ns.ScanClasses()
  return PickTable() and cache.key or nil
end

function ns.IsScanClass(token)
  local sel = PickTable()
  return sel ~= nil and sel[token] == true
end

local function Changed()
  cache.ver = cache.ver + 1
  if ns.ClearSplits then ns.ClearSplits() end
  if ns.RefreshUI then ns.RefreshUI() end
end

function ns.ToggleScanClass(token, on)
  local s = BegDB.settings
  if type(s.scanClasses) ~= "table" then s.scanClasses = {} end
  if on == nil then on = not s.scanClasses[token] end
  s.scanClasses[token] = on and true or nil
  Changed()
end

function ns.ClearScanClasses()
  BegDB.settings.scanClasses = nil
  Changed()
end
