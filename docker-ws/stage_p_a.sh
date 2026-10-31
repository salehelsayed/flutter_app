#!/bin/bash
# Stage P part A: the five physical Android rows on the owner-approved disposable Pixel, one row per
# sims.dart --only invocation, serially (Codex package bd18c7aa, commit 96bf5618e). Self-detached.
#   host-run bash docker-ws/stage_p_a.sh start <out under build/kayan-safe/> <pixel serial> <emulator serial>
#   host-run bash docker-ws/stage_p_a.sh status <out>
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"; cd "$REPO" || exit 2
ROWS="android.voice_recorder_native_smoke android.voice_message_e2e android.foreground_webrtc_audio production.startup_resume_performance performance.device.critical"
case "${1:-status}" in
  start)
    OUT="${2:?out}"; PIXEL="${3:?pixel serial}"; EMU="${4:?emulator serial}"
    case "$OUT" in build/kayan-safe/*) ;; *) echo "refused output"; exit 2;; esac
    [[ "$PIXEL" =~ ^[0-9A-Za-z]{8,32}$ ]] || { echo "refused pixel serial"; exit 2; }
    [[ "$EMU" =~ ^emulator-[0-9]+$ ]] || { echo "refused emulator serial"; exit 2; }
    mkdir -p "$OUT"; chmod 700 "$OUT"; rm -f "$OUT/DONE"
    nohup bash "$0" _run "$OUT" "$PIXEL" "$EMU" > "$OUT/detached.log" 2>&1 < /dev/null &
    echo $! > "$OUT/detached.pid"; echo "started pid $!" ;;
  _run)
    OUT="$2"; PIXEL="$3"; EMU="$4"
    RELAYS=$(tr '\n' ',' < build/kayan-safe/test-relay.txt | sed 's/,$//')
    BASE=(env -i HOME="$HOME" USER="$USER" TMPDIR="${TMPDIR:-/tmp}" LANG=en_US.UTF-8
      PATH="$HOME/development/flutter-3.47.2/bin:$HOME/.maestro/bin:$HOME/Library/Android/sdk/platform-tools:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
      ANDROID_HOME="$HOME/Library/Android/sdk" ANDROID_SDK_ROOT="$HOME/Library/Android/sdk"
      JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home MAESTRO_CLI_NO_ANALYTICS=1
      GOTOOLCHAIN=go1.27.1 GOMAXPROCS=2 GOFLAGS=-p=2
      GRADLE_OPTS='-Dorg.gradle.workers.max=2 -Dorg.gradle.parallel=false -Dorg.gradle.daemon=false'
      SIMS_MAX_PARALLEL=1 SIMS_HOST_CONCURRENCY=1 MKNOON_HOST_FLUTTER_WORKERS=1
      MKNOON_RELAY_ADDRESSES="$RELAYS"
      MKNOON_PRESERVE_PHYSICAL_APP_DATA=1 MKNOON_DISPOSABLE_PHYSICAL_ANDROID_SERIALS="$PIXEL"
      SIMS_ANDROID_PHYSICAL_DEVICE_ID="$PIXEL" SIMS_ANDROID_EMULATOR_DEVICE_ID="$EMU"
      SIMS_PROTECTED_DEVICE_ASSIGNMENTS_JSON="{\"android-physical\":\"$PIXEL\",\"android-emulator\":\"$EMU\"}")
    echo "start $(date -u +%FT%TZ) head=$(git rev-parse --short HEAD)"
    worst=0
    for ROW in $ROWS; do
      D="$OUT/$ROW"; mkdir -p "$D"
      echo "ROW $ROW start $(date -u +%T)"
      "${BASE[@]}" SIMS_REPORT_PATH="$D/native-report.json" SIMS_CHECKPOINT_PATH="$D/checkpoint.json" \
        SIMS_PROOF_DIRECTORY="$D/proofs" \
        dart run tool/sims/sims.dart major --only "$ROW" > "$D/run.log" 2>&1
      rc=$?; echo "ROW $ROW exit=$rc $(date -u +%T)"; [ $rc -ne 0 ] && worst=1
    done
    echo "STAGE_P_A_EXIT=$worst $(date -u +%FT%TZ)"; echo "$worst" > "$OUT/DONE" ;;
  status)
    OUT="${2:?out}"; P=$(cat "$OUT/detached.pid" 2>/dev/null)
    echo "pid ${P:-none} $(ps -p "${P:-0}" >/dev/null 2>&1 && echo running || echo stopped) done=$(cat "$OUT/DONE" 2>/dev/null || echo no)"
    tail -n 4 "$OUT/detached.log" 2>/dev/null ;;
esac
