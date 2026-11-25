-- BegBuddy / UIAlerts.lua
-- In-game 1-click smart reply & post-trade close-out UI:
--   1) Post-Trade Close-Out Toast (BegBuddyTradeToast): 1-click "Thanks + Leave (+ Friend)".
--   2) Floating Smart Reply Queue (BegBuddySmartReplyFrame): pooled, scrollable FIFO queue
--      showing ALL pending incoming whispers with intent badges & 1-click reply buttons per row.
--   3) Embedded Smart Auto-Reply Bar inside BegBuddy's main window detail pane (W.BuildSmartBar /
--      W.PaintSmartBar) so you can 1-click auto-reply directly inside BegBuddy too.
-- 100% ToS-safe: every whisper, invite, leave, or friend call runs strictly on a human click.

local _, ns = ...

local W = ns.W
local BACKDROP, DIM, Style, Sanitize = W.BACKDROP, W.DIM, W.Style, W.Sanitize
local WithIcon, MakeButton = W.WithIcon, W.MakeButton

----------------------------------------------------------------------
-- Thank-You Formatting & 2-Man Party Safety Guard
----------------------------------------------------------------------

function ns.RenderThankYou(contact, copper, units, summary)
  local s = BegDB and BegDB.settings or {}
  local threshold = tonumber(s.postTradeBigThreshold) or 10000
  local isBig = (tonumber(copper) or 0) >= threshold and threshold > 0
  local tpl = isBig and (s.postTradeBigThankYou or "") or (s.postTradeThankYou or "")
  if tpl == "" then tpl = "tysm {name}!! appreciate the {gift} so much!" end
  local giftStr = (type(summary) == "string" and summary ~= "") and summary or "the help"
  local goldStr = (tonumber(copper) or 0) > 0 and (ns.Coins and ns.Coins(copper) or tostring(copper)) or ""
  local itemsStr = (tonumber(units) or 0) > 0 and (tostring(units) .. " item(s)") or ""

  local out = tpl
    :gsub("{gift}",  (giftStr:gsub("%%", "%%%%")))
    :gsub("{gold}",  (goldStr:gsub("%%", "%%%%")))
    :gsub("{items}", (itemsStr:gsub("%%", "%%%%")))
  if ns.FillTemplateText then
    out = ns.FillTemplateText(contact, out, true)
  end
  return out, isBig
end

-- True when currently in a 2-person party whose other member is this contact.
-- Protects real 5-man dungeon / raid groups from ever being auto-left.
function ns.IsTwoManPartyWith(contact)
  if not contact then return false end
  if not (IsInGroup and IsInGroup()) then return false end
  if IsInRaid and IsInRaid() then return false end
  local n = type(GetNumGroupMembers) == "function" and tonumber((GetNumGroupMembers())) or 0
  if n ~= 2 then return false end
  local bare = contact.name or ns.ShortName(contact.full)
  if type(UnitInParty) == "function" and bare then
    local ok, inP = pcall(UnitInParty, bare)
    if ok and ns.Readable(inP) and inP then return true end
  end
  return false
end

----------------------------------------------------------------------
-- Shared Styling & Tooltip Helpers
----------------------------------------------------------------------

local TONE_PALETTE = {
  go      = { bg = { 0.10, 0.42, 0.20 }, hi = { 0.15, 0.56, 0.28 }, bd = { 0.30, 0.85, 0.45 } },
  warn    = { bg = { 0.45, 0.24, 0.06 }, hi = { 0.58, 0.32, 0.09 }, bd = { 0.95, 0.55, 0.15 } },
  danger  = { bg = { 0.44, 0.11, 0.11 }, hi = { 0.58, 0.16, 0.16 }, bd = { 0.92, 0.30, 0.30 } },
  neutral = { bg = { 0.13, 0.16, 0.22 }, hi = { 0.20, 0.25, 0.34 }, bd = { 0.32, 0.45, 0.62 } },
  plain   = { bg = { 0.12, 0.12, 0.14 }, hi = { 0.20, 0.20, 0.24 }, bd = { 0.18, 0.18, 0.21 } },
}

