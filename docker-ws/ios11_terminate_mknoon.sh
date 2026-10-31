#!/bin/bash
# Find com.mknoon.app's PID on the iPhone 11 by its bundle path, and terminate exactly that PID.
#   host-run bash docker-ws/ios11_terminate_mknoon.sh pid          print the PID (or none)
#   host-run bash docker-ws/ios11_terminate_mknoon.sh kill <pid>   terminate after re-checking the PID is com.mknoon.app
U=00008030-001A6D2801BB802E; J=$(mktemp); P=$(mktemp)
timeout 90 /usr/bin/xcrun devicectl device info apps --device "$U" --json-output "$J" >/dev/null 2>&1
timeout 90 /usr/bin/xcrun devicectl device info processes --device "$U" --json-output "$P" >/dev/null 2>&1
PID=$(python3 - "$J" "$P" <<'PY'
import json, sys
apps = json.load(open(sys.argv[1]))["result"]["apps"]; procs = json.load(open(sys.argv[2]))["result"]["runningProcesses"]
url = next(a["url"].rstrip("/") for a in apps if a.get("bundleIdentifier") == "com.mknoon.app")
print(" ".join(str(p["processIdentifier"]) for p in procs if p.get("executable", "") == url + "/Runner"))
import sys as _s
_s.stderr.write("all: " + " ".join(f"{p['processIdentifier']}={p['executable'][len(url)+1:]}" for p in procs if p.get("executable", "").startswith(url + "/")) + "\n")
PY
)
rm -f "$J" "$P"
case "$1" in
  pid) echo "mknoon_pid ${PID:-none} $(date -u +%TZ)" ;;
  kill)
    [[ "$2" =~ ^[0-9]+$ ]] || { echo "bad pid"; exit 2; }
    [ "$PID" = "$2" ] || { echo "pid $2 is not com.mknoon.app (now: ${PID:-none})"; exit 3; }
    timeout 90 /usr/bin/xcrun devicectl device process terminate --device "$U" --pid "$2" 2>&1 | tail -1
    echo "terminated $2 $(date -u +%TZ)" ;;
  *) echo "usage: pid | kill <pid>"; exit 2 ;;
esac
