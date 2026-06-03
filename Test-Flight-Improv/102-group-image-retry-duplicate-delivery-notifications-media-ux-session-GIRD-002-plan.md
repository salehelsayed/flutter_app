Status: accepted

# 102 GIRD-002 - Sender Retry Ownership Across Composer, Failed-Card, Upload, and Resume Plan

## Planning Progress

| Time | Role | Files inspected since last update | Decision/blocker | Next action |
| --- | --- | --- | --- | --- |
| `2026-05-31 18:02 CEST` | Evidence Collector started | `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-breakdown.md`; `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux.md`; `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-GIRD-001-plan.md`; `git status --short` | Confirmed `GIRD-002` session and intended plan path. `GIRD-001` is accepted in the breakdown ledger; dirty tree includes accepted GIRD-001 changes plus unrelated modified `scripts/check_reliability_simulation_discovery.sh`. No planning blocker. | Inspect GIRD-002 scope, gate docs, owner files, and likely tests. |
| `2026-05-31 18:07 CEST` | Evidence Collector completed / Planner started | GIRD-002 breakdown/source sections; `Test-Flight-Improv/test-gate-definitions.md`; `Test-Flight-Improv/14-regression-test-strategy.md`; group composer/retry/resume owner files and direct tests; small analogous 1:1 restored-draft slice | Current group composer mints a new id after restored media send failure, screen resume does not reload messages/media, failed-card retry skips `upload_pending` rows generically, and retry owners already have partial ordering guards. No blocker. | Draft execution-safe RED-first plan scoped to sender retry ownership. |
| `2026-05-31 18:07 CEST` | Planner completed / Reviewer started | Draft plan sections in this file | Drafted a host-side implementation-ready plan with RED tests for restored composer id reuse, upload-pending failed-card feedback, already-open screen refresh, and retry-owner ordering. No blocker. | Review for missing source coverage, gates, and scope drift. |
| `2026-05-31 18:09 CEST` | Reviewer completed / Arbiter started | Full draft plan; `lib/l10n` file listing; retrier test listing | Reviewer verdict: sufficient with adjustments. Patched stale localization file list, ambiguous retrier test choice, conditional lifecycle command wording, and explicit blocker/fallback interpretation. | Arbiter classifies whether any structural blocker remains. |
| `2026-05-31 18:11 CEST` | Arbiter completed | Final plan in this file | Arbiter verdict: execution-ready. No structural blocker remains; deferred simulator/device proof and durable schema are explicit accepted differences, not hidden scope. | Hand off to implementation executor for GIRD-002 only. |

## Execution Progress

