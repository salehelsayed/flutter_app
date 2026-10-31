#!/bin/bash
# Start the H2 fault fixture detached (output to a log file), wait for readiness, print its PID. Stop: touch <state>.stop.
#   host-run bash docker-ws/nfretry_fixture_start.sh
W="$(cd "$(dirname "$0")/.." && pwd)/build/wt-nfretry"; SDK="${MKNOON_FLUTTER_SDK:-$HOME/development/flutter-3.47.2}"
cd "$W" || exit 3
E="$W/.codex-test-logs/nfretry"; mkdir -p "$E/private"; chmod 700 "$E/private"
S="$E/private/state.json"; rm -f "$S" "$S.stop" "$S.target"
PLAN347_FIXTURE_GO_TIMEOUT=240m nohup "$SDK/bin/dart" run integration_test/scripts/run_media_fault_fixture.dart serve "$S" > "$E/serve.log" 2>&1 < /dev/null &
P=$!; echo "$P" > "$E/serve.pid"
for i in $(seq 1 120); do grep -q H2_FIXTURE_READY "$E/serve.log" && break; kill -0 "$P" 2>/dev/null || break; sleep 2; done
grep -q H2_FIXTURE_READY "$E/serve.log" && echo "ready pid=$P" || { echo "not ready"; tail -5 "$E/serve.log"; exit 4; }
