# GCA-007 Unauthorized Or Missing-Group Send Error Surface Plan

Status: execution-ready

## Planning Progress

- 2026-05-23T19:55:02+02:00 - Arbiter completed. Files inspected since last update: reviewer findings, draft plan sections, scope guard, test/gate contract, and stop rule. Decision/blocker: no structural blockers remain; incremental voice-parity wording is intentionally constrained rather than expanded. Next action: hand off execution-ready plan.
- 2026-05-23T19:54:33+02:00 - Arbiter started. Files inspected since last update: reviewer findings and adjusted draft. Decision/blocker: no structural blocker found; one wording issue was corrected so the plan does not imply a new helper abstraction. Next action: classify reviewer findings and finalize status.
- 2026-05-23T19:54:33+02:00 - Reviewer completed. Files inspected since last update: full plan draft. Decision/blocker: sufficient with adjustment; missing test/gate contract, closure bar, scope guard, and hard file cap are present. Adjustment made: progress wording changed from helper to existing snackbar path. Next action: start Arbiter.
- 2026-05-23T19:53:11+02:00 - Reviewer started. Files inspected since last update: full draft plan sections and evidence set. Decision/blocker: draft written with a two-file implementation path and hard three-file cap; needs sufficiency review for test/gate contract and scope drift. Next action: review the plan against mandatory sections and stop rules.
- 2026-05-23T19:53:11+02:00 - Planner completed. Files inspected since last update: collected evidence and existing GCA plan format. Decision/blocker: drafted a narrow TDD plan for user-facing feedback on terminal send results without changing send use-case semantics, retry behavior, or matrix/breakdown closure. Next action: start Reviewer.

## Arbiter Decision

Structural blockers: none.

Incremental details intentionally deferred:

- A dedicated voice unauthorized/not-found widget test is not required for this session unless the executor changes voice-specific recording behavior. Same-file mirroring of the existing terminal-result branch is allowed only to avoid leaving identical send results silent.

Accepted differences:

- `unauthorized` and `groupNotFound` remain terminal non-retryable UI outcomes.
- `groupDissolved` remains separate and keeps its existing refresh plus dissolved feedback.
- Stale-send prevention is not broadened here; this session surfaces the terminal error when a stale send reaches the use case.

Final verdict: execution-ready.

## Reviewer Findings

Plan sufficiency: sufficient with one adjustment already applied.

Missing files, tests, regressions, or gates: none. The plan names the expected two non-doc files, direct failing-first selectors, direct full widget suite, preservation selectors, `./scripts/run_test_gates.sh groups`, `git diff --check`, and one manual verification step.

Stale or incorrect assumptions: no blocker found. The missing-group test relies on the current test setup key and stale widget snapshot; if that seam proves stale during execution, the executor should adapt within `group_conversation_wired_test.dart` rather than touching repositories or use-case logic.

Overengineering: the draft correctly rejects send-use-case changes, localization churn, new retry state, modals, and new abstractions. The only wording issue was a progress entry that implied a helper; it was changed to the existing snackbar path.

Decomposition: narrow enough for implementation. The ordinary text tests prove the user-visible gap directly, while voice parity is constrained to a same-file mirror only if the executor sees the same existing terminal branch.

Minimum needed for sufficiency: no further plan changes required.

## Evidence Summary

- `GCA-007` is open in `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-matrix.md` and is classified `implementation-ready` in the breakdown.
- `GroupConversationWired._onSend` creates an optimistic `sending` message, calls `sendGroupMessage`, and removes the optimistic message for `SendGroupMessageResult.groupNotFound`, `groupDissolved`, and `unauthorized`. Only `groupDissolved` currently shows `This group has been dissolved`.
- The voice send path has a similar terminal-result branch. The session should not invent new voice behavior, but any ordinary-send terminal-result copy added in `GroupConversationWired` should not leave an obvious same-result voice branch silently inconsistent if the executor can mirror it inside the same file.
- `sendGroupMessage` returns `groupNotFound` when `groupRepo.getGroup(groupId)` is null and `unauthorized` for announcement non-admin sends, removed/non-member senders, and unbound sender devices. Those result classifications are application-layer behavior and are not the target of this session.
- Existing focused tests in `group_conversation_wired_test.dart` cover successful optimistic send, publish failure retry behavior, group-not-found/unauthorized ordinary media cleanup, stale removed send guards, dissolved read-only UI, and dissolved reaction feedback. Missing coverage is a concrete user-visible error for ordinary text `groupNotFound` and `unauthorized` terminal send results.
- `Test-Flight-Improv/test-gate-definitions.md` says `./scripts/run_test_gates.sh groups` is the named gate for group send behavior changes; the script remains the command source of truth.

