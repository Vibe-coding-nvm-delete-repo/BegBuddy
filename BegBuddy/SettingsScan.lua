-- BegBuddy / SettingsScan.lua
-- Settings page "Scan": the level range and slice size, the send gap and warning numbers, and the three
-- behaviour switches. A number saves on Enter or Escape, and again when the page closes.

local _, ns = ...
local S = ns.Settings
local Z = ZipUI
local ACCENT = { 0.36, 0.78, 1.00 }
local WHITE = { 0.9, 0.9, 0.9 }

local FLOOR = { minLevel = 1, maxLevel = 1, bandSize = 1, whoCapWarning = 1, replyGap = 0, rewhisperMinutes = 0, guildCooldownMinutes = 0 }

-- The new value for a field, or nil when it is not a number or breaks the Min / Max order.
local function checked(key, text)
  local v = tonumber(text)
  if not v then return nil end
  v = math.max(FLOOR[key] or 0, math.floor(v))
  local set = BegDB.settings
  if key == "minLevel" and set.maxLevel and v > set.maxLevel then
    ns.Print(string.format("Min level can't be above Max level (%d). Raise Max first.", set.maxLevel))
    return nil
  elseif key == "maxLevel" and set.minLevel and v < set.minLevel then
    ns.Print(string.format("Max level can't be below Min level (%d). Lower Min first.", set.minLevel))
    return nil
  end
  return v
end

local function addField(c, key, label, x, y)
  local l = S.Label(c.page, label, x, y + 4, WHITE)
  local e = Z.Edit(c.page, 54, 22)
  e:SetMaxLetters(7)
  e:SetPoint("LEFT", l, "RIGHT", 6, 0)
  local function commit(self)
    self:ClearFocus()
    local v = checked(key, self:GetText())
    if v and v ~= BegDB.settings[key] then
      BegDB.settings[key] = v
      ns.Print(string.format("%s set to %d.", label, v))
    end
    self:SetText(tostring(BegDB.settings[key]))
    c.preview()
    ns.RefreshUI()
  end
  e:SetScript("OnEscapePressed", commit)
  e:SetScript("OnEnterPressed", commit)
  c.fields[key] = e
end

-- The level numbers are the only input for the scan plan; this line shows what they make.
local function slicePreview(c)
  local slices = ns.BuildSlices()
  if #slices == 0 then
    c.slicesPrev:SetText("|cffff8080No level range set.|r")
    return
  end
  local parts = {}
  for i = 1, math.min(#slices, 8) do parts[i] = string.format("%d-%d", slices[i][1], slices[i][2]) end
  local more = (#slices > 8) and string.format(", +%d more", #slices - 8) or ""
  c.slicesPrev:SetText(string.format("%d slices to scan:  %s%s", #slices, table.concat(parts, ", "), more))
end

local function addSwitch(c, label, key, y, after)
  local cb = Z.Check(c.page, label, function() return BegDB.settings[key] end, function(v)
    BegDB.settings[key] = v
    if after then after() end
  end)
  cb:SetPoint("TOPLEFT", c.page, "TOPLEFT", 0, -y)
  c.switches[#c.switches + 1] = cb
end

local function load(c)
  for key, e in pairs(c.fields) do e:SetText(tostring(BegDB.settings[key] or "")) end
  for _, cb in ipairs(c.switches) do cb:Refresh() end
  c.preview()
end

-- Commit any number that was typed and then abandoned by closing the page, using the same validation as Enter/Escape.
local function commitTyped(c)
  for key, e in pairs(c.fields) do
    local v = checked(key, e:GetText())
    if v then BegDB.settings[key] = v end
  end
end

function ns.SettingsScan(page)
  local c = { page = page, fields = {}, switches = {} }
  c.preview = function() slicePreview(c) end
  S.Note(page, "Min and Max are the level range to scan. It is cut into slices small enough to stay under the per-query result cap.", 0, 0)
  addField(c, "minLevel", "Min level", 0, 40)
  addField(c, "maxLevel", "Max level", 180, 40)
  addField(c, "bandSize", "Slice size", 360, 40)
  c.slicesPrev = S.Note(page, "", 0, 76, 524, { 0.50, 0.85, 0.50 })
  S.Label(page, "Other", 0, 108, ACCENT)
  addField(c, "replyGap", "Send gap (seconds)", 0, 130)
  addField(c, "whoCapWarning", "Cap warning at", 190, 130)
  addField(c, "rewhisperMinutes", "Re-whisper (min)", 0, 160)
  addField(c, "guildCooldownMinutes", "Guild cooldown (min)", 190, 160)
  S.Label(page, "Behaviour", 0, 198, ACCENT)
  addSwitch(c, "Skip non-Latin names", "skipNonLatin", 220)
  addSwitch(c, "Skip friends, guildmates and party/raid members", "skipKnownPlayers", 246)
  addSwitch(c, "Skip guildless players", "skipGuildless", 272)
  addSwitch(c, "Auto-archive anyone who is offline", "autoArchiveOffline", 298)
  addSwitch(c, "One-click send (off: the message loads into chat and you press Enter)", "oneClickSend", 324, ns.RefreshUI)
  S.Note(page, "Escape or Enter saves a number. Guild cooldown spaces out asks to the same guild (0 = off).", 0, 358)
  S.Add("scan", page, {
    Load = function() load(c) end, Refresh = c.preview, fields = c.fields,
    Hide = function() commitTyped(c) end,
  })
  return 402
end
