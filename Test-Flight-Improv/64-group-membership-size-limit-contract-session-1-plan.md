# 64 Session 1 Plan: Define Group Membership Size Contract

## Final verdict

- `implementation-ready`

## Final plan

### Real scope

- choose one explicit repo-owned max group size for the current product
  contract
- encode that cap once in a shared policy/helper seam so create, add, UI, and
  maintained docs cannot silently fork the rule
- expose a typed overflow exception with enough metadata for later sessions to
  reject over-limit operations without string matching
- add direct policy proof for the chosen cap, remaining-slot math, and
  overflow metadata

Out of scope for this session:

- enforcing the cap in create/add flows
- user-visible create/add failure copy
- matrix or architecture-doc closure work

### Closure bar

Session `1` is done only when:

- the repo names one concrete max group size instead of leaving it
  contract-undefined
- the counting rule is explicit enough for later sessions to enforce
  deterministically
- later sessions can catch one typed overflow exception instead of parsing raw
  strings
- direct tests pin the cap and overflow math

### Source of truth

- active session contract:
  `Test-Flight-Improv/64-group-membership-size-limit-contract-session-breakdown.md`
- product/problem doc:
  `Test-Flight-Improv/64-group-membership-size-limit-contract.md`
- maintained architecture note:
  `Test-Flight-Improv/09-network-group-messaging.md`
- matrix row source:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`

### Exact problem statement

`UX-009` is still open because the repo describes target group-size ranges but
does not own one explicit product cap. Later enforcement and UX sessions cannot
be truthful until the app first names one concrete max-membership contract and
one reusable overflow helper.

### Files and repos to inspect next

Production files:

- `lib/features/groups/domain/models/group_membership_limit_policy.dart`
- `lib/features/groups/application/add_group_member_use_case.dart`

Direct tests:

- `test/features/groups/domain/models/group_membership_limit_policy_test.dart`

### Existing tests covering this area

- there is currently no direct policy seam or test for max group size, so this
  session must introduce both

### Regression/tests to add first

- add `test/features/groups/domain/models/group_membership_limit_policy_test.dart`
  first so the chosen cap and helper math are pinned before later sessions
  depend on them

### Step-by-step implementation plan

1. Add one shared policy file that defines the explicit member cap for the
   current repo-owned contract.
2. Add helper math for remaining slots and overflow count.
3. Add a typed `GroupMembershipLimitException` that records current count,
   requested additional members, and the max.
4. Add direct unit tests for the cap value, remaining-slot math, and overflow
   exception metadata.
5. Run the direct policy test and the required named gate.

### Risks and edge cases

- make the counting rule explicit: the cap is total members in the group,
  including the creator/admin
- keep the helper generic enough for both create-time selection and later
  add-member flows
- do not widen into bridge-side limits the repo does not own

### Exact tests and gates to run

Direct tests:

- `flutter test test/features/groups/domain/models/group_membership_limit_policy_test.dart`

Named gates:

- `./scripts/run_test_gates.sh groups`

### Done criteria

- one concrete max-group-size contract is encoded in repo-owned code
- overflow math and exception metadata are directly tested
- Session `2` can enforce the cap without inventing its own counting logic

### Scope guard

- do not enforce the limit in create/add flows in this session
- do not add user-visible strings or snackbars in this session
- do not touch maintained docs in this session
