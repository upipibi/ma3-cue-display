local t = require("runner")
local state = require("state")

local function snap(name, number, cuename)
  return { name = name, cueNumber = number, cueName = cuename or (name .. " cue") }
end

t.describe("state.update", function()
  t.it("starts empty", function()
    local st = state.new()
    t.assert_equal(st.displayed.sequence, "")
    t.assert_equal(st.displayed.cueNumber, "--")
    t.assert_equal(st.displayed.cueName, "")
  end)

  t.it("displays the first active sequence on cold start", function()
    local st = state.new()
    state.update(st, { snap("Main", "1"), snap("Haze", "3") })
    t.assert_equal(st.displayed.sequence, "Main")
    t.assert_equal(st.displayed.cueNumber, "1")
  end)

  t.it("follows a cue change on the displayed sequence", function()
    local st = state.new()
    state.update(st, { snap("Main", "1") })
    state.update(st, { snap("Main", "2") })
    t.assert_equal(st.displayed.sequence, "Main")
    t.assert_equal(st.displayed.cueNumber, "2")
  end)

  t.it("switches to another sequence when that one fires", function()
    local st = state.new()
    state.update(st, { snap("Main", "1") })
    state.update(st, { snap("Main", "1"), snap("Haze", "5") })
    t.assert_equal(st.displayed.sequence, "Haze")
    t.assert_equal(st.displayed.cueNumber, "5")
  end)

  t.it("keeps the displayed sequence when two change in one scan", function()
    local st = state.new()
    state.update(st, { snap("Main", "1"), snap("Haze", "1") })
    state.update(st, { snap("Main", "1"), snap("Haze", "1") })
    t.assert_equal(st.displayed.sequence, "Main")
    -- Both advance in the same scan. Main is displayed, so Main wins and the
    -- display does not flap to Haze.
    state.update(st, { snap("Main", "2"), snap("Haze", "2") })
    t.assert_equal(st.displayed.sequence, "Main")
    t.assert_equal(st.displayed.cueNumber, "2")
  end)

  t.it("takes the first changed sequence when the displayed one did not change", function()
    local st = state.new()
    state.update(st, { snap("Main", "1"), snap("Haze", "1"), snap("Strobe", "1") })
    t.assert_equal(st.displayed.sequence, "Main")
    state.update(st, { snap("Main", "1"), snap("Haze", "2"), snap("Strobe", "2") })
    t.assert_equal(st.displayed.sequence, "Haze")
  end)

  t.it("keeps the last cue when the displayed sequence stops playing", function()
    local st = state.new()
    state.update(st, { snap("Main", "7", "Sermon Wash") })
    state.update(st, {})
    t.assert_equal(st.displayed.sequence, "Main")
    t.assert_equal(st.displayed.cueNumber, "7")
    t.assert_equal(st.displayed.cueName, "Sermon Wash")
  end)

  t.it("does not change anything when nothing changed", function()
    local st = state.new()
    state.update(st, { snap("Main", "1"), snap("Haze", "4") })
    state.update(st, { snap("Main", "1"), snap("Haze", "4") })
    t.assert_equal(st.displayed.sequence, "Main")
    t.assert_equal(st.displayed.cueNumber, "1")
  end)

  t.it("treats a re-activated sequence at the same cue as a fresh fire", function()
    local st = state.new()
    state.update(st, { snap("Main", "1"), snap("Haze", "9") })
    state.update(st, { snap("Main", "1") })                     -- Haze goes off
    t.assert_equal(st.displayed.sequence, "Main")
    state.update(st, { snap("Main", "1"), snap("Haze", "9") })   -- Haze fires again
    t.assert_equal(st.displayed.sequence, "Haze")
    t.assert_equal(st.displayed.cueNumber, "9")
  end)

  t.it("tracks the active sequence list in console order", function()
    local st = state.new()
    state.update(st, { snap("Main", "1"), snap("Haze", "2") })
    t.assert_equal(#st.activeSequences, 2)
    t.assert_equal(st.activeSequences[1], "Main")
    t.assert_equal(st.activeSequences[2], "Haze")
    state.update(st, {})
    t.assert_equal(#st.activeSequences, 0)
  end)
end)

t.describe("state.payload", function()
  t.it("produces the wire shape", function()
    local st = state.new()
    state.update(st, { snap("Main", "12.5", "Sermon Wash") })
    local p = state.payload(st, "2.0.0", 91234.5)
    t.assert_equal(p.sequence, "Main")
    t.assert_equal(p.cueNumber, "12.5")
    t.assert_equal(p.cueName, "Sermon Wash")
    t.assert_equal(p.version, "2.0.0")
    t.assert_equal(p.updatedAt, 91234.5)
    t.assert_equal(#p.activeSequences, 1)
  end)
end)

-- ---------------------------------------------------------------------------
-- Grid: fixed slots, fire times, timecode
-- ---------------------------------------------------------------------------
local json = require("json")

local function gsnap(number, cue, fade, name)
  return { name = name or ("Seq " .. number), number = number, cueNumber = tostring(cue),
           cueName = "Cue " .. tostring(cue), cueKey = cue * 1000, fade = fade }
end

-- Slot contents as a compact string of sequence numbers, "-" for an empty slot.
local function slots_of(st, now)
  local p = state.payload(st, "t", now or 0)
  local out = {}
  for i = 1, #p.grid do
    out[i] = p.grid[i] == json.null and "-" or tostring(p.grid[i].number)
  end
  return table.concat(out, " ")
end

t.describe("state grid slots", function()
  t.it("always reports eight slots, all empty at first", function()
    local st = state.new()
    t.assert_equal(slots_of(st), "- - - - - - - -")
  end)

  t.it("shows only sequences inside the range, ends included", function()
    local st = state.new()
    state.update(st, { gsnap(0, 1), gsnap(1, 1), gsnap(89, 1), gsnap(90, 1), gsnap(171, 1) }, 10)
    t.assert_equal(slots_of(st), "1 89 - - - - - -")
  end)

  t.it("honours a configured range and slot count", function()
    local st = state.new({ grid_from = 50, grid_to = 60, slots = 4 })
    state.update(st, { gsnap(49, 1), gsnap(55, 1), gsnap(61, 1) }, 10)
    t.assert_equal(slots_of(st), "55 - - -")
  end)

  t.it("places same-scan arrivals by sequence number, whatever the console order", function()
    local st = state.new()
    state.update(st, { gsnap(73, 1), gsnap(55, 1) }, 10)
    t.assert_equal(slots_of(st), "55 73 - - - - - -")
  end)

  t.it("gives a later arrival the lowest empty slot and moves nobody", function()
    local st = state.new()
    state.update(st, { gsnap(55, 1), gsnap(73, 1) }, 10)
    state.update(st, { gsnap(55, 1), gsnap(73, 1), gsnap(39, 1) }, 11)
    t.assert_equal(slots_of(st), "55 73 39 - - - - -")
  end)

  t.it("leaves a gap when a sequence stops", function()
    local st = state.new()
    state.update(st, { gsnap(55, 1), gsnap(73, 1) }, 9)
    state.update(st, { gsnap(55, 1), gsnap(73, 1), gsnap(39, 1) }, 10)
    state.update(st, { gsnap(73, 1), gsnap(39, 1) }, 11)
    t.assert_equal(slots_of(st), "- 73 39 - - - - -")
  end)

  t.it("returns a sequence to its old slot when that slot is empty", function()
    local st = state.new()
    state.update(st, { gsnap(55, 1), gsnap(73, 1) }, 9)
    state.update(st, { gsnap(55, 1), gsnap(73, 1), gsnap(39, 1) }, 10) -- 39 in slot 3
    state.update(st, { gsnap(55, 1), gsnap(73, 1) }, 11)             -- 39 stops (slot 3)
    state.update(st, { gsnap(55, 1) }, 12)                            -- 73 stops (slot 2)
    state.update(st, { gsnap(55, 1), gsnap(39, 1) }, 13)              -- 39 returns
    t.assert_equal(slots_of(st), "55 - 39 - - - - -")
  end)

  t.it("gives a returning sequence the lowest empty slot when its old one is taken", function()
    local st = state.new()
    state.update(st, { gsnap(55, 1) }, 10)                            -- 55 in slot 1
    state.update(st, {}, 11)
    state.update(st, { gsnap(73, 1) }, 12)                            -- 73 takes slot 1
    state.update(st, { gsnap(73, 1), gsnap(55, 1) }, 13)
    t.assert_equal(slots_of(st), "73 55 - - - - - -")
  end)

  t.it("makes a ninth sequence wait, then places it when a slot frees", function()
    local st = state.new()
    local nine = {}
    for n = 1, 9 do nine[n] = gsnap(n, 1) end
    state.update(st, nine, 10)
    t.assert_equal(slots_of(st), "1 2 3 4 5 6 7 8")
    table.remove(nine, 3)                                             -- sequence 3 stops
    state.update(st, nine, 11)
    t.assert_equal(slots_of(st), "1 2 9 4 5 6 7 8")
  end)

  t.it("never moves the others while one sequence starts and stops fifty times", function()
    local st = state.new()
    state.update(st, { gsnap(55, 1), gsnap(37, 1), gsnap(73, 1) }, 0)
    t.assert_equal(slots_of(st), "37 55 73 - - - - -")
    for i = 1, 50 do
      state.update(st, { gsnap(55, 1), gsnap(73, 1) }, i)
      t.assert_equal(slots_of(st), "- 55 73 - - - - -")
      state.update(st, { gsnap(55, 1), gsnap(37, 1), gsnap(73, 1) }, i + 0.5)
      t.assert_equal(slots_of(st), "37 55 73 - - - - -")
    end
  end)

  t.it("ignores snapshots without a number and keeps the single-cue fields", function()
    local st = state.new()
    state.update(st, { snap("Main", "1") })
    t.assert_equal(slots_of(st), "- - - - - - - -")
    t.assert_equal(st.displayed.sequence, "Main")
  end)
end)

t.describe("state grid entries", function()
  local function entry(st, slot, now) return state.payload(st, "t", now).grid[slot] end

  t.it("carries number, name, cue and fade", function()
    local st = state.new()
    state.update(st, { gsnap(55, 3, 2, "He Is") }, 10)
    local e = entry(st, 1, 10)
    t.assert_equal(e.number, 55)
    t.assert_equal(e.name, "He Is")
    t.assert_equal(e.cueNumber, "3")
    t.assert_equal(e.cueName, "Cue 3")
    t.assert_equal(e.fade, 2)
  end)

  t.it("writes an unknown fade as null and keeps a fade of zero", function()
    local st = state.new()
    state.update(st, { gsnap(55, 1, nil), gsnap(56, 1, 0), gsnap(57, 1, "CueTiming") }, 10)
    t.assert_equal(entry(st, 1, 10).fade, json.null)
    t.assert_equal(entry(st, 2, 10).fade, 0)
    t.assert_equal(entry(st, 3, 10).fade, json.null)
  end)

  t.it("does not invent a countdown for sequences running at the first scan", function()
    local st = state.new()
    state.update(st, { gsnap(55, 1, 4) }, 10)
    t.assert_equal(entry(st, 1, 12).firedAgo, json.null)
  end)

  t.it("counts from the scan in which a sequence starts", function()
    local st = state.new()
    state.update(st, {}, 10)
    state.update(st, { gsnap(55, 1, 4) }, 20)
    t.assert_equal(entry(st, 1, 20).firedAgo, 0)
    t.assert_equal(entry(st, 1, 21.5).firedAgo, 1.5)
  end)

  t.it("restarts the count on a cue change and not otherwise", function()
    local st = state.new()
    state.update(st, {}, 10)
    state.update(st, { gsnap(55, 1, 4) }, 20)
    state.update(st, { gsnap(55, 1, 4) }, 21)
    t.assert_equal(entry(st, 1, 21).firedAgo, 1)
    state.update(st, { gsnap(55, 2, 2) }, 22)
    t.assert_equal(entry(st, 1, 22.25).firedAgo, 0.25)
    t.assert_equal(entry(st, 1, 22.25).cueNumber, "2")
  end)

  t.it("counts again when a stopped sequence comes back on the same cue", function()
    local st = state.new()
    state.update(st, { gsnap(37, 1, 0) }, 10)
    state.update(st, {}, 11)
    state.update(st, { gsnap(37, 1, 0) }, 12)
    t.assert_equal(entry(st, 1, 12.5).firedAgo, 0.5)
  end)

  t.it("never reports a negative age", function()
    local st = state.new()
    state.update(st, {}, 10)
    state.update(st, { gsnap(55, 1, 4) }, 20)
    t.assert_equal(entry(st, 1, 19).firedAgo, 0)
  end)
end)

t.describe("state timecode", function()
  local function tc(st, now) return state.payload(st, "t", now).timecode end

  t.it("is an empty list before any sample", function()
    t.assert_equal(#tc(state.new(), 0), 0)
  end)

  t.it("reports slots in sample order with their seconds", function()
    local st = state.new()
    state.update_timecode(st, { { slot = 1, seconds = 7204.5 }, { slot = 2, seconds = 0 } }, 10)
    local out = tc(st, 10)
    t.assert_equal(#out, 2)
    t.assert_equal(out[1].slot, 1)
    t.assert_equal(out[1].seconds, 7204.5)
    t.assert_equal(out[2].slot, 2)
    t.assert_equal(out[2].seconds, 0)
  end)

  t.it("is running while the value keeps changing", function()
    local st = state.new()
    state.update_timecode(st, { { slot = 1, seconds = 100.00 } }, 10.00)
    t.assert_equal(tc(st, 10.00)[1].running, false)
    state.update_timecode(st, { { slot = 1, seconds = 100.05 } }, 10.05)
    t.assert_equal(tc(st, 10.05)[1].running, true)
  end)

  t.it("does not flicker to stopped on one repeated sample", function()
    local st = state.new()
    state.update_timecode(st, { { slot = 1, seconds = 100.00 } }, 10.00)
    state.update_timecode(st, { { slot = 1, seconds = 100.05 } }, 10.05)
    state.update_timecode(st, { { slot = 1, seconds = 100.05 } }, 10.10)
    t.assert_equal(tc(st, 10.10)[1].running, true)
  end)

  t.it("is stopped once the value has not changed for a quarter second", function()
    local st = state.new()
    state.update_timecode(st, { { slot = 1, seconds = 100.00 } }, 10.00)
    state.update_timecode(st, { { slot = 1, seconds = 100.05 } }, 10.05)
    for i = 1, 6 do state.update_timecode(st, { { slot = 1, seconds = 100.05 } }, 10.05 + i * 0.05) end
    local out = tc(st, 10.35)
    t.assert_equal(out[1].running, false)
    t.assert_equal(out[1].seconds, 100.05)
  end)

  t.it("writes an unreadable slot as null and stopped", function()
    local st = state.new()
    state.update_timecode(st, { { slot = 1, seconds = 100 } }, 10.00)
    state.update_timecode(st, { { slot = 1, seconds = 100.05 } }, 10.05)
    state.update_timecode(st, { { slot = 1, seconds = nil } }, 10.10)
    local out = tc(st, 10.10)
    t.assert_equal(out[1].seconds, json.null)
    t.assert_equal(out[1].running, false)
  end)
end)

t.describe("state.payload with the grid", function()
  t.it("keeps every old field next to the new ones", function()
    local st = state.new()
    state.update(st, { gsnap(55, 12.5, 2, "Main") }, 5)
    local p = state.payload(st, "2.0.0", 91234.5)
    t.assert_equal(p.sequence, "Main")
    t.assert_equal(p.cueNumber, "12.5")
    t.assert_equal(p.cueName, "Cue 12.5")
    t.assert_equal(p.version, "2.0.0")
    t.assert_equal(p.updatedAt, 91234.5)
    t.assert_equal(#p.activeSequences, 1)
    t.assert_equal(#p.grid, 8)
    t.assert_equal(#p.timecode, 0)
  end)

  t.it("encodes to JSON with nulls for the empty slots", function()
    local st = state.new({ slots = 2 })
    state.update(st, {}, 1)
    state.update(st, { gsnap(55, 1, 2, "He Is") }, 2)
    local body = json.encode(state.payload(st, "t", 2).grid)
    t.assert_equal(body,
      '[{"cueName":"Cue 1","cueNumber":"1","fade":2,"firedAgo":0,"name":"He Is","number":55},null]')
  end)
end)
