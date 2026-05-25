# Group4 Critical Findings Session G4-S3 Plan - Lifecycle Recovery And Retry Concurrency

Status: accepted_with_explicit_follow_up

## Planning Progress

- 2026-05-24 02:23:22 CEST - Arbiter completed. Files inspected since last update: reviewer findings and final plan sections. Decision/blocker: no structural blockers; reviewer adjustment accepted as an incremental strengthening, and execution may proceed. Next action: implement from this plan without broadening scope.
- 2026-05-24 02:23:22 CEST - Arbiter started. Files inspected since last update: reviewer findings and final plan sections. Decision/blocker: no blocker. Next action: classify review findings.
- 2026-05-24 02:22:50 CEST - Reviewer completed. Files inspected since last update: plan artifact and targeted `rg` verification across lifecycle/retry/retrier files. Decision/blocker: sufficient with one non-structural strengthening added to pin that group pause uses `recoverStuckSendingMessages` rather than the blanket transition. Next action: arbiter classification.
- 2026-05-24 02:22:50 CEST - Reviewer started. Files inspected since last update: plan artifact and targeted `rg` verification across lifecycle/retry/retrier files. Decision/blocker: no blocker. Next action: sufficiency review.
- 2026-05-24 02:20:57 CEST - Planner completed. Files inspected since last update: current evidence set only. Decision/blocker: draft below is implementation-ready pending strict review. Next action: review for missing files, tests, stale assumptions, and scope creep.

## Execution Progress

- 2026-05-24 02:24:15 CEST - Contract extracted. Files inspected since last update: this G4-S3 plan, source matrix, and session breakdown. Decision/blocker: execution scope is rows G4-002/G4-003/G4-004 only with focused lifecycle/retry production files and tests. Next action: spawn isolated Executor pass.
- 2026-05-24 02:27:36 CEST - Executor pass started. Files inspected since last update: `lib/core/lifecycle/handle_app_paused.dart`, `lib/core/lifecycle/handle_app_resumed.dart`, `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`, and the three focused G4-S3 test files. Decision/blocker: current code still has blanket group pause recovery, no retry in-flight guard, no fresh sending pre-upload skip, and a no-drain ack path in the groupRepo-only resume branch. Next action: add the required regressions before production edits.
- 2026-05-24 02:35:00 CEST - Controller local execution fallback completed after the spawned execution worker did not return a durable verdict within the wait window and was closed. Files changed: `handle_app_paused.dart`, `handle_app_resumed.dart`, `retry_incomplete_group_uploads_use_case.dart`, three focused test files, source matrix, and session breakdown. Decision/blocker: no G4-S3 owner blocker remains.

## Real Scope

Rows G4-002, G4-003, and G4-004 only:

- Replace pause-time group recovery in `handleAppPaused` from blanket `transitionSendingToFailed()` to stale-only recovery through existing `GroupMessageRepository.recoverStuckSendingMessages({required Duration olderThan})`.
- Add process-local app-isolate exclusion to `retryIncompleteGroupUploads` so overlapping invocations in the same Dart isolate cannot process the same pending rows.
- Add a fresh outgoing `sending` parent guard in `retryIncompleteGroupUploads` so an active group media send is not uploaded/published again by recovery.
- Change `handleAppResumed` so `group:acknowledgeRecovery` is called only after a group inbox drain ran and succeeded. The `groupRepo != null && groupMsgRepo == null` branch must still rejoin topics, but it must skip ack and emit explicit telemetry.

This session does not introduce DB lease columns, schema migrations, durable lock tables, cross-isolate coordination, or new recovery architecture.

## Closure Bar

G4-S3 is good enough when:

