-- BegBuddy / SettingsQuick.lua
-- Settings page "Quick messages": edit, hide, reorder, delete and add the one-click whispers shown in the main
-- window. Saved as you type. The list is not part of the settings table, so a settings reset and Clear all keep it.

local _, ns = ...
local S = ns.Settings
local Z = ZipUI

local TOP, ROW = 130, 26 -- where the rows start, and the height of one

-- Redraws this page and the main window.
local function changed(c)
  c.load()
  if ns.RefreshUI then ns.RefreshUI() end
end

-- One row: the text, Hide/Show, up, down, delete. It works on the message at c.rows[i].index.
local function editRow(c, i)
  local row = { index = i }
  local y = TOP + (i - 1) * ROW
  row.box = S.Input(c.page, 308, 0, y, ns.QUICK_LEN)
  row.box:SetScript("OnTextChanged", function(self)
    local m = not c.loading and BegDB.quickMessages[row.index]
    if not m then return end
    m.text = (self:GetText() or ""):gsub("[\r\n]+", " ")
    if ns.RefreshUI then ns.RefreshUI() end
  end)
  row.hide = S.Button(c.page, "Hide", 48, 314, y, function()
    local m = BegDB.quickMessages[row.index]
    if m then m.hidden = (not m.hidden) or nil end
    changed(c)
  end)
  row.up = S.Button(c.page, "Up", 34, 366, y, function()
    if ns.MoveQuick(row.index, -1) then changed(c) end
  end)
  row.down = S.Button(c.page, "Down", 42, 404, y, function()
    if ns.MoveQuick(row.index, 1) then changed(c) end
  end)
  row.del = S.Button(c.page, "Delete", 52, 450, y, function()
    if ns.RemoveQuick(row.index) then changed(c) end
  end)
  return row
end

local function rowParts(row)
  return { row.box, row.hide, row.up, row.down, row.del }
end

-- Shows one row per saved message and hides the spare ones.
local function load(c)
  ns.EnsureQuick()
  local q = BegDB.quickMessages
  c.loading = true
  for i, row in ipairs(c.rows) do
    local m = q[i]
    for _, w in ipairs(rowParts(row)) do w:SetShown(m ~= nil) end
    if m then
      row.box:SetText(m.text)
      row.box:SetAlpha(m.hidden and 0.5 or 1)
      row.hide:SetText(m.hidden and "Show" or "Hide")
    end
  end
  c.loading = false
  c.count:SetText(string.format("%d of %d messages. Hidden ones stay in the list but are not shown in the window.",
    #q, ns.QUICK_MAX))
end

-- A blank message is not worth keeping once the page closes.
local function writeBack(c)
  local q = BegDB.quickMessages
  for i = #q, 1, -1 do
    if (q[i].text or ""):match("^%s*$") then table.remove(q, i) end
  end
end

local function addRow(c)
  S.Label(c.page, "New message:", 0, 66, { 0.9, 0.9, 0.9 })
  c.newBox = S.Input(c.page, 340, 80, 62, ns.QUICK_LEN)
  local function add()
    local m, err = ns.AddQuick(c.newBox:GetText())
    if not m then ns.Print(err or "Could not add it.") return end
    c.newBox:SetText("")
    c.newBox:ClearFocus()
    changed(c)
  end
  c.newBox:SetScript("OnEnterPressed", function() add(); if ns.FlushUI then ns.FlushUI() end end)
  S.Button(c.page, "Add", 52, 426, 62, add)
  -- Replacing the list throws away the player's edits, so it asks first.
  local reset = Z.ConfirmButton(c.page, "Restore the starting list", 170, S.Click(function()
    ns.ResetQuick()
    ns.Print("Quick messages are back to the starting list.")
    changed(c)
  end))
  reset:SetPoint("TOPLEFT", c.page, "TOPLEFT", 0, -94)
end

function ns.SettingsQuick(page)
  local c = { page = page, rows = {} }
  c.load = function() load(c) end
  S.Note(page, "Click a message in the main window to whisper it to the person you have open. Nothing is sent "
    .. "when nobody is open. {name} and {level} work in a message. These are kept when you reset the settings "
    .. "and when you use Clear all.", 0, 0)
  addRow(c)
  c.count = S.Note(page, "", 180, 96, 360)
  for i = 1, ns.QUICK_MAX do c.rows[i] = editRow(c, i) end
  S.Add("quick", page, { Load = c.load, Hide = function() writeBack(c) end, rows = c.rows, newBox = c.newBox })
  return TOP + ns.QUICK_MAX * ROW + 10
end
