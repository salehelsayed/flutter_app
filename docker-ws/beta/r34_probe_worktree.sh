#!/bin/bash
# Read-only: how the fix worktree's iPhone candidates were built, and its Go/iOS binding state.
W=/Volumes/CrucialX9/flutter_app-r2-fixes-20261001
L=$W/.codex-test-logs/r2-open-issues
ls "$L" 2>/dev/null | head -40
for d in candidate-normal-profile-final candidate-profile; do
  [ -d "$L/$d" ] || continue
  echo "== $d"; ls "$L/$d" | head
  P="$L/$d/Runner.app/Info.plist"; [ -f "$P" ] && echo "version $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$P") build $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$P")"
done
grep -rhoE -- "--dart-define[= ][A-Z_]+=[^ ]+|--(profile|release|debug)" "$L"/*build*.log "$L"/*/*build*.log 2>/dev/null | sort | uniq -c | head -20
ls -la "$W/ios/Frameworks" "$W"/ios/*.xcframework 2>/dev/null | head -5
grep -nE "go1\.|GOTOOLCHAIN|go_bin|GO=" "$W/scripts/ensure_go_ios_bindings.sh" | head -8
ls ~/sdk ~/go/bin 2>/dev/null | grep -i 'go1' | head
which go; go version
for u in 00008030-001A6D2801BB802E 00008110-00184D622289801E; do
  J=$(mktemp); xcrun devicectl device info apps --device $u --json-output $J >/dev/null 2>&1
  python3 -c "import json,sys;[print('$u', a.get('bundleVersion'), a.get('version')) for a in json.load(open('$J'))['result']['apps'] if a.get('bundleIdentifier')=='com.mknoon.app']"
done
