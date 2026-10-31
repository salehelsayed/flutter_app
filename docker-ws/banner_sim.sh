#!/bin/bash
# Banner proof simulator helper (disposable simulator CS-receiver, app from build/wt-banner).
#   list | create | boot <udid> | install <udid> | launch <udid> | launch_console <udid> <log-in-evid> | terminate <udid>
#   | pid <udid> | logstream <udid> <log> | stoppid <udid> <pid> | shot <udid> <png-in-evid> | uninstall <udid> | shutdown <udid> | pbcopy <udid> <file-in-evid>
set -uo pipefail
E=/Volumes/CrucialX9/flutter_app/.codex-test-logs/banner-fix-20261025T1856Z
APP=/Volumes/CrucialX9/flutter_app/build/wt-banner/build/ios/iphonesimulator/Runner.app
BID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist" 2>/dev/null)
U="${2:-}"
case "${1:-list}" in
  list) xcrun simctl list devices | grep -E "CS-receiver|Booted" | head -20 ;;
  create) RT=$(xcrun simctl list runtimes available | grep -o 'com.apple.CoreSimulator.SimRuntime.iOS-[0-9-]*' | tail -1)
    xcrun simctl create CS-receiver "com.apple.CoreSimulator.SimDeviceType.iPhone-16" "$RT" || xcrun simctl create CS-receiver "iPhone 15" "$RT" ;;
  boot) xcrun simctl boot "$U"; xcrun simctl bootstatus "$U" -b | tail -1 ;;
  install) echo "bid=$BID"; xcrun simctl install "$U" "$APP" && echo installed ;;
  launch) xcrun simctl launch "$U" "$BID" ;;
  launch_console) nohup xcrun simctl launch --console-pty --terminate-running-process "$U" "$BID" > "$E/$3" 2>&1 < /dev/null & echo "console pid $!" ;;
  terminate) xcrun simctl terminate "$U" "$BID"; echo "rc=$?" ;;
  pid) xcrun simctl spawn "$U" launchctl list | grep -i "$BID" | head -3 ;;
  shot) T=$(mktemp -t cs_shot).png; xcrun simctl io "$U" screenshot "$T" >/dev/null 2>&1 && cp "$T" "$E/$3" && rm -f "$T" && echo "saved $3" ;;
  logstream) nohup xcrun simctl spawn "$U" log stream --style compact --level debug --predicate 'process == "Runner"' > "$E/$3" 2>&1 < /dev/null & echo "logstream pid $!" ;;
  logshow) xcrun simctl spawn "$U" log show --style compact --start "$3" --predicate 'process == "Runner"' > "$E/$4" 2>&1; echo "lines $(wc -l < "$E/$4")" ;;
  stoppid) ps -p "$3" -o command= | grep -q -E 'simctl (spawn .* log stream|launch --console-pty)' && kill "$3" && echo "stopped $3" || echo "refused $3" ;;
  uninstall) xcrun simctl uninstall "$U" "$BID"; echo "rc=$?" ;;
  shutdown) xcrun simctl shutdown "$U"; echo "rc=$?" ;;
  kill_settings) xcrun simctl terminate "$U" com.apple.Preferences; echo "rc=$?" ;;
  open_url) xcrun simctl openurl "$U" "$3"; echo "rc=$?" ;;
  *) echo usage; exit 2 ;;
esac
