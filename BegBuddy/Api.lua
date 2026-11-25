-- BegBuddy / Api.lua
-- A small public hook for other addons (Copperline asks auction sellers for a
-- discount). It only records names: it never sends anything.

local _, ns = ...

BegBuddyAPI = {
  version = 1,

  -- The pipeline state of a name ("queued", "contacted", "replied", "funded",
  -- "declined", "archived", "blocked"), or nil when BegBuddy does not know it.
  Status = function(name)
    if not BegDB or not ns.Readable(name) then return nil end
    local c = ns.FindContact(name)
    return c and c.status or nil
  end,

  -- Call just before whispering someone from another addon. The name becomes
  -- a contact, so the whisper is logged as the opener when the client confirms
  -- it went out, and their reply shows in Replied. Refuses names closed out
  -- in BegBuddy (declined, blocked): returns false and why.
  Track = function(name, source)
    if not BegDB then return false, "BegBuddy is not loaded yet." end
    if not ns.Readable(name, source) then return false, "The game hides that name from addons right now." end
    local c = ns.EnsureContact(name)
    if not c then return false, "Invalid name." end
    if c.status == ns.STATUS.BLOCKED or c.status == ns.STATUS.DECLINED then
      return false, c.name .. " is closed out in BegBuddy (" .. c.status .. ")."
    end
    if type(source) == "string" and source ~= "" and (c.source or "") == "" then c.source = source end
    -- an archived name comes back to Queued, so the outgoing whisper counts as an ask
    if c.status == ns.STATUS.ARCHIVED then ns.SetStatus(c, ns.STATUS.QUEUED) end
    return true
  end,
}
