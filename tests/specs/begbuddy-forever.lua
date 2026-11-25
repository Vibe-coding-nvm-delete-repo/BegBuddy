-- The launch fixes for WoW: Forever (#54): the C_ API names, hidden values, the send guards, realms and defaults.

local sent, msgs
local function client()
  sent, msgs = {}, {}
  SendChatMessage = function(text, kind, _, target)
    sent[#sent + 1] = tostring(target) .. ":" .. text
    msgs[#msgs + 1] = { text = text, kind = kind, target = target }
  end
  ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
  WHO_RESULTS, WHO_MATCHED = {}, nil
  C_FriendList.GetNumWhoResults = function() return #WHO_RESULTS, WHO_MATCHED or #WHO_RESULTS end
  C_FriendList.GetWhoInfo = function(i) return WHO_RESULTS[i] end
end
local function contactCount() local n = 0; for _ in pairs(BegDB.contacts) do n = n + 1 end return n end
local function printed(text) return table.concat(PRINTS, "\n"):find(text, 1, true) ~= nil end

-- Forever has no GetCoinTextureString global, only C_CurrencyInfo's
client()
GetCoinTextureString = nil
C_CurrencyInfo = { GetCoinTextureString = function(copper) return "COIN" .. copper end }
Reset()
check("gold amounts use C_CurrencyInfo.GetCoinTextureString when the old global is gone", NS.Coins(500) == "COIN500")
C_CurrencyInfo = nil
Reset()
check("and still read without either", NS.Coins(10203) == "1g 2s 3c")

-- Hidden values (WoW: Forever) change nothing
client()
Reset()
EnableSecrets()
WHO_RESULTS = { { fullName = "Cat", level = 7, classStr = "Mage", filename = HIDDEN, area = "Orgrimmar" } }
NS.Harvest()
check("a /who entry whose class token is hidden is skipped, not stored", NS.FindContact("Cat") == nil)
local before = contactCount()
local ok = BegBuddyAPI.Track(HIDDEN, "Copperline")
check("BegBuddyAPI.Track refuses a hidden name and adds nothing", not ok and contactCount() == before)
check("BegBuddyAPI.Status of a hidden name is unknown", BegBuddyAPI.Status(HIDDEN) == nil)
local box = { GetAttribute = function(_, k) return ({ chatType = "WHISPER", tellTarget = HIDDEN })[k] end }
ChatEdit_GetActiveWindow = function() return box end
check("a quick message to a hidden /reply target sends nothing when nobody is open", not NS.SendQuick("Hi!") and #msgs == 0)
NS.EnsureContact("Bob", { level = 5 })
NS.activeContact = NS.FindContact("Bob")
NS.SendQuick("Hi {name}!")
check("and goes to the person open instead", #msgs == 1 and msgs[1].kind == "WHISPER" and msgs[1].text == "Hi Bob!")
ChatEdit_GetActiveWindow = nil
NS.mail.pending = { key = NS.activeContact.key, subject = "s", body = "b", at = NOW }
Fire("UI_ERROR_MESSAGE", 1, HIDDEN)
check("a hidden error line is not taken as the mail's error", NS.mail.lastError == nil)
NS.mail.pending = nil
DisableSecrets()

-- Auto keeps the Send gap (BB-04) and only says "Sent" once the game confirms it (BB-06)
client()
Reset()
for _, n in ipairs({ "Ann", "Bob", "Cat" }) do NS.EnsureContact(n, { level = 5 }) end
check("Auto whispers the top name", NS.SendNext() and #sent == 1)
check("and says it is whispering, not that it was sent", printed("Whispering Ann...") and not printed("Sent to Ann"))
Fire("CHAT_MSG_WHISPER_INFORM", "Hi", "Ann")
check("the confirm says it was sent and how many are left", printed("Sent to Ann. 2 left."))
NOW = NOW + 0.5
check("a click inside the Send gap sends nothing", not NS.SendNext() and #sent == 1)
NOW = NOW + 2
check("after the gap the next click sends", NS.SendNext() and #sent == 2)

-- Being ignored closes the name out (BB-06)
client()
Reset()
NS.EnsureContact("Bob", { level = 5 })
local bob = NS.FindContact("Bob")
NS.SendNext()
Fire("CHAT_MSG_IGNORED", "", "Bob")
check("a name that ignores you moves to Declined", bob.status == "declined" and bob.note == "ignores you")
NOW = NOW + 120
check("and Auto never whispers it again", not NS.SendNext() and #sent == 1)
Fire("CHAT_MSG_RESTRICTED", "")
check("a chat restriction pauses sending", BegDB.paused == true)

-- Only real whisper failures count as server warnings (BB-05)
client()
Reset()
ERR_FRIEND_ONLINE_SS = "[%s] has come online."
NS.EnsureContact("Bob", { level = 5 })
bob = NS.FindContact("Bob")
NS.QuickSend(bob)
for _ = 1, 3 do Fire("CHAT_MSG_SYSTEM", "[Guildie] has come online.") end
check("login lines near a send are not filed on the card", #(bob.history or {}) == 0)
check("and do not pause sending", BegDB.paused ~= true)
ERR_CHAT_PLAYER_AMBIGUOUS_S = "%s is ambiguous."
Fire("CHAT_MSG_SYSTEM", "Bob is ambiguous.")
check("a real whisper failure is still filed on the card", bob.history[#bob.history].text == "Bob is ambiguous.")

-- Chat lockdown (WoW: Forever): no openers, and a hidden confirm keeps the full hold (BB-02, BB-08)
client()
Reset()
NS.EnsureContact("Bob", { level = 5 })
bob = NS.FindContact("Bob")
C_ChatInfo = { InChatMessagingLockdown = function() return true end }
check("an opener is refused while chat is locked", not NS.QuickSend(bob) and not NS.SendNext() and #sent == 0)
check("a reply is refused while chat is locked", not NS.SendReply(bob, "hi") and #sent == 0)
ChatEdit_GetActiveWindow = function() return { GetAttribute = function(_, k) return ({ chatType = "PARTY" })[k] end } end
check("a quick message to party is refused while chat is locked", not NS.SendQuick("Hi!") and #msgs == 0)
ChatEdit_GetActiveWindow = nil
C_ChatInfo = nil
check("once chat is open again the opener goes out", NS.QuickSend(bob) and #sent == 1)
EnableSecrets()
Fire("CHAT_MSG_WHISPER_INFORM", HIDDEN, HIDDEN)
DisableSecrets()
NOW = NOW + 63
check("a hidden confirm keeps the name held past one minute", NS.CanWhisper(bob) == false and not NS.SendNext() and #sent == 1)
NOW = NOW + 30 * 60
check("and frees it after the re-whisper wait", NS.CanWhisper(bob) == true)

-- An archived name is still guarded (found by the verifier)
client()
Reset()
NS.EnsureContact("Bob", { level = 5 })
NS.EnsureContact("Ann", { level = 5 })
bob, ann = NS.FindContact("Bob"), NS.FindContact("Ann")
NS.QuickSend(bob)
Fire("CHAT_MSG_WHISPER_INFORM", "Hi", "Bob")
NS.SetStatus(bob, "archived")
NS.sentAt, NS.lastLoadedKey = {}, nil -- a /reload forgets the session holds
NOW = NOW + 60
local allowed, why = NS.CanWhisper(bob)
check("a name archived just after it was asked waits out the re-whisper time", not allowed and why:find("Wait another", 1, true) ~= nil)
NS.SetStatus(ann, "replied")
NS.SetStatus(ann, "archived")
NOW = NOW + 2 * 3600
bob.contactedAt = time() - 2 * 3600 -- the card's clock is time(), not GetTime()
allowed, why = NS.CanWhisper(ann)
check("a name that replied and was then archived never gets the opener again", not allowed and why:find("already replied", 1, true) ~= nil)
check("while an archived name that never answered can be tried again later", NS.CanWhisper(bob) == true)

-- Defaults the lead set for launch: the whisper button loads the chat box, strangers are not tracked (X2)
client()
Reset()
check("a new player's whisper button loads the chat box (One-click send is off)", BegDB.settings.oneClickSend == false)
check("a new player does not track strangers who whisper first", BegDB.settings.trackUnknownWhispers == false)
Fire("CHAT_MSG_WHISPER", "inv?", "Leader")
check("so a whisper from someone BegBuddy does not know makes no contact", NS.FindContact("Leader") == nil)
local page = BuildPage("message")
check("the Whisper settings page has a switch for it", ZipUI.Hub.byKey["begbuddy/message"] ~= nil and page ~= nil
  and NS.Settings.pages.message.track ~= nil)
BegDB.settings.trackUnknownWhispers = true
C_FriendList.GetFriendInfo = function(name) if name == "Pal" then return { name = "Pal" } end end
Fire("CHAT_MSG_WHISPER", "hey", "Pal")
check("with it on, a friend is still never added", NS.FindContact("Pal") == nil)
Fire("CHAT_MSG_WHISPER_INFORM", "lf1m?", "Leader2")
Fire("CHAT_MSG_WHISPER", "inv", "Leader2")
check("nor someone you whispered yourself", NS.FindContact("Leader2") == nil)
Fire("CHAT_MSG_WHISPER", "hi there", "Stranger")
check("but a real stranger is", NS.FindContact("Stranger") ~= nil and NS.FindContact("Stranger").status == "replied")
C_FriendList.GetFriendInfo = nil
