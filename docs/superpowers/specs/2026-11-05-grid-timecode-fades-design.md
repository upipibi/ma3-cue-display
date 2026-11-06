# MA3 Cue Display: grid view with timecode and fades

**Date:** 2026-11-05
**Status:** approved by Aaron 2026-11-05 ("approved"); built the same evening in the working
tree, verified locally, not released. See "As built" at the bottom.
**Builds on:** `2026-08-04-ma3-cue-display-lua-plugin-design.md` (the plugin as shipped in 2.0.1).
That design deferred a fade bar; this one adds it in a different way (see "Fades").
**Mockups:** `.superpowers/brainstorm/<session>/content/` (local only): `frame-shapes.html`,
`block-eight.html`, `grid-b2.html`, `grid-fixed.html`. The last one is the look to build.

---

## Why

Aaron records and monitors programming in OBS. Today the page shows one cue: the most recently
fired. During a Christmas production song several sequences run at once (the song, its `(key)`
twin, effect sequences fired by timecode), the show runs from timecode, and the cue fades are part
of what he wants to see. He wants one picture that carries all of it and that he can place in OBS
once and never re-crop.

## What Aaron decided (his words)

- Show timecode: "slot 1 and slot 2".
- "the fades for any cue running".
- "it just grids from the center, keeping things tight as we can center".
- "a grid that is a specific size, so that when I have this open in OBS, I know where to place and
  crop and it doesn't change on me"; "just one big piece for one single OBS crop".
- "Ideally it's just song and key sequences".
- From the first mockup: "I think B, but can we have 8 slots of sequences instead of 4" (B = the
  block: timecode on top, sequence boxes below).
- From the second mockup: "B2 please" (1280 x 800, two boxes across, four rows, the larger text).
- From the third: "Can everything stay where it is? ... Can time code always be at the top. Can
  there always be that 4 x 2 grid, just with placeholders until a sequence occupies it? So things
  don't move around and shuffle as sequences fire?"

That last request overrides his earlier "grids from the center": nothing inside the frame moves.

Everything else in this document is Claude's call unless marked otherwise. The calls are listed
together under "Calls made for Aaron".

## Goals

- One new view, the grid, that shows both timecode slots and up to eight running sequences, each
  with its current cue and that cue's fade.
- The frame is exactly 1280 x 800 pixels and never changes size or position, whatever is running
  and whatever the browser window size.
- Nothing inside the frame moves either: the clocks and the eight slots are always in the same
  place, and a sequence stays in the slot it took for as long as it runs.
- The three existing views (`/`, `/?style=overlay`, `/debug`) keep working exactly as they do.

## Non-goals

- Controlling the console. Still read-only.
- A frame-exact timecode reference. The readout is a monitor, good to a frame or two.
- True fade progress as the console computes it (see "Fades" for what is shown instead).
- Choosing the frame size or slot count at runtime. One fixed layout.
- Per-attribute or per-fixture timing, out fades, delays, multi-part cues beyond part 0.

## Anti-goals

- The frame must not move, resize or reflow its outline when sequences start or stop. That is the
  whole reason for the fixed frame.
- A running sequence's box must never change slot, and a start or stop must never move another
  box. Shuffling is the failure Aaron named.
- The new work must not slow the tick loop. No new per-tick sweep of the sequence pool, and no
  blocking call (the standing rule of this project).
- No show-file text through `innerHTML`.

---

## The view

### Address

- `GET /grid`: the frame on the page's dark background.
- `GET /grid?style=overlay`: the same frame with a transparent page and frame background, for an
  OBS Browser source laid over video. Boxes and clocks keep their own dark fill.

The same single `display.html` serves it; the mode is picked client-side from the path, as today.
`http.lua` routes `/grid` to the page the way it routes `/debug`.

### Frame

- 1280 x 800 CSS pixels, fixed. Anchored at the page's top-left corner (0, 0), no margin, so:
  - an OBS Browser source set to 1280 x 800 is exactly the frame, no crop needed;
  - a captured browser window crops to the top-left 1280 x 800 at any window size.
- The frame does not scale with the window. If the window is smaller, the page scrolls; that is
  correct for a crop target.
- Padding 20. Background `#0b0d10` (the existing page colour).

### Contents: fixed positions

Everything is drawn at a fixed place in the frame. Nothing is centred on its content and nothing
reflows.

1. **Clocks row, pinned to the top.** Two clocks side by side, centred horizontally, `TC 1` and
   `TC 2`, always both present, always in the same order. Each: a small uppercase label and the
   time as `HH:MM:SS:FF` in tabular digits (58 px, weight 700). A slot that is not running keeps
   its place, shows its last value in the dim colour, and its label reads `TC 2  stopped`.
