# Session MR-020 Plan - At least one admin remains

## Final verdict

`implementation-ready`

Current repo evidence shows `MR-020` is a real repo-owned behavior gap with a
narrow, implementable closure path:

- `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  classifies `MR-020` as `implementation-ready` and requires code plus tests.
- `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md` still records
  the row as open because last-admin protection is not enforced.
- `Test-Flight-Improv/11-group-discussion-use-case-audit.md` still says groups
  can become leaderless if the original admin leaves.
- `lib/features/groups/application/leave_group_use_case.dart` currently leaves
  unconditionally.
- `lib/features/groups/presentation/screens/group_info_wired.dart` calls
  `leaveGroup(...)` directly from `_onLeave()` and only logs errors, so the UI
  does not currently block or explain the last-admin case.
- `test/features/groups/application/leave_group_use_case_test.dart` currently
  proves successful leave/cleanup only, which confirms the missing guard rather
  than the desired block.

The smallest safe session is therefore to add a sole-admin leave guard, surface
that failure truthfully in the wired screen, and land direct regressions that
prove leaderless exit is blocked without broadening into admin-transfer product
work.

## Final plan

### real scope

- Close source row `MR-020` only: prevent a sole admin from leaving a group in
  a way that would leave the group leaderless.
- Keep the production change narrow to:
  - `lib/features/groups/application/leave_group_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Add only the direct regressions needed to prove:
  - the use case blocks sole-admin leave
  - a non-final-admin leave still succeeds
  - the wired screen keeps the user on the page and surfaces a truthful error
  - the group membership smoke coverage includes the blocked sole-admin path
- Update only the row-owned closure docs named by the breakdown after code and
  tests land:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`

### closure bar

- A sole local admin can no longer leave a group if doing so would leave zero
  admins in the current repo-owned group state.
- The leave attempt is blocked before destructive cleanup or bridge leave work
  begins.
- The wired group-info flow does not pop away on the blocked path and gives the
  user a truthful explanation.
- A leave remains allowed when another admin already exists.
- Direct regressions for the use case, wired screen, and group membership seam
  pass.
- `MR-020` is updated to `Closed` or `Covered` only after the row docs cite the
  landed code and tests.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Current code/tests win over stale prose when they disagree.
- Verified seam files:
  - `lib/features/groups/application/leave_group_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/domain/models/group_member.dart`
  - `test/features/groups/application/leave_group_use_case_test.dart`
  - `test/features/groups/presentation/group_info_wired_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/shared/fakes/group_test_user.dart`

### session classification

`implementation-ready`

### exact problem statement

- The current repo allows the final admin to leave a group without any guard.
- That violates source row `MR-020` because the group can become leaderless in
  the local product contract.
- The missing behavior is not rich role transfer or promotion. The minimum
  truthful fix is to block the destructive leave path when the local member set
  would otherwise end with zero admins.
- The current UI also lacks direct user feedback for the blocked path, so a
  narrow wired-surface explanation is needed to make the block user-visible.

### files and repos to inspect next

- Production files:
  - `lib/features/groups/application/leave_group_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/domain/repositories/group_repository.dart`
  - `lib/features/groups/domain/models/group_member.dart`
- Direct tests:
  - `test/features/groups/application/leave_group_use_case_test.dart`
  - `test/features/groups/presentation/group_info_wired_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/shared/fakes/group_test_user.dart`
- Gate source:
  - `Test-Flight-Improv/test-gate-definitions.md`

### existing tests covering this area

- `test/features/groups/application/leave_group_use_case_test.dart` proves the
  happy-path leave cleanup and bridge call, but has no last-admin guard case.
- `test/features/groups/presentation/group_info_wired_test.dart` proves the
  leave button currently calls through and pops to the first route, which is
  the behavior that must stay blocked for the sole-admin case.
- `test/features/groups/integration/group_membership_smoke_test.dart` already
  covers membership churn and post-removal behavior, so it is the right home
  for one row-owned smoke proof that the sole-admin leave path is rejected.
- `lib/features/groups/application/remove_group_member_use_case.dart` already
  enforces admin-only removal for removing others, so `MR-020` does not need a
  broader role-management architecture to close.

### regression/tests to add first

- Add a direct use-case regression first:
  - sole admin leave throws before bridge leave or repo cleanup
- Add a direct allow-path use-case regression:
  - leave still succeeds when another admin exists in the member list
- Add a wired-screen regression:
  - tapping `Leave Group` as the sole admin keeps the route in place and shows
    a user-visible error instead of silently logging and popping away
- Add a smoke-level regression:
  - a creator/admin with only writer members cannot leave and the local group
    state remains intact

### step-by-step implementation plan

1. Re-read the live worktree for the files above and preserve unrelated local
   edits.
2. Add the sole-admin guard inside `leaveGroup(...)`:
   - load the group and current members
   - if `group.myRole == GroupRole.admin` and the current member set contains
     exactly one admin, throw a narrow `StateError` before `group:leave` or any
     destructive repo cleanup runs
   - otherwise preserve the existing leave behavior
3. Keep the guard local to the leave path; do not widen into promotion,
   transfer, or server-authoritative role reassignment.
4. Update `GroupInfoWired._onLeave()` to surface the blocked-path error
   truthfully to the user and avoid popping the route on failure.
5. Add the direct use-case regressions for blocked sole-admin leave and allowed
   leave when another admin exists.
6. Add the wired-screen regression proving the blocked UI path stays in place
   and surfaces the message.
7. Add one membership smoke regression proving a sole admin cannot leave a
   group that still has only non-admin members.
8. Run the direct tests and named gates below.
9. Update the matrix row, this breakdown, and the group-discussion audit only
   after the landed code/tests satisfy the closure bar.

### risks and edge cases

- The local member list is the repo-owned source used by the guard. Do not
  invent remote consensus or promotion flows in this session.
- The guard must run before `group:leave`, member deletion, key deletion, or
  group deletion so blocked leave attempts stay non-destructive.
- The UI path must not swallow the failure silently; otherwise the product
  contract is still ambiguous even if the use case throws.
- Do not block non-admin members from leaving; the row is specifically about
  preserving at least one admin.
- Do not make `remove_group_member_use_case.dart` broader unless execution
  proves the leave-path fix cannot close the row safely on its own.

### exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/features/groups/application/leave_group_use_case_test.dart`
  - `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart`
  - `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart`
