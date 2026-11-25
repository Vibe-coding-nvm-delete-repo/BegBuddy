-- Profiles: named copies of an addon's settings, saved account-wide so any character can load them.
-- An addon opts in with def.profile = { keys = { "settings" }, defaults = function() return { settings = ... } end,
-- after = function() end } where keys are the parts of its saved table that hold settings (not data).
-- keep: dotted paths of learned data or the player's own lists. Load and Reset never change them, and a shared
-- code never carries them. private: dotted paths of settings a shared code never carries (spending limits).
-- Loading a setup that has no value there leaves the player's own value alone.
if ZipUI.skip then return end
local Z = ZipUI
local R = {}
Z.Profiles = R

local function store(def)
  local db = def.db and def.db()
  if type(db) ~= "table" then return nil end
  db.zipui = db.zipui or {}
  db.zipui.profiles = db.zipui.profiles or {}
  return db.zipui.profiles, db
end

local function keys(def)
  local k = def.profile.keys
  return type(k) == "function" and k() or k
end

local function defaultsOf(def)
  local d = def.profile.defaults and def.profile.defaults()
  return type(d) == "table" and d or {}
end

-- profile.keep or profile.private, as a list.
local function paths(def, field)
  local list = def.profile[field]
  return type(list) == "table" and list or {}
end

-- The table that holds a dotted path's last part, and that part: at(db, "modules.vendor.never").
local function at(db, path)
  local t, last = db, nil
  for part in path:gmatch("[^.]+") do
    if last then t = type(t) == "table" and t[last] or nil end
    last = part
  end
  return type(t) == "table" and t or nil, last
end

local function valueAt(db, path)
  local t, k = at(db, path)
  if t then return t[k] end
end

-- A copy of v without the values whose type differs from the default at the same place (nil when v itself is
-- the wrong type), so a hand-made code cannot put text where a number belongs. A default list is one value:
-- only its type is checked. Where there is no default (a free list such as never-sell items), any plain value stays.
local PLAIN = { boolean = true, number = true, string = true, table = true }
local function fit(v, default)
  if not PLAIN[type(v)] then return nil end
  if type(v) == "number" and (v ~= v or v == math.huge or v == -math.huge) then return nil end
  if default == nil then return Z.Copy(v) end
  if type(v) ~= type(default) then return nil end
  if type(v) ~= "table" or default[1] ~= nil then return Z.Copy(v) end
  local out = {}
  for k, x in pairs(v) do
    if type(k) == "string" or type(k) == "number" then out[k] = fit(x, default[k]) end
  end
  return out
end
R.Fit = fit

-- Take the keep and private paths out of a setup, so a shared code never carries the player's own lists,
-- learned data or spending limits.
function R.Strip(def, snap)
  for _, field in ipairs({ "keep", "private" }) do
    for _, path in ipairs(paths(def, field)) do
      local t, k = at(snap, path)
      if t then t[k] = nil end
    end
  end
  return snap
end

local function forget(db, name)
  if db and db.zipui and db.zipui.imported then db.zipui.imported[name] = nil end
end

function R.List(def)
  local out = {}
  for name in pairs(store(def) or {}) do out[#out + 1] = name end
  table.sort(out)
  return out
end

-- A copy of the settings parts of the addon's saved table (nil when the addon keeps no setups).
function R.Snapshot(def)
  local profiles, db = store(def)
  if not profiles or not def.profile then return nil end
  local snap = {}
  for _, k in ipairs(keys(def)) do snap[k] = Z.Copy(db[k]) end
  return snap
end

function R.Save(def, name)
  local profiles, db = store(def)
  if not profiles then return false end
  profiles[name] = R.Snapshot(def)
  forget(db, name)
  return true
end

-- Store a setup that came from outside (a shared code). It keeps only the parts this addon uses, each value only
-- when its type matches the addon's default, and never the keep or private paths. False when none of its parts
-- are in it. The setup is marked as shared, so the Load button asks once more.
function R.Put(def, name, src)
  local profiles, db = store(def)
  if not profiles or type(src) ~= "table" then return false end
  local defaults = defaultsOf(def)
  local snap, any = {}, false
  for _, k in ipairs(keys(def)) do
    local v = fit(src[k], defaults[k])
    if v ~= nil then snap[k], any = v, true end
  end
  if not any then return false end
  profiles[name] = R.Strip(def, snap)
  db.zipui.imported = db.zipui.imported or {}
  db.zipui.imported[name] = true
  return true
end

-- True when a saved setup came from a shared code.
function R.Imported(def, name)
  local _, db = store(def)
  return (db and db.zipui.imported and db.zipui.imported[name]) == true
end

-- Put src into db[k], keeping the table db[k] already is (code may hold it), then add any newer defaults.
local function apply(db, k, src, defaults)
  if type(db[k]) == "table" and type(src) == "table" then Z.Replace(db[k], src) else db[k] = Z.Copy(src) end
  if type(db[k]) == "table" and type(defaults[k]) == "table" then Z.Fill(db[k], defaults[k]) end
end

-- What Load and Reset put back afterwards: every keep path, and every private path the incoming settings
-- (src) have no value for.
local function stash(def, db, src)
  local kept = {}
  for _, path in ipairs(paths(def, "keep")) do kept[#kept + 1] = { path, Z.Copy(valueAt(db, path)) } end
  for _, path in ipairs(paths(def, "private")) do
    if valueAt(src, path) == nil then kept[#kept + 1] = { path, Z.Copy(valueAt(db, path)) } end
  end
  return kept
end

local function finish(def, db, kept)
  for _, entry in ipairs(kept) do
    local t, k = at(db, entry[1])
    local v = entry[2]
    if t and v ~= nil then
      if type(t[k]) == "table" and type(v) == "table" then Z.Replace(t[k], v) else t[k] = v end
    end
  end
  if def.profile.after then def.profile.after() end
end

function R.Load(def, name)
  local profiles, db = store(def)
  local snap = profiles and profiles[name]
  if not snap then return false end
  local defaults = defaultsOf(def)
  -- Values of the wrong type (from an older or hand-made code) are left out, so the default takes their place.
  local src = {}
  for _, k in ipairs(keys(def)) do src[k] = fit(snap[k], defaults[k]) end
  local kept = stash(def, db, src)
  for _, k in ipairs(keys(def)) do
    if src[k] ~= nil then apply(db, k, src[k], defaults) end
  end
  finish(def, db, kept)
  return true
end

function R.Delete(def, name)
  local profiles, db = store(def)
  if not (profiles and profiles[name]) then return false end
  profiles[name] = nil
  forget(db, name)
  return true
end

-- Every setting back to what the addon ships with. Data (the keep paths) is left alone.
function R.Reset(def)
  local _, db = store(def)
  if not db then return false end
  local defaults = defaultsOf(def)
  local kept = stash(def, db, defaults)
  for _, k in ipairs(keys(def)) do
    if defaults[k] ~= nil then apply(db, k, defaults[k], defaults) end
  end
  finish(def, db, kept)
  return true
end
