-- BegBuddy / UIMain.lua
-- The main window: header, scan panel, tabs, contact list, detail pane, bottom bar.

local ADDON, ns = ...

local W = ns.W
local BACKDROP, ACCENT, DIM, Style = W.BACKDROP, W.ACCENT, W.DIM, W.Style
local WithIcon, MakeButton, MakeScroller = W.WithIcon, W.MakeButton, W.MakeScroller
local MakeZonePicker, MakeList = W.MakeZonePicker, W.MakeList

local function NewMainFrame()
  -- The shell (frame, title, close, Settings button, drag, saved place and lock) is ZipUI's.
  return ZipUI.Window({
    name = "BegBuddyFrame", title = "BegBuddy", icon = ns.ICON, width = 860, height = 630, settings = "begbuddy",
    db = function() BegDB.window = BegDB.window or {}; return BegDB.window end,
  })
end

local function MainHeader(f)
  -- Live Gold/Hour pill front and center in the top bar at all times.
  local gphBtn = CreateFrame("Button", nil, f, BACKDROP)
  Style(gphBtn, 0.20, 0.15, 0.03, 0.96)
  if gphBtn.SetBackdropBorderColor then gphBtn:SetBackdropBorderColor(0.85, 0.68, 0.16, 1) end
  gphBtn:SetHeight(24)
  gphBtn:SetWidth(215)
  gphBtn:SetPoint("LEFT", f.title, "RIGHT", 14, 0)
  gphBtn.text = gphBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  gphBtn.text:SetPoint("CENTER")
  gphBtn.text:SetText(WithIcon("gph", "|cffffd100Gold/hr: 0c|r"))
  gphBtn:SetScript("OnClick", function()
    f.activeTab = "stats"
    ns.RefreshUI()
    ns.FlushUI()
  end)
  gphBtn:SetScript("OnEnter", function(self)
    if self.SetBackdropColor then self:SetBackdropColor(0.28, 0.21, 0.04, 1) end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Gold per Hour (from 1st message sent)", 1, 0.82, 0)
    if ns.GoldPerHour and ns.Coins then
      local _, totalGold, activeSec, firstAt, sessGph, sessGold, sessSec, allActiveGph = ns.GoldPerHour()
      if sessSec and sessSec > 0 then
        GameTooltip:AddLine(string.format("This session: %s / hr  (%s over %.0f min)", ns.Coins(math.floor(sessGph)), ns.Coins(sessGold), sessSec / 60), 0.5, 0.95, 0.5)
      end
      if firstAt then
        GameTooltip:AddLine(string.format("All-time (active): %s / hr  (%s over %.1f active hrs)", ns.Coins(math.floor(allActiveGph or 0)), ns.Coins(totalGold), activeSec / 3600), 1, 1, 1)
      else
        GameTooltip:AddLine("Send your first message to start tracking Gold/hr.", 0.8, 0.8, 0.8)
      end
      local st = ns.Stats()
      local fn = st.funnel
      local gpr = fn.replied > 0 and math.floor(fn.gold / fn.replied) or 0
      GameTooltip:AddLine(string.format("Gold/reply: %s   Items: %d   Funded: %d", ns.Coins(gpr), fn.items or 0, fn.funded or 0), 0.85, 0.85, 0.88)
    end
    GameTooltip:AddLine("Click to open Analytics & Cohorts.", 0.36, 0.78, 1)
    GameTooltip:Show()
  end)
  gphBtn:SetScript("OnLeave", function(self)
    if self.SetBackdropColor then self:SetBackdropColor(0.20, 0.15, 0.03, 0.96) end
    GameTooltip:Hide()
  end)
  f.gphBtn = gphBtn

  local settingsBtn = f.settingsBtn

  -- Top right, next to Settings: out of a party or raid in one click, no menu.
  local leaveBtn = MakeButton(f, "Leave group", 92)
  leaveBtn:SetPoint("RIGHT", settingsBtn, "LEFT", -6, 0)
  leaveBtn:SetScript("OnClick", function() ns.LeaveGroup() end)
  leaveBtn:SetScript("OnEnter", function(self)
    if self.SetBackdropColor then self:SetBackdropColor(0.20, 0.20, 0.24, 1) end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Leave group", 1, 1, 1)
    GameTooltip:AddLine("Leaves your party or raid in one click. /beg leave does the same.", 0.9, 0.9, 0.9, true)
    GameTooltip:Show()
  end)
  leaveBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.leaveBtn = leaveBtn

  -- Whisper or mail. Mail turns on by itself while a mailbox is open; this
  -- switches back to whispers there if you want.
  local modeBtn = MakeButton(f, "", 166)
  modeBtn:SetPoint("RIGHT", leaveBtn, "LEFT", -6, 0)
  modeBtn:SetScript("OnClick", function()
    if not ns.mail.open then
      ns.Print("Mail mode turns on when you open a mailbox.")
      return
    end
    ns.mail.forceWhisper = not ns.mail.forceWhisper
    ns.RefreshUI()
  end)
  f.modeBtn = modeBtn
