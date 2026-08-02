# 148 - Minimum Parity Encrypted Push Spool for Notification Tap Fast-Path  (Feature Improvement)

Status: BLOCKED on Phase-0 evidence gate
Spec: derived from `Test-Flight-Improv/nse-app-group-push-spool-persistence-analysis-and-design.md`
Scope: evidence-gated umbrella only. Do not implement until Phase-0 proves a residual compact 1:1 text notification-tap delay after plans 145, 146, and 147.

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-23 | Evidence Collector | graphify-arch query, `nse-app-group-push-spool-persistence-analysis-and-design.md`, iOS NSE files, Android background handler, notification route/open tests, reliability-sim list | Current repo has iOS preview decrypt/app-group sidecars and Android generic fallback; no `PushSpool` writer/reader exists | Build TDD matrix |
| 2026-06-23 | Planner | 146/147 plan shape, notification/open gates, `scripts/run_test_gates.sh reliability-sim 1to1 --list` | Plan needs shared Dart spool contract, iOS writer, Android writer, targeted notification-open replay, and a simulator row | Emit plan |
| 2026-06-23 | Reviewer | source anchors, existing tests, gate inventory | Host-only closure is insufficient; iOS and Android writers plus OS-boundary proof are required if the work proceeds | Add closure bar and scope guard |
| 2026-06-23 | External Review | Plan 148 draft, gate scripts, receipt minting paths | Feedback is meaningful: plan was premature, had invalid empty gate cells, missed delivery-receipt double-mint, and bundled too much scope | Demote and split |
| 2026-06-23 | Arbiter | revised draft | Plan 148 is not execution-ready. Keep it as an evidence-gated umbrella; execute only staged child plans 148a-148e if Phase-0 passes | Wait for Phase-0 readout |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| | Phase-0 readout | | 145 TestFlight + 146/147 landed + residual-delay threshold met | BLOCKED | Fill Phase-0 table before any implementation |
| | baseline counts | | `./scripts/run_test_gates.sh 1to1`; `./scripts/run_test_gates.sh reliability-sim 1to1 --list`; RunnerTests count | pending | Record exact baseline before edits |
| | 148a shared schema/repo/privacy | | | not started | child plan required |
| | 148b drain/open/receipt/dedupe | | | not started | child plan required |
| | 148c iOS NSE writer | | | not started | child plan required |
| | 148d Android writer | | | not started | explicit Android design required |
| | 148e reliability-sim parity | | | not started | device/sim plan required |
| | QA (independent) | | | pending | verdict |

## Phase-0 Evidence Gate  (hard stop)

No code session may start until this table is filled with real evidence. If the residual delay threshold is not met, cancel Plan 148 instead of implementing it.

| Gate item | Required evidence | Current state | Decision |
|---|---|---|---|
| 145 shipped to TestFlight | TestFlight build/date plus a telemetry window that includes notification-tap compact 1:1 text opens | not recorded | blocked |
| 146 landed | commit/PR plus green host gates for delivery-receipt deferral | awaiting review / not recorded as landed | blocked |
| 147 landed | commit/PR plus green host gates for bounded decrypt fan-out | awaiting review / not recorded as landed | blocked |
| Residual delay survives | After 145/146/147, compact 1:1 text notification taps still show `p95 tap_to_live_render_ms >= 750ms` or `p50 tap_to_live_render_ms >= 300ms`, sample `n >= 30`, with `drainMs`/`replayMs` attribution showing relay drain/replay accounts for at least half of the residual | not measured | blocked |
| Scope still matches v1 | Delay is on compact 1:1 text messages, not group, media byte availability, voice/image/video download, or Android preview text parity | not measured | blocked |

## Source Of Truth

- Primary design: `Test-Flight-Improv/nse-app-group-push-spool-persistence-analysis-and-design.md`
- Prior notification-open dependency: `Test-Flight-Improv/145-notif-tap-nonblocking-route-and-catching-up-affordance-tdd-plan.md`
- Drain performance dependencies: `Test-Flight-Improv/146-1to1-drain-delivery-receipt-deferral-tdd-plan.md`, `Test-Flight-Improv/147-1to1-inbox-replay-decrypt-fanout-tdd-plan.md`
- Push preview/privacy background: `Test-Flight-Improv/73-on-device-push-decrypt-plan.md`, `Test-Flight-Improv/74-privacy-preserving-notification-previews.md`, `Test-Flight-Improv/142-relay-media-push-payload-too-large-tdd-plan.md`
- Gate definitions: `scripts/run_test_gates.sh`, `scripts/run_reliability_simulations.sh`, `scripts/check_reliability_simulation_discovery.sh`, `scripts/smoke_test_push_decrypt_simulator.sh`
- Current code wins over prose if any cited doc is stale.

## Session Classification

evidence-gated umbrella plan

Execution dependency: do not execute until Phase-0 passes. If it passes, split implementation into child plans 148a through 148e. This file is the contract and acceptance map, not a single monolithic execution session.

---

## Exact Problem Statement

Honesty banner: this is a contingency plan, not approved implementation. It is best-effort, compact-1:1-text-only, contingent on Phase-0 telemetry, and may be cancelled if plans 145, 146, and 147 make notification-tap delay acceptable.

When a user taps a 1:1 message notification, the app can route quickly after plan 145, but the new message may still become visible only after main-app relay inbox drain/replay. The push itself already carries compact encrypted 1:1 envelope fields for small messages (`kem`, `ciphertext`, `nonce`, `sender_id`, `message_id`), but the app currently discards that encrypted data after showing the notification preview/fallback.

iOS already has an NSE that decrypts locally for previews and writes marker sidecars into the app group, but it does not persist the encrypted envelope for main-app ingestion. Android already receives data-only pushes in `firebaseMessagingBackgroundHandler`, but it only shows a privacy-safe fallback/local notification and does not persist the encrypted envelope either.

