#!/bin/bash
# Run mknoon_checks change-mode run for a --only subset inside a worktree under build/, logging to an evidence dir.
#   host-run bash docker-ws/checks_only_in_tree.sh <tree under build/> <base rev> <only csv> <evidence dir under repo>
REPO="$(cd "$(dirname "$0")/.." && pwd)"; cd "$REPO/${1:?tree}" || exit 2
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
E="$REPO/${4:?evidence}"; mkdir -p "$E"
python3 scripts/mknoon_checks.py run --mode change --base "${2:?base}" --local --only "${3:?only}" --output "$E/report" > "$E/run.log" 2>&1
rc=$?; echo "exit=$rc" >> "$E/run.log"; echo "exit=$rc"; exit $rc
