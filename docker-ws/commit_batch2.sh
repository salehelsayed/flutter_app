#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
D=build/kayan-safe/batch2
[ "$(git rev-parse HEAD)" = dbab73ebccb548ccee7693a9c5003c4058af2c04 ] || { echo "head moved"; exit 3; }
[ "$(shasum -a 256 $D/batch2.patch | cut -d' ' -f1)" = 09c5d3867f821cd99e0776192ede7ab0eb4a3dd01a8ee7860e670dfdcad11c10 ] || { echo "patch sha differs"; exit 3; }
[ -z "$(git diff --cached --name-only)" ] || { echo "index not clean"; exit 3; }
git apply --check $D/batch2.patch
git apply $D/batch2.patch
xargs git add -- < $D/files.txt
git diff --cached --name-only | sort | diff - <(sort $D/files.txt) >/dev/null || { echo "staged set differs"; exit 3; }
[ "$(git write-tree)" = a2f269c81baeb4518c222548fd9bb7bd22715398 ] || { echo "tree differs"; exit 3; }
git commit -q -F $D/commit-msg.txt
git log -1 --format='%H %T'