## Real Scope

Show a concrete user-facing error when a stale group conversation send reaches `SendGroupMessageResult.unauthorized` or `SendGroupMessageResult.groupNotFound`.

The expected implementation path is limited to `GroupConversationWired` and its focused widget test file. It should preserve existing terminal cleanup: the optimistic message may still be removed for terminal not-found/unauthorized results, durable media cleanup should remain intact, and these terminal results should not become retryable failed rows.

Do not change `sendGroupMessage` result classification, bridge commands, group repository semantics, media upload behavior, voice recording lifecycle, group dissolution behavior, or the matrix/breakdown closure docs in this implementation session.

## Closure Bar

This session is good enough when:

- ordinary text send returning `unauthorized` shows a visible error such as `You no longer have permission to send messages in this group.`;
- ordinary text send returning `groupNotFound` shows a visible error such as `This group is no longer available.`;
- the optimistic message is not left visible as a successful or retryable row for those terminal results;
- `groupDissolved` still refreshes the visible group and shows the existing dissolved feedback;
- publish failures and upload failures still use the existing failed-row/draft/quote retry behavior;
- the behavior is pinned by failing-first focused widget tests.

## Source Of Truth

Primary row contract:

- `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-matrix.md` row `GCA-007`.
- `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-breakdown.md` session `GCA-007`.

Current code and tests win over stale prose if they disagree with planning text.

Gate source of truth:

- `Test-Flight-Improv/test-gate-definitions.md` for when the `groups` named gate applies.
- `scripts/run_test_gates.sh` for exact named-gate execution.

## Session Classification

`implementation-ready`

## Exact Problem Statement

When a group conversation screen is stale, the composer can still start an optimistic send. If the use case returns `groupNotFound` or `unauthorized`, `GroupConversationWired` removes the optimistic message and cleans up any local media state, but it does not tell the user what happened. The user sees their just-sent message disappear with no explanation.

The user-visible improvement is a clear transient error for these terminal send results. Existing dissolved-group feedback, terminal cleanup, and retry behavior for ordinary publish/upload failures must stay unchanged.

## Files And Repos To Inspect Next

Implementation candidates, capped to two expected non-doc files:

- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`

Inspect only, do not modify unless evidence disproves the plan:

- `lib/features/groups/application/send_group_message_use_case.dart`
- `test/shared/fakes/in_memory_group_repository.dart`
- `test/shared/fakes/in_memory_group_message_repository.dart`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`

Hard cap: the eventual implementation must touch no more than 3 non-doc implementation/test files. If the executor finds the fix requires a fourth non-doc file, they must stop and ask before editing it.

## Existing Tests Covering This Area

- `group_conversation_wired_test.dart` has optimistic text-send coverage proving a sending row appears before `group:publish` completes and is updated on success.
- The same file has publish failure coverage proving failed publish keeps a visible failed row and preserves retry affordance behavior.
- The same file has ordinary media `groupNotFound` and `unauthorized` cleanup tests proving terminal results remove pre-persisted media state and do not publish.
- The same file has stale membership/send guard and dissolved-group UI tests proving read-only and dissolved states stay protected.

Missing coverage:

- No focused widget test requires a snackbar or other visible error when ordinary text send returns `unauthorized`.
- No focused widget test requires a snackbar or other visible error when ordinary text send returns `groupNotFound`.

## Regression/Tests To Add First

Add failing-first widget coverage in `test/features/groups/presentation/group_conversation_wired_test.dart` before changing production code.

Preferred tests:

1. `unauthorized text send shows a concrete error instead of disappearing silently`
   - Build with a stale writable widget snapshot, for example `makeAnnouncementGroup(role: GroupRole.admin)`, while the repository has the same group as `GroupRole.member`.
   - Enter text, tap send, and pump.
   - Assert the sent text is not left as a successful/failed retry row.
   - Assert no `group:publish` happened.
   - Assert a visible snackbar/error text such as `You no longer have permission to send messages in this group.` appears.