local function ApplyTone(b, tone)
  local pal = TONE_PALETTE[tone] or TONE_PALETTE.plain
  b.tonePal = pal
  if b.SetBackdropColor then b:SetBackdropColor(pal.bg[1], pal.bg[2], pal.bg[3], 0.98) end
  if b.SetBackdropBorderColor then b:SetBackdropBorderColor(pal.bd[1], pal.bd[2], pal.bd[3], 1) end
end

local function BindSmartTooltip(b, getContext)
  b:SetScript("OnEnter", function(self)
    local pal = self.tonePal or TONE_PALETTE.plain
    if self.SetBackdropColor then self:SetBackdropColor(pal.hi[1], pal.hi[2], pal.hi[3], 1) end
    local act, contact = getContext(self)
    if not act or not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(tostring(act.label or "Smart Action"), 1, 0.82, 0)
    if act.reply and act.reply ~= "" then
      local who = contact and contact.name or "player"
      GameTooltip:AddLine("Whispers " .. tostring(who) .. ":", 0.55, 0.85, 1.0)
      GameTooltip:AddLine('"' .. tostring(act.reply) .. '"', 1, 1, 1, true)
    end
    local extras = {}
    if act.invite then extras[#extras + 1] = "Invites to party" end
    if act.leave then extras[#extras + 1] = "Leaves group" end
    if act.decline then extras[#extras + 1] = "Marks Declined" end
    if act.block then extras[#extras + 1] = "Marks Blocked" end
    if act.open then extras[#extras + 1] = "Opens contact in BegBuddy" end
    if #extras > 0 then
      GameTooltip:AddLine(table.concat(extras, " + "), 0.50, 0.95, 0.50, true)
    end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function(self)
    local pal = self.tonePal or TONE_PALETTE.plain
    if self.SetBackdropColor then self:SetBackdropColor(pal.bg[1], pal.bg[2], pal.bg[3], 0.98) end
    if GameTooltip then GameTooltip:Hide() end
  end)
end

local function MakeAlertFrame(name, width, height, borderR, borderG, borderB, defaultY)
  local f = CreateFrame("Frame", name, UIParent, BACKDROP)
  f:SetSize(width, height)
  f:SetPoint("TOP", UIParent, "TOP", 0, defaultY)
  f:SetFrameStrata("HIGH")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetClampedToScreen(true)
  Style(f, 0.05, 0.06, 0.08, 0.96)
  if f.SetBackdropBorderColor then f:SetBackdropBorderColor(borderR, borderG, borderB, 1) end
  f:Hide()
  return f
end

local function ScheduleAutoHide(frame)
  local sec = tonumber(BegDB and BegDB.settings and BegDB.settings.postTradeAutoHideSec) or 0
  frame.hideToken = (frame.hideToken or 0) + 1
  local tok = frame.hideToken
  if sec > 0 and C_Timer and C_Timer.After then
    C_Timer.After(sec, function()
      if frame.hideToken == tok and frame:IsShown() then frame:Hide() end
    end)
  end
end

local function FormatBadge(intent)
  local m = (ns.SMART_META and ns.SMART_META[intent]) or { badge = "REPLY", color = "b8bac6" }
  return "|cff" .. m.color .. "[" .. m.badge .. "]|r"
end

local function Truncate(s, maxLen)
  s = tostring(s or "")
  if #s <= maxLen then return s end
  return s:sub(1, maxLen - 3) .. "..."
end

----------------------------------------------------------------------
-- 1) Floating Post-Trade Close-Out Toast
----------------------------------------------------------------------

local function BuildTradeToast()
  local f = MakeAlertFrame("BegBuddyTradeToast", 442, 88, 1.0, 0.82, 0.20, -130)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 10, -8)
  title:SetPoint("TOPRIGHT", -34, -8)
  title:SetJustifyH("LEFT")
  f.title = title

  local sub = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  sub:SetPoint("TOPLEFT", 10, -26)
  sub:SetPoint("TOPRIGHT", -10, -26)
  sub:SetJustifyH("LEFT")
  sub:SetTextColor(0.85, 0.86, 0.90)
  f.sub = sub

  local close = MakeButton(f, "X", 22)
  close:SetPoint("TOPRIGHT", -6, -6)
  close:SetScript("OnClick", function() f:Hide() end)
  f.closeBtn = close

  local primary = MakeButton(f, WithIcon("funded", "Thanks + Leave"), 188)
  primary:SetHeight(26)
  primary:SetPoint("BOTTOMLEFT", 10, 10)
  ApplyTone(primary, "go")
  f.primaryBtn = primary

  local thanksOnly = MakeButton(f, WithIcon("whisper", "Thanks only"), 110)
  thanksOnly:SetHeight(26)
  thanksOnly:SetPoint("LEFT", primary, "RIGHT", 6, 0)
  f.thanksBtn = thanksOnly

  local leaveOnly = MakeButton(f, "Leave group", 96)
  leaveOnly:SetHeight(26)
  leaveOnly:SetPoint("LEFT", thanksOnly, "RIGHT", 6, 0)
  f.leaveBtn = leaveOnly

  primary:SetScript("OnClick", function()
    local d = f.data
    if not d or not d.contact then f:Hide(); return end
    if not ns.SendReply(d.contact, d.thankText) then return end
    local s = BegDB and BegDB.settings or {}
    if s.postTradeLeaveGroup ~= false and IsInGroup and IsInGroup() then
      ns.LeaveGroup()
    end
    if s.postTradeAddFriend and d.isBig then
      ns.AddFriendContact(d.contact)
    end
    f:Hide()
  end)

  thanksOnly:SetScript("OnClick", function()
    local d = f.data
    if d and d.contact and not ns.SendReply(d.contact, d.thankText) then return end
    f:Hide()
  end)

  leaveOnly:SetScript("OnClick", function()
    ns.LeaveGroup()
    f:Hide()
  end)

  return f
end

function ns.UI.ShowTradeToast(contact, copper, units, summary, preview)
  if not contact then return end
  local s = BegDB and BegDB.settings or {}
  if not preview and not s.postTradePopup then return end
  if not ns.UI.tradeToast then ns.UI.tradeToast = BuildTradeToast() end
  local f = ns.UI.tradeToast

  local thankText, isBig = ns.RenderThankYou(contact, copper, units, summary)
  local inGroup = IsInGroup and IsInGroup() and true or false
  local willLeave = inGroup and (s.postTradeLeaveGroup ~= false)
  local willFriend = isBig and s.postTradeAddFriend

  f.data = { contact = contact, copper = copper, units = units, summary = summary, thankText = thankText, isBig = isBig }

  local tag = isBig and "|cffffd100BIG DEAL CLOSED!|r " or "|cff7fe07fDEAL CLOSED!|r "
  f.title:SetText(tag .. ns.ClassHexFor(contact) .. Sanitize(contact.name or "?") .. "|r  |cffffd100+" .. Sanitize(summary or "gift") .. "|r")
  f.sub:SetText("|cffb8bac6Reply:|r " .. Sanitize(thankText))

  local primaryLabel = "Send Thanks"
  if willLeave and willFriend then primaryLabel = "Thanks + Leave + Friend"
  elseif willLeave then primaryLabel = "Thanks + Leave"
  elseif willFriend then primaryLabel = "Thanks + Friend" end
  f.primaryBtn:SetLabel(WithIcon("funded", "|cffffffff" .. primaryLabel .. "|r"))
  ApplyTone(f.primaryBtn, "go")

  f.thanksBtn:SetShown(willLeave)
  f.leaveBtn:SetShown(inGroup)
  f:Show()
  ScheduleAutoHide(f)
end

----------------------------------------------------------------------
-- 2) Floating Smart Reply QUEUE (Pooled, Scrollable, Zero-GC)
----------------------------------------------------------------------

local MAX_QUEUE_ROWS = 4
local Q_HEAD_H = 28
local Q_ROW_H  = 58
local Q_ROW_G  = 4

local function BuildQueueRow(parent, idx)
  local row = CreateFrame("Frame", nil, parent, BACKDROP)
  Style(row, 0.08, 0.09, 0.12, 0.96)
  row:SetHeight(Q_ROW_H)
  row:SetPoint("TOPLEFT", 8, -Q_HEAD_H - (idx - 1) * (Q_ROW_H + Q_ROW_G))
  row:SetPoint("TOPRIGHT", -8, -Q_HEAD_H - (idx - 1) * (Q_ROW_H + Q_ROW_G))

  local header = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  header:SetPoint("TOPLEFT", 8, -6)
  header:SetPoint("TOPRIGHT", -32, -6)
  header:SetJustifyH("LEFT")
  row.header = header

  local b1 = MakeButton(row, "", 166)
  b1:SetHeight(22)
  b1:SetPoint("BOTTOMLEFT", 8, 6)
  row.b1 = b1

  local b2 = MakeButton(row, "", 140)
  b2:SetHeight(22)
  b2:SetPoint("LEFT", b1, "RIGHT", 5, 0)
  row.b2 = b2

  local b3 = MakeButton(row, "", 96)
  b3:SetHeight(22)
  b3:SetPoint("LEFT", b2, "RIGHT", 5, 0)
  row.b3 = b3

  local dismiss = MakeButton(row, "x", 22)
  dismiss:SetHeight(22)
  dismiss:SetPoint("BOTTOMRIGHT", -6, 6)
  dismiss:SetScript("OnClick", function()
    if row.entry and row.entry.key then
      ns.SmartReplyRemove(row.entry.key)
    end
  end)
  row.dismissBtn = dismiss

  local function ctxFor(slot)
    return function()
      return row[slot], row.entry and row.entry.contact or nil
    end
  end
  BindSmartTooltip(b1, ctxFor("act1"))
  BindSmartTooltip(b2, ctxFor("act2"))
  BindSmartTooltip(b3, ctxFor("act3"))

  local function wireClick(btn, slot)
    btn:SetScript("OnClick", function()
      local e, act = row.entry, row[slot]
      if not e or not e.contact or not act then return end
      ns.RunSmartAction(e.contact, act, { preview = e.preview })
    end)
  end
  wireClick(b1, "act1")
  wireClick(b2, "act2")
  wireClick(b3, "act3")

  row:Hide()
  return row
end

local function BuildSmartReplyQueueFrame()
  local f = MakeAlertFrame("BegBuddySmartReplyFrame", 474, Q_HEAD_H + Q_ROW_H + 10, 0.36, 0.78, 1.00, -226)
  f.offset = 0
  f.rows = {}

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 10, -7)
  title:SetPoint("TOPRIGHT", -86, -7)
  title:SetJustifyH("LEFT")
  f.title = title

  local close = MakeButton(f, "X", 22)
  close:SetHeight(20)
  close:SetPoint("TOPRIGHT", -6, -4)
  close:SetScript("OnClick", function() f:Hide() end)
  f.closeBtn = close

  local clearBtn = MakeButton(f, "Clear", 48)
  clearBtn:SetHeight(20)
  clearBtn:SetPoint("RIGHT", close, "LEFT", -4, 0)
  clearBtn:SetScript("OnClick", function() ns.SmartReplyClear() end)
  f.clearBtn = clearBtn

  for i = 1, MAX_QUEUE_ROWS do
    f.rows[i] = BuildQueueRow(f, i)
  end

  local footer = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  footer:SetPoint("BOTTOMLEFT", 10, 5)
  footer:SetPoint("BOTTOMRIGHT", -10, 5)
  footer:SetJustifyH("RIGHT")
  footer:SetTextColor(DIM[1], DIM[2], DIM[3])
  footer:Hide()
  f.footer = footer

  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(self, delta)
    local total = ns.SmartReplyCount and ns.SmartReplyCount() or 0
    local maxOff = math.max(0, total - MAX_QUEUE_ROWS)
    self.offset = math.max(0, math.min(maxOff, (self.offset or 0) - delta))
    ns.UI.RefreshSmartQueue()
  end)

  -- Backwards-compatible aliases pointing to row 1.
  f.b1, f.b2, f.b3 = f.rows[1].b1, f.rows[1].b2, f.rows[1].b3
  return f
