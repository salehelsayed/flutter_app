#!/bin/bash
# Read-only idle check: lock state and whether Mknoon (Runner) is running.   host-run bash docker-ws/tr129_ios_idle.sh <11|13>
case "$1" in 11) U=00008030-001A6D2801BB802E;; 13) U=00008110-00184D622289801E;; *) echo usage; exit 2;; esac
date -u +%FT%TZ
timeout 60 /usr/bin/xcrun devicectl device info lockState --device "$U" 2>&1 | grep -iE 'passcode|unlocked' | head -2
J=$(mktemp); timeout 90 /usr/bin/xcrun devicectl device info processes --device "$U" --json-output "$J" >/dev/null 2>&1
python3 - "$J" <<'PY'
import json,sys
try: p=json.load(open(sys.argv[1]))["result"]["runningProcesses"]
except Exception: print("processes failed"); sys.exit()
print("mknoon running:", any("Runner.app/Runner" in (x.get("executable") or "") for x in p))
PY
rm -f "$J"
