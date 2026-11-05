#!/usr/bin/env bash
# Runs the test suite under Lua 5.5, the version grandMA3 2.5 ships (the console reports
# _VERSION = "Lua 5.5"), then under Lua 5.4 as a compatibility check for older software.
# 5.5 is stricter: a for-loop control variable is read-only, so code that passes on 5.4
# can be a syntax error on the console. That is how 2.0.0 shipped broken.
set -euo pipefail

cd "$(dirname "$0")"
ran=0
for LUA in /opt/homebrew/opt/lua@5.5/bin/lua /opt/homebrew/opt/lua@5.4/bin/lua; do
  if [[ ! -x "$LUA" ]]; then
    echo "MISSING: $LUA (brew install lua@5.5 lua@5.4)" >&2
    exit 1
  fi
  "$LUA" -v
  "$LUA" tests/all.lua
  ran=$((ran + 1))
done
echo "test suite passed on $ran Lua versions"
