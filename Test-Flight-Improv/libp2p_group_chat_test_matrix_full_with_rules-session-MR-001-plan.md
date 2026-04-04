# Session MR-001 Plan - Only admin can add members

## Final verdict

`acceptance-only`

Current repo evidence suggests row `MR-001` is already proven at the
repo-owned permission seam:

- `test/features/groups/presentation/group_info_wired_test.dart` already
  proves the add-member affordance is shown for admins and hidden for
  non-admins.
- `test/features/groups/application/add_group_member_use_case_test.dart`
  already proves admin add succeeds while a non-admin caller is rejected with a
  `StateError`.
- The row contract is narrower than add-success bootstrap or member-list sync;
  it only needs truthful admin-only permission proof.

The safest session is therefore to reuse the current UI-plus-use-case proof on
the current repo state and close the row with evidence only.

## Final plan

### real scope

- Resolve source row `MR-001` only: `Only admin can add members`.
- Prefer no production or test edits.
- Update only the row truth in
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md` and
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  after exact evidence is verified.
- Do not widen into bootstrap-completion, duplicate-add handling, or remove
  flows.

### closure bar

- There is direct automated proof that admins see the add-member affordance and
  non-admins do not.
- There is direct automated proof that the underlying add-member use case
  accepts admin callers and rejects non-admin callers.
- The direct tests below pass on the current repo state.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
- Current code and tests beat stale prose when they disagree.
- Verified seam files:
  - `test/features/groups/presentation/group_info_wired_test.dart`
  - `test/features/groups/application/add_group_member_use_case_test.dart`
  - `lib/features/groups/application/add_group_member_use_case.dart`

### session classification

`acceptance-only`

### exact problem statement

- The matrix row needs row-owned proof that add-member permissions are enforced
  in both the surfaced UI and the repo-owned state layer.
- The current tree already appears to prove that contract, but the row is not
  yet classified closed in the matrix and breakdown.

### files and repos to inspect next

- Primary proof targets:
  - `test/features/groups/presentation/group_info_wired_test.dart`
  - `test/features/groups/application/add_group_member_use_case_test.dart`
- Supporting production seam:
  - `lib/features/groups/application/add_group_member_use_case.dart`

### existing tests covering this area

- `GroupInfoWired shows Add Member button for admin role`
- `GroupInfoWired hides Add Member button for non-admin role`
- `adds member successfully when caller is admin`
- `rejects when caller is not admin`

### regression/tests to add first

- First try to close the row without edits by rerunning the current widget and
  use-case proofs.
- Only if the proof is ambiguous, add the narrowest missing permission
  assertion and stop.

### step-by-step implementation plan

1. Re-read the current UI and use-case permission tests.
2. Confirm they still match the exact row contract.
3. Rerun the direct tests below.
4. If the proof stays exact and green, move straight to doc refresh.

### risks and edge cases

- Overclaim risk: do not treat add-success or member-list sync as proof of the
  admin-only permission contract.
- Scope risk: do not widen into duplicate-add or bootstrap behavior.

### exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart`
  - `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart`
- Named gates:
  - none unless a production-code change is required

### known-failure interpretation

- Treat a visible add-member affordance for non-admins or a successful
  non-admin use-case call as current-session blockers.

### done criteria

- `MR-001` has exact row-owned UI-plus-state permission proof.
- No broader membership behavior is reopened.
- The source matrix and breakdown can truthfully mark the row resolved.

### scope guard

- Non-goals:
  - bootstrap participation proof
  - duplicate-member handling
  - remove-member permissions

### accepted differences / intentionally out of scope

- `MR-001` does not own late-bootstrap send behavior.
- `MR-001` does not claim protocol-level raw-message bypass coverage beyond the
  repo-owned UI and use-case seams.

### dependency impact

- A truthful `MR-001` resolution informs `MR-002`, but it does not
  automatically close add-success or member-list-sync rows.
