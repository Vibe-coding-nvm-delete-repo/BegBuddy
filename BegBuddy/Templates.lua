-- BegBuddy / Templates.lua
-- Whisper and mail templates, and the per-template analytics.

local _, ns = ...
local DEFAULT_TEMPLATE = ns.DEFAULT_TEMPLATE
local DEFAULT_MAIL_SUBJECT = ns.DEFAULT_MAIL_SUBJECT
local DEFAULT_MAIL_BODY = ns.DEFAULT_MAIL_BODY

----------------------------------------------------------------------
-- Templates and per-template analytics
----------------------------------------------------------------------

local DEFAULT_TEMPLATE_NAME = "Default"

function ns.FindTemplate(name)
  if type(name) ~= "string" or name == "" then return nil end
  for _, t in ipairs(BegDB.templates or {}) do
    if t.name == name then return t end
  end
  return nil
end

-- One-time move from the old single-template layout into a named list.
function ns.MigrateTemplates()
  if type(BegDB.templates) ~= "table" then BegDB.templates = {} end
  if #BegDB.templates > 0 then return end
  BegDB.templates[1] = {
    name = DEFAULT_TEMPLATE_NAME,
    text = BegDB.settings.template or DEFAULT_TEMPLATE,
    sent = 0, replied = 0, funded = 0,
  }
  BegDB.settings.activeTemplate = DEFAULT_TEMPLATE_NAME
end

function ns.ActiveTemplate()
  ns.MigrateTemplates()
  local found = ns.FindTemplate(BegDB.settings.activeTemplate)
  if found then return found end
  local first = BegDB.templates[1]
  BegDB.settings.activeTemplate = first.name
  return first
end

function ns.TemplateText()
  local t = ns.ActiveTemplate()
  return (t and t.text) or BegDB.settings.template or DEFAULT_TEMPLATE
end

function ns.AddTemplate(name, text)
  ns.MigrateTemplates()
  name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then return nil, "Give it a name first." end
  if ns.FindTemplate(name) then return nil, "That name is already in use." end
  BegDB.templates[#BegDB.templates + 1] = {
    name = name, text = text or "", sent = 0, replied = 0, funded = 0,
  }
  return ns.FindTemplate(name)
end