2. `missing-group text send shows a concrete error instead of disappearing silently`
   - Build with `makeChatGroup()` but do not save that group to `groupRepo`; keep the existing test setup key so the stale composer can attempt send.
   - Enter text, tap send, and pump.
   - Assert the sent text is not left as a successful/failed retry row.
   - Assert no `group:publish` happened.
   - Assert a visible snackbar/error text such as `This group is no longer available.` appears.

These tests should fail against current code because the terminal branches remove the optimistic message without showing feedback for `unauthorized` or `groupNotFound`.

## Step-By-Step Implementation Plan

1. Confirm the direct widget test file is otherwise usable in the dirty worktree; do not revert unrelated edits.
2. Add the two failing-first widget tests above in `group_conversation_wired_test.dart`, close to the existing optimistic send or terminal media cleanup tests.
3. Run the two focused selectors and confirm they fail because the expected snackbar/error text is missing.
4. In `group_conversation_wired.dart`, update the existing terminal-result branch in `_onSend` so `groupNotFound` and `unauthorized` show a floating snackbar after local cleanup. Keep `groupDissolved` behavior unchanged.
5. Inspect the nearby voice-send terminal-result branch. If it has the same `groupNotFound`/`unauthorized` silent cleanup, mirror only the same snackbar calls inside that existing branch in the same file. Do not add new voice-specific flow, retry behavior, or abstractions.
6. Do not add a new public API, repository method, localization pass, dialog, retry queue, or shared abstraction. Use the existing `_showFloatingSnackBar` helper.
7. Run the focused selectors again, then the full direct widget file.
8. Run the required gate/diff commands and record any known residual gate failures distinctly from row-owned failures.
9. Stop and ask if any required fix would exceed the 3 non-doc-file cap, require send-use-case result changes, or require product behavior beyond terminal send feedback.

## Risks And Edge Cases

- A stale writable widget snapshot can differ from the repository group state; tests should model that explicitly instead of changing read-only composer rules.
- Terminal `unauthorized` and `groupNotFound` results should not create retryable failed rows; those are not transient publish failures.
- Do not break `groupDissolved`, which already refreshes the visible group and disables future writes.
- Do not break media cleanup for ordinary media terminal results or pending upload directory cleanup.
- Do not alter publish failure behavior, where the existing failed row and retry affordance are intentional.
- Avoid raw exception text in user-visible copy.

## Exact Tests And Gates To Run

Failing-first selectors:

```bash
flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "unauthorized text send shows a concrete error instead of disappearing silently"
flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "missing-group text send shows a concrete error instead of disappearing silently"
```

Direct regression file:

```bash
flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart
```

Targeted preservation selectors:

```bash
flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "failed publish shows message with failed status"
flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "dissolved groups show read-only copy and no send controls"
```

Named group gate:

```bash
./scripts/run_test_gates.sh groups
```

Diff hygiene:

```bash
git diff --check
```

Manual verification step:

```text
In a debug build, open a group conversation from a writable stale screen, remove the sender's ability to send or delete the group from another path/device, then attempt one text send; verify the optimistic text disappears with a visible no-permission or group-unavailable snackbar and no retryable failed row remains.
```

## Known-Failure Interpretation

Failures in the two new focused selectors are row-owned.

Failures in `group_conversation_wired_test.dart` are row-owned if they involve send result handling, optimistic row cleanup, snackbar feedback, dissolved groups, publish failure retry behavior, media cleanup, or composer writable state.

For `./scripts/run_test_gates.sh groups`, investigate failures. The source matrix and prior GCA closure notes document residual unrelated failures around `group_membership_smoke_test.dart` `GM-028` and other concurrent group integration symptoms. A groups-gate failure may be classified as residual-only for this session only if focused `group_conversation_wired_test.dart` coverage passes, an isolated rerun confirms the failing selector is unrelated to `GroupConversationWired` send-result feedback, and the failure is not diff-linked to the two expected files.

## Done Criteria

- Plan status is `execution-ready`.
- Failing-first tests are named and expected to fail before implementation.
- The expected implementation touches only `group_conversation_wired.dart` and `group_conversation_wired_test.dart`.
- The hard cap of no more than 3 non-doc implementation/test files is preserved.
- Unauthorized and missing-group terminal sends show concrete user-facing feedback.
- Existing dissolved handling and failed publish retry behavior stay unchanged.
- Exact direct tests, named gate, diff hygiene, known-failure handling, and one manual verification step are documented.

## Scope Guard

Non-goals:

- Do not modify `send_group_message_use_case.dart`.
- Do not change when `SendGroupMessageResult.unauthorized`, `groupNotFound`, `groupDissolved`, or `error` are returned.
- Do not introduce retry for terminal authorization/not-found results.
- Do not restore drafts or quote state for terminal results unless the failing-first test proves existing behavior already requires it.
- Do not add localization, modals, banners, new state models, repositories, migrations, or telemetry contracts.
- Do not edit the source matrix or session breakdown during implementation; closure docs belong to the later closure/audit step.
- Do not refactor `GroupConversationWired` or add abstractions; keep edits local to the existing result branches and existing snackbar helper.

Overengineering for this session would include a generic send-error framework, route-level stale-group recovery, cross-screen permission synchronization, bridge/use-case rewrites, or broad composer state redesign.

## Accepted Differences / Intentionally Out Of Scope

- `groupDissolved` remains a distinct result with existing copy and visible group refresh.
- `unauthorized` and `groupNotFound` remain terminal, non-retryable outcomes in this UI.
- The session does not attempt to prevent every stale send before it starts; `GCA-006` owns missing-identity/silent-send guard work, and other stale permission prevention can remain separate.
- Voice-specific recording UX is not expanded. If the same terminal-result branch is touched in the same file, it should only mirror the ordinary-send snackbar copy without adding new voice tests unless the executor changes voice-specific behavior.

## Execution Progress

