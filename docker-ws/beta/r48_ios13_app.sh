#!/bin/bash
# Read-only: the installed Mknoon app on the iPhone 13 (version, build, install path).
U=${1:-00008110-00184D622289801E}
xcrun devicectl device info apps --device "$U" --bundle-id com.mknoon.app --json-output /tmp/r48_apps.json >/dev/null 2>&1
python3 -c 'import json;d=json.load(open("/tmp/r48_apps.json"));[print({k:a.get(k) for k in ("bundleVersion","version","url","name")}) for a in d["result"]["apps"]]'
ls -la -t /Volumes/CrucialX9/flutter_app-ui-update/build/ios/iphoneos 2>/dev/null | head -3
ls -la -t /Volumes/CrucialX9/flutter_app/build/ios/iphoneos 2>/dev/null | head -3
git -C /Volumes/CrucialX9/flutter_app-ui-update log -1 --format='%h %ci %s' 2>/dev/null
