#!/bin/bash
# Print the installed com.mknoon.app version/build on one iPhone (read-only).   host-run bash docker-ws/ios_installed_build.sh <udid>
U=${1:?udid}; T=$(mktemp)
timeout 60 xcrun devicectl device info apps --device "$U" --bundle-id com.mknoon.app --json-output "$T" >/dev/null 2>&1
python3 -c "import json,sys;a=json.load(open('$T'))['result']['apps'];print([(x.get('version'),x.get('bundleVersion')) for x in a])"; rm -f "$T"
