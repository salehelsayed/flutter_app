#!/bin/bash
# PR 5 device proof: production-startup-resume-performance on the Pixel only, at the PR commit in wave3-next. Detached.
if [ -z "${P5D_DETACHED:-}" ]; then P5D_DETACHED=1 nohup bash "$0" >/dev/null 2>&1 & echo "started detached (pid $!)"; exit 0; fi
OUT=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5/pr5_device.out
CFG=/Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next/.codex-test-logs/production-bootstrap-migration-20260930/pr5-pixel-device-config.json
{ echo "start $(date -u +%T) $(git -C /Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next log -1 --format=%h)"
  bash /Volumes/CrucialX9/flutter_app/docker-ws/beta/wt_campaign.sh production-startup-resume-performance "$CFG" 2>&1 | tail -30
  echo "end $(date -u +%T)"; } > "$OUT" 2>&1
