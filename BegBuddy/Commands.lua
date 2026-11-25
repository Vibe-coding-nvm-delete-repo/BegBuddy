-- BegBuddy / Commands.lua
-- BegBuddy's own slash words. Settings.lua hands them to ZipUI.Slash, which adds the shared words
-- (open, settings, lock, unlock, scale, minimap, profile, list, help). Here "reset" is the slice plan,
-- so it wins over the shared "reset" (the window's place is reset from the Zip settings home).

local _, ns = ...

local C = {}
ns.Commands = C

-- word = what it does, shown by "/beg help" and on the About page.
ns.COMMAND_HELP = {
  scan = "run the next /who slice",
  reset = "restart the slice plan for the selected city",
  addzone = "add the zone you are standing in (and pick it)",
  nextzone = "move the scan on to the next picked zone",
  mail = "mail the next name in Queued (mailbox must be open)",
  probe = "print API availability on this client",
  dumpwho = "dump the raw Who fields for entry 1",
  export = "dump every contact to a copyable window",
  stats = "open the Stats tab; prints per-template sent / replied / funded",
  perf = "measure how long a full redraw takes",
  template = "reset the message, or set it: /beg template Hi {name}!",
  pause = "stop sending",
  resume = "allow sending again",
  leave = "leave your party or raid",
  queue = "open the floating 1-click Smart Reply Queue",
  copilot = "toggle WoW /chatlog for BegBuddy AI Copilot",
  save = "ask the client to write SavedVariables",
  clear = "move everyone in Queued to Archived",
  wipe = "delete all data, like Clear all (asks for confirmation)",
}

local function refresh() if ns.RefreshUI then ns.RefreshUI() end end

-- The settings pages hold the template text and the counters; reload them when one is open.
local function reloadSettings()
  if ns.UI and ns.UI.settings and ns.UI.settings:IsShown() then ns.UI.settings:Load() end
end

function C.scan() ns.ScanNextSlice() end
function C.reset() ns.ResetSlices() end
function C.addzone() ns.AddCurrentZone() end
function C.nextzone() ns.NextZone() end
function C.mail() ns.MailNext(); refresh() end
function C.probe() ns.Probe() end
function C.dumpwho() ns.DumpWho() end
function C.save() ns.SaveNow() end

function C.template(rest)
  local text
  if rest == "" or ns.StrLower(rest) == "reset" then
    text = ns.DEFAULT_TEMPLATE
    ns.Print("Template reset to the default.")
  else
    text = rest
    ns.Print(string.format("Template set (%d characters).", #text))
  end
  -- Write the record: that is what the send path actually reads. The mirror
  -- is kept only for the login-time repair.
  local t = ns.ActiveTemplate()
  if t then t.text = text end
  BegDB.settings.template = text
  reloadSettings()
end

function C.pause()
  BegDB.paused = true
  ns.Print("Sending paused.")
  refresh()
end

function C.resume()
  BegDB.paused = false
  ns.warnCount = 0
  ns.firstWarnAt = nil
  ns.Print("Sending allowed again.")
  refresh()
end

function C.leave() ns.LeaveGroup() end
function C.queue() if ns.UI and ns.UI.OpenSmartQueue then ns.UI.OpenSmartQueue() end end
function C.copilot() ns.ToggleCopilotChatLog() end

function C.export()
  local text = ns.BuildExport()
  if #text > 60000 then
    text = ns.TrimToBytes(text, 60000) .. "\n\n... truncated at 60000 characters."
    ns.Print("Export was longer than 60000 characters, so it got truncated.")
  end
  ns.Print(string.format("Export ready: %d characters, already selected - press Ctrl+C.", #text))
  if ns.UI and ns.UI.ShowCopy then
    ns.UI.ShowCopy(text, "BegBuddy export - copy and save this")
  end
end

function C.stats()
  -- The numbers live on the window's Stats tab; this also prints the per-template lines.
  if ns.UI and ns.UI.Open then
    ns.UI.Open()
    local f = ns.UI.frame
    if f then f.activeTab = "stats"; ns.RefreshUI() end
  end
  local rows = ns.TemplateSummary()
  if #rows == 0 then
    ns.Print("No templates yet.")
    return
  end
  local active = BegDB.settings.activeTemplate
  ns.Print("Per-template results:")
  for _, r in ipairs(rows) do
    ns.Print(string.format("  %s%s: %d sent, %d replied (%.0f%%), %d funded (%.0f%%)",
      (r.name == active) and "> " or "  ", ns.Sanitize(r.name),
      r.sent, r.replied, r.replyRate, r.funded, r.fundRate))
  end
end

function C.perf()
  if not ns.RefreshUINow then
    ns.Print("Open the window once first, then run this.")
    return
  end
  local clock = debugprofilestop or function() return GetTime() * 1000 end
  local runs = 50
  local t0 = clock()
  for _ = 1, runs do ns.RefreshUINow() end
  local ms = (clock() - t0) / runs
  local total = 0
  for _ in pairs(BegDB.contacts or {}) do total = total + 1 end
  ns.Print(string.format("Full redraw: %.2f ms over %d runs (%d contacts).", ms, runs, total))
end

function C.clear()
  local n = ns.ClearQueued()
  ns.Print(string.format("Cleared %d queued (moved to Archived; Requeue brings a name back).", n))
end

function C.wipe(rest)
  if rest ~= "confirm" then
    ns.Print("This deletes every contact and message. Run: /beg wipe confirm")
    return
  end
  ns.ClearAll()
  ns.Print("All data deleted. Your quick messages were kept.")
end
