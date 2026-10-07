#!/bin/bash
# Read-only progress of the Wave 5 full run: age in seconds of the newest file under its output dir and the SIMS proofs.
OUT=$(cat /Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5/devices_run.dir 2>/dev/null)
W=/Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next
now=$(date +%s)
newest=$(find "$OUT" "$W/build/sims/proofs" "$W/build/sims/latest" -type f -mmin -120 -print0 2>/dev/null | xargs -0 stat -f %m 2>/dev/null | sort -n | tail -1)
echo "age=$(( now - ${newest:-0} ))"
echo "files=$(find "$OUT" -type f 2>/dev/null | wc -l | tr -d ' ')"
echo "runner=$(pgrep -f 'mknoon_checks.py full' | head -1)"
# Child-process signature: changes whenever the runner starts or ends a child (build, test, device step).
r=$(pgrep -f 'mknoon_checks.py full' | head -1)
desc(){ for c in $(pgrep -P "$1"); do echo "$c"; desc "$c"; done; }
[ -n "$r" ] && echo "kids=$(desc "$r" | sort -n | tr '\n' ',' | md5 -q)"
# Newest write under the SIMS logs (journeys and builds append to their logs as they run).
W=/Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next
nl=$(find "$W/build/sims/logs" "$W/build/ios" "$W/build/sims/ios-device-production-derived/Logs" -type f -mmin -30 -print0 2>/dev/null | xargs -0 stat -f %m 2>/dev/null | sort -n | tail -1)
echo "logage=$(( $(date +%s) - ${nl:-0} ))"
