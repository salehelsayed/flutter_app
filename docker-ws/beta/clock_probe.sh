#!/bin/bash
# Read-only: compare Mac, emulator and network (NTP / HTTPS Date) clocks.
. "$(dirname "$0")/beta_env.sh"
echo "mac now:      $(date -u '+%H:%M:%S')"
echo "--- mac vs NTP (query only, never sets the clock)"
sntp -t 3 time.apple.com 2>&1 | tail -2
echo "--- mac network time settings"
systemsetup -getusingnetworktime 2>&1 | head -1
systemsetup -getnetworktimeserver 2>&1 | head -1
echo "--- HTTPS Date headers (server clocks)"
for u in https://www.google.com https://mknoun.xyz; do
  printf '%s  mac=%s  server=%s\n' "$u" "$(date -u '+%H:%M:%S')" \
    "$(curl -sI --max-time 5 "$u" 2>/dev/null | tr -d '\r' | awk -F': ' 'tolower($1)=="date"{print $2}')"
done
echo "--- emulator"
echo "emu now:      $($ADB shell date -u '+%H:%M:%S')   mac: $(date -u '+%H:%M:%S')"
$ADB shell settings get global auto_time | sed 's/^/auto_time: /'
$ADB shell dumpsys network_time_update_service 2>/dev/null | grep -iE "mTime|TimeResult|server|offset|lastRefresh|NtpTrustedTime" | head -8 | cut -c1-220
$ADB shell dumpsys time_detector 2>/dev/null | grep -iE "latest|network|suggest|confidence|systemClock" | head -12 | cut -c1-220
echo "--- iOS simulator clock"
xcrun simctl spawn "$UDID" date -u '+%H:%M:%S' 2>&1 | head -1
echo "mac now:      $(date -u '+%H:%M:%S')"
