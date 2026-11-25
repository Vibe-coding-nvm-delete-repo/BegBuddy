-- The same slash words in every Zip addon: open, settings, lock, unlock, reset, scale, minimap, profile, list, help.
-- Z.Slash(def, "ZIPBAR", { "/zb", "/zipbar" }) registers them; def.commands adds the addon's own words:
-- def.commands = { history = { function(rest) ... end, "show the history" } }. An addon word wins over a shared one.
if ZipUI.skip then return end
local Z = ZipUI
local L = Z.L

local function windowOf(def)
  local w = def.window
  if type(w) == "function" then w = w() end
  return w
end

local SHARED = {}
local ORDER = { "open", "settings", "lock", "unlock", "reset", "scale", "minimap", "profile", "list", "health", "help" }
local HELP = {
  open = L["open the window"], settings = L["open the settings"], lock = L["lock the window"],
  unlock = L["unlock the window"], reset = L["put the window back in the middle"], scale = L["window size, 0.5 to 2"],
  minimap = L["show or hide the Zip minimap button"], profile = L["save, load, delete, list or reset setups"],
  list = L["every Zip addon and whether it runs"], help = L["this list"],
  health = L["errors and blocked calls saved from Zip addons (health clear empties the list)"],
}
local NEEDS_WINDOW = { lock = true, unlock = true, reset = true, scale = true }

function SHARED.open(def)
  local open = Z.Suites.Opener(def)
  if open then return open() end
  Z.Open(def.key)
end
function SHARED.settings(def) Z.Open(def.key) end
function SHARED.lock(def, _, say) windowOf(def):SetLocked(true); say(L["window locked"]) end
function SHARED.unlock(def, _, say) windowOf(def):SetLocked(false); say(L["window unlocked"]) end
function SHARED.reset(def, _, say) windowOf(def):ResetPosition(); say(L["window moved back to the middle"]) end
function SHARED.scale(def, rest, say)
  local n = tonumber(rest)
  if not n then return say(L["type a size from 0.5 to 2, like: scale 1.2"]) end
  say(L["window size"] .. " " .. windowOf(def):SetSavedScale(n))
end
function SHARED.minimap(_, _, say)
  Z.SetPref("minimapHide", not Z.Prefs().minimapHide)
  if Z.Launcher then Z.Launcher.Update() end
  say(Z.Prefs().minimapHide and L["Zip minimap button hidden"] or L["Zip minimap button shown"])
end
function SHARED.list(_, _, say) for _, line in ipairs(Z.Suites.Describe()) do say(line) end end
-- The health log (Health.lua): every saved error and refused call of every Zip addon, or "clear" to empty it.
function SHARED.health(_, rest, say)
  if (rest or ""):lower() == "clear" then
    Z.Health.Clear()
    return say(L["problem log emptied"])
  end
  for _, line in ipairs(Z.Health.Lines()) do say(line) end
end

local PROFILE = {}
function PROFILE.save(def, name, say) Z.Profiles.Save(def, name); say(L["saved setup"] .. " " .. name) end
function PROFILE.load(def, name, say)
  say(Z.Profiles.Load(def, name) and (L["loaded setup"] .. " " .. name) or (L["no setup named"] .. " " .. name))
end
function PROFILE.delete(def, name, say)
  say(Z.Profiles.Delete(def, name) and (L["deleted setup"] .. " " .. name) or (L["no setup named"] .. " " .. name))
end
function PROFILE.list(def, _, say)
  local names = Z.Profiles.List(def)
  say(#names > 0 and table.concat(names, ", ") or L["no saved setups yet"])
end
function PROFILE.reset(def, _, say) Z.Profiles.Reset(def); say(L["settings reset to defaults"]) end

function SHARED.profile(def, rest, say)
  if not def.profile then return say(L["this addon has no setups to save"]) end
  local verb, name = (rest or ""):match("^(%S*)%s*(.-)$")
  local fn = PROFILE[verb:lower()]
  if not fn or (name == "" and verb ~= "list" and verb ~= "reset") then
    return say(def.cmd .. " profile save|load|delete <name>, " .. def.cmd .. " profile list, " .. def.cmd .. " profile reset")
  end
  fn(def, name, say)
end

-- Which shared words this addon has: the window words only when it has a window.
local function sharedWords(def)
  local out = {}
  for _, w in ipairs(ORDER) do
    if (not NEEDS_WINDOW[w] or def.window) and (w ~= "profile" or def.profile) then out[#out + 1] = w end
  end
  return out
end

-- The help lines, also shown on the addon's About page.
local function helpLines(def)
  local lines = {}
  for _, w in ipairs(sharedWords(def)) do
    if not (def.commands and def.commands[w]) then lines[#lines + 1] = ("%s %s: %s"):format(def.cmd, w, HELP[w]) end
  end
  local own = {}
  for w in pairs(def.commands or {}) do own[#own + 1] = w end
  table.sort(own)
  for _, w in ipairs(own) do lines[#lines + 1] = ("%s %s: %s"):format(def.cmd, w, def.commands[w][2] or "") end
  return lines
end

function SHARED.help(def, _, say) for _, line in ipairs(def.help) do say(line) end end

local ALIAS = { show = "open", toggle = "open", options = "settings", config = "settings", size = "scale", profiles = "profile" }

function Z.Slash(def, id, names)
  def.cmd = def.cmd or names[1]
  def.help = helpLines(def)
  local say = def.print or Z.Printer(def.title)
  for i, n in ipairs(names) do _G["SLASH_" .. id .. i] = n end
  local allowed = {}
  for _, w in ipairs(sharedWords(def)) do allowed[w] = true end
  SlashCmdList[id] = function(msg)
    local word, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    word = word:lower()
    local own = def.commands and def.commands[word]
    if own then return own[1](rest) end
    word = ALIAS[word] or word
    if word == "" then word = "open" end
    if allowed[word] then return SHARED[word](def, rest, say) end
    -- A settings page: "/zk autotrain/weapons" opens zipkit/autotrain/weapons; "/zk zipbar" another addon's page.
    local page = (Z.Hub.Has(def.key .. "/" .. word) and def.key .. "/" .. word) or (Z.Hub.Has(word) and word)
    if page then return Z.Open(page) end
    say(L["unknown command"] .. " '" .. word .. "'. " .. def.cmd .. " help " .. L["lists them all"] .. ".")
  end
  return def
end
