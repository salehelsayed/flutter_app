#!/bin/bash
# After the current reruns: move the worktree to the flow fix, then rerun up012 (full config) and nw006 (iOS config).
while pgrep -f "wave5/run_reruns.sh" >/dev/null; do sleep 30; done
echo "reruns finished $(date -u +%T)"
/claude-host-bin/host-run bash /workspace/docker-ws/beta/wt_next.sh git checkout -- info.plist 2>/dev/null
/claude-host-bin/host-run bash /workspace/docker-ws/beta/wt_next.sh rebase 2>&1 | tail -1
C=/Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next/.codex-test-logs/production-bootstrap-migration-20260930
export QPREFIX="" QPROOF=""
QCONFIG=$C/wave5-full-device-config.json QAVDS='7|6a|8' bash /workspace/docker-ws/beta/wave3/queue.sh $(cat /workspace/docker-ws/beta/wave5/rerun_up012_args.txt) > /workspace/docker-ws/beta/wave5/followup_up012.log 2>&1
QCONFIG=$C/wave3-device-config-ios.json QAVDS=none bash /workspace/docker-ws/beta/wave3/queue.sh $(cat /workspace/docker-ws/beta/wave5/rerun_nw006_args.txt) > /workspace/docker-ws/beta/wave5/followup_nw006.log 2>&1
echo "FOLLOWUP-DONE $(date -u +%T)"
