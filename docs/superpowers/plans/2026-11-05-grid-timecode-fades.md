# Grid View (Timecode + Fades) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a fixed 1280 x 800 `/grid` view to MA3 Cue Display that shows timecode slots 1 and 2 and up to eight running sequences in fixed slots, each with its cue and that cue's fade.

**Architecture:** `ma3.lua` (the only console-touching file) reads sequence number, cue fade and timecode. `state.lua` (pure) owns slot assignment, fire times and timecode running state, and emits two new payload fields. `display.html` gains a grid mode that draws what the payload says and animates clocks and fade bars between polls.

**Tech Stack:** Lua 5.5 (5.4 as a check), LuaSocket on the console, vanilla HTML/CSS/JS. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-05-grid-timecode-fades-design.md`

## Global Constraints

- Frame exactly 1280 x 800 CSS px, anchored at page top-left, never scales.
- Clocks pinned to the top; eight slots always drawn, 2 across x 4 rows, each 612 x 150, gap 14, frame padding 20.
- A running sequence never changes slot; a start or stop never moves another box.
- Sequence range default 1 to 89 (`grid_from`, `grid_to`); timecode slots `{1, 2}`; 30 fps.
- `TIME` on a `TimecodeSlot` is seconds x 2^24 (16777216).
- Existing views (`/`, `/?style=overlay`, `/debug`) and existing payload fields unchanged.
- All console access in `src/ma3.lua`, every call in `pcall`. Never block. Never assign to a loop variable (Lua 5.5).
- `src/display.html`: no `]==]`, no external URL, show-file text only through `textContent`.
- No commits: Aaron commits through `/save`. Each task ends with `./run-tests.sh` green on both Lua versions instead.
- `VERSION` in `build.sh` is not changed by this plan (Aaron's call at release).

## Review Focus

1. A sequence starts and stops many times a second (strobe hits): its slot must come back to the same place and no other box may move. Test in Task 2.
2. Nine or more sequences in range: the ninth must wait and appear when a slot frees, never evict. Test in Task 2.
3. A cue whose fade is not a number, or a cue with no part: no bar, no crash. Test in Task 3 and page check in Task 5.
4. A timecode slot that cannot be read, or a sample that repeats for one tick while rolling: dashes, and no one-tick "stopped" flicker. Tests in Tasks 2 and 3.
5. Timecode jumps (locate, loop back to zero): the page clock must re-base at once, not glide. Page check in Task 5.

---

### Task 1: JSON null marker and the `/grid` route

**Files:** Modify `src/json.lua`, `src/http.lua`; Test `tests/test_json.lua`, `tests/test_http.lua`

**Interfaces:** Produces `json.null` (a unique table value that `json.encode` writes as `null`, legal inside arrays and objects); `http.route` serves `ctx.html` for path `/grid`.

- [ ] Tests: `json.encode({ 1, json.null, 3 }) == '[1,null,3]'`; an array of eight `json.null` encodes as eight `null`; `json.encode({ a = json.null }) == '{"a":null}'`; `/grid` and `/grid` with query `style=overlay` return the same body as `/`.
- [ ] Run `./run-tests.sh`, expect the new tests to fail.
- [ ] Implement: `M.null = setmetatable({}, { __tostring = function() return "null" end })`, checked first in the table branch of `encode`; add `p == "/grid"` to the page route.
- [ ] `./run-tests.sh` green on both versions.

### Task 2: Slots, fire times and timecode state (`state.lua`)

**Files:** Modify `src/state.lua`; Test `tests/test_state.lua`

**Interfaces:**
- Consumes snapshot entries `{ name, cueNumber, cueName, number?, cueKey?, fade? }` (Task 3 adds the last three; entries without `number` are ignored by the grid).
- Produces:
  - `state.new(opts)`, `opts = { grid_from = 1, grid_to = 89, slots = 8 }`, all optional.
  - `state.update(st, snapshots, now)`; `now` optional (old callers), seconds.
  - `state.update_timecode(st, samples, now)`, `samples = { { slot = n, seconds = number|nil }, ... }`.
  - `state.payload(st, version, now)` adds `grid` (exactly `slots` entries, object or `json.null`), `timecode` (`{ slot, seconds (number or json.null), running }` in sample order) and keeps every old field.
  - Grid object: `{ number, name, cueNumber, cueName, fade (number or json.null), firedAgo (seconds, or json.null) }`.

Rules (from the spec, "Which sequences are shown, and where" and "Fades"):
- Eligible: `number` within range. Free the slot of any sequence not in this scan first.
- Unplaced eligible sequences, ascending `number`: previous slot (`lastSlot[number]`) if empty, else lowest empty slot, else unplaced.
- `firedAt[number] = now` when the sequence was absent last scan (except on the very first scan: nil) or its `cueKey` (fallback `cueNumber`) changed. `firedAgo = max(0, now - firedAt)`.
- Timecode: `running` is true while `seconds` changed within the last 0.25 s; a nil sample gives `seconds = json.null`, `running = false`.

- [ ] Tests (one `it` each): range filter (0, 90, 171 excluded; 1 and 89 included); two arrivals in one scan placed by number in slots 1 and 2; a later arrival takes slot 3; stopping slot 1's sequence leaves slots 2 and 3 untouched and slot 1 `json.null`; the stopped sequence returns to slot 1; if slot 1 was taken meanwhile it gets the lowest empty one; nine running: the ninth absent, placed when one stops; 50 start/stop cycles of one sequence among three: the other two never change slot; first scan `firedAgo` is `json.null`; a sequence starting on a later scan has `firedAgo == 0` then grows with `now`; cue change resets it; `fade` nil becomes `json.null`; snapshots without `number` leave `grid` all null and the old single-cue tests still pass; timecode: changing samples give running true, one repeated sample within 0.25 s stays true, repeats beyond 0.25 s give false, nil sample gives `json.null` and false; `payload` keeps `sequence`, `cueNumber`, `cueName`, `activeSequences`, `updatedAt`, `version`.
- [ ] Run, expect failures. Implement. `./run-tests.sh` green.

### Task 3: Console reads (`ma3.lua`)

**Files:** Modify `src/ma3.lua`; Test `tests/test_ma3.lua`

**Interfaces:**
- `ma3.new(api)`: `api.sequences()` as today; new `api.slot(n)` returning the `TimecodeSlot n` object, default `function(n) return ObjectList("TimecodeSlot " .. n)[1] end`.
- `ma3.snapshot(self)` entries gain `number = tonumber(seq.No)`, `cueKey = cue.No` (raw), `fade = tonumber(part:Get("CUEINFADE"))` where `part = cue:Ptr(1)`; `fade` is nil when anything in that chain fails or is not a number.
- The fade is read only when `cueKey` for that `number` differs from the adapter's cache (`self.fades[number] = { key, fade }`).
- `ma3.timecode(self, slots)` returns `{ { slot = n, seconds = raw / 16777216 or nil }, ... }` reading `slot:Get("TIME")`; slot handles cached in `self.slots`, dropped when a read fails.

- [ ] Tests: `number`, `cueKey`, `fade` present for a playing sequence; fade `"CueTiming"` and a cue without parts give nil fade and the entry is still returned; two snapshots on the same cue call `Get("CUEINFADE")` once, a cue change calls it again; `timecode({1,2})` converts `120870893431` to `7204.4667` (within 0.001) and returns `seconds = nil` for a slot whose `Get` throws or whose lookup returns nil, then retries the lookup next call; existing tests untouched.
- [ ] Run, expect failures. Implement. `./run-tests.sh` green.

### Task 4: Tick loop and fake console

**Files:** Modify `src/main.lua`, `tools/fake-console.lua`, `run-fake-console.sh`

**Interfaces:** Consumes Tasks 1 to 3. `CONFIG` gains `grid_from = 1`, `grid_to = 89`, `timecode_slots = { 1, 2 }`, `timecode_fps = 30`. Payload gains top-level `timecodeFps`.

- [ ] `main.lua`: `state.new` with the range; every tick `state.update_timecode(st, ma3.timecode(adapter, CONFIG.timecode_slots), clock())` and rebuild `ctx.state_json`; every 4th tick the sequence scan with `clock()` passed to `state.update`. `report_urls` prints the `/grid` address.
- [ ] `tools/fake-console.lua`: third argument `grid` selects a grid scenario and leaves the default scenario exactly as it is. Grid scenario: sequences get `No`; cues get `Ptr(1)` returning a part with `Get("CUEINFADE")`; `He Is` (55) advancing every 3 s through fades 4, 2, 2, 0, 0, 4, 8, 2, 15; `He Is (key)` (73) every 5 s; `Ladders` (39) and `R1 Strobe` (37) switching on and off; one cue with fade `"CueTiming"`; `Main House` (171) running and out of range; global `ObjectList` answering `TimecodeSlot 1` (rolling from 7204.4667 s on the wall clock, jumping back to 3600 s once after 40 s) and `TimecodeSlot 2` (still at 0). `run-fake-console.sh [seconds] [scenario]` passes it through.
- [ ] Verify: `./build.sh`; `./run-fake-console.sh 20 grid` in the background; `curl -s http://127.0.0.1:8090/api/state` twice 1 s apart shows `grid` with 8 entries, `timecode[0].seconds` advanced by about 1, `timecode[1].running` false, `/health` ok; default scenario `./run-fake-console.sh 10` still exits cleanly. Report resumes per second against the 20 Hz target.

