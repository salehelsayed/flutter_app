#!/bin/bash
# Run a list of flutter test files (one path per line) in a worktree under build/ with the pinned SDK, in one flutter test call.
#   host-run bash docker-ws/focused_in_tree.sh <tree under build/> <list file under repo> <log file under repo>
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${MKNOON_FLUTTER_SDK:-$HOME/development/flutter-3.47.2}"
L="$REPO/${3:?log}"; LIST="$REPO/${2:?list}"
cd "$REPO/${1:?tree}" || exit 3
"$SDK/bin/flutter" test --no-pub --concurrency=1 --timeout=2m $(cat "$LIST") > "$L" 2>&1
rc=$?; echo "exit=$rc" >> "$L"; tail -3 "$L"; exit $rc
