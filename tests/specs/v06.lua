-- BegBuddy v0.6 behavioral & boundary spec:
-- Template variables (16), Guild/Race capture + Per-Guild Cooldown + Known-Player skip,
-- Automatic trade attribution (gold + named items), Live Gold/Hour top bar,
-- Dashboard Min/Max level inputs, Search/Filter + Needs Reply queue,
-- Rich sortable Cohort Analytics subtab, and SettingsScan validation fix.

local function eq(name, got, want)
  local ok = got == want
  check(name, ok)
  if not ok then io.write("    got " .. tostring(got) .. ", want " .. tostring(want) .. "\n") end
end
local function truthy(name, v) check(name, v and true or false) end
local function has(name, s, sub)
  local ok = type(s) == "string" and s:find(sub, 1, true) ~= nil
  check(name, ok)
  if not ok then io.write("    expected '" .. tostring(s) .. "' to contain '" .. tostring(sub) .. "'\n") end
end

-- 1. Full 16-variable Template Engine (Whisper + Mail) ---------------------
Reset()
UnitName  = function(u) return u == "player" and "Beggar" or nil end
UnitLevel = function() return 7 end
UnitClass = function() return "Warrior" end
UnitRace  = function() return "Human" end
GetRealZoneText = function() return "Stormwind City" end
GetGuildInfo    = function() return "Tiny Guild" end
GetRealmName    = function() return "Dreamscythe" end

local alice = NS.EnsureContact("Alice-Dreamscythe", {
  level = 58, class = "Mage", classToken = "MAGE", race = "Gnome",
  zone = "Ironforge", guild = "Arcane Order",
})
local tpl = "{greeting} {name} (lvl {level} {race} {class} in {zone} of {guild} on {realm})! I am {me} ({mylevel} {myrace} {myclass} in {myzone}, {myguild}) on {day} #{ask_num} {unknown}"
local rendered = NS.RenderTemplate(alice, tpl)
has("whisper renders {name}", rendered, "Alice")
has("whisper renders {level}", rendered, "lvl 58")
has("whisper renders {race} and {class}", rendered, "Gnome Mage")
has("whisper renders {zone}", rendered, "Ironforge")
has("whisper renders {guild}", rendered, "Arcane Order")
has("whisper renders {realm}", rendered, "Dreamscythe")
has("whisper renders {me} and self vars", rendered, "I am Beggar (7 Human Warrior in Stormwind City, Tiny Guild)")
has("whisper renders {ask_num}", rendered, "#1")
has("unknown {token} stays untouched", rendered, "{unknown}")

local solo = NS.EnsureContact("Solo", { level = 20, class = "Rogue" })
local cleaned = NS.RenderTemplate(solo, "Hi {name} {guild} friend!")
eq("empty optional {guild} collapses double spaces cleanly", cleaned, "Hi Solo friend!")

local mSubj, mBody = NS.RenderMail(alice, { subject = "{greeting} {name} ({class})", body = "Hey {name} in {zone}!\nFrom {me} ({myclass})" })
has("mail subject renders vars", mSubj, "Alice (Mage)")
has("mail body keeps newline and renders vars", mBody, "Hey Alice in Ironforge!\nFrom Beggar (Warrior)")

-- 2. Guild & Race /who capture + Auto-Skip Known Players + Guild Cooldown --
Reset()
local whoRows = {
  { fullName = "KnightOne", fullGuildName = "Knights", level = 60, raceStr = "Human", classStr = "Paladin", classFile = "PALADIN", area = "Stormwind City" },
  { fullName = "KnightTwo", fullGuildName = "Knights", level = 55, raceStr = "Dwarf", classStr = "Priest",  classFile = "PRIEST",  area = "Stormwind City" },
  { fullName = "BestFriend", fullGuildName = "Friends", level = 40, raceStr = "Human", classStr = "Mage", classFile = "MAGE", area = "Stormwind City" },
  { fullName = "GuildMate",  fullGuildName = "MyGuild", level = 50, raceStr = "Human", classStr = "Rogue", classFile = "ROGUE", area = "Stormwind City" },
  { fullName = "LoneWolf",   fullGuildName = "",        level = 45, raceStr = "Night Elf", classStr = "Hunter", classFile = "HUNTER", area = "Ironforge" },
}
C_FriendList.GetNumWhoResults = function() return #whoRows, #whoRows end
C_FriendList.GetWhoInfo = function(i) return whoRows[i] end
C_FriendList.GetFriendInfo = function(n) return n == "BestFriend" and { name = "BestFriend" } or nil end
C_GuildInfo = { MemberExistsByName = function(n) return n == "GuildMate" end }

