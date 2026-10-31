#!/bin/bash
# Read-only: Mknoon name/version/build on the iPhone 13 (no other app data printed).
#   host-run bash docker-ws/ios11_mknoon_version.sh
U=00008110-00184D622289801E
J=$(mktemp)
timeout 90 /usr/bin/xcrun devicectl device info apps --device "$U" --json-output "$J" >/dev/null 2>&1 || { echo "devicectl failed rc=$?"; exit 1; }
python3 - "$J" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
hit = [a for a in d.get("result", {}).get("apps", []) if a.get("bundleIdentifier", "").startswith("com.mknoon")]
for a in hit: print(a.get("bundleIdentifier"), a.get("name"), "version=", a.get("version"), "build=", a.get("bundleVersion"))
if not hit: print("com.mknoon.app not-installed")
PY
timeout 60 /usr/bin/xcrun devicectl device info lockState --device "$U" 2>&1 | grep -iE 'passcode|unlocked' | head -3
