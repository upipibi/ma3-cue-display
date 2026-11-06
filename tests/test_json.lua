local t = require("runner")
local json = require("json")

t.describe("json.encode", function()
  t.it("encodes strings with escaping", function()
    t.assert_equal(json.encode("hi"), '"hi"')
    t.assert_equal(json.encode('a"b'), '"a\\"b"')
    t.assert_equal(json.encode("a\\b"), '"a\\\\b"')
    t.assert_equal(json.encode("a\nb"), '"a\\nb"')
    t.assert_equal(json.encode("a\tb"), '"a\\tb"')
  end)

  t.it("escapes other control characters as \\u", function()
    t.assert_equal(json.encode("a\1b"), '"a\\u0001b"')
  end)

  t.it("encodes integers without a decimal point", function()
    t.assert_equal(json.encode(42), "42")
    t.assert_equal(json.encode(0), "0")
    t.assert_equal(json.encode(-7), "-7")
  end)

  t.it("encodes floats compactly", function()
    t.assert_equal(json.encode(12.5), "12.5")
  end)

  -- Regression: at %.6g a Unix timestamp collapsed to "1.78595e+09" and stayed
  -- byte-identical for hours, so viewers read a healthy console as wedged.
  t.it("keeps full precision on Unix-scale timestamps", function()
    t.assert_equal(json.encode(1785949123.45), "1785949123.45")
  end)

  t.it("renders successive timestamps as distinct strings", function()
    local a = json.encode(1785949123.45)
    local b = json.encode(1785949123.65)
    if a == b then
      error("two timestamps 200ms apart encoded identically: " .. a)
    end
  end)

  t.it("encodes non-finite numbers as null", function()
    t.assert_equal(json.encode(1 / 0), "null")
    t.assert_equal(json.encode(0 / 0), "null")
  end)

  t.it("encodes booleans and nil", function()
    t.assert_equal(json.encode(true), "true")
    t.assert_equal(json.encode(false), "false")
    t.assert_equal(json.encode(nil), "null")
  end)

  t.it("encodes arrays in order", function()
    t.assert_equal(json.encode({ "a", "b" }), '["a","b"]')
  end)

  t.it("encodes an empty table as an empty array", function()
    t.assert_equal(json.encode({}), "[]")
  end)

  t.it("encodes objects with sorted keys so output is deterministic", function()
    t.assert_equal(json.encode({ b = 2, a = 1 }), '{"a":1,"b":2}')
  end)

  t.it("encodes the real state payload shape", function()
    t.assert_equal(
      json.encode({
        sequence = "Main",
        cueNumber = "12.5",
        cueName = 'Sermon "Wash"',
        activeSequences = { "Main", "Haze" },
        updatedAt = 5,
        version = "2.0.0",
      }),
      '{"activeSequences":["Main","Haze"],"cueName":"Sermon \\"Wash\\"",'
        .. '"cueNumber":"12.5","sequence":"Main","updatedAt":5,"version":"2.0.0"}'
    )
  end)

  t.it("writes json.null as null inside arrays and objects", function()
    t.assert_equal(json.encode({ 1, json.null, 3 }), "[1,null,3]")
    t.assert_equal(json.encode({ a = json.null }), '{"a":null}')
    t.assert_equal(json.encode(json.null), "null")
  end)

  t.it("encodes an array of eight nulls, and nulls in any position", function()
    local n = json.null
    t.assert_equal(json.encode({ n, n, n, n, n, n, n, n }),
      "[null,null,null,null,null,null,null,null]")
    t.assert_equal(json.encode({ n, { number = 55 }, n }), '[null,{"number":55},null]')
  end)
end)
