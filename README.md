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
| `http://<console-ip>:8090/grid` | Fixed 1280 x 800 grid: two timecode clocks and up to eight running sequences with their cue fades |
| `http://<console-ip>:8090/grid?style=overlay` | The same grid with a transparent background, for OBS |
| `http://<console-ip>:8090/debug` | Active sequences, poll stats, raw state |
| `http://<console-ip>:8090/api/state` | JSON, if you want to build something else |
| `http://<console-ip>:8090/health` | Liveness check |

Viewers poll `/api/state` every 250 ms. There is no WebSocket: a held-open
connection inside a cooperative single-coroutine server is a liability, and
250 ms is invisible on a cue display.

## The grid view

`/grid` is one frame of exactly **1280 x 800** pixels, pinned to the top-left corner of the
page. It never changes size and nothing inside it moves, so you place or crop it once.

- **Two timecode clocks** along the top, slots 1 and 2, as `HH:MM:SS:FF`. A slot that is not
  rolling stays in place, greyed, and reads `stopped`.
- **Eight slots** below, two across and four down, always drawn. An empty slot is a faint
  outline. A running sequence takes a slot and keeps it until it stops; then the slot goes back
  to an outline and nothing else moves.
- **Each occupied slot** shows the sequence name, the cue number and name, and the cue's fade:
  a bar that fills while the fade runs with the seconds remaining, then `fade 4 s`. A fade of
  zero reads `snap`.

Which sequences appear: the ones that are running and numbered **1 to 89**. A sequence that
starts takes the slot it had before if that is free, otherwise the first free slot. If all eight
are taken, a ninth waits for one to free up.

What the grid is not:

- **The fade is the programmed fade**, read from the cue (part 0, in fade) and counted from the
  moment the cue fires. It does not follow an executor time fader, a rate or speed master, a
  manual crossfade, or individual attribute timing. If the cue has no fade value the bar is
  hidden.
- **The timecode is a monitor, not a sync reference.** It is sampled 20 times a second and
  smoothed in the page; expect it within a frame or two of the console.
- Firing the cue a sequence is already on does not restart its bar.

The range, the slots shown and the frame rate are the `grid_from`, `grid_to`, `timecode_slots`
and `timecode_fps` values in `CONFIG` at the top of `src/main.lua`.

## Requirements

- A grandMA3 console or onPC station with LuaSocket available
- The viewing device on the same network as the console
- Port **8090** reachable on the console (8080 is MA3's own Web Remote)

## Install

1. Copy `MA3CueDisplay.lua` and `MA3CueDisplay.xml` onto a USB stick.
2. On the console, put both in `gma3_library/datapools/plugins`.
3. Import the plugin in the Plugin Pool.
4. Check the plugin's **InStream** property is on, so the code is stored in the show
   file and travels with the show. From 2.0.1 the console sets it by itself on import.
5. Make one macro, `Cue Display`, containing `Plugin "MA3CueDisplay"`.
6. Put that macro on an executor button.

## Running it

Press **Cue Display**. The Command Line Feedback window prints the port and the
URLs. Read your console's IP off the network menu and open the page.

The button is a **toggle** — press it again to stop the server and release the
port. There is one component and one macro: press to start, press to stop.

**There is no auto-start on a console.** grandMA3 offers a `RUNPLUGIN` launch
argument for onPC only; a console has no supported on-show-load hook, because
the engine cannot be started while it is still being assembled. So this is one
button press per session.

The plugin also stops itself if it hits ten consecutive internal errors, rather
than continuing to run in a bad state on a live desk.

If the feedback says *stop requested* but nothing was actually running — which
can happen if a previous run was killed abnormally and left its flag set — press
the button once more to start.

## OBS setup

1. Add a **Browser** source.
2. URL: `http://<console-ip>:8090/?style=overlay`
3. Width 1920, Height 1080.
4. Leave **Shutdown source when not visible** off, so it stays current.

The page background is fully transparent in overlay mode, so it keys straight
over a camera input with no chroma key.

For the grid view:

1. Add a **Browser** source.
2. URL: `http://<console-ip>:8090/grid` (or `/grid?style=overlay` to lay it over video).
3. Width 1280, Height 800. The source is then exactly the frame, with no crop needed.

If you capture a browser window instead, crop to the top-left 1280 x 800: the frame sits there
at any window size.

## When it shows the wrong thing

Open `/debug`. It lists every sequence the console reports as playing, the raw
state JSON, and poll timing.

The display tracks **whatever fired most recently on any executor**. Bumping a
flash or effect executor will pull it off your main stack until the main stack
fires again — that is by design, matching how the original OSC version behaved.

Three rules make that deterministic:

- If several stacks advance within the same scan and one is already displayed,
  it keeps the display rather than flapping between them.
- On startup, the first active stack with a cue wins.
- When the displayed stack stops playing, its last cue stays on screen. A
  display that blanks itself when a stack goes off is worse than one showing the
  last cue that ran.

If the page dims, it names which failure it is:

| Message | Meaning |
|---|---|
| **No data from console** | The console is unreachable — plugin stopped, or a network problem. |
| **Console stopped updating** | The console is answering, but its tick loop has wedged. Toggle the plugin off and on. |

## Building from source

```bash
brew install lua@5.5 lua@5.4   # the console runs 5.5 on grandMA3 2.5; 5.4 is a compatibility check
./run-tests.sh           # unit tests for the pure modules
./build.sh               # produces dist/MA3CueDisplay.lua and .xml
```

Sources live in `src/` as small modules and are concatenated into one file for
distribution. `src/ma3.lua` is the only file that touches the grandMA3 API.

### Testing without a console

```bash
./run-fake-console.sh    # then open http://127.0.0.1:8090/
```

For the grid view, run the grid scenario and open `http://127.0.0.1:8090/grid`. It adds numbered
sequences that start, stop and change cue, cues with fades, and two timecode slots:

```bash
./run-fake-console.sh 120 grid
```

This runs the **built artifact** against a stubbed object model whose cue stacks
advance on a timer, driven by a scheduler that honors `coroutine.yield` the way
MA3's does. It exercises the real shipped Lua rather than a test double, which is
what caught a JSON precision bug the unit tests could not see. It needs LuaSocket
locally — the console provides it, a Mac does not:

```bash
brew install luarocks
luarocks --lua-version=5.4 --lua-dir=/opt/homebrew/opt/lua@5.4 install --local luasocket
```

## History

Version 2.0.0 is a complete rewrite, and the third architecture this project has
had. Earlier versions were a macOS menu-bar app — first Electron, then
Tauri/Rust — that received OSC over UDP from the console and served the display
from a Mac. That needed a dedicated machine, OSC output configured on the console
pointed at it, and an unsigned app users had to talk macOS into opening. The
console hosts everything now, and the fragile regex that reverse-engineered
`"SequenceName CueNum CueName"` out of an OSC string went with it.

The old apps remain in this repository's git history.

## License

MIT — see [LICENSE](LICENSE).

Unofficial third-party plugin. Not affiliated with or endorsed by MA Lighting.
MA's own documentation notes that plugins reach deeper into the system than
normal console use, and that their support may not be able to help with plugin
issues.
