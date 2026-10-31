#!/bin/bash
# Apply or list H2 fixture faults for the running lever 5 fixture.
#   host-run bash docker-ws/nfretry_fault.sh pending | <op>
W="$(cd "$(dirname "$0")/.." && pwd)/build/wt-nfretry"; SDK="${MKNOON_FLUTTER_SDK:-$HOME/development/flutter-3.47.2}"; cd "$W" || exit 3
S="$W/.codex-test-logs/nfretry/private/state.json"
if [ "$1" = pending ]; then exec "$SDK/bin/dart" run integration_test/scripts/run_media_fault_fixture.dart pending "$S"; fi
exec "$SDK/bin/dart" run integration_test/scripts/run_media_fault_fixture.dart fault "$S" "$1"
