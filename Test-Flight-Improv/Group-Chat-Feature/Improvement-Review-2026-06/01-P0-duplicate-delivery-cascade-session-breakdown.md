Status: reusable-breakdown

# 01-P0 Duplicate Delivery Cascade Session Breakdown

## Recommended Plan Count

Create 8 doc-scoped session plans.

## Decomposition Artifact

- Artifact path: `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade-session-breakdown.md`
- Source doc path: `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade.md`
- Downstream workflow rule: detailed planning happens one session at a time. Later sessions must be refreshed against landed code before execution, especially around `GroupConversationWired`, `GroupMessageRepositoryImpl.saveMessage/updateMessageStatus`, and the group message DB helper contracts.
- Scope rule: this artifact decomposes the work only. It does not implement code and does not run the pipeline.

## Overall Closure Bar

The doc-102 duplicate-delivery cascade residue is considered closed only when all implementation and acceptance sessions prove the full group text and recorded-voice chain: failed text has an in-place id-stable retry, restored text resend does not mint a new id when the user is continuing the same failed send, voice retry can recover `upload_pending` rows without forcing a re-record, reliable-send timeout and in-doubt pending recovery no longer strand rows unnecessarily, local sweep status flips become visible in an open group conversation, retried `sending` rows are not failed by stale creation timestamps, live plus replay/drain delivery cannot emit or notify twice for one `messageId`, and the referenced gate and notification matrix docs record the final verification state.

## Run Mode Snapshot

- Active mode: `standard`
- Degraded local continuation explicitly allowed: no
- Source proposal path: `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade.md`
- Source status vocabulary: proposal sections and closure evidence; no row-owned `Open`/`Partial`/`Closed` matrix vocabulary is defined by the source doc.
- Overall closure bar: close the doc-102 duplicate-delivery cascade residue for group text and recorded voice, timeout/in-doubt pending recovery, local status broadcasts, stuck-sending timestamp recovery, live/replay dedup, and final gate/matrix documentation.
- Final verdict policy: persist exactly one final program verdict of `closed`, `accepted_with_explicit_follow_up`, `residual_only`, or `still_open`; this controller reports completion only after an allowed persisted final verdict exists or a concrete blocker is recorded.

## Controller Progress

- 2026-06-03 23:05:55 CEST: `status-timestamp-migration` execution evidence has reached QA review in fresh execution/QA child `019e8f39-4af2-73b0-acec-968bdf077b86`. Direct plan tests passed, the required group simulator proof passed, `git diff --check` passed, and `./scripts/run_test_gates.sh groups` failed only with the carried `GCA-004` residual already scoped as non-session-owned; the separate QA Reviewer child is still running, so the session ledger remains `pending` until QA returns a verdict and closure audit persists session evidence.
- 2026-06-03 23:11:08 CEST: Closure audit for `status-timestamp-migration` verified the accepted plan output against scoped repo evidence and persisted execution/QA evidence; session closure evidence was added below and the ledger row is now `accepted_with_explicit_follow_up`. Remaining sessions are `live-replay-dedup` and `acceptance-doc-closure`; no final whole-doc verdict is persisted here.
- 2026-06-03 23:13:46 CEST: Starting session `live-replay-dedup`; dependency `timeout-pending-retry` is accepted, `status-timestamp-migration` is now closed, no reusable plan exists at the intended path, and the next action is a fresh `gpt-5.5`/`xhigh` planning child for `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade-session-live-replay-dedup-plan.md`.
- 2026-06-03 23:22:43 CEST: Planning phase completed for `live-replay-dedup` with `Status: execution-ready` at the intended doc-scoped plan path; no blocker was recorded. The plan requires a RED concurrent live/replay listener regression, direct listener/drain/notification tests, `./scripts/run_test_gates.sh groups`, and simulator closure via `$run-flutter-reliability-sims` group `--only integration_test/foreground_group_push_drain_test.dart`. Next action is a fresh `gpt-5.5`/`xhigh` execution/QA child for that plan.
- 2026-06-03 23:27:19 CEST: `live-replay-dedup` execution is in progress under fresh execution/QA child `019e8f5e-bd76-7e31-a59e-7e7f6e190b26`; its isolated Executor `019e8f5f-daec-7a33-9096-129bd9c8be8b` is running and the session plan records the Executor handoff at 23:24:51 CEST. No blocker is recorded; next action remains waiting on Executor output, then spawning the isolated QA Reviewer before session closure.
- 2026-06-03 23:51:01 CEST: `live-replay-dedup` execution/QA completed with persisted plan verdict `accepted`; Executor `019e8f5f-daec-7a33-9096-129bd9c8be8b` and QA Reviewer `019e8f73-e1d5-71e0-96a1-175a7dbda0ad` found no blockers or follow-ups. Next action is a fresh `gpt-5.5`/`xhigh` closure-audit child to persist session ledger and closure evidence; the ledger row remains `pending` until that closure child updates it.
- 2026-06-03 23:55:28 CEST: Closure audit for `live-replay-dedup` verified the accepted plan output against scoped listener/test evidence and persisted session closure evidence; the ledger row is now `accepted_with_explicit_follow_up` because the only gate residual is the carried non-session-owned GCA-004 groups-gate failure. Remaining session is `acceptance-doc-closure`; no final whole-doc verdict, notification matrix update, or gate-definition update is persisted here.
- 2026-06-04 00:00:23 CEST: Starting session `acceptance-doc-closure`; all implementation-session ledger rows are now resolved as `accepted_with_explicit_follow_up`, no reusable plan exists at the intended path, and the next action is a fresh `gpt-5.5`/`xhigh` planning child for `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade-session-acceptance-doc-closure-plan.md`.
- 2026-06-04 00:06:18 CEST: `acceptance-doc-closure` planning remains in progress under fresh `gpt-5.5`/`xhigh` planning child `019e8f81-1ba6-7343-8ff6-1bdccfcb1d1a` (process session `67574`). Child output reported a draft plan write, but the intended plan path is not yet visible in this workspace, so no planning verdict is accepted. Next action is to wait for the child to return, then either verify the persisted plan at the doc-scoped path, restart planning in a fresh compliant child if no artifact was persisted, or record a concrete blocker.
- 2026-06-04 00:08:56 CEST: `acceptance-doc-closure` planning child `019e8f81-1ba6-7343-8ff6-1bdccfcb1d1a` exited successfully and persisted `Status: execution-ready` in `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade-session-acceptance-doc-closure-plan.md`. Next action is a fresh `gpt-5.5`/`xhigh` execution/QA child for that acceptance-only plan; the ledger row remains `pending` until execution and closure evidence are persisted.

## Closure Progress

- 2026-06-04 00:47:39 CEST: Session `acceptance-doc-closure`; phase `Completion Auditor`; docs inspected/updated: breakdown and acceptance plan inspected, breakdown progress updated; tentative verdict `accepted_with_explicit_follow_up`; next action verify persisted plan verdict, acceptance doc/matrix/source lineage updates, no final program verdict, and pending ledger row before writing closure evidence.
- 2026-06-04 00:48:17 CEST: Session `acceptance-doc-closure`; phase `Closure Writer`; docs inspected/updated: plan final execution verdict, source doc, notification matrix, doc-102 lineage, gate definitions classification, and breakdown ledger inspected; tentative verdict `accepted_with_explicit_follow_up`; next action update only the session ledger row and session closure evidence, leaving final program verdict to the parent final acceptance child.
- 2026-06-04 00:49:00 CEST: Session `acceptance-doc-closure`; phase `Closure Reviewer`; docs inspected/updated: breakdown ledger and new closure evidence updated; tentative verdict `accepted_with_explicit_follow_up`; next action review for overclaiming, confirm no final program verdict was written, and run lightweight `git diff --check` plus targeted `rg` verification.
- 2026-06-04 00:50:06 CEST: Session `acceptance-doc-closure`; phase `Closure Reviewer completed`; docs inspected/updated: breakdown ledger, closure evidence, persisted plan verdict, source/matrix/lineage update markers, and final-verdict heading absence verified; verdict `accepted_with_explicit_follow_up`; next action parent controller may spawn the separate final acceptance child to persist the whole-doc/program verdict.

