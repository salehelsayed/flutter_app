# INTEGRATE-OB-011 Release Telemetry Integration Contract

Status: accepted

## Source Of Truth
- Source row: `OB-011` / "Release telemetry can answer who missed which message and why".
- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-011-plan.md`.
- Source closure status: accepted/covered with focused unit, fake-network, criteria, and iOS 26.2 app-peer proof.

## Integration Scope
Import only the row-owned release missed-message telemetry delta:

- `lib/features/groups/application/group_missed_message_telemetry.dart`
- `test/features/groups/application/group_missed_message_telemetry_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`

Out of scope: changing delivery semantics, production analytics backend work, OB-012 redaction proof, retry-loop telemetry, dispatcher recovery behavior, stress-row injection, Android, physical iOS, source matrix rewrites, COMPLETE_1 docs, and source worktree docs.

## Imported Delta
- Added `GroupDeliveryExpectation`, `GroupDeliveryObservation`, `buildGroupMissedMessageTelemetryReport`, and `emitGroupMissedMessageTelemetryReport`.
- The report emits sanitized group/message/sender/recipient prefixes, key epoch, cause, source event, resolution, per-cause counts, covered cause classes, and `unknownCount`.
- Unit proof covers transport, key, membership, replay, dispatcher, and UI-filter causes with zero unknown classifications and sanitized release telemetry flow output.
- Fake-network proof exercises a real zero-peer send/replay context and emits `GROUP_RELEASE_MISSED_MESSAGE_TELEMETRY`.
- Criteria and live harness proof add `ob011ReleaseTelemetryProof` on `private_background_resume_group_delivery`.

## Verification
- `dart format --set-exit-if-changed lib/features/groups/application/group_missed_message_telemetry.dart test/features/groups/application/group_missed_message_telemetry_test.dart test/features/groups/integration/group_resume_recovery_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart`
- `flutter test --no-pub test/features/groups/application/group_missed_message_telemetry_test.dart --plain-name "OB-011"` (`+2`)
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name "OB-011"` (`+1`)
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "OB-011"` (`+2`)
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name "NW-010"` (`+1`)
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "private_background_resume_group_delivery"` (`No tests ran`; selector absent in current main, so no standalone claim)
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "NW-010"` (`+5`)
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name "OB-008"` (`+1`)
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name "OB-008"` (`+1`)
- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name "OB-009"` (`+1`)
- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name "OB-010"` (`+1`)
- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name "DE-019"` (`+2`)
- `flutter analyze --no-pub lib/features/groups/application/group_missed_message_telemetry.dart test/features/groups/application/group_missed_message_telemetry_test.dart test/features/groups/integration/group_resume_recovery_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` (`No issues found!`)
- `git diff --check`

## Device Proof
Required iOS 26.2 app-peer proof passed:

- command scenario: `private_background_resume_group_delivery`
- run id: `1779351484682`
- shared dir: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_background_resume_group_delivery_CPRbd5`
- Alice: `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`
- Bob: `279B82AE-2BB9-4924-9AAE-581870ED3FA9`
- Charlie: `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`
- orchestrator verdict: `private_background_resume_group_delivery verdicts valid for alice, bob, charlie`

## Closure Verdict
Accepted for `INTEGRATE-OB-011`. The row imported only missing row-owned release missed-message telemetry code, host/fake-network proof, criteria validation, and live-harness proof fields, preserved NW-010/OB-008/OB-009/OB-010/DE-019 behavior, and left unrelated `info.plist` unstaged and untouched.
