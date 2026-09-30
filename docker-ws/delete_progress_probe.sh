#!/bin/bash
# Read-only: is the artifacts delete still running, and how much is left.
cd "$(dirname "$0")/.."
pgrep -fl "rm -rf artifacts/testflight|delete_testflight_crash" || echo "no delete process"
T=artifacts/testflight-crash-investigation-20260910
[ -d "$T" ] && echo "remaining top entries: $(ls "$T" | wc -l)" || echo "gone: $T"
df -h . | tail -1 | awk '{print "free="$4}'
