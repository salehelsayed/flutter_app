# 73 - Session 8 Plan: Cross-Platform Smoke And Acceptance Matrix

## Scope

Close the acceptance layer required by the source plan:

- add simulator/emulator fixture injection wrappers for iOS APNs payloads and
  Android FCM data-only broadcasts
- add a smoke orchestrator with dry-run fixture shaping for CI environments
  that do not have the full simulator farm installed
- make the full OS-delivery smoke self-contained: build the debug simulator
  app/APK, boot the configured iPhone 17, iPhone 17 Pro, and Pixel 7 API 37
  targets, install `com.mknoon.app`, and verify the app container/package path
  before attempting non-dry-run push injection
- expand `scripts/smoke_test_push_decrypt_simulator.sh` so its scenario map
  covers every required `S-iOS-1` through `S-iOS-19` and `S-And-1` through
  `S-And-19` row; if a row cannot be automated by the local simulator/emulator
  harness, leave Session 8 blocked and name the exact row and reason
- run the strongest current host-side notification routing, foreground drain,
  background fallback/decrypt, and release-configuration gates
- update the fixture mapping, matrix docs, and gate docs only after the script
  truthfully reflects the full required row set

## Code Entry Points

- `scripts/push_fixture_to_simulator.sh`
- `scripts/push_fixture_to_android_emulator.sh`
- `scripts/smoke_test_push_decrypt_simulator.sh`
- `Test-Flight-Improv/52-notification-journey-test-matrix.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-breakdown.md`

## Tests And Gates

Focused verification:

- `bash -n` for the three smoke scripts
- `scripts/smoke_test_push_decrypt_simulator.sh --dry-run`
- app-installed OS-smoke preflight:
  - `flutter build ios --simulator --debug`
  - resolve iOS simulator IDs with
    `xcrun simctl list devices available | rg "iPhone 17|iPhone 17 Pro"`
  - `xcrun simctl boot <iphone-17-udid-or-name> || true`
  - `xcrun simctl boot <iphone-17-pro-udid-or-name> || true`
  - `xcrun simctl install <iphone-17-udid-or-name> build/ios/iphonesimulator/Runner.app`
  - `xcrun simctl install <iphone-17-pro-udid-or-name> build/ios/iphonesimulator/Runner.app`
  - `xcrun simctl get_app_container <iphone-17-udid-or-name> com.mknoon.app`
  - `xcrun simctl get_app_container <iphone-17-pro-udid-or-name> com.mknoon.app`
  - `flutter build apk --debug`
  - `/Users/I560101/Library/Android/sdk/platform-tools/adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk`
  - `/Users/I560101/Library/Android/sdk/platform-tools/adb -s emulator-5554 shell pm path com.mknoon.app`
- `scripts/smoke_test_push_decrypt_simulator.sh` without `--dry-run`
  on each installed target:
  - `SIMULATOR_DEVICE=<iphone-17-udid-or-name> scripts/smoke_test_push_decrypt_simulator.sh --ios-only`
  - `SIMULATOR_DEVICE=<iphone-17-pro-udid-or-name> scripts/smoke_test_push_decrypt_simulator.sh --ios-only`
  - `ANDROID_SERIAL=emulator-5554 scripts/smoke_test_push_decrypt_simulator.sh --android-only`
- focused notification routing/open/foreground/background/decrypt Flutter
  suite
- `flutter test -d macos integration_test/foreground_group_push_drain_test.dart`
- `scripts/check_push_release_gate.sh`
- full plan-73 verification sweep before accepting Session 8:
  - `flutter test`
  - `(cd go-relay-server && go test ./...)`
  - `xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,name=iPhone 17'`
  - `./scripts/run_test_gates.sh baseline`
  - `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh runtime-telemetry`
  - `./scripts/run_test_gates.sh completeness-check`
  - `scripts/check_push_release_gate.sh`

## Done Criteria

- The simulator/emulator smoke scripts generate ciphertext-shaped APNs/FCM
  payloads from the shared fixtures.
- The smoke orchestrator enumerates all `S-iOS-1..19` and `S-And-1..19` rows,
  maps each row to a fixture and delivery target, and fails if any required
  row is missing from dry-run or non-dry-run execution.
- The app-installed preflight passes on the configured iPhone 17, iPhone 17
  Pro, and Pixel 7 API 37 targets; if an install or package/container check
  fails, Session 8 remains blocked rather than accepting dry-run evidence.
- The full non-dry-run simulator smoke passes after installation on iPhone 17,
  iPhone 17 Pro, and `emulator-5554`.
- Host-side notification route, open, foreground drain, background fallback,
  decrypt preview, and active suppression seams stay green for ciphertext
  payloads.
- The full plan-73 verification sweep passes, including all Dart tests, all
  relay Go tests, the iOS Runner test suite, named baseline/1:1/groups/runtime
  telemetry gates, and completeness-check.
- Session 8 is accepted only if every required row is automated and green; if
  not, it stays blocked with exact non-automated row IDs and reasons.

## Local Evidence

- `bash -n scripts/push_fixture_to_simulator.sh scripts/push_fixture_to_android_emulator.sh scripts/smoke_test_push_decrypt_simulator.sh`
  passed, including the pipeline rerun on 2026-04-24.
