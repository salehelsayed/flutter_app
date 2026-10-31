#!/bin/bash
# The host-runnable cases of the legacy full regression, in the temp worktree at <rev>, one at a time, self-detached.
# Device-touching steps use only the disposable emulator named here; never the physical phones.
#   host-run bash docker-ws/run_legacy_host_cases.sh start <rev> <out dir under .codex-test-logs/> <emulator-id>
#   host-run bash docker-ws/run_legacy_host_cases.sh status <out dir>
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO/docker-ws/_host_paths.sh"
CMD="${1:?}"; shift
case "$CMD" in
  start)
    REV="${1:?rev}"; OUT="$REPO/${2:?out}"; EMU="${3:?emulator id}"
    [[ "$EMU" =~ ^emulator-[0-9]+$ ]] || { echo "refused: only emulator-NNNN targets"; exit 2; }
    mknoon_require_output "$REPO" "$OUT/run.log" || exit 2
    mkdir -p "$OUT"; rm -f "$OUT/DONE"
    nohup bash "$0" _run "$REV" "$OUT" "$EMU" > "$OUT/run.log" 2>&1 < /dev/null &
    echo $! > "$OUT/pid"; echo "started pid $!" ;;
  _run)
    REV="$1"; OUT="$2"; EMU="$3"; WT="/Volumes/CrucialX9/flutter_app_wt_full_$REV"
    [ -d "$WT" ] || { echo "no worktree $WT"; echo 2 > "$OUT/DONE"; exit 2; }
    export PATH="$HOME/development/flutter-3.47.2/bin:/usr/local/bin:/opt/homebrew/bin:$HOME/Library/Android/sdk/platform-tools:/usr/bin:/bin:/usr/sbin:/sbin"
    export GOTOOLCHAIN=go1.27.1 GOMAXPROCS=4 GOFLAGS=-p=4 GRADLE_OPTS='-Dorg.gradle.workers.max=2 -Dorg.gradle.parallel=false'
    cd "$WT" || exit 2
    worst=0
    step() {
      local name="$1"; shift
      echo "STEP $name start $(date -u +%T)"
      "$@" > "$OUT/$name.log" 2>&1; local rc=$?
      echo "STEP $name exit=$rc $(date -u +%T)"; echo -e "$name\t$rc" >> "$OUT/summary.tsv"
      [ $rc -ne 0 ] && worst=1
    }
    : > "$OUT/summary.tsv"
    step analyze-baseline ./scripts/check_flutter_analyze_baseline.sh
    step completeness-check ./scripts/run_test_gates.sh completeness-check
    step gate-all env FLUTTER_DEVICE_ID="$EMU" ./scripts/run_test_gates.sh all
    step gate-benchmark-sim env FLUTTER_DEVICE_ID="$EMU" ./scripts/run_test_gates.sh benchmark-sim
    echo "LEGACY_HOST_EXIT=$worst"; echo "$worst" > "$OUT/DONE" ;;
  status)
    OUT="$REPO/${1:?out}"; P=$(cat "$OUT/pid" 2>/dev/null)
    echo "pid ${P:-none} $(ps -p "${P:-0}" >/dev/null 2>&1 && echo running || echo stopped) done=$(cat "$OUT/DONE" 2>/dev/null || echo no)"
    tail -n 4 "$OUT/run.log" 2>/dev/null ;;
esac
