# Feasibility probe

Run this on the actual grandMA3 console before the rest of the plugin gets
built. It answers questions that cannot be verified without the hardware.

Nothing here ships. This whole folder is disposable once the answers are in.

## Run it

1. Copy `MA3CueDisplay-Probe.lua` to a USB stick.
2. On the console, create a new plugin in the Plugin Pool named `Probe`.
3. Import `MA3CueDisplay-Probe.lua` as its Lua file.
4. **Have at least one cue stack running** before you press it, or the sequence
   checks will have nothing to report.
5. Press the plugin. It takes about two seconds (the last check deliberately
   yields 200 times to prove the engine keeps resuming a long-lived plugin).
6. Open the Command Line Feedback window and screenshot every `PROBE |` line.

It is safe to run during a service if you have to — it binds port 8090 only long
enough to prove it can, then closes it, and it never loops indefinitely.

## Also needed — the plugin XML template

While you are in the Plugin Pool:

1. Create an empty plugin named `MA3CueDisplay`.
2. Export it to the USB stick.
3. Send back the resulting `MA3CueDisplay.xml`.

The exact plugin XML schema is not reliably documented anywhere, so the console
has to be the source of truth. Hand-writing it risks a file the console imports
as a silently broken plugin.

## What the output means

| Line | Meaning |
|---|---|
| `socket: OK` | LuaSocket exists. The design is viable. |
| `socket: FAIL` | **Hard blocker.** Stop and report — do not work around it. |
| `bind 8090: OK` | The console permits a listening socket. |
| `bind 8090: FAIL` | Port is taken or blocked. Report the error text; the port is configurable. |
| `scan: ... took N ms` | How much UI-thread time one full sequence sweep costs. Sets the cue poll rate. |
| `scan: WARNING` | Over 20 ms per sweep. Report it — 5 Hz polling would be too aggressive. |
| `active: ... cue.name=nil` | Cue names are not readable this way and the display design needs revisiting. |
| `active: ... cue.index=12 cue.No=12500` | Confirms why the plugin uses `cue.No / 1000` — `index` truncates 12.5 to 12. |
| `yield: 2.00 s wall elapsed` | The engine honors yield timing, so the tick loop will run at the intended rate. |

## The one line that matters most

`PROBE | socket: FAIL` means LuaSocket is not available on console hardware and
the console-hosted design is dead. Stop and report it. The retired macOS app is
still recoverable from this repository's git history, which is the fallback.
