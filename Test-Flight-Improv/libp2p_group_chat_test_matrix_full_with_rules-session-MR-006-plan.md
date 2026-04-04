# Session MR-006 Plan - Only admin can remove members

## Final verdict

`implementation-ready`

Current repo evidence showed row `MR-006` was close to covered but not yet
exact:

- `test/features/groups/application/remove_group_member_use_case_test.dart`
  already proved non-admin remove is rejected in the repo-owned state layer
- `test/features/groups/integration/group_membership_smoke_test.dart` already
  proved admin removal succeeds and syncs
- the missing proof was an explicit UI-level block showing non-admins do not
  get remove controls

The smallest safe session was therefore to add the narrowest widget assertion
for the missing UI-side permission proof and stop there.

## Final plan

### real scope

- Resolve source row `MR-006` only: `Only admin can remove members`.
- Prefer test-only changes in
  `test/features/groups/presentation/group_info_wired_test.dart`.
- Reuse the current use-case and integration proofs for rejection and successful
  admin removal.
- Update only the row truth in
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md` and
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  after exact evidence is verified.
- Do not widen into confirmation-dialog, removed-state notice, or last-admin
  protection work.

### closure bar

- There is direct automated proof that non-admins do not get remove controls in
  the surfaced UI.
- There is direct automated proof that the underlying remove-member use case
  rejects non-admin callers.
- There is direct automated proof that admin removal still succeeds.
- The direct tests below pass.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
- Current code and tests beat stale prose when they disagree.
- Verified seam files:
  - `test/features/groups/presentation/group_info_wired_test.dart`
  - `test/features/groups/application/remove_group_member_use_case_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`

### session classification

`implementation-ready`

### exact problem statement

- The repo already covered remove-member rejection and admin success at the
  state seam, but the row lacked explicit UI proof that non-admins are blocked
  before they can start the remove flow.
- Without that UI assertion, the row could not be truthfully called closed.

### files and repos to inspect next

- Primary regression target:
  - `test/features/groups/presentation/group_info_wired_test.dart`
- Supporting proof targets:
  - `test/features/groups/application/remove_group_member_use_case_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`

### existing tests covering this area

- `throws when caller is not admin`
- `admin removes member — remaining members update their local member list`
- `admin removes member — removed member stops receiving messages`
- Missing before this session:
  - explicit UI proof that non-admins do not get remove controls

### regression/tests to add first

- Add the narrowest widget test asserting a non-admin group-info surface shows
  no remove-member icon buttons.
- Reuse the existing use-case and integration proofs for the rest of the row.

### step-by-step implementation plan

1. Re-read the current remove-member widget and use-case tests.
2. Add the missing non-admin UI assertion.
3. Run the direct tests below.
4. Update the matrix row note and breakdown ledger only after evidence is
   verified.

### risks and edge cases

- Overclaim risk: a throwing use case alone is not enough when the row also
  requires surfaced UI blocking.
- Scope risk: do not widen into confirmation or remove-state UX.

### exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart`
  - `flutter test --no-pub test/features/groups/application/remove_group_member_use_case_test.dart`
  - `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart`
- Named gates:
  - none unless a production-code change is required

### known-failure interpretation

- Treat visible non-admin remove controls, a successful non-admin remove
  attempt, or a failed admin remove as current-session blockers.

### done criteria

- `MR-006` has exact row-owned UI-plus-state permission proof.
- Any test delta is limited to the narrowest missing UI assertion.
- Required direct tests pass.
- The source matrix and breakdown can truthfully mark the row resolved.

### scope guard

- Non-goals:
  - confirmation-dialog behavior
  - removed-state notice UX
  - last-admin protection

### accepted differences / intentionally out of scope

- `MR-006` does not own the remove confirmation contract in `MR-007`.
- `MR-006` does not claim protocol-layer raw bypass proof outside the
  repo-owned UI and use-case seams.

### dependency impact

- A truthful `MR-006` resolution clears the permission baseline for `MR-007`,
  but it does not automatically close confirmation or remove-state rows.