### Task 5: The grid view (`display.html`)

**Files:** Modify `src/display.html`

**Interfaces:** Consumes the payload of Tasks 2 and 4. Mode `grid` when `location.pathname === "/grid"`; body class `grid`, plus `gridclear` when `style=overlay`.

Look: `.superpowers/brainstorm/*/content/grid-fixed.html` (colours `--frame #0b0d10`, `--box #14181d`, `--line #2a3038`, placeholder border `#1b1f25`, accent `#009CDE`; clock digits 58 px / 700; cue number 52 px; cue name 38 px / 600; sequence label 14 px uppercase; bar 8 px; fade text 17 px).

- [ ] Markup and CSS: a `#grid` frame (hidden outside grid mode; `.stack` hidden in grid mode), `position: absolute; left: 0; top: 0; width: 1280px; height: 800px`, clocks row then an 8-cell CSS grid `612px 612px`. Body in grid mode: no padding, no flex centring, `overflow: auto`. `gridclear`: body and frame transparent, empty slots invisible. Stale: frame at 0.25 opacity; the offline message sits inside the frame's bottom edge in grid mode.
- [ ] Script: build the 2 clocks and 8 slots once with `createElement`. On each poll store `grid`, `timecode`, `timecodeFps`. A `requestAnimationFrame` loop (grid mode only) draws:
  - clocks: `HH:MM:SS:FF`, frames `floor(frac * fps)`; `--:--:--:--` when `seconds` is null; running slot extrapolates from the least delayed of the last 8 samples (largest `seconds - localSeconds`), re-bases when a sample departs from the extrapolation by more than 0.5 s, freezes when stale; stopped slot shows the sample, dim, label `TC n  stopped`.
  - slots: null entry is an empty placeholder; else name, cue number, cue name via `textContent`; fade start per slot kept while `number` and `cueNumber` are unchanged, taking the earliest `Date.now() - firedAgo * 1000`, and replaced when a new estimate is more than 500 ms later (a re-fire); `firedAgo` null draws done; fade null hides bar and text; fade 0 reads `snap`; counting reads remaining seconds with one decimal; done reads `fade N s` (N trimmed to at most two decimals).
