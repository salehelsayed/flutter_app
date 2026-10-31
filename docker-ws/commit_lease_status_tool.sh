#!/bin/bash
# Commit scripts/lease_status.py + its test onto a new branch lease-status-tool from a345dee2f, without touching the checkout or index.
set -euo pipefail
cd "$(dirname "$0")/.."
BASE=a345dee2f59f42a84a6a3012a871d1792a270628
git rev-parse -q --verify refs/heads/lease-status-tool >/dev/null && { echo "branch exists"; exit 3; }
export GIT_INDEX_FILE="$(mktemp -d)/index"
git read-tree "$BASE"
git update-index --add --chmod=+x scripts/lease_status.py
git update-index --add scripts/test/lease_status_test.py
[ "$(git diff --cached --name-only "$BASE" | sort | tr '\n' ' ')" = "scripts/lease_status.py scripts/test/lease_status_test.py " ] || { echo "unexpected staged set"; exit 3; }
T=$(git write-tree)
C=$(printf 'tool(lease): read-only lease status script for shared native-build and device leases\n\nReports FREE or HELD with holder pid, age, cwd and command using lsof and ps only;\nnever flock-probes or takes a lease. --json for machine use.\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n' | git commit-tree "$T" -p "$BASE")
git update-ref refs/heads/lease-status-tool "$C"
echo "$C $T"