end

-- Scan panel ------------------------------------------------------
-- Everything about scanning lives in this one box, in the order you use it:
-- where, which ranges, and what the next click does.
local function NewScanPanel(f)
  local panel = CreateFrame("Frame", nil, f, BACKDROP)
  Style(panel, 0.055, 0.055, 0.07, 0.95)
  panel:SetPoint("TOPLEFT", 12, -42)
  panel:SetPoint("TOPRIGHT", -12, -42)
  panel:SetHeight(114)
  panel.chips = {}
  -- If the first RefreshUI ran before the panel had a width, the chips would
  -- otherwise stay hidden until something unrelated triggered a redraw.
  panel:SetScript("OnSizeChanged", function()
    if ns.RefreshUI then ns.RefreshUI() end
  end)

  local panelTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  panelTitle:SetPoint("TOPLEFT", 12, -8)
  panelTitle:SetText("SCAN")
  panelTitle:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])

  local function RowLabel(text, y)
    local l = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    l:SetPoint("TOPLEFT", 12, y)
    l:SetText(text)
    l:SetTextColor(DIM[1], DIM[2], DIM[3])
    return l
  end

  RowLabel("Zones", -30)
  RowLabel("Plan", -56)
  RowLabel("Next", -86)
  return panel
end

local function MakeLevelInput(panel, key, label, width)
  local eb = CreateFrame("EditBox", nil, panel, BACKDROP)
  Style(eb, 0.09, 0.09, 0.12, 1)
  eb:SetSize(width, 22)
  eb:SetAutoFocus(false)
  eb:SetMaxLetters(3)
  eb:SetFontObject("ChatFontNormal")
  eb:SetJustifyH("CENTER")
  eb:SetTextInsets(2, 2, 0, 0)
  local function commit(self)
    self:ClearFocus()
    local v = tonumber(self:GetText())
    if v then
      v = math.max(1, math.min(200, math.floor(v)))
      local set = BegDB.settings
      if key == "minLevel" and set.maxLevel and v > set.maxLevel then
        ns.Print(string.format("Min level can't be above Max level (%d). Raise Max first.", set.maxLevel))
      elseif key == "maxLevel" and set.minLevel and v < set.minLevel then
        ns.Print(string.format("Max level can't be below Min level (%d). Lower Min first.", set.minLevel))
      elseif v ~= set[key] then
        set[key] = v
        ns.Print(string.format("%s set to %d.", label, v))
      end
    end
    self:SetText(tostring(BegDB.settings[key] or ""))
    ns.RefreshUI()
    ns.FlushUI()
  end
  eb:SetScript("OnEnterPressed", commit)
  eb:SetScript("OnEscapePressed", commit)
  eb:SetScript("OnEditFocusLost", commit)
  return eb
end

