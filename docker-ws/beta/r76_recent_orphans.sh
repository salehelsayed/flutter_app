#!/bin/bash
# Read-only: processes reparented to launchd (ppid 1) started within the last N minutes, excluding apps/daemons.
ps -axo pid=,ppid=,etime=,command= | awk -v m="${1:-35}" '$2==1 {split($3,t,/[:-]/); n=length(t); mins = (n==2)? t[1] : (n==3? t[1]*60+t[2] : 9999); if (mins < m) print}' \
 | grep -v -E "/System/|/usr/libexec|/usr/sbin|\.app/Contents/MacOS|CoreSimulator|launchd" | cut -c1-170 | head -20