- A pause event leaves fresh group `sending` messages alone and only fails stale group sends using the existing stale cutoff repository API.
- Two concurrent same-isolate `retryIncompleteGroupUploads` calls cannot both upload/publish the same pending group message.
- Retry skips fresh outgoing `sending` parent rows without terminalizing their attachments.
- Recovery ack is impossible in any resume path that did not run a successful group inbox drain.
- Focused lifecycle/retry tests pass, existing intentional retry validation behavior remains intact, and broad gate residuals are classified instead of hidden.

## Source Of Truth

- Primary source rows: `Test-Flight-Improv/Group-Chat-Feature/group4-critical-findings-2026-05-24-matrix.md` rows G4-002, G4-003, G4-004.
- Session decomposition: `Test-Flight-Improv/Group-Chat-Feature/group4-critical-findings-2026-05-24-session-breakdown.md` G4-S3.
- Current code and focused tests win over stale prose.
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` define named gate expectations.
- Existing G4-S1/G4-S2 closure notes document known unrelated red signatures in broad `groups` and `completeness-check` gates.

## Session Classification

implementation-ready

## Exact Problem Statement

Pause currently calls `groupMsgRepo.transitionSendingToFailed()` for all outgoing group `sending` rows, so a fresh media send can be marked failed and later retried while the original send path is still active.

`retryIncompleteGroupUploads` currently reads all upload-pending attachments without a process-local claim and processes each parent independently. If resume, pending retrier, or another same-isolate trigger overlaps, both invocations can upload/publish the same rows. It also only guards late final-send state after upload, so a fresh parent row in `sending` can already be duplicated before recovery determines it is stale.

`handleAppResumed` correctly gates ack on successful drain when both `groupRepo` and `groupMsgRepo` exist, but the rejoin-only branch where `groupRepo != null && groupMsgRepo == null` can still acknowledge recovery without any group drain. Go/node recovery should not be acknowledged unless Flutter actually drained the group inbox successfully.

User-visible behavior that must improve: fewer duplicate group media sends and no false recovery ack that can cause missed group replay. Existing 1:1 pause/retry behavior, group rejoin behavior, media MIME/size/integrity validation, and failed-message retry ordering must stay unchanged.

## Files And Repos To Inspect Next

Production files:

- `lib/core/lifecycle/handle_app_paused.dart`
- `lib/core/lifecycle/handle_app_resumed.dart`
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`
- `lib/features/groups/domain/repositories/group_message_repository.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
- `lib/main.dart`

Focused tests and fakes:

- `test/core/lifecycle/handle_app_paused_group_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart`
- `test/core/lifecycle/main_resume_group_upload_wiring_test.dart`
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`
- `test/shared/fakes/in_memory_group_message_repository.dart`
- `test/shared/fakes/in_memory_media_attachment_repository.dart`

Gate docs/scripts:

- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`

## Existing Tests Covering This Area

- `test/core/lifecycle/handle_app_paused_group_test.dart` currently pins the blanket group pause transition and must be updated to stale-only semantics.
- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart` already covers ack-after-join-and-drain, no ack while drain is incomplete, no ack when drain reports an error, and group resume callback ordering.
- `test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart` covers resume ordering around group stuck-send recovery.
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart` covers missing parent skip, incoming skip, MIME/file/size validation, late deleted parent abort, and final-send status aborts, but not overlapping invocations or fresh `sending` parent pre-upload skip.
- `test/features/groups/domain/repositories/group_message_repository_impl_test.dart` already proves `recoverStuckSendingMessages(olderThan:)` recovers old sending rows and leaves recent sending rows alone.

## Regression/Tests To Add First

Add or adjust these tests before production edits:

- In `test/core/lifecycle/handle_app_paused_group_test.dart`, change the group pause expectations so an old outgoing group `sending` row becomes `failed`, a fresh outgoing group `sending` row remains `sending`, and `AppPausedResult.groupTransitionedCount` counts only stale rows. Update the throwing fake to throw from `recoverStuckSendingMessages`, not `transitionSendingToFailed`, and add a tracking/failing fake assertion that `transitionSendingToFailed()` is not called by group pause.
- In `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`, add a concurrent invocation regression using a blocking upload function: start one retry, wait until upload begins, start a second retry, then assert only one upload/publish occurs and the second call returns `0`.
- In the same retry test file, add a fresh parent regression: a parent `GroupMessage(status: 'sending', timestamp: DateTime.now().toUtc())` with an `upload_pending` attachment must produce count `0`, no upload, no `group:publish`, no `group:inboxStore`, and the attachment remains `upload_pending`.
- In `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, add a `groupRepo`-only resume regression with `needsGroupRecovery: true`: seed a joinable group, call `handleAppResumed` with `groupRepo` and no `groupMsgRepo`, assert `group:join` ran, `group:inboxRetrieveCursor` did not run, `group:acknowledgeRecovery` did not run, and a telemetry event such as `APP_LIFECYCLE_RESUME_GROUP_ACK_SKIPPED_NO_DRAIN` was emitted with reason `missing_group_message_repository`.