| Time | Phase | Files inspected or touched | Command | Decision/blocker | Next action |
| --- | --- | --- | --- | --- | --- |
| `2026-05-31 18:12 CEST` | Contract extracted | `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-GIRD-002-plan.md`; `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-breakdown.md`; `Test-Flight-Improv/test-gate-definitions.md`; `Test-Flight-Improv/14-regression-test-strategy.md`; `git status --short` | n/a | Execution contract is host-only `GIRD-002`: RED-first sender retry ownership tests, direct preservation tests, `./scripts/run_test_gates.sh groups`, `git diff --check`; `transport` conditional only if transport/app-bootstrap behavior changes. Dirty tree includes accepted `GIRD-001` edits and unrelated `scripts/check_reliability_simulation_discovery.sh`. | Spawn isolated Executor with `model: gpt-5.5`, `reasoning_effort: xhigh`. |
| `2026-05-31 18:13 CEST` | Executor started / owner inspection | `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-GIRD-002-plan.md`; `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-breakdown.md`; `lib/features/groups/presentation/screens/group_conversation_wired.dart`; `lib/features/groups/application/retry_failed_group_messages_use_case.dart`; `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`; `lib/core/services/pending_message_retrier.dart`; `test/features/groups/presentation/group_conversation_wired_test.dart`; `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`; `test/core/services/pending_message_retrier_upload_ordering_test.dart`; `git status --short` | n/a | Confirmed likely GIRD-002 gaps: group composer send always mints a fresh id, failed-card retry delegates upload-pending rows to generic failed retry, and lifecycle resume refreshes group metadata but not message/media state. Existing incomplete-upload and retrier ordering already appear to await/abort correctly. | Add planned RED tests before production edits. |
| `2026-05-31 18:17 CEST` | RED tests added | `test/features/groups/presentation/group_conversation_wired_test.dart`; `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`; `test/core/services/pending_message_retrier_upload_ordering_test.dart`; `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-GIRD-002-plan.md` | n/a | Added planned GIRD-002 tests before production edits: restored composer id reuse, upload-pending failed-card feedback, already-open resume refresh, incomplete-upload late owner abort, and pending retrier async ordering. | Run exact focused RED commands and record failures/unexpected greens. |
| `2026-05-31 18:20 CEST` | Focused RED complete | `test/features/groups/presentation/group_conversation_wired_test.dart`; `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`; `test/core/services/pending_message_retrier_upload_ordering_test.dart` | `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "GIRD-002 restored media composer continuation reuses the failed group row id"`; `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "GIRD-002 upload-pending failed-card retry shows pending feedback without publishing"`; `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "GIRD-002 already-open group screen reflects resume retry status and media refresh"`; `flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart --plain-name "GIRD-002 incomplete-upload retry aborts final send when another owner settled the row"`; `flutter test test/core/services/pending_message_retrier_upload_ordering_test.dart --plain-name "GIRD-002 online group retry sweep awaits incomplete uploads before failed-message retry"` | Expected RED failures observed: restored composer retry produced two rows/two ids; upload-pending failed-card retry showed generic failure instead of pending-upload feedback; already-open screen stayed `failed` after resume. Unexpected greens accepted as preservation: incomplete-upload late abort already emitted `message_status_sent` and did not publish; pending retrier already awaited incomplete group uploads before failed-message retry. | Implement scoped `GroupConversationWired` restored-continuation tracking, upload-pending feedback, and resume message/media refresh. |
| `2026-05-31 18:22 CEST` | Execution child interrupted for tool no-progress | This plan file; current GIRD-002 test deltas | n/a | The first execution child produced useful RED evidence, then stalled after tool errors (`stdin is closed` during wait and an `apply_patch` context miss) without a trustworthy final Executor/QA result. No active `flutter test` process remained. This is a `spawn_or_tool_failure` recovery point, not a product blocker. | Spawn a fresh execution/QA child from the current on-disk state to complete implementation, GREEN gates, and QA verdict. |
| `2026-05-31 18:12 CEST` | Executor spawned | This plan file | n/a | Spawned isolated Executor agent `019e7ecf-864c-7043-9e23-d1b69c1b73cf` with `model: gpt-5.5`, `reasoning_effort: xhigh`. | Wait for Executor result, then verify on-disk code/test/doc evidence before QA. |
| `2026-05-31 18:24 CEST` | Recovery contract extracted / fresh Executor spawning | `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-GIRD-002-plan.md`; `git status --short`; current GIRD-002 RED test deltas | n/a | Continuing from `Focused RED complete` and `Execution child interrupted for tool no-progress`; no replanning and no duplicate RED tests. Scope remains GIRD-002 only. | Spawn fresh isolated Executor with `model: gpt-5.5`, `reasoning_effort: xhigh` to implement and run required GREEN/preservation/gate commands. |
| `2026-05-31 18:24 CEST` | Fresh Executor spawned | This plan file | n/a | Spawned isolated Executor agent `019e7eda-37a2-73b3-b847-c6dbe85de48c` with `model: gpt-5.5`, `reasoning_effort: xhigh`. | Wait for Executor result, then inspect on-disk code/test/doc evidence before spawning QA Reviewer. |
| `2026-05-31 18:26 CEST` | Recovery Executor inspection complete | `git status --short`; `git diff --stat`; `lib/features/groups/presentation/screens/group_conversation_wired.dart`; GIRD-002 tests in `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`, `test/core/services/pending_message_retrier_upload_ordering_test.dart`; `lib/features/groups/application/retry_failed_group_messages_use_case.dart`; `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`; 1:1 restored-draft pattern in `lib/features/conversation/presentation/screens/conversation_wired.dart` | n/a | Confirmed RED tests are already present and should not be duplicated. Current production diff only has a partial GIRD-002 scaffold in `GroupConversationWired` plus accepted GIRD-001 changes elsewhere; unrelated `scripts/check_reliability_simulation_discovery.sh` remains dirty and untouched. | Implement scoped `GroupConversationWired` restored media continuation reuse, upload-pending retry feedback, and resume refresh; add localization copy only if needed for the snackbar. |
| `2026-05-31 18:29 CEST` | Implementation pass complete / focused GREEN starting | `lib/features/groups/presentation/screens/group_conversation_wired.dart`; `lib/l10n/app_en.arb`; `lib/l10n/app_de.arb`; `lib/l10n/app_ar.arb`; generated `lib/l10n/app_localizations*.dart` | `flutter gen-l10n`; `dart format lib/features/groups/presentation/screens/group_conversation_wired.dart lib/l10n/app_localizations.dart lib/l10n/app_localizations_en.dart lib/l10n/app_localizations_de.dart lib/l10n/app_localizations_ar.dart` | Implemented restored media continuation tracking/reuse under original id/timestamp, upload-pending failed-card retry feedback without publishing, mounted screen refresh on app resume and group recovery completion, and localized pending-upload snackbar copy. No changes to retry owner ordering, relay/native, notification, screen, lifecycle, or transport files. | Run required focused GREEN commands, then preservation commands and named gates. |
| `2026-05-31 18:33 CEST` | Fresh Executor no-progress closed / local fallback started | This plan file; `git status --short`; `git diff --stat`; `pgrep -fl "flutter test|dart .*test|run_test_gates"` | `multi_agent_v1.wait_agent` bounded wait twice, then `multi_agent_v1.close_agent 019e7eda-37a2-73b3-b847-c6dbe85de48c` | Fresh Executor made real code/doc progress but never returned a trustworthy final result after the allowed waits. Closed it as `spawn_or_tool_failure`. Local sequential fallback is allowed because the plan remains concrete, the landed changes are on disk, and no hidden partial child state remains; unrelated pre-existing transport census processes are running but are outside GIRD-002 and were not touched. | Continue Executor responsibilities locally: inspect/fix implementation, run required focused GREEN, preservation commands, groups gate, and `git diff --check`, then perform local QA unless a concrete blocker remains. |
| `2026-05-31 18:34 CEST` | Local fallback implementation cleanup | `lib/features/groups/presentation/screens/group_conversation_wired.dart` | `dart format lib/features/groups/presentation/screens/group_conversation_wired.dart` | Removed temporary debug logging and over-broad failed-media polling from the interrupted Executor landing; kept scoped refresh on app resume and group recovery completion. | Run required focused GREEN commands. |
| `2026-05-31 18:36 CEST` | Focused GREEN complete | `lib/features/groups/presentation/screens/group_conversation_wired.dart`; `test/features/groups/presentation/group_conversation_wired_test.dart`; `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`; `test/core/services/pending_message_retrier_upload_ordering_test.dart` | `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "GIRD-002"`; `flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart --plain-name "GIRD-002"`; `flutter test test/core/services/pending_message_retrier_upload_ordering_test.dart --plain-name "GIRD-002"` | All focused GIRD-002 tests passed after one local fallback fix to let the resume-refresh widget test await lifecycle-triggered async repository/media hydration. | Run required preservation commands, then `./scripts/run_test_gates.sh groups` and `git diff --check`. |
| `2026-05-31 18:38 CEST` | Direct preservation complete | `test/features/groups/presentation/group_conversation_wired_test.dart`; `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`; `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`; `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`; `test/core/services/pending_message_retrier_upload_ordering_test.dart`; `test/features/groups/application/send_group_message_use_case_test.dart`; `test/features/groups/application/handle_incoming_group_message_use_case_test.dart` | Plan-listed preservation commands for restored composer, failed-card retry targeting, upload-pending skipped by failed retry owner, incomplete-upload guards, lifecycle/retrier ordering, and `GIRD-001` send/incoming replay | All preservation commands passed. | Run `./scripts/run_test_gates.sh groups`, then `git diff --check`; record conditional gate skips. |
| `2026-05-31 18:40 CEST` | Named gates complete / QA complete / final verdict written | `lib/features/groups/presentation/screens/group_conversation_wired.dart`; `lib/l10n/app_*.arb`; generated `lib/l10n/app_localizations*.dart`; GIRD-002 direct tests; this plan file | `./scripts/run_test_gates.sh groups`; `flutter gen-l10n`; `git diff --check`; rerun `flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart --plain-name "GIRD-002"` after formatter changed that test only | `groups` gate passed (`00:54 +313: All tests passed!`), `git diff --check` passed, l10n generation completed, and local QA found no blocking issues. `transport` skipped because no bridge/startup/reconnect/app-bootstrap/device-backed transport behavior changed. Lifecycle GIRD-002 command skipped because `handle_app_resumed.dart` was unchanged and no lifecycle GIRD-002 test was added; existing lifecycle ordering preservation passed. Screen-specific commands skipped because `group_conversation_screen.dart` was unchanged. | Final verdict: `accepted`; no blockers or non-blocking follow-ups remain for GIRD-002. |

