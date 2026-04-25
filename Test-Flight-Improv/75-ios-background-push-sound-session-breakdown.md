# 75 - iOS Background Push Sound Session Breakdown

## Decomposition artifact

- Artifact path:
  `Test-Flight-Improv/75-ios-background-push-sound-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/75-ios-background-push-sound.md`
- Decomposition date:
  `2026-04-24`
- Decomposition status:
  `local fallback after spawned decomposer no-progressed without leaving the adjacent breakdown artifact`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code and tests before execution

## Recommended plan count

- `3`

## Overall closure bar

Report `75` is finished only when all of the following are true at the same time:

- relay-built iOS APNs payloads for user-visible 1:1 and group message notifications carry an explicit audible background sound contract
- encrypted/ciphertext-only message push payloads keep `alert`, `content-available`, `mutable-content`, route data, and privacy-preserving fallback copy while adding sound
- Android message notification behavior remains high-priority and audible without changing the existing data-only encrypted message contract
- Flutter local fallback notification details remain audible on iOS and Android, and background fallback display still uses those shared details
- foreground remote presentation remains intentionally quiet through `setForegroundNotificationPresentationOptions(sound: false)`
- active-conversation suppression and recent-remote duplicate suppression still prevent noisy duplicate local notifications
- notification tap routing, background fallback routing, encrypted preview rewriting, APNs registration diagnostics, and push permission requests keep their current behavior
- stable notification matrix and gate docs record the deterministic coverage plus any manual simulator or TestFlight sound evidence that remains external

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/75-ios-background-push-sound.md`
- `Test-Flight-Improv/notification-sound-smoke-plan.md`
- `Test-Flight-Improv/52-notification-journey-test-matrix.md`
- `Test-Flight-Improv/53-notification-background-delivery-reliability-plan.md`
- `Test-Flight-Improv/74-privacy-preserving-notification-previews.md`
- `Test-Flight-Improv/test-gate-definitions.md`

Current repo facts that govern the split:

- `go-relay-server/inbox.go` builds 1:1 message APNs payloads through
  `buildPushMessage(...)` and message/group encrypted fallback APNs payloads
  through `buildCiphertextOnlyPushMessage(...)`; both message paths now set the
  explicit APNs message sound contract while preserving alert headers and
  privacy-preserving fallback copy.
- `go-relay-server/inbox_test.go` already asserts message push route data,
  APNs alert shape, `content-available`, `mutable-content`, no plaintext
  preview leakage, and Android data-only behavior; it is the right place for
  deterministic APNs sound contract coverage.
- `lib/main.dart` sets foreground Firebase presentation options with
  `sound: false`, so app-open remote push presentation must stay quiet.
- `lib/core/notifications/local_notification_support.dart` defines the shared
  local message notification details with Android `playSound: true` and iOS
  `presentSound: true`; `test/core/notifications/local_notification_support_test.dart`
  already covers the static detail object.
- `lib/features/push/application/background_message_handler.dart` shows
  routable data-only fallback notifications using
  `mknoonMessagesNotificationDetails`; its tests cover display, route payloads,
  duplicate suppression, iOS fallback display, and now pin the audible
  platform specifics on the plugin `show(...)` seam.
- `lib/features/push/application/show_notification_use_case.dart` owns
  active-conversation and recent-remote suppression; its tests are the direct
  guard against foreground or duplicate noise regressions.
- `test/features/push/application/ios_push_project_config_test.dart` now pins
  the `lib/main.dart` foreground remote presentation contract to
  `alert: false`, `badge: false`, and `sound: false`.
- `ios/NotificationService/NotificationService.swift` and
  `ios/NotificationService/NotificationPreviewResolver.swift` rewrite
  title/body/threading for encrypted previews and must not strip or invalidate
  the APNs sound contract.

Disagreement rule:

- current code and tests beat stale prose
- `go-relay-server/inbox_test.go` is authoritative for relay message APNs
  payload shape
- `Test-Flight-Improv/test-gate-definitions.md` and
  `./scripts/run_test_gates.sh` decide named gate membership

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Closure docs touched | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `1` | `Relay APNs audible message push contract` | `implementation-ready` | `Test-Flight-Improv/75-ios-background-push-sound-session-1-plan.md` | none | `accepted` | `Test-Flight-Improv/75-ios-background-push-sound-session-1-plan.md`, `Test-Flight-Improv/75-ios-background-push-sound-session-breakdown.md` | Local bounded fallback used after fresh child materialization failed on `/Users/I560101/.codex/sessions`; explicit APNs sound now lands for 1:1 and group message pushes, and `GOCACHE=/tmp/go-build-report75 go test ./...` passed in `go-relay-server`. |
| `2` | `Flutter local fallback sound and quiet suppression proof` | `implementation-ready` | `Test-Flight-Improv/75-ios-background-push-sound-session-2-plan.md` | `1` | `accepted` | `Test-Flight-Improv/75-ios-background-push-sound-session-2-plan.md`, `Test-Flight-Improv/75-ios-background-push-sound-session-breakdown.md` | Local bounded fallback used after fresh child materialization failed on `/Users/I560101/.codex/sessions`; no Flutter production change was needed, and the direct fallback/suppression/routing suites passed through the writable Flutter SDK overlay at `/tmp/flutter-sdk-report75`. |
| `3` | `Notification matrix, gate classification, and acceptance closure` | `acceptance-only` | `Test-Flight-Improv/75-ios-background-push-sound-session-3-plan.md` | `1`, `2` | `accepted_with_explicit_follow_up` | `Test-Flight-Improv/75-ios-background-push-sound-session-3-plan.md`, `Test-Flight-Improv/75-ios-background-push-sound-session-breakdown.md`, `Test-Flight-Improv/52-notification-journey-test-matrix.md`, `Test-Flight-Improv/test-gate-definitions.md` | Local bounded fallback used after fresh child materialization failed on `/Users/I560101/.codex/sessions`; the matrix and gate docs were updated, the relay + Flutter acceptance bundle passed, and the only remaining item is explicit manual simulator/TestFlight audible confirmation. |

## Final program verdict

- Status:
  `residual_only`
- Last updated:
  `2026-04-24`
- Completion summary:
  - planning, execution, and closure continued through bounded local fallbacks
    because fresh child materialization was blocked by
    `/Users/I560101/.codex/sessions` permission errors
  - session `1` accepted after the relay message APNs builders gained the
    explicit sound contract and both the focused and full relay Go test runs
    passed with `GOCACHE=/tmp/go-build-report75`
  - session `2` accepted after the Flutter proof-only test additions landed and
    the background fallback, suppression, routing, and quiet-foreground suites
    passed through the writable Flutter SDK overlay at `/tmp/flutter-sdk-report75`
  - session `3` accepted_with_explicit_follow_up after the notification matrix
    and gate docs were updated, the relay + Flutter acceptance replay passed,
    and `./scripts/run_test_gates.sh completeness-check` passed
  - no broad repo gap remains for Report `75`; the only residual item is manual
    simulator/TestFlight audible confirmation, which stays explicitly external
    and should reopen the report only if later evidence shows the OS-level
    audio contract still fails in practice

## Ordered session breakdown

### Session 1

- Title:
  `Relay APNs audible message push contract`
- Session id:
  `1`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/75-ios-background-push-sound-session-1-plan.md`
