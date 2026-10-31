#!/bin/bash
# Dump (and optionally clear) the Pixel logcat's Mknoon flow/migration lines into the safe-transfer-b evidence dir.
#   sb_logcat.sh <name> [clear]
E=/Volumes/CrucialX9/flutter_app/.codex-test-logs/safe-transfer-b-20261023T1310Z
adb -s 21071FDF600CSC logcat -d -v time 2>/dev/null | grep -E "FLOW|MIGRATION|Migration|migration" > "$E/$1.txt"
wc -l < "$E/$1.txt"
grep -o -E '"event":"[A-Z0-9_]+"|event[=: ]+[A-Z0-9_]+' "$E/$1.txt" | sed -E 's/.*[":= ]([A-Z0-9_]+)"?$/\1/' | grep -i -E "MIGRATION|QR|TRANSFER|CUTOVER|EXPORT|PAIR" | uniq -c | tail -40
[ "$2" = clear ] && adb -s 21071FDF600CSC logcat -c
