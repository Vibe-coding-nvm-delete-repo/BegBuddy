-- BegBuddy / UIClasses.lua
-- Class picker: every class in its own colour, tick as many as you like. The
-- ticks are saved. The rows are built once; a click only repaints them.

local ADDON, ns = ...

local W = ns.W
local BACKDROP, Style = W.BACKDROP, W.Style

local CHECK_BOX  = "Interface\\Buttons\\UI-CheckBox-Up"
local CHECK_MARK = "Interface\\Buttons\\UI-CheckBox-Check"
local ROW, TOP = 20, 6
local NONE_HEX = "|cff8f8f96"
local ALL_TEXT = "All classes"

-- The click-catcher behind the popup and the popup itself.
local function NewPopup(width)
  local catcher = CreateFrame("Frame", nil, UIParent)
  catcher:SetAllPoints(UIParent)
  catcher:SetFrameStrata("FULLSCREEN")
  catcher:EnableMouse(true)
  catcher:Hide()

  local popup = CreateFrame("Frame", nil, UIParent, BACKDROP)
  Style(popup, 0.06, 0.06, 0.08, 0.98)
  popup:SetFrameStrata("FULLSCREEN_DIALOG")
  popup:SetWidth(width)
  popup:EnableMouse(true)       -- clicks on the gaps must not fall through and close it
  popup:Hide()
  return catcher, popup
end

local function NewRow(popup, i)
  local row = CreateFrame("Button", nil, popup)
  row:SetHeight(ROW)
  row:SetPoint("TOPLEFT", 4, -TOP - (i - 1) * ROW)
  row:SetPoint("TOPRIGHT", -4, -TOP - (i - 1) * ROW)
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.bg:SetColorTexture(1, 1, 1, 0)
  row.hl = row:CreateTexture(nil, "BORDER")
  row.hl:SetAllPoints()
  row.hl:SetColorTexture(1, 1, 1, 0.07)
  row.hl:Hide()
  row.box = row:CreateTexture(nil, "ARTWORK")
  row.box:SetSize(16, 16)
  row.box:SetPoint("LEFT", 6, 0)
  row.box:SetTexture(CHECK_BOX)
  row.check = row:CreateTexture(nil, "OVERLAY")
  row.check:SetSize(16, 16)
  row.check:SetPoint("CENTER", row.box, "CENTER")
  row.check:SetTexture(CHECK_MARK)
  row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.text:SetPoint("LEFT", row.box, "RIGHT", 4, 0)
  row.text:SetPoint("RIGHT", -4, 0)
  row.text:SetJustifyH("LEFT")
  row.text:SetWordWrap(false)
  row:SetScript("OnEnter", function(self) self.hl:Show() end)
  row:SetScript("OnLeave", function(self) self.hl:Hide() end)
  return row
end

-- A faint wash of the class colour behind a ticked row.
local function PaintRows(rows)
  for _, row in ipairs(rows) do
    local on
    if row.token then on = ns.IsScanClass(row.token) else on = ns.ScanClasses() == nil end
    row.check:SetShown(on)
    if on then
      local r, g, b = 1, 1, 1
      if row.token then r, g, b = ns.ClassColor(row.token) end
      row.bg:SetColorTexture(r, g, b, 0.16)
    else
      row.bg:SetColorTexture(1, 1, 1, 0)
    end
  end
end

-- The button text: up to two ticked classes in their colours, then +N.
local function PickedLabel()
  local names = {}
  for _, c in ipairs(ns.WhoClasses()) do
    if ns.IsScanClass(c.token) then names[#names + 1] = c end
  end
  if #names == 0 then return NONE_HEX .. ALL_TEXT .. "|r" end
  local shown = {}
  for i = 1, math.min(#names, 2) do
    shown[i] = ns.ClassHex(names[i].token) .. ns.Sanitize(names[i].name) .. "|r"
  end
  local more = #names > 2 and string.format(" |cffffd100+%d|r", #names - 2) or ""
  return table.concat(shown, ", ") .. more
end

local function MakeClassPicker(parent, width)
  local btn = W.NewPickerButton(parent, width)
  local catcher, popup = NewPopup(150)
  local rows

  local function Changed() PaintRows(rows); btn:SetPicked() end

  local function Build()
    rows = {}
    local all = NewRow(popup, 1)
    all.text:SetText(NONE_HEX .. ALL_TEXT .. "|r")
    all:SetScript("OnClick", function() ns.ClearScanClasses(); Changed() end)
    rows[1] = all
    for i, c in ipairs(ns.WhoClasses()) do
      local row = NewRow(popup, i + 1)
      row.token = c.token
      row.text:SetText(ns.ClassHex(c.token) .. ns.Sanitize(c.name) .. "|r")
      row:SetScript("OnClick", function() ns.ToggleScanClass(c.token); Changed() end)
      rows[#rows + 1] = row
    end
    popup:SetHeight(TOP * 2 + #rows * ROW)
  end

  btn:SetScript("OnClick", function(self)
    if popup:IsShown() then popup:Hide(); catcher:Hide(); return end
    if not rows then Build() end
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
    PaintRows(rows)
    popup:Show()
    catcher:Show()
  end)
  catcher:SetScript("OnMouseDown", function() popup:Hide(); catcher:Hide() end)

  function btn:Close() popup:Hide(); catcher:Hide() end

  -- Rebuilt only when the ticks change, so calling this on every redraw costs a lookup.
  function btn:SetPicked()
    local key = ns.ScanClassKey() or ""
    if self.pickedKey == key then return end
    self.pickedKey = key
    self.label:SetText(PickedLabel())
  end
  return btn
end

ns.W.MakeClassPicker = MakeClassPicker
