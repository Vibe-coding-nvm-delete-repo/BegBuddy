-- BegBuddy / Gifts.lua
-- Gold and items that came back from a person you asked: from the mailbox (Mail.lua) and from a trade window. Each
-- gift is added to that person's card once, so the Stats tab can say how much each template, class or zone earned.

local _, ns = ...

local MAX_GIFTS = 20

-- Adds a gift to a contact. Returns true when something was recorded. Nothing counts for a blocked person.
function ns.RecordGift(c, copper, items, how)
  copper, items = tonumber(copper) or 0, tonumber(items) or 0
  if not c or (copper <= 0 and items <= 0) then return false end
  if c.status == ns.STATUS.BLOCKED then return false end
  local now = time()
  c.goldIn  = (c.goldIn or 0) + math.max(copper, 0)
  c.itemsIn = (c.itemsIn or 0) + math.max(items, 0)
  c.fundedAt = c.fundedAt or now
  c.gifts = type(c.gifts) == "table" and c.gifts or {}
  c.gifts[#c.gifts + 1] = { t = now, gold = copper, items = items, how = how }
  while #c.gifts > MAX_GIFTS do table.remove(c.gifts, 1) end
  ns.TouchList()
  return true
end

----------------------------------------------------------------------
-- Trades
----------------------------------------------------------------------

-- The trade window shows what the other player put in. The numbers are read when they accept, and counted only when
-- the game says the trade completed. Every read is guarded: a value the game hides from addons is simply skipped.
local trade = {}

local function safe(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c = pcall(fn, ...)
  if ok then return a, b, c end
end

local function partnerName()
  local n = safe(UnitName, "NPC")
  if type(n) ~= "string" and _G.TradeFrameRecipientNameText and _G.TradeFrameRecipientNameText.GetText then
    n = safe(_G.TradeFrameRecipientNameText.GetText, _G.TradeFrameRecipientNameText)
  end
  if type(n) == "string" and ns.Readable(n) and n ~= "" then return n end
end

-- What the other player has put in the window right now: copper and units of items.
local function offered()
  local copper = tonumber(safe(_G.GetTargetTradeMoney)) or 0
  local units = 0
  for i = 1, 6 do
    local name, _, qty = safe(_G.GetTradeTargetItemInfo, i)
    if name and ns.Readable(name, qty) then units = units + (tonumber(qty) or 1) end
  end
  return copper, units
end

function ns.TradeOpened() trade = { name = partnerName() } end

function ns.TradeAccepted(playerAccepted, targetAccepted)
  if not trade.name then trade.name = partnerName() end
  if targetAccepted == 1 or targetAccepted == true then
    trade.copper, trade.units = offered()
  end
end

-- The game said the trade went through.
function ns.TradeCompleted()
  local name, copper, units = trade.name, trade.copper or 0, trade.units or 0
  trade = {}
  local c = name and ns.FindContact(name)
  if not c or (copper <= 0 and units <= 0) then return false end
  if not ns.RecordGift(c, copper, units, "trade") then return false end
  if c.status ~= ns.STATUS.BLOCKED then ns.SetStatus(c, ns.STATUS.FUNDED) end
  ns.PushHistory(c, "in", string.format("[trade] %s%s", ns.Coins(copper), units > 0 and (" and " .. units .. " item(s)") or ""))
  ns.Print(string.format("|cffffd100%s traded you %s%s.|r", tostring(c.name), ns.Coins(copper),
    units > 0 and (" and " .. units .. " item(s)") or ""))
  return true
end

local f = CreateFrame("Frame")
f:RegisterEvent("TRADE_SHOW")
f:RegisterEvent("TRADE_ACCEPT_UPDATE")
f:RegisterEvent("UI_INFO_MESSAGE")
f:SetScript("OnEvent", function(_, event, a, b)
  if event == "TRADE_SHOW" then ns.TradeOpened()
  elseif event == "TRADE_ACCEPT_UPDATE" then ns.TradeAccepted(a, b)
  elseif event == "UI_INFO_MESSAGE" then
    -- The numbers kept from the last accept are used only on this message, and a new trade window clears them.
    if ns.Readable(b) and b == _G.ERR_TRADE_COMPLETE then ns.TradeCompleted() end
  end
end)
