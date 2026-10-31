#!/bin/bash
# Read-only: list host adb logcat processes (pid, etime, args).
ps -axo pid=,etime=,args= | grep -E 'adb .*logcat' | grep -v grep | cut -c1-120
exit 0
