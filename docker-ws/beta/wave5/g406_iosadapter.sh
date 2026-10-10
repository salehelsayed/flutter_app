#!/bin/bash
# Plan 406: rerun ios_notification_provider_adapter_test.py and the Dart tests
# for the edited sims/integration files in the go-upgrade-406 worktree.
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:/usr/local/bin:/usr/local/go/bin:$PATH"
cd /Volumes/CrucialX9/flutter_app/.claude/worktrees/go-upgrade-406 || exit 1
python3 scripts/test/ios_notification_provider_adapter_test.py 2>&1 | grep -E "FAIL|Error|Ran |^OK|FAILED" | head -10
bash scripts/test/run_claude_docker_update_contract_test.sh 2>&1 | tail -1
flutter analyze --no-pub tool/sims/device_binding.dart integration_test/scripts/ios_notification_payload_xcui_driver.dart integration_test/scripts/run_production_audio_call_sims.dart test/integration/android_production_audio_call_campaign_test.dart 2>&1 | tail -1
flutter test --no-pub --reporter failures-only test/tool/sims/ test/integration/android_production_audio_call_campaign_test.dart 2>&1 | tail -3
