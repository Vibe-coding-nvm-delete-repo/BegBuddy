-- WoW client stub for BegBuddy. Frames keep their shown state, text, scale, scripts and checked state;
-- any other CamelCase call returns the frame, so UI code runs end to end. Each spec calls Reset().

PRINTS = {}
print = function(...)
  local t = {}
  for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
  PRINTS[#PRINTS + 1] = table.concat(t, " ")
end
unpack = unpack or table.unpack
time = os.time

FRAMES = {}
local function newFrame(name)
  local f = { events = {}, scripts = {}, hooks = {}, shown = true, name = name, alpha = 1, scale = 1, text = "" }
  function f:RegisterEvent(e) self.events[e] = true end
  function f:SetScript(k, fn) self.scripts[k] = fn end
  function f:GetScript(k) return self.scripts[k] end
  function f:HookScript(k, fn) self.hooks[k] = fn end
  function f:Show() self.shown = true end
  function f:Hide() self.shown = false end
  function f:SetShown(v) self.shown = v and true or false end
  function f:IsShown() return self.shown end
  function f:IsVisible() return self.shown end
  function f:SetText(t)
    self.text = t
    if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end
  end
  function f:GetText() return self.text end
  function f:SetAlpha(a) self.alpha = a end
  function f:SetScale(s) self.scale = s end
  function f:EnableMouse(v) self.mouse = v end
  function f:EnableMouseWheel(v) self.wheel = v end
  function f:SetPoint(...) self.point = { ... } end
  function f:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
  function f:SetHeight(h) self.h = h end
  function f:SetWidth(w) self.w = w end
  function f:SetSize(w, h) self.w, self.h = w, h end
  function f:GetEffectiveScale() return 1 end
  function f:SetValue(v) self.value = v end
  function f:GetValue() return self.value end
  function f:GetName() return self.name end
  function f:GetHeight() return self.h or 22 end
  function f:GetWidth() return self.w or 600 end
  function f:GetScale() return self.scale end
  function f:GetStringHeight() return 20 end
  function f:GetStringWidth() return #tostring(self.text or "") * 6 end
  function f:GetChecked() return self.checked end
  function f:SetChecked(v) self.checked = v end
  function f:IsEnabled() return not self.disabled end
  function f:Enable() self.disabled = false end
  function f:Disable() self.disabled = true end
  function f:GetVerticalScrollRange() return 0 end
  function f:GetVerticalScroll() return 0 end
  function f:CreateTexture() return newFrame() end
  function f:CreateFontString() return newFrame() end
  setmetatable(f, { __index = function(_, k)
    if type(k) == "string" and k:match("^%u") then return function(self2) return self2 end end
  end })
  FRAMES[#FRAMES + 1] = f
  return f
end
function CreateFrame(_, name) local f = newFrame(name); if name then _G[name] = f end; return f end

-- What ZipUI needs from the client
PlaySound, SOUNDKIT = function() end, { IG_CHARACTER_INFO_TAB = 841, IG_CHARACTER_INFO_OPEN = 839, IG_CHARACTER_INFO_CLOSE = 840 }
function IsAddOnLoaded() return true end
function GetAddOnInfo(name) return name end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
Settings = {
  RegisterCanvasLayoutCategory = function() return { GetID = function() return 7 end } end,
  RegisterAddOnCategory = function() end,
  OpenToCategory = function(id) OPENED = id end,
}

-- Client API BegBuddy reads
function GetTime() return NOW end
function UnitName() return "Zip" end
function GetRealmName() return "Realm" end
function GetMaxPlayerLevel() return 60 end
function GetNormalizedRealmName() return "Realm" end
function StaticPopup_Show() end
C_Timer = { After = function() end }
C_FriendList = { SetWhoToUi = function() end, SendWho = function(q) SENT_WHO = q end }

-- Forever hides some values from addons. HIDDEN stands for a hidden string: issecretvalue flags it once EnableSecrets()
-- has run (Classic Era has no such global). It cannot raise on use as the real one does, so specs check what the
-- addon did with it: a hidden value must change nothing.
HIDDEN = "Zzhidden"
function EnableSecrets() issecretvalue = function(v) return type(v) == "string" and v:find("^Zzhid") ~= nil end end -- any "Zzhid..." name is hidden
function DisableSecrets() issecretvalue = nil end

function Fire(event, ...)
  for _, f in ipairs(FRAMES) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end

-- A fresh client with the addon loaded the way the game does it. savedVars becomes BegDB (nil = a new account).
function Reset(savedVars)
  FRAMES, PRINTS = {}, {}
  NOW, SENT_WHO = 1000, nil
  UIParent, GameTooltip = newFrame(), newFrame()
  SlashCmdList, UISpecialFrames, StaticPopupDialogs = {}, {}, {}
  ZipUI, ZipKitHub, ZipUIOptions, OPENED = nil, nil, nil, nil -- a fresh ZipUI too, or its copy would skip itself
  BegBuddyFrame, BegBuddyPopout, BegBuddyCopy = nil, nil, nil
  BegDB = savedVars
  NS = {}
  for name in TOC_FILES:gmatch("[^,]+") do
    assert(load(_G["SRC_" .. name], name .. ".lua"))("BegBuddy", NS)
  end
  Fire("ADDON_LOADED", "BegBuddy")
  Fire("PLAYER_LOGIN")
end

-- Show the Zip settings home, as Esc > Options > AddOns > Zip does (its controls are built on first show).
function OpenSettings()
  ZipUI.Hub.Build()
  ZipUIOptions.scripts.OnShow(ZipUIOptions)
end

-- Build one of BegBuddy's settings pages the way the Zip settings home does. Returns the page frame.
function BuildPage(key)
  local page = CreateFrame("Frame")
  ZipUI.Hub.byKey["begbuddy/" .. key].Build(page)
  return page
end

local fails = 0
function check(name, cond)
  io.write((cond and "  PASS " or "  FAIL ") .. name .. "\n")
  if not cond then fails = fails + 1; FAILED = fails end
end

Reset()
