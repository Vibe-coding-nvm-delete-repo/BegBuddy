-- BegBuddy / Mail.lua
-- The mailbox side. While a mailbox is open the send buttons post a mail
-- (subject and body from the active mail template) instead of a whisper.
-- Same rule as whispers: one click, one mail, to one person. Mail reaches
-- people who are offline and anywhere in the world, so it pairs with
-- scanning any zone.

local ADDON, ns = ...

-- WoW: Forever has only the C_CurrencyInfo version; Classic Era has both, with the same arguments and string result.
local GetCoinTextureString = C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString or _G.GetCoinTextureString

ns.mail = {
  open = false,          -- a mailbox is open right now
  forceWhisper = false,  -- the player switched back to whispers at the mailbox
  pending = nil,         -- { key, subject, body, at } until the server answers
  lastError = nil,
  lastResult = nil,      -- one line for the window: what the last mail did
}

local PENDING_TTL = 10   -- seconds to wait for the server before giving up

-- True when the send buttons should mail rather than whisper.
function ns.MailMode()
  return ns.mail.open and not ns.mail.forceWhisper
end

----------------------------------------------------------------------
-- Rendering
----------------------------------------------------------------------

-- Uses the shared 15-variable template engine while keeping line breaks in the body.
function ns.RenderMail(contact, tpl)
  tpl = tpl or ns.ActiveMailTemplate()
  local subject = ns.FillTemplateText(contact, tpl and tpl.subject, true)
  local body = ns.FillTemplateText(contact, tpl and tpl.body, false)
  subject = ns.TrimToBytes(subject, ns.MAIL_SUBJECT_MAX)
  body = ns.TrimToBytes(body, ns.MAIL_BODY_MAX)
  return subject, body
end

----------------------------------------------------------------------
-- Safety checks
----------------------------------------------------------------------

-- SendMail sends whatever is sitting in the Send Mail tab as well: items in
-- the attachment slots, gold, or a cash-on-delivery charge. A begging mail
-- must never carry any of that, so refuse while any of it is set.
local function SendFormIsClean()
  local maxSlots = tonumber(ATTACHMENTS_MAX_SEND) or 12
  local has = type(HasSendMailItem) == "function" and HasSendMailItem or GetSendMailItem
  if type(has) == "function" then
    for i = 1, maxSlots do
      local ok, found = pcall(has, i)
      if ok and found then
        return false, "There is an item in the Send Mail tab. Take it out first, or it would go with the mail."
      end
    end
  end
  if type(GetSendMailMoney) == "function" and (tonumber(GetSendMailMoney()) or 0) > 0 then
    return false, "There is gold set in the Send Mail tab. Clear it first, or it would go with the mail."
  end
  if type(GetSendMailCOD) == "function" and (tonumber(GetSendMailCOD()) or 0) > 0 then
    return false, "Cash on delivery is set in the Send Mail tab. Clear it first."
  end
  return true
end

-- The recipient the way the game's own mail box writes it: no realm suffix
-- for your own realm, the suffix kept for anyone else.
function ns.MailTarget(contact)
  local full = contact.full or contact.name
  if Ambiguate and type(full) == "string" then
    local ok, name = pcall(Ambiguate, full, "mail")
    if ok and type(name) == "string" and name ~= "" then return name end
  end
  return full
end

function ns.MailPostage()
  local p = type(GetSendMailPrice) == "function" and tonumber(GetSendMailPrice()) or nil
  return p or 30
end

-- How many mails the gold on hand pays for.
function ns.MailsAffordable()
  local money = type(GetMoney) == "function" and tonumber(GetMoney()) or 0
  local p = ns.MailPostage()
  if p <= 0 then return 9999 end
  return math.floor(money / p)
end

function ns.CanMail(contact)
  if not ns.mail.open then return false, "Open a mailbox first." end
  local p = ns.mail.pending
  if p and p.at and (GetTime() - p.at) < PENDING_TTL then
    return false, "Waiting for the server to confirm the last mail."
  end
  return ns.CanWhisper(contact)
end

-- Next name for Mail next: top of Queued in screen order. Unlike whispers,
-- someone a check found offline still gets the mail.
function ns.NextToMail()
  local list = ns.SortedList(ns.STATUS.QUEUED)
  local n, first = 0, nil
  for _, c in ipairs(list) do
    if ns.CanWhisper(c) then
      n = n + 1
      first = first or c
    end
  end
  return first, n
end

----------------------------------------------------------------------
-- Sending
----------------------------------------------------------------------

