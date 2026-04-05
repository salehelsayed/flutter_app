# 64 Session 2 Plan: Enforce Group Size Limit In Create/Add Flows

## Final verdict

- `implementation-ready`

## Final plan

### Real scope

- enforce the shared 50-member cap in single-member add, create-with-members,
  and the add-member batch invite flow
- make batch overflow deterministic and all-or-nothing so an over-limit
  selection leaves the existing group unchanged
- prevent bridge config sync, group creation, or invite publish side effects on
  rejected over-limit operations
- add direct regressions for at-limit success, over-limit single add rejection,
  over-limit create rejection, and over-limit batch invite rejection

Out of scope for this session:

- specialized user-facing size-limit copy or localization
- maintained-doc and matrix closure work

### Closure bar

Session `2` is done only when:

- adding the 50th member still succeeds
- adding one more member beyond the cap throws the typed overflow exception
  before local mutation or bridge sync
- create-with-members rejects an over-limit initial selection before creating a
  group or persisting members
- the batch invite path rejects an over-limit selection without partial added
  members, config update, or members_added publish
- direct tests and the named gate prove the mutation paths without needing the
  final user-visible copy yet

### Source of truth

- active session contract:
  `Test-Flight-Improv/64-group-membership-size-limit-contract-session-breakdown.md`
- session `1` policy seam:
  `lib/features/groups/domain/models/group_membership_limit_policy.dart`
- product/problem doc:
  `Test-Flight-Improv/64-group-membership-size-limit-contract.md`
- named gate contract:
  `Test-Flight-Improv/test-gate-definitions.md`

### Exact problem statement

The repo now names one explicit 50-member contract, but the create and add
flows still do not enforce it. Without this session, groups can still grow past
the chosen limit or partially mutate during a too-large batch invite, so
`UX-009` remains false in practice.

### Files and repos to inspect next

Production files:

- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/create_group_with_members_use_case.dart`
- `lib/features/groups/presentation/screens/contact_picker_wired.dart`

Direct tests:

- `test/features/groups/application/add_group_member_use_case_test.dart`
- `test/features/groups/application/create_group_with_members_use_case_test.dart`
- `test/features/groups/presentation/contact_picker_wired_test.dart`

### Existing tests covering this area

- `add_group_member_use_case_test.dart` already covers admin gating, duplicate
  rejection, and rollback on config-sync failure, so it is the right seam for
  single-member overflow rejection
- `create_group_with_members_use_case_test.dart` already proves initial group
  creation, batch member add, and invite send behavior, so it can pin the
  over-limit create rejection before any side effects
- `contact_picker_wired_test.dart` already proves stale duplicate rejection
  avoids config sync and members_added publish, so it can absorb the
  over-limit batch no-op regression

### Regression/tests to add first

- add single-member over-limit rejection to
  `add_group_member_use_case_test.dart`
- add create-with-members over-limit rejection before `group:create` to
  `create_group_with_members_use_case_test.dart`
- add an over-limit batch invite widget regression to
  `contact_picker_wired_test.dart`

### Step-by-step implementation plan

1. Guard `addGroupMember(...)` with the shared size-limit helper after loading
   the current member count and before saving the new member.
2. Guard `createGroupWithMembers(...)` before `createGroup(...)` so an
   over-limit initial selection fails before any group, member, or key rows are
   created.
3. Guard `ContactPickerWired._inviteSelected()` before the local add loop so a
   batch that would exceed the limit is rejected as all-or-nothing.
4. Add the direct regressions above and rerun them plus the required `groups`
   gate.

### Risks and edge cases

- do not count only invited peers; the cap is total current group members,
  including the creator/admin
- keep the add-member batch rule all-or-nothing so rejected selections do not
  partially mutate local state
- preserve existing at-limit success; the 50th member should still be allowed
- do not widen into user-facing copy yet beyond the existing generic failure
  surfaces

### Exact tests and gates to run

Direct tests:

- `flutter test test/features/groups/application/add_group_member_use_case_test.dart test/features/groups/application/create_group_with_members_use_case_test.dart test/features/groups/presentation/contact_picker_wired_test.dart`

Named gates:

- `./scripts/run_test_gates.sh groups`

### Done criteria

- single-add overflow is rejected before mutation
- create-with-members overflow is rejected before group creation
- add-member batch overflow leaves the group unchanged
- the direct suites above pass
- the required named gate is run

### Scope guard

- do not add new localized strings or special-case snackbars in this session
- do not start maintained-doc closure in this session
