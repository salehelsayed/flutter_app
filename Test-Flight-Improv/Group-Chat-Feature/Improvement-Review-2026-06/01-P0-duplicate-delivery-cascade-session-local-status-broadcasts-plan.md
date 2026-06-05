Status: accepted_with_explicit_follow_up

# P0 Duplicate Delivery Cascade - Local Status Broadcasts Session Plan

## Planning Progress

- 2026-06-03 22:03 CEST - Arbiter completed. Files inspected since last update: reviewer findings and plan scope/closure sections. Decision/blocker: no structural blockers remain; accepted differences are documented and incremental details are deferred to execution. Next action: hand off this execution-ready plan to the session pipeline executor.
- 2026-06-03 22:01 CEST - Reviewer completed; Arbiter started. Files inspected since last update: full plan draft, mandatory section checklist, simulator closure rule, source-row coverage ledger, direct tests/gates. Decision/blocker: no structural blocker found; plan is sufficient with incremental execution details only. Next action: classify findings, record accepted differences, and finalize execution-ready status.
- 2026-06-03 21:58 CEST - Planner completed; Reviewer started. Files inspected since last update: `group_message_repository.dart`, `group_message_repository_impl.dart`, `group_conversation_wired.dart`, retry/recover use cases, direct tests, `integration_test/group_recovery_e2e_test.dart`, `Test-Flight-Improv/test-gate-definitions.md`, `scripts/run_test_gates.sh`, prior accepted session plans. Decision/blocker: no blocker; draft uses a narrow optional local-change stream plus batch reload event for count-only sweeps. Next action: review for missing gates, overreach, stale assumptions, and checklist coverage.
- 2026-06-03 21:54 CEST - Evidence Collector completed; Planner started. Files inspected since last update: repository interface/fakes, production app repository wiring, `GroupConversationWired` subscriptions/lifecycle, send/retry/recover status writes, simulator skill, existing group recovery simulator scenarios. Decision/blocker: no blocker; current code has no UI-facing repository status stream, and existing simulator scenarios do not specifically prove this local-status seam. Next action: draft exact scope, closure bar, tests, gates, residual classification, and downstream closure expectations.
- 2026-06-03 21:48 CEST - Evidence Collector in progress. Files inspected since last update: source doc, session breakdown, worktree status. Decision/blocker: dependencies are accepted in the breakdown; prior-session changes are present and must be preserved; no blocker. Next action: inspect repository status-write seams, open `GroupConversationWired` stream/update handling, retrier/resume sweep code, direct tests, and `groups` gate definitions.

## Execution Progress

