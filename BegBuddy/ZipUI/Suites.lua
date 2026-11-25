-- Every Zip addon registers itself here, and the settings home lists it with its own pages.
-- Z.Register{ key, title, addon, icon, notes, cmd, open, window, pages, profile, db } (see ZipUI/README.md).
if ZipUI.skip then return end
local Z = ZipUI
local L = Z.L
local S = {}
Z.Suites = S

-- Other addons the settings home knows about without a registration. slash: the SlashCmdList key the addon
-- registers (calling it with no text opens its window). retired: a Zip addon that another one replaced.
S.KNOWN = {
  { key = "recruitflow", title = "RecruitFlow", addon = "RecruitFlow", slash = "RECRUITFLOW", cmd = "/rf", icon = "Interface/Icons/INV_Letter_15" },
  { key = "ziploot", title = "ZipLoot", addon = "ZipLoot", slash = "ZIPLOOT", cmd = "/zl", retired = "ZipKit > Loot", icon = "Interface/Icons/INV_Misc_Bag_08" },
  { key = "zipquest", title = "ZipQuest", addon = "ZipQuest", slash = "ZIPQUEST", cmd = "/zq", retired = "ZipKit > Quest", icon = "Interface/Icons/INV_Misc_Note_01" },
}

function Z.Register(def)
  assert(def.key and def.title, "ZipUI.Register needs a key and a title")
  local old = Z.suites[def.key]
  if old then for k, v in pairs(old) do if def[k] == nil then def[k] = v end end end -- a second call adds to the first
  Z.suites[def.key] = def
  if Z.Hub and Z.Hub.Rebuild then Z.Hub.Rebuild() end
  return def
end

-- The old ZipKit name for the same thing, so addons written against ZipKit's hub keep working.
ZipKitHub = ZipKitHub or {}
ZipKitHub.Register = function(def) return Z.Register(def) end

-- The C_AddOns calls (the only ones on Forever; Era has both) are looked up on each call and wrapped in pcall,
-- since a name the client does not know may raise an error instead of returning nil.
local function meta(addon, field)
  local get = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
  if not (addon and get) then return nil end
  local ok, value = pcall(get, addon, field)
  return ok and value or nil
end
S.Meta = meta

function S.Loaded(name)
  if not name then return false end
  local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
  if not loaded then return false end
  local ok, yes = pcall(loaded, name)
  return ok and yes and true or false
end

-- GetAddOnInfo gives name, title, notes, loadable, reason: a missing addon gives nil, or a name with reason "MISSING".
local function installed(addon)
  local info = C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo
  if not info then return false end
  local ok, name, _, _, _, reason = pcall(info, addon)
  if not ok then return false end
  if type(name) == "table" then name, reason = name.name, name.reason end -- newer clients may return one table
  return name ~= nil and reason ~= "MISSING"
end

-- "active" (running), "off" (installed but not running) or "missing".
function S.State(s)
  if Z.suites[s.key] == s or not s.addon or S.Loaded(s.addon) then return "active" end
  return installed(s.addon) and "off" or "missing"
end

S.LABEL = { active = L["running"], off = L["installed, not running (enable it at the character screen)"], missing = L["not installed"] }

-- The registered addons, by their order field then title.
function S.Registered()
  local out = {}
  for _, def in pairs(Z.suites) do out[#out + 1] = def end
  table.sort(out, function(a, b)
    if (a.order or 50) ~= (b.order or 50) then return (a.order or 50) < (b.order or 50) end
    return a.title < b.title
  end)
  return out
end

-- Known addons that did not register themselves and are running.
function S.Others()
  local out = {}
  for _, k in ipairs(S.KNOWN) do
    if not Z.suites[k.key] and S.State(k) == "active" then out[#out + 1] = k end
  end
  return out
end

function S.Notes(s) return s.notes or meta(s.addon, "Notes") or "" end
function S.Version(s) return s.version or meta(s.addon, "Version") end

-- What opens a suite's own window: its open function, or its slash command with no text.
function S.Opener(s)
  if s.open then return s.open end
  local fn = s.slash and SlashCmdList and SlashCmdList[s.slash]
  if fn then return function() fn("") end end
end

-- One line per suite, for "/<cmd> list" and the overview page.
function S.Describe()
  local lines = {}
  for _, s in ipairs(S.Registered()) do
    local v = S.Version(s)
    lines[#lines + 1] = ("%s%s: %s%s"):format(s.title, v and (" " .. v) or "", L["running"], s.cmd and (" (" .. s.cmd .. ")") or "")
  end
  for _, k in ipairs(S.KNOWN) do
    if not Z.suites[k.key] then
      lines[#lines + 1] = ("%s: %s%s"):format(k.title, S.LABEL[S.State(k)], k.cmd and (" (" .. k.cmd .. ")") or "")
    end
  end
  return lines
end
