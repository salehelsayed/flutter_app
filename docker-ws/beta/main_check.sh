#!/bin/bash
# In the main checkout: format + analyze the CHANGED .dart files (vs HEAD, plus untracked) and run the named
# Dart tests. Output: docker-ws/beta/main_check.out
#   main_check.sh [test/...dart ...]
M=/Volumes/CrucialX9/flutter_app
SDK=$HOME/development/flutter-3.47.2
OUT=$M/docker-ws/beta/main_check.out
cd "$M" || exit 1
CHANGED=$( (git diff --name-only HEAD; git ls-files --others --exclude-standard) | grep '\.dart$' | sort -u)
TESTS=$(printf '%s\n' "$@" | grep '_test\.dart$')
{
  echo "== changed: $(echo $CHANGED | wc -w) dart files"
  [ -n "$CHANGED" ] && { echo "== format"; "$SDK/bin/dart" format $CHANGED 2>&1 | tail -3; echo "== analyze"; "$SDK/bin/dart" analyze $CHANGED 2>&1 | tail -15; }
  [ -n "$TESTS" ] && { echo "== dart tests"; "$SDK/bin/flutter" test $TESTS 2>&1 | grep -E 'All tests passed|Some tests failed|\[E\]|^[0-9]{2}:[0-9]{2} \+[0-9]+ -[0-9]+' | tail -25; }
} > "$OUT" 2>&1
cat "$OUT"