local function ScanButtons(f, panel)
  local cityDrop = MakeZonePicker(panel, 220)
  cityDrop:SetPoint("TOPLEFT", 52, -26)

  local addZone = MakeButton(panel, WithIcon("here", "Add zone"), 92)
  addZone:SetPoint("LEFT", cityDrop, "RIGHT", 6, 0)
  addZone:SetScript("OnClick", function()
    ns.AddCurrentZone()
    cityDrop:Refresh()
  end)

  -- Inline Min / Max level range directly on the home dashboard.
  local lvlLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  lvlLbl:SetPoint("LEFT", addZone, "RIGHT", 10, 0)
  lvlLbl:SetText(WithIcon("levels", "Lvl:"))
  lvlLbl:SetTextColor(DIM[1], DIM[2], DIM[3])

  local minBox = MakeLevelInput(panel, "minLevel", "Min level", 36)
  minBox:SetPoint("LEFT", lvlLbl, "RIGHT", 4, 0)
  f.minLvlBox = minBox

  local dash = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  dash:SetPoint("LEFT", minBox, "RIGHT", 3, 0)
  dash:SetText("-")
  dash:SetTextColor(DIM[1], DIM[2], DIM[3])

  local maxBox = MakeLevelInput(panel, "maxLevel", "Max level", 36)
  maxBox:SetPoint("LEFT", dash, "RIGHT", 3, 0)
  f.maxLvlBox = maxBox

  local nextZoneBtn = MakeButton(panel, WithIcon("nextzone", "Next zone"), 94)
  nextZoneBtn:SetPoint("LEFT", maxBox, "RIGHT", 8, 0)
  nextZoneBtn:SetScript("OnClick", function()
    ns.NextZone()
    cityDrop:Refresh()
  end)
  f.nextZoneBtn = nextZoneBtn

  -- Limits scans to the ticked classes, each in its class colour. None ticked scans everyone.
  local classDrop = W.MakeClassPicker(panel, 136)
  classDrop:SetPoint("LEFT", nextZoneBtn, "RIGHT", 6, 0)
  f.classDrop = classDrop
  return cityDrop, addZone
end

local function NextLine(f, panel)
  -- Clipped holder: a long line must never spill out of the panel and over the
  -- tab row below it.
  local nextHolder = CreateFrame("Frame", nil, panel)
  nextHolder:SetPoint("TOPLEFT", 52, -86)
  nextHolder:SetPoint("TOPRIGHT", -230, -86)
  nextHolder:SetHeight(16)
  nextHolder:SetClipsChildren(true)
  f.nextHolder = nextHolder

  local nextText = nextHolder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  nextText:SetPoint("TOPLEFT", 0, 0)
  nextText:SetPoint("TOPRIGHT", 0, 0)
  nextText:SetJustifyH("LEFT")
  return nextText
end

local function ScanActions(panel, cityDrop)
  local scanBtn = MakeButton(panel, WithIcon("scan", "Scan next slice"), 150)
  scanBtn:SetPoint("TOPRIGHT", -70, -82)
  scanBtn:SetScript("OnClick", function()
    ns.ScanNextSlice()
    cityDrop:Refresh()
  end)

  local resetBtn = MakeButton(panel, "Reset", 56)
  resetBtn:SetPoint("TOPRIGHT", -8, -82)
  resetBtn:SetScript("OnClick", function() ns.ResetSlices() end)
  return scanBtn, resetBtn
end

local function ScanPanel(f)
  local panel = NewScanPanel(f)
  local cityDrop, addZone = ScanButtons(f, panel)
  local nextText = NextLine(f, panel)
  local scanBtn, resetBtn = ScanActions(panel, cityDrop)

  f.scanPanel = panel
  f.cityDrop  = cityDrop
  f.addZone   = addZone
  f.nextText  = nextText
  f.scanBtn   = scanBtn
  f.resetBtn  = resetBtn
end

