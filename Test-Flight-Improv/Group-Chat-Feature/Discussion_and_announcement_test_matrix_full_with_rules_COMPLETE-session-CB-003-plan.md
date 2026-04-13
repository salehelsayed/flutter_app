# Session CB-003 Plan - Partial create member-add failure yields a truthful subset

## Final verdict

`implementation-ready`

## Final plan

### real scope

- Resolve source row `CB-003` only: partial per-member add failure during
  create yields a truthful successful subset.
- Prefer no production code changes.
- Add the narrowest regression proof in
  `test/features/groups/application/create_group_with_members_use_case_test.dart`
  so the repo proves that failed add-member recipients are excluded from:
  - persisted membership
  - `group:updateConfig`
  - `members_added` publish payload
  - invite fan-out recipients
- Touch `test/features/groups/presentation/create_group_picker_wired_test.dart`
  only if the current use-case seam cannot prove the row-owned user-visible
  contract without one picker-level assertion.
- Update only the row truth in:
  - `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
  - `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
  - `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`

### closure bar

- The repo has direct automated proof that a create flow with mixed member-add
  outcomes keeps the created group while exposing only the successfully added
  subset as members.
- The same proof shows failed recipients are absent from the generated
  `groupConfig`, absent from the `members_added` system payload, and absent
  from invite fan-out.
- Required direct tests pass.
- The source matrix row can be updated truthfully from `Partial` to `Covered`
  with file-and-test evidence tied to `CB-003`.

### source of truth

- Active breakdown contract:
  `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`
- Source matrix:
  `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- Repo coverage inventory:
  `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- Gate definitions:
  `Test-Flight-Improv/test-gate-definitions.md`
- Current code/tests beat stale prose when they disagree.
- Verified seam files:
  - `lib/features/groups/application/create_group_with_members_use_case.dart`
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `lib/features/groups/application/send_group_invite_use_case.dart`
  - `test/features/groups/application/create_group_with_members_use_case_test.dart`
  - `test/features/groups/presentation/create_group_picker_wired_test.dart`

### session classification

`implementation-ready`

### exact problem statement

- The current create-with-members implementation already catches per-contact
  add failures and only fans invites out to successfully added members.
- The repo does not yet pin that exact row-owned contract with a direct
  regression that forces one add-member failure during create and then checks
  the full successful subset truth.
- This session should prove the existing behavior first. Only if the regression
  disproves the contract should production code change.

### files and repos to inspect next

- Primary implementation seam:
  - `lib/features/groups/application/create_group_with_members_use_case.dart`
- Supporting seam:
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `lib/features/groups/application/send_group_invite_use_case.dart`
- Primary proof target:
  - `test/features/groups/application/create_group_with_members_use_case_test.dart`
- Secondary proof only if needed:
  - `test/features/groups/presentation/create_group_picker_wired_test.dart`
- Supporting test fake:
  - `test/shared/fakes/in_memory_group_repository.dart`
  - `test/core/bridge/fake_bridge.dart`

### existing tests covering this area

- `create_group_with_members_use_case_test.dart` already proves the happy path
  for member addition, config sync, `members_added` publish, and invite send.
- The same suite already proves invite-send failure does not block local create,
  but it does not yet force a single member-add failure and assert the
  successful subset contract.
- `create_group_picker_wired_test.dart` already proves create success,
  navigation, and failure snackbar behavior, but it does not currently own the
  subset-truth contract.

### regression/tests to add first

- Add one direct regression in
  `test/features/groups/application/create_group_with_members_use_case_test.dart`
  that injects one failing member-save/add path during create and asserts:
  - the group is still created
  - only successful recipients are persisted as members
  - `result.membersAdded` matches the successful subset
  - `group:updateConfig` includes only the successful subset plus self
  - `members_added` includes only the successful subset
  - invite fan-out reaches only successful recipients
- Reuse the existing fake bridge and repository patterns where possible.
- Only add a picker/widget assertion if the use-case regression cannot fully
  prove the row-owned contract.

### step-by-step implementation plan

1. Re-read the current dirty worktree for the targeted create-with-members test
   so unrelated local edits are preserved.
2. Add the smallest failure-injection test helper needed to make one member add
   fail during `createGroupWithMembers(...)`.
3. Write the direct regression in
   `create_group_with_members_use_case_test.dart` and stop if it proves the row
   without product code changes.
4. If the regression exposes a real product bug instead of a proof gap, make
   the narrowest production fix inside
   `create_group_with_members_use_case.dart` and keep the change row-scoped.
5. Run the exact direct tests below.
6. Update the matrix row, inventory note, and breakdown ledger only after the
   evidence is green.

### risks and edge cases

- Do not simulate failure with an unrealistic seam that bypasses the actual
  member-add path entirely.
- Do not overclaim invite truth unless the regression checks recipient filtering
  as well as member persistence.
- Do not widen into create-time invite degradation (`CB-004`), publish/config
  rollback (`CB-005`), or keyless create (`CB-008`).
- Preserve the existing happy-path create coverage.

### exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/features/groups/application/create_group_with_members_use_case_test.dart`
- Optional direct proof only if touched:
  - `flutter test --no-pub test/features/groups/presentation/create_group_picker_wired_test.dart`
- Named gates:
  - none for the planned test-only proof scope
  - if execution unexpectedly changes production invite/create behavior, rerun
    `./scripts/run_test_gates.sh groups`

### known-failure interpretation

- If the new regression cannot prove subset truth without production changes,
  treat that as current-session product work, not as a flaky test condition.
- If unrelated pre-existing failures appear outside the exact direct suite,
  record them separately and do not misclassify them as `CB-003` regressions.
- If `./scripts/run_test_gates.sh groups` becomes necessary and fails in
  unrelated frozen suites, record the exact failures and keep the row scoped to
  whether the `CB-003` direct proof is green.

### done criteria

- `CB-003` has exact row-owned automated proof in repo-local tests.
- Any code/test delta is limited to the narrowest seam needed for this row.
- The direct proof suite passes.
- The source matrix row and breakdown can truthfully mark `CB-003` resolved.

### scope guard

- Non-goals:
  - per-recipient invite degradation UX
  - rollback after later config/publish failure
  - description support
  - topic namespace proof
  - picker copy or new snackbar UX
- Overengineering for this session would be adding new harnesses, broad
  create-flow refactors, or closing adjacent rows from the same seam.

### accepted differences / intentionally out of scope

- `CB-003` does not require device-lab proof, 3-simulator orchestration, or
  fake-network harness expansion in this session.
- `CB-003` does not own user-facing copy for mixed invite-send degradation.
- `CB-003` does not resolve whether later publish/config failures roll back
  prior local membership; that stays in `CB-005`.

### dependency impact

- A truthful `CB-003` resolution strengthens later create/invite rows, but it
  does not automatically close `CB-004`, `CB-005`, `DV-013`, or `DV-014`.
- If the regression unexpectedly reveals a product bug, adjacent create rows
  should be refreshed against that landing before they are closed.
