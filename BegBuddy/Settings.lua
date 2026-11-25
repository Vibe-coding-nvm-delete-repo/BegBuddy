-- BegBuddy / Settings.lua
-- BegBuddy's settings live in the shared Zip settings home (ZipUI): Esc > Options > AddOns > Zip > BegBuddy,
-- or the Settings button on the BegBuddy window. Five pages (Whisper, Mail, Scan, Quick messages, Zones & data), built by
-- SettingsWhisper / SettingsMail / SettingsScan / SettingsData.lua. This file registers the addon and its
-- slash words, and holds the small helpers the page files share.

local _, ns = ...
local Z = ZipUI
local S = { pages = {} }
ns.Settings = S

local DIM = { 0.62, 0.62, 0.66 }
S.WIDTH = 540 -- the width ZipUI gives a page

-- A click handler that redraws the main window at once, like the old BegBuddy buttons did.
function S.Click(fn)
  return function(...)
    fn(...)
    if ns.FlushUI then ns.FlushUI() end
  end
end

-- A small grey or gold label at x, y (down from the page's top left).
function S.Label(parent, text, x, y, color)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
  fs:SetText(text)
  local c = color or DIM
  fs:SetTextColor(c[1], c[2], c[3])
  return fs
end

-- A wrapped note under a page's controls.
function S.Note(parent, text, x, y, width, color)
  local fs = S.Label(parent, text, x, y, color)
  fs:SetWidth(width or S.WIDTH)
  fs:SetJustifyH("LEFT")
  return fs
end

-- A button in the shared look at x, y.
function S.Button(parent, text, w, x, y, onClick)
  local b = Z.Button(parent, text, w, 22, S.Click(onClick))
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
  return b
end

-- A one-line box at x, y. Escape and Enter just leave it; the caller sets what Enter does.
function S.Input(parent, w, x, y, maxLetters)
  local e = Z.Edit(parent, w, 22)
  e:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
  if maxLetters then e:SetMaxLetters(maxLetters) end
  return e
end

-- A multi-line box with the chat font, for message text.
function S.Editor(parent, w, h)
  local e = CreateFrame("EditBox", nil, parent)
  Z.Box(e, Z.Colors.bg, Z.Colors.border)
  e:SetMultiLine(true)
  e:SetAutoFocus(false)
  e:SetFontObject("ChatFontNormal")
  e:SetSize(w, h)
  e:SetTextInsets(6, 6, 4, 4)
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  return e
end

-- A page the player is looking at loads fresh values each time it opens, and writes back what was typed when
-- it closes. page = { Load, Hide (optional), Refresh (optional) }.
function S.Add(id, parent, page)
  page.frame = parent
  S.pages[id] = page
  parent:SetScript("OnShow", function() page.Load() end)
  parent:SetScript("OnHide", function()
    if page.Hide then page.Hide() end
    if ns.RefreshUI then ns.RefreshUI() end
  end)
  page.Load()
end

-- What the rest of the addon calls "the settings window": it is open when any page is on screen.
local settings = {}
function settings:IsShown()
  for _, p in pairs(S.pages) do if p.frame:IsVisible() then return true end end
  return false
end
function settings:Load() for _, p in pairs(S.pages) do p.Load() end end
function settings:Refresh()
  for _, p in pairs(S.pages) do
    if p.Refresh and p.frame:IsVisible() then p.Refresh() end
  end
end
ns.UI = ns.UI or {}
ns.UI.settings = settings

local PAGES = {
  { key = "message", title = "Whisper", icon = "Interface/Icons/INV_Letter_15", file = "Whisper" },
  { key = "mail", title = "Mail", icon = "Interface/Icons/INV_Letter_02", file = "Mail" },
  { key = "scan", title = "Scan", icon = "Interface/Icons/INV_Misc_Spyglass_02", file = "Scan" },
  { key = "quick", title = "Quick messages", icon = "Interface/Icons/INV_Misc_Note_01", file = "Quick" },
  { key = "closeout", title = "Close-out & Smart Reply", icon = "Interface/Icons/INV_Misc_Coin_02", file = "Closeout" },
  { key = "data", title = "Zones & data", icon = "Interface/Icons/INV_Misc_Map_01", file = "Data" },
}

-- What a profile saves and Reset goes back to: the settings table. Contacts, templates, progress and the
-- rest are data. The template choices and the template text mirror point at records, so a load leaves them be.
local function profile()
  return {
    keys = { "settings" },
    keep = { "settings.activeTemplate", "settings.activeMailTemplate", "settings.template" },
    defaults = function() return { settings = ns.SettingsDefaults() } end,
    after = function()
      settings:Load()
      if ns.RefreshUI then ns.RefreshUI() end
    end,
  }
end

function S.Register()
  local pages = {}
  for i, p in ipairs(PAGES) do
    pages[i] = { key = p.key, title = p.title, icon = p.icon, Build = function(parent) return ns["Settings" .. p.file](parent) end }
  end
  local commands = {}
  for word, fn in pairs(ns.Commands) do commands[word] = { fn, ns.COMMAND_HELP[word] or "" } end
  S.def = Z.Register({
    key = "begbuddy", title = "BegBuddy", addon = "BegBuddy", icon = ns.ICON, order = 60,
    db = function() return BegDB end,
    window = function() ns.UI.EnsureBuilt(); return ns.UI.frame end,
    open = function() ns.UI.Toggle() end,
    home = "General", commands = commands, print = ns.Print,
    pages = pages, profile = profile(),
  })
  Z.Slash(S.def, "BEGBUDDY", { "/beg", "/begbuddy" })
end
