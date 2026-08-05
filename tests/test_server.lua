local t = require("runner")
local server = require("server")

local CTX = { html = "<html>p</html>", state_json = '{"a":1}', version = "2.0.0" }

-- A fake client that hands over its request in chunks, one per receive() call,
-- to exercise partial reads across ticks.
local function fake_client(chunks)
  return {
    sent = {},
    closed = false,
    _chunks = chunks,
    _i = 0,
    settimeout = function() end,
    receive = function(self)
      self._i = self._i + 1
      local c = self._chunks[self._i]
      if c == nil then return nil, "timeout", "" end
      if c.line then return c.line end
      return nil, "timeout", c.partial
    end,
    send = function(self, data)
      self.sent[#self.sent + 1] = data
      return #data
    end,
    close = function(self) self.closed = true end,
  }
end

-- Copies the queue: accept() drains it via table.remove, and without a copy the
-- caller's own list would be emptied out from under its later assertions.
local function fake_listener(queue)
  local own = {}
  for i, c in ipairs(queue) do own[i] = c end
  return {
    _queue = own,
    settimeout = function() end,
    accept = function(self) return table.remove(self._queue, 1) end,
    close = function(self) self.closed = true end,
  }
end

t.describe("server.tick", function()
  t.it("serves a request that arrives complete on the first poll", function()
    local c = fake_client({ { line = "GET /health HTTP/1.1" } })
    local sv = server.new(fake_listener({ c }))
    local r1 = server.tick(sv, CTX, 0)
    t.assert_equal(r1.accepted, 1)
    -- Accepted this tick; the read pass runs in the same tick.
    t.assert_equal(r1.served, 1)
    t.assert_equal(c.closed, true)
    t.assert_match(c.sent[1], "ok 2.0.0")
  end)

  t.it("accumulates a partial request across ticks", function()
    local c = fake_client({
      { partial = "GET /hea" },
      { line = "GET /health HTTP/1.1" },
    })
    local sv = server.new(fake_listener({ c }))
    local r1 = server.tick(sv, CTX, 0)
    t.assert_equal(r1.served, 0)
    t.assert_equal(c.closed, false)
    local r2 = server.tick(sv, CTX, 0.05)
    t.assert_equal(r2.served, 1)
    t.assert_match(c.sent[1], "ok 2.0.0")
  end)

  t.it("never blocks: a silent client is left pending, not waited on", function()
    local c = fake_client({})
    local sv = server.new(fake_listener({ c }))
    server.tick(sv, CTX, 0)
    t.assert_equal(#sv.pending, 1)
    t.assert_equal(c.closed, false)
  end)

  t.it("drops a client that ages past client_timeout", function()
    local c = fake_client({})
    local sv = server.new(fake_listener({ c }), { client_timeout = 2.0 })
    server.tick(sv, CTX, 0)
    local r = server.tick(sv, CTX, 2.5)
    t.assert_equal(r.dropped, 1)
    t.assert_equal(c.closed, true)
    t.assert_equal(#sv.pending, 0)
  end)

  t.it("caps accepts per tick", function()
    local clients = {}
    for i = 1, 10 do clients[i] = fake_client({}) end
    local sv = server.new(fake_listener(clients), { max_accepts_per_tick = 4 })
    local r = server.tick(sv, CTX, 0)
    t.assert_equal(r.accepted, 4)
  end)

  t.it("rejects new clients with 503 when the pending queue is full", function()
    local clients = {}
    for i = 1, 6 do clients[i] = fake_client({}) end
    local sv = server.new(fake_listener(clients),
      { max_accepts_per_tick = 6, max_pending = 3 })
    server.tick(sv, CTX, 0)
    t.assert_equal(#sv.pending, 3)
    t.assert_equal(clients[4].closed, true)
    t.assert_match(clients[4].sent[1], "503 Service Unavailable")
  end)

  t.it("400s an oversized request line and closes it", function()
    local c = fake_client({ { partial = string.rep("x", 3000) } })
    local sv = server.new(fake_listener({ c }), { max_request_bytes = 2048 })
    local r = server.tick(sv, CTX, 0)
    t.assert_equal(r.dropped, 1)
    t.assert_equal(c.closed, true)
    t.assert_match(c.sent[1], "400 Bad Request")
  end)

  t.it("400s an unparseable request line", function()
    local c = fake_client({ { line = "hello there" } })
    local sv = server.new(fake_listener({ c }))
    server.tick(sv, CTX, 0)
    t.assert_match(c.sent[1], "400 Bad Request")
    t.assert_equal(c.closed, true)
  end)

  t.it("survives a client whose send throws", function()
    local c = fake_client({ { line = "GET / HTTP/1.1" } })
    c.send = function() error("broken pipe") end
    local sv = server.new(fake_listener({ c }))
    local r = server.tick(sv, CTX, 0)
    t.assert_equal(r.served, 1)
    t.assert_equal(c.closed, true)
  end)

  t.it("survives a client whose receive throws", function()
    local c = fake_client({})
    c.receive = function() error("connection reset") end
    local sv = server.new(fake_listener({ c }))
    local r = server.tick(sv, CTX, 0)
    t.assert_equal(r.dropped, 1)
    t.assert_equal(c.closed, true)
    t.assert_equal(#sv.pending, 0)
  end)

  t.it("survives a listener whose accept throws", function()
    local l = fake_listener({})
    l.accept = function() error("socket gone") end
    local sv = server.new(l)
    local r = server.tick(sv, CTX, 0)
    t.assert_equal(r.accepted, 0)
  end)

  t.it("does nothing when there is no traffic", function()
    local sv = server.new(fake_listener({}))
    local r = server.tick(sv, CTX, 0)
    t.assert_equal(r.accepted, 0)
    t.assert_equal(r.served, 0)
    t.assert_equal(r.dropped, 0)
  end)

  t.it("serves several clients in one tick", function()
    local a = fake_client({ { line = "GET /health HTTP/1.1" } })
    local b = fake_client({ { line = "GET /api/state HTTP/1.1" } })
    local sv = server.new(fake_listener({ a, b }))
    local r = server.tick(sv, CTX, 0)
    t.assert_equal(r.served, 2)
    t.assert_match(a.sent[1], "ok 2.0.0")
    t.assert_match(b.sent[1], '{"a":1}')
  end)
end)

t.describe("server.close", function()
  t.it("closes the listener and every pending client", function()
    local c = fake_client({})
    local l = fake_listener({ c })
    local sv = server.new(l)
    server.tick(sv, CTX, 0)
    t.assert_equal(#sv.pending, 1)
    server.close(sv)
    t.assert_equal(c.closed, true)
    t.assert_equal(l.closed, true)
    t.assert_equal(#sv.pending, 0)
  end)
end)
