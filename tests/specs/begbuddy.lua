-- ZipUI: BegBuddy registers with ZipUI with its four settings pages, keeps its slash words, opens the Zip
-- settings from the shared words, and its profile only touches the settings table (never contacts or templates).

Reset()
local Z = ZipUI
check("registered with ZipUI", Z.Suites.Registered()[1].key == "begbuddy")
for _, key in ipairs({ "message", "mail", "scan", "data" }) do
  check("the " .. key .. " page is in the settings home", Z.Hub.Has("begbuddy/" .. key))
end
check("the Profiles page is there", Z.Hub.Has("begbuddy/profiles"))
check("the old settings window is gone", BegBuddySettings == nil and NS.UI.OpenSettings ~= nil)
check("the main window is a ZipUI window", BegBuddyFrame ~= nil and BegBuddyFrame.settingsBtn ~= nil)

-- Shared words
SlashCmdList.BEGBUDDY("settings")
check("/beg settings opens the Zip settings", OPENED == 7)
OPENED = nil
SlashCmdList.BEGBUDDY("config")
check("/beg config still opens settings", OPENED == 7)
OPENED = nil
NS.UI.OpenSettings("scan")
check("the Change levels button opens the Scan page", OPENED == 7 and Z.Hub.want == "begbuddy/scan")
SlashCmdList.BEGBUDDY("")
check("bare /beg opens the window", BegBuddyFrame:IsShown())
SlashCmdList.BEGBUDDY("lock")
check("/beg lock locks the window and saves it", BegDB.window.locked == true)
SlashCmdList.BEGBUDDY("scale 1.5")
check("/beg scale sizes the window", BegDB.window.scale == 1.5)
SlashCmdList.BEGBUDDY("nonsense")
check("an unknown word points at help", PRINTS[#PRINTS]:find("unknown command", 1, true) ~= nil)

-- Old words that still work
Reset()
local scans = 0
NS.ScanNextSlice = function() scans = scans + 1 end
SlashCmdList.BEGBUDDY("scan")
check("/beg scan runs the next slice", scans == 1)
local resets = 0
NS.ResetSlices = function() resets = resets + 1 end
SlashCmdList.BEGBUDDY("reset")
check("/beg reset restarts the slice plan (not the window)", resets == 1)
SlashCmdList.BEGBUDDY("pause")
check("/beg pause pauses sending", BegDB.paused == true)
SlashCmdList.BEGBUDDY("resume")
check("/beg resume allows sending", BegDB.paused == false)
SlashCmdList.BEGBUDDY("template Hi {name}, spare a silver?")
check("/beg template sets the template record", NS.ActiveTemplate().text == "Hi {name}, spare a silver?"
  and BegDB.settings.template == "Hi {name}, spare a silver?")
SlashCmdList.BEGBUDDY("template reset")
check("/beg template reset goes back to the default", NS.ActiveTemplate().text == NS.DEFAULT_TEMPLATE)
PRINTS = {}
SlashCmdList.BEGBUDDY("wipe")
check("/beg wipe asks first", PRINTS[#PRINTS]:find("wipe confirm", 1, true) ~= nil)
SlashCmdList.BEGBUDDY("help")
check("/beg help lists BegBuddy's words", table.concat(PRINTS, "\n"):find("/beg addzone", 1, true) ~= nil)

-- Profiles
Reset()
BegDB.contacts["zed-realm"] = { name = "Zed", key = "zed-realm", status = "queued" }
BegDB.order[1] = "zed-realm"
local active = NS.ActiveTemplate().name
BegDB.settings.minLevel, BegDB.settings.bandSize, BegDB.settings.oneClickSend = 20, 9, true
SlashCmdList.BEGBUDDY("profile save Mine")
SlashCmdList.BEGBUDDY("profile reset")
check("profile reset: settings back to defaults", BegDB.settings.minLevel == 1 and BegDB.settings.bandSize == 5
  and BegDB.settings.oneClickSend == false and BegDB.settings.maxLevel == 60)
check("profile reset: contacts and the active template are kept", BegDB.contacts["zed-realm"] ~= nil
  and BegDB.order[1] == "zed-realm" and BegDB.settings.activeTemplate == active)
SlashCmdList.BEGBUDDY("profile load Mine")
check("profile load: settings come back", BegDB.settings.minLevel == 20 and BegDB.settings.bandSize == 9
  and BegDB.settings.oneClickSend == true)

-- Settings pages write the saved settings
Reset()
local scan = BuildPage("scan")
local pages = NS.Settings.pages
pages.scan.fields.minLevel:SetText("10")
pages.scan.fields.minLevel.scripts.OnEnterPressed(pages.scan.fields.minLevel)
check("typing Min level and pressing Enter saves it", BegDB.settings.minLevel == 10)
pages.scan.fields.minLevel:SetText("99")
pages.scan.fields.minLevel.scripts.OnEnterPressed(pages.scan.fields.minLevel)
check("Min level above Max level is refused", BegDB.settings.minLevel == 10 and pages.scan.fields.minLevel:GetText() == "10")
pages.scan.fields.bandSize:SetText("8")
scan.scripts.OnHide()
check("closing the page saves a number typed but not confirmed", BegDB.settings.bandSize == 8)

local checks = {}
for _, f in ipairs(FRAMES) do if f.label and f.label.text and f.GetChecked and f.scripts.OnClick and f.SetCheckedTexture then checks[f.label.text] = f end end
local box = checks["Skip non-Latin names"]
check("the behaviour switches are on the Scan page", box ~= nil)
box:SetChecked(false)
box.scripts.OnClick(box)
check("a Scan switch writes BegDB.settings", BegDB.settings.skipNonLatin == false)

local whisper = BuildPage("message")
local editor = pages.message.box
editor:SetText("Hello {name}!")
check("typing in the Whisper box saves the active template", NS.ActiveTemplate().text == "Hello {name}!"
  and BegDB.settings.template == "Hello {name}!")

local mail = BuildPage("mail")
pages.mail.subject:SetText("Hey")
pages.mail.body:SetText("Body {name}")
check("typing in the Mail boxes saves the active mail template", NS.ActiveMailTemplate().subject == "Hey"
  and NS.ActiveMailTemplate().body == "Body {name}")

BuildPage("data")
check("the Zones & data page loads", pages.data ~= nil)

-- Wipe reloads the open pages so their text cannot come back
whisper.shown = true
SlashCmdList.BEGBUDDY("wipe confirm")
check("/beg wipe confirm clears the data", next(BegDB.contacts) == nil)
check("and the open Whisper page shows the default again", editor:GetText() == NS.DEFAULT_TEMPLATE)
whisper.scripts.OnHide()
check("closing the page afterwards does not bring the old text back", NS.ActiveTemplate().text == NS.DEFAULT_TEMPLATE)