- [ ] Verify in headless Chrome against `./run-fake-console.sh 90 grid` (screenshots at window widths 1280, 1600, 900): frame rectangle is 0,0,1280,800 in all three; slot rectangles identical across a start and a stop; a counting bar, a `snap`, a hidden bar (the `CueTiming` cue), a stopped clock, the jump back to 01:00:00 re-bases; `/grid?style=overlay` has a transparent background; `/`, `/?style=overlay`, `/debug` render as before; stale state after the harness exits.

### Task 6: Docs

**Files:** Modify `README.md`, `CLAUDE.md`, the spec's status line

- [ ] README: URL table rows for `/grid` and `/grid?style=overlay`; OBS setup (Browser source 1280 x 800, or crop a window to the top-left 1280 x 800); what the fade bar is and is not; timecode accuracy; the range and slot rule; fake-console `grid` scenario.
- [ ] CLAUDE.md: Architecture (routes, 20 Hz timecode sample), Where things live, Conventions (json.null, slot rules live in `state.lua`), Status (built, verified locally, console items not yet verified: `TIME` live while rolling, `seq.No`, `CUEINFADE` through `Ptr(1)`).
- [ ] Spec status: built, with an "As built" note for anything that diverged.
- [ ] Final: `./run-tests.sh`, `./build.sh`, `luac5.5 -p dist/MA3CueDisplay.lua` if `luac5.5` exists.

## Console checks that need Aaron (after the build)

1. Timecode rolling for a few seconds: read `TimecodeSlot 1` twice through the MA3 MCP plugin; `TIME` must differ. If not, try `TIMESTRING`; if neither, stop and report.
2. Import the build, start it, open `/grid` with a song and its key running from timecode.
