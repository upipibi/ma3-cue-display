-- Non-blocking HTTP connection state machine. Socket-agnostic: it only needs
-- objects with settimeout/accept/receive/send/close, so tests inject fakes.
--
-- With settimeout(0) the request bytes have usually not arrived in the same tick
-- as the accept, so accepted clients go on a pending queue and get re-polled on
-- later ticks. The alternative -- giving each client a small blocking timeout --
-- would stall the console's UI thread, which this design forbids outright.
local http = require("http")

local M = {}

local DEFAULTS = {
  max_accepts_per_tick = 4,
  max_pending = 8,
  client_timeout = 2.0,
  max_request_bytes = 2048,
}

function M.new(listener, opts)
  opts = opts or {}
  local o = {}
  for k, v in pairs(DEFAULTS) do
    o[k] = opts[k] == nil and v or opts[k]
  end
  listener:settimeout(0)
  return { listener = listener, opts = o, pending = {} }
end

local function finish(entry, response)
  if response then pcall(function() entry.sock:send(response) end) end
  pcall(function() entry.sock:close() end)
end

local function accept_pass(sv, stats, now)
  for _ = 1, sv.opts.max_accepts_per_tick do
    local ok, client = pcall(function() return sv.listener:accept() end)
    if not ok or not client then return end

    pcall(function() client:settimeout(0) end)

    if #sv.pending >= sv.opts.max_pending then
      -- Shed load rather than grow an unbounded queue inside the console.
      finish({ sock = client },
        http.response(503, "text/plain; charset=utf-8", "busy"))
    else
      sv.pending[#sv.pending + 1] = {
        sock = client,
        buf = "",
        deadline = now + sv.opts.client_timeout,
      }
      stats.accepted = stats.accepted + 1
    end
  end
end

local function read_pass(sv, ctx, stats, now)
  local keep = {}
  for _, entry in ipairs(sv.pending) do
    local line, partial
    local ok = pcall(function()
      -- Own locals here: `_` outside is the loop's control variable, which Lua 5.5
      -- (the console's version on 2.5) makes read-only. Assigning to it is a syntax error.
      local received, _, rest = entry.sock:receive("*l")
      line, partial = received, rest
    end)

    if not ok then
      finish(entry, nil)
      stats.dropped = stats.dropped + 1
    elseif line then
      local req = http.parse_request(line)
      if req then
        finish(entry, http.route(req, ctx))
      else
        finish(entry, http.response(400, "text/plain; charset=utf-8", "bad request"))
      end
      stats.served = stats.served + 1
    else
      -- LuaSocket hands back already-consumed bytes in the third return value.
      -- They are lost unless accumulated here, before the size check.
      entry.buf = entry.buf .. (partial or "")
      if #entry.buf > sv.opts.max_request_bytes then
        finish(entry, http.response(400, "text/plain; charset=utf-8", "request too large"))
        stats.dropped = stats.dropped + 1
      elseif now >= entry.deadline then
        finish(entry, nil)
        stats.dropped = stats.dropped + 1
      else
        keep[#keep + 1] = entry
      end
    end
  end
  sv.pending = keep
end

function M.tick(sv, ctx, now)
  local stats = { accepted = 0, served = 0, dropped = 0 }
  accept_pass(sv, stats, now)
  read_pass(sv, ctx, stats, now)
  return stats
end

function M.close(sv)
  for _, entry in ipairs(sv.pending) do
    pcall(function() entry.sock:close() end)
  end
  sv.pending = {}
  pcall(function() sv.listener:close() end)
end

return M
