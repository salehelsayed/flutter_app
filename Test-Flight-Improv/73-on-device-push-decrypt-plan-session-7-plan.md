# 73 - Session 7 Plan: Observability, Degrade-Rate Gate, And Schema Decision

## Scope

Implement the telemetry and gate slice for on-device push decrypt:

- emit leak-safe Android data decrypt success/failure flow events through a
  testable event sink
- emit leak-safe iOS Notification Service Extension decrypt success/failure and
  timeout events
- add a deterministic degrade-rate calculator that excludes expected rollout
  fallback reasons from both numerator and denominator
- add tests proving telemetry events do not carry plaintext or canary values
- assert the current push-data contract intentionally omits `schemaVersion`,
  `version`, and `v` keys
- document the runtime telemetry gate and the TestFlight soak evidence needed
  for final acceptance

## Code Entry Points

- `lib/core/utils/flow_event_emitter.dart`
- `lib/features/push/application/push_decrypt_preview.dart`
- `lib/features/push/application/push_preview_telemetry_gate.dart`
- `test/features/push/application/push_decrypt_preview_test.dart`
- `test/features/push/application/push_preview_telemetry_gate_test.dart`
- `ios/NotificationService/NotificationPreviewResolver.swift`
- `ios/NotificationService/NotificationService.swift`
- `ios/RunnerTests/NotificationPreviewResolverTests.swift`
- `go-relay-server/inbox_test.go`
- `scripts/run_test_gates.sh`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/52-notification-journey-test-matrix.md`

## Tests And Gates

Focused verification:

- `dart format` on touched Dart code and tests
- `flutter test test/features/push/application/push_preview_telemetry_gate_test.dart test/features/push/application/push_decrypt_preview_test.dart`
- `go test ./...` from `go-relay-server`
- focused RunnerTests Xcode run for `NotificationPreviewResolverTests`
- `./scripts/run_test_gates.sh completeness-check`

## Done Criteria

- Android and iOS push decrypt telemetry emits only event names and safe
  reason/kind metadata.
- The degrade-rate gate calculator counts real decrypt failures and excludes
  `client_pre_decrypt`, `keychain_locked`, and `migration_pending` from both
  numerator and denominator.
- Relay push payload contract tests prove no direct schema-version key is
  present in chat or group push data.
- Gate definitions and the notification journey matrix name the runtime
  telemetry gate and its required TestFlight soak evidence.

## Closure Evidence

- `dart format` completed for touched Dart telemetry code and tests.
- `flutter test test/features/push/application/push_preview_telemetry_gate_test.dart test/features/push/application/push_decrypt_preview_test.dart`
  passed.
- `go test ./...` from `go-relay-server` passed.
- Focused
  `xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,id=5BA69F1C-B112-47BE-B1FF-8C1003728C8F' CODE_SIGNING_ALLOWED=NO -only-testing:RunnerTests/NotificationPreviewResolverTests`
  passed all six resolver tests.
- `./scripts/run_test_gates.sh runtime-telemetry` passed.
- `./scripts/run_test_gates.sh completeness-check` passed with `668/668`
  test files classified.

## Scope Guard

- Do not run full cross-platform simulator smoke here; Session 8 owns that.
- Do not remove legacy compatibility paths; Session 9 owns cleanup after the
  acceptance pass.
