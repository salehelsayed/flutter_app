#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xargs git add -- < build/kayan-safe/astra-it4/files.txt
test "$(git write-tree)" = 4d73c11300e191d76799a842ada8181ab9a5348e || { echo "tree mismatch"; exit 3; }
git commit -q -F build/kayan-safe/astra-it4/commit-msg.txt
git log -1 --format='%H %T'
