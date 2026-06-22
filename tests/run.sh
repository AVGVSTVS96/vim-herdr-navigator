#!/usr/bin/env bash
# Run the dependency-free smoke test against this plugin.
#
#   tests/run.sh
#
# Requires only `nvim` on PATH. Exits non-zero if any check fails.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

exec nvim --headless --noplugin -u NONE \
  --cmd "set rtp+=$ROOT" \
  -c "luafile $ROOT/tests/smoke.lua"
