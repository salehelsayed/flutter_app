#!/bin/bash
# Probe: the journey's exact Maestro call (maestro_flow_runner.py) for the iOS permission flow, detached.
if [ -z "${R82_DETACHED:-}" ]; then R82_DETACHED=1 nohup bash "$0" "$@" >/dev/null 2>&1 & echo "started"; exit 0; fi
cd /Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next
export PATH="$HOME/.maestro/bin:/opt/homebrew/bin:$PATH"; export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home
export MAESTRO_DRIVER_STARTUP_TIMEOUT=240000 MAESTRO_CLI_NO_ANALYTICS=1
OUT=/Volumes/CrucialX9/flutter_app/docker-ws/beta/r82.out; D=$(mktemp -d)/m
{ echo "start $(date -u +%T)"; s=$(date +%s)
  python3 scripts/maestro_flow_runner.py --device "$1" --flow integration_test/maestro/production_ios_allow_notifications.yaml \
    --expected-name production_ios_allow_notifications --output "$D" --timeout 300 --env APP_ID=com.mknoon.app
  echo "runner rc=$? seconds=$(( $(date +%s)-s ))"; cat "$D/result.json"; tail -6 "$D/process.log"
} > "$OUT" 2>&1
