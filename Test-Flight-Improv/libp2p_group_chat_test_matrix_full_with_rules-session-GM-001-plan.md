# Session GM-001 Plan - Create group successfully

## Final verdict

`implementation-ready`

Current repo evidence shows row `GM-001` is already close to covered but not yet
proven exactly at the matrix contract:

- `test/features/groups/integration/group_messaging_smoke_test.dart` already
  creates a 3-user group, adds B and C, starts all listeners, and proves
  fan-out works after creation.
- `test/shared/fakes/group_test_user.dart` gives the smoke suite direct access
  to each user's saved `GroupModel` and member repository state, so the missing
  proof is narrow and test-local rather than architectural.
- `lib/features/groups/application/create_group_use_case.dart` persists the
  creator as admin and stores the initial group model/key.
- `lib/features/groups/application/create_group_with_members_use_case.dart`
  owns the real create-plus-membership bootstrap seam and already has focused
  unit coverage for member persistence, config update, and invite fan-out.

The smallest safe session is therefore to tighten the current fake-network
integration proof so `GM-001` explicitly asserts shared group identity plus
consistent member/admin state across A/B/C, then rerun the direct create-group
tests and named group/baseline gates.

## Final plan

### real scope

- Tighten repo-local proof for matrix row `GM-001` only:
  `Create group successfully`.
- Prefer edits in
  `test/features/groups/integration/group_messaging_smoke_test.dart`.
- Touch production code only if the new assertions expose a real repo bug in
  the existing create/bootstrap path.
- Do not widen into later rows such as online fan-out, offline bootstrap,
  notification routing, restart recovery, or announcement semantics.

### closure bar

- There is one direct regression proving that after A creates a group with B
  and C, all three peers observe the same group id and the same persisted group
  membership/admin state.
- The regression proves:
  - A's saved group exists and A is admin.
  - B and C each hydrate the same group id after the add/bootstrap flow.
  - A/B/C see the same member set for the created group.
  - the creator/admin identity is consistent across the hydrated repos.
- The direct tests below pass.
- Required named gates pass without introducing a broader behavioral claim than
  row `GM-001`.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
- Current code and tests beat stale prose when they disagree.
- Verified seam files:
  - `lib/features/groups/application/create_group_use_case.dart`
  - `lib/features/groups/application/create_group_with_members_use_case.dart`
  - `test/features/groups/integration/group_messaging_smoke_test.dart`
  - `test/features/groups/application/create_group_use_case_test.dart`
  - `test/features/groups/application/create_group_with_members_use_case_test.dart`
  - `test/shared/fakes/group_test_user.dart`

### session classification

`implementation-ready`

### exact problem statement

- The matrix row requires proof that group creation completes successfully for
  A/B/C at the repo-local product seam, not just that later message fan-out
  works.
- The current smoke test demonstrates usable post-create messaging, but it does
  not explicitly pin the exact row contract that all peers share the same
  created group id plus consistent member/admin state.
- Because the repo already has create-group unit coverage and fake-network
  multi-user coverage, the safest move is to add the narrowest missing
  assertions first and stop if they already prove the row without any product
  code change.

### files and repos to inspect next

- Primary direct regression target:
  - `test/features/groups/integration/group_messaging_smoke_test.dart`
- Supporting fake harness:
  - `test/shared/fakes/group_test_user.dart`
- Production create/bootstrap seams to inspect only if the tightened regression
  exposes a bug:
  - `lib/features/groups/application/create_group_use_case.dart`
  - `lib/features/groups/application/create_group_with_members_use_case.dart`
- Existing direct tests that already pin parts of the contract:
  - `test/features/groups/application/create_group_use_case_test.dart`
  - `test/features/groups/application/create_group_with_members_use_case_test.dart`

### existing tests covering this area

- `test/features/groups/integration/group_messaging_smoke_test.dart` already
  exercises a 3-user create/add/send path and is the best home for `GM-001`
  proof.
- `test/features/groups/application/create_group_use_case_test.dart` already
  proves group creation persists the group, creator admin membership, and key.
- `test/features/groups/application/create_group_with_members_use_case_test.dart`
  already proves member persistence, config update, and invite fan-out for the
  real create-plus-members bootstrap path.
