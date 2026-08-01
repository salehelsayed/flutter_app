#!/usr/bin/env bash
# Read-only probe: is any git process actually holding /workspace/.git/index.lock?
# The checkout is shared with concurrent sessions, so a lock must never be
# removed on age alone — only when no holder exists.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LOCK="$REPO/.git/index.lock"

echo "=== lock ==="
ls -l "$LOCK" 2>/dev/null || { echo "no lock present"; exit 0; }

echo "=== git processes on host ==="
ps -eo pid,etime,command | grep -E '[g]it ' | head -20 || echo "(none)"

echo "=== processes with the lock file open (lsof) ==="
lsof "$LOCK" 2>/dev/null || echo "(no open file handles — lock is not held by a live process)"

echo "=== git processes touching this repo ==="
ps -eo pid,etime,command | grep -F "$REPO" | grep -E '[g]it' | head -10 || echo "(none)"
