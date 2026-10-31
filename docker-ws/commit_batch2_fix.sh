#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
D=build/kayan-safe/batch2/voice-fix
[ "$(git rev-parse HEAD)" = 5dad050c8d115fcedd16edf5fa2003c28f5cdeee ] || { echo "head moved"; exit 3; }
[ "$(shasum -a 256 $D/voice-fix.patch | cut -d' ' -f1)" = b07d60fac74b996dff5deee77b4d9c4e80da650f13bcc18bf1f9bec687d5f0e4 ] || { echo "patch sha differs"; exit 3; }
[ -z "$(git diff --cached --name-only)" ] || { echo "index not clean"; exit 3; }
git apply --check $D/voice-fix.patch
git apply $D/voice-fix.patch
xargs git add -- < $D/files.txt
git diff --cached --name-only | sort | diff - <(sort $D/files.txt) >/dev/null || { echo "staged set differs"; exit 3; }
[ "$(git write-tree)" = 1f409e26a3c990261c4595fbc9a2915917dff8a2 ] || { echo "tree differs"; exit 3; }
git commit -q -F $D/commit-msg.txt
git log -1 --format='%H %T'