- 2026-06-03 22:28 CEST - Phase: closure audit completed. Files inspected/touched: this session plan and the session breakdown ledger/evidence only. Evidence audited: final Execution/QA verdict, QA review, scoped local-status repo/wired symbols, direct repository and wired regressions, targeted group simulator proof, `/tmp/mknoon-local-status-groups.log`, focused `GM-008` rerun result, format, and `git diff --check`. Decision/blocker: closure verdict is `accepted_with_explicit_follow_up`; no session-owned failures remain, and the only follow-up is the known unrelated `GCA-004` groups-gate residual. Next action: later pipeline work may continue with `status-timestamp-migration`; do not mark a whole-doc final verdict here.
- 2026-06-03 22:24 CEST - Phase: final verdict written. Files touched: session plan only. Commands/results: final execution/QA verdict persisted as `accepted_with_explicit_follow_up`. Decision/blocker: no blocking issues; only the allowed known `GCA-004` groups-gate residual remains as explicit carry-forward. Next action: parent controller may run closure audit if required; do not update breakdown ledger or source-doc final verdict in this QA pass.
- 2026-06-03 22:24 CEST - Phase: QA completed. Files inspected/touched: session plan updated with QA review and verdict. Commands/results: none beyond spot checks already recorded. Decision/blocker: local-status implementation meets the plan scope, closure bar, tests, and gate classification. Next action: persist final verdict section.
- 2026-06-03 22:23 CEST - Phase: QA log inspection and spot checks completed. Files inspected: `/tmp/mknoon-local-status-groups.log`. Commands/results: log contains exactly one explicit `[E]` failure, `GCA-004 bridgeError recovery drains inbox after settled materialized invite` at `test/features/groups/integration/invite_round_trip_test.dart:2930`, `Expected: not null`, `Actual: <null>`; later `GM-008` lines only carry the existing `-1` runner failure count. Spot checks passed: `flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart --plain-name "saveMessage emits one local status event when an outgoing row changes status"`, `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "local outgoing status event updates visible row without listener stream"`, and `git diff --check`. Decision/blocker: groups-gate residual is the allowed known residual, not session-owned. Next action: write QA review.
- 2026-06-03 22:23 CEST - Phase: QA files inspected. Files inspected: session plan scope/closure/done criteria/known residuals/Executor Result; source doc; session breakdown without editing; diffs for `lib/features/groups/domain/repositories/group_message_repository.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `test/shared/fakes/in_memory_group_message_repository.dart`, `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, and `integration_test/group_recovery_e2e_test.dart`; relevant DB helper outgoing-sweep predicates. Decision/blocker: no blocking issue found; unrelated dirty work, including `info.plist` and prior accepted text/voice/timeout-session hunks, was preserved and not attributed to this session. Next action: inspect gate log and run narrow spot checks.
- 2026-06-03 22:23 CEST - Phase: QA started. Files inspected: plan intake and worktree status. Current command: reviewer-only local inspection, no code fixes. Decision/blocker: status was `executor-complete-pending-qa`; proceed to verify landed behavior, required regressions, scope guard, and gate evidence. Next action: inspect owner diffs and gate log.
- 2026-06-03 22:20 CEST - Phase: QA Reviewer spawned/running. Files inspected/touched: session plan only. Current command: spawned child agent `019e8f25-c2c4-7b10-ba14-02bb62f40ca5` with `model: gpt-5.5`, `reasoning_effort: xhigh`. Decision/blocker: no blocker; waiting for bounded QA result and file-backed review evidence. Next action: inspect QA completion and run fix pass only if QA reports blocking issues.
- 2026-06-03 22:20 CEST - Phase: QA Reviewer spawning. Files inspected/touched: session plan only. Current command: none. Decision/blocker: Executor child completed with persisted result and reported required direct suites, simulator proof, groups-gate triage, format, and `git diff --check`; no session-owned failures reported. Next action: spawn a separate QA Reviewer child with `model: gpt-5.5` and `reasoning_effort: xhigh` to inspect scope, behavior, and evidence without editing code.
- 2026-06-03 22:18 CEST - Phase: Executor completion persisted. Files touched: session plan only. Commands/results: Executor result summary written below. Decision/blocker: implementation and Executor-side verification are complete; no QA reviewer duties, closure audit, session-ledger acceptance, or final whole-doc verdict were performed. Next action: hand off to separate QA Reviewer.
- 2026-06-03 22:18 CEST - Phase: final hygiene checks completed. Files touched: none. Commands/results: `dart format --output=none --set-exit-if-changed lib/features/groups/domain/repositories/group_message_repository.dart lib/features/groups/domain/repositories/group_message_repository_impl.dart lib/features/groups/presentation/screens/group_conversation_wired.dart test/shared/fakes/in_memory_group_message_repository.dart test/features/groups/domain/repositories/group_message_repository_impl_test.dart test/features/groups/presentation/group_conversation_wired_test.dart integration_test/group_recovery_e2e_test.dart` passed with `Formatted 7 files (0 changed)`; `git diff --check` passed. Decision/blocker: formatting and diff integrity are clean. Next action: persist Executor result summary.
- 2026-06-03 22:17 CEST - Phase: groups gate focused triage completed. Files touched: session plan only. Commands/results: `flutter test test/features/groups/integration/group_membership_smoke_test.dart --plain-name "GM-008 removes C, restarts C before re-add, and rejoins from current persisted epoch"` passed. Gate log inspection command/results: `/tmp/mknoon-local-status-groups.log` contains a single explicit `[E]` failure, `GCA-004 bridgeError recovery drains inbox after settled materialized invite` in `test/features/groups/integration/invite_round_trip_test.dart:2930`, with `Expected: not null`, `Actual: <null>`; later `GM-008` lines only carry the existing `-1` runner failure count and the focused rerun is green. Classification: known carried `GCA-004` residual, not a `local-status-broadcasts` regression. Decision/blocker: no session-owned groups-gate failure remains. Next action: run required format check and `git diff --check`.
- 2026-06-03 22:15 CEST - Phase: groups gate failed; pending triage recorded before log inspection. Files touched: none. Failing gate command: `./scripts/run_test_gates.sh groups` (run through `bash -lc 'set -o pipefail; ./scripts/run_test_gates.sh groups 2>&1 | tee /tmp/mknoon-local-status-groups.log'`). Failing file/test if known: `test/features/groups/integration/group_membership_smoke_test.dart`, `GM-008 removes C, restarts C before re-add, and rejoins from current persisted epoch` observed as the active failing slice in gate output. Log path: `/tmp/mknoon-local-status-groups.log`. Focused triage command: `flutter test test/features/groups/integration/group_membership_smoke_test.dart --plain-name "GM-008 removes C, restarts C before re-add, and rejoins from current persisted epoch"`. Classification: `pending_triage`. Decision/blocker: do not classify as known `GCA-004`; this is a different groups-gate failure until focused rerun evidence proves otherwise. Next action: run focused triage command.
- 2026-06-03 22:13 CEST - Phase: targeted simulator proof completed; groups gate starting. Files touched: none. Commands/results: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/group_recovery_e2e_test.dart` passed; command #8 `integration_test/group_recovery_e2e_test.dart` passed on one-device `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`. Current command: `./scripts/run_test_gates.sh groups` with output mirrored to `/tmp/mknoon-local-status-groups.log`. Decision/blocker: simulator proof green. Next action: run required groups gate and triage immediately if it fails.
- 2026-06-03 22:10 CEST - Phase: simulator list completed; targeted simulator proof starting. Files touched: none. Commands/results: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list` passed; resolved one-device `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, two-device `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,38FECA55-03C1-4907-BD9D-8E64BF8E3469`; `integration_test/group_recovery_e2e_test.dart` appears as group command #8. Current command: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/group_recovery_e2e_test.dart`. Decision/blocker: no simulator discovery blocker. Next action: run targeted group recovery simulator proof.
- 2026-06-03 22:10 CEST - Phase: direct widget suite completed; simulator proof starting. Files touched: none. Commands/results: `flutter test test/features/groups/presentation/group_conversation_wired_test.dart` passed. Current command: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list`. Decision/blocker: required direct repository and wired widget suites are green. Next action: run simulator list pass and targeted group recovery E2E proof.
- 2026-06-03 22:09 CEST - Phase: direct repository suite completed; direct widget suite starting. Files touched: none. Commands/results: `flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart` passed. Current command: `flutter test test/features/groups/presentation/group_conversation_wired_test.dart`. Decision/blocker: repository direct coverage is green. Next action: run full wired widget suite.
- 2026-06-03 22:08 CEST - Phase: focused verification completed. Files touched: none after formatting. Commands/results: `flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart --plain-name "saveMessage emits one local status event when an outgoing row changes status"` passed; `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "local outgoing status event updates visible row without listener stream"` passed. Decision/blocker: focused RED regressions are now green. Next action: run required full direct repository and wired widget suites.
- 2026-06-03 22:08 CEST - Phase: production implementation completed. Files touched: `lib/features/groups/domain/repositories/group_message_repository.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `test/shared/fakes/in_memory_group_message_repository.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, plus RED test files. Current command: none. Decision/blocker: optional `GroupOutgoingLocalMessageChangeSource` stream implemented; production/fake repositories emit outgoing status changes after successful status-changing writes and emit batch rows-changed for count-only sweeps with count > 0; wired screen subscribes, updates matching per-message events in-place, reloads for batch events, ignores other groups, and cancels/resubscribes on dispose/group/repository change. Next action: rerun focused repository and widget tests that were RED.
- 2026-06-03 22:05 CEST - Phase: RED focused tests completed. Files touched: no new files. Commands/results: `flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart --plain-name "saveMessage emits one local status event when an outgoing row changes status"` failed as expected with missing `GroupOutgoingLocalMessageChange` type and missing `outgoingLocalMessageChanges` getter; `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "local outgoing status event updates visible row without listener stream"` failed as expected because mounted screen status stayed `failed` after repository row changed to `sent`. Decision/blocker: RED evidence captured; no blocker. Next action: implement optional repository event capability, fake event source, and `GroupConversationWired` subscription.
- 2026-06-03 22:04 CEST - Phase: RED regressions added. Files touched: `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `integration_test/group_recovery_e2e_test.dart`. Current command: none. Decision/blocker: tests now cover repository per-message outgoing events, incoming/unchanged suppression, batch sweep events, open-screen in-place status updates, other-group ignore, batch reload, dispose/repository-change lifecycle, and a simulator local-status smoke. Next action: run focused RED commands before production edits.
- 2026-06-03 22:01 CEST - Phase: Executor inspection completed. Files inspected: `group_message_repository.dart`, `group_message_repository_impl.dart`, `group_conversation_wired.dart`, `in_memory_group_message_repository.dart`, direct repository/widget tests, `integration_test/group_recovery_e2e_test.dart`, send/retry/recover group use cases, current dirty diffs in overlapping files. Current command: none. Decision/blocker: repository-owned emissions can cover per-message and count-only sweep paths; no conditional retrier/resume production files are needed. Next action: add RED regressions before production edits.
- 2026-06-03 21:57 CEST - Phase: Executor started. Files inspected: session plan, `git status --short`, execution and simulator skill instructions. Current command: none. Decision/blocker: contract extracted; dirty worktree contains pre-existing modified files including `info.plist`, `integration_test/group_recovery_e2e_test.dart`, and `group_conversation_wired.dart`/tests, so overlapping files will be inspected before edits and unrelated changes preserved. Next action: inspect owner files, conditional owner seams, and current diffs before adding RED regressions.
- 2026-06-03 21:56 CEST - Phase: controller contract extraction. Files inspected: this plan, session breakdown, `Test-Flight-Improv/test-gate-definitions.md`, `scripts/run_test_gates.sh`, repository/wired entry-point grep, worktree status. Current command: none. Decision/blocker: execution contract is concrete and safe to hand off; scope is limited to optional repository-local outgoing status broadcasts, `GroupConversationWired` subscription behavior, direct repository/widget regressions, the required group simulator proof, and `./scripts/run_test_gates.sh groups` with only the documented `GCA-004` residual allowed. Next action: spawn fresh Executor child with `model: gpt-5.5` and `reasoning_effort: xhigh`.
- 2026-06-03 21:57 CEST - Phase: Executor spawned/running. Files inspected/touched: plan progress only. Current command: spawned child agent `019e8f0f-98d2-7830-913e-3be2b5be7620` with `model: gpt-5.5`, `reasoning_effort: xhigh`. Decision/blocker: no blocker; waiting for bounded Executor result and file-backed progress. Next action: wait for Executor completion, then spawn a separate QA Reviewer child.

