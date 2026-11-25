-- The settings home for every Zip addon (Esc > Options > AddOns > Zip). A row of tabs across the top (Overview,
-- each Zip addon, other addons), a row of sub-tabs under the chosen tab (its own page first, then its sub-pages),
-- and the chosen page in a framed box. Pages are built the first time they are opened.
if ZipUI.skip then return end
local Z = ZipUI
local L = Z.L
local H = { pages = {}, byKey = {}, flat = {}, rows = {}, pools = {} }
Z.Hub = H

local PAD, PAGE_W, HEAD_H = 16, 540, 46
local WIDTH = PAGE_W + 2 * PAD + 28
H.PAGE_W = PAGE_W
local FALLBACK = "Interface/Icons/INV_Misc_QuestionMark"
H.ICON = "Interface/Icons/INV_Misc_EngGizmos_20"

-- A wrapped paragraph at height y, the page's width. Returns the next free y.
function H.Text(parent, y, str, template) return Z.Para(parent, y, str, PAGE_W, template) end
function H.Heading(parent, y, str) return Z.Heading(parent, y, str, PAGE_W) end

-- Sub-pages and sub-sub-pages: list = { { key, title, icon, home, Build(parent, db), pages = { ... } }, ... }.
function H.PageNodes(prefix, list, getDb)
  local out = {}
  for _, p in ipairs(list or {}) do
    local key = prefix .. "/" .. p.key
    out[#out + 1] = {
      key = key, title = p.title, icon = p.icon, home = p.home,
      Build = function(parent) return p.Build(parent, getDb and getDb()) end,
      children = H.PageNodes(key, p.pages, getDb),
    }
  end
  return out
end

local function suiteNode(def)
  local children = H.PageNodes(def.key, def.pages, def.db)
  if def.profile then
    children[#children + 1] = { key = def.key .. "/profiles", title = L["Profiles"], icon = "Interface/Icons/INV_Misc_Book_09",
      Build = function(parent) return Z.Pages.Profiles(parent, def) end, children = {} }
  end
  return {
    key = def.key, title = def.title, icon = def.icon, home = def.home or L["About"],
    Build = function(parent) return Z.Pages.Home(parent, def) end, children = children,
  }
end

