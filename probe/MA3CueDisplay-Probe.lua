-- MA3CueDisplay-Probe — throwaway feasibility check. Not part of the shipped plugin.
--
-- Prints answers to the questions that decide whether a console-hosted HTTP
-- server is possible at all. Safe: binds a port only long enough to prove it
-- can, then closes it. Never loops indefinitely.
--
-- Run it with at least one cue stack playing, or the sequence checks have
-- nothing to report.

-- Printf takes a format string, so a value containing a % would break it.
-- Always pass the finished text through %s.
local function line(fmt, ...)
  Printf("%s", "PROBE | " .. string.format(fmt, ...))
end

local function try(fn)
  local ok, value = pcall(fn)
  if ok then return value end
  return nil, value
end

local function probe_version()
  local v, err = try(function() return Version() end)
  if v ~= nil then
    line("ma3 version: %s", tostring(v))
  else
    line("ma3 version: Version() unavailable (%s)", tostring(err))
  end
end

local function probe_socket()
  local ok, sock = pcall(require, "socket")
  if not ok then
    line("socket: FAIL -- require('socket') errored: %s", tostring(sock))
    line("socket: THIS IS THE HARD BLOCKER. Stop here and report it.")
    return nil
  end
  line("socket: OK -- _VERSION=%s", tostring(sock._VERSION))

  local t = try(function() return sock.gettime() end)
  if t then
    line("socket.gettime: OK (%.3f)", t)
  else
    line("socket.gettime: MISSING -- client timeouts will fall back to os.time()")
  end
  return sock
end

local function probe_bind(sock, port)
  if not sock then return end
  local server, err = sock.bind("*", port)
  if not server then
    line("bind %d: FAIL -- %s", port, tostring(err))
    return
  end
  line("bind %d: OK", port)

  local name = try(function()
    local ip, p = server:getsockname()
    return tostring(ip) .. ":" .. tostring(p)
  end)
  if name then line("bind %d: sockname %s", port, name) end

  server:close()
  line("bind %d: closed cleanly", port)
end

local function probe_sequences()
  local seqs, err = try(function() return DataPool().Sequences:Children() end)
  if type(seqs) ~= "table" then
    line("sequences: FAIL -- %s", tostring(err))
    return
  end
  line("sequences: %d total in show file", #seqs)

  -- CPU time is the right clock here: this measures how much of the console's
  -- UI thread a full sweep consumes, which is exactly the budget question.
  local t0 = os.clock()
  local active = 0
  for _, seq in ipairs(seqs) do
    local playing = try(function() return seq:HasActivePlayback() end)
    if playing then active = active + 1 end
  end
  local elapsed_ms = (os.clock() - t0) * 1000

  line("scan: %d active, full HasActivePlayback sweep took %.2f ms", active, elapsed_ms)
  line("scan: at 5 Hz that is %.2f%% of the UI thread", (elapsed_ms * 5) / 10)
  if elapsed_ms > 20 then
    line("scan: WARNING -- over 20 ms per sweep. Report this; the cue poll rate")
    line("scan:          should drop below 5 Hz before shipping.")
  end

  for _, seq in ipairs(seqs) do
    local playing = try(function() return seq:HasActivePlayback() end)
    if playing then
      local seqname = tostring(try(function() return seq.name end))
      local cue = try(function() return seq:CurrentChild() end)
      if cue then
        local no = try(function() return cue.No end)
        local nm = try(function() return cue.name end)
        local idx = try(function() return cue.index end)
        line("active: seq.name=%s  cue.No=%s  cue.name=%s  cue.index=%s",
          seqname, tostring(no), tostring(nm), tostring(idx))
      else
        line("active: seq.name=%s  CurrentChild() returned nothing", seqname)
      end
    end
  end
end

-- The toggle depends entirely on this round-tripping. If GlobalVars does not
-- persist a value, the plugin can start but never be stopped from the button.
local function probe_globalvars()
  local ok, err = pcall(function()
    SetVar(GlobalVars(), "MA3CueDisplayProbe", 1)
  end)
  if not ok then
    line("globalvars: FAIL on SetVar -- %s", tostring(err))
    return
  end

  local got = select(2, pcall(function()
    return GetVar(GlobalVars(), "MA3CueDisplayProbe")
  end))
  line("globalvars: SetVar/GetVar round-trip returned %s (want 1)", tostring(got))

  if tonumber(got) ~= 1 then
    line("globalvars: WARNING -- the toggle will not be able to stop the plugin")
  end

  pcall(function() SetVar(GlobalVars(), "MA3CueDisplayProbe", 0) end)
end

local function probe_yield(sock)
  -- os.clock() measures CPU time, which stays near zero while yielding, so it
  -- cannot tell us whether the engine actually resumed us on schedule. Use a
  -- wall clock instead.
  local wall = (sock and sock.gettime) or function() return os.time() end
  local t0 = wall()
  local iterations = 200
  for _ = 1, iterations do
    coroutine.yield(0.01)
  end
  local elapsed = wall() - t0
  line("yield: survived %d iterations of coroutine.yield(0.01)", iterations)
  line("yield: %.2f s wall elapsed (expect around %.2f s if the engine honors it)",
    elapsed, iterations * 0.01)
end

return function()
  line("==== MA3 Cue Display feasibility probe ====")
  probe_version()
  local sock = probe_socket()
  probe_bind(sock, 8090)
  probe_globalvars()
  probe_sequences()
  probe_yield(sock)
  line("==== probe complete ====")
end
