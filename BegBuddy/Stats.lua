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
}
ns.STATS_VIEW_IDS = {}
for _, v in ipairs(ns.STATS_VIEWS) do ns.STATS_VIEW_IDS[v.id] = true end
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
  if not n then return "(no template)", 99 end
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

-- The funnel pass: one cheap look at every contact. The breakdowns are built later, one at a time, when asked for.
local function tally(ctx, c)
  local fn = ctx.funnel
  fn.found = fn.found + 1
  local field = STATUS_FIELD[c.status]
  if field then fn[field] = fn[field] + 1 end
  fn.gold = fn.gold + (c.goldIn or 0)
  fn.items = fn.items + (c.itemsIn or 0)
  if (c.goldIn or 0) > 0 then fn.funders = fn.funders + 1 end
  if not wasAsked(c) then return end

  fn.asked = fn.asked + 1
  if gotReply(c) then fn.replied = fn.replied + 1 end
  if gotFunded(c) then fn.funded = fn.funded + 1 end
  if isSuccess(c, ctx.stage, ctx.goldMin) then fn.success = fn.success + 1 end
  local r = minutes(askTime(c), c.repliedAt)
  if r then ctx.replyMins[#ctx.replyMins + 1] = r end
  local g = minutes(askTime(c), c.fundedAt)
  if g then ctx.fundMins[#ctx.fundMins + 1] = g end
end

local function compute(stage, goldMin, minSample)
  local ctx = {
    stage = stage, goldMin = goldMin, replyMins = {}, fundMins = {},
    funnel = { found = 0, asked = 0, replied = 0, funded = 0, success = 0, declined = 0, blocked = 0,
      archived = 0, gold = 0, items = 0, funders = 0 },
  }
  for _, c in pairs(BegDB.contacts or {}) do tally(ctx, c) end
  return { funnel = ctx.funnel, views = {}, sorted = {}, stage = stage, goldMin = goldMin, minSample = minSample,
    medianReply = median(ctx.replyMins), medianFund = median(ctx.fundMins) }
end

-- One breakdown: a row per label, with the asks, replies, funders, successes and gold behind it.
local function buildView(st, view)
  local keyOf, rows = KEYS[view], {}
  local needsClock = view == "time" or view == "day"
  for _, c in pairs(BegDB.contacts or {}) do
    if wasAsked(c) then
      local label, order, token = keyOf(c, needsClock and clock(askTime(c)) or nil)
      local r = rows[label]
      if not r then r = newRow(label, order, token); rows[label] = r end
      r.sent = r.sent + 1
      if gotReply(c) then r.replied = r.replied + 1 end
      if gotFunded(c) then r.funded = r.funded + 1 end
      if isSuccess(c, st.stage, st.goldMin) then r.success = r.success + 1 end
      r.gold = r.gold + (c.goldIn or 0)
      r.items = r.items + (c.itemsIn or 0)
    end
  end
  local list = {}
  for _, r in pairs(rows) do
    r.rate = r.success / r.sent
    r.goldPerAsk = r.gold / r.sent
    r.few = r.sent < st.minSample -- too few asks to trust the rate
    list[#list + 1] = r
  end
  return list
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
  local trust = key == "rate" or key == "goldPerAsk" -- a rate from a handful of asks must not top the list
  return function(a, b)
    if trust and a.few ~= b.few then return b.few end
    local x, y = a[key], b[key]
    if x == y then return a.label < b.label end
    if desc then return x > y end
    return x < y
  end
end

-- key: label, order, sent, replied, funded, success, rate, gold or goldPerAsk.
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

-- The sort a view starts with: natural order for levels, times and days, otherwise the most asked first.
function ns.StatsDefaultSort(view)
  if ns.STATS_NATURAL[view] then return "order", false end
  return "sent", true
end