end

local function PaintQueueRow(row, entry)
  if not entry or not entry.contact then
    row.entry, row.act1, row.act2, row.act3 = nil, nil, nil, nil
    row:Hide()
    return
  end
  local c = entry.contact
  local intent, a1, a2, a3 = ns.SmartReplyActions(c, entry.text)
  entry.intent = intent
  row.entry = entry
  row.data  = { contact = c, incoming = entry.text, intent = intent }
  row.act1, row.act2, row.act3 = a1, a2, a3

  local mult = (entry.count and entry.count > 1) and (" |cff8f8f96(" .. entry.count .. ")|r") or ""
  local snip = Sanitize(Truncate(entry.text, 44))
  row.header:SetText(
    ns.ClassHexFor(c) .. Sanitize(c.name or "?") .. "|r "
    .. FormatBadge(intent) .. mult .. '  |cffd8d8dc"' .. snip .. '"|r'
  )

  row.b1:SetLabel("|cffffffff" .. Sanitize(a1.label) .. "|r")
  ApplyTone(row.b1, a1.tone or (a1.warn and "warn" or "go"))
  row.b2:SetLabel(Sanitize(a2.label))
  ApplyTone(row.b2, a2.tone == "danger" and "danger" or "plain")
  row.b3:SetLabel(Sanitize(a3.label))
  ApplyTone(row.b3, a3.tone == "danger" and "danger" or "plain")
  row:Show()
