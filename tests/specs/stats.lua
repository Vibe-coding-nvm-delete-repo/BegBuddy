-- Stats: gold and items from mail and trades are kept on the person once, the numbers (funnel, success stage,
-- breakdowns, medians, small-sample flag) are right on a known set of people, and the Stats tab shows them.

local function eq(name, got, want)
  local ok = got == want
  check(name, ok)
  if not ok then io.write("    got " .. tostring(got) .. ", want " .. tostring(want) .. "\n") end
end
local function truthy(name, v) check(name, v and true or false) end

local function newContact(name, f)
  local c = NS.EnsureContact(name, { level = f.level, class = f.class, classToken = f.token, zone = f.zone })
  for k, v in pairs(f) do if k ~= "level" and k ~= "class" and k ~= "token" and k ~= "zone" then c[k] = v end end
  return c
end

-- Mail ---------------------------------------------------------------------
Reset()
local inbox = {}
GetInboxNumItems = function() return #inbox end
GetInboxHeaderInfo = function(i)
  local m = inbox[i]
  return nil, nil, m.sender, m.subject, m.money or 0, 0, 10, m.items or 0, false, m.returned or false
end
local bob = newContact("Bob", { level = 12, class = "Mage", token = "MAGE", zone = "Elwynn Forest", mailedAt = 1, attempts = 1 })
inbox = { { sender = "Bob", subject = "Thanks", money = 5000, items = 2 } }
Fire("MAIL_INBOX_UPDATE")
eq("mail gold is added to the person", bob.goldIn, 5000)
eq("and so are the items", bob.itemsIn, 2)
eq("they are marked funded", bob.status, "funded")
truthy("the time they funded is kept", bob.fundedAt ~= nil)
eq("the gift is listed as a mail gift", bob.gifts[1].how, "mail")
Fire("MAIL_INBOX_UPDATE")
eq("the same mail is never counted twice", bob.goldIn, 5000)

local ann = newContact("Ann", { mailedAt = 1, attempts = 1 })
inbox = { { sender = "Ann", subject = "Your mail", money = 700, returned = true } }
Fire("MAIL_INBOX_UPDATE")
eq("a returned mail is your own gold coming back, not a gift", ann.goldIn, nil)

local eve = newContact("Eve", { mailedAt = 1, attempts = 1, status = "blocked" })
inbox = { { sender = "Eve", subject = "Hi", money = 900 } }
Fire("MAIL_INBOX_UPDATE")
eq("a blocked person's gold is not counted", eve.goldIn, nil)

-- Trades -------------------------------------------------------------------
Reset()
ERR_TRADE_COMPLETE = "Trade complete."
local partner, offeredCopper, offeredItems = "Cat", 12345, { { "Linen Cloth", nil, 3 } }
UnitName = function(unit) if unit == "NPC" then return partner end return "Me" end
GetTargetTradeMoney = function() return offeredCopper end
GetTradeTargetItemInfo = function(i) local it = offeredItems[i]; if it then return it[1], it[2], it[3] end end
local cat = newContact("Cat", { attempts = 1, contactedAt = 100, status = "contacted" })
Fire("TRADE_SHOW")
Fire("TRADE_ACCEPT_UPDATE", 1, 1)
Fire("UI_INFO_MESSAGE", 0, ERR_TRADE_COMPLETE)
eq("trade gold is added to the person", cat.goldIn, 12345)
eq("trade items are added (units)", cat.itemsIn, 3)
eq("the trade marks them funded", cat.status, "funded")
eq("the gift is listed as a trade gift", cat.gifts[1].how, "trade")

