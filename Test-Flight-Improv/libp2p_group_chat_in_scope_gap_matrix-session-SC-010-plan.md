# Session SC-010 Plan - Replay protection

## Final verdict

`implementation-ready`

Current repo evidence shows `SC-010` is a proof gap, not a broad behavior gap:

- `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  classifies `SC-010` as `implementation-ready` with `tests only` ownership.
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
  already deduplicates incoming messages by `messageId` before the listener can
  emit a second timeline item.
- `lib/features/groups/application/group_message_listener.dart` only calls
  `maybeShowNotification(...)` when `handleIncomingGroupMessage(...)` returns a
  newly persisted message, so duplicate replays should not notify twice.
- The missing piece is one row-owned regression that proves a replayed group
  message does not create a second local notification.

The smallest safe session is therefore to add one replay-through-listener
notification regression, verify the existing `groups` gate still passes, and
then update the row-owned docs truthfully.

## Final plan

### real scope

- Close source row `SC-010` only: prove that replaying the same group message
  does not create a second timeline row or a second local notification.
- Keep the implementation test-only unless the direct regression disproves the
  current listener logic.
- Preferred direct test home:
  - `test/features/groups/application/group_message_listener_test.dart`
- Update only the row-owned closure docs named by the breakdown after the proof
  lands:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`

### closure bar

- The repo has one direct regression that:
  - delivers a group message normally
  - replays the same message later through the listener path
  - proves the stored message count remains `1`
  - proves the local notification count remains `1`
- No production code change is needed unless the regression fails.
- Direct proof passes, and the named `groups` gate passes.
- `SC-010` is updated to `Closed` or `Covered` only after the row docs cite
  the landed test evidence.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Current code/tests win over stale prose when they disagree.
- Verified seam files:
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
  - `lib/features/push/application/show_notification_use_case.dart`
  - `test/features/groups/application/group_message_listener_test.dart`

### session classification

`implementation-ready`

### exact problem statement

- The repo already deduplicates replayed incoming group messages and should
  avoid duplicate notifications because the listener only notifies on newly
  persisted messages.
- The open gap is narrower: there is not yet one explicit replay regression
  proving the no-duplicate-notification half.
- This session should not widen into route-open behavior or remote-push
  suppression policy changes.

### regression/tests to add first

- Add one direct replay regression in
  `test/features/groups/application/group_message_listener_test.dart`
  proving the same `messageId` replayed through the listener path does not
  create a second notification or a second stored row.

### step-by-step implementation plan

1. Preserve unrelated local edits and keep the session test-only unless the
   regression exposes a real behavior gap.
2. Add the replay-through-listener regression in
   `test/features/groups/application/group_message_listener_test.dart`.
3. Reuse the existing notification harness, fake notification service, and
   in-memory repositories instead of inventing a new harness.
4. Run the direct suites and named gate below.
5. Update the matrix row, breakdown ledger/notes, and
   `09-network-group-messaging.md` only after the landed proof passes.

### risks and edge cases

- Keep the proof tied to replay of the same message id; broader stale-event
- or remote-push policy work belongs to other rows.
- Avoid changing notification routing or route-open logic unless the direct
  replay regression disproves current behavior.

### exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart`
- Named gates:
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`

### known-failure interpretation

- If the new replay regression fails, treat that as in-scope evidence that the
  listener still notifies on duplicate replays.
- If the `groups` gate exposes unrelated pre-existing failures, keep them
  separate unless they touch the replay/dedupe seam.

### done criteria

- The new replay regression proves the same message replay does not create a
  second local notification or a second stored row.
- The direct suite above passes.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passes.
- `SC-010` is updated in the source matrix and breakdown with concrete
  file-and-test evidence, and `09-network-group-messaging.md` no longer treats
  this row as only partially proven.

### scope guard

- Do not widen into notification-route anchoring; that remains `GM-011`.
- Do not broaden into remote-push policy changes beyond replay suppression.
- Do not widen into stale-event rollback or authentication work.

### accepted differences / intentionally out of scope

- Remote push dedupe policy remains as currently implemented.
- Route-open behavior for taps stays unchanged in this session.

### dependency impact

- `SC-010` can close independently once the replay notification regression
  lands.
- `CLOSURE-001` depends on this row being truthfully updated after execution.
