# Credits & Attributions

## Runtime dependencies

| Dependency | License | Notes |
|---|---|---|
| [Lua 5.4](https://www.lua.org/license.html) | MIT | Provided by grandMA3 |
| [LuaSocket](https://github.com/lunarmodules/luasocket) | MIT | Provided by grandMA3; used for the TCP listener |

**Nothing is vendored.** The JSON encoder, HTTP layer, connection state machine,
and test runner were written for this project, so the plugin ships as two plain
text files with no bundled third-party code.

## Development-only

| Tool | License | Notes |
|---|---|---|
| [LuaSocket](https://github.com/lunarmodules/luasocket) | MIT | Needed locally only for `run-fake-console.sh`, since a Mac has no console to provide it |

No npm, no Rust, no Xcode, no build framework.

## Frontend

No frameworks, no build step, no webfonts. `src/display.html` is vanilla
HTML/CSS/JS on a system font stack, because the console has no route to the
internet — an external asset would block rendering and then fail. `build.sh`
fails the build if a URL appears in the page.

## Reference material

The grandMA3 plugin XML schema was derived from real exported plugins published
by the community, since it is not reliably documented:

- [hossimo/GMA3Plugins](https://github.com/hossimo/GMA3Plugins)
- [imhofroger/GMA3_LUA](https://github.com/imhofroger/GMA3_LUA)

The MA Lighting forum threads on non-blocking plugins, `coroutine.yield` timing,
and reading the current cue informed the architecture. They are cited in the
design doc under `docs/superpowers/specs/`.

## Platform

grandMA3 by [MA Lighting](https://www.malighting.com/). This is an unofficial
third-party plugin, not affiliated with or endorsed by MA Lighting. MA's own
documentation notes that plugins can reach deeper into the system than normal
console use, and that their support may not be able to help with plugin issues.

## History

Versions before 2.0.0 were macOS menu-bar apps — first
[Electron](https://www.electronjs.org/), then [Tauri](https://tauri.app/)
(MIT/Apache-2.0) with `warp`, `rosc`, `tokio`, `serde`, `regex`, and
[Inter](https://fonts.google.com/specimen/Inter) (SIL OFL 1.1). That code and its
license notices remain in this repository's git history.

---

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
