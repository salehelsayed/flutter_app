#!/bin/bash
# Read-only: what is big in the live checkout? Used to pick rsync excludes for
# the isolated proof checkout.
#   /claude-host-bin/host-run bash docker-ws/proof_checkout_size_probe.sh
set -uo pipefail
SRC=/Volumes/CrucialX9/flutter_app
cd "$SRC" || exit 2
echo "=== top-level entries by size ==="
du -sk -- * .[!.]* 2>/dev/null | sort -n | tail -30 | awk '{printf "%8.2f GB  %s\n", $1/1048576, $2}'
echo "=== heaviest nested dirs (depth 3) ==="
du -k -d 3 . 2>/dev/null | sort -n | tail -25 | awk '{printf "%8.2f GB  %s\n", $1/1048576, $2}'
