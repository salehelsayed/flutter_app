# 73 - On-Device Push Decrypt Session Breakdown

## decomposition artifact

- Artifact path:
  `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/73-on-device-push-decrypt-plan.md`
- Decomposition date:
  `2026-04-24`
- Decomposition status:
  `local fallback after spawned decomposer no-progressed without leaving the adjacent breakdown artifact`
- Downstream workflow rule:
  detailed planning happens one session at a time; later sessions must be
  refreshed against landed code and tests before execution.

## downstream execution path

- Reuse an existing doc-scoped session plan when safe; otherwise create or
  tighten it with `$implementation-plan-orchestrator`.
- Execute each session with `$implementation-execution-qa-orchestrator`.
- Close each session with `$implementation-closure-audit-orchestrator`.
- Use fresh child-agent contexts for planning, execution, and closure when
  available.
- Continue session by session until this breakdown records a final program
  verdict. A first plan, first accepted session, or first ledger update is not
  pipeline completion.
- Treat this as an implementation-committed rollout for the source plan's
  closure bar: do not downgrade implementation-ready code/test sessions to
  doc-only work because the feature is currently open.

## recommended plan count

- `9`

## overall closure bar

Report `73` is closed only when message notification previews for 1:1 and group
messages are rendered from device-side decryption while the relay and push
providers see only ciphertext plus routing metadata:

- relay APNs and FCM message pushes emit no plaintext preview body, title,
  sender display name, group name, media descriptor, or outer 1:1
  `senderUsername`
- 1:1 and group send paths stop sending plaintext `pushTitle` / `pushBody`;
  the 1:1 sender username is inside the encrypted payload and compatible
  receivers read it from decrypted content
- Android background/data handling decrypts supported ciphertext payloads,
  renders typed previews, preserves tap routing, and degrades to `New message`
  on missing keys, corrupt data, unsupported kinds, or timeout-equivalent
  failures
- iOS has a Notification Service Extension with shared key access that decrypts
  the same fixture set, rewrites title/body/threading, dedupes replayed
  message IDs, and degrades without leaking plaintext
- foreground drain, active-conversation suppression, route-open preparation,
  and duplicate notification suppression remain green for ciphertext payloads
- cross-platform fixtures, frozen rollout payloads, simulator smoke scripts,
  and named gates prove old/new compatibility, routing, background/terminated
  handling, and no-plaintext security invariants
- telemetry captures decrypt success/failure/timeout/degrade causes and the
  configured TestFlight degrade-rate gate can distinguish expected old-build
  fallback from real decrypt failures
- cleanup removes only the legacy compatibility paths whose retirement is
  justified by the minimum-client-version floor, and maintained notification
  docs/gate definitions match the landed behavior

## source of truth

Primary source doc and gate docs:

- `Test-Flight-Improv/73-on-device-push-decrypt-plan.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/52-notification-journey-test-matrix.md`
- `Test-Flight-Improv/53-notification-background-delivery-reliability-plan.md`
- `Test-Flight-Improv/71-foreground-group-push-drain-gap-plan.md`

Authoritative contract files and likely entry points:

- `go-relay-server/inbox.go`
- `go-relay-server/inbox_test.go`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/group_offline_replay_envelope.dart`
- `lib/features/conversation/domain/models/message_payload.dart`
- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/features/push/application/background_message_handler.dart`
- `lib/features/push/application/background_push_notification_fallback.dart`
- `lib/features/push/application/show_notification_use_case.dart`
- `lib/core/bridge/bridge.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `lib/core/secure_storage/secure_key_store.dart`
- `lib/core/secure_storage/flutter_secure_key_store.dart`
- `ios/Runner/Runner.entitlements`
- `ios/Share Extension/`

Disagreement rule:

- current code and tests beat stale prose
- `go-relay-server/inbox_test.go` is authoritative for relay push shape
- `Test-Flight-Improv/test-gate-definitions.md` and
  `./scripts/run_test_gates.sh` decide named gate membership

## session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Closure docs touched | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `1` | `Relay ciphertext-only push contract and legacy-degrade metrics` | `implementation-ready` | `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-1-plan.md` | none | `accepted` | `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-breakdown.md`, `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-1-plan.md` | Message push builders now emit APNs fallback + mutable-content and Android data-only payloads with encrypted route data; 1:1/group tests assert no plaintext title/body/sender preview fields. Verification: `go test ./...` from `go-relay-server`. |
| `2` | `Client send-path redaction and 1:1 encrypted sender identity` | `implementation-ready` | `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-2-plan.md` | `1` | `accepted` | `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-breakdown.md`, `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-2-plan.md` | New encrypted 1:1 envelopes omit outer `senderUsername`; group replay helpers tolerate legacy preview fields but no longer serialize or forward `pushTitle`/`pushBody`. Verification: focused message-payload, group-send, and group retry Flutter suites passed. |
| `3` | `Push fixture, frozen-payload, routing, and no-plaintext security foundation` | `implementation-ready` | `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-3-plan.md` | `1`, `2` | `accepted` | `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-breakdown.md`, `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-3-plan.md`, `Test-Flight-Improv/test-gate-definitions.md` | Added committed push fixtures/frozen payloads, ciphertext route coverage, Go/Dart forbidden-field classifiers, and `test/security` gate classification. Verification: focused notification/security Flutter tests, relay `go test ./...`, and completeness-check passed. |
| `4` | `Android data-only decrypt-and-replace handler` | `implementation-ready` | `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-4-plan.md` | `3` | `accepted` | `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-breakdown.md`, `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-4-plan.md` | Added a Dart decrypt-preview resolver with 1:1/group fallback behavior, preview caps, Android decrypt flow events, and a background-handler resolver seam. Verification: focused push decrypt and background handler tests passed. |
| `5` | `iOS shared key access, entitlements, and NSE target foundation` | `implementation-ready` | `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-5-plan.md` | `3` | `accepted` | `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-breakdown.md`, `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-5-plan.md` | Added access-group-aware secure storage, matching Runner/NotificationService App Group and Keychain entitlements, a buildable NotificationService app-extension target embedded by Runner, and iOS configuration tests. Verification: focused secure-store Flutter test, plist/project lint, NotificationService simulator build, and focused Xcode configuration test passed. |
| `6` | `iOS NSE decrypt/render, dedupe, and leak-safe preview parity` | `implementation-ready` | `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-6-plan.md` | `5` | `accepted` | `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-breakdown.md`, `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-6-plan.md` | Added an iOS NotificationService preview resolver, Go bridge decryptor, shared keychain reader, atomic App Group dedupe, app-side shared push-key mirroring, CocoaPods GoMknoon linkage, and Swift fixture/fallback/dedupe tests. Verification: focused Dart mirror tests, pod install, workspace NotificationService build, and focused Xcode resolver tests passed. |
| `7` | `Observability, degrade-rate gate, and push schema version decision` | `implementation-ready` | `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-7-plan.md` | `4`, `6` | `accepted` | `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-breakdown.md`, `Test-Flight-Improv/test-gate-definitions.md`, `Test-Flight-Improv/52-notification-journey-test-matrix.md`, `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-7-plan.md` | Added leak-safe Android and iOS NSE decrypt telemetry, a deterministic `push_preview_degrade_rate_gate` calculator/command, no-plaintext telemetry tests, no-direct-schema-version push data assertions, and TestFlight soak gate docs. Verification: focused Flutter telemetry tests, relay `go test ./...`, focused iOS resolver tests, runtime telemetry gate, and completeness-check passed. |
| `8` | `Cross-platform simulator smoke and final acceptance matrix` | `acceptance-only` | `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-8-plan.md` | `4`, `6`, `7` | `accepted` | `scripts/smoke_test_push_decrypt_simulator.sh`, `scripts/push_fixture_to_simulator.sh`, `scripts/push_fixture_to_android_emulator.sh`, `test/features/push/fixtures/*.json`, `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-breakdown.md`, `Test-Flight-Improv/52-notification-journey-test-matrix.md`, `Test-Flight-Improv/test-gate-definitions.md`, `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-8-plan.md` | Expanded the simulator smoke harness to enumerate and run S-iOS-1..19 and S-And-1..19, fixed Android broadcast quoting for values with spaces, added missing fixtures, and passed non-dry-run smoke on installed iPhone 17, iPhone 17 Pro, and `emulator-5554`. Full companion gates passed: `flutter test`, relay `go test ./...`, iOS Runner xcodebuild tests, baseline, 1to1, groups, runtime-telemetry, completeness-check, and push release gate. |
| `9` | `Legacy cleanup, compatibility retirement, and maintained-doc closure` | `closure-only` | `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-9-plan.md` | `8` | `accepted` | `go-relay-server/inbox.go`, `go-relay-server/metrics.go`, `go-relay-server/inbox_test.go`, `go-relay-server/forbidden_field_classifier_test.go`, `lib/core/bridge/bridge_group_helpers.dart`, `lib/features/groups/application/group_offline_replay_envelope.dart`, `lib/features/push/application/background_push_notification_fallback.dart`, `Test-Flight-Improv/52-notification-journey-test-matrix.md`, `Test-Flight-Improv/test-gate-definitions.md`, `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-breakdown.md`, `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-9-plan.md` | Retired dead `pushTitle`/`pushBody` relay and Dart helper plumbing, removed the rollout-only legacy plaintext push metric, stopped background fallback from reading retired plaintext preview fields, and documented the final ciphertext-only closure. Verification passed: focused cleanup suites, relay `go test ./...`, named gates, release gate, and final full `flutter test`. |

## ordered session breakdown

### Session 1

- Title:
  `Relay ciphertext-only push contract and legacy-degrade metrics`
- Session id:
  `1`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-1-plan.md`
- Exact scope:
  - change relay message push construction so 1:1, group, and dissolve message
    pushes put ciphertext/routing metadata in `data` and emit only the static
    degraded alert fallback where provider payloads require an alert
  - keep contact-request, introduction, and group-invite static push shapes
    unchanged
  - make `inbox_test.go` assert absence of `pushBody`, `pushTitle`,
    `senderUsername`, group names, sender display names, and media descriptors
    in APNs/FCM/log/metric surfaces where Phase 1 owns them
  - preserve group fanout and post-push envelope retrieval behavior
  - add legacy cleartext exposure measurement for inbound old-format senders
    without re-emitting plaintext
  - add relay-side 1:1 outer-envelope sender-username scrub/back-compat tests
- Why it is its own session:
  server push shape is the upstream privacy boundary and can ship
  independently per the product decision in Section 9.8. It has Go-only
  contract tests and different rollout risk from Flutter/iOS handlers.
- Likely code-entry files:
  - `go-relay-server/inbox.go`
  - `go-relay-server/inbox_test.go`
  - possible relay metrics/helpers near existing push providers
- Likely direct tests/regressions:
  - `go test ./go-relay-server/...`
  - `TestBuildMessagePush_CiphertextOnlyDataPayload`
  - `TestBuildGroupPush_CiphertextOnlyDataPayload`
  - `TestBuildDissolvePush_FlowsThroughCiphertextOnlyPath`
  - `TestBuildContactRequestPush_UnchangedShape`
  - `TestBuildGroupInvitePush_UnchangedShape`
  - `TestBuildIntroductionPush_UnchangedShape`
  - `TestBuildMessagePush_PayloadSizeWithinProviderBudgets`
  - group fanout and post-push retrieval tests from Sections 9.1.24 and 9.1.25
  - legacy-v2-envelope metric/back-compat tests from Sections 9.1.26 and 9.1.29
- Likely named gates:
  - direct `go test ./...` or the repo's Go relay test command
  - Group Messaging Gate after client-side integration points are touched or
    as a final regression check for the push fanout contract
  - Baseline Gate if shared app push fixtures or route tests are changed in
    the same session
- Matrix/closure docs to update when done:
  - this breakdown ledger
  - defer stable matrix changes to Sessions 7-9 unless Session 1 changes the
    rollout compatibility statement
- Dependency on earlier sessions:
  none

### Session 2

- Title:
  `Client send-path redaction and 1:1 encrypted sender identity`
- Session id:
  `2`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-2-plan.md`
- Exact scope:
  - remove client-built `pushTitle` / `pushBody` metadata from group message
    sends while preserving encrypted offline replay envelopes
  - update group dissolve sender path to use the ciphertext-only message path
    required by Section 9.1.1.1
  - change the 1:1 payload/envelope so `senderUsername` is inside encrypted
    content rather than a relay-visible outer field
  - keep rollout-window receive compatibility for legacy v2 1:1 envelopes
  - add Dart send-path and serialization tests proving plaintext preview data
    is not emitted from send use cases
- Why it is its own session:
  sender-side redaction changes Flutter/domain envelope contracts and must
  land after the relay can ignore old preview fields. It has a different test
  family from the relay and from platform notification rendering.
- Likely code-entry files:
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/application/group_offline_replay_envelope.dart`
  - `lib/features/groups/application/dissolve_group_use_case.dart`
  - `lib/features/conversation/domain/models/message_payload.dart`
  - `lib/features/conversation/application/send_chat_message_use_case.dart`
  - receive-path models/listeners that parse legacy and new 1:1 payloads
- Likely direct tests/regressions:
  - `flutter test test/features/groups/application/send_group_message_use_case_test.dart`
  - `flutter test test/features/groups/application/dissolve_group_use_case_test.dart`
  - `flutter test test/features/groups/application/send_group_reaction_use_case_test.dart`
  - `flutter test test/features/conversation/domain/models/message_payload_test.dart`
  - `flutter test test/features/conversation/application/send_chat_message_use_case_test.dart`
  - `flutter test test/features/conversation/application/chat_message_listener_test.dart`
  - `flutter test test/security/no_plaintext_leak_test.dart`
  - Dart forbidden-field classifier coverage for send use cases
- Likely named gates:
  - `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh groups`
  - direct Notification Gate candidates named in Session 3
- Matrix/closure docs to update when done:
  - this breakdown ledger
  - `Test-Flight-Improv/test-gate-definitions.md` only if new security tests
    are classified in this session
- Dependency on earlier sessions:
  `1`

### Session 3

- Title:
  `Push fixture, frozen-payload, routing, and no-plaintext security foundation`
- Session id:
  `3`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-3-plan.md`
- Exact scope:
  - add deterministic Go fixture generation for push decrypt payloads and
    mirror committed fixtures into Dart and iOS test fixture locations
  - add fixture drift checks and a README describing fixture fields
  - add frozen rollout payloads for pre-Phase-1, post-Phase-1, post-Phase-2,
    and post-Phase-3/4 compatibility states
  - add or extend notification route contract tests for ciphertext payloads
  - establish forbidden-field classifier helpers for Go and Dart surfaces;
    leave Swift-specific scanner integration to Session 6 if the target does
    not exist yet
  - classify newly added security/fixture/routing tests in gate docs so
    completeness checks stay truthful
- Why it is its own session:
  Android and iOS decrypt work need stable shared fixtures and compatibility
  payloads. Keeping this foundation separate prevents platform sessions from
  inventing incompatible local fixtures.
- Likely code-entry files:
  - `go-relay-server/testfixtures/push_crypto_fixtures_test.go`
  - `go-mknoon/crypto/testhelpers/deterministic_nonce.go`
  - `test/features/push/fixtures/*.json`
  - `test/features/push/fixtures/README.md`
  - `test/features/push/frozen_payloads/*.json`
  - `test/core/notifications/notification_route_contract_matrix_test.dart`
  - `test/core/notifications/notification_route_target_test.dart`
  - `test/security/forbidden_field_classifier_test.dart`
  - `go-relay-server/forbidden_field_classifier_test.go`
- Likely direct tests/regressions:
  - `go test ./go-relay-server/testfixtures/...`
  - `go test ./go-relay-server/...`
  - `flutter test test/features/push/cross_platform_parity_test.dart`
  - `flutter test test/core/notifications/notification_route_contract_matrix_test.dart`
  - `flutter test test/core/notifications/notification_route_target_test.dart`
  - `flutter test test/features/push/old_handler_frozen_payload_compatibility_test.dart`
  - `scripts/run_old_handler_compatibility.sh` against the last released tag
  - `flutter test test/security/forbidden_field_classifier_test.dart`
- Likely named gates:
  - Notification Gate direct suites:
    `test/core/notifications/notification_route_contract_matrix_test.dart`,
    `test/core/notifications/notification_route_target_test.dart`
  - `./scripts/run_test_gates.sh baseline`
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh completeness-check`
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/test-gate-definitions.md`
  - this breakdown ledger
- Dependency on earlier sessions:
  `1`, `2`

### Session 4

- Title:
  `Android data-only decrypt-and-replace handler`
- Session id:
  `4`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-4-plan.md`
- Exact scope:
  - extend the FCM background handler to parse ciphertext-only push data,
    decrypt 1:1/group/dissolve envelopes through existing bridge commands, and
    show rewritten local notifications
  - keep dual tolerance for legacy plaintext push bodies and both-present
    payloads during staged rollout
  - implement shared preview formatting rules including typed media
    descriptors and the 140-grapheme cap for push previews only
  - handle key-missing, corrupt ciphertext, tampered signatures, unknown
    envelope kinds, and permission-denied paths by degrading without crashing
  - preserve notification tap routing, active-conversation suppression,
    foreground group drain behavior from Report 71, and no duplicate local
    notification behavior
  - add Android decrypt flow events without logging plaintext
- Why it is its own session:
  Android has a Dart background-isolate implementation and emulator-focused
  evidence. It can land after shared fixtures without being blocked by iOS NSE
  target work.
- Likely code-entry files:
  - `lib/features/push/application/background_message_handler.dart`
  - `lib/features/push/application/background_push_notification_fallback.dart`
  - `lib/features/push/application/show_notification_use_case.dart`
  - `lib/core/bridge/bridge.dart`
  - `lib/core/bridge/bridge_group_helpers.dart`
  - `lib/core/notifications/notification_route_target.dart`
  - `integration_test/foreground_group_push_drain_test.dart`
  - `integration_test/foreground_onetoone_push_drain_test.dart`
- Likely direct tests/regressions:
  - `flutter test test/features/push/application/background_message_handler_test.dart`
  - `flutter test test/features/push/application/push_preview_body_test.dart`
  - `flutter test test/features/push/application/show_notification_use_case_test.dart`
  - `flutter test test/features/push/application/background_push_notification_fallback_test.dart`
  - `flutter test test/features/push/application/permission_denied_test.dart`
  - `flutter test test/features/push/cross_platform_parity_test.dart`
  - `flutter test test/features/push/performance/background_decrypt_benchmark_test.dart`
  - `flutter test integration_test/foreground_group_push_drain_test.dart`
  - `flutter test integration_test/foreground_onetoone_push_drain_test.dart`
  - Android emulator rows S-And-1 through S-And-19 on Pixel 7 API 37
- Likely named gates:
  - Notification direct suites listed in `test-gate-definitions.md`
  - `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh baseline`
  - Android smoke rows from Section 9.5
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/test-gate-definitions.md`
  - this breakdown ledger
- Dependency on earlier sessions:
  `3`

### Session 5

- Title:
  `iOS shared key access, entitlements, and NSE target foundation`
- Session id:
  `5`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-5-plan.md`
- Exact scope:
  - extend secure key storage so the main app can write identity and group
    keys into the iOS Keychain access group readable by the NSE
  - migrate legacy keychain items idempotently and preserve fresh-install
    behavior
  - add a Notification Service Extension target with App Group and Keychain
    access-group entitlements aligned with Runner
  - add build-time entitlement and bundle-size gates before decrypt logic is
    introduced
  - prove cold-boot/unreadable-key degradation paths at the unit/XCTest level
- Why it is its own session:
  key sharing and target wiring are prerequisites for all iOS decrypt work and
  are high-risk platform/build configuration changes that need their own
  verification before preview rendering is added.
- Likely code-entry files:
  - `lib/core/secure_storage/secure_key_store.dart`
  - `lib/core/secure_storage/flutter_secure_key_store.dart`
  - iOS plugin or platform-channel code backing access-group configuration
  - `ios/Runner.xcodeproj/project.pbxproj`
  - `ios/Runner/Runner.entitlements`
  - `ios/NotificationService/NotificationService.entitlements`
  - `ios/RunnerTests/*Keychain*Tests.swift`
- Likely direct tests/regressions:
  - `flutter test` suites for secure storage wrapper behavior where host-side
    seams exist
  - `xcodebuild test -scheme RunnerTests` keychain migration tests:
    `test_legacyKeychainItem_migratedToAccessGroup_readableByNSE`,
    `test_migrationIsIdempotent`,
    `test_freshInstall_usesAccessGroupFromFirstWrite`,
    `test_coldBoot_deviceLocked_NSEDegradesGracefully`,
    `test_afterFirstUnlock_keychainAccessible_NSEDecrypts`
  - entitlement tests:
    `test_NSEEntitlements_matchRunnerEnvironment`,
    `test_NSEEntitlements_accessGroupMatchesMainApp`
  - NSE bundle-size CI gate
- Likely named gates:
  - `xcodebuild test -scheme RunnerTests`
  - Startup / Transport Gate only if app bootstrap or platform initialization
    is changed
  - `./scripts/run_test_gates.sh baseline`
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/test-gate-definitions.md`
  - this breakdown ledger
- Dependency on earlier sessions:
  `3`

### Session 6

- Title:
  `iOS NSE decrypt/render, dedupe, and leak-safe preview parity`
- Session id:
  `6`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-6-plan.md`
- Exact scope:
  - implement NSE decrypt for 1:1, group, and dissolve ciphertext using the
    shared fixtures and existing crypto bridge or a verified Swift equivalent
  - rewrite notification title/body/threadIdentifier for decrypted message
    previews while leaving placeholder fallback on key-missing, corruption,
    tampered signature, unknown kind, timeout, or `serviceExtensionTimeWillExpire`
  - port the push preview formatter and 140-grapheme cap with parity tests
  - implement extracted dedupe sentinel logic for replayed message IDs and
    concurrent writes
  - add Swift no-plaintext leak scanner for logs and flow events emitted by
    the extension
  - preserve mute/DND design decision that the NSE does not consult app mute
    state, and add the muted-group behavioral regression required by the plan
- Why it is its own session:
  actual iOS decrypt/render behavior depends on Session 5 but has different
  correctness, race, timeout, and presentation risks. It owns the main iOS
  user-visible preview parity contract.
- Likely code-entry files:
  - `ios/NotificationService/NotificationService.swift`
  - `ios/NotificationService/*`
  - `ios/RunnerTests/NotificationServiceTests.swift`
  - `ios/RunnerTests/Fixtures/*`
  - `ios/RunnerTests/NSEDedupeSentinelTests.swift`
  - Swift preview formatting helpers
- Likely direct tests/regressions:
  - `xcodebuild test -scheme RunnerTests`
  - `test_decryptsOneToOneCiphertext_replacesBody`
  - `test_decryptsGroupCiphertext_replacesTitleAndBody`
  - `test_keyMissing_leavesPlaceholderBody`
  - `test_corruptCiphertext_leavesPlaceholderBody`
  - `test_timeWillExpire_deliversPlaceholder`
  - `test_mediaOnlyPlaintext_rendersTypedDescriptor`
  - `test_replayedMessageId_notShownTwice`
  - `test_concurrentWrites_sentinelStaysValidJSON`
  - `test_decryptedPlaintext_neverAppearsInSwiftLogs`
  - `test_decryptedPlaintext_neverAppearsInFlowEventsEmittedFromNSE`
  - iOS simulator rows S-iOS-1 through S-iOS-19 after smoke wiring exists
- Likely named gates:
  - `xcodebuild test -scheme RunnerTests`
  - iOS simulator smoke from Section 9.5
  - `./scripts/run_test_gates.sh baseline`
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/test-gate-definitions.md`
  - this breakdown ledger
- Dependency on earlier sessions:
  `5`

### Session 7

- Title:
  `Observability, degrade-rate gate, and push schema version decision`
- Session id:
  `7`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-7-plan.md`
- Exact scope:
  - add flow events and counters for iOS NSE decrypt ok/fail/timeout and
    Android data decrypt ok/fail without including plaintext or canary strings
  - implement deterministic degrade-rate gate tests, including
    `client_pre_decrypt` exclusion for expected old-build fallback
  - update `test-gate-definitions.md` with runtime telemetry gate definitions
    and plan-specific direct suites
  - decide and test push-data schema versioning behavior from Section 9.10.5
  - add dashboard or metric documentation needed to operate the TestFlight soak
    window from Section 9.10
- Why it is its own session:
  telemetry and release gates need both platform decrypt paths to exist before
  their events are meaningful, but they should land before final acceptance so
  the release can be stopped by measured degrade rate.
- Likely code-entry files:
  - flow-event and telemetry helpers near existing push code
  - Android decrypt handler event emission
  - iOS NSE event emission path or test listener
  - `Test-Flight-Improv/test-gate-definitions.md`
  - telemetry gate test files under `test/features/push/` or `test/security/`
  - `Test-Flight-Improv/52-notification-journey-test-matrix.md`
- Likely direct tests/regressions:
  - telemetry-gate test feeding mixed decrypt/degrade events
  - no-plaintext-in-flow-events gate
  - `flutter test test/security/forbidden_field_classifier_test.dart`
  - `xcodebuild test -scheme RunnerTests` for Swift event leak scanner
  - `./scripts/run_test_gates.sh completeness-check`
- Likely named gates:
  - Runtime Telemetry Gates once added
  - Notification direct suites
  - `./scripts/run_test_gates.sh baseline`
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `Test-Flight-Improv/52-notification-journey-test-matrix.md`
  - this breakdown ledger
- Dependency on earlier sessions:
  `4`, `6`

### Session 8

- Title:
  `Cross-platform simulator smoke and final acceptance matrix`
- Session id:
  `8`
- Session classification:
  `acceptance-only`
- Intended plan file:
  `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-8-plan.md`
- Exact scope:
  - add or finalize `scripts/push_fixture_to_simulator.sh`,
    `scripts/push_fixture_to_android_emulator.sh`, and
    `scripts/smoke_test_push_decrypt_simulator.sh`
  - build and install `com.mknoon.app` on the configured iPhone 17,
    iPhone 17 Pro, and Pixel 7 API 37 targets before non-dry-run smoke;
    verify iOS app containers and Android package path before injecting pushes
  - run or document the authoritative iOS simulator rows S-iOS-1 through
    S-iOS-19 and Android emulator rows S-And-1 through S-And-19, including
    background and terminated-state columns
  - verify notification tap routing through existing
    `NotificationRouteTarget.fromRemoteMessageData` paths for ciphertext
    payloads
  - verify foreground drain and active-conversation suppression with
    ciphertext payloads for both 1:1 and group paths
  - confirm CI runtime budget placement and nightly-vs-PR split
  - update the notification journey matrix with landed evidence and explicit
    simulator limitations
- Why it is its own session:
  this is the whole-feature acceptance layer that spans both platform
  implementations and telemetry. It should not be mixed with one platform's
  implementation work because it validates cross-platform release readiness.
- Likely code-entry files:
  - `scripts/push_fixture_to_simulator.sh`
  - `scripts/push_fixture_to_android_emulator.sh`
  - `scripts/smoke_test_push_decrypt_simulator.sh`
  - `scripts/smoke_test_push_decrypt.sh`
  - `integration_test/foreground_group_push_drain_test.dart`
  - `integration_test/foreground_onetoone_push_drain_test.dart`
  - `Test-Flight-Improv/52-notification-journey-test-matrix.md`
- Likely direct tests/regressions:
  - app-installed OS-smoke preflight:
    `flutter build ios --simulator --debug`,
    `xcrun simctl install <iphone-17> build/ios/iphonesimulator/Runner.app`,
    `xcrun simctl install <iphone-17-pro> build/ios/iphonesimulator/Runner.app`,
    `flutter build apk --debug`,
    `/Users/I560101/Library/Android/sdk/platform-tools/adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk`,
    and `get_app_container` / `pm path com.mknoon.app` verification
  - iOS simulator smoke rows S-iOS-1 through S-iOS-19
  - Android emulator smoke rows S-And-1 through S-And-19
  - `scripts/smoke_test_push_decrypt_simulator.sh`
  - `flutter test`
  - `(cd go-relay-server && go test ./...)`
  - `xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,name=iPhone 17'`
  - `flutter test test/features/push/application/chat_and_group_push_open_flow_test.dart`
  - `flutter test test/core/notifications/notification_route_contract_matrix_test.dart`
  - `flutter test test/core/notifications/notification_route_target_test.dart`
  - `flutter test integration_test/foreground_group_push_drain_test.dart`
  - `flutter test integration_test/foreground_onetoone_push_drain_test.dart`
  - full PR-budget gate set documented in Section 9.9
- Likely named gates:
  - Notification direct suites
  - `./scripts/run_test_gates.sh baseline`
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh runtime-telemetry`
  - `./scripts/run_test_gates.sh completeness-check`
  - `scripts/check_push_release_gate.sh`
  - simulator smoke scripts and nightly matrix jobs
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/52-notification-journey-test-matrix.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
  - this breakdown ledger
- Dependency on earlier sessions:
  `4`, `6`, `7`

### Session 9

- Title:
  `Legacy cleanup, compatibility retirement, and maintained-doc closure`
- Session id:
  `9`
- Session classification:
  `closure-only`
- Intended plan file:
  `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-9-plan.md`
- Exact scope:
  - after the minimum-client-version floor allows it, remove legacy relay
    acceptance paths and old metrics that existed only for rollout measurement
  - delete unused fallback constants only when no call sites remain after
    platform decrypt handling lands
  - convert dual-format back-compat tests to assert relay rejection or absence
    of old preview fields where Phase 6 requires it
  - update maintained notification matrix and gate docs to describe the final
    ciphertext-only preview contract
  - persist the final program verdict in this breakdown artifact
- Why it is its own session:
  cleanup is intentionally blocked on rollout evidence and should not weaken
  early-session compatibility. It is also the natural final doc closure pass.
- Likely code-entry files:
  - `go-relay-server/inbox.go`
  - `go-relay-server/inbox_test.go`
  - `lib/features/push/application/background_push_notification_fallback.dart`
  - `lib/features/push/application/background_message_handler.dart`
  - `Test-Flight-Improv/52-notification-journey-test-matrix.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
  - this breakdown artifact
- Likely direct tests/regressions:
  - full relay tests
  - full Dart notification/security suites from earlier sessions
  - `xcodebuild test -scheme RunnerTests`
  - named gates that changed during the rollout:
    `baseline`, `1to1`, `groups`, Notification direct suites, Runtime
    Telemetry Gates, and completeness check
- Likely named gates:
  - all gates required by touched files
  - final program acceptance review
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/52-notification-journey-test-matrix.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-breakdown.md`
- Dependency on earlier sessions:
  `8`

## why this is not fewer sessions

- Relay push-shape changes can ship before client adoption, have a Go-only
  contract boundary, and must not be coupled to Flutter or iOS build work.
- Sender redaction changes the outbound encrypted envelope and send use cases;
  it needs 1:1 and group regression gates that are separate from relay tests.
- Shared fixtures, frozen payloads, and forbidden-field classifiers are
  prerequisites for both platform handlers. Mixing them into either platform
  session would create duplicate or incompatible fixture ownership.
- Android decrypt behavior is Dart/background-isolate work with emulator
  evidence, while iOS first needs keychain/entitlement/build work before the
  NSE can decrypt anything.
- iOS key sharing and iOS preview rendering are split because App Group and
  Keychain mistakes can block the extension entirely and deserve a smaller
  failure surface before notification rendering is added.
- Observability and degrade-rate gates depend on both platform paths existing,
  but acceptance needs those gates available before release verification.
- Simulator/smoke acceptance validates the end-to-end product behavior across
  both platforms and should not be treated as implementation detail of a single
  platform session.
- Cleanup must wait for compatibility evidence and the minimum-client-version
  floor; doing it earlier would violate the rollout constraints in Section 9.8.

## reviewer and arbiter notes

- Structural blockers found:
  none in the source plan for decomposition purposes.
- Required splits:
  iOS was split into key-sharing/target foundation and decrypt/render parity
  because the build/entitlement risks can fail independently of crypto/render
  logic.
- Mergeable sessions:
  none. Sessions `7` and `8` are close, but telemetry gates must be available
  before final simulator acceptance and release matrix updates.
- Accepted differences:
  physical-device reliability remains deferred/backstopped by TestFlight
  telemetry per Sections 9.4.1.3 and 9.6; this breakdown does not add a
  separate physical-device session.

## pipeline progress

- `2026-04-24`: Spawned decomposition attempt did not leave
  `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-breakdown.md`
  under the bounded wait; the controller closed that attempt and wrote this
  reusable breakdown via the allowed local decomposition fallback.
- `2026-04-24`: Session `1` accepted via local pipeline fallback after
  landing the relay ciphertext-only message push contract in
  `go-relay-server/inbox.go`, adding the aggregate
  `relay_legacy_plaintext_push_payload_total` metric, updating relay tests for
  APNs mutable-content and Android data-only message pushes, and passing
  `go test ./...` from `go-relay-server`.
- `2026-04-24`: Session `2` accepted after removing outer 1:1
  `senderUsername` from new encrypted chat envelopes, stopping group replay
  helpers and group/dissolve send paths from forwarding plaintext
  `pushTitle`/`pushBody`, and passing:
  `flutter test test/features/conversation/domain/models/message_payload_test.dart test/features/groups/application/send_group_message_use_case_test.dart`
  plus
  `flutter test test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart test/features/groups/application/retry_failed_group_messages_use_case_test.dart`.
- `2026-04-24`: Session `3` accepted after adding shared push decrypt
  fixtures and frozen payload examples, extending notification route contract
  tests for ciphertext-shaped data, adding Go and Dart forbidden-field
  classifiers, classifying `test/security/*.dart`, and passing:
  `flutter test test/core/notifications/notification_route_target_test.dart test/core/notifications/notification_route_contract_matrix_test.dart test/security/forbidden_field_classifier_test.dart`,
  `go test ./...` from `go-relay-server`, and
  `./scripts/run_test_gates.sh completeness-check`.
- `2026-04-24`: Session `4` accepted after adding
  `push_decrypt_preview.dart`, wiring `background_message_handler.dart` through
  a testable preview resolver, and passing
  `flutter test test/features/push/application/push_decrypt_preview_test.dart test/features/push/application/background_message_handler_test.dart`.
- `2026-04-24`: Session `5` accepted after adding
  `mknoonSharedAppleAccessGroup` support to `FlutterSecureKeyStore`, aligning
  Runner and NotificationService App Group/Keychain entitlements, wiring a real
  `NotificationService` Xcode app-extension target into Runner's embed phase,
  and passing:
  `flutter test test/core/secure_storage/flutter_secure_key_store_test.dart`,
  `plutil -lint ios/Runner.xcodeproj/project.pbxproj ios/Runner/Runner.entitlements ios/NotificationService/NotificationService.entitlements ios/NotificationService/Info.plist`,
  `xcodebuild -project ios/Runner.xcodeproj -target NotificationService -configuration Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build`,
  and focused
  `xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner ... -only-testing:RunnerTests/NotificationServiceConfigurationTests`.
- `2026-04-24`: Session `6` accepted after adding
  `NotificationPreviewResolver.swift`, wiring `NotificationService.swift` to
  decrypt and rewrite notification previews from ciphertext route data, linking
  `GoMknoon` into the extension through CocoaPods, adding atomic App Group
  duplicate suppression, mirroring app-side 1:1 and group push-decrypt keys
  into shared iOS keychain storage, and passing:
  `flutter test test/features/identity/domain/repositories/identity_repository_impl_test.dart test/features/groups/domain/repositories/group_repository_impl_test.dart`,
  `cd ios && pod install`,
  `xcodebuild -workspace ios/Runner.xcworkspace -scheme NotificationService -configuration Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build`,
  and focused
  `xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner ... -only-testing:RunnerTests/NotificationPreviewResolverTests`.
- `2026-04-24`: Session `7` accepted after adding a testable Dart flow-event
  sink, emitting leak-safe Android and iOS NSE decrypt success/failure/timeout
  telemetry, adding `push_preview_degrade_rate_gate` calculation and command
  coverage with rollout-reason exclusions, asserting the relay push-data
  contract omits direct `schemaVersion` / `version` / `v` keys, and updating
  runtime telemetry gate docs plus matrix row `RG-007`. Verification passed:
  focused Flutter telemetry tests, `go test ./...` from `go-relay-server`,
  focused iOS `NotificationPreviewResolverTests`, `./scripts/run_test_gates.sh
  runtime-telemetry`, and `./scripts/run_test_gates.sh completeness-check`.
- `2026-04-24`: Session `8` made local acceptance progress but remains
  blocked against the source closure bar. Added
  `scripts/push_fixture_to_simulator.sh`,
  `scripts/push_fixture_to_android_emulator.sh`, and
  `scripts/smoke_test_push_decrypt_simulator.sh`; documented simulator smoke
  CI placement and matrix row `RG-008`; passed script syntax, dry-run fixture
  shaping, the focused host-side notification acceptance bundle,
  `flutter test -d macos integration_test/foreground_group_push_drain_test.dart`,
  and `scripts/check_push_release_gate.sh`. Full S-iOS-1 through S-iOS-19 and
  S-And-1 through S-And-19 OS-delivery runs were not executed because the full
  configured simulator/emulator farm with the app installed was not available
  in this workspace.
- `2026-04-24`: Continued from Session `8` using the existing breakdown. The
  spawned Session 8 execution worker did not leave trustworthy disk progress
  under the bounded wait, so it was closed and the controller used local
  execution fallback to recheck the live device prerequisites. Flutter saw
  iPhone 17, iPhone 17 Pro, and `emulator-5554` Android API 37; both iOS
  simulator app-container checks for `com.mknoon.app` failed, and
  `/Users/I560101/Library/Android/sdk/platform-tools/adb -s emulator-5554 shell pm path com.mknoon.app`
  returned no package path. Script syntax and dry-run fixture shaping still
  passed, but Session `8` remains blocked on the full app-installed OS-delivery
  matrix. Session `9` remains prerequisite-blocked.
- `2026-04-24`: Tightened Session `8` after the app-install blocker was
  identified. The Session 8 plan, this breakdown, the main plan's simulator
  automation section, and `test-gate-definitions.md` now require the next
  executor to build/install `com.mknoon.app` on the configured iOS simulators
  and Android emulator before non-dry-run smoke, verify package/container
  presence, run the full non-dry-run smoke, and run the full plan-73
  verification sweep before accepting Session `8`.
- `2026-04-24`: Session `8` continued with the single local execution fallback
  after the spawned worker made build progress but did not persist a final
  verdict under the bounded waits. The fallback passed
  `flutter build ios --simulator --debug`, installed and verified
  `com.mknoon.app` on iPhone 17 and iPhone 17 Pro simulators, passed
  `flutter build apk --debug`, installed and verified `com.mknoon.app` on
  `emulator-5554`, passed the landed non-dry-run smoke subset on both iOS
  simulators and Android, and passed the focused host-side notification bundle,
  foreground group push drain on macOS, runtime telemetry gate,
  completeness-check, and push release gate. Session `8` remains blocked
  because the source closure bar requires S-iOS-1..19 and S-And-1..19
  OS-delivery coverage, while the current harness implements only
  S-iOS-1/3/11/12 and S-And-1/3/17.
- `2026-04-24`: Session `8` accepted after the app-install blocker was cleared
  and the remaining OS-delivery coverage gap was closed locally. The smoke
  harness now enumerates every S-iOS-1..19 and S-And-1..19 row; added fixtures
  cover media, corrupt ciphertext, tampered signature, unknown envelope, dissolve,
  long-text, and forbidden-field canary cases. Non-dry-run app-installed smoke
  passed on iPhone 17
  (`5BA69F1C-B112-47BE-B1FF-8C1003728C8F`), iPhone 17 Pro
  (`38FECA55-03C1-4907-BD9D-8E64BF8E3469`), and Android `emulator-5554`.
  Companion verification passed: `flutter test`, relay `go test ./...`, iOS
  Runner `xcodebuild test`, baseline with `FLUTTER_DEVICE_ID` targeting iPhone
  17, `1to1`, `groups`, `runtime-telemetry`, `completeness-check`, and
  `scripts/check_push_release_gate.sh`.
- `2026-04-24`: Session `9` accepted after creating the missing doc-scoped plan
  and executing the closure cleanup. The relay no longer models or forwards
  `pushTitle` / `pushBody` request fields for group message pushes, the
  rollout-only legacy plaintext push metric was retired, Dart group inbox helper
  signatures no longer expose plaintext preview parameters, and background push
  fallback ignores retired plaintext preview keys. Documentation now records the
  final ciphertext-only simulator matrix and maintained gate commands.
  Verification passed: focused cleanup Flutter suites, relay `go test ./...`,
  `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh baseline`,
  `./scripts/run_test_gates.sh 1to1`, `groups`, `runtime-telemetry`,
  `completeness-check`, `scripts/check_push_release_gate.sh`, and final full
  `flutter test`.

## final program verdict

- Status:
  `accepted`
- Last updated:
  `2026-04-24`
- Why:
  sessions `1` through `9` are accepted. The final app-installed simulator
  smoke matrix covers S-iOS-1..19 and S-And-1..19 on the configured iOS and
  Android targets, companion gates passed, and Session `9` retired the legacy
  plaintext preview plumbing while preserving ciphertext-only push behavior.