local function MainTabs(f)
  local tabRow = CreateFrame("Frame", nil, f)
  tabRow:SetPoint("TOPLEFT", 12, -164)
  tabRow:SetPoint("TOPRIGHT", -12, -164)
  tabRow:SetHeight(24)
  f.tabButtons = {}
  local prev
  for i, tab in ipairs(ns.TABS) do
    local b = MakeButton(tabRow, tab.label, 90)
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0)
    else b:SetPoint("LEFT", 0, 0) end
    local id = tab.id
    b:SetScript("OnClick", function()
      f.activeTab = id
      ns.RefreshUI()
    end)
    f.tabButtons[i] = b
    prev = b
  end
  -- Stats sits apart from the pipeline tabs: it swaps the list and card for the numbers.
  local stats = MakeButton(tabRow, WithIcon("stats", "Analytics"), 96)
  stats:SetPoint("LEFT", prev, "RIGHT", 14, 0)
  stats:SetScript("OnClick", function()
    f.activeTab = "stats"
    ns.RefreshUI()
  end)
  f.statsTab = stats
end

local function MainList(f)
  -- Search + quick filter bar right above the contact list for instant lookup.
  local bar = CreateFrame("Frame", nil, f)
  bar:SetPoint("TOPLEFT", 12, -192)
  bar:SetSize(330, 24)
  f.searchBar = bar
  f.searchQuery = ""
  f.listFilters = { needsReply = false, hasGuild = false }

  local sb = CreateFrame("EditBox", nil, bar, BACKDROP)
  Style(sb, 0.08, 0.08, 0.10, 1)
  sb:SetPoint("TOPLEFT", 0, 0)
  sb:SetSize(148, 22)
  sb:SetAutoFocus(false)
  sb:SetMaxLetters(40)
  sb:SetFontObject("ChatFontNormal")
  sb:SetTextInsets(6, 18, 0, 0)
  local ph = sb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  ph:SetPoint("LEFT", 6, 0)
  ph:SetText("Search name/guild...")
  ph:SetTextColor(0.45, 0.45, 0.50)
  sb.placeholder = ph
  sb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  sb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  sb:SetScript("OnTextChanged", function(self)
    local txt = self:GetText() or ""
    f.searchQuery = txt
    ph:SetShown(txt == "")
    ns.RefreshUI()
  end)
  f.searchBox = sb

  local clr = CreateFrame("Button", nil, sb)
  clr:SetSize(16, 16)
  clr:SetPoint("RIGHT", -2, 0)
  clr.t = clr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  clr.t:SetPoint("CENTER")
  clr.t:SetText("|cff8f8f96x|r")
  clr:SetScript("OnClick", function()
    sb:SetText("")
    f.searchQuery = ""
    sb:ClearFocus()
    ns.RefreshUI()
    ns.FlushUI()
  end)

  local nrBtn = MakeButton(bar, WithIcon("reply", "Reply"), 116)
  nrBtn:SetPoint("LEFT", sb, "RIGHT", 4, 0)
  nrBtn:SetScript("OnClick", function()
    if f.activeTab ~= ns.STATUS.REPLIED then
      f.activeTab = ns.STATUS.REPLIED
      f.listFilters.needsReply = true
    else
      f.listFilters.needsReply = not f.listFilters.needsReply
    end
    ns.RefreshUI()
  end)
  f.needsReplyBtn = nrBtn

  local gBtn = MakeButton(bar, WithIcon("guild", "Guild"), 58)
  gBtn:SetPoint("LEFT", nrBtn, "RIGHT", 4, 0)
  gBtn:SetScript("OnClick", function()
    f.listFilters.hasGuild = not f.listFilters.hasGuild
    ns.RefreshUI()
  end)
  f.hasGuildBtn = gBtn

  local list = MakeList(f, function(entry)
    f.advance = nil
    ns.activeContact = entry
    if ns.unread then ns.unread[entry.key] = nil end
    ns.RefreshUI()
  end)
  list:SetPoint("TOPLEFT", 12, -220)
  list:SetPoint("BOTTOMLEFT", 12, 78)
  list:SetWidth(330)
  f.list = list
