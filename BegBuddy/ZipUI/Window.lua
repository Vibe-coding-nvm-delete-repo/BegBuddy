-- Tabs and windows in the shared look. A tab is dark with a gold label and its icon; the chosen one is lit
-- with a gold underline. A window has the addon's icon and name on top, a close button, icon tabs and a framed
-- page, and remembers where it was, its size (scale) and whether it is locked.
if ZipUI.skip then return end
local Z = ZipUI
local GOLD, DIM, WHITE = Z.GOLD, Z.DIM, Z.WHITE

local function paint(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

-- big = a main tab (30 high, 20 px icon); otherwise a sub-tab (22 high, greyed until chosen).
function Z.StyleTab(b, on, big)
  if on then b.bg:SetColorTexture(0.32, 0.22, 0.06, 0.95) else b.bg:SetColorTexture(0.08, 0.07, 0.05, big and 0.9 or 0.7) end
  if on then b.line:Show() else b.line:Hide() end
  paint(b.label, on and WHITE or (big and GOLD or DIM))
  b.icon:SetDesaturated(not on and not big)
  b:Show()
end

function Z.Tab(parent, big, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(big and 30 or 22)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.line = b:CreateTexture(nil, "ARTWORK")
  b.line:SetPoint("BOTTOMLEFT", 0, 0)
  b.line:SetPoint("BOTTOMRIGHT", 0, 0)
  b.line:SetHeight(2)
  b.line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
  local glow = b:CreateTexture(nil, "HIGHLIGHT")
  glow:SetAllPoints()
  glow:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.12)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(big and 20 or 14, big and 20 or 14)
  b.icon:SetPoint("LEFT", 6, big and 0 or 1)
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trim the icon's own border
  b.label = b:CreateFontString(nil, "ARTWORK", big and "GameFontNormal" or "GameFontNormalSmall")
  b.label:SetPoint("LEFT", b.icon, "RIGHT", 5, 0)
  b:SetScript("OnClick", function(self) Z.Sound("IG_CHARACTER_INFO_TAB"); onClick(self) end)
  return b
end

-- Set a tab's icon and text and size it to fit. Returns its width.
function Z.FitTab(b, icon, title, big)
  b.icon:SetTexture(icon or "Interface/Icons/INV_Misc_QuestionMark")
  b.label:SetText(title)
  local w = math.floor((b.label:GetStringWidth() or 0) + (big and 38 or 30))
  b:SetWidth(w)
  return w
end

-- Saved window state: point, scale, locked. db() returns the table it lives in (made on first use).
local function state(f)
  local t = f.db and f.db()
  if type(t) ~= "table" then t = f.fallback end
  return t
end

local function savePoint(f)
  local p, _, rp, x, y = f:GetPoint()
  state(f).point = { p, rp, x, y }
end

function Z.RestoreWindow(f)
  local st = state(f)
  f:SetScale(st.scale or 1)
  f:ClearAllPoints()
  local pt = st.point
  if pt then f:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4]) else f:SetPoint("CENTER") end
end

local function titleBar(f, opts)
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(22, 22)
  f.icon:SetPoint("TOPLEFT", 10, -8)
  f.icon:SetTexture(opts.icon or "Interface/Icons/INV_Misc_QuestionMark")
  f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  f.title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  f.title:SetPoint("LEFT", f.icon, "RIGHT", 8, 0)
  f.title:SetText(opts.title or "")
  f.closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  f.closeBtn:SetPoint("TOPRIGHT", -2, -2)
  if opts.settings then -- every Zip window opens its settings the same way: this button, top right
    f.settingsBtn = Z.Button(f, Z.L["Settings"], 80, 22, function() Z.Open(opts.settings) end)
    f.settingsBtn:SetPoint("RIGHT", f.closeBtn, "LEFT", -4, 0)
  end
  f.rule = f:CreateTexture(nil, "ARTWORK")
  f.rule:SetPoint("TOPLEFT", 10, -36)
  f.rule:SetPoint("TOPRIGHT", -10, -36)
  f.rule:SetHeight(1)
  f.rule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.35)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) if not state(self).locked then self:StartMoving() end end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePoint(self) end)
end

local METHODS = {}

function METHODS:SetLocked(on)
  state(self).locked = on and true or false
end
function METHODS:IsLocked() return state(self).locked == true end

function METHODS:SetSavedScale(v)
  v = math.max(0.5, math.min(2, tonumber(v) or 1))
  state(self).scale = v
  self:SetScale(v)
  return v
end

function METHODS:ResetPosition()
  local st = state(self)
  st.point, st.scale = nil, 1
  Z.RestoreWindow(self)
end

function METHODS:Toggle()
  if self:IsShown() then self:Hide() else self:Show() end
end

-- Tabs along the top: AddTab(key, title, icon, build(content)) where build makes the page once.
function METHODS:AddTab(key, title, icon, build)
  local b = Z.Tab(self, true, function(tb) self:SelectTab(tb.key) end)
  b.key = key
  local w = Z.FitTab(b, icon, title, true)
  b:SetPoint("TOPLEFT", self.tabX, -42)
  self.tabX = self.tabX + w + 4
  self.tabs[#self.tabs + 1] = b
  self.builders[key] = build
  Z.StyleTab(b, false, true)
  return b
end

function METHODS:SelectTab(key)
  if not self.builders[key] then return false end
  for _, b in ipairs(self.tabs) do Z.StyleTab(b, b.key == key, true) end
  if self.shownPage then self.shownPage:Hide() end
  local page = self.pages[key]
  if not page then
    page = CreateFrame("Frame", nil, self.box)
    page:SetPoint("TOPLEFT", 10, -10)
    page:SetPoint("BOTTOMRIGHT", -10, 10)
    self.pages[key] = page
    self.builders[key](page)
  end
  page:Show()
  self.shownPage, self.current = page, key
  if self.onSelect then self.onSelect(key) end
  return true
end

-- opts: name (global, so Esc closes it), title, icon, width, height, db (function -> table for point, scale,
-- locked), tabs (true: leave room for a tab row), settings (a settings page key: adds a Settings button that
-- opens it). Put widgets in window.box (the framed page) or use AddTab.
function Z.Window(opts)
  local f = CreateFrame("Frame", opts.name, UIParent, Z.BACKDROP)
  for k, fn in pairs(METHODS) do f[k] = fn end
  f.db, f.fallback = opts.db, {}
  f.tabs, f.builders, f.pages, f.tabX = {}, {}, {}, 12
  f:SetSize(opts.width or 600, opts.height or 440)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  Z.Framed(f)
  titleBar(f, opts)
  f.box = Z.FramedFrame("Frame", f)
  f.box:SetPoint("TOPLEFT", 8, opts.tabs and -76 or -42)
  f.box:SetPoint("BOTTOMRIGHT", -8, 8)
  f.content = f.box
  if opts.name and UISpecialFrames then table.insert(UISpecialFrames, opts.name) end
  f:SetScript("OnShow", function(self) Z.Sound("IG_CHARACTER_INFO_OPEN"); Z.RestoreWindow(self) end)
  f:SetScript("OnHide", function() Z.Sound("IG_CHARACTER_INFO_CLOSE") end)
  f:Hide()
  return f
end
