-- BegBuddy / SettingsData.lua
-- Settings page "Zones & data": remove or add zones by hand, export everything, save now.

local _, ns = ...
local S = ns.Settings
local WHITE = { 0.9, 0.9, 0.9 }

local function again() S.pages.data.Refresh() end

-- Export, save, and the note about when WoW writes its saved data.
local function dataRows(data)
  S.Button(data, "Export everything", 130, 0, 176, function()
    local text = ns.BuildExport()
    if #text > 60000 then
      text = ns.TrimToBytes(text, 60000) .. "\n\n... truncated at 60000 characters."
      ns.Print("Export was longer than 60000 characters and got truncated.")
    end
    ns.UI.ShowCopy(text, "BegBuddy export - copy and save this")
    ns.Print(string.format("Export ready: %d characters, already selected.", #text))
  end)
  S.Button(data, "Try to save now", 120, 136, 176, function() ns.SaveNow() end)
  S.Note(data, "WoW only writes SavedVariables on exit or /reload, so a client crash loses the session. Export first if you care about it.", 0, 216)
end

-- Built-in zones are always in the Zones picker, so only zones added by hand can be removed here.
local function refresh(c)
  local names = {}
  for _, city in ipairs(ns.GetCities()) do
    if not ns.IsBuiltInZone(city.name) then names[#names + 1] = city.name end
  end
  local picked = #(ns.SelectedZones())
  local sig = table.concat(names, "\1") .. "\2" .. picked
  if c.sig == sig then return end
  c.sig = sig
  c.drop:SetItems(names, (#names > 0) and "Remove a zone added by hand..." or "(no zones added by hand)")
  c.cityLbl:SetText(string.format("|cffffd100%d zones ticked|r in the Zones picker, %d added by hand. Every open-world zone is listed there already; add one here only if it is missing.",
    picked, #names))
end

function ns.SettingsData(data)
  local c = {}
  c.cityLbl = S.Note(data, "", 0, 0, 524)
  c.drop = ns.UI.Dropdown(data, 280, function(picked)
    if ns.RemoveCity(picked) then ns.Print("Removed " .. picked .. ".") end
    if BegDB.selectedCity == picked then BegDB.selectedCity = nil end
    again()
    if ns.RefreshUI then ns.RefreshUI() end
  end)
  c.drop:SetPoint("TOPLEFT", data, "TOPLEFT", 0, -62)
  S.Label(data, "Add a zone by name:", 0, 104, WHITE)
  local manual = S.Input(data, 220, 130, 100)
  manual:SetScript("OnEnterPressed", function(self)
    ns.AddCityByName(self:GetText())
    self:SetText("")
    self:ClearFocus()
    again()
  end)
  S.Button(data, "Add the zone I'm standing in", 190, 0, 134, function()
    ns.AddCurrentZone()
    again()
  end)
  dataRows(data)
  local function show() refresh(c) end
  S.Add("data", data, {
    Load = show, Refresh = show, drop = c.drop,
    Hide = function() if c.drop.Close then c.drop:Close() end end,
  })
  return 270
end
