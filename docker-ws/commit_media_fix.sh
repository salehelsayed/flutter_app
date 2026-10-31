#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xargs git add -- < build/kayan-safe/media-unavailable/files.txt
git diff --cached --name-only | sort | diff - <(sort build/kayan-safe/media-unavailable/files.txt) >/dev/null || { echo "staged set differs"; exit 3; }
git commit -q -F build/kayan-safe/media-unavailable/commit-msg.txt
git log -1 --format='%H %T'
