-- BegBuddy / UIQuick.lua
-- The quick-message strip in the detail pane: one button per message, above the reply box. Click one to send it
-- where the cursor is: the chat box's channel, else a whisper to the person open. A Quick button beside Send folds
-- the strip away.

local _, ns = ...

local W = ns.W
local Sanitize, MakeButton = W.Sanitize, W.MakeButton

local GAP, ROW_H = 4, 20
local STRIP_Y = 34 -- the strip sits just above the reply row
local FALLBACK_W = 448 -- the detail pane's width when the client has not measured it yet

local function IsOpen()
  local db = BegDB.window
  return not (db and db.quickClosed)
end

local function StripWidth(detail)
  local w = detail:GetWidth()
  if type(w) ~= "number" or w < 100 then w = FALLBACK_W + 20 end
  return w - 20
end

-- One button per shown message, left to right, wrapping to a new row when the next one will not fit.
-- Returns the strip's height.
local function PlaceButtons(f, shown, avail)
  local strip = f.quick.strip
  local x, row = 0, 0
  for i, m in ipairs(shown) do
    local b = strip.buttons[i]
    if not b then
      b = MakeButton(strip, "", 60)
      b:SetHeight(ROW_H)
      b.text:SetWordWrap(false)
      b:SetScript("OnClick", function(self) ns.SendQuick(self.message) end)
      strip.buttons[i] = b
    end
    b.message = m.text
    b.text:SetWidth(0) -- measure the whole text, not the width it was clipped to last time
    b:SetLabel(Sanitize(m.text))
    local w = math.min(math.max(b.text:GetStringWidth() + 16, 44), avail)
    b:SetWidth(w)
    b.text:SetWidth(w - 8)
    if x > 0 and x + w > avail then x, row = 0, row + 1 end
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", strip, "TOPLEFT", x, -row * (ROW_H + GAP))
    b:Show()
    x = x + w + GAP
  end
  for i = #shown + 1, #strip.buttons do strip.buttons[i]:Hide() end
  return (#shown > 0) and ((row + 1) * (ROW_H + GAP) - GAP) or 0
end

-- Single source of truth for the detail pane's bottom stack:
--   reply row -> optional Quick strip -> optional Smart Auto-Reply bar -> chat history.
local function LayoutDetailBottom(f)
  local detail = f.detail
  if not detail or not detail.history then return end
  local qH = (f.quick and f.quick.height) or 0
  local y = STRIP_Y + (qH > 0 and (qH + 4) or 0)
  local bar = detail.smartBar
  if bar and bar:IsShown() then
    bar:ClearAllPoints()
    bar:SetPoint("BOTTOMLEFT", detail, "BOTTOMLEFT", 10, y)
    bar:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -10, y)
    y = y + (bar.barHeight or 48) + 4
  end
  detail.history:SetPoint("BOTTOMRIGHT", -10, y)
end
W.LayoutDetailBottom = LayoutDetailBottom

-- Lays the strip out again, only when the messages, the width or the fold changed.
local function Layout(f)
  local q = f.quick
  local detail = f.detail
  local shown = ns.QuickShown()
  local open = IsOpen() and #shown > 0
  local avail = StripWidth(detail)
  local parts = { tostring(open), tostring(avail) }
  for i, m in ipairs(shown) do parts[#parts + 1] = m.text end
  local sig = table.concat(parts, "\1")
  if q.sig == sig then return end
  q.sig = sig
  local h = open and PlaceButtons(f, shown, avail) or 0
  q.height = h
  q.strip:SetShown(open)
  q.strip:SetHeight(math.max(h, 1))
  LayoutDetailBottom(f)
end

-- Called with every redraw. `usable` is false in combat: the buttons grey out.
function W.PaintQuick(f, usable)
  local q = f.quick
  if not q then return end
  Layout(f)
  q.toggle:SetLabel(IsOpen() and "Quick -" or "Quick +")
  if q.strip:IsShown() then
    for _, b in ipairs(q.strip.buttons) do
      if usable then b:Enable() else b:Disable() end
    end
  end
end

function W.BuildQuick(f)
  local detail = f.detail
  local q = {}
  f.quick = q

  -- Squeeze the reply box to make room for the Quick button beside Send.
  detail.reply:SetPoint("BOTTOMRIGHT", -134, 8)
  q.toggle = MakeButton(detail, "Quick -", 56)
  q.toggle:SetPoint("BOTTOMRIGHT", -72, 8)
  q.toggle:SetScript("OnClick", function()
    if #ns.QuickShown() == 0 then
      ns.Print("No quick messages to show. Add some in Settings > BegBuddy > Quick messages.")
      return
    end
    BegDB.window = BegDB.window or {}
    BegDB.window.quickClosed = IsOpen() or nil
    q.sig = nil
    ns.RefreshUI()
  end)

  q.strip = CreateFrame("Frame", nil, detail)
  q.strip:SetPoint("BOTTOMLEFT", 10, STRIP_Y)
  q.strip:SetPoint("BOTTOMRIGHT", -10, STRIP_Y)
  q.strip:SetHeight(1)
  q.strip.buttons = {}
  return q
end
