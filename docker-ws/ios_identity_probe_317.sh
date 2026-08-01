#!/usr/bin/env bash
# TC-08 topology probe: launch mknoon on the iPhone 13 and capture ~18s of
# device syslog to learn the app's identity/roster hints from [FLOW] lines.
set -u
UDID="93B4C4D0-F4B7-50F6-B130-0A7578BA4E9E"
OUT="docker-ws/ios_identity_probe_317.log"
idevicesyslog -u "$UDID" > "$OUT.raw" 2>&1 &
SYSPID=$!
sleep 2
xcrun devicectl device process launch --device "$UDID" com.mknoon.app >/dev/null 2>&1
sleep 18
kill "$SYSPID" 2>/dev/null
grep -aE 'mknoon|FLOW|Runner' "$OUT.raw" | tail -120 > "$OUT"
wc -l "$OUT"
