# MA3 Cue Display — Lua Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the macOS Tauri app with a grandMA3 Lua plugin that reads cue state from the console's own object model and serves a live cue display over HTTP from the console itself.

**Architecture:** One Lua coroutine inside the console runs a 20 Hz tick loop. Every fourth tick it scans active sequences and caches a JSON state string; every tick it services a non-blocking HTTP server. Browsers and OBS poll `/api/state` every 250 ms. Sources are written as small pure modules on the Mac, unit-tested under Lua 5.4, and concatenated into one distributable `.lua` by a build script.

**Tech Stack:** Lua 5.4 · LuaSocket (console-provided) · vanilla HTML/CSS/JS · bash build script · hand-rolled zero-dependency test runner

**Spec:** [2026-08-04-ma3-cue-display-lua-plugin-design.md](../specs/2026-08-04-ma3-cue-display-lua-plugin-design.md)

## Global Constraints

Every task's requirements implicitly include this section.

- **Target runtime is Lua 5.4.4** (grandMA3). Develop and test against `lua@5.4`. The Mac's default `lua` is 5.5.0 — do not use it.
- **No external Lua dependencies.** LuaSocket is the only library, and it comes from the console. No luarocks, no busted, no npm, no Rust.
- **No network assets in HTML.** The console has no internet route. No Google Fonts, no CDN, no external stylesheet or script. System font stack only.
- **All grandMA3 API access is confined to `src/ma3.lua`.** No other file may reference `DataPool`, `Root`, `Printf`, `GetVar`, `SetVar`, `SelectedSequence`, or any MA3 global. `src/main.lua` is the one exception, for `Printf`/`GetVar`/`SetVar`/`coroutine.yield` only.
- **No blocking socket call, ever.** `settimeout(0)` on the listener and on every accepted client. A blocking call freezes the console UI.
- **Default HTTP port 8090**, configurable at the top of `src/main.lua`. Never 8080 (MA3 Web Remote).
- **Version is `2.0.0`**, defined once in `build.sh` and injected. No hardcoded version strings elsewhere.
- **`src/display.html` must never contain the sequence `]==]`** — it is embedded in a Lua `[==[ … ]==]` long string. `build.sh` enforces this.
- **Accent color `#009CDE`** (brand Light Blue). Brand primary `#004C97` fails WCAG AA on black and must not be used on dark backgrounds.
- **Commit messages** end with `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`.

## File Structure

```
src/json.lua        pure JSON encoder (encode only — we never decode)
src/state.lua       pure cue-state tracking + most-recently-fired resolution
src/http.lua        pure HTTP request parsing, routing, response building
src/server.lua      non-blocking accept/read/respond state machine; socket-agnostic
src/ma3.lua         the ONLY module touching the grandMA3 object model
src/display.html    the display page — full-screen, overlay, and debug modes
src/main.lua        plugin entry: bind, tick loop, watchdog, Start/Stop
build.sh            concatenates src/ into dist/MA3CueDisplay.lua
run-tests.sh        runs tests under lua@5.4
tests/runner.lua    ~50-line zero-dependency test runner
tests/all.lua       loads every test file, reports, sets exit code
tests/test_*.lua    one per pure module
probe/              throwaway feasibility plugin (not shipped)
dist/               build output (gitignored except the released artifact)
```

**Refinement over the spec:** the spec listed six source files; this plan adds `src/server.lua`. Splitting the non-blocking connection state machine out of `main.lua` makes it testable with mock sockets, which is where the subtle bugs live (partial reads, client timeouts, pending-queue overflow). `main.lua` shrinks to wiring plus the MA3 loop.

---

### Task 1: Migrate the repo to upipibi

**Files:**
- Modify: git remote configuration only (no file changes)

**Interfaces:**
- Consumes: nothing
- Produces: `origin` pointing at `git@github.com:upipibi/ma3-cue-display.git`, full history preserved

Nothing else can be committed correctly until this is done. The Northwoods repo is **not** deleted here — that is the final task, after a passing desk test.

- [ ] **Step 1: Confirm the working tree is clean enough to migrate**

```bash
cd "/Users/aaronlarson/Documents/VS Code/MA3 Cue Display"
git status --short
git log --oneline -3
```

Expected: the design spec commit is present. Untracked files `.claude-notes`, `CLAUDE.md`, `LAUNCHER_TEMPLATE.md` and the deletion of `.claude/CLAUDE.md` may be present — leave them alone, Task 11 handles them.

- [ ] **Step 2: Create the new public repo under upipibi**

```bash
gh repo create upipibi/ma3-cue-display \
  --public \
  --description "Cue display for grandMA3 — a console-hosted Lua plugin that serves a live cue page to browsers and OBS" \
  --disable-wiki
```

Expected: prints the new repo URL. Do **not** pass `--source` or `--push`; the next step controls the push explicitly.

- [ ] **Step 3: Point origin at the new repo and push all history and tags**

```bash
git remote rename origin northwoods-old
git remote add origin https://github.com/upipibi/ma3-cue-display.git
git push -u origin main
git push origin --tags
```

The old remote is kept as `northwoods-old` so the final task can verify against it before deleting.

- [ ] **Step 4: Verify history and tags actually arrived**

```bash
git ls-remote --heads --tags origin
gh repo view upipibi/ma3-cue-display --json name,visibility,defaultBranchRef
```

Expected: `refs/heads/main` present, every local tag present, visibility `PUBLIC`.

- [ ] **Step 5: Commit nothing, but record the migration in the plan**

No commit — this task changed only git config. Confirm with:

```bash
git remote -v
```

Expected: `origin` → `upipibi/ma3-cue-display`, `northwoods-old` → `NorthwoodsCommunityChurch/Ma3_Cue_Display`.

---

### Task 2: Feasibility probe plugin

**Files:**
- Create: `probe/MA3CueDisplay-Probe.lua`
- Create: `probe/README.md`

**Interfaces:**
- Consumes: nothing
- Produces: answers to the six gate questions in the spec, **plus an authoritative plugin XML file exported from the console** that Task 10 needs as its template

This is a hard gate on Tasks 9, 12, and 13, but not on Tasks 3–8 (pure modules). Build it, hand it to Aaron, and continue while it waits for desk time.

The probe deliberately also asks Aaron to export an empty plugin from the console. The exact grandMA3 plugin XML schema is not reliably documented, and inventing it would produce a file the console silently refuses to import. The console must be the source of truth.

- [ ] **Step 1: Write the probe plugin**

```lua
-- MA3CueDisplay-Probe — throwaway feasibility check. Not part of the shipped plugin.
-- Prints answers to the questions that decide whether a console-hosted HTTP
-- server is possible at all. Safe: binds a port only long enough to prove it can,
-- then closes it. Never loops.

local function line(fmt, ...)
  Printf("PROBE | " .. string.format(fmt, ...))
end

local function probe_version()
  local ok, v = pcall(function() return Version() end)
  line("ma3 version: %s", ok and tostring(v) or "Version() unavailable")
end

local function probe_socket()
  local ok, sock = pcall(require, "socket")
  if not ok then
    line("socket: FAIL -- require('socket') errored: %s", tostring(sock))
    line("socket: THIS IS THE HARD BLOCKER. Stop here and report.")
    return nil
  end
  line("socket: OK -- _VERSION=%s", tostring(sock._VERSION))
  local ok2, t = pcall(function() return sock.gettime() end)
  line("socket.gettime: %s", ok2 and string.format("OK (%.3f)", t) or "MISSING")
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
  local ok, ip, p = pcall(function() return server:getsockname() end)
  if ok then line("bind %d: sockname %s:%s", port, tostring(ip), tostring(p)) end
  server:close()
  line("bind %d: closed cleanly", port)
end

local function probe_sequences()
  local ok, seqs = pcall(function() return DataPool().Sequences:Children() end)
  if not ok or not seqs then
    line("sequences: FAIL -- %s", tostring(seqs))
    return
  end
  line("sequences: %d total in show file", #seqs)

  local t0 = os.clock()
  local active = 0
  for _, seq in ipairs(seqs) do
    local ok2, playing = pcall(function() return seq:HasActivePlayback() end)
    if ok2 and playing then active = active + 1 end
  end
  local elapsed = (os.clock() - t0) * 1000
  line("scan: %d active, full HasActivePlayback sweep took %.2f ms", active, elapsed)
  line("scan: at 5 Hz that is %.2f%% of the UI thread", (elapsed * 5) / 10)

  for _, seq in ipairs(seqs) do
    local ok2, playing = pcall(function() return seq:HasActivePlayback() end)
    if ok2 and playing then
      local ok3, cue = pcall(function() return seq:CurrentChild() end)
      if ok3 and cue then
        local no = select(2, pcall(function() return cue.No end))
        local nm = select(2, pcall(function() return cue.name end))
        line("active: seq.name=%s  cue.No=%s  cue.name=%s",
          tostring(seq.name), tostring(no), tostring(nm))
      else
        line("active: seq.name=%s  CurrentChild() returned nothing", tostring(seq.name))
      end
    end
  end
end

local function probe_yield()
  local t0 = os.clock()
  for i = 1, 200 do
    coroutine.yield(0.01)
  end
  line("yield: survived 200 iterations of coroutine.yield(0.01) in %.2f s wall-ish",
    os.clock() - t0)
end

return function()
  line("==== MA3 Cue Display feasibility probe ====")
  probe_version()
  local sock = probe_socket()
  probe_bind(sock, 8090)
  probe_sequences()
  probe_yield()
  line("==== probe complete ====")
end
```

- [ ] **Step 2: Write the probe instructions for Aaron**

Create `probe/README.md`:

