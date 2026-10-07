#!/bin/bash
# Wave 5 step 4 (user choice 2026-10-06): the 66 production capabilities, one campaign check each, through the Wave 3 queue.
# Runs in the container (the queue drives the Mac through host-run). Log: docker-ws/beta/wave5/queue.log
export QPREFIX="" QPROOF="" QAVDS='7|6a|8'
export QCONFIG=/Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next/.codex-test-logs/production-bootstrap-migration-20260930/wave5-full-device-config.json
exec bash /workspace/docker-ws/beta/wave3/queue.sh $(cat /workspace/docker-ws/beta/wave5/queue_args.txt)
