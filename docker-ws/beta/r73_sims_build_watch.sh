#!/bin/bash
# Run SIMS for build.ios.simulator.app only (bounded) and sample its process tree every 10 s.
cd /Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:$PATH"
OUT=/Volumes/CrucialX9/flutter_app/docker-ws/beta/r73.out
( timeout 240 dart tool/sims/sims.dart major --only build.ios.simulator.app --format text > "$OUT" 2>&1; echo "rc=$?" >> "$OUT" ) &
sleep 3; root=$(pgrep -f "dartvm.*sims.dart major --only build.ios.simulator.app" | head -1); echo "dartvm pid $root"
for i in 1 2; do sleep 15
  echo "t=$((i*10))s cpu=$(ps -o %cpu=,time= -p $root 2>/dev/null) files=$(lsof -p $root 2>/dev/null | awk '$5=="REG"' | tail -1 | awk '{print $NF}' | cut -c1-90) kids: $(pgrep -P $root | while read c; do echo "$c cpu=$(ps -o %cpu=,time= -p $c) cmd=$(ps -o command= -p $c | sed 's/.*--resolved_executable_name=[^ ]* //' | grep -o '[^ ]*\.dart.*' | cut -c1-140)"; for g in $(pgrep -P $c); do echo "   grandchild $(ps -o command= -p $g | cut -c1-100)"; done; done)"
done
wait; tail -8 "$OUT"
