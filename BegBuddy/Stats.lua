-- BegBuddy / Stats.lua
-- What worked: the funnel (found, asked, replied, funded), the gold and items that came back, and the same numbers
-- broken down by template, class, level, zone, time of day, day, whisper or mail, and ask number. "Success" is the
-- stage the player picks: replied, funded, or gold at least some amount. Everything is worked out from the contact
-- records, in one pass, and kept until a contact changes or a setting does.

local _, ns = ...

ns.STATS_VIEWS = {
  { id = "template", label = "Template" },
  { id = "class",    label = "Class" },
  { id = "level",    label = "Level" },
  { id = "zone",     label = "Zone" },
  { id = "time",     label = "Time of day" },
  { id = "day",      label = "Day" },
  { id = "method",   label = "Whisper / mail" },
  { id = "ask",      label = "Ask #" },
  { id = "cohorts",  label = "Cohorts" },
}
ns.STATS_VIEW_IDS = {}
for _, v in ipairs(ns.STATS_VIEWS) do ns.STATS_VIEW_IDS[v.id] = true end

ns.COHORT_VIEWS = {
  { id = "level_class",     label = "Level x Class" },
  { id = "zone_level",      label = "Zone x Level" },
  { id = "guild_status",    label = "Guild vs Solo" },
  { id = "guild_top",       label = "Top Guilds" },
  { id = "template_method", label = "Template x Channel" },
  { id = "time_zone",       label = "Time x Zone" },
}
ns.COHORT_VIEW_IDS = {}
for _, v in ipairs(ns.COHORT_VIEWS) do ns.COHORT_VIEW_IDS[v.id] = true end

-- Views that read best in their natural order (level 10, 20, 30...) rather than biggest first.
ns.STATS_NATURAL = { level = true, time = true, day = true, method = true, ask = true }
ns.STATS_GOLD_STEPS   = { 100, 1000, 5000, 10000, 50000, 100000 } -- copper: 1s 10s 50s 1g 5g 10g
ns.STATS_SAMPLE_STEPS = { 10, 20, 30, 50, 100 }

local DAYS = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }

----------------------------------------------------------------------
-- Settings and per-contact facts
----------------------------------------------------------------------

-- stage ("replied", "funded" or "gold"), the gold a person must send for "gold", and the asks a row needs before
-- its rate is trusted.
function ns.StatsSettings()
  local s = BegDB.settings
  local stage = s.successStage
  if stage ~= "replied" and stage ~= "gold" then stage = "funded" end
  return stage, tonumber(s.successGold) or 1000, tonumber(s.statsMinSample) or 30
end

local function wasAsked(c)
  return (c.firstContactedAt or c.contactedAt or c.mailedAt or (c.attempts or 0) > 0) and true or false
end

local function askTime(c) return c.firstContactedAt or c.contactedAt or c.mailedAt end

local function gotFunded(c)
  return (c.countedFunded or c.status == "funded" or (c.goldIn or 0) > 0 or (c.itemsIn or 0) > 0) and true or false
end

-- A person who funded you has answered, so the funnel only ever narrows.
local function gotReply(c)
  return (c.countedReplied or c.repliedAt or c.status == "replied" or gotFunded(c)) and true or false
end

local function isSuccess(c, stage, goldMin)
  if stage == "replied" then return gotReply(c) end
  if stage == "gold" then return (c.goldIn or 0) >= goldMin end
  return gotFunded(c)
end

local function clock(t)
  local d = rawget(_G, "date") or (os and os.date)
  return d and t and d("*t", t) or nil
end

-- Labels that repeat for thousands of people are built once.
local TIME_LABEL, LEVEL_LABEL = {}, {}
for block = 0, 5 do TIME_LABEL[block] = string.format("%02d-%02dh", block * 4, block * 4 + 3) end
for lo = 0, 200, 10 do LEVEL_LABEL[lo] = lo .. "-" .. (lo + 9) end

----------------------------------------------------------------------
-- How a contact is filed in each view: label, order, class token
----------------------------------------------------------------------

local KEYS = {}

function KEYS.template(c)
  local n = c.templateUsed
  if not n then return gotFunded(c) and "(direct trade)" or "(no template)", 99 end
  return (c.templateKind == "mail" and "Mail: " or "") .. n, 0
end

function KEYS.class(c)
  local token = c.classToken or ns.ClassToken(c.class)
  return c.class or "Unknown", 0, token
end

function KEYS.level(c)
  local lvl = tonumber(c.level)
  if not lvl then return "Level ?", 999 end
  local lo = math.floor(lvl / 10) * 10
  return LEVEL_LABEL[lo] or (lo .. "-" .. (lo + 9)), lo
