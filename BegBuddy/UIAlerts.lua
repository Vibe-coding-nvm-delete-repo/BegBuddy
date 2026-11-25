-- BegBuddy / UIAlerts.lua
-- Two lightweight, draggable, non-focus-stealing in-game floating bars:
--   1) Smart Reply Mini-Bar: pops on incoming whispers with 1-click intent-matched buttons
--      (Reply with location, Invite + Reply, Polite exit + Decline, Mark Declined, Open).
--   2) Post-Trade Close-Out Toast: pops on completed trades with 1-click "Thanks + Leave"
--      (personalized tiered thank-you whisper + optional Leave Group + optional Add Friend).
-- 100% ToS-safe: every whisper/invite/friend send happens strictly on a real human click.

local _, ns = ...

local W = ns.W
local BACKDROP, DIM, Style, Sanitize = W.BACKDROP, W.DIM, W.Style, W.Sanitize
local WithIcon, MakeButton = W.WithIcon, W.MakeButton

----------------------------------------------------------------------
-- Intent Detection & Thank-You Formatting
----------------------------------------------------------------------

local function lower(s) return ns.StrLower(tostring(s or "")) end

local function hasAny(padded, phrases)
  for _, w in ipairs(phrases) do
    if padded:find(" " .. w .. " ", 1, true) then return true end
  end
  return false
end

local DECLINE_WORDS = { "no", "nope", "nah", "fuck", "fck", "stfu", "scam", "beggar", "get a job", "grind", "earn it", "blocked", "ignored", "reported", "broke", "sorry no", "can't", "cant" }
local INVITE_WORDS  = { "inv", "invite", "party", "group" }
local TRADE_WORDS   = { "omw", "on my way", "coming", "here", "trade", "sent", "mailed" }
local WHERE_WORDS   = { "where", "wher", "u at", "you at", "meet", "come to", "at ah", "at bank", "stormwind", "ironforge", "orgrimmar", "location" }
local AMOUNT_WORDS  = { "how much", "how many", "what do u need", "what u need", "silver", "gold", "bag", "bags", "wand" }

function ns.DetectWhisperIntent(text)
  local norm = lower(text):gsub("[^%w']", " "):gsub("%s+", " ")
  local padded = " " .. norm .. " "
  if hasAny(padded, DECLINE_WORDS) then return "decline" end
  if hasAny(padded, INVITE_WORDS)  then return "invite" end
  if hasAny(padded, TRADE_WORDS)   then return "trade" end
  if hasAny(padded, WHERE_WORDS)   then return "location" end
  if hasAny(padded, AMOUNT_WORDS)  then return "amount" end
  return "general"
end

function ns.RenderThankYou(contact, copper, units, summary)
  local s = BegDB and BegDB.settings or {}
  local threshold = tonumber(s.postTradeBigThreshold) or 10000
  local isBig = (tonumber(copper) or 0) >= threshold and threshold > 0
  local tpl = isBig and (s.postTradeBigThankYou or "") or (s.postTradeThankYou or "")
  if tpl == "" then tpl = "tysm {name}!! appreciate the {gift} so much!" end
  local giftStr = (type(summary) == "string" and summary ~= "") and summary or "the help"
  local goldStr = (tonumber(copper) or 0) > 0 and (ns.Coins and ns.Coins(copper) or tostring(copper)) or ""
  local itemsStr = (tonumber(units) or 0) > 0 and (tostring(units) .. " item(s)") or ""

  -- First substitute trade-specific tokens safely, then pass through the 16-var template engine.
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
-- Shared floating toast helpers
----------------------------------------------------------------------

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

local function PaintPrimary(b, r, g, bl, br, bg, bbl)
  if b.SetBackdropColor then b:SetBackdropColor(r, g, bl, 0.98) end
  if b.SetBackdropBorderColor then b:SetBackdropBorderColor(br, bg, bbl, 1) end
end

----------------------------------------------------------------------
-- 1) Floating Post-Trade Close-Out Toast
----------------------------------------------------------------------

local function BuildTradeToast()
  local f = MakeAlertFrame("BegBuddyTradeToast", 442, 88, 1.0, 0.82, 0.20, -130)

  local primary = MakeButton(f, WithIcon("funded", "Thanks + Leave"), 188)
  primary:SetHeight(26)
  primary:SetPoint("BOTTOMLEFT", 10, 10)
  PaintPrimary(primary, 0.10, 0.42, 0.20, 0.30, 0.85, 0.45)
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
    ns.SendReply(d.contact, d.thankText)
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
    if d and d.contact then ns.SendReply(d.contact, d.thankText) end
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
  PaintPrimary(f.primaryBtn, 0.10, 0.42, 0.20, 0.30, 0.85, 0.45)

  f.thanksBtn:SetShown(willLeave)
  f.leaveBtn:SetShown(inGroup)
  f:Show()
  ScheduleAutoHide(f)
end

----------------------------------------------------------------------
-- 2) Floating In-Addon 1-Click Smart Reply Mini-Bar
----------------------------------------------------------------------

