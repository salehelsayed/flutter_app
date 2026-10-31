#!/bin/bash
# Probe: does idevicesyslog keep writing after a devicectl launch on the Codex-UI iPhone 11?  Prints sizes only.
#   host-run bash docker-ws/cui_syslog_stall_probe.sh <out-dir-in-repo>
set -u
cd "$(dirname "$0")/.."
UDID=00008030-001A6D2801BB802E
OUT="${1:?out dir}"; mkdir -p "$OUT"; chmod 700 "$OUT"; F="$OUT/probe.raw.log"; rm -f "$F"
idevicesyslog -u "$UDID" --no-colors --output "$F" >/dev/null 2>&1 &
P=$!
for t in 10 20 30 40; do sleep 10; echo "t=${t}s size=$(stat -f %z "$F" 2>/dev/null || echo 0) alive=$(kill -0 $P 2>/dev/null && echo y || echo n)"; done
perl -e 'alarm 40; exec @ARGV' xcrun devicectl device process launch --device "$UDID" com.apple.Preferences >/dev/null 2>&1; echo "launch rc=$?"
for t in 50 60 70 80 90 100; do sleep 10; echo "t=${t}s size=$(stat -f %z "$F" 2>/dev/null || echo 0) alive=$(kill -0 $P 2>/dev/null && echo y || echo n)"; done
kill $P 2>/dev/null; sleep 1; kill -9 $P 2>/dev/null
rm -f "$F"