end

function KEYS.zone(c) return c.zone or "Unknown", 0 end

function KEYS.time(c, d)
  if not d then return "Unknown", 99 end
  local block = math.floor(d.hour / 4)
  return TIME_LABEL[block] or "?", block
end

function KEYS.day(c, d)
  if not d then return "Unknown", 99 end
  return DAYS[d.wday] or "?", d.wday
end

function KEYS.method(c)
  if c.templateKind == "mail" then return "Mail", 2 end
  return "Whisper", 1
end

function KEYS.ask(c)
  local n = c.attempts or 1
  if n <= 1 then return "1st ask", 1 end
  if n == 2 then return "2nd ask", 2 end
  return "3rd+ ask", 3
end

-- Cohort key functions (multi-dimensional breakdowns for the Cohorts subtab)
local COHORT_KEYS = {}

function COHORT_KEYS.level_class(c)
  local lvlLabel, lo = KEYS.level(c)
  local cls, _, token = KEYS.class(c)
  return lvlLabel .. " " .. cls, lo, token
end

function COHORT_KEYS.zone_level(c)
  local z = c.zone or "Unknown"
  local lvlLabel, lo = KEYS.level(c)
  return z .. " · " .. lvlLabel, lo
end

function COHORT_KEYS.guild_status(c)
  if type(c.guild) == "string" and c.guild ~= "" then
    return "In a Guild", 1
  end
  return "Guildless", 2
end

function COHORT_KEYS.guild_top(c)
  if type(c.guild) == "string" and c.guild ~= "" then
    return "<" .. c.guild .. ">", 0
  end
  return "(Guildless)", 1
end

function COHORT_KEYS.template_method(c)
  local tpl = c.templateUsed or "(no template)"
  local ch  = (c.templateKind == "mail") and "Mail" or "Whisper"
  return tpl .. " (" .. ch .. ")", 0
end

function COHORT_KEYS.time_zone(c, d)
  local tLabel, block = KEYS.time(c, d)
  local z = c.zone or "Unknown"
  return tLabel .. " · " .. z, block
end

----------------------------------------------------------------------
-- Passes over the contacts
----------------------------------------------------------------------

local function newRow(label, order, token)
  return { label = label, order = order, token = token, sent = 0, replied = 0, funded = 0, success = 0, gold = 0, items = 0 }
end

local function minutes(from, to)
  if from and to and to >= from then return (to - from) / 60 end
end

local function median(list)
  local n = #list
  if n == 0 then return nil end
  table.sort(list)
  if n % 2 == 1 then return list[(n + 1) / 2] end
  return (list[n / 2] + list[n / 2 + 1]) / 2
end

local STATUS_FIELD = { declined = "declined", blocked = "blocked", archived = "archived" }

-- A contact belongs in the analytics funnel and breakdown tables if they were
-- asked, replied, OR funded (e.g. a direct trade or alt trade). Dropping funded
-- contacts with attempts == 0 caused total Gold/Items to disagree with Funded
-- and left cohort rows showing 0 Funded / "-" Gold.
local function inAnalytics(c)
  return wasAsked(c) or gotReply(c) or gotFunded(c)
end

