#!/usr/bin/env bash
# Runs the built plugin against a fake grandMA3 on this Mac, so the real shipped
# artifact can be exercised end-to-end without a console.
#
# It stubs the four MA3 globals, fakes an object model whose cue stacks advance
# on a timer, and — the part that matters — resumes the plugin coroutine after
# each coroutine.yield(seconds), which is what MA3's plugin scheduler does.
#
# Then open:
#   http://127.0.0.1:8090/                  full-screen display
#   http://127.0.0.1:8090/?style=overlay    OBS overlay (transparent)
#   http://127.0.0.1:8090/debug             active sequences, poll stats, raw state
#
#   http://127.0.0.1:8090/grid              fixed 1280 x 800 grid (use the grid scenario)
#
# Usage: ./run-fake-console.sh [seconds] [grid]     (default 120 s, single-cue scenario)
#   grid: numbered sequences that start, stop and change cue, cues with fades,
#         and two timecode slots, for the /grid view
set -euo pipefail

SECONDS_TO_RUN="${1:-120}"
LUA=/opt/homebrew/opt/lua@5.4/bin/lua
ROCKS="$HOME/.luarocks"

cd "$(dirname "$0")"

if [[ ! -x "$LUA" ]]; then
  echo "ERROR: Lua 5.4 not found at $LUA — run: brew install lua@5.4" >&2
  exit 1
fi

if [[ ! -f "$ROCKS/lib/lua/5.4/socket/core.so" ]]; then
  cat >&2 <<'EOF'
ERROR: LuaSocket is not installed for Lua 5.4 on this Mac.

The console provides LuaSocket itself, so it is not needed to build or to run
the unit tests — only to run this fake-console harness. Install it with:

  brew install luarocks
  luarocks --lua-version=5.4 --lua-dir=/opt/homebrew/opt/lua@5.4 install --local luasocket
EOF
  exit 1
fi

if [[ ! -f dist/MA3CueDisplay.lua ]]; then
  echo "dist/MA3CueDisplay.lua missing — building first" >&2
  ./build.sh
fi

export LUA_PATH="$ROCKS/share/lua/5.4/?.lua;$ROCKS/share/lua/5.4/?/init.lua;;"
export LUA_CPATH="$ROCKS/lib/lua/5.4/?.so;;"

exec "$LUA" tools/fake-console.lua dist/MA3CueDisplay.lua "$SECONDS_TO_RUN" "${2:-default}"