## Executor Result

Executor status: complete, pending separate QA review.

Files touched/updated for this session:

- `lib/features/groups/domain/repositories/group_message_repository.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `test/shared/fakes/in_memory_group_message_repository.dart`
- `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `integration_test/group_recovery_e2e_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade-session-local-status-broadcasts-plan.md`

Note: the worktree had pre-existing unrelated dirty changes, including overlapping group files and `info.plist`; this Executor preserved them and does not claim ownership of every existing hunk in those files.

Implemented result:

- Added optional `GroupOutgoingLocalMessageChangeSource` with lightweight outgoing local status and batch rows-changed events.
- `GroupMessageRepositoryImpl.saveMessage(...)` and `updateMessageStatus(...)` emit per-message status events only after successful writes, only for outgoing rows, and only when status changes.
- Incoming rows and unchanged-status saves/updates do not emit.
- `recoverStuckSendingMessages(...)` and `transitionSendingToFailed(...)` emit one batch rows-changed event only when count > 0.
- `GroupConversationWired` subscribes when the optional capability is available, updates matching visible per-message status events in place, reloads scoped messages for batch events, ignores other groups, and cancels/resubscribes on dispose, group reset, and repository instance changes.
- Retry semantics, ids, timestamps, timeouts, schema/migrations, receive dedup, notifications, final docs, and bridge/native code were not intentionally changed. Conditional retrier/resume production files were not touched in this session, so no conditional direct tests were required.

