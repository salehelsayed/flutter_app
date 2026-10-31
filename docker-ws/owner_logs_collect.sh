#!/bin/bash
# Read-only log collection for the owner's UI-Update test session (Pixel 6 + iPhone 11). No installs, no restarts.
#   host-run bash docker-ws/owner_logs_collect.sh dump|live|status|stop <pid>
O=/Volumes/CrucialX9/owner-uiupdate-logs-20261024
S=21071FDF600CSC; U=00008030-001A6D2801BB802E
IDS="$(command -v idevicesyslog || echo /opt/homebrew/bin/idevicesyslog)"
ICR="$(command -v idevicecrashreport || echo /opt/homebrew/bin/idevicecrashreport)"
mkdir -p "$O/pixel6" "$O/iphone11"
case "$1" in
  dump)
    date -u +%FT%TZ > "$O/dump_time_utc.txt"
    adb -s "$S" logcat -d -b all -v threadtime > "$O/pixel6/logcat_all_dump.txt" 2>&1
    adb -s "$S" logcat -d -b crash -v threadtime > "$O/pixel6/logcat_crash_dump.txt" 2>&1
    adb -s "$S" shell dumpsys package com.mknoon.app | grep -E "versionCode|versionName|firstInstallTime|lastUpdateTime" > "$O/pixel6/package.txt"
    adb -s "$S" shell dumpsys dropbox --print 2>/dev/null | grep -A40 -i "com.mknoon.app" | head -400 > "$O/pixel6/dropbox_mknoon.txt"
    for f in "$O/pixel6/logcat_all_dump.txt"; do echo "pixel first: $(grep -m1 -E '^[0-9]{2}-[0-9]{2} ' "$f" | cut -c1-18)  last: $(grep -E '^[0-9]{2}-[0-9]{2} ' "$f" | tail -1 | cut -c1-18)  lines: $(wc -l < "$f")"; done
    for b in main system events crash; do echo "pixel $b head: $(adb -s "$S" logcat -d -b $b -v threadtime 2>/dev/null | grep -m1 -E '^[0-9]{2}-[0-9]{2} ' | cut -c1-18)"; done
    timeout 120 xcrun devicectl device info files --device "$U" --domain-type appDataContainer --domain-identifier com.mknoon.app > "$O/iphone11/container_listing.txt" 2>&1
    echo "iphone container entries: $(wc -l < "$O/iphone11/container_listing.txt")"
    mkdir -p "$O/iphone11/crash_reports_tmp"
    timeout 180 "$ICR" -u "$U" -k -e "$O/iphone11/crash_reports_tmp" > "$O/iphone11/crash_pull.log" 2>&1
    mkdir -p "$O/iphone11/crash_reports"
    find "$O/iphone11/crash_reports_tmp" -type f \( -iname '*Runner*' -o -iname '*mknoon*' -o -iname 'JetsamEvent*' \) -newermt "2026-10-24 00:00" -exec cp {} "$O/iphone11/crash_reports/" \;
    rm -rf "$O/iphone11/crash_reports_tmp"
    echo "iphone crash/jetsam files today: $(ls "$O/iphone11/crash_reports" | wc -l)"
    ls "$O/iphone11/crash_reports" | head -20 ;;
  live)
    nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' adb -s "$S" logcat -T 1 -b all -v threadtime > "$O/pixel6/logcat_live.txt" 2>&1 < /dev/null &
    echo "pixel live pid $!"
    nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' "$IDS" -u "$U" --no-colors > "$O/iphone11/syslog_live_unfiltered.txt" 2>&1 < /dev/null &
    echo "iphone live pid $!"
    date -u +%FT%TZ > "$O/live_start_utc.txt" ;;
  status)
    ps -axo pid=,args= | grep -E "logcat -T 1 -b all|idevicesyslog -u $U --no-colors" | grep -v grep | cut -c1-100
    ls -la "$O/pixel6/logcat_live.txt" "$O/iphone11/syslog_live_unfiltered.txt" 2>&1 | awk '{print $5, $9}' ;;
  stop)
    P="$2"; [[ "$P" =~ ^[0-9]+$ ]] || { echo refused; exit 2; }
    case "$(ps -o args= -p "$P")" in *"logcat -T 1 -b all"*|*"idevicesyslog -u $U --no-colors"*) kill "$P" && echo "TERM $P";; *) echo "refused";; esac ;;
esac
case "$1" in
  listing) grep -i -E "log|crash|diag|flow" "$O/iphone11/container_listing.txt" | head -30; echo "--"; head -5 "$O/iphone11/container_listing.txt" ;;
  copy) timeout 180 xcrun devicectl device copy from --device "$U" --domain-type appDataContainer --domain-identifier com.mknoon.app --source "$2" --destination "$O/iphone11/$(basename "$(dirname "$2")")__$(basename "$2")" 2>&1 | tail -2 ;;
esac
case "$1" in
  readme) cp "$(dirname "$0")/owner_logs_README.md" "$O/README.md"; rm -f "$O/iphone11/state.json" "$O/iphone11/diagnostics-v1.json"; ls -la "$O" "$O/pixel6" "$O/iphone11" | awk '{print $5, $9}' ;;
