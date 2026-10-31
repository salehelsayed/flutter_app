#!/bin/bash
# Signed debug simulator build of the current tree for the media-bug repro. Self-detached.
#   host-run bash docker-ws/build_ios_sim_debug.sh start <log under build/kayan-safe/>
#   host-run bash docker-ws/build_ios_sim_debug.sh status <log>
set -uo pipefail
cd "$(dirname "$0")/.."
case "${1:-status}" in
  start) LOG="${2:?log}"; case "$LOG" in build/kayan-safe/*) ;; *) echo refused; exit 2;; esac
    rm -f "$LOG.done"; nohup bash "$0" _run "$LOG" > "$LOG" 2>&1 < /dev/null & echo "started pid $!" ;;
  _run) LOG="$2"
    export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" GOTOOLCHAIN=go1.27.1
    echo "start $(date -u +%T) head=$(git rev-parse --short HEAD)"
    bash scripts/ensure_go_ios_bindings.sh; echo "bindings exit=$?"
    flutter build ios --simulator --debug --no-pub --dart-define-from-file=tool/build/voice_call_release_defines.json; rc=$?
    echo "build exit=$rc $(date -u +%T)"; ls -d build/ios/iphonesimulator/Runner.app 2>&1
    codesign -d --entitlements - build/ios/iphonesimulator/Runner.app 2>&1 | grep -c application-groups
    echo $rc > "$LOG.done" ;;
  status) LOG="${2:?log}"; echo "done=$(cat "$LOG.done" 2>/dev/null || echo no)"; tail -4 "$LOG" ;;
esac