```markdown
# Feasibility probe

Run this on the actual grandMA3 console before any of the plugin gets built.
It answers questions that cannot be verified without the hardware.

## Run it

1. Copy `MA3CueDisplay-Probe.lua` to a USB stick.
2. On the console: create a new plugin in the Plugin Pool named `Probe`.
3. Import `MA3CueDisplay-Probe.lua` as its Lua file.
4. **Have at least one cue stack running** before you press it, or the sequence
   checks will have nothing to report.
5. Press the plugin.
6. Open the Command Line Feedback window and screenshot every `PROBE |` line.

## Also needed — the plugin XML template

While you are in the Plugin Pool:

1. Create an empty plugin named `MA3CueDisplay`.
2. Export it to the USB stick.
3. Send back the resulting `MA3CueDisplay.xml`.

The exact plugin XML schema is not reliably documented anywhere, so the console
has to be the source of truth. Task 10 uses this file as its template.

## The one line that matters most

`PROBE | socket: FAIL` means LuaSocket is not available on console hardware and
the console-hosted design is dead. Stop and report it — do not try to work
around it.
```

- [ ] **Step 3: Verify the probe is syntactically valid Lua 5.4**

```bash
brew install lua@5.4
/opt/homebrew/opt/lua@5.4/bin/luac -p probe/MA3CueDisplay-Probe.lua && echo "syntax OK"
```

Expected: `syntax OK`. Note this only checks syntax — the MA3 globals (`Printf`, `Version`, `DataPool`) do not exist locally and are not called at load time.

- [ ] **Step 4: Commit**

```bash
git add probe/
git commit -m "$(cat <<'EOF'
Add feasibility probe plugin

Reports MA3 version, LuaSocket availability, port bind, cue property names,
and full sequence-scan timing. Also collects an exported plugin XML from the
console, since the schema is not reliably documented.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
git push
```

---

### Task 3: Test runner and JSON encoder

**Files:**
- Create: `tests/runner.lua`
- Create: `tests/all.lua`
- Create: `run-tests.sh`
- Create: `src/json.lua`
- Test: `tests/test_json.lua`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `runner.describe(name, fn)`, `runner.it(name, fn)`, `runner.assert_equal(actual, expected, msg?)`, `runner.assert_match(actual, pattern)`, `runner.report()`
  - `json.encode(value) -> string`. Object keys are sorted, so output is byte-deterministic and tests can assert on exact strings. Empty tables encode as `[]`.

- [ ] **Step 1: Write the test runner and harness**

`tests/runner.lua`:

```lua
-- Zero-dependency test runner. The whole point of this project is that it needs
-- nothing but Lua, so the tests need nothing but Lua either.
local M = { passed = 0, failed = 0, failures = {} }
local current = "?"

function M.describe(name, fn)
  current = name
  fn()
end

function M.it(name, fn)
  local ok, err = pcall(fn)
  if ok then
    M.passed = M.passed + 1
  else
    M.failed = M.failed + 1
    M.failures[#M.failures + 1] =
      string.format("%s > %s\n      %s", current, name, tostring(err))
  end
end

local function fmt(v)
  if type(v) == "table" then
    local parts = {}
    for k, x in pairs(v) do
      parts[#parts + 1] = tostring(k) .. "=" .. fmt(x)
    end
    table.sort(parts)
    return "{" .. table.concat(parts, ",") .. "}"
  end
  if type(v) == "string" then return string.format("%q", v) end
  return tostring(v)
end

function M.assert_equal(actual, expected, msg)
  if actual ~= expected then
    error(string.format("%sexpected %s, got %s",
      msg and (msg .. ": ") or "", fmt(expected), fmt(actual)), 2)
  end
end

function M.assert_match(actual, pattern)
  if type(actual) ~= "string" or not actual:find(pattern, 1, true) then
    error(string.format("expected %s to contain %s", fmt(actual), fmt(pattern)), 2)
  end
end

function M.assert_nil(actual)
  if actual ~= nil then
    error(string.format("expected nil, got %s", fmt(actual)), 2)
  end
end

function M.report()
  for _, f in ipairs(M.failures) do io.write("FAIL  ", f, "\n") end
  io.write(string.format("\n%d passed, %d failed\n", M.passed, M.failed))
  os.exit(M.failed == 0 and 0 or 1)
end

return M
```

`tests/all.lua`:

```lua
package.path = "./?.lua;./src/?.lua;./tests/?.lua;" .. package.path

local runner = require("runner")

require("test_json")

runner.report()
```

`run-tests.sh`:

```bash
#!/usr/bin/env bash
# Runs the test suite under Lua 5.4 — the version grandMA3 ships. The Mac's
# default `lua` is newer and would let 5.5-only syntax slip through to a console.
set -euo pipefail

LUA=/opt/homebrew/opt/lua@5.4/bin/lua
if [[ ! -x "$LUA" ]]; then
  echo "Lua 5.4 not found at $LUA — run: brew install lua@5.4" >&2
  exit 1
fi

"$LUA" -v
cd "$(dirname "$0")"
exec "$LUA" tests/all.lua
```

Then:

```bash
chmod +x run-tests.sh
```

- [ ] **Step 2: Write the failing JSON test**

`tests/test_json.lua`:

```lua
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
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
./run-tests.sh
```

Expected: FAIL — `module 'json' not found`.

- [ ] **Step 4: Write the JSON encoder**

`src/json.lua`:

```lua
-- Minimal JSON encoder. We only ever encode, never decode, and the console is
-- not guaranteed to ship a JSON library. Object keys are sorted so output is
-- byte-deterministic and testable.
local M = {}

local ESCAPES = {
  ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
  ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
}

local function escape_string(s)
  local out = s:gsub('[%c"\\]', function(c)
    return ESCAPES[c] or string.format("\\u%04x", c:byte())
  end)
  return out
end

-- A table is an array if every key is a positive integer with no gaps.
-- An empty table counts as an array: the only empty table we emit is
-- activeSequences, which is genuinely a list.
local function is_array(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" or k % 1 ~= 0 or k < 1 then return false end
    n = n + 1
  end
  return n == #t
end

function M.encode(v)
  local tv = type(v)
  if v == nil then
    return "null"
  elseif tv == "boolean" then
    return tostring(v)
  elseif tv == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "null" end
    if math.type(v) == "integer" then return tostring(v) end
    return (string.format("%.6g", v))
  elseif tv == "string" then
    return '"' .. escape_string(v) .. '"'
  elseif tv == "table" then
    local parts = {}
    if is_array(v) then
      for i = 1, #v do parts[i] = M.encode(v[i]) end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    for _, k in ipairs(keys) do
      parts[#parts + 1] = '"' .. escape_string(k) .. '":' .. M.encode(v[k])
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  error("json: cannot encode type " .. tv)
end

return M
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
./run-tests.sh
```

Expected: `10 passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add tests/ run-tests.sh src/json.lua
git commit -m "$(cat <<'EOF'
Add zero-dependency test runner and JSON encoder

Tests run under lua@5.4 to match the console runtime rather than the Mac's
newer default. Encoder sorts object keys so output is byte-deterministic.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
git push
```

---

### Task 4: Cue-state tracking

**Files:**
- Create: `src/state.lua`
- Test: `tests/test_state.lua`
- Modify: `tests/all.lua` (add `require("test_state")`)

**Interfaces:**
- Consumes: nothing
- Produces:
  - `state.new() -> st`
  - `state.update(st, snapshots) -> st` where `snapshots` is an array of `{ name=string, cueNumber=string, cueName=string }` in console iteration order, containing **only** sequences that are both playing and have a current cue
  - `state.payload(st, version, now) -> table` with keys `sequence`, `cueNumber`, `cueName`, `activeSequences`, `updatedAt`, `version`
  - `state.EMPTY_CUE_NUMBER == "--"`

This is the heart of the plugin and the only place the three edge cases from the spec are resolved. Tests come first and they define the contract.

- [ ] **Step 1: Write the failing state tests**

`tests/test_state.lua`:

```lua
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
    state.update(st, { snap("Main", "1") })          -- Haze goes off
    t.assert_equal(st.displayed.sequence, "Main")
    state.update(st, { snap("Main", "1"), snap("Haze", "9") })  -- Haze fires again
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
```

Add to `tests/all.lua`, after `require("test_json")`:

```lua
require("test_state")
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
./run-tests.sh
```

Expected: FAIL — `module 'state' not found`.

- [ ] **Step 3: Write the state module**

`src/state.lua`:

```lua
-- Pure cue-state tracking. Knows nothing about grandMA3 or sockets: it takes a
-- list of active-sequence snapshots and decides which cue to display.
--
-- "Most recently fired" is underdetermined on its own, so three rules make it
-- deterministic:
--   1. If several sequences advance in the same scan and one of them is already
--      displayed, keep it. Otherwise take the first in console iteration order.
--      Without this the display flaps between two simultaneously running stacks.
--   2. Cold start shows the first active sequence that has a cue.
--   3. When the displayed sequence stops playing, keep showing its last cue. A
--      display that blanks itself when a stack goes off is worse than one
--      showing the last cue that ran.
local M = {}

M.EMPTY_CUE_NUMBER = "--"

function M.new()
  return {
    displayed = { sequence = "", cueNumber = M.EMPTY_CUE_NUMBER, cueName = "" },
    seen = {},              -- sequence name -> cue number at the previous scan
    activeSequences = {},
  }
end

function M.update(st, snapshots)
  local previous = st.seen
  local seen = {}
  local active = {}
  local changed = {}

  for _, s in ipairs(snapshots) do
    seen[s.name] = s.cueNumber
    active[#active + 1] = s.name
    -- A name absent from the previous scan counts as changed. That covers both
    -- cold start and a sequence being re-fired at the cue it was already on.
    if previous[s.name] ~= s.cueNumber then
      changed[#changed + 1] = s
    end
  end

  st.seen = seen
  st.activeSequences = active

  if #changed > 0 then
    local pick = changed[1]
    for _, s in ipairs(changed) do
      if s.name == st.displayed.sequence then
        pick = s
        break
      end
    end
    st.displayed = {
      sequence = pick.name,
      cueNumber = pick.cueNumber,
      cueName = pick.cueName,
    }
  end

  return st
end

function M.payload(st, version, now)
  return {
    sequence = st.displayed.sequence,
    cueNumber = st.displayed.cueNumber,
    cueName = st.displayed.cueName,
    activeSequences = st.activeSequences,
    updatedAt = now,
    version = version,
  }
end

return M
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
./run-tests.sh
```

