# MA3 Cue Display — console-hosted Lua plugin

**Date:** 2026-08-04
**Status:** approved design, not yet implemented
**Replaces:** the macOS Tauri app (v1.0.1) entirely
**Version of the new product:** 2.0.0 (see Versioning)

---

## Problem

The current product is a macOS menu-bar app (Tauri 2, Rust + vanilla JS) that receives OSC
over UDP from a grandMA3 console, parses the cue out of an OSC string, and serves a live cue
display on port 3000 for browsers and OBS.

It works, but it costs a whole second machine and a chain of setup that has to be right every
time: a Mac on the lighting network, OSC output configured on the console pointed at that Mac's
IP, an unsigned app the user must `xattr -cr` past Gatekeeper, no auto-update, and a fragile
regex that reverse-engineers `"SequenceName CueNum CueName"` out of an OSC argument.

**Goal:** the console hosts the display itself. A tech installs a plugin, presses one button,
and any browser or OBS instance on the network can open the cue display. No second machine,
no OSC configuration, no app to sign or update.

## Non-goals

- Controlling the console from the browser. This is read-only display. MA3's own Web Remote
  on `:8080` already does remote control, and competing with it is out of scope.
- Fade-progress bar (deferred — see Deferred).
- Supporting onPC as a first-class target. It will probably work, but the console is the
  design target and the only platform that gets tested.
- Auto-update. There is no update mechanism for MA3 plugins; new versions are re-imported.

---

## Feasibility gate (build this first)

Everything below depends on facts that cannot be verified without grandMA3 hardware. Research
confirmed LuaSocket works on grandMA3 **onPC for Windows** — a forum author has a working
`socket.bind("*", 8956)` listening server in an MA3 plugin — but explicitly noted that
**console and Mac were untested.** No source anywhere confirms LuaSocket ships on the Linux
console image.

So the first deliverable is a throwaway probe plugin, `MA3CueDisplay-Probe`, which `Printf`s:

| Probe check | Why it gates the design |
|---|---|
| MA3 software version | API surface differs between versions |
| `require("socket")` succeeds + `socket._VERSION` | **Hard blocker.** No LuaSocket, no console-hosted server. |
| `socket.bind("*", 8090)` succeeds, then closes | Confirms the console permits a listening socket |
| `cue.name` exists alongside the confirmed `cue.No` | Cue name is half the display; only `cue.No` is documented |
| `os.clock()` around a full `DataPool().Sequences:Children()` scan on the real show file | Sets the safe cue-poll rate. Drives the tick budget. |
| A `coroutine.yield(0.05)` loop survives a few hundred iterations | Confirms the engine keeps resuming a long-lived plugin |

**If `require("socket")` fails on the console, this design is dead.** Stop and re-plan rather
than working around it. The Tauri app stays recoverable in git history for exactly this reason.

---

## Architecture

One Lua coroutine, one plugin, no OSC anywhere. The console reads its own object model, which
removes the entire "Destination IP = the Mac, Port 8000, UDP" setup step from the instructions
and removes the OSC-string regex from the codebase.

```
grandMA3 console — plugin "MA3CueDisplay", single coroutine tick loop
  loop:  coroutine.yield(0.05)          -- 20 Hz, releases the UI thread every tick
    |
    +- every 4th tick (~5 Hz) — read cue state
    |    for each DataPool().Sequences:Children() where HasActivePlayback():
    |        cue = seq:CurrentChild();  no = cue.No / 1000;  name = cue.name
    |    whichever (sequence, cueNo) pair changed since last scan = "most recently fired"
    |    serialize to JSON once, cache the string
    |
    +- every tick — serve HTTP, never blocking
         server:settimeout(0)
         accept up to 4 connections per tick, each: read -> route -> write -> close
           GET /                  full-screen display page
           GET /?style=overlay    transparent lower-third for OBS
           GET /api/state         the cached JSON string
           GET /debug             all active sequences + raw state + poll latency
           GET /health            ok + version
```

**Default HTTP port: 8090.** Configurable at the top of the Lua file. Not 8080 — that is
MA3's own Web Remote. Not 3000 — no reason to inherit the old app's port.

### Why polling, not hooks

MA3 provides no working way to be notified of a cue change:

- `HookObjectChange` on `DataPool().Sequences` fires only on *physical* changes (moving or
  editing a sequence), not on playback.
- `HasActivePlayback()` is a function, not an attribute, so it cannot be hooked.
- Hooking `Root().Temp.RunningSequences` reportedly only works while the Running Sequences
  window is open on a physical MA3 screen — an unacceptable dependency.

Polling is therefore the only reliable mechanism, and the tick loop already exists for the
socket server, so it costs nothing structurally.

### Why polling clients, not WebSocket or SSE

