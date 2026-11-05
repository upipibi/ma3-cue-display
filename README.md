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

Viewers poll `/api/state` every 250 ms. There is no WebSocket: a held-open
connection inside a cooperative single-coroutine server is a liability, and
250 ms is invisible on a cue display.

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
