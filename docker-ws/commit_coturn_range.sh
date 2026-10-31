#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
D=build/kayan-safe/coturn-port-range
[ "$(git rev-parse HEAD)" = d161fe20c2b01bf034cc808ed2d284d1ec7d7ca8 ] || { echo "head moved"; exit 3; }
xargs git add -- < $D/files.txt
git diff --cached --name-only | sort | diff - <(sort $D/files.txt) >/dev/null || { echo "staged set differs"; exit 3; }
[ "$(git write-tree)" = c5f7bba248f73450ecb692d7a8662a5f7eff7c91 ] || { echo "tree differs"; exit 3; }
git commit -q -F $D/commit-msg.txt
git log -1 --format='%H %T'
