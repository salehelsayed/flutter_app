#!/bin/bash
# Host-side disk check: did deleting docker-ws/iphone13_syslog.txt actually
# reclaim space, or is a writer still holding the unlinked inode open?
# Run: /claude-host-bin/host-run bash docker-ws/check_disk_reclaim.sh
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
echo "== file present on host? =="
ls -l "$REPO/docker-ws/iphone13_syslog.txt" 2>&1 | head -2
echo "== host df for the repo volume =="
df -h "$REPO" | tail -2
echo "== any process holding a deleted/unlinked file in the repo =="
lsof +D "$REPO/docker-ws" 2>/dev/null | head -15
echo "== any process with 'syslog' or 'iphone13' open =="
lsof 2>/dev/null | grep -iE "iphone13|idevicesyslog|_syslog" | head -10
