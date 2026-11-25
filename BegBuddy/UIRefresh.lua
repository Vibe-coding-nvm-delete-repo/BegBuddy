-- BegBuddy / UIRefresh.lua
-- Redraws the main window from the saved data: the scan panel, tabs, list, detail pane and bottom bar.

local ADDON, ns = ...

local W = ns.W
local WithIcon, Sanitize, RenderChips = W.WithIcon, W.Sanitize, W.RenderChips

local DIR_TAG = {
  ["in"]  = "|cff7fe07fthem|r",
  ["out"] = "|cffffd080you|r",
  ["sys"] = "|cffff8080server|r",
}

-- Only the message body is user data, so only it gets sanitised. Running a
-- whole line through Sanitize doubles the pipes in our own colour codes and
-- prints them as raw markup instead of colouring anything.
local function HistoryLines(contact, stampFormat)
  local lines = {}
  local history = (contact and contact.history) or {}
  for _, h in ipairs(history) do
    local stamp = (date and date(stampFormat, h.t)) or ""
    local tag = DIR_TAG[h.dir] or DIR_TAG.sys
    lines[#lines + 1] = string.format("[%s] %s  %s", stamp, tag, Sanitize(h.text))
  end
  return lines
end
W.HistoryLines = HistoryLines

-- What to tell the player to do next. The scan is one query per click by
-- necessity, so the window has to say what the next click will actually do.
local EMPTY_TEXT = {
  queued    = "Nothing scanned yet.\n\n1. Tick one or more zones with the Zones button above.\n2. Click Scan next slice.\n\nOne click runs one /who query - the client does not allow more than that. When a zone is done the scan moves on to the next one you ticked.",
  contacted = "Nobody contacted yet.\n\nClick send next to a name in Queued (or select it and click Send whisper).",
  replied   = "No replies yet.\n\nIncoming whispers land here automatically and get a 'new' marker.",
  funded    = "Nobody has funded you yet.",
  declined  = "Nobody has said no yet.\n\n'Not interested' moves people here, and they are never re-queued.",
  archived  = "Nothing archived yet.",
  blocked   = "Nobody blocked.",
}

-- The last scan's result while it is still fresh, or nil.
local function LastScanHint()
  local ls = ns.lastScan
  if ls and ls.at and (time() - ls.at) <= 30 then
    local extra = (ls.skipped and ls.skipped > 0)
      and string.format(", %d skipped", ls.skipped) or ""
    return string.format("Last scan: %d result(s), %d new%s.",
      ls.total or 0, ls.added or 0, extra)
  end
end

-- The panel above already says what the next scan will do, so this line is
-- free to report state rather than repeat it.
local function ComputeHint(counts)
  if ns.scan and ns.scan.busy then
    return "Waiting on the server for the query..."
  end

  if #(ns.SelectedZones()) == 0 then
    return "No zones ticked. Click Zones above and tick where to scan."
  end

  local scanned = LastScanHint()
  if scanned then return scanned end

  if ((counts or {}).queued or 0) > 0 then
    if BegDB.settings.oneClickSend then
      return "Click send next to a name. One click, one whisper."
    end
    return "Click whisper next to a name to load the message, then press Enter."
  end

  return "Ready. The panel above shows what the next scan will do."
end

-- At a mailbox the hint line is about mail: postage, what the gold pays
-- for, and how the last mail went. Built from safe parts, so not sanitised.
local function MailHint()
  if not (ns.MailMode and ns.MailMode()) then return nil end
  local parts = {}
  if ns.mail.pending then
    parts[#parts + 1] = "|cffffd100Sending...|r"
  elseif ns.mail.lastResult then
    parts[#parts + 1] = ns.mail.lastResult
  else
    parts[#parts + 1] = "|cffffd100Mailbox open:|r Mail next sends the mail template to the top of Queued."
  end
  parts[#parts + 1] = string.format("|cff8f8f96postage %s, gold for %d more|r",
    ns.Coins(ns.MailPostage()), ns.MailsAffordable())
  return table.concat(parts, "   ")
end

-- Callers can fire this as often as they like: the real redraw happens once on
-- the next frame. Whisper events arrive in bursts (send, status change, reply)
-- and this collapses them into a single pass.
function ns.RefreshUI()
  if ns.refreshQueued then return end
  ns.refreshQueued = true
  local scheduled = false
  if C_Timer and C_Timer.After then
    -- Guarded: if scheduling throws, the flag must not be left set or every
    -- later redraw would be silently dropped for the rest of the session.
    scheduled = pcall(C_Timer.After, 0, function()
      if not ns.refreshQueued then return end   -- already drawn by FlushUI
      ns.refreshQueued = false
      ns.RefreshUINow()
    end)
  end
  if not scheduled then
    ns.refreshQueued = false
    ns.RefreshUINow()
  end
end

-- Draws a pending redraw right now, in the frame of the click that caused it.
function ns.FlushUI()
  if not ns.refreshQueued then return end
  ns.refreshQueued = false
  ns.RefreshUINow()
end

local function PaintPopout()
  local p = ns.UI.popout
  if p and p:IsShown() and p.contact then
    if BegDB.contacts[p.contact.key] then
      ns.UI.ShowPopout(p.contact)
    else
      p:Hide()
    end
  end
end

local function PaintZones(f)
  local zones = ns.SelectedZones()
  local citySig = table.concat(zones, "\1") .. "\2" .. tostring(ns.GetSelectedCity())
  if f.citySig ~= citySig then
    f.citySig = citySig
    local label
    if #zones == 0 then
      label = "|cffff8080No zones ticked - click to pick|r"
    else
      local shown = {}
      for i = 1, math.min(#zones, 3) do shown[i] = Sanitize(zones[i]) end
      label = string.format("|cffffd100%d zone%s|r: %s%s", #zones, #zones == 1 and "" or "s",
        table.concat(shown, ", "), #zones > 3 and string.format(" +%d", #zones - 3) or "")
    end
    f.cityDrop.label:SetText(WithIcon("zones", label))
    f.cityDrop:Refresh()
  end
  if #zones > 1 then f.nextZoneBtn:Enable() else f.nextZoneBtn:Disable() end
end

-- The class picker's button text (only rebuilt when the picks change).
local function PaintClass(f)
  f.classDrop:SetPicked()
end

local function PaintPlan(f)
  local done = ns.ScanProgress()
  local slices = ns.BuildSlices()
  local planSig = tostring(f.scanPanel:GetWidth()) .. "|" .. done .. "|" .. #slices
  for i = 1, #slices do
    planSig = planSig .. "|" .. slices[i][1] .. "-" .. slices[i][2]
  end
  if f.scanPanel.planSig ~= planSig then
    f.scanPanel.planSig = planSig
    RenderChips(f.scanPanel, slices, done, done + 1)
  end
  f.nextText:SetText(ns.NextStepText())
end

local function PaintTabs(f, counts)
  for i, tab in ipairs(ns.TABS) do
    local b = f.tabButtons[i]
    if b then
      local n = counts[tab.id] or 0
      b:SetLabel(ns.StatusText(tab.id, n > 0 and (tab.label .. " " .. n) or tab.label))
      local on = (tab.id == f.activeTab)
      b.activeTab = on
      if b.SetBackdropColor then
        if on then b:SetBackdropColor(0.16, 0.30, 0.40, 1)
        else b:SetBackdropColor(0.12, 0.12, 0.14, 0.95) end
      end
    end
  end
end

-- The Stats tab swaps the list and the card for the numbers; any other tab brings them back.
local function ShowTabBody(f)
  local stats = f.activeTab == "stats"
  f.list:SetShown(not stats)
  f.detail:SetShown(not stats)
  f.statsPane:SetShown(stats)
  if f.statsTab then
    f.statsTab.activeTab = stats
    if f.statsTab.SetBackdropColor then
      if stats then f.statsTab:SetBackdropColor(0.16, 0.30, 0.40, 1) else f.statsTab:SetBackdropColor(0.12, 0.12, 0.14, 0.95) end
    end
  end
  return stats
end

local function PaintList(f)
  local active = f.activeTab or ns.STATUS.QUEUED
  local listData = ns.SortedList(active)
  local adv = f.advance
  if adv then
    local cur = ns.activeContact
    if not cur or cur.key ~= adv.key or adv.tab ~= active or GetTime() > adv.untilT then
      f.advance = nil
    elseif cur.status ~= active then
      f.advance = nil
      local nextC = listData[math.min(adv.idx, #listData)]
      ns.activeContact = nextC
      if nextC and ns.unread then ns.unread[nextC.key] = nil end
    end
  end
  f.list:SetEmptyText(EMPTY_TEXT[active] or "Nothing here yet.")
  f.list:SetData(listData)
  if ns.activeContact then f.list:Select(ns.activeContact.key) end
end

local function ContactMeta(c)
  local bits = {}
  if c.level then bits[#bits + 1] = "level " .. tostring(c.level) end
  if c.class then bits[#bits + 1] = tostring(c.class) end
  if c.zone  then bits[#bits + 1] = tostring(c.zone) end
  if c.status then bits[#bits + 1] = "status: " .. tostring(c.status) end
  if c.attempts and c.attempts > 0 then bits[#bits + 1] = "attempts: " .. tostring(c.attempts) end
  -- an open Copperline offer to this seller (asked from the auction house): the item and the price
  local cl = rawget(_G, "CopperlineAPI")
  local offer = type(cl) == "table" and type(cl.OfferText) == "function" and cl.OfferText(c.name)
  if type(offer) == "string" and offer ~= "" then bits[#bits + 1] = offer end
  return Sanitize(table.concat(bits, "   "))
end

local function PaintContact(f, c)
  local lvlTxt = c.level and ("   |cff8f8f96" .. tostring(c.level) .. "|r") or ""
  f.detail.name:SetText(ns.ClassHexFor(c) .. Sanitize(c.name or "?") .. "|r" .. lvlTxt)
  f.detail.meta:SetText(ContactMeta(c))

  -- Rebuilding this string is the priciest thing in the redraw, and it only
  -- changes when the conversation does.
  local hist = c.history or {}
  local hsig = table.concat({
    c.key, tostring(#hist), tostring(c.histVer or 0),
  }, "|")
  if f.histSig ~= hsig then
    f.histSig = hsig
    local lines = HistoryLines(c, "%H:%M")
    if #lines == 0 then
      lines[1] = "|cff9a9a9aNo messages recorded for this contact yet.|r\n" ..
                 "|cff9a9a9aWhispers are only captured while the addon is loaded, so a reply that arrived before a reload will not appear here.|r"
    end
    f.detail.history:SetText(table.concat(lines, "\n"), #lines, #lines > 0)
  end
  f.detail.status:SetText(c.status and ns.StatusText(c.status) or "")
  local talked = c.status == ns.STATUS.REPLIED or c.status == ns.STATUS.FUNDED
  f.detail.inviteBtn:SetShown(talked)
  f.detail.friendBtn:SetShown(talked)
end

local function PaintNoContact(f)
  f.detail.inviteBtn:Hide()
  f.detail.friendBtn:Hide()
  f.detail.name:SetText("No contact selected")
  f.detail.meta:SetText("")
  if f.histSig ~= nil then
    f.histSig = nil
    f.detail.history:SetText("")
  end
  f.detail.status:SetText("")
end

-- The counters line and the Pause button. Returns true while combat blocks the buttons.
local function PaintStatusLine(f, counts)
  local unlock = BegDB.paused and "|cffff6060PAUSED|r   " or ""
  local blockedNow = ns.inCombat or (InCombatLockdown and InCombatLockdown())
  local combat = blockedNow and "|cffff6060in combat|r   " or ""
  local function Count(id, word)
    return ns.StatusText(id, string.format("%s %d", word, counts[id] or 0))
  end
  f.status:SetText(string.format("%s%s%s   %s   %s   %s",
    unlock, combat, Count("queued", "queued"), Count("contacted", "contacted"),
    Count("replied", "replied"), Count("funded", "funded")))
  f.pauseBtn:SetLabel(BegDB.paused and "|cff7fe07fResume|r" or "Pause")
  return blockedNow
end

local function PaintModeButton(f, mailing)
  if mailing then
    f.modeBtn:SetLabel(WithIcon("mail", "|cffffd100Sending: mail|r"))
  elseif ns.mail and ns.mail.open then
    f.modeBtn:SetLabel(WithIcon("whisper", "Whispers - click for mail"))
  else
    f.modeBtn:SetLabel(WithIcon("whisper", "|cff5cc8ffSending: whispers|r"))
  end
end

local function PaintAutoButton(f, mailing)
  local left
  if mailing then
    left = select(2, ns.NextToMail())
  else
    left = select(2, ns.NextToSend())
  end
  local busyMail = mailing and ns.mail.pending ~= nil
  if BegDB.paused then
    f.autoBtn:SetLabel(WithIcon(mailing and "mail" or "whisper", "|cffff6060Paused - click Resume|r"))
  elseif mailing then
    f.autoBtn:SetLabel(WithIcon("mail", busyMail and "Sending..."
      or string.format("|cffffd100Mail next (%d)|r", left)))
  else
    f.autoBtn:SetLabel(WithIcon("whisper", string.format("Auto: send next (%d)", left)))
  end
  if BegDB.paused or left == 0 or busyMail then f.autoBtn:Disable() else f.autoBtn:Enable() end
end

-- Whisper or mail decides the mode, Auto and send buttons.
local function PaintSendButtons(f)
  local mailing = ns.MailMode and ns.MailMode()
  PaintModeButton(f, mailing)
  PaintAutoButton(f, mailing)
  if mailing then
    f.detail.sendBtn:SetLabel(WithIcon("mail", "Send mail"))
  else
    f.detail.sendBtn:SetLabel(WithIcon("whisper",
      BegDB.settings.oneClickSend and "Send whisper" or "Load whisper"))
  end
end

local function PaintEnabled(f, blockedNow, hasContact)
  -- The scan button reports what it is doing right now
  local busy = ns.scan and ns.scan.busy
  f.scanBtn:SetLabel(WithIcon("scan", busy and "Waiting..." or "Scan next slice"))
  if blockedNow or busy then f.scanBtn:Disable() else f.scanBtn:Enable() end

  if blockedNow then
    f.resetBtn:Disable(); f.addZone:Disable(); f.nextZoneBtn:Disable()
    f.detail.reply:Disable(); f.detail.sendReply:Disable(); f.detail.sendBtn:Disable()
  else
    f.resetBtn:Enable(); f.addZone:Enable()
    if hasContact then
      f.detail.reply:Enable(); f.detail.sendReply:Enable(); f.detail.sendBtn:Enable()
    else
      f.detail.reply:Disable(); f.detail.sendReply:Disable(); f.detail.sendBtn:Disable()
    end
  end
end

function ns.RefreshUINow()
  PaintPopout()

  local f = ns.UI.frame
  if not f or not f:IsShown() then return end

  PaintZones(f)
  PaintClass(f)
  PaintPlan(f)

  local counts = ns.Counts()
  PaintTabs(f, counts)
  local statsOn = ShowTabBody(f)
  if statsOn then W.PaintStats(f) else PaintList(f) end

  local c = ns.activeContact
  local hasContact = c and BegDB.contacts[c.key]
  if statsOn then
    -- nothing to paint on the card while it is hidden
  elseif hasContact then PaintContact(f, c) else PaintNoContact(f) end

  local blockedNow = PaintStatusLine(f, counts)
  PaintSendButtons(f)

  -- Keep the settings pages honest while they sit open beside this window.
  local st = ns.UI.settings
  if st and st:IsShown() then st:Refresh() end

  -- What to do next, spelled out, so the flow is never a guess
  f.hint:SetText(MailHint() or Sanitize(ComputeHint(counts)))

  PaintEnabled(f, blockedNow, hasContact)
  -- Quick messages stay live with nobody open: the chat box may be their target.
  W.PaintQuick(f, not blockedNow)
end
