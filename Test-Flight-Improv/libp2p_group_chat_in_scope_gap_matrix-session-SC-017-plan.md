# Session SC-017 Plan - Duplicate membership or role event is idempotent

## Final verdict

`implementation-ready`

Current repo evidence shows `SC-017` is mostly a proof gap, with one likely
duplicate-self-removal edge that may need a small runtime guard:

- `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  classifies `SC-017` as `implementation-ready`.
- `member_added` persistence is already map/upsert-backed in the in-memory
  repository and membership system events are not emitted on
  `groupMessageStream`.
- `member_removed` for non-self peers is already idempotent at the repository
  layer, but duplicate self-removal appears able to call `leaveGroup()` and
  emit `groupRemovedStream` more than once because system messages are still
  processed after the local group has been deleted.

The smallest safe session is therefore to add direct duplicate-event
regressions first, keep the work test-led, and land only the smallest code
guard required if the self-removal duplicate path proves non-idempotent.

## Final plan

### real scope

- Close source row `SC-017` only: prove duplicate supported membership events
  converge to one canonical state and do not produce duplicate UI effects.
- Cover the repo-owned event types that currently exist:
  - duplicate `member_added`
  - duplicate `member_removed` for self-removal UI cleanup
- Keep the implementation as tests-only unless the duplicate self-removal
  regression proves a real repeated-effect bug.
- Preferred direct test home:
  - `test/features/groups/application/group_message_listener_test.dart`
- If a code fix is needed, keep it limited to
  `lib/features/groups/application/group_message_listener.dart`.
- Update only the row-owned closure docs named by the breakdown after the proof
  lands:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`

### closure bar

- The repo has direct regressions that:
  - deliver the same `member_added` system event twice
  - prove there is one canonical member/admin-role state and no regular
    message-stream UI effect
  - deliver the same self-removal `member_removed` system event twice
  - prove `groupRemovedStream` emits once and `group:leave` runs once
- No broader architecture or validator changes are needed.
- Direct proof passes, and the named `groups` gate passes.
- `SC-017` is updated to `Closed` or `Covered` only after the row docs cite
  the landed evidence.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Current code/tests win over stale prose when they disagree.
- Verified seam files:
  - `lib/features/groups/application/group_message_listener.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/shared/fakes/in_memory_group_repository.dart`

### session classification

`implementation-ready`

### exact problem statement

- The repo already stores membership state in an upsert-like way and does not
  surface membership system events on the regular message stream.
- The missing row-owned proof is explicit duplicate-event coverage, and the
  self-removal path may still duplicate the removal UI effect.
- This session should not widen into signed-event validation, stale-event
  ordering, or raw unauthorized-event resistance.

### regression/tests to add first

- Add duplicate `member_added` coverage in
  `test/features/groups/application/group_message_listener_test.dart`.
- Add duplicate self-removal `member_removed` coverage in the same file.

### step-by-step implementation plan

1. Preserve unrelated local edits and start with direct duplicate-event tests.
2. If duplicate self-removal emits repeated UI cleanup, add the smallest guard
   in `lib/features/groups/application/group_message_listener.dart` so already
   removed groups ignore duplicate self-removal events.
3. Re-run the focused suite and named gate below.
4. Update the matrix row, breakdown ledger/notes, and
   `09-network-group-messaging.md` only after the landed proof passes.

### risks and edge cases

- Keep the scope tied to the membership system event types the repo actually
  handles today.
- Do not widen into future promote/demote protocol design beyond the current
  member-role state carried in existing config snapshots.

### exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart`
- Named gates:
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`

### known-failure interpretation

- If duplicate self-removal repeats `groupRemovedStream` or `group:leave`, that
  is an in-scope idempotence bug and should be fixed in this session.
- If the `groups` gate exposes unrelated pre-existing failures, keep them
  separate unless they touch membership-event idempotence.

### done criteria

- Duplicate `member_added` and duplicate self-removal `member_removed`
  regressions pass.
- The direct suite above passes.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passes.
- `SC-017` is updated in the source matrix and breakdown with concrete
  file-and-test evidence, and `09-network-group-messaging.md` no longer treats
  this row as only partially proven.

### scope guard

- Do not widen into authenticated event validation; that remains `SC-015`.
- Do not widen into stale-event rollback; that remains `SC-018`.
- Do not widen into remove-vs-send ordering; that remains `MR-015` and
  `SC-012`.

### accepted differences / intentionally out of scope

- Future standalone role-event protocol design remains unchanged.
- Bridge validator update retries remain as currently implemented.

### dependency impact

- `SC-017` can close independently once duplicate membership-event idempotence
  is directly proven.
- `CLOSURE-001` depends on this row being truthfully updated after execution.
