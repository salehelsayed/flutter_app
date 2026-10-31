#!/bin/bash
# Erase notification-state proof: disposable iOS simulator helper.
#   list | create | boot <udid> | install <udid> | launch <udid> | terminate <udid> | pbpaste <udid>
#   | data <udid> | shutdown <udid> | delete <udid> | shot <udid> <png-in-evid>
set -uo pipefail
E=/Volumes/CrucialX9/flutter_app/.codex-test-logs/erase-notif-state-20261023T2145Z
APP=/Volumes/CrucialX9/flutter_app/build/wt-astra3/build/ios/iphonesimulator/Runner.app
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
  pbcopyfile) xcrun simctl pbcopy "$U" < "$3" && echo copied ;;
  pbpaste) xcrun simctl pbpaste "$U" ;;
  data) D=$(xcrun simctl get_app_container "$U" "$BID" data); echo "$D"
    find "$D" -type f \( -name '*.jpg' -o -name '*.mp4' -o -name '*.m4a' -o -name '*.pdf' \) -not -path '*/tmp/*' -exec shasum -a 256 {} \; | sed "s|$D/||" ;;
  notif) for K in data groups; do D=$(xcrun simctl get_app_container "$U" "$BID" $K 2>/dev/null)
      if [ "$K" = groups ]; then D=$(echo "$D" | awk '/group.com.mknoon.app.share/ {print $2}'); fi
      echo "== $K $( [ -n "$D" ] && echo found || echo none)"
      [ -n "$D" ] && find "$D" \( -name ReactionNotificationClaims -o -name NotificationConversationIds -o -name PendingConversationNotificationOverlay -o -name NotificationServiceDedupe -o -name NotificationToneLeases -o -name RecentRemoteShown -o -name 'mknoon_recent_remote_notifications.json*' -o -name .NotificationServiceDedupe.lock -o -name identity.db \) 2>/dev/null | while read -r x; do n=$(find "$x" -type f 2>/dev/null | wc -l | tr -d ' '); echo "$n ${x#$D/}"; done
    done ;;
  seed) for K in data groups; do D=$(xcrun simctl get_app_container "$U" "$BID" $K 2>/dev/null)
      if [ "$K" = groups ]; then D=$(echo "$D" | awk '/group.com.mknoon.app.share/ {print $2}'); else D="$D/Library/Application Support"; fi
      [ -d "$D" ] || { echo "== $K no dir"; continue; }
      for d in ReactionNotificationClaims NotificationConversationIds PendingConversationNotificationOverlay NotificationServiceDedupe NotificationToneLeases RecentRemoteShown mknoon_recent_remote_notifications.json.aliases; do [ -e "$D/$d" ] || { mkdir -p "$D/$d" && echo seed > "$D/$d/seed_fixture"; }; done
      for f in mknoon_recent_remote_notifications.json.account .NotificationServiceDedupe.lock; do [ -e "$D/$f" ] || echo seed > "$D/$f"; done
      echo "== $K seeded"; done ;;
  list10) for K in data groups; do D=$(xcrun simctl get_app_container "$U" "$BID" $K 2>/dev/null)
      if [ "$K" = groups ]; then D=$(echo "$D" | awk '/group.com.mknoon.app.share/ {print $2}'); else D="$D/Library/Application Support"; fi
      echo "== $K $( [ -d "$D" ] && echo dir || echo nodir)"
      for x in ReactionNotificationClaims NotificationConversationIds PendingConversationNotificationOverlay NotificationServiceDedupe NotificationToneLeases RecentRemoteShown mknoon_recent_remote_notifications.json mknoon_recent_remote_notifications.json.account mknoon_recent_remote_notifications.json.aliases .NotificationServiceDedupe.lock; do
        if [ -d "$D/$x" ]; then echo "dir $x files=$(find "$D/$x" -type f | wc -l | tr -d ' ')"; elif [ -f "$D/$x" ]; then echo "file $x"; else echo "absent $x"; fi; done; done
    DD=$(xcrun simctl get_app_container "$U" "$BID" data); echo "identity_db=$(find "$DD" -name 'identity.db*' | wc -l | tr -d ' ') media=$(find "$DD" -path '*media*' -type f | wc -l | tr -d ' ')" ;;
  erasecheck) xcrun simctl spawn "$U" log show --last 15m --style compact --predicate 'eventMessage CONTAINS "ERASE" OR eventMessage CONTAINS "FATAL"' 2>/dev/null | grep -o -E 'ACCOUNT_[A-Z_]*ERASE[A-Z_]*|FATAL[A-Z_ ]*' | sort | uniq -c ;;
  fatalctx) xcrun simctl spawn "$U" log show --last 20m --style compact --predicate 'eventMessage CONTAINS "FATAL"' 2>/dev/null | cut -c1-220 | tail -5 ;;
  shot) xcrun simctl io "$U" screenshot "$E/shots/$3" ;;
  uninstall) xcrun simctl uninstall "$U" "$BID"; echo "rc=$?" ;;
  shutdown) xcrun simctl shutdown "$U"; echo "rc=$?" ;;
  delete) xcrun simctl delete "$U"; echo "rc=$?" ;;
  *) echo usage; exit 2 ;;
esac