What would improve if Phase-0 passes:

- On both iOS and Android, a compact encrypted 1:1 `new_message` push is saved to local device storage as an encrypted spool entry.
- On notification tap/open, the main app starts a targeted local spool replay for that sender before or alongside relay drain.
- If the spool entry is valid and decryptable, the message is persisted through the normal 1:1 ingestion pipeline and can render before relay drain finishes.
- The later relay drain remains authoritative for server custody, relay ACK, and final duplicate suppression.

What must stay unchanged:

- Notification previews remain available.
- No plaintext message text, preview body, username, group name, or media bytes are written to the spool.
- No relay `inbox:ack` is sent for push-spool-only data.
- Push-spool replay does not mint delivery receipts; the later relay/inbox path owns sender custody receipt minting.
- The canonical `handleIncomingChatMessage` / `ChatMessageListener` path still owns decrypt, validation, dedupe, persistence, media metadata handling, contact updates, and receipts.
- Group pushes and media-byte availability are out of scope for v1.
- Full Android decrypted-preview parity is out of scope; Android minimum parity is encrypted-envelope persistence plus main-app replay.

## Root Cause And Evidence

- iOS NSE resolves previews at `ios/NotificationService/NotificationService.swift:27` and `ios/NotificationService/NotificationPreviewResolver.swift:107`, then writes only notification content and sidecar markers.
- iOS 1:1 preview decrypt has the required inputs at `ios/NotificationService/NotificationPreviewResolver.swift:166-202`.
- iOS app-group marker stores exist at `ios/NotificationService/NotificationPreviewResolver.swift:420` and `ios/NotificationService/NotificationPreviewResolver.swift:475`, proving app-group file persistence is already used for notification coordination.
- The main app exposes and persists the app-group path through `ios/Runner/AppDelegate.swift:304` and `lib/core/notifications/recent_remote_gate_ios_wiring.dart:16-76`.
- Android background push handling starts at `lib/features/push/application/background_message_handler.dart:99` and shows local notification fallback at `:183`, but there is no spool writer.
- Android decrypt-preview helper exists at `lib/features/push/application/push_decrypt_preview.dart:23`, but production calls it without decrypt callbacks, so minimum parity must not depend on Android preview decrypt.
- 1:1 push route data is parsed from `sender_id`/`from` in `lib/core/notifications/notification_route_target.dart:129-141`.
- The relay copies compact encrypted push data from the encrypted message at `go-relay-server/inbox.go:286-309` and `go-relay-server/inbox.go:536-553`.
- The Dart v2 encrypted envelope can be reconstructed with `MessagePayload.buildEncryptedEnvelope` at `lib/features/conversation/domain/models/message_payload.dart:124-145`. It does not serialize `senderUsername`; compact push does not carry username, so spool replay may use a placeholder and rely on post-decrypt/contact recovery.
- Canonical ingest and duplicate handling live in `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart` and `lib/features/conversation/application/chat_message_listener.dart:403-424`.
- Relay ACK happens only after relay retrieve/stage at `lib/core/services/p2p_service_impl.dart:1508-1565`; push spool does not have relay entry ids and must not touch this boundary.
- Delivery-receipt double-mint is a real unpinned boundary: `deliveryReceiptMintDecision` currently mints for `stagedEntryId` values that are not direct/lan and can mint for `transport: 'push_spool'` when confirmatory direct/LAN receipts are enabled. The later relay duplicate paths can mint again. This is probably wasteful rather than corrupting, but it must be pinned.

Refuted / do-NOT-re-introduce:

- "iOS-only spool is enough" - rejected. This plan is minimum parity: both platforms must write encrypted spool entries if the work proceeds.
- "Save the decrypted preview/plaintext" - rejected. It expands privacy surface unnecessarily and violates the source design.
- "Use push spool to ACK relay entries" - rejected. Push payloads have message ids, not relay inbox entry ids.
- "Mint delivery receipts from push spool" - rejected for v1. Relay/inbox replay remains the custody receipt boundary.
- "Implement Android full preview decrypt now" - rejected for this session. Android writer does not require decrypting in the background.
- "Write directly to the messages table from NSE/background handler" - rejected. Main app replay must own persistence.

## Real Scope

Plan 148 must be split. Each child plan needs its own RED/GREEN evidence and closure note.

- 148a shared Dart schema/repository/privacy:
  - `PushSpoolEntry` v1 schema.
  - filesystem-backed repository with first-wins create, claim/delete, TTL pruning, corrupt quarantine/delete, no backup where platform APIs allow it.
  - privacy canary tests.
- 148b Dart drain, notification-open hook, receipt boundary, relay dedupe:
  - targeted drain by sender/message id.
  - reconstruct encrypted v2 envelope and pass through existing listener/handler.
  - `push_spool` origin does not send relay ACK and does not mint delivery receipts.
  - relay duplicate later dedupes and owns receipt minting.
- 148c iOS NSE writer:
  - native app-group writer under `PushSpool/v1`.
  - compact encrypted 1:1 route data only.
  - first-wins atomic file create/rename.
  - no plaintext.
- 148d Android writer:
  - explicit Android design first.
  - background isolate writer for compact encrypted 1:1 route data.
  - best-effort failure behavior; local fallback notification still displays.
- 148e reliability-sim parity:
  - new OS-boundary write-to-consume proof.
  - discovery registration plus repo-native simulator dry-run.
  - iOS and Android where devices are available.

Out of scope:

- Group push spool.
- Raw media/image/video/voice file spool.
- Full Android decrypted-preview parity.
- Native Android `FirebaseMessagingService` rewrite.
- Relay payload changes.
- SQLCipher migration.
- Relay ACK from push data.
- Reworking 146/147 drain performance changes.

