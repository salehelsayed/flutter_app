#!/bin/bash
# Wave 5 step 4 reruns (2026-10-07): 7 Android capabilities with the full config, then 4 iOS catalog cases
# with the Wave 3 iOS config (they need ios_simulator_a). Log: docker-ws/beta/wave5/queue.log
C=/Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next/.codex-test-logs/production-bootstrap-migration-20260930
export QPREFIX="" QPROOF=""
QCONFIG=$C/wave5-full-device-config.json QAVDS='7|6a|8' bash /workspace/docker-ws/beta/wave3/queue.sh $(cat /workspace/docker-ws/beta/wave5/rerun_android_args.txt) | grep -v '^QUEUE-DONE'
QCONFIG=$C/wave3-device-config-ios.json QAVDS=none bash /workspace/docker-ws/beta/wave3/queue.sh $(cat /workspace/docker-ws/beta/wave5/rerun_ios_args.txt)
