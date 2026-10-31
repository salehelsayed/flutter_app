#!/bin/bash
# Container-side: run KX row groups (and then device-media N times) on the release-127 tree, each with
# Mac-side logcat on both Androids. Battery check before each step; under 15 percent it stops.
#   bash docker-ws/release127_rows_with_logs.sh <evidence-dir-relative> <media-runs> <kx-group>...
EV="$1"; MEDIA="$2"; shift 2
CFG=.codex-test-logs/release-127-devices-20261026T1000Z/device-config.json
export ADB_SERVER_SOCKET=tcp:host.docker.internal:5037
lvl() { /claude-host-bin/adb -s 21071FDF600CSC shell dumpsys battery 2>/dev/null | sed -n 's/^  level: //p' | tr -d '\r'; }
step() {
  local name="$1"; shift
  L=$(lvl); echo "== $name battery=${L:-none} $(date -u +%H:%M:%SZ)"
  [ -z "$L" ] || [ "$L" -lt 15 ] && { echo "STOP battery"; exit 5; }
  /claude-host-bin/host-run bash docker-ws/logcat_capture.sh 21071FDF600CSC "$EV/$name-pixel.log" 7200 > /dev/null 2>&1 &
  P1=$!
  /claude-host-bin/host-run bash docker-ws/logcat_capture.sh emulator-5554 "$EV/$name-emu.log" 7200 > /dev/null 2>&1 &
  P2=$!
  sleep 8
  "$@" | tail -14
  echo "== $name done $(date -u +%H:%M:%SZ)"
  touch "$EV/$name-pixel.log.stop" "$EV/$name-emu.log.stop"
  wait $P1 $P2
  wc -c "$EV/$name-pixel.log" "$EV/$name-emu.log" | head -2
}
for g in "$@"; do
  step "kx-$(echo "$g" | tr ',' '-')" /claude-host-bin/host-run bash docker-ws/kx_rows_campaign.sh wt-release-127 "$g" "$EV" "$CFG"
done
for i in $(seq 1 "$MEDIA"); do
  step "media-$i" /claude-host-bin/host-run bash docker-ws/step4_main_campaigns.sh run device-media "$EV" wt-release-127
done
echo "ALL ROWS DONE"