## Closure Bar

Good enough after all child plans means:

- Phase-0 evidence is filled and says proceed.
- A compact encrypted 1:1 push writes one spool entry on iOS.
- A compact encrypted 1:1 push writes one spool entry on Android.
- The spool file contains only encrypted envelope/routing fields and no plaintext canary fields.
- A notification-open conversation path starts targeted spool replay and does not wait for full relay drain.
- Spool replay can commit a message through the normal 1:1 handler before relay drain finishes.
- Push-spool replay never sends relay ACK and never mints delivery receipts.
- Later relay replay dedupes and does not create a second card; relay/inbox owns final custody receipt.
- Expired, malformed, unsupported, group, visible fallback, and missing-ciphertext pushes do not create usable spool entries.
- Simulator closure includes a new PROD-CRITICAL 1:1 reliability-sim row that proves encrypted push spool write+consume on notification-open, plus existing iOS tap and push-decrypt smoke gates.

Minimum parity checklist:

| Requirement | Planned proof | Status |
|---|---|---|
| iOS saves encrypted push envelope locally | TC-03, TC-04, TC-14 | planned (post-evidence-gate) |
| Android saves encrypted push envelope locally | TC-05, TC-06, TC-14 | planned (post-evidence-gate) |
| Notification tap can load from local encrypted spool before relay drain | TC-07, TC-11, TC-14 | planned (post-evidence-gate) |
| No plaintext spool | TC-01, TC-02, TC-03, TC-05, TC-13 | planned (post-evidence-gate) |
| Relay drain/ACK remains authoritative | TC-09, TC-10, TC-12 | planned (post-evidence-gate) |
| Full Android decrypted preview parity | accepted out of scope | intentionally deferred |

## Files To Inspect Next

Production:

- `ios/NotificationService/NotificationService.swift`
- `ios/NotificationService/NotificationPreviewResolver.swift`
- `lib/features/push/application/background_message_handler.dart`
- `lib/features/push/application/push_decrypt_preview.dart`
- `lib/features/push/application/prepare_notification_open_use_case.dart`
- `lib/core/notifications/notification_route_target.dart`
- `lib/core/notifications/recent_remote_gate_ios_wiring.dart`
- `lib/features/conversation/application/chat_message_listener.dart`
- `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
- `lib/features/conversation/application/recovered_inbox_chat_disposition.dart`
- `lib/features/conversation/application/send_delivery_receipt_use_case.dart`
- `lib/features/conversation/domain/models/message_payload.dart`
- `lib/main.dart`

New production files expected if Phase-0 passes:

- `lib/features/push/application/push_spool_entry.dart`
- `lib/features/push/application/push_spool_repository.dart`
- `lib/features/push/application/drain_push_spool_use_case.dart`
- `lib/features/push/application/background_push_spool_writer.dart`
- optional: `ios/NotificationService/PushSpoolStore.swift`

Tests:

- `ios/RunnerTests/NotificationPreviewResolverTests.swift` or new `PushSpoolStoreTests.swift`
- `test/features/push/application/push_spool_entry_test.dart`
- `test/features/push/application/push_spool_repository_test.dart`
- `test/features/push/application/drain_push_spool_use_case_test.dart`
- `test/features/push/application/background_message_handler_test.dart`
- `test/features/push/application/prepare_notification_open_use_case_test.dart`
- `test/features/conversation/application/send_delivery_receipt_use_case_test.dart`
- `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
- `test/core/inbox/inbox_round_trip_test.dart`
- `integration_test/scripts/run_push_spool_notification_open.dart`
- `scripts/check_reliability_simulation_discovery.sh`
- `scripts/run_reliability_simulations.sh`

## Existing Tests And Gate Inventory

- `ios/RunnerTests/NotificationPreviewResolverTests.swift` covers iOS preview decrypt, muted group short-circuit, recent remote marker parity, and `AppGroupPushDedupeStore` first-wins. Missing: encrypted spool writer.
- `ios/RunnerTests/NotificationServiceConfigurationTests.swift` covers entitlements. Missing: spool directory behavior.
- `test/features/push/application/push_decrypt_preview_test.dart` covers plaintext-free push route fixtures and injected Android decrypt preview helper. Missing: spool extraction/writer.
- `test/features/push/application/background_message_handler_test.dart` covers Android local fallback, injected resolver, duplicate fallback suppression, and DB-backed group eligibility. Missing: encrypted spool writer and not currently in `ONE_TO_ONE_TESTS`.
- `test/core/notifications/recent_remote_notification_gate_test.dart` covers app-group sidecar consumption. Missing: app-group push spool reader.
- `test/core/notifications/recent_remote_gate_ios_wiring_test.dart` covers persisted app-group path for sidecars. Missing: persisted app-group path use for spool.
- `test/features/conversation/application/send_delivery_receipt_use_case_test.dart` is in `ONE_TO_ONE_TESTS`. Missing: `push:` / `push_spool` skip boundary.
- `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart` covers canonical 1:1 decrypt/dedupe/persist/receipt behavior. Missing: push-spool-origin receipt/transport contract.
- `test/features/conversation/application/recovered_inbox_chat_disposition_test.dart` covers replay outcome mapping. Missing: push spool terminal/retry lifecycle.
- `test/core/inbox/inbox_round_trip_test.dart` is in `ONE_TO_ONE_TESTS` and covers relay inbox stage/replay/dedupe. Missing: push-spool-before-relay dedupe.
- `integration_test/app_group_path_simulator_test.dart` covers app-group path and sidecar round trip in one process. Missing: push spool directory round trip.
- `scripts/run_ios_notification_tap_ui_smoke.sh` and `scripts/smoke_test_push_decrypt_simulator.sh` cover existing notification tap/preview smoke. Missing: encrypted spool write+consume assertion.
- `scripts/run_test_gates.sh` has `ONE_TO_ONE_TESTS` but no `PUSH_TESTS` family. Current pre-148 `ONE_TO_ONE_TESTS` file count is 47. New Dart spool tests must be added there explicitly; do not reference a non-existent push gate.
- `./scripts/run_test_gates.sh reliability-sim 1to1 --list` currently reports 22 dry-run commands. TC-14 must make that 23 and must also be discoverable through `scripts/check_reliability_simulation_discovery.sh`.