Clients `fetch('/api/state')` every 250 ms. No held-open connections, no client list to
manage, no half-open socket cleanup, and no hand-written SHA-1 + base64 WebSocket handshake
in Lua. 250 ms is imperceptible on a cue display. This is the single largest robustness win
available in this design, and it is what makes a cooperative single-coroutine server viable.

### Safety properties

This code runs inside the process driving the lights during a service. Each of these is a
requirement, not a nicety:

1. **`settimeout(0)` on every socket operation.** The documented UI-freeze failure mode comes
   from blocking `accept()` and `receive()` — MA3 plugins are coroutines sharing the UI
   thread, so a blocking call freezes the console. Non-blocking means no client, however slow
   or dead, can stall the desk.
2. **Per-tick work cap.** Maximum 4 accepts per tick, 2 KB request read cap,
   `Connection: close`, no keep-alive. A connection flood cannot monopolize a tick, and no
   socket is ever held open between ticks.
3. **`pcall` around the entire tick body.** A Lua error in this plugin must not escape into
   the console's Lua engine.
4. **Watchdog.** N consecutive tick errors, or a failed bind, closes the listener and exits
   cleanly with an explanatory `Printf` rather than spinning.
5. **Explicit `Stop` component plus a double-start guard.** Without a stop path, a wedged
   loop means restarting the console mid-service. The guard prevents a second button press
   from trying to bind an already-bound port.

---

## Data model

`GET /api/state`:

```json
{
  "sequence": "Main",
  "cueNumber": "12.5",
  "cueName": "Sermon Wash",
  "activeSequences": ["Main", "Haze"],
  "updatedAt": 91234.56,
  "version": "2.0.0"
}
```

Cue number comes from `cue.No / 1000` rendered via `tostring()`, **not** `cue.index`.
MA3 cue numbers allow three decimal places and `cue.index` truncates to whole numbers, so
cue 12.5 would display as 12.

The page watches `updatedAt`. If it stops advancing, or the fetch fails, the page shows a
disconnected state rather than a cue that is no longer real — the failure that matters most
on a display the whole room can see.

### Which cues are tracked

**Whatever fired most recently, on any executor.** This matches the current app's behavior.
Each scan compares every active sequence's `(name, cueNo)` against the previous scan; the
pair that changed becomes the displayed cue.

Three edge cases the scan must handle explicitly, because "most recently fired" is
underdetermined by itself:

- **Two sequences change in the same scan.** At 5 Hz this is normal, not rare. Rule: if the
  currently-displayed sequence is among those that changed, keep showing it; otherwise take
  the first changed sequence in iteration order. This is deterministic and stops the display
  from flapping between two simultaneously-running stacks.
- **Cold start, before anything fires.** Show the first active sequence that has a current
  cue. If nothing is active, show `--` for the cue number and an empty sequence name, which
  is what the old app did.
- **The displayed sequence stops playing.** Keep displaying its last known cue. Do not clear
  or blank on playback stop — the old app behaved this way, and a display that empties itself
  when a stack goes off is worse than one showing the last cue that ran.

Known trade-off, accepted: bumping a flash or effect executor will pull the display off the
main stack until the main stack fires again. A fixed-sequence mode was considered and
rejected in favor of matching existing behavior.

---

## Display page

One HTML document embedded in the `.lua` as a `[==[ ... ]==]` long string — a `[[ ... ]]`
delimiter would break on the `]]` that appears in CSS and JS. Embedding keeps the plugin a
single self-contained artifact with no file-path dependencies, so it works stored in the show
file.

- **`/`** — full-screen dark. Small muted sequence name above, very large cue number, cue
  name beneath.
- **`/?style=overlay`** — transparent background, lower-third bottom-left, text shadow for
  legibility over a camera feed, no page chrome. Drops into an OBS browser source, which
  keys on the page's alpha.
- **Color** — accent is Light Blue `#009CDE`. The brand primary `#004C97` fails WCAG AA on
  black. System font stack; Myriad Pro is not bundled anywhere.
- **Typography** — `clamp()`/vw units throughout, so one page reads correctly on a 4K
  confidence monitor and a 1280x720 OBS source with no configuration.
- **Disconnected state** — dim the display and say so explicitly.
- **`/debug`** — replaces the old `/osc-log` page, which has nothing to log now. Lists every
  active sequence, the raw state JSON, and poll latency. This is the page you open when
  someone says it's showing the wrong cue.

---

## Source layout and build

Lua that only runs inside a lighting console is easy to leave untested. The fix is modular
sources built on the Mac and concatenated into one distributable file:

```
src/json.lua       pure JSON encoder — the console is not guaranteed to have one
src/state.lua      pure: fake sequence tables in -> state + most-recent-fire detection out
src/http.lua       pure: raw request string in -> response string out
src/ma3.lua        the ONLY file touching DataPool()/Root() — thin adapter, mocked in tests
src/display.html   inlined at build time
src/main.lua       tick loop, watchdog, socket lifecycle
build.sh        -> dist/MA3CueDisplay.lua + dist/MA3CueDisplay.xml
tests/             run under plain lua5.4 on macOS against a mocked MA3 API
```