- Missing today:
  - no direct `GM-001` assertion that B and C hydrate the same created group id
    as A
  - no direct `GM-001` assertion that all three repos agree on the member/admin
    state immediately after creation/bootstrap

### regression/tests to add first

- Tighten the first `group_messaging_smoke_test.dart` scenario or add a narrow
  adjacent scenario so it explicitly asserts:
  - one shared `groupId` across A/B/C
  - the same persisted member peer ids across A/B/C
  - the creator/admin role is present and consistent
- Only if those assertions uncover a real bug, add the minimal production fix
  in the create/bootstrap seam and keep the regression focused on `GM-001`.

### step-by-step implementation plan

1. Re-read the live dirty worktree for the targeted test and helper files so
   unrelated in-flight edits are preserved.
2. Audit the existing first smoke scenario in
   `test/features/groups/integration/group_messaging_smoke_test.dart` against
   the exact `GM-001` matrix expectations.
3. Add the narrowest missing assertions for shared group id, member list, and
   admin state across A/B/C.
4. If the new assertions fail because of a real create/bootstrap defect, patch
   only the minimal create-group seam required to satisfy the row.
5. Run the exact direct tests and named gates below.
6. Update the row truth in the source matrix and session breakdown only after
   the regression evidence is green.

### risks and edge cases

- Fake-harness risk: `GroupTestUser.createGroup` and `addMember` simulate the
  bootstrap flow directly; the row should only be claimed closed if the
  assertions still match the intended repo-local product seam.
- Overclaim risk: message fan-out passing is not by itself proof that the full
  create-group state contract is pinned.
- Scope risk: do not pull in offline member bootstrap (`GM-002`), send fan-out
  (`GM-003`), or restart/recovery work (`GM-012`) just because the same test
  file touches those themes.
- Dirty-worktree risk: there are unrelated local edits in the repo; do not
  revert or normalize them during this session.

### exact tests and gates to run

- Direct tests:
  - `flutter test test/features/groups/integration/group_messaging_smoke_test.dart`
  - `flutter test test/features/groups/application/create_group_use_case_test.dart`
  - `flutter test test/features/groups/application/create_group_with_members_use_case_test.dart`
- Named gates:
  - `./scripts/run_test_gates.sh baseline`
  - `./scripts/run_test_gates.sh groups`
- Conditional only if production lifecycle or transport code changes:
  - `./scripts/run_test_gates.sh transport`

### known-failure interpretation

- Treat failures in the new or tightened `GM-001` assertions as current-session
  blockers.
- If `baseline` or `groups` fail only in unrelated pre-existing suites, record
  the exact failing files and keep `GM-001` scoped to whether its direct proof
  and touched-file regressions are green.
- Do not delete or weaken the new assertions to make a broader gate appear
  green.

### done criteria

- The repo has direct automated proof for row `GM-001` at the exact group
  creation seam.
- Any necessary code/test delta is limited to the create/bootstrap path needed
  for this row.
- The direct tests above pass.
- Required named gates are run and their results are recorded honestly.
- The source matrix and breakdown can truthfully reclassify `GM-001` based on
  landed evidence.

### scope guard

- Non-goals:
  - adding coverage for other group-chat rows
  - redesigning the fake group harness
  - widening frozen gate definitions
  - refactoring create/send flows for style or cleanup
- Overengineering for this session would be creating a new multi-user test
  harness or changing unrelated group lifecycle behavior without a regression
  proving it is required for `GM-001`.

### accepted differences / intentionally out of scope

- `GM-001` does not need protocol-level raw-frame validation, ciphertext proof,
  or real-device notification evidence.
- `GM-001` does not own unsupported metadata/admin-transfer features or any
  repo-external validator proof.
- If the fake-network harness proves the row sufficiently, this session should
  not reopen a broader end-to-end/device-lab track.

### dependency impact

- A clean `GM-001` regression can reduce uncertainty for later create/send
  rows, but it does not automatically close them.
- If execution discovers that the fake-network harness cannot truthfully prove
  the row, later row-owned sessions that rely on the same create bootstrap seam
  should be refreshed against that finding rather than silently inherited as
  covered.
