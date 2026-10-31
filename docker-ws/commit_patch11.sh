#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xargs git add -- < build/kayan-safe/patch11/files.txt
test "$(git write-tree)" = 53b5f44cfa125a70076134aae37efa0f58632a65 || { echo "tree mismatch"; exit 3; }
git commit -q -F build/kayan-safe/patch11/commit-msg.txt
git log -1 --format='%H %T'
