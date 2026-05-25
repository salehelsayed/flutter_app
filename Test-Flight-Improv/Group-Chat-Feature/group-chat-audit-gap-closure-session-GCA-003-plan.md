Status: execution-ready

# GCA-003 - Group Creation Skipped-Member Warning/Failure Handling Plan

## Planning Progress

- 2026-05-23T17:38:18Z - Arbiter completed. Files inspected since last update: reviewer findings and full draft plan. Decision/blocker: no structural blockers; incremental details are documented as optional picker preservation only. Next action: hand off execution-ready plan.
- 2026-05-23T17:38:02Z - Reviewer completed. Files inspected since last update: draft plan artifact plus previously collected evidence. Decision/blocker: sufficient with no structural blocker; plan stays inside the three non-doc-file cap and uses a failing-first application test. Next action: arbiter classification and final status.
- 2026-05-23T17:37:03Z - Planner completed. Files inspected since last update: evidence set above. Decision/blocker: drafted narrow result-warning implementation plan using existing picker warning surface; no blocker. Next action: reviewer sufficiency pass.
- 2026-05-23T17:37:03Z - Evidence Collector completed. Files inspected since last update: `group-chat-audit-gap-closure-matrix.md`, `group-chat-audit-gap-closure-session-breakdown.md`, `create_group_with_members_use_case.dart`, `create_group_picker_wired.dart`, `create_group_with_members_use_case_test.dart`, `create_group_picker_wired_test.dart`, `test-gates-reference.md`, `test-inventory.md`, `scripts/run_test_gates.sh`, `in_memory_group_repository.dart`, `send_group_invite_use_case.dart`. Decision/blocker: no blocker; existing picker warning path can surface any `CreateGroupWithMembersResult.buildCreateWarningMessage()` result, so implementation can stay in the use case and focused application test. Next action: draft the execution-safe plan.
- 2026-05-23T17:35:43Z - Evidence Collector started. Files inspected since last update: user prompt only. Decision/blocker: source row `GCA-003`, source matrix, breakdown, and intended plan path confirmed from prompt. Next action: inspect breakdown, matrix row, current group creation use case, picker surface, and focused tests.

## Arbiter Decision

Structural blockers: none.

Incremental details:

- Optional picker preservation test is listed only if implementation touches picker wiring.

Accepted differences:

- The existing partial-create behavior remains accepted; this session makes skipped selected members observable rather than making group creation transactional.

Final verdict: execution-ready.

## Reviewer Findings

Plan sufficiency: sufficient as-is.

Missing files, tests, or gates: none. The only required implementation files are the use case and its focused test; the picker file is explicitly optional only if the existing result-warning snackbar path proves stale.

Stale or incorrect assumptions: none found. Current code still catches `addGroupMember` failures and emits only a flow event, while `CreateGroupPickerWired` still shows `buildCreateWarningMessage()` after successful create navigation.

Overengineering: none in the required path. The plan avoids retry, rollback, persistence, localization churn, and presentation rewrites.

Decomposition: narrow enough for implementation. The failing-first test names the exact seam and preserves the current subset truth behavior.

Minimum needed for sufficiency: no changes required.

## Real Scope

Change only the group-creation result/warning contract for selected contacts whose `addGroupMember` call fails during `createGroupWithMembers`.

The use case must keep the existing partial-create behavior: create the group, add the contacts that can be added, build config/publish/invite fanout from successfully added members only, and continue to exclude failed contacts from persisted members, config, publish payload, and invites.

The creator-facing warning should become observable through the existing `CreateGroupWithMembersResult.buildCreateWarningMessage()` path, which `CreateGroupPickerWired` already displays after successful navigation. No navigation, retry, rollback, invite, membership-limit, or picker loading behavior is in scope.

## Closure Bar

This session is good enough when a selected contact that fails during `addGroupMember`:

- is still not persisted, configured, published, or invited;
- is represented in the create result as an add-member failure;
- makes `CreateGroupWithMembersResult.hasWarnings` true;
- appears in `buildCreateWarningMessage()` with a clear "not added" style warning that can be shown by the existing picker snackbar path;
- is covered by a failing-first focused test.

## Source Of Truth

Primary row contract:

- `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-matrix.md` row `GCA-003`.
- `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-breakdown.md` session `GCA-003`.

Current code and tests win over stale prose if there is a disagreement.

Gate source of truth:

- `Test-Flight-Improv/test-gates-reference.md` for the `groups` named gate.
- `scripts/run_test_gates.sh` for the exact `groups` command expansion.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` for existing direct coverage in `create_group_with_members_use_case_test.dart` and `create_group_picker_wired_test.dart`.

## Session Classification

`implementation-ready`

## Exact Problem Statement

`createGroupWithMembers` catches failures from `addGroupMember`, emits `CREATE_GROUP_WITH_MEMBERS_ADD_MEMBER_ERROR`, and continues. The partial behavior is intentional, and an existing test already verifies failed contacts are excluded from persisted members, config, publish payload, and invite fanout. The gap is that the returned `CreateGroupWithMembersResult` does not record those add failures, so `hasWarnings` remains tied only to invite, config-sync, and publish degradations, and `buildCreateWarningMessage()` cannot tell the creator that selected members were skipped.

The user-visible improvement is a creator-visible warning after successful group creation when one or more selected contacts could not be added. Successful members and existing degradation warnings must keep working unchanged.

## Files And Repos To Inspect Next

Implementation candidates, capped to two non-doc files:

- `lib/features/groups/application/create_group_with_members_use_case.dart`
- `test/features/groups/application/create_group_with_members_use_case_test.dart`

Only inspect or touch `lib/features/groups/presentation/screens/create_group_picker_wired.dart` if the existing `buildCreateWarningMessage()` snackbar path is discovered to no longer surface result warnings. Current evidence says no picker change is needed.

Do not touch `create_group_picker_screen.dart`; it was changed by `GCA-002A` for contact loading/error states and is unrelated to this row.

## Existing Tests Covering This Area

- `test/features/groups/application/create_group_with_members_use_case_test.dart` has a focused test named `excludes failed add-member recipients from persisted members, config, publish payload, and invite fan-out`. It already injects a `saveMember` failure for `peer-bob` through `_FailingSaveMemberGroupRepository`, verifies `membersAdded == 2`, and verifies Bob is excluded from storage/config/publish/invites.
- The same application test file covers existing warning channels for invite delivery failures, missing secure keys, config-sync rollback, and `members_added` publish failure.
- `test/features/groups/presentation/create_group_picker_wired_test.dart` has a widget test proving `CreateGroupPickerWired` shows a snackbar when create succeeds with an invite-degradation warning. That covers the generic result-warning display path.

Missing coverage:

- No test currently requires add-member failures to set warning state or appear in `buildCreateWarningMessage()`.

## Regression/Tests To Add First

First, extend or add a focused application test in `test/features/groups/application/create_group_with_members_use_case_test.dart` for a selected contact failing `addGroupMember`.

Preferred failing-first approach:

- Extend the existing failed-add-member test or add a neighboring test that uses `_FailingSaveMemberGroupRepository(failingPeerIds: {'peer-bob'})`.
- Assert current subset behavior still holds.
- Add new expectations before implementation:
  - result exposes one failed add-member recipient for Bob;
  - `result.hasWarnings` is true;
  - `result.buildCreateWarningMessage()` is not null and contains Bob's display name plus language indicating the selected member was not added.

This should fail against current code because the result has no add-member failure field and `buildCreateWarningMessage()` ignores `CREATE_GROUP_WITH_MEMBERS_ADD_MEMBER_ERROR`.

## Step-By-Step Implementation Plan

1. Add the failing-first assertion/test in `create_group_with_members_use_case_test.dart`.
2. In `create_group_with_members_use_case.dart`, add a small result type or simple immutable data structure to represent selected-member add failures. Include `peerId`, display name/username, and enough information to describe the failure without exposing noisy exception text in the user-facing warning.
3. Track failures in the existing `catch` around `addGroupMember`, while preserving the current flow event.
4. Add the tracked failures to `CreateGroupWithMembersResult`.
5. Update `hasWarnings` so add-member failures count as warnings.
6. Update `buildCreateWarningMessage()` to include a concise selected-member warning, following the existing invite failure style and limiting long lists if necessary.
7. Return the add-member failures in both the normal success path and any early result path where applicable. For config-sync rollback, do not confuse rollback with per-member add failures; include only failures already observed before rollback if the implementation naturally tracks them, but keep rollback wording intact.
8. Run the focused failing-first test, then the full direct application test file. If the existing picker warning test remains enough evidence, do not add a picker test.
9. Run formatting/diff hygiene and the relevant group gate only after focused tests pass.

Stop if adding a creator-visible warning cannot be done through the existing result-warning path without touching more than three non-doc files.

## Risks And Edge Cases

- Do not leak raw exception strings into snackbar copy; they can be technical and unstable.
- Preserve partial success semantics: failed contacts remain excluded from config, publish payload, and invite fanout.
- Preserve invite-degradation warning composition when both member-add and invite failures happen.
- Avoid changing duplicate-contact behavior; deduped duplicates should not become warnings.
- Avoid changing `GCA-002A` contact loading/error state work in `create_group_picker_wired.dart` and `create_group_picker_screen.dart`.

## Exact Tests And Gates To Run

Failing-first selector:

```bash
flutter test --no-pub test/features/groups/application/create_group_with_members_use_case_test.dart --plain-name "excludes failed add-member recipients from persisted members, config, publish payload, and invite fan-out"
```

Direct regression file:

```bash
flutter test --no-pub test/features/groups/application/create_group_with_members_use_case_test.dart
```

Optional preservation check if implementation unexpectedly touches picker wiring:

```bash
flutter test --no-pub test/features/groups/presentation/create_group_picker_wired_test.dart --plain-name "shows an explicit warning when create succeeds with invite degradation"
```

Named gate:

```bash
./scripts/run_test_gates.sh groups
```

Diff hygiene:

```bash
git diff --check
```

## Known-Failure Interpretation

The current breakdown records the `groups` named gate as red on an unrelated isolated `group_membership_smoke_test.dart` `GM-028` failure after `GCA-001` and `GCA-002B`. If `./scripts/run_test_gates.sh groups` still fails only on that known unrelated `GM-028` symptom, classify it as residual-only for this session and rely on the focused application test plus diff hygiene for row closure. Any new failure in `create_group_with_members_use_case_test.dart`, invite degradation tests, picker warning tests, or a changed group-creation/invite failure must be treated as row-owned.

## Done Criteria

- `GCA-003` plan status is `execution-ready`.
- Failing-first test is identified and expected to fail before implementation.
- Implementation is constrained to no more than three non-doc files, with the expected path using two.
- The result warning contract makes selected add-member failures creator-observable through the existing picker snackbar path.
- Focused direct tests and gate commands are named exactly.

## Scope Guard

Non-goals:

- Do not make group creation fully transactional.
- Do not retry failed member adds.
- Do not add new dependencies.
- Do not restructure group creation, invite fanout, config sync, or picker navigation.
- Do not change contact loading/error UI from `GCA-002A`.
- Do not update matrix or breakdown closure rows during implementation; that belongs to the later closure audit.

Overengineering for this session would include new repositories, persistent failure models, retry queues, dialogs/modals, localization expansion beyond the existing warning-message style, or broad presentation rewrites.

## Accepted Differences / Intentionally Out Of Scope

- The group may still be created with a subset of selected members; this session only makes that subset outcome visible to the creator.
- Invite delivery failures are already modeled separately via `GroupInviteBatchResult`; do not merge member-add failures into invite attempts because failed members are not invite recipients.
- The picker does not need a new dedicated add-member warning test if the generic result-warning snackbar path remains covered.

## Dependency Impact

Closing this plan unblocks the row-owned `GCA-003` gap without changing later sessions. If implementation discovers the picker no longer surfaces `buildCreateWarningMessage()`, the session may need to touch `create_group_picker_wired.dart`; if that would exceed the three non-doc-file cap, stop and return blocked instead of broadening.

Later closure should update:

- source matrix row `GCA-003`;
- breakdown ledger row `GCA-003`;
- closure progress notes with focused test evidence and any residual named-gate classification.

## Execution Progress

- 2026-05-23T17:39:26Z - Contract extracted. Files inspected: this plan, session breakdown, source matrix, `lib/features/groups/application/create_group_with_members_use_case.dart`, `test/features/groups/application/create_group_with_members_use_case_test.dart`. Decision/blocker: no nested subagent tooling is available, so execution is using the local sequential fallback authorized by the prompt; scope is limited to the use case, focused test, and this progress section. Next action: add failing-first expectations to the existing failed add-member test and run the focused selector.
- 2026-05-23T17:40:01Z - Executor fallback running. Files touched: `test/features/groups/application/create_group_with_members_use_case_test.dart`. Decision/blocker: added failing-first expectations for add-member failure exposure, warning state, and warning copy while preserving existing subset assertions. Command starting: `flutter test --no-pub test/features/groups/application/create_group_with_members_use_case_test.dart --plain-name "excludes failed add-member recipients from persisted members, config, publish payload, and invite fan-out"`. Next action: confirm RED, then implement the minimal result/warning contract.
- 2026-05-23T17:40:21Z - RED confirmed. Files inspected: focused test output. Decision/blocker: selector fails at compile time because `CreateGroupWithMembersResult.addMemberFailures` is missing, which matches the planned gap. Next action: add an immutable add-member failure result, track failures in the existing catch block, and include them in warnings without changing partial-create behavior.
- 2026-05-23T17:41:34Z - Executor fallback implementation completed. Files touched: `lib/features/groups/application/create_group_with_members_use_case.dart`, `test/features/groups/application/create_group_with_members_use_case_test.dart`. Decision/blocker: result now exposes add-member failures and warning copy while the existing added-member subset drives config, publish, and invite fanout. Command finished: `dart format lib/features/groups/application/create_group_with_members_use_case.dart test/features/groups/application/create_group_with_members_use_case_test.dart` passed. Next action: rerun the focused selector, then the direct application test file.
- 2026-05-23T17:41:53Z - Focused selector passed. Files inspected: focused test output and scoped diff. Command finished: `flutter test --no-pub test/features/groups/application/create_group_with_members_use_case_test.dart --plain-name "excludes failed add-member recipients from persisted members, config, publish payload, and invite fan-out"` passed. Decision/blocker: no picker warning-path change needed because the existing result warning builder is now populated. Next action: run the full direct application test file.
- 2026-05-23T17:42:16Z - Direct application suite passed. Files inspected: full direct test output and scoped status. Command finished: `flutter test --no-pub test/features/groups/application/create_group_with_members_use_case_test.dart` passed. Decision/blocker: focused application behavior is green; changed files remain within scope. Next action: run `./scripts/run_test_gates.sh groups` and `git diff --check`.
- 2026-05-23T17:45:13Z - Named gate and diff hygiene finished. Files inspected: gate output, filtered failure summary, scoped diff stat. Commands finished: `git diff --check` passed; `./scripts/run_test_gates.sh groups` failed. Decision/blocker: gate failures are outside the GCA-003 touched use-case/test seam and include concurrent dirty-tree invite/recovery/membership symptoms (`BB-007`, `IJ005`, startup/rejoin replay cases, `GE-017`/`GE-019`/`GE-020`, `GM-029`, and known `GM-028`); no failure occurred in `create_group_with_members_use_case_test.dart` or the row-owned add-member warning behavior. Next action: run local QA sufficiency review against scope, behavior, and required evidence.
- 2026-05-23T17:45:46Z - Local QA completed. Files inspected: scoped code/test diff and touched line ranges. Decision/blocker: no row-owned blocking issues remain; the implementation preserves partial-create semantics, excludes failed members from persisted/config/publish/invite paths, and surfaces add-member failures through `hasWarnings` plus `buildCreateWarningMessage()`. The required named gate remains red on unrelated/concurrent integration failures, so final session verdict is `accepted_with_explicit_follow_up` rather than clean `accepted`. Next action: rerun final diff hygiene and report execution verdict.
- 2026-05-23T17:46:10Z - Final verdict written. Files inspected: `git status --short`, scoped diff stat, final `git diff --check`. Command finished: final `git diff --check` passed. Decision/blocker: session complete with verdict `accepted_with_explicit_follow_up`; follow-up is limited to unrelated/concurrent groups-gate failures outside GCA-003.
