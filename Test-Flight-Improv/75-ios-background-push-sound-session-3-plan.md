# Report 75 Session 3 Plan - Notification Matrix, Gate Classification, and Acceptance Closure

## Final verdict

- Status:
  `accepted_with_explicit_follow_up`
- Accepted on:
  `2026-04-24`
- Execution mode:
  `local bounded fallback after fresh child materialization failed because codex could not access /Users/I560101/.codex/sessions`
- Why:
  - `Test-Flight-Improv/52-notification-journey-test-matrix.md` now carries
    explicit 1:1 and group iOS background-audible contract rows with concrete
    deterministic evidence and an honest manual-audio follow-up note.
  - `Test-Flight-Improv/test-gate-definitions.md` now classifies the direct
    Report 75 sound-proof suites as optional/manual direct suites without
    widening a frozen named gate.
  - The acceptance replay passed the relay Go tests, the Flutter direct test
    bundle, and `./scripts/run_test_gates.sh completeness-check`.
  - The only remaining item is explicit manual simulator/TestFlight audible
    confirmation, which was not run in this environment and remains
    non-blocking.

## real scope

- Update the stable notification matrix and gate doc so they reflect the deterministic evidence that landed in Sessions 1 and 2.
- Replay the feasible direct acceptance bundle for the relay and Flutter seams touched by Report 75.
- Record simulator/device audible proof honestly as an explicit follow-up if it cannot be completed in this environment.
- Persist the final program verdict in the breakdown ledger.

Out of scope for this session:

- new production code
- rewriting named gates
- pretending local unit/integration proof is the same as real iOS speaker output

## closure bar

Session 3 is good enough only when the matrix names the new 1:1 and group audible background rows with concrete evidence, `Test-Flight-Improv/test-gate-definitions.md` classifies the direct proof suites without widening frozen named gates, the feasible direct tests and `completeness-check` pass, and the breakdown records a truthful final program verdict plus any explicit manual-audio follow-up.

## source of truth