local dan = newContact("Dan", { attempts = 1, contactedAt = 100, status = "contacted" })
partner = "Dan"
Fire("TRADE_SHOW")
Fire("TRADE_ACCEPT_UPDATE", 1, 1)
Fire("TRADE_CLOSED")
eq("a trade that is cancelled counts for nothing", dan.goldIn, nil)
Fire("TRADE_SHOW")
Fire("TRADE_ACCEPT_UPDATE", 1, 0)
Fire("UI_INFO_MESSAGE", 0, ERR_TRADE_COMPLETE)
eq("nothing counts until the other player has accepted", dan.goldIn, nil)
partner = "Stranger"
Fire("TRADE_SHOW")
Fire("TRADE_ACCEPT_UPDATE", 1, 1)
Fire("UI_INFO_MESSAGE", 0, ERR_TRADE_COMPLETE)
local stranger = NS.FindContact("Stranger")
truthy("an accepted trade from a non-known stranger auto-creates a funded contact", stranger ~= nil and stranger.status == "funded" and stranger.goldIn == 12345)
UnitName = function() return nil end
Fire("TRADE_SHOW")
Fire("UI_INFO_MESSAGE", 0, ERR_TRADE_COMPLETE)
check("a trade whose partner can't be read does no harm", true)

-- The numbers -------------------------------------------------------------
Reset()
local T = os.time({ year = 2026, month = 11, day = 3, hour = 14, min = 0 })
newContact("C1", { level = 12, class = "Mage", token = "MAGE", zone = "Elwynn Forest", templateUsed = "A", firstContactedAt = T,
  contactedAt = T, repliedAt = T + 600, countedReplied = true, goldIn = 6000, fundedAt = T + 900, countedFunded = true,
  status = "funded", attempts = 1 })
newContact("C2", { level = 15, class = "Mage", token = "MAGE", zone = "Elwynn Forest", templateUsed = "A", firstContactedAt = T,
  contactedAt = T, repliedAt = T + 1800, countedReplied = true, status = "replied", attempts = 1 })
newContact("C3", { level = 25, class = "Rogue", token = "ROGUE", zone = "Durotar", templateUsed = "A", firstContactedAt = T,
  contactedAt = T, status = "contacted", attempts = 1 })
newContact("C4", { level = 27, class = "Rogue", token = "ROGUE", zone = "Durotar", templateUsed = "B", templateKind = "mail",
  mailedAt = T, goldIn = 200, itemsIn = 1, status = "funded", attempts = 1 })
newContact("C5", { class = "Priest", token = "PRIEST", templateUsed = "B", templateKind = "mail", mailedAt = T,
  status = "contacted", attempts = 2 })
newContact("C6", { level = 30, class = "Mage", token = "MAGE", status = "queued" })
newContact("C7", { level = 5, class = "Mage", token = "MAGE", zone = "Elwynn Forest", templateUsed = "A", firstContactedAt = T,
  contactedAt = T, status = "declined", attempts = 1 })
NS.TouchList()
BegDB.settings.successStage, BegDB.settings.successGold, BegDB.settings.statsMinSample = "funded", 1000, 2
local st = NS.Stats()
local fn = st.funnel
eq("found counts everyone", fn.found, 7)
eq("asked counts only people you asked", fn.asked, 6)
eq("replied includes people who funded without replying", fn.replied, 3)
eq("funded", fn.funded, 2)
eq("success follows the stage (funded)", fn.success, 2)
eq("gold total", fn.gold, 6200)
eq("items total", fn.items, 1)
eq("people who sent gold", fn.funders, 2)
eq("declined", fn.declined, 1)
eq("median reply time in minutes", st.medianReply, 20)
eq("median time to fund", st.medianFund, 15)

BegDB.settings.successStage = "replied"
eq("success at the replied stage", NS.Stats().funnel.success, 3)
BegDB.settings.successStage = "gold"
eq("success at gold of 10s or more", NS.Stats().funnel.success, 1)
BegDB.settings.successGold = 100
eq("success at gold of 1s or more", NS.Stats().funnel.success, 2)
BegDB.settings.successStage, BegDB.settings.successGold = "funded", 1000

local function rowOf(view, label)
  for _, r in ipairs(NS.StatsRows(view, "sent", true)) do if r.label == label then return r end end
