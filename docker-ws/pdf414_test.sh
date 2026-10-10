#!/bin/bash
# Plan 414: run flutter test in this worktree. Usage: pdf414_test.sh <log name> <test paths...>
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SDK="${MKNOON_FLUTTER_SDK:-$HOME/development/flutter-3.47.2}"
LOG="Test-Flight-Improv/evidence/414/$1"; shift
mkdir -p "$(dirname "$LOG")"
"$SDK/bin/flutter" test --no-pub --reporter expanded "$@" > "$LOG.full" 2>&1
CODE=$?
grep -v '^\[FLOW\]' "$LOG.full" > "$LOG"
rm -f "$LOG.full"
echo "EXIT=$CODE" >> "$LOG"
tail -3 "$LOG"