---

## RED Test Catalog  (add BEFORE production code - INV-RED-FIRST)

1. `push_spool_entry_test.dart::builds a v1 1:1 encrypted spool entry from push route data without plaintext`
   - Tier: unit/application
   - Shape/setup: feed `one_to_one_text` fixture `routeData`; expect `PushSpoolEntry` has schemaVersion 1, type `new_message`, sender id, message id, `kem`, `ciphertext`, `nonce`, `receivedAtMs`, `expiresAtMs`, and no fields named `text`, `body`, `title`, `senderUsername`, `groupName`, or `media`.
   - RED on HEAD because: `PushSpoolEntry` does not exist.
   - GREEN after fix asserts: compact encrypted route data maps to a privacy-safe entry.
   - Mutation that re-reds: include fixture plaintext text or title/body in serialized entry.

2. `push_spool_repository_test.dart::writes claims reads deletes prunes and first-wins by stable id`
   - Tier: unit/application
   - Shape/setup: temp dir repository; write entry twice; assert one stored entry; claim moves/marks it once; delete removes it; expired entries prune; corrupt JSON is quarantined/deleted without throw.
   - RED on HEAD because: repository does not exist.
   - GREEN after fix asserts: durable local lifecycle works without SQLCipher.
   - Mutation that re-reds: remove first-wins/claim logic or ignore TTL.

3. `PushSpoolStoreTests.swift::iOS app-group store writes encrypted 1:1 spool and excludes plaintext`
   - Tier: native unit
   - Shape/setup: temp directory `AppGroupPushSpoolStore(directory:)`; pass `one_to_one_text` route data; assert exactly one JSON file under `PushSpool/v1`; assert it contains `kem/ciphertext/nonce/sender_id/message_id` and not plaintext canary strings.
   - RED on HEAD because: iOS spool store does not exist.
   - GREEN after fix asserts: iOS writer is filesystem-backed, first-wins, encrypted-only.
   - Mutation that re-reds: write preview body or raw plaintext into the file.

4. `NotificationPreviewResolverTests.swift::NSE writes 1:1 spool only after decryptable preview and never for group or fallback`
   - Tier: native unit
   - Shape/setup: inject `MemoryPushSpoolStore` into resolver or service path; one valid 1:1 fixture records one entry; missing decrypt input, corrupt ciphertext, unsupported type, group fixture, and muted/suppressed group record none.
   - RED on HEAD because: resolver/service has no spool writer injection.
   - GREEN after fix asserts: v1 scope is 1:1 only and writer does not affect preview rendering.
   - Mutation that re-reds: write group entries or write before validating required encrypted fields.

5. `background_message_handler_test.dart::Android data-only encrypted 1:1 push writes encrypted spool before showing fallback`
   - Tier: unit/application
   - Shape/setup: inject `debugSetBackgroundPushSpoolWriter`; send `RemoteMessage(data: one_to_one_text.routeData)`; assert writer called once with encrypted entry and the local notification path still shows fallback.
   - RED on HEAD because: no background spool writer injection/call exists.
   - GREEN after fix asserts: Android minimum parity writer exists without needing background decrypt.
   - Mutation that re-reds: only write spool after decrypt callback succeeds, or skip Android writer.

6. `background_message_handler_test.dart::Android missing ciphertext visible fallback and write failure do not break notification fallback`
   - Tier: unit/application
   - Shape/setup: missing `kem/ciphertext/nonce` writes nothing; `RemoteMessage.notification != null` with generic visible fallback writes nothing; writer throwing emits `PUSH_SPOOL_WRITE_ERROR` and fallback notification still shows.
   - RED on HEAD because: no writer/error path exists.
   - GREEN after fix asserts: spool is best-effort and privacy-safe.
   - Mutation that re-reds: let writer errors abort local notification display.

7. `drain_push_spool_use_case_test.dart::targeted drain replays entry through listener and deletes committed terminal outcome`
   - Tier: unit/application
   - Shape/setup: repository seeded with a valid 1:1 entry for sender A; fake local peer id; fake listener returns stored; run targeted drain for sender A; assert it reconstructs a `ChatMessage` whose content is a v2 encrypted envelope and deletes the entry. Because `buildEncryptedEnvelope` does not carry `senderUsername`, assert placeholder username behavior is accepted and post-decrypt recovery owns contact naming.
   - RED on HEAD because: use case does not exist.
   - GREEN after fix asserts: replay uses existing message path shape, not direct DB write.
   - Mutation that re-reds: bypass listener and write directly to messages.

8. `drain_push_spool_use_case_test.dart::retryable outcomes stay short-lived and terminal duplicate/rejected outcomes delete`
   - Tier: unit/application
   - Shape/setup: fake listener returns `decryptionDeferred`, `missingMlKemSecret`, `duplicate`, `blockedSender`, and `decryptionFailed`; assert retryable entries remain until TTL, duplicate/rejected delete, cryptographic failure quarantines or deletes per documented policy.
   - RED on HEAD because: use case does not exist.
   - GREEN after fix asserts: lifecycle mirrors recovered-inbox disposition without infinite loops.
   - Mutation that re-reds: delete retryable `decryptionDeferred` immediately.

