-- BegBuddy / UIWidgets.lua
-- Shared look and small widgets for the windows: styles, icons, buttons, dropdown.
-- Self-contained (no MenuUtil, no ScrollBox, no UIDropDownMenu) so this keeps
-- working on a beta client whose frame APIs are still moving.

local ADDON, ns = ...

ns.W = ns.W or {}

local BACKDROP = BackdropTemplateMixin and "BackdropTemplate" or nil
local ACCENT   = { 0.36, 0.78, 1.00 }
local DIM      = { 0.62, 0.62, 0.66 }

-- Small icons for the contact actions, drawn inline in the button label.
-- Every path here is one Classic Era's own interface uses, so none of them
-- can come up as a missing-texture square.
local ICON = {
  whisper   = "Interface\\Icons\\INV_Letter_15:14:14:0:0:64:64:5:59:5:59",
  funded    = "Interface\\Icons\\INV_Misc_Coin_01:14:14:0:0:64:64:5:59:5:59",
  archive   = "Interface\\Icons\\INV_Misc_Note_02:14:14:0:0:64:64:5:59:5:59",
  requeue   = "Interface\\Icons\\INV_Misc_PocketWatch_01:14:14:0:0:64:64:5:59:5:59",
  declined  = "Interface\\RaidFrame\\ReadyCheck-NotReady:14:14",
  block     = "Interface\\Icons\\Ability_Defend:14:14:0:0:64:64:5:59:5:59",
  history   = "Interface\\Icons\\inv_misc_scrollunrolled01:14:14:0:0:64:64:5:59:5:59",
  invite    = "Interface\\GroupFrame\\UI-Group-LeaderIcon:14:14",
  friend    = "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon:14:14",
  mail      = "Interface\\Minimap\\Tracking\\Mailbox:14:14",
  scan      = "Interface\\Icons\\INV_Misc_Spyglass_02:14:14:0:0:64:64:5:59:5:59",
  zones     = "Interface\\Icons\\INV_Misc_Map_01:14:14:0:0:64:64:5:59:5:59",
  here      = "Interface\\Icons\\INV_Misc_Flag_01:14:14:0:0:64:64:5:59:5:59",
  nextzone  = "Interface\\Icons\\Ability_Rogue_Sprint:14:14:0:0:64:64:5:59:5:59",
  levels    = "Interface\\Icons\\INV_Misc_Note_01:14:14:0:0:64:64:5:59:5:59",
  settings  = "Interface\\Icons\\INV_Misc_Gear_01:14:14:0:0:64:64:5:59:5:59",
  ready     = "Interface\\RaidFrame\\ReadyCheck-Ready:14:14",
}
local function WithIcon(key, label)
  return "|T" .. ICON[key] .. "|t " .. label
end

local function Style(f, r, g, b, a)
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile   = "Interface\\Buttons\\WHITE8x8",
      edgeFile = "Interface\\Buttons\\WHITE8x8",
      edgeSize = 1,
    })
    f:SetBackdropColor(r or 0.04, g or 0.04, b or 0.05, a or 0.92)
    f:SetBackdropBorderColor(0.18, 0.18, 0.21, 1)
  end
end

-- Shared with Core so Scan.lua can sanitise interpolated data too.
local Sanitize = ns.Sanitize

local function MakeButton(parent, label, width)
  local b = CreateFrame("Button", nil, parent, BACKDROP)
  Style(b, 0.12, 0.12, 0.14, 0.95)
  b:SetHeight(22)
  if width then b:SetWidth(width) end
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  b.text:SetPoint("CENTER")
  b.text:SetText(label)
  b:SetScript("OnEnter", function(self)
    if self.SetBackdropColor then self:SetBackdropColor(0.20, 0.20, 0.24, 1) end
  end)
  b:SetScript("OnLeave", function(self)
    if not self.SetBackdropColor then return end
    -- Restore the selected tint if this is an active tab, otherwise a hover
    -- would leave it looking unselected.
    if self.activeTab then
      self:SetBackdropColor(0.16, 0.30, 0.40, 1)
    else
      self:SetBackdropColor(0.12, 0.12, 0.14, 0.95)
    end
  end)
  -- A visible press, so a click registers before anything else happens.
  b:SetScript("OnMouseDown", function(self)
    if self:IsEnabled() then self.text:SetPoint("CENTER", 1, -1) end
  end)
  b:SetScript("OnMouseUp", function(self) self.text:SetPoint("CENTER", 0, 0) end)
  -- Every click handler ends with an immediate redraw, so the window answers
  -- in the same frame instead of the next one.
  local setScript = b.SetScript
  function b:SetScript(event, fn)
    if event == "OnClick" and fn then
      return setScript(self, event, function(...)
        fn(...)
        ns.FlushUI()
      end)
    end
    return setScript(self, event, fn)
  end
  function b:SetLabel(s) self.text:SetText(s) end
  return b
