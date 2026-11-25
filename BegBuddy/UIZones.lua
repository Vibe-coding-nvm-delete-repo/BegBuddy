-- BegBuddy / UIZones.lua
-- Zone picker: every zone, grouped like the world map, tick as many as
-- you like. The ticks are saved, so the pick survives a reload.

local ADDON, ns = ...

local W = ns.W
local BACKDROP, Style, Sanitize, MakeButton = W.BACKDROP, W.Style, W.Sanitize, W.MakeButton

local CHECK_BOX  = "Interface\\Buttons\\UI-CheckBox-Up"
local CHECK_MARK = "Interface\\Buttons\\UI-CheckBox-Check"
local ROW, MAX_ROWS, TOP = 18, 22, 26

local function NewZoneButton(parent, width)
  local btn = CreateFrame("Button", nil, parent, BACKDROP)
  Style(btn, 0.10, 0.10, 0.12, 0.95)
  btn:SetHeight(22)
  btn:SetWidth(width or 260)
  btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  btn.label:SetPoint("LEFT", 8, 0)
  btn.label:SetPoint("RIGHT", -18, 0)
  btn.label:SetJustifyH("LEFT")
  btn.label:SetWordWrap(false)
  btn.arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  btn.arrow:SetPoint("RIGHT", -8, 0)
  btn.arrow:SetText("v")
  btn:SetScript("OnEnter", function(self)
    if self.SetBackdropColor then self:SetBackdropColor(0.16, 0.16, 0.20, 1) end
  end)
  btn:SetScript("OnLeave", function(self)
    if self.SetBackdropColor then self:SetBackdropColor(0.10, 0.10, 0.12, 0.95) end
  end)
  return btn
end

-- The click-catcher behind the popup and the popup itself.
local function NewZonePopup()
  local catcher = CreateFrame("Frame", nil, UIParent)
  catcher:SetAllPoints(UIParent)
  catcher:SetFrameStrata("FULLSCREEN")
  catcher:EnableMouse(true)
  catcher:Hide()

  local popup = CreateFrame("Frame", nil, UIParent, BACKDROP)
  Style(popup, 0.06, 0.06, 0.08, 0.98)
  popup:SetFrameStrata("FULLSCREEN_DIALOG")
  popup:SetWidth(320)
  popup:EnableMouse(true)       -- clicks on the gaps must not fall through and close it
  popup:EnableMouseWheel(true)
  popup:Hide()
  popup.rows = {}
  popup.offset = 0

  popup.title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  popup.title:SetPoint("TOPLEFT", 8, -8)
  popup.title:SetPoint("TOPRIGHT", -8, -8)
  popup.title:SetJustifyH("LEFT")
  popup.more = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  popup.more:SetPoint("BOTTOMRIGHT", -8, 4)
  popup.more:SetTextColor(0.55, 0.55, 0.58)
  return catcher, popup
end

