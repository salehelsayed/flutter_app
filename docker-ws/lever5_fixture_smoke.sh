#!/bin/bash
# Host-only smoke of the H2 fault fixture: start serve, list pending, apply clock faults, stop. No devices.
#   host-run bash docker-ws/lever5_fixture_smoke.sh
set -uo pipefail
W="$(cd "$(dirname "$0")/.." && pwd)/build/wt-lever5"; SDK="${MKNOON_FLUTTER_SDK:-$HOME/development/flutter-3.47.2}"
cd "$W" || exit 3
E="$W/.codex-test-logs/lever5"; mkdir -p "$E/private"; chmod 700 "$E/private"
S="$E/private/smoke-state.json"; rm -f "$S" "$S.stop"
"$SDK/bin/dart" run integration_test/scripts/run_media_fault_fixture.dart serve "$S" > "$E/smoke-serve.log" 2>&1 &
P=$!
for i in $(seq 1 90); do grep -q H2_FIXTURE_READY "$E/smoke-serve.log" && break; sleep 2; done
grep -q H2_FIXTURE_READY "$E/smoke-serve.log" || { echo "not ready"; kill "$P"; exit 4; }
"$SDK/bin/dart" run integration_test/scripts/run_media_fault_fixture.dart pending "$S"
"$SDK/bin/dart" run integration_test/scripts/run_media_fault_fixture.dart fault "$S" expire
"$SDK/bin/dart" run integration_test/scripts/run_media_fault_fixture.dart fault "$S" clock_reset
"$SDK/bin/dart" run integration_test/scripts/run_media_fault_fixture.dart fault "$S" remove; echo "remove-on-empty exit=$?"
touch "$S.stop"; wait "$P"; echo "serve exit=$?"
tail -1 "$E/smoke-serve.log"; ls -l "$S" | cut -c1-10