9. `drain_push_spool_use_case_test.dart::push-spool replay never calls relay ACK and uses push_spool origin`
   - Tier: unit/application
   - Shape/setup: provide fake ack spy that fails if called; run a committed replay; assert `stagedEntryId` is `push:<stable-id>` or transport is `push_spool`, and no relay ACK callback fires.
   - RED on HEAD because: use case/origin contract does not exist.
   - GREEN after fix asserts: push spool remains an accelerator, not relay custody.
   - Mutation that re-reds: call `callP2PInboxAck` or route through `InboxStagingRepository` with a fake relay id.

10. `send_delivery_receipt_use_case_test.dart::push-spool origin skips delivery receipt mint so relay duplicate owns receipt`
   - Tier: unit/application
   - Shape/setup: call `deliveryReceiptMintDecision` with `stagedEntryId: 'push:msg-1'` and/or `transport: 'push_spool'`, including the confirmatory direct/LAN flag enabled; expect skip reason `pushSpool`. Then verify an ordinary relay/inbox replay for the same message still mints normally.
   - RED on HEAD because: current decision mints for non-direct/non-LAN staged ids and can mint non-inbox transport under the confirmatory flag.
   - GREEN after fix asserts: push spool does not double-mint; relay/inbox remains authoritative for sender custody receipt.
   - Mutation that re-reds: remove the `push:` / `push_spool` skip branch and watch push spool mint again.

11. `prepare_notification_open_use_case_test.dart::conversation open starts targeted push-spool drain without waiting for relay drain`
   - Tier: unit/application
   - Shape/setup: conversation route; `drainPushSpoolForTarget` records target and returns a gated future; `drainOfflineInbox` is never-completing; assert prepare/open returns promptly or route callback is reached, and both spool drain and relay drain are started.
   - RED on HEAD because: no spool drain hook exists.
   - GREEN after fix asserts: notification tap starts local spool replay and preserves non-blocking route behavior.
   - Mutation that re-reds: await full relay drain before starting/route.

12. `inbox_round_trip_test.dart::relay replay after push-spool commit dedupes and does not duplicate`
   - Tier: integration/host
   - Shape/setup: commit a message through spool replay, then stage the same encrypted envelope through relay inbox replay; assert one message row/card, relay replay returns duplicate/rejected terminal disposition, and relay/inbox owns any delivery-receipt minting.
   - RED on HEAD because: spool path does not exist.
   - GREEN after fix asserts: source-of-truth relay drain remains safe after spool acceleration.
   - Mutation that re-reds: use a new/reminted message id during spool reconstruction.

13. `push_spool_privacy_canary_test.dart::fixtures and persisted spool never contain forbidden plaintext fields`
   - Tier: unit/application + native mirror
   - Shape/setup: serialize representative iOS and Android spool entries from `one_to_one_text`, `one_to_one_long_text`, and `forbidden_field_canary_text`; assert forbidden keys/values are absent.
   - RED on HEAD because: spool serialization does not exist.
   - GREEN after fix asserts: privacy contract is mechanically pinned.
   - Mutation that re-reds: add `senderUsername`, preview title/body, text, or media bytes to spool JSON.

14. `integration_test/scripts/run_push_spool_notification_open.dart::push spool renders before blocked relay drain on iOS and Android`
   - Tier: reliability-sim/device
   - PROD-CRITICAL: only end-to-end OS-boundary write-to-consume proof.
   - Shape/setup: install app, inject compact encrypted 1:1 push fixture, block or delay relay drain in harness, tap/open conversation, assert local spool entry was consumed and message appears; run for iOS simulator and Android emulator when available.
   - RED on HEAD because: no spool writer/reader and no simulator row.
   - GREEN after fix asserts: real notification/open journey proves minimum parity.
   - Mutation that re-reds: disable either platform writer or disable targeted spool drain.

## Test Coverage Matrix  (ZERO empty cells)

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-01 entry schema | privacy/schema | unit | `push_spool_entry_test.dart::builds a v1 1:1 encrypted spool entry...` | class absent | serialize plaintext | `flutter test test/features/push/application/push_spool_entry_test.dart` | add file to `ONE_TO_ONE_TESTS` (47 -> 48) |
| TC-02 repository lifecycle | durability/TTL | unit | `push_spool_repository_test.dart::writes claims reads deletes prunes...` | repository absent | remove claim/TTL | `flutter test test/features/push/application/push_spool_repository_test.dart` | add file to `ONE_TO_ONE_TESTS` (48 -> 49) |
| TC-03 iOS store | iOS writer/privacy | native unit | `PushSpoolStoreTests.swift::iOS app-group store writes...` | store absent | write plaintext | `xcodebuild test ... RunnerTests` | RunnerTests target; add new Swift test file or suite |
| TC-04 iOS NSE integration | scope/privacy | native unit | `NotificationPreviewResolverTests.swift::NSE writes 1:1 spool only...` | injection absent | write group/fallback | `xcodebuild test ... RunnerTests` | existing RunnerTests target |
| TC-05 Android writer | parity/background | unit | `background_message_handler_test.dart::Android data-only encrypted...` | writer absent | skip Android writer | `flutter test test/features/push/application/background_message_handler_test.dart` | add existing file to `ONE_TO_ONE_TESTS` (49 -> 50) |
| TC-06 Android best effort | privacy/fallback | unit | `background_message_handler_test.dart::Android missing ciphertext...` | writer absent | throw aborts fallback | same as TC-05 | same file already registered by TC-05 |
| TC-07 targeted replay commit | replay/ingest | unit | `drain_push_spool_use_case_test.dart::targeted drain replays...` | use case absent | direct DB write | `flutter test test/features/push/application/drain_push_spool_use_case_test.dart` | add file to `ONE_TO_ONE_TESTS` (50 -> 51) |
| TC-08 retry lifecycle | replay/disposition | unit | `drain_push_spool_use_case_test.dart::retryable outcomes...` | use case absent | delete retryable | same as TC-07 | same file already registered by TC-07 |
| TC-09 no relay ACK | custody boundary | unit | `drain_push_spool_use_case_test.dart::push-spool replay never calls relay ACK...` | use case absent | call relay ACK | same as TC-07 | same file already registered by TC-07 |
| TC-10 no receipt double-mint | custody receipt boundary | unit | `send_delivery_receipt_use_case_test.dart::push-spool origin skips delivery receipt mint...` | current decision mints | remove skip branch | `flutter test test/features/conversation/application/send_delivery_receipt_use_case_test.dart` | existing `ONE_TO_ONE_TESTS` entry |
| TC-11 notification open hook | route/nonblocking | unit | `prepare_notification_open_use_case_test.dart::conversation open starts targeted push-spool...` | hook absent | await relay drain | `flutter test test/features/push/application/prepare_notification_open_use_case_test.dart` | existing `ONE_TO_ONE_TESTS` entry |
| TC-12 relay dedupe after spool | no duplicate | integration/host | `inbox_round_trip_test.dart::relay replay after push-spool commit dedupes...` | spool absent | remint id | `flutter test test/core/inbox/inbox_round_trip_test.dart` | existing `ONE_TO_ONE_TESTS` entry |
| TC-13 privacy canary | privacy | unit/native | `push_spool_privacy_canary_test.dart::fixtures and persisted spool...` | serialization absent | include forbidden fields | `flutter test test/features/push/application/push_spool_privacy_canary_test.dart` plus RunnerTests mirror | add Dart file to `ONE_TO_ONE_TESTS` (51 -> 52); native mirror in RunnerTests |
| TC-14 simulator parity | e2e/minimum parity | reliability-sim | `integration_test/scripts/run_push_spool_notification_open.dart` | row absent | disable either platform writer | `./scripts/run_test_gates.sh reliability-sim 1to1 --only integration_test/scripts/run_push_spool_notification_open.dart` | add script, add `classify_path()` case under 1to1, add run row; reliability-sim list 22 -> 23 |