## Step-By-Step Implementation Plan

1. Update `handleAppPaused` to call `groupMsgRepo.recoverStuckSendingMessages(olderThan: kStuckSendingGroupThreshold)` instead of `transitionSendingToFailed()`. Import/reuse the existing `kStuckSendingGroupThreshold` from `recover_stuck_sending_group_messages_use_case.dart` or move only the constant to a shared location if an import cycle appears. Keep the existing error isolation and result shape.
2. Rename pause telemetry/debug text only enough to avoid lying: keep existing event names if that minimizes fallout, but include `olderThanSeconds` or equivalent details so stale-cutoff behavior is observable.
3. Add a module-local retry guard in `retry_incomplete_group_uploads_use_case.dart`, for example a private static/file-level boolean set before the first await and reset in a `finally`. If already running, emit skip/timing telemetry and return `0`. This is intentionally process-local and app-isolate-only.
4. Add a pre-upload parent guard in `retryIncompleteGroupUploads` immediately after loading `parentMessage`: if the message is outgoing, `status == 'sending'`, and its timestamp is within the stale threshold window, emit skip telemetry and continue without loading group members, validating/uploading files, or sending. Do not skip failed rows. Do not terminalize attachments for this fresh-send case.
5. Preserve the existing late final-send guard, which still protects deleted/incoming/non-sendable parents after upload completion. Extend it only if needed to share the same stale threshold logic cleanly.
6. Update `handleAppResumed` rejoin-only branch (`groupRepo != null && resumeGroupRecoveryEnabled` but `groupMsgRepo == null`) so it never calls `callGroupAcknowledgeRecovery`. If `needsGroupRecovery && rejoinResult.canAcknowledgeGroupRecovery`, emit telemetry for skipped ack because no group drain ran. Keep rejoin behavior and `groupReregisterMs`.
7. Do not change `PendingMessageRetrier` unless a focused test proves it has the same no-drain ack bug in the current callback path. Current evidence shows its ack path already runs `_runGroupDrainIfNeeded()` before `_acknowledgeGroupRecoveryIfEligible()`.
8. Update the source matrix rows G4-002, G4-003, and G4-004 only after tests pass, recording exact code/test evidence. Update the G4-S3 row in the session breakdown only with execution evidence.
9. Stop if current code has already been changed by another worker to satisfy a row; verify with tests and only adjust docs/evidence for that row.

## Risks And Edge Cases

- Fresh send cutoff must be based on the same clock semantics already used by `recoverStuckSendingMessages`; the repository uses message timestamp, so tests should set explicit UTC timestamps.
- A process-local boolean does not protect multiple app isolates or process restarts. That is accepted for this pass and must not be expanded into schema leases.
- Returning `0` for overlapping retry means work may be skipped once, but later resume/timer retries can pick it up; this is preferable to duplicate publish.
- A fresh `sending` parent with invalid media should not be terminalized by recovery because the active send path still owns it.
- A stale `sending` parent may still be recovered by pause/resume first; if retry sees it directly, the plan allows existing retry behavior unless tests prove it duplicates active work.
- Ack skip telemetry must not throw or block resume.
- The dirty worktree includes many unrelated group, database, Go, notification, and doc changes; implementation must not revert or normalize unrelated files.

