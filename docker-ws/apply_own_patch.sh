#!/bin/bash
# Apply my own reviewed patch to the index of local main (no commit).  host-run bash docker-ws/apply_own_patch.sh <patch under build/> <sha256> <base head>
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"; cd "$REPO"; P="$REPO/${1:?patch}"
[ "$(shasum -a 256 "$P" | awk '{print $1}')" = "${2:?sha}" ] || { echo "FAIL sha"; exit 3; }
[ "$(git rev-parse --short=9 HEAD)" = "${3:?head}" ] || { echo "FAIL head"; exit 3; }
[ -z "$(git diff --cached --name-only)" ] || { echo "FAIL index not empty"; exit 3; }
git update-index -q --refresh || true
git apply --check "$P"; git apply --index "$P"
git diff --cached --stat; echo "tree=$(git write-tree)"
