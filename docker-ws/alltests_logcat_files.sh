#!/bin/bash
# Read-only: output files of running adb logcat streams, and their size/mtime.
for p in $(pgrep -f "adb -s 21071FDF600CSC shell -x logcat"); do
  for fd in 1 2; do f=$(lsof -a -p $p -d $fd -Fn 2>/dev/null | sed -n 's/^n//p'); [ -n "$f" ] && ls -la "$f" 2>/dev/null | awk -v p=$p -v fd=$fd '{print p, fd, $5, $6, $7, $8, $9}'; done
done
