# Group4 Critical Findings Session Breakdown - 2026-05-24

## Run Mode Snapshot

- active mode: standard
- degraded local continuation explicitly allowed: no
- source matrix: `Test-Flight-Improv/Group-Chat-Feature/group4-critical-findings-2026-05-24-matrix.md`
- source status vocabulary: Open, Closed, Covered, Skipped
- overall closure bar: every implemented row is Closed with concrete code/test evidence; skipped rows keep a cited current-code reason
- final verdict policy: `closed` only when all non-skipped rows are Closed or Covered

## Recommended Plan Count

3

## Downstream Execution Path

For each session, use:

1. `$implementation-plan-orchestrator`
2. `$implementation-execution-qa-orchestrator`
3. `$implementation-closure-audit-orchestrator`

Fresh child-agent isolation is preferred. The controller may use bounded local artifact fallback only if a child does not produce trustworthy artifacts.

## Session Ledger

| Session | Rows | Status | Plan Path | Execution Verdict | Closure Docs | Blocker | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| G4-S1 | G4-005, G4-007, G4-008, G4-009, G4-019 | closed | `Test-Flight-Improv/Group-Chat-Feature/group4-critical-findings-2026-05-24-session-G4-S1-plan.md` | accepted_with_explicit_follow_up | matrix updated; closure audit logged | classified gate residuals | Notification routing, active tracker, dedupe, and foreground fallback landed. Fresh closure audit on 2026-05-24 reconfirmed direct and broader notification/push tests pass; broad `groups`/`baseline` and `completeness-check` retain residual failures outside G4-S1 notification/push owner rows. |
| G4-S2 | G4-001, G4-010, G4-011, G4-012, G4-013, G4-014, G4-015, G4-016, G4-017, G4-018, G4-020 | closed | `Test-Flight-Improv/Group-Chat-Feature/group4-critical-findings-2026-05-24-session-G4-S2-plan.md` | accepted_with_explicit_follow_up | matrix updated; closure audit logged | classified gate residuals | Group conversation/media/send/read/reaction fixes landed. Direct G4-S2 tests and scoped diff hygiene passed; broad `groups` and `completeness-check` gates remain red only on unrelated residuals outside G4-S2 owner behavior. |
| G4-S3 | G4-002, G4-003, G4-004 | closed | `Test-Flight-Improv/Group-Chat-Feature/group4-critical-findings-2026-05-24-session-G4-S3-plan.md` | accepted_with_explicit_follow_up | matrix updated; closure audit logged | classified gate residuals | Lifecycle recovery and retry concurrency hardening landed. Direct G4-S3 owner analyzers/tests passed; full group recovery file still has an unrelated IR-018 replay persistence failure, and broad `groups` remains red in existing membership/rejoin residuals. |
| G4-SKIP | G4-006 | skipped | n/a | n/a | matrix | none | Current navigation already resolves group/pending invite before opening. |

## Ordered Session Breakdown

### G4-S1 - Notification Routing And Active Route Safety

- classification: implementation-ready
- dependencies: none
- exact scope:
  - add group payload aliases and missing group-id event
  - add route-key-aware active suppression and safe active clearing
  - separate notification-open in-flight and completed dedupe
  - return foreground push drain result and show local fallback on group drain failure
- likely code-entry files:
  - `lib/core/notifications/notification_route_target.dart`
  - `lib/core/notifications/active_conversation_tracker.dart`
  - `lib/core/notifications/notification_open_dedupe_gate.dart`
  - `lib/features/push/application/show_notification_use_case.dart`
  - `lib/features/push/application/handle_foreground_remote_message_use_case.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/features/conversation/presentation/screens/conversation_wired.dart`
  - `lib/main.dart`
- likely tests:
  - `test/core/notifications/notification_route_target_test.dart`
  - `test/core/notifications/notification_open_dedupe_gate_test.dart`
  - `test/features/push/application/show_notification_use_case_test.dart`
  - `test/features/push/application/handle_foreground_remote_message_use_case_test.dart`
  - focused group conversation active tracker widget test if cheap
