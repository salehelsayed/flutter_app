#!/bin/bash
# Baseline "full" run of scripts/mknoon_checks.py in a clean temporary worktree at <rev>, outside the repo.
# Self-detaches (the bridge call would time out); progress goes to <out>/run.log, the end to <out>/DONE.
#   host-run bash docker-ws/run_full_baseline.sh start <rev> <out dir under .codex-test-logs/> [extra mknoon_checks args...]
#   host-run bash docker-ws/run_full_baseline.sh status <out dir>
#   host-run bash docker-ws/run_full_baseline.sh cleanup <rev>
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO/docker-ws/_host_paths.sh"
CMD="${1:?start|status|cleanup}"; shift
wt_for() { echo "/Volumes/CrucialX9/flutter_app_wt_full_$1"; }
case "$CMD" in
  start)
    REV="${1:?rev}"; OUT="$REPO/${2:?out}"; shift 2
    [[ "$REV" =~ ^[0-9a-f]{7,40}$ ]] || { echo "invalid rev"; exit 2; }
    mknoon_require_output "$REPO" "$OUT/run.log" || exit 2
    mkdir -p "$OUT" || exit 2
    [ -f "$OUT/pid" ] && ps -p "$(cat "$OUT/pid")" >/dev/null 2>&1 && { echo "already running pid $(cat "$OUT/pid")"; exit 2; }
    rm -f "$OUT/DONE"
    nohup bash "$0" _run "$REV" "$OUT" "$@" > "$OUT/run.log" 2>&1 < /dev/null &
    echo $! > "$OUT/pid"; echo "started pid $!" ;;
  _run)
    REV="$1"; OUT="$2"; shift 2
    WT="$(wt_for "$REV")"
    export PATH="$HOME/development/flutter-3.47.2/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    export PROJECT_MEMORY_TEST_MEMORY_DIR="$HOME/.claude-docker-home/.claude/projects/-workspace/memory"
    export GOTOOLCHAIN=go1.27.1 GOMAXPROCS=4 GOFLAGS=-p=4 GRADLE_OPTS='-Dorg.gradle.workers.max=2 -Dorg.gradle.parallel=false'
    echo "start $(date -u +%FT%TZ) rev=$REV"
    if [ ! -d "$WT" ]; then git -C "$REPO" worktree add --detach "$WT" "$REV" || { echo "FULL_EXIT=2 worktree"; echo 2 > "$OUT/DONE"; exit 2; }; fi
    for f in android/app/libs/GoMknoon.aar android/app/libs/GoMknoon-sources.jar android/app/google-services.json android/local.properties android/gradlew android/gradle/wrapper/gradle-wrapper.jar graphify-arch/graphify-out/graph.json graphify-out/graph.json; do
      [ -f "$REPO/$f" ] && mkdir -p "$(dirname "$WT/$f")" && cp -p "$REPO/$f" "$WT/$f"
    done
    cd "$WT" || exit 2
    echo "worktree head $(git rev-parse --short HEAD) dirty=$(git status --porcelain | wc -l | tr -d ' ')"
    flutter pub get --offline --enforce-lockfile > "$OUT/pub-get.log" 2>&1; echo "pub get exit=$?"
    python3 scripts/mknoon_checks.py full --base "$REV" --output "$OUT/report" "$@" > "$OUT/checks.log" 2>&1
    rc=$?; echo "FULL_EXIT=$rc $(date -u +%FT%TZ)"; echo "$rc" > "$OUT/DONE" ;;
  status)
    OUT="$REPO/${1:?out}"; P=$(cat "$OUT/pid" 2>/dev/null)
    echo "pid ${P:-none} $(ps -p "${P:-0}" >/dev/null 2>&1 && echo running || echo stopped) done=$(cat "$OUT/DONE" 2>/dev/null || echo no)"
    tail -n 3 "$OUT/run.log" 2>/dev/null; tail -n 5 "$OUT/checks.log" 2>/dev/null ;;
  cleanup)
    REV="${1:?rev}"; WT="$(wt_for "$REV")"; [ -d "$WT" ] && git -C "$REPO" worktree remove --force "$WT" && echo "removed $WT" ;;
  *) echo "unknown"; exit 2 ;;
esac
