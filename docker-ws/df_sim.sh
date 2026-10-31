#!/bin/bash
# Safe Transfer rows: disposable iOS simulator helper.
#   list | create | boot <udid> | install <udid> | launch <udid> | terminate <udid> | pbpaste <udid>
#   | data <udid> | shutdown <udid> | delete <udid> | shot <udid> <png-in-evid>
set -uo pipefail
E=/Volumes/CrucialX9/flutter_app/.codex-test-logs/discovery-fix-20261023T1820Z
APP=/Volumes/CrucialX9/flutter_app/build/wt-t011/build/ios/iphonesimulator/Runner.app
BID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist" 2>/dev/null)
U="${2:-}"
case "${1:-list}" in
  list) xcrun simctl list devices | grep -E "T011|--" | head -40 ;;
  create) RT=$(xcrun simctl list runtimes available | grep -o 'com.apple.CoreSimulator.SimRuntime.iOS-[0-9-]*' | tail -1)
    xcrun simctl create T011-receiver "com.apple.CoreSimulator.SimDeviceType.iPhone-16" "$RT" || xcrun simctl create T011-receiver "iPhone 15" "$RT" ;;
  boot) xcrun simctl boot "$U"; xcrun simctl bootstatus "$U" -b | tail -1 ;;
  install) echo "bid=$BID"; xcrun simctl install "$U" "$APP" && echo installed ;;
  launch) xcrun simctl launch "$U" "$BID" ;;
  terminate) xcrun simctl terminate "$U" "$BID"; echo "rc=$?" ;;
  pbpaste) xcrun simctl pbpaste "$U" ;;
  data) D=$(xcrun simctl get_app_container "$U" "$BID" data); echo "$D"
    find "$D" -type f \( -name '*.jpg' -o -name '*.mp4' -o -name '*.m4a' -o -name '*.pdf' \) -not -path '*/tmp/*' -exec shasum -a 256 {} \; | sed "s|$D/||" ;;
  shot) xcrun simctl io "$U" screenshot "$E/shots/$3" ;;
  uninstall) xcrun simctl uninstall "$U" "$BID"; echo "rc=$?" ;;
  shutdown) xcrun simctl shutdown "$U"; echo "rc=$?" ;;
  delete) xcrun simctl delete "$U"; echo "rc=$?" ;;
  *) echo usage; exit 2 ;;
esac