local added, shown, _, skipped = NS.Harvest()
eq("harvest captures non-known players", added, 3)
eq("harvest skips friend and guildmate", skipped, 2)
eq("friend was not queued", NS.FindContact("BestFriend"), nil)
eq("guildmate was not queued", NS.FindContact("GuildMate"), nil)

local k1 = NS.FindContact("KnightOne")
local k2 = NS.FindContact("KnightTwo")
local lw = NS.FindContact("LoneWolf")
eq("guild captured from /who", k1.guild, "Knights")
eq("race captured from /who", k1.race, "Human")
eq("empty guild stored as nil", lw.guild, nil)

-- Per-Guild Cooldown: messaging KnightOne holds KnightTwo, so NextToSend picks LoneWolf
BegDB.settings.guildCooldownMinutes = 60
BegDB.settings.oneClickSend = true
NS.MarkGuildContacted(k1)
NS.SetStatus(k1, NS.STATUS.CONTACTED)
local canK2, whyK2 = NS.CanWhisper(k2)
eq("per-guild cooldown blocks second member of same guild", canK2, false)
has("guild cooldown reason names the guild", whyK2, "<Knights>")
local nextC = NS.NextToSend()
eq("NextToSend skips guild-cooldown member and picks LoneWolf", nextC and nextC.name, "LoneWolf")

BegDB.settings.guildCooldownMinutes = 0
local canK2Off = NS.CanWhisper(k2)
eq("guildCooldownMinutes = 0 disables guild cooldown", canK2Off, true)

-- 3. Automatic Trade Tracking (Gold + Named Items) & Closed-Deal CRM -------
Reset()
ERR_TRADE_COMPLETE = "Trade complete."
local partner, offeredCopper, offeredItems = "Generous", 0, {
  { "Linen Bag", nil, 2 },
  { "Greater Magic Wand", nil, 1 },
}
UnitName = function(u) if u == "NPC" then return partner end return "Beggar" end
GetTargetTradeMoney = function() return offeredCopper end
GetTradeTargetItemInfo = function(i) local it = offeredItems[i]; if it then return it[1], it[2], it[3] end end
GetTradeTargetItemLink = function(i) local it = offeredItems[i]; if it then return "[" .. it[1] .. "]" end end
C_FriendList.GetFriendInfo = function(n) return n == "MyBuddy" and { name = "MyBuddy" } or nil end

