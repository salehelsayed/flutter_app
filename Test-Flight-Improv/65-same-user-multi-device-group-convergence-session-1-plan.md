# 65 Session 1 Plan: Define The Same-User Multi-Device Contract

## Final verdict

- `implementation-ready`

## Final plan

### Real scope

- choose one explicit shared-vs-device-local contract for two devices that
  restore the same identity
- encode that contract once in a repo-owned policy seam so later harness,
  regression, and maintained-doc work can cite one source of truth
- make the joined-device precondition explicit: shared-state convergence applies
  once the second device has already materialized the group locally
- add direct proof for the selected mapping

Out of scope for this session:

- same-peer harness changes or receive-path behavior
- new integration proofs for live or replay convergence
- maintained-doc closure work

### Closure bar

Session `1` is done only when:

- the repo names exactly which group facts are shared across same-identity
  joined devices and which remain installation-local
- the chosen contract is encoded in one repo-owned seam rather than only in
  markdown prose
- direct tests prove that mapping without relying on inferred comments

### Source of truth

- active session contract:
  `Test-Flight-Improv/65-same-user-multi-device-group-convergence-session-breakdown.md`
- product/problem doc:
  `Test-Flight-Improv/65-same-user-multi-device-group-convergence.md`
- current architecture note:
  `Test-Flight-Improv/09-network-group-messaging.md`
- local state seams:
  `lib/features/groups/domain/models/group_model.dart`
  `lib/features/identity/domain/repositories/identity_repository.dart`
  `lib/features/groups/application/set_group_muted_use_case.dart`
  `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
  `lib/features/groups/application/decline_pending_group_invite_use_case.dart`

### Exact problem statement

The repo currently has no explicit same-user multi-device rule. Without a
single contract, later harness and regression work would have to guess whether
messages, membership, mute, unread, notifications, and invite review are
shared or device-local, which would keep `UX-013` contract-undefined in
practice.

### Files and repos to inspect next

Production files:

- `lib/features/groups/domain/models/group_model.dart`
- `lib/features/identity/domain/repositories/identity_repository.dart`
- `lib/features/groups/application/set_group_muted_use_case.dart`
- `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
- `lib/features/groups/application/decline_pending_group_invite_use_case.dart`

Direct tests:

- `test/features/groups/domain/models/group_multi_device_policy_test.dart`

### Step-by-step implementation plan

1. Add a repo-owned group multi-device policy seam that names each supported
   facet as either shared across joined devices or device-local.
2. Encode the joined-device precondition in that seam so later sessions do not
   overclaim pending-invite or account-wide sync behavior.
3. Add direct policy tests proving the shared-vs-local mapping.
4. Run the direct policy suite and prepare Session `2` against the landed
   contract.

### Risks and edge cases

- do not imply a new account-sync subsystem that does not exist in this repo
- keep pending invite review separate from joined-group convergence unless the
  code genuinely supports more
- be explicit that device-local mute, unread, and notifications are a chosen
  product contract, not an accidental omission

### Exact tests and gates to run

Direct tests:

- `flutter test test/features/groups/domain/models/group_multi_device_policy_test.dart`

Named gates:

- no named gate is required for the policy-only slice if production behavior
  does not change yet

### Done criteria

- the repo owns one explicit same-user multi-device contract seam
- direct policy proof passes
- Session `2` can implement harness and receive-path work without policy drift

### Scope guard

- do not start same-peer harness edits in this session until the contract seam
  exists
- do not touch maintained docs yet