## Final Acceptance Progress

- 2026-06-04 00:52:18 CEST: Final whole-doc acceptance child started under `$implementation-closure-audit-orchestrator`; progress marker persisted before final evidence audit/write/review. Tentative program verdict remains `accepted_with_explicit_follow_up` pending disk verification and exactly one final verdict section.

## Final Doc/Program Verdict

- Final doc/program verdict: `accepted_with_explicit_follow_up`
- Recorded: `2026-06-04T00:54:03+0200`
- Follow-up sweep recorded: `2026-06-04T10:35:16+0200`
- Sessions completed/blocked: 8/8 Session Ledger rows are resolved as `accepted_with_explicit_follow_up`; 0 blocked; final audit found no Session Ledger rows with `pending`, `blocked`, `prerequisite-blocked`, or `skipped_due_to_dependency`.
- Pre-write final-verdict check: no prior final whole-doc/program verdict section existed in this breakdown before this section was added.

Docs updated by the rollout:

- `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade.md`: contains `Acceptance Closure (2026-06-04)` and current closure status for the text/voice/timeout/status/dedup extension, with provider APNs/TestFlight preserved as the only remaining strict-closure residual after the GCA and real-network follow-up sweep.
- `Test-Flight-Improv/52-notification-journey-test-matrix.md`: rows `SM-003`, `GMN-001`, `GMN-101`, `GMN-104`, and `JRN-FG-GRP-01` now cite current closure evidence.
- `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux.md`: contains `June 2026 Closure Lineage` preserving doc-102 media lineage and recording the accepted text/voice follow-up evidence.
- `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade-session-acceptance-doc-closure-plan.md`: records final execution verdict `accepted_with_explicit_follow_up` at `2026-06-04T00:44:57+0200`.
- This breakdown: all session ledger rows and session closure evidence are resolved, and this final doc/program verdict is now the single whole-doc verdict.
- Session plan artifacts for the seven implementation sessions and the acceptance-only session remain the supporting execution/QA record.

Code/test files updated by implementation sessions, grouped by ownership:

- Group retry and conversation UI: `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/l10n/app_*.arb`, and generated `lib/l10n/app_localizations*.dart`.
- Send, retry, timeout, and upload recovery: `lib/core/bridge/bridge_group_helpers.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, and `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`.
- Persistence, stuck-sending recovery, and local status visibility: `lib/core/database/migrations/073_group_message_last_send_attempt_at.dart`, `lib/main.dart`, `lib/core/database/helpers/group_messages_db_helpers.dart`, `lib/features/groups/domain/models/group_message.dart`, `lib/features/groups/domain/repositories/group_message_repository*.dart`, and `test/shared/fakes/in_memory_group_message_repository.dart`.
- Live/replay/drain dedup: `lib/features/groups/application/group_message_listener.dart`.
- Follow-up invite recovery and real-network harness evidence: `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `scripts/run_test_gates.sh`, and `integration_test/group_recovery_cli_e2e_test.dart`.
- Representative tests: `test/features/groups/presentation/group_conversation_*test.dart`, `test/features/groups/application/*group_message*_test.dart`, `test/core/bridge/bridge_group_helpers_test.dart`, `test/core/database/**/group_messages_*test.dart`, `test/core/lifecycle/handle_app_resumed_group_*test.dart`, `integration_test/group_recovery_e2e_test.dart`, and `integration_test/foreground_group_push_drain_test.dart`.

Tests/gates run and results:

| Evidence | Result |
|---|---|
| Host direct suites | Passed: 20 required `flutter test` suites recorded in `/tmp/acceptance-doc-closure-direct-rerun.log`. |
| Simulator proof `integration_test/group_recovery_e2e_test.dart` command `#8` | Passed with reliability-sim `PASS` on simulator `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`. |
| Simulator proof `integration_test/foreground_group_push_drain_test.dart` command `#2` | Passed with reliability-sim `PASS` on simulator `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`. |
| `FLUTTER_DEVICE_ID=5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3 ./scripts/run_test_gates.sh transport` | Passed, recorded in `/tmp/acceptance-doc-closure-transport.log`. |
| `./scripts/run_test_gates.sh groups` | Passed after the follow-up `GCA-004` fix (`00:54 +318: All tests passed!`). |
| Focused `GCA-004` triage and regression coverage | Passed: inline invite bridge-error recovery preserves recovery state, welcome-package bridge-error recovery remains retryable, and `invite_round_trip_test.dart --plain-name "GCA-004 bridgeError recovery drains inbox after settled materialized invite"` passes. |
| `git diff --check` | Passed in the acceptance session, parent pre-final verification, and this final acceptance child after the verdict edit. |
| `./scripts/run_test_gates.sh completeness-check` | Not run: `Test-Flight-Improv/test-gate-definitions.md` was inspected and left unchanged, so this conditional classification gate was not required. |
| `./scripts/run_test_gates.sh group-real-network-nightly` | Passed on simulator `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3` with `MKNOON_RELAY_ADDRESSES` unset; the gate injected the app default relay CSV. The optional CLI fixture subtest skipped inside this gate because `CLI_PEER_FIXTURE` was not set. |
| Fixture-backed group recovery E2E | Passed with the app default relays via `dart run integration_test/scripts/run_group_recovery_e2e.dart -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`; the harness migration chain was updated through version `073`. |
| `./scripts/check_push_release_gate.sh` | Passed push release configuration checks, with warning that `FIREBASE_SERVICE_ACCOUNT` is unset. |
| `FIREBASE_SERVICE_ACCOUNT=<workspace service-account JSON> ./scripts/check_push_release_gate.sh --require-service-account` | Passed with zero warnings; the service-account `project_id` matches the iOS Firebase project. |
| Physical iPhone provider/APNs foreground probe | Passed on physical iPhone `00008110-00184D622289801E`: native logs show notification authorization enabled, APNs token registration, FCM token minting, relay push-token registration, Firebase FCM v1 send success for `projects/mknoon-c6e62/messages/1780565433195304`, and native `willPresent` receipt for probe `iphone13-foreground-20260604T113032`. |
| Physical iPhone provider/APNs background attempt | Not accepted as background proof: the delivered probe receipts were logged as `context=willPresent`, which means the app was foreground at delivery time. |
| Physical iPhone provider/APNs locked-screen tap proof | Passed on physical iPhone `00008110-00184D622289801E`: Firebase accepted probe `iphone13-locked2-20260604T113904` as `projects/mknoon-c6e62/messages/1780565944971027`; the user observed the lock-screen notification and tapped it; device process evidence immediately after tap showed `NotificationService.appex` PID `1973` and `Runner.app` PID `1975` running. |
| TestFlight install attempt | Direct `devicectl` install of `build/ios/ipa/mknoon.ipa` failed with `Attempted to install a Beta profile without the proper entitlement`, confirming direct IPA install is not a TestFlight substitute. `com.apple.TestFlight` is installed on the iPhone and was launched for manual app install/update. |

Residual follow-up items:

- Real TestFlight-installed background/terminated delivery proof remains explicit, non-blocking residual evidence. Service-account configuration, physical foreground provider delivery, and physical locked-screen provider tap delivery are now verified on iPhone hardware.

Accepted differences:

- Gate definitions are accepted unchanged; the touched suites are already covered by direct, optional/manual, nightly/release, or directory-level classifications.
- `completeness-check` is accepted as not required for this rollout because no gate-definition classification changed.
- Provider-backed APNs/TestFlight delivery remains accepted as external provider proof, not a repo-local implementation blocker. Fixture-backed real-network group recovery is no longer residual after the follow-up sweep.

Reopen policy:

- Reopen only on a new duplicate-delivery regression, a GCA invite recovery regression, a provider APNs/TestFlight proof failure, or a future real-network gate failure.

## Source Of Truth