end

function ns.UI.RefreshSmartQueue(forceShow)
  local queue = ns.smartQueue or {}
  local total = #queue
  local f = ns.UI.smartReply

  -- Keep main-window queue badge synced whenever main window is open.
  if ns.UI.frame and ns.UI.frame:IsShown() and ns.UI.frame.detail and ns.UI.frame.detail.smartBar then
    local qb = ns.UI.frame.detail.smartBar.queueBtn
    if qb then
      qb:SetLabel(total > 0 and ("|cff7fe07fQueue (" .. total .. ")|r") or "Queue")
    end
  end

  if total == 0 then
    if f then
      f.data, f.act1, f.act2, f.act3 = nil, nil, nil, nil
      for i = 1, MAX_QUEUE_ROWS do f.rows[i]:Hide() end
      f:Hide()
    end
    return
  end

  if not f then
    if not forceShow then return end
    f = BuildSmartReplyQueueFrame()
    ns.UI.smartReply = f
  end

  local maxOff = math.max(0, total - MAX_QUEUE_ROWS)
  if (f.offset or 0) > maxOff then f.offset = maxOff end
  if (f.offset or 0) < 0 then f.offset = 0 end

  local vis = math.min(total, MAX_QUEUE_ROWS)
  f.title:SetText(WithIcon("reply", "|cff5cc8ffSmart Reply Queue|r |cffffd100(" .. total .. ")|r"))

  for i = 1, MAX_QUEUE_ROWS do
    local entry = (i <= vis) and queue[f.offset + i] or nil
    PaintQueueRow(f.rows[i], entry)
  end

  -- Keep backwards-compatible top-row aliases fresh.
  f.data = f.rows[1].data
  f.act1, f.act2, f.act3 = f.rows[1].act1, f.rows[1].act2, f.rows[1].act3

  local extraFooter = 0
  if total > MAX_QUEUE_ROWS then
    f.footer:SetText(string.format("Showing %d-%d of %d (scroll wheel for more)",
      f.offset + 1, math.min(total, f.offset + vis), total))
    f.footer:Show()
    extraFooter = 16
  else
    f.footer:Hide()
  end

  f:SetHeight(Q_HEAD_H + vis * (Q_ROW_H + Q_ROW_G) + 4 + extraFooter)
  if forceShow then f:Show() end
