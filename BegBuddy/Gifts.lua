-- BegBuddy / Gifts.lua
-- Gold and items that came back from a person you asked: from the mailbox (Mail.lua) and from a trade window. Each
-- gift is added to that person's card once, so the Stats tab can say how much each template, class or zone earned.

local _, ns = ...

local MAX_GIFTS = 20

-- Formats an array of { name, qty } into "2x Linen Bag, 1x Wand", or falls back to "N item(s)".
function ns.FormatGiftItems(itemList, units)
  if type(itemList) == "table" and #itemList > 0 then
    local parts = {}
    for _, it in ipairs(itemList) do
      local q = tonumber(it.qty) or 1
      local n = tostring(it.name or "item")
      parts[#parts + 1] = q > 1 and (q .. "x " .. n) or n
    end
    return table.concat(parts, ", ")
  end
  units = tonumber(units) or 0
  if units > 0 then return units .. " item(s)" end
  return ""
end

-- Adds a gift to a contact. Returns true when something was recorded. Nothing counts for a blocked person.
-- itemList (optional): array of { name = string, qty = number, link = string|nil }.
function ns.RecordGift(c, copper, items, how, itemList)
  copper, items = tonumber(copper) or 0, tonumber(items) or 0
  if not c or (copper <= 0 and items <= 0) then return false end
  if c.status == ns.STATUS.BLOCKED then return false end
  local now = time()
  local addCopper = math.max(copper, 0)
  local addItems  = math.max(items, 0)
  c.goldIn  = (c.goldIn or 0) + addCopper
  c.itemsIn = (c.itemsIn or 0) + addItems
  c.fundedAt = c.fundedAt or now
  ns.sessionGoldIn  = (ns.sessionGoldIn or 0) + addCopper
  ns.sessionItemsIn = (ns.sessionItemsIn or 0) + addItems
  c.gifts = type(c.gifts) == "table" and c.gifts or {}
  local rec = { t = now, gold = addCopper, items = addItems, how = how }
  if type(itemList) == "table" and #itemList > 0 then
    rec.itemList = itemList
    c.giftItems = type(c.giftItems) == "table" and c.giftItems or {}
    for _, it in ipairs(itemList) do
      c.giftItems[#c.giftItems + 1] = { t = now, name = it.name, qty = it.qty, link = it.link }
    end
    while #c.giftItems > MAX_GIFTS * 2 do table.remove(c.giftItems, 1) end
  end
  c.gifts[#c.gifts + 1] = rec
  while #c.gifts > MAX_GIFTS do table.remove(c.gifts, 1) end
  ns.TouchList()
  return true
end

----------------------------------------------------------------------
-- Trades
----------------------------------------------------------------------

-- The trade window shows what the other player put in. We snapshot continuously
-- on money/item/accept changes while the window is open, and commit ONLY when
-- the server confirms ERR_TRADE_COMPLETE. Every read is guarded for WoW Forever
-- secret values.
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

-- What the other player has put in the window right now: copper, total units, and named item list.
local function offered()
  local copper = tonumber(safe(_G.GetTargetTradeMoney)) or 0
  local units = 0
  local itemList = {}
  for i = 1, 6 do
    local name, _, qty = safe(_G.GetTradeTargetItemInfo, i)
    if name and ns.Readable(name, qty) then
      local q = tonumber(qty) or 1
      units = units + q
      local link = safe(_G.GetTradeTargetItemLink, i)
      if link and not ns.Readable(link) then link = nil end
      itemList[#itemList + 1] = { name = name, qty = q, link = link }
    end
  end
  return copper, units, itemList
end

local function snapshotLive()
  if not trade.open then return end
  if not trade.name then trade.name = partnerName() end
  trade.liveCopper, trade.liveUnits, trade.liveItems = offered()
end

function ns.TradeOpened()
  trade = { open = true, name = partnerName(), accepted = false, copper = 0, units = 0, itemList = {} }
end

function ns.TradeUpdated()
  if not trade.open then trade.open = true end
  snapshotLive()
end

function ns.TradeAccepted(playerAccepted, targetAccepted)
  if not trade.open then trade.open = true end
  if not trade.name then trade.name = partnerName() end
  if targetAccepted == 1 or targetAccepted == true then
    local copper, units, itemList = offered()
    if copper == 0 and units == 0 and ((trade.liveCopper or 0) > 0 or (trade.liveUnits or 0) > 0) then
      copper, units, itemList = trade.liveCopper, trade.liveUnits, trade.liveItems
    end
    trade.copper, trade.units, trade.itemList = copper, units, itemList
    trade.accepted = true
  else
    trade.accepted = false
  end
end

function ns.TradeClosed()
  -- Keep the accepted snapshot briefly because UI_INFO_MESSAGE (ERR_TRADE_COMPLETE)
  -- can arrive immediately after TRADE_CLOSED on Classic Era; just mark closed
  -- so further window reads don't overwrite the snapshot with zeros.
  trade.open = false
end

-- The game said the trade went through.
function ns.TradeCompleted()
  local accepted = trade.accepted
  local name = trade.name
  local copper = trade.copper or 0
  local units = trade.units or 0
  local itemList = trade.itemList
  trade = {}
  if not accepted or not name or (copper <= 0 and units <= 0) then return false end

  local c = ns.FindContact(name)
  -- If they aren't in the CRM yet and aren't a friend/guildmate/group member,
  -- auto-create them so every incoming deal is tracked & closed automatically.
  if not c and not (ns.IsKnownPlayer and ns.IsKnownPlayer(name)) then
    c = ns.EnsureContact(name)
  end
  if not c then return false end
  if not ns.RecordGift(c, copper, units, "trade", itemList) then return false end

  if c.status ~= ns.STATUS.BLOCKED then
    ns.SetStatus(c, ns.STATUS.FUNDED)
  end

  local goldTxt = copper > 0 and ns.Coins(copper) or ""
  local itemTxt = ns.FormatGiftItems(itemList, units)
  local summary
  if goldTxt ~= "" and itemTxt ~= "" then summary = goldTxt .. " and " .. itemTxt
  elseif goldTxt ~= "" then summary = goldTxt
  else summary = itemTxt end

  ns.PushHistory(c, "in", "[trade] " .. summary)
  ns.Print(string.format("|cffffd100%s traded you %s — marked Funded!|r", tostring(c.name), summary))
  return true
end

local f = CreateFrame("Frame")
f:RegisterEvent("TRADE_SHOW")
f:RegisterEvent("TRADE_TARGET_ITEM_CHANGED")
f:RegisterEvent("TRADE_MONEY_CHANGED")
f:RegisterEvent("TRADE_ACCEPT_UPDATE")
f:RegisterEvent("TRADE_CLOSED")
f:RegisterEvent("UI_INFO_MESSAGE")
f:SetScript("OnEvent", function(_, event, a, b)
  if event == "TRADE_SHOW" then ns.TradeOpened()
  elseif event == "TRADE_TARGET_ITEM_CHANGED" or event == "TRADE_MONEY_CHANGED" then ns.TradeUpdated()
  elseif event == "TRADE_ACCEPT_UPDATE" then ns.TradeAccepted(a, b)
  elseif event == "TRADE_CLOSED" then ns.TradeClosed()
  elseif event == "UI_INFO_MESSAGE" then
    -- The numbers kept from the last accept/update are used only on this message, and a new trade window clears them.
    if ns.Readable(b) and b == _G.ERR_TRADE_COMPLETE then ns.TradeCompleted() end
  end
end)
