#!/usr/bin/env bash
# Plan 321: decode the provisioning profile embedded in the built Runner.app and
# report which of our phones it authorizes. This is the decisive evidence for
# install error 0xe8008012 ("profile cannot be installed on this device").
set -uo pipefail
cd "$(dirname "$0")/../.."
APP=build/ios/iphoneos/Runner.app
PROF="$APP/embedded.mobileprovision"
[ -f "$PROF" ] || { echo "NO EMBEDDED PROFILE at $PROF"; exit 2; }

security cms -D -i "$PROF" > /tmp/prof321.plist 2>/dev/null
echo "=== profile identity ==="
/usr/libexec/PlistBuddy -c 'Print :Name' /tmp/prof321.plist 2>/dev/null
/usr/libexec/PlistBuddy -c 'Print :TeamName' /tmp/prof321.plist 2>/dev/null
/usr/libexec/PlistBuddy -c 'Print :ExpirationDate' /tmp/prof321.plist 2>/dev/null
echo
echo "=== provisioned devices ==="
python3 - <<'PY'
import plistlib, subprocess
raw = open('/tmp/prof321.plist','rb').read()
p = plistlib.loads(raw)
devs = p.get('ProvisionedDevices', [])
print(f"count={len(devs)}")
ours = {
 "00008030-001A6D2801BB802E": "Saleh's iPhone (installed OK)",
 "00008110-00184D622289801E": "iPhone 26.5 (installed OK)",
 "00008150-001C3C6A3684401C": "Saleh's iPhone wireless (FAILED 0xe8008012)",
 "00008101-000E2C263EA1001E": "iPhone 18.6.2 (FAILED 1011)",
}
for udid, label in ours.items():
    print(("IN PROFILE     " if udid in devs else "NOT IN PROFILE ") + udid + "  " + label)
PY
