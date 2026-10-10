#!/bin/bash
# Plan 406: iPhone 13 reachability + installed Mknoon version.
UDID=00008110-00184D622289801E
if command -v timeout >/dev/null 2>&1; then TO() { timeout "$@"; }; else TO() { shift; "$@"; }; fi
TO 45 xcrun devicectl device info details --device "$UDID" 2>&1 | grep -iE "name|state|ddiServices|developerMode|bootState|transport" | head -8
J=$(mktemp)
TO 60 xcrun devicectl device info apps --device "$UDID" --json-output "$J" >/dev/null 2>&1
python3 - "$J" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    print("apps: unreadable", e); sys.exit()
for a in d.get("result", {}).get("apps", []):
    if a.get("bundleIdentifier") == "com.mknoon.app":
        print("mknoon:", a.get("version"), "build", a.get("bundleVersion")); break
else:
    print("mknoon: not installed")
PY