- `scripts/smoke_test_push_decrypt_simulator.sh --dry-run` passed for
  S-iOS-1, S-iOS-3, S-iOS-11, S-iOS-12, S-And-1, S-And-3, and S-And-17
  fixture shaping, including the pipeline rerun on 2026-04-24.
- Focused host-side notification acceptance bundle passed:
  `flutter test test/core/notifications/notification_route_target_test.dart test/core/notifications/notification_route_contract_matrix_test.dart test/features/push/application/chat_and_group_push_open_flow_test.dart test/features/push/application/handle_foreground_remote_message_use_case_test.dart test/features/push/application/show_notification_use_case_test.dart test/features/push/application/background_push_notification_fallback_test.dart test/features/push/application/background_message_handler_test.dart test/features/push/application/push_decrypt_preview_test.dart`.
- `flutter test -d macos integration_test/foreground_group_push_drain_test.dart`
  passed. The first attempt without `-d` did not start because multiple
  devices were connected.
- `scripts/check_push_release_gate.sh` passed with one expected local warning:
  `FIREBASE_SERVICE_ACCOUNT` was not set, so the service-account project check
  was skipped.
- The 2026-04-24 continuation check found the required simulators/emulator
  visible to Flutter: iPhone 17, iPhone 17 Pro, and `emulator-5554` Android
  API 37. The app was not installed on either iOS simulator
  (`xcrun simctl get_app_container ... com.mknoon.app` returned no container),
  and the Android emulator did not report `com.mknoon.app` via
  `/Users/I560101/Library/Android/sdk/platform-tools/adb -s emulator-5554 shell pm path com.mknoon.app`.
- The 2026-04-24 local execution fallback resolved the app-install preflight
  for the configured local targets:
  - `flutter build ios --simulator --debug` passed and built
    `build/ios/iphonesimulator/Runner.app`.
  - `xcrun simctl install 5BA69F1C-B112-47BE-B1FF-8C1003728C8F build/ios/iphonesimulator/Runner.app`
    and
    `xcrun simctl install 38FECA55-03C1-4907-BD9D-8E64BF8E3469 build/ios/iphonesimulator/Runner.app`
    passed; both `xcrun simctl get_app_container ... com.mknoon.app` checks
    returned Runner app containers.
  - `flutter build apk --debug` passed, and
    `/Users/I560101/Library/Android/sdk/platform-tools/adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk`
    plus
    `/Users/I560101/Library/Android/sdk/platform-tools/adb -s emulator-5554 shell pm path com.mknoon.app`
    passed.
  - The full non-dry-run smoke matrix passed on both iOS simulators and the
    Android emulator:
    `SIMULATOR_DEVICE=5BA69F1C-B112-47BE-B1FF-8C1003728C8F IOS_SECONDARY_SIMULATOR_DEVICE=38FECA55-03C1-4907-BD9D-8E64BF8E3469 scripts/smoke_test_push_decrypt_simulator.sh --ios-only`,
    `SIMULATOR_DEVICE=38FECA55-03C1-4907-BD9D-8E64BF8E3469 IOS_SECONDARY_SIMULATOR_DEVICE=5BA69F1C-B112-47BE-B1FF-8C1003728C8F scripts/smoke_test_push_decrypt_simulator.sh --ios-only`,
    and
    `ANDROID_SERIAL=emulator-5554 scripts/smoke_test_push_decrypt_simulator.sh --android-only`.
    The logs enumerate S-iOS-1..19 and S-And-1..19.
  - Focused host-side acceptance passed:
    `flutter test test/core/notifications/notification_route_target_test.dart test/core/notifications/notification_route_contract_matrix_test.dart test/features/push/application/chat_and_group_push_open_flow_test.dart test/features/push/application/handle_foreground_remote_message_use_case_test.dart test/features/push/application/show_notification_use_case_test.dart test/features/push/application/background_push_notification_fallback_test.dart test/features/push/application/background_message_handler_test.dart test/features/push/application/push_decrypt_preview_test.dart`.
  - Full companion gates passed:
    `flutter test`,
    `(cd go-relay-server && go test ./...)`,
    `xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,name=iPhone 17'`,
    `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh baseline`,
    `./scripts/run_test_gates.sh 1to1`,
    `./scripts/run_test_gates.sh groups`,
    `./scripts/run_test_gates.sh runtime-telemetry`,
    `./scripts/run_test_gates.sh completeness-check`, and
    `scripts/check_push_release_gate.sh`. The release gate still emitted the
    expected local warning that `FIREBASE_SERVICE_ACCOUNT` was not set.

## Session Verdict

- Accepted. No S-iOS or S-And rows remain blocked after the 2026-04-24 harness
  expansion and app-installed non-dry-run simulator/emulator evidence.

## Scope Guard

- Do not accept Session 8 on the old landed subset. Full `S-iOS-1..19` and
  `S-And-1..19` coverage is required unless blocked rows are explicitly named.
- Do not remove legacy compatibility paths here; Session 9 owns the cleanup
  decision based on accepted evidence.