Expected: `21 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add src/state.lua tests/test_state.lua tests/all.lua
git commit -m "$(cat <<'EOF'
Add pure cue-state tracking with most-recently-fired resolution

Resolves the three ambiguities in "whatever fired most recently": simultaneous
changes keep the displayed sequence rather than flapping, cold start picks the
first active sequence, and a stopped sequence keeps its last cue on screen.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
git push
```

---

### Task 5: HTTP parsing, routing, and responses

**Files:**
- Create: `src/http.lua`
- Test: `tests/test_http.lua`
- Modify: `tests/all.lua` (add `require("test_http")`)

**Interfaces:**
- Consumes: nothing
- Produces:
  - `http.parse_request(line) -> {method=string, path=string, query=string} | nil`
  - `http.response(status, content_type, body) -> string`
  - `http.route(req, ctx) -> string` where `ctx = {html=string, state_json=string, version=string}`

The page decides its own mode from `location.pathname` and `location.search` client-side, so the server serves one identical HTML document for both `/` and `/debug`. No server-side branching on style.

- [ ] **Step 1: Write the failing HTTP tests**

`tests/test_http.lua`:

```lua
local t = require("runner")
local http = require("http")

local CTX = { html = "<html>page</html>", state_json = '{"a":1}', version = "2.0.0" }

t.describe("http.parse_request", function()
  t.it("parses a plain GET", function()
    local r = http.parse_request("GET / HTTP/1.1")
    t.assert_equal(r.method, "GET")
    t.assert_equal(r.path, "/")
    t.assert_equal(r.query, "")
  end)

  t.it("splits path from query", function()
    local r = http.parse_request("GET /?style=overlay HTTP/1.1")
    t.assert_equal(r.path, "/")
    t.assert_equal(r.query, "style=overlay")
  end)

  t.it("parses HTTP/1.0", function()
    local r = http.parse_request("GET /health HTTP/1.0")
    t.assert_equal(r.path, "/health")
  end)

  t.it("parses a non-GET method", function()
    local r = http.parse_request("POST /api/state HTTP/1.1")
    t.assert_equal(r.method, "POST")
  end)

  t.it("returns nil on garbage", function()
    t.assert_nil(http.parse_request("hello"))
    t.assert_nil(http.parse_request(""))
    t.assert_nil(http.parse_request("GET /"))
  end)
end)

t.describe("http.response", function()
  t.it("builds a well-formed response", function()
    local r = http.response(200, "text/plain", "hi")
    t.assert_match(r, "HTTP/1.1 200 OK\r\n")
    t.assert_match(r, "Content-Type: text/plain\r\n")
    t.assert_match(r, "Content-Length: 2\r\n")
    t.assert_match(r, "Connection: close\r\n")
    t.assert_match(r, "Cache-Control: no-store\r\n")
    t.assert_match(r, "Access-Control-Allow-Origin: *\r\n")
    t.assert_match(r, "\r\n\r\nhi")
  end)

  t.it("uses the right reason phrase", function()
    t.assert_match(http.response(404, "text/plain", ""), "404 Not Found")
    t.assert_match(http.response(405, "text/plain", ""), "405 Method Not Allowed")
    t.assert_match(http.response(503, "text/plain", ""), "503 Service Unavailable")
  end)

  t.it("computes Content-Length in bytes, not characters", function()
    t.assert_match(http.response(200, "text/plain", "\xc3\xa9"), "Content-Length: 2\r\n")
  end)
end)

t.describe("http.route", function()
  t.it("serves the page at /", function()
    local r = http.route({ method = "GET", path = "/", query = "" }, CTX)
    t.assert_match(r, "200 OK")
    t.assert_match(r, "text/html")
    t.assert_match(r, "<html>page</html>")
  end)

  t.it("serves the same page at /debug", function()
    local r = http.route({ method = "GET", path = "/debug", query = "" }, CTX)
    t.assert_match(r, "<html>page</html>")
  end)

  t.it("serves the page unchanged for ?style=overlay", function()
    local plain = http.route({ method = "GET", path = "/", query = "" }, CTX)
    local overlay = http.route({ method = "GET", path = "/", query = "style=overlay" }, CTX)
    t.assert_equal(overlay, plain)
  end)

  t.it("serves cached JSON at /api/state", function()
    local r = http.route({ method = "GET", path = "/api/state", query = "" }, CTX)
    t.assert_match(r, "application/json")
    t.assert_match(r, '{"a":1}')
  end)

  t.it("serves health with the version", function()
    local r = http.route({ method = "GET", path = "/health", query = "" }, CTX)
    t.assert_match(r, "ok 2.0.0")
  end)

  t.it("404s an unknown path", function()
    t.assert_match(http.route({ method = "GET", path = "/nope", query = "" }, CTX),
      "404 Not Found")
  end)

  t.it("405s a non-GET method", function()
    t.assert_match(http.route({ method = "POST", path = "/", query = "" }, CTX),
      "405 Method Not Allowed")
  end)
end)
```

Add to `tests/all.lua`:

```lua
require("test_http")
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
./run-tests.sh
```

Expected: FAIL — `module 'http' not found`.

- [ ] **Step 3: Write the HTTP module**

`src/http.lua`:

```lua
-- Pure HTTP: a request line in, a response string out. No sockets here, which
-- is what makes all of it testable off-console.
local M = {}

local REASONS = {
  [200] = "OK",
  [400] = "Bad Request",
  [404] = "Not Found",
  [405] = "Method Not Allowed",
  [500] = "Internal Server Error",
  [503] = "Service Unavailable",
}

function M.parse_request(line)
  if type(line) ~= "string" then return nil end
  local method, target = line:match("^(%u+)%s+(%S+)%s+HTTP/1%.[01]")
  if not method then return nil end
  local path, query = target:match("^([^?]*)%??(.*)$")
  return { method = method, path = path, query = query or "" }
end

function M.query_param(query, key)
  for pair in (query or ""):gmatch("[^&]+") do
    local k, v = pair:match("^([^=]*)=?(.*)$")
    if k == key then return v end
  end
  return nil
end

function M.response(status, content_type, body)
  body = body or ""
  return table.concat({
    "HTTP/1.1 " .. status .. " " .. (REASONS[status] or "OK"),
    "Content-Type: " .. content_type,
    "Content-Length: " .. #body,
    "Cache-Control: no-store",
    -- Cheap, and it stops /api/state from failing confusingly if someone
    -- embeds it in a page served from somewhere else.
    "Access-Control-Allow-Origin: *",
    "Connection: close",
    "",
    body,
  }, "\r\n")
end

-- The page picks its own mode from location.pathname and location.search, so
-- "/" and "/debug" serve one identical document and there is no server-side
-- styling logic to keep in sync.
function M.route(req, ctx)
  if req.method ~= "GET" then
    return M.response(405, "text/plain; charset=utf-8", "method not allowed")
  end
  local p = req.path
  if p == "/" or p == "/debug" then
    return M.response(200, "text/html; charset=utf-8", ctx.html)
  elseif p == "/api/state" then
    return M.response(200, "application/json; charset=utf-8", ctx.state_json)
  elseif p == "/health" then
    return M.response(200, "text/plain; charset=utf-8", "ok " .. ctx.version)
  end
  return M.response(404, "text/plain; charset=utf-8", "not found")
end

return M
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
./run-tests.sh
```

Expected: `40 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add src/http.lua tests/test_http.lua tests/all.lua
git commit -m "$(cat <<'EOF'
Add pure HTTP request parsing, routing, and response building

One HTML document serves / and /debug; the page selects its mode client-side
so there is no server-side styling branch to keep in sync.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
git push
```

---

### Task 6: Non-blocking connection state machine

**Files:**
- Create: `src/server.lua`
- Test: `tests/test_server.lua`
- Modify: `tests/all.lua` (add `require("test_server")`)

**Interfaces:**
- Consumes: `http.parse_request`, `http.route`, `http.response`
- Produces:
  - `server.new(listener, opts) -> sv` where `opts = {max_accepts_per_tick=4, max_pending=8, client_timeout=2.0, max_request_bytes=2048}`
  - `server.tick(sv, ctx, now) -> {accepted=n, served=n, dropped=n}`

The listener and clients are duck-typed, so tests inject fakes. A real LuaSocket listener satisfies the same interface.

Why a pending queue rather than accept-then-read: with `settimeout(0)` the request bytes have usually **not arrived** in the same tick as the accept. Reading immediately would nearly always get nothing. Giving the client a small blocking timeout instead would stall the console — exactly what this design forbids. So accepted clients go on a queue and are re-polled on later ticks until their request line completes or they age out.

- [ ] **Step 1: Write the failing server tests**

`tests/test_server.lua`:

```lua
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

local function fake_listener(queue)
  return {
    _queue = queue,
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
    -- Accepted this tick; read happens on the same tick's read pass.
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

  t.it("does nothing when there is no traffic", function()
    local sv = server.new(fake_listener({}))
    local r = server.tick(sv, CTX, 0)
    t.assert_equal(r.accepted, 0)
    t.assert_equal(r.served, 0)
    t.assert_equal(r.dropped, 0)
  end)
end)
```

Add to `tests/all.lua`:

```lua
require("test_server")
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
./run-tests.sh
```

Expected: FAIL — `module 'server' not found`.

- [ ] **Step 3: Write the server module**