## real scope

GIRD-002 changes only sender-side group retry ownership and the already-open group conversation refresh surface.

In scope:

- A restored group media composer continuation for the same failed user-intended send must not mint a new group message id when the user retries without materially changing the draft, quote, or attachment set.
- Dedicated failed-card retry must continue to target only the selected failed media row.
- If the selected failed-card row still has `upload_pending` media, the retry action must not silently no-op or publish a second logical send; it must give truthful feedback and leave ownership with the incomplete-upload retry path.
- Resume and pending-message recovery must keep incomplete-upload retry ahead of failed-message retry, and must not let both owners publish the same logical group image in one sweep.
- An already-open `GroupConversationWired` for the affected group must observe sender status/media changes caused by resume/background retry without requiring close/reopen.

Out of scope:

- Recipient logical dedupe for distinct reminted ids, attachment movement on recipient rows, relay/native inbox idempotency, notification identity/suppression, media unavailable placeholder copy, and simulator/device incident acceptance. Those are `GIRD-003` through `GIRD-007`.
- New persistent schema for durable composer drafts or a broad logical-send-id architecture. If the current sender row and attachment state are not enough to safely continue in place, stop and replan instead of adding schema in this session.

## closure bar

Good enough for GIRD-002 means every sender retry surface converges on one original sender row/message id when the user is continuing the same failed group image send, while intentional edited/new sends can still create a new row.

Coverage ledger for the exact GIRD-002 scope:

| Requirement from breakdown | Required proof |
| --- | --- |
| failed-card retry, restored composer continuation, app resume recovery, pending-message retrier recovery, and incomplete-upload retry converge on one logical group image send | New `GIRD-002` widget/use-case tests plus existing retry-order tests prove one sender row/id for restored composer retry, selected failed-card retry, and ordered resume/retrier sweeps |
| prevent restored composer send from minting a fresh recipient-visible message id for the same failed/in-doubt user-intended image send | New RED widget test proves a restored media composer retry reuses the original failed row id and publish payload id instead of creating a second row |
| handle retry while media is still `upload_pending` with truthful feedback and no silent no-op | New RED widget test proves failed-card retry on `upload_pending` media does not publish, shows specific pending/preparing feedback, and leaves the row retry-owned |
| prevent incomplete-upload retry and failed-message retry from both sending the same logical image during the same recovery sweep | New or preserved `retry_incomplete_group_uploads_use_case_test.dart` and retrier/lifecycle ordering tests prove failed retry observes the post-upload owner state and does not publish the same id twice |
| ensure already-open group conversation screens observe background/resume retry status and media changes without close/reopen | New RED widget test proves a mounted `GroupConversationWired` refreshes the affected row/media after resume/retry state changes |
| preserve dedicated failed-card retry targeting only the selected failed media row | Existing targeted failed-card widget/use-case tests stay green; add `GIRD-002` assertion only if the restored-continuation changes touch this path |

## source of truth

- Primary session contract: `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-breakdown.md`, Session `GIRD-002`.
- Source incident/spec context: `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux.md`, limited to sender retry, restored composer, upload-pending, resume, and already-open screen edge cases.
- Dependency baseline: `GIRD-001` accepted in the breakdown ledger and in `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-GIRD-001-plan.md`.
- Gate source of truth: `Test-Flight-Improv/test-gate-definitions.md`; if it disagrees with `./scripts/run_test_gates.sh`, the script wins.
- Current code/tests beat stale prose. Do not revert accepted `GIRD-001` changes or the unrelated modified `scripts/check_reliability_simulation_discovery.sh`.

## session classification

`accepted`

The dependency is satisfied because the breakdown ledger marks `GIRD-001` accepted. This is not acceptance-only: current evidence shows sender UI/retry code needs regressions and likely implementation.

## exact problem statement

After a group image send fails or appears failed, the sender has several retry surfaces that can act on the same user-intended image: restored composer send, failed-card retry, app resume recovery, pending-message retrier, and incomplete-upload retry. Current group composer behavior generates a fresh id for a restored media draft, so continuing the same send can create another recipient-visible logical message. Current already-open group screens listen for group listener events but do not reload message/media state on resume retry completion. Current failed-card retry skips `upload_pending` media rows through the failed-message owner and reports only generic failure.

GIRD-002 must make those sender surfaces converge on the original row/id when the user is continuing the same send, while preserving intentional separate sends and the accepted `GIRD-001` in-doubt `pending` behavior.

## files and repos to inspect next

Production entry files:

- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- `lib/core/lifecycle/handle_app_resumed.dart`
- `lib/core/services/pending_message_retrier.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`
- `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`, `lib/l10n/app_ar.arb`, and generated localization files if new user-visible pending-upload retry copy is required by the existing localization workflow

Direct tests:

- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart`
- `test/core/services/pending_message_retrier_test.dart`
- `test/core/services/pending_message_retrier_upload_ordering_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`

Dependency context only:

- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`

## existing tests covering this area

- `group_conversation_wired_test.dart` already covers ordinary media durable pre-persist, upload failure restoring composer/quote, publish failure restoring composer/attachments, cancel terminalizing durable pending rows, zero-peer success not restoring the draft, and failed-card retry targeting only one selected failed media row.
- `retry_failed_group_messages_use_case_test.dart` already covers failed text retry in place, failed media retry from persisted done attachments, retry order by persisted timestamp/id, skipping `upload_pending` media rows, and `retryFailedGroupMessage` targeting only the requested failed row.
- `retry_incomplete_group_uploads_use_case_test.dart` already covers the same-isolate in-flight guard, fresh `sending` parent skip, re-upload of pending group media with stable blob id, transient terminalization, and late final-send abort when the parent row disappears or is no longer eligible.
- `handle_app_resumed_group_recovery_test.dart` already covers group resume ordering: rejoin, drain, recover stuck, incomplete upload retry, failed-message retry, then failed-inbox retry.
- `pending_message_retrier_upload_ordering_test.dart` already covers online sweep ordering across group and 1:1 retry callbacks.
- `group_resume_recovery_test.dart` already has host fake-network coverage for failed-message retry after recovery, caller-supplied id survival through retry, unread correctness across retry recovery, and related resume/retry preservation.
- `GIRD-001` tests already prove reliable timeout and reliable publish-zero-peers/no-custody are non-failed `pending` sender rows, and same-id own replay can repair failed rows with retry evidence.

Missing coverage:

- No group widget test proves restored media composer continuation reuses the original failed row id.
- No group widget test proves a mounted already-open screen refreshes retry status/media after resume/background retry without close/reopen.
- No group widget test gives a specific `upload_pending` failed-card retry proof.
- Retry-owner ordering has preservation coverage, but needs a GIRD-002-labeled proof or explicit green preservation command tied to this session.

## regression/tests to add first

Add these tests before production changes and run the exact focused RED commands. If a planned test unexpectedly passes, record why in the plan progress and do not add unnecessary implementation for that seam.

1. `test/features/groups/presentation/group_conversation_wired_test.dart`
   - Test name: `GIRD-002 restored media composer continuation reuses the failed group row id`
   - Shape: seed a group, attach one image, make first publish fail after upload succeeds, assert the composer restores. Send the unchanged restored draft. Expected after fix: one sender row for that text, original failed id reused, final status `sent`, and all `group:publish` payloads for the continuation use the original message id. Expected current RED: second send mints a fresh id / leaves two rows.

2. `test/features/groups/presentation/group_conversation_wired_test.dart`
   - Test name: `GIRD-002 upload-pending failed-card retry shows pending feedback without publishing`
   - Shape: render a failed outgoing group media row with a persisted `upload_pending` attachment. Invoke `onRetryFailedMedia` for that message. Expected after fix: no `group:publish`, row/media remain visible and retry-owned, and the snackbar copy says the media is still preparing/uploading or will continue retrying. Expected current RED: generic failed retry feedback.

3. `test/features/groups/presentation/group_conversation_wired_test.dart`
   - Test name: `GIRD-002 already-open group screen reflects resume retry status and media refresh`
   - Shape: render a failed outgoing media row, mutate the repositories as resume retry would after successful retry under the same id (`status: sent`, hydrated done attachment), trigger `tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed)` or the concrete recovery-completion hook added by the implementation, and assert the mounted screen now shows the row as non-failed with refreshed media without rebuilding the route. Expected current RED: screen remains stale until `_loadMessages`/route reopen.

4. `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
   - Test name: `GIRD-002 incomplete-upload retry aborts final send when another owner settled the row`
   - Shape: while retryIncompleteGroupUploads is between upload completion and final send, mutate the parent row to `sent`/non-failed. Expected: no final `group:publish` from incomplete-upload retry, count `0`, and an abort event/reason for non-eligible status. If current `_lateGroupSendAbortReason` already passes, keep it as a preservation proof.

5. `test/core/services/pending_message_retrier_upload_ordering_test.dart`
   - Test name: `GIRD-002 online group retry sweep awaits incomplete uploads before failed-message retry`
   - Shape: make `retryIncompleteGroupUploadsFn` async-gated and assert `retryFailedGroupMessagesFn` is not called until the upload gate completes. This proves the same sweep cannot start the failed owner while upload owner is still running. If existing ordering already covers it, add the GIRD-labeled stricter async gate or document the accepted green preservation.

6. `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
   - Test name: `GIRD-002 resume group retry awaits incomplete uploads before failed-message retry`
   - Shape: same as the retrier proof, but through `handleAppResumed`. Required only if implementation changes `handle_app_resumed.dart`; otherwise run the existing ordering test as preservation.

## step-by-step implementation plan

1. Add and run the RED tests above before production edits.
2. In `GroupConversationWired`, add a small restored-continuation tracker modeled on the existing 1:1 restored-failed-draft pattern, but scoped to group sends and media:
   - Track original failed `messageId`, timestamp, draft text, quoted id, and an attachment fingerprint for restored composer state.
   - Set the tracker when `_restoreComposerSnapshot(...)` restores a failed outgoing group send that still represents a retryable row.
   - Clear the tracker when the draft text, quote, attachment set, group, or selected files materially change.
3. Before `_onSend` mints a new id, check whether the current composer still matches the restored-continuation tracker:
   - If the original row has already become `sent` or `pending` because resume/replay settled it, refresh the row/media, clear the composer/tracker, and do not send another row.
   - If the original row is still `failed`, continue the send using the original `messageId` and timestamp instead of `_uuid.v4()`.
   - For existing stale attachment rows under that id, remove only rows owned by the restored continuation before writing new durable pending rows, or use the already-persisted done attachments through `retryFailedGroupMessage` when that is safer. Do not leave duplicate attachment rows under one message id.
4. In `_onRetryFailedMedia`, inspect persisted attachments for the selected row before calling `retryFailedGroupMessage`:
   - If any attachment is `upload_pending`, do not call the failed-message owner and do not publish. Show specific feedback that upload/preparation is still retry-owned.
   - If attachments are retryable `done`, call `retryFailedGroupMessage` exactly for that `messageId` and refresh only that row/media, preserving the existing selected-row behavior.
5. Tighten incomplete-upload and failed-message ownership only as tests require:
   - Prefer existing `_retryIncompleteGroupUploadsInFlight`, `_lateGroupSendAbortReason`, and ordered awaits.
   - Add no global queue or new scheduler unless the RED tests prove the current guards cannot prevent double publish.
