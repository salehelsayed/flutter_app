# Session GM-016 Plan - Network partition and reconnect

## Final verdict

`implementation-ready`

Current repo evidence shows `GM-016` is a narrow direct-proof gap:

- `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  classifies `GM-016` as `implementation-ready` with `tests only` ownership.
- The repo already proves the component behaviors separately: a disconnected
  reader can drain missed group messages on resume, watchdog restart rejoins
  topics and resumes live delivery, and partial live-plus-inbox delivery is
  covered.
- The remaining row-specific gap is narrower: there is still no single
  fake-network regression that explicitly models a temporary partition, then
  heals it with deterministic inbox page release order before live delivery
  resumes.

The smallest safe session is therefore to add one row-owned integration
regression that uses the existing fake network and cursor inbox bridge to model
partition -> missed sends -> ordered inbox replay on heal -> resumed live
delivery, then update the row-owned docs truthfully after that proof passes.

## Final plan

### real scope

- Close source row `GM-016` only: add one narrow fake-network integration
  regression proving a temporarily partitioned group member misses live sends,
  replays the missed messages in deterministic inbox order after heal, and then
  resumes live delivery without duplicates.
- Keep the change bounded to test coverage in:
  - `test/features/groups/integration/group_resume_recovery_test.dart`
- Update only the row-owned closure docs named by the breakdown after the proof
  lands:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`

### closure bar

- The new regression explicitly creates a temporary partition using the fake
  group pubsub network.
- An online peer receives the partition-window messages live while the
  partitioned peer receives none before heal.
- Healing the partition replays the missed inbox backlog in the intended order
  via deterministic cursor pages.
- After heal, a new live message reaches both peers once.
- Direct proof passes, and the named gate below passes or is recorded
  truthfully if an unrelated failure remains outside this row's write scope.
- `GM-016` is updated to `Closed` or `Covered` only after the docs cite the
  landed evidence.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Current code/tests win over stale prose when they disagree.

### session classification

`implementation-ready`

### exact problem statement

- Existing reconnect coverage is real but fragmented across separate tests.
- The row still lacks one exact fake-network partition/heal regression with
  controlled split timing and release order.
- This session should not widen into transport redesign, relay recovery
  rewrites, or new production partition controls.

### regression/tests to add first

- Add one row-owned integration test in
  `test/features/groups/integration/group_resume_recovery_test.dart` that:
  - partitions one member by unsubscribing them from the fake network
  - sends two messages during the split through the bridge-backed group send
    path so inbox fallback is exercised
  - replays those missed messages through deterministic cursor pages on heal
  - asserts ordered catch-up plus post-heal live delivery

### step-by-step implementation plan

1. Preserve unrelated local edits and keep the scope on `GM-016` test proof
   only.
2. Add any tiny test helpers needed to capture multiple stored inbox payloads
   deterministically.
3. Add the partition-heal integration regression to
   `test/features/groups/integration/group_resume_recovery_test.dart`.
4. Run the direct test file and the named gate below.
5. Update the matrix row, breakdown ledger/notes, and
   `09-network-group-messaging.md` only after the proof passes.

### risks and edge cases

- Keep the test deterministic; do not rely on random fake-network drop rate.
- Do not weaken the row into a generic resume test that never proves the split
  and heal phases explicitly.
- Do not assert a stronger total-ordering guarantee than the repo currently
  claims; this row is about partition catch-up and resumed delivery.

### exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart`
- Named gates:
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh transport` only if a
    production timing, replay, or reconnect path changes instead of test-only
    proof

### known-failure interpretation

- If the partitioned peer can receive partition-window messages before heal,
  the fake-network split is not modeled correctly and the row remains open.
- If the inbox replay order is not deterministic after heal, the row still
  lacks the required controlled release-order proof.
- If post-heal live delivery does not resume, the repo still has a real
  reconnect gap for this row.

### done criteria

- One explicit fake-network partition-heal regression exists and passes.
- The regression proves missed-message catch-up plus resumed live delivery for
  the partitioned member.
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart`
  passes.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passes.
- `GM-016` is updated in the source matrix and breakdown with concrete
  file-and-test evidence, and `09-network-group-messaging.md` no longer treats
  the row as missing an explicit partition-heal proof.

### scope guard

- Do not change production reconnection logic unless the test disproves the
  current behavior.
- Do not widen into lifecycle, relay-health, or notification work.
- Do not add generalized fake-network partition infrastructure unless one tiny
  helper is required for this exact regression.

### accepted differences / intentionally out of scope

- Large-scale churn, random packet loss, and true concurrent multi-writer
  partitions remain outside this row.
- Receipt-level proof of end-user delivery remains outside this row.

### dependency impact

- `GM-016` can close independently once the explicit partition-heal proof
  lands.
- `CLOSURE-001` depends on this row being truthfully updated after execution.