## Expected Count Deltas And Preservation Sentinels

- `ONE_TO_ONE_TESTS` file registration baseline: 47 files before 148. Expected file-count delta after registering new Dart tests: 52 files (+5: entry, repository, background handler, drain, privacy canary).
- Last recorded full 1:1 preservation from plan 145: `1113/1113`. Before 148 implementation, rerun `./scripts/run_test_gates.sh 1to1` and record the current exact total in Execution Progress. Final expected total is baseline test count plus the exact new TC count, with 0 regressions.
- Reliability-sim `1to1 --list` baseline: 22 commands. Expected after TC-14 registration: 23 commands, with existing sentinels 1, 21, and 22 still present and green.
- RunnerTests baseline count must be recorded before 148c. Expected delta: TC-03/TC-04 native tests and TC-13 native privacy mirror, 0 existing RunnerTests regressions.
- Preservation sentinels that must remain green: `prepare_notification_open_use_case_test.dart`, `send_delivery_receipt_use_case_test.dart`, `inbox_round_trip_test.dart`, `push_decrypt_preview_test.dart`, recent remote gate tests, `run_ios_notification_tap_ui_smoke.sh`, and `smoke_test_push_decrypt_simulator.sh`.

## Invariants Locked By Tests

- INV-1: iOS and Android both write encrypted 1:1 spool entries for compact data-only/message-extension pushes.
- INV-2: persisted spool never contains plaintext text, preview title/body, usernames, group names, or media bytes.
- INV-3: push-spool replay uses the existing ingest path and never writes directly to the message DB.
- INV-4: push-spool replay never sends relay ACK.
- INV-5: push-spool replay never mints delivery receipts; relay/inbox replay owns custody receipt minting.
- INV-6: terminal replay outcomes remove/quarantine entries; retryable outcomes do not disappear prematurely.
- INV-7: relay replay after spool commit is duplicate-safe.
- INV-8: notification route/open remains non-blocking relative to full relay drain.
- INV-9: group/media/full Android preview parity remain out of v1 unless a separate plan accepts them.

## Step-By-Step Implementation Plan

0. **Phase-0 readout or stop.** Fill the Phase-0 table. Stop and cancel if 145/146/147 remove the residual delay or if telemetry points to group/media/download delay instead of compact 1:1 text drain/replay delay.
1. **Baseline and dependency check.** Capture `git status --short`. Run and record baseline counts for `./scripts/run_test_gates.sh 1to1`, RunnerTests, and `./scripts/run_test_gates.sh reliability-sim 1to1 --list`.
2. **Create child plan 148a.** Cover TC-01, TC-02, TC-13 Dart privacy serialization. Add exact gate registration to `ONE_TO_ONE_TESTS`. Do not touch native writers or notification-open wiring.
3. **Execute 148a RED/GREEN.** Add schema/repository RED tests first; implement `PushSpoolEntry`, `PushSpoolRepository`, TTL constants, deterministic stable id, file claim/delete/prune, and privacy-safe JSON. No DB migration.
4. **Create child plan 148b.** Cover TC-07 through TC-12. Include receipt skip branch in `deliveryReceiptMintDecision` for `push:` staged ids and `transport: 'push_spool'`.
5. **Execute 148b RED/GREEN.** Add `DrainPushSpoolUseCase`, targeted drain hook, notification-open scheduling, receipt skip, relay dedupe proof. Do not call relay ACK, do not mint delivery receipt from push spool, and do not write directly to DB.
6. **Create child plan 148c.** Cover TC-03, TC-04, and the native side of TC-13. Reuse app-group directory patterns from `AppGroupPushDedupeStore` and `RecentRemoteShownMarkerStore`.
7. **Execute 148c RED/GREEN.** Add native app-group spool writer, injection seam, first-wins atomic create/rename, no-plaintext canaries, and pruning. Notification preview behavior must remain unchanged.
8. **Create child plan 148d.** First write explicit Android background writer design because the design doc called this out as incomplete. Cover TC-05 and TC-06.
9. **Execute 148d RED/GREEN.** Add `BackgroundPushSpoolWriter` and background handler seam. Writer failure logs `PUSH_SPOOL_WRITE_ERROR` and never aborts fallback notification display.
10. **Create child plan 148e.** Cover TC-14 only. Register the new script correctly in discovery and reliability-sim.
11. **Execute 148e RED/GREEN.** Add `integration_test/scripts/run_push_spool_notification_open.dart`, add a `classify_path()` case under 1to1 in `scripts/check_reliability_simulation_discovery.sh`, and add the run row in `scripts/run_reliability_simulations.sh`. Verify list count 22 -> 23.
12. **Final preservation pass.** Run direct tests, RunnerTests, `./scripts/run_test_gates.sh 1to1`, reliability-sim discovery, the new simulator row, existing simulator sentinels, `flutter analyze`, and `git diff --check`.