`src/server.lua`:

```lua
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
      sv.pending[#sv.pending + 1] = { sock = client, buf = "", deadline = now + sv.opts.client_timeout }
      stats.accepted = stats.accepted + 1
    end
  end
end

local function read_pass(sv, ctx, stats, now)
  local keep = {}
  for _, entry in ipairs(sv.pending) do
    local line, err, partial
    local ok = pcall(function()
      line, err, partial = entry.sock:receive("*l")
    end)

    if not ok then
      finish(entry, nil)
      stats.dropped = stats.dropped + 1
    elseif line then
      local req = http.parse_request(line)
      if req then
        finish(entry, http.route(req, ctx))
        stats.served = stats.served + 1
      else
        finish(entry, http.response(400, "text/plain; charset=utf-8", "bad request"))
        stats.served = stats.served + 1
      end
    else
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
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
./run-tests.sh
```

Expected: `54 passed, 0 failed`.

If the partial-read test fails, check that `read_pass` appends `partial` to `entry.buf` **before** the size check — LuaSocket returns already-consumed bytes in the third return value and they are lost if not accumulated.

- [ ] **Step 5: Commit**

```bash
git add src/server.lua tests/test_server.lua tests/all.lua
git commit -m "$(cat <<'EOF'
Add non-blocking HTTP connection state machine

Accepted clients go on a pending queue and are re-polled across ticks, since
settimeout(0) means request bytes rarely arrive in the same tick as the accept.
Caps accepts per tick, sheds load at 503 when the queue fills, and ages out
silent clients so nothing is ever waited on.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
git push
```

---

### Task 7: grandMA3 adapter

**Files:**
- Create: `src/ma3.lua`
- Test: `tests/test_ma3.lua`
- Modify: `tests/all.lua` (add `require("test_ma3")`)

**Interfaces:**
- Consumes: nothing
- Produces:
  - `ma3.format_cue_number(no) -> string` — pure; converts MA3's internal `cue.No` to display form
  - `ma3.new(api?) -> adapter` where `api = {sequences = function() -> array}`; defaults to the real `DataPool().Sequences:Children()`
  - `ma3.snapshot(adapter) -> array` of `{name, cueNumber, cueName}`, feeding `state.update` directly

This is the only file that touches the MA3 object model, and it is deliberately thin so an MA API change touches one small file. Every MA3 call is wrapped in `pcall` — a property that vanishes in a future software version must degrade, not crash the plugin.

Cue numbers use `cue.No / 1000`, **not** `cue.index`. MA3 cue numbers allow three decimals and `cue.index` truncates to whole numbers, so cue 12.5 would render as 12.

- [ ] **Step 1: Write the failing adapter tests**

`tests/test_ma3.lua`:

```lua
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

  t.it("skips a sequence whose HasActivePlayback throws", function()
    local bad = fake_seq("Bad", true, 1000, "x")
    bad.HasActivePlayback = function() error("gone in 3.0") end
    local a = adapter_over({ bad, fake_seq("Main", true, 1000, "A") })
    local snaps = ma3.snapshot(a)
    t.assert_equal(#snaps, 1)
    t.assert_equal(snaps[1].name, "Main")
  end)

  t.it("returns an empty list when the sequence pool itself throws", function()
    local a = ma3.new({ sequences = function() error("no datapool") end })
    t.assert_equal(#ma3.snapshot(a), 0)
  end)
end)
```

Add to `tests/all.lua`:

```lua
require("test_ma3")
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
./run-tests.sh
```

Expected: FAIL — `module 'ma3' not found`.

- [ ] **Step 3: Write the adapter**

`src/ma3.lua`:

```lua
-- The ONLY module that touches the grandMA3 object model. Deliberately thin:
-- MA's own docs warn that plugins may need rewriting on a software upgrade, so
-- when that happens this is the single file to revisit.
--
-- Every console call is wrapped in pcall. A property that disappears in a future
-- MA3 version must degrade the display, not crash the plugin mid-service.
local M = {}

local EMPTY = "--"

-- MA3 stores cue numbers scaled by 1000 (cue 12.5 is 12500) and allows three
-- decimal places. cue.index truncates to whole numbers and must not be used.
function M.format_cue_number(no)
  local n = tonumber(no)
  if not n then return EMPTY end
  local s = string.format("%.3f", n / 1000)
  s = s:gsub("0+$", "")
  s = s:gsub("%.$", "")
  return s
end

function M.new(api)
  return {
    api = api or {
      sequences = function() return DataPool().Sequences:Children() end,
    },
  }
end

local function try(fn)
  local ok, value = pcall(fn)
  if ok then return value end
  return nil
end

function M.snapshot(self)
  local out = {}
  local seqs = try(self.api.sequences)
  if type(seqs) ~= "table" then return out end

  for _, seq in ipairs(seqs) do
    local playing = try(function() return seq:HasActivePlayback() end)
    if playing then
      local cue = try(function() return seq:CurrentChild() end)
      if cue then
        local no = try(function() return cue.No end)
        if no ~= nil then
          out[#out + 1] = {
            name = tostring(try(function() return seq.name end) or "?"),
            cueNumber = M.format_cue_number(no),
            cueName = tostring(try(function() return cue.name end) or ""),
          }
        end
      end
    end
  end
  return out
end

return M
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
./run-tests.sh
```

Expected: `66 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add src/ma3.lua tests/test_ma3.lua tests/all.lua
git commit -m "$(cat <<'EOF'
Add grandMA3 object-model adapter

Only file touching DataPool/Root, so an MA API change lands in one place.
Every console call is pcall-wrapped to degrade rather than crash. Cue numbers
come from cue.No/1000, since cue.index truncates 12.5 to 12.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
git push
```

---

### Task 8: Display page

**Files:**
- Create: `src/display.html`

**Interfaces:**
- Consumes: `GET /api/state` returning the `state.payload` shape
- Produces: one HTML document with three modes selected client-side — full-screen (default), overlay (`?style=overlay`), debug (`/debug`)

Carries forward the existing display's visual language — `clamp()` typography, muted grey sequence name, radial vignette on the overlay — from [web-display.html](../../gma3-cue-display-tauri/src/web-display.html), while removing two things that cannot survive the move to a console: the Google Fonts link (the console has no internet route, so it would block rendering and then fail) and the client-side cue-name regex (Lua now supplies clean fields).

- [ ] **Step 1: Write the page**

`src/display.html`:

