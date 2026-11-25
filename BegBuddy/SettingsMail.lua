-- BegBuddy / SettingsMail.lua
-- Settings page "Mail": the mail templates (their own, separate from the whisper ones: a mail has a subject
-- and a longer body that keeps its line breaks), the "open with the mailbox" switch, and results per template.

local _, ns = ...
local S = ns.Settings
local Z = ZipUI
local Sanitize = ns.Sanitize
local ACCENT = { 0.36, 0.78, 1.00 }
local WHITE = { 0.9, 0.9, 0.9 }

local function countColor(fs, n, max)
  fs:SetText(string.format("%d / %d", n, max))
  if n >= max then fs:SetTextColor(1, 0.8, 0.4) else fs:SetTextColor(0.50, 0.85, 0.50) end
end

-- The body can run to several lines, so it sits in a scroll area. Returns its box and scroll frame.
local function bodyEditor(page, y)
  local bg = CreateFrame("Frame", nil, page)
  Z.Box(bg, Z.Colors.bg, Z.Colors.border)
  bg:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
  bg:SetSize(524, 120)
  local sf = CreateFrame("ScrollFrame", nil, bg)
  sf:SetPoint("TOPLEFT", 4, -4)
  sf:SetPoint("BOTTOMRIGHT", -4, 4)
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(self, delta)
    local range = self:GetVerticalScrollRange() or 0
    local v = (self:GetVerticalScroll() or 0) - delta * 28
    self:SetVerticalScroll(math.max(0, math.min(range, v)))
  end)
  local box = CreateFrame("EditBox", nil, sf)
  box:SetMultiLine(true)
  box:SetAutoFocus(false)
  box:SetMaxLetters(ns.MAIL_BODY_MAX)
  box:SetFontObject("ChatFontNormal")
  box:SetSize(508, 110)
  box:SetTextInsets(2, 2, 0, 0)
  sf:SetScrollChild(box)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  -- Keep the line being typed on screen.
  box:SetScript("OnCursorChanged", function(_, _, y2, _, h)
    local top, view = -y2, sf:GetHeight()
    local cur = sf:GetVerticalScroll() or 0
    if top < cur then sf:SetVerticalScroll(top)
    elseif top + h > cur + view then sf:SetVerticalScroll(top + h - view) end
  end)
  -- Clicking anywhere in the box area, not just on text, starts typing.
  bg:EnableMouse(true)
  bg:SetScript("OnMouseDown", function() box:SetFocus() end)
  return box, sf
end

-- Template picker, new copy, delete (asks twice) and the "open with the mailbox" switch.
local function pickerRow(c)
  local p = c.page
  S.Label(p, "Template:", 0, 30, WHITE)
  c.drop = ns.UI.Dropdown(p, 150, function(picked)
    BegDB.settings.activeMailTemplate = picked
    c.load()
  end)
  c.drop:SetPoint("TOPLEFT", p, "TOPLEFT", 60, -26)
  S.Button(p, "New copy", 76, 218, 26, function()
    local base = ns.ActiveMailTemplate()
    local name, n = "Mail copy", 2
    while ns.FindMailTemplate(name) do name = "Mail copy " .. n; n = n + 1 end
    local made, err = ns.AddMailTemplate(name, base and base.subject or "", base and base.body or "")
    if not made then ns.Print(err or "Could not create it.") return end
    BegDB.settings.activeMailTemplate = made.name
    ns.Print("Created mail template '" .. Sanitize(made.name) .. "'. Rename it below.")
    c.load()
  end)
  local del = Z.ConfirmButton(p, "Delete", 70, S.Click(function()
    local ok, err = ns.DeleteMailTemplate(BegDB.settings.activeMailTemplate)
    if not ok then ns.Print(err or "Could not delete it.") return end
    ns.Print("Mail template deleted. Its results stay on the contacts.")
    c.load()
  end))
  del:SetPoint("TOPLEFT", p, "TOPLEFT", 300, -26)
  c.open = Z.Check(p, "Open this window when a mailbox opens",
    function() return BegDB.settings.mailOpenWindow end,
    function(v) BegDB.settings.mailOpenWindow = v end)
  c.open:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -58)
end

