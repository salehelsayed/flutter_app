# 65 Session 4 Plan: Close UX-013 In Maintained Docs

## Final verdict

- `implementation-ready`

## Final plan

### Real scope

- update the maintained architecture note and matrix docs so they describe the
  landed same-user multi-device contract instead of leaving `UX-013`
  contract-undefined
- close `UX-013` with concrete proof references spanning the shared-state
  contract, same-identity joined-device convergence, and the explicit
  device-local exceptions
- remove `UX-013` from the policy-needed and not-fully-implemented trackers
- record the final doc-65 closure verdict after same-day verification is
  attached

Out of scope for this session:

- changing the chosen shared-versus-local same-user contract
- inventing account-wide mute, unread, notification, or invite-review sync
- reopening admin-transfer or other still-open matrix rows

### Closure bar

Session `4` is done only when:

- `09-network-group-messaging.md` states the explicit same-user multi-device
  contract, including the joined-device precondition, the shared
  group-authoritative state, and the device-local exceptions
- the full matrix marks `UX-013` closed with exact repo-local proof references
- the policy-needed and not-fully-implemented trackers no longer list
  `UX-013`
- the doc-65 breakdown records a final `closed` verdict with same-day
  verification evidence

### Source of truth

- active session contract:
  `Test-Flight-Improv/65-same-user-multi-device-group-convergence-session-breakdown.md`
- product/problem doc:
  `Test-Flight-Improv/65-same-user-multi-device-group-convergence.md`
- session `1` contract seam:
  `lib/features/groups/domain/models/group_multi_device_policy.dart`
- session `2` shared-state seams:
  `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
  `test/features/groups/integration/group_multi_device_convergence_test.dart`
- session `3` device-local proof:
  `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
  `test/features/groups/application/decline_pending_group_invite_use_case_test.dart`
- maintained architecture note:
  `Test-Flight-Improv/09-network-group-messaging.md`
- maintained matrix docs:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  `Test-Flight-Improv/libp2p_group_chat_policy_needed_matrix.md`
  `Test-Flight-Improv/libp2p_group_chat_matrix_not_fully_implemented.md`

### Exact problem statement

The repo now owns the same-user multi-device contract in code and tests, but
the long-lived maintenance docs still describe `UX-013` as
contract-undefined. Session `4` must bring those docs back into sync so the
row stays closed unless the behavior truly regresses.

### Files and repos to inspect next

Docs:

- `Test-Flight-Improv/09-network-group-messaging.md`
- `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/libp2p_group_chat_policy_needed_matrix.md`
- `Test-Flight-Improv/libp2p_group_chat_matrix_not_fully_implemented.md`
- `Test-Flight-Improv/65-same-user-multi-device-group-convergence-session-breakdown.md`

Verification artifacts:

- `test/features/groups/domain/models/group_multi_device_policy_test.dart`
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- `test/features/groups/integration/group_multi_device_convergence_test.dart`
- `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
- `test/features/groups/application/decline_pending_group_invite_use_case_test.dart`

### Step-by-step implementation plan

1. Refresh the maintained network architecture note so it states the explicit
   same-user multi-device contract: joined devices share group-authoritative
   state after local materialization, while mute, unread, local notifications,
   and pending-invite review remain device-local.
2. Update the full matrix row for `UX-013` from `Contract-undefined` to
   `Closed`, using the policy seam and the same-user convergence/device-local
   regressions as proof.
3. Remove `UX-013` from the policy-needed and not-fully-implemented trackers,
   updating the tracker counts to match.
4. Re-run the targeted policy and same-user proof suites plus the required
   named gate, then write the final doc-65 breakdown verdict with same-day
   evidence.

### Risks and edge cases

- keep the docs aligned on the same joined-device precondition: the second
  device must materialize the group locally before shared convergence claims
  apply
- do not describe mute, unread, notification suppression, or pending invites
  as account-wide sync; the chosen contract is explicitly device-local there
- avoid touching unrelated still-open rows beyond the count and wording changes
  required after removing `UX-013`

### Exact tests and gates to run

Direct tests:

- `flutter test test/features/groups/domain/models/group_multi_device_policy_test.dart test/features/groups/application/handle_incoming_group_message_use_case_test.dart test/features/groups/integration/group_multi_device_convergence_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/application/decline_pending_group_invite_use_case_test.dart`

Required named gates:

- `./scripts/run_test_gates.sh groups`

### Done criteria

- maintained docs all agree that `UX-013` is landed repo behavior
- the trackers and full matrix no longer disagree about same-user
  multi-device support
- doc `65` records a final closed verdict with same-day verification evidence

### Scope guard

- do not advance to any later doc or reopen earlier docs until doc `65`
  records a final close
- do not widen this pass into broader account-sync or admin-transfer work