end

function ns.UI.ShowSmartReply(contact, incomingText, preview)
  if not contact then return end
  local s = BegDB and BegDB.settings or {}
  local entry = ns.SmartReplyEnqueue(contact, incomingText, preview)
  if not entry then return end
  if preview or s.smartReplyPopup then
    ns.UI.RefreshSmartQueue(true)
  end
end

function ns.UI.OpenSmartQueue()
  local total = ns.SmartReplyCount and ns.SmartReplyCount() or 0
  if total == 0 then
    ns.Print("Smart Reply Queue is empty. Incoming whispers from contacted players land here automatically.")
    return false
  end
  ns.UI.RefreshSmartQueue(true)
  return true
end

function ns.UI.PreviewSmartReplyQueue()
  local samples = {
    {
      contact = { key = "preview:shadowdru", name = "Shadow Dru", classToken = "DRUID", level = 55 },
      text = "haha sure where are you at?",
    },
    {
      contact = { key = "preview:bownel", name = "Bownel Bigjon", classToken = "WARRIOR", level = 60 },
      text = "i just left the city im sorry",
    },
    {
      contact = { key = "preview:frosty", name = "Frosty Mage", classToken = "MAGE", level = 60 },
      text = "can u inv me? think were on diff layers",
    },
  }
  for _, item in ipairs(samples) do
    ns.SmartReplyEnqueue(item.contact, item.text, true)
  end
  ns.UI.RefreshSmartQueue(true)
