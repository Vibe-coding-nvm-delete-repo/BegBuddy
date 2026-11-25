-- Widgets in the shared look: text, headings, buttons, check boxes, sliders, choice rows, inputs, colour boxes,
-- progress bars, scroll areas and framed boxes. Built from plain frames and colour textures, so no dropdown taint.
if ZipUI.skip then return end
local Z = ZipUI
local C, L = Z.Colors, Z.L
local max, min, floor = math.max, math.min, math.floor

local WHITE8 = "Interface/Buttons/WHITE8x8"
local function setColor(tex, c) tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
Z.SetColor = setColor

-- Unique names for the Blizzard templates that need a global name.
local counter = 0
function Z.UniqueName(prefix)
  counter = counter + 1
  return "ZipUI" .. prefix .. counter
end

-- A one pixel border with a flat fill inside it.
function Z.Box(frame, bg, border)
  frame.border = frame.border or frame:CreateTexture(nil, "BACKGROUND", nil, -2)
  frame.bg = frame.bg or frame:CreateTexture(nil, "BACKGROUND", nil, -1)
  frame.border:SetAllPoints()
  setColor(frame.border, border or C.border)
  frame.bg:SetPoint("TOPLEFT", 1, -1)
  frame.bg:SetPoint("BOTTOMRIGHT", -1, 1)
  setColor(frame.bg, bg or C.panel)
  return frame
end

