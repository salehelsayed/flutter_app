#!/bin/bash
# Release 126 store build in build/wt-release-126: Go iOS bindings first, then both store artifacts.
#   host-run docker-ws/with_native_lease.py <log> -- bash docker-ws/release126_full_build.sh
set -uo pipefail
W="$(cd "$(dirname "$0")/.." && pwd)/build/wt-release-126"
cd "$W" || exit 2
echo "== ensure_go_ios_bindings $(date -u +%H:%M:%SZ)"
scripts/ensure_go_ios_bindings.sh || { echo "GO_IOS_BINDINGS FAILED"; exit 3; }
echo "== store build $(date -u +%H:%M:%SZ)"
bash docker-ws/build_store_release.sh; rc=$?
echo "== result file"; cat docker-ws/build_store_release_result.txt
echo "== done $(date -u +%H:%M:%SZ) rc=$rc"
exit $rc
