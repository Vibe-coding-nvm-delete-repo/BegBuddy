-- Quick messages (one-click whispers to the person open) and the Clear all button.

local sent
local function client()
  sent = {}
  SendChatMessage = function(text, _, _, target) sent[#sent + 1] = target .. ":" .. text end
end
local function click(b) b.scripts.OnClick(b) end
local function shownTexts()
  local out = {}
  for _, m in ipairs(NS.QuickShown()) do out[#out + 1] = m.text end
  return out
end
local function has(list, text)
  for _, t in ipairs(list) do if t == text then return true end end
  return false
end
local function buttonTexts(f)
  local out = {}
  for _, b in ipairs(f.quick.strip.buttons) do if b:IsShown() then out[#out + 1] = b.message end end
  return out
end

-- The starting list: Chris's seven first, exactly as he wrote them, then a friendly extra set
Reset()
local expected = { "Tysm!", "Tysm!!! You're the best!", "Yes please!", "I'm in front of the AH!",
  "I'm in front of the bank!", "I'm rich!!!", "Fuck yes tysm!" }
local q = BegDB.quickMessages
local firstSeven = true
for i, text in ipairs(expected) do if not q[i] or q[i].text ~= text then firstSeven = false end end
check("a new account starts with Chris's seven messages in order, worded exactly", firstSeven)
check("and a friendly set after them", #q > 7 and #q <= NS.QUICK_MAX)
local friendly = true
for _, want in ipairs({ "Thank you so much!", "Please!", "Where are you?", "One moment please!", "On my way!",
  "Sorry, I can't right now.", "No thanks, I'm good!", "What do you need?" }) do
  if not has(shownTexts(), want) then friendly = false end
end
check("covering thank you, please, where are you, one moment, on my way, sorry, no thanks and what do you need", friendly)
local fits = true
for _, m in ipairs(q) do if #m.text > 255 or m.hidden then fits = false end end
check("every starting message fits a whisper and is shown", fits)
check("the list is its own key, not part of the settings", BegDB.settings.quickMessages == nil)

-- An old save without the list gets the starting set; an emptied list stays empty
Reset({ settings = {}, contacts = {}, order = {} })
check("a save from before quick messages gets the starting list", #BegDB.quickMessages == #NS.DEFAULT_QUICK_MESSAGES)
BegDB.quickMessages = {}
NS.InitDB()
check("a list the player emptied is not refilled", #BegDB.quickMessages == 0)
BegDB.quickMessages = { "junk", { text = "Kept!" }, { notext = true } }
NS.InitDB()
check("a damaged entry is dropped, the rest stays", #BegDB.quickMessages == 1 and BegDB.quickMessages[1].text == "Kept!")

-- Sending
Reset()
client()
NS.EnsureContact("Bob", { level = 5 })
local bob = NS.FindContact("Bob")
check("with nobody open nothing is sent", not NS.SendQuick("Tysm!") and #sent == 0)
NS.activeContact = bob
check("with someone open it whispers them", NS.SendQuick("Tysm!") and sent[1] == "Bob:Tysm!")
NOW = NOW + 3
NS.SendQuick("Hi {name}, level {level}")
check("{name} and {level} fill in", sent[2] == "Bob:Hi Bob, level 5")
check("a second click inside the wait between sends is refused", (function()
  local n = #sent
  NS.SendQuick("Again!")
  return #sent == n
end)())
NOW = NOW + 3
local n = #sent
NS.SendQuick("   ")
NS.SendQuick("")
NS.SendQuick(nil)
check("a blank message sends nothing", #sent == n)
NS.SendQuick(string.rep("a", 300))
check("a long message is cut to 255", #sent == n + 1 and #sent[#sent] == #"Bob:" + 255)
NOW = NOW + 3
BegDB.paused = true
check("Pause does not stop a reply to someone talking to you", NS.SendQuick("Pausing!") and sent[#sent] == "Bob:Pausing!")
BegDB.paused = false
NOW = NOW + 3
NS.inCombat = true
n = #sent
check("nothing goes out in combat", not NS.SendQuick("Combat!") and #sent == n)
NS.inCombat = false
BegDB.contacts[bob.key] = nil
check("a contact that was deleted is not whispered", not NS.SendQuick("Gone!") and #sent == n)

-- Changing the list
Reset()
local m = NS.AddQuick("  Mine!  ")
check("Add puts a trimmed message at the end", m and BegDB.quickMessages[#BegDB.quickMessages].text == "Mine!")
check("Add refuses a blank message", NS.AddQuick("   ") == nil)
NS.MoveQuick(#BegDB.quickMessages, -1)
check("Move swaps with the neighbour", BegDB.quickMessages[#BegDB.quickMessages - 1].text == "Mine!")
check("Move off the end does nothing", NS.MoveQuick(1, -1) == false)
BegDB.quickMessages[1].hidden = true
check("a hidden message is not shown", not has(shownTexts(), "Tysm!") and #shownTexts() == #BegDB.quickMessages - 1)
while #BegDB.quickMessages < NS.QUICK_MAX do NS.AddQuick("x") end
local full, err = NS.AddQuick("one more")
check("the list stops at its limit and says so", full == nil and err:find(tostring(NS.QUICK_MAX), 1, true) ~= nil)
check("Delete removes one", NS.RemoveQuick(1) and #BegDB.quickMessages == NS.QUICK_MAX - 1)
NS.ResetQuick()
check("Restore brings back the starting list", #BegDB.quickMessages == #NS.DEFAULT_QUICK_MESSAGES and BegDB.quickMessages[1].text == "Tysm!")

-- The buttons in the main window
Reset()
client()
SlashCmdList.BEGBUDDY("")
local f = BegBuddyFrame
NS.EnsureContact("Bob", { level = 5 })
NS.EnsureContact("Ann", { level = 6 })
NS.RefreshUINow()
check("one button per shown message", #buttonTexts(f) == #NS.QuickShown() and buttonTexts(f)[1] == "Tysm!")
check("the buttons are live with nobody open, since the chat box may be the target", f.quick.strip.buttons[1].disabled == false)
NS.inCombat = true
NS.RefreshUINow()
check("and greyed out in combat", f.quick.strip.buttons[1].disabled == true)
NS.inCombat = false
NS.activeContact = NS.FindContact("Bob")
NS.RefreshUINow()
check("and live again after it", f.quick.strip.buttons[1].disabled == false)
click(f.quick.strip.buttons[2])
check("clicking a button whispers that message to the person open", sent[1] == "Bob:Tysm!!! You're the best!")
check("the strip makes room by lifting the history off the reply row", f.detail.history.point[3] > 34)
NS.activeContact = nil
NS.RefreshUINow()
click(f.quick.strip.buttons[1])
check("clicking with nobody open and the chat box closed sends nothing", #sent == 1)
check("and says what to do", PRINTS[#PRINTS]:find("cursor in the chat box", 1, true) ~= nil)

-- Where the cursor is: the chat box's channel wins over the person open
local msgs
local function chatClient()
  msgs = {}
  SendChatMessage = function(text, kind, _, target) msgs[#msgs + 1] = { text = text, kind = kind, target = target } end
end
local box
local function chatBox(kind, target)
  if not kind then box = nil return end
  local attrs = { chatType = kind, tellTarget = (kind == "WHISPER" or kind == "BN_WHISPER") and target or nil,
    channelTarget = (kind == "CHANNEL") and target or nil }
  box = { GetAttribute = function(_, k) return attrs[k] end }
end
ChatEdit_GetActiveWindow = function() return box end
local function last() return msgs[#msgs] end

Reset()
chatClient()
NS.EnsureContact("Bob", { level = 5 })
NS.EnsureContact("Ann", { level = 6 })
chatBox("PARTY")
check("with the cursor in the chat box set to Party and nobody open, the message goes to party chat",
  NS.SendQuick("On my way!") and #msgs == 1 and last().kind == "PARTY" and last().target == nil and last().text == "On my way!")
for _, kind in ipairs({ "SAY", "GUILD", "RAID", "YELL", "OFFICER", "RAID_WARNING", "INSTANCE_CHAT", "BATTLEGROUND", "EMOTE" }) do
  chatBox(kind)
  NS.SendQuick("Hi!")
  check("the chat box set to " .. kind .. " sends there", last().kind == kind and last().target == nil and last().text == "Hi!")
end
chatBox("CHANNEL", 2)
NS.SendQuick("Hi!")
check("a numbered channel sends to that number", last().kind == "CHANNEL" and last().target == 2)
chatBox("CHANNEL", nil)
local n = #msgs
check("a channel with no number sends nothing", not NS.SendQuick("Hi!") and #msgs == n)
chatBox("WEIRD")
check("a kind the game cannot send to sends nothing and says so", not NS.SendQuick("Hi!") and #msgs == n
  and PRINTS[#PRINTS]:find("WEIRD", 1, true) ~= nil)
chatBox("PARTY")
NS.activeContact = NS.FindContact("Bob")
NS.SendQuick("Hi {name}!")
check("with someone open too, the chat box still wins and {name} is the person open",
  last().kind == "PARTY" and last().text == "Hi Bob!")
chatBox("PARTY")
NS.SendQuick("Again!")
check("party messages do not wait for the gap between whispers", last().text == "Again!")
chatBox("WHISPER", "Ann")
NOW = NOW + 3
NS.SendQuick("Hi {name}!")
check("the chat box set to whisper Ann goes to Ann, not the person open, and {name} is Ann",
  last().kind == "WHISPER" and last().target == "Ann" and last().text == "Hi Ann!")
check("and it counts as a send to Ann", NS.lastSendKey == NS.FindContact("Ann").key)
chatBox("WHISPER", "Zed-Realm")
NOW = NOW + 3
NS.SendQuick("Hi {name}!")
check("a whisper to someone BegBuddy does not know still goes out, by name", last().kind == "WHISPER"
  and last().target == "Zed-Realm" and last().text == "Hi Zed!")
chatBox("WHISPER", "")
NOW = NOW + 3
NS.SendQuick("Hi!")
check("a whisper box with no name yet falls back to the person open", last().kind == "WHISPER" and last().target == "Bob")
chatBox("WHISPER", "Ann")
n = #msgs
NS.SendQuick("Too soon!")
check("a whisper from the chat box still waits for the gap between whispers", #msgs == n)
chatBox(nil)
NOW = NOW + 3
NS.SendQuick("Hi!")
check("with the chat box closed it whispers the person open", last().kind == "WHISPER" and last().target == "Bob")
chatBox("PARTY")
NS.inCombat = true
n = #msgs
check("nothing goes to a channel in combat", not NS.SendQuick("Hi!") and #msgs == n)
NS.inCombat = false
BegDB.paused = true
NS.SendQuick("Paused!")
check("Pause does not stop a channel message", last().kind == "PARTY" and last().text == "Paused!")
BegDB.paused = false

-- Battle.net whispers need the friend's id
local bn = {}
BNet_GetBNetIDAccount = function(name) return name == "Pal" and 77 or nil end
BNSendWhisper = function(id, text) bn[#bn + 1] = id .. ":" .. text end
chatBox("BN_WHISPER", "Pal")
check("a Battle.net whisper goes through BNSendWhisper", NS.SendQuick("Hi!") and bn[1] == "77:Hi!")
chatBox("BN_WHISPER", "Nobody")
check("an unknown Battle.net friend sends nothing and says so", not NS.SendQuick("Hi!") and #bn == 1
  and PRINTS[#PRINTS]:find("Battle.net", 1, true) ~= nil)
BNet_GetBNetIDAccount, BNSendWhisper = nil, nil

-- The 12.0 door: the function moved under ChatFrameUtil
ChatEdit_GetActiveWindow = nil
ChatFrameUtil = { GetActiveWindow = function() return box end }
chatBox("GUILD")
NS.SendQuick("Hi!")
check("a client that moved the chat box call still sends to its channel", last().kind == "GUILD")
ChatFrameUtil = nil
n = #msgs
NOW = NOW + 3
NS.SendQuick("Hi!")
check("with no chat box call at all it whispers the person open", last().kind == "WHISPER" and last().target == "Bob")
box = nil

-- The buttons send there too
Reset()
chatClient()
SlashCmdList.BEGBUDDY("")
f = BegBuddyFrame
NS.RefreshUINow()
ChatEdit_GetActiveWindow = function() return box end
chatBox("PARTY")
click(f.quick.strip.buttons[1])
check("a button click with the cursor in party chat and nobody open sends to party", last().kind == "PARTY" and last().text == "Tysm!")
ChatEdit_GetActiveWindow = nil
box = nil

-- Folding the strip away
NS.activeContact = NS.FindContact("Bob")
click(f.quick.toggle)
check("the Quick button folds the strip away and remembers it", f.quick.strip:IsShown() == false and BegDB.window.quickClosed == true)
click(f.quick.toggle)
check("and opens it again", f.quick.strip:IsShown() == true and not BegDB.window.quickClosed)

-- Settings page
BuildPage("quick")
local page = NS.Settings.pages.quick
check("the Quick messages page is in the settings home", ZipUI.Hub.Has("begbuddy/quick"))
check("it lists every saved message", page.rows[1].box:GetText() == "Tysm!" and page.rows[#BegDB.quickMessages].box:IsShown()
  and not page.rows[#BegDB.quickMessages + 1].box:IsShown())
page.rows[1].box:SetText("Thanks a lot!")
NS.FlushUI()
check("typing in a row saves the message", BegDB.quickMessages[1].text == "Thanks a lot!")
check("and the window shows it", buttonTexts(f)[1] == "Thanks a lot!")
click(page.rows[1].hide)
check("Hide hides it", BegDB.quickMessages[1].hidden == true and not has(buttonTexts(f), "Thanks a lot!")
  and page.rows[1].hide.label.text == "Show")
click(page.rows[1].hide)
check("Show brings it back", BegDB.quickMessages[1].hidden == nil and buttonTexts(f)[1] == "Thanks a lot!")
click(page.rows[1].down)
check("Down moves it", BegDB.quickMessages[2].text == "Thanks a lot!" and page.rows[2].box:GetText() == "Thanks a lot!")
click(page.rows[2].up)
check("Up moves it back", BegDB.quickMessages[1].text == "Thanks a lot!")
local before = #BegDB.quickMessages
click(page.rows[1].del)
check("Delete drops it", #BegDB.quickMessages == before - 1 and BegDB.quickMessages[1].text == "Tysm!!! You're the best!")
page.newBox:SetText("See you at the AH!")
page.newBox.scripts.OnEnterPressed(page.newBox)
check("a new message typed in the box is added on Enter", BegDB.quickMessages[#BegDB.quickMessages].text == "See you at the AH!"
  and has(buttonTexts(f), "See you at the AH!"))
page.rows[1].box:SetText("")
page.frame.scripts.OnHide()
check("a message left blank is dropped when the page closes", #BegDB.quickMessages == before - 1)

-- Restore asks first
local restore
for _, fr in ipairs(FRAMES) do if fr.label and fr.label.text == "Restore the starting list" then restore = fr end end
check("Restore the starting list is on the page", restore ~= nil)
click(restore)
check("the first click only arms it", #BegDB.quickMessages ~= #NS.DEFAULT_QUICK_MESSAGES or BegDB.quickMessages[1].text ~= "Tysm!")
click(restore)
check("the second click restores the list", #BegDB.quickMessages == #NS.DEFAULT_QUICK_MESSAGES and BegDB.quickMessages[1].text == "Tysm!")

-- Kept through a settings reset
Reset()
NS.AddQuick("Mine!")
BegDB.settings.minLevel = 20
SlashCmdList.BEGBUDDY("profile save Mine")
SlashCmdList.BEGBUDDY("profile reset")
check("a settings reset leaves the quick messages alone", BegDB.settings.minLevel == 1
  and BegDB.quickMessages[#BegDB.quickMessages].text == "Mine!")

-- Clear all
local function fill()
  Reset()
  client()
  BegDB.window = BegDB.window or {}
  NS.AddQuick("Mine!")
  BegDB.quickMessages[1].text = "Edited!"
  NS.EnsureContact("Bob", { level = 5 })
  NS.EnsureContact("Ann", { level = 6 })
  NS.FindContact("Bob").status = "replied"
  NS.FindContact("Bob").history = { { t = 1, dir = "in", text = "hello" } }
  NS.ActiveTemplate().sent = 9
  NS.ActiveTemplate().text = "My own opener {name}"
  BegDB.progress.TestZone = 4
  BegDB.zoneSel = { Orgrimmar = true }
  BegDB.settings.minLevel = 20
  BegDB.paused = true
  NS.activeContact = NS.FindContact("Bob")
  NS.sentAt = { bob = 1 }
  NS.unread = { bob = true }
end

fill()
SlashCmdList.BEGBUDDY("")
f = BegBuddyFrame
NS.RefreshUINow()
check("Clear all sits beside Clear", f.clearAllBtn ~= nil and f.clearBtn ~= nil
  and f.clearAllBtn.point[2] == f.clearBtn)
local lines = {}
GameTooltip.AddLine = function(self, t) lines[#lines + 1] = t; return self end
f.clearAllBtn.scripts.OnEnter(f.clearAllBtn)
local tip = table.concat(lines, " ")
check("its tooltip says it cannot be undone and that quick messages are kept", tip:find("cannot be undone", 1, true) ~= nil
  and tip:find("quick messages", 1, true) ~= nil)
BegDB.zipui = BegDB.zipui or {}
BegDB.zipui.profiles = { Mine = {} }
local savedZipui = BegDB.zipui
click(f.clearAllBtn)
check("the first click only asks", NS.FindContact("Bob") ~= nil and f.clearAllBtn.armed == true)
check("and the label changes", f.clearAllBtn.label.text == "Click again to confirm")
NS.refreshQueued = false -- as on a real client, where no redraw is waiting when the click lands
click(f.clearAllBtn)
check("the second click wipes the contacts and their history", next(BegDB.contacts) == nil and #BegDB.order == 0)
check("the counters, scan progress, zone picks and settings go too", NS.ActiveTemplate().sent == 0
  and NS.ActiveTemplate().text == NS.DEFAULT_TEMPLATE and next(BegDB.progress) == nil
  and BegDB.settings.minLevel == 1 and BegDB.paused == false)
check("the quick messages are kept, edits and all", BegDB.quickMessages[1].text == "Edited!"
  and BegDB.quickMessages[#BegDB.quickMessages].text == "Mine!")
check("so is the window's place", BegDB.window ~= nil)
check("and ZipUI's saved profiles", BegDB.zipui ~= nil and BegDB.zipui == savedZipui)
check("the session forgets the open contact and its marks", NS.activeContact == nil and next(NS.sentAt) == nil
  and next(NS.unread) == nil)
check("the window is refreshed", f.detail.name.text == "No contact selected" and f.status.text:find("queued 0", 1, true) ~= nil)
check("the label is back to Clear all", f.clearAllBtn.label.text == "Clear all")
check("nothing was sent", #sent == 0)

-- Clear all with a settings page open does not write the old text back
fill()
local whisper = BuildPage("message")
whisper.shown = true
NS.ClearAll()
whisper.scripts.OnHide()
check("an open Whisper page does not bring the old text back", NS.ActiveTemplate().text == NS.DEFAULT_TEMPLATE)

-- /beg wipe confirm is the same wipe
fill()
SlashCmdList.BEGBUDDY("wipe confirm")
check("/beg wipe confirm also keeps the quick messages", next(BegDB.contacts) == nil
  and BegDB.quickMessages[1].text == "Edited!")

-- The regular Clear is unchanged: it moves Queued to Archived and touches nothing else
fill()
SlashCmdList.BEGBUDDY("")
f = BegBuddyFrame
local ann = NS.FindContact("Ann")
click(f.clearBtn)
check("Clear opens its own prompt and changes nothing yet", ann.status == "queued")
StaticPopupDialogs.BEGBUDDY_CLEAR_QUEUED.OnAccept()
check("Clear moves Queued to Archived", ann.status == "archived")
check("and keeps the contacts, history, counters and quick messages", NS.FindContact("Bob").history[1].text == "hello"
  and NS.ActiveTemplate().sent == 9 and BegDB.progress.TestZone == 4 and BegDB.quickMessages[1].text == "Edited!")
