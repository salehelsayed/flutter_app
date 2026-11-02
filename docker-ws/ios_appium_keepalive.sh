#!/bin/bash
# Keep one Appium session alive on iPhone 11 and iPhone 13 (owner rule 2026-11-02: no PIN prompts). Every 5 min it reads the
# app state of each session (no taps); if the session is missing or dead it opens a new one. Prints one line per check.
# Exits with NEEDS_OWNER if an open fails twice in a row (for example a passcode or Face ID is needed after a reboot).
#   bash docker-ws/ios_appium_keepalive.sh          (run as a tracked background job, never with & or disown)
cd /workspace/docker-ws/beta || exit 2
declare -A fails=([11]=0 [13]=0)
while true; do
  for p in 11 13; do
    st=$(timeout 60 python3 ap.py "$p" app state 2>&1 | tail -1)
    if [[ "$st" =~ ^[0-9]+$ ]]; then fails[$p]=0; echo "$(date -u +%T) iPhone $p alive state=$st"; continue; fi
    echo "$(date -u +%T) iPhone $p session down ($st), reopening"
    # Never reopen through Appium's own xcodebuild: a failing WDA test run spawns sudo (owner prompt, 11-02).
    # Restart WDA with docker-ws/wda_start_safe.sh, then: AP_WDA_URL=http://127.0.0.1:<port> ap.py <phone> open
    echo "NEEDS_SAFE_START iPhone $p: run wda_start_safe.sh, then attach with AP_WDA_URL"; exit 3
    o=$(timeout 600 python3 ap.py "$p" open 2>&1 | tail -1)
    if [[ "$o" == session* ]]; then fails[$p]=0; echo "$(date -u +%T) iPhone $p reopened"; else
      fails[$p]=$(( fails[$p] + 1 )); echo "$(date -u +%T) iPhone $p reopen failed: ${o:0:160}"
      [ "${fails[$p]}" -ge 2 ] && { echo "NEEDS_OWNER iPhone $p: two reopen attempts failed"; exit 3; }
    fi
  done
  sleep 300
done
