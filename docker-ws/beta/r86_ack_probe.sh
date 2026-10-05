#!/bin/bash
# Probe the runtime acknowledgement on one simulator with a failed attempt's staged files. Detached; r86.out.
#   r86_ack_probe.sh <simulator udid> <attempt dir>
if [ -z "${R86_DETACHED:-}" ]; then R86_DETACHED=1 nohup bash "$0" "$@" >/dev/null 2>&1 & echo "started"; exit 0; fi
W=/Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next; cd "$W"; U=$1; A=$2
OUT=/Volumes/CrucialX9/flutter_app/docker-ws/beta/r86.out
APP=${3:-$(ls -d build/sims/cache/ios.simulator.app/*/Runner.app | head -1)}
{ echo "start $(date -u +%T)"
  xcrun simctl terminate "$U" com.mknoon.app 2>/dev/null; xcrun simctl uninstall "$U" com.mknoon.app 2>/dev/null
  xcrun simctl install "$U" "$APP" && echo installed
  C=$(xcrun simctl get_app_container "$U" com.mknoon.app data); echo "container $C"
  mkdir -p "$C/Documents/production-journey"
  cp "$(ls "$A"/alice-*-auto_setup.json.staging | head -1)" "$C/Documents/auto_setup.json"
  cp "$(ls "$A"/alice-*-production-journey-runtime-config.json.staging | head -1)" \
     "$C/Documents/production-journey/runtime-config.json"
  echo "runtime-config: $(head -c 300 "$C/Documents/production-journey/runtime-config.json")"
  T0=$(date '+%Y-%m-%d %H:%M:%S'); xcrun simctl launch "$U" com.mknoon.app; sleep 90
  echo "--- Documents tree:"; find "$C/Documents" -maxdepth 2 | sed "s#$C##" | head -30
  echo "--- ack: $(head -c 300 "$C/Documents/production-journey/runtime-ack.json" 2>/dev/null)"
  echo "--- app log (flutter / errors):"
  xcrun simctl spawn "$U" log show --start "$T0" --predicate 'process == "Runner"' --style compact 2>/dev/null \
    | grep -i -E "flutter|error|exception|production|journey|sims|profile" | head -40 | cut -c1-240
  echo "end $(date -u +%T)"
} > "$OUT" 2>&1
