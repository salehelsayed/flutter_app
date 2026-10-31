#!/bin/bash
# Mac-side: run se41_publish.py with the Mac python (owner-approved publish only).
#   host-run bash docker-ws/se41_publish_mac.sh <signed file> <backup suffix>
cd "$(dirname "$0")/.." || exit 2
/opt/homebrew/bin/python3 -c "import paramiko" 2>/dev/null || { echo "no paramiko on the Mac python"; exit 7; }
exec /opt/homebrew/bin/python3 docker-ws/se41_publish.py "$@"