end

local function DetailHeader(f)
  local detail = CreateFrame("Frame", nil, f, BACKDROP)
  Style(detail, 0.05, 0.05, 0.06, 0.85)
  detail:SetPoint("TOPLEFT", f.list, "TOPRIGHT", 8, 28)
  detail:SetPoint("BOTTOMRIGHT", -12, 78)
  f.detail = detail

  local dName = detail:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  dName:SetPoint("TOPLEFT", 10, -8)
  dName:SetText("No contact selected")
  detail.name = dName

  local dMeta = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  dMeta:SetPoint("TOPLEFT", dName, "BOTTOMLEFT", 0, -2)
  dMeta:SetTextColor(DIM[1], DIM[2], DIM[3])
  detail.meta = dMeta

  local dStatus = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  dStatus:SetPoint("TOPRIGHT", -10, -8)
  detail.status = dStatus
  return detail
end

-- Two action rows so nothing overflows the pane
local function ActionAdder(detail)
  local rowY = { -52, -78 }
  local cursor = { nil, nil }
  return function(label, width, row, fn)
    local b = MakeButton(detail, label, width)
    b.plainLabel = label
    if cursor[row] == nil then
      b:SetPoint("TOPLEFT", 10, rowY[row])
    else
      b:SetPoint("LEFT", cursor[row], "RIGHT", 4, 0)
    end
    b:SetScript("OnClick", fn)
    cursor[row] = b
    return b
  end
end

-- Once the selected contact leaves the tab you are working through (you
-- closed them out, or their whisper went through), the next one in that tab
-- is selected for you, at the same spot in the list.
local function ArmAdvance(f, c, ttl)
  if not c then return end
  local data = f.list.data or {}
  local idx = 1
  for i, e in ipairs(data) do if e == c then idx = i break end end
  f.advance = { key = c.key, tab = f.activeTab, idx = idx, untilT = GetTime() + (ttl or 1) }
end

local function SetActive(f, status)
  local c = ns.activeContact
  if not c then return end
  ArmAdvance(f, c)
  ns.SetStatus(c, status)
end

local function DetailActions(f, detail)
  local AddAction = ActionAdder(detail)

  detail.sendBtn = AddAction(WithIcon("whisper", "Send whisper"), 112, 1, function()
    local c = ns.activeContact
    if not c then return end
    -- Armed until the send is confirmed, so the next name comes up by itself.
    if ns.WhisperContact(c) then ArmAdvance(f, c, 60) end
  end)

  AddAction(WithIcon("funded", "Funded"), 76, 1, function() SetActive(f, ns.STATUS.FUNDED) end)
  AddAction(WithIcon("archive", "Archive"), 78, 1, function() SetActive(f, ns.STATUS.ARCHIVED) end)
  AddAction(WithIcon("requeue", "Requeue"), 80, 1, function()
    local c = ns.activeContact
    if c and ns.sentAt then ns.sentAt[c.key] = nil end
    SetActive(f, ns.STATUS.QUEUED)
  end)

  AddAction(WithIcon("declined", "Not interested"), 108, 2, function() SetActive(f, ns.STATUS.DECLINED) end)
  AddAction(WithIcon("block", "Block"), 68, 2, function() SetActive(f, ns.STATUS.BLOCKED) end)
  AddAction(WithIcon("history", "History"), 76, 2, function()
    ns.UI.ShowPopout(ns.activeContact)
  end)
  -- For people who talked back: keep them close.
  detail.inviteBtn = AddAction(WithIcon("invite", "Invite"), 66, 2, function()
    ns.InviteContact(ns.activeContact)
  end)
  detail.friendBtn = AddAction(WithIcon("friend", "Add friend"), 86, 2, function()
    ns.AddFriendContact(ns.activeContact)
  end)
end

