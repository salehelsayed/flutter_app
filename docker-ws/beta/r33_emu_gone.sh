#!/bin/bash
# Read-only: why did the emulator disappear? Recent qemu crash reports, memory pressure, emulator log tails.
echo "now $(date '+%H:%M:%S')"
ls -lt ~/Library/Logs/DiagnosticReports/ 2>/dev/null | grep -iE 'qemu|emulator' | head -5
log show --last 20m --style compact --predicate 'process == "kernel" && (eventMessage CONTAINS "qemu" || eventMessage CONTAINS "jetsam" || eventMessage CONTAINS "memorystatus")' 2>/dev/null | tail -8 | cut -c1-200
echo "memory: $(memory_pressure 2>/dev/null | grep -E 'free percentage' )  swap: $(sysctl -n vm.swapusage)"
for f in $(ls -t ~/.android/avd/Pixel_7a.avd/*.log /Volumes/CrucialX9/flutter_app/artifacts/beta-20260928/emulator_restart_*.log 2>/dev/null | head -2); do echo "--- $f"; tail -5 "$f" | cut -c1-200; done
ps -axo pid,etime,command | grep -iE 'emulator|qemu' | grep -v grep | cut -c1-160
