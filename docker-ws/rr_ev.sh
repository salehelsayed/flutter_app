#!/bin/bash
# Discovery-fix proof: print "ts event [stage/reason]" for the TEST package's flow lines only (the Pixel's own com.mknoon.app also logs FLOW).
#   df_ev.sh [regex]
S=21071FDF600CSC; P=$(adb -s $S shell pidof com.mknoon.sims.t011 | tr -d '\r')
[ -z "$P" ] && { echo "test app not running"; exit 1; }
adb -s $S logcat -d -v epoch 2>/dev/null | awk -v p="$P" '$2==p' | grep -a '\[FLOW\]' | \
  sed -E 's/.*"ts":"[0-9-]+T([0-9:.]+)Z".*"event":"([A-Z0-9_]+)"(.*)/\1 \2 \3/' | \
  sed -E 's/"(peerId|sessionId|host)":"[^"]*",?//g' | cut -c1-160 | grep -a -E "${1:-LOCAL_MDNS|MIGRATION|RESOLVE}"
