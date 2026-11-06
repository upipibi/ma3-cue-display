-- Fake grandMA3 console, just real enough to run the shipped bundle unmodified.
--
-- Provides the four MA3 globals main.lua uses, a DataPool() whose sequences
-- advance cues on a timer, and the piece that actually matters: a scheduler that
-- resumes the plugin coroutine after each coroutine.yield(seconds), which is how
-- MA3 drives a long-lived plugin.

local socket = require("socket")

local BUNDLE = assert(arg[1], "usage: fake-console.lua <bundle.lua> [seconds] [grid]")
local RUN_FOR = tonumber(arg[2]) or 12
-- "grid" adds what the /grid view needs: numbered sequences that start, stop and
-- change cue, cues with fades, and two timecode slots. Without it the scenario
-- is the original single-cue one, unchanged.
local SCENARIO = arg[3] or "default"

---------------------------------------------------------------------------
-- MA3 globals
---------------------------------------------------------------------------
local globalvars = {}

function Printf(fmt, ...)
  io.write("[console] ", string.format(fmt, ...), "\n")
  io.flush()
end

function GlobalVars() return globalvars end

function GetVar(store, name) return store[name] end

function SetVar(store, name, value) store[name] = value end

---------------------------------------------------------------------------
-- Fake object model
---------------------------------------------------------------------------
-- Two stacks. Main advances every 2s. Haze sits still, so it should never steal
-- the display after its first appearance. Cue numbers are MA3-scaled (x1000).
local sequences = {
  {
    _name = "Main",
    _cues = { { 1000, "House Up" }, { 2000, "Preshow" }, { 12500, "Sermon Wash" },
              { 13000, "Response" } },
    _i = 1,
    _playing = true,
  },
  {
    _name = "Haze",
    _cues = { { 5000, "Haze Idle" } },
    _i = 1,
    _playing = true,
  },
  {
    _name = "Blackout",
    _cues = { { 99000, "BO" } },
    _i = 1,
    _playing = false,   -- never playing; must never appear in state
  },
}

-- Grid scenario. Cues are { number x1000, name, fade }. _every is how often the
-- stack advances; _toggle is how often it switches on and off.
local grid_started = socket.gettime()
if SCENARIO == "grid" then
  sequences = {
    { _name = "He Is", No = 55, _playing = true, _i = 1, _every = 3,
      _cues = { { 1000, "Start - He Is", 4 }, { 2000, "Verse 1", 2 }, { 3000, "Pre Chorus", 2 },
                { 4000, "Chorus / Hits", 0 }, { 4200, "Hit 2", 0 }, { 5000, "Verse 2", 4 },
                { 6000, "Bridge", 8 }, { 7000, "Chorus (Big)", 2 }, { 8000, "Ending", 15 } } },
    { _name = "He Is (key)", No = 73, _playing = true, _i = 1, _every = 5,
      _cues = { { 1000, "(KEY) Start - He Is", 2 }, { 2000, "Lead Vox", 1 }, { 3000, "Duet", "CueTiming" },
                { 4000, "All Vox with a very long cue name that has to be cut off", 4 } } },
    { _name = "Ladders", No = 39, _playing = false, _i = 1, _every = 4, _toggle = 7,
      _cues = { { 1000, "Chase Up", 2 }, { 2000, "Sparkle", 4 } } },
    { _name = "R1 Strobe", No = 37, _playing = false, _i = 1, _toggle = 4,
      _cues = { { 1000, "Strobe On", 0 } } },
    { _name = "Main House", No = 171, _playing = true, _i = 1,   -- out of the grid range
      _cues = { { 1000, "House Half", 3 } } },
  }
  for _, s in ipairs(sequences) do s._last_advance, s._last_toggle = grid_started, grid_started end

  -- Slot 1 rolls from 2h00m04:14 and jumps back to 1h00m00 once, 40 s in (a
  -- locate). Slot 2 sits at zero.
  local function slot(n)
    return {
      Get = function(_, prop)
        if prop ~= "TIME" then return nil end
        if n ~= 1 then return 0 end
        local elapsed = socket.gettime() - grid_started
        local seconds = elapsed < 40 and (7204 + 14 / 30 + elapsed) or (3600 + elapsed - 40)
        return math.floor(seconds * 16777216)
      end,
    }
  end
  local slots = { slot(1), slot(2) }
  function ObjectList(address)
    local n = tonumber(tostring(address):match("^TimecodeSlot (%d+)$"))
    return { slots[n] }
  end