Tests added/updated:

- Repository RED/regression coverage for outgoing per-message status events, incoming suppression, unchanged-status suppression, and count-only batch events.
- Wired-screen regression coverage for in-place visible row updates without listener echo, other-group ignore, batch reload, disposal cancellation, and repository-change resubscription.
- Group recovery simulator smoke for an open group screen reflecting local outgoing status without listener echo.

Executor-side commands and outcomes:

- RED: `flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart --plain-name "saveMessage emits one local status event when an outgoing row changes status"` failed before production edits with the missing local-change type/getter.
- RED: `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "local outgoing status event updates visible row without listener stream"` failed before production edits because the visible status stayed `failed`.
- GREEN: `flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart --plain-name "saveMessage emits one local status event when an outgoing row changes status"` passed after implementation.
- GREEN: `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "local outgoing status event updates visible row without listener stream"` passed after implementation.
- GREEN: `flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart` passed.
- GREEN: `flutter test test/features/groups/presentation/group_conversation_wired_test.dart` passed.
- GREEN: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list` passed and listed `integration_test/group_recovery_e2e_test.dart` as group command #8.
- GREEN: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/group_recovery_e2e_test.dart` passed on one-device `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`.
- ACCEPTED RESIDUAL: `./scripts/run_test_gates.sh groups` was run through `bash -lc 'set -o pipefail; ./scripts/run_test_gates.sh groups 2>&1 | tee /tmp/mknoon-local-status-groups.log'` and exited 1 only with the known `GCA-004 bridgeError recovery drains inbox after settled materialized invite` residual in `test/features/groups/integration/invite_round_trip_test.dart:2930`, `Expected: not null`, `Actual: <null>`. Log path: `/tmp/mknoon-local-status-groups.log`.
- GREEN TRIAGE: `flutter test test/features/groups/integration/group_membership_smoke_test.dart --plain-name "GM-008 removes C, restarts C before re-add, and rejoins from current persisted epoch"` passed, confirming the apparent GM-008 runner line was not a distinct failure.
- GREEN: `dart format --output=none --set-exit-if-changed lib/features/groups/domain/repositories/group_message_repository.dart lib/features/groups/domain/repositories/group_message_repository_impl.dart lib/features/groups/presentation/screens/group_conversation_wired.dart test/shared/fakes/in_memory_group_message_repository.dart test/features/groups/domain/repositories/group_message_repository_impl_test.dart test/features/groups/presentation/group_conversation_wired_test.dart integration_test/group_recovery_e2e_test.dart` passed with `Formatted 7 files (0 changed)`.
- GREEN: `git diff --check` passed.

Failure classification:

- No session-owned failures remain from Executor-side verification.
- The only remaining groups-gate failure is the allowed known `GCA-004` residual described in the plan.

Items for QA to scrutinize:

- Production count-only sweeps emit a global batch rows-changed event because the DB helper returns only a count; open screens reload their current group through scoped `_loadMessages()`.
- Verify subscription lifecycle behavior around repository swaps and group-id changes against any additional widget scenarios QA considers relevant.

## real scope

Implement one doc-scoped in-process refresh seam for outgoing group message status changes:

- Expose a lightweight local outgoing group message change stream from repository-owned writes.
- Emit per-message status changes when `GroupMessageRepositoryImpl.saveMessage(...)` or `updateMessageStatus(...)` changes the status of an outgoing row.
- Emit a batch "outgoing rows changed, reload if open" signal from repository-owned count-only status sweeps such as `recoverStuckSendingMessages(...)` and `transitionSendingToFailed(...)`, where the current DB helper returns only a count and not affected ids.
- Have an open `GroupConversationWired` subscribe to that optional stream, update the visible row status in-place for matching per-message events, and run a scoped `_loadMessages()` for batch rows-changed events.

This session does not change send retry semantics, message ids, timestamps, timeouts, schema, receive-side dedup, notifications, final matrix docs, or final source-doc verdict.

Primary owner files:

- `lib/features/groups/domain/repositories/group_message_repository.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `test/shared/fakes/in_memory_group_message_repository.dart`
- `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `integration_test/group_recovery_e2e_test.dart` for the required simulator-backed proof

Conditional owner files only if execution chooses a retrier/resume-owned batch event instead of repository-owned batch emission:

- `lib/core/services/pending_message_retrier.dart`
- `lib/core/lifecycle/handle_app_resumed.dart`
- `test/core/services/pending_message_retrier_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`

## closure bar

This session is closed only when all of the following are true:

- An outgoing local status change written by the group repository is observable by an already-open `GroupConversationWired` for the same group without a self-echo, `groupMessageStream` event, app lifecycle resume, or route reload.
- Incoming rows do not emit outgoing-status events.
- Unchanged-status saves/updates do not spam duplicate status events.
- Count-only repository sweeps that move outgoing group rows from `sending` to `failed` cause an open group screen to refresh from the local repository even though no per-message ids are available.
- Subscription lifecycle is safe: cancel on dispose, no setState-after-dispose, ignore other groups, and keep existing `groupMessageStream`, reaction, removed-group, media progress, and resume reload behavior intact.
- Direct repository and widget regressions pass.
- The named gate `./scripts/run_test_gates.sh groups` is run and either passes or fails only with the exact known `GCA-004` residual described below.
- Because this touches group messaging recovery UI, a `$run-flutter-reliability-sims` group proof is required. If no existing simulator scenario can prove the local-status seam, execution must extend `integration_test/group_recovery_e2e_test.dart` with the narrowest local-status broadcast smoke before claiming full closure.

Coverage ledger:

| Requirement | Planned proof |
|---|---|
| Expose lightweight outgoing group status change signal | `group_message_repository_impl_test.dart` asserts per-message outgoing status events from `saveMessage` and `updateMessageStatus`. |
| Include local retrier/sweep updates | Repository recover/transition tests assert a batch rows-changed event when count-only sending-to-failed sweeps update rows. |
| Open screen applies updates without self-echo or route reload | `group_conversation_wired_test.dart` updates the repo while the screen is mounted and emits no `groupMessageStream` event; the screen status changes in-place. |
| Keep this as an in-process UI seam only | Scope guard below forbids retry, schema, timeout, notification, dedup, and final doc closure changes. |
| Simulator-backed group closure | Add/extend a focused `integration_test/group_recovery_e2e_test.dart` local-status scenario and run it through `run_with_devices.sh group --only integration_test/group_recovery_e2e_test.dart`. |

## source of truth

Authoritative docs and code:

- Product/source scope: `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade.md`
- Session scope and dependency state: `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade-session-breakdown.md`
- Gate source: `Test-Flight-Improv/test-gate-definitions.md`; if it disagrees with `scripts/run_test_gates.sh`, the script wins.
- Current production truth: `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`, `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`.
- Current test truth: direct repository/wired tests plus `integration_test/group_recovery_e2e_test.dart`.

On disagreement, current code and tests beat stale prose. The session breakdown beats broader source-doc improvement ideas for this session's scope.

## session classification

implementation-ready

## exact problem statement

The open group conversation already applies messages that arrive through `groupMessageStream` and reloads on app resume. The residual gap is local-only outgoing status changes from repository/retry/sweep paths: they update the DB, but an already-open group screen can keep showing the old failed/sending/pending state until a self-echo, stream message, resume reload, or route reload happens.

User-visible behavior to improve: when background or local retry/recovery updates an outgoing group row's status, the open conversation should reflect the status promptly and locally.

Behavior that must stay unchanged:

- Send retry/id-stability behavior from `text-retry-ui`, `text-continuation-id`, `voice-id-stable-retry`, and `timeout-pending-retry`.
- Existing self-echo/replay reconciliation.
- Existing resume reload.
- Existing media upload retry behavior.
- Existing notification and receive-side dedup behavior.

## files and repos to inspect next

Before implementation, re-read these exact files in the current dirty worktree:

- `lib/features/groups/domain/repositories/group_message_repository.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `test/shared/fakes/in_memory_group_message_repository.dart`
- `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `integration_test/group_recovery_e2e_test.dart`
- `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/core/services/pending_message_retrier.dart`
- `lib/core/lifecycle/handle_app_resumed.dart`
- `test/core/services/pending_message_retrier_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`

## existing tests covering this area

Existing coverage:

- `test/features/groups/domain/repositories/group_message_repository_impl_test.dart` covers `saveMessage`, `updateMessageStatus`, failed outgoing message loading, and stuck-sending recovery, but it does not currently assert a local outgoing status event stream.
- `test/features/groups/presentation/group_conversation_wired_test.dart` covers open-screen `groupMessageStream` updates, resume reload behavior, retry UI flows, restored text continuation, voice retry, and the older GIRD-002 resume refresh. It does not currently prove repo-local status changes update the screen without stream/resume.
- `test/core/services/pending_message_retrier_test.dart` covers retry ordering/timers for the background service, but not a group rows-changed UI signal.
- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart` covers resume group recovery ordering, including recover-stuck, incomplete uploads, failed retries, and inbox-store retry ordering.
- `integration_test/group_recovery_e2e_test.dart` now has group recovery simulator smokes for failed restored text continuation, failed voice re-record, missed group messages after resume drain, missed announcements, and dissolved cleanup. It does not yet specifically prove a local-status broadcast to an already-open screen.

Important current-code facts:

- `GroupMessageRepositoryImpl.saveMessage(...)` persists and emits flow telemetry, but no UI-facing stream.
- `GroupMessageRepositoryImpl.updateMessageStatus(...)` calls only `dbUpdateGroupMessageStatus(...)`.
- `GroupMessageRepositoryImpl.recoverStuckSendingMessages(...)` and `transitionSendingToFailed(...)` return only counts from the DB helper.
- `GroupConversationWired` subscribes to `groupMessageListener.groupMessageStream`, removed-group, reactions, and media progress. It reloads on resume and already has `_updateLocalMessageStatus(...)`.

## regression/tests to add first

Add the direct regressions before production edits:

1. `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`
   - RED: outgoing `saveMessage(existing.copyWith(status: 'sent'))` emits one local status event with `groupId`, `messageId`, and `status`.
   - RED: outgoing `updateMessageStatus(id, 'failed')` emits one local status event after the DB write succeeds.
   - RED: incoming saves/updates emit no outgoing local status event.
   - RED: same-status saves/updates emit no duplicate status event.
   - RED: `recoverStuckSendingMessages(...)` and `transitionSendingToFailed()` emit one batch rows-changed event only when the returned count is greater than zero.

2. `test/features/groups/presentation/group_conversation_wired_test.dart`
   - RED: while `GroupConversationWired` is mounted and no `groupMessageStream` event is emitted, a local outgoing status event for the open group updates the row status in the rendered `GroupConversationScreen`.
   - RED: an event for another group is ignored.
   - RED: a batch rows-changed event causes a scoped reload and picks up a `sending -> failed` row update without route reload or lifecycle resume.
   - RED: after unmount, emitting an event does not throw or call `setState`.

3. `integration_test/group_recovery_e2e_test.dart`
   - Add or extend a narrow group simulator smoke that mounts an open group screen with an outgoing failed/sending row, applies a local repository status change or batch sweep, emits no listener/self-echo event, and asserts the open screen reflects the new status.
   - Prefer the existing file to avoid gate-definition churn. If a new simulator file is unavoidable, update `Test-Flight-Improv/test-gate-definitions.md` and run `./scripts/run_test_gates.sh completeness-check`.

Only add `test/core/services/pending_message_retrier_test.dart` or `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart` regressions if implementation touches those production files.

## step-by-step implementation plan

1. Re-read the current dirty worktree and preserve prior-session changes. Do not revert modified files from accepted dependencies.
2. Add a small local-change value type and optional capability in `group_message_repository.dart`. Keep it repository-local and in-process. Suggested shape:
   - per-message status event: `groupId`, `messageId`, `status`
   - batch rows-changed event: `reloadRequired == true` or equivalent, for count-only sweeps
   - optional source interface, for example `GroupOutgoingLocalMessageChangeSource`, so existing `GroupMessageRepository` implementers are not forced into broad churn unless they opt in.
3. Implement the optional stream in `GroupMessageRepositoryImpl` with a broadcast controller.
   - `saveMessage(...)`: load the previous row before write, persist, then emit a per-message outgoing status event only if the saved row is outgoing and its status differs from the previous row or it is a new outgoing row whose status should be visible.
   - `updateMessageStatus(...)`: load previous row before write, persist, then emit only if the previous row exists, is outgoing, and the status changed.
   - `recoverStuckSendingMessages(...)` and `transitionSendingToFailed(...)`: emit one batch rows-changed event when count > 0.
   - Do not emit for incoming rows.
4. Update `test/shared/fakes/in_memory_group_message_repository.dart` to implement the same optional capability for widget/simulator tests, using the same emission rules.
5. In `GroupConversationWired`, subscribe when `widget.msgRepo is GroupOutgoingLocalMessageChangeSource`.
   - Store a dedicated subscription field.
   - For matching per-message status events, call existing `_updateLocalMessageStatus(messageId, status)`.
   - For batch rows-changed events, call `_loadMessages()`.
   - Ignore events for other groups.
   - Cancel on dispose and when the repository instance changes if that path exists in `didUpdateWidget`.
6. Keep `PendingMessageRetrier` and `handle_app_resumed` unchanged if repository-owned batch emission covers their count-only sweep callbacks. Touch them only if evidence shows the repository event cannot cover a required path; if touched, preserve current ordering and add direct ordering tests.
7. Extend `integration_test/group_recovery_e2e_test.dart` only narrowly for the simulator closure rule. Do not broaden it into final acceptance, duplicate notification, live/replay dedup, or timeout coverage.
8. Run format, direct tests, named gate, simulator gate, and `git diff --check`.
9. Stop if tests show current code already emits the needed events, but current evidence says it does not.

## risks and edge cases

- Event emitted before DB write would let the UI show uncommitted state. Emit only after successful writes.
- `recoverStuckSendingMessages(...)` has only a count, not ids. Use a batch reload event rather than inventing a broad DB query or schema change in this session.
- Adding a required member to `GroupMessageRepository` would force broad fake churn. Prefer an optional capability.
- Local status events can race with `groupMessageStream`; `_updateLocalMessageStatus` must remain idempotent.
- Batch reload can run after dispose or group change. Guard with `mounted` and current group filtering where possible.
- Incoming rows and remote self-echo handling must not be reclassified as local outgoing status changes.
- A status event for an unknown row in the currently open group should not add a synthetic row from event data alone. Either no-op for per-message status or use batch reload when ids are unavailable.

## exact tests and gates to run

Focused tests while developing:

```bash
flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart --plain-name "<new outgoing local status event test name>"
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "<new open screen local status event test name>"
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "<new open screen batch rows changed test name>"
```

Full direct suites:

```bash
flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart
flutter test test/features/groups/presentation/group_conversation_wired_test.dart
```

Conditional direct suites if production files are touched:

```bash
flutter test test/core/services/pending_message_retrier_test.dart
flutter test test/core/lifecycle/handle_app_resumed_group_recovery_test.dart
```

Simulator list and targeted group proof:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/group_recovery_e2e_test.dart
```