2. **The grid: eight slots, always drawn.** Two across, four rows, each 612 x 150, gap 14,
   directly under the clocks. Slots are numbered 1 to 8 left to right, top to bottom
   (1 and 2 on the first row).
   - An **empty slot** is a placeholder: the same outline at the same size, a fainter border, no
     fill, no text.
   - An **occupied slot** shows: the sequence name (small uppercase, muted, one line, ellipsis);
     the cue number (accent colour, 52 px, tabular) and cue name (38 px, weight 600, one line,
     ellipsis); the fade row (a bar and a text).
3. There is no "nothing running" message. With nothing running the frame shows the clocks and
   eight placeholders.

In the overlay style (`?style=overlay`) the placeholders are not drawn, so empty slots do not put
outlines over video; the positions are the same.

Sizes, colours and fonts are those of `grid-fixed.html`. System font stack only, no external
assets, plain 1 px hairline borders, no coloured side accents.

### Which sequences are shown, and where

- A sequence is eligible while `HasActivePlayback()` is true and its number is inside the
  configured range. Default range 1 to 89: on Aaron's shows that is songs, `(key)` twins and the
  song effect sequences, and it excludes house looks, Resolume control, clears and helpers (171
  and up). The range is two numbers in `CONFIG` in `src/main.lua` (`grid_from`, `grid_to`).
- **Slot assignment.** When an eligible sequence is first seen running it takes a slot and keeps
  it until it stops:
  1. if it held a slot earlier in this plugin run and that slot is empty, it goes back to it
     (so a strobe sequence that fires again and again returns to the same place);
  2. otherwise it takes the lowest-numbered empty slot;
  3. if no slot is empty it is not shown, and it takes a slot later if one frees while it is
     still running.
  Several sequences first seen in the same scan are placed in ascending sequence number.
- When a sequence stops, its slot becomes a placeholder on the next scan. No other box moves.
  (The single-cue view keeps showing the last cue of a stopped sequence; the grid does not,
  because a box that stays would lie about what is running.)
- The remembered slot per sequence lasts for the plugin run. It is a preference, never a
  reservation: an empty slot is given to whoever needs it.

### Fades

What the box shows is **the stored fade time of the cue that is current, counted down from the
moment the plugin saw that cue become current.**

- Source: the cue's part 0, property `CUEINFADE` (read through the cue's first child, as the
  MA3 MCP plugin's `ma3_cue_timing` does). A number of seconds. Anything that is not a number
  (a default marker, a missing part) is treated as "no fade information": the bar is hidden and
  the text is empty.
- While counting: the bar fills left to right over the fade time, in the accent colour, and the
  text shows the seconds remaining with one decimal (`2.6 s`).
- When done: the bar is full in a neutral grey and the text reads `fade 4 s` (the cue's fade, as a
  reminder).
- Fade of 0: the bar is full, grey, and the text reads `snap`.
- A sequence that starts running (absent from the previous scan, present in this one) counts as
  a cue firing: its first cue's fade counts down. That is the most common fade of all, the
  `Start` cue of a song.
- A sequence that was already running at the plugin's first scan is shown as done. No invented
  countdown.

Limits, to be stated in the README:

