-- Leave group: the header button and /beg leave leave a party or raid in one click, and
-- say plainly when there is nothing to leave. The client calls are mocked per case.

local leaves
local function client(grouped, opts)
  opts = opts or {}
  leaves, GROUPED = 0, grouped
  IsInGroup = function() return GROUPED end
  C_PartyInfo = nil
  LeaveParty = nil
  if opts.c_party then
    C_PartyInfo = { LeaveParty = function() leaves = leaves + 1 end }
  end
  if opts.global then
    LeaveParty = function() leaves = leaves + 1 end
  end
end

local function lastPrint() return PRINTS[#PRINTS] or "" end

-- In a party, with the modern call: one click leaves
client(true, { c_party = true })
Reset()
BegBuddyFrame:Show()
NS.RefreshUINow()
check("the window has a Leave group button", BegBuddyFrame.leaveBtn ~= nil)
BegBuddyFrame.leaveBtn.scripts.OnClick(BegBuddyFrame.leaveBtn)
check("one click leaves the group", leaves == 1)
check("and says so", lastPrint():find("Left the group", 1, true) ~= nil)

-- Classic Era has no C_PartyInfo: the global call is used instead
client(true, { global = true })
Reset()
BegBuddyFrame:Show()
NS.RefreshUINow()
BegBuddyFrame.leaveBtn.scripts.OnClick(BegBuddyFrame.leaveBtn)
check("the global LeaveParty works the same", leaves == 1 and lastPrint():find("Left the group", 1, true) ~= nil)

-- Nobody to leave: no call, and a plain answer
client(false, { c_party = true })
Reset()
BegBuddyFrame:Show()
NS.RefreshUINow()
BegBuddyFrame.leaveBtn.scripts.OnClick(BegBuddyFrame.leaveBtn)
check("solo, the button does nothing", leaves == 0)
check("and explains why", lastPrint():find("not in a group", 1, true) ~= nil)

-- A client with neither call must not raise
client(true)
Reset()
BegBuddyFrame:Show()
NS.RefreshUINow()
BegBuddyFrame.leaveBtn.scripts.OnClick(BegBuddyFrame.leaveBtn)
check("a missing call is explained, not an error", lastPrint():find("no leave party call", 1, true) ~= nil)

-- /beg leave is the same action, for a macro
client(true, { c_party = true })
Reset()
check("/beg leave is registered", type(NS.Commands.leave) == "function")
NS.Commands.leave()
check("/beg leave leaves the group", leaves == 1 and lastPrint():find("Left the group", 1, true) ~= nil)
