-- The health log: every Lua error and every call the game refuses that comes from a Zip addon, written down so a
-- break can be traced later. The game hides script errors by default and its "blocked" popup never names the call,
-- so without this a break leaves nothing behind. Rows live under .zipui.health in the saved table of the addon they
-- belong to (or of any registered Zip addon, when that one has none), so they can be read after logout from
-- WTF/Account/<account>/SavedVariables/<Addon>.lua. "<cmd> health" lists them in the game; "<cmd> health clear" empties them.
--
-- Errors: the game's handler list (Blizzard_ScriptErrors) takes secure callers only, so the handler itself is wrapped,
-- once per client, as error-catcher addons do. The wrapper records and then always calls the handler that was there
-- before; a failure inside the log is swallowed. Only problems from Zip addon folders are kept. If the game ever
-- refuses the wrap, that is saved and it is never tried again; refused calls are still recorded.
if ZipUI.skip then return end
local Z = ZipUI
local L = Z.L
local H = {}
Z.Health = H

-- Zip addon folders, registered with ZipUI or not (ZipNote has no ZipUI copy). Registered addons are added to these.
H.ADDONS = { "ZipKit", "ZipBar", "ZipNote", "BagSnap", "BegBuddy", "GroupBoard", "!ZipAddons" }
local KEEP, SESSION, TEXT, STACK = 30, 60, 300, 800 -- saved rows per addon, distinct problems a session, characters

-- This session's problems. Kept on ZipUI so a newer copy loading later carries on with the same list and hook.
Z.health = Z.health or { rows = {}, byKey = {}, said = {} }
local state = Z.health
local rememberRefusal -- set further down: saves that the game refused the handler wrap

local function zipAddons()
  local set = {}
  for _, name in ipairs(H.ADDONS) do set[name] = true end
  for _, def in pairs(Z.suites) do
    if def.addon then set[def.addon] = true end
  end
  return set
end

-- The first addon folder a message or stack names.
local function folder(text)
  return type(text) == "string" and text:match("[Aa]dd[Oo]ns[/\\]([^/\\]+)[/\\]") or nil
end

-- The Zip addon a problem belongs to, or nil: by the file in the message, else by the top of the stack.
function H.Owner(text, stack)
  local name = folder(text) or folder(stack)
  return name and zipAddons()[name] and name or nil
end