- It is the programmed fade, not the fade the console is executing. It does not follow the
  executor time fader (`USEEXECUTORTIME` is on for Aaron's song sequences), a rate or speed master,
  a manual crossfade, `Go` with a time, or individual preset and attribute timing.
- The start is detected by polling at 5 Hz, so the countdown starts up to 0.2 s late, plus the
  page's own poll (see "Timing on the page").
- Re-firing the cue a sequence is already on (Goto the same cue) is not detected, so the bar does
  not restart. Same limit as the existing change detection.

This replaces the earlier deferred idea of reading executor fader values every tick.

### Timecode

- Slots shown: 1 and 2 (`CONFIG.timecode_slots = { 1, 2 }`).
- Source per slot: the `TimecodeSlot <n>` object, property `TIME`. Read on the console
  2026-11-05: `TIME` is seconds x 2^24 (`120870893431` for `2h00m04:14`), `TIMESTRING` is the
  console's own text (`2h00m04:14`).
- Display format `HH:MM:SS:FF`. Frames from the fraction of a second at the configured rate,
  `CONFIG.timecode_fps = 30` (Aaron's productions run 30 fps; his timecode shows read
  `S1<30 fps>`).
- Running or stopped: a slot is running when `TIME` differs from the previous sample.
- Sampled on every tick (20 Hz), not on the 5 Hz cue scan: it is four property reads, and it keeps
  the readout close to the console.

**Feasibility check, first build step.** When the slot was read three times in a row through the
MA3 MCP plugin it returned the same value; nothing was rolling. Whether `TIME` advances live for a
plugin while timecode rolls is unverified. The first deliverable is a check on the console with
timecode rolling (Aaron rolls it for a few seconds; two reads through the MA3 MCP plugin, or the
plugin's own `/api/state`). If `TIME` does not move, try `TIMESTRING`; if neither moves, stop and
bring the finding to Aaron before building the clocks.

---

## Data

### What `ma3.lua` returns

`ma3.snapshot()` keeps returning the list it returns today (running sequences with name, cue
number, cue name) with three additions per entry, read only for running sequences:

- `number`: the sequence number (`seq.No`).
- `fade`: the current cue's `CUEINFADE` as a number, or nil.
- `cueKey`: a value that identifies the current cue for change detection (the raw cue `No`).

The fade is read only when the cue of that sequence changed since the last scan (cache per
sequence, keyed by sequence handle or number, in the adapter). No extra work on a scan where
nothing fired.

New function `ma3.timecode(self)`: returns `{ { slot = 1, seconds = <number or nil> }, ... }` for
the configured slots. Each read is wrapped in `pcall` like every other console access; a failed
read gives `seconds = nil` and the page shows dashes.

All console access stays in `src/ma3.lua`.

### State (`state.lua`, pure)

`state.update(st, snapshots, now)` keeps its current behaviour for the single-cue fields and
additionally maintains:

- per running sequence, `firedAt`: the time (plugin wall clock) at which its `cueKey` was first
  seen to differ from the previous scan, or at which the sequence appeared. Only on the first
  scan after the plugin starts do running sequences get `firedAt = nil` ("not seen firing").
- `slots[1..8]`: which sequence (by number) holds each slot, and `lastSlot[number]`: the slot a
  sequence held most recently. The assignment rules of "Which sequences are shown, and where" are
  implemented here, in the pure module, so they are unit-tested off the console. The range filter
  is applied here too (the range is passed in from `CONFIG`).

`state.payload` adds two fields; every existing field stays as is, so the three old views and
anything else reading `/api/state` are unaffected:

```json
{
  "sequence": "He Is", "cueNumber": "3", "cueName": "Pre Chorus",
  "activeSequences": ["He Is", "He Is (key)"],
  "updatedAt": 1793923080.123, "version": "2.1.0",
  "grid": [
    { "number": 55, "name": "He Is", "cueNumber": "3", "cueName": "Pre Chorus",
      "fade": 2, "firedAgo": 0.35 },
    { "number": 73, "name": "He Is (key)", "cueNumber": "2", "cueName": "Lead Vox",
      "fade": 1, "firedAgo": null },
    null, null, null, null, null, null
  ],
  "timecode": [
    { "slot": 1, "seconds": 7204.4667, "running": true },
    { "slot": 2, "seconds": 0, "running": false }
  ]
}
```

- `grid` always has exactly eight entries, one per slot in slot order: an object for an occupied
  slot, `null` for an empty one. The page draws entry n in slot n and decides nothing about
  placement.
- `firedAgo` is seconds since the cue fired, computed when the JSON is built
  (`now - firedAt`), or null. An age, not a timestamp, so the console clock and the browser clock
  never have to agree.
- `json.lua` must encode `null` for a nil inside these objects and for an empty slot in the array
  (a Lua table with holes cannot carry that by itself: use an explicit null marker value that the
  encoder writes as `null`), and keep its `%.14g` floats.

### Tick loop (`main.lua`)

- Every tick: `ma3.timecode()`, fold into state, rebuild the cached JSON.
- Every 4th tick (unchanged): the sequence scan and `state.update`.
- The JSON is therefore rebuilt 20 times a second instead of 5. It is a small table; the encoder
  is pure Lua string building. Measure the tick time under `run-fake-console.sh` before and after;
  if it shows, rebuild on timecode change only.

### Timing on the page

The page polls `/api/state` every 250 ms as today and runs a `requestAnimationFrame` loop for the
grid view only.

- **Fade bars.** On each poll, for each box, the page computes a local start time
  `Date.now() - firedAgo * 1000` and keeps it while the box's sequence and cue stay the same
  (it takes the earliest start it has seen for that cue, which is the least delayed sample). The
  bar and the countdown are drawn from that start every frame.
- **Clocks.** For a running slot the page keeps an offset between the console's `seconds` and its
  own clock, taken from the least delayed recent sample (the largest `seconds - localNow` over the
  last few polls), and draws `localNow + offset` every frame. If the reported value departs from
  the extrapolation by more than half a second (a jump, a locate, a loop), it re-bases at once.
  A stopped slot shows the reported value as is.
- Expected accuracy: within a frame or two of the console for timecode, within about a quarter of
  a second for the start of a fade.
- **Stale.** The existing rules apply to the grid: if the console stops answering or `updatedAt`
  stops moving for 2 s, the frame dims and the existing message shows. Clocks stop extrapolating
  when stale.

---

## Testing

- `tests/test_state.lua`: slot assignment (range filter; lowest empty slot; a running sequence
  never changes slot when others start and stop; a stopped sequence frees its slot and nothing
  else moves; a returning sequence gets its old slot when empty and the lowest empty one when
  not; a ninth sequence waits and is placed when a slot frees; same-scan arrivals in number
  order); `firedAt` set on a cue change and when a sequence starts, nil for sequences already
  running at the first scan; existing single-cue behaviour unchanged.
- `tests/test_ma3.lua`: `number`, `fade` (number, non-number, missing part), fade read only on
  change (count the reads on the fake), `timecode()` with a good and a failing slot.
- `tests/test_json.lua`: null inside objects, nested arrays of objects, an array of eight with
  nulls in any position.
- `tests/test_http.lua`: `/grid` and `/grid?style=overlay` serve the page.
- `tools/fake-console.lua`: a second and third running sequence, cues with different fades, two
  timecode slots (one rolling), so `./run-fake-console.sh` shows the grid alive in a browser.
- Both Lua versions, 5.5 first, as `run-tests.sh` already does.
- In a browser against the fake console: the frame measures 1280 x 800 at three window sizes; the
  clocks and every slot keep the same pixel position with zero, one, five and eight sequences and
  through starts and stops; a long cue name; a fade of 0; the stale state; the overlay background
  is transparent and draws no placeholders.
- On the console (Aaron): a song and its key running from timecode; compare the clock with the
  console's own timecode window; compare a 4 s fade by eye.

## Build order

1. The timecode feasibility check on the console (needs Aaron to roll timecode briefly).
2. `ma3.lua`, `state.lua`, `json.lua`, `http.lua` with their tests.
3. The grid view in `display.html`, checked against the fake console.
4. README (URL table, OBS setup for the grid, the fade and timecode limits), CLAUDE.md.
5. Build, Aaron imports and tests on the console. The version number is his call at release
   (suggestion: 2.1.0, a new view).

## Calls made for Aaron (not his words)

- The address `/grid`, and that the old views stay untouched.
- The frame is anchored top-left and does not scale.
- Sequence range 1 to 89.
- How a sequence gets its slot: its previous slot if empty, else the lowest empty one; a ninth
  sequence waits. Slots numbered left to right, top to bottom.
- A stopped sequence's slot goes back to a placeholder at once (it does not hold its last cue).
- Placeholders are faint empty outlines, and are not drawn in the overlay style.
- Timecode as `HH:MM:SS:FF` at 30 fps; a stopped slot greyed in place.
- The fade shown is the cue's stored in-fade from part 0, counted from when the plugin sees the
  cue fire; `snap` for 0; no delay, no out fade.
- A sequence already running when the plugin starts shows its fade as done; a sequence that
  starts later counts down its first cue's fade.
- Timecode sampled at 20 Hz, cues at 5 Hz as today.

## Risks

| Risk | Mitigation |
|---|---|
| `TIME` does not advance for a plugin while timecode rolls | First build step is the check; fall back to `TIMESTRING`; stop if neither moves |
| The fade shown differs from what the console does (executor time, rate master) | Stated in the README and on approval; the bar is labelled with the programmed fade |
| 20 Hz JSON rebuild costs tick time | Measure on the fake console; rebuild only when timecode changed |
| The sequence sweep cost on a real show (already open in the 2.0 design) | Unchanged by this work; the fade read is cached per cue change |
| More than eight sequences in range | The ninth waits for a free slot; range is configurable |

## As built (2026-11-05)

- Built as designed. Plan: `docs/superpowers/plans/2026-11-05-grid-timecode-fades.md`.
- The payload also carries `timecodeFps` (from `CONFIG.timecode_fps`), so the page does not
  hard-code the frame rate.
- The JSON is rebuilt every tick. Measured on the build Mac: about 74 microseconds with a full
  grid; the fake console holds the same resume rate with and without the grid.
- The sequence number is read as `seq.No`, with `seq:Get("NO")` as a fallback.
- The feasibility check for timecode (build order step 1) has not been run: it needs timecode
  rolling on the console. The clocks were built against `TIME`; if it does not move for a
  plugin, the fallback is `TIMESTRING`.
- Verified locally: 111 unit tests on Lua 5.5 and 5.4; headless Chrome against the fake console
  for 52 s (frame 0,0,1280,800 at three window sizes, slot and clock rectangles identical in
  every sample, no sequence changed slot, clock steps of one frame with no backward step, the
  locate re-based at once, overlay transparent, stale state, old views unchanged).
- 2026-11-06, first console import: the plugin shut itself down after ten failed ticks. Cause:
  the bundle resolved modules through `package.preload`, and the console's shared
  `package.loaded` still held 2.0's modules from earlier in the session. Not a design fault of
  the grid; the bundler now carries a private module table. The data reads themselves were then
  proven on the console (sequence number, fade through part 0, `TIME`).
