#!/bin/bash
# Run the Plan407 Step 2 thin thought-send fixture on the sender emulator (disposable package com.mknoon.sims.step2).
#   host-run bash docker-ws/run_step2_fixture.sh <sender-serial> <texts '|' sep> <gap-ms> <hold-ms>   (under docker-ws/with_native_lease.py)
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"; WT="$REPO/build/wt-cui-377d"
SER="${1:?serial}"; TEXTS="${2:?texts}"; GAP="${3:-0}"; HOLD="${4:-0}"
case "$SER" in emulator-5560|emulator-5562) ;; *) echo "refused serial"; exit 2;; esac
RX="$(cat "$REPO/build/kayan-safe/batch2/dev/step2-rx-peer.private.txt")"; [ -n "$RX" ] || exit 3
export ORG_GRADLE_PROJECT_androidApplicationId=com.mknoon.sims.step2
export ORG_GRADLE_PROJECT_disableGoogleServicesForDisposableProof=true
cd "$WT" || exit 2
flutter test integration_test/plan407_thought_send_fixture_test.dart -d "$SER" --no-pub \
  --dart-define=PLAN407_THOUGHT_RECEIVER="$RX" --dart-define=PLAN407_THOUGHT_TEXTS="$TEXTS" \
  --dart-define=PLAN407_THOUGHT_GAP_MS="$GAP" --dart-define=PLAN407_THOUGHT_HOLD_MS="$HOLD"
