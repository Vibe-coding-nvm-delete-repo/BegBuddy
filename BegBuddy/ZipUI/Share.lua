-- Share: turn an addon's settings into one line of text, and a line of text back into a saved setup, so players
-- can trade setups. The line is  ZIP1:<addon key>:<base64 data>:<check>  . The data is a plain text form of
-- tables, numbers, strings and booleans that is read back by hand: pasted text is never run as code.
if ZipUI.skip then return end
local Z = ZipUI
local L = Z.L
local S = {}
Z.Share = S

local fmt, floor = string.format, math.floor
local MAX_DEPTH, MAX_ITEMS, MAX_LEN = 12, 20000, 400000

local function supported(k, v)
  local tk, tv = type(k), type(v)
  if tk ~= "string" and tk ~= "number" then return false end
  if tv == "number" then return v == v and v ~= math.huge and v ~= -math.huge end
  return tv == "string" or tv == "boolean" or tv == "table"
end

local function sortedKeys(t)
  local keys = {}
  for k, v in pairs(t) do
    if supported(k, v) then keys[#keys + 1] = k end
  end
  table.sort(keys, function(a, b)
    if type(a) ~= type(b) then return type(a) == "number" end
    return a < b
  end)
  return keys
end

local function put(v, out, depth)
  local t = type(v)
  if t == "number" then
    out[#out + 1] = "n" .. fmt("%.17g", v) .. ";"
  elseif t == "boolean" then
    out[#out + 1] = v and "T" or "F"
  elseif t == "string" then
    out[#out + 1] = "s" .. #v .. ":" .. v
  else
    if depth > MAX_DEPTH then error("too deep") end
    out[#out + 1] = "{"
    for _, k in ipairs(sortedKeys(v)) do
      put(k, out, depth + 1)
      put(v[k], out, depth + 1)
    end
    out[#out + 1] = "}"
  end
end

-- Table in, text out.
function S.Serialize(tbl)
  local out = {}
  put(tbl, out, 0)
  return table.concat(out)
end

local read

local function readNumber(s, i)
  local e = s:find(";", i, true)
  local n = e and tonumber(s:sub(i + 1, e - 1))
  if not n or n ~= n or n == math.huge or n == -math.huge then error("bad number") end
  return n, e + 1
end

local function readString(s, i)
  local colon = s:find(":", i, true)
  local len = colon and tonumber(s:sub(i + 1, colon - 1))
  if not len or len < 0 or len ~= floor(len) then error("bad string") end
  local str = s:sub(colon + 1, colon + len)
  if #str ~= len then error("short string") end
  return str, colon + len + 1
end

local function readTable(s, i, depth, count)
  if depth > MAX_DEPTH then error("too deep") end
  local t = {}
  i = i + 1
  while s:sub(i, i) ~= "}" do
    if i > #s then error("unfinished table") end
    local k, v
    k, i = read(s, i, depth + 1, count)
    if type(k) ~= "string" and type(k) ~= "number" then error("bad key") end
    v, i = read(s, i, depth + 1, count)
    t[k] = v
  end
  return t, i + 1
end

function read(s, i, depth, count)
  count.n = count.n + 1
  if count.n > MAX_ITEMS then error("too big") end
  local c = s:sub(i, i)
  if c == "n" then return readNumber(s, i) end
  if c == "T" then return true, i + 1 end
  if c == "F" then return false, i + 1 end
  if c == "s" then return readString(s, i) end
  if c == "{" then return readTable(s, i, depth, count) end
  error("unknown mark")
end

-- Text in, table out (nil and a reason when the text is not something Serialize made).
function S.Parse(text)
  local ok, value, nextAt = pcall(read, text, 1, 0, { n = 0 })
  if not ok then return nil, value end
  if nextAt ~= #text + 1 or type(value) ~= "table" then return nil, "trailing data" end
  return value
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local UNB64 = {}
for i = 1, 64 do UNB64[B64:sub(i, i)] = i - 1 end

function S.Base64(s)
  local out = {}
  for i = 1, #s, 3 do
    local a, b, c = s:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    local d = { floor(n / 262144) % 64, floor(n / 4096) % 64, floor(n / 64) % 64, n % 64 }
    local chunk = {}
    for j = 1, 4 do chunk[j] = B64:sub(d[j] + 1, d[j] + 1) end
    if not b then chunk[3], chunk[4] = "=", "=" elseif not c then chunk[4] = "=" end
    out[#out + 1] = table.concat(chunk)
  end
  return table.concat(out)
end

function S.Unbase64(text)
  text = text:gsub("=+$", "")
  if text:find("[^A-Za-z0-9+/]") or #text % 4 == 1 then return nil end
  local out = {}
  for i = 1, #text, 4 do
    local n, got = 0, 0
    for j = 0, 3 do
      local ch = text:sub(i + j, i + j)
      n = n * 64 + (ch ~= "" and UNB64[ch] or 0)
      if ch ~= "" then got = got + 1 end
    end
    local bytes = { floor(n / 65536) % 256, floor(n / 256) % 256, n % 256 }
    for j = 1, got - 1 do out[#out + 1] = string.char(bytes[j]) end
  end
  return table.concat(out)
end

local function check(s)
  local a, b = 1, 0
  for i = 1, #s do
    a = (a + s:byte(i)) % 65521
    b = (b + a) % 65521
  end
  return fmt("%04x%04x", b, a)
end

-- The line for an addon's current settings.
function S.Encode(def)
  local snap = Z.Profiles.Snapshot(def)
  if not snap then return nil, L["this addon has no setups to save"] end
  local raw = S.Serialize(Z.Profiles.Strip(def, snap)) -- never the player's own lists or spending limits
  return "ZIP1:" .. def.key .. ":" .. S.Base64(raw) .. ":" .. check(raw)
end

-- Read a line back: the settings table and the addon key it was made for, or nil and a reason.
function S.Decode(line)
  line = (line or ""):gsub("%s+", "")
  if #line > MAX_LEN then return nil, L["That code is too long."] end
  local key, data, sum = line:match("^ZIP1:([%w_%-]+):([A-Za-z0-9+/=]+):(%x+)$")
  if not key then return nil, L["That is not a Zip setup code."] end
  local raw = S.Unbase64(data)
  if not raw or check(raw) ~= sum then return nil, L["The code is damaged. Copy it again, all of it."] end
  local snap, err = S.Parse(raw)
  if not snap then return nil, L["The code is damaged. Copy it again, all of it."] .. " (" .. tostring(err) .. ")" end
  return snap, key
end

local function freeName(def, base)
  local taken = {}
  for _, n in ipairs(Z.Profiles.List(def)) do taken[n] = true end
  if not taken[base] then return base end
  local i = 2
  while taken[base .. " " .. i] do i = i + 1 end
  return base .. " " .. i
end

-- Add a pasted line as a saved setup (it is not loaded). Returns the setup name, or nil and a reason.
function S.Import(def, line, name)
  local snap, key = S.Decode(line)
  if not snap then return nil, key end
  if key ~= def.key then return nil, L["That code is for another addon:"] .. " " .. key end
  name = freeName(def, (name and name ~= "") and name or L["Imported"])
  if not Z.Profiles.Put(def, name, snap) then return nil, L["The code has no settings for this addon."] end
  return name
end