## Exact Tests And Gates To Run

Regression-first focused tests:

- `flutter test test/core/lifecycle/handle_app_paused_group_test.dart`
- `flutter test test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
- `flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`

Focused supporting tests:

- `flutter test test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart`
- `flutter test test/core/lifecycle/main_resume_group_upload_wiring_test.dart`
- `flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart`

Static/format checks for touched files:

- `dart format lib/core/lifecycle/handle_app_paused.dart lib/core/lifecycle/handle_app_resumed.dart lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart test/core/lifecycle/handle_app_paused_group_test.dart test/core/lifecycle/handle_app_resumed_group_recovery_test.dart test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `dart analyze lib/core/lifecycle/handle_app_paused.dart lib/core/lifecycle/handle_app_resumed.dart lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- `dart analyze test/core/lifecycle/handle_app_paused_group_test.dart test/core/lifecycle/handle_app_resumed_group_recovery_test.dart test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `git diff --check -- lib/core/lifecycle/handle_app_paused.dart lib/core/lifecycle/handle_app_resumed.dart lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart test/core/lifecycle/handle_app_paused_group_test.dart test/core/lifecycle/handle_app_resumed_group_recovery_test.dart test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart Test-Flight-Improv/Group-Chat-Feature/group4-critical-findings-2026-05-24-matrix.md Test-Flight-Improv/Group-Chat-Feature/group4-critical-findings-2026-05-24-session-breakdown.md`

Named gates after focused tests pass:

- `./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh completeness-check`

## Known-Failure Interpretation

Do not classify existing broad gate failures as G4-S3 regressions unless the failing signature is in the touched lifecycle/retry behavior. The source breakdown records that `groups` currently has unrelated invite/membership/rejoin/resume failures and `completeness-check` has unmatched shared fake tests from the dirty worktree. Re-run and record exact failure signatures; only reopen G4-S3 if a failure points to stale group pause recovery, group upload retry concurrency/fresh-send guard, or no-drain recovery ack behavior.

## Done Criteria

- Rows G4-002, G4-003, and G4-004 have regression tests that fail before production edits and pass after edits, or the executor documents that current dirty code already satisfies them.
- `handleAppPaused` no longer calls `transitionSendingToFailed()` for groups.
- `retryIncompleteGroupUploads` has a process-local in-flight guard and skips fresh outgoing `sending` parents before upload/publish.
- `handleAppResumed` never acknowledges group recovery from the rejoin-only/no-`groupMsgRepo` branch and emits skip telemetry.
- All exact focused tests and static checks above pass, or any failures are classified with evidence as unrelated existing dirty-worktree residuals.
- Matrix rows G4-002/G4-003/G4-004 and the G4-S3 breakdown ledger are updated with exact code/test evidence.

## Scope Guard

Non-goals:

- No database lease columns, migrations, durable lock records, or schema changes.
- No cross-process or multi-isolate distributed claim system.
- No changes to 1:1 retry, post retry, push notification routing, group membership repair, Go bridge/node behavior, or group media validation policy except where existing retry tests require preserving behavior.
- No broad refactors of lifecycle orchestration, `PendingMessageRetrier`, repository interfaces, or `lib/main.dart` wiring unless a targeted G4-S3 test proves the current wiring is wrong.
- No unrelated formatting churn in the dirty worktree.

Overengineering signals:

- Adding lease columns or transactional claim APIs.
- Introducing a new retry scheduler.
- Reworking `sendGroupMessage` or media upload primitives for this pass.
- Changing broad gate definitions to make this session pass.

