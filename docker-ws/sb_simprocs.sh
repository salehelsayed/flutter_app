#!/bin/bash
# Read-only: state, cpu and short name of the T011 simulator's runnable processes.
ps -axo stat=,pcpu=,time=,pid=,args= | grep -E "iOS 26.5.simruntime" | grep -v grep | awk 'substr($1,1,1)=="R"' | sed -E 's|/Library/Developer/CoreSimulator/Volumes/[^ ]+/Contents/Resources/RuntimeRoot||; s|iOS 26.5.simruntime/Contents/Resources/RuntimeRoot||' | awk '{n=split($6,a,"/"); print $1,$2,$3,$4,a[n]}' | head -25
