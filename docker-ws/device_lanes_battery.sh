#!/bin/bash
# Container-side: run sims device lanes one at a time on the release tree, checking the Pixel battery before each.
# Under 15 percent it waits (up to 2 h) until the level is back at 30 or more.
#   bash docker-ws/device_lanes_battery.sh <evidence-dir-relative> <tree under build/> <lane>...
EV="$1"; TREE="$2"; shift 2
export ADB_SERVER_SOCKET=tcp:host.docker.internal:5037
lvl() { /claude-host-bin/adb -s 21071FDF600CSC shell dumpsys battery 2>/dev/null | sed -n 's/^  level: //p' | tr -d '\r'; }
for lane in "$@"; do
  L=$(lvl); echo "== $lane battery=${L:-none} $(date -u +%H:%M:%SZ)"
  if [ -z "$L" ] || [ "$L" -lt 15 ]; then
    echo "PAUSE battery=${L:-none}"
    for i in $(seq 1 240); do L=$(lvl); [ -n "$L" ] && [ "$L" -ge 30 ] && break; sleep 30; done
    [ -z "$L" ] || [ "$L" -lt 30 ] && { echo "STOP battery still low"; exit 5; }
  fi
  /claude-host-bin/host-run bash docker-ws/step4_main_campaigns.sh run "$lane" "$EV" "$TREE" | tail -4
  echo "== $lane done $(date -u +%H:%M:%SZ) battery=$(lvl)"
done
echo "ALL LANES DONE"