- Exact scope:
  - add the explicit APNs sound value for user-visible 1:1 message pushes that
    route through `buildPushMessage(...)`
  - add the same explicit APNs sound value for ciphertext-only 1:1 and group
    message pushes that route through `buildCiphertextOnlyPushMessage(...)`
  - preserve `apns-push-type: alert`, `apns-priority: 10`,
    `content-available`, `mutable-content`, thread IDs, fallback alert copy,
    and route data
  - preserve encrypted message privacy guarantees: no plaintext title/body,
    sender display name, group name, media descriptor, or outer sender username
    is reintroduced
  - preserve Android encrypted message data-only behavior and high priority
  - keep non-message notification families such as intros, contact requests,
    and group invites out of scope unless the implementation already shares a
    helper that requires the sound assertion to stay generalized
- Why it is its own session:
  - the missing background sound bug originates in the provider payload
    contract, and the relay has a focused Go test family that can prove the
    deterministic APNs shape without touching Flutter behavior
  - this server-side change can land independently while leaving Flutter local
    fallback and foreground quietness for a later session
- Likely code-entry files:
  - `go-relay-server/inbox.go`
  - `go-relay-server/inbox_test.go`
- Likely direct tests/regressions:
  - `go test ./...` from `go-relay-server`
  - focused assertions in:
    - `TestBuildChatPushMessage_LegacyPlaintextEnvelopeEmitsOnlyFallbackAndRouteData`
    - `TestBuildChatPushMessage_CarriesEncryptedDataWithoutPlaintextPreview`
    - `TestBuildGroupPushMessage_CarriesEncryptedDataWithoutPlaintextPreview`
  - any existing push-shape tests touched by the helper change
- Likely named gates:
  - direct relay Go test command
  - `./scripts/run_test_gates.sh completeness-check` only if gate docs are
    changed in this session
- Matrix/closure docs to update when done:
  - this breakdown ledger
  - the session plan artifact
- Dependency on earlier sessions:
  none
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

### Session 2

- Title:
  `Flutter local fallback sound and quiet suppression proof`
