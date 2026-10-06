#!/bin/bash
# Read-only-ish: time a 20 MB write+read on the external drive, disk throughput, Defender CPU.
T=/Volumes/CrucialX9/flutter_app/build/.w5_disk_probe
s=$(date +%s.%N 2>/dev/null || date +%s); dd if=/dev/zero of=$T bs=1m count=20 2>&1 | tail -1; cat $T > /dev/null; rm -f $T
iostat -d -c 3 -w 1 2>/dev/null | tail -2
ps -axo pid,pcpu,time,command | grep -E "wdavdaemon|dsymutil|mds_stores|mdworker" | grep -v grep | cut -c1-130 | head -8