end

----------------------------------------------------------------------
-- Dropdown
----------------------------------------------------------------------

local ROW, MAX_ROWS = 20, 12

local function NewDropdownButton(parent, width)
  local btn = CreateFrame("Button", nil, parent, BACKDROP)
  Style(btn, 0.10, 0.10, 0.12, 0.95)
  btn:SetHeight(22)
  btn:SetWidth(width or 220)
  btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  btn.label:SetPoint("LEFT", 8, 0)
  btn.label:SetPoint("RIGHT", -18, 0)
  btn.label:SetJustifyH("LEFT")
  btn.label:SetText("(none)")
  btn.arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  btn.arrow:SetPoint("RIGHT", -8, 0)
  btn.arrow:SetText("v")
  return btn
end

-- The click-catcher behind the popup and the popup itself.
local function NewDropdownPopup(btn)
  local catcher = CreateFrame("Frame", nil, UIParent)
  catcher:SetAllPoints(UIParent)
  catcher:SetFrameStrata("FULLSCREEN")
  catcher:EnableMouse(true)  -- a plain Frame ignores the mouse unless asked
  catcher:Hide()

  local popup = CreateFrame("Frame", nil, UIParent, BACKDROP)
  Style(popup, 0.08, 0.08, 0.10, 0.98)
  popup:SetFrameStrata("FULLSCREEN_DIALOG")
  popup:SetWidth(btn:GetWidth())
  popup:Hide()
  popup.rows = {}
  popup.items = {}
  popup.offset = 0
  popup:EnableMouseWheel(true)

  popup.more = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  popup.more:SetPoint("BOTTOMRIGHT", -8, 4)
  popup.more:SetTextColor(0.55, 0.55, 0.58)
  return catcher, popup
end

-- One selectable line in the popup.
local function NewDropRow(popup, catcher, i, onPick)
  local row = CreateFrame("Button", nil, popup)
  row:SetHeight(ROW)
  row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * ROW)
  row:SetPoint("TOPRIGHT", -4, -4 - (i - 1) * ROW)
  row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.text:SetPoint("LEFT", 4, 0)
  row.text:SetPoint("RIGHT", -4, 0)
  row.text:SetJustifyH("LEFT")
  row:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 1) end)
  row:SetScript("OnLeave", function(self) self.text:SetTextColor(0.85, 0.85, 0.88) end)
  row:SetScript("OnClick", function(self)
    if self.emptyAction then
      ns.FindCities()
    elseif self.value and onPick then
      onPick(self.value)
    end
    popup:Hide()
    catcher:Hide()
    ns.FlushUI()
  end)
  return row
end

local function FillDropRow(row, item, i, n, shown)
  if i == 1 and n == 0 then
    row.value = nil
    row.emptyAction = true
    row.text:SetText("|cff888888No cities yet - click to scan|r")
    row:Show()
  elseif item and i <= shown then
    row.value = item
    row.emptyAction = false
    row.text:SetText(Sanitize(item))
    row:Show()
  else
    row.value = nil
    row.emptyAction = false
    row:Hide()
  end
end

local function DropFooter(popup, n, shown)
  local extra = 0
  if n > shown then
    popup.more:SetText(string.format("%d-%d of %d, scroll for more",
      popup.offset + 1, popup.offset + shown, n))
    popup.more:Show()
    extra = 14
  else
    popup.more:Hide()
  end
  popup:SetHeight((n == 0 and 1 or shown) * ROW + 8 + extra)
end

