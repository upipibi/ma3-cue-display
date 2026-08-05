local t = require("runner")
local ma3 = require("ma3")

t.describe("ma3.format_cue_number", function()
  t.it("divides by 1000 and trims trailing zeros", function()
    t.assert_equal(ma3.format_cue_number(1000), "1")
    t.assert_equal(ma3.format_cue_number(12500), "12.5")
    t.assert_equal(ma3.format_cue_number(12345), "12.345")
    t.assert_equal(ma3.format_cue_number(10000), "10")
    t.assert_equal(ma3.format_cue_number(20000), "20")
    t.assert_equal(ma3.format_cue_number(100), "0.1")
    t.assert_equal(ma3.format_cue_number(10), "0.01")
    t.assert_equal(ma3.format_cue_number(0), "0")
  end)

  t.it("falls back for non-numbers", function()
    t.assert_equal(ma3.format_cue_number(nil), "--")
    t.assert_equal(ma3.format_cue_number("nope"), "--")
    t.assert_equal(ma3.format_cue_number({}), "--")
  end)

  t.it("accepts numeric strings", function()
    t.assert_equal(ma3.format_cue_number("12500"), "12.5")
  end)
end)

-- Fake console objects matching the shape ma3.snapshot expects.
local function fake_seq(name, playing, cue_no, cue_name)
  return {
    name = name,
    HasActivePlayback = function() return playing end,
    CurrentChild = function()
      if cue_no == nil then return nil end
      return { No = cue_no, name = cue_name }
    end,
  }
end

local function adapter_over(seqs)
  return ma3.new({ sequences = function() return seqs end })
end

t.describe("ma3.snapshot", function()
  t.it("returns only playing sequences that have a current cue", function()
    local a = adapter_over({
      fake_seq("Main", true, 12500, "Sermon Wash"),
      fake_seq("Idle", false, 1000, "Nope"),
      fake_seq("NoCue", true, nil, nil),
    })
    local snaps = ma3.snapshot(a)
    t.assert_equal(#snaps, 1)
    t.assert_equal(snaps[1].name, "Main")
    t.assert_equal(snaps[1].cueNumber, "12.5")
    t.assert_equal(snaps[1].cueName, "Sermon Wash")
  end)

  t.it("preserves console iteration order", function()
    local a = adapter_over({
      fake_seq("Main", true, 1000, "A"),
      fake_seq("Haze", true, 2000, "B"),
    })
    local snaps = ma3.snapshot(a)
    t.assert_equal(snaps[1].name, "Main")
    t.assert_equal(snaps[2].name, "Haze")
  end)

  t.it("substitutes an empty string for a missing cue name", function()
    local a = adapter_over({ fake_seq("Main", true, 1000, nil) })
    t.assert_equal(ma3.snapshot(a)[1].cueName, "")
  end)

  t.it("substitutes ? for a missing sequence name", function()
    local s = fake_seq(nil, true, 1000, "A")
    local a = adapter_over({ s })
    t.assert_equal(ma3.snapshot(a)[1].name, "?")
  end)

  t.it("skips a sequence whose HasActivePlayback throws", function()
    local bad = fake_seq("Bad", true, 1000, "x")
    bad.HasActivePlayback = function() error("gone in 3.0") end
    local a = adapter_over({ bad, fake_seq("Main", true, 1000, "A") })
    local snaps = ma3.snapshot(a)
    t.assert_equal(#snaps, 1)
    t.assert_equal(snaps[1].name, "Main")
  end)

  t.it("skips a sequence whose CurrentChild throws", function()
    local bad = fake_seq("Bad", true, 1000, "x")
    bad.CurrentChild = function() error("no cue object") end
    local a = adapter_over({ bad, fake_seq("Main", true, 1000, "A") })
    local snaps = ma3.snapshot(a)
    t.assert_equal(#snaps, 1)
    t.assert_equal(snaps[1].name, "Main")
  end)

  t.it("returns an empty list when the sequence pool itself throws", function()
    local a = ma3.new({ sequences = function() error("no datapool") end })
    t.assert_equal(#ma3.snapshot(a), 0)
  end)

  t.it("returns an empty list when the pool is not a table", function()
    local a = ma3.new({ sequences = function() return nil end })
    t.assert_equal(#ma3.snapshot(a), 0)
  end)

  t.it("feeds state.update directly", function()
    local state = require("state")
    local a = adapter_over({ fake_seq("Main", true, 12500, "Sermon Wash") })
    local st = state.update(state.new(), ma3.snapshot(a))
    t.assert_equal(st.displayed.sequence, "Main")
    t.assert_equal(st.displayed.cueNumber, "12.5")
    t.assert_equal(st.displayed.cueName, "Sermon Wash")
  end)
end)
