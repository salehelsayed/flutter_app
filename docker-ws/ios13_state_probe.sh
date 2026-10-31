#!/bin/bash
# Read-only: lock state, DDI services, display info and installed test runners on the iPhone 13 via CoreDevice.
#   host-run bash docker-ws/ios13_state_probe.sh <out-file-in-repo>
U=00008110-00184D622289801E; O="$1"
{ echo "== lockState $(date -u +%TZ)"; timeout 60 /usr/bin/xcrun devicectl device info lockState --device "$U" 2>&1 | tail -8
  echo "== ddiServices"; timeout 120 /usr/bin/xcrun devicectl device info ddiServices --device "$U" 2>&1 | tail -15
  echo "== displays"; timeout 60 /usr/bin/xcrun devicectl device info displays --device "$U" 2>&1 | tail -12
  echo "== runner apps"; timeout 120 /usr/bin/xcrun devicectl device info apps --device "$U" 2>&1 | grep -iE 'xctrunner|webdriveragent|runnerui|Name ' | head -20
  echo "== end $(date -u +%TZ)"; } > "$O" 2>&1