local function DetailReply(detail)
  -- History
  local history = MakeScroller(detail)
  history:SetPoint("TOPLEFT", 10, -106)
  history:SetPoint("BOTTOMRIGHT", -10, 34)
  detail.history = history

  -- Reply row
  local replyBox = CreateFrame("EditBox", nil, detail, BACKDROP)
  Style(replyBox, 0.09, 0.09, 0.11, 1)
  replyBox:SetHeight(22)
  replyBox:SetPoint("BOTTOMLEFT", 10, 8)
  replyBox:SetPoint("BOTTOMRIGHT", -70, 8)
  replyBox:SetAutoFocus(false)
  replyBox:SetMaxLetters(255)
  replyBox:SetFontObject("ChatFontNormal")
  replyBox:SetTextInsets(6, 6, 0, 0)
  replyBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  detail.reply = replyBox

  local sendBtn = MakeButton(detail, "Send", 56)
  sendBtn:SetPoint("BOTTOMRIGHT", -10, 8)
  sendBtn:SetScript("OnClick", function()
    local c = ns.activeContact
    if not c then return end
    if ns.SendReply(c, replyBox:GetText()) then
      replyBox:SetText("")
      replyBox:ClearFocus()
    end
  end)
  detail.sendReply = sendBtn

  replyBox:SetScript("OnEnterPressed", function(self)
    local c = ns.activeContact
    if not c then return end
    if ns.SendReply(c, self:GetText()) then
      self:SetText("")
      self:ClearFocus()
    end
  end)
end

-- Bottom bar: a "what to do next" hint on top, counters underneath
local function BottomStatus(f)
  local hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hint:SetPoint("BOTTOMLEFT", 12, 54)
  hint:SetPoint("BOTTOMRIGHT", -480, 54)
  hint:SetJustifyH("LEFT")
  hint:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
  f.hint = hint

  local status = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  status:SetPoint("BOTTOMLEFT", 12, 24)
  status:SetPoint("BOTTOMRIGHT", -540, 24)
  status:SetJustifyH("LEFT")
  status:SetTextColor(DIM[1], DIM[2], DIM[3])
  f.status = status
end

local function BottomButtons(f)
  local pauseBtn = MakeButton(f, "Pause", 64)
  pauseBtn:SetPoint("BOTTOMRIGHT", -12, 22)
  pauseBtn:SetScript("OnClick", function()
    BegDB.paused = not BegDB.paused
    if not BegDB.paused then ns.warnCount = 0; ns.firstWarnAt = nil end
    ns.RefreshUI()
  end)
  f.pauseBtn = pauseBtn

  -- Prominent, high-visibility primary CTA: one click, one whisper (or mail).
  local autoBtn = CreateFrame("Button", nil, f, BACKDROP)
  Style(autoBtn, 0.10, 0.42, 0.20, 0.98)
  if autoBtn.SetBackdropBorderColor then autoBtn:SetBackdropBorderColor(0.30, 0.85, 0.45, 1) end
  autoBtn:SetSize(236, 36)
  autoBtn:SetPoint("RIGHT", pauseBtn, "LEFT", -8, 0)
  autoBtn.text = autoBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  autoBtn.text:SetPoint("CENTER")
  autoBtn.text:SetText(WithIcon("auto", "AUTO SEND NEXT"))
  function autoBtn:SetLabel(s) self.text:SetText(s) end
  autoBtn:SetScript("OnEnter", function(self)
    if not self:IsEnabled() or not self.SetBackdropColor then return end
    if self.ctaMode == "mail" then self:SetBackdropColor(0.62, 0.44, 0.10, 1)
    elseif self.ctaMode == "paused" then self:SetBackdropColor(0.45, 0.14, 0.14, 1)
    else self:SetBackdropColor(0.15, 0.56, 0.28, 1) end
  end)
  autoBtn:SetScript("OnLeave", function(self)
    if not self.SetBackdropColor then return end
    if self.ctaMode == "mail" then self:SetBackdropColor(0.48, 0.34, 0.06, 0.98)
    elseif self.ctaMode == "paused" then self:SetBackdropColor(0.35, 0.10, 0.10, 0.95)
    elseif self.ctaMode == "empty" then self:SetBackdropColor(0.14, 0.14, 0.16, 0.90)
    else self:SetBackdropColor(0.10, 0.42, 0.20, 0.98) end
  end)
  autoBtn:SetScript("OnMouseDown", function(self)
    if self:IsEnabled() then self.text:SetPoint("CENTER", 1, -1) end
  end)
  autoBtn:SetScript("OnMouseUp", function(self) self.text:SetPoint("CENTER", 0, 0) end)
  autoBtn:SetScript("OnClick", function()
    if ns.SendNext() then ns.RefreshUI() end
    ns.FlushUI()
  end)
  f.autoBtn = autoBtn
