-- BegBuddy / UIStats.lua
-- The Stats tab: pick what counts as success, see the funnel and the gold, then a sortable table for one breakdown at
-- a time (template, class, level, zone, time of day, day, whisper or mail, ask number). The numbers come from Stats.lua,
-- which keeps them until something changes; this file only paints, and skips painting when nothing it shows changed.

local ADDON, ns = ...

local W = ns.W
local BACKDROP, ACCENT, DIM, Style, MakeButton = W.BACKDROP, W.ACCENT, W.DIM, W.Style, W.MakeButton
local Sanitize = W.Sanitize

local ROWS, ROWS_COHORT, ROW_H = 11, 10, 18
local TOP_STD, TOP_COHORT = 124, 150
local GOLD_HEX, DIM_HEX = "|cffffd100", "|cff6f6f76"

-- key, heading, x, width, left aligned (fits cleanly inside 836px pane)
local COLS = {
  { "label",        "Name",         10, 210, true },
  { "sent",         "Asked",       224,  52 },
  { "replied",      "Replied",     280,  56 },
  { "funded",       "Funded",      340,  54 },
  { "rate",         "Success",     398,  88 },
  { "gold",         "Gold",        490,  90 },
  { "goldPerReply", "Gold/reply",  584,  86 },
  { "goldPerAsk",   "Gold/ask",    674,  82 },
  { "items",        "Items",       760,  58 },
}

----------------------------------------------------------------------
-- Text
----------------------------------------------------------------------

-- 12g 40s, 40s 5c, 7c; a dash for nothing.
local function Money(copper)
  copper = math.floor(tonumber(copper) or 0)
  if copper <= 0 then return "-" end
  local g, s, c = math.floor(copper / 10000), math.floor((copper % 10000) / 100), copper % 100
  if g > 0 then return string.format("%dg %ds", g, s) end
  if s > 0 then return string.format("%ds %dc", s, c) end
  return c .. "c"
end

local function Short(copper)
  if copper >= 10000 then return string.format("%dg", math.floor(copper / 10000)) end
  return string.format("%ds", math.floor(copper / 100))
end

local function Pct(a, b)
  if b <= 0 then return "0%" end
  return string.format("%.0f%%", a / b * 100)
end

local function Span(mins)
  if not mins then return "none yet" end
  if mins < 90 then return string.format("%d min", math.floor(mins + 0.5)) end
  if mins < 2880 then return string.format("%.1f h", mins / 60) end
  return string.format("%.1f days", mins / 1440)
end

local STAGE_WORD = { replied = "replied", funded = "funded" }

local function FunnelLines(st)
  local fn = st.funnel
  local word = STAGE_WORD[st.stage] or ("sent " .. Short(st.goldMin) .. " or more")
  local l1 = string.format("%sFound|r %d   >   %sAsked|r %d (%s of found)   >   %sReplied|r %d (%s of asked)   >   %sFunded|r %d (%s of replied)",
    "|cffd8d8dc", fn.found, "|cff5cc8ff", fn.asked, Pct(fn.asked, fn.found),
    "|cff7fe07f", fn.replied, Pct(fn.replied, fn.asked), GOLD_HEX, fn.funded, Pct(fn.funded, fn.replied))
  local avg = fn.funders > 0 and (fn.gold / fn.funders) or 0
  local gph = ns.GoldPerHour and select(1, ns.GoldPerHour()) or 0
  local gpr = fn.replied > 0 and (fn.gold / fn.replied) or 0
  local l2 = string.format("Gold/hr %s%s|r   Gold %s%s|r (avg %s, %s/reply, %s/ask)   Items %d   Success (%s): %s%d|r (%s)   Reply in %s",
    GOLD_HEX, Money(gph), GOLD_HEX, Money(fn.gold), Money(avg), Money(gpr),
    Money(fn.asked > 0 and fn.gold / fn.asked or 0), fn.items, word, GOLD_HEX, fn.success,
    Pct(fn.success, fn.asked), Span(st.medianReply))
  return l1, l2
end

local function Cells(r, st)
  local dim = r.few and DIM_HEX or ""
  local label = Sanitize(r.label) .. (r.few and "*" or "")
  if r.token and not r.few then label = ns.ClassHex(r.token) .. label .. "|r" elseif r.few then label = DIM_HEX .. label .. "|r" end
  local gCol = r.few and DIM_HEX or GOLD_HEX
  return {
    label = label,
    sent = dim .. r.sent, replied = dim .. r.replied, funded = dim .. r.funded,
    rate = string.format("%s%d (%.1f%%)", dim, r.success, r.rate * 100),
    gold = gCol .. Money(r.gold),
    goldPerReply = gCol .. Money(r.goldPerReply),
    goldPerAsk = gCol .. Money(r.goldPerAsk),
    items = dim .. tostring(r.items or 0),
  }
end

----------------------------------------------------------------------
-- Building the pane
----------------------------------------------------------------------

