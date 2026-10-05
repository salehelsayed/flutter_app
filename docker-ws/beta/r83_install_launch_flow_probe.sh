#!/bin/bash
# Probe: install the cached ios.simulator.app on one simulator, launch it as the journey does, then run the
# journey's Maestro call. Detached; log r83.out.
if [ -z "${R83_DETACHED:-}" ]; then R83_DETACHED=1 nohup bash "$0" "$@" >/dev/null 2>&1 & echo "started"; exit 0; fi
W=/Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next; cd "$W"
export PATH="$HOME/.maestro/bin:/opt/homebrew/bin:$PATH"; export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home
export MAESTRO_DRIVER_STARTUP_TIMEOUT=240000 MAESTRO_CLI_NO_ANALYTICS=1
OUT=/Volumes/CrucialX9/flutter_app/docker-ws/beta/r83.out; U=$1
APP=$(ls -d build/sims/cache/ios.simulator.app/*/Runner.app | head -1)
{ echo "start $(date -u +%T) app $APP"
  xcrun simctl terminate $U com.mknoon.app 2>/dev/null; xcrun simctl uninstall $U com.mknoon.app 2>/dev/null
  xcrun simctl install $U "$APP" && echo "installed $(date -u +%T)"
  xcrun simctl launch $U com.mknoon.app && echo "launched $(date -u +%T)"
  D=$(mktemp -d)/m; s=$(date +%s)
  python3 scripts/maestro_flow_runner.py --device $U --flow integration_test/maestro/production_ios_allow_notifications.yaml \
    --expected-name production_ios_allow_notifications --output "$D" --timeout 300 --env APP_ID=com.mknoon.app
  echo "runner rc=$? seconds=$(( $(date +%s)-s ))"; grep -m2 -E "not ready|Exception|Passed|Failed" "$D/process.log"
  xcrun simctl terminate $U com.mknoon.app; xcrun simctl uninstall $U com.mknoon.app; echo "cleaned"
} > "$OUT" 2>&1