Named gate and final checks:

```bash
./scripts/run_test_gates.sh groups
dart format --output=none --set-exit-if-changed lib/features/groups/domain/repositories/group_message_repository.dart lib/features/groups/domain/repositories/group_message_repository_impl.dart lib/features/groups/presentation/screens/group_conversation_wired.dart test/shared/fakes/in_memory_group_message_repository.dart test/features/groups/domain/repositories/group_message_repository_impl_test.dart test/features/groups/presentation/group_conversation_wired_test.dart integration_test/group_recovery_e2e_test.dart
git diff --check
```

If a new simulator test file is added instead of extending `integration_test/group_recovery_e2e_test.dart`, also run:

```bash
./scripts/run_test_gates.sh completeness-check
```

## known-failure interpretation

Known carried residual:

- `./scripts/run_test_gates.sh groups` may fail only with `GCA-004 bridgeError recovery drains inbox after settled materialized invite` in `test/features/groups/integration/invite_round_trip_test.dart` at `invite_round_trip_test.dart:2930`, with `Expected: not null`, `Actual: <null>`.

Classification rules:

- If the groups gate fails only with that exact `GCA-004` signature, classify it as the known residual, not a `local-status-broadcasts` regression.
- Any failure in the new repository, wired-screen, simulator local-status proof, or formatting/diff checks is session-owned until fixed or explicitly reclassified with evidence.
- Any different `groups` gate failure is session-owned until triaged.

## done criteria

- Plan-owned event type/capability exists and is documented by tests.
- `GroupMessageRepositoryImpl` emits outgoing per-message local status events after successful `saveMessage` and `updateMessageStatus` status changes.
- Count-only outgoing rows-changed sweeps emit a batch reload event when they change at least one row.
- `GroupConversationWired` applies per-message status events in-place and batch events through `_loadMessages()` while mounted.
- Other groups and incoming rows are ignored.
- Subscription lifecycle is covered and safe.
- Required direct suites pass.
- Required simulator command passes, or a concrete device/simulator blocker is recorded and the session is not claimed fully closed on host tests alone.
- `./scripts/run_test_gates.sh groups` passes or fails only with the known `GCA-004` residual.
- `git diff --check` passes.

## scope guard

Do not change:

- status timestamp migration or any DB schema/migration
- reliable-send timeout values
- pending retry-payload fallback behavior
- failed text retry UI behavior
- restored text continuation/id reuse semantics
- recorded voice retry/upload behavior
- receive-side live/replay dedup
- notification routing, notification coalescing, or notification matrix docs
- final source-doc verdict, final breakdown verdict, or acceptance-doc closure
- bridge/native code or wire envelope contracts

Overengineering markers:

- Adding a global app event bus.
- Rewriting `GroupMessageRepository` as a fully reactive repository.
- Forcing every repository fake to implement a required stream member when an optional capability suffices.
- Adding DB queries or schema solely to recover ids from count-only sweeps in this session.
- Making local status events create missing messages from partial event data.

