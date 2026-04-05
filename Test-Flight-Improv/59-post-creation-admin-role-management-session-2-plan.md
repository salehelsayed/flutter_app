# 59 Session 2 Plan: Group Info Role-Management Surface and Timeline

## Final verdict

- `implementation-ready`

## Final plan

### Real scope

- expose post-creation promote/demote controls on the existing group info
  member-management surface without regressing add/remove-member behavior
- refresh the current screen from repo state so admin-only affordances reflect
  the latest landed `myRole` and member-role snapshot instead of the stale
  navigation argument
- broadcast and persist the shipped `member_role_updated` timeline/event flow
  from the group info surface so the user-visible role-change contract is the
  same one Session `1` taught the listener to consume
- add direct presentation regressions for the visible affordances,
  confirmations, snackbars, and state refresh after role changes

Out of scope for this session:

- matrix/audit/architecture doc closure, which belongs to session `3`
- broader group metadata editing, notification controls, or dissolve flows
- inventing new role types or a second admin-management surface outside group
  info

### Closure bar

Session `2` is done only when:

- an admin viewing group info can promote a non-self member to admin and
  demote an existing admin from the same surface
- non-admin viewers do not see dead role-management affordances, and self rows
  do not expose self-promotion/demotion controls
- the current user's admin-only affordances refresh from repo truth after the
  surface loads or after a role mutation changes local permissions
- the promote/demote flow shows confirmation and outcome feedback instead of
  silently mutating state
- the role badge and shipped timeline/system-event wording stay aligned with
  the landed `member_role_updated` contract from session `1`
- the direct presentation suites pass, plus the required named `groups` gate

### Source of truth

- active session contract:
  `Test-Flight-Improv/59-post-creation-admin-role-management-session-breakdown.md`
- product intent:
  `Test-Flight-Improv/59-post-creation-admin-role-management.md`
- gate definitions:
  `Test-Flight-Improv/test-gate-definitions.md`
- regression strategy:
  `Test-Flight-Improv/14-regression-test-strategy.md`
- landed session `1` contract and code/test truth win over stale prose on
  disagreement

### Session classification

- `implementation-ready`

### Exact problem statement

Session `1` landed the core role-change mutation contract, but the shipped
group info surface still exposes only add/remove membership controls based on
the navigation-time `GroupModel`. That leaves promotion/demotion unsupported in
the product UI and risks stale permission affordances after role changes. This
session must wire the existing group info surface to the landed role-change
contract, ship honest confirmation/feedback, and refresh from repo truth.

### Files and repos to inspect next

Production files:

- `lib/features/groups/presentation/screens/group_info_screen.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `lib/features/groups/presentation/widgets/group_member_row.dart`
- `lib/features/groups/application/update_group_member_role_use_case.dart`
- `lib/features/groups/application/group_membership_timeline_message.dart`
- `lib/features/groups/domain/models/group_member.dart`
- `lib/features/groups/domain/models/group_model.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`

Direct tests and helpers:

- `test/features/groups/presentation/group_info_screen_test.dart`
- `test/features/groups/presentation/group_info_wired_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/core/bridge/fake_bridge.dart`
- `test/shared/fakes/in_memory_group_repository.dart`
- `test/shared/fakes/in_memory_group_message_repository.dart`

### Existing tests covering this area

- `group_info_screen_test.dart` already proves the current member list, role
  badges, and add-member affordance visibility
- `group_info_wired_test.dart` already proves add/remove-member visibility,
  leave flow behavior, remove-member side effects, and the current group-info
  loading contract
- `group_membership_smoke_test.dart` already proves the session `1` mutation
  contract, including promoted-admin continuity, but not the group-info UI

Missing direct proof for this session:

- promote/demote affordances on the shipped group-info surface
- confirmation and snackbar feedback for role changes
- stale navigation-role refresh back to repo truth on screen load
- UI blocking of self-targeted and non-admin role-management actions

### Regression/tests to add first

- extend `test/features/groups/presentation/group_info_screen_test.dart` to
  prove the new role-management affordances only appear for eligible non-self
  rows and trigger the callback contract
- extend `test/features/groups/presentation/group_info_wired_test.dart` to
  prove:
  - promote flow shows confirmation, updates repo state, updates the badge, and
    emits success feedback
  - demote flow shows confirmation, updates repo state, updates the badge, and
    emits success feedback
  - the surface refreshes admin affordances from repo truth even when the
    navigation-time `GroupModel` is stale
  - the role-change broadcast/timeline payload matches the landed
    `member_role_updated` contract when `msgRepo` is present
- only touch `group_membership_smoke_test.dart` if the final UI contract needs
  one more multi-user proof after the widget suites go green

### Step-by-step implementation plan

1. Add a narrow role-management affordance to each eligible member row, reusing
   the existing pure-screen plus wired split instead of inventing a second
   state model.
2. Teach `GroupInfoWired` to load the current group from `groupRepo` and render
   from that repo snapshot so `myRole` can refresh after landed role changes.
3. Wire promote/demote actions through `updateGroupMemberRole(...)`, then
   publish the aligned `member_role_updated` system event and optional timeline
   artifact using the same wording contract as session `1`.
4. Refresh the local member/group snapshot after success or failure so badges
   and admin-only affordances stay truthful.
5. Land the direct screen/wired regressions first, then run the required
   `groups` gate.
6. Stop and return `blocked` if the group info surface cannot refresh to repo
   truth without widening into a separate live-subscription architecture.

### Risks and edge cases

- showing promote/demote controls on the self row would create a dead or
  conflicting surface beside `Leave Group`
- relying only on the pushed-in `widget.group` would leave stale admin-only
  affordances after a role change lands in the repo
- the role-change publish path could diverge from the landed listener contract
  if the UI invents different payload or copy
- success snackbars can become misleading if the repo state is not reloaded
  after the mutation
- the UI work must not regress the existing remove-member confirmation and key
  rotation flow

### Exact tests and gates to run

Direct tests:

- `flutter test test/features/groups/presentation/group_info_screen_test.dart`
- `flutter test test/features/groups/presentation/group_info_wired_test.dart`
- `flutter test test/features/groups/integration/group_membership_smoke_test.dart`

Required named gates:

- `./scripts/run_test_gates.sh groups`

### Known-failure interpretation

- treat unrelated pre-existing failures outside the touched group-info/admin
  surface as known only if they reproduce on unchanged code and do not involve
  the role-management affordances or `member_role_updated` contract
- do not waive new failures in the group-info screen/wired suites or the
  `groups` gate

### Done criteria

- a doc-scoped code/test delta lands for the group-info role-management surface
- the direct presentation regressions exist and pass
- the required `groups` gate passes
- the session `2` ledger entry can truthfully move out of `pending`
- session `3` can close the matrix/doc rows against a stable shipped surface

### Scope guard

- do not widen into group metadata editing, mute controls, or dissolve work
- do not create a second admin-management route outside the existing group info
  surface
- do not update matrix/audit docs in this session except the breakdown/plan
  artifacts needed for pipeline bookkeeping
- do not refactor unrelated group conversation or membership code just because
  it is nearby

### Accepted differences / intentionally out of scope

- the role-management affordance can be a compact menu/control on the member
  row rather than a dedicated full-screen editor
- exact snackbar/dialog copy may stay narrow as long as the shipped contract is
  explicit and directly tested

### Dependency impact

- session `3` depends on this plan landing the truthful shipped surface for
  `MR-019` and `UX-011`
- if this plan blocks materially, do not start session `3`

## Structural blockers remaining

- none

## Incremental details intentionally deferred

- final matrix-row wording and closure docs
- any extra multi-device proof beyond what the direct presentation suites and
  `groups` gate require

## Accepted differences intentionally left unchanged

- the app still uses the existing `StatefulWidget` plus wired-screen contract
- no attempt is made here to live-subscribe group info to repo changes beyond
  bounded reloads from the landed action paths and initial load

## Exact docs/files used as evidence

- `Test-Flight-Improv/59-post-creation-admin-role-management-session-breakdown.md`
- `Test-Flight-Improv/59-post-creation-admin-role-management.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `lib/features/groups/presentation/screens/group_info_screen.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `lib/features/groups/presentation/widgets/group_member_row.dart`
- `lib/features/groups/application/update_group_member_role_use_case.dart`
- `lib/features/groups/application/group_membership_timeline_message.dart`
- `lib/features/groups/domain/models/group_member.dart`
- `lib/features/groups/domain/models/group_model.dart`
- `test/features/groups/presentation/group_info_screen_test.dart`
- `test/features/groups/presentation/group_info_wired_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`

## Why the plan is safe to implement now

- it builds directly on the landed session `1` mutation contract instead of
  replanning admin-role semantics
- it keeps the work inside the existing group-info seam and names exact direct
  regressions and the required gate
- it assigns matrix/doc closure to session `3`, so this session can focus on
  truthful shipped behavior