```html
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>grandMA3 Cue</title>
<style>
  /* No webfont: the console has no route to the internet, so an external font
     would block paint and then fail. System stack only. */
  :root {
    --accent: #009CDE;   /* brand Light Blue. #004C97 fails WCAG AA on black. */
    --muted: #8a9099;
    --dim: #444a52;
    --fg: #ffffff;
  }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  html, body { height: 100%; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
                 "Helvetica Neue", Arial, sans-serif;
    background: #0b0d10;
    color: var(--fg);
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 2rem;
    -webkit-font-smoothing: antialiased;
    overflow: hidden;
  }
  .stack { text-align: center; max-width: 100%; }
  .sequence {
    font-size: clamp(1rem, 2.5vw, 2rem);
    font-weight: 400;
    color: var(--muted);
    letter-spacing: 0.04em;
    text-transform: uppercase;
    margin-bottom: 0.4em;
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
  }
  .cue { display: flex; align-items: baseline; justify-content: center;
         gap: 0.4em; max-width: 100%; }
  .number {
    font-size: clamp(3rem, 11vw, 9rem);
    font-weight: 700;
    color: var(--accent);
    font-variant-numeric: tabular-nums;
    line-height: 1;
  }
  .name {
    font-size: clamp(2rem, 7vw, 5.5rem);
    font-weight: 600;
    line-height: 1.1;
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
  }
  .waiting { color: var(--dim); font-weight: 400;
             font-size: clamp(1.2rem, 3.5vw, 2.4rem); }

  /* Stale: the console stopped answering, or updatedAt stopped advancing.
     Showing a cue that is no longer real is the failure that actually bites. */
  body.stale .stack { opacity: 0.25; }
  .offline {
    position: fixed; bottom: 1.2rem; left: 0; right: 0;
    text-align: center; color: #d9534f;
    font-size: clamp(0.8rem, 1.6vw, 1.1rem);
    letter-spacing: 0.08em; text-transform: uppercase;
    display: none;
  }
  body.stale .offline { display: block; }

  /* Overlay: OBS keys on the page's alpha, so the background must be fully
     transparent. The vignette keeps text legible over a camera feed. */
  body.overlay {
    background: transparent;
    align-items: flex-end;
    justify-content: flex-start;
    padding: 0 0 4vh 4vw;
  }
  body.overlay .stack {
    text-align: left;
    background: radial-gradient(ellipse at 30% 50%,
      rgba(0,0,0,0.72) 0%, rgba(0,0,0,0.42) 55%, transparent 82%);
    padding: 1.2em 3em 1.2em 1.5em;
    border-radius: 0.5rem;
  }
  body.overlay .cue { justify-content: flex-start; }
  body.overlay .number, body.overlay .name {
    text-shadow: 0 2px 12px rgba(0,0,0,0.9), 0 0 3px rgba(0,0,0,0.8);
  }
  body.overlay .sequence { text-shadow: 0 1px 6px rgba(0,0,0,0.9); }

  /* Debug: the page you open when someone says it shows the wrong cue. */
  body.debug { align-items: flex-start; justify-content: flex-start;
               padding: 1.5rem; display: block; overflow: auto; }
  body.debug .stack { text-align: left; margin-bottom: 1.5rem; }
  body.debug .number { font-size: 3rem; }
  body.debug .name { font-size: 2rem; }
  .debugpanel { display: none; font-family: ui-monospace, "SF Mono", Menlo, monospace;
                font-size: 0.85rem; color: var(--muted); }
  body.debug .debugpanel { display: block; }
  .debugpanel h2 { font-size: 0.8rem; text-transform: uppercase;
                   letter-spacing: 0.1em; color: var(--accent);
                   margin: 1.2rem 0 0.4rem; }
  .debugpanel pre { white-space: pre-wrap; word-break: break-all;
                    background: #14171c; padding: 0.8rem; border-radius: 4px; }
  .debugpanel li { list-style: none; padding: 0.15rem 0; }
</style>
</head>
<body>
  <div class="stack">
    <div class="sequence" id="sequence"></div>
    <div class="cue">
      <span class="number" id="number"></span>
      <span class="name waiting" id="name">Waiting for first cue</span>
    </div>
  </div>

  <div class="offline" id="offline">No data from console</div>

  <div class="debugpanel">
    <h2>Active sequences</h2>
    <ul id="dbgActive"></ul>
    <h2>Poll</h2>
    <ul id="dbgPoll"></ul>
    <h2>Raw state</h2>
    <pre id="dbgRaw">—</pre>
  </div>

<script>
(function () {
  "use strict";

  var POLL_MS = 250;
  var STALE_MS = 2000;   // 8 missed polls before we stop trusting the display

  var params = new URLSearchParams(location.search);
  var mode = location.pathname === "/debug" ? "debug"
           : (params.get("style") === "overlay" ? "overlay" : "full");
  document.body.classList.add(mode);

  var el = {
    sequence: document.getElementById("sequence"),
    number: document.getElementById("number"),
    name: document.getElementById("name"),
    dbgActive: document.getElementById("dbgActive"),
    dbgPoll: document.getElementById("dbgPoll"),
    dbgRaw: document.getElementById("dbgRaw")
  };

  var lastGoodAt = 0;
  var lastUpdatedAt = null;
  var stalledSince = null;
  var polls = 0, errors = 0, lastLatency = 0;

  function render(s) {
    el.sequence.textContent = s.sequence || "";
    var hasCue = s.cueNumber && s.cueNumber !== "--";
    el.number.textContent = hasCue ? s.cueNumber : "";
    if (hasCue || s.cueName) {
      el.name.classList.remove("waiting");
      el.name.textContent = s.cueName || "";
    } else {
      el.name.classList.add("waiting");
      el.name.textContent = "Waiting for first cue";
    }
  }

  function renderDebug(s, raw) {
    if (mode !== "debug") return;
    var active = (s && s.activeSequences) || [];
    el.dbgActive.innerHTML = active.length
      ? active.map(function (n) { return "<li>" + n + "</li>"; }).join("")
      : "<li>none</li>";
    el.dbgPoll.innerHTML = [
      "<li>polls: " + polls + "</li>",
      "<li>errors: " + errors + "</li>",
      "<li>last latency: " + lastLatency + " ms</li>",
      "<li>server updatedAt: " + (s ? s.updatedAt : "—") + "</li>",
      "<li>stalled: " + (stalledSince === null ? "no" : "since " + stalledSince) + "</li>",
      "<li>version: " + (s ? s.version : "—") + "</li>"
    ].join("");
    el.dbgRaw.textContent = raw || "—";
  }

  function markStale(isStale) {
    document.body.classList.toggle("stale", isStale);
  }

  function poll() {
    var t0 = performance.now();
    // no-store, plus a cache-buster, because OBS's embedded browser is more
    // willing to cache a 200 than a normal browser is.
    fetch("/api/state?_=" + Date.now(), { cache: "no-store" })
      .then(function (r) {
        if (!r.ok) throw new Error("HTTP " + r.status);
        return r.text();
      })
      .then(function (raw) {
        lastLatency = Math.round(performance.now() - t0);
        polls++;
        var s = JSON.parse(raw);
        lastGoodAt = Date.now();

        // The console answering is not the same as the console still running its
        // tick loop. If updatedAt stops advancing, the loop has wedged.
        if (s.updatedAt === lastUpdatedAt) {
          if (stalledSince === null) stalledSince = s.updatedAt;
        } else {
          stalledSince = null;
          lastUpdatedAt = s.updatedAt;
        }

        render(s);
        markStale(stalledSince !== null && Date.now() - lastGoodAt > STALE_MS);
        renderDebug(s, raw);
      })
      .catch(function () {
        errors++;
        markStale(Date.now() - lastGoodAt > STALE_MS);
        renderDebug(null, null);
      });
  }

  poll();
  setInterval(poll, POLL_MS);
})();
</script>
</body>
</html>
```

- [ ] **Step 2: Verify the page contains no forbidden sequence and no external assets**

```bash
grep -c ']==]' src/display.html || echo "no ]==] — good"
grep -nE 'https?://|//fonts\.|src="//' src/display.html || echo "no external assets — good"
```

Expected: both print the "good" message. A hit on the first would break the Lua long-string embedding; a hit on the second would fail on a console with no internet route.

- [ ] **Step 3: Eyeball all three modes against a stub API**

```bash
mkdir -p /tmp/ma3page && cp src/display.html /tmp/ma3page/index.html
cat > /tmp/ma3page/api-state.json <<'EOF'
{"sequence":"Main","cueNumber":"12.5","cueName":"Sermon Wash",
 "activeSequences":["Main","Haze"],"updatedAt":91234.5,"version":"2.0.0"}
EOF
cd /tmp/ma3page && python3 -c "
import http.server, socketserver, json, time
class H(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith('/api/state'):
            d = json.load(open('api-state.json')); d['updatedAt'] = time.time()
            b = json.dumps(d).encode()
            self.send_response(200); self.send_header('Content-Type','application/json')
            self.send_header('Content-Length',str(len(b))); self.end_headers(); self.wfile.write(b)
        elif self.path == '/debug' or self.path == '/':
            b = open('index.html','rb').read()
            self.send_response(200); self.send_header('Content-Type','text/html')
            self.send_header('Content-Length',str(len(b))); self.end_headers(); self.wfile.write(b)
        else: self.send_error(404)
print('http://localhost:8099/')
socketserver.TCPServer(('',8099), H).serve_forever()
"
```

Open and confirm each:
- `http://localhost:8099/` — dark, cue number `12.5` in Light Blue, name beside it, sequence name muted above
- `http://localhost:8099/?style=overlay` — transparent background (browser shows white), text bottom-left with a vignette
- `http://localhost:8099/debug` — active sequences, poll counters, raw JSON
- Stop the Python server and confirm the display dims and shows **No data from console** within ~2 s

Then `Ctrl-C` the server.

- [ ] **Step 4: Commit**

```bash
git add src/display.html
git commit -m "$(cat <<'EOF'
Add display page with full-screen, overlay, and debug modes

Mode is selected client-side from pathname and query string, so one document
serves every route. Drops the Google Fonts link (no internet route from a
console) and the client-side cue-name regex (Lua supplies clean fields now).
Goes stale rather than showing a cue that is no longer real.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
git push
```

---

### Task 9: Plugin entry point — tick loop, watchdog, Start/Stop

**Files:**
- Create: `src/main.lua`

**Interfaces:**
- Consumes: `json.encode`, `state.new/update/payload`, `server.new/tick/close`, `ma3.new/snapshot`, and `display_html` (a module returning the page as a string, supplied by `build.sh`)
- Produces: two plugin entry functions, `Start` and `Stop`, shared via the MA3 global variable `MA3CueDisplayRunning`

**Gated on Task 2's probe coming back with `socket: OK` and `bind 8090: OK`.** Do not start this task until that is confirmed.

Start and Stop are separate plugin components and therefore separate Lua chunks that cannot share upvalues. MA3's `GlobalVars()` is the reliable channel between them, so the run flag lives there.

- [ ] **Step 1: Write the entry point**

`src/main.lua`:

```lua
-- Plugin entry point. Everything MA3-specific that is not object-model access
-- lives here: Printf, GlobalVars, and the coroutine.yield tick loop.
--
-- MA3 plugins run as coroutines sharing the console's UI thread. Every socket
-- call is non-blocking and every tick yields, because a blocking call here
-- freezes the desk mid-service.

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
}

local RUN_VAR = "MA3CueDisplayRunning"
local VERSION = MA3CUEDISPLAY_VERSION or "dev"

local function log(fmt, ...)
  Printf("MA3 Cue Display: " .. string.format(fmt, ...))
end

local function running()
  return tonumber(GetVar(GlobalVars(), RUN_VAR) or 0) == 1
end

local function set_running(on)
  SetVar(GlobalVars(), RUN_VAR, on and 1 or 0)
end

-- socket.gettime() is a monotonic-enough wall clock and is confirmed present.
-- os.clock() measures CPU time, which would make client deadlines meaningless.
local function now_fn(socket)
  if socket and socket.gettime then return socket.gettime end
  return function() return os.time() end
end

local function report_urls()
  -- The console does not expose its own address through a documented Lua call,
  -- so print the port and let the operator read the IP off the network menu.
  log("serving on port %d -- open http://<console-ip>:%d", CONFIG.port, CONFIG.port)
  log("  full screen : http://<console-ip>:%d/", CONFIG.port)
  log("  OBS overlay : http://<console-ip>:%d/?style=overlay", CONFIG.port)
  log("  debug       : http://<console-ip>:%d/debug", CONFIG.port)
end

local function start()
  if running() then
    log("already running -- use the Stop Cue Display macro first")
    return
  end

  local ok, socket = pcall(require, "socket")
  if not ok then
    log("FAILED: LuaSocket is not available on this station (%s)", tostring(socket))
    return
  end

  local listener, err = socket.bind("*", CONFIG.port)
  if not listener then
    log("FAILED: cannot bind port %d (%s)", CONFIG.port, tostring(err))
    return
  end

  local clock = now_fn(socket)
  local sv = server.new(listener, {})
  local st = state.new()
  local adapter = ma3.new()
  local ctx = {
    html = display_html,
    state_json = json.encode(state.payload(st, VERSION, clock())),
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
      if tick % CONFIG.cue_scan_every == 0 then
        state.update(st, ma3.snapshot(adapter))
        ctx.state_json = json.encode(state.payload(st, VERSION, clock()))
      end
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
  log("stopped")
end

local function stop()
  if not running() then
    log("not running")
    return
  end
  set_running(false)
  log("stop requested -- the loop will close its socket on the next tick")
end

return start, stop
```

