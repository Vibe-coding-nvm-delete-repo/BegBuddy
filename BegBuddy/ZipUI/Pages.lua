-- The pages ZipUI makes for every addon: the overview of all Zip addons, each addon's About page (what it
-- is, its commands, its window settings) and its Profiles page.
if ZipUI.skip then return end
local Z = ZipUI
local L, C = Z.L, Z.Colors
local P = {}
Z.Pages = P

local function button(parent, x, y, text, w, onClick)
  local b = Z.Button(parent, text, w or 150, 22, onClick)
  b:SetPoint("TOPLEFT", x, -y)
  return b
end

-- Make a page again (after its list changed) and stay on it.
function P.Redraw(key)
  local H = Z.Hub
  local old = H.pages[key]
  if old then old:Hide(); H.pages[key] = nil; if H.shown == old then H.shown = nil end end
  H.Select(key)
end

local function addonRow(parent, y, def)
  local icon = parent:CreateTexture(nil, "ARTWORK")
  icon:SetSize(20, 20)
  icon:SetPoint("TOPLEFT", 0, -y)
  icon:SetTexture(def.icon)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local v = Z.Suites.Version(def)
  local fs = Z.Text(parent, 12, C.text, "LEFT")
  fs:SetPoint("TOPLEFT", 28, -(y + 4))
  fs:SetText(("|cffffd100%s|r %s   %s"):format(def.title, v or "", def.cmd or ""))
  local open = Z.Suites.Opener(def)
  if open then button(parent, 330, y, L["Open"], 90, open) end
  button(parent, 426, y, L["Settings"], 100, function() Z.Hub.Select(def.key) end)
  return y + 28
end

-- The first page: every Zip addon with its version and command, and the settings they share.
function P.Overview(parent)
  local H = Z.Hub
  local y = H.Text(parent, 0, L["Every Zip addon keeps its settings here. Pick a tab above for one addon, or open its window below."])
  y = H.Heading(parent, y, L["Zip addons"])
  for _, def in ipairs(Z.Suites.Registered()) do y = addonRow(parent, y, def) end
  y = H.Heading(parent, y + 6, L["Shared"])
  local cb = Z.Check(parent, L["Show the Zip button on the minimap"], function() return not Z.Prefs().minimapHide end,
    function(v) Z.SetPref("minimapHide", not v); if Z.Launcher then Z.Launcher.Update() end end)
  cb:SetPoint("TOPLEFT", 0, -y)
  y = y + 28
  return H.Text(parent, y, L["Settings are saved for your whole account, so every character shares them. Each addon's Profiles tab keeps named setups you can load or reset."], "GameFontDisable")
end

-- The window settings every addon with a window gets: lock, size and a way home.
local function windowBlock(parent, y, def)
  local H = Z.Hub
  local win = type(def.window) == "function" and def.window() or def.window
  if not win then return y end
  y = H.Heading(parent, y, L["Window"])
  local lock = Z.Check(parent, L["Lock the window in place"], function() return win:IsLocked() end, function(v) win:SetLocked(v) end)
  lock:SetPoint("TOPLEFT", 0, -y)
  local size = Z.Slider(parent, L["Window size"], 0.5, 2, 0.05, function() return win:GetScale() or 1 end,
    function(v) win:SetSavedScale(v) end, "%.2f")
  size:SetPoint("TOPLEFT", 4, -(y + 46))
  button(parent, 260, y + 34, L["Reset position"], 150, function() win:ResetPosition() end)
  return y + 80
end

local function commandBlock(parent, y, def)
  if not def.help then return y end
  local H = Z.Hub
  y = H.Heading(parent, y, L["Commands"])
  return H.Text(parent, y, table.concat(def.help, "\n"), "GameFontHighlightSmall")
end

-- An addon's own page: what it is, how it runs, a button to open it, its window settings and commands.
function P.Home(parent, def)
  local H = Z.Hub
  local y = H.Text(parent, 0, Z.Suites.Notes(def))
  local v = Z.Suites.Version(def)
  local line = L["Status"] .. ": " .. Z.Suites.LABEL[Z.Suites.State(def)]
  if v then line = line .. "   " .. L["Version"] .. ": " .. v end
  if def.cmd then line = line .. "   " .. L["Command"] .. ": " .. def.cmd end
  y = H.Text(parent, y, line, "GameFontNormal")
  if def.retired then
    y = H.Text(parent, y, (L["Replaced by %s. Turn %s off at the character screen so only one runs."]):format(def.retired, def.title), "GameFontNormal")
  end
  local open = Z.Suites.Opener(def)
  if open then
    button(parent, 0, y, (L["Open %s"]):format(def.title), 200, open)
    y = y + 34
  end
  if def.extraHome then y = def.extraHome(parent, y) end
  y = windowBlock(parent, y, def)
  return commandBlock(parent, y, def) + 8