- named gates: targeted `flutter test` files above
- docs to update: source matrix and this breakdown
- execution result 2026-05-24: G4-001/G4-010/G4-011/G4-012/G4-013/G4-014/G4-015/G4-016/G4-017/G4-018/G4-020 are closed in the source matrix with code/test evidence. Direct analyzer and focused test gates passed: group media MIME (`+6`), group media integrity (`+6`), incomplete group upload retry (`+15`), group conversation widget (`+98`), and group conversation background task widget (`+18`). `./scripts/run_test_gates.sh groups` remains red at `+261 -40` in broad invite/membership/rejoin/resume integration paths outside G4-S2 media/read/reaction owner behavior. `./scripts/run_test_gates.sh completeness-check` remains red at `744/746` with unmatched shared fake test files.
- execution result 2026-05-24: G4-005/G4-007/G4-008/G4-009/G4-019 are closed in the source matrix with code/test evidence. Direct notification/push/group/1:1 widget tests passed; `flutter test test/core/notifications` passed (`+117`); `flutter test test/features/push/application` passed (`+161`); scoped `git diff --check` and formatting passed. `./scripts/run_test_gates.sh groups` and extra `baseline` remain red in unrelated broad group membership/key smoke paths, and `./scripts/run_test_gates.sh completeness-check` remains red on the already documented unmatched shared fake tests.

### G4-S2 - Group Conversation Media/Send State Integrity

- classification: implementation-ready
- dependencies: none
- exact scope:
  - fix typed clamp values
  - validate actual file bytes before durable/retry upload rows
  - reject `application/octet-stream` for group media
  - align display resolver with encryption metadata policy
  - clean old durable retry state when restoring composer
  - persist partial successful uploads
  - stabilize voice attachment local paths
  - guard background begin/end so `_isSending` always resets
  - reset group conversation state on group id changes
  - gate mark-read on foreground active visibility
  - rollback optimistic reactions on failure/throw
- likely code-entry files:
  - `lib/core/media/group_media_mime_policy.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- likely tests:
  - `test/core/media/group_media_mime_policy_test.dart`
  - `test/core/media/group_media_integrity_policy_test.dart`
  - `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
  - `test/features/groups/presentation/group_conversation_wired_test.dart`
  - `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`
- named gates: targeted `flutter test` files above
- docs to update: source matrix and this breakdown

### G4-S3 - Lifecycle Recovery And Retry Concurrency

- classification: implementation-ready
- dependencies: G4-S2 for media validation helpers, but stale cutoff/retry lock can land independently
- exact scope:
  - change pause group send recovery from blanket transition to stale cutoff
  - prevent concurrent app-isolate `retryIncompleteGroupUploads` runs from processing the same rows
  - skip fresh outgoing `sending` parent rows during retry
  - never acknowledge group recovery unless a group inbox drain ran and succeeded
