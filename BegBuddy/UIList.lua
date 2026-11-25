-- BegBuddy / UIList.lua
-- The selectable contact list and the slice chips.

local ADDON, ns = ...

local W = ns.W
local BACKDROP, DIM, Style, Sanitize = W.BACKDROP, W.DIM, W.Style, W.Sanitize

----------------------------------------------------------------------
-- Selectable list
----------------------------------------------------------------------

-- Names cannot contain pipes, but this is belt-and-braces. Keyed on the source
-- so a name changed from outside the addon cannot leave a stale cached copy
-- (the cache would otherwise be persisted into SavedVariables).
local function DispName(c)
  if c.dispNameSrc ~= c.name then
    c.dispNameSrc = c.name
    c.dispName = Sanitize(c.name or "?")
  end
  return c.dispName
end

local ROW_H = 22
local HEAD_H = 18   -- column header strip at the top of the list

local function NewListHost(parent)
  local host = CreateFrame("Frame", nil, parent, BACKDROP)
  Style(host, 0.05, 0.05, 0.06, 0.85)
  host.data = {}
  host.rows = {}
  host.offset = 0
  host.selectedKey = nil
  host:EnableMouseWheel(true)

  -- Shown when the active tab has nothing in it, so an empty list explains
  -- itself instead of looking broken.
  host.emptyText = "Nothing here yet."
  host.empty = host:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  host.empty:SetPoint("TOPLEFT", 10, -HEAD_H - 6)
  host.empty:SetPoint("TOPRIGHT", -10, -HEAD_H - 6)
  host.empty:SetJustifyH("LEFT")
  host.empty:SetTextColor(0.55, 0.55, 0.58)
  host.empty:Hide()

  -- Says the list scrolls, so names past the bottom edge are not missed.
  host.more = host:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  host.more:SetPoint("BOTTOMRIGHT", -8, 3)
  host.more:SetTextColor(0.55, 0.55, 0.58)
  host.more:Hide()
  return host
end