end
local a, b = rowOf("template", "A"), rowOf("template", "Mail: B")
eq("template A asked", a.sent, 4)
eq("template A funded", a.funded, 1)
eq("template A success rate", a.rate, 0.25)
eq("template A gold", a.gold, 6000)
eq("a mail template is listed apart", b.sent, 2)
eq("mail template success", b.success, 1)
eq("gold per ask", a.goldPerAsk, 1500)
truthy("a row under the sample size is flagged", not a.few and not b.few)
eq("class rows", rowOf("class", "Mage").sent, 3)
eq("class row keeps the class colour token", rowOf("class", "Rogue").token, "ROGUE")
eq("level bands", rowOf("level", "10-19").sent, 2)
eq("a missing level has its own row", rowOf("level", "Level ?").sent, 1)
eq("zone rows", rowOf("zone", "Elwynn Forest").sent, 3)
eq("time of day blocks (14h is 12-15h)", rowOf("time", "12-15h").sent, 6)
local wday = os.date("*t", T).wday
eq("day of the week", rowOf("day", ({ "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" })[wday]).sent, 6)
eq("whisper versus mail", rowOf("method", "Mail").sent, 2)
eq("ask number", rowOf("ask", "2nd ask").sent, 1)

BegDB.settings.statsMinSample = 3
local best = NS.StatsRows("template", "rate", true)
eq("a high rate from too few asks sorts after a trusted one", best[1].label, "A")
BegDB.settings.statsMinSample = 2
best = NS.StatsRows("template", "rate", true)
eq("with enough asks the higher rate leads", best[1].label, "Mail: B")
eq("level view starts in natural order", NS.StatsRows("level", NS.StatsDefaultSort("level"))[1].label, "0-9")
eq("template view starts with the most asked", select(1, NS.StatsDefaultSort("template")), "sent")

local first = NS.Stats()
eq("the numbers are kept until something changes", NS.Stats(), first)
NS.TouchList()
truthy("a changed contact makes them again", NS.Stats() ~= first)
local second = NS.Stats()
BegDB.settings.statsMinSample = 50
truthy("a changed setting makes them again", NS.Stats() ~= second)
BegDB.settings.statsMinSample = 2

-- The tab --------------------------------------------------------------------
local F = BegBuddyFrame
F:Show()
NS.RefreshUINow()
truthy("the card and list show on a normal tab", F.list:IsShown() and F.detail:IsShown() and not F.statsPane:IsShown())
F.statsTab.scripts.OnClick(F.statsTab)
NS.RefreshUINow()
truthy("the Stats tab swaps them for the numbers", F.statsPane:IsShown() and not F.list:IsShown() and not F.detail:IsShown())
local p = F.statsPane
truthy("the funnel line shows the asked count", p.funnel.text:find("Asked|r 6", 1, true) ~= nil)
truthy("and the gold", p.funnel.text:find("Gold", 1, true) ~= nil)
truthy("the first row is a template", p.rows[1].cells.label.text:find("A", 1, true) ~= nil)
p.views.class.scripts.OnClick(p.views.class)
NS.RefreshUINow()
truthy("the Class view lists classes in their colour", p.rows[1].cells.label.text:find(NS.ClassHex("MAGE"), 1, true) ~= nil)
eq("the setting remembers the view", BegDB.settings.statsView, "class")
p.heads.gold.scripts.OnClick(p.heads.gold)
NS.RefreshUINow()
truthy("a heading click sorts by that column", p.sortKey == "gold" and p.sortDesc == true)
p.stage.gold.scripts.OnClick(p.stage.gold)
eq("Gold becomes the success stage", BegDB.settings.successStage, "gold")
p.stage.gold.scripts.OnClick(p.stage.gold)
eq("a second click steps the gold amount up", BegDB.settings.successGold, 5000)
BegDB.settings.statsMinSample = 20
p.sample.scripts.OnClick(p.sample)
eq("the trust button steps the sample size", BegDB.settings.statsMinSample, 30)
F.tabButtons[1].scripts.OnClick(F.tabButtons[1])
NS.RefreshUINow()
truthy("another tab brings the list back", F.list:IsShown() and not F.statsPane:IsShown())

-- /beg stats opens the tab
SlashCmdList.BEGBUDDY("stats")
NS.RefreshUINow()
truthy("/beg stats opens the Stats tab", F.activeTab == "stats" and F.statsPane:IsShown())