end

for _, s in ipairs(sequences) do
  s.name = s._name
  s.HasActivePlayback = function(self) return self._playing end
  s.CurrentChild = function(self)
    local c = self._cues[self._i]
    if not c then return nil end
    local part = { Get = function(_, prop) if prop == "CUEINFADE" then return c[3] end end }
    return { No = c[1], name = c[2], Ptr = function(_, i) if i == 1 then return part end end }
  end
end

function DataPool()
  return { Sequences = { Children = function() return sequences end } }
end

---------------------------------------------------------------------------
-- A console is never a clean Lua state. package.loaded is shared by every plugin
-- and keeps whatever was loaded earlier in the session: the previous version of
-- this plugin, another plugin's modules, and the console's own "json". A bundle
-- that resolves its modules through package.* gets those instead of its own.
-- (2.1.0's first build did, on a grandMA3 light: it ran 2.0's state module, found
-- no update_timecode in it, failed on every tick and shut itself down.)
-- Stale stand-ins are planted here so that mistake fails on this Mac too.
---------------------------------------------------------------------------
for _, name in ipairs({ "json", "state", "http", "server", "ma3", "display_html" }) do
  local stale = { stale_module = name, encode = function() return "{}" end,
                  new = function() return {} end, tick = function() return {} end }
  package.loaded[name] = name == "display_html" and "<html>stale page from an older version</html>" or stale
  package.preload[name] = function() return stale end
end

---------------------------------------------------------------------------
-- Load the shipped bundle and drive it like MA3's plugin scheduler does
---------------------------------------------------------------------------
local entry = assert(loadfile(BUNDLE))()
assert(type(entry) == "function", "bundle did not return an entry function")

local co = coroutine.create(entry)
local started = socket.gettime()
local last_advance = started
local resumes = 0

io.write("[harness] driving the real bundle for ", RUN_FOR, "s\n")

while coroutine.status(co) ~= "dead" do
  local ok, yielded = coroutine.resume(co)
  if not ok then
    io.write("[harness] PLUGIN ERROR: ", tostring(yielded), "\n")
    os.exit(1)
  end
  resumes = resumes + 1

  local now = socket.gettime()

  if SCENARIO == "grid" then
    for _, s in ipairs(sequences) do
      if s._toggle and now - s._last_toggle >= s._toggle then
        s._playing = not s._playing
        s._last_toggle = now
        if s._playing then s._i = 1 end
      end
      if s._every and s._playing and now - s._last_advance >= s._every then
        s._i = s._i % #s._cues + 1
        s._last_advance = now
      end
    end
  -- Advance the Main stack every 2s so the display has something to follow.
  elseif now - last_advance >= 2.0 then
    local main = sequences[1]
    main._i = main._i + 1
    if main._i > #main._cues then
      -- Stack runs out and stops playing: the display must hold its last cue.
      main._i = #main._cues
      main._playing = false
      io.write("[harness] Main stack finished and stopped playing\n")
    else
      io.write("[harness] Main advanced to cue ", main._cues[main._i][1] / 1000, "\n")
    end
    last_advance = now
  end

  if now - started >= RUN_FOR then
    io.write("[harness] time is up, asking the plugin to stop\n")
    globalvars["MA3CueDisplayRunning"] = 0
  end

  -- This is the scheduler contract: yield(seconds) means resume me later.
  if coroutine.status(co) ~= "dead" then
    socket.sleep(tonumber(yielded) or 0.05)
  end
end

io.write("[harness] plugin coroutine exited cleanly after ", resumes, " resumes\n")
io.write("[harness] run flag left at: ",
  tostring(globalvars["MA3CueDisplayRunning"]), "\n")
