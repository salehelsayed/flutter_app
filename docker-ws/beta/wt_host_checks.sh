#!/bin/bash
# The batch's host check, run inside the next-batch worktree (the main checkout stays free for device runs).
#   wt_host_checks.sh [check,check,...]
W=/Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next
cd "$W" || exit 1
export ANDROID_HOME="$HOME/Library/Android/sdk"
export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home
export PATH="$HOME/development/flutter-3.47.2/bin:$HOME/.maestro/bin:$ANDROID_HOME/platform-tools:/opt/homebrew/bin:$PATH"
CHECKS="${1:-workflow,affected-groups,affected-surfaces,maestro-flow-contracts,notifications,production-journey-contracts,runtime-roots,small-group}"
OUT="$W/.codex-test-logs/wt-host-$(date -u +%Y%m%dT%H%M%SZ)"
python3 scripts/mknoon_checks.py run --mode change --base "$(git rev-parse main)" --local --only "$CHECKS" --output "$OUT" 2>&1 \
  | grep -v "^NOT RUN" | tail -30