-- The framed box pages sit in: dark marble with a gold-grey border, like a quest log page.
Z.BACKDROP = BackdropTemplateMixin and "BackdropTemplate" or nil -- the template a frame needs for SetBackdrop
function Z.Framed(frame)
  if frame.SetBackdrop then
    frame:SetBackdrop({
      bgFile = "Interface/DialogFrame/UI-DialogBox-Background-Dark", tile = true, tileSize = 32,
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 14,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
  else
    Z.Box(frame, C.bg, C.border)
  end
  return frame
end

-- A new framed frame: Z.FramedFrame("Frame", parent) or with a global name.
function Z.FramedFrame(kind, parent, name)
  return Z.Framed(CreateFrame(kind or "Frame", name, parent, Z.BACKDROP))
end

function Z.Text(parent, size, color, justify, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  fs:SetFont(Z.Font, size or 12, "")
  local c = color or C.text
  fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
  fs:SetJustifyH(justify or "LEFT")
  return fs
end

-- A wrapped paragraph at height y, `width` wide. Returns the next free y.
function Z.Para(parent, y, str, width, template)
  local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
  fs:SetPoint("TOPLEFT", 0, -y)
  fs:SetWidth(width or 540)
  fs:SetJustifyH("LEFT")
  fs:SetText(str)
  return y + fs:GetStringHeight() + 8
end

-- A gold section heading with a thin rule under it. Returns the next free y.
function Z.Heading(parent, y, str, width)
  local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  fs:SetPoint("TOPLEFT", 0, -y)
  fs:SetText(str)
  local rule = parent:CreateTexture(nil, "ARTWORK")
  rule:SetPoint("TOPLEFT", 0, -(y + 16))
  rule:SetSize(width or 540, 1)
  rule:SetColorTexture(Z.GOLD[1], Z.GOLD[2], Z.GOLD[3], 0.25)
  return y + 24
end

-- A flat button. SetActive(true) lights it as the chosen one in a row of buttons.
function Z.Button(parent, text, w, h, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w or 80, h or 22)
  Z.Box(b, C.panel, C.border)
  b.label = Z.Text(b, 12, C.accent, "CENTER")
  b.label:SetPoint("CENTER")
  b.label:SetText(text or "")
  b.hl = b:CreateTexture(nil, "HIGHLIGHT")
  b.hl:SetAllPoints()
  setColor(b.hl, C.hover)
  b:SetScript("OnClick", function(self, ...)
    Z.Sound("IG_MAINMENU_OPTION")
    if onClick then onClick(self, ...) end
  end)
  function b:SetText(s) self.label:SetText(s) end
  function b:SetActive(on)
    self.active = on and true or false
    setColor(self.bg, on and C.active or C.panel)
    local c = on and Z.WHITE or C.accent
    self.label:SetTextColor(c[1], c[2], c[3], 1)
  end
  return b
end

-- A tick box with a label: a real CheckButton, so GetChecked works, drawn in the shared look.
-- get() reads the setting, set(value) writes it. A box in a Group also refreshes the group's "Check all".
function Z.Check(parent, label, get, set)
  local cb = CreateFrame("CheckButton", nil, parent)
  cb:SetSize(16, 16)
  Z.Box(cb, C.bg, C.border)
  cb:SetCheckedTexture("Interface/Buttons/UI-CheckBox-Check")
  local glow = cb:CreateTexture(nil, "HIGHLIGHT")
  glow:SetAllPoints()
  setColor(glow, C.hover)
  cb.label = Z.Text(cb, 12, C.text, "LEFT")
  cb.label:SetPoint("LEFT", cb, "RIGHT", 6, 0)
  cb.label:SetText(label or "")
  cb:SetHitRectInsets(0, -min(400, (cb.label:GetStringWidth() or 0) + 8), 0, 0) -- the label clicks too
  function cb:Refresh() self:SetChecked(get() and true or false) end
  cb:SetScript("OnShow", cb.Refresh) -- a page is built once; a command or another page may have changed it since
  cb:SetScript("OnClick", function(self)
    local on = self:GetChecked() and true or false
    Z.Sound(on and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
    set(on)
    if self.group then self.group:Refresh() end
  end)
  cb:Refresh()
  return cb
end

-- A list of check boxes with a "Check all" box above it: list = { { label, get, set }, ... }, laid out in
-- `cols` columns `colW` wide from height y. Ticking "Check all" ticks every box; unticking it clears them.
-- Returns the height used below y.
function Z.Group(parent, y, list, cols, colW)
  cols, colW = cols or 1, colW or 260
  local boxes, top, group = {}, y, {}
  if #list >= 2 then
    local all = Z.Check(parent, "|cffffd100" .. L["Check all"] .. "|r", function()
      for _, e in ipairs(list) do if not e[2]() then return false end end
      return true
    end, function(v)
      for _, e in ipairs(list) do e[3](v) end
    end)
    all:SetPoint("TOPLEFT", 0, -y)
    all.group, group.all = group, all
    y = y + 24
  end
  for i, e in ipairs(list) do
    local col, row = (i - 1) % cols, floor((i - 1) / cols)
    local cb = Z.Check(parent, e[1], e[2], e[3])
    cb:SetPoint("TOPLEFT", col * colW + (group.all and 16 or 0), -(y + row * 24))
    cb.group, boxes[i] = group, cb
  end
  function group:Refresh()
    for i, cb in ipairs(boxes) do cb:SetChecked(list[i][2]() and true or false) end
    if self.all then self.all:Refresh() end
  end
  return y - top + math.ceil(#list / cols) * 24
end

-- A stack of check boxes for yes/no options saved in db: list = { { saved key, label }, ... }. Returns the height.
function Z.Options(parent, db, list, y)
  local entries = {}
  for _, opt in ipairs(list) do
    local key = opt[1]
    entries[#entries + 1] = { opt[2], function() return db[key] == true end, function(v) db[key] = v end }
  end
  return Z.Group(parent, y or 0, entries)
end

local function styleSlider(s, lo, hi)
  local name = s:GetName()
  if _G[name .. "Low"] then _G[name .. "Low"]:SetText("") end
  if _G[name .. "High"] then _G[name .. "High"]:SetText("") end
  local title = _G[name .. "Text"] or Z.Text(s, 12)
  title:SetFont(Z.Font, 12, "")
  title:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
  s.title = title
  s:SetMinMaxValues(lo, hi)
end

-- A labelled slider that shows its value in the label. fmt is a format string such as "%d%%".
function Z.Slider(parent, label, lo, hi, step, get, set, fmt)
  local s = CreateFrame("Slider", Z.UniqueName("Slider"), parent, "OptionsSliderTemplate")
  s:SetWidth(200)
  styleSlider(s, lo, hi)
  s:SetValueStep(step or 1)
  if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
  local function show(v) s.title:SetText((label or "") .. ": " .. string.format(fmt or "%s", v)) end
  function s:Refresh()
    self.quiet = true
    self:SetValue(get())
    self.quiet = false
    show(self:GetValue() or get())
  end
  s:SetScript("OnValueChanged", function(self, v)
    show(v)
    if not self.quiet then set(v) end
  end)
  s:SetScript("OnShow", s.Refresh)
  s:Refresh()
  return s
end

-- Choices may be plain strings or { value, text } pairs.
local function choiceParts(c)
  if type(c) == "table" then return c[1] or c.value, c[2] or c.text or c[1] or c.value end
  return c, c
end

-- A label and a row of small buttons, one per choice. No dropdown. A row too wide for maxW wraps.
function Z.Choice(parent, label, choices, get, set, maxW)
  local f = CreateFrame("Frame", nil, parent)
  f.label = Z.Text(f, 12, C.text, "LEFT")
  f.label:SetPoint("TOPLEFT", 0, -4)
  f.label:SetText(label or "")
  local labelW = max(40, min(120, math.ceil(f.label:GetStringWidth() or 0) + 10))
  f.label:SetWidth(labelW)
  f.buttons = {}
  local x, line, widest = labelW + 6, 0, 0
  for i, c in ipairs(choices) do
    local value, text = choiceParts(c)
    local b = Z.Button(f, tostring(text), max(40, #tostring(text) * 7 + 14), 20, function()
      set(value)
      f:Refresh()
    end)
    b.value = value
    if maxW and x > labelW + 6 and x + b:GetWidth() > maxW then x, line = labelW + 6, line + 1 end
    b:SetPoint("TOPLEFT", x, -line * 24 - 1)
    x = x + b:GetWidth() + 4
    widest = max(widest, x)
    f.buttons[i] = b
  end
  f:SetSize(widest, 22 + line * 24)
  function f:Refresh()
    local cur = get()
    for _, b in ipairs(self.buttons) do b:SetActive(b.value == cur) end
  end
  f:SetScript("OnShow", f.Refresh)
  f:Refresh()
  return f
end

function Z.Edit(parent, w, h, onEnter)
  local e = CreateFrame("EditBox", nil, parent)
  e:SetSize(w or 100, h or 22)
  Z.Box(e, C.bg, C.border)
  e:SetFont(Z.Font, 12, "")
  e:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
  e:SetTextInsets(5, 5, 0, 0)
  e:SetAutoFocus(false)
  e:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    if onEnter then onEnter(self:GetText(), self) end
  end)
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  return e
end

-- Presets used when the game has no colour picker (and for right click).
local PALETTE = {
  { 0.04, 0.04, 0.06 }, { 0, 0, 0 }, { 0.1, 0.1, 0.22 },
  { 0.22, 0.06, 0.06 }, { 0.05, 0.16, 0.08 }, { 0.2, 0.2, 0.2 },
}

local function openPicker(c, apply)
  local cp = ColorPickerFrame
  if not (cp and cp.SetupColorPickerAndShow) then return false end
  cp:SetupColorPickerAndShow({
    r = c[1], g = c[2], b = c[3], hasOpacity = false,
    swatchFunc = function() apply(cp:GetColorRGB()) end,
    cancelFunc = function() apply(c[1], c[2], c[3]) end,
  })
  return true
end

-- A colour box. Left click opens the picker when there is one, otherwise (and on right click) it cycles presets.
function Z.Swatch(parent, label, get, set)
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(300, 22)
  local text = Z.Text(row, 12, C.text, "LEFT")
  text:SetPoint("LEFT", 0, 0)
  text:SetText(label)
  local btn = CreateFrame("Button", nil, row)
  btn:SetSize(40, 18)
  btn:SetPoint("LEFT", 150, 0)
  Z.Box(btn, C.bg, C.border)
  local tex = btn:CreateTexture(nil, "ARTWORK")
  tex:SetPoint("TOPLEFT", 1, -1)
  tex:SetPoint("BOTTOMRIGHT", -1, 1)
  tex:SetTexture(WHITE8)
  local idx = 0
  local function paint()
    local c = get()
    tex:SetVertexColor(c[1], c[2], c[3])
  end
  local function apply(r, g, b) set({ r, g, b }); paint() end
  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  btn:SetScript("OnClick", function(_, which)
    if which ~= "RightButtonUp" and openPicker(get(), apply) then return end
    idx = idx % #PALETTE + 1
    apply(PALETTE[idx][1], PALETTE[idx][2], PALETTE[idx][3])
  end)
  row.Refresh = paint
  paint()
  return row
end

-- A bar with a fill, an optional rested overlay (drawn behind) and centred text.
function Z.Progress(parent, w, h)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w or 200, h or 16)
  Z.Box(f, C.bg, C.border)
  f.rested = f:CreateTexture(nil, "ARTWORK", nil, 0)
  f.fill = f:CreateTexture(nil, "ARTWORK", nil, 1)
  f.text = Z.Text(f, 11, C.text, "CENTER", "OVERLAY")
  f.text:SetPoint("CENTER")
  setColor(f.fill, C.xp)
  setColor(f.rested, C.rested)
  for _, t in ipairs({ f.fill, f.rested }) do
    t:SetPoint("TOPLEFT", 1, -1)
    t:SetPoint("BOTTOMLEFT", 1, 1)
  end
  local function width(frac)
    return max(0.001, floor((f:GetWidth() - 2) * max(0, min(1, frac or 0)) + 0.5))
  end
  function f:SetValue(frac)
    self.fill:SetShown(frac and frac > 0)
    self.fill:SetWidth(width(frac))
  end
  function f:SetRested(frac)
    self.rested:SetShown(frac and frac > 0)
    self.rested:SetWidth(width(frac))
  end
  function f:SetText(s) self.text:SetText(s or "") end
  function f:SetColors(fill, rested)
    if fill then setColor(self.fill, fill) end
    if rested then setColor(self.rested, rested) end
  end
  return f
end

-- A scroll area with Blizzard's scroll bar. Returns the scroll frame and the content frame inside it.
function Z.Scroll(parent, w, h)
  local sf = CreateFrame("ScrollFrame", Z.UniqueName("Scroll"), parent, "UIPanelScrollFrameTemplate")
  sf:SetSize(w, h)
  local content = CreateFrame("Frame", nil, sf)
  content:SetSize(max(1, w - 26), h)
  sf:SetScrollChild(content)
  return sf, content
end

-- A button that asks once before it acts: the first click turns it red with "Click again", the second acts.
function Z.ConfirmButton(parent, text, w, onConfirm)
  local b
  b = Z.Button(parent, text, w or 180, 22, function()
    if b.armed then
      b.armed = false
      b:SetText(text)
      return onConfirm()
    end
    b.armed = true
    b:SetText(L["Click again to confirm"])
    b.label:SetTextColor(C.bad[1], C.bad[2], C.bad[3], 1)
    if C_Timer then C_Timer.After(4, function() if b.armed then b.armed = false; b:SetText(text); b:SetActive(false) end end) end
  end)
  return b
end