- Session id:
  `2`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/75-ios-background-push-sound-session-2-plan.md`
- Exact scope:
  - prove the background local fallback path uses
    `mknoonMessagesNotificationDetails` with iOS `presentSound: true`,
    `presentAlert: true`, `presentBadge: true`, and Android `playSound: true`
  - keep `lib/core/notifications/local_notification_support.dart` unchanged
    unless the current details no longer satisfy that contract
  - preserve `lib/main.dart` foreground remote presentation options with
    `sound: false`
  - preserve active-conversation notification suppression for 1:1 and group
    notifications while the app is resumed
  - preserve recent-remote duplicate suppression so a visible remote push plus
    later local replay does not create a duplicate audible local notification
  - preserve background fallback route payloads and notification tap routing
    for chat and group message targets
- Why it is its own session:
  - Flutter local fallback and suppression behavior are a different runtime
    seam from relay APNs payload construction and require Dart unit/integration
    evidence rather than Go payload tests
  - this session guards against the main regression risk of the server fix:
    solving background sound must not make foreground or already-open chats
    noisy
- Likely code-entry files:
  - `lib/core/notifications/local_notification_support.dart`
  - `lib/main.dart`
  - `lib/features/push/application/background_message_handler.dart`
  - `lib/features/push/application/show_notification_use_case.dart`
  - `test/core/notifications/local_notification_support_test.dart`
  - `test/features/push/application/background_message_handler_test.dart`
  - `test/features/push/application/show_notification_use_case_test.dart`
  - `test/features/push/application/chat_and_group_push_open_flow_test.dart`
  - `test/integration/notification_tap_smoke_test.dart`
- Likely direct tests/regressions:
  - `flutter test test/core/notifications/local_notification_support_test.dart`
  - `flutter test test/features/push/application/background_message_handler_test.dart`
  - `flutter test test/features/push/application/show_notification_use_case_test.dart`
  - `flutter test test/features/push/application/chat_and_group_push_open_flow_test.dart`
  - `flutter test test/integration/notification_tap_smoke_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh baseline` if shared startup, foreground push,
    or tap-routing behavior changes
  - direct notification suites above are mandatory because this notification
    work is not fully represented by one frozen named gate
- Matrix/closure docs to update when done:
  - this breakdown ledger
  - the session plan artifact
- Dependency on earlier sessions:
  `1`
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

### Session 3

- Title:
  `Notification matrix, gate classification, and acceptance closure`
- Session id:
  `3`
- Session classification:
  `acceptance-only`
- Intended plan file:
  `Test-Flight-Improv/75-ios-background-push-sound-session-3-plan.md`
- Exact scope:
  - update `Test-Flight-Improv/52-notification-journey-test-matrix.md` with an
    explicit iOS background-audible row for 1:1 and group message pushes,
    linking the deterministic relay and Flutter evidence from Sessions `1` and
    `2`
  - classify any new direct test files or smoke scripts in
    `Test-Flight-Improv/test-gate-definitions.md` without widening frozen
    named gates unless the repo's gate policy already requires it
  - run the feasible direct tests and named gates from Sessions `1` and `2`
    again as the acceptance bundle
  - record whether simulator or device-level audible proof was completed; if
    it cannot be completed in this environment, keep it as an explicit
    non-blocking follow-up rather than implying the OS produced audible sound
  - update this breakdown ledger with final statuses and a final program
    verdict
- Why it is its own session:
  - the stable notification matrix and final acceptance evidence span the relay
    and Flutter sessions, so closure must happen after both have landed
  - real iOS audible behavior depends on OS notification settings, Focus,
    silent mode, simulator audio, and APNs delivery; those conditions should be
    recorded honestly separate from deterministic payload/unit evidence
- Likely code-entry files:
  - `Test-Flight-Improv/52-notification-journey-test-matrix.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `Test-Flight-Improv/75-ios-background-push-sound-session-breakdown.md`
  - optionally `Test-Flight-Improv/notification-sound-smoke-plan.md` if the
    existing smoke plan needs a narrow cross-reference to Report `75`
- Likely direct tests/regressions:
  - replay the accepted direct Go and Flutter commands from Sessions `1` and
    `2`
  - `./scripts/run_test_gates.sh completeness-check`
  - `dart run integration_test/scripts/run_notification_sound_smoke.dart` only
    if the existing smoke harness is present and two suitable simulators plus
    manual audio confirmation are available
- Likely named gates:
  - `./scripts/run_test_gates.sh baseline` when Flutter startup/tap routing
    evidence changed
  - `./scripts/run_test_gates.sh completeness-check` when docs or gate
    classifications changed
- Matrix/closure docs to update when done:
  - this breakdown ledger
  - `Test-Flight-Improv/52-notification-journey-test-matrix.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Dependency on earlier sessions:
  `1`, `2`
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Why this is not fewer sessions

- The APNs payload sound fix is a Go relay contract with provider-payload tests;
  bundling it with Flutter fallback/suppression tests would mix independent
  server and client evidence families and make failures harder to isolate.
- Flutter local fallback and foreground quietness are the main regression guard
  for user noise. They should be verified after the relay contract lands but
  before claiming acceptance.
- Stable matrix and final acceptance have to summarize evidence from both code
  sessions and keep manual iOS audible proof honest, so they need a separate
  closure pass instead of being hidden inside either implementation session.
