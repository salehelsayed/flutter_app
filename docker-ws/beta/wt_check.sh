#!/bin/bash
# In the next-batch worktree: format + analyze the CHANGED .dart files (vs HEAD, plus untracked),
# run the named Dart tests and the named Python test modules. Output: docker-ws/beta/wt_check.out
#   wt_check.sh [test/...dart ...] [py:scripts.test.module ...]
W=/Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next
SDK=$HOME/development/flutter-3.47.2
OUT=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wt_check.out
cd "$W" || exit 1
CHANGED=$( (git diff --name-only HEAD; git ls-files --others --exclude-standard) | grep '\.dart$' | sort -u)
TESTS=$(printf '%s\n' "$@" | grep '_test\.dart$')
PY=$(printf '%s\n' "$@" | grep '^py:' | sed 's/^py://')
{
  echo "== changed: $(echo $CHANGED | wc -w) dart files"
  [ -n "$CHANGED" ] && { echo "== format"; "$SDK/bin/dart" format $CHANGED 2>&1 | tail -3; echo "== analyze"; "$SDK/bin/dart" analyze $CHANGED 2>&1 | tail -15; }
  [ -n "$TESTS" ] && { echo "== dart tests"; "$SDK/bin/flutter" test $TESTS 2>&1 | grep -E 'All tests passed|Some tests failed|\[E\]|^[0-9]{2}:[0-9]{2} \+[0-9]+ -[0-9]+' | tail -20; }
  [ -n "$PY" ] && { echo "== python tests"; python3 -m unittest $PY 2>&1 | tail -6; }
} > "$OUT" 2>&1
cat "$OUT"