- Active session contract: `Test-Flight-Improv/75-ios-background-push-sound-session-breakdown.md`
- Proposal context: `Test-Flight-Improv/75-ios-background-push-sound.md`
- Stable closure docs:
  - `Test-Flight-Improv/52-notification-journey-test-matrix.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `Test-Flight-Improv/notification-sound-smoke-plan.md`
- Current code/tests win on disagreement:
  - `go-relay-server/inbox.go`
  - `go-relay-server/inbox_test.go`
  - `test/core/notifications/local_notification_support_test.dart`
  - `test/features/push/application/background_message_handler_test.dart`
  - `test/features/push/application/show_notification_use_case_test.dart`
  - `test/features/push/application/chat_and_group_push_open_flow_test.dart`
  - `test/integration/notification_tap_smoke_test.dart`
  - `test/features/push/application/ios_push_project_config_test.dart`

## session classification

`acceptance-only`

## exact problem statement

Sessions 1 and 2 landed deterministic relay and Flutter proof, but the stable notification matrix and gate definitions still do not call out the new audible background contract explicitly. This session closes the doc gap, reruns the feasible acceptance evidence, and keeps manual iOS audio confirmation as an explicit external follow-up rather than overclaiming full speaker-level verification.

## files and repos to inspect next

- `Test-Flight-Improv/52-notification-journey-test-matrix.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/notification-sound-smoke-plan.md`
- `Test-Flight-Improv/75-ios-background-push-sound-session-breakdown.md`
- `Test-Flight-Improv/75-ios-background-push-sound-session-1-plan.md`
- `Test-Flight-Improv/75-ios-background-push-sound-session-2-plan.md`

## existing tests covering this area

- Relay deterministic sound contract:
  - `go-relay-server/inbox_test.go`
- Shared local notification details:
  - `test/core/notifications/local_notification_support_test.dart`
- Background fallback detail usage:
  - `test/features/push/application/background_message_handler_test.dart`
- Quiet/suppression guard:
  - `test/features/push/application/show_notification_use_case_test.dart`
- Warm/cold/tap routing:
  - `test/features/push/application/chat_and_group_push_open_flow_test.dart`
  - `test/integration/notification_tap_smoke_test.dart`
- Foreground quiet project contract:
  - `test/features/push/application/ios_push_project_config_test.dart`
- Optional manual simulator smoke harness already exists:
  - `integration_test/scripts/run_notification_sound_smoke.dart`

## regression/tests to add first

- None required before acceptance. This session should reuse the landed direct suites and update docs truthfully.

## step-by-step implementation plan

1. Add one explicit 1:1 audible-background row and one explicit group audible-background row to `Test-Flight-Improv/52-notification-journey-test-matrix.md`.
2. Update `Test-Flight-Improv/test-gate-definitions.md` to classify the direct sound-proof suites as optional/manual direct suites without widening frozen named gates.
3. Replay the relay and Flutter direct test bundle from Sessions 1 and 2.
4. Run `./scripts/run_test_gates.sh completeness-check` through the writable Flutter SDK overlay because the gate doc changed.
5. Record the manual iOS audio confirmation as an explicit follow-up unless the simulator/device smoke is actually run and observed in this session.
6. Persist the final per-session statuses and final program verdict in the breakdown artifact.

## risks and edge cases

- The matrix must distinguish deterministic payload/detail proof from real audible OS output.
- Gate doc updates must not imply these suites joined a frozen named gate when they remain optional/manual direct suites.
- Acceptance must stay honest about the writable `/tmp` Flutter overlay and `/tmp` Go cache being execution accommodations, not product changes.

## exact tests and gates to run

Direct tests:

- `cd go-relay-server && GOCACHE=/tmp/go-build-report75 go test ./... -run 'TestBuildChatPushMessage_(LegacyPlaintextEnvelopeEmitsOnlyFallbackAndRouteData|CarriesEncryptedDataWithoutPlaintextPreview)|TestBuildGroupPushMessage_CarriesEncryptedDataWithoutPlaintextPreview'`
- `cd go-relay-server && GOCACHE=/tmp/go-build-report75 go test ./...`
- `HOME=/tmp CI=true FLUTTER_SUPPRESS_ANALYTICS=true PUB_CACHE=/tmp/pub-cache-report75 /tmp/flutter-sdk-report75/bin/flutter test --no-pub test/core/notifications/local_notification_support_test.dart`
- `HOME=/tmp CI=true FLUTTER_SUPPRESS_ANALYTICS=true PUB_CACHE=/tmp/pub-cache-report75 /tmp/flutter-sdk-report75/bin/flutter test --no-pub test/features/push/application/background_message_handler_test.dart`
- `HOME=/tmp CI=true FLUTTER_SUPPRESS_ANALYTICS=true PUB_CACHE=/tmp/pub-cache-report75 /tmp/flutter-sdk-report75/bin/flutter test --no-pub test/features/push/application/show_notification_use_case_test.dart test/features/push/application/chat_and_group_push_open_flow_test.dart test/integration/notification_tap_smoke_test.dart`
- `HOME=/tmp CI=true FLUTTER_SUPPRESS_ANALYTICS=true PUB_CACHE=/tmp/pub-cache-report75 /tmp/flutter-sdk-report75/bin/flutter test --no-pub test/features/push/application/ios_push_project_config_test.dart`

Named gates:

- `PATH=\"/tmp/flutter-sdk-report75/bin:$PATH\" HOME=/tmp CI=true FLUTTER_SUPPRESS_ANALYTICS=true PUB_CACHE=/tmp/pub-cache-report75 ./scripts/run_test_gates.sh completeness-check`

Optional manual follow-up, not required for acceptance in this environment:

- `HOME=/tmp CI=true FLUTTER_SUPPRESS_ANALYTICS=true PUB_CACHE=/tmp/pub-cache-report75 /tmp/flutter-sdk-report75/bin/dart run integration_test/scripts/run_notification_sound_smoke.dart`

## known-failure interpretation

- Missing real iOS speaker-level verification is a non-blocking explicit follow-up for this session as long as deterministic repo-owned proof and doc updates are complete.
- Any direct test or `completeness-check` failure is blocking.

## done criteria

- The matrix has explicit 1:1 and group audible background rows tied to concrete evidence.
- The gate doc classifies the direct proof suites without widening frozen named gates.
- The direct acceptance bundle and `completeness-check` pass.
- The breakdown ledger records accepted session statuses and a final program verdict that does not overclaim manual iOS audio proof.

## scope guard

- Do not add a new named gate or expand an existing one for Report 75.
- Do not claim simulator/device audio was verified unless the manual smoke is actually run and observed here.
- Do not reopen Sessions 1 or 2 unless the acceptance replay surfaces a real regression.

## accepted differences / intentionally out of scope

- Real audible speaker output remains environment-dependent on Focus, silent mode, notification permissions, simulator audio routing, and APNs delivery timing.
- Existing optional smoke harnesses stay optional/manual direct evidence rather than frozen named-gate members.

## dependency impact

- If Session 3 closes cleanly, Report 75 should reopen only for a real regression in the relay/Flutter deterministic contract or for later manual-audio evidence work.