end

-- The other addons the settings home knows: what each is and whether it runs.
function P.Others(parent)
  local H = Z.Hub
  local y = H.Text(parent, 0, L["Other addons that work alongside the Zip addons."])
  for _, line in ipairs(Z.Suites.Describe()) do y = H.Text(parent, y, line) end
  return y
end

local function profileRow(parent, y, def, name)
  local fs = Z.Text(parent, 12, C.text, "LEFT")
  fs:SetPoint("TOPLEFT", 0, -(y + 4))
  local function load()
    Z.Profiles.Load(def, name)
    Z.Hub.Rebuild()
  end
  if Z.Profiles.Imported(def, name) then
    -- A setup from a shared code: say so, and ask once more before it replaces the settings.
    fs:SetText(name .. "  |cff9e8c6b(" .. L["shared code"] .. ")|r")
    Z.ConfirmButton(parent, L["Load"], 120, load):SetPoint("TOPLEFT", 200, -y)
  else
    fs:SetText(name)
    button(parent, 200, y, L["Load"], 120, load)
  end
  local del = Z.ConfirmButton(parent, L["Delete"], 120, function()
    Z.Profiles.Delete(def, name)
    P.Redraw(def.key .. "/profiles")
  end)
  del:SetPoint("TOPLEFT", 326, -y)
  return y + 28
end

-- Trade setups as text: Export puts a code for the current settings in the box (already selected, so Ctrl+C
-- copies it); paste a friend's code in the second box and Import adds it to the saved setups.
function P.Share(parent, def, y)
  y = Z.Hub.Text(parent, y, L["Export makes one line of text for your current settings. Paste a line from a friend into the second box and press Import."])
  local out = Z.Edit(parent, 330, 22)
  out:SetMaxLetters(0)
  out:SetPoint("TOPLEFT", 0, -y)
  button(parent, 340, y, L["Export"], 90, function()
    local code, err = Z.Share.Encode(def)
    out:SetText(code or err)
    out:SetFocus()
    out:HighlightText()
  end)
  local into = Z.Edit(parent, 330, 22)
  into:SetMaxLetters(0)
  into:SetPoint("TOPLEFT", 0, -(y + 30))
  local status = Z.Text(parent, 12, C.dim, "LEFT")
  status:SetPoint("TOPLEFT", 0, -(y + 62))
  button(parent, 340, y + 30, L["Import"], 90, function()
    local name, err = Z.Share.Import(def, into:GetText())
    if not name then return status:SetText(err) end
    into:SetText("")
    P.Redraw(def.key .. "/profiles")
  end)
  return y + 84
end

-- Named setups: save this addon's settings under a name, load or delete one, or go back to the defaults.
function P.Profiles(parent, def)
  local H = Z.Hub
  local key = def.key .. "/profiles"
  local y = H.Text(parent, 0, L["Save this addon's settings under a name to load later, on any character. Your data (records, history) is never touched."])
  local edit = Z.Edit(parent, 220, 22)
  edit:SetPoint("TOPLEFT", 0, -y)
  local function save()
    local name = (edit:GetText() or ""):match("^%s*(.-)%s*$")
    if name == "" then return end
    Z.Profiles.Save(def, name)
    P.Redraw(key)
  end
  edit:SetScript("OnEnterPressed", save)
  button(parent, 230, y, L["Save"], 90, save)
  y = H.Heading(parent, y + 36, L["Saved setups"])
  local names = Z.Profiles.List(def)
  if #names == 0 then y = H.Text(parent, y, L["None yet."], "GameFontDisable") end
  for _, name in ipairs(names) do y = profileRow(parent, y, def, name) end
  y = P.Share(parent, def, H.Heading(parent, y + 6, L["Share a setup"]))
  y = H.Heading(parent, y + 6, L["Start over"])
  local reset = Z.ConfirmButton(parent, L["Reset all settings to defaults"], 260, function()
    Z.Profiles.Reset(def)
    Z.Hub.Rebuild()
  end)
  reset:SetPoint("TOPLEFT", 0, -y)
  return y + 34
end
