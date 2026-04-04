# Session MR-005 Plan - Member list sync after add

## Final verdict

`implementation-ready`

Current repo evidence showed row `MR-005` was close to covered but not yet
exact:

- the old `member_added` smoke scenario proved Bob updated his list after an
  add, but it did not prove all participants converged on the same member list
  and role state
- the source row requires full list and role convergence across the group, not
  just one existing member hydrating the new entry

The smallest safe session was therefore to tighten that same smoke seam with
explicit member-list and role assertions across admin, existing member, and new
member.

## Final plan

### real scope

- Resolve source row `MR-005` only: `Member list sync after add`.
- Prefer test-only changes in
  `test/features/groups/integration/group_membership_smoke_test.dart`.
- Touch production code only if the widened member-list convergence proof
  exposes a real repo bug.
- Update only the row truth in
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md` and
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  after exact evidence is verified.
- Do not widen into remove flows or admin-promotion rows.

### closure bar

- There is direct automated proof that after the add flow completes, all
  participants converge on the same member list and role state.
- The direct tests below pass.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
- Current code and tests beat stale prose when they disagree.
- Verified seam files:
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/shared/fakes/group_test_user.dart`
  - `lib/features/groups/application/group_message_listener.dart`

### session classification

`implementation-ready`

### exact problem statement

- The repo already proved some post-add sync behavior, but the row lacked exact
  proof that admin, existing members, and the new member share the same final
  membership and role view.
- Without that full convergence assertion, the row could not be truthfully
  closed.

### files and repos to inspect next

- Primary regression target:
  - `test/features/groups/integration/group_membership_smoke_test.dart`
- Supporting sync seam:
  - `test/shared/fakes/group_test_user.dart`
  - `lib/features/groups/application/group_message_listener.dart`

### existing tests covering this area

- The previous smoke scenario covered Bob updating his local list.
- Missing before this session:
  - explicit admin/Bob/Charlie convergence assertions for member list and roles

### regression/tests to add first

- Tighten the membership smoke scenario to assert:
  - admin sees all members with correct roles
  - the existing member sees all members with correct roles
  - the newly added member sees all members with correct roles
- Only if that regression exposes a real bug, patch the minimal production seam
  needed to satisfy it.

### step-by-step implementation plan

1. Re-read the current member-added smoke scenario.
2. Add exact convergence assertions for every participant.
3. Run the direct tests below.
4. Update the matrix row note and breakdown ledger only after evidence is
   verified.

### risks and edge cases

- Overclaim risk: one-device member-list sync is not enough for this row.
- Scope risk: do not widen into promotion, leave, or remove-state work.

### exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart`
- Named gates:
  - none unless a production-code change is required

### known-failure interpretation

- Treat divergent member lists or divergent roles across peers as
  current-session blockers.

### done criteria

- `MR-005` has exact row-owned member-list convergence proof.
- Any test delta is limited to the narrowest sync assertion seam.
- Required direct tests pass.
- The source matrix and breakdown can truthfully mark the row resolved.

### scope guard

- Non-goals:
  - remove-member behavior
  - promotion or badge-transfer flows
  - pre-bootstrap send blocking

### accepted differences / intentionally out of scope

- `MR-005` does not own UI-specific badge styling beyond repo-owned role state.
- `MR-005` does not claim promotion/admin-change propagation.

### dependency impact

- A truthful `MR-005` resolution reduces uncertainty for later membership-sync
  rows, but it does not automatically close remove or promotion sessions.
