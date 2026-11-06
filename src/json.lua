-- Minimal JSON encoder. We only ever encode, never decode, and the console is
-- not guaranteed to ship a JSON library. Object keys are sorted so output is
-- byte-deterministic and testable.
local M = {}

-- A marker for "null inside a table". Lua tables cannot hold nil, so an empty grid
-- slot or an unknown fade is written as json.null and encodes as null.
M.null = setmetatable({}, { __tostring = function() return "null" end })

local ESCAPES = {
  ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
  ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
}

local function escape_string(s)
  local out = s:gsub('[%c"\\]', function(c)
    return ESCAPES[c] or string.format("\\u%04x", c:byte())
  end)
  return out
end

-- A table is an array if every key is a positive integer with no gaps.
-- An empty table counts as an array: the only empty table we emit is
-- activeSequences, which is genuinely a list.
local function is_array(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" or k % 1 ~= 0 or k < 1 then return false end
    n = n + 1
  end
  return n == #t
end

function M.encode(v)
  local tv = type(v)
  if v == nil then
    return "null"
  elseif tv == "boolean" then
    return tostring(v)
  elseif tv == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "null" end
    if math.type(v) == "integer" then return tostring(v) end
    -- 14 significant digits, not 6. updatedAt carries a Unix timestamp, which
    -- needs 13 digits before the decimal point alone; at %.6g it rendered as
    -- 1.78595e+09 and stayed byte-identical for hours of real time. Every
    -- viewer uses that value as the console's heartbeat, so a frozen-looking
    -- updatedAt makes a healthy console read as wedged.
    return (string.format("%.14g", v))
  elseif tv == "string" then
    return '"' .. escape_string(v) .. '"'
  elseif tv == "table" then
    if v == M.null then return "null" end
    local parts = {}
    if is_array(v) then
      for i = 1, #v do parts[i] = M.encode(v[i]) end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    for _, k in ipairs(keys) do
      parts[#parts + 1] = '"' .. escape_string(k) .. '":' .. M.encode(v[k])
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  error("json: cannot encode type " .. tv)
end

return M
