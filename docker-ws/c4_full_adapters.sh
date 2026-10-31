#!/bin/bash
# C4 full.* adapters through mknoon_checks (Codex runbook), self-detached.
#   host-run bash docker-ws/c4_full_adapters.sh start <out under build/kayan-safe/> <comma-separated full.* ids>
#   host-run bash docker-ws/c4_full_adapters.sh status <out>
# The ignored device config pins simulator A and the Mac, the approved test relay and the isolated
# fixture flags. No ios_ui_fixtures file is supplied: adapters that need one must report it missing.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"; cd "$REPO" || exit 2
CMD="${1:?start|status}"; OUT="${2:?out}"
case "$OUT" in build/kayan-safe/*) ;; *) echo "output must be under build/kayan-safe/"; exit 2;; esac
case "$CMD" in
  start)
    IDS="${3:?ids}"; mkdir -p "$OUT"; rm -f "$OUT/DONE"
    A=$(python3 -c "import json;print(json.load(open('build/kayan-safe/c4-ios-preparation/available-pins.json'))['A'])")
    RELAYS=$(tr '\n' ',' < build/kayan-safe/test-relay.txt | sed 's/,$//')
    python3 - "$OUT/device-config.json" "$A" "$RELAYS" <<'PY'
import json, sys
path, sim, relays = sys.argv[1:]
json.dump({"isolated_test_environment": True, "fixture_reference": "explicit-disposable-test-relay",
           "devices": {"ios_simulator": sim, "macos": "macos"},
           "full_suite": {"relay_addresses": relays, "ios_disposable_simulator_ids": sim}},
          open(path, "w"), indent=2)
PY
    chmod 600 "$OUT/device-config.json"
    nohup bash "$0" _run "$OUT" "$IDS" > "$OUT/detached.log" 2>&1 < /dev/null &
    echo $! > "$OUT/detached.pid"; echo "started pid $!" ;;
  _run)
    IDS="${3:?ids}"
    export PATH="$HOME/development/flutter-3.47.2/bin:$HOME/.maestro/bin:$HOME/Library/Android/sdk/platform-tools:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home GOTOOLCHAIN=go1.27.1
    HEAD=$(git rev-parse HEAD)
    echo "start $(date -u +%FT%TZ) head=${HEAD:0:9} ids=$IDS"
    python3 scripts/mknoon_checks.py full --base "$HEAD" --local --jobs 1 --flutter-workers 1 \
      --only "$IDS" --device-config "$OUT/device-config.json" --output "$OUT/report" > "$OUT/checks.log" 2>&1
    rc=$?; echo "FULL_EXIT=$rc $(date -u +%FT%TZ)"; echo "$rc" > "$OUT/DONE" ;;
  status)
    P=$(cat "$OUT/detached.pid" 2>/dev/null)
    echo "pid ${P:-none} $(ps -p "${P:-0}" >/dev/null 2>&1 && echo running || echo stopped) done=$(cat "$OUT/DONE" 2>/dev/null || echo no)"
    tail -n 3 "$OUT/detached.log" 2>/dev/null ;;
esac
