#!/bin/bash
# In the main checkout: run the named Flutter tests only (no format, no analyze). Python/shell tests by suffix.
cd /Volumes/CrucialX9/flutter_app || exit 1
SDK=$HOME/development/flutter-3.47.2
D=$(printf '%s\n' "$@" | grep '_test\.dart$'); P=$(printf '%s\n' "$@" | grep '_test\.py$'); S=$(printf '%s\n' "$@" | grep '\.sh$')
[ -n "$D" ] && { echo "== dart"; "$SDK/bin/flutter" test $D 2>&1 | grep -E 'All tests passed|Some tests failed|\[E\]|^[0-9]{2}:[0-9]{2} \+[0-9]+ -[0-9]+' | tail -8; }
for p in $P; do echo "== $p"; python3 -m unittest "$p" 2>&1 | tail -2; done
for s in $S; do echo "== $s"; PATH="$SDK/bin:/opt/homebrew/bin:$PATH" bash "$s" 2>&1 | tail -2; done
