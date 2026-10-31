#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xargs git add -- < build/kayan-safe/astra-matrix/files.txt
git diff --cached --name-only | sort | diff - <(sort build/kayan-safe/astra-matrix/files.txt) >/dev/null || { echo "staged set differs"; exit 3; }
git commit -q -F build/kayan-safe/astra-matrix/commit-msg.txt
git log -1 --format='%H %T'
