-- Fake grandMA3 console, just real enough to run the shipped bundle unmodified.
--
-- Provides the four MA3 globals main.lua uses, a DataPool() whose sequences
-- advance cues on a timer, and the piece that actually matters: a scheduler that
-- resumes the plugin coroutine after each coroutine.yield(seconds), which is how
-- MA3 drives a long-lived plugin.

local socket = require("socket")

local BUNDLE = assert(arg[1], "usage: console_harness.lua <bundle.lua> [seconds]")
local RUN_FOR = tonumber(arg[2]) or 12

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

for _, s in ipairs(sequences) do
  s.name = s._name
  s.HasActivePlayback = function(self) return self._playing end
  s.CurrentChild = function(self)
    local c = self._cues[self._i]
    if not c then return nil end
    return { No = c[1], name = c[2] }
  end
end

function DataPool()
  return { Sequences = { Children = function() return sequences end } }
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

  -- Advance the Main stack every 2s so the display has something to follow.
  if now - last_advance >= 2.0 then
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