end

----------------------------------------------------------------------
-- 3) Embedded Smart Auto-Reply Bar inside BegBuddy Main Window
----------------------------------------------------------------------

local SMART_BAR_H = 48

local function SelectNextUnanswered(f, skipKey)
  -- First follow the live Smart Reply Queue (FIFO, instant even before server CHAT_MSG_WHISPER_INFORM echo).
  for _, q in ipairs(ns.smartQueue or {}) do
    if not q.preview and q.contact and q.key ~= skipKey and BegDB.contacts[q.key] then
      f.activeTab = q.contact.status or ns.STATUS.REPLIED
      ns.activeContact = q.contact
      if ns.unread then ns.unread[q.key] = nil end
      ns.RefreshUI()
      return true
    end
  end
  -- Fallback: any Replied contact whose history still has them speaking last.
  local list = ns.FilteredList and ns.FilteredList(ns.STATUS.REPLIED, "", { needsReply = true })
    or ns.SortedList(ns.STATUS.REPLIED)
  for _, entry in ipairs(list) do
    if entry.key ~= skipKey and ns.NeedsReply and ns.NeedsReply(entry) then
      f.activeTab = ns.STATUS.REPLIED
      ns.activeContact = entry
      if ns.unread then ns.unread[entry.key] = nil end
      ns.RefreshUI()
      return true
    end
  end
  return false
end

function W.BuildSmartBar(f)
  local detail = f.detail
  local bar = CreateFrame("Frame", nil, detail, BACKDROP)
  Style(bar, 0.07, 0.08, 0.11, 0.96)
  if bar.SetBackdropBorderColor then bar:SetBackdropBorderColor(0.24, 0.42, 0.56, 1) end
  bar:SetHeight(SMART_BAR_H)
  bar:Hide()

  local label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetPoint("TOPLEFT", 8, -5)
  label:SetPoint("TOPRIGHT", -76, -5)
  label:SetJustifyH("LEFT")
  bar.label = label

  local qBtn = MakeButton(bar, "Queue", 66)
  qBtn:SetHeight(16)
  qBtn:SetPoint("TOPRIGHT", -6, -3)
  qBtn:SetScript("OnClick", function() ns.UI.OpenSmartQueue() end)
  bar.queueBtn = qBtn

  local b1 = MakeButton(bar, "", 166)
  b1:SetHeight(22)
  b1:SetPoint("BOTTOMLEFT", 8, 5)
  bar.b1 = b1

  local b2 = MakeButton(bar, "", 134)
  b2:SetHeight(22)
  b2:SetPoint("LEFT", b1, "RIGHT", 4, 0)
  bar.b2 = b2

  local b3 = MakeButton(bar, "", 92)
  b3:SetHeight(22)
  b3:SetPoint("LEFT", b2, "RIGHT", 4, 0)
  bar.b3 = b3

  local nextBtn = MakeButton(bar, "Next >", 58)
  nextBtn:SetHeight(22)
  nextBtn:SetPoint("LEFT", b3, "RIGHT", 4, 0)
  nextBtn:SetScript("OnClick", function()
    local curKey = ns.activeContact and ns.activeContact.key or nil
    if not SelectNextUnanswered(f, curKey) then
      ns.Print("No other unanswered replies right now.")
    end
  end)
  bar.nextBtn = nextBtn

  local function ctxFor(slot)
    return function() return bar[slot], bar.contact end
  end
  BindSmartTooltip(b1, ctxFor("act1"))
  BindSmartTooltip(b2, ctxFor("act2"))
  BindSmartTooltip(b3, ctxFor("act3"))

  local function wireClick(btn, slot)
    btn:SetScript("OnClick", function()
      local c, act = bar.contact, bar[slot]
      if not c or not act then return end
      if ns.RunSmartAction(c, act) then
        -- When working through Replies, advance smoothly to the next unanswered person.
        if f.activeTab == ns.STATUS.REPLIED and not act.open then
          SelectNextUnanswered(f, c.key)
        else
          ns.RefreshUI()
        end
      end
    end)
  end
  wireClick(b1, "act1")
  wireClick(b2, "act2")
  wireClick(b3, "act3")

  detail.smartBar = bar
  bar.barHeight = SMART_BAR_H
  return bar
