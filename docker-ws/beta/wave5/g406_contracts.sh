#!/bin/bash
# Plan 406: run the contract tests that pin the Go toolchain, plus the Dart
# tests that read it, in the go-upgrade-406 worktree. Self-detaches.
set -u
W=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5
OUT=$W/g406_contracts.log
if [ -z "${G406C_DETACHED:-}" ]; then
  G406C_DETACHED=1 nohup bash "$0" "$@" >"$OUT" 2>&1 &
  echo "detached pid $! log $OUT"; exit 0
fi
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:/usr/local/bin:/usr/local/go/bin:$PATH"
cd /Volumes/CrucialX9/flutter_app/.claude/worktrees/go-upgrade-406 || exit 1
for t in relay_go_toolchain_contract_test.sh host_test_gate_batch_contract_test.sh \
         relay_ack_custody_rollout_contract_test.sh run_claude_docker_update_contract_test.sh \
         production_audio_call_fixture_adapter_contract_test.sh reliability_simulation_discovery_contract_test.sh; do
  echo "=== $t"; bash scripts/test/$t > /tmp/g406_$t.log 2>&1; rc=$?
  tail -3 /tmp/g406_$t.log; echo "RESULT $t exit=$rc"
done
python3 scripts/test/ios_notification_provider_adapter_test.py > /tmp/g406_ios_adapter.log 2>&1; echo "RESULT ios_notification_provider_adapter_test exit=$?"; tail -3 /tmp/g406_ios_adapter.log
echo "=== dart"
flutter pub get >/dev/null 2>&1
flutter test --no-pub --reporter failures-only test/integration/production_audio_call_local_fixture_test.dart test/integration/android_production_audio_call_campaign_test.dart test/tool/sims/sims_manifest_test.dart 2>&1 | tail -15
echo "RESULT dart exit=${PIPESTATUS[0]}"
echo "CONTRACTS DONE"
