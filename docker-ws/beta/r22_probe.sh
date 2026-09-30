#!/bin/bash
# R2-2 validation, read-only probe: booted simulators, other running Mknoon apps, installed iPhone build,
# the dns-sd tool, existing _mknoon._tcp adverts, recent Runner crash reports, Mac load.
. "$(dirname "$0")/beta_env.sh"
echo "=== booted sims"; xcrun simctl list devices booted | grep -v '^=='
echo "=== Runner processes"; ps -axo pid,etime,command | grep -E 'Runner.app/Runner|/Runner$' | grep -v grep | cut -c1-220
echo "=== installed ios build"
APP=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" app)
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist"; /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist"
ls -ld "$APP"
echo "=== app running?"; xcrun simctl spawn "$UDID" launchctl list | grep -i mknoon
echo "=== dns-sd usage"; dns-sd 2>&1 | head -45
echo "=== _mknoon._tcp adverts now (4 s browse)"
dns-sd -B _mknoon._tcp local. > /tmp/r22_browse.txt 2>&1 & p=$!; sleep 4; kill $p 2>/dev/null; cat /tmp/r22_browse.txt | head -20
echo "=== recent Runner crash reports"; ls -lt ~/Library/Logs/DiagnosticReports/Runner-*.ips 2>/dev/null | head -5
echo "=== mac hostname"; scutil --get LocalHostName
echo "=== load"; uptime
