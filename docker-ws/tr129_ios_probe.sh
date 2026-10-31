#!/bin/bash
# Build-129 translation device test, read-only iOS probe.
#   host-run bash docker-ws/tr129_ios_probe.sh <11|13> [artifact]
# Prints Mknoon version/build, lock state, free space; with "artifact" also prints the built app's bundleVersion.
case "$1" in 11) U=00008030-001A6D2801BB802E;; 13) U=00008110-00184D622289801E;; *) echo "usage: 11|13"; exit 2;; esac
[ "$2" = artifact ] && /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$HOME/tmp-dd-161/Build/Products/Release-iphoneos/Runner.app/Info.plist"
J=$(mktemp)
timeout 90 /usr/bin/xcrun devicectl device info apps --device "$U" --json-output "$J" >/dev/null 2>&1 || { echo "devicectl apps failed rc=$?"; }
python3 - "$J" <<'PY'
import json, sys
try: d = json.load(open(sys.argv[1]))
except Exception: d = {}
hit = [a for a in d.get("result", {}).get("apps", []) if a.get("bundleIdentifier") == "com.mknoon.app"]
for a in hit: print("mknoon version=", a.get("version"), "build=", a.get("bundleVersion"))
if not hit: print("mknoon not found")
PY
timeout 60 /usr/bin/xcrun devicectl device info lockState --device "$U" 2>&1 | grep -iE 'passcode|unlocked' | head -3
K=$(mktemp); timeout 60 /usr/bin/xcrun devicectl device info details --device "$U" --json-output "$K" >/dev/null 2>&1
python3 - "$K" <<'PY'
import json, sys
try: d = json.load(open(sys.argv[1]))["result"]
except Exception: print("details failed"); sys.exit()
dp = d.get("deviceProperties", {}); hp = d.get("hardwareProperties", {})
print("os", dp.get("osVersionNumber"), "ram?", hp.get("internalStorageCapacity"))
PY
rm -f "$J" "$K"
