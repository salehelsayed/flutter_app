#!/bin/bash
set -uo pipefail
cd "$(dirname "$0")/.."
git revert --no-commit cac7678553ea7ec006bf948e511a5a3c67d7bce2 || { git revert --abort; echo "revert conflict, aborted"; exit 3; }
git commit -q -F build/kayan-safe/patch11/revert-msg.txt
git log -1 --format='%H %T'
git diff --stat 027385214 HEAD -- android/ | tail -1
