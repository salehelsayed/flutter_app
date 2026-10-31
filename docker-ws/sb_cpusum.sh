#!/bin/bash
# Read-only: total CPU percent used by all processes and by the T011 simulator's processes.
ps -axo pcpu=,args= | awk '{t+=$1} /CoreSimulator\/Devices\/F83C694C|iOS 26.5.simruntime/{s+=$1} END{printf "total %.0f%% of 1200%%  simulator %.0f%%\n", t, s}'