6. Refresh already-open group screens after resume/background recovery:
   - Prefer the smallest `GroupConversationWired` refresh hook that reloads current messages/media for the active group after resume/recovery state changes.
   - Preserve scroll offset behavior and avoid rebuilding the whole route.
   - If the fix requires changing `handleAppResumed` or `PendingMessageRetrier`, keep the change to callback ordering/refresh signaling only and run the lifecycle/retrier preservation commands.
7. Keep `GIRD-001` behavior intact:
   - Do not show failed-card retry for `pending` in-doubt reliable sends.
   - Do not convert reliable timeout or zero-peer/no-custody `pending` rows back to `failed`.
   - Do not break same-id own replay repair of failed rows with retry evidence.
8. Stop if the only safe implementation needs a persistent logical-send-id schema or recipient-side dedupe; that belongs outside GIRD-002 and must be replanned rather than smuggled into this session.

## risks and edge cases

- Reusing a restored id after the user materially edits text, quote, or attachments could collapse an intentional separate send. Clear continuation tracking on material edits.
- Reusing a restored id while stale failed/upload_failed attachment rows remain could make media appear duplicated or unavailable under one message. Tests must inspect attachment rows for the reused id.
- Background resume may settle the original row while the restored composer is still visible. The send button must refresh and clear instead of publishing a new row.
- `upload_pending` failed-card retry must not be a silent no-op and must not call the wrong owner.
- Existing `GIRD-001` `pending` rows are in-doubt, not failed. They should not be pulled into failed-card retry.
- Lifecycle/pending retrier sweeps can overlap conceptually. Prefer existing in-flight guards and ordered awaits; add only the minimum guard proven necessary.

## Device/Relay Proof Profile

GIRD-002 is host-only for execution closure in this breakdown. It mentions group messaging, lifecycle resume, and sender recovery, but this session owns deterministic Flutter sender/UI/retry seams that are directly provable with host tests under `test/`.

No simulator, real-network relay, multi-relay, three-party, OS-notification, or `integration_test/` proof is required to close GIRD-002. The three-user incident, recipient device rows, real relay behavior, and `$run-flutter-reliability-sims` group acceptance proof are deferred to `GIRD-007` by the breakdown.