-- The checks before a mail goes out. Prints why and returns true when it is blocked.
local function MailBlocked(contact)
  if BegDB.paused then
    ns.Print("Sending is paused. /beg resume")
    return true
  end
  if ns.inCombat or (InCombatLockdown and InCombatLockdown()) then
    ns.Print("Not during combat.")
    return true
  end
  local allowed, why = ns.CanMail(contact)
  if not allowed then
    ns.Print(why or "Not allowed.")
    return true
  end
  local clean, dirty = SendFormIsClean()
  if not clean then
    ns.Print(dirty)
    return true
  end
  if ns.MailsAffordable() < 1 then
    ns.Print("Not enough money for postage.")
    return true
  end
  if type(SendMail) ~= "function" then
    ns.Print("This client has no SendMail call. Run /beg probe.")
    return true
  end
  return false
end

function ns.MailContact(contact)
  if not contact or MailBlocked(contact) then return false end

  local subject, body = ns.RenderMail(contact)
  if subject == "" then
    ns.Print("The mail template has no subject. Write one in Settings > Mail.")
    return false
  end

  local now = GetTime()
  ns.mail.lastError = nil
  ns.mail.pending = { key = contact.key, subject = subject, body = body, at = now }
  ns.lastLoadedKey = contact.key
  ns.lastLoadedAt  = now
  local ok, err = pcall(SendMail, ns.MailTarget(contact), subject, body)
  if not ok then
    ns.mail.pending = nil
    ns.Print("The mail was refused: " .. tostring(err))
    return false
  end
  -- lastSendAt is left alone on purpose: it arms the whisper path's reading
  -- of server chat lines, and mail has its own answer events.
  ns.sentAt = ns.sentAt or {}
  ns.sentAt[contact.key] = now

  -- If the server never answers, free the button rather than leave it stuck.
  if C_Timer and C_Timer.After then
    C_Timer.After(PENDING_TTL + 0.5, function()
      local p = ns.mail.pending
      if p and p.key == contact.key and p.at == now then
        ns.mail.pending = nil
        ns.mail.lastResult = "|cffff9933No answer about the mail to " .. ns.Sanitize(contact.name) .. ".|r"
        ns.Print("No answer from the server about that mail. Check your Sent mail before resending.")
        if ns.RefreshUI then ns.RefreshUI() end
      end
    end)
  end
  return true
end

function ns.MailNext()
  if not ns.mail.open then
    ns.Print("Open a mailbox first, then click Mail next.")
    return false
  end
  local c, n = ns.NextToMail()
  if not c then
    ns.Print("Nobody left to mail in Queued. Scan for more.")
    return false
  end
  if ns.MailContact(c) then
    ns.Print(string.format("Mailing %s... %d left after this.", tostring(c.name), n - 1))
    return true
  end
  return false
end

----------------------------------------------------------------------
-- Server answers
----------------------------------------------------------------------

local function OnSendSuccess()
  local p = ns.mail.pending
  if not p then return end
  ns.mail.pending = nil
  local c = BegDB.contacts[p.key]
  if not c then return end

  local flatBody = tostring(p.body or ""):gsub("%s*\n+%s*", " ")
  ns.PushHistory(c, "out", "[mail] " .. p.subject .. " - " .. flatBody)
  ns.RecordMailSent(c)
  c.mailedAt = time()

  local st = c.status
  if st == ns.STATUS.QUEUED or st == ns.STATUS.CONTACTED or st == ns.STATUS.ARCHIVED then
    c.attempts = (c.attempts or 0) + 1
    ns.sessionFirstAskAt = ns.sessionFirstAskAt or time()
    if ns.MarkGuildContacted then ns.MarkGuildContacted(c) end
    ns.SetStatus(c, ns.STATUS.CONTACTED)
  elseif ns.RefreshUI then
    ns.RefreshUI()
  end
  local left = select(2, ns.NextToMail())
  ns.mail.lastResult = string.format("|cff7fe07fMailed %s.|r %d left in Queued.", ns.Sanitize(c.name), left)
end

