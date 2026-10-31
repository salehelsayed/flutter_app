#!/bin/bash
# Terminate leg: force-stop the owned test package as soon as the source logs SNAPSHOT_EXPORTED (logcat must be cleared first). Gives up after 90 s.
P=com.mknoon.sims.t011; S=21071FDF600CSC
for i in $(seq 1 900); do
  if adb -s $S logcat -d 2>/dev/null | grep -q -E "BUNDLE_SOURCE_SNAPSHOT_EXPORTED|BUNDLE_SOURCE_BUILT"; then
    adb -s $S shell am force-stop $P; echo "force-stop $(date -u +%H:%M:%S.%N | cut -c1-12)"
    adb -s $S logcat -d -v time 2>/dev/null | grep -a -o -E '"event":"ACCOUNT_MIGRATION_[A-Z_]+"' | tail -6
    exit 0
  fi
  sleep 0.1
done
echo "no export seen in 90 s"; exit 1