Deferred final acceptance profile for `GIRD-007`:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only <GIRD-007 group image retry incident scenario>
```

Host lifecycle proof is required through the direct `test/core/lifecycle` and `test/core/services` commands below. `./scripts/run_test_gates.sh transport` is required only if implementation changes bridge startup, reconnect, real transport fallback, app bootstrap, or device-backed `integration_test/` transport behavior; if required, run it with a concrete simulator/device id:

```bash
FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport
```

## exact tests and gates to run

Focused RED commands before production edits:

```bash
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "GIRD-002 restored media composer continuation reuses the failed group row id"
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "GIRD-002 upload-pending failed-card retry shows pending feedback without publishing"
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "GIRD-002 already-open group screen reflects resume retry status and media refresh"
flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart --plain-name "GIRD-002 incomplete-upload retry aborts final send when another owner settled the row"
flutter test test/core/services/pending_message_retrier_upload_ordering_test.dart --plain-name "GIRD-002 online group retry sweep awaits incomplete uploads before failed-message retry"
```

Add and run this RED command only if `handle_app_resumed.dart` changes:

```bash
flutter test test/core/lifecycle/handle_app_resumed_group_recovery_test.dart --plain-name "GIRD-002 resume group retry awaits incomplete uploads before failed-message retry"
```

Focused GREEN after implementation:

```bash
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "GIRD-002"
flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart --plain-name "GIRD-002"
flutter test test/core/services/pending_message_retrier_upload_ordering_test.dart --plain-name "GIRD-002"
```

If `handle_app_resumed.dart` changes or the lifecycle GIRD-002 test is added, also run:

```bash
flutter test test/core/lifecycle/handle_app_resumed_group_recovery_test.dart --plain-name "GIRD-002"
```

If `group_conversation_screen.dart` changes, also run:

```bash
flutter test test/features/groups/presentation/group_conversation_screen_test.dart --plain-name "failed outgoing media rows show retry and delete controls"
flutter test test/features/groups/presentation/group_conversation_screen_test.dart --plain-name "incoming, text-only, and read-only announcement rows do not show failed-media controls"
```

Direct preservation commands:

```bash
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "publish failure restores quote draft and attachments"
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "ordinary media upload failure persists failed parent state and restores composer and quote"
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "retry control re-sends only the targeted failed outgoing media row"
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "sending a message with zero topic peers keeps the row sent and does not restore the draft"
flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart --plain-name "skips rows whose persisted media attachments are still upload_pending"
flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart --plain-name "retryFailedGroupMessage only retries the requested failed media row"
flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart --plain-name "retries a failed media row from persisted done attachments when inboxRetryPayload was cleared after inbox success"
flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart --plain-name "returns 0 for overlapping same-isolate retry while first upload is in flight"
flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart --plain-name "skips fresh outgoing sending parent before upload or publish"
flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart --plain-name "skips the final group send when the parent row is deleted after uploads complete"
flutter test test/core/lifecycle/handle_app_resumed_group_recovery_test.dart --plain-name "calls rejoin, drain, recoverStuck, retryIncompleteGroupUploads, retryFailed, then retryFailedGroupInboxStores"
flutter test test/core/services/pending_message_retrier_upload_ordering_test.dart --plain-name "online sweep runs rejoin, drain, group retries, shared 1:1 retries, then group inbox retry"
flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "GIRD-001"
flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name "GIRD-001"
```

Named gates and whitespace:

```bash
./scripts/run_test_gates.sh groups
git diff --check
```

Conditional gates:

```bash
FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport
```

Run `transport` only if bridge/startup/reconnect/app-bootstrap/real transport behavior changes. If only `GroupConversationWired`, group retry use cases, host lifecycle ordering tests, or localization copy change, direct host tests plus `groups` are the closure gates.

## known-failure interpretation

- Treat any new failure in the focused GIRD-002 tests, listed preservation tests, `GIRD-001` preservation tests, `./scripts/run_test_gates.sh groups`, or `git diff --check` as blocking unless proven unrelated by an unchanged pre-existing failure.
- `Test-Flight-Improv/test-gate-definitions.md` records a pre-existing `completeness-check` issue from 2026-05-28 for three unclassified files. Do not run or classify `completeness-check` for this session unless implementation adds a new test file outside the already classified/direct-suite pattern; if it is run and fails only on the recorded three files, do not treat that as a GIRD-002 regression.
- If `transport` is conditionally required and no simulator/device is available, classify the transport proof as environment-blocked and do not claim device-backed closure. Host-only GIRD-002 can still be execution-complete if no transport code was changed.

## blocker/fallback interpretation

- If the RED restored-composer test cannot be fixed without adding durable schema or a broad logical-send-id architecture, stop and mark the session `prerequisite-blocked`; do not implement schema in GIRD-002.
- If the restored row is already `sent` or `pending` when the user presses Send again, the correct fallback is to refresh and clear the restored composer, not to publish a new row.
- If stale attachment cleanup for reused ids would risk deleting media for a different logical send, stop and narrow the continuation match instead of deleting broadly.
- If the already-open screen refresh hook cannot reliably observe background/retry completion from host code, keep the host refresh proof honest and defer real app-instance timing proof to `GIRD-007`; do not claim simulator/device closure here.

## done criteria

- All planned RED tests were added before production edits and either failed for the expected current gap or were documented as already-covered preservation.
- Restored unchanged group media composer continuation no longer creates a fresh message id for the same failed user-intended send.
- Failed-card retry on `upload_pending` media gives truthful feedback, does not publish, and leaves retry ownership with incomplete-upload recovery.
- Failed-card retry on completed failed media still targets only the selected row and can settle it in place.
- Resume/pending retrier ordering prevents incomplete-upload and failed-message owners from both publishing the same logical image in one sweep.
- Already-open group conversation UI refreshes status/media after resume/background retry under the same id.
- Accepted `GIRD-001` behavior remains green: reliable timeout and reliable zero-peer/no-custody stay non-failed `pending`, and same-id own replay repair remains intact.
- Required direct tests, `./scripts/run_test_gates.sh groups`, and `git diff --check` pass, with conditional `transport` handled per the profile above.

## scope guard

Do not:

- Add a broad logical-send-id schema, new database migration, or recipient dedupe key in GIRD-002.
- Collapse distinct intentional sends of the same image after the user edits the draft/attachments or after a previous send is already clearly complete.
- Modify relay-server/native inbox storage, notification dedupe, Android/iOS notification presentation, or recipient replay behavior.
- Revert or weaken accepted `GIRD-001` pending/in-doubt semantics.
- Run destructive git commands or revert unrelated dirty files, especially `scripts/check_reliability_simulation_discovery.sh`.

## accepted differences / intentionally out of scope

- Host tests prove sender id/row convergence and UI refresh, not full B/C recipient duplicate suppression. Recipient logical dedupe is `GIRD-003`; relay/native inbox idempotency is `GIRD-004`; notification identity is `GIRD-006`; full incident acceptance is `GIRD-007`.
- Close/reopen recovery is covered here through persisted failed/upload-pending rows and retry owners. Durable composer-draft restoration across process death is not added unless an existing route contract already supplies the original message id; otherwise it is a separate schema/product decision.
- Same-message-id live pubsub plus inbox replay remains a preservation behavior from existing tests, not the primary duplicate-row mechanism for GIRD-002.

## reviewer sufficiency review

- Source coverage is sufficient for execution: the plan ties back to the breakdown, source doc, accepted `GIRD-001`, gate docs, owner files, and direct tests without expanding into recipient/relay/notification sessions.
- The exact RED tests are executable and ordered before production edits. Preservation tests and named gates are explicit, with conditional lifecycle/screen/transport commands where ownership files actually change.
- The implementation path avoids overengineering by preferring existing group retry owners, in-flight guards, and a small restored-continuation tracker. Schema, recipient dedupe, and notification work are explicitly out of scope.
- Assumptions are explicit: `GIRD-001` is accepted, `GIRD-002` is host-only, simulator/device incident proof is deferred to `GIRD-007`, and `transport` is required only if transport/app-bootstrap code changes.

## arbiter decision

No structural blocker remains. The remaining implementation choices are incremental and executor-owned: the exact UI refresh hook for already-open screens, whether some retry-order tests land as newly RED or preservation-green, and the safest narrow cleanup for stale attachment rows when reusing a restored id.

The plan is execution-ready for GIRD-002 only. If execution proves restored composer id reuse requires durable schema or a broad logical-send-id architecture, that is a prerequisite blocker and must be replanned outside this session.

## execution verdict

Final verdict: `accepted`

Spawned-agent isolation used: yes. Fresh Executor agent `019e7eda-37a2-73b3-b847-c6dbe85de48c` was spawned with `model: gpt-5.5`, `reasoning_effort: xhigh`.

Local sequential fallback used: yes. The fresh Executor made code/doc progress but did not return a trustworthy final result after the bounded waits, so it was closed as `spawn_or_tool_failure` and the allowed local fallback completed Executor verification plus QA in this isolated execution context.

QA verdict: no blocking issues. Scope stayed within GIRD-002 sender retry ownership and already-open group screen refresh. GIRD-001 edits in the dirty tree were preserved, and the unrelated modified `scripts/check_reliability_simulation_discovery.sh` was not edited.

Implementation completed:

- Restored group media composer continuation now tracks the failed row and reuses its original `messageId`/timestamp when draft, quote, group, and attachment fingerprint still match.
- If that restored row was already settled to non-failed before the user presses Send, the screen refreshes the row/media and clears the restored composer instead of publishing a new row.
- Upload-pending failed-card retry now shows localized pending-upload feedback, refreshes the row/media, does not call the failed-message retry owner, and does not publish.
- Already-open `GroupConversationWired` reloads messages/media on app resume and after group recovery gate completion.

Focused GREEN commands passed:

```bash
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "GIRD-002"
flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart --plain-name "GIRD-002"
flutter test test/core/services/pending_message_retrier_upload_ordering_test.dart --plain-name "GIRD-002"
```

Required preservation commands passed:

```bash
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "publish failure restores quote draft and attachments"
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "ordinary media upload failure persists failed parent state and restores composer and quote"
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "retry control re-sends only the targeted failed outgoing media row"
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "sending a message with zero topic peers keeps the row sent and does not restore the draft"
flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart --plain-name "skips rows whose persisted media attachments are still upload_pending"
flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart --plain-name "retryFailedGroupMessage only retries the requested failed media row"
flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart --plain-name "retries a failed media row from persisted done attachments when inboxRetryPayload was cleared after inbox success"
flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart --plain-name "returns 0 for overlapping same-isolate retry while first upload is in flight"
flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart --plain-name "skips fresh outgoing sending parent before upload or publish"
flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart --plain-name "skips the final group send when the parent row is deleted after uploads complete"
flutter test test/core/lifecycle/handle_app_resumed_group_recovery_test.dart --plain-name "calls rejoin, drain, recoverStuck, retryIncompleteGroupUploads, retryFailed, then retryFailedGroupInboxStores"
flutter test test/core/services/pending_message_retrier_upload_ordering_test.dart --plain-name "online sweep runs rejoin, drain, group retries, shared 1:1 retries, then group inbox retry"
flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "GIRD-001"
flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name "GIRD-001"
```

Named gates and format/generation checks passed:

```bash
./scripts/run_test_gates.sh groups
flutter gen-l10n
git diff --check
```

Conditional gates skipped:

- `./scripts/run_test_gates.sh transport`: skipped because no bridge/startup/reconnect/app-bootstrap/device-backed transport behavior changed.
- `flutter test test/core/lifecycle/handle_app_resumed_group_recovery_test.dart --plain-name "GIRD-002"`: skipped because `lib/core/lifecycle/handle_app_resumed.dart` was unchanged and no lifecycle GIRD-002 test was added.
- `group_conversation_screen_test.dart` failed-media control commands: skipped because `lib/features/groups/presentation/screens/group_conversation_screen.dart` was unchanged.

Blocking issues remaining: none.

Non-blocking follow-ups deferred: none for GIRD-002.

## dependency impact

- `GIRD-003` depends on GIRD-002 preserving a stable sender-side message id for a continued logical send, so recipient dedupe can reason about sender identity without compensating for avoidable restored-composer remints.
- `GIRD-004` depends on sender retry owners not double-publishing the same logical image while relay/native idempotency is evaluated.
- `GIRD-006` notification identity should not be planned until GIRD-002 and GIRD-003 clarify which ids can represent one logical image send.
- `GIRD-007` final simulator/device acceptance must rerun the incident against the complete chain. If GIRD-002 cannot safely converge restored composer and retry owners without new schema, downstream sessions should pause and the breakdown should be revised before continuing.