end

function W.PaintSmartBar(f, c, usable)
  local bar = f.detail and f.detail.smartBar
  if not bar then return end

  local qCount = ns.SmartReplyCount and ns.SmartReplyCount() or 0
  bar.queueBtn:SetLabel(qCount > 0 and ("|cff7fe07fQueue (" .. qCount .. ")|r") or "Queue")

  local lastIn, unanswered = nil, false
  if c and ns.LastIncomingWhisper then
    lastIn, unanswered = ns.LastIncomingWhisper(c)
  end
  if not c or not lastIn then
    bar.contact, bar.act1, bar.act2, bar.act3 = nil, nil, nil, nil
    if bar.shownState ~= false then
      bar.shownState = false
      bar.sig = nil
      bar:Hide()
      if W.LayoutDetailBottom then W.LayoutDetailBottom(f) end
    end
    return
  end

  local loc = (BegDB and BegDB.settings and BegDB.settings.smartReplyLocation) or ""
  local sig = table.concat({
    tostring(c.key), tostring(c.status or ""), tostring(c.histVer or 0),
    tostring(unanswered), tostring(loc),
  }, "|")

  if bar.sig ~= sig or bar.shownState ~= true then
    bar.sig = sig
    bar.shownState = true
    local intent, a1, a2, a3 = ns.SmartReplyActions(c, lastIn)
    bar.contact = c
    bar.intent = intent
    bar.act1, bar.act2, bar.act3 = a1, a2, a3

    local previewStr = (a1.reply and a1.reply ~= "")
      and ('-> "' .. Sanitize(Truncate(a1.reply, 44)) .. '"')
      or ("-> " .. Sanitize(a1.label))
    local stateTag = unanswered and "|cff7fe07fSmart:|r " or "|cff8f8f96Last:|r "
    bar.label:SetText(stateTag .. FormatBadge(intent) .. " " .. previewStr)

    bar.b1:SetLabel("|cffffffff" .. Sanitize(a1.label) .. "|r")
    ApplyTone(bar.b1, a1.tone or (a1.warn and "warn" or "go"))
    bar.b2:SetLabel(Sanitize(a2.label))
    ApplyTone(bar.b2, a2.tone == "danger" and "danger" or "plain")
    bar.b3:SetLabel(Sanitize(a3.label))
    ApplyTone(bar.b3, a3.tone == "danger" and "danger" or "plain")

    local meta = ns.SMART_META and ns.SMART_META[intent]
    local pal = TONE_PALETTE[meta and meta.tone or "neutral"] or TONE_PALETTE.neutral
    if bar.SetBackdropBorderColor then
      bar:SetBackdropBorderColor(pal.bd[1], pal.bd[2], pal.bd[3], 0.85)
    end
    bar:Show()
    if W.LayoutDetailBottom then W.LayoutDetailBottom(f) end
  end

  local nr = ns.NeedsReplyCount and ns.NeedsReplyCount() or 0
  if nr > 0 then bar.nextBtn:Enable() else bar.nextBtn:Disable() end

  for _, b in ipairs({ bar.b1, bar.b2, bar.b3 }) do
    if usable then b:Enable() else b:Disable() end
  end
end
