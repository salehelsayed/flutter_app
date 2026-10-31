#!/bin/bash
# Read-only: tail the T011 emulator launch log and list emulator processes (pid, args head).
tail -20 /tmp/emulator_Pixel_8_5560.log 2>/dev/null
ps -axo pid,etime,args | grep -E "qemu-system|emulator -avd" | grep -v grep | cut -c1-200