## Risks And Edge Cases

- **Privacy regression:** storing preview/plaintext would create a new local data surface. Pinned by TC-01/03/05/13.
- **Route blocking regression:** awaiting decrypt/spool replay too early could reintroduce notification-open delay. Pinned by TC-11.
- **Duplicate cards:** relay drain later can replay the same message. Pinned by TC-12.
- **Double delivery receipt mint:** push spool plus relay duplicate can mint twice unless push spool skips. Pinned by TC-10.
- **False relay custody:** push spool lacks relay entry ids. Pinned by TC-09.
- **Android background path instability:** background isolate path/provider can fail on some devices. Writer is best-effort and fallback notification must still show.
- **First launch iOS app-group path race:** main app may not have persisted the app-group path yet. Reader must fail open and retry later; iOS writer still writes to app group.
- **Clock/TTL drift:** stale entries must be pruned, but short transient decrypt failures should not be lost immediately.
- **Media expectation mismatch:** v1 only accelerates compact encrypted message envelope; it does not make media bytes available.

## Device/Relay Proof Profile

Host tests prove schema, privacy, replay lifecycle, dedupe, receipt boundary, and route scheduling. They are not sufficient for closure because this work touches notification opening and platform background delivery.

Simulator/device closure must include:

- app-group path availability on iOS;
- iOS notification tap/open behavior;
- Android background push injection path;
- a new PROD-CRITICAL write+consume spool proof that blocks relay drain and still renders the spooled message.

## Acceptance Gates  (literal - repo-native)

```bash
# 0) Phase-0 / baseline snapshot
git status --short
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh reliability-sim 1to1 --list

# 1) RED/GREEN direct Dart tests
flutter test test/features/push/application/push_spool_entry_test.dart
flutter test test/features/push/application/push_spool_repository_test.dart
flutter test test/features/push/application/drain_push_spool_use_case_test.dart
flutter test test/features/push/application/background_message_handler_test.dart
flutter test test/features/push/application/prepare_notification_open_use_case_test.dart
flutter test test/features/conversation/application/send_delivery_receipt_use_case_test.dart
flutter test test/core/inbox/inbox_round_trip_test.dart
flutter test test/features/push/application/push_spool_privacy_canary_test.dart

# 2) Existing privacy / route sentinels
flutter test test/features/push/application/push_decrypt_preview_test.dart
flutter test test/core/notifications/recent_remote_notification_gate_test.dart
flutter test test/core/notifications/recent_remote_gate_ios_wiring_test.dart
flutter test test/integration/notification_tap_smoke_test.dart

# 3) Native iOS tests (destination may vary by installed simulator)
cd ios && xcodebuild test \
  -workspace Runner.xcworkspace \
  -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:RunnerTests/NotificationPreviewResolverTests
cd -

# 4) Named host gate
./scripts/run_test_gates.sh 1to1

# 5) Reliability simulator discovery and list must include the new row
./scripts/check_reliability_simulation_discovery.sh --records-tsv | rg 'run_push_spool_notification_open|1to1'
./scripts/run_test_gates.sh reliability-sim 1to1 --list

# 6) New minimum-parity simulator row
./scripts/run_test_gates.sh reliability-sim 1to1 --only integration_test/scripts/run_push_spool_notification_open.dart

# 7) Existing notification/push simulator sentinels
./scripts/run_test_gates.sh reliability-sim 1to1 --only 1
./scripts/run_test_gates.sh reliability-sim 1to1 --only 21
./scripts/run_test_gates.sh reliability-sim 1to1 --only 22

# 8) Hygiene
flutter analyze
git diff --check
```

If `iPhone 17` is unavailable, use the repo's simulator resolver/helper or the currently booted iPhone simulator. Record the actual destination.

## Known-Failure Interpretation

- Expected RED before implementation: TC-01 through TC-14 fail because the schema, repository, writers, drain use case, receipt skip, hook, and simulator row do not exist.
- Green-on-HEAD locks: existing push preview privacy tests, recent remote sidecar tests, notification tap smoke tests, recovered inbox disposition tests, delivery receipt tests, and relay inbox round-trip tests must stay green.
- Environment blocker: simulator gates may be blocked by missing booted iOS/Android devices. That is an external closure blocker, not a reason to mark the plan fully closed.
- Scope drift blocker: any implementation that writes plaintext, adds group spool, ACKs relay from push data, mints delivery receipts from push spool, or rewrites Android notification services belongs in a separate plan.
- Pre-existing dirty worktree is expected; do not revert unrelated files.

## Done Criteria

