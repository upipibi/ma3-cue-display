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
end)
