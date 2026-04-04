# Session MR-002 Plan - Add member success

## Final verdict

`implementation-ready`

Current repo evidence showed row `MR-002` was close to covered but not yet
exact:

- the tree already supported add-member persistence and member hydration
  through `GroupTestUser.addMember`, but the existing smoke proof stopped short
  of showing the newly added member participating after bootstrap completes
- the old `member_added` smoke scenario proved list sync for existing members,
  not that the invitee can actually send once the add flow is complete

The smallest safe session was therefore to tighten the membership smoke proof
so the added member starts after bootstrap and successfully participates in the
group.

## Final plan

### real scope

- Resolve source row `MR-002` only: `Add member success`.
- Prefer test-only changes in
  `test/features/groups/integration/group_membership_smoke_test.dart`.
- Touch production code only if the tightened bootstrap participation proof
  exposes a real repo bug.
- Update only the row truth in
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md` and
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  after exact evidence is verified.
- Do not widen into pre-bootstrap send blocking, duplicate-add handling, or
  remove flows.

### closure bar

- There is direct automated proof that after the admin adds a new member and
  bootstrap completes, the new member can participate in the group.
- The direct tests below pass.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
- Current code and tests beat stale prose when they disagree.
- Verified seam files:
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/features/groups/application/add_group_member_use_case_test.dart`
  - `test/shared/fakes/group_test_user.dart`

### session classification

`implementation-ready`

### exact problem statement

- The repo already supported add-member bootstrap, but the row lacked exact
  proof that the newly added member can participate once bootstrap completes.
- Without that participation proof, the row could not be truthfully called
  closed.

### files and repos to inspect next

- Primary regression target:
  - `test/features/groups/integration/group_membership_smoke_test.dart`
- Supporting add-member seam:
  - `test/features/groups/application/add_group_member_use_case_test.dart`
  - `test/shared/fakes/group_test_user.dart`

### existing tests covering this area

- The prior `member_added` smoke scenario already covered list sync for
  existing members.
- `add_group_member_use_case_test.dart` already covered state-layer success.
- Missing before this session:
  - direct proof that the newly added member participates after bootstrap

### regression/tests to add first

- Tighten the membership smoke scenario to prove:
  - the added member starts after bootstrap data is present
  - the added member can send successfully
  - existing members receive that first post-bootstrap message
- Only if that regression exposes a real bug, patch the minimal production seam
  needed to satisfy it.

### step-by-step implementation plan

1. Re-read the current membership smoke scenario.
2. Tighten it to include post-bootstrap participation by the newly added
   member.
3. Run the direct tests below.
4. Update the matrix row note and breakdown ledger only after evidence is
   verified.

### risks and edge cases

- Overclaim risk: a saved member row alone is not enough for this contract.
- Scope risk: do not reopen pre-bootstrap send blocking or duplicate-add
  semantics.

### exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart`
  - `flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart`
- Named gates:
  - none unless a production-code change is required

### known-failure interpretation

- Treat missing post-bootstrap participation or missing delivery to existing
  members as current-session blockers.

### done criteria

- `MR-002` has exact row-owned add-success proof.
- Any test delta is limited to the narrowest bootstrap-participation seam.
- Required direct tests pass.
- The source matrix and breakdown can truthfully mark the row resolved.

### scope guard

- Non-goals:
  - pre-bootstrap send blocking
  - duplicate-member handling
  - remove-member flows

### accepted differences / intentionally out of scope

- `MR-002` does not own `MR-003` pre-bootstrap send behavior.
- `MR-002` does not claim raw protocol invite proof outside the repo-owned
  Flutter seam.

### dependency impact

- A truthful `MR-002` resolution reduces uncertainty for `MR-005`, but it does
  not automatically close the pre-bootstrap row.
