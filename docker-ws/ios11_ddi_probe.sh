#!/bin/bash
# Read-only: show and (re)mount the developer disk image services on the iPhone 11 via CoreDevice, then list tools.
#   host-run bash docker-ws/ios11_ddi_probe.sh <out-file-in-repo>
U=00008030-001A6D2801BB802E; O="$1"
{ echo "== ddiServices $(date -u +%TZ)"; timeout 180 /usr/bin/xcrun devicectl device info ddiServices --device "$U" 2>&1 | tail -25
  echo "== lockState"; timeout 60 /usr/bin/xcrun devicectl device info lockState --device "$U" 2>&1 | tail -6
  echo "== tools"; command -v pymobiledevice3 idevicescreenshot ideviceimagemounter 2>&1
  echo "== end $(date -u +%TZ)"; } > "$O" 2>&1
