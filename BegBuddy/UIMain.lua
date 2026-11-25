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
    name = "BegBuddyFrame", title = "BegBuddy", icon = ns.ICON, width = 800, height = 600, settings = "begbuddy",
    db = function() BegDB.window = BegDB.window or {}; return BegDB.window end,
  })
end

local function MainHeader(f)
  local sub = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  sub:SetPoint("LEFT", f.title, "RIGHT", 8, 0)
  sub:SetText("one click, one message - never automatic")
  sub:SetTextColor(DIM[1], DIM[2], DIM[3])

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
  local modeBtn = MakeButton(f, "", 170)
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

local function ScanButtons(f, panel)
  local cityDrop = MakeZonePicker(panel, 230)
  cityDrop:SetPoint("TOPLEFT", 52, -26)

  local addZone = MakeButton(panel, WithIcon("here", "Add this zone"), 112)
  addZone:SetPoint("LEFT", cityDrop, "RIGHT", 6, 0)
  addZone:SetScript("OnClick", function()
    ns.AddCurrentZone()
    cityDrop:Refresh()
  end)

  local levelsBtn = MakeButton(panel, WithIcon("levels", "Change levels"), 112)
  levelsBtn:SetPoint("LEFT", addZone, "RIGHT", 6, 0)
  levelsBtn:SetScript("OnClick", function() ns.UI.OpenSettings("scan") end)

  local nextZoneBtn = MakeButton(panel, WithIcon("nextzone", "Next zone"), 96)
  nextZoneBtn:SetPoint("LEFT", levelsBtn, "RIGHT", 6, 0)
  nextZoneBtn:SetScript("OnClick", function()
    ns.NextZone()
    cityDrop:Refresh()
  end)
  f.nextZoneBtn = nextZoneBtn

  -- Limits scans to the ticked classes, each in its class colour. None ticked scans everyone.
  local classDrop = W.MakeClassPicker(panel, 140)
  classDrop:SetPoint("LEFT", nextZoneBtn, "RIGHT", 6, 0)
  f.classDrop = classDrop
  return cityDrop, addZone, levelsBtn
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
  local cityDrop, addZone, levelsBtn = ScanButtons(f, panel)
  local nextText = NextLine(f, panel)
  local scanBtn, resetBtn = ScanActions(panel, cityDrop)

  f.scanPanel = panel
  f.cityDrop  = cityDrop
  f.addZone   = addZone
  f.levelsBtn = levelsBtn
  f.nextText  = nextText
  f.scanBtn   = scanBtn
  f.resetBtn  = resetBtn
end

local function MainTabs(f)
  local tabRow = CreateFrame("Frame", nil, f)
  tabRow:SetPoint("TOPLEFT", 12, -164)
  tabRow:SetPoint("TOPRIGHT", -12, -164)
  tabRow:SetHeight(22)
  f.tabButtons = {}
  local prev
  for i, tab in ipairs(ns.TABS) do
    local b = MakeButton(tabRow, tab.label, 84)
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
  local stats = MakeButton(tabRow, "Stats", 70)
  stats:SetPoint("LEFT", prev, "RIGHT", 16, 0)
  stats:SetScript("OnClick", function()
    f.activeTab = "stats"
    ns.RefreshUI()
  end)
  f.statsTab = stats
end

local function MainList(f)
  local list = MakeList(f, function(entry)
    f.advance = nil
    ns.activeContact = entry
    if ns.unread then ns.unread[entry.key] = nil end
    ns.RefreshUI()
  end)
  list:SetPoint("TOPLEFT", 12, -192)
  list:SetPoint("BOTTOMLEFT", 12, 68)
  list:SetWidth(300)
  f.list = list
end

local function DetailHeader(f)
  local detail = CreateFrame("Frame", nil, f, BACKDROP)
  Style(detail, 0.05, 0.05, 0.06, 0.85)
  detail:SetPoint("TOPLEFT", f.list, "TOPRIGHT", 8, 0)
  detail:SetPoint("BOTTOMRIGHT", -12, 68)
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
  hint:SetPoint("BOTTOMLEFT", 12, 46)
  hint:SetPoint("BOTTOMRIGHT", -100, 46)
  hint:SetJustifyH("LEFT")
  hint:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
  f.hint = hint

  local status = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  status:SetPoint("BOTTOMLEFT", 12, 22)
  status:SetPoint("BOTTOMRIGHT", -394, 22)
  status:SetJustifyH("LEFT")
  status:SetTextColor(DIM[1], DIM[2], DIM[3])
  f.status = status
end

local function BottomButtons(f)
  local pauseBtn = MakeButton(f, "Pause", 60)
  pauseBtn:SetPoint("BOTTOMRIGHT", -12, 18)
  pauseBtn:SetScript("OnClick", function()
    BegDB.paused = not BegDB.paused
    if not BegDB.paused then ns.warnCount = 0; ns.firstWarnAt = nil end
    ns.RefreshUI()
  end)
  f.pauseBtn = pauseBtn

  -- One click, one whisper to the next person in Queued.
  local autoBtn = MakeButton(f, WithIcon("whisper", "Auto: send next"), 160)
  autoBtn:SetPoint("RIGHT", pauseBtn, "LEFT", -6, 0)
  autoBtn:SetScript("OnClick", function()
    if ns.SendNext() then ns.RefreshUI() end
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
  f.activeTab = ns.STATUS.QUEUED
  return f
end

ns.W.BuildMain = BuildMain