- 2026-05-23T20:31:15+02:00 - Controller contract extraction started. Files inspected/touched: `implementation-execution-qa-orchestrator/SKILL.md`, this plan, `git status --short`, and Codex CLI availability. Decision/blocker: spawned-agent path appears available through `codex exec`; dirty worktree includes row-owned files and many unrelated files, so execution must avoid reverting external edits. Next action: inspect current row-owned files and gate definitions.
- 2026-05-23T20:31:15+02:00 - Controller contract extracted. Files inspected/touched: `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `Test-Flight-Improv/test-gate-definitions.md`, `scripts/run_test_gates.sh`. Decision/blocker: scope remains capped to ordinary text terminal feedback in the existing send result branch, with same-file voice parity allowed; required direct tests and `./scripts/run_test_gates.sh groups` confirmed. Next action: spawn Executor agent for failing-first tests and minimal implementation.
- 2026-05-23T20:34:08+02:00 - Executor started and owner files inspected. Files inspected/touched: this plan, `git status --short`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, and `lib/features/groups/application/send_group_message_use_case.dart` for result evidence only. Decision/blocker: no blocker; dirty unrelated files remain untouched, and implementation still fits the two expected row-owned files. Next action: add failing-first focused widget tests.
- 2026-05-23T20:35:40+02:00 - Failing-first widget tests added and RED confirmed before production changes. Files inspected/touched: `test/features/groups/presentation/group_conversation_wired_test.dart`. Commands: `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "unauthorized text send shows a concrete error instead of disappearing silently"` failed because the no-permission snackbar text was missing; `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "missing-group text send shows a concrete error instead of disappearing silently"` failed because the group-unavailable snackbar text was missing. Decision/blocker: expected RED state captured; row-owned behavior is missing only snackbar feedback. Next action: update existing terminal result branches in `group_conversation_wired.dart`.
- 2026-05-23T20:36:27+02:00 - Minimal implementation landed. Files inspected/touched: `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`. Decision/blocker: ordinary text `unauthorized` and `groupNotFound` now use existing `_showFloatingSnackBar`; the same silent voice terminal branch mirrors the same snackbar calls only. `groupDissolved` behavior and copy are unchanged. Next action: rerun focused selectors and required gates.
- 2026-05-23T20:39:41+02:00 - Required direct tests and gates completed. Files inspected/touched: `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, this plan. Commands/results: `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "unauthorized text send shows a concrete error instead of disappearing silently"` passed after implementation; `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "missing-group text send shows a concrete error instead of disappearing silently"` passed after implementation; `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart` failed with 17 existing send-path failures where fixtures without active members now return `groupDissolved`/`empty_membership` before publish; `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "failed publish shows message with failed status"` failed for the same empty-membership pre-publish path; `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "dissolved groups show read-only copy and no send controls"` passed; `./scripts/run_test_gates.sh groups` failed with 13 group integration failures including GM-028/GM-029 membership convergence cases; isolated rerun `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name "GM-028 empty PeerId add event does not persist or block valid delivery"` reproduced the GM-028 failure outside row-owned files; `git diff --check` passed. Decision/blocker: GCA-007 focused behavior is green, but required broad suite/gate evidence remains red from pre-existing/unrelated membership and fixture failures outside this session's allowed scope. Next action: hand off to QA reviewer with residual failures called out.
- 2026-05-23T20:39:41+02:00 - Executor completed. Files inspected/touched: `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, this plan only for GCA-007. Decision/blocker: implementation stayed within the expected two non-doc files and did not update source matrix or breakdown; no additional GCA-007 code changes are pending. Required red suite/gate residuals remain for QA classification.
- 2026-05-23T20:41:08+02:00 - QA Reviewer spawned. Files inspected/touched: this plan. Decision/blocker: awaiting independent sufficiency review of scope adherence, focused passing selectors, failed required direct suite/preservation selector, failed groups gate, and residual classification. Next action: wait for QA verdict.
- 2026-05-23T20:43:28+02:00 - QA Reviewer inspected landed GCA-007 diff and reran focused selectors. Files inspected/touched: this plan, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`. Commands/results: `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "missing-group text send shows a concrete error instead of disappearing silently"` passed; a concurrent rerun of the unauthorized selector hit Flutter startup/native-asset lock, then serial rerun `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "unauthorized text send shows a concrete error instead of disappearing silently"` passed. Decision/blocker: targeted snackbar behavior appears landed.
- 2026-05-23T20:43:28+02:00 - QA Reviewer reran required preservation selector. Files inspected/touched: this plan only. Command/result: `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "failed publish shows message with failed status"` failed at `test/features/groups/presentation/group_conversation_wired_test.dart:4370`; flow logs show `GROUP_SEND_MSG_USE_CASE_EMPTY_MEMBERSHIP_DISSOLVED` and `outcome":"group_dissolved"` before publish, so the expected failed row text `Will fail` is absent. Decision/blocker: blocking issue; this is required direct evidence and row-owned under the plan's known-failure rule for publish-failure retry behavior. Fix-pass Executor required before completion.
- 2026-05-23T20:44:24+02:00 - Fix-pass Executor 1 spawned. Files inspected/touched: this plan. Decision/blocker: fix pass must address QA blocking issue without broadening GCA-007; prefer same-file fixture correction if current tests no longer reach publish because they omit active members. Next action: wait for fix-pass result.
- 2026-05-23T20:57:31+02:00 - Fix-pass Executor 1 inspected current plan progress, row-owned diff, and failed selector region. Files inspected/touched: this plan, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `scripts/run_test_gates.sh`, and related read-only send/membership evidence. Command/result: `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "failed publish shows message with failed status"` reproduced the QA failure with `GROUP_SEND_MSG_USE_CASE_EMPTY_MEMBERSHIP_DISSOLVED` before `group:publish`. Decision/blocker: failure was a stale widget-test fixture, not GCA-007 snackbar production behavior. Next action: patch only `group_conversation_wired_test.dart`.
- 2026-05-23T20:57:31+02:00 - Fix-pass fixture correction landed. Files inspected/touched: `test/features/groups/presentation/group_conversation_wired_test.dart` and this plan. Change: added a small `saveActiveGroupMembers` fixture helper and applied it only to direct send-path tests that must reach publish/send behavior; added the missing key to the delayed not-found repository fixture that replaces the default setup repository. Decision/blocker: no production code changed; non-doc changes remain within the two allowed row-owned files.
- 2026-05-23T20:57:31+02:00 - Required direct selectors completed after fix-pass. Files inspected/touched: `test/features/groups/presentation/group_conversation_wired_test.dart`. Commands/results: `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "failed publish shows message with failed status"` passed; `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "unauthorized text send shows a concrete error instead of disappearing silently"` passed; `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "missing-group text send shows a concrete error instead of disappearing silently"` passed; `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "dissolved groups show read-only copy and no send controls"` passed. Decision/blocker: required focused snackbar and preservation selectors are green.
- 2026-05-23T20:57:31+02:00 - Required direct file and hygiene completed. Files inspected/touched: `test/features/groups/presentation/group_conversation_wired_test.dart`, this plan. Commands/results: `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart` passed (`+88`); `git diff --check` passed. Decision/blocker: direct widget file is green and diff hygiene is clean. Next action: run required groups gate.
- 2026-05-23T20:57:31+02:00 - Required groups gate completed. Files inspected/touched: this plan only. Command/result: `./scripts/run_test_gates.sh groups` failed with combined gate result `+288 -13`. Diagnostic JSON reporter extraction over the same six gate files listed these failing selectors: `BB-007 accepted pending invite joins with exact full config and replays accepted epoch`; `IJ005 multi-use direct credential replay is duplicate-safe`; `BB-012 restart recovery drains replay before ack and stays live`; `NW-004 reconnect recovery stays live after ack across multiple groups`; `IR-018 restart recovery keeps recovering state until replay drains and live stays active`; `PL-004 quote ids survive live replay and re-add visibility boundaries`; `IR-003 timestamp replay boundary drains same-ms fake-network messages once`; `ST-004 clock skew fake-network replay keeps relay boundary exact`; `GE-017 seeded random membership operations preserve invariants`; `GE-019 seeded random key rotations preserve access windows`; `GE-020 long soak private group with churn preserves convergence`; `GM-029 config version monotonicity converges across A/B/C shuffled delivery`; `GM-028 empty PeerId add event does not persist or block valid delivery`. Decision/blocker: direct GCA-007 widget evidence is green; the named groups gate remains red in integration membership/replay/startup coverage outside the two GCA-007 row-owned files. Next action: hand off to QA for classification; no executor-side production change pending.
- 2026-05-23T20:57:31+02:00 - Final fix-pass hygiene rerun completed after plan-note edit. Files inspected/touched: this plan. Command/result: `git diff --check` passed. Decision/blocker: no whitespace hygiene issue remains.
- 2026-05-23T20:59:05+02:00 - QA Reviewer 2 spawned after fix-pass. Files inspected/touched: this plan. Decision/blocker: awaiting independent classification of the green direct widget evidence and red `groups` integration gate residuals.
- 2026-05-23T21:03:26+02:00 - QA Reviewer 2 inspected landed GCA-007 diff and scope. Files inspected/touched: this plan, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `scripts/run_test_gates.sh`, and `Test-Flight-Improv/test-gate-definitions.md`; only this plan was edited for QA notes. Decision/blocker: GCA-007 implementation stays within the two allowed non-doc row-owned files, adds no dependency, keeps terminal unauthorized/not-found sends non-retryable, preserves dissolved handling, and does not edit source matrix or breakdown.
- 2026-05-23T21:03:26+02:00 - QA Reviewer 2 reran required direct evidence. Files inspected/touched: this plan only. Commands/results: `git diff --check` passed; `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "unauthorized text send shows a concrete error instead of disappearing silently"` passed; `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "missing-group text send shows a concrete error instead of disappearing silently"` passed; `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "failed publish shows message with failed status"` passed; `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart` passed (`+88`). Decision/blocker: no row-owned direct failure remains.
- 2026-05-23T21:03:26+02:00 - QA Reviewer 2 classified required groups gate residuals via recorded executor `./scripts/run_test_gates.sh groups` failure plus targeted machine extraction over the six `GROUP_TESTS` files from `scripts/run_test_gates.sh`. Files inspected/touched: this plan only. Command/result: `flutter test --no-pub --machine test/features/groups/integration/group_messaging_smoke_test.dart test/features/groups/integration/group_resume_recovery_test.dart test/features/groups/integration/group_edge_cases_smoke_test.dart test/features/groups/integration/invite_round_trip_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_startup_rejoin_smoke_test.dart` produced `done success=false` with 13 failures (`BB-007`, `IJ005`, `BB-012`, `NW-004`, `IR-018`, `PL-004`, `IR-003`, `ST-004`, `GE-017`, `GE-019`, `GE-020`, `GM-029`, `GM-028`). Decision/blocker: residual failures are integration membership/replay/startup coverage outside the two GCA-007 row-owned files and outside unauthorized/missing-group send snackbar behavior.
- 2026-05-23T21:03:26+02:00 - QA Reviewer 2 completed with verdict `pass-with-residuals`. Files inspected/touched: this plan only. Decision/blocker: no fix-pass executor required for GCA-007; remaining red groups-gate selectors are out of GCA-007 scope and should remain residuals for later closure/audit tracking.

## Dependency Impact

Closing this plan resolves only source matrix row `GCA-007`.

Later closure work should update:

- source matrix row `GCA-007`;
- breakdown ledger row `GCA-007`;
- closure notes with focused selector results, direct widget suite result, groups-gate result or residual classification, and `git diff --check`.

If this plan changes to require send-use-case edits or more than 3 non-doc files, later sessions that assume terminal group send results are stable should pause until the new scope is reviewed.
