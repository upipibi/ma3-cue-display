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

-- ---------------------------------------------------------------------------
-- Grid reads: sequence number, cue fade, timecode
-- ---------------------------------------------------------------------------

-- A playing sequence whose current cue has a part 0 carrying the fade. reads
-- counts how often the fade property is asked for.
local function grid_seq(number, name, cue_no, fade, reads)
  local part = {
    Get = function(_, prop)
      if reads then reads.n = reads.n + 1 end
      if prop == "CUEINFADE" then return fade end
      return nil
    end,
  }
  local seq = {
    name = name, No = number, _cue_no = cue_no, _part = part,
    HasActivePlayback = function() return true end,
  }
  seq.CurrentChild = function(self)
    return { No = self._cue_no, name = "Cue", Ptr = function(_, i) if i == 1 then return self._part end end }
  end
  return seq
end

t.describe("ma3.snapshot for the grid", function()
  t.it("adds the sequence number, the raw cue key and the cue fade", function()
    local a = adapter_over({ grid_seq(55, "He Is", 3000, 2) })
    local s = ma3.snapshot(a)[1]
    t.assert_equal(s.number, 55)
    t.assert_equal(s.cueKey, 3000)
    t.assert_equal(s.fade, 2)
    t.assert_equal(s.cueNumber, "3")
  end)

  t.it("accepts a numeric string for the number and the fade", function()
    local a = adapter_over({ grid_seq("55", "He Is", 3000, "0.5") })
    local s = ma3.snapshot(a)[1]
    t.assert_equal(s.number, 55)
    t.assert_equal(s.fade, 0.5)
  end)

  t.it("falls back to Get(\"NO\") when the No field gives nothing", function()
    local seq = grid_seq(nil, "He Is", 3000, 2)
    seq.Get = function(_, prop) if prop == "NO" then return 55 end end
    t.assert_equal(ma3.snapshot(adapter_over({ seq }))[1].number, 55)
  end)

  t.it("keeps a fade of zero", function()
    local a = adapter_over({ grid_seq(55, "He Is", 3000, 0) })
    t.assert_equal(ma3.snapshot(a)[1].fade, 0)
  end)

  t.it("returns the entry with no fade when the fade is not a number", function()
    local a = adapter_over({ grid_seq(55, "He Is", 3000, "CueTiming") })
    local snaps = ma3.snapshot(a)
    t.assert_equal(#snaps, 1)
    t.assert_nil(snaps[1].fade)
  end)

  t.it("returns the entry with no fade when the cue has no part or the read throws", function()
    local no_part = grid_seq(55, "He Is", 3000, 2)
    no_part._part = nil
    local throws = grid_seq(56, "Other", 1000, 2)
    throws._part = { Get = function() error("gone in 3.0") end }
    local old_shape = fake_seq("Main", true, 1000, "A")     -- cue without Ptr at all
    local snaps = ma3.snapshot(adapter_over({ no_part, throws, old_shape }))
    t.assert_equal(#snaps, 3)
    t.assert_nil(snaps[1].fade)
    t.assert_nil(snaps[2].fade)
    t.assert_nil(snaps[3].fade)
    t.assert_nil(snaps[3].number)
  end)

  t.it("reads the fade once per cue, not once per scan", function()
    local reads = { n = 0 }
    local seq = grid_seq(55, "He Is", 3000, 2, reads)
    local a = adapter_over({ seq })
    ma3.snapshot(a); ma3.snapshot(a); ma3.snapshot(a)
    t.assert_equal(reads.n, 1)
    seq._cue_no = 4000
    t.assert_equal(ma3.snapshot(a)[1].cueKey, 4000)
    t.assert_equal(reads.n, 2)
  end)

  t.it("reads the fade again after the sequence stopped and came back", function()
    local reads = { n = 0 }
    local seq = grid_seq(55, "He Is", 3000, 2, reads)
    local a = adapter_over({ seq })
    ma3.snapshot(a)
    seq.HasActivePlayback = function() return false end
    ma3.snapshot(a)
    seq.HasActivePlayback = function() return true end
    ma3.snapshot(a)
    t.assert_equal(reads.n, 2)
  end)
end)

t.describe("ma3.timecode", function()
  local function slot_obj(raw)
    return { Get = function(_, prop) if prop == "TIME" then return raw end end }
  end

  t.it("converts the console's raw TIME to seconds", function()
    local a = ma3.new({ slot = function(n) return slot_obj(n == 1 and 120870893431 or 0) end })
    local out = ma3.timecode(a, { 1, 2 })
    t.assert_equal(#out, 2)
    t.assert_equal(out[1].slot, 1)
    t.assert_equal(math.abs(out[1].seconds - 7204.4667) < 0.001, true)
    t.assert_equal(out[2].slot, 2)
    t.assert_equal(out[2].seconds, 0)
  end)

  t.it("looks a slot up once and reuses the handle", function()
    local lookups = 0
    local a = ma3.new({ slot = function() lookups = lookups + 1 return slot_obj(16777216) end })
    ma3.timecode(a, { 1 }); ma3.timecode(a, { 1 }); ma3.timecode(a, { 1 })
    t.assert_equal(lookups, 1)
    t.assert_equal(ma3.timecode(a, { 1 })[1].seconds, 1)
  end)

  t.it("reports no seconds for a slot that cannot be found, and looks again next time", function()
    local lookups = 0
    local a = ma3.new({ slot = function() lookups = lookups + 1 return nil end })
    t.assert_nil(ma3.timecode(a, { 1 })[1].seconds)
    t.assert_nil(ma3.timecode(a, { 1 })[1].seconds)
    t.assert_equal(lookups, 2)
  end)

  t.it("reports no seconds when the lookup or the read throws, and recovers", function()
    local broken = true
    local a = ma3.new({ slot = function()
      if broken then return { Get = function() error("no TIME") end } end
      return slot_obj(33554432)
    end })
    t.assert_nil(ma3.timecode(a, { 1 })[1].seconds)
    broken = false
    t.assert_equal(ma3.timecode(a, { 1 })[1].seconds, 2)
    local b = ma3.new({ slot = function() error("no ObjectList") end })
    t.assert_nil(ma3.timecode(b, { 1 })[1].seconds)
  end)

  t.it("reports no seconds when TIME is not a number", function()
    local a = ma3.new({ slot = function() return slot_obj("soon") end })
    t.assert_nil(ma3.timecode(a, { 1 })[1].seconds)
  end)

  t.it("returns an empty list for no slots", function()
    t.assert_equal(#ma3.timecode(ma3.new({}), nil), 0)
  end)
end)
