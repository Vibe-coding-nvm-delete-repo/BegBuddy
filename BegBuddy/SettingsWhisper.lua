-- BegBuddy / SettingsWhisper.lua
-- Settings page "Whisper": the whisper templates (pick, copy, delete, rename, edit with a live preview and a
-- length counter) and the results per template. Saved as you type; written back again when the page closes.

local _, ns = ...
local S = ns.Settings
local Z = ZipUI
local Sanitize = ns.Sanitize
local ACCENT = { 0.36, 0.78, 1.00 }
local WHITE = { 0.9, 0.9, 0.9 }

-- Prefer a real contact from the queue over a placeholder, so the preview is the actual thing that will be sent.
function ns.SampleIdentity()
  local c = ns.ListFor(ns.STATUS.QUEUED)[1] or ns.ListFor(ns.STATUS.CONTACTED)[1]
  if c then return c.name or "Sample", c.level, true, c end
  local fallback = { name = "Sample", level = 42, class = "Mage", race = "Human", zone = "Stormwind City", guild = "Knights of Azeroth" }
  return fallback.name, fallback.level, false, fallback
end

-- Template picker, new copy and delete (asks twice: a deleted template cannot be recovered).
local function pickerRow(c)
  local p = c.page
  S.Label(p, "Template:", 0, 30, WHITE)
  c.drop = ns.UI.Dropdown(p, 150, function(picked)
    BegDB.settings.activeTemplate = picked
    c.load()
  end)
  c.drop:SetPoint("TOPLEFT", p, "TOPLEFT", 60, -26)
  S.Button(p, "New copy", 76, 218, 26, function()
    local base = ns.ActiveTemplate()
    local name, n = "Copy", 2
    while ns.FindTemplate(name) do name = "Copy " .. n; n = n + 1 end
    local made, err = ns.AddTemplate(name, base and base.text or "")
    if not made then ns.Print(err or "Could not create it.") return end
    BegDB.settings.activeTemplate = made.name
    ns.Print("Created template '" .. Sanitize(made.name) .. "'. Rename it below.")
    c.load()
  end)
  local del = Z.ConfirmButton(p, "Delete", 70, S.Click(function()
    local ok, err = ns.DeleteTemplate(BegDB.settings.activeTemplate)
    if not ok then ns.Print(err or "Could not delete it.") return end
    ns.Print("Template deleted. Its results stay on the contacts.")
    c.load()
  end))
  del:SetPoint("TOPLEFT", p, "TOPLEFT", 300, -26)
end

-- Clickable variable insert chips and the rename box.
local QUICK_VARS = { "{name}", "{level}", "{class}", "{zone}", "{guild}", "{race}", "{greeting}", "{me}" }

