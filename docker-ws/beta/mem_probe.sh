#!/bin/bash
# Read-only: what holds the Mac's memory (booted simulators, emulators, top RSS).
echo "--- booted iOS simulators"
xcrun simctl list devices booted 2>/dev/null | grep -E "Booted" | sed 's/^ *//'
echo "--- android emulators (adb)"
"$HOME/Library/Android/sdk/platform-tools/adb" devices -l 2>/dev/null | tail -n +2
echo "--- top 15 processes by resident memory (MB)"
ps -axo rss,pid,etime,comm | sort -rn | head -15 | awk '{printf "%6d MB  pid %-6s %-12s %s\n", $1/1024, $2, $3, $4}'
echo "--- swap / pressure"
sysctl -n vm.swapusage; memory_pressure 2>/dev/null | grep -E "free percentage|Pages free|Swapins|Swapouts" | head -4
