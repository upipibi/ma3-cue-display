-- Zero-dependency test runner. The whole point of this project is that it needs
-- nothing but Lua, so the tests need nothing but Lua either.
local M = { passed = 0, failed = 0, failures = {} }
local current = "?"

function M.describe(name, fn)
  current = name
  fn()
end

function M.it(name, fn)
  local ok, err = pcall(fn)
  if ok then
    M.passed = M.passed + 1
  else
    M.failed = M.failed + 1
    M.failures[#M.failures + 1] =
      string.format("%s > %s\n      %s", current, name, tostring(err))
  end
end

local function fmt(v)
  if type(v) == "table" then
    local parts = {}
    for k, x in pairs(v) do
      parts[#parts + 1] = tostring(k) .. "=" .. fmt(x)
    end
    table.sort(parts)
    return "{" .. table.concat(parts, ",") .. "}"
  end
  if type(v) == "string" then return string.format("%q", v) end
  return tostring(v)
end

function M.assert_equal(actual, expected, msg)
  if actual ~= expected then
    error(string.format("%sexpected %s, got %s",
      msg and (msg .. ": ") or "", fmt(expected), fmt(actual)), 2)
  end
end

function M.assert_match(actual, pattern)
  if type(actual) ~= "string" or not actual:find(pattern, 1, true) then
    error(string.format("expected %s to contain %s", fmt(actual), fmt(pattern)), 2)
  end
end

function M.assert_nil(actual)
  if actual ~= nil then
    error(string.format("expected nil, got %s", fmt(actual)), 2)
  end
end

function M.report()
  for _, f in ipairs(M.failures) do io.write("FAIL  ", f, "\n") end
  io.write(string.format("\n%d passed, %d failed\n", M.passed, M.failed))
  os.exit(M.failed == 0 and 0 or 1)
end

return M
