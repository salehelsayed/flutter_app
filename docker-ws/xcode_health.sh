#!/bin/bash
# Read-only Xcode health check: each command time-boxed to 30 s; prints exit code and seconds (no device IDs).
#   host-run bash docker-ws/xcode_health.sh
t() { local s=$(date +%s); perl -e 'alarm 30; exec @ARGV' "$@" > /tmp/xh_out.txt 2>&1; local rc=$?; echo "$* -> exit=$rc in $(( $(date +%s)-s ))s lines=$(wc -l < /tmp/xh_out.txt | tr -d ' ')"; }
t xcodebuild -checkFirstLaunchStatus
t xcrun simctl list devices
t xcrun devicectl list devices
grep -cE "iPhone 1[13] " /tmp/xh_out.txt | sed 's/^/physical iPhone rows in devicectl: /'
