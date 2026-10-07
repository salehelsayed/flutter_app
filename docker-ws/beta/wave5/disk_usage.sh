#!/bin/bash
# Read-only: free space and the largest test-output folders on the external drive, the internal disk and TMPDIR.
df -h /Volumes/CrucialX9 / 2>/dev/null | awk 'NR==1||/CrucialX9|\/$/'
M=/Volumes/CrucialX9/flutter_app; W=$M/.claude/worktrees/wave3-next; T=${TMPDIR:-/tmp}
for d in "$W/build/sims/proofs" "$W/build/sims/logs" "$W/build/sims/cache" "$W/build/sims/ios-device-production-derived" "$W/build/sims/ios-device-group-media-269-derived" "$W/build" "$W/.codex-test-logs" "$M/.codex-test-logs" "$M/build" "$M/docker-ws/beta" "$HOME/Library/Developer/Xcode/DerivedData" "$HOME/Library/Developer/CoreSimulator/Devices" "$HOME/.maestro/tests" "$HOME/.gradle/caches" "$HOME/.gradle/daemon" "$T"; do
  [ -e "$d" ] && printf '%8s  %s\n' "$(du -sh "$d" 2>/dev/null | cut -f1)" "${d/$HOME/~}"
done
echo "-- TMPDIR big children"; du -sh "$T"/* 2>/dev/null | sort -rh | head -8
