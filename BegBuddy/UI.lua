-- BegBuddy / UI.lua
-- The windows' public surface, the history popout and the copy box. Shared widgets are in
-- UIWidgets.lua, the main window in UIMain.lua and its redraw in UIRefresh.lua.

local ADDON, ns = ...

ns.UI = ns.UI or {}

local W = ns.W
local BACKDROP, DIM, Style, Sanitize = W.BACKDROP, W.DIM, W.Style, W.Sanitize
local MakeButton, MakeScroller, BuildMain = W.MakeButton, W.MakeScroller, W.BuildMain

----------------------------------------------------------------------
-- History popout
----------------------------------------------------------------------

local function BuildPopout()
  local p = CreateFrame("Frame", "BegBuddyPopout", UIParent, BACKDROP)
  p:SetSize(560, 420)
  p:SetPoint("CENTER")
  p:SetFrameStrata("DIALOG")
  p:SetMovable(true)
  p:EnableMouse(true)
  p:RegisterForDrag("LeftButton")
  p:SetScript("OnDragStart", p.StartMoving)
  p:SetScript("OnDragStop", p.StopMovingOrSizing)
  p:SetClampedToScreen(true)
  Style(p, 0.03, 0.03, 0.04, 1)
  p:Hide()
  table.insert(UISpecialFrames, "BegBuddyPopout")

  local t = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  t:SetPoint("TOPLEFT", 12, -12)
  p.title = t

  local close = MakeButton(p, "X", 24)
  close:SetPoint("TOPRIGHT", -8, -8)
  close:SetScript("OnClick", function() p:Hide() end)

  local scroller = MakeScroller(p)
  scroller:SetPoint("TOPLEFT", 12, -40)
  scroller:SetPoint("BOTTOMRIGHT", -12, 12)
  p.scroller = scroller
  return p
end

----------------------------------------------------------------------
-- Copy box
----------------------------------------------------------------------

local function NewCopyFrame()
  local p = CreateFrame("Frame", "BegBuddyCopy", UIParent, BACKDROP)
  p:SetSize(520, 180)
  p:SetPoint("CENTER")
  p:SetFrameStrata("DIALOG")
  p:SetMovable(true)
  p:EnableMouse(true)
  p:RegisterForDrag("LeftButton")
  p:SetScript("OnDragStart", p.StartMoving)
  p:SetScript("OnDragStop", p.StopMovingOrSizing)
  p:SetClampedToScreen(true)
  Style(p, 0.03, 0.03, 0.04, 1)
  p:Hide()
  table.insert(UISpecialFrames, "BegBuddyCopy")

  local t = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  t:SetPoint("TOPLEFT", 12, -12)
  t:SetText("Chat box unavailable - copy this instead")
  p.title = t

  local hint = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hint:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -4)
  hint:SetTextColor(DIM[1], DIM[2], DIM[3])
  hint:SetText("It is already selected. Press Ctrl+C, then paste into the chat box with Ctrl+V.")

  local close = MakeButton(p, "X", 24)
  close:SetPoint("TOPRIGHT", -8, -8)
  close:SetScript("OnClick", function() p:Hide() end)
  return p
end

local function AddCopyBox(p)
  local bg = CreateFrame("Frame", nil, p, BACKDROP)
  Style(bg, 0.09, 0.09, 0.11, 1)
  bg:SetPoint("TOPLEFT", 12, -66)
  bg:SetPoint("BOTTOMRIGHT", -12, 12)

  local sf = CreateFrame("ScrollFrame", nil, bg)
  sf:SetPoint("TOPLEFT", 4, -4)
  sf:SetPoint("BOTTOMRIGHT", -4, 4)
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(self, delta)
    local range = self:GetVerticalScrollRange() or 0
    local v = (self:GetVerticalScroll() or 0) - delta * 40
    self:SetVerticalScroll(math.max(0, math.min(range, v)))
  end)

  local box = CreateFrame("EditBox", nil, sf)
  box:SetMultiLine(true)
  box:SetAutoFocus(false)
  box:SetFontObject("ChatFontNormal")
  box:SetWidth(480)
  box:SetTextInsets(2, 2, 0, 0)
  -- Give it a real height to start from. It grows with the text, but a
  -- zero-height child of a scroll area may not be drawn at all.
  box:SetHeight(90)
  sf:SetScrollChild(box)
  p.scroll = sf
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  p.box = box
end

-- Last resort for a client whose chat box will not accept pre-filled text:
-- show the message somewhere it can be selected and copied.
local function BuildCopyPopup()
  local p = NewCopyFrame()
  AddCopyBox(p)

  function p:ShowText(text, title)
    self.title:SetText(title or "Chat box unavailable - copy this instead")
    self.box:SetText(text or "")
    self.scroll:SetVerticalScroll(0)
    self:Show()
    self.box:SetFocus()
    self.box:HighlightText()
  end
  return p
end

----------------------------------------------------------------------
-- Public surface
----------------------------------------------------------------------

-- The settings pages (Settings*.lua) build their template and zone pickers with this.
ns.UI.Dropdown = W.MakeDropdown

function ns.UI.EnsureBuilt()
  if not ns.UI.frame then
    ns.UI.frame    = BuildMain()
    ns.UI.popout   = BuildPopout()
    ns.UI.copy     = BuildCopyPopup()
  end
end

function ns.UI.ShowCopy(text, title)
  ns.UI.EnsureBuilt()
  ns.UI.copy:ShowText(text, title)
end

function ns.UI.OnLogin()
  ns.UI.EnsureBuilt()
  ns.Print("Window ready. /beg to open, /beg addzone to add this zone, /beg probe to check APIs.")
end

function ns.UI.Toggle()
  ns.UI.EnsureBuilt()
  local f = ns.UI.frame
  if f:IsShown() then
    f:Hide()
  else
    f:Show()
    ns.RefreshUI()
  end
end

-- Called when the mailbox opens: show the window without toggling it shut.
function ns.UI.Open()
  ns.UI.EnsureBuilt()
  local f = ns.UI.frame
  if not f:IsShown() then f:Show() end
  ns.RefreshUI()
end

function ns.UI.ToggleSettings() ZipUI.Open("begbuddy") end

function ns.UI.OnNewReply(contact, incomingText)
  if ns.UI.frame and ns.UI.frame:IsShown() then ns.RefreshUI() end
  if contact and contact.status ~= ns.STATUS.BLOCKED and ns.UI.ShowSmartReply then
    ns.UI.ShowSmartReply(contact, incomingText)
  end
end

function ns.UI.ShowPopout(contact)
  ns.UI.EnsureBuilt()
  if not contact then return end
  local p = ns.UI.popout
  -- Only redraw when the conversation changed, so a refresh does not yank
  -- the scroll position while someone is reading.
  local hist = contact.history or {}
  local sig = table.concat({ contact.key, tostring(#hist), tostring(contact.histVer or 0) }, "|")
  p.contact = contact
  if p:IsShown() and p.sig == sig then return end
  p.sig = sig
  p.title:SetText("History: " .. ns.ClassHexFor(contact) .. Sanitize(contact.name or "?") .. "|r")
  local lines = W.HistoryLines(contact, "%Y-%m-%d %H:%M")
  if #lines == 0 then lines[1] = "|cff9a9a9aNo messages recorded for this contact yet.|r" end
  p.scroller:SetText(table.concat(lines, "\n"), #lines, true)
  p:Show()
end

-- Opens settings on one page, e.g. "scan" from the Change levels button.
function ns.UI.OpenSettings(page)
  ZipUI.Open(page and ("begbuddy/" .. page) or "begbuddy")
end