local function tree()
  local out = { { key = "zip", title = L["Overview"], icon = H.ICON, Build = function(p) return Z.Pages.Overview(p) end, children = {} } }
  for _, def in ipairs(Z.Suites.Registered()) do out[#out + 1] = suiteNode(def) end
  local others = {}
  for _, k in ipairs(Z.Suites.Others()) do
    others[#others + 1] = { key = k.key, title = k.title, icon = k.icon, Build = function(p) return Z.Pages.Home(p, k) end, children = {} }
  end
  if #others > 0 then
    out[#out + 1] = { key = "other", title = L["Other addons"], icon = "Interface/Icons/INV_Misc_Bag_10_Blue", home = L["All"],
      Build = function(p) return Z.Pages.Others(p) end, children = others }
  end
  return out
end

local function index(nodes, parent, depth)
  for _, n in ipairs(nodes) do
    n.parent, n.depth = parent, depth
    n.icon = n.icon or (parent and parent.icon) or FALLBACK
    H.byKey[n.key] = n
    index(n.children, n, depth + 1)
  end
end

local function signature(nodes, out)
  for _, n in ipairs(nodes) do out[#out + 1] = n.key; signature(n.children, out) end
  return out
end

-- Rebuild the tabs from what is registered and running now.
function H.Rebuild()
  H.byKey, H.tree = {}, tree()
  index(H.tree, nil, 0)
  local sig = table.concat(signature(H.tree, {}), " ")
  local changed = sig ~= H.sig
  H.sig = sig
  if not H.box then return end
  -- The overview and other-addons pages list what runs now, so they are made again when that changed
  -- (only then: the game never frees a frame, so a page made on every open would pile up).
  if changed then
    for _, key in ipairs({ "zip", "other" }) do
      local old = H.pages[key]
      if old then old:Hide(); H.pages[key] = nil; if H.shown == old then H.shown = nil end end
    end
  end
  H.Select(H.byKey[H.current] and H.current or "zip")
end

function H.Has(key) return H.byKey[key] ~= nil end

-- One tab button from pool `level` (1 = main tabs, 2 and deeper = sub-tabs), made once and reused.
local function tab(level, i)
  H.pools[level] = H.pools[level] or {}
  local pool = H.pools[level]
  if not pool[i] then pool[i] = Z.Tab(H.panel, level == 1, function(self) H.Select(self.key, true) end) end
  return pool[i]
end

-- Where a row of tabs must wrap: the panel's real width once the game has laid it out.
function H.Right()
  local w = H.panel.GetWidth and H.panel:GetWidth()
  if type(w) == "number" and w > 300 then return w - PAD end
  return WIDTH - PAD
end

-- Lay one row of tabs out from x = PAD at height y, wrapping when it runs past the window. Returns the next free y.
local function row(level, y, entries, activeKey)
  local big = level == 1
  local x, h = PAD, big and 30 or 22
  for i, e in ipairs(entries) do
    local b = tab(level, i)
    b.key = e.key
    local w = Z.FitTab(b, e.node.icon, e.title, big)
    if x + w > H.Right() and x > PAD then x, y = PAD, y + h + 4 end
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", x, -y)
    Z.StyleTab(b, e.key == activeKey, big)
    H.rows[#H.rows + 1], H.flat[#H.flat + 1] = b, e.node
    x = x + w + 4
  end
  for i = #entries + 1, #H.pools[level] do H.pools[level][i]:Hide() end
  return y + h + 6
end

-- The tabs of a group: its own page first (named by `home`), then its children.
local function groupEntries(node)
  local out = { { key = node.key, title = node.home or node.title, node = node } }
  for _, c in ipairs(node.children) do out[#out + 1] = { key = c.key, title = c.title, node = c } end
  return out
end

-- The path from the top tab down to the current page: { top, sub, subsub }.
local function chain(key)
  local path, n = {}, H.byKey[key]
  while n do table.insert(path, 1, n); n = n.parent end
  return path
end

local function hideFrom(level)
  for lv, pool in pairs(H.pools) do
    if lv >= level then for _, b in ipairs(pool) do b:Hide() end end
  end
end

-- Draw the tab rows for the current page and fit the page box under them.
function H.Layout()
  H.rows, H.flat = {}, {}
  local path = chain(H.current)
  local top = {}
  for _, n in ipairs(H.tree) do top[#top + 1] = { key = n.key, title = n.title, node = n } end
  local y = row(1, HEAD_H, top, path[1] and path[1].key)
  local level = 2
  while path[level - 1] and #path[level - 1].children > 0 do
    local group = path[level - 1]
    y = row(level, y, groupEntries(group), (path[level] or group).key)
    level = level + 1
  end
  hideFrom(level)
  H.box:ClearAllPoints()
  H.box:SetPoint("TOPLEFT", PAD - 6, -(y + 2))
  H.box:SetPoint("BOTTOMRIGHT", -(PAD - 6), 8)
end

local function crumbs(node)
  local parts = {}
  for _, n in ipairs(chain(node.key)) do parts[#parts + 1] = n.title end
  return "Zip  >  " .. table.concat(parts, "  >  ")
end

-- A page: big icon, title and where it sits, then the page body.
local function buildPage(node)
  local page = CreateFrame("Frame", nil, H.scroll)
  page:SetSize(PAGE_W, 1)
  local icon = page:CreateTexture(nil, "ARTWORK")
  icon:SetSize(32, 32)
  icon:SetPoint("TOPLEFT", 0, 0)
  icon:SetTexture(node.icon)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local title = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -1)
  title:SetText(node.title)
  local where = page:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  where:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
  where:SetText(crumbs(node))
  local top = H.Heading(page, 38, "")
  local body = CreateFrame("Frame", nil, page)
  body:SetPoint("TOPLEFT", 0, -top)
  body:SetSize(PAGE_W, 1)
  -- A page that throws while it builds says so on the page and sends the error to the game's error display,
  -- so the rest of the settings home keeps working. It is kept, so it is not built again on every click.
  local ok, height = xpcall(function() return node.Build(body) end, function(err)
    local handler = geterrorhandler and geterrorhandler()
    if handler then handler(err) end
    return err
  end)
  if not ok then
    body:Hide()
    body = CreateFrame("Frame", nil, page)
    body:SetPoint("TOPLEFT", 0, -top)
    body:SetSize(PAGE_W, 1)
    height = H.Text(body, 0, L["This page could not be drawn."], "GameFontDisable")
    page.broken = true
  end
  height = type(height) == "number" and height or 0
  body:SetHeight(height)
  page:SetHeight(top + height + PAD)
  return page
end

local function show(node)
  local page = H.pages[node.key]
  if not page then
    page = buildPage(node)
    H.pages[node.key] = page
  end
  if H.shown and H.shown ~= page then H.shown:Hide() end
  page:Show()
  H.scroll:SetScrollChild(page)
  H.scroll:SetVerticalScroll(0)
  H.shown = page
  return page
end

-- Open a page by key ("zipkit", "zipkit/autotrain/weapons", "zipbar/bar").
function H.Select(key)
  if not H.box then H.want = key return true end -- the window is not built yet: remember it
  local node = H.byKey[key]
  if not node then return false end
  H.current = key
  H.Layout()
  local page = show(node)
  -- Only a page that drew is remembered, so a broken page does not open first every session.
  if not page.broken then Z.SetPref("hubLast", key)
  elseif Z.Prefs().hubLast == key then Z.SetPref("hubLast", "zip") end
  return true
end

-- Build the window inside the options panel (called the first time the panel is shown).
function H.Fill(panel)
  H.panel, H.pools = panel, {}
  local rule = panel:CreateTexture(nil, "ARTWORK")
  rule:SetPoint("TOPLEFT", PAD, -(HEAD_H - 6))
  rule:SetSize(WIDTH - 2 * PAD, 1)
  rule:SetColorTexture(Z.GOLD[1], Z.GOLD[2], Z.GOLD[3], 0.35)
  H.box = Z.FramedFrame("Frame", panel)
  H.scroll = CreateFrame("ScrollFrame", nil, H.box, "UIPanelScrollFrameTemplate")
  H.scroll:SetPoint("TOPLEFT", 12, -12)
  H.scroll:SetPoint("BOTTOMRIGHT", -30, 10)
  panel:SetScript("OnShow", function() H.Rebuild() end) -- addons may have loaded since: list what runs now
  local key = H.want or Z.Prefs().hubLast
  H.want = nil
  if not (key and H.Select(key)) then H.Select("zip") end
end

local function register(panel)
  if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
    H.category = category
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
  end
end

-- The options panel, made once at login when every Zip addon has registered.
function H.Build()
  if H.panel or H.built then return end
  H.built = true
  local panel = CreateFrame("Frame", "ZipUIOptions", UIParent)
  panel.name = "Zip"
  H.optionsPanel = panel
  local head = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
  head:SetPoint("TOPLEFT", PAD, -PAD)
  head:SetText("Zip")
  register(panel)
  H.Rebuild()
  -- The controls are made the first time the panel is shown, so a login that never opens it pays nothing.
  panel:SetScript("OnShow", function(self)
    self:SetScript("OnShow", nil)
    H.Fill(self)
  end)
end
Z.On("PLAYER_LOGIN", H.Build)

-- Open the settings home, on a page when a key is given.
function Z.Open(key)
  H.Build()
  if key then H.Select(key) end
  if Settings and Settings.OpenToCategory and H.category then
    Settings.OpenToCategory(H.category:GetID())
  elseif InterfaceOptionsFrame_OpenToCategory then
    InterfaceOptionsFrame_OpenToCategory(H.optionsPanel) -- called twice: the first call can open the wrong page
    InterfaceOptionsFrame_OpenToCategory(H.optionsPanel)
  end
end