- [ ] Phase-0 table completed and explicitly says proceed.
- [ ] Child plans 148a through 148e exist and each closes independently.
- [ ] Baseline counts recorded before edits: `ONE_TO_ONE_TESTS`, full 1:1 test count, RunnerTests count, reliability-sim list count.
- [ ] TC-01..TC-14 added before production changes and RED for expected reason.
- [ ] iOS writes encrypted 1:1 spool entries and never plaintext.
- [ ] Android writes encrypted 1:1 spool entries and never plaintext.
- [ ] Shared Dart replay commits through existing handler/listener only.
- [ ] Push-spool replay never calls relay ACK.
- [ ] Push-spool replay never mints delivery receipts; relay/inbox still mints normally.
- [ ] Notification-open starts targeted spool replay without blocking full relay drain.
- [ ] Relay replay after spool commit dedupes; no duplicate card.
- [ ] New PROD-CRITICAL reliability-sim row proves write+consume before blocked relay drain.
- [ ] Existing push preview, notification tap, sidecar, delivery receipt, and 1:1 gates stay green.
- [ ] No DB migration.
- [ ] `flutter analyze` and `git diff --check` clean.

Coverage ledger:

| User requirement | Done condition |
|---|---|
| iOS saves encrypted envelope locally | TC-03/04 + TC-14 green |
| Android saves encrypted envelope locally | TC-05/06 + TC-14 green |
| Notification tap loads faster from local spool | Phase-0 threshold + TC-11/14 green |
| No plaintext/privacy regression | TC-01/03/05/13 green |
| Relay drain remains authoritative | TC-09/10/12 green |

## Scope Guard  (hard "Do not")

- Do not implement before Phase-0 evidence says proceed.
- Do not store plaintext, preview body, usernames, group names, or media bytes.
- Do not implement group spool in this plan.
- Do not implement media-byte spool in this plan.
- Do not call relay ACK from push-spool replay.
- Do not mint delivery receipts from push-spool replay.
- Do not write messages directly from NSE or Android background handler.
- Do not rewrite Android to native `FirebaseMessagingService` for this plan.
- Do not require Android decrypt-preview parity for this plan.
- Do not weaken existing push privacy fixtures.
- Do not make conversation notification route wait for full relay drain again.

## Accepted Differences / Intentionally Out Of Scope

- Android may still show a generic fallback notification if production decrypt-preview callbacks are not wired. Minimum parity is encrypted-envelope persistence plus main-app replay.
- iOS writer is native NSE/app-group; Android writer can be Dart background isolate/app-private storage. Functional parity matters more than identical implementation.
- Group messages remain relay-drain-only for v1.
- Media bytes remain fetched/downloaded through existing media paths.
- Push spool is best-effort; relay drain remains the durable delivery authority.

## Dependency Impact

- Depends on plan 145 being shipped to TestFlight and measured, not merely merged.
- Depends on 146 and 147 being landed and measured before deciding whether 148 has value.
- If this lands, future Android full-preview parity can reuse the same spool schema and privacy tests.
- If relay push payload shape changes, TC-01/05 and fixture canaries must be updated before implementation continues.

## Reviewer Findings

Sufficiency review: the original artifact was valuable but not sufficient for execution. The feedback is accepted as meaningful:

- The old `execution-ready` label contradicted the source design's measurement gate.
- The old matrix used invalid or empty gate language and referenced a non-existent push gate family.
- The old plan did not pin the push-spool delivery-receipt double-mint boundary.
- The old scope bundled shared Dart, native iOS, Android background writing, app wiring, and simulator work into one oversized implementation.
- The old simulator registration path was incomplete because it did not require `check_reliability_simulation_discovery.sh` classification.

Document fixes made here:

- Demoted to BLOCKED on Phase-0 evidence gate.
- Added numeric residual-delay threshold and readout table.
- Split execution into 148a through 148e.
- Added TC-10 for delivery-receipt skip.
- Filled every matrix cell with concrete repo-native gate registration.
- Replaced external Codex wrapper simulator commands with `./scripts/run_test_gates.sh reliability-sim 1to1 --only ...`.
- Marked TC-14 PROD-CRITICAL and added discovery registration.
- Added expected count deltas and preservation sentinels.
- Relabeled parity checklist items as planned post-evidence-gate.

## Arbiter Decision

Structural status after this revision: corrected as a plan artifact, still blocked for execution.

Remaining blocker:

- Phase-0 evidence is absent. Do not implement until 145 ships, 146 and 147 land, and telemetry proves the named residual-delay threshold on compact 1:1 text taps.

If Phase-0 passes:

- Execute only staged child plans 148a through 148e.
- Use a fresh implementation session and reviewer pass for each child plan.
- Stop after any child if telemetry or tests show the value no longer justifies the remaining scope.

## Final Execution Verdict

Verdict: blocked on Phase-0 evidence gate.
Files changed: plan document only.
Tests run: reliability-sim 1to1 dry-run list during review; no implementation tests should be run for closure yet.
Blocking: 145 TestFlight telemetry, 146 landed, 147 landed, residual-delay readout.
QA verdict: not applicable until execution is authorized.

---

## CLOSED — superseded by plan 327 (user decision, 2026-08-02)

**Status: CLOSED. Do not execute. Never executed — it remained blocked on its own Phase-0 evidence gate above, so no work is discarded by this closure.**

Plan 148 wanted to spool a **richer** push payload so a notification tap renders instantly. Plan 327 (content-free push) shrinks the push payload to stop leaking routing metadata and display names to APNs/FCM. **The two are mutually exclusive** — more payload means faster taps and more provider-visible metadata; less payload means better privacy and a short fetch after the tap.

The user chose **privacy** on 2026-08-02. 148 is closed in favour of 327.

Reopening 148 would silently undo 327's Stage A and Stage B, so it must not be revived without explicitly reversing that decision. If the tap-latency concern returns, raise it against 327 rather than restoring this plan — 327's Stage C (NSE fetch) is the shape that could serve both goals, and it is tracked there.
