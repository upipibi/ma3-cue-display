# MA3 Cue Display — Project Context

A grandMA3 **Lua plugin** that runs on the console and serves a live cue display
over HTTP to browsers and OBS. No companion app, no OSC. Personal project under
`upipibi`. Stack: **Lua 5.5 (the console's version; 5.4 as a check) + LuaSocket + vanilla HTML/CSS/JS**.

> **Read first:** [README.md](README.md) for install and OBS setup.
> Design rationale: [docs/superpowers/specs/2026-08-04-ma3-cue-display-lua-plugin-design.md](docs/superpowers/specs/2026-08-04-ma3-cue-display-lua-plugin-design.md)
> Build plan: [docs/superpowers/plans/2026-08-04-ma3-cue-display-lua-plugin.md](docs/superpowers/plans/2026-08-04-ma3-cue-display-lua-plugin.md)

---

## Out-of-session changes

### 2026-11-05 — work done from MA3 MCP

- Aaron imported 2.0.0 on the console (grandMA3 2.5.1.1, show `Christmas 2026`, Plugin 38). The console
  flagged `SYNTAXERROR` on the component and treated the plugin as a library resource, not showfile data.
- Fixed `src/server.lua` `read_pass`: it assigned to `_`, the enclosing loop's control variable. The
  console runs **Lua 5.5** on 2.5 (not 5.4.4), where that is a syntax error.
- `src/plugin.xml.template` now uses the plain form proven with the MA3 MCP plugin the same day:
  `DataVersion="2.5.1.1"`, bare `ComponentLua` with no `Installed` / `LoadOnDemand`. With those two
  attributes the console read `ISRESOURCE=true`, `INSTREAM=false`, path `shared/resource/lib_plugins`.
- `run-tests.sh` and `build.sh` now run on Lua 5.5 first and 5.4 as a check. `run-fake-console.sh` is
  still pinned to 5.4 (its LuaSocket rock is installed for 5.4 only).
- Re-imported on the console the same day as `Plugin 38` and verified: `SYNTAXERROR=false`, `INSTREAM=true`,
  `ISRESOURCE=false`, `/health` answers `ok 2.0.0`, `/api/state` returns JSON. So LuaSocket exists on console
  hardware and the plugin XML imports (two items the Status block below still lists as unverified).
- Released as 2.0.1 the same evening on Aaron's word (GitHub release `v2.0.1`, zip with the two plugin files).
  The copy on the console still reports 2.0.0 until it is imported again; the code is the same.
- Feature Aaron designed from that session and approved the same evening: the grid view (see Status).
  It was built in the working tree from the MA3 MCP session; the conversation record is in that
  project's CLAUDE.md. Browser mockups live in `.superpowers/brainstorm/` here (git-ignored).
- **Verify:** `./run-tests.sh` (68 passed on both versions), `./build.sh`, `luac5.5 -p dist/MA3CueDisplay.lua`;
  on the console after re-import, `Plugin <n>.1` should read `SYNTAXERROR=false`, `INSTREAM=true`.

### 2026-11-06 — work done from MA3 MCP

- Built the grid view Aaron designed and approved ("approved", 2026-11-05): `/grid`, a fixed 1280 x 800
  frame with timecode slots 1 and 2 and eight fixed sequence slots with cue fades. Spec and plan are in
  `docs/superpowers/`. He chose the version ("Sure! 2.1.0").
- The first 2.1.0 build shut itself down on the console: the bundle used `package.preload`, and the
  console's shared `package.loaded` served it 2.0's modules. `build.sh` now gives the bundle a private
  module table; its verify step and `tools/fake-console.lua` plant stale modules so this fails on the Mac.
- The rebuilt 2.1.0 was imported by Aaron and runs on the console (`/health` = `ok 2.1.0`, `/grid` serves),
  stored in the show file, show saved. Committed and pushed from that session; no GitHub release yet.
- Not yet seen on the console: timecode rolling and a song running in the grid. Aaron plans that for
  Sunday 2026-11-08.
- **Verify:** `./run-tests.sh` (111 passed on both Lua versions), `./build.sh` ("own modules resolved in a
  dirty Lua state"), `./run-fake-console.sh 60 grid` then open `http://127.0.0.1:8090/grid`.

## Status — 2026-11-06
- **Stage:** 2.0.1 is the last GitHub release; 2.1.0 runs on a grandMA3 light (2.5.1.1), stored in the show file.
- **2.1.0 runs on the console (imported 2026-11-06), no GitHub release yet: the grid view**
  (`/grid`): a fixed
  1280 x 800 frame with timecode slots 1 and 2 and eight fixed sequence slots, each with its cue
  and the cue's fade. Design: `docs/superpowers/specs/2026-11-05-grid-timecode-fades-design.md`;
  plan: `docs/superpowers/plans/2026-11-05-grid-timecode-fades.md`. Aaron chose the version
  ("Sure! 2.1.0"); `build.sh` says 2.1.0. No GitHub release yet. Verified locally: 111 unit tests on Lua 5.5 and 5.4,
  and a headless-browser run against `./run-fake-console.sh 75 grid` (frame rectangle, no slot
  ever moves, clocks, fades, overlay, stale, old views unchanged). **Not yet verified on the
  console:** that a `TimecodeSlot`'s `TIME` advances for a plugin while timecode rolls (needs
  Aaron to roll timecode). Proven on the console 2026-11-06 by running the real `json`, `state`
  and `ma3` modules through the MA3 MCP plugin's Lua tool for twelve ticks: `seq.No` and
  `Get("NO")` both give the number, the fade reads through the cue's part 0 (`0.0`, a float),
  `TIME` reads as an integer, the payload encodes. The first 2.1.0 build failed on the desk for
  a different reason, the shared `package.loaded` (see Conventions); the rebuilt 2.1.0 runs
  there (`/health` = `ok 2.1.0`, grid empty and clocks stopped with nothing in range running).
- **Works (verified on the console, 2026-11-05):** LuaSocket exists on console hardware; the plugin
  XML imports through the GUI and the code lands in the show file with no manual step
  (`INSTREAM=true`); the plugin starts, `/health` answers and `/api/state` returns JSON; the page
  opens in a browser on the network.
- **Works (verified locally):** 68 unit tests green on Lua 5.5 and 5.4; the built artifact runs
  end-to-end under `./run-fake-console.sh` against a stubbed object model, serving a real browser —
  cues advance, a stopped stack holds its last cue, a never-playing sequence never appears, tick
  loop holds ~19 resumes/sec against 20 Hz. All three display modes verified in-browser.
- **Not yet verified (needs a running show):**
  - Whether `cue.name` reads correctly while sequences play on a real show file (the console was
    idle when checked: `activeSequences` empty).
  - How long a full sequence sweep takes on a real show file — that decides whether 5 Hz cue
    polling is safe.
  - Survival of a console restart with the USB stick removed.
- **Known limitations:**
  - **No auto-start on a console.** One macro press per session. `RUNPLUGIN` is
    onPC-only and there is no supported on-show-load hook.
  - **MA disclaims plugin support** and warns plugins may need rewriting on a
    software upgrade. `src/ma3.lua` is kept thin so that lands in one file.

## Architecture

One Lua coroutine, 20 Hz tick loop, `coroutine.yield(0.05)` every tick.

```
plugin "MA3CueDisplay" — single component, acts as a TOGGLE
  press while stopped -> bind port, run the loop
  press while running -> flip GlobalVars flag; loop exits on its next tick

  every tick (20 Hz):     ma3.timecode() -> state.update_timecode()   (two property reads)
  every 4th tick (~5 Hz): ma3.snapshot() -> state.update()            (the sequence sweep)
  every tick:             state.payload() -> json.encode(), cached
  every tick:             server.tick() — non-blocking accept/read/respond
    GET /                 display page (full-screen)
    GET /?style=overlay   same page, transparent for OBS
    GET /grid             same page, fixed 1280 x 800 grid (?style=overlay: transparent)
    GET /debug            same page, debug panel
    GET /api/state        cached JSON
    GET /health           ok + version
    GET /favicon.ico      204, so viewers stop retrying a 404
```

The grid view decides nothing in the browser about what goes where. `state.lua` assigns the
eight slots (a running sequence keeps its slot; a stopped one frees it; a returning one prefers
its old slot) and records when each cue fired; the payload's `grid` is always eight entries,
an object or `null`. The page draws entry n in slot n and runs its own clock between polls so
the timecode and the fade bars move smoothly.

Clients poll `/api/state` every 250 ms. No WebSocket — a held-open connection in
a cooperative single-coroutine server is a liability, and 250 ms is invisible on
a cue display.

### Where things live
```
src/json.lua              pure JSON encoder (encode only)
src/state.lua             pure cue-state tracking: most-recently-fired resolution, grid slot
                          assignment, cue fire times, timecode running state
src/http.lua              pure request parse / route / response
src/server.lua            non-blocking connection state machine, socket-agnostic
src/ma3.lua               the ONLY file touching the grandMA3 object model
src/display.html          the page — all four modes (full, overlay, grid, debug), selected client-side
src/main.lua              plugin entry: bind, tick loop, watchdog, toggle
src/plugin.xml.template   plugin XML; build.sh injects the version
build.sh                  bundles src/ into dist/ with a private module table (never package.*)
run-tests.sh              unit tests under lua@5.4
run-fake-console.sh       runs the built artifact against a fake console
tools/fake-console.lua    the fake object model + yield-honoring scheduler; `grid` scenario for /grid
probe/                    throwaway feasibility plugin, not shipped
```

## Key identifiers
| Thing | Value |
|---|---|
| Type / stack | grandMA3 Lua plugin — Lua 5.5 on the console (5.4 kept as a check) + LuaSocket, vanilla frontend |
| GitHub repo | `upipibi/ma3-cue-display` (public) |
| Current version | 2.1.0 in `build.sh` (last GitHub release: 2.0.1) |
| Ports | 8090 HTTP (configurable in `src/main.lua`) |
| Host | grandMA3 console |
| Secrets | none |
| Legacy tags | `v1.0.0`, `v1.1.0` belong to the retired Mac app. Do not reuse. |

## Build / Run / Release
```bash
brew install lua@5.5 lua@5.4
./run-tests.sh          # must pass before any commit (runs on 5.5, then 5.4)
./build.sh              # -> dist/MA3CueDisplay.lua + .xml
./run-fake-console.sh   # exercise the real artifact with no console
```

A release is two generated text files, zipped as `MA3CueDisplay-<version>.zip` on a GitHub release
tagged `v<version>` (first one: `v2.0.1`). No signing, no notarization, no Sparkle,
no `xattr -cr`, no Gatekeeper. That whole class of problem left with the Mac app.

`dist/` is fully gitignored — both artifacts are generated, and the XML comes
from a tracked template.

## Conventions & gotchas
- **Never block a socket call.** `settimeout(0)` everywhere. MA3 plugins are
  coroutines on the console's UI thread; a blocking `accept()` or `receive()`
  freezes the desk. This is the single most important rule in the project.
- **Accepted clients go on a pending queue, re-polled across ticks.** With
  `settimeout(0)` the request bytes usually have not arrived in the same tick as
  the accept, and LuaSocket returns already-consumed bytes in `receive`'s third
  return value — they are lost unless accumulated.
- **The bundle never touches `package.preload` or `package.loaded`.** On a console they are
  shared by every plugin and keep whatever was loaded earlier in the session: the previous
  version of this plugin, another plugin's modules, the console's own `json`. Everything up to
  the first 2.1.0 build used `package.preload`; `require` then returned the modules of the
  version loaded earlier that session. 2.0.x got away with it (the modules had not changed);
  2.1.0 ran 2.0's `state`, found no `update_timecode`, failed on every tick and shut itself down
  (2026-11-06, on the desk). `build.sh` now gives the bundle a private module table and its own
  `require`; its verify step and `tools/fake-console.lua` both plant stale modules first, so a
  regression fails on the Mac. The version is a local in the bundle, not a global.
- **The console runs Lua 5.5 on grandMA3 2.5** (`_VERSION = "Lua 5.5"`, read on 2.5.1). Tests and the
  build verify on 5.5 first, then 5.4. 5.5 makes for-loop control variables read-only: never assign
  to `_` (or any loop variable) inside its loop. 2.0.0 did, passed on 5.4, and failed on the desk.
- **All MA3 API access stays in `src/ma3.lua`.** `src/main.lua` may use
  `Printf`/`GetVar`/`SetVar`/`GlobalVars` only. Keeping the pure modules free of
  console globals is what makes them testable off-console.
- **`Printf` takes a format string.** Always call it as `Printf("%s", text)` — a
  cue name containing `%` would otherwise break it.
- **Cue numbers come from `cue.No / 1000`.** `cue.index` truncates 12.5 to 12.
- **JSON floats use `%.14g`, not `%.6g`.** At 6 significant digits a Unix
  timestamp collapsed to `1.78595e+09` and stayed byte-identical for hours.
  Viewers treat `updatedAt` as the console's heartbeat, so that made a healthy
  console read as wedged. Regression tests pin it.
- **`updatedAt` is regenerated every scan, not only when the cue changes.** It is
  the heartbeat; a frozen value is a failure signal.
- **Cue-change hooks do not work.** `HookObjectChange` on sequences fires only on
  edits, not playback; `HasActivePlayback()` is a function so it cannot be
  hooked; hooking `Root().Temp.RunningSequences` reportedly needs the Running
  Sequences window open on a physical screen. Polling is the only reliable path.
- **The plugin is a toggle, not Start/Stop.** A `ComponentLua` points at its own
  `FileName`, so two components would mean two `.lua` files and two macros.
- **Plugin XML is `GMA3 > Plugin > ComponentLua`.** Verified against two real
  exported plugins in public repos, not guessed. The `Plugin Version` attribute is 4-part
  (`2.0.0.0`). Keep `ComponentLua` bare (`Name` + `FileName` only): with `Installed="Yes"
  LoadOnDemand="Yes"` the console imported it as a library resource that cannot live in the showfile.
- **`src/display.html` must never contain `]==]`** — it is embedded in a Lua long
  string. `build.sh` fails the build if it does.
- **No external assets in the page.** The console has no internet route; a
  webfont or CDN script would block paint and then fail. `build.sh` enforces it.
- **`json.null` marks a null inside a table.** Lua tables cannot hold nil, so an empty grid
  slot or an unknown fade is `json.null`; the encoder writes it as `null`.
- **Grid rules live in `src/state.lua`, not in the page.** A running sequence never changes
  slot and a start or stop never moves another box: that is the reason the view exists (Aaron:
  "So things don't move around and shuffle as sequences fire"). Tests pin it.
- **A `TimecodeSlot`'s `TIME` is seconds x 2^24.** Read on the console 2026-11-05
  (`120870893431` while the slot showed `2h00m04:14`).
- **The grid's fade is the programmed fade**, part 0 `CUEINFADE`, read once per cue change and
  counted from when the plugin sees the cue fire. It does not follow executor time or a rate
  master. Say so wherever the bar is described.
- **A sequence already running at the plugin's first scan gets no countdown**; one that starts
  later counts its first cue's fade.
- **Never `innerHTML` show-file text.** Cue and sequence names are untrusted
  input. The debug panel builds its lists with `textContent`.

## Update Protocol
| When you… | Update… |
|---|---|
| ship a version | Status date · version in `build.sh` · README |
| add or rename a route | Architecture · README URL table |
| change how cue state is read | `src/ma3.lua` · Conventions & gotchas |
| hit and fix a gotcha | Conventions & gotchas |
| get probe results from the desk | Status block — move items out of "not yet verified" |

## Document history
| Date | Change |
|---|---|
| 2026-05-29 | Initial CLAUDE.md to Northwoods standard, for the Tauri macOS app |
| 2026-08-05 | Rewritten for the console-hosted Lua plugin; moved to `upipibi`; version 2.0.0 |
| 2026-11-05 | First console import failed (Lua 5.5 syntax error, resource-form XML); fixed from the MA3 MCP session, see Out-of-session changes |
| 2026-11-05 | Released 2.0.1; Status rewritten for what the console run proved |
| 2026-11-05 | Grid view built (timecode + fades, fixed slots); not released, console checks pending |
| 2026-11-06 | First 2.1.0 build shut itself down on the desk: stale modules from the shared `package.loaded`. Bundler rewritten with a private module table |
