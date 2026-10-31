#!/bin/bash
# Impacted host checks in a clean temporary worktree at <rev> (outside the repo), clean env, one at a time, detached.
#   host-run bash docker-ws/run_impacted_checks.sh start <rev> <out under .codex-test-logs/> <step>...
#   host-run bash docker-ws/run_impacted_checks.sh status <out>
#   steps: validate completeness analyze gradle-wrapper native-374 workflow pdf3 file:<test path>
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO/docker-ws/_host_paths.sh"
CMD="${1:?}"; shift
case "$CMD" in
  start)
    REV="${1:?rev}"; OUT="$REPO/${2:?out}"; shift 2
    [[ "$REV" =~ ^[0-9a-f]{7,40}$ ]] || { echo "invalid rev"; exit 2; }
    mknoon_require_output "$REPO" "$OUT/run.log" || exit 2
    mkdir -p "$OUT"; rm -f "$OUT/DONE"
    nohup bash "$0" _run "$REV" "$OUT" "$@" > "$OUT/run.log" 2>&1 < /dev/null &
    echo $! > "$OUT/pid"; echo "started pid $!" ;;
  _run)
    REV="$1"; OUT="$2"; shift 2; WT="/Volumes/CrucialX9/flutter_app_wt_impacted_$REV"
    [ -d "$WT" ] || git -C "$REPO" worktree add --detach "$WT" "$REV" > /dev/null 2>&1 || { echo 2 > "$OUT/DONE"; exit 2; }
    for f in ios/Runner/GoogleService-Info.plist android/app/libs/GoMknoon.aar android/app/libs/GoMknoon-sources.jar android/app/google-services.json android/local.properties graphify-arch/graphify-out/graph.json graphify-out/graph.json; do
      [ -f "$REPO/$f" ] && mkdir -p "$(dirname "$WT/$f")" && cp -p "$REPO/$f" "$WT/$f"
    done
    # Git-ignored iOS/macOS Go bindings: without them the binding-freshness checks read
    # missing binaries in this worktree and report them as stale.
    for d in ios/Runner/GoMknoon.xcframework ios/Runner/GoMknoonNSE.xcframework macos/Runner/GoMknoon.xcframework; do
      [ -d "$REPO/$d" ] && mkdir -p "$(dirname "$WT/$d")" && cp -Rp "$REPO/$d" "$WT/$d"
    done
    [ -f "$REPO/ios/Runner/GoMknoon.inputs.sha256" ] && cp -p "$REPO/ios/Runner/GoMknoon.inputs.sha256" "$WT/ios/Runner/"
    CLEAN=(env -i HOME="$HOME" USER="$USER" TMPDIR="${TMPDIR:-/tmp}" LANG=en_US.UTF-8
      PATH="$HOME/development/flutter-3.47.2/bin:$HOME/Library/Android/sdk/platform-tools:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
      JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home ANDROID_HOME="$HOME/Library/Android/sdk"
      GOTOOLCHAIN=go1.27.1 GOMAXPROCS=4 GOFLAGS=-p=4 GRADLE_OPTS='-Dorg.gradle.workers.max=2 -Dorg.gradle.parallel=false')
    cd "$WT" || exit 2
    echo "worktree $(git rev-parse --short HEAD) dirty=$(git status --porcelain | wc -l | tr -d ' ')"
    "${CLEAN[@]}" flutter pub get --offline --enforce-lockfile > "$OUT/pub-get.log" 2>&1; echo "pub get exit=$?"
    worst=0
    for S in "$@"; do
      N="${S//[:\/]/_}"; echo "STEP $S start $(date -u +%T)"
      case "$S" in
        validate) "${CLEAN[@]}" python3 scripts/mknoon_checks.py validate ;;
        completeness) "${CLEAN[@]}" bash scripts/run_test_gates.sh completeness-check ;;
        analyze) "${CLEAN[@]}" bash scripts/check_flutter_analyze_strict.sh ;;
        gradle-wrapper) ls -l android/gradlew android/gradle/wrapper/gradle-wrapper.jar && "${CLEAN[@]}" bash android/gradlew -p android --offline --no-daemon --version ;;
        native-374) "${CLEAN[@]}" bash scripts/test/run_android_headless_recovery_native_374.sh ;;
        workflow) "${CLEAN[@]}" python3 -m unittest $(python3 -c "import json; print(' '.join(json.load(open('tool/testing/selection.json'))['commands']['workflow']['paths']))" 2>/dev/null || python3 -c "
import json; d=json.load(open('tool/testing/selection.json'))
def f(o):
    if isinstance(o,dict):
        w=o.get('workflow')
        if isinstance(w,dict) and 'paths' in w: return w['paths']
        for v in o.values():
            r=f(v)
            if r: return r
print(' '.join(f(d) or []))") ;;
        pdf3) for i in 1 2 3; do "${CLEAN[@]}" flutter test --no-pub --concurrency 1 test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name 'a picked PDF is staged and a fake PDF is refused'; echo "pdf run $i exit=$?"; done ;;
        file:*) "${CLEAN[@]}" flutter test --no-pub --concurrency 1 "${S#file:}" ;;
        files:*) "${CLEAN[@]}" flutter test --no-pub --concurrency 2 $(cat "$REPO/${S#files:}") ;;
        host-all-launcherenv) "${CLEAN[@]}" MKNOON_PRESERVE_PHYSICAL_APP_DATA=1 SIMS_DISPOSABLE_ANDROID_JOURNEYS=1 \
            SIMS_ANDROID_EMULATOR_DEVICE_ID=emulator-5554 SIMS_ANDROID_EMULATOR_SECOND_DEVICE_ID=emulator-5556 \
            SIMS_ANDROID_EMULATOR_FOURTH_DEVICE_ID=emulator-5558 SIMS_MAX_PARALLEL=1 SIMS_HOST_CONCURRENCY=1 \
            MKNOON_RELAY_ADDRESSES="$(tr '\n' ',' < "$REPO/build/kayan-safe/test-relay.txt" | sed 's/,$//')" \
            ./scripts/run_host_test_gates.sh host-all --dart-only --batch-flutter --concurrency 4 --reporter failures-only ;;
        host-all-clean) "${CLEAN[@]}" ./scripts/run_host_test_gates.sh host-all --dart-only --batch-flutter --concurrency 4 --reporter failures-only ;;
        go-all) (cd go-mknoon && "${CLEAN[@]}" go test ./... -count=1 -timeout=20m) ;;
        go-pkg:*) (cd go-mknoon && "${CLEAN[@]}" go test "${S#go-pkg:}" -count=1 -timeout=20m) ;;
        relay-it:*) (cd go-relay-server && "${CLEAN[@]}" go test -tags integration -run "${S#relay-it:}" -count=1 -v -timeout=20m .) ;;
        android-unit) "${CLEAN[@]}" ./android/gradlew -p android :app:testDebugUnitTest ;;
        runtime-roots) "${CLEAN[@]}" ./scripts/run_test_gates.sh runtime-roots ;;
        sims-contracts) "${CLEAN[@]}" ./scripts/run_test_gates.sh sims-contracts ;;
        py:*) "${CLEAN[@]}" python3 -m unittest -v "${S#py:}" ;;
        checks-plan:*) "${CLEAN[@]}" python3 scripts/mknoon_checks.py plan --mode change --base "${S#checks-plan:}" --output "$OUT/checks-plan" ;;
        checks-run:*) "${CLEAN[@]}" python3 scripts/mknoon_checks.py run --mode change --base "${S#checks-run:}" --jobs 1 --flutter-workers 2 --output "$OUT/checks-run" ;;
        *) echo "unknown step"; false ;;
      esac > "$OUT/$N.log" 2>&1; rc=$?
      echo "STEP $S exit=$rc $(date -u +%T)"; echo -e "$S\t$rc" >> "$OUT/summary.tsv"; [ $rc -ne 0 ] && worst=1
    done
    echo "IMPACTED_EXIT=$worst"; echo "$worst" > "$OUT/DONE" ;;
  status)
    OUT="$REPO/${1:?out}"; P=$(cat "$OUT/pid" 2>/dev/null)
    echo "pid ${P:-none} $(ps -p "${P:-0}" >/dev/null 2>&1 && echo running || echo stopped) done=$(cat "$OUT/DONE" 2>/dev/null || echo no)"
    tail -n 3 "$OUT/run.log" 2>/dev/null ;;
esac
