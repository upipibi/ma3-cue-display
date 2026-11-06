-- Plugin entry point. Everything MA3-specific that is not object-model access
-- lives here: Printf, GlobalVars, and the coroutine.yield tick loop.
--
-- MA3 plugins run as coroutines sharing the console's UI thread. Every socket
-- call is non-blocking and every tick yields, because a blocking call here
-- freezes the desk mid-service.
--
-- The plugin is a TOGGLE, not a Start/Stop pair. A grandMA3 ComponentLua points
-- at its own FileName, so two components would mean shipping two .lua files and
-- building two macros. One toggling component means one file and one button:
-- press to start, press again to stop. Pressing while running spawns a second
-- coroutine that flips the shared flag and returns immediately; the original
-- loop sees it and shuts down on its next tick.

local json = require("json")
local state = require("state")
local server = require("server")
local ma3 = require("ma3")
local display_html = require("display_html")

local CONFIG = {
  port = 8090,             -- never 8080; that is MA3's own Web Remote
  tick_seconds = 0.05,     -- 20 Hz socket service
  cue_scan_every = 4,      -- every 4th tick => ~5 Hz cue polling
  max_consecutive_errors = 10,
  -- The grid view (/grid) shows running sequences numbered grid_from..grid_to:
  -- songs, their (key) twins and the song effect sequences. House looks,
  -- Resolume control and helpers live above that range.
  grid_from = 1,
  grid_to = 89,
  timecode_slots = { 1, 2 },   -- the two clocks on the grid view
  timecode_fps = 30,           -- frames per second of the timecode readout
}

-- Start and stop run as separate coroutines with no shared upvalues, so the
-- run flag has to live somewhere the console owns.
local RUN_VAR = "MA3CueDisplayRunning"

local VERSION = MA3CUEDISPLAY_VERSION or "dev"

-- Printf takes a format string, so text containing a % would break it.
-- Everything goes through %s.
local function log(fmt, ...)
  Printf("%s", "MA3 Cue Display: " .. string.format(fmt, ...))
end

local function running()
  return tonumber(GetVar(GlobalVars(), RUN_VAR) or 0) == 1
end

local function set_running(on)
  SetVar(GlobalVars(), RUN_VAR, on and 1 or 0)
end

-- socket.gettime() is a wall clock. os.clock() measures CPU time, which would
-- make client deadlines meaningless in a loop that spends its life yielding.
local function wall_clock(socket)
  if socket and socket.gettime then return socket.gettime end
  return function() return os.time() end
end

local function report_urls()
  -- The console does not expose its own address through a documented Lua call,
  -- so print the port and let the operator read the IP off the network menu.
  log("serving on port %d -- replace <console-ip> with this station's address", CONFIG.port)
  log("  full screen : http://<console-ip>:%d/", CONFIG.port)
  log("  OBS overlay : http://<console-ip>:%d/?style=overlay", CONFIG.port)
  log("  grid        : http://<console-ip>:%d/grid", CONFIG.port)
  log("  debug       : http://<console-ip>:%d/debug", CONFIG.port)
end

local function run_server()
  local ok, socket = pcall(require, "socket")
  if not ok then
    log("FAILED: LuaSocket is not available on this station (%s)", tostring(socket))
    return
  end

  local listener, err = socket.bind("*", CONFIG.port)
  if not listener then
    log("FAILED: cannot bind port %d (%s)", CONFIG.port, tostring(err))
    log("if that says address in use, an earlier run may still be alive --")
    log("press the plugin twice to clear the flag and start again")
    return
  end

  local clock = wall_clock(socket)
  local sv = server.new(listener, {})
  local st = state.new({ grid_from = CONFIG.grid_from, grid_to = CONFIG.grid_to })
  local adapter = ma3.new()

  local function encode_state()
    local payload = state.payload(st, VERSION, clock())
    payload.timecodeFps = CONFIG.timecode_fps
    return json.encode(payload)
  end

  local ctx = {
    html = display_html,
    state_json = encode_state(),
    version = VERSION,
  }

  set_running(true)
  log("version %s started", VERSION)
  report_urls()

  local errors = 0
  local tick = 0

  while running() do
    local ok_tick, tick_err = pcall(function()
      tick = tick + 1
      -- Timecode is sampled on every tick: it is two property reads, and the
      -- clocks on the grid view are only as close to the console as this is.
      state.update_timecode(st, ma3.timecode(adapter, CONFIG.timecode_slots), clock())
      -- The sequence pool sweep is the expensive read, so it stays at ~5 Hz.
      if tick % CONFIG.cue_scan_every == 0 then
        state.update(st, ma3.snapshot(adapter), clock())
      end
      -- Regenerated unconditionally, not only when something changes: a moving
      -- updatedAt is the heartbeat every viewer uses to tell a live console
      -- from a wedged one.
      ctx.state_json = encode_state()
      server.tick(sv, ctx, clock())
    end)

    if ok_tick then
      errors = 0
    else
      errors = errors + 1
      log("tick error (%d/%d): %s", errors, CONFIG.max_consecutive_errors, tostring(tick_err))
      if errors >= CONFIG.max_consecutive_errors then
        log("too many consecutive errors -- shutting down to protect the console")
        break
      end
    end

    coroutine.yield(CONFIG.tick_seconds)
  end

  server.close(sv)
  set_running(false)
  log("stopped -- port %d released", CONFIG.port)
end

return function()
  if running() then
    set_running(false)
    log("stop requested -- the loop closes its socket on the next tick")
    log("if nothing was actually running, press again to start")
    return
  end
  run_server()
end
