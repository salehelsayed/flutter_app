#!/bin/bash
# VC-014: read-only: show given PIDs, plus emulator/appium/idevicesyslog processes.
for p in "$@"; do ps -ww -o pid=,etime=,args= -p "$p" | cut -c1-600 || echo "$p gone"; done
echo "--- emulator/appium/idevicesyslog ---"
ps -axo pid=,etime=,args= | grep -E "qemu-system|emulator -avd|appium --port|idevicesyslog" | grep -v grep | cut -c1-160
