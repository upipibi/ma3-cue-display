# MA3 Cue Display — Project Context

A grandMA3 **Lua plugin** that runs on the console and serves a live cue display
over HTTP to browsers and OBS. No companion app, no OSC. Personal project under
`upipibi`. Stack: **Lua 5.4 + LuaSocket + vanilla HTML/CSS/JS**.

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
- Version left at 2.0.0 (Aaron decides on a bump).
- Feature idea Aaron started designing in that session, paused: also show timecode slots 1 and 2 and the fades
  of every running cue, in one fixed-size frame for a single OBS crop, song and key sequences only. Notes are in
  the MA3 MCP project's CLAUDE.md ("Paused 2026-11-05: Cue Display feature design").
- **Verify:** `./run-tests.sh` (68 passed on both versions), `./build.sh`, `luac5.5 -p dist/MA3CueDisplay.lua`;
  on the console after re-import, `Plugin <n>.1` should read `SYNTAXERROR=false`, `INSTREAM=true`.

## Status — 2026-08-05
- **Stage:** rewritten from the macOS Tauri app to a console-hosted Lua plugin.
  **Built and verified locally; not yet run on real console hardware.**
- **Works (verified):** 68 unit tests green; the built artifact runs end-to-end
  under `./run-fake-console.sh` against a stubbed object model, serving a real
  browser — cues advance, a stopped stack holds its last cue, a never-playing
  sequence never appears, tick loop holds ~19 resumes/sec against 20 Hz. All
  three display modes verified in-browser, including both stale paths.
- **Not yet verified (needs the desk):**
  - **Does LuaSocket exist on console hardware?** Confirmed on onPC/Windows only.
    `probe/` answers this and is the hard gate. If it fails this design is dead,
    and the Tauri app is recoverable from git history (see `7891e1c`).
  - Whether `cue.name` reads correctly on a real show file.
  - How long a full sequence sweep takes on a real show file — that decides
    whether 5 Hz cue polling is safe.
  - Whether the console imports the plugin XML without complaint.
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

  every 4th tick (~5 Hz): ma3.snapshot() -> state.update() -> json.encode(), cached
  every tick:             server.tick() — non-blocking accept/read/respond
    GET /                 display page (full-screen)
    GET /?style=overlay   same page, transparent for OBS
    GET /debug            same page, debug panel
    GET /api/state        cached JSON
    GET /health           ok + version
    GET /favicon.ico      204, so viewers stop retrying a 404
```

Clients poll `/api/state` every 250 ms. No WebSocket — a held-open connection in
a cooperative single-coroutine server is a liability, and 250 ms is invisible on
a cue display.

### Where things live
```
src/json.lua              pure JSON encoder (encode only)
src/state.lua             pure cue-state tracking, most-recently-fired resolution
src/http.lua              pure request parse / route / response
src/server.lua            non-blocking connection state machine, socket-agnostic
src/ma3.lua               the ONLY file touching the grandMA3 object model
src/display.html          the page — all three modes, selected client-side
src/main.lua              plugin entry: bind, tick loop, watchdog, toggle
src/plugin.xml.template   plugin XML; build.sh injects the version
build.sh                  bundles src/ into dist/ via package.preload
run-tests.sh              unit tests under lua@5.4
run-fake-console.sh       runs the built artifact against a fake console
tools/fake-console.lua    the fake object model + yield-honoring scheduler
probe/                    throwaway feasibility plugin, not shipped
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
| Legacy tags | `v1.0.0`, `v1.1.0` belong to the retired Mac app. Do not reuse. |

## Build / Run / Release
```bash
brew install lua@5.4
./run-tests.sh          # must pass before any commit
./build.sh              # -> dist/MA3CueDisplay.lua + .xml
./run-fake-console.sh   # exercise the real artifact with no console
```

A release is two generated text files. No signing, no notarization, no Sparkle,
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
