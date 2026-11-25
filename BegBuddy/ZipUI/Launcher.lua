-- One minimap button for every Zip addon. Left click lists them (click one to open it), right click opens the
-- settings home, drag moves it around the map edge. Where it sits and whether it shows are shared preferences.
if ZipUI.skip then return end
local Z = ZipUI
local L = Z.L
local M = {}
Z.Launcher = M
local RADIUS = 80

local function place(b)
  local a = math.rad(Z.Prefs().minimapAngle or 200)
  b:ClearAllPoints()
  b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * RADIUS, math.sin(a) * RADIUS)
end

local function dragUpdate(b)
  local mx, my = Minimap:GetCenter()
  local cx, cy = GetCursorPosition()
  local s = Minimap:GetEffectiveScale()
  Z.SetPref("minimapAngle", math.deg(math.atan2(cy / s - my, cx / s - mx)))
  place(b)
end

-- The addons the menu lists: every registered one with a window to open.
function M.Entries()
  local out = {}
  for _, def in ipairs(Z.Suites.Registered()) do
    local open = Z.Suites.Opener(def)
    if open and def.launcher ~= false then out[#out + 1] = { title = def.title, icon = def.icon, open = open } end
  end
  out[#out + 1] = { title = L["Settings"], icon = Z.Hub.ICON, open = function() Z.Open() end }
  return out
end

local function menuRow(menu, i, e)
  local r = menu.rows[i]
  if not r then
    r = CreateFrame("Button", nil, menu)
    r:SetSize(170, 22)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(16, 16)
    r.icon:SetPoint("LEFT", 6, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.label = r:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    r.label:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    local glow = r:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAllPoints()
    Z.SetColor(glow, Z.Colors.hover)
    menu.rows[i] = r
  end
  r.icon:SetTexture(e.icon)
  r.label:SetText(e.title)
  r:SetPoint("TOPLEFT", 6, -(6 + (i - 1) * 22))
  r:SetScript("OnClick", function() menu:Hide(); e.open() end)
  r:Show()
end

function M.ShowMenu(anchor)
  local menu = M.menu
  if not menu then
    menu = Z.FramedFrame("Frame", UIParent, "ZipUILauncherMenu")
    menu:SetFrameStrata("DIALOG")
    menu.rows = {}
    if UISpecialFrames then table.insert(UISpecialFrames, "ZipUILauncherMenu") end
    M.menu = menu
  end
  local list = M.Entries()
  for i, e in ipairs(list) do menuRow(menu, i, e) end
  for i = #list + 1, #menu.rows do menu.rows[i]:Hide() end
  menu:SetSize(182, 12 + #list * 22)
  menu:ClearAllPoints()
  menu:SetPoint("TOPRIGHT", anchor, "BOTTOMLEFT", 0, 0)
  menu:Show()
end

local function tooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine("Zip")
  for _, def in ipairs(Z.Suites.Registered()) do GameTooltip:AddLine(def.title .. "  " .. (def.cmd or ""), 1, 1, 1) end
  GameTooltip:AddLine(L["Left click: open an addon   Right click: settings   Drag: move"], 0.62, 0.55, 0.42)
  GameTooltip:Show()
end

function M.Build()
  if M.button or not Minimap then return M.button end
  local b = CreateFrame("Button", "ZipUIMinimapButton", Minimap)
  b:SetSize(32, 32)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetTexture(Z.Hub.ICON)
  b.icon:SetSize(20, 20)
  b.icon:SetPoint("CENTER")
  b.border = b:CreateTexture(nil, "OVERLAY")
  b.border:SetTexture("Interface/Minimap/MiniMap-TrackingBorder")
  b.border:SetSize(54, 54)
  b.border:SetPoint("TOPLEFT")
  b:SetHighlightTexture("Interface/Minimap/UI-Minimap-ZoomButton-Highlight")
  b:SetScript("OnClick", function(self, btn)
    if btn == "RightButton" then return Z.Open() end
    if M.menu and M.menu:IsShown() then return M.menu:Hide() end
    M.ShowMenu(self)
  end)
  b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", dragUpdate) end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  b:SetScript("OnEnter", tooltip)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  M.button = b
  place(b)
  M.Update()
  return b
end

function M.Update()
  if M.button then
    if Z.Prefs().minimapHide then M.button:Hide() else M.button:Show() end
  end
end

Z.On("PLAYER_LOGIN", M.Build)