- Named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh baseline` only if execution broadens beyond
    the group-info leave flow into broader Flutter navigation/startup behavior

### known-failure interpretation

- There is no accepted difference that allows a sole admin to leave and strand
  the group without any admin.
- If a direct MR-020 regression fails, treat that as in-scope.
- If `groups` or conditional `baseline` expose unrelated pre-existing failures,
  keep them separate unless the failure touches the new leave guard or group
  info error-path behavior.

### done criteria

- Sole-admin leave is blocked before destructive cleanup starts.
- Leave still succeeds when another admin already exists.
- The group-info wired flow gives a truthful blocked-path message and does not
  pop away on failure.
- The direct tests above pass, and the required named gate(s) pass.
- `MR-020` is updated in the source matrix and breakdown with concrete
  file-and-test evidence, and `11-group-discussion-use-case-audit.md` no longer
  claims the repo can become leaderless through last-admin leave.

### scope guard

- Do not implement admin transfer, promotion, demotion, or richer role-editing
  workflows in this session.
- Do not add new backend/protocol validators or signed membership-event logic;
  those belong to other rows such as `SC-001` and `SC-015`.
- Do not redesign `GroupInfoScreen` or broaden the change into unrelated member
  management UX.
- Do not reopen already-blocked prerequisite rows while closing `MR-020`.

### accepted differences / intentionally out of scope

- The repo may still lack a full admin-transfer workflow after this session.
- The product can remain conservative by preventing the final admin from
  leaving rather than inventing automatic reassignment.
- Promotion/admin-change propagation for offline members remains separate work
  in `MR-024`.

### dependency impact

- `MR-020` can close independently and does not require the blocked prerequisite
  rows to move first.
- `CLOSURE-001` depends on this row being truthfully updated after execution.
- If execution shows the local member-role data is too weak to identify the
  sole-admin condition safely, stop and reclassify with concrete evidence
  instead of widening into a larger role-management seam.