function ns.RenameTemplate(oldName, newName)
  newName = tostring(newName or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if newName == "" then return false, "Give it a name first." end
  local t = ns.FindTemplate(oldName)
  if not t then return false, "No such template." end
  if newName ~= oldName and ns.FindTemplate(newName) then
    return false, "That name is already in use."
  end
  t.name = newName
  if BegDB.settings.activeTemplate == oldName then
    BegDB.settings.activeTemplate = newName
  end
  -- Keep history attached to the renamed template. A mail template may share
  -- the name, so only whisper attributions move.
  for _, c in pairs(BegDB.contacts or {}) do
    if c.templateUsed == oldName and c.templateKind ~= "mail" then c.templateUsed = newName end
  end
  return true
end

function ns.DeleteTemplate(name)
  ns.MigrateTemplates()
  if #BegDB.templates <= 1 then
    return false, "Keep at least one template."
  end
  for i, t in ipairs(BegDB.templates) do
    if t.name == name then
      -- Tombstone the attributions, so a future template that reuses this name
      -- cannot inherit an old conversation's results.
      local tomb = name .. " (deleted)"
      for _, c in pairs(BegDB.contacts or {}) do
        if c.templateUsed == name and c.templateKind ~= "mail" then c.templateUsed = tomb end
      end
      table.remove(BegDB.templates, i)
      if BegDB.settings.activeTemplate == name then
        BegDB.settings.activeTemplate = BegDB.templates[1].name
      end
      return true
    end
  end
  return false, "No such template."
end

-- Called when a whisper actually goes out. The active template takes the
-- credit, and the contact remembers which one was used so replies can be
-- attributed to it later.
function ns.RecordSent(contact)
  local t = ns.ActiveTemplate()
  if t then t.sent = (tonumber(t.sent) or 0) + 1 end
  if contact then
    contact.templateUsed = t and t.name or nil
    contact.templateKind = nil
  end
end

function ns.RecordOutcome(contact, field)
  if not contact or not field then return end
  local name = contact.templateUsed
  if not name then return end
  local t
  if contact.templateKind == "mail" then t = ns.FindMailTemplate(name)
  else t = ns.FindTemplate(name) end
  if t then t[field] = (tonumber(t[field]) or 0) + 1 end
end

----------------------------------------------------------------------
-- Mail templates: a subject and a body, kept apart from the whisper ones
-- so each channel has its own wording and its own results.
----------------------------------------------------------------------

function ns.FindMailTemplate(name)
  if type(name) ~= "string" or name == "" then return nil end
  for _, t in ipairs(BegDB.mailTemplates or {}) do
    if t.name == name then return t end
  end
  return nil
end

function ns.MigrateMailTemplates()
  if type(BegDB.mailTemplates) ~= "table" then BegDB.mailTemplates = {} end
  if #BegDB.mailTemplates > 0 then return end
  BegDB.mailTemplates[1] = {
    name = DEFAULT_TEMPLATE_NAME, subject = DEFAULT_MAIL_SUBJECT, body = DEFAULT_MAIL_BODY,
    sent = 0, replied = 0, funded = 0,
  }
  BegDB.settings.activeMailTemplate = DEFAULT_TEMPLATE_NAME
end

function ns.ActiveMailTemplate()
  ns.MigrateMailTemplates()
  local found = ns.FindMailTemplate(BegDB.settings.activeMailTemplate)
  if found then return found end
  local first = BegDB.mailTemplates[1]
  BegDB.settings.activeMailTemplate = first.name
  return first
end

function ns.AddMailTemplate(name, subject, body)
  ns.MigrateMailTemplates()
  name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then return nil, "Give it a name first." end
  if ns.FindMailTemplate(name) then return nil, "That name is already in use." end
  BegDB.mailTemplates[#BegDB.mailTemplates + 1] = {
    name = name, subject = subject or "", body = body or "", sent = 0, replied = 0, funded = 0,
  }
  return ns.FindMailTemplate(name)
end

function ns.RenameMailTemplate(oldName, newName)
  newName = tostring(newName or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if newName == "" then return false, "Give it a name first." end
  local t = ns.FindMailTemplate(oldName)
  if not t then return false, "No such template." end
  if newName ~= oldName and ns.FindMailTemplate(newName) then
    return false, "That name is already in use."
  end
  t.name = newName
  if BegDB.settings.activeMailTemplate == oldName then
    BegDB.settings.activeMailTemplate = newName
  end
  for _, c in pairs(BegDB.contacts or {}) do
    if c.templateUsed == oldName and c.templateKind == "mail" then c.templateUsed = newName end
  end
  return true
end

function ns.DeleteMailTemplate(name)
  ns.MigrateMailTemplates()
  if #BegDB.mailTemplates <= 1 then
    return false, "Keep at least one mail template."
  end
  for i, t in ipairs(BegDB.mailTemplates) do
    if t.name == name then
      local tomb = name .. " (deleted)"
      for _, c in pairs(BegDB.contacts or {}) do
        if c.templateUsed == name and c.templateKind == "mail" then c.templateUsed = tomb end
      end
      table.remove(BegDB.mailTemplates, i)
      if BegDB.settings.activeMailTemplate == name then
        BegDB.settings.activeMailTemplate = BegDB.mailTemplates[1].name
      end
      return true
    end
  end
  return false, "No such template."
end

-- Called when the server confirms a mail went out.
function ns.RecordMailSent(contact)
  local t = ns.ActiveMailTemplate()
  if t then t.sent = (tonumber(t.sent) or 0) + 1 end
  if contact then
    contact.templateUsed = t and t.name or nil
    contact.templateKind = "mail"
  end
end

function ns.MailTemplateSummary()
  local rows = {}
  for _, t in ipairs(BegDB.mailTemplates or {}) do
    local sent = tonumber(t.sent) or 0
    local rep  = tonumber(t.replied) or 0
    local fund = tonumber(t.funded) or 0
    rows[#rows + 1] = {
      name = t.name, sent = sent, replied = rep, funded = fund,
      replyRate = (sent > 0) and (rep / sent * 100) or 0,
      fundRate  = (sent > 0) and (fund / sent * 100) or 0,
    }
  end
  return rows
end

function ns.TemplateSummary()
  local rows = {}
  for _, t in ipairs(BegDB.templates or {}) do
    local sent = tonumber(t.sent) or 0
    local rep  = tonumber(t.replied) or 0
    local fund = tonumber(t.funded) or 0
    rows[#rows + 1] = {
      name = t.name, sent = sent, replied = rep, funded = fund,
      replyRate = (sent > 0) and (rep / sent * 100) or 0,
      fundRate  = (sent > 0) and (fund / sent * 100) or 0,
    }
  end
  return rows
end