local function BuildSmartReplyBar()
  local f = MakeAlertFrame("BegBuddySmartReplyFrame", 450, 92, 0.36, 0.78, 1.00, -230)

  local b1 = MakeButton(f, "", 170)
  b1:SetHeight(26)
  b1:SetPoint("BOTTOMLEFT", 10, 10)
  PaintPrimary(b1, 0.10, 0.42, 0.20, 0.30, 0.85, 0.45)
  f.b1 = b1

  local b2 = MakeButton(f, "", 162)
  b2:SetHeight(26)
  b2:SetPoint("LEFT", b1, "RIGHT", 6, 0)
  f.b2 = b2

  local b3 = MakeButton(f, "Open", 84)
  b3:SetHeight(26)
  b3:SetPoint("LEFT", b2, "RIGHT", 6, 0)
  f.b3 = b3

  local function runAction(act)
    local d = f.data
    if not d or not d.contact or not act then f:Hide(); return end
    local c = d.contact
    if act.invite then ns.InviteContact(c) end
    if act.reply and act.reply ~= "" then ns.SendReply(c, act.reply) end
    if act.decline then ns.SetStatus(c, ns.STATUS.DECLINED, "declined") end
    if act.open then
      ns.activeContact = c
      if ns.unread then ns.unread[c.key] = nil end
      ns.UI.Open()
      if ns.UI.frame then ns.UI.frame.activeTab = c.status or ns.STATUS.REPLIED; ns.RefreshUI() end
    end
    f:Hide()
  end

  b1:SetScript("OnClick", function() runAction(f.act1) end)
  b2:SetScript("OnClick", function() runAction(f.act2) end)
  b3:SetScript("OnClick", function() runAction(f.act3) end)
  return f
end

function ns.SmartReplyActions(contact, incomingText)
  local s = BegDB and BegDB.settings or {}
  local loc = (type(s.smartReplyLocation) == "string" and s.smartReplyLocation ~= "")
    and s.smartReplyLocation or "right outside the Stormwind AH steps"
  local intent = ns.DetectWhisperIntent(incomingText)

  if intent == "decline" then
    return intent,
      { label = "Polite exit + Decline", reply = "all good no worries, gl out there!", decline = true, warn = true },
      { label = "Mark Declined", decline = true },
      { label = "Open", open = true }
  elseif intent == "invite" then
    return intent,
      { label = "Invite + Location", invite = true, reply = "tysm!! inv sent, im " .. loc },
      { label = "Send Location", reply = "tysm! im " .. loc },
      { label = "Open", open = true }
  elseif intent == "location" then
    return intent,
      { label = "Send Location", reply = "tysm! im " .. loc .. ", can i inv u?" },
      { label = "Invite + Location", invite = true, reply = "tysm!! inv sent, im " .. loc },
      { label = "Open", open = true }
  elseif intent == "trade" then
    return intent,
      { label = "Send Thanks!", reply = "tysm!! youre literally the best, appreciate it!" },
      { label = "Invite", invite = true },
      { label = "Open", open = true }
  elseif intent == "amount" then
    return intent,
      { label = "Reply: 1-2s / bag", reply = "honestly even 1-2 silver or a spare bag helps a ton, tysm!" },
      { label = "Send Location", reply = "im " .. loc .. " if u have a sec, tysm!" },
      { label = "Open", open = true }
  end
  return intent,
    { label = "Reply + Location", reply = "haha tysm! im " .. loc .. " if u have a sec" },
    { label = "Invite + Location", invite = true, reply = "tysm!! inv sent, im " .. loc },
    { label = "Open", open = true }
end

function ns.UI.ShowSmartReply(contact, incomingText, preview)
  if not contact then return end
  local s = BegDB and BegDB.settings or {}
  if not preview and not s.smartReplyPopup then return end
  if not ns.UI.smartReply then ns.UI.smartReply = BuildSmartReplyBar() end
  local f = ns.UI.smartReply

  local text = incomingText
  if not text and type(contact.history) == "table" and #contact.history > 0 then
    text = contact.history[#contact.history].text
  end
  text = tostring(text or "")

  local intent, a1, a2, a3 = ns.SmartReplyActions(contact, text)
  f.data = { contact = contact, incoming = text, intent = intent }
  f.act1, f.act2, f.act3 = a1, a2, a3

  local badge = intent == "decline" and " |cffff9933[DECLINE]|r"
    or intent == "location" and " |cff7fe07f[LOCATION]|r"
    or intent == "invite" and " |cff5cc8ff[INVITE]|r"
    or intent == "trade" and " |cffffd100[TRADE]|r"
    or ""
  f.title:SetText(WithIcon("reply", ns.ClassHexFor(contact) .. Sanitize(contact.name or "?") .. "|r whispered" .. badge))
  local snippet = #text > 72 and (text:sub(1, 69) .. "...") or text
  f.sub:SetText('"' .. Sanitize(snippet) .. '"')

  f.b1:SetLabel("|cffffffff" .. a1.label .. "|r")
  if a1.warn then
    PaintPrimary(f.b1, 0.45, 0.24, 0.06, 0.95, 0.55, 0.15)
  else
    PaintPrimary(f.b1, 0.10, 0.42, 0.20, 0.30, 0.85, 0.45)
  end
  f.b2:SetLabel(a2.label)
  f.b3:SetLabel(a3.label)
  f:Show()
  ScheduleAutoHide(f)
end
