#!/usr/bin/env bash
# Run the dependency-free smoke test against the classic Vim adapter.
#
#   tests/run-vim.sh
#
# Requires only `vim` on PATH. Exits non-zero if any check fails.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT
export VIM_HERDR_NAVIGATOR_TEST_LOG="$LOG"

set +e
vim -Nu NONE -n -N -es \
  --cmd "set rtp+=$ROOT" \
  -S "$ROOT/tests/vim-smoke.vim"
status=$?
set -e

cat "$LOG"
exit "$status"
