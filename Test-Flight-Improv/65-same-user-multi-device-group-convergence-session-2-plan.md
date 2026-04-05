# 65 Session 2 Plan: Support Same-Identity Joined-Device Convergence

## Final verdict

- `implementation-ready`

## Final plan

### Real scope

- extend the fake group pubsub harness so two devices can share one peer
  identity without overwriting each other's controllers or subscriptions
- preserve existing distinct-peer semantics while letting a same-identity
  sibling device receive the live publish copy it needs for shared message
  history convergence
- make the receive path self-aware so a sibling device that gets the same
  user's own message persists truthful sent history instead of unread incoming
  state
- add same-user joined-device regressions for shared message/state convergence
  inside the current repo-owned scope

Out of scope for this session:

- device-local mute, unread, notification, or pending-invite proofs
- maintained-doc closure work
- inventing a new account-sync or backup transport outside the current
  repo-owned group message and state seams

### Closure bar

Session `2` is done only when:

- the test harness can keep two devices with one peer id alive at the same
  time without controller clobbering
- a message sent from one joined device is reflected on a sibling joined device
  with truthful local sent-state semantics
- same-user joined devices continue to converge supported group-authoritative
  state without duplicate membership rows
- direct integration and receive-path tests prove the new behavior without
  breaking existing distinct-peer flows

### Source of truth

- active session contract:
  `Test-Flight-Improv/65-same-user-multi-device-group-convergence-session-breakdown.md`
- session `1` contract seam:
  `lib/features/groups/domain/models/group_multi_device_policy.dart`
- current harness seams:
  `test/shared/fakes/fake_group_pubsub_network.dart`
  `test/shared/fakes/group_test_user.dart`
- receive path:
  `lib/features/groups/application/group_message_listener.dart`
  `lib/features/groups/application/handle_incoming_group_message_use_case.dart`

### Exact problem statement

The repo now names the same-user contract, but it still cannot prove it:
`FakeGroupPubSubNetwork` overwrites one controller per peer id, publish skips
all devices for the sender peer, and `handleIncomingGroupMessage(...)` has no
way to tell that another joined device with the same identity should treat the
message as local sent history rather than unread incoming state.

### Files and repos to inspect next

Production files:

- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`

Test harness files:

- `test/shared/fakes/fake_group_pubsub_network.dart`
- `test/shared/fakes/group_test_user.dart`

Direct tests:

- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- `test/features/groups/integration/group_multi_device_convergence_test.dart`

### Step-by-step implementation plan

1. Add a device-aware registration/subscription path to the fake group pubsub
   network while preserving the current peer-id-based API for existing tests.
2. Update `GroupTestUser` so same-identity devices can opt into distinct device
   ids and publish with a source-device hint instead of clobbering one another.
3. Extend `handleIncomingGroupMessage(...)` and the listener call site so the
   receive seam can persist same-self deliveries as local sent history on a
   sibling device.
4. Add same-user joined-device regressions for shared live message convergence
   and no-duplicate-membership behavior.
5. Run the direct receive/integration suites plus the required `groups` gate.

### Risks and edge cases

- do not break the existing single-device-per-peer tests that rely on the old
  API shape
- keep sender-device duplicate suppression intact for the source device while
  allowing the sibling device to converge
- avoid counting a same-identity sibling device as a new group member
- keep self-sent copies off unread counters and local notifications on sibling
  devices

### Exact tests and gates to run

Direct tests:

- `flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart test/features/groups/integration/group_multi_device_convergence_test.dart`

Named gates:

- `./scripts/run_test_gates.sh groups`

### Done criteria

- same-identity sibling devices can coexist in the harness
- live same-user joined-device message convergence is proven
- direct receive/integration suites pass
- the required named gate is run

### Scope guard

- do not widen this session into mute/unread/notification policy proof yet
- do not touch maintained docs until Sessions `2` and `3` are both accepted
