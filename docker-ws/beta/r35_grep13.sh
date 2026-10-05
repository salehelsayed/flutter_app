#!/bin/bash
# Read-only: lines from all iPhone 13 capture files in a time window matching a regex. Usage: r35_grep13.sh <from HH:MM:SS> <to> <regex> [n]
D=$(cat "$(dirname "$0")/r34_capture_dir.txt")
cat "$D"/iphone13_syslog*.txt | awk -v a="$1" -v b="$2" '{t=$3} t>=a && t<=b' | grep -E "$3" | head -${4:-40} | cut -c1-260
