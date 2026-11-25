-- BegBuddy / Contacts.lua
-- The contact book: lookup, creation, status changes, counts and sorting.

local _, ns = ...
local StrLower = ns.StrLower

----------------------------------------------------------------------
-- Contacts
----------------------------------------------------------------------

-- Look up by exact key first, then fall back to a short-name match. The
-- short-name fallback is what saves you when the Who list hands back "Bob"
-- but the whisper event reports "Bob-Stormrage" (or the reverse).
-- Lower-case bare name -> every contact with that name. Built on first use
-- and kept up to date as contacts are added (contacts are never renamed or
-- removed), so a lookup never has to walk the whole list.
local byShort
local function HasRealm(full)
  local short = ns.ShortName(full)
  return short ~= nil and StrLower(short) ~= StrLower(full)
end
local function IndexAdd(c)
  local s = c.name and StrLower(c.name)
  if not s then return end
  local list = byShort[s]
  if not list then list = {}; byShort[s] = list end
  list[#list + 1] = c
end
local function Index()
  if not byShort then
    byShort = {}
    for _, c in pairs(BegDB.contacts) do IndexAdd(c) end
  end
  return byShort
end
function ns.ResetContactIndex() byShort = nil end

function ns.FindContact(full)
  local key = ns.KeyFor(full)
  if key and BegDB.contacts[key] then return BegDB.contacts[key] end
  local short = ns.ShortName(full)
  if not short then return nil end
  local list = Index()[StrLower(short)]
  if not list then return nil end
  -- A realm-tagged name only matches a contact stored without a realm: Bob of
  -- one realm is never Bob of another. A bare name matches any realm.
  local tagged = HasRealm(full)
  local found, count = nil, 0
  for _, c in ipairs(list) do
    if not tagged or not HasRealm(c.full or c.key) then
      found = c
      count = count + 1
    end
  end
  -- Only when unambiguous. Two Bobs on connected realms must stay separate.
  if count == 1 then return found end
  return nil
end

-- Returns contact, created.
-- Bumped whenever a contact is added or changes status or level, so the
-- sorted tab lists are rebuilt only when something they show has changed.
ns.listVer = 0
function ns.TouchList() ns.listVer = ns.listVer + 1 end

function ns.EnsureContact(full, info)
  if type(full) ~= "string" or full == "" then return nil, false end
  local existing = ns.FindContact(full)
  if existing then
    if info then
      ns.TouchList()
      existing.level      = info.level      or existing.level
      existing.class      = info.class      or existing.class
      existing.classToken = info.classToken or existing.classToken
      existing.zone       = info.zone       or existing.zone
      if info.guild and info.guild ~= "" then existing.guild = info.guild end
      if info.race  and info.race  ~= "" then existing.race  = info.race  end
    end
    return existing, false
  end
  local key = ns.KeyFor(full)
  local c = {
    key       = key,
    full      = full,
    name      = ns.ShortName(full) or full,
    status    = ns.STATUS.QUEUED,
    seenAt    = time(),
    attempts  = 0,
    history   = {},
  }
  if info then
    c.level      = info.level
    c.class      = info.class
    c.classToken = info.classToken
    c.zone       = info.zone
    if info.guild and info.guild ~= "" then c.guild = info.guild end
    if info.race  and info.race  ~= "" then c.race  = info.race  end
  end
  BegDB.contacts[key] = c
  BegDB.order[#BegDB.order + 1] = key
  if byShort then IndexAdd(c) end
  ns.TouchList()
  return c, true
end

function ns.PushHistory(c, dir, text)
  if not c or type(text) ~= "string" or text == "" then return end
  local h = c.history
  if type(h) ~= "table" then h = {}; c.history = h end
  h[#h + 1] = { t = time(), dir = dir, text = text }
  -- Monotonic version for cache invalidation. A count+timestamp signature can
  -- collide when a new message lands in the same second that an old one is
  -- trimmed off the front; this cannot.
  c.histVer = (tonumber(c.histVer) or 0) + 1
  if dir == "in" or dir == "out" then ns.TouchList() end
  local cap = tonumber(BegDB.settings.maxHistory) or 40
  while #h > cap do table.remove(h, 1) end
end

function ns.SetStatus(c, status, note)
  if not c or not status then return end
  c.status = status
  ns.TouchList()
  local now = time()
  if status == ns.STATUS.CONTACTED then
    -- Refreshed on every ask, so the re-whisper cooldown measures the LAST
    -- contact rather than the first one ever.
    c.contactedAt = now
    c.firstContactedAt = c.firstContactedAt or now -- the first ask, for the Stats tab's time of day
  elseif status == ns.STATUS.REPLIED then
    c.repliedAt = now
  elseif ns.TERMINAL[status] or status == ns.STATUS.ARCHIVED then
    c.closedAt = now
  end
  if note then c.note = note end

  -- Count each outcome exactly once per contact, against the template that
  -- earned it, so the per-template rates cannot inflate on repeat messages.
  if status == ns.STATUS.REPLIED and not c.countedReplied then
    c.countedReplied = true
    ns.RecordOutcome(c, "replied")
  elseif status == ns.STATUS.FUNDED and not c.countedFunded then
    c.countedFunded = true
    c.fundedAt = c.fundedAt or now
    ns.RecordOutcome(c, "funded")
  end

  if ns.RefreshUI then ns.RefreshUI() end
end

-- Moves everyone still waiting in Queued to Archived. Archived (not deleted)
-- so a later scan cannot put them straight back, and Requeue can undo it.
function ns.ClearQueued()
  local n = 0
  local now = time()
  for _, c in pairs(BegDB.contacts) do
    if c.status == ns.STATUS.QUEUED then
      c.status = ns.STATUS.ARCHIVED
      c.closedAt = now
      if ns.sentAt then ns.sentAt[c.key] = nil end
      n = n + 1
    end
  end
  if n > 0 then ns.TouchList() end
  if ns.RefreshUI then ns.RefreshUI() end
  return n
end

-- Clear all: deletes every saved list, history, counter and record, then starts again from a fresh database.
-- Kept: the quick messages (they are settings), the window's place and ZipUI's own saved profiles and
-- preferences (BegDB.zipui, shared by every Zip addon). It cannot be undone.
-- What this session remembered about the names that are gone.
local function ForgetSession()
  ns.activeContact, ns.pending, ns.lastSendKey, ns.lastLoadedKey = nil, nil, nil, nil
  for _, t in ipairs({ ns.sentAt or {}, ns.unread or {}, ns.checkState or {} }) do
    for k in pairs(t) do t[k] = nil end
  end
  ns.warnCount, ns.firstWarnAt, ns.lastScan = 0, nil, nil
  ns.sessionFirstAskAt, ns.sessionGoldIn, ns.sessionItemsIn = nil, 0, 0
  if ns.ClearSplits then ns.ClearSplits() end
  if ns.mail then ns.mail.lastResult = nil end
  if ns.UI and ns.UI.list then ns.UI.list.selectedKey = nil end
end

function ns.ClearAll()
  local keep = {}
  for _, key in ipairs({ "quickMessages", "window", "zipui" }) do keep[key] = BegDB and BegDB[key] end
  BegDB = nil
  ns.InitDB()
  for key, v in pairs(keep) do
    if type(v) == "table" then BegDB[key] = v end
  end
  ForgetSession()
  ns.TouchList()
  -- An open settings page still holds the old text; reload it, or closing it would write that back.
  if ns.UI and ns.UI.settings and ns.UI.settings:IsShown() then ns.UI.settings:Load() end
  -- Queue a redraw, then draw it now: FlushUI alone does nothing unless one is waiting.
  if ns.RefreshUI then ns.RefreshUI() end
  if ns.FlushUI then ns.FlushUI() end
end

function ns.Counts()
  local out = {}
  for _, tab in ipairs(ns.TABS) do out[tab.id] = 0 end
  for _, c in pairs(BegDB.contacts) do
    if out[c.status] then out[c.status] = out[c.status] + 1 end
  end
  return out
end

function ns.ListFor(status)
  local out = {}
  for _, key in ipairs(BegDB.order) do
    local c = BegDB.contacts[key]
    if c and c.status == status then out[#out + 1] = c end
  end
  return out
end

-- Sorts a contact list in place by the list's column setting. Ties fall back
-- to name and then the order found, so rows never jump between redraws.
function ns.SortContacts(list)
  local by = BegDB.settings.listSort
  local desc = BegDB.settings.listSortDesc and true or false
  if by ~= "name" and by ~= "level" then return list end
  local pos, lname = {}, {}
  for i, c in ipairs(list) do
    pos[c] = i
    lname[c] = tostring(c.name or c.key or ""):lower()
  end
  local function nameOf(c) return lname[c] end
  table.sort(list, function(a, b)
    if by == "level" then
      local la, lb = tonumber(a.level), tonumber(b.level)
      if la ~= lb then
        -- Unknown levels always go last, whichever way the column points.
        if not la then return false end
        if not lb then return true end
        if desc then return la > lb end
        return la < lb
      end
    end
    local na, nb = nameOf(a), nameOf(b)
    if na ~= nb then
      if by == "name" and desc then return na > nb end
      return na < nb
    end
    return pos[a] < pos[b]
  end)
  return list
end

-- A tab's contacts in the on-screen order, reused until the contacts or the
-- sort setting change. Callers must not modify the returned table.
local sortedCache = {}
function ns.SortedList(status)
  local st = BegDB.settings
  local hit = sortedCache[status]
  if hit and hit.ver == ns.listVer and hit.by == st.listSort
     and hit.desc == st.listSortDesc and hit.n == #BegDB.order then
    return hit.list
  end
  local list = ns.SortContacts(ns.ListFor(status))
  sortedCache[status] = { ver = ns.listVer, by = st.listSort, desc = st.listSortDesc,
                          n = #BegDB.order, list = list }
  return list
end

-- True when a Replied contact spoke last (you haven't answered yet).
function ns.NeedsReply(c)
  if not c or c.status ~= ns.STATUS.REPLIED then return false end
  local h = c.history
  if type(h) ~= "table" or #h == 0 then return false end
  for i = #h, 1, -1 do
    local d = h[i] and h[i].dir
    if d == "in" then return true end
    if d == "out" then return false end
  end
  return false
end

function ns.NeedsReplyCount()
  local n = 0
  for _, c in pairs(BegDB.contacts or {}) do
    if ns.NeedsReply(c) then n = n + 1 end
  end
  return n
end

-- In-memory (never persisted to SavedVariables) lowercased search haystack per contact,
-- plus cached filtered list keyed on listVer + status + query + filter flags.
local searchBlob, searchVer = {}, -1
local filterCache = {}

local function BlobFor(c)
  if searchVer ~= ns.listVer then
    searchBlob = {}
    searchVer = ns.listVer
  end
  local b = searchBlob[c.key]
  if not b then
    b = StrLower(table.concat({
      c.name or "", c.full or "", c.guild or "", c.zone or "",
      c.class or "", c.race or "", c.note or "",
    }, "\1"))
    searchBlob[c.key] = b
  end
  return b
end

-- Fast filtered view of a tab's sorted contact list. Returns the cached sorted
-- list directly with zero allocations when no search query or filter is active.
function ns.FilteredList(status, query, opts)
  local list = ns.SortedList(status)
  local q = type(query) == "string" and StrLower(query:gsub("^%s+", ""):gsub("%s+$", "")) or ""
  local needsReply = (opts and opts.needsReply) and true or false
  local hasGuild   = (opts and opts.hasGuild) and true or false
  if q == "" and not needsReply and not hasGuild then return list end

  local st = BegDB.settings
  local sig = table.concat({
    tostring(ns.listVer), tostring(status), q,
    tostring(needsReply), tostring(hasGuild),
    tostring(st.listSort), tostring(st.listSortDesc),
  }, "|")
  local hit = filterCache[status]
  if hit and hit.sig == sig then return hit.list end

  local out = {}
  for i = 1, #list do
    local c = list[i]
    local ok = true
    if needsReply and not ns.NeedsReply(c) then ok = false end
    if ok and hasGuild and (type(c.guild) ~= "string" or c.guild == "") then ok = false end
    if ok and q ~= "" and BlobFor(c):find(q, 1, true) == nil then ok = false end
    if ok then out[#out + 1] = c end
  end
  filterCache[status] = { sig = sig, list = out }
  return out
end

-- Cuts a string to at most n bytes without splitting a UTF-8 character.
function ns.TrimToBytes(s, n)
  if type(s) ~= "string" then return "" end
  n = tonumber(n) or 0
  if n <= 0 then return "" end
  if #s <= n then return s end
  local cut = s:sub(1, n)
  -- Walk back over continuation bytes until a real boundary. Unbounded so a
  -- malformed run of non-ASCII bytes cannot leave a dangling tail.
  while #cut > 0 do
    local b = cut:byte(-1)
    if not b then break end
    if b < 0x80 then break end   -- ASCII: clean boundary
    cut = cut:sub(1, -2)
    if b >= 0xC0 then break end  -- just dropped a lead byte: done
  end
  return cut
end

-- True when a name contains characters outside the Latin scripts. UTF-8 lead
-- bytes up to 0xC9 cover Latin-1 Supplement, Latin Extended-A and Latin
-- Extended-B, so Jose, Muller, Soren and Nunez keep their accents. Cyrillic
-- (0xD0 and up) and everything past it is skipped.
function ns.IsNonLatinName(name)
  local s = tostring(name or "")
  if s == "" then return false end
  s = s:gsub("\194\160", "")   -- U+00A0, the alt-code no-break space
  return s:find("[\202-\255]") ~= nil
end