## Accepted Differences / Intentionally Out Of Scope

- Process-local locking is intentionally weaker than a DB-backed lease and only protects overlapping invocations in the app isolate. This is the accepted recommendation for G4-003.
- Fresh-send guard uses an age cutoff rather than ownership from an active send token. Active send tokens or durable leases are out of scope.
- 1:1 pause still uses its existing transition path; G4-S3 is group-only for pause/retry hardening.
- `PendingMessageRetrier` ack sequencing appears already drain-first in current code and is not part of this session unless direct evidence contradicts that.

## Dependency Impact

- Closing G4-S3 lets the Group4 critical findings matrix move toward final closure after G4-S1/G4-S2.
- Future work that wants multi-isolate or after-restart duplicate protection should start from a new plan and explicitly revisit DB/schema leases; it must not be smuggled into this pass.
- If the stale threshold constant moves, later group recovery and retry code should keep using one shared value to avoid drift.

## Reviewer Findings

Verdict: sufficient with one adjustment already applied.

- Missing files/tests/gates: none structural. The plan names the production files, direct tests, static checks, and named broad gates needed for G4-S3.
- Stale or incorrect assumptions: none found. Current code still calls `transitionSendingToFailed()` in `handleAppPaused`, retry still has no same-isolate exclusion, and `handleAppResumed` still has a rejoin-only ack path.
- Overengineering: none. The plan explicitly rejects DB leases/schema changes and keeps the accepted process-local lock.
- Decomposition quality: sufficient. Each row has a direct regression and a narrow production seam.
- Minimum sufficiency adjustment: pin the pause API change with a tracking/failing fake so an implementation cannot keep calling blanket `transitionSendingToFailed()` while still passing stale/fresh state assertions by accident.

## Arbiter Decision

Structural blockers: none.

Incremental details:

- The reviewer-requested pause fake assertion is included in the regression section. No further plan edits are needed before execution.
- The exact telemetry event name for the no-drain ack skip may be adjusted during implementation if the repo has a more specific naming convention, but the behavior and reason payload are required.

Accepted differences:

- Process-local lock plus fresh-send guard remains the accepted G4-003 solution. DB schema lease columns remain intentionally out of scope.
- `PendingMessageRetrier` stays out of scope unless a direct targeted regression proves it violates the no-drain/no-ack contract.

Final verdict: execution-ready. Implement G4-002, G4-003, and G4-004 only, then update the matrix and breakdown with exact passing/failing evidence.

## Final Execution Verdict

- Final verdict: `accepted_with_explicit_follow_up`.
- Plan fallback used: no; spawned planner produced this execution-ready plan.
- Execution fallback used: yes; spawned execution worker did not return a durable verdict before timeout and was closed, so the controller applied the scoped implementation locally.
- Blocking issues remaining: none for G4-S3 owner behavior.
- Production behavior closed:
  - `handleAppPaused` uses `recoverStuckSendingMessages(olderThan: kPausedGroupSendingRecoveryThreshold)` for group messages instead of blanket `transitionSendingToFailed()`.
  - `retryIncompleteGroupUploads` has a process-local in-flight guard and skips fresh outgoing `sending` parents before upload/publish.
  - `handleAppResumed` emits `APP_LIFECYCLE_RESUME_GROUP_ACK_SKIPPED` and does not acknowledge recovery when no group inbox drain ran or when drain reports errors.