local function Tint(b, on)
  b.activeTab = on
  if b.SetBackdropColor then
    if on then b:SetBackdropColor(0.16, 0.30, 0.40, 1) else b:SetBackdropColor(0.12, 0.12, 0.14, 0.95) end
  end
end

local function NextStep(list, current)
  for i, v in ipairs(list) do
    if v == current then return list[i % #list + 1] end
  end
  return list[1]
end

-- Success is replied, funded, or gold of at least some amount. A second click on Gold steps the amount up.
local function StageButtons(pane)
  local label = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetPoint("TOPLEFT", 10, -13)
  label:SetText("Success is")
  label:SetTextColor(DIM[1], DIM[2], DIM[3])
  pane.stage = {}
  local x = 68
  for _, def in ipairs({ { "replied", "Replied", 70 }, { "funded", "Funded", 70 }, { "gold", "Gold", 118 } }) do
    local id = def[1]
    local b = MakeButton(pane, def[2], def[3])
    b:SetPoint("TOPLEFT", x, -8)
    b:SetScript("OnClick", function()
      local s = BegDB.settings
      if id == "gold" and s.successStage == "gold" then
        s.successGold = NextStep(ns.STATS_GOLD_STEPS, tonumber(s.successGold) or 1000)
      end
      s.successStage = id
      ns.TouchList()
      ns.RefreshUI()
    end)
    pane.stage[id] = b
    x = x + def[3] + 4
  end
  pane.sample = MakeButton(pane, "", 150)
  pane.sample:SetPoint("TOPRIGHT", -10, -8)
  pane.sample:SetScript("OnClick", function()
    local s = BegDB.settings
    s.statsMinSample = NextStep(ns.STATS_SAMPLE_STEPS, tonumber(s.statsMinSample) or 30)
    ns.TouchList()
    ns.RefreshUI()
  end)
end

local function ViewButtons(pane)
  pane.views = {}
  local x = 10
  for _, v in ipairs(ns.STATS_VIEWS) do
    local w = math.max(46, #v.label * 6 + 18)
    local b = MakeButton(pane, v.label, w)
    b:SetPoint("TOPLEFT", x, -74)
    local id = v.id
    b:SetScript("OnClick", function() BegDB.settings.statsView = id; pane.offset = 0; ns.RefreshUI() end)
    pane.views[id] = b
    x = x + w + 4
  end
end

local function CohortButtons(pane)
  local bar = CreateFrame("Frame", nil, pane)
  bar:SetPoint("TOPLEFT", 10, -100)
  bar:SetPoint("TOPRIGHT", -10, -100)
  bar:SetHeight(22)
  bar:Hide()
  pane.cohortBar = bar
  pane.cohorts = {}
  local x = 0
  for _, cv in ipairs(ns.COHORT_VIEWS) do
    local w = math.max(78, #cv.label * 6 + 18)
    local b = MakeButton(bar, cv.label, w)
    b:SetPoint("TOPLEFT", x, 0)
    local id = cv.id
    b:SetScript("OnClick", function()
      BegDB.settings.statsCohort = id
      pane.offset = 0
      ns.RefreshUI()
    end)
    pane.cohorts[id] = b
    x = x + w + 4
  end
end

local function Headers(pane)
  pane.heads = {}
  for _, col in ipairs(COLS) do
    local b = MakeButton(pane, col[2], col[4])
    b:SetPoint("TOPLEFT", col[3], -100)
    b:SetHeight(20)
    local key = col[1]
    b:SetScript("OnClick", function()
      if pane.sortKey == key then pane.sortDesc = not pane.sortDesc else pane.sortKey, pane.sortDesc = key, key ~= "label" end
      pane.offset = 0
      ns.RefreshUI()
    end)
    pane.heads[key] = b
  end
end

local function NewRow(pane, i)
  local row = CreateFrame("Frame", nil, pane)
  row:SetHeight(ROW_H)
  row:SetPoint("TOPLEFT", 0, -TOP_STD - (i - 1) * ROW_H)
  row:SetPoint("TOPRIGHT", 0, -TOP_STD - (i - 1) * ROW_H)
  row.cells = {}
  for _, col in ipairs(COLS) do
    local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("LEFT", col[3] + 4, 0)
    fs:SetWidth(col[4] - 8)
    fs:SetJustifyH(col[5] and "LEFT" or "RIGHT")
    fs:SetWordWrap(false)
    row.cells[col[1]] = fs
  end
  return row
end

local function LayoutTable(pane, isCohort)
  if pane.lastIsCohort == isCohort then return end
  pane.lastIsCohort = isCohort
  pane.cohortBar:SetShown(isCohort)
  local headY = isCohort and -126 or -100
  local topY  = isCohort and TOP_COHORT or TOP_STD
  for _, col in ipairs(COLS) do
    local b = pane.heads[col[1]]
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", col[3], headY)
  end
  for i = 1, ROWS do
    local row = pane.rows[i]
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, -topY - (i - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", 0, -topY - (i - 1) * ROW_H)
  end
end

function W.MakeStatsPane(f)
  local pane = CreateFrame("Frame", nil, f, BACKDROP)
  Style(pane, 0.055, 0.055, 0.07, 0.95)
  pane:SetPoint("TOPLEFT", 12, -192)
  pane:SetPoint("BOTTOMRIGHT", -12, 78)
  pane:EnableMouseWheel(true)
  pane:Hide()
  pane.offset = 0
  StageButtons(pane)
  pane.funnel = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  pane.funnel:SetPoint("TOPLEFT", 10, -36)
  pane.funnel:SetPoint("TOPRIGHT", -10, -36)
  pane.funnel:SetJustifyH("LEFT")
  pane.funnel:SetHeight(32)
  pane.funnel:SetJustifyV("TOP")
  ViewButtons(pane)
  CohortButtons(pane)
  Headers(pane)
  pane.rows = {}
  for i = 1, ROWS do pane.rows[i] = NewRow(pane, i) end
  pane.foot = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  pane.foot:SetPoint("BOTTOMLEFT", 10, 6)
  pane.foot:SetPoint("BOTTOMRIGHT", -10, 6)
  pane.foot:SetJustifyH("LEFT")
  pane.foot:SetTextColor(DIM[1], DIM[2], DIM[3])
  pane:SetScript("OnMouseWheel", function(_, delta) pane.offset = math.max(0, pane.offset - delta * 3); ns.RefreshUI() end)
  f.statsPane = pane
  return pane
end

----------------------------------------------------------------------
-- Painting
----------------------------------------------------------------------

local function PaintControls(pane, st, view, cohort)
  local s = BegDB.settings
  for id, b in pairs(pane.stage) do Tint(b, st.stage == id) end
  pane.stage.gold:SetLabel("Gold >= " .. Short(st.goldMin))
  pane.sample:SetLabel(string.format("Trust after %d asks", st.minSample))
  for id, b in pairs(pane.views) do Tint(b, id == view) end
  if s.statsView ~= view then s.statsView = view end
  if pane.cohorts then
    for id, b in pairs(pane.cohorts) do Tint(b, id == cohort) end
  end
  for _, col in ipairs(COLS) do
    local key = col[1]
    local title = (key == "label" and view == "cohorts") and "Cohort" or col[2]
    local arrow = (pane.sortKey == key) and (pane.sortDesc and " v" or " ^") or ""
    pane.heads[key]:SetLabel(title .. arrow)
  end
end

local function PaintRows(pane, list, st, isCohort)
  local vis = isCohort and ROWS_COHORT or ROWS
  local n = #list
  pane.offset = math.max(0, math.min(pane.offset, math.max(0, n - vis)))
  for i = 1, ROWS do
    local row = pane.rows[i]
    local r = (i <= vis) and list[pane.offset + i] or nil
    row:SetShown(r ~= nil)
    if r then
      for key, text in pairs(Cells(r, st)) do row.cells[key]:SetText(text) end
    end
  end
  local foot = n == 0 and "Nothing asked yet: send a whisper or a mail and the numbers appear here."
    or string.format("%d-%d of %d.  * = fewer than %d asks, too few to trust (rates sort them last).  Click a heading to sort, scroll for more.",
      pane.offset + 1, math.min(n, pane.offset + vis), n, st.minSample)
  pane.foot:SetText(foot)
end

-- Repaints the Stats pane for the current numbers. Does nothing when nothing shown has changed.
function W.PaintStats(f)
  local pane = f.statsPane
  local st = ns.Stats()
  local view = BegDB.settings.statsView
  if not ns.STATS_VIEW_IDS[view] then view = "template" end
  local isCohort = (view == "cohorts")
  local cohort = BegDB.settings.statsCohort
  if not ns.COHORT_VIEW_IDS[cohort] then cohort = "level_class" end
  local activeKey = isCohort and ("cohorts:" .. cohort) or view
  if pane.sortView ~= activeKey then
    pane.sortView = activeKey
    if isCohort then
      pane.sortKey, pane.sortDesc = "gold", true
    else
      pane.sortKey, pane.sortDesc = ns.StatsDefaultSort(view)
    end
    pane.offset = 0
  end
  local sig = table.concat({ st.sig, activeKey, pane.sortKey, tostring(pane.sortDesc), pane.offset }, "|")
  if pane.paintSig == sig then return end
  pane.paintSig = sig
  LayoutTable(pane, isCohort)
  PaintControls(pane, st, view, cohort)
  pane.funnel:SetText(table.concat({ FunnelLines(st) }, "\n"))
  local rows = isCohort and ns.CohortRows(cohort, pane.sortKey, pane.sortDesc)
    or ns.StatsRows(view, pane.sortKey, pane.sortDesc)
  PaintRows(pane, rows, st, isCohort)
end