## accepted differences / intentionally out of scope

- Batch rows-changed events may reload the open group page instead of applying per-message ids for count-only sweeps. This is accepted because the current DB helper returns only a count, and adding affected-row discovery is broader than this UI refresh seam.
- Media attachment changes may still require existing media refresh paths or batch reloads. This session is about outgoing message status visibility, not media-state synchronization.
- A simulator proof may run the whole `integration_test/group_recovery_e2e_test.dart` file through the reliability wrapper, as prior accepted sessions did, even if the new local-status smoke is the row-owned scenario.
- Final source-doc/matrix closure stays out of scope and remains owned by `acceptance-doc-closure`.

## dependency impact

- This plan depends on accepted prior sessions `text-retry-ui`, `voice-id-stable-retry`, and `timeout-pending-retry` only as sources of hardened status transitions to observe. It must not alter their semantics.
- Later `status-timestamp-migration` may change which rows the stuck-sending sweep updates, but should still be able to use the batch rows-changed signal.
- Later `live-replay-dedup` should remain independent; this session does not alter incoming stream serialization or notification behavior.
- `acceptance-doc-closure` should use this session's closure evidence to mark the local-status-broadcasts row resolved, but final whole-doc verdict and matrix updates remain downstream.

## reviewer pass

Reviewer verdict: sufficient as-is, with only incremental execution details.

- Missing files/tests/gates: none structurally missing. The plan includes primary owner files, conditional retrier/resume files, direct repository/wired tests, the named `groups` gate, and the required group simulator wrapper.
- Stale assumptions: none found. Current evidence shows no UI-facing repository status stream, and `GroupConversationWired` currently listens to `groupMessageStream` plus lifecycle reloads, not local repository status events.
- Overengineering: the optional capability avoids broad fake churn and avoids a global event bus.
- Decomposition: narrow enough for implementation. It owns local outgoing status visibility only and explicitly excludes retry, schema, timeout, dedup, notification, and final closure work.
- Minimum needed for sufficiency: keep the simulator proof narrow and use concrete test names during execution.

## arbiter decision

Final arbiter verdict: execution-ready.

- Structural blockers: none.
- Incremental details intentionally deferred: choose concrete focused test names during execution; keep conditional retrier/resume tests only if those production files are touched.
- Accepted differences intentionally left unchanged: count-only sweeps may use a batch reload event instead of per-message status ids; final source-doc and matrix closure remain downstream.
- Stop rule: no structural blocker remains, so do not loop or broaden the plan.

## QA Review

QA reviewer verdict: no blocking issues found.

- Scope adherence: session-owned changes stay on the optional repository-local outgoing status stream, concrete/fake repository emissions, wired-screen subscription handling, direct regressions, and the narrow group recovery simulator smoke. No session-owned schema/migration, bridge/native, notification, receive-dedup, timeout, retry-semantics, final-doc, or breakdown-ledger acceptance change was found. The dirty worktree still contains unrelated/prior accepted changes, including `info.plist`, and those were preserved.
- Behavior sufficiency: `GroupMessageRepositoryImpl` emits per-message events only after successful status-changing `saveMessage`/`updateMessageStatus` writes for outgoing rows; incoming and unchanged-status paths are suppressed; `recoverStuckSendingMessages(...)` and `transitionSendingToFailed()` emit one batch rows-changed signal only when count > 0. `GroupConversationWired` subscribes only when the optional source exists, updates matching same-group per-message status events in place, reloads for batch events, ignores other groups, and cancels/resubscribes across dispose, group reset, and repository changes.
- Regression sufficiency: repository direct tests cover outgoing save/update events, incoming suppression, unchanged suppression, and positive/zero-count batch events. Wired widget tests cover in-place update without listener echo, other-group ignore, batch reload, unmount cancellation, and repository replacement. `integration_test/group_recovery_e2e_test.dart` includes the required open-screen local-status simulator smoke.
- Gate evidence: Executor-reported full direct repository and wired suites, simulator list, targeted group recovery simulator proof, format, and `git diff --check` are credible. QA spot-reran the focused repository event test, focused wired in-place update test, and `git diff --check`; all passed.
- Groups-gate classification: `/tmp/mknoon-local-status-groups.log` contains exactly one explicit `[E]` failure: `GCA-004 bridgeError recovery drains inbox after settled materialized invite` at `test/features/groups/integration/invite_round_trip_test.dart:2930`, `Expected: not null`, `Actual: <null>`. Later `GM-008` lines only carry the existing `-1` runner failure count, matching the Executor's focused green triage.

Blocking issues: none.

Non-blocking follow-up: carry the known unrelated `GCA-004` groups-gate residual to the downstream acceptance/gate owner.

## Final Execution/QA Verdict

Final verdict: `accepted_with_explicit_follow_up`.

Rationale: the local-status-broadcasts session meets its scope, done criteria, behavior requirements, direct regression requirements, simulator proof requirement, and hygiene checks. The only remaining failure evidence is the explicitly allowed known `GCA-004` residual from the broad `groups` gate, so it is not a session-owned blocker.
