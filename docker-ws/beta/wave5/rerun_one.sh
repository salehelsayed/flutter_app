#!/bin/bash
# Run one Flutter test file N times in the wave3-next worktree (no format/analyze); print each result line.
cd /Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next || exit 1
SDK=$HOME/development/flutter-3.47.2
for i in $(seq 1 "${2:-3}"); do
  "$SDK/bin/flutter" test "$1" 2>&1 | grep -E 'All tests passed|Some tests failed' | tail -1 | sed "s/^/run $i: /"
done