local function ZoneItems()
  local items = {}
  for _, g in ipairs(ns.ZoneGroups()) do
    local picked = 0
    for _, z in ipairs(g.zones) do
      if ns.IsZoneSelected(z) then picked = picked + 1 end
    end
    items[#items + 1] = { group = g, picked = picked }
    if not BegDB.zoneCollapsed[g.id] then
      for _, z in ipairs(g.zones) do items[#items + 1] = { group = g, zone = z } end
    end
  end
  return items
end

local function SetGroup(g, on, Build)
  for _, z in ipairs(g.zones) do BegDB.zoneSel[z] = on and true or nil end
  Build()
  ns.RefreshUI()
end

local function NewZoneRow(popup, i, Build)
  local row = CreateFrame("Button", nil, popup)
  row:SetHeight(ROW)
  row:SetPoint("TOPLEFT", 4, -TOP - (i - 1) * ROW)
  row:SetPoint("TOPRIGHT", -4, -TOP - (i - 1) * ROW)
  row.hl = row:CreateTexture(nil, "BACKGROUND")
  row.hl:SetAllPoints()
  row.hl:SetColorTexture(1, 1, 1, 0.07)
  row.hl:Hide()
  row.box = row:CreateTexture(nil, "ARTWORK")
  row.box:SetSize(16, 16)
  row.box:SetPoint("LEFT", 16, 0)
  row.box:SetTexture(CHECK_BOX)
  row.check = row:CreateTexture(nil, "OVERLAY")
  row.check:SetSize(16, 16)
  row.check:SetPoint("CENTER", row.box, "CENTER")
  row.check:SetTexture(CHECK_MARK)
  row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.text:SetJustifyH("LEFT")
  row.text:SetWordWrap(false)


  row.none = MakeButton(row, "none", 38)
  row.none:SetHeight(16)
  row.none:SetPoint("RIGHT", -2, 0)
  row.none:SetScript("OnClick", function(self) SetGroup(self:GetParent().item.group, false, Build) end)
  row.all = MakeButton(row, "all", 30)
  row.all:SetHeight(16)
  row.all:SetPoint("RIGHT", row.none, "LEFT", -3, 0)
  row.all:SetScript("OnClick", function(self) SetGroup(self:GetParent().item.group, true, Build) end)

  row:SetScript("OnEnter", function(self) self.hl:Show() end)
  row:SetScript("OnLeave", function(self) self.hl:Hide() end)
  row:SetScript("OnClick", function(self)
    local it = self.item
    if not it then return end
    if it.zone then
      ns.SetZoneSelected(it.zone, not ns.IsZoneSelected(it.zone))
    else
      local id = it.group.id
      BegDB.zoneCollapsed[id] = not BegDB.zoneCollapsed[id] or nil
    end
    Build()
    ns.FlushUI()
  end)
  popup.rows[i] = row
  return row
end

local function PaintZoneItem(row, it, current)
  local on = ns.IsZoneSelected(it.zone)
  row.box:Show()
  row.check:SetShown(on)
  row.all:Hide(); row.none:Hide()
  row.text:ClearAllPoints()
  row.text:SetPoint("LEFT", row.box, "RIGHT", 4, 0)
  row.text:SetPoint("RIGHT", -4, 0)
  local name = Sanitize(it.zone)
  local label = on and ("|cffffffff" .. name .. "|r") or ("|cff8f8f96" .. name .. "|r")
  if on and it.zone == current then label = label .. "  |cff5cc8ff< scanning now|r" end
  row.text:SetText(label)
  row:Show()
end

local function PaintGroupItem(row, it)
  local g = it.group
  row.box:Hide(); row.check:Hide()
  row.all:Show(); row.none:Show()
  row.text:ClearAllPoints()
  row.text:SetPoint("LEFT", 4, 0)
  row.text:SetPoint("RIGHT", row.all, "LEFT", -4, 0)
  row.text:SetText(string.format("|cff%s%s %s|r  |cff8f8f96%d of %d|r",
    g.color, BegDB.zoneCollapsed[g.id] and "+" or "-", g.label, it.picked, #g.zones))
  row:Show()
end

-- Title line and the "scroll for more" footer, then the popup height.
local function ZoneFooter(popup, n, shown)
  local picked = #ns.SelectedZones()
  popup.title:SetText(string.format(
    "|cffffd100%d|r zone%s picked   |cff8f8f96tick zones, click a heading to fold it|r",
    picked, picked == 1 and "" or "s"))

  local extra = 0
  if n > shown then
    popup.more:SetText(string.format("%d-%d of %d, scroll for more",
      popup.offset + 1, popup.offset + shown, n))
    popup.more:Show()
    extra = 14
  else
    popup.more:Hide()
  end
  popup:SetHeight(TOP + shown * ROW + 8 + extra)
end

local function WireZonePicker(btn, popup, catcher, Build)
  popup:SetScript("OnMouseWheel", function(_, delta)
    popup.offset = popup.offset - delta * 3
    Build()
  end)

  btn:SetScript("OnClick", function(self)
    if popup:IsShown() then
      popup:Hide(); catcher:Hide(); return
    end
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
    Build()
    popup:Show()
    catcher:Show()
  end)

  catcher:SetScript("OnMouseDown", function()
    popup:Hide(); catcher:Hide()
  end)

  function btn:Close()
    popup:Hide()
    catcher:Hide()
  end
  -- Redraws the open list after a change from outside (Add this zone, etc.).
  function btn:Refresh()
    if popup:IsShown() then Build() end
  end
end

local function MakeZonePicker(parent, width)
  local btn = NewZoneButton(parent, width)
  local catcher, popup = NewZonePopup()

  local Build
  Build = function()
    local items = ZoneItems()
    local n = #items
    local shown = math.min(n, MAX_ROWS)
    popup.offset = math.max(0, math.min(popup.offset, n - shown))
    local current = ns.GetSelectedCity()

    for i = 1, math.max(shown, #popup.rows) do
      local row = popup.rows[i] or NewZoneRow(popup, i, Build)
      local it = (i <= shown) and items[popup.offset + i] or nil
      row.item = it
      if not it then
        row:Hide()
      elseif it.zone then
        PaintZoneItem(row, it, current)
      else
        PaintGroupItem(row, it)
      end
    end
    ZoneFooter(popup, n, shown)
  end

  WireZonePicker(btn, popup, catcher, Build)
  return btn
end

ns.W.MakeZonePicker = MakeZonePicker
ns.W.NewPickerButton = NewZoneButton