- [ ] **Step 2: Verify it is valid Lua 5.4**

```bash
/opt/homebrew/opt/lua@5.4/bin/luac -p src/main.lua && echo "syntax OK"
```

Expected: `syntax OK`. The MA3 globals do not exist locally and are not called at load time.

- [ ] **Step 3: Confirm no MA3 API leaked outside main.lua and ma3.lua**

```bash
grep -nE '\b(DataPool|SelectedSequence|Root|Printf|GetVar|SetVar|GlobalVars|UserVars)\b' \
  src/json.lua src/state.lua src/http.lua src/server.lua || echo "clean — no MA3 API leakage"
```

Expected: `clean — no MA3 API leakage`. This is a Global Constraint; a hit here means a pure module became untestable.

- [ ] **Step 4: Verify every module main.lua requires is one the build script bundles**

This coupling breaks silently. `build.sh` hardcodes its module list, so adding a `require` in `src/` without adding the module to that list produces a bundle that loads fine locally and fails only on the console, where there is no `src/` directory to fall back to.

```bash
echo "required by main.lua:"
grep -oE 'require\("[a-z_]+"\)' src/main.lua | sed 's/require("//;s/")//' | sort -u
echo "bundled by build.sh:"
grep -oE 'for m in [a-z ]+' build.sh | sed 's/for m in //' | tr ' ' '\n' | sort -u
```

Expected: every module `main.lua` requires appears in the build list, except `display_html` (bundled by its own separate `package.preload` block) and `socket` (provided by the console). `build.sh` does not exist until Task 10 — if it is missing here, re-run this check as part of Task 10 Step 3.

- [ ] **Step 5: Commit**

```bash
git add src/main.lua
git commit -m "$(cat <<'EOF'
Add plugin entry point with tick loop and watchdog

20 Hz socket service, ~5 Hz cue scan, pcall per tick, and a shutdown after ten
consecutive errors so a wedged loop cannot ride out a service. Start and Stop
are separate Lua chunks, so the run flag lives in GlobalVars.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
git push
```

---

### Task 10: Build script and distributable

**Files:**
- Create: `build.sh`
- Create: `dist/MA3CueDisplay.xml` (from the console-exported template collected in Task 2)
- Create: `.gitignore` entry for `dist/MA3CueDisplay.lua`

**Interfaces:**
- Consumes: everything in `src/`, plus the exported XML template from Task 2
- Produces: `dist/MA3CueDisplay.lua` — one self-contained file; and `dist/MA3CueDisplay.xml`

Modules are bundled with `package.preload`, which keeps `require("json")` working inside a single concatenated file with no path setup.

**Requires the console-exported XML from Task 2.** Do not hand-write the plugin XML — an invented schema imports as a silently broken plugin.

- [ ] **Step 1: Write the build script**

`build.sh`:

```bash
#!/usr/bin/env bash
# Bundles src/ into one self-contained Lua file for the console. Modules are
# wrapped in package.preload so require() works with no path setup.
set -euo pipefail

VERSION="2.0.0"
LUA=/opt/homebrew/opt/lua@5.4/bin/lua
OUT_LUA="dist/MA3CueDisplay.lua"
OUT_XML="dist/MA3CueDisplay.xml"

cd "$(dirname "$0")"
mkdir -p dist

# The page is embedded in a [==[ ... ]==] long string. A literal ]==] in the
# HTML would terminate it early and produce a syntax error on the console.
if grep -q ']==]' src/display.html; then
  echo "ERROR: src/display.html contains ]==] which breaks the Lua long string" >&2
  exit 1
fi

# The console has no route to the internet; an external asset would fail there.
if grep -qE 'https?://' src/display.html; then
  echo "ERROR: src/display.html references an external URL" >&2
  exit 1
fi

{
  echo "-- MA3 Cue Display ${VERSION}"
  echo "-- Generated by build.sh -- do not edit. Source:"
  echo "--   https://github.com/upipibi/ma3-cue-display"
  echo ""
  for m in json state http server ma3; do
    echo "package.preload[\"${m}\"] = function()"
    cat "src/${m}.lua"
    echo "end"
    echo ""
  done
  echo 'package.preload["display_html"] = function() return [==['
  cat src/display.html
  echo ']==] end'
  echo ""
  echo "MA3CUEDISPLAY_VERSION = \"${VERSION}\""
  echo ""
  cat src/main.lua
} > "$OUT_LUA"

if [[ ! -f "$OUT_XML" ]]; then
  echo "WARNING: $OUT_XML missing. Copy the console-exported template into place." >&2
else
  # Keep the version in the XML aligned with the build.
  sed -i '' "s/Version=\"[0-9.]*\"/Version=\"${VERSION}\"/" "$OUT_XML" || true
fi

"$LUA" -e "assert(loadfile('${OUT_LUA}'))" \
  && echo "built ${OUT_LUA} ($(wc -c < "$OUT_LUA" | tr -d ' ') bytes) -- syntax OK"
```

Then:

```bash
chmod +x build.sh
```

- [ ] **Step 2: Install the console-exported XML template**

Copy the `MA3CueDisplay.xml` that came back from Task 2's probe into `dist/`, then confirm it names the Lua file and declares the two components. If the exported file declares only one component, add the second by duplicating the existing component element and renaming it — following the exact attribute names the console produced, not invented ones.

```bash
cp /path/to/exported/MA3CueDisplay.xml dist/MA3CueDisplay.xml
cat dist/MA3CueDisplay.xml
```

Expected: valid XML naming `MA3CueDisplay.lua` with components for Start and Stop.

- [ ] **Step 3: Build and verify the bundle loads**

```bash
./build.sh
```

Expected: `built dist/MA3CueDisplay.lua (NNNNN bytes) -- syntax OK`.

- [ ] **Step 4: Verify the bundled modules actually resolve**

```bash
/opt/homebrew/opt/lua@5.4/bin/lua -e '
  local chunk = assert(loadfile("dist/MA3CueDisplay.lua"))
  -- Stub the MA3 globals main.lua closes over at load time.
  Printf = function() end
  GetVar = function() return 0 end
  SetVar = function() end
  GlobalVars = function() return {} end
  local start, stop = chunk()
  assert(type(start) == "function", "start must be a function")
  assert(type(stop) == "function", "stop must be a function")
  assert(#require("display_html") > 1000, "page did not embed")
  assert(require("json").encode({a=1}) == "{\"a\":1}", "json module broken")
  print("bundle OK: modules resolve, page embedded, entry points returned")
'
```

Expected: `bundle OK: modules resolve, page embedded, entry points returned`.

- [ ] **Step 5: Gitignore the generated Lua, keep the XML**

Append to `.gitignore`:

```
# Generated by build.sh — rebuilt on demand, attached to releases
dist/MA3CueDisplay.lua
```

- [ ] **Step 6: Run the full suite once more, then commit**

```bash
./run-tests.sh && ./build.sh
git add build.sh dist/MA3CueDisplay.xml .gitignore
git commit -m "$(cat <<'EOF'
Add build script producing a single-file plugin bundle

Modules are wrapped in package.preload so require() works inside one
concatenated file. Build fails closed if the page contains ]==] or references
an external URL, both of which break on a console.

XML template is the console's own export, not hand-written — an invented schema
imports as a silently broken plugin.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
git push
```

---

### Task 11: Remove the Tauri app and rewrite the docs

**Files:**
- Delete: `gma3-cue-display-tauri/`, `MA3CueDisplay-v1.0.1-aarch64.zip`, `.claude-notes`, `LAUNCHER_TEMPLATE.md`, `Launcher.png`, `MA3 Cue Display.code-workspace`
- Rewrite: `README.md`, `CLAUDE.md`, `CREDITS.md`
- Keep: `LICENSE`, `Icons/`, `Web Layout.png`

**Interfaces:**
- Consumes: the finished plugin from Tasks 3–10
- Produces: a repo whose docs describe what the project now is

Everything deleted stays recoverable from git history, which the spec requires as the fallback path if the probe ever comes back red.

- [ ] **Step 1: Remove the dead Mac app and its artifacts**

```bash
git rm -r --quiet gma3-cue-display-tauri
git rm --quiet "MA3CueDisplay-v1.0.1-aarch64.zip" "Launcher.png" "MA3 Cue Display.code-workspace"
git rm --quiet --cached .claude-notes LAUNCHER_TEMPLATE.md 2>/dev/null || true
rm -f .claude-notes LAUNCHER_TEMPLATE.md
git status --short
```

Expected: deletions staged. `.claude-notes` and `LAUNCHER_TEMPLATE.md` were untracked, so `git rm --cached` may report nothing — the `rm -f` handles them.

- [ ] **Step 2: Rewrite README.md**

```markdown
# MA3 Cue Display

A cue display for grandMA3 that runs **on the console itself**. No extra
computer, no OSC configuration, no app to install on a Mac.

Install a plugin, press one button, and any browser or OBS instance on the
network can see the current cue.

![Web layout](Web%20Layout.png)

## What it does

The plugin reads the console's own object model to find whichever cue stack
fired most recently, and serves a live page over HTTP from the console. Open it
on a confidence monitor, a phone, or as an OBS browser source.

| URL | What you get |
|---|---|
| `http://<console-ip>:8090/` | Full-screen display for a monitor |
| `http://<console-ip>:8090/?style=overlay` | Transparent overlay for OBS |
| `http://<console-ip>:8090/debug` | Active sequences, poll stats, raw state |
| `http://<console-ip>:8090/api/state` | JSON, if you want to build something else |
| `http://<console-ip>:8090/health` | Liveness check |

