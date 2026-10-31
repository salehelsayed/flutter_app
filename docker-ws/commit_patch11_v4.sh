#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xargs git add -- < build/kayan-safe/patch11/files-v4.txt
test "$(git write-tree)" = f1204da405f25e8aa5a80bca50794c122aa75b7f || { echo "tree mismatch"; exit 3; }
git commit -q -F build/kayan-safe/patch11/commit-msg-v4.txt
git log -1 --format='%H %T'