local function WireDropdown(btn, popup, catcher, Build)
  popup:SetScript("OnMouseWheel", function(_, delta)
    popup.offset = popup.offset - delta
    Build()
  end)

  btn:SetScript("OnClick", function(self)
    if popup:IsShown() then
      popup:Hide(); catcher:Hide(); return
    end
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
    popup:SetWidth(self:GetWidth())
    popup.offset = 0
    Build()
    popup:Show()
    catcher:Show()
  end)

  catcher:SetScript("OnMouseDown", function()
    popup:Hide(); catcher:Hide()
  end)

  function btn:SetItems(items, current)
    popup.items = items or {}
    if current then self.label:SetText(Sanitize(current)) end
    Build()
  end
  -- The popup lives on UIParent so it can overhang its parent frame, which
  -- means hiding that frame does not hide the popup. Close it explicitly.
  function btn:Close()
    popup:Hide()
    catcher:Hide()
  end
end

local function MakeDropdown(parent, width, onPick)
  local btn = NewDropdownButton(parent, width)
  local catcher, popup = NewDropdownPopup(btn)

  local function Build()
    local n = #popup.items
    local shown = math.min(n, MAX_ROWS)
    popup.offset = math.max(0, math.min(popup.offset, n - shown))
    -- Always lay out at least one row slot. Without this an empty list builds
    -- zero rows and the popup opens as a collapsed 8px sliver.
    local slots = math.max(n, 1)

    for i = 1, math.max(slots, #popup.rows) do
      local row = popup.rows[i]
      if not row then
        row = NewDropRow(popup, catcher, i, onPick)
        popup.rows[i] = row
      end
      FillDropRow(row, popup.items[popup.offset + i], i, n, shown)
    end
    DropFooter(popup, n, shown)
  end

  WireDropdown(btn, popup, catcher, Build)
  return btn
end

----------------------------------------------------------------------
-- Scrolling text (history, popout)
----------------------------------------------------------------------

local LINE_H = 15

local function ScrollReflow(host)
  local fs = host.fs
  local h = fs:GetStringHeight() or 0
  if h <= 0 and (host.lineCount or 0) > 0 then
    -- Font engine has not measured yet. Estimate instead, so text can never
    -- be left parked off-screen just because a height reading was stale.
    h = host.lineCount * LINE_H
  end
  local view = host:GetHeight() or 0
  local maxOff = math.max(0, h - view + 12)
  if host.offset > maxOff then host.offset = maxOff end
  if host.offset < 0 then host.offset = 0 end
  fs:ClearAllPoints()
  fs:SetPoint("TOPLEFT", 4, -4 + host.offset)
  fs:SetPoint("TOPRIGHT", -4, -4 + host.offset)
end

local function MakeScroller(parent)
  local host = CreateFrame("Frame", nil, parent, BACKDROP)
  Style(host, 0.05, 0.05, 0.06, 0.85)
  host:SetClipsChildren(true)

  -- The text belongs to the box itself, not to an inner frame. An inner frame
  -- only had a width, and with clipping on the game can skip drawing a
  -- zero-height frame, which left the history blank.
  local fs = host:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetPoint("TOPLEFT", 4, -4)
  fs:SetPoint("TOPRIGHT", -4, -4)
  fs:SetJustifyH("LEFT")
  fs:SetJustifyV("TOP")
  fs:SetSpacing(3)

  host.offset = 0
  host.lineCount = 0
  host.fs = fs

  local function Reflow() ScrollReflow(host) end
  host.Reflow = Reflow

  host:EnableMouseWheel(true)
  host:SetScript("OnMouseWheel", function(_, delta)
    host.offset = host.offset - delta * 26
    Reflow()
  end)
  host:SetScript("OnSizeChanged", Reflow)

  -- Text is expected to already be safe: callers sanitise each message body,
  -- never the colour markup this addon adds itself.
  function host:SetText(text, lineCount, scrollToEnd)
    fs:SetText(text or "")
    host.lineCount = lineCount or 0
    host.offset = 0
    Reflow()
    if scrollToEnd and C_Timer and C_Timer.After then
      -- Second pass once the font engine has measured, so a log lands on its
      -- newest line. If this never runs we simply sit at the top, which is
      -- still readable.
      C_Timer.After(0, function()
        host.offset = 1e6
        Reflow()
      end)
    end
  end
  return host
end

local W = ns.W
W.BACKDROP, W.ACCENT, W.DIM, W.ICON = BACKDROP, ACCENT, DIM, ICON
W.WithIcon, W.Style, W.Sanitize = WithIcon, Style, Sanitize
W.MakeButton, W.MakeDropdown, W.MakeScroller = MakeButton, MakeDropdown, MakeScroller