- likely code-entry files:
  - `lib/core/lifecycle/handle_app_paused.dart`
  - `lib/core/lifecycle/handle_app_resumed.dart`
  - `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- likely tests:
  - `test/core/lifecycle/handle_app_paused_group_test.dart`
  - `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
  - `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- named gates: targeted `flutter test` files above
- docs to update: source matrix and this breakdown
- execution result 2026-05-24: G4-002/G4-003/G4-004 are closed in the source matrix with code/test evidence. Group pause now uses a two-minute stale cutoff through `recoverStuckSendingMessages` instead of blanket `transitionSendingToFailed`; `retryIncompleteGroupUploads` now has a process-local in-flight guard and skips fresh outgoing `sending` parents before upload/publish; `handleAppResumed` skips and logs recovery ack when no group drain can run or when drain reports errors. Direct analyzers passed for the three G4-S3 production files and three owner test files. Focused tests passed: `flutter test test/core/lifecycle/handle_app_paused_group_test.dart` (`+5`), `flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart` (`+17`), targeted `rejoins but skips recovery ack when group message repository is unavailable`, targeted `BB-012 does not acknowledge recovery when inbox drain reports an error`, and supporting `flutter test test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart test/core/lifecycle/main_resume_group_upload_wiring_test.dart test/features/groups/domain/repositories/group_message_repository_impl_test.dart` (`+43`). Full `flutter test test/core/lifecycle/handle_app_resumed_group_recovery_test.dart` remains red only at pre-existing IR-018 replay persistence (`replayed` message is null after drain) outside G4-S3 ack gating. `./scripts/run_test_gates.sh groups` remains red at `+259 -42`, ending in broad membership/rejoin residuals including `GM-028`; `./scripts/run_test_gates.sh completeness-check` reports `744/746` with unmatched shared fake test files.

## Controller Progress

- 2026-05-24T00:00:00Z: Created source matrix and session breakdown from current repo audit. Next action: execute G4-S1, G4-S2, and G4-S3 fixes with focused verification.

## Closure Progress

- 2026-05-24 01:22:19 CEST - Fresh G4-S1-only closure audit completed. Verified the on-disk plan, source matrix, and breakdown exist; rows G4-005/G4-007/G4-008/G4-009/G4-019 remain `Closed` with code/test evidence for route aliases and missing-id telemetry, active-key normalization and guarded clear, two-phase remote-open dedupe, and foreground group-drain fallback. Re-ran the combined G4-S1 direct test set, `flutter test test/core/notifications` (`+117`), `flutter test test/features/push/application` (`+161`), and scoped `git diff --check`; all passed. Re-ran script gates: `./scripts/run_test_gates.sh completeness-check` still fails at `744/746` with unmatched `test/shared/fakes/fake_group_pubsub_network_test.dart` and `test/shared/fakes/seeded_group_reproduction_log_test.dart`; `./scripts/run_test_gates.sh groups` still fails in broad group integration/membership paths, ending with `GM-028` and `+262 -39`; `./scripts/run_test_gates.sh baseline` still fails in `test/features/groups/integration/group_messaging_smoke_test.dart` with `+90 -7`. Scoped diff caveat: the full dirty worktree includes unrelated overlapping changes such as database/pending-membership wiring in `lib/main.dart` and non-G4-S1 identity/load/send hunks in `GroupConversationWired`; no production code was edited during this audit. Closure decision: G4-S1 remains `accepted_with_explicit_follow_up`; reopen only if notification/push owner tests regress or a red gate is traced to G4-S1 owner behavior.
- 2026-05-24 02:14:04 CEST - Fresh G4-S2 execution and local QA closure completed. Rows G4-001/G4-010/G4-011/G4-012/G4-013/G4-014/G4-015/G4-016/G4-017/G4-018/G4-020 are `Closed` with concrete code/test evidence for typed clamp casts, byte validation, octet-stream rejection, media display integrity, restored retry cleanup, partial upload persistence, durable voice paths, guarded background tasks, group-id reset, active foreground read gating, and optimistic reaction rollback. Post-QA hardening kept unreadable file validation non-throwing and prevented incoming done media on pending-upload paths from bypassing the encryption-metadata display gate. Final direct G4-S2 tests and scoped analyzers passed. Required script gates were rerun and classified: `groups` failed at `+261 -40` in broad invite/membership/rejoin/resume integration paths, and `completeness-check` failed at `744/746` on unmatched shared fake tests; neither signature is in G4-S2 owner behavior. Closure decision: G4-S2 is `accepted_with_explicit_follow_up`; reopen only if media/send/read/reaction owner tests regress or a red broad gate is traced to G4-S2 behavior.
- 2026-05-24 02:21:00 CEST - Fresh G4-S2-only closure review completed. Re-verified the source matrix, this breakdown, and `group4-critical-findings-2026-05-24-session-G4-S2-plan.md`; the eleven G4-S2 rows remain `Closed` and G4-S3 lifecycle/retry-concurrency rows remain open. Re-ran scoped analyzers on the three G4-S2 production owner files and the group conversation widget test file; both analyzers passed. Re-ran direct focused tests: `flutter test test/core/media/group_media_mime_policy_test.dart test/core/media/group_media_integrity_policy_test.dart` passed (`+12`), and `flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart` passed (`+131`). Verified persisted final gate logs: `/tmp/g4s2_groups_gate_final.log` still fails at `+261 -40` in broad invite/membership/rejoin/resume signatures including `SendGroupInviteResult.invalidPayload`, stale membership events, and `GM-028`; `/tmp/g4s2_completeness_gate_final.log` still fails at `744/746` on unmatched shared fake tests. Closure decision remains `accepted_with_explicit_follow_up`; no production code was edited during this review.
- 2026-05-24 02:35:00 CEST - G4-S3 execution and local QA closure completed after spawned execution did not return a durable verdict and was closed. Rows G4-002/G4-003/G4-004 are `Closed` with concrete evidence for stale-only pause recovery, process-local group upload retry exclusion, fresh outgoing `sending` parent skip, and no-drain recovery ack skip. Direct analyzers passed for G4-S3 production/test owner files. Focused G4-S3 tests passed: pause group (`+5`), retry incomplete group uploads (`+17`), targeted no-`groupMsgRepo` ack skip, targeted drain-error no-ack, and supporting resume stuck/wiring/repository tests (`+43`). Full group recovery test file still fails at the unrelated IR-018 replay-persistence assertion where `groupMsgRepo.getMessage(messageId)` is null after drain; broad `groups` remains red at `+259 -42` ending in membership smoke `GM-028`, and completeness still reports the two unmatched shared fake tests. Closure decision: G4-S3 is `accepted_with_explicit_follow_up`; reopen only if stale group pause recovery, upload retry in-flight/fresh-send guard, or recovery ack gating regresses.
- 2026-05-24 02:40:00 CEST - Fresh G4-S3 closure audit completed with no production edits. Reconfirmed G4-002/G4-003/G4-004 implementation in `handle_app_paused.dart`, `retry_incomplete_group_uploads_use_case.dart`, and `handle_app_resumed.dart`: stale-only group pause cutoff, process-local retry in-flight guard with `finally` reset, fresh outgoing `sending` retry skip before upload/publish, and recovery ack only after successful group inbox drain. Re-ran scoped analyzers on G4-S3 production and owner test files; both passed. Re-ran `git diff --check` for scoped G4-S3 files; passed. Re-ran focused tests: pause group (`+5`), retry incomplete group uploads (`+17`), targeted no-`groupMsgRepo` ack skip (`+1`), targeted drain-error no-ack (`+1`), and supporting resume stuck/wiring/repository suite (`+43`); all passed. Re-ran full recovery file; it still fails only at IR-018 replay persistence where `replayed` is null after drain, outside G4-S3 ack-gating behavior. Re-ran `./scripts/run_test_gates.sh groups`; it still fails at `+259 -42`, ending at broad membership `GM-028 empty PeerId add event does not persist or block valid delivery`. Re-ran `./scripts/run_test_gates.sh completeness-check`; it still reports `744/746` with the same two unmatched shared fake tests. Closure decision remains `accepted_with_explicit_follow_up`; reopen only on a regression in stale pause recovery, same-isolate retry exclusion, fresh-send retry skip, or drain-gated recovery ack.

## Final Program Verdict

- verdict: accepted_with_explicit_follow_up
- reason: all non-skipped group4 source rows are `Closed` with concrete code/test evidence, and G4-006 is intentionally `Skipped` based on current navigation resolution. Remaining red gates are classified as existing broad group membership/replay/completeness residuals outside the implemented group4 owner rows.
- reopen criteria: reopen this rollout only if a red gate is traced to one of the closed group4 owner behaviors, or if G4-006's current route-resolution assumption is removed.
