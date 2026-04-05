# 65 Session 3 Plan: Prove Device-Local Same-User Exceptions

## Final verdict

- `implementation-ready`

## Final plan

### Real scope

- prove that group mute remains device-local across two devices that restore
  the same identity, even after Session `2` landed shared joined-device
  message and membership convergence
- prove that unread counts and local notification suppression also remain
  device-local, so clearing or muting on one device does not silently clear or
  suppress the sibling device
- prove that pending-invite review stays local to the installation that
  accepted or declined it; there is no repo-owned account-wide pending-invite
  sync channel
- keep the proof bounded to tests unless the current code contradicts the
  already-chosen contract

Out of scope for this session:

- reopening the shared-state harness work from Session `2` unless a new test
  proves a real defect there
- maintained-doc closure or matrix cleanup
- inventing a new account-sync, invite-sync, or preferences-sync transport

### Closure bar

Session `3` is done only when:

- muting a group on one same-identity device leaves the sibling device
  unmuted and able to keep its own local notification behavior
- unread state is proven device-local by showing that clearing one device does
  not clear the sibling device
- pending-invite review is proven device-local by showing that accepting or
  declining on one repository does not automatically clear the sibling
  repository
- the focused direct/integration suites pass along with the required
  `groups` gate

### Source of truth

- active session contract:
  `Test-Flight-Improv/65-same-user-multi-device-group-convergence-session-breakdown.md`
- session `1` policy seam:
  `lib/features/groups/domain/models/group_multi_device_policy.dart`
- session `2` shared-state proof:
  `test/features/groups/integration/group_multi_device_convergence_test.dart`
- local mute and notification seams:
  `lib/features/groups/application/set_group_muted_use_case.dart`
  `lib/features/groups/application/group_message_listener.dart`
- pending-invite review seams:
  `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
  `lib/features/groups/application/decline_pending_group_invite_use_case.dart`

### Exact problem statement

The repo now names device-local exceptions in policy and can model shared
joined-device convergence, but it still needs explicit proof that those
exceptions stay local. Without that proof, `UX-013` still reads as partially
implicit because mute, unread, notification suppression, and pending-invite
review could appear account-wide by accident or drift over time.

### Files and repos to inspect next

Direct/shared-state proof:

- `test/features/groups/integration/group_multi_device_convergence_test.dart`

Notification and local-state seams:

- `test/shared/fakes/group_test_user.dart`
- `test/shared/fakes/fake_notification_service.dart`
- `lib/features/groups/application/group_message_listener.dart`

Pending-invite proof:

- `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
- `test/features/groups/application/decline_pending_group_invite_use_case_test.dart`
- `test/shared/fakes/in_memory_pending_group_invite_repository.dart`

### Existing tests covering this area

- Session `2` already proves same-identity joined devices share live message
  history and membership convergence once the second device has materialized
  the group locally
- `group_message_listener_test.dart` already proves muted-group notification
  suppression on one device, but not the same-user sibling-device contrast
- accept/decline pending-invite tests already prove single-device local
  behavior, but not same-user sibling-device independence across two repos

### Regression/tests to add first

- extend `group_multi_device_convergence_test.dart` with a same-user
  sibling-device scenario where one device is muted, the other is not, and the
  same incoming group message proves notification suppression and unread state
  remain local
- add an accept-pending-invite regression that uses two independent pending
  invite repositories for the same logical user and proves accepting on one
  device does not clear the sibling device
- add a decline-pending-invite regression that proves the same device-local
  independence for decline

### Step-by-step implementation plan

1. Extend the same-user integration harness to inject independent local
   notification services into two devices that share one peer identity.
2. Add a focused integration regression that mutes only one device, delivers
   the same incoming message to both devices, and proves mute, notification,
   and unread behavior stay device-local.
3. Add direct accept/decline pending-invite regressions using two repositories
   for the same invite so device-local review behavior is explicit.
4. Run the focused direct/integration suites and the required `groups` gate.

### Risks and edge cases

- do not accidentally restate the contract as account-wide mute or unread sync;
  Session `1` already chose device-local for those facets
- keep the same-user integration proof truthful by using joined devices for
  message-state assertions and separate pending-invite repositories for
  pre-join invite-review assertions
- avoid relying on notification side effects alone; also assert persisted
  message and unread state so the proof remains stable

### Exact tests and gates to run

Direct tests:

- `flutter test test/features/groups/integration/group_multi_device_convergence_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/application/decline_pending_group_invite_use_case_test.dart`

Named gates:

- `./scripts/run_test_gates.sh groups`

### Done criteria

- same-user sibling devices prove device-local mute, unread, and local
  notification behavior under one incoming-message scenario
- accept and decline pending-invite tests prove repository-local review
  behavior across two devices
- the direct suites above pass
- the required named gate is run

### Scope guard

- do not widen this session into maintained-doc edits; that belongs to Session
  `4`
- do not invent cross-device cleanup for pending invites when the chosen
  contract is explicit that invite review remains local until a device
  materializes the group