-- The funnel pass: one cheap look at every contact. The breakdowns are built later, one at a time, when asked for.
local function tally(ctx, c)
  local fn = ctx.funnel
  fn.found = fn.found + 1
  local field = STATUS_FIELD[c.status]
  if field then fn[field] = fn[field] + 1 end
  fn.gold = fn.gold + (c.goldIn or 0)
  fn.items = fn.items + (c.itemsIn or 0)
  if (c.goldIn or 0) > 0 then fn.funders = fn.funders + 1 end
  if not inAnalytics(c) then return end

  local asked = wasAsked(c)
  if asked then fn.asked = fn.asked + 1 end
  local at = askTime(c) or c.fundedAt or c.repliedAt
  if at and (not fn.firstAskAt or at < fn.firstAskAt) then fn.firstAskAt = at end
  if gotReply(c) then fn.replied = fn.replied + 1 end
  if gotFunded(c) then fn.funded = fn.funded + 1 end
  if isSuccess(c, ctx.stage, ctx.goldMin) then fn.success = fn.success + 1 end
  if asked then
    local r = minutes(askTime(c), c.repliedAt)
    if r then ctx.replyMins[#ctx.replyMins + 1] = r end
    local g = minutes(askTime(c), c.fundedAt)
    if g then ctx.fundMins[#ctx.fundMins + 1] = g end
  end
end

local function compute(stage, goldMin, minSample)
  local ctx = {
    stage = stage, goldMin = goldMin, replyMins = {}, fundMins = {},
    funnel = { found = 0, asked = 0, replied = 0, funded = 0, success = 0, declined = 0, blocked = 0,
      archived = 0, gold = 0, items = 0, funders = 0, firstAskAt = nil },
  }
  for _, c in pairs(BegDB.contacts or {}) do tally(ctx, c) end
  return { funnel = ctx.funnel, views = {}, cohorts = {}, sorted = {}, stage = stage, goldMin = goldMin, minSample = minSample,
    medianReply = median(ctx.replyMins), medianFund = median(ctx.fundMins) }
end

local function buildRows(st, keyOf, needsClock)
  local rows = {}
  for _, c in pairs(BegDB.contacts or {}) do
    if inAnalytics(c) then
      local ts = askTime(c) or c.fundedAt or c.repliedAt
      local label, order, token = keyOf(c, needsClock and clock(ts) or nil)
      local r = rows[label]
      if not r then r = newRow(label, order, token); rows[label] = r end
      if wasAsked(c) then r.sent = r.sent + 1 end
      if gotReply(c) then r.replied = r.replied + 1 end
      if gotFunded(c) then r.funded = r.funded + 1 end
      if isSuccess(c, st.stage, st.goldMin) then r.success = r.success + 1 end
      r.gold = r.gold + (c.goldIn or 0)
      r.items = r.items + (c.itemsIn or 0)
    end
  end
  local list = {}
  for _, r in pairs(rows) do
    local denom = r.sent > 0 and r.sent or math.max(r.replied, r.funded, 1)
    r.rate = r.success / denom
    r.goldPerAsk = r.gold / denom
    r.goldPerReply = r.replied > 0 and (r.gold / r.replied) or 0
    r.few = r.sent < st.minSample -- too few asks to trust the rate
    list[#list + 1] = r
  end
  return list
end

-- One breakdown: a row per label, with the asks, replies, funders, successes and gold behind it.
local function buildView(st, view)
  local keyOf = KEYS[view]
  local needsClock = view == "time" or view == "day"
  return buildRows(st, keyOf, needsClock)
end

local function buildCohort(st, cohort)
  local keyOf = COHORT_KEYS[cohort]
  local needsClock = cohort == "time_zone"
  return buildRows(st, keyOf, needsClock)
end

-- Persisted session tracker (survives /reload as long as last activity was within 30 min).
local SESSION_IDLE_SEC = 30 * 60

function ns.TouchSessionAsk(nowTs)
  local now = nowTs or time()
  local s = BegDB and BegDB.session
  if type(s) ~= "table" or not s.lastAt or (now - s.lastAt) > SESSION_IDLE_SEC then
    s = { startAt = now, lastAt = now, gold = 0, items = 0 }
    if BegDB then BegDB.session = s end
  else
    s.startAt = s.startAt or now
    s.lastAt = now
  end
  ns.sessionFirstAskAt = s.startAt
  ns.sessionGoldIn = s.gold or 0
  ns.sessionItemsIn = s.items or 0
end

function ns.TouchSessionGift(copper, items, nowTs)
  local now = nowTs or time()
  local s = BegDB and BegDB.session
  if type(s) ~= "table" or not s.lastAt or (now - s.lastAt) > SESSION_IDLE_SEC then
    s = { startAt = now, lastAt = now, gold = 0, items = 0 }
    if BegDB then BegDB.session = s end
  else
    s.startAt = s.startAt or now
    s.lastAt = now
  end
  s.gold  = (s.gold or 0) + math.max(tonumber(copper) or 0, 0)
  s.items = (s.items or 0) + math.max(tonumber(items) or 0, 0)
  ns.sessionFirstAskAt = s.startAt
  ns.sessionGoldIn = s.gold
  ns.sessionItemsIn = s.items
end

-- Computes total active outreach seconds across all contacts by merging activity
-- timestamps separated by <= 30 min (excludes offline/sleep gaps so all-time GPH
-- doesn't collapse to 6c/hr after sleeping).
local function activeSeconds(now)
  local times = {}
  for _, c in pairs(BegDB.contacts or {}) do
    local t1 = askTime(c)
    if t1 then times[#times + 1] = t1 end
    if c.repliedAt then times[#times + 1] = c.repliedAt end
    if c.fundedAt then times[#times + 1] = c.fundedAt end
  end
  if #times == 0 then return 0 end
  table.sort(times)
  local total = 0
  local spanStart, spanEnd = times[1], times[1]
  for i = 2, #times do
    local t = times[i]
    if (t - spanEnd) <= SESSION_IDLE_SEC then
      spanEnd = t
    else
      total = total + math.max(60, spanEnd - spanStart)
      spanStart, spanEnd = t, t
    end
  end
  -- If the latest activity is still within the active window, count up to now.
  if (now - spanEnd) <= SESSION_IDLE_SEC then spanEnd = math.max(spanEnd, now) end
  total = total + math.max(60, spanEnd - spanStart)
  return math.max(60, total)
end

-- Gold per hour from the 1st message sent.
-- Returns: displayGph, totalGold, activeSec, firstAt, sessGph, sessGold, sessSec, allActiveGph
-- displayGph prefers active Session GPH (persisted across /reload for 30 min) so
-- the top bar always shows your live motivating rate, falling back to Active All-Time GPH.
function ns.GoldPerHour(nowTs)
  local now = nowTs or time()
  local st = ns.Stats()
  local fn = st.funnel
  local totalGold = fn.gold or 0
  local firstAt = fn.firstAskAt
  local actSec = firstAt and activeSeconds(now) or 0
  local allActiveGph = (firstAt and actSec > 0) and (totalGold * 3600 / actSec) or 0

  local s = BegDB and BegDB.session
  local sActive = type(s) == "table" and s.lastAt and (now - s.lastAt) <= SESSION_IDLE_SEC
  if type(s) == "table" and not sActive then
    ns.sessionFirstAskAt, ns.sessionGoldIn, ns.sessionItemsIn = nil, 0, 0
  end
  local sessStart = sActive and s.startAt or (type(s) ~= "table" and ns.sessionFirstAskAt or nil)
  local sessGold  = sActive and (s.gold or 0) or (type(s) ~= "table" and (ns.sessionGoldIn or 0) or 0)
  local sessSec   = sessStart and math.max(60, now - sessStart) or 0
  local sessGph   = (sessStart and sessSec > 0) and (sessGold * 3600 / sessSec) or 0

  local displayGph = (sessStart and sessGold > 0) and sessGph or allActiveGph
  return displayGph, totalGold, actSec, firstAt, sessGph, sessGold, sessSec, allActiveGph
end

local cache

-- The numbers, worked out again only when a contact or a setting changed.
function ns.Stats()
  local stage, goldMin, minSample = ns.StatsSettings()
  local sig = table.concat({ ns.listVer, stage, goldMin, minSample }, "|")
  if cache and cache.sig == sig then return cache end
  cache = compute(stage, goldMin, minSample)
  cache.sig = sig
  return cache
end

----------------------------------------------------------------------
-- Sorted rows for one view
----------------------------------------------------------------------

local function comparator(key, desc)
  local trust = key == "rate" or key == "goldPerAsk" or key == "goldPerReply" -- a rate from a handful of asks must not top the list
  return function(a, b)
    if trust and a.few ~= b.few then return b.few end
    local x, y = a[key] or 0, b[key] or 0
    if x == y then return a.label < b.label end
    if desc then return x > y end
    return x < y
  end
end

-- key: label, order, sent, replied, funded, success, rate, gold, goldPerReply, goldPerAsk or items.
function ns.StatsRows(view, key, desc)
  local st = ns.Stats()
  if not KEYS[view] then return {} end
  if not st.views[view] then st.views[view] = buildView(st, view) end
  local id = view .. "|" .. key .. "|" .. tostring(desc)
  local list = st.sorted[id]
  if not list then
    list = {}
    for i, r in ipairs(st.views[view]) do list[i] = r end
    table.sort(list, comparator(key, desc))
    st.sorted[id] = list
  end
  return list
end

-- Sorted rows for one cohort dimension in the Cohorts subtab.
function ns.CohortRows(cohort, key, desc)
  local st = ns.Stats()
  if not COHORT_KEYS[cohort] then return {} end
  if not st.cohorts[cohort] then st.cohorts[cohort] = buildCohort(st, cohort) end
  local id = "cohort|" .. cohort .. "|" .. key .. "|" .. tostring(desc)
  local list = st.sorted[id]
  if not list then
    list = {}
    for i, r in ipairs(st.cohorts[cohort]) do list[i] = r end
    table.sort(list, comparator(key, desc))
    st.sorted[id] = list
  end
  return list
end

-- The sort a view starts with: natural order for levels, times and days, otherwise the most asked first.
function ns.StatsDefaultSort(view)
  if ns.STATS_NATURAL[view] then return "order", false end
  return "sent", true
end
