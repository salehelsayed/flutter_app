#!/bin/bash
# Run docker-ws/run_sims_safe.py self-detached with the host tool PATH (bridge env lacks Java, Maestro, adb).
#   host-run bash docker-ws/run_sims_safe_detached.sh start <mode> <output under build/kayan-safe/> [--exclude-file <ignored file>]
#   host-run bash docker-ws/run_sims_safe_detached.sh status <output>
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
CMD="${1:?}"; shift
case "$CMD" in
  start)
    MODE="${1:?mode}"; OUT="${2:?output}"; shift 2
    case "$OUT" in build/kayan-safe/*) ;; *) echo "output must be under build/kayan-safe/"; exit 2;; esac
    mkdir -p "$REPO/$OUT"; rm -f "$REPO/$OUT/DONE"
    nohup bash "$0" _run "$MODE" "$OUT" "$@" > "$REPO/$OUT/detached.log" 2>&1 < /dev/null &
    echo $! > "$REPO/$OUT/detached.pid"; echo "started pid $!" ;;
  _run)
    MODE="$1"; OUT="$2"; shift 2; cd "$REPO" || exit 2
    export ANDROID_HOME="$HOME/Library/Android/sdk" ANDROID_SDK_ROOT="$HOME/Library/Android/sdk"
    export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home
    export PATH="$HOME/development/flutter-3.47.2/bin:$HOME/.maestro/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$ANDROID_HOME/cmdline-tools/latest/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    export MAESTRO_CLI_NO_ANALYTICS=1
    echo "start $(date -u +%FT%TZ) mode=$MODE head=$(git rev-parse --short HEAD)"
    python3 docker-ws/run_sims_safe.py "$MODE" --output "$OUT" "$@"; rc=$?
    echo "SAFE_SIMS_EXIT=$rc $(date -u +%FT%TZ)"; echo "$rc" > "$REPO/$OUT/DONE" ;;
  status)
    OUT="$REPO/${1:?output}"; P=$(cat "$OUT/detached.pid" 2>/dev/null)
    echo "pid ${P:-none} $(ps -p "${P:-0}" >/dev/null 2>&1 && echo running || echo stopped) done=$(cat "$OUT/DONE" 2>/dev/null || echo no) logbytes=$(stat -f %z "$OUT/launcher.log" 2>/dev/null || echo 0)"
    tail -n 3 "$OUT/detached.log" 2>/dev/null ;;
esac