-- The server's own reason, matched against the client's strings so it works
-- in any language.
-- Recipient problems: this person can never get the mail, so archive them.
local RECIPIENT_ERRORS = {
  ERR_MAIL_TARGET_NOT_FOUND = "no such character",
  ERR_PLAYER_WRONG_FACTION = "other faction",
  ERR_MAIL_RECEPIENT_IS_SELF_FOUND_CANNOT_RECEIVE_MAIL = "self-found, cannot receive mail",
  ERR_MAIL_TARGET_CANNOT_RECEIVE_MAIL = "cannot receive mail",
  ERR_MAIL_RECEPIENT_CANT_RECEIVE_MAIL = "cannot receive mail",
  ERR_MAIL_CANT_SEND_REALM = "other realm",
  ERR_MAIL_TO_SELF = "that is you",
}
-- Sender problems: your own character hit a limit, so every further mail
-- would fail the same way. Pause instead of blaming the recipient.
local SENDER_ERRORS = {
  ERR_MAIL_REACHED_CAP = "You hit the game's cap on how many different people you can mail. Wait a while before mailing more.",
  ERR_MAIL_NOT_FRIEND_OR_GUILD = "This character may only mail friends or guild members.",
  ERR_PLAYER_IS_SELF_FOUND_CANNOT_SEND_MAIL = "Self-found characters cannot send mail.",
}

local function Classify(msg)
  if type(msg) ~= "string" then return nil end
  for key, note in pairs(RECIPIENT_ERRORS) do
    if _G[key] == msg then return "recipient", note end
  end
  for key, note in pairs(SENDER_ERRORS) do
    if _G[key] == msg then return "sender", note end
  end
  return nil
end
ns.ClassifyMailError = Classify

local function OnSendFailed()
  local p = ns.mail.pending
  if not p then return end
  ns.mail.pending = nil
  local c = BegDB.contacts[p.key]
  local why = ns.mail.lastError or "the server refused it"
  ns.mail.lastResult = "|cffff6060Mail failed: " .. ns.Sanitize(why) .. "|r"
  local kind, note = Classify(why)

  if kind == "sender" then
    -- Not this person's fault: clear the hold so they are first again later.
    if ns.sentAt then ns.sentAt[p.key] = nil end
    BegDB.paused = true
    ns.Print("|cffff6060Mail sending paused:|r " .. note .. " /beg resume when ready.")
    if c then ns.PushHistory(c, "sys", "mail not sent: " .. why) end
    if ns.RefreshUI then ns.RefreshUI() end
    return
  end
  if not c then return end

  ns.PushHistory(c, "sys", "mail failed: " .. why)
  if kind == "recipient" then
    if ns.sentAt then ns.sentAt[p.key] = nil end
    ns.SetStatus(c, ns.STATUS.ARCHIVED, "cannot be mailed: " .. note)
    ns.Print(string.format("%s cannot be mailed (%s) - archived.", tostring(c.name), why))
    return
  end
  -- Unknown reason: the person keeps the short hold from the send, so the
  -- next click moves on to someone else instead of retrying them at once.
  ns.Print(string.format("Mail to %s failed: %s", tostring(c.name), why))
  if ns.CountWarning then ns.CountWarning() end
  if ns.RefreshUI then ns.RefreshUI() end
end

----------------------------------------------------------------------
-- Inbox: replies and gold from people you mailed
----------------------------------------------------------------------

local function Coins(copper)
  copper = tonumber(copper) or 0
  if type(GetCoinTextureString) == "function" then
    local ok, s = pcall(GetCoinTextureString, copper)
    if ok and type(s) == "string" then return s end
  end
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  return string.format("%dg %ds %dc", g, s, c)
end
ns.Coins = Coins

-- "5g 3s and 2 item(s)": what a gift was, for the card and for chat.
local function GiftText(money, items)
  local gold = money > 0 and Coins(money) or ""
  if items <= 0 then return gold end
  return gold .. (money > 0 and " and " or "") .. items .. " item(s)"
end

-- A mail with gold or items: the person funded you.
local function AnnounceGift(c, subject, money, items)
  local what = GiftText(money, items)
  ns.PushHistory(c, "in", string.format("[mail] %s (+%s)", tostring(subject or ""), what))
  if c.status ~= ns.STATUS.BLOCKED then ns.SetStatus(c, ns.STATUS.FUNDED) end
  ns.Print(string.format("|cffffd100%s sent you %s by mail!|r", tostring(c.name), what))
end

-- Says what a mail was, on the card and in chat.
local function AnnounceMail(c, subject, money, wasReturned, items)
  items = items or 0
  if wasReturned then
    ns.PushHistory(c, "sys", "[mail] sent your mail back")
  elseif money > 0 or items > 0 then
    AnnounceGift(c, subject, money, items)
  else
    ns.PushHistory(c, "in", "[mail] " .. tostring(subject or ""))
    local s = c.status
    if s ~= ns.STATUS.BLOCKED and s ~= ns.STATUS.FUNDED and s ~= ns.STATUS.DECLINED then
      ns.SetStatus(c, ns.STATUS.REPLIED)
    end
    ns.Print(string.format("%s answered your mail.", tostring(c.name)))
  end