- Product intent: `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade.md`
- Regression model: `Test-Flight-Improv/14-regression-test-strategy.md`
- Named gate source of truth: `Test-Flight-Improv/test-gate-definitions.md`
- Notification matrix: `Test-Flight-Improv/52-notification-journey-test-matrix.md`
- Related closure lineage: `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux.md` and GIRD-001 through GIRD-007 notes referenced by the source doc
- UI and wiring evidence: `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/conversation/presentation/screens/conversation_screen.dart`, `lib/features/conversation/presentation/widgets/letter_card.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- Send/retry evidence: `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/core/bridge/bridge_group_helpers.dart`, `go-mknoon/node/config.go`, `go-mknoon/node/pubsub.go`
- Persistence/recovery evidence: `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`, `lib/core/database/helpers/group_messages_db_helpers.dart`, `lib/main.dart`, `lib/core/database/migrations/`
- Receive/dedup evidence: `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- Existing direct tests to extend: `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/core/bridge/bridge_group_helpers_test.dart`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`, `test/core/database/helpers/group_messages_db_helpers_sending_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/integration/group_notification_dedupe_integration_test.dart`, `integration_test/foreground_group_push_drain_test.dart`

## Session Ledger

| Session id | Title | Classification | Intended plan file | Depends on | Current status |
|---|---|---|---|---|---|
| `text-retry-ui` | Failed text group retry and delete wiring | implementation-ready | `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade-session-text-retry-ui-plan.md` | none | accepted_with_explicit_follow_up |
| `text-continuation-id` | Id-stable restored text continuation | implementation-ready | `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade-session-text-continuation-id-plan.md` | `text-retry-ui` | accepted_with_explicit_follow_up |
| `voice-id-stable-retry` | Recorded-voice id-stable retry and upload recovery | implementation-ready | `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade-session-voice-id-stable-retry-plan.md` | `text-retry-ui` | accepted_with_explicit_follow_up |
| `timeout-pending-retry` | Reliable-send timeout and in-doubt pending retry payloads | implementation-ready | `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade-session-timeout-pending-retry-plan.md` | none | accepted_with_explicit_follow_up |
| `local-status-broadcasts` | Local sweep status broadcasts to open group screens | implementation-ready | `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade-session-local-status-broadcasts-plan.md` | `text-retry-ui`, `voice-id-stable-retry`, `timeout-pending-retry` | accepted_with_explicit_follow_up |
| `status-timestamp-migration` | Status-change timestamp for stuck-sending recovery | implementation-ready | `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade-session-status-timestamp-migration-plan.md` | `timeout-pending-retry` | accepted_with_explicit_follow_up |
| `live-replay-dedup` | Atomic live/replay dedup and one-notification proof | implementation-ready | `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade-session-live-replay-dedup-plan.md` | `timeout-pending-retry` | accepted_with_explicit_follow_up |
| `acceptance-doc-closure` | End-to-end acceptance, gate classification, and matrix closure | acceptance-only | `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade-session-acceptance-doc-closure-plan.md` | all implementation sessions | accepted_with_explicit_follow_up |

## Session Closure Evidence

### `text-retry-ui` - `accepted_with_explicit_follow_up` (2026-06-03)

What is closed:

- `GroupConversationScreen` accepts `onRetryFailedMessage` and passes `LetterCard.onRetryFailedMessage` plus `failedMessageActionKeySuffix: message.id` for failed, outgoing, text-only, non-empty rows when the group is writable and the callback exists.
- Failed-media retry/delete remains on the existing media-only path; a failed media row with caption keeps media retry/delete controls and does not get the text retry key.
- `GroupConversationWired._onRetryFailedMessage(String messageId)` calls `retryFailedGroupMessage(messageId: ...)`, refreshes the hydrated row with `_refreshMessageWithHydratedMedia(messageId)`, and shows `failed_message_retry_failed` when `retried == 0`.
- `GroupConversationWired` passes the text retry callback when `_canWrite` and `mediaAttachmentRepo` are available, without requiring `mediaFileManager`.
- `failed_message_retry_failed` is present in English, German, and Arabic ARBs plus generated localizations.

Code/test files carrying the closure:

- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`, `lib/l10n/app_ar.arb`, `lib/l10n/app_localizations*.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`

Verification evidence:

- `dart format --output=none --set-exit-if-changed lib/features/groups/presentation/screens/group_conversation_screen.dart lib/features/groups/presentation/screens/group_conversation_wired.dart test/features/groups/presentation/group_conversation_screen_test.dart test/features/groups/presentation/group_conversation_wired_test.dart` passed with 4 files formatted and 0 changed.
- `flutter test test/features/groups/presentation/group_conversation_screen_test.dart --plain-name "failed outgoing text-only rows show retry"` passed.
- `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "retry control re-sends the targeted failed outgoing text row"` passed.
- `flutter test test/features/groups/presentation/group_conversation_screen_test.dart` passed: 47 tests.
- `flutter test test/features/groups/presentation/group_conversation_wired_test.dart` passed: 105 tests.
- `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart` passed: 14 tests.

Residual-only / explicit follow-up:

- `./scripts/run_test_gates.sh groups` failed in `test/features/groups/integration/invite_round_trip_test.dart`, test `GCA-004 bridgeError recovery drains inbox after settled materialized invite`, at `invite_round_trip_test.dart:2930` with `Expected: not null`, `Actual: <null>`.
- The focused reproduction command `flutter test test/features/groups/integration/invite_round_trip_test.dart --plain-name "GCA-004 bridgeError recovery drains inbox after settled materialized invite"` failed with the same assertion. This is not attached to `text-retry-ui`; it remains carry-forward gate evidence for the parent controller or a later acceptance/gate session.

Still open:

- Current still-open program work after this closure pass: `local-status-broadcasts`, `status-timestamp-migration`, `live-replay-dedup`, and `acceptance-doc-closure` remain pending.
- The source proposal and final notification/gate matrix closure remain owned by `acceptance-doc-closure`.

Accepted differences:

- No failed text delete control was added in this session.
- No text continuation id semantics, voice retry/upload-pending behavior, bridge timeout, local sweep status broadcast, DB migration, live/replay dedup, notification behavior, test-gate definition, or whole-program closure verdict changed here.

### `text-continuation-id` - `accepted_with_explicit_follow_up` (2026-06-03)

What is closed:

- Restored text-only group composer continuation now tracks the failed row's continuation state when `_restoreComposerSnapshot` restores a non-empty text draft without pending attachments.
- Sending an unchanged restored text-only draft can reuse the failed row's original `messageId` and original timestamp through the existing restored-continuation resolution path in `_onSend`.
- Edited restored text remains a new send: the draft-change path clears the restored continuation when text diverges, and the send-use-case collision guard treats a mismatched explicit old failed-row id as a collision resolved by `messageIdFactory`.
- Existing text retry UI behavior from `text-retry-ui`, existing text-only in-place retry behavior, and existing media restored-continuation behavior remain covered by rerun tests.
- A narrow simulator-backed group recovery proof now covers failed restored text continuation preserving one sender row id and one receiver materialization for the same message id.

Code/test files carrying this session's closure:

- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `integration_test/group_recovery_e2e_test.dart`

Verification evidence:

- `dart format --output=none --set-exit-if-changed lib/features/groups/presentation/screens/group_conversation_wired.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/application/send_group_message_use_case_test.dart integration_test/group_recovery_e2e_test.dart` passed.
- Focused direct regressions passed: `restored text-only composer continuation reuses the failed group row id`, `editing restored text-only composer continuation creates a new group row id`, `message id collision guard treats edited restored failed text as a new message`, `retries a text-only failed row in place using the original ids`, and `GIRD-002 restored media composer continuation reuses the failed group row id`.
- Full direct suites passed: `test/features/groups/presentation/group_conversation_wired_test.dart` with 107 tests, `test/features/groups/application/send_group_message_use_case_test.dart` with 132 tests, and `test/features/groups/application/retry_failed_group_messages_use_case_test.dart` with 14 tests.
- `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list` passed and identified `integration_test/group_recovery_e2e_test.dart` as group command `#8`.
- `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/group_recovery_e2e_test.dart` passed.
- `./scripts/run_test_gates.sh groups` first failed in `ST-003`; the focused `ST-003` rerun passed. The logged full rerun at `/tmp/text-continuation-groups-rerun.log` exited 1 only with the carried `GCA-004 bridgeError recovery drains inbox after settled materialized invite` residual at `test/features/groups/integration/invite_round_trip_test.dart:2930`, `Expected: not null`, `Actual: <null>`.
- QA reran the five focused tests plus `git diff --check`; all passed.