esac
case "$1" in
  live_ios_runner)
    nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' bash -c "\"$IDS\" -u \"$U\" --no-colors | grep --line-buffered -E ' Runner(\(|\[)' > \"$O/iphone11/syslog_live_runner.txt\"" > /dev/null 2>&1 < /dev/null &
    echo "iphone runner capture pid $!"; date -u +%FT%TZ > "$O/live_ios_runner_start_utc.txt" ;;
  stop_ios_runner)
    P="$2"; [[ "$P" =~ ^[0-9]+$ ]] || { echo refused; exit 2; }
    case "$(ps -o args= -p "$P")" in *"idevicesyslog"*"$U"*"syslog_live_runner"*) kill -- "-$P" && echo "TERM group $P";; *) echo "refused";; esac ;;
esac
case "$1" in
  sizes) ls -la "$O/iphone11/" "$O/pixel6/" | grep -E "syslog|logcat_live" | awk '{print $5, $9}'; ps -axo pid=,pgid=,args= | grep -E "syslog_live_runner|idevicesyslog -u $U" | grep -v grep | cut -c1-120 ;;
esac
case "$1" in
  snapshot)
    R="$O/${2:-repeat-$(date +%H%M)}"; mkdir -p "$R/pixel6" "$R/iphone11"; date -u +%FT%TZ > "$R/snapshot_time_utc.txt"
    cp "$O/pixel6/logcat_live.txt" "$R/pixel6/logcat_live_until_snapshot.txt"
    cp "$O/iphone11/syslog_live_runner.txt" "$R/iphone11/syslog_runner_until_snapshot.txt"; grep -a "\[FLOW\]" "$O/iphone11/syslog_live_runner.txt" > "$R/iphone11/flow_lines_since_build129.txt"
    adb -s "$S" logcat -d -b all -v threadtime > "$R/pixel6/logcat_all_dump.txt" 2>&1
    for f in "Library/Application Support/app_diagnostics/state.json" "Library/Application Support/MknoonAppDiagnostics/diagnostics-v1.json" "Library/Application Support/call_diagnostics/state.json" "Library/Application Support/MknoonCallDiagnostics/diagnostics-v1.json"; do
      timeout 180 xcrun devicectl device copy from --device "$U" --domain-type appDataContainer --domain-identifier com.mknoon.app --source "$f" --destination "$R/iphone11/$(basename "$(dirname "$f")")__$(basename "$f")" >/dev/null 2>&1
    done
    echo "$R"; ls -la "$R/pixel6" "$R/iphone11" | awk '{print $5, $9}' ;;
esac
case "$1" in
  grep) F="$O/$2"; shift 2; grep -a -E "$1" "$F" | cut -c1-${2:-220} | head -${3:-60} ;;
  tags) F="$O/$2"; P=$(adb -s "$S" shell pidof com.mknoon.app); echo "pid $P"; awk -v p="$P" '$3==p {print $6}' "$F" | sort | uniq -c | sort -rn | head -40 ;;
esac
case "$1" in
  rotate_ios_runner)
    [ -f "$O/iphone11/syslog_live_runner.txt" ] || { echo "no live runner file"; exit 3; }
    N="$O/iphone11/syslog_runner_build${2:-127}_until_$(date +%H%M).txt"
    mv "$O/iphone11/syslog_live_runner.txt" "$N" && echo "moved to $(basename "$N") $(wc -c < "$N") bytes" ;;
  identity) timeout 120 xcrun devicectl device info files --device "$U" --domain-type appDataContainer --domain-identifier com.mknoon.app --subdirectory Documents 2>&1 | grep -E "identity.db|files:" ;;
esac
case "$1" in
  launch) timeout 90 xcrun devicectl device process launch --device "$U" --terminate-existing com.mknoon.app 2>&1 | tail -1 ;;
esac
case "$1" in
  evcount) F="$O/$2"; sed -nE "s/^Oct 24 ([0-9:]{5}).*\"event\":\"([A-Z0-9_]+)\".*/\1 \2/p" "$F" | awk "{print \$2}" | sort | uniq -c | sort -rn | head -${3:-120} ;;
  evline) F="$O/$2"; sed -nE "s/^Oct 24 ([0-9:.]{12}).*\"event\":\"([A-Z0-9_]+)\".*/\1 \2/p" "$F" | grep -E -v "${3:-^$}" | head -${4:-300} ;;
  evdetail) F="$O/$2"; grep -a -E "\"event\":\"($3)\"" "$F" | sed -E "s/^Oct 24 ([0-9:.]{12}).*\"event\":\"([A-Z0-9_]+)\"(.*)/\1 \2 \3/" | sed -E "s/12D3KooW[A-Za-z0-9]+/<peer>/g; s/\"(peerId|senderId|recipientId|contactId|displayName|name|username|text|body|content|payload|qrPayload|token|publicKey|messageId|conversationId|host|address|addr)\":\"[^\"]*\"/\"\1\":\"<x>\"/g" | cut -c1-${4:-220} | head -${5:-80} ;;
  evwin) F="$O/$2"; awk -v a="$3" -v b="$4" '{t=substr($3,1,8)} t>=a && t<=b' "$F" | grep -a -E "\"event\":\"($5)\"" | sed -E "s/^Oct 24 ([0-9:.]{12}).*\"event\":\"([A-Z0-9_]+)\"(.*)/\1 \2 \3/" | sed -E "s/12D3KooW[A-Za-z0-9]+/<peer>/g; s/\"(peerId|senderId|recipientId|contactId|displayName|name|username|text|body|content|payload|qrPayload|token|publicKey|messageId|conversationId|groupId|topic|host|address|addr|title|preview)\":\"[^\"]*\"/\"\1\":\"<x>\"/g" | cut -c1-${6:-260} | head -${7:-400} ;;
esac
