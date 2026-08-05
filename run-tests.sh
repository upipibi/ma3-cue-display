#!/usr/bin/env bash
# Runs the test suite under Lua 5.4 — the version grandMA3 ships. The Mac's
# default `lua` is newer and would let 5.5-only syntax slip through to a console.
set -euo pipefail

LUA=/opt/homebrew/opt/lua@5.4/bin/lua
if [[ ! -x "$LUA" ]]; then
  echo "Lua 5.4 not found at $LUA — run: brew install lua@5.4" >&2
  exit 1
fi

"$LUA" -v
cd "$(dirname "$0")"
exec "$LUA" tests/all.lua
