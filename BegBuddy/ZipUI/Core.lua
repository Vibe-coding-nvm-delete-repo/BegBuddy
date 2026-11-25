-- ZipUI: the look, settings home, commands, minimap button and profiles every Zip addon shares.
-- Each addon carries a copy in its own ZipUI folder (synced from the repo's ZipUI folder by tools/sync-zipui.mjs).
-- The newest copy that loads wins: an older or equal copy loading later skips its files, so one ZipUI runs.

local REV = 4
if ZipUI and (ZipUI.REV or 0) >= REV then ZipUI.skip = true return end
ZipUI = ZipUI or {} -- an older copy's table is kept, so addons that registered with it stay registered
local Z = ZipUI
Z.REV, Z.skip = REV, false
Z.suites = Z.suites or {}

-- Gold on dark, like the game's own frames.
Z.GOLD, Z.DIM, Z.WHITE = { 1, 0.82, 0 }, { 0.62, 0.55, 0.42 }, { 1, 1, 1 }
-- The client's own text font: Friz Quadrata has no Cyrillic, Korean or Chinese letters, so those clients use another.
Z.Font = STANDARD_TEXT_FONT or "Fonts/FRIZQT__.TTF"
Z.Colors = {
  bg = { 0.05, 0.045, 0.035, 0.96 },
  panel = { 0.09, 0.075, 0.05, 0.95 },
  border = { 0.6, 0.5, 0.3, 1 },
  text = { 0.92, 0.9, 0.85, 1 },
  dim = { 0.62, 0.55, 0.42, 1 },
  accent = { 1, 0.82, 0, 1 },
  active = { 0.32, 0.22, 0.06, 0.95 },
  good = { 0.3, 0.85, 0.4, 1 },
  bad = { 0.95, 0.3, 0.3, 1 },
  warn = { 1, 0.6, 0.2, 1 },
  xp = { 0.58, 0.2, 0.85, 1 },
  rested = { 0.2, 0.45, 0.95, 1 },
  row = { 0.1, 0.085, 0.06, 0.8 },
  rowAlt = { 0.14, 0.115, 0.08, 0.8 },
  hover = { 1, 0.82, 0, 0.12 },
}

-- The game's own click sounds; quiet where the client lacks one.
function Z.Sound(name)
  local id = SOUNDKIT and SOUNDKIT[name]
  if id and PlaySound then PlaySound(id) end
end

-- A chat line prefixed with the addon's name in its colour: Z.Printer("ZipBar", "00ff00")("hello").
function Z.Printer(title, hex)
  return function(msg) print(("|cff%s%s|r %s"):format(hex or "ffd100", title, msg)) end
end

function Z.Copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = Z.Copy(x) end
  return out
end

-- Fill missing keys of dst from src, deeply. Keys dst already has are kept. A list (src has [1]) is one
-- value: dst gets the whole default list only when it has none, never default entries padded onto its own.
function Z.Fill(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = Z.Copy(v)
      elseif v[1] == nil then Z.Fill(dst[k], v) end
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
  return dst
end

-- Make dst hold exactly what src holds, keeping dst and every table inside it that src also has a table for,
-- so code (or a settings page) holding a reference to one sees the change.
function Z.Replace(dst, src)
  for k in pairs(dst) do if src[k] == nil then dst[k] = nil end end
  for k, v in pairs(src) do
    if type(v) == "table" and type(dst[k]) == "table" then Z.Replace(dst[k], v) else dst[k] = Z.Copy(v) end
  end
  return dst
end

-- Translations. L = Z.Locale("ZipBar"); L["Lock window"] gives the text in the player's language, or the
-- English text itself when there is no translation yet. Z.AddLocale("ZipBar", "deDE", { ["Lock window"] = "..." }).
Z.locale = (GetLocale and GetLocale()) or "enUS"
Z.strings = Z.strings or {}
local LOOKUP = { __index = function(_, k) return k end }
function Z.Locale(addon)
  Z.strings[addon] = Z.strings[addon] or setmetatable({}, LOOKUP)
  return Z.strings[addon]
end
function Z.AddLocale(addon, locale, map)
  if locale ~= Z.locale then return end
  local L = Z.Locale(addon)
  for k, v in pairs(map) do rawset(L, k, v) end
end
Z.L = Z.Locale("ZipUI")

-- Shared preferences (the minimap button, the last settings page) live under .zipui.prefs in the saved table
-- of every registered addon, so any one Zip addon is enough to keep them. Writes go to all; reads take the newest.
local function uiTables()
  local out = {}
  for _, def in pairs(Z.suites) do
    local db = def.db and def.db()
    if type(db) == "table" then
      db.zipui = db.zipui or {}
      db.zipui.prefs = db.zipui.prefs or {}
      out[#out + 1] = db.zipui
    end
  end
  return out
end

function Z.Prefs()
  local best
  for _, t in ipairs(uiTables()) do
    if not best or (t.prefs.stamp or 0) > (best.stamp or 0) then best = t.prefs end
  end
  return best or {}
end

function Z.SetPref(key, value)
  local prefs = Z.Copy(Z.Prefs())
  prefs[key] = value
  prefs.stamp = (prefs.stamp or 0) + 1
  for _, t in ipairs(uiTables()) do t.prefs = Z.Copy(prefs) end
end

-- One event frame for the whole library; a newer copy replaces the handler, not the frame.
Z.events = Z.events or CreateFrame("Frame")
Z.handlers = {}
function Z.On(event, fn)
  Z.handlers[event] = Z.handlers[event] or {}
  table.insert(Z.handlers[event], fn)
  Z.events:RegisterEvent(event)
end
Z.events:SetScript("OnEvent", function(_, event, ...)
  for _, fn in ipairs(Z.handlers[event] or {}) do fn(...) end
end)