-- A sortable column header; the click cycles ascending, descending, default.
local function HeadButton(host, key, label, justify)
  local b = CreateFrame("Button", nil, host)
  b:SetHeight(HEAD_H)
  b.key, b.plain = key, label
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  b.text:SetAllPoints()
  b.text:SetJustifyH(justify)
  b:SetScript("OnClick", function()
    local st = BegDB.settings
    if st.listSort ~= key then
      st.listSort, st.listSortDesc = key, false
    elseif not st.listSortDesc then
      st.listSortDesc = true
    else
      st.listSort, st.listSortDesc = "found", false
    end
    ns.RefreshUI()
    ns.FlushUI()
  end)
  b:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 1) end)
  b:SetScript("OnLeave", function() host.PaintHead() end)
  host.head[#host.head + 1] = b
  return b
end

local function AddListHeaders(host)
  host.head = {}
  local hName = HeadButton(host, "name", "Name", "LEFT")
  hName:SetPoint("TOPLEFT", 8, -1)
  hName:SetPoint("TOPRIGHT", -164, -1)
  local hLvl = HeadButton(host, "level", "Lvl", "RIGHT")
  hLvl:SetPoint("TOPRIGHT", -100, -1)
  hLvl:SetWidth(60)
end

local function PaintListHead(host)
  local st = BegDB.settings
  for _, b in ipairs(host.head) do
    if st.listSort == b.key then
      local arrow
      if b.key == "name" then arrow = st.listSortDesc and "Z-A" or "A-Z"
      else arrow = st.listSortDesc and "high" or "low" end
      b.text:SetText(b.plain .. " (" .. arrow .. ")")
      b.text:SetTextColor(0.36, 0.78, 1)
    else
      b.text:SetText(b.plain)
      b.text:SetTextColor(0.55, 0.55, 0.58)
    end
  end
end

-- Rapid fire: one click loads the whisper for this row without changing the
-- selection. Press Enter, and the row moves out of the tab so the next name
-- takes its place under the cursor.
local function NewActButton(row)
  row.act = CreateFrame("Button", nil, row, BACKDROP)
  Style(row.act, 0.13, 0.26, 0.16, 0.95)
  row.act:SetWidth(44)
  row.act:SetHeight(16)
  row.act:SetPoint("RIGHT", -3, 0)
  row.act.label = row.act:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.act.label:SetPoint("CENTER")
  row.act.label:SetText("whisper")
  row.act:SetScript("OnEnter", function(self)
    if not self.SetBackdropColor then return end
    if self.mailing then self:SetBackdropColor(0.48, 0.36, 0.10, 1)
    else self:SetBackdropColor(0.19, 0.40, 0.24, 1) end
  end)
  row.act:SetScript("OnLeave", function(self)
    if not self.SetBackdropColor then return end
    if self.mailing then self:SetBackdropColor(0.32, 0.24, 0.06, 0.95)
    else self:SetBackdropColor(0.13, 0.26, 0.16, 0.95) end
  end)
  row.act:SetScript("OnClick", function(self)
    local target = self.owner
    if not target then return end
    ns.WhisperContact(target)
    ns.FlushUI()
  end)
  return row.act
end

-- Online check: one /who for this name. Offline gets archived.
local function NewCheckButton(row)
  row.chk = CreateFrame("Button", nil, row, BACKDROP)
  Style(row.chk, 0.14, 0.18, 0.28, 0.95)
  row.chk:SetWidth(48)
  row.chk:SetHeight(16)
  row.chk:SetPoint("RIGHT", row.act, "LEFT", -3, 0)
  row.chk.label = row.chk:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.chk.label:SetPoint("CENTER")
  row.chk.label:SetText("check")
  row.chk:SetScript("OnEnter", function(self)
    if self.SetBackdropColor then self:SetBackdropColor(0.20, 0.28, 0.44, 1) end
  end)
  row.chk:SetScript("OnLeave", function(self)
    if self.SetBackdropColor then self:SetBackdropColor(0.14, 0.18, 0.28, 0.95) end
  end)
  row.chk:SetScript("OnClick", function(self)
    local target = self.owner
    if not target then return end
    ns.CheckContact(target)
    ns.RefreshUI()
    ns.FlushUI()
  end)
  return row.chk
end

local function NewListRow(host, i, onSelect, Update)
  local row = CreateFrame("Button", nil, host)
  row:SetHeight(ROW_H)
  row:SetPoint("TOPLEFT", 0, -HEAD_H - (i - 1) * ROW_H)
  row:SetPoint("TOPRIGHT", 0, -HEAD_H - (i - 1) * ROW_H)
  row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.text:SetPoint("LEFT", 8, 0)
  row.text:SetPoint("RIGHT", -132, 0)
  row.text:SetJustifyH("LEFT")
  row.lvl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.lvl:SetPoint("RIGHT", -100, 0)
  row.lvl:SetWidth(28)
  row.lvl:SetJustifyH("RIGHT")
  row.lvl:SetTextColor(0.62, 0.62, 0.66)

  NewActButton(row)
  NewCheckButton(row)

  row:SetScript("OnClick", function(self)
    if self.entry then
      host.selectedKey = self.entry.key
      Update()
      if onSelect then onSelect(self.entry) end
      ns.FlushUI()
    end
  end)
  host.rows[i] = row
  return row
end

local function HideRowActions(row)
  row.act.owner = nil
  row.act:Hide()
  row.chk.owner = nil
  row.chk:Hide()
end

local function RowLabel(e, selectedKey)
  local prefix = (e.key == selectedKey) and "|cff5cc8ff>|r " or "  "
  local extra = ""
  if ns.unread and ns.unread[e.key] then extra = extra .. " |cffff6060new|r" end
  if e.attempts and e.attempts > 1 then
    extra = extra .. string.format(" |cff888888x%d|r", e.attempts)
  end
  return prefix .. ns.ClassHexFor(e) .. DispName(e) .. "|r" .. extra
end

-- The whisper / mail button and the online check for one row.
local function PaintRowActions(row, e)
  -- ns.CanWhisper decides, so the button only appears where sending is
  -- actually safe: never for someone who already replied or is closed
  -- out, and not again for someone contacted inside the cooldown.
  row.act.owner = e
  -- Gold "mail" at a mailbox, green "send" otherwise. Mail reaches
  -- offline players too, so the online check is hidden then.
  local mailing = ns.MailMode and ns.MailMode()
  if row.act.mailing ~= mailing then
    row.act.mailing = mailing
    if mailing then Style(row.act, 0.32, 0.24, 0.06, 0.95)
    else Style(row.act, 0.13, 0.26, 0.16, 0.95) end
  end
  row.act.label:SetText(mailing and "|cffffd100mail|r"
    or (BegDB.settings.oneClickSend and "send" or "whisper"))
  row.chk.owner = e
  local st = ns.CheckState(e.key)
  row.chk.label:SetText(st == "pending" and "..." or st == "online" and "|cff7fe07fonline|r"
    or st == "offline" and "|cffff6060offline|r" or "check")
  if ns.CanWhisper(e) then
    row.act:Show()
    row.chk:SetShown(not mailing)
  else
    row.act:Hide()
    row.chk:Hide()
  end
end

local function PaintListRow(row, e, selectedKey)
  row.entry = e
  if not e then
    HideRowActions(row)
    row:Hide()
    return
  end
  row:Show()
  row.text:SetText(RowLabel(e, selectedKey))
  row.lvl:SetText(e.level and tostring(e.level) or "?")
  PaintRowActions(row, e)
end

local function ListMaxRows(view, total)
  local maxRows = math.max(1, math.floor(view / ROW_H))
  if total > maxRows then
    -- Keep a strip at the bottom for the counter.
    maxRows = math.max(1, math.floor((view - 14) / ROW_H))
  end
  return maxRows
end

local function ListFooter(host, total, maxRows)
  if total > maxRows then
    host.more:SetText(string.format("%d-%d of %d, scroll for more",
      host.offset + 1, math.min(total, host.offset + maxRows), total))
    host.more:Show()
  else
    host.more:Hide()
  end

  if total == 0 then
    host.empty:SetText(Sanitize(host.emptyText))
    host.empty:Show()
  else
    host.empty:Hide()
  end
end

local function MakeList(parent, onSelect)
  local host = NewListHost(parent)
  AddListHeaders(host)
  function host.PaintHead() PaintListHead(host) end

  local function Update()
    host.PaintHead()
    local view = (host:GetHeight() or 0) - HEAD_H
    local total = #host.data
    local maxRows = ListMaxRows(view, total)
    local maxOff = math.max(0, total - maxRows)
    if host.offset > maxOff then host.offset = maxOff end
    if host.offset < 0 then host.offset = 0 end

    for i = 1, maxRows do
      local row = host.rows[i] or NewListRow(host, i, onSelect, Update)
      PaintListRow(row, host.data[host.offset + i], host.selectedKey)
    end

    for i = maxRows + 1, #host.rows do
      local row = host.rows[i]
      row.entry = nil
      HideRowActions(row)
      row:Hide()
    end

    ListFooter(host, total, maxRows)
  end

  host:SetScript("OnMouseWheel", function(_, delta)
    host.offset = host.offset - delta
    Update()
  end)
  host:SetScript("OnSizeChanged", Update)

  function host:SetEmptyText(text)
    self.emptyText = text or ""
    Update()
  end
  function host:SetData(data)
    self.data = data or {}
    Update()
  end
  function host:Select(key)
    self.selectedKey = key
    Update()
  end
  return host
end

----------------------------------------------------------------------
-- Slice chips
----------------------------------------------------------------------

-- Chip width and how many fit on the row.
local function ChipLayout(panel, n)
  -- GetWidth() returns 0, not nil, on an unlaid-out frame, so an `or` default
  -- can never fire. Check for both.
  local pw = panel:GetWidth()
  if not pw or pw <= 0 then pw = 740 end
  local avail = pw - 52 - 12
  local gap = 4
  local w = 58
  if n > 0 then
    w = math.floor((avail - gap * (n - 1)) / n)
    if w > 58 then w = 58 end
    if w < 26 then w = 26 end
  end
  local fits = math.floor((avail + gap) / (w + gap))
  local show = math.min(n, math.max(fits, 0))
  return w, gap, show
end

local function NewChip(panel)
  local chip = CreateFrame("Frame", nil, panel, BACKDROP)
  chip:SetHeight(18)
  chip.text = chip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  chip.text:SetPoint("CENTER")
  return chip
end

local function PaintChip(chip, s, i, done, nextIdx)
  chip.text:SetText(string.format("%d-%d", s[1], s[2]))
  if i <= done then
    Style(chip, 0.09, 0.20, 0.11, 0.95)
    chip.text:SetTextColor(0.50, 0.85, 0.50)
  elseif i == nextIdx then
    Style(chip, 0.13, 0.30, 0.44, 1)
    chip.text:SetTextColor(1, 1, 1)
  else
    Style(chip, 0.08, 0.08, 0.09, 0.95)
    chip.text:SetTextColor(0.52, 0.52, 0.56)
  end
end

local function ChipsMore(panel, chips, show, n)
  if not panel.more then
    panel.more = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.more:SetTextColor(DIM[1], DIM[2], DIM[3])
  end
  if show > 0 and show < n then
    panel.more:ClearAllPoints()
    panel.more:SetPoint("LEFT", chips[show], "RIGHT", 6, 0)
    panel.more:SetText(string.format("+%d more", n - show))
    panel.more:Show()
  else
    panel.more:Hide()
  end
end

-- A chip per slice the player defined: dim when pending, blue when next,
-- green when done. This is the whole plan, visible at a glance.
local function RenderChips(panel, slices, done, nextIdx)
  local chips = panel.chips
  local n = #slices
  local w, gap, show = ChipLayout(panel, n)

  for i = 1, show do
    local chip = chips[i]
    if not chip then
      chip = NewChip(panel)
      chips[i] = chip
    end
    chip:ClearAllPoints()
    chip:SetPoint("TOPLEFT", 52 + (i - 1) * (w + gap), -52)
    chip:SetWidth(w)
    PaintChip(chip, slices[i], i, done, nextIdx)
    chip:Show()
  end

  for i = show + 1, #chips do chips[i]:Hide() end
  ChipsMore(panel, chips, show, n)
end

ns.W.MakeList, ns.W.RenderChips = MakeList, RenderChips