## Requirements

- A grandMA3 console or onPC station with LuaSocket available
- The viewing device on the same network as the console
- Port **8090** reachable on the console (8080 is MA3's own Web Remote)

## Install

1. Copy `MA3CueDisplay.lua` and `MA3CueDisplay.xml` onto a USB stick.
2. On the console, put both in `gma3_library/datapools/plugins`.
3. Import the plugin in the Plugin Pool.
4. Set the plugin's **InStream** property so it is stored in the show file. It
   then travels with the show and survives a console reboot.
5. Make two macros:
   - `Start Cue Display` → `Plugin "MA3CueDisplay"`
   - `Stop Cue Display` → the plugin's Stop component
6. Put `Start Cue Display` on an executor button.

## Running it

Press **Start Cue Display**. The Command Line Feedback window prints the port
and the URLs. Read your console's IP off the network menu and open the page.

**There is no auto-start on a console.** grandMA3 offers a `RUNPLUGIN` launch
argument for onPC only; a console has no supported on-show-load hook, because
the engine cannot be started while it is still being assembled. So this is one
button press per session.

Press **Stop Cue Display** to shut it down. The plugin also stops itself if it
hits ten consecutive internal errors, rather than continuing to run in a bad
state on a live desk.

## OBS setup

1. Add a **Browser** source.
2. URL: `http://<console-ip>:8090/?style=overlay`
3. Width 1920, Height 1080.
4. Leave **Shutdown source when not visible** off, so it stays current.

The page background is fully transparent in overlay mode, so it keys straight
over a camera input with no chroma key.

## When it shows the wrong thing

Open `/debug`. It lists every sequence the console reports as playing, the raw
state JSON, and poll timing.

The display tracks **whatever fired most recently on any executor**. Bumping a
flash or effect executor will pull it off your main stack until the main stack
fires again — that is by design, matching how the original OSC version behaved.

If the page dims and says **No data from console**, the plugin stopped or the
console became unreachable. Press Start Cue Display again.

## Building from source

```bash
brew install lua@5.4
./run-tests.sh     # unit tests for the pure modules
./build.sh         # produces dist/MA3CueDisplay.lua
```

Sources live in `src/` as small modules and are concatenated into one file for
distribution. `src/ma3.lua` is the only file that touches the grandMA3 API.

## History

Version 2.0.0 is a complete rewrite. Earlier versions were a macOS menu-bar app
(Tauri/Rust) that received OSC over UDP from the console and served the display
from a Mac. That required a dedicated machine, OSC output configured on the
console, and an unsigned app users had to talk macOS into opening. The console
hosts everything now. The old app remains in this repository's git history.

## License

MIT — see [LICENSE](LICENSE).
```

- [ ] **Step 3: Rewrite CLAUDE.md**

```markdown
# MA3 Cue Display — Project Context

A grandMA3 **Lua plugin** that runs on the console and serves a live cue display
over HTTP to browsers and OBS. No companion app, no OSC. Personal project under
`upipibi`. Stack: **Lua 5.4 + LuaSocket + vanilla HTML/CSS/JS**.

> **Read first:** [README.md](README.md) for install and OBS setup.
> Design rationale: [docs/superpowers/specs/2026-08-04-ma3-cue-display-lua-plugin-design.md](docs/superpowers/specs/2026-08-04-ma3-cue-display-lua-plugin-design.md)

---

## Status — 2026-08-04
- **Stage:** rewritten from the macOS Tauri app to a console-hosted Lua plugin
- **Works:** cue-state polling from the object model, non-blocking HTTP server,
  three display modes (full-screen / OBS overlay / debug), `/api/state`,
  `/health`, unit-tested pure modules, single-file build
- **Known issues:**
  - **No auto-start on a console.** One macro press per session. `RUNPLUGIN` is
    onPC-only and there is no supported on-show-load hook.
  - **MA disclaims plugin support** and warns plugins may need rewriting on a
    software upgrade. `src/ma3.lua` is kept thin so that lands in one file.

## Architecture

One Lua coroutine, 20 Hz tick loop, `coroutine.yield(0.05)` every tick.

```
plugin "MA3CueDisplay" (Start component)
  every 4th tick (~5 Hz): ma3.snapshot() -> state.update() -> json.encode(), cached
  every tick:             server.tick() -- non-blocking accept/read/respond
    GET /                 display page (full-screen)
    GET /?style=overlay   same page, transparent for OBS
    GET /debug            same page, debug panel
    GET /api/state        cached JSON
    GET /health           ok + version
Stop component: clears GlobalVars MA3CueDisplayRunning; loop closes its socket
```

Clients poll `/api/state` every 250 ms. No WebSocket — a held-open connection in
a cooperative single-coroutine server is a liability, and 250 ms is invisible on
a cue display.

### Where things live
```
src/json.lua       pure JSON encoder (encode only)
src/state.lua      pure cue-state tracking, most-recently-fired resolution
src/http.lua       pure request parse / route / response
src/server.lua     non-blocking connection state machine, socket-agnostic
src/ma3.lua        the ONLY file touching the grandMA3 object model
src/display.html   the page — all three modes, selected client-side
src/main.lua       plugin entry: bind, tick loop, watchdog, Start/Stop
build.sh           bundles src/ into dist/MA3CueDisplay.lua via package.preload
run-tests.sh       runs tests/ under lua@5.4
probe/             throwaway feasibility plugin, not shipped
```

## Key identifiers
| Thing | Value |
|---|---|
| Type / stack | grandMA3 Lua plugin — Lua 5.4 + LuaSocket, vanilla frontend |
| GitHub repo | `upipibi/ma3-cue-display` (public) |
| Current version | 2.0.0 (defined once, in `build.sh`) |
| Ports | 8090 HTTP (configurable in `src/main.lua`) |
| Host | grandMA3 console |
| Secrets | none |

## Build / Run / Release
```bash
brew install lua@5.4
./run-tests.sh     # must pass before any commit
./build.sh         # -> dist/MA3CueDisplay.lua
```

A release is two text files: `dist/MA3CueDisplay.lua` and
`dist/MA3CueDisplay.xml`. No signing, no notarization, no Sparkle, no
`xattr -cr`, no Gatekeeper. That whole class of problem left with the Mac app.

## Conventions & gotchas
- **Never block a socket call.** `settimeout(0)` everywhere. MA3 plugins are
  coroutines on the console's UI thread; a blocking `accept()` or `receive()`
  freezes the desk. This is the single most important rule in the project.
- **Test under `lua@5.4`, not the Mac's default.** Homebrew's plain `lua` is
  5.5; the console runs 5.4.4. `run-tests.sh` pins the right one.
- **All MA3 API access stays in `src/ma3.lua`.** `src/main.lua` may use
  `Printf`/`GetVar`/`SetVar`/`GlobalVars` only. Keeping the pure modules free of
  console globals is what makes them testable.
- **Cue numbers come from `cue.No / 1000`.** `cue.index` truncates 12.5 to 12.
- **Cue-change hooks do not work.** `HookObjectChange` on sequences fires only
  on edits, not playback; `HasActivePlayback()` is a function so it cannot be
  hooked; hooking `Root().Temp.RunningSequences` reportedly needs the Running
  Sequences window open on a physical screen. Polling is the only reliable path.
- **`src/display.html` must never contain `]==]`** — it is embedded in a Lua
  long string. `build.sh` fails the build if it does.
- **No external assets in the page.** The console has no internet route; a
  webfont or CDN script would block paint and then fail. `build.sh` enforces it.
- **Start and Stop are separate Lua chunks** and cannot share upvalues. The run
  flag lives in `GlobalVars()` under `MA3CueDisplayRunning`.

## Update Protocol
| When you… | Update… |
|---|---|
| ship a version | Status date · version in `build.sh` · README |
| add or rename a route | Architecture · README URL table |
| change how cue state is read | `src/ma3.lua` · Conventions & gotchas |
| hit and fix a gotcha | Conventions & gotchas |

## Document history
| Date | Change |
|---|---|
| 2026-05-29 | Initial CLAUDE.md for the Tauri macOS app |
| 2026-08-04 | Rewritten for the console-hosted Lua plugin; moved to `upipibi` |
```

- [ ] **Step 4: Rewrite CREDITS.md**

```markdown
# Credits

## Runtime dependencies

| Dependency | License | Notes |
|---|---|---|
| [Lua 5.4](https://www.lua.org/license.html) | MIT | Provided by grandMA3 |
| [LuaSocket](https://github.com/lunarmodules/luasocket) | MIT | Provided by grandMA3; used for the TCP listener |

No bundled third-party code. The JSON encoder, HTTP layer, and test runner are
written for this project specifically, so the plugin ships as plain Lua with
nothing vendored.

## Frontend

No frameworks, no build step, no webfonts. `src/display.html` is vanilla
HTML/CSS/JS using a system font stack, because the console has no route to the
internet and an external asset would block rendering and then fail.

## Platform

grandMA3 by [MA Lighting](https://www.malighting.com/). This is an unofficial
third-party plugin, not affiliated with or endorsed by MA Lighting. MA's own
documentation notes that plugins can reach deeper into the system than normal
console use and that their support may not be able to help with plugin issues.

## History

Versions before 2.0.0 were a macOS app built with [Tauri](https://tauri.app/)
(MIT/Apache-2.0), using `warp`, `rosc`, `tokio`, and `serde`. That code and its
license notices remain in this repository's git history.
```

- [ ] **Step 5: Verify no doc still describes the dead app**

```bash
grep -rniE 'tauri|xattr|codesign|sparkle|gatekeeper|osc port|port 3000|port 8000|menu.?bar' \
  README.md CLAUDE.md CREDITS.md \
  | grep -viE 'git history|remain in this repository|left with the Mac app|Earlier versions|Versions before' \
  || echo "clean — no stale references to the Mac app"
```

Expected: `clean — no stale references to the Mac app`.

- [ ] **Step 6: Run the full suite and build, then commit**

```bash
./run-tests.sh && ./build.sh
git add -A
git commit -m "$(cat <<'EOF'
Remove the Tauri macOS app and rewrite the docs for the Lua plugin

Deletes the Rust/Tauri project, the 6 MB release zip, the macOS signing notes,
and the launcher design doc. All recoverable from git history, which is the
fallback path if console LuaSocket ever turns out to be unavailable.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
git push
```

---

### Task 12: Desk test on the console

**Files:** none — this is a manual verification gate

**Interfaces:**
- Consumes: `dist/MA3CueDisplay.lua` and `dist/MA3CueDisplay.xml` from Task 10
- Produces: a pass/fail signal gating Task 13

Nothing gets tagged or released until this passes. Aaron's explicit instruction: test before releasing.

- [ ] **Step 1: Install on the console**

Copy both files to a USB stick, place in `gma3_library/datapools/plugins`, import in the Plugin Pool, set `InStream`, and create the Start and Stop macros per the README.

- [ ] **Step 2: Verify start-up and the console stays responsive**

Press **Start Cue Display**, then check each:

- Command Line Feedback prints `version 2.0.0 started` and the URL lines
- **Move a fader, run a cue, open a window, type in the command line.** The desk must feel completely normal. Any stutter, lag, or hesitation is a stop-the-line failure — press Stop immediately and report it.
- Press Start a second time: it must print `already running`, not bind twice

- [ ] **Step 3: Verify the display in a browser**

From a laptop on the same network:

- `http://<console-ip>:8090/` shows the current cue
- Fire cues on the main stack — the number and name update within about half a second
- Fire a different executor — the display switches to it
- Fire the main stack again — it comes back
- Turn the displayed stack off — the last cue stays on screen, it does not blank
- `http://<console-ip>:8090/debug` lists the active sequences correctly
- `http://<console-ip>:8090/health` returns `ok 2.0.0`
- **Cue numbers with decimals** (e.g. cue 12.5) display as `12.5`, not `12`

- [ ] **Step 4: Verify OBS**

Add a Browser source at `http://<console-ip>:8090/?style=overlay`, 1920×1080, over a camera input.

- Text appears over the camera with no background box and no chroma key
- Cues update live
- Leave it running for ten minutes and confirm it neither freezes nor drifts

- [ ] **Step 5: Verify failure behavior**

- Press **Stop Cue Display**: feedback prints `stopped`, and the browser page dims to **No data from console** within about two seconds
- Press **Start** again — it comes back
- Open five browser tabs at once, plus OBS. The console must stay responsive and every viewer must stay current. This exercises the pending-queue cap.
- Unplug the laptop's network mid-poll, then reconnect. The page recovers on its own with no reload.

- [ ] **Step 6: Soak it through an actual service**

Run it through one real service before releasing. The failure modes that matter — slow drift, a wedged tick, a memory creep over hours — do not show up in a ten-minute bench test.

Report the result. **Any console-responsiveness problem blocks the release outright**, regardless of whether the display itself worked.

---

### Task 13: Release 2.0.0

**Files:**
- Create: git tag `v2.0.0` and a GitHub release with both plugin files attached

**Interfaces:**
- Consumes: a passing Task 12
- Produces: a public release on `upipibi/ma3-cue-display`

**Gated on Task 12 passing, including the service soak.** Do not run this task otherwise.

- [ ] **Step 1: Confirm the gate and a clean tree**

```bash
./run-tests.sh && ./build.sh
git status --short
```

Expected: all tests pass, build succeeds, working tree clean. Confirm with Aaron that the desk test and service soak both passed before continuing.

- [ ] **Step 2: Tag**

```bash
git tag -a v2.0.0 -m "MA3 Cue Display 2.0.0 — console-hosted Lua plugin"
git push origin v2.0.0
```

- [ ] **Step 3: Create the release with both plugin files**

```bash
gh release create v2.0.0 \
  dist/MA3CueDisplay.lua \
  dist/MA3CueDisplay.xml \
  --title "2.0.0 — console-hosted Lua plugin" \
  --notes "$(cat <<'EOF'
A complete rewrite. The cue display now runs **on the grandMA3 console itself** —
no companion Mac, no OSC configuration, no unsigned app to talk macOS into
opening.

## Install

Copy both files to `gma3_library/datapools/plugins`, import in the Plugin Pool,
set `InStream`, and make a macro `Plugin "MA3CueDisplay"`. Full steps in the
README.

## What you get

- `http://<console-ip>:8090/` — full-screen display for a monitor
- `http://<console-ip>:8090/?style=overlay` — transparent overlay for OBS, keys
  straight over a camera with no chroma key
- `http://<console-ip>:8090/debug` — active sequences, poll stats, raw state
- `http://<console-ip>:8090/api/state` — JSON

## Notes

- Tracks whichever cue stack fired most recently, read from the console's object
  model rather than parsed out of an OSC string.
- **No auto-start on a console** — one macro press per session. grandMA3's
  `RUNPLUGIN` launch argument is onPC-only and there is no supported
  on-show-load hook.
- Every socket call is non-blocking, because MA3 plugins share the console's UI
  thread and a blocking call would freeze the desk.
- Unofficial third-party plugin, not affiliated with MA Lighting.
EOF
)"
```

- [ ] **Step 4: Verify the release**

```bash
gh release view v2.0.0
```

Expected: both `MA3CueDisplay.lua` and `MA3CueDisplay.xml` attached. Download the Lua asset and confirm it is the built bundle, not a source file:

```bash
gh release download v2.0.0 --pattern 'MA3CueDisplay.lua' --dir /tmp/relcheck --clobber
head -3 /tmp/relcheck/MA3CueDisplay.lua
grep -c 'package.preload' /tmp/relcheck/MA3CueDisplay.lua
```

Expected: the generated header, and 6 `package.preload` lines (five modules plus the page).

---

### Task 14: Delete the Northwoods repository

**Files:** none — this removes a remote repository

**Interfaces:**
- Consumes: a verified, released `upipibi/ma3-cue-display`
- Produces: `NorthwoodsCommunityChurch/Ma3_Cue_Display` gone

**This is irreversible and takes issues, releases, and tags with it.** It runs last, only after Task 13, and only with Aaron's explicit go-ahead at that moment — not on the strength of this plan.

- [ ] **Step 1: Verify the replacement is complete before destroying the original**

```bash
rm -rf /tmp/migration-check
git clone https://github.com/upipibi/ma3-cue-display.git /tmp/migration-check
cd /tmp/migration-check
git log --oneline | wc -l
git tag | sort
gh release list --repo upipibi/ma3-cue-display
cd -
```

Compare against the old repo:

```bash
git ls-remote --heads --tags northwoods-old
gh release list --repo NorthwoodsCommunityChurch/Ma3_Cue_Display
```

Expected: every commit and tag from the old repo is present in the new clone. **If anything is missing, stop.**

- [ ] **Step 2: Archive the old repo's releases locally, in case anyone still needs the Mac app**

```bash
mkdir -p ~/Documents/OneDrive-archive-ma3-cue-display
gh release download --repo NorthwoodsCommunityChurch/Ma3_Cue_Display \
  --dir ~/Documents/OneDrive-archive-ma3-cue-display --clobber || \
  echo "no release assets to archive"
ls -la ~/Documents/OneDrive-archive-ma3-cue-display
```

The v1.0.1 signed zip is the only build of the Mac app that exists. It is also in git history as a committed file, but keeping the released asset costs nothing.

- [ ] **Step 3: Get explicit confirmation from Aaron**

Ask directly, naming what is about to be destroyed:

> Ready to delete `NorthwoodsCommunityChurch/Ma3_Cue_Display`. This is irreversible and takes its issues, releases, and tags with it. The new repo is verified with full history and a 2.0.0 release. Confirm?

Do not proceed without a yes.

- [ ] **Step 4: Add the delete_repo scope**

The current `gh` token has `gist, read:org, repo, workflow` — no `delete_repo`, so deletion will fail without this:

```bash
gh auth refresh -h github.com -s delete_repo
gh auth status
```

Expected: `delete_repo` now listed in the token scopes.

- [ ] **Step 5: Delete the repository and drop the stale remote**

```bash
gh repo delete NorthwoodsCommunityChurch/Ma3_Cue_Display --yes
git remote remove northwoods-old
git remote -v
```

Expected: only `origin` remains, pointing at `upipibi/ma3-cue-display`.

- [ ] **Step 6: Note the removal in CLAUDE.md and commit**

Add to the `Document history` table in `CLAUDE.md`:

```markdown
| 2026-08-04 | Migrated to `upipibi/ma3-cue-display`; `NorthwoodsCommunityChurch/Ma3_Cue_Display` deleted after verifying full history and the 2.0.0 release |
```

```bash
git add CLAUDE.md
git commit -m "$(cat <<'EOF'
Record the repo migration and removal of the Northwoods original

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
git push
```

---

## Execution notes

**Task order and gating:**

- Task 1 must run first — nothing commits correctly until `origin` moves.
- Task 2 produces a deliverable Aaron runs on the console. It gates Tasks 9, 12, and 13, but **not** Tasks 3–8. Build the pure modules while the probe waits for desk time.
- Tasks 3–8 are pure, testable, and need no console.
- Task 10 needs the console-exported XML from Task 2.
- Tasks 12–14 are gated in sequence: desk test → release → delete the old repo.

**If the probe reports `socket: FAIL`:** stop. Do not work around it. The console-hosted design is dead, the Tauri app is still in git history, and the design needs revisiting with Aaron before any more code is written.
