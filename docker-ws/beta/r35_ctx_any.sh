#!/bin/bash
# Read-only: matching lines from all iPhone 11 capture files in the current capture dir (ordered), limited.
D=$(cat "$(dirname "$0")/r34_capture_dir.txt")
cat "$D"/iphone11_syslog_*.txt | grep -E "$1" | head -${2:-30} | cut -c1-200
