#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
D=build/kayan-safe/batch2/voice-fix
[ "$(git rev-parse HEAD)" = 5dad050c8d115fcedd16edf5fa2003c28f5cdeee ] || { echo "head moved"; exit 3; }
xargs git add -- < $D/files.txt
git diff --cached --name-only | sort | diff - <(sort $D/files.txt) >/dev/null || { echo "staged set differs"; exit 3; }
[ "$(git write-tree)" = 1f409e26a3c990261c4595fbc9a2915917dff8a2 ] || { echo "tree differs"; exit 3; }
git commit -q -F $D/commit-msg.txt
git log -1 --format='%H %T'
