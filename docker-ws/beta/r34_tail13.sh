#!/bin/bash
# Read-only: last lines of the newest iPhone 13 capture, and a count of lines per minute 15:0x-15:1x.
F=$(ls -t "$(cat "$(dirname "$0")/r34_capture_dir.txt")"/iphone13_syslog_*.txt | head -1); echo "$F"
tail -3 "$F" | cut -c1-160
grep -oE '^Oct  1 [0-9]{2}:[0-9]{2}' "$F" | uniq -c | tail -12
