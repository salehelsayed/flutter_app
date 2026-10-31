#!/bin/bash
# Read-only: is com.mknoon.app installed on the iPhone 11, and its bundle version.
J=$(mktemp); timeout 90 xcrun devicectl device info apps --device 00008030-001A6D2801BB802E --json-output "$J" >/dev/null 2>&1 || { echo "UNREACHABLE"; exit 1; }
python3 - "$J" <<'PY'
import json,sys
apps=json.load(open(sys.argv[1]))['result']['apps']
m=[a for a in apps if a.get('bundleIdentifier')=='com.mknoon.app']
print('mknoon installed' if m else 'mknoon NOT installed', m[0].get('bundleVersion') if m else '')
PY