Residual-only / explicit follow-up:

- The broad groups gate residual remains the known unrelated `GCA-004 bridgeError recovery drains inbox after settled materialized invite` at `test/features/groups/integration/invite_round_trip_test.dart:2930`, `Expected: not null`, `Actual: <null>`. This is carried forward exactly as prior session evidence and does not attach to `text-continuation-id`.
- QA noted an optional timestamp-only failed-row id collision guard variant as non-blocking. The production predicate and required edited-text/mismatched guard regression already cover the required contract.

Still open:

- Current still-open program work after this closure pass: `local-status-broadcasts`, `status-timestamp-migration`, `live-replay-dedup`, and `acceptance-doc-closure` remain pending.
- The source proposal, final notification matrix, and final whole-program verdict remain owned by `acceptance-doc-closure`.

Accepted differences:

- Helper names remain media-oriented (`_RestoredGroupMediaContinuation`, `_trackRestoredMediaContinuation`, and related methods) even though the behavior now also covers text-only restored composer continuation. This naming difference is accepted because the closure behavior and regression coverage are explicit.
- No voice retry/upload-pending behavior, bridge timeout, local status broadcast, DB schema or migration, receive-side live/replay dedup, notification behavior, gate-definition classification, or whole-program closure verdict changed in this session.

### `voice-id-stable-retry` - `accepted_with_explicit_follow_up` (2026-06-03)

What is closed:

- Uploaded failed voice rows with done audio attachments have explicit same-id retry coverage: retry publishes the original `messageId` and timestamp and updates one existing row.
- Failed outgoing voice rows with `upload_pending` audio now use a message-scoped upload retry path from the failed-media action, re-drive only that row's upload, then publish the same `messageId` after upload success.
- Manual upload-pending voice retry is background-task protected and refreshes the target row/media after retry.
- Durable voice prep failures clean up generated unsent state instead of leaving an empty retry-less failed row or orphan pending-upload directory.
- Immediate voice re-record after a retryable voice failure can reuse the failed row's `messageId` and timestamp through a narrow in-memory continuation guard.
- A narrow simulator-backed proof in `integration_test/group_recovery_e2e_test.dart` covers one sender row id and one receiver materialization for the voice re-record same-id path.

Code/test files carrying this session's closure:

- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`
- `integration_test/group_recovery_e2e_test.dart`

Verification evidence:

- `dart format --output=none --set-exit-if-changed lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart lib/features/groups/presentation/screens/group_conversation_wired.dart test/features/groups/application/retry_failed_group_messages_use_case_test.dart test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart integration_test/group_recovery_e2e_test.dart` passed with `Formatted 7 files (0 changed)`.
- Focused voice regressions passed for message-scoped upload retry, wired upload-pending voice retry, durable voice prep cleanup, voice re-record continuation, background-task protection, and uploaded-audio same-id retry.
- Full direct suites passed: `test/features/groups/application/retry_failed_group_messages_use_case_test.dart` with `+15`, `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart` with `+19`, `test/features/groups/presentation/group_conversation_wired_test.dart` with `+110`, and `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart` with `+19`.
- `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/group_recovery_e2e_test.dart` passed on one-device simulator `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, command `#8`, with `+7`.
- `./scripts/run_test_gates.sh groups` exited `1` only with the carried `GCA-004 bridgeError recovery drains inbox after settled materialized invite` residual at `test/features/groups/integration/invite_round_trip_test.dart:2930`, `Expected: not null`, `Actual: <null>`.
- `git diff --check` passed.

Residual-only / explicit follow-up:

- The broad groups gate residual remains the known unrelated `GCA-004 bridgeError recovery drains inbox after settled materialized invite` at `test/features/groups/integration/invite_round_trip_test.dart:2930`, `Expected: not null`, `Actual: <null>`. This is carried forward exactly as prior session evidence and does not attach to `voice-id-stable-retry`.
- Optional hardening only: add a dedicated wired-screen done-audio retry proof later if desired. QA accepted the current use-case same-id proof plus generic wired media retry coverage as sufficient, so this is not a blocking residual.

Still open:

- Current still-open program work after this closure pass: `local-status-broadcasts`, `status-timestamp-migration`, `live-replay-dedup`, and `acceptance-doc-closure` remain pending.
- The source proposal, final notification matrix, gate-definition final classification, and final whole-program verdict remain owned by `acceptance-doc-closure`.

Accepted differences:

- Non-voice `upload_pending` failed media may keep the existing pending-feedback behavior unless a later scoped session intentionally generalizes it with explicit non-regression tests.
- Voice continuation is intentionally in-memory and same-screen only; restart recovery remains owned by in-place failed-row retry and upload retry.
- If two different same-id voice byte streams race, recipients may keep whichever same-id delivery materializes first. The accepted contract is one logical voice message id and one bubble, not post-delivery byte replacement.
- No bridge timeout, pending retry-payload fallback, local status broadcast, DB schema/migration, receive-side live/replay dedup, notification behavior, source-doc final closure, or whole-program verdict changed in this session.

### `timeout-pending-retry` - `accepted_with_explicit_follow_up` (2026-06-03)

What is closed:

- `callGroupSendReliable` now exposes and uses `groupSendReliableDefaultTimeout = Duration(seconds: 40)`, above the native reliable-send publish budget while preserving explicit caller-provided timeouts.
- The in-doubt reliable-send path remains success-returning and saves ambiguous timeout / publish-without-custody rows as `pending`, not false `failed`.
- Existing native-envelope retry-payload fallback is now pinned by a direct regression: when local replay-envelope construction fails but native reliable-send returns a valid `envelope` and `recipientPeerIds`, the saved pending row has a non-null inbox retry payload and is selected by the inbox retry sweep.
- No plaintext, raw publish params, or private-key material is persisted as retry payload data.

Code/test files:

- `lib/core/bridge/bridge_group_helpers.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `test/core/bridge/bridge_group_helpers_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`
- `integration_test/group_recovery_e2e_test.dart`

Verification evidence:

- Formatter gate passed for the timeout owner files and required direct-test set.
- Focused direct tests passed: `callGroupSendReliable`, `GIRD-001`, `replay-envelope`, DB `pending`, and `handle_app_resumed_group_inbox_retry_test.dart`.
- Full direct suites passed: `test/core/bridge/bridge_group_helpers_test.dart` with 80 tests, `test/features/groups/application/send_group_message_use_case_test.dart` with 133 tests, and `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart` with 44 tests.
- `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh transport` passed after the first unselected-device attempt failed before test execution because multiple devices were connected.
- `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/group_recovery_e2e_test.dart` passed on one-device simulator `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, command `#8`, with `+7`.
- `git diff --check` passed; QA spot checks reran `callGroupSendReliable`, `GIRD-001`, and `git diff --check` successfully.

Residual-only/explicit follow-up:

- `./scripts/run_test_gates.sh groups` exited `1` only with the carried known `GCA-004 bridgeError recovery drains inbox after settled materialized invite` residual at `test/features/groups/integration/invite_round_trip_test.dart:2930`, `Expected: not null`, `Actual: <null>`.
- The focused triage command reproduced that exact `GCA-004` residual. It remains unrelated carry-forward gate evidence for the later acceptance/closure owner and does not attach to `timeout-pending-retry`.
- No timeout-owned follow-up remains.

Still open:

- `local-status-broadcasts`, `status-timestamp-migration`, `live-replay-dedup`, and `acceptance-doc-closure` remain pending.
- The source proposal, final notification matrix, gate-definition final classification, and final whole-program verdict remain owned by `acceptance-doc-closure`.

Accepted differences:

- Native early-custody signaling was not added; the accepted scoped fix is the Dart-side timeout bump plus retained in-doubt handling.
- No stale-pending sweep, DB schema or migration, local status broadcast, status-change timestamp, live/replay dedup, notification behavior, source-doc final closure, or whole-program verdict changed in this session.
- `lib/features/groups/application/send_group_message_use_case.dart` needed no production change because the existing native-envelope retry-payload path passed the new regression.

### `local-status-broadcasts` - `accepted_with_explicit_follow_up` (2026-06-03)

What is closed:

- `GroupMessageRepositoryImpl` exposes the optional `GroupOutgoingLocalMessageChangeSource` stream and emits per-message outgoing local status events after successful status-changing `saveMessage(...)` and `updateMessageStatus(...)` writes.
- Incoming rows and unchanged-status saves/updates are suppressed so the UI does not receive duplicate local status spam.
- Count-only outgoing sweeps from `recoverStuckSendingMessages(...)` and `transitionSendingToFailed()` emit one batch rows-changed event when at least one row changed.
- `GroupConversationWired` subscribes only when the repository supports the optional source, updates matching same-group per-message statuses in place, reloads current messages for batch rows-changed events, ignores other groups, and cancels/resubscribes across dispose, group reset, and repository changes.
- A narrow simulator-backed proof in `integration_test/group_recovery_e2e_test.dart` covers an open group screen reflecting a local outgoing status change without listener/self-echo publication.

Code/test files carrying this session's closure:

- `lib/features/groups/domain/repositories/group_message_repository.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
- `test/shared/fakes/in_memory_group_message_repository.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `integration_test/group_recovery_e2e_test.dart`

Verification evidence:

- Focused RED regressions failed before implementation, then passed after implementation: `saveMessage emits one local status event when an outgoing row changes status` and `local outgoing status event updates visible row without listener stream`.
- Full direct suites passed: `flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart` and `flutter test test/features/groups/presentation/group_conversation_wired_test.dart`.
- `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list` passed and listed `integration_test/group_recovery_e2e_test.dart` as group command `#8`.
- `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/group_recovery_e2e_test.dart` passed on one-device simulator `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`.
- `./scripts/run_test_gates.sh groups`, run through `bash -lc 'set -o pipefail; ./scripts/run_test_gates.sh groups 2>&1 | tee /tmp/mknoon-local-status-groups.log'`, exited `1` only with the carried known `GCA-004 bridgeError recovery drains inbox after settled materialized invite` residual at `test/features/groups/integration/invite_round_trip_test.dart:2930`, `Expected: not null`, `Actual: <null>`.
- Focused triage `flutter test test/features/groups/integration/group_membership_smoke_test.dart --plain-name "GM-008 removes C, restarts C before re-add, and rejoins from current persisted epoch"` passed, confirming the later `GM-008` runner lines were not a distinct failure.
- QA spot checks passed: the focused repository local-status event test, the focused wired in-place update test, and `git diff --check`.
- `dart format --output=none --set-exit-if-changed lib/features/groups/domain/repositories/group_message_repository.dart lib/features/groups/domain/repositories/group_message_repository_impl.dart lib/features/groups/presentation/screens/group_conversation_wired.dart test/shared/fakes/in_memory_group_message_repository.dart test/features/groups/domain/repositories/group_message_repository_impl_test.dart test/features/groups/presentation/group_conversation_wired_test.dart integration_test/group_recovery_e2e_test.dart` passed with `Formatted 7 files (0 changed)`.

Residual-only / explicit follow-up:

- The broad groups gate residual remains the known unrelated `GCA-004 bridgeError recovery drains inbox after settled materialized invite` at `test/features/groups/integration/invite_round_trip_test.dart:2930`, `Expected: not null`, `Actual: <null>`. This is carried forward exactly as prior session evidence and does not attach to `local-status-broadcasts`.

Still open:

- `status-timestamp-migration`, `live-replay-dedup`, and `acceptance-doc-closure` remain pending.
- The source proposal, final notification matrix, gate-definition final classification, and final whole-program verdict remain owned by `acceptance-doc-closure`.

Accepted differences:

- Count-only sweeps emit a batch rows-changed event that reloads the open group's current page instead of recovering per-message ids. This is accepted because the current DB helper returns only a count, and adding affected-row discovery would broaden this UI-refresh session.
- Media attachment state synchronization remains on existing media refresh paths or batch reloads; this session closes outgoing message status visibility only.
- No send retry semantics, message id/timestamp semantics, timeout values, DB schema/migration, receive-side live/replay dedup, notification behavior, source-doc final closure, or whole-program verdict changed in this session.

### `status-timestamp-migration` - `accepted_with_explicit_follow_up` (2026-06-03)

What is closed:

- Accepted plan `01-P0-duplicate-delivery-cascade-session-status-timestamp-migration-plan.md` landed migration `073`, adding nullable `group_messages.last_send_attempt_at` without backfilling old rows.
- `lib/main.dart` is wired to database version `73`, imports migration `073`, and runs it on fresh create and upgrade from versions below `73`.
- `GroupMessage` now maps and copies nullable `lastSendAttemptAt` through `last_send_attempt_at`.
- New outgoing group send attempts persist a fresh UTC `lastSendAttemptAt` on the pre-persisted `status: 'sending'` row while keeping the logical message `timestamp` unchanged.
- Retry keeps the original message id and logical timestamp while receiving a fresh attempt timestamp through `sendGroupMessage`.
- Stuck-sending recovery now uses `COALESCE(last_send_attempt_at, timestamp)` in the DB helper selection/transition paths, so fresh retry attempts are not failed by stale creation/logical timestamps and legacy rows with `NULL last_send_attempt_at` keep the old fallback behavior.
- The in-memory fake uses `lastSendAttemptAt ?? timestamp` for stuck-sending recovery, keeping application tests aligned with SQLite behavior.
- Status transitions to `sent`, `pending`, or `failed` preserve `lastSendAttemptAt` through model copy/save behavior without changing message ordering or duplicate identity.

Code/test files carrying this session's closure:

- `lib/core/database/migrations/073_group_message_last_send_attempt_at.dart`
- `lib/main.dart`
- `lib/core/database/helpers/group_messages_db_helpers.dart`
- `lib/features/groups/domain/models/group_message.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `test/shared/fakes/in_memory_group_message_repository.dart`
- `test/core/database/migrations/073_group_message_last_send_attempt_at_test.dart`
- `test/core/database/integration/full_migration_chain_test.dart`
- `test/core/database/helpers/group_messages_db_helpers_sending_test.dart`
- `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`
- `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart`
- `test/core/database/helpers/group_sync_receipts_db_helpers_test.dart`

Verification evidence:

- Plan status is `accepted`.
- Direct tests passed: `flutter test --no-pub test/core/database/migrations/073_group_message_last_send_attempt_at_test.dart`, `flutter test --no-pub test/core/database/helpers/group_messages_db_helpers_sending_test.dart`, `flutter test --no-pub test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`, `flutter test --no-pub test/features/groups/domain/repositories/group_message_repository_impl_test.dart`, `flutter test --no-pub test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `flutter test --no-pub test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`, `flutter test --no-pub test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart`, and `flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart`.
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart` failed once due to a compile-shape issue where `lastSendAttemptAt` was passed to `_resolveOutgoingMessageId`; the focused fix moved the attempt timestamp to outgoing `GroupMessage` construction, then the test passed.
- Extra touched-file validation `flutter test --no-pub test/core/database/helpers/group_sync_receipts_db_helpers_test.dart` passed.
- `./scripts/run_test_gates.sh groups` exited `1` only with the carried known `GCA-004 bridgeError recovery drains inbox after settled materialized invite` residual at `test/features/groups/integration/invite_round_trip_test.dart:2930`, `Expected: not null`, `Actual: <null>`.
- Focused `GCA-004` triage reproduced the same assertion, so the groups gate failure is classified as non-session-owned.
- Required simulator proof passed: `${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh group --only integration_test/group_recovery_e2e_test.dart` on one-device simulator `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, runner command `#8`.
- `git diff --check` passed.
- Execution QA Reviewer returned `no_blocking_issues` with no non-blocking follow-ups required.

Residual-only / explicit follow-up:

- The broad groups gate residual remains the known unrelated `GCA-004 bridgeError recovery drains inbox after settled materialized invite` at `test/features/groups/integration/invite_round_trip_test.dart:2930`, `Expected: not null`, `Actual: <null>`. This is carried forward exactly as prior session evidence and does not attach to `status-timestamp-migration`.

Still open:

- `live-replay-dedup` and `acceptance-doc-closure` remain pending.
- The source proposal, final notification matrix, gate-definition final classification, and final whole-program verdict remain owned by `acceptance-doc-closure`.

Accepted differences:

- The session added `last_send_attempt_at`, not a general status-updated timestamp, and it does not backfill old rows. `NULL` plus `COALESCE(..., timestamp)` is the compatibility contract.
- `dbLoadStuckSendingGroupMessages` was updated with the same cutoff predicate as `dbTransitionGroupSendingToFailed`; ordering remains by logical `timestamp ASC, id ASC`.
- No message id generation, logical timestamp ordering, retry payload format, bridge timeout, local status broadcast contract, receive-side live/replay dedup, notification behavior, source-doc final closure, or whole-program verdict changed in this session.

### `live-replay-dedup` - `accepted_with_explicit_follow_up` (2026-06-03)

What is closed:

- Accepted plan `01-P0-duplicate-delivery-cascade-session-live-replay-dedup-plan.md` landed listener-owned per-user-message serialization in `GroupMessageListener`.
- Live delivery and `handleReplayEnvelope(...)` now route non-system user payloads with a stable, non-empty `messageId` through a shared message queue before `_handleMessage(...)`, so live and replay/drain handling for one user message id cannot overlap inside the receive use case and double-own listener side effects.
- System payloads and message-id-less payloads keep the existing handling path, preserving signed membership/config cleanup behavior.
- `handleReplayEnvelope(...)` still forwards `msgRepoOverride`, `rethrowOnError`, and `allowMembershipBuffer`; live handling remains `_trackInFlight(...)` tracked.
- The direct race regression proves one saved visible row, one `groupMessageStream` emit, one local notification, and unread count one for raced `live-replay-race-message`.
- Future work should reopen this slice only on a real regression where live/replay/drain handling for the same non-system user `messageId` again produces duplicate visible materialization, duplicate stream emits, duplicate local notifications, or duplicate unread increments.

Code/test files carrying this session's closure:

- `lib/features/groups/application/group_message_listener.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade-session-live-replay-dedup-plan.md`

Verification evidence:

- Plan status is `accepted`.
- Executor `019e8f5f-daec-7a33-9096-129bd9c8be8b` completed first; QA Reviewer `019e8f73-e1d5-71e0-96a1-175a7dbda0ad` completed second with no blocking issues and no non-blocking follow-ups.
- Focused RED regression `flutter test test/features/groups/application/group_message_listener_test.dart --plain-name "live and replay delivery for one message id emit and notify once when raced"` initially failed with two stream emits for `live-replay-race-message`, then passed after the listener queue fix.
- `flutter test test/features/groups/application/group_message_listener_test.dart` passed.
- `flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart` passed.
- `flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` passed.
- `flutter test test/integration/group_notification_dedupe_integration_test.dart` passed.
- `./scripts/run_test_gates.sh groups` exited `1` only with the carried known `GCA-004 bridgeError recovery drains inbox after settled materialized invite` residual at `test/features/groups/integration/invite_round_trip_test.dart:2930`, `Expected: not null`, `Actual: <null>`.
- Required simulator proof passed: `${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh group --only integration_test/foreground_group_push_drain_test.dart` on simulator `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, command `#2`, with all 8 tests passed.
- `dart format` applied formatting to `lib/features/groups/application/group_message_listener.dart` and `test/features/groups/application/group_message_listener_test.dart`; the follow-up `dart format --output=none --set-exit-if-changed` check for those touched Dart files passed.
- `git diff --check` passed.

Residual-only / explicit follow-up:

- The broad groups gate residual remains the known unrelated `GCA-004 bridgeError recovery drains inbox after settled materialized invite` at `test/features/groups/integration/invite_round_trip_test.dart:2930`, `Expected: not null`, `Actual: <null>`. This is carried forward exactly as prior session evidence and does not attach to `live-replay-dedup`.
- No `live-replay-dedup` follow-up remains.

Still open:

- `acceptance-doc-closure` remains pending.
- The source proposal, final notification matrix, gate-definition final classification, and final whole-program verdict remain owned by `acceptance-doc-closure`.

Accepted differences:

- Listener-owned per-message serialization is accepted instead of repository insert-result plumbing or a new cross-repo dedupe service.
- The queue is intentionally scoped to stable non-system user `messageId`s; system payloads and message-id-less events retain existing behavior.
- `integration_test/foreground_group_push_drain_test.dart` did not need extension because the existing required simulator target passed as the foreground push/drain closure proof.
- No send/retry UI, restored text id semantics, voice retry/upload recovery, bridge timeout, local status broadcast, DB schema/migration, source-doc final closure, notification matrix, or gate-definition behavior changed in this session.

### `acceptance-doc-closure` - `accepted_with_explicit_follow_up` (2026-06-04)

What is closed:

- Accepted plan `01-P0-duplicate-delivery-cascade-session-acceptance-doc-closure-plan.md` persisted final execution verdict `accepted_with_explicit_follow_up` at `2026-06-04T00:44:57+0200`.
- The acceptance session reconciled all seven implementation-session evidence records into the source proposal, notification matrix, doc-102 lineage, and the session plan's evidence ledger without touching production code, behavior tests, migrations, app config, or prior implementation-session files.
- `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade.md` now treats failed text retry, restored text same-id continuation, recorded-voice retry/re-record recovery, timeout/pending retry payloads, local outgoing status visibility, stuck-sending attempt timestamps, and live/replay one-notification dedup as accepted repo-local evidence rather than missing implementation gaps.
- `Test-Flight-Improv/52-notification-journey-test-matrix.md` rows `SM-003`, `GMN-001`, `GMN-101`, `GMN-104`, and `JRN-FG-GRP-01` now cite the accepted text/voice recovery, foreground drain, live/replay one-materialization, and one-notification evidence while keeping provider-backed proof residual.
- `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux.md` now preserves doc-102 as the media lineage anchor and records that the June 2026 follow-up closes or residualizes the text/voice extension.
- `Test-Flight-Improv/test-gate-definitions.md` was inspected and left unchanged because existing classifications cover the relevant direct, optional/manual, nightly/release, and database test paths; `completeness-check` was not required.

Docs touched / inspected:

- Touched by the acceptance session: `Test-Flight-Improv/52-notification-journey-test-matrix.md`, `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade.md`, `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux.md`, and `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade-session-acceptance-doc-closure-plan.md`.
- Inspected and unchanged: `Test-Flight-Improv/test-gate-definitions.md`.
- Updated by this closure audit: this breakdown's `acceptance-doc-closure` ledger row and this session closure evidence subsection only.

Verification evidence:

- Final execution verdict persisted in the plan: `accepted_with_explicit_follow_up`, recorded `2026-06-04T00:44:57+0200`.
- Host direct rerun sweep passed for 20 required suites, recorded in `/tmp/acceptance-doc-closure-direct-rerun.log`.
- Simulator closure proofs passed in spawned Executor evidence: `integration_test/group_recovery_e2e_test.dart` command `#8` and `integration_test/foreground_group_push_drain_test.dart` command `#2` on simulator `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, each with reliability-sim `PASS`.
- `FLUTTER_DEVICE_ID=5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3 ./scripts/run_test_gates.sh transport` passed, recorded in `/tmp/acceptance-doc-closure-transport.log`.
- `./scripts/run_test_gates.sh groups` failed only with the carried known non-owned `GCA-004 bridgeError recovery drains inbox after settled materialized invite` residual during this earlier closure pass; that historical residual was closed by the follow-up sweep recorded in `Final Doc/Program Verdict`.
- `git diff --check` passed during execution/QA before closure audit.

Residual-only / explicit follow-up:

- Real provider-backed APNs/TestFlight background/terminated proof remains residual-only and is not a repo-local implementation blocker.
- The earlier broad groups-gate `GCA-004` residual is superseded by the follow-up sweep: focused regression coverage and `./scripts/run_test_gates.sh groups` now pass.
- The earlier `group-real-network-nightly` fixture note is superseded by the follow-up sweep: the gate now uses app default relays when `MKNOON_RELAY_ADDRESSES` is unset, and both the named gate and fixture-backed group recovery E2E passed with those defaults.

Still open:

- No current-session implementation work remains open.
- Final whole-doc/program verdict is intentionally not written by this closure child. The parent controller owns the separate final acceptance child and must persist exactly one final program verdict.

Accepted differences:

- Gate definitions remain unchanged because the existing inventory classifications already cover the direct, optional/manual, nightly/release, and database tests used by this acceptance session.
- Historical/original checklist wording remains in the source doc where explicitly marked as historical or original context; the new acceptance closure tables are the current source of truth.
- Spawned Executor progress is accepted for simulator proofs because the plan records command ids, simulator id, pass counts, and reliability-sim `PASS`; the no-progress recovery path reran the host direct suites, `transport`, `git diff --check`, and separate QA review.
- The earlier broad `groups` accepted-with-follow-up allowance for `GCA-004` is closed; any future GCA or groups-gate failure should reopen triage rather than inherit this historical acceptance.

## Ordered Session Breakdown

### 1. Failed Text Group Retry And Delete Wiring

- Session id: `text-retry-ui`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade-session-text-retry-ui-plan.md`
- Exact scope: add group-screen `onRetryFailedMessage` wiring for failed text-only outgoing rows, mirror the 1:1 retry affordance, call existing `retryFailedGroupMessage(messageId: ...)`, refresh the hydrated row, and preserve existing failed-media retry/delete behavior.
- Why it is its own session: it is the smallest high-leverage UI slice and can be verified without changing send semantics, schema, bridge timeouts, or voice recording.
- Likely code-entry files: `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/conversation/presentation/widgets/letter_card.dart` as read-only reference, `lib/features/groups/application/retry_failed_group_messages_use_case.dart` as existing call target.
- Likely direct tests/regressions: `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`.
- Likely named gates: `./scripts/run_test_gates.sh groups`; baseline is normal PR hygiene if the downstream plan asks for broad confidence.
- Matrix/closure docs to update when done: final ownership stays with `acceptance-doc-closure`; only update `Test-Flight-Improv/test-gate-definitions.md` in this session if a new high-value test file needs classification.
- Dependency on earlier sessions: none.

### 2. Id-Stable Restored Text Continuation

- Session id: `text-continuation-id`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade-session-text-continuation-id-plan.md`
- Exact scope: generalize restored-composer continuation tracking so a failed text-only row can reuse its original `messageId` and timestamp when the user continues the same text, while edited text remains a new message.
- Why it is its own session: it changes resend/id semantics rather than only surfacing existing retry plumbing, and it needs focused id-reuse regressions.
- Likely code-entry files: `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/application/send_group_message_use_case.dart` for `_resolveOutgoingMessageId` behavior, existing 1:1/group retry tests as references.
- Likely direct tests/regressions: `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, and existing text-only retry assertions in `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`.
- Likely named gates: `./scripts/run_test_gates.sh groups`.
- Matrix/closure docs to update when done: final ownership stays with `acceptance-doc-closure`.
- Dependency on earlier sessions: `text-retry-ui`, so the downstream plan can decide whether restored typing should remain secondary to in-place retry.

### 3. Recorded-Voice Id-Stable Retry And Upload Recovery

- Session id: `voice-id-stable-retry`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade-session-voice-id-stable-retry-plan.md`
- Exact scope: make failed voice retry prove same-id resend for uploaded audio, make `upload_pending` voice retry immediately re-drive the specific upload instead of snackbar-only no-op, handle pre-send durable-prep failures without leaving empty retry-less rows, and guard any re-record continuation so one intended voice send still owns one stable id.
- Why it is its own session: voice uses `_onRecordStop()` rather than `_onSend`, has upload-specific failure modes, and has a different duplicate risk because re-recorded bytes cannot be content-deduped.
- Likely code-entry files: `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`, voice media repository helpers touched by existing upload tests.
- Likely direct tests/regressions: `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`.
- Likely named gates: `./scripts/run_test_gates.sh groups`; optional/manual simulator media or recovery suites only if the downstream plan introduces device-backed voice acceptance.
- Matrix/closure docs to update when done: final ownership stays with `acceptance-doc-closure`.
- Dependency on earlier sessions: `text-retry-ui` only for shared failed-row action conventions.

### 4. Reliable-Send Timeout And In-Doubt Pending Retry Payloads

- Session id: `timeout-pending-retry`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade-session-timeout-pending-retry-plan.md`
- Exact scope: raise `callGroupSendReliable`'s default timeout above the native concurrent `InboxTimeout`/`PubSubTimeout` budget, keep in-doubt handling for genuine slow cases, and ensure pending in-doubt rows keep a non-null retry payload even if replay-envelope construction fails.
- Why it is its own session: it closes the no-schema send-reliability residue and can be verified independently from UI affordances and DB schema changes.
- Likely code-entry files: `lib/core/bridge/bridge_group_helpers.dart`, `go-mknoon/node/config.go`, `go-mknoon/node/pubsub.go`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/core/database/helpers/group_messages_db_helpers.dart`.
- Likely direct tests/regressions: `test/core/bridge/bridge_group_helpers_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`, `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`.
- Likely named gates: `./scripts/run_test_gates.sh groups`; `./scripts/run_test_gates.sh transport` if bridge helper timeout behavior is treated as transport-facing by the downstream plan.
- Matrix/closure docs to update when done: final ownership stays with `acceptance-doc-closure`.
- Dependency on earlier sessions: none.

### 5. Local Sweep Status Broadcasts To Open Group Screens

- Session id: `local-status-broadcasts`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade-session-local-status-broadcasts-plan.md`
- Exact scope: expose a lightweight outgoing group status change signal from local repository/retrier updates and have an open `GroupConversationWired` apply those updates without waiting for a self-echo or route reload.
- Why it is its own session: it is an in-process UI refresh seam, not a send retry or schema problem, and it has lifecycle/subscription risks that need isolated tests.
- Likely code-entry files: `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/core/services/pending_message_retrier.dart`, `lib/core/lifecycle/handle_app_resumed.dart` if the downstream plan chooses a batched rows-changed event.
- Likely direct tests/regressions: `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/core/services/pending_message_retrier_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`.
- Likely named gates: `./scripts/run_test_gates.sh groups`.
- Matrix/closure docs to update when done: final ownership stays with `acceptance-doc-closure`.
- Dependency on earlier sessions: `text-retry-ui`, `voice-id-stable-retry`, and `timeout-pending-retry` so the event contract observes the status transitions those sessions harden.

### 6. Status-Change Timestamp For Stuck-Sending Recovery

- Session id: `status-timestamp-migration`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade-session-status-timestamp-migration-plan.md`
- Exact scope: add a nullable group-message status-change or send-attempt timestamp column in the next DB version after current version 72, write it when rows enter `sending`, and make `dbTransitionGroupSendingToFailed` compare against that timestamp with legacy fallback to `timestamp`.
- Why it is its own session: it is the only schema-bearing slice, touches migration order in `lib/main.dart`, and must not be mixed with UI or notification changes.
- Likely code-entry files: `lib/core/database/migrations/`, `lib/main.dart`, `lib/core/database/helpers/group_messages_db_helpers.dart`, `lib/features/groups/domain/models/group_message.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`.
- Likely direct tests/regressions: a new migration test under `test/core/database/migrations/`, `test/core/database/helpers/group_messages_db_helpers_sending_test.dart`, `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`, `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`, `test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart`.
- Likely named gates: `./scripts/run_test_gates.sh groups`; `./scripts/run_test_gates.sh completeness-check` only if new test files require classification updates.
- Matrix/closure docs to update when done: final ownership stays with `acceptance-doc-closure`.
- Dependency on earlier sessions: `timeout-pending-retry`, because both define the final retry/pending/stuck status semantics.

### 7. Atomic Live/Replay Dedup And One-Notification Proof

- Session id: `live-replay-dedup`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade-session-live-replay-dedup-plan.md`
- Exact scope: route replay/drain and live group message handling through a shared serialization or idempotent emit/notify guard so concurrent handling of one `messageId` cannot produce two stream emits or two local notifications.
- Why it is its own session: receive-side concurrency and notification dedup are lower-priority than send recovery but have a distinct blast radius and different direct tests.
- Likely code-entry files: `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, notification gate helpers if the idempotent-notify option is chosen.
- Likely direct tests/regressions: `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/integration/group_notification_dedupe_integration_test.dart`, `integration_test/foreground_group_push_drain_test.dart`.
- Likely named gates: `./scripts/run_test_gates.sh groups`; optional/manual notification direct suites from `test-gate-definitions.md` if touched.
- Matrix/closure docs to update when done: `acceptance-doc-closure` must update notification matrix rows tied to one-visible-materialization and one-notification guarantees.
- Dependency on earlier sessions: `timeout-pending-retry`, so final dedup assertions run against the hardened pending/replay contract.

### 8. End-To-End Acceptance, Gate Classification, And Matrix Closure

- Session id: `acceptance-doc-closure`
- Session classification: `acceptance-only`
- Intended plan file: `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade-session-acceptance-doc-closure-plan.md`
- Exact scope: run or record the final direct suites and named gates selected by prior sessions, classify any newly added high-value tests in `Test-Flight-Improv/test-gate-definitions.md`, update the notification matrix with the text/voice retry and one-notification closure evidence, and record any device/real-APNs residual as residual-only rather than implementation scope.
- Why it is its own session: it validates multiple prior slices and owns documentation updates that would be easy to forget if spread across implementation plans.
- Likely code-entry files: none unless a test classification doc needs a small correction.
- Likely direct tests/regressions: direct suites added or extended by sessions 1 through 7, plus `test/integration/group_notification_dedupe_integration_test.dart`, `integration_test/foreground_group_push_drain_test.dart`, and the group recovery E2E commands when devices/fixtures are available.
- Likely named gates: `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh transport` if session 4 changed bridge timeout behavior, `./scripts/run_test_gates.sh completeness-check` if gate definitions changed, and `./scripts/run_test_gates.sh group-real-network-nightly` only as fixture-backed release evidence when `FLUTTER_DEVICE_ID` and relay config are available.
- Matrix/closure docs to update when done: `Test-Flight-Improv/test-gate-definitions.md`, `Test-Flight-Improv/52-notification-journey-test-matrix.md`, `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux.md` if the doc-102 closure lineage remains maintained, and this source doc or its closure notes if the improvement-review archive tracks status.
- Dependency on earlier sessions: all implementation sessions.

## Why This Is Not Fewer Sessions

Fewer sessions would bundle unrelated risk: text retry UI is not the same seam as restored-composer id reuse; voice recovery uses `_onRecordStop()` and upload retry behavior; bridge timeout and orphaned pending payloads are no-schema send reliability; local status broadcasts introduce subscription lifecycle behavior; status timestamps require a DB migration; live/replay dedup affects receive concurrency and notifications; final matrix/gate closure validates all earlier work. Collapsing these would make downstream plans too broad and would blur which direct regressions actually prove each fix.

## Why This Is Not More Sessions

The split intentionally groups changes that share the same seam and verification value. Text retry UI keeps its screen/wired call path together. Voice upload retry, durable-prep handling, and re-record id stability stay together because separating them would leave voice in a misleading partially recovered state. Timeout and pending retry-payload fallback both harden the in-doubt send contract without a schema change. The final closure session centralizes matrix and gate edits instead of scattering doc updates through every implementation session.

## Regression And Gate Contract

- `Test-Flight-Improv/14-regression-test-strategy.md` applies by using focused direct regressions for every escaped production bug and by running change-based named gates only where the edited subsystem requires them.
- `Test-Flight-Improv/test-gate-definitions.md` is the execution source of truth for named gates. The stable named group gate is `./scripts/run_test_gates.sh groups` for group send, receive, retry, resume, and listener changes.
- `./scripts/run_test_gates.sh transport` applies to session `timeout-pending-retry` if the downstream plan treats the reliable bridge timeout default as transport-facing.
- `./scripts/run_test_gates.sh completeness-check` applies when a session adds or reclassifies integration, cross-feature, service, lifecycle, resilience, notification, or orchestration test files.
- Nightly/release device suites, including `integration_test/group_recovery_e2e_test.dart`, `integration_test/group_recovery_cli_e2e_test.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, and `./scripts/run_test_gates.sh group-real-network-nightly`, are acceptance evidence when devices and relay config exist. They are not required to be converted into always-run gates by this decomposition.

## Matrix Update Contract

- Primary matrix doc: `Test-Flight-Improv/52-notification-journey-test-matrix.md`.
- Rows to refresh or annotate after implementation evidence lands: `SM-003`, `GMN-001`, `GMN-101`, `GMN-104`, and `JRN-FG-GRP-01`, with explicit text/voice retry and one-notification expectations where appropriate.
- Gate-definition doc: `Test-Flight-Improv/test-gate-definitions.md` must classify any new high-value direct, integration, lifecycle, notification, migration, or simulator test file and keep `./scripts/run_test_gates.sh completeness-check` green.
- Closure lineage: `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux.md` and referenced GIRD closure notes should be updated only if they are still maintained as active closure records. Do not create a new matrix doc.
- Responsible session: `acceptance-doc-closure`.

## Downstream Execution Path

| Session id | Next path |
|---|---|
| `text-retry-ui` | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |
| `text-continuation-id` | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |
| `voice-id-stable-retry` | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |
| `timeout-pending-retry` | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |
| `local-status-broadcasts` | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |
| `status-timestamp-migration` | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |
| `live-replay-dedup` | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |
| `acceptance-doc-closure` | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |

## Structural Blockers Remaining

None. The final arbiter pass accepts the 8-session split as sufficient for downstream planning and execution.

## Accepted Differences Intentionally Left Unchanged

- The optional native early-custody signal from the source doc is intentionally not a session. The timeout bump is the scoped no-wire-contract fix; native custody signaling should require a separate bridge/native contract plan if later chosen.
- Real APNs/TestFlight audible or provider-delivery proof remains residual acceptance evidence, not implementation scope for this source doc.
- The doc-102 three-user incident reproduction may remain blocked if simulator/relay prerequisites are missing; the acceptance session should record concrete blocker evidence rather than reopening implementation scope without a code regression.

## Exact Docs/Files Used As Evidence

- `/Users/I560101/.codex/skills/implementation-session-decomposer/SKILL.md`
- `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/52-notification-journey-test-matrix.md`
- `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux.md`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
- `lib/features/conversation/presentation/widgets/letter_card.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `lib/core/database/helpers/group_messages_db_helpers.dart`
- `lib/main.dart`
- `go-mknoon/node/config.go`
- `go-mknoon/node/pubsub.go`
- Test files named in the session breakdown above.

## Why The Decomposition Is Safe To Send Into Downstream Planning/Execution

Each session has one primary seam, a doc-scoped plan path, direct test families, named-gate expectations, and an explicit dependency boundary. The only schema-bearing work is isolated, the notification matrix update is assigned to one final acceptance session, and later sessions are required to refresh against landed code before they plan or execute.
