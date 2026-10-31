#!/bin/bash
# Run mknoon_checks validate and a change plan inside a repo worktree under build/.
#   host-run bash docker-ws/checks_in_tree.sh <tree under build/> <base rev> <out under build/kayan-safe/>
REPO="$(cd "$(dirname "$0")/.." && pwd)"; cd "$REPO/${1:?tree}" || exit 2
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
python3 scripts/mknoon_checks.py validate > "$REPO/${3:?out}.validate.log" 2>&1; echo "validate=$?"
python3 scripts/mknoon_checks.py plan --mode change --base "${2:?base}" --local --output "$REPO/$3.plan" > "$REPO/$3.plan.log" 2>&1; echo "plan=$?"
tail -5 "$REPO/$3.plan.log"