- Passing focused evidence:
  - `dart analyze lib/core/lifecycle/handle_app_paused.dart lib/core/lifecycle/handle_app_resumed.dart lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart` passed with no issues.
  - `dart analyze test/core/lifecycle/handle_app_paused_group_test.dart test/core/lifecycle/handle_app_resumed_group_recovery_test.dart test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart` passed with no issues.
  - `flutter test test/core/lifecycle/handle_app_paused_group_test.dart` passed (`+5`).
  - `flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart` passed (`+17`).
  - Targeted `handle_app_resumed_group_recovery_test.dart --plain-name "rejoins but skips recovery ack when group message repository is unavailable"` passed (`+1`).
  - Targeted `handle_app_resumed_group_recovery_test.dart --plain-name "BB-012 does not acknowledge recovery when inbox drain reports an error"` passed (`+1`).
  - Supporting `flutter test test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart test/core/lifecycle/main_resume_group_upload_wiring_test.dart test/features/groups/domain/repositories/group_message_repository_impl_test.dart` passed (`+43`).
- Classified residuals:
  - Full `flutter test test/core/lifecycle/handle_app_resumed_group_recovery_test.dart` remains red at IR-018 replay persistence, where `groupMsgRepo.getMessage(messageId)` is null after drain; this is outside the G4-S3 ack-gating change.
  - `./scripts/run_test_gates.sh groups` remains red at `+259 -42`, ending in existing membership/rejoin residuals including `GM-028`.
  - `./scripts/run_test_gates.sh completeness-check` reports `744/746` with unmatched shared fake test files.

## Fresh Closure Audit - 2026-05-24 02:40 CEST

- Closure verdict: `accepted_with_explicit_follow_up`.
- Scope verified: rows G4-002/G4-003/G4-004 only. No production code was edited during this closure audit.
- Implementation evidence reconfirmed:
  - `handleAppPaused` calls `recoverStuckSendingMessages(olderThan: kPausedGroupSendingRecoveryThreshold)` for group pause recovery and no longer calls the blanket group `transitionSendingToFailed()` path.
  - `retryIncompleteGroupUploads` uses a process-local in-flight guard, resets it in `finally`, and skips fresh outgoing `sending` parents before loading group state, uploading media, publishing, or terminalizing attachments.
  - `handleAppResumed` acknowledges group recovery only after successful group rejoin plus group inbox drain; missing `groupMsgRepo` and failed drain paths emit `APP_LIFECYCLE_RESUME_GROUP_ACK_SKIPPED`.
- Fresh passing evidence:
  - `dart analyze lib/core/lifecycle/handle_app_paused.dart lib/core/lifecycle/handle_app_resumed.dart lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart` passed.
  - `dart analyze test/core/lifecycle/handle_app_paused_group_test.dart test/core/lifecycle/handle_app_resumed_group_recovery_test.dart test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart` passed.
  - `git diff --check` passed for the scoped G4-S3 production/test/doc files.
  - `flutter test test/core/lifecycle/handle_app_paused_group_test.dart` passed (`+5`).
  - `flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart` passed (`+17`).
  - Targeted no-drain ack tests passed: `rejoins but skips recovery ack when group message repository is unavailable` and `BB-012 does not acknowledge recovery when inbox drain reports an error`.
  - Supporting lifecycle/repository suite passed: `flutter test test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart test/core/lifecycle/main_resume_group_upload_wiring_test.dart test/features/groups/domain/repositories/group_message_repository_impl_test.dart` (`+43`).
- Fresh residual classification:
  - Full `flutter test test/core/lifecycle/handle_app_resumed_group_recovery_test.dart` still fails only at IR-018 replay persistence (`replayed` is null after drain), outside the G4-S3 ack-gating owner behavior.
  - `./scripts/run_test_gates.sh groups` still fails at `+259 -42`, ending at `GM-028 empty PeerId add event does not persist or block valid delivery`; this is broad membership/rejoin behavior outside G4-S3.
  - `./scripts/run_test_gates.sh completeness-check` still reports `744/746` with unmatched `test/shared/fakes/fake_group_pubsub_network_test.dart` and `test/shared/fakes/seeded_group_reproduction_log_test.dart`.
- Reopen criteria: reopen G4-S3 only if stale group pause recovery, same-isolate retry exclusion, fresh outgoing `sending` retry skip, or drain-gated recovery ack behavior regresses.
