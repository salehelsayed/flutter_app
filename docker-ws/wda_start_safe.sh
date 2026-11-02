#!/bin/bash
# Start WebDriverAgent on one iPhone WITHOUT Appium's own xcodebuild, with -collect-test-diagnostics never, so a failing
# run never spawns sudo for diagnostics (owner prompt on 11-02). Forwards the WDA device port (USE_PORT in the xctestrun, default 8100) to <local port> with iproxy.
# Detached: survives this call. Refuses if a WDA xcodebuild for that device already runs.
#   host-run bash docker-ws/wda_start_safe.sh <udid> <local port> <log dir under repo> [extra xcodebuild args...]
set -uo pipefail
U=${1:?udid}; LP=${2:?local port}; L="/Volumes/CrucialX9/flutter_app/${3:?log dir}"; shift 3; mkdir -p "$L"
D="$HOME/Library/Developer/Xcode/DerivedData/WebDriverAgent-gkkiiuvnweforsdihdsaljhfmztm/Build/Products"
X=$(ls -t "$D"/WebDriverAgentRunner_iphoneos*.xctestrun 2>/dev/null | head -1)
[ -n "$X" ] || { echo "STOP no WDA xctestrun"; exit 2; }
if ps -axo command | grep -v grep | grep -q "WebDriverAgent.*id=$U"; then echo "STOP a WDA xcodebuild for this device already runs"; exit 3; fi
DP=$(grep -A1 "<key>USE_PORT</key>" "$X" | sed -n "s:.*<string>\([0-9]*\)</string>.*:\1:p" | head -1); DP=${DP:-8100}
echo "xctestrun=${X##*/} device_port=$DP"
nohup xcodebuild test-without-building -xctestrun "$X" -destination "id=$U" -collect-test-diagnostics never "$@" \
  > "$L/wda_xcodebuild.log" 2>&1 < /dev/null &
echo "xcodebuild pid=$!"
if ! lsof -nP -iTCP:"$LP" -sTCP:LISTEN >/dev/null 2>&1; then
  nohup /opt/homebrew/bin/iproxy "$LP" "$DP" -u "$U" > "$L/iproxy.log" 2>&1 < /dev/null &
  echo "iproxy pid=$!"
else echo "port $LP already forwarded"; fi
for i in $(seq 1 84); do
  s=$(curl -s -m 4 "http://127.0.0.1:$LP/status" | head -c 300)
  case "$s" in *'"ready"'*|*'"state"'*) echo "WDA ready after $((i*5)) s"; exit 0;; esac
  sleep 5
done
echo "WDA not ready after 420 s"; tail -5 "$L/wda_xcodebuild.log"; exit 4
