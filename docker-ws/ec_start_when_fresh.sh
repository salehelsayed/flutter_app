#!/bin/bash
# Wait (up to $1 s, default 120) until the newest local discovery event is a PEER_FOUND at most 6 s old, then tap Start transfer on the Pixel.
S=21071FDF600CSC; LIM=${1:-120}; END=$(( $(date +%s) + LIM ))
while [ "$(date +%s)" -lt "$END" ]; do
  L=$(adb -s $S logcat -d -v epoch 2>/dev/null | grep -a -E "LOCAL_MDNS_(PEER_FOUND|PEER_SKIPPED_NO_LIBP2P_ADDR|PEER_STALE|PEER_LOST)" | tail -1)
  T=$(echo "$L" | awk '{print int($1)}'); D=$(adb -s $S shell date +%s | tr -d '\r')
  if echo "$L" | grep -q '"LOCAL_MDNS_PEER_FOUND"' && [ -n "$T" ] && [ $((D - T)) -le 6 ]; then
    echo "fresh PEER_FOUND age $((D - T))s"; python3 "$(dirname "$0")/ec_ap.py" px tap "desc:Start transfer"; date -u +"start %H:%M:%S"; exit 0
  fi
  sleep 1
done
echo "no fresh PEER_FOUND within $LIM s"; exit 1
