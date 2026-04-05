# 59 Session 1 Plan: Role-Change Mutation Contract and Admin-Continuity Guards

## Final verdict

- `implementation-ready`

## Final plan

### Real scope

- add the core post-creation admin-role mutation path for existing groups
- enforce admin-only authorization, non-member rejection, and last-admin safety
  for role changes
- make multi-admin leave use the landed continuity rule without reopening the
  old sole-admin dead end
- extend the current listener/config propagation seam so peers converge on the
  same final member/admin state after role changes
- add the direct regressions that prove the mutation seam before UI/session 2
  builds on it

Out of scope for this session:

- final group info controls, confirmation copy, and badge/timeline polish that
  belong to session `2`
- matrix/audit/architecture doc closure that belongs to session `3`
- broader moderation systems or new role taxonomies beyond the current
  admin/member roles

### Closure bar

Session `1` is done only when:

- an admin-owned product path can change a member role after group creation
- non-admin callers and non-member targets fail cleanly without mutating repo
  or peer-visible state
- no landed mutation path can leave a group without any admin
- a group with multiple admins still allows the current admin to leave
- peers apply the same authoritative role-change state through the existing
  config/listener seam
- the direct session tests pass and the required named gates pass

### Source of truth

- active session contract:
  `Test-Flight-Improv/59-post-creation-admin-role-management-session-breakdown.md`
- product intent:
  `Test-Flight-Improv/59-post-creation-admin-role-management.md`
- gate definitions:
  `Test-Flight-Improv/test-gate-definitions.md`
- regression strategy:
  `Test-Flight-Improv/14-regression-test-strategy.md`
- current code/tests win over stale prose on disagreement

### Session classification

- `implementation-ready`

### Exact problem statement

The repo already stores member roles and already blocks the sole admin from
leaving, but it does not ship a post-creation admin-role mutation contract.
That leaves the product unable to promote another admin, revoke admin safely,
or satisfy multi-admin continuity scenarios after group creation. This session
must add the core mutation and convergence behavior without yet taking on the
separate group-info surface work.

### Files and repos to inspect next

Production files:

- `lib/features/groups/application/leave_group_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/group_membership_timeline_message.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `lib/features/groups/domain/repositories/group_repository.dart`
- `lib/features/groups/domain/repositories/group_repository_impl.dart`
- `lib/features/groups/domain/models/group_member.dart`
- `lib/features/groups/domain/models/group_model.dart`

Direct tests and helpers:

- `test/features/groups/application/leave_group_use_case_test.dart`
- `test/features/groups/application/remove_group_member_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/domain/repositories/group_repository_impl_test.dart`
- `test/shared/fakes/in_memory_group_repository.dart`
- `test/core/bridge/fake_bridge.dart`

### Existing tests covering this area

- `leave_group_use_case_test.dart` already proves sole-admin leave blocking and
  multi-admin leave success
- `remove_group_member_use_case_test.dart` already proves admin-only mutation,
  non-member rejection, and bridge config-sync structure for membership changes
- `group_message_listener_test.dart` already proves authenticated
  `member_added`/`member_removed` handling plus stale ordering protections on
  membership state
- `group_membership_smoke_test.dart` already proves add/remove flows, replay,
  and membership-list convergence, but not post-creation admin-role mutation

Missing direct proof for this session:

- admin promotion after creation
- admin revocation/demotion after creation
- role-change rejection for non-members and non-admin callers
- peer convergence for the role-change snapshot/event path

### Regression/tests to add first

- add a focused application/use-case regression file for the role-change seam,
  likely `test/features/groups/application/update_group_member_role_use_case_test.dart`,
  to prove:
  - admin can promote a writer to admin
  - admin can revoke/demote another admin when at least one admin remains
  - non-admin caller is rejected
  - non-member target is rejected
  - mutation that would leave no admin is rejected
- extend `test/features/groups/application/group_message_listener_test.dart`
  with the exact role-change propagation path and stale-order handling for the
  chosen system/config update contract
- extend `test/features/groups/integration/group_membership_smoke_test.dart`
  with at least one end-to-end flow that proves promoted-admin continuity and
  multi-admin leave behavior across peers

Why these prove the seam:

- they pin the new mutation contract before the UI depends on it
- they verify both local guard rails and peer-visible convergence

### Step-by-step implementation plan

1. inspect the current member-management mutation path and decide the narrowest
   new core seam for post-creation role changes
2. add the direct application-level regression file for role mutation guard
   rails before broad UI work
3. implement the role-change use case or equivalent mutation path, reusing the
   existing repo/config update pattern instead of inventing a parallel state
   channel
4. update the leave/admin-continuity logic only as much as needed so a
   multi-admin group can continue after one admin leaves while a last-admin
   group still cannot become leaderless
5. extend the listener/config/timeline plumbing so peers receive and persist
   the authoritative role-change state
6. add or tighten the direct listener/integration regressions for propagation
   and peer convergence
7. run the required direct tests first, then the required named gates
8. stop and return `blocked` if the chosen role-change propagation contract
   cannot land coherently across use case, listener, and tests in this session

### Risks and edge cases

- a demotion path that accidentally removes the last remaining admin
- stale cached admin state during replay/resume causing unauthorized mutation
- peers seeing different final admin/member states because the new role-change
  event is less authoritative than the existing config snapshot path
- self-demotion or self-leave interactions that delete the local group before
  peers converge
- widening session `1` into UI redesign or doc closure work

### Exact tests and gates to run

Direct tests:

- `flutter test test/features/groups/application/update_group_member_role_use_case_test.dart`
- `flutter test test/features/groups/application/group_message_listener_test.dart`
- `flutter test test/features/groups/application/leave_group_use_case_test.dart`
- `flutter test test/features/groups/integration/group_membership_smoke_test.dart`

Required named gates:

- `./scripts/run_test_gates.sh baseline`
- `./scripts/run_test_gates.sh groups`

### Known-failure interpretation

- treat unrelated pre-existing failures outside the touched group/admin seam as
  known only if the failing state clearly predates this session and is not
  widened by the landed change
- do not waive new failures in the new role-change regression file, the group
  listener suite, or the required gates

### Done criteria

- a doc-scoped code/test delta lands for the core role-mutation seam
- the direct session regressions exist and pass
- `baseline` and `groups` gates pass
- the session `1` ledger entry can truthfully move out of `pending`
- session `2` can build on a stable, tested mutation contract without guessing

### Scope guard

- do not add session `2` UI affordances beyond the minimum wiring needed to
  exercise the session `1` mutation path
- do not update matrix/audit/architecture docs in this session except the
  breakdown/plan artifacts needed for pipeline bookkeeping
- do not invent new roles, moderation concepts, or notification settings
- do not refactor unrelated group membership code just because the seam is
  nearby

### Accepted differences / intentionally out of scope

- the landed surface may treat transfer-admin as promote-plus-leave rather than
  a dedicated transfer verb in this session
- session `1` may use the narrowest truthful role-change event/config contract;
  copy polish and final timeline wording wait for session `2`

### Dependency impact

- session `2` depends on this plan landing a stable mutation API and
  peer-convergence contract
- session `3` depends on the direct regressions from this session to close the
  admin-role matrix rows truthfully
- if this plan changes materially or blocks, do not start sessions `2` or `3`

## Structural blockers remaining

- none

## Incremental details intentionally deferred

- exact button labels and confirmation copy for role changes
- final doc closure wording for matrix/audit updates

## Accepted differences intentionally left unchanged

- richer moderation systems remain outside this session
- no attempt is made here to redesign the underlying group role taxonomy

## Exact docs/files used as evidence

- `Test-Flight-Improv/59-post-creation-admin-role-management-session-breakdown.md`
- `Test-Flight-Improv/59-post-creation-admin-role-management.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `lib/features/groups/application/leave_group_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/group_membership_timeline_message.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `lib/features/groups/domain/repositories/group_repository.dart`
- `lib/features/groups/domain/repositories/group_repository_impl.dart`
- `test/features/groups/application/leave_group_use_case_test.dart`
- `test/features/groups/application/remove_group_member_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/domain/repositories/group_repository_impl_test.dart`

## Why the plan is safe to implement now

- it stays inside the session `1` seam and assigns the UI/doc work to later
  sessions
- it makes the regression-first contract explicit instead of leaving execution
  to infer the new admin-role seam
- it names exact tests and required gates so QA can verify the outcome without
  reopening planning