-- Registered addons that have a saved table now, in a fixed order: { { def, zipui table } ... }.
local function tables()
  local keys, out = {}, {}
  for key in pairs(Z.suites) do keys[#keys + 1] = key end
  table.sort(keys)
  for _, key in ipairs(keys) do
    local def = Z.suites[key]
    local ok, db = pcall(function() return def.db and def.db() end)
    if ok and type(db) == "table" then
      db.zipui = db.zipui or {}
      out[#out + 1] = { def = def, t = db.zipui }
    end
  end
  return out
end

-- Where an addon's rows are saved: its own table, else the first one there is.
local function tableFor(addon)
  local all = tables()
  for _, e in ipairs(all) do
    if e.def.addon == addon then return e.t end
  end
  return all[1] and all[1].t
end

local function savedRow(list, row)
  for _, e in ipairs(list) do
    if e.kind == row.kind and e.addon == row.addon and e.text == row.text then return e end
  end
  local e = { kind = row.kind, addon = row.addon, text = row.text, count = 0 }
  list[#list + 1] = e
  while #list > KEEP do table.remove(list, 1) end
  return e
end

-- Adds n sightings of a problem to the saved log. With no saved table yet (still loading), they wait in row.unsaved.
local function save(row, n)
  local t = tableFor(row.addon)
  if not t then
    row.unsaved = (row.unsaved or 0) + n
    return
  end
  t.health = t.health or {}
  local e = savedRow(t.health, row)
  e.count = e.count + n
  e.stack, e.at, e.build, e.version, e.combat = row.stack, row.at, row.build, row.version, row.combat
end

-- Saves what was met before any saved table existed. Run at login and logout.
function H.Flush()
  for _, row in ipairs(state.rows) do
    local n = row.unsaved
    if n then
      row.unsaved = nil
      save(row, n)
    end
  end
end

local function clip(text, max)
  text = type(text) == "string" and text or ""
  return #text > max and text:sub(1, max) or text
end

local function build()
  if not GetBuildInfo then return "" end
  local version, number = GetBuildInfo()
  return tostring(version) .. "." .. tostring(number)
end

-- The slash command to name in chat: the addon's own, else any Zip addon's.
local function command(addon)
  local any
  for _, e in ipairs(tables()) do
    if e.def.cmd and e.def.addon == addon then return e.def.cmd end
    any = any or e.def.cmd
  end
  return any
end

-- One chat line per addon a session; the rest is in the log.
local function tell(addon)
  if state.said[addon] then return end
  state.said[addon] = true
  local cmd = command(addon)
  if not cmd then return end
  Z.Printer("Zip")((L["%s ran into a problem and saved it. Type %s health to see it."]):format(addon, cmd))
end

-- kind: "error", "forbidden" (a call only Blizzard may make) or "blocked" (a call refused in combat).
function H.Record(kind, addon, text, stack)
  text = clip(text, TEXT)
  local key = kind .. "\n" .. addon .. "\n" .. text
  local row = state.byKey[key]
  if not row then
    if #state.rows >= SESSION then return end -- a runaway error must not grow the log without end
    row = { kind = kind, addon = addon, text = text }
    state.rows[#state.rows + 1], state.byKey[key] = row, row
  end
  row.stack, row.build = clip(stack, STACK), build()
  row.at = date and date("%Y-%m-%d %H:%M") or ""
  row.version = Z.Suites and Z.Suites.Meta(addon, "Version") or nil
  row.combat = InCombatLockdown and InCombatLockdown() and true or false
  save(row, 1)
  tell(addon)
end

local function hidden(v) return issecretvalue and issecretvalue(v) or false end

-- A Lua error, as the game's handler gets it. A message the game hides is placed by its stack and not read.
function H.Error(msg)
  local text = nil
  if not hidden(msg) then text = type(msg) == "string" and msg or tostring(msg) end
  local stack = debugstack and debugstack(3, 20, 0) or ""
  if hidden(stack) then stack = "" end
  local addon = H.Owner(text, stack)
  if addon then H.Record("error", addon, text or L["(message hidden by the game)"], stack) end
end

-- A refused call: the events give the addon's name and the call. They fire inside the call, so the stack still
-- holds the line that made it.
function H.Refused(kind, addon, call)
  if type(addon) ~= "string" or hidden(addon) or not zipAddons()[addon] then return end
  local stack = debugstack and debugstack(3, 12, 0) or ""
  local text = hidden(call) and L["(call hidden by the game)"] or tostring(call)
  if text:find("seterrorhandler", 1, true) then rememberRefusal() end
  H.Record(kind, addon, text, hidden(stack) and "" or stack)
end

-- Every saved row, oldest first, with the addon whose table holds it left out: the row names its own addon.
function H.Rows()
  local out = {}
  for _, e in ipairs(tables()) do
    for _, row in ipairs(e.t.health or {}) do out[#out + 1] = row end
  end
  for _, row in ipairs(state.rows) do
    if row.unsaved then out[#out + 1] = { kind = row.kind, addon = row.addon, text = row.text, count = row.unsaved,
      stack = row.stack, at = row.at, build = row.build, version = row.version, combat = row.combat } end
  end
  table.sort(out, function(a, b) return (a.at or "") < (b.at or "") end)
  return out
end

local KIND = { error = L["error"], forbidden = L["forbidden call"], blocked = L["call blocked in a fight"] }

local function rowLines(row, lines)
  lines[#lines + 1] = ("%s%s, %s x%d, %s, %s %s%s: %s"):format(row.addon, row.version and (" " .. row.version) or "",
    KIND[row.kind] or row.kind, row.count or 1, row.at or "", L["game"], row.build or "",
    row.combat and (", " .. L["in a fight"]) or "", row.text)
  local at = (row.stack or ""):match("[^\n]*[Aa]dd[Oo]ns[^\n]*")
  if at and not row.text:find(at, 1, true) then lines[#lines + 1] = "  " .. at end
end

-- The log as chat lines.
function H.Lines()
  local rows = H.Rows()
  if #rows == 0 then return { L["No problems saved. Zip addons have run clean."] } end
  local lines = { (L["%d problem(s) saved, oldest first:"]):format(#rows) }
  for _, row in ipairs(rows) do rowLines(row, lines) end
  return lines
end

function H.Clear()
  for _, e in ipairs(tables()) do e.t.health = nil end
  state.rows, state.byKey = {}, {}
end

-- Saved tables of the Zip addons that carry ZipUI, by their global names. Read raw, since the wrap is decided when
-- the first Zip addon has loaded, before any of them has registered.
H.SAVED = { "ZipAddonsDB", "BagSnapDB", "BegDB", "GroupBoardDB", "ZipBarDB", "ZipKitDB" }

-- True when an earlier session saw the game refuse the wrap. That it is allowed on every client is not proven in
-- game, and a refused call is what shows Blizzard's "blocked" popup: so one refusal is remembered and never retried.
local function wrapRefused()
  if state.noHook then return true end
  for _, name in ipairs(H.SAVED) do
    local db = _G[name]
    local ui = type(db) == "table" and db.zipui
    local prefs = type(ui) == "table" and ui.prefs
    if type(prefs) == "table" and prefs.noErrorHook then return true end
  end
  return false
end

function rememberRefusal()
  state.noHook = true
  pcall(Z.SetPref, "noErrorHook", true)
end

-- The handler is wrapped once per client, by whichever copy loads first; it looks ZipUI.Health up on each error, so a
-- newer copy's code runs without a second wrap. It waits for the first Zip addon to finish loading, when saved data
-- can say whether the game refused the wrap before.
local function hook()
  if state.hooked or wrapRefused() or not (seterrorhandler and geterrorhandler) then return end
  local before, busy = geterrorhandler(), false
  local function onError(msg, ...)
    if not busy then
      busy = true
      local health = ZipUI and ZipUI.Health
      if health then pcall(health.Error, msg) end
      busy = false
    end
    if before then return before(msg, ...) end
  end
  state.hooked = pcall(seterrorhandler, onError)
end

Z.On("ADDON_LOADED", function(name)
  if type(name) == "string" and zipAddons()[name] then pcall(hook) end
end)
Z.On("ADDON_ACTION_FORBIDDEN", function(addon, call) pcall(H.Refused, "forbidden", addon, call) end)
Z.On("ADDON_ACTION_BLOCKED", function(addon, call) pcall(H.Refused, "blocked", addon, call) end)
Z.On("PLAYER_LOGIN", function()
  pcall(H.Flush)
  if state.noHook then rememberRefusal() end -- saved tables exist now
end)
Z.On("PLAYER_LOGOUT", function() pcall(H.Flush) end)
