#!/bin/bash
# Plan 406: install the NEW iOS release over the existing app on the iPhone 13
# (keeps identity and data: an in-place upgrade), launch, verify build number.
set -u
UDID=00008110-00184D622289801E
BUNDLE_ID=com.mknoon.app
APP=/Volumes/CrucialX9/flutter_app/.claude/worktrees/go-upgrade-406/build/ios/iphoneos/Runner.app
RUN_STAMP=261008164231
if command -v timeout >/dev/null 2>&1; then TO() { timeout "$@"; }; else TO() { shift; "$@"; }; fi
echo "== install"
TO 300 xcrun devicectl device install app --device "$UDID" "$APP" 2>&1 | tail -3 || { echo "FAILED(install)"; exit 1; }
echo "== launch"
TO 90 xcrun devicectl device process launch --device "$UDID" --terminate-existing "$BUNDLE_ID" 2>&1 | tail -2
J=$(mktemp)
TO 90 xcrun devicectl device info apps --device "$UDID" --json-output "$J" >/dev/null 2>&1
GOT=$(python3 - "$J" "$BUNDLE_ID" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for a in d.get("result", {}).get("apps", []):
    if a.get("bundleIdentifier") == sys.argv[2]:
        print(a.get("bundleVersion", "?")); break
else:
    print("not-installed")
PY
)
[ "$GOT" = "$RUN_STAMP" ] && echo "OK iPhone 13 runs bundleVersion=$GOT (new406)" || echo "FAILED(verify: '$GOT' != '$RUN_STAMP')"