local gen = NS.EnsureContact("Generous", { level = 60, class = "Mage", guild = "Rich Guild" })
NS.RecordSent(gen)
NS.SetStatus(gen, NS.STATUS.CONTACTED)
Fire("TRADE_SHOW")
Fire("TRADE_TARGET_ITEM_CHANGED")
Fire("TRADE_ACCEPT_UPDATE", 1, 1)
Fire("UI_INFO_MESSAGE", 0, ERR_TRADE_COMPLETE)
eq("item-only trade marks contact funded", gen.status, "funded")
eq("item-only trade counts total units", gen.itemsIn, 3)
eq("item-only trade stores named item list", gen.giftItems and gen.giftItems[1].name, "Linen Bag")
eq("item-only trade credits template funded count", NS.ActiveTemplate().funded, 1)
has("trade history records exact item names", gen.history[#gen.history].text, "2x Linen Bag, Greater Magic Wand")

-- Known friend trading you is not auto-added to CRM
partner = "MyBuddy"
offeredCopper = 5000
Fire("TRADE_SHOW")
Fire("TRADE_ACCEPT_UPDATE", 1, 1)
Fire("UI_INFO_MESSAGE", 0, ERR_TRADE_COMPLETE)
eq("known friend trade does not pollute CRM", NS.FindContact("MyBuddy"), nil)

-- 4. Live Gold/Hour (from 1st message sent) & Top Bar Pill -----------------
Reset()
NS.UI.Open()
local f = NS.UI.frame
local now = time()
local p1 = NS.EnsureContact("P1", { level = 55, class = "Mage", classToken = "MAGE", zone = "Stormwind City", guild = "Alpha" })
p1.attempts = 1; p1.firstContactedAt = now - 1800; p1.contactedAt = now - 1800; p1.repliedAt = now - 1700
p1.status = "funded"; p1.countedReplied = true; p1.countedFunded = true; p1.goldIn = 50000; p1.itemsIn = 1; p1.templateUsed = "Default"
local p2 = NS.EnsureContact("P2", { level = 52, class = "Mage", classToken = "MAGE", zone = "Stormwind City", guild = "Alpha" })
p2.attempts = 1; p2.firstContactedAt = now - 1200; p2.contactedAt = now - 1200; p2.repliedAt = now - 1100
p2.status = "replied"; p2.countedReplied = true; p2.goldIn = 0; p2.templateUsed = "Default"
local p3 = NS.EnsureContact("P3", { level = 25, class = "Warrior", classToken = "WARRIOR", zone = "Ironforge" })
p3.attempts = 1; p3.firstContactedAt = now - 600; p3.contactedAt = now - 600; p3.repliedAt = now - 500
p3.status = "funded"; p3.countedReplied = true; p3.countedFunded = true; p3.goldIn = 10000; p3.itemsIn = 2; p3.templateUsed = "Mail1"; p3.templateKind = "mail"
NS.TouchList()

local gph, totalGold, elapsed = NS.GoldPerHour(now)
eq("total gold across contacts is 6g", totalGold, 60000)
eq("elapsed from 1st message sent is 1800s", elapsed, 1800)
eq("Gold/hr from 1st message is 12g/hr (120000c)", math.floor(gph + 0.5), 120000)

NS.RefreshUINow()
has("top bar GPH pill renders live Gold/hr", f.gphBtn.text:GetText(), "12g 0s")

-- 5. Dashboard Inline Min/Max Level Inputs ---------------------------------
f.minLvlBox:SetText("20")
f.minLvlBox:GetScript("OnEnterPressed")(f.minLvlBox)
eq("dashboard minLevel input updates BegDB.settings", BegDB.settings.minLevel, 20)
f.maxLvlBox:SetText("10")
f.maxLvlBox:GetScript("OnEnterPressed")(f.maxLvlBox)
eq("dashboard maxLevel rejects value below minLevel", BegDB.settings.maxLevel, 60)

-- 6. Fast Search/Filter Bar + Needs Reply Queue ----------------------------
NS.PushHistory(p2, "in", "Sure meet me at AH")
eq("NeedsReply true when contact spoke last", NS.NeedsReply(p2), true)
eq("NeedsReplyCount counts warm leads", NS.NeedsReplyCount(), 1)
local filteredReply = NS.FilteredList("replied", "", { needsReply = true })
eq("FilteredList needsReply finds P2", #filteredReply, 1)
local filteredGuild = NS.FilteredList("funded", "alpha", { hasGuild = true })
eq("FilteredList search by guild finds P1", #filteredGuild == 1 and filteredGuild[1].name, "P1")
NS.PushHistory(p2, "out", "On my way!")
eq("NeedsReply clears once you reply", NS.NeedsReply(p2), false)
local filteredAfterReply = NS.FilteredList("replied", "", { needsReply = true })
eq("FilteredList invalidates cache immediately after replying", #filteredAfterReply, 0)

-- 7. Rich Sortable Cohort Analytics Subtab ---------------------------------
BegDB.settings.statsMinSample = 1
NS.TouchList()
local lc = NS.CohortRows("level_class", "goldPerReply", true)
eq("Level x Class cohort has 2 groups", #lc, 2)
eq("50-59 Mage leads by goldPerReply (25000c vs 10000c)", lc[1].label, "50-59 Mage")
eq("50-59 Mage goldPerReply is 25000c", lc[1].goldPerReply, 25000)
eq("20-29 Warrior goldPerReply is 10000c", lc[2].goldPerReply, 10000)

local gs = NS.CohortRows("guild_status", "gold", true)
eq("Guild vs Solo cohort separates In a Guild vs Guildless", gs[1].label, "In a Guild")
eq("In a Guild total gold is 50000c", gs[1].gold, 50000)

local tm = NS.CohortRows("template_method", "gold", true)
eq("Template x Channel separates Whisper and Mail", #tm, 2)

f.activeTab = "stats"
BegDB.settings.statsView = "cohorts"
BegDB.settings.statsCohort = "level_class"
NS.RefreshUINow()
truthy("Cohorts subtab bar is shown when view is cohorts", f.statsPane.cohortBar:IsShown())
has("Cohorts subtab renders 50-59 Mage row", f.statsPane.rows[1].cells.label:GetText(), "50-59 Mage")
has("Cohorts subtab renders Gold/reply cell", f.statsPane.rows[1].cells.goldPerReply:GetText(), "2g 50s")

-- 8. SettingsScan Hide() validation fix (cannot bypass checked()) ----------
BegDB.settings.minLevel = 10
BegDB.settings.maxLevel = 40
NS.UI.OpenSettings("scan")
local scanPage = NS.Settings.pages and NS.Settings.pages.scan
if scanPage and scanPage.fields and scanPage.fields.minLevel and scanPage.Hide then
  scanPage.fields.minLevel:SetText("55") -- invalid: > maxLevel (40)
  scanPage.Hide()
  eq("SettingsScan Hide() refuses minLevel > maxLevel", BegDB.settings.minLevel, 10)
  scanPage.fields.guildCooldownMinutes:SetText("45")
  scanPage.Hide()
  eq("SettingsScan Hide() saves valid guildCooldownMinutes", BegDB.settings.guildCooldownMinutes, 45)
end

-- 9. Direct-traded / un-asked funders appear in Funnel AND Cohort tables ---
Reset()
ERR_TRADE_COMPLETE = "Trade complete."
UnitName  = function(u) return u == "NPC" and "DirectDonor" or "Beggar" end
UnitLevel = function(u) return u == "NPC" and 54 or 7 end
UnitClass = function(u) return u == "NPC" and "Paladin" or "Warrior", u == "NPC" and "PALADIN" or "WARRIOR" end
UnitRace  = function(u) return u == "NPC" and "Human" or "Human" end
GetGuildInfo = function(u) return u == "NPC" and "Silver Hand" or nil end
GetRealZoneText = function() return "Stormwind City" end
GetTargetTradeMoney = function() return 25000 end
GetTradeTargetItemInfo = function(i) if i == 1 then return "Runecloth Bag", nil, 1 end end
GetTradeTargetItemLink = function(i) if i == 1 then return "[Runecloth Bag]" end end
Fire("TRADE_SHOW")
Fire("TRADE_ACCEPT_UPDATE", 1, 1)
Fire("UI_INFO_MESSAGE", 0, ERR_TRADE_COMPLETE)
local dd = NS.FindContact("DirectDonor")
eq("direct trader captures NPC level", dd and dd.level, 54)
eq("direct trader captures NPC class", dd and dd.class, "Paladin")
eq("direct trader captures NPC guild", dd and dd.guild, "Silver Hand")
local stDirect = NS.Stats()
eq("direct trader counted in funnel.funded even with 0 asks", stDirect.funnel.funded, 1)
eq("direct trader counted in funnel.gold", stDirect.funnel.gold, 25000)
local lcDirect = NS.CohortRows("level_class", "gold", true)
eq("direct trader appears in Level x Class cohort table", lcDirect[1] and lcDirect[1].label, "50-59 Paladin")
eq("cohort row carries direct trader gold", lcDirect[1] and lcDirect[1].gold, 25000)
eq("cohort row carries direct trader items", lcDirect[1] and lcDirect[1].items, 1)

-- 10. Data Integrity Fixes: Active GPH, Repeat Mail Dedup, Mail from attempts=0, Template Replied Drift --
-- A. Active GPH excludes 10-day offline gap
Reset()
local now2 = time()
local oldC = NS.EnsureContact("OldFunder", { level = 50, class = "Mage" })
oldC.attempts = 1; oldC.firstContactedAt = now2 - 864000; oldC.contactedAt = now2 - 864000
oldC.fundedAt = now2 - 862200; oldC.status = "funded"; oldC.countedFunded = true; oldC.goldIn = 50000 -- 5g over 30m active, 10 days ago
NS.TouchList()
local gphActive, _, actSec = NS.GoldPerHour(now2)
eq("Active GPH excludes 10-day offline gap (30m active = 1800s)", actSec, 1800)
eq("Active GPH is 10g/hr (100000c), not diluted by 10 days offline", math.floor(gphActive + 0.5), 100000)

-- B. Session GPH persists across /reload via BegDB.session
NS.TouchSessionAsk(now2 - 900)
NS.TouchSessionGift(25000, 1, now2)
NS.sessionFirstAskAt, NS.sessionGoldIn = nil, 0 -- simulate /reload clearing runtime locals
local dispGph, _, _, _, sessGph = NS.GoldPerHour(now2)
eq("Session GPH survives /reload (2.5g in 15m = 10g/hr)", math.floor(sessGph + 0.5), 100000)
eq("Top bar prefers active Session GPH", math.floor(dispGph + 0.5), 100000)
-- After >30m idle WITHOUT /reload, session expires cleanly and falls back to Active All-Time GPH
NS.TouchSessionAsk(now2 - 900)
NS.TouchSessionGift(25000, 1, now2)
local dispAfterIdle, _, _, _, sessGphIdle, _, _, allGphIdle = NS.GoldPerHour(now2 + 2400)
eq("Expired session (>30m idle without /reload) resets sessGph to 0", sessGphIdle, 0)
eq("Top bar falls back cleanly to Active All-Time GPH after idle", math.floor(dispAfterIdle + 0.5), math.floor(allGphIdle + 0.5))

-- C. Repeat mail gifts with same/blank subject on different days are BOTH counted
Reset()
local inbox2 = {}
GetInboxNumItems = function() return #inbox2 end
GetInboxHeaderInfo = function(i)
  local m = inbox2[i]
  return nil, nil, m.sender, m.subject, m.money or 0, 0, m.daysLeft or 30, m.items or 0, false, false
end
local mSender = NS.EnsureContact("MailPatron", { level = 60, class = "Priest" }) -- attempts = 0!
inbox2 = { { sender = "MailPatron", subject = "Thanks", money = 10000, daysLeft = 29.5 } }
Fire("MAIL_INBOX_UPDATE")
eq("mail gift from attempts=0 contact is credited", mSender.goldIn, 10000)
eq("mail gift marks them funded", mSender.status, "funded")
-- Second mail arrives next day with identical subject
inbox2 = {
  { sender = "MailPatron", subject = "Thanks", money = 0, daysLeft = 29.5 }, -- looted first mail
  { sender = "MailPatron", subject = "Thanks", money = 15000, daysLeft = 30.0 }, -- new second mail
}
Fire("MAIL_INBOX_UPDATE")
eq("second mail with same subject is NOT dropped", mSender.goldIn, 25000)

-- D. Direct-to-Funded credits both template.replied AND template.funded (no counter drift)
Reset()
local dC = NS.EnsureContact("DirectTradeTpl", { level = 55, class = "Rogue" })
NS.RecordSent(dC)
NS.SetStatus(dC, NS.STATUS.CONTACTED)
NS.SetStatus(dC, NS.STATUS.FUNDED)
eq("direct-to-Funded credits template.replied to match Stats.lua", NS.ActiveTemplate().replied, 1)
eq("direct-to-Funded credits template.funded", NS.ActiveTemplate().funded, 1)

-- E. In-addon AI Copilot /chatlog toggle button
local chatLogFlag = false
LoggingChat = function(v) if v ~= nil then chatLogFlag = v and true or false end; return chatLogFlag end
NS.UI.Open()
NS.RefreshUINow()
has("AI Copilot button defaults to AI Copilot when chatlog is off", NS.UI.frame.copilotBtn.text:GetText(), "AI Copilot")
NS.ToggleCopilotChatLog()
NS.RefreshUINow()
eq("ToggleCopilotChatLog enables Blizzard LoggingChat(true)", chatLogFlag, true)
has("AI Copilot button shows AI Log: ON when enabled", NS.UI.frame.copilotBtn.text:GetText(), "AI Log: ON")

-- 11. In-Addon 1-Click Smart Reply Mini-Bar & Customizable Post-Trade Close-Out --
Reset()
local sentWhispers, invitedNames, leftPartyCount, addedFriends = {}, {}, 0, {}
SendChatMessage = function(msg, ch, _, tgt) sentWhispers[#sentWhispers + 1] = { msg = msg, ch = ch, tgt = tgt } end
InviteUnit = function(n) invitedNames[#invitedNames + 1] = n end
LeaveParty = function() leftPartyCount = leftPartyCount + 1 end
AddFriend = function(n) addedFriends[#addedFriends + 1] = n end
IsInGroup = function() return true end
IsInRaid = function() return false end
GetNumGroupMembers = function() return 2 end
UnitInParty = function(n) return n == "WhaleDonor" end

-- A. Smart Reply intent detection & 1-click bar on incoming whisper
eq("DetectWhisperIntent location", NS.DetectWhisperIntent("haha sure where are you at?"), "location")
eq("DetectWhisperIntent invite", NS.DetectWhisperIntent("inv me plz"), "invite")
eq("DetectWhisperIntent decline", NS.DetectWhisperIntent("no get a job"), "decline")
eq("DetectWhisperIntent amount", NS.DetectWhisperIntent("how much do u need?"), "amount")
eq("DetectWhisperIntent trade", NS.DetectWhisperIntent("omw to stormwind"), "trade")

local sr = NS.EnsureContact("Shadow Dru", { level = 55, class = "Druid", classToken = "DRUID" })
BegDB.settings.smartReplyPopup = true
BegDB.settings.smartReplyLocation = "by Ironforge bank"
NS.OnWhisperIn("sure where are you at?", "Shadow Dru")
truthy("Smart Reply mini-bar pops on incoming whisper", NS.UI.smartReply and NS.UI.smartReply:IsShown())
NS.UI.smartReply.b1:GetScript("OnClick")(NS.UI.smartReply.b1)
eq("Smart Reply 1-click sends location whisper", #sentWhispers, 1)
has("Smart Reply whisper includes custom location", sentWhispers[1].msg, "by Ironforge bank")
eq("Smart Reply bar hides after clicking", NS.UI.smartReply:IsShown(), false)

-- Decline 1-click marks contact declined
NS.lastSendAt = nil
NS.OnWhisperIn("no sorry im broke", "Shadow Dru")
truthy("Smart Reply pops for decline", NS.UI.smartReply:IsShown())
NS.UI.smartReply.b1:GetScript("OnClick")(NS.UI.smartReply.b1)
eq("Decline 1-click moves contact to declined", sr.status, "declined")

-- B. Post-Trade Close-Out toast: standard vs big-tip + 1-click Thanks + Leave + Friend
NS.lastSendAt = nil
ERR_TRADE_COMPLETE = "Trade complete."
local whale = NS.EnsureContact("WhaleDonor", { level = 60, class = "Paladin", classToken = "PALADIN" })
BegDB.settings.postTradePopup = true
BegDB.settings.postTradeLeaveGroup = true
BegDB.settings.postTradeAddFriend = true
BegDB.settings.postTradeBigThreshold = 10000 -- 1g
BegDB.settings.postTradeAutoLeave = false

UnitName = function(u) return u == "NPC" and "WhaleDonor" or "Beggar" end
GetTargetTradeMoney = function() return 20000 end -- 2g (>= 1g big tip!)
GetTradeTargetItemInfo = function(i) if i == 1 then return "Runecloth Bag", nil, 1 end end
GetTradeTargetItemLink = function(i) if i == 1 then return "[Runecloth Bag]" end end
Fire("TRADE_SHOW")
Fire("TRADE_ACCEPT_UPDATE", 1, 1)
Fire("UI_INFO_MESSAGE", 0, ERR_TRADE_COMPLETE)

truthy("Post-Trade Close-Out toast pops on completed trade", NS.UI.tradeToast and NS.UI.tradeToast:IsShown())
has("Big tip uses postTradeBigThankYou template", NS.UI.tradeToast.data.thankText, "WHOA tysm WhaleDonor!!")
has("Thank-you substitutes {gift} with gold and item", NS.UI.tradeToast.data.thankText, "Runecloth Bag")
local beforeW = #sentWhispers
NS.UI.tradeToast.primaryBtn:GetScript("OnClick")(NS.UI.tradeToast.primaryBtn)
eq("1-click primary button sends thank-you whisper", #sentWhispers, beforeW + 1)
eq("1-click primary button leaves party", leftPartyCount, 1)
eq("1-click primary button adds big-tip donor to friends", addedFriends[1], "WhaleDonor")
eq("Post-Trade toast hides after click", NS.UI.tradeToast:IsShown(), false)

-- C. Auto-leave guard: leaves 2-man party with trader, NEVER leaves 5-man dungeon party
BegDB.settings.postTradeAutoLeave = true
leftPartyCount = 0
GetNumGroupMembers = function() return 5 end
Fire("TRADE_SHOW"); Fire("TRADE_ACCEPT_UPDATE", 1, 1); Fire("UI_INFO_MESSAGE", 0, ERR_TRADE_COMPLETE)
eq("Auto-leave NEVER kicks you out of a 5-man dungeon party", leftPartyCount, 0)
GetNumGroupMembers = function() return 2 end
Fire("TRADE_SHOW"); Fire("TRADE_ACCEPT_UPDATE", 1, 1); Fire("UI_INFO_MESSAGE", 0, ERR_TRADE_COMPLETE)
eq("Auto-leave leaves 2-man party with trader immediately", leftPartyCount, 1)




