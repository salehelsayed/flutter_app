#!/bin/bash
# Run one command in the idle-poll worktree with the Flutter toolchain on PATH; output to <log> (relative to the worktree).
#   host-run bash docker-ws/idlepoll_step.sh <log> -- <command...>
set -uo pipefail
W=/Volumes/CrucialX9/flutter_app/build/wt-idlepoll
LOG="$1"; shift; [ "$1" = "--" ] && shift
cd "$W" || exit 3
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:$HOME/Library/Android/sdk/platform-tools:$PATH"
"$@" > "$LOG" 2>&1; rc=$?; echo "exit=$rc" >> "$LOG"; exit $rc
