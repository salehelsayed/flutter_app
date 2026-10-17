#!/bin/bash
# SE-42 D12: run the test-only mixed-precision fixture helper on ONE disposable Android emulator.
#   host-run bash docker-ws/d12_device_helper.sh <emulator-serial> <seed|snapshot> <log-file-in-repo> [paired-peer-id] [round 1-4]
set -uo pipefail
cd "$(dirname "$0")/.."
SERIAL="${1:?emulator serial}"; MODE="${2:?mode}"; LOG="${3:?log}"; PEER="${4:-}"; ROUND="${5:-1}"
[[ "$ROUND" =~ ^[1-4]$ ]] || { echo "d12: refused round" >&2; exit 2; }
[[ -z "$PEER" || "$PEER" =~ ^12D3KooW[A-Za-z0-9]+$ ]] || { echo "d12: refused peer" >&2; exit 2; }
case "$SERIAL" in emulator-*) ;; *) echo "d12: refused, not an emulator" >&2; exit 2 ;; esac
case "$MODE" in seed|snapshot) ;; *) echo "d12: refused mode" >&2; exit 2 ;; esac
flutter test integration_test/se42_d12_mixed_precision_seed_test.dart -d "$SERIAL" --no-pub --no-uninstall \
  --dart-define=D12_MODE="$MODE" --dart-define=D12_PEER="$PEER" --dart-define=D12_ROUND="$ROUND" > "$LOG" 2>&1
rc=$?
echo "exit=$rc" >> "$LOG"
exit "$rc"
