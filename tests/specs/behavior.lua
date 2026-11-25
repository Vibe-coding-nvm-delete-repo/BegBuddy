-- The rules the split into smaller files must keep: nothing is ever sent without a click, the send guards,
-- scans that split full bands, mail problems, and the backup export.

local sent, mails
local function client()
  sent, mails = {}, {}
  SendChatMessage = function(text, _, _, target) sent[#sent + 1] = target .. ":" .. text end
  SendMail = function(target) mails[#mails + 1] = target end
  GetMoney, GetSendMailPrice = function() return 1000 end, function() return 30 end
  ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
  ERR_CHAT_THROTTLED = "You are sending too fast"
  ERR_MAIL_TARGET_NOT_FOUND, ERR_MAIL_REACHED_CAP = "Target not found", "Cap reached"
  WHO_RESULTS, WHO_MATCHED = {}, nil
  C_FriendList.GetNumWhoResults = function() return #WHO_RESULTS, WHO_MATCHED or #WHO_RESULTS end
  C_FriendList.GetWhoInfo = function(i) return WHO_RESULTS[i] end
end
local function who(name) return { fullName = name, level = 7, classStr = "Mage", classFile = "MAGE", area = "Orgrimmar" } end

-- Nothing goes out on its own
client()
Reset()
NS.EnsureContact("Bob", { level = 5 })
NS.EnsureContact("Ann", { level = 6 })
Fire("CHAT_MSG_WHISPER", "hello", "Bob")
Fire("CHAT_MSG_WHISPER", "who are you", "Stranger")
Fire("CHAT_MSG_SYSTEM", "No player named 'Bob' is currently playing.")
BegDB.selectedCity = "Orgrimmar"
BegDB.zoneSel = { Orgrimmar = true }
WHO_RESULTS = { who("Cat") }
NS.ScanNextSlice()
Fire("WHO_LIST_UPDATE")
Fire("MAIL_SHOW")
Fire("MAIL_INBOX_UPDATE")
Fire("MAIL_CLOSED")
Fire("PLAYER_REGEN_DISABLED")
Fire("PLAYER_REGEN_ENABLED")
check("events, scans and whispers in never send a whisper or a mail", #sent == 0 and #mails == 0)
check("a whisper in makes a thread on the card", NS.FindContact("Bob").history[1].text == "hello"
  and NS.FindContact("Bob").status == "replied")

-- With the setting off, a send only loads the chat box: the player presses Enter
client()
Reset()
local loaded
ChatFrame_OpenChat = function(text) loaded = text end
NS.EnsureContact("Bob", { level = 5 })
local bob = NS.FindContact("Bob")
BegDB.settings.oneClickSend = false
check("Load whisper fills the chat box", NS.WhisperContact(bob) and loaded:find("/w Bob ", 1, true) == 1)
check("and sends nothing", #sent == 0)
check("the card only moves once the game confirms the send", bob.status == "queued")
Fire("CHAT_MSG_WHISPER_INFORM", "Hi", "Bob")
check("the confirmed send counts one attempt", bob.status == "contacted" and bob.attempts == 1)
ChatFrame_OpenChat = nil

-- The send guards
client()
Reset()
NS.EnsureContact("Bob", { level = 5 })
bob = NS.FindContact("Bob")
BegDB.settings.oneClickSend = true -- the whisper buttons send (off by default)
BegDB.paused = true
check("a paused send is refused", not NS.QuickSend(bob) and #sent == 0)
BegDB.paused = false
NS.inCombat = true
check("a send in combat is refused", not NS.QuickSend(bob) and #sent == 0)
NS.inCombat = false
check("one click sends one whisper", NS.QuickSend(bob) and #sent == 1)
local allowed, why = NS.CanWhisper(bob)
check("a second click on the same name is refused", not allowed and why:find("Just whispered", 1, true) ~= nil)
NOW = NOW + 6
allowed, why = NS.CanWhisper(bob)
check("an unconfirmed send holds the name for a minute", not allowed and why:find("Already sent", 1, true) ~= nil)
NOW = NOW + 60
check("then it is free again", NS.CanWhisper(bob) == true)
Fire("CHAT_MSG_WHISPER_INFORM", "Hi", "Bob")
allowed, why = NS.CanWhisper(bob)
check("the re-whisper wait starts on a confirmed send", not allowed and why:find("Wait another", 1, true) ~= nil)
for status, words in pairs({ replied = "already replied", declined = "closed out", blocked = "closed out", funded = "funded" }) do
  bob.status = status
  allowed, why = NS.CanWhisper(bob)
  check("a " .. status .. " name gets no opener", not allowed and why:find(words, 1, true) ~= nil)
end

-- Three warnings in a minute pause sending
client()
Reset()
NS.EnsureContact("Bob", { level = 5 })
bob = NS.FindContact("Bob")
NS.QuickSend(bob)
Fire("CHAT_MSG_SYSTEM", "No player named 'Bob' is currently playing.")
check("an offline answer archives the name", bob.status == "archived" and bob.note == "not playing")
NS.lastSendAt, NS.lastSendKey = NOW, bob.key
for _ = 1, 3 do Fire("CHAT_MSG_SYSTEM", "You are sending too fast") end
check("three server warnings pause sending", BegDB.paused == true)

-- A full /who band is split into smaller scans
client()
Reset()
BegDB.settings.minLevel, BegDB.settings.maxLevel, BegDB.settings.bandSize = 1, 3, 3
BegDB.selectedCity = "Orgrimmar"
BegDB.zoneSel = { Orgrimmar = true }
NS.ScanNextSlice()
check("a scan asks for the band", SENT_WHO == 'z-"Orgrimmar" 1-3')
check("it is busy until the server answers", NS.scan.busy == true)
WHO_RESULTS, WHO_MATCHED = { who("Zip"), who("Cat") }, 60
Fire("WHO_LIST_UPDATE")
check("a full band queues one scan per level", NS.PendingSplits("Orgrimmar") == 3)
check("the player's own name is never queued", NS.FindContact("Zip") == nil and NS.FindContact("Cat") ~= nil)
NS.ScanNextSlice()
check("the extra scan runs next", SENT_WHO == 'z-"Orgrimmar" 1-1')
WHO_RESULTS, WHO_MATCHED = {}, 60
Fire("WHO_LIST_UPDATE")
check("a full single level queues one scan per class", NS.PendingSplits("Orgrimmar") > 3)
check("a declined name stays declined when found again", (function()
  NS.SetStatus(NS.FindContact("Cat"), "declined")
  NS.ScanNextSlice()
  WHO_RESULTS, WHO_MATCHED = { who("Cat") }, nil
  Fire("WHO_LIST_UPDATE")
  return NS.FindContact("Cat").status == "declined"
end)())

-- The class picks (tick as many as you like)
client()
Reset()
BegDB.settings.minLevel, BegDB.settings.maxLevel, BegDB.settings.bandSize = 1, 6, 3
BegDB.selectedCity = "Orgrimmar"
BegDB.zoneSel = { Orgrimmar = true }
check("no class is ticked at first", NS.ScanClasses() == nil and NS.ScanClassKey() == nil)
NS.ToggleScanClass("MAGE")
check("a tick is saved by class token", BegDB.settings.scanClasses.MAGE == true and NS.IsScanClass("MAGE"))
NS.ScanNextSlice()
check("one class asks for that class", SENT_WHO == 'z-"Orgrimmar" 1-3 c-"Mage"')
WHO_RESULTS, WHO_MATCHED = { who("Cat") }, nil
Fire("WHO_LIST_UPDATE")
check("the band is credited once its class has answered", NS.GetProgress("Orgrimmar") == 1)
NS.ScanNextSlice()
check("the next band asks for the same class", SENT_WHO == 'z-"Orgrimmar" 4-6 c-"Mage"')
Fire("WHO_LIST_UPDATE")

-- Two classes: each band gets one scan per class, in class order
BegDB.progress = {}
NS.ToggleScanClass("ROGUE")
check("two ticks are kept", NS.IsScanClass("MAGE") and NS.IsScanClass("ROGUE") and #NS.ScanClasses() == 2)
local first, second = NS.ScanClasses()[1], NS.ScanClasses()[2]
WHO_RESULTS, WHO_MATCHED = {}, nil
NS.ScanNextSlice()
check("the first class of band one", SENT_WHO == 'z-"Orgrimmar" 1-3 c-"' .. first .. '"')
check("the other class of that band waits in the queue", NS.PendingSplits("Orgrimmar") == 2)
check("the next step text names the class and the band", NS.NextStepText():find(first, 1, true) ~= nil)
Fire("WHO_LIST_UPDATE")
NS.ScanNextSlice()
check("the second class of band one", SENT_WHO == 'z-"Orgrimmar" 1-3 c-"' .. second .. '"')
Fire("WHO_LIST_UPDATE")
check("then the plan moves on", NS.GetProgress("Orgrimmar") == 1 and NS.PendingSplits("Orgrimmar") == 0)
NS.ScanNextSlice()
check("band two starts with the first class again", SENT_WHO == 'z-"Orgrimmar" 4-6 c-"' .. first .. '"')
Fire("WHO_LIST_UPDATE")

-- Full band with a class: cut into levels, keeping the class
BegDB.progress = {}
NS.ClearScanClasses()
NS.ToggleScanClass("PRIEST")
NS.ScanNextSlice()
WHO_RESULTS, WHO_MATCHED = { who("Zip"), who("Cat") }, 60
Fire("WHO_LIST_UPDATE")
check("a full band with a class queues one scan per level", NS.PendingSplits("Orgrimmar") == 3)
NS.ScanNextSlice()
check("the level scan keeps the class", SENT_WHO == 'z-"Orgrimmar" 1-1 c-"Priest"')
WHO_RESULTS, WHO_MATCHED = {}, 60
Fire("WHO_LIST_UPDATE")
check("a full level with a class has no per-class scans left", NS.PendingSplits("Orgrimmar") == 2)

-- Changing the picks
NS.ToggleScanClass("WARRIOR")
check("changing the picks drops the extra scans", NS.PendingSplits("Orgrimmar") == 0)
check("and gives the new set its own progress", NS.GetProgress("Orgrimmar") == 0)
NS.ClearScanClasses()
check("clearing goes back to every class", NS.ScanClasses() == nil and NS.GetProgress("Orgrimmar") == 0)
NS.ScanNextSlice()
check("with none ticked the query has no class", SENT_WHO == 'z-"Orgrimmar" 1-3')
Fire("WHO_LIST_UPDATE")

-- The picker button
Reset()
BegBuddyFrame:Show()
NS.RefreshUINow()
check("the picker starts on All classes", BegBuddyFrame.classDrop.label:GetText():find("All classes", 1, true) ~= nil)
NS.ToggleScanClass("ROGUE")
NS.ToggleScanClass("MAGE")
NS.RefreshUINow()
local lbl = BegBuddyFrame.classDrop.label:GetText()
check("ticked classes show in their own colour", lbl:find(NS.ClassHex("MAGE") .. "Mage", 1, true) ~= nil
  and lbl:find(NS.ClassHex("ROGUE") .. "Rogue", 1, true) ~= nil)
NS.ToggleScanClass("DRUID")
NS.RefreshUINow()
check("more than two show a +N", BegBuddyFrame.classDrop.label:GetText():find("+1", 1, true) ~= nil)
BegBuddyFrame.classDrop.scripts.OnClick(BegBuddyFrame.classDrop)
check("opening the picker builds it without error", true)

-- Starting zones
Reset()
local starting
for _, g in ipairs(NS.ZoneGroups()) do if g.id == "starting" then starting = g end end
check("the zone picker has a Starting zones group", starting ~= nil and starting.label == "Starting zones")
local has = {}
for _, z in ipairs(starting.zones) do has[z] = true end
check("it holds the six Classic starting zones",
  has["Elwynn Forest"] and has["Dun Morogh"] and has["Teldrassil"] and has["Durotar"] and has["Mulgore"] and has["Tirisfal Glades"])
BegDB.zoneSel = {}
NS.SetZoneSelected("Durotar", true)
local n = 0
for _, z in ipairs(NS.SelectedZones()) do if z == "Durotar" then n = n + 1 end end
check("a zone listed twice is still scanned once", n == 1 and #NS.SelectedZones() == 1)
check("a starting zone counts as built in", NS.IsBuiltInZone("Mulgore"))

-- Mail
client()
Reset()
NS.EnsureContact("Bob", { level = 5 })
NS.EnsureContact("Ann", { level = 6 })
bob = NS.FindContact("Bob")
check("no mail without an open mailbox", not NS.MailContact(bob) and #mails == 0)
Fire("MAIL_SHOW")
GetSendMailMoney = function() return 5 end
check("no mail while gold is set in the Send Mail tab", not NS.MailContact(bob) and #mails == 0)
GetSendMailMoney = nil
check("one click sends one mail", NS.MailContact(bob) and #mails == 1)
Fire("MAIL_SEND_SUCCESS")
check("a confirmed mail contacts the name", bob.status == "contacted" and bob.mailedAt ~= nil)
NOW = NOW + 6
local ann = NS.FindContact("Ann")
NS.MailContact(ann)
Fire("UI_ERROR_MESSAGE", 1, "Target not found")
check("a recipient error archives the name", ann.status == "archived")
NOW = NOW + 6
bob.status = "queued"
NS.lastLoadedAt = nil
NS.sentAt = {}
NS.MailContact(bob)
Fire("UI_ERROR_MESSAGE", 1, "Cap reached")
check("a sender error pauses sending and spares the name", BegDB.paused == true and bob.status == "queued")
BegDB.paused = false

GetInboxNumItems, GetInboxHeaderInfo = function() return 1 end, function() return nil, nil, "Bob", "Gold", 500, nil, nil, nil, nil, false end
Fire("MAIL_INBOX_UPDATE")
check("gold in the inbox funds the name", bob.status == "funded")
local n = #bob.history
Fire("MAIL_INBOX_UPDATE")
check("the same mail is only handled once", #bob.history == n)
GetInboxNumItems, GetInboxHeaderInfo = nil, nil
Fire("MAIL_CLOSED")

-- The backup, and the window drawn from it
local export = NS.BuildExport()
check("the export lists every section", export:find("=== FUNDED (1) ===", 1, true) and export:find("=== TEMPLATES ===", 1, true)
  and export:find("=== MAIL TEMPLATES ===", 1, true) and export:find("them: [mail] Gold", 1, true))
NS.activeContact = bob
BegBuddyFrame:Show()
NS.RefreshUINow()
check("the window draws the open card", BegBuddyFrame.detail.name.text:find("Bob", 1, true) ~= nil
  and BegBuddyFrame.detail.history.fs.text:find("[mail] Gold", 1, true) ~= nil)
check("the tabs carry their counts", BegBuddyFrame.tabButtons[4].text.text:find("Funded 1", 1, true) ~= nil)
NS.UI.ShowCopy("copy me")
check("the copy box shows the text", BegBuddyCopy.box.text == "copy me")
NS.UI.ShowPopout(bob)
check("the history popout opens on the card", BegBuddyPopout:IsShown() and BegBuddyPopout.title.text:find("Bob", 1, true) ~= nil)

-- WoW: Forever hides some chat text, names and /who answers: a hidden value changes nothing.
client()
Reset()
EnableSecrets()
local function contactCount() local n = 0; for _ in pairs(BegDB.contacts) do n = n + 1 end return n end
NS.EnsureContact("Bob", { level = 5 })
local hiddenBob = NS.FindContact("Bob")
BegDB.selectedCity = "Orgrimmar"
BegDB.zoneSel = { Orgrimmar = true }
WHO_RESULTS = { who(HIDDEN), who("Cat") }
local added = NS.Harvest()
check("a /who answer with a hidden name is skipped and the readable one is kept", added == 1 and NS.FindContact("Cat") ~= nil)
local before, historyBefore = contactCount(), #(hiddenBob.history or {})
Fire("CHAT_MSG_WHISPER", HIDDEN, "Bob")
check("a hidden whisper line is not added to the card or marked as a reply", #(hiddenBob.history or {}) == historyBefore and hiddenBob.status ~= "replied")
Fire("CHAT_MSG_WHISPER", "hello", "Zzhidtwo")
check("a whisper from a hidden name makes no new contact", contactCount() == before)

-- The online check: an answer the game hides, in part or whole, cannot prove a name is offline.
client()
Reset()
EnableSecrets()
NS.EnsureContact("Dan", { level = 5 })
local dan = NS.FindContact("Dan")
WHO_RESULTS = { { fullName = HIDDEN, level = 7, classStr = "Mage", classFile = "MAGE", area = "Orgrimmar" } }
check("the online check for the first name starts", NS.CheckContact(dan) == true)
Fire("WHO_LIST_UPDATE")
check("a hidden /who entry does not archive the name as offline", dan.status ~= "archived" and NS.CheckState(dan.key) ~= "offline")
NS.EnsureContact("Eve", { level = 5 })
local eve = NS.FindContact("Eve")
WHO_RESULTS = {}
C_FriendList.GetNumWhoResults = function() return HIDDEN, HIDDEN end
check("the online check for the second name starts", NS.CheckContact(eve) == true)
Fire("WHO_LIST_UPDATE")
check("hidden /who counts do not archive the name as offline", eve.status ~= "archived" and NS.CheckState(eve.key) ~= "offline")
DisableSecrets()
