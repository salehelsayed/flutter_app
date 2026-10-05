#!/bin/bash
# Warm the worktree's iOS simulator build (Go bindings, Pods, Xcode intermediates) outside a timed campaign.
# Detach on the Mac: the host bridge ends a call (and its children) when the call times out.
if [ -z "${WARM_DETACHED:-}" ]; then
  WARM_DETACHED=1 nohup bash "$0" >/dev/null 2>&1 &
  echo "started detached (pid $!); log docker-ws/beta/wt_warm_ios_sim.out"; exit 0
fi
W=/Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next
OUT=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wt_warm_ios_sim.out
cd "$W" || exit 1
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:$PATH"
{
  echo "start $(date -u +%T)"
  bash scripts/ensure_go_ios_bindings.sh 2>&1 | tail -3
  # Full log (no tail pipe): a stalled step stays visible.
  echo "bindings done $(date -u +%T)"
  flutter build ios --simulator --debug --target lib/main.dart --dart-define=E2E_TEST_MODE=true -v > /Volumes/CrucialX9/flutter_app/docker-ws/beta/wt_warm_ios_sim.verbose.log 2>&1
  echo "build rc=$? end $(date -u +%T)"; tail -15 /Volumes/CrucialX9/flutter_app/docker-ws/beta/wt_warm_ios_sim.verbose.log
} > "$OUT" 2>&1
