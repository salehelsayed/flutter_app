#!/bin/bash
# Read-only AWS relay identity check for the 129 pre-publish lanes. The SSH key is used by path only.
set -uo pipefail
M=/Volumes/CrucialX9/flutter_app; SK="$M/se.pem"; [ -f "$SK" ] || { echo "relay SSH key missing"; exit 3; }
ssh -i "$SK" -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new ubuntu@51.21.194.144 \
  'echo "active=$(systemctl is-active relay-server) since=$(systemctl show relay-server -p ActiveEnterTimestamp --value)"; sha256sum /usr/local/bin/relay-server; sudo journalctl -u relay-server --no-pager | grep -aE "Starting relay-server v" | tail -1 | grep -aoE "Starting relay-server v[0-9.]+"'
