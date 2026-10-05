#!/bin/bash
# Read-only progress signals for the Wave 3 worktree campaign (key=value lines).
WT=/Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next
now=$(date +%s)
newest=$(find "$WT/build/sims/proofs" "$WT/build/sims/logs" -type f -mmin -60 -print0 2>/dev/null | xargs -0 stat -f '%m' 2>/dev/null | sort -n | tail -1)
echo "progress_age=$(( now - ${newest:-0} ))"
checks=$(pgrep -f "scripts/mknoon_checks.py run" | head -1); echo "checks_pid=${checks:-none}"
sims=$(pgrep -f "dartvm.*tool/sims/sims.dart major" | head -1); echo "sims_pid=${sims:-none}"
[ -n "$sims" ] && echo "sims_cpu=$(ps -o %cpu= -p $sims | tr -d ' ') sims_children=$(pgrep -P $sims | wc -l | tr -d ' ')"
orph=0; for p in $(ps -axo pid=,ppid=,command= | awk '$2==1 && /dartvm/ && /build ios/ {print $1}'); do
  lsof -a -p "$p" -d cwd -Fn 2>/dev/null | grep -q wave3-next && orph=$((orph+1)); done
echo "orphan_build_helpers=$orph"
echo "maestro=$(pgrep -f 'maestro.cli.AppKt test' | wc -l | tr -d ' ')"
echo "booted_sims=$(xcrun simctl list devices booted 2>/dev/null | grep -c Booted)"
echo "load=$(sysctl -n vm.loadavg | awk '{print $2}')"