end

local function ClearButton(f)
  -- Empties the Queued tab. Asks first: one stray click would drop a whole scan.
  StaticPopupDialogs["BEGBUDDY_CLEAR_QUEUED"] = {
    text = "Clear every name in Queued? They move to Archived, and Requeue brings any of them back.",
    button1 = "Clear",
    button2 = CANCEL,
    OnAccept = function()
      local n = ns.ClearQueued()
      ns.Print(string.format("Cleared %d queued.", n))
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
  }
  local clearBtn = MakeButton(f, "Clear", 60)
  clearBtn:SetPoint("RIGHT", f.autoBtn, "LEFT", -6, 0)
  clearBtn:SetScript("OnClick", function()
    if (ns.Counts().queued or 0) == 0 then
      ns.Print("Queued is already empty.")
      return
    end
    StaticPopup_Show("BEGBUDDY_CLEAR_QUEUED")
  end)
  f.clearBtn = clearBtn
end

-- Wipes everything BegBuddy saved. Asks once (first click arms it, the second acts) because there is no way back.
local function ClearAllButton(f)
  local label = "Clear all"
  local btn = ZipUI.ConfirmButton(f, label, 74, function() ns.ClearAll() end)
  -- Wide enough for "Click again to confirm" while armed, small again when it is not. It grows to the left.
  local setText = btn.SetText
  function btn:SetText(s)
    setText(self, s)
    self:SetWidth(s == label and 74 or 140)
  end
  btn:SetPoint("RIGHT", f.clearBtn, "LEFT", -6, 0)
  btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Clear all", 1, 1, 1)
    GameTooltip:AddLine("Deletes everything BegBuddy saved: every list, history, counter and player record. "
      .. "It cannot be undone, so it asks once.", 0.9, 0.9, 0.9, true)
    GameTooltip:AddLine("Your quick messages, the window's place and saved profiles are kept. "
      .. "The Clear button next to it only empties Queued.", 0.62, 0.62, 0.66, true)
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.clearAllBtn = btn
end

local function BuildMain()
  local f = NewMainFrame()
  MainHeader(f)
  ScanPanel(f)
  MainTabs(f)
  MainList(f)
  local detail = DetailHeader(f)
  DetailActions(f, detail)
  DetailReply(detail)
  ns.W.MakeStatsPane(f)
  BottomStatus(f)
  BottomButtons(f)
  ClearButton(f)
  ClearAllButton(f)
  ns.W.BuildQuick(f)

  f:HookScript("OnShow", function() ns.RefreshUI() end)
  f:HookScript("OnHide", function()
    if f.cityDrop and f.cityDrop.Close then f.cityDrop:Close() end
    if f.classDrop and f.classDrop.Close then f.classDrop:Close() end
  end)
  -- Keep the top-bar Gold/hr pill fresh every 15s while the window is open.
  local gphElapsed = 0
  f:SetScript("OnUpdate", function(self, dt)
    gphElapsed = gphElapsed + (tonumber(dt) or 0)
    if gphElapsed >= 15 then
      gphElapsed = 0
      if ns.PaintGphBadge then ns.PaintGphBadge(self) end
    end
  end)
  f.activeTab = ns.STATUS.QUEUED
  return f
end

ns.W.BuildMain = BuildMain