end

-- True when this mail was already handled. Gold and items are left out of the key: taking them out of a mail must
-- not make it look new. A mail first seen without gold that now shows gold is handled once more, as gold.
local function MailSeen(c, sig, money)
  local seen = c.mailIn[sig]
  return seen, seen and not (seen ~= "gold" and money > 0)
end

-- Handles one inbox mail for one contact. Returns true when it was new.
local function NoteMail(c, subject, money, wasReturned, items)
  c.mailIn = type(c.mailIn) == "table" and c.mailIn or {}
  money = tonumber(money) or 0
  local sig = tostring(subject) .. "|" .. tostring(wasReturned and true or false)
  local seen, handled = MailSeen(c, sig, money)
  if handled then return false end
  c.mailIn[sig] = money > 0 and "gold" or true
  -- Items count the first time the mail is seen only; a mail that later shows gold adds just the gold.
  items = seen and 0 or (tonumber(items) or 0)
  if not wasReturned then ns.RecordGift(c, money, items, "mail") end
  AnnounceMail(c, subject, money, wasReturned, items)
  ns.unread = ns.unread or {}
  if ns.activeContact ~= c then ns.unread[c.key] = true end
  return true
end

-- The contact a mail sender is, if you mailed them.
local function MailedContact(sender)
  local c = type(sender) == "string" and sender ~= "" and ns.FindContact(sender) or nil
  if c and (c.mailedAt or (c.attempts or 0) > 0) then return c end
end

-- Reads only the headers (sender, subject, gold), never the mail itself, so
-- nothing gets marked as read. Each mail is handled once.
function ns.ScanInbox()
  if type(GetInboxNumItems) ~= "function" or type(GetInboxHeaderInfo) ~= "function" then return end
  local n = tonumber((GetInboxNumItems())) or 0
  local found = 0
  for i = 1, n do
    local _, _, sender, subject, money, _, _, hasItem, _, wasReturned = GetInboxHeaderInfo(i)
    local c = ns.Readable(sender, subject, money) and MailedContact(sender) or nil
    local items = (ns.Readable(hasItem) and (tonumber(hasItem) or (hasItem and 1))) or 0
    if c and NoteMail(c, subject, money, wasReturned, items) then found = found + 1 end
  end
  if found > 0 and ns.RefreshUI then ns.RefreshUI() end
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("MAIL_SHOW")
f:RegisterEvent("MAIL_CLOSED")
f:RegisterEvent("MAIL_SEND_SUCCESS")
f:RegisterEvent("MAIL_FAILED")
f:RegisterEvent("MAIL_INBOX_UPDATE")
f:RegisterEvent("UI_ERROR_MESSAGE")
local function OnUiError(arg1, arg2)
  -- A hidden error line (WoW: Forever) cannot be compared with the mail errors, so it is skipped.
  if not ns.Readable(arg1, arg2) then return end
  -- Classic passes (errorType, message); older builds passed only the message.
  local msg = type(arg2) == "string" and arg2 or (type(arg1) == "string" and arg1) or nil
  local p = ns.mail.pending
  if msg and p and p.at and (GetTime() - p.at) < PENDING_TTL then
    ns.mail.lastError = msg
    -- A known mail error settles it now, even if MAIL_FAILED never follows.
    if Classify(msg) then OnSendFailed() end
  end
end

local function Refresh() if ns.RefreshUI then ns.RefreshUI() end end

local handlers = {
  MAIL_SHOW = function()
    ns.mail.open = true
    ns.mail.forceWhisper = false
    if BegDB.settings.mailOpenWindow and ns.UI and ns.UI.Open then ns.UI.Open() end
    Refresh()
  end,
  MAIL_CLOSED = function()
    ns.mail.open = false
    Refresh()
  end,
  MAIL_SEND_SUCCESS = function() OnSendSuccess() end,
  MAIL_FAILED = function() OnSendFailed() end,
  MAIL_INBOX_UPDATE = function() ns.ScanInbox() end,
  UI_ERROR_MESSAGE = OnUiError,
}

f:SetScript("OnEvent", function(_, event, arg1, arg2)
  local handler = handlers[event]
  if handler then handler(arg1, arg2) end
end)
