#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
D=build/kayan-safe/media-unavailable
[ "$(git rev-parse HEAD)" = 56574ad24a4855b1eb1ee4741eaf3e552b2dea69 ] || { echo "head moved"; exit 3; }
xargs git add -- < $D/files-v3.txt
git diff --cached --name-only | sort | diff - <(sort $D/files-v3.txt) >/dev/null || { echo "staged set differs"; exit 3; }
[ "$(git write-tree)" = 106d177b5ff3c1fe1c3dd1cdde5c24cb157eeb80 ] || { echo "tree differs"; exit 3; }
git commit -q -F $D/commit-msg-v3.txt
git log -1 --format='%H %T'