-- Subject and body boxes, the {name} / {level} buttons, rename and reset.
local function editorRows(c)
  local p = c.page
  S.Label(p, "Subject:", 0, 150, WHITE)
  c.subj = S.Input(p, 380, 60, 146, ns.MAIL_SUBJECT_MAX)
  c.subjCount = S.Label(p, "", 450, 150)
  S.Label(p, "Body  (Enter makes a new line)", 0, 180, WHITE)
  c.bodyCount = S.Label(p, "", 450, 180)
  c.body, c.bodySf = bodyEditor(p, 198)
  -- {name} / {level} go into whichever box was used last.
  local lastBox = c.body
  c.subj:SetScript("OnEditFocusGained", function(self) lastBox = self end)
  c.body:SetScript("OnEditFocusGained", function(self) lastBox = self end)
  local function insert(tok) lastBox:SetFocus(); lastBox:Insert(tok) end
  S.Label(p, "Insert:", 0, 90, WHITE)
  S.Button(p, "{name}", 62, 50, 86, function() insert("{name}") end)
  S.Button(p, "{level}", 62, 118, 86, function() insert("{level}") end)
  S.Label(p, "goes in the last box you clicked", 190, 90)
  S.Label(p, "Rename to:", 0, 124, WHITE)
  c.nameBox = S.Input(p, 150, 70, 120, 24)
  c.nameBox:SetScript("OnEnterPressed", function(self)
    local ok, err = ns.RenameMailTemplate(BegDB.settings.activeMailTemplate, self:GetText())
    self:ClearFocus()
    if not ok then ns.Print(err or "Could not rename it.") return end
    ns.Print("Renamed.")
    self:SetText("")
    c.load()
  end)
  S.Button(p, "Reset to default", 116, 408, 324, function()
    c.subj:SetText(ns.DEFAULT_MAIL_SUBJECT)
    c.body:SetText(ns.DEFAULT_MAIL_BODY)
    ns.Print("Mail template reset to the default text.")
  end)
end

local function refreshMail(c)
  local tpl = { subject = c.subj:GetText() or "", body = c.body:GetText() or "" }
  countColor(c.subjCount, #tpl.subject, ns.MAIL_SUBJECT_MAX)
  countColor(c.bodyCount, #tpl.body, ns.MAIL_BODY_MAX)
  local name, level, real = ns.SampleIdentity()
  c.prevLbl:SetText(real and ("Preview - exactly what " .. name .. " will get:")
    or "Preview - scan someone and this uses their real name:")
  local subject, body = ns.RenderMail({ name = name, level = level }, tpl)
  if subject == "" then subject = "|cffff6060(no subject - mail will not send)|r" else subject = Sanitize(subject) end
  c.prevText:SetText("|cffffd100" .. subject .. "|r\n" .. Sanitize(body))
end

local function refreshStats(c)
  local active = BegDB.settings.activeMailTemplate
  local lines = {}
  for i, r in ipairs(ns.MailTemplateSummary()) do
    if i > 3 then lines[#lines + 1] = "|cff8f8f96...more in the export.|r" break end
    local mark = (r.name == active) and "|cffffd100>|r " or "  "
    lines[#lines + 1] = string.format("%s%s: %d sent, %s, %s", mark, Sanitize(r.name), r.sent,
      ns.StatusText("replied", string.format("%d replied (%.0f%%)", r.replied, r.replyRate)),
      ns.StatusText("funded", string.format("%d funded (%.0f%%)", r.funded, r.fundRate)))
  end
  if #lines == 0 then lines[1] = "|cff8f8f96No mail sent yet.|r" end
  c.statsText:SetText(table.concat(lines, "\n"))
end

local function loadMail(c)
  local t = ns.ActiveMailTemplate()
  c.loading = true
  c.subj:SetText(t and t.subject or "")
  c.body:SetText(t and t.body or "")
  c.loading = false
  c.subj:SetCursorPosition(0)
  c.body:SetCursorPosition(0)
  c.bodySf:SetVerticalScroll(0)
  local names = {}
  for _, rec in ipairs(BegDB.mailTemplates or {}) do names[#names + 1] = rec.name end
  c.drop:SetItems(names, t and t.name or "(none)")
  c.nameBox:SetText("")
  c.open:Refresh()
  refreshMail(c)
  refreshStats(c)
end

-- Auto-save as you type (not while a load fills the boxes).
local function onTyped(c)
  if not c.loading then
    local t = ns.ActiveMailTemplate()
    if t then
      t.subject = c.subj:GetText() or ""
      t.body = c.body:GetText() or ""
    end
  end
  refreshMail(c)
end

function ns.SettingsMail(page)
  local c = { page = page }
  c.load = function() loadMail(c) end
  S.Note(page, "Sent from a mailbox with Mail next. Saved as you type. Postage is paid per mail.", 0, 0)
  pickerRow(c)
  editorRows(c)
  c.prevLbl = S.Label(page, "", 0, 352)
  c.prevText = S.Note(page, "", 4, 372, 516, { 0.90, 0.90, 0.92 })
  S.Label(page, "Results by mail template", 0, 480, ACCENT)
  c.statsText = S.Note(page, "", 4, 500, 516, { 0.8, 0.8, 0.82 })
  c.subj:SetScript("OnTextChanged", function() onTyped(c) end)
  c.body:SetScript("OnTextChanged", function() onTyped(c) end)
  S.Add("mail", page, {
    Load = c.load, Refresh = function() refreshStats(c) end, subject = c.subj, body = c.body,
    Hide = function() if c.drop.Close then c.drop:Close() end end,
  })
  return 540
end
