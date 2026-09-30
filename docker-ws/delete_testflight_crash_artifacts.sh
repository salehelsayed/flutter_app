#!/bin/bash
# One-off (user-approved 2026-09-28): delete artifacts/testflight-crash-investigation-20260910 only.
set -u
cd "$(dirname "$0")/.."
T="artifacts/testflight-crash-investigation-20260910"
[ -d "$T" ] || { echo "not found: $T"; exit 1; }
echo "before: $(df -h . | tail -1 | awk '{print "free="$4}')"
rm -rf "$T"
echo "exit=$?"
[ -e "$T" ] && echo "STILL PRESENT: $T" || echo "deleted: $T"
echo "after: $(df -h . | tail -1 | awk '{print "free="$4}')"
du -sh artifacts
