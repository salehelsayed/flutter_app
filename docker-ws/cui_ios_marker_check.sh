#!/bin/bash
# Confirm the diagnostic marker in the prepared Runner and NSE binaries.  host-run bash docker-ws/cui_ios_marker_check.sh
W=/Volumes/CrucialX9/flutter_app/build/wt-cui-b376
B="$W/build/sims/prepared/ios.device.production.bundle/TestProducts"
A=$(find "$B" -maxdepth 3 -name Runner.app -type d | head -1)
echo "app=${A#$W/}"
for bin in "$A/Runner" "$A/PlugIns/NotificationService.appex/NotificationService"; do
  n=$(strings -a "$bin" 2>/dev/null | grep -c MKNOON_IOS_PAYLOAD_DIAGNOSTIC_V1)
  echo "$(basename "$bin") sha=$(shasum -a 256 "$bin" | cut -c1-16) marker_count=$n"
done
ls "$A/PlugIns" 2>/dev/null
