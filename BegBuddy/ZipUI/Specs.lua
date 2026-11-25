-- Settings pages described as data rows and built in a loop, so each page stays short:
-- { type = "check", label = "Show the bar", tbl = function() return db.bar end, key = "shown" }.
-- Types: header, text, check, slider, choice, button, swatch. A row may give get/set instead of tbl/key.
if ZipUI.skip then return end
local Z = ZipUI

local ROW_H = { header = 26, text = 22, check = 24, slider = 48, choice = 32, swatch = 26, button = 30 }
-- A slider draws its title above its own frame, so it sits this much lower than its row top.
local DROP = { slider = 16 }
Z.ROW_H = ROW_H

local function accessors(s, changed)
  if s.get then
    return s.get, function(v) s.set(v); if changed then changed(s) end end
  end
  local function get()
    local v = s.tbl()[s.key]
    if v == nil then return s.default end
    return v
  end
  local function set(v)
    s.tbl()[s.key] = v
    if changed then changed(s) end
    if s.after then s.after(v) end
  end
  return get, set
end

local MAKE = {}
function MAKE.header(p, s)
  local fs = Z.Text(p, 13, Z.Colors.accent, "LEFT")
  fs:SetText(s.label)
  return fs
end
function MAKE.text(p, s)
  local fs = Z.Text(p, 12, Z.Colors.dim, "LEFT")
  fs:SetWidth(s.width or 300)
  fs:SetText(s.label)
  return fs
end
function MAKE.check(p, s, changed) return Z.Check(p, s.label, accessors(s, changed)) end
function MAKE.slider(p, s, changed)
  local g, st = accessors(s, changed)
  return Z.Slider(p, s.label, s.min or 0, s.max or 100, s.step or 1, g, st, s.fmt)
end
function MAKE.choice(p, s, changed)
  local g, st = accessors(s, changed)
  return Z.Choice(p, s.label, s.choices, g, st, s.wrap)
end
function MAKE.button(p, s)
  if s.confirm then return Z.ConfirmButton(p, s.label, s.width or 180, s.onClick) end
  return Z.Button(p, s.label, s.width or 180, 22, s.onClick)
end
function MAKE.swatch(p, s, changed) return Z.Swatch(p, s.label, accessors(s, changed)) end

-- Lay specs out down one or two columns (spec.col = 1 or 2). changed(spec) runs after any value changes.
-- Returns the widgets (for Z.Refresh) and the height used.
function Z.Build(parent, specs, colW, changed)
  local y, widgets, col = { 0, 0 }, {}, 1
  for _, s in ipairs(specs) do
    col = s.col or col -- a spec with col set moves every later spec to that column
    local w = MAKE[s.type](parent, s, changed)
    w:SetPoint("TOPLEFT", parent, "TOPLEFT", 8 + (col - 1) * (colW or 320), -(8 + y[col] + (DROP[s.type] or 0)))
    local h = ROW_H[s.type]
    if s.type == "choice" then h = math.max(h, w:GetHeight() + 10) end
    y[col] = y[col] + h
    widgets[#widgets + 1] = w
  end
  return widgets, math.max(y[1], y[2]) + 16
end

-- Re-read saved values into controls that know how (after a reset or an outside change).
function Z.Refresh(widgets)
  for _, w in ipairs(widgets or {}) do
    if type(w.Refresh) == "function" then w:Refresh() end
  end
end
