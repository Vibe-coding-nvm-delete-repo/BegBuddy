-- BegBuddy / SettingsCloseout.lua
-- Settings page "Close-out": customize the floating 1-click Smart Reply mini-bar and the
-- Post-Trade Close-Out toast (standard & big-tip thank-you templates, threshold, auto-leave,
-- auto-friend, auto-hide timer, and live Preview buttons).

local _, ns = ...
local S = ns.Settings
local Z = ZipUI
local ACCENT = { 0.36, 0.78, 1.00 }
local WHITE  = { 0.9, 0.9, 0.9 }

local function addSwitch(c, label, key, y, after)
  local cb = Z.Check(c.page, label, function() return BegDB.settings[key] end, function(v)
    BegDB.settings[key] = v and true or false
    if after then after() end
  end)
  cb:SetPoint("TOPLEFT", c.page, "TOPLEFT", 0, -y)
  c.switches[#c.switches + 1] = cb
end

local function load(c)
  local s = BegDB.settings
  c.loading = true
  c.locBox:SetText(tostring(s.smartReplyLocation or ""))
  c.stdBox:SetText(tostring(s.postTradeThankYou or ""))
  c.bigBox:SetText(tostring(s.postTradeBigThankYou or ""))
  c.threshBox:SetText(tostring(math.floor((tonumber(s.postTradeBigThreshold) or 10000) / 100)))
  c.hideBox:SetText(tostring(tonumber(s.postTradeAutoHideSec) or 0))
  c.loading = false
  for _, cb in ipairs(c.switches) do cb:Refresh() end
end

local function commitNumbers(c)
  local s = BegDB.settings
  local silver = tonumber(c.threshBox:GetText())
  if silver and silver >= 0 then s.postTradeBigThreshold = math.floor(silver) * 100 end
  local hideSec = tonumber(c.hideBox:GetText())
  if hideSec and hideSec >= 0 then s.postTradeAutoHideSec = math.floor(hideSec) end
end

function ns.SettingsCloseout(page)
  local c = { page = page, switches = {} }

  S.Label(page, "1-Click Smart Reply Bar (on incoming whispers)", 0, 0, ACCENT)
  addSwitch(c, "Pop floating 1-click Smart Reply bar when a contact whispers you", "smartReplyPopup", 20)
  S.Label(page, "My meet-up location:", 0, 50, WHITE)
  c.locBox = S.Input(page, 386, 128, 46, 120)
  c.locBox:SetScript("OnTextChanged", function(self)
    if not c.loading then BegDB.settings.smartReplyLocation = (self:GetText() or ""):gsub("[\r\n]+", " ") end
  end)

  S.Label(page, "Post-Trade Close-Out Toast (on completed trade)", 0, 84, ACCENT)
  addSwitch(c, "Pop 1-click Post-Trade Close-Out toast after every completed trade", "postTradePopup", 104)
  addSwitch(c, "Include Leave Group inside the 1-click 'Thanks + Leave' button", "postTradeLeaveGroup", 130)
  addSwitch(c, "Auto-leave 2-person party immediately after trade (only when grouped with trader)", "postTradeAutoLeave", 156)
  addSwitch(c, "Also Add Friend on 1-click close-out for big tips (>= threshold below)", "postTradeAddFriend", 182)

  S.Label(page, "Thank-you ({name}, {gift}, {gold}, {items}):", 0, 214, WHITE)
  c.stdBox = S.Input(page, 514, 0, 232, 240)
  c.stdBox:SetScript("OnTextChanged", function(self)
    if not c.loading then BegDB.settings.postTradeThankYou = (self:GetText() or ""):gsub("[\r\n]+", " ") end
  end)

  S.Label(page, "Big-tip thank-you:", 0, 264, WHITE)
  c.bigBox = S.Input(page, 514, 0, 282, 240)
  c.bigBox:SetScript("OnTextChanged", function(self)
    if not c.loading then BegDB.settings.postTradeBigThankYou = (self:GetText() or ""):gsub("[\r\n]+", " ") end
  end)

  S.Label(page, "Big-tip threshold (silver):", 0, 318, WHITE)
  c.threshBox = S.Input(page, 64, 150, 314, 6)
  c.threshBox:SetScript("OnEnterPressed", function(self) self:ClearFocus(); commitNumbers(c); load(c) end)
  c.threshBox:SetScript("OnEscapePressed", function(self) self:ClearFocus(); commitNumbers(c); load(c) end)

  S.Label(page, "Auto-hide (sec, 0=stay):", 236, 318, WHITE)
  c.hideBox = S.Input(page, 54, 378, 314, 4)
  c.hideBox:SetScript("OnEnterPressed", function(self) self:ClearFocus(); commitNumbers(c); load(c) end)
  c.hideBox:SetScript("OnEscapePressed", function(self) self:ClearFocus(); commitNumbers(c); load(c) end)

  S.Button(page, "Preview Trade Toast", 148, 0, 352, function()
    local sample = { key = "sample", name = "Generous", classToken = "PALADIN", level = 60 }
    ns.UI.ShowTradeToast(sample, 15000, 1, "1g 50s and Linen Bag", true)
  end)
  S.Button(page, "Preview Smart Reply Bar", 170, 156, 352, function()
    local sample = { key = "sample", name = "Shadow Dru", classToken = "DRUID", level = 55 }
    ns.UI.ShowSmartReply(sample, "haha sure where are you at?", true)
  end)

  S.Note(page, "Both floating bars can be dragged anywhere on screen. Every whisper/invite/friend send runs strictly on your click (100% ToS-safe).", 0, 386)
  S.Add("closeout", page, {
    Load = function() load(c) end,
    Hide = function() commitNumbers(c) end,
  })
  return 430
end
