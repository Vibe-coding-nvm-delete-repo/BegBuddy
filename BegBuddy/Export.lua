-- BegBuddy / Export.lua
-- Plain-text backup of the whole CRM.

local _, ns = ...

local function Add(lines, text) lines[#lines + 1] = text end

local function ContactLine(c)
  local bits = {}
  if c.level then bits[#bits + 1] = "level " .. tostring(c.level) end
  if c.class then bits[#bits + 1] = tostring(c.class) end
  if c.zone  then bits[#bits + 1] = tostring(c.zone) end
  if c.attempts and c.attempts > 0 then
    bits[#bits + 1] = "attempts " .. tostring(c.attempts)
  end
  return string.format("%s%s", tostring(c.name or "?"),
    (#bits > 0) and ("  [" .. table.concat(bits, ", ") .. "]") or "")
end

local function HistoryLine(h)
  local stamp = (date and date("%Y-%m-%d %H:%M", h.t)) or ""
  local who = "server"
  if h.dir == "in" then who = "them"
  elseif h.dir == "out" then who = "you" end
  return string.format("    [%s] %s: %s", stamp, who, h.text)
end

local function AddContacts(lines)
  for _, tab in ipairs(ns.TABS) do
    local list = ns.ListFor(tab.id)
    if #list > 0 then
      Add(lines, string.format("=== %s (%d) ===", string.upper(tab.label), #list))
      for _, c in ipairs(list) do
        Add(lines, ContactLine(c))
        for _, h in ipairs(c.history or {}) do Add(lines, HistoryLine(h)) end
      end
      Add(lines, "")
    end
  end
end

local function StatsLine(t)
  return string.format("%s: %d sent, %d replied, %d funded",
    tostring(t.name), tonumber(t.sent) or 0,
    tonumber(t.replied) or 0, tonumber(t.funded) or 0)
end

-- Templates and their counters, so the export really is a full backup.
local function AddTemplates(lines)
  Add(lines, "=== TEMPLATES ===")
  for _, t in ipairs(BegDB.templates or {}) do
    Add(lines, StatsLine(t))
    Add(lines, "    " .. tostring(t.text or ""))
  end
  Add(lines, "")

  Add(lines, "=== MAIL TEMPLATES ===")
  for _, t in ipairs(BegDB.mailTemplates or {}) do
    Add(lines, StatsLine(t))
    Add(lines, "    Subject: " .. tostring(t.subject or ""))
    Add(lines, "    " .. tostring(t.body or ""):gsub("\n", "\n    "))
  end
  Add(lines, "")
end

-- Plain-text dump of the whole CRM, for backup. SavedVariables are the only
-- copy that exists, so this is the only way to get the data out of the game.
function ns.BuildExport()
  local lines = {}
  Add(lines, string.format("BegBuddy export - %s",
    (date and date("%Y-%m-%d %H:%M")) or "unknown time"))

  local total = 0
  for _, n in pairs(ns.Counts()) do total = total + n end
  Add(lines, string.format("%d contacts", total))
  Add(lines, "")

  AddContacts(lines)
  AddTemplates(lines)
  return table.concat(lines, "\n")
end