Tests cover `state.lua`, `http.lua`, and `json.lua` — the state-diff and request-routing
logic, which is where bugs would be subtle rather than obvious. `main.lua` and `ma3.lua`
cannot be tested off-console; the probe plugin and a desk check cover them.

Requires `lua` on the Mac (`brew install lua`). No npm, no Rust, no Xcode — the entire
previous toolchain disappears.

---

## Install and start

1. Copy `MA3CueDisplay.xml` and `MA3CueDisplay.lua` to `gma3_library/datapools/plugins`
   (USB stick).
2. Import into the Plugin Pool.
3. Set `InStream` so the plugin is stored **in the show file** — it then travels with the
   show and survives console reboots.
4. Create macro `Start Cue Display` = `Plugin "MA3CueDisplay"`, and `Stop Cue Display`.
   Put Start on an executor button.

On start, the plugin `Printf`s the real URLs — console IP and port — into command line
feedback, so the operator reads the address off the desk instead of hunting for it.

**There is no true auto-start on a console.** MA3 offers `RUNPLUGIN="plugin.xml"-x` as a
launch argument for onPC only. On a console there is no supported on-show-load hook: the
engine cannot be started while it is being assembled, and the only workaround the community
cites is a DMX Remote firing after load. Editing system files to fake it may violate the
EULA. So the accepted UX is **one labeled button press per session** — still far less
friction than installing and babysitting a Mac app.

---

## Versioning

The plugin ships as **2.0.0**. It is a different language, platform, host machine, and install
method, sharing nothing with the Tauri app but the idea, so a major bump is honest.

A fresh 1.0.0 line was considered first and abandoned once the history push revealed the
constraint: the Mac app already owns the `v1.0.0` and `v1.1.0` tags, and those came across
with the full history. Reusing `v1.0.0` would have meant renaming or deleting existing tags,
and 2.0.0 sidesteps that with no tag surgery on a repo that is already public.

For the record, the retired app's version history ran v1.0.0 → v1.1.0 → v1.0.1, with v1.0.1
marked latest despite sorting lowest. 2.0.0 is the first version in this repo that is
unambiguously above everything before it.

---

## Repo migration

1. Create **`upipibi/ma3-cue-display`**, public.
2. **Push full history first**, not a fresh repo. Provenance and the v1.0.1 Tauri artifact
   survive, and the rewrite lands as commits on top. The Tauri app leaves the working tree
   but stays recoverable from git — required by the feasibility gate.
3. Build, then run the probe on the console, then desk-test.
4. **Only after a passing desk test**: tag and release. A release is now two text files plus
   a convenience zip. No `.app`, no `codesign`, no `xattr -cr`, no Gatekeeper, no Sparkle.
5. **Delete `NorthwoodsCommunityChurch/Ma3_Cue_Display` last**, after cloning the new repo
   fresh and confirming history and releases came across. Requires explicit go-ahead at that
   moment — deletion takes issues, releases, and tags with it and is irreversible.

### Files removed in the rewrite

- `gma3-cue-display-tauri/` — the entire Tauri project
- `MA3CueDisplay-v1.0.1-aarch64.zip` — 6 MB binary in the repo root
- `.claude-notes` — macOS signing/release checklist, obsolete
- `LAUNCHER_TEMPLATE.md` — launcher window design notes for the dead Mac app
- `Launcher.png` — screenshot of the dead Mac app

### Docs rewritten

- `CLAUDE.md` — almost entirely: stack, architecture, ports, build, release, gotchas all change
- `README.md` — drop the OSC console setup; add plugin install, macro setup, OBS browser
  source steps, and the one-button-press-per-session note
- `CREDITS.md` — swap the Rust crates for LuaSocket

The org's `Always True` rules about Sparkle and signed zips stop applying. That file is
org-wide and this repo is leaving the org, so nothing to edit there.

---

## Deferred

**Fade-progress bar.** The old app derived it from the OSC `FaderMaster` action. From Lua it
means reading executor fader values on every tick — more per-tick work on the console's UI
thread for decoration. The state shape leaves room for a `progress` field and `ma3.lua` is
where the read would go.

## Risks

| Risk | Mitigation |
|---|---|
| LuaSocket absent on console | Probe plugin is the first deliverable and a hard gate |
| Sequence scan too slow on a large show file | Probe measures it; cue-poll rate is independent of socket-poll rate and can drop below 5 Hz |
| Plugin breaks on an MA3 software upgrade | MA documents this explicitly for all plugins. Mitigated by keeping `ma3.lua` thin and isolated. |
| Wedged loop during a service | `pcall` per tick, watchdog exit, explicit Stop macro |
| MA support won't help with plugin issues | Stated in MA's own docs. Accepted. |
