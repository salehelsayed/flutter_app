#!/bin/bash
# Read-only: lines before/after the first match of a regex in the newest iPhone 11 capture. Usage: r34_ctx.sh <regex> [before] [after] [nth]
F=$(ls -t "$(cat "$(dirname "$0")/r34_capture_dir.txt")"/iphone11_syslog_*.txt | head -1)
n=$(grep -nE "$1" "$F" | sed -n "${4:-1}p" | cut -d: -f1)
[ -n "$n" ] || { echo "no match"; exit 0; }
sed -n "$((n-${2:-15})),$((n+${3:-5}))p" "$F" | cut -c1-230