local function insertRows(c)
  local p = c.page
  local function insert(tok) c.box:SetFocus(); c.box:Insert(tok) end -- drops it in at the cursor
  S.Label(p, "Insert:", 0, 58, WHITE)
  local x = 48
  for _, tok in ipairs(QUICK_VARS) do
    local w = math.max(46, #tok * 6 + 10)
    S.Button(p, tok, w, x, 54, function() insert(tok) end)
    x = x + w + 4
  end
  S.Label(p, "More: {realm} {mylevel} {myclass} {myrace} {myzone} {myguild} {day} {ask_num}", 0, 82)
  S.Label(p, "Rename to:", 0, 104, WHITE)
  c.nameBox = S.Input(p, 150, 70, 100, 24)
  c.nameBox:SetScript("OnEnterPressed", function(self)
    local ok, err = ns.RenameTemplate(BegDB.settings.activeTemplate, self:GetText())
    self:ClearFocus()
    if not ok then ns.Print(err or "Could not rename it.") return end
    ns.Print("Renamed.")
    self:SetText("")
    c.load()
  end)
end

-- Counter, then Undo / Trim to fit / Reset under the editor.
local function editBar(c)
  local p, box = c.page, c.box
  c.counter = S.Label(p, "", 0, 206)
  c.measure = S.Note(p, "", 70, 206, 180)
  S.Button(p, "Undo", 56, 258, 202, function()
    local previous = c.undoValue
    if type(previous) ~= "string" then ns.Print("Nothing to undo yet.") return end
    c.undoValue = box:GetText() or ""
    box:SetText(previous)
    box:SetCursorPosition(0)
  end)
  S.Button(p, "Trim to fit", 78, 320, 202, function()
    local txt = box:GetText() or ""
    if #txt <= 255 then ns.Print("Already fits in 255 characters.") return end
    c.undoValue = txt
    local cut = ns.TrimToBytes(txt, 255)
    local sp = cut:match("^.*()%s")
    if sp and sp > 180 then cut = cut:sub(1, sp - 1) end
    box:SetText(cut)
    box:SetCursorPosition(0)
    ns.Print("Trimmed to fit. Undo puts it back.")
  end)
  S.Button(p, "Reset", 58, 402, 202, function()
    c.undoValue = box:GetText() or ""
    box:SetText(ns.DEFAULT_TEMPLATE)
    box:SetCursorPosition(0)
    ns.Print("Template reset. Undo puts your version back.")
  end)
end

local function refreshTemplate(c)
  local txt = c.box:GetText() or ""
  local n = #txt
  c.counter:SetText(string.format("%d / 255", n))
  if n > 255 then
    c.counter:SetTextColor(1, 0.4, 0.4)
    c.measure:SetText(string.format("|cffff6060%d over - the end gets cut|r", n - 255))
  elseif n > 140 then
    c.counter:SetTextColor(1, 0.8, 0.4)
    c.measure:SetText("|cffffcc66long - may scroll out of view|r")
  else
    c.counter:SetTextColor(0.50, 0.85, 0.50)
    c.measure:SetText(string.format("|cff8f8f96room for %d more.|r", 255 - n))
  end
  local name, level, real, sample = ns.SampleIdentity()
  c.prevLbl:SetText(real and ("Preview - exactly what " .. name .. " will see:")
    or "Preview - scan someone and this uses their real contact:")
  local rendered = ns.RenderTemplate(sample or { name = name, level = level }, txt)
  if #rendered > 260 then rendered = rendered:sub(1, 260) .. " [...]" end
  c.prevText:SetText(Sanitize(rendered))
  c.savedLbl:SetText("|cff7fe07fSaved|r")
end

local function refreshStats(c)
  local rows = ns.TemplateSummary()
  local active = BegDB.settings.activeTemplate
  local lines = {}
  for i, r in ipairs(rows) do
    if i > 4 then break end
    local mark = (r.name == active) and "|cff5cc8ff>|r " or "  "
    lines[#lines + 1] = string.format("%s%s: %d sent, %d replied (%.0f%%), %d funded (%.0f%%)",
      mark, Sanitize(r.name), r.sent, r.replied, r.replyRate, r.funded, r.fundRate)
  end
  if #rows > 4 then
    lines[#lines + 1] = string.format("|cff8f8f96...and %d more. /beg stats for all.|r", #rows - 4)
  end
  if #lines == 0 then lines[1] = "|cff8f8f96No sends recorded yet.|r" end
  local sig = table.concat(lines, "\n")
  if c.statsSig == sig then return end
  c.statsSig = sig
  c.statsText:SetText(sig)
end

-- Pulls the active template into the editor and refreshes the picker.
local function loadTemplate(c)
  local box = c.box
  local t = ns.ActiveTemplate()
  c.loading = true
  box:SetText(t and t.text or "")
  c.loading = false
  -- Keep the mirror in step, or Undo / Trim / Reset would act on the previously selected template's text
  -- and overwrite this one with it.
  BegDB.settings.template = box:GetText() or ""
  c.undoValue = BegDB.settings.template
  c.dirty = false
  box:SetCursorPosition(0)
  local names = {}
  for _, rec in ipairs(BegDB.templates or {}) do names[#names + 1] = rec.name end
  c.drop:SetItems(names, t and t.name or "(none)")
  c.nameBox:SetText("")
  refreshTemplate(c)
  refreshStats(c)
end

-- Auto-save as you type. Skipped while a load fills the box, so it can never write back a truncated copy.
local function onTyped(c, box)
  if not c.loading then
    local text = box:GetText() or ""
    -- A whisper is one line. Strip line breaks here so the box shows what will actually be sent.
    if text:find("[\r\n]") then
      box:SetText((text:gsub("[\r\n]+", " "))) -- SetText fires this handler again with the flat text
      return
    end
    local t = ns.ActiveTemplate()
    if t then t.text = text end
    BegDB.settings.template = text -- mirror, for anything still reading it
    c.dirty = true
  end
  refreshTemplate(c)
end

-- Only write back what the player actually edited, so a programmatic load can never persist a truncated copy.
local function writeBack(c)
  if c.dirty then
    local text = c.box:GetText() or ""
    local t = ns.ActiveTemplate()
    if t then t.text = text end
    BegDB.settings.template = text
  end
  if c.drop.Close then c.drop:Close() end
end

function ns.SettingsWhisper(page)
  local c = { page = page }
  c.load = function() loadTemplate(c) end
  S.Note(page, "Saved as you type. Each named template keeps its own results.", 0, 0)
  c.box = S.Editor(page, 524, 72)
  c.box:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -126)
  pickerRow(c)
  insertRows(c)
  editBar(c)
  c.prevLbl = S.Label(page, "", 0, 232)
  c.prevText = S.Note(page, "", 4, 252, 516, { 0.90, 0.90, 0.92 })
  c.savedLbl = S.Label(page, "", 0, 314, { 0.5, 0.88, 0.5 })
  S.Label(page, "Results by template", 0, 340, ACCENT)
  c.statsText = S.Note(page, "", 4, 360, 516, { 0.8, 0.8, 0.82 })
  c.box:SetScript("OnTextChanged", function(self) onTyped(c, self) end)
  -- Off by default: strangers who whisper first (group leaders, guildmates, friends) are not begging leads.
  c.track = Z.Check(page, "Add people who whisper you first to Replied (never friends, guild, group or anyone you whispered)",
    function() return BegDB.settings.trackUnknownWhispers end,
    function(v) BegDB.settings.trackUnknownWhispers = v and true or false end)
  c.track:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -402)
  S.Add("message", page, {
    Load = function() c.load(); c.track:Refresh() end, Refresh = function() refreshStats(c) end, box = c.box,
    Hide = function() writeBack(c) end, track = c.track,
  })
  return 436
end
