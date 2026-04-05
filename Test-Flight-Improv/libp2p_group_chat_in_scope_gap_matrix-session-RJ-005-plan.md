# Session RJ-005 Plan - Notifications resume after rejoin

## Final verdict

`implementation-ready`

Current repo evidence still says `RJ-005` is a direct-proof gap, not a
production-code gap:

- `GroupMessageListener` already raises local notifications for incoming group
  messages when the app is backgrounded and the conversation is not active.
- Existing rejoin coverage already proves a removed member can be re-added and
  resume send/receive behavior with current group state.
- What is still missing is one row-owned regression that keeps those two facts
  in the same test seam: no notification while removed, then notification
  resumes only after rejoin becomes effective.

The smallest safe session is therefore to add a notification-enabled
multi-user rejoin regression, with only the minimal test-harness widening
needed to inject the existing notification dependencies into `GroupTestUser`.

## Final plan

### real scope

- Close source row `RJ-005` only: prove local group notifications stay off
  while a removed member is out of the group and resume after the member is
  re-added effectively.
- Keep the change bounded to:
  - `test/shared/fakes/group_test_user.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
- Reuse existing notification coverage in
  `test/features/groups/application/group_message_listener_test.dart` rather
  than widening into production notification-routing changes.
- Update only the row-owned closure docs named by the breakdown after proof
  lands:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`

### closure bar

- While the removed member is unsubscribed and the local group has been cleaned
  up, a new group message does not produce a local notification for that user.
- After the same member is re-added effectively, a new incoming group message
  does produce a local notification again.
- The regression uses the existing listener notification path instead of a
  fake-only shortcut.
- Direct proof passes, and the named gate below passes.
- `RJ-005` is updated to `Closed` or `Covered` only after the docs cite the
  landed evidence.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Current code/tests win over stale prose when they disagree.

### session classification

`implementation-ready`

### exact problem statement

- The repo already proves that removed members stop receiving traffic and that
  re-added members can resume normal group use.
- The repo also already proves the listener can show local notifications for
  incoming group messages.
- The missing row-owned proof is the boundary behavior across removal and
  rejoin: notifications should remain off while removed and come back only once
  rejoin is effective.

### regression/tests to add first

- Add one integration regression in
  `test/features/groups/integration/group_membership_smoke_test.dart` that
  drives remove -> message while removed -> re-add -> message after rejoin
  while observing a fake notification service on the removed/rejoined member.
- Widen `test/shared/fakes/group_test_user.dart` only enough to inject the
  existing notification service, conversation tracker, and lifecycle callback
  into its listener.

### step-by-step implementation plan

1. Preserve unrelated local edits and keep the scope on rejoin-notification
   proof only.
2. Add optional notification dependency injection to the `GroupTestUser`
   helper without changing current callers.
3. Add the row-owned integration regression proving no notification while
   removed and notification resumption after rejoin becomes effective.
4. Run the direct proof commands below.
5. Run the named `groups` gate below.
6. Update the matrix row, breakdown ledger/notes, and
   `11-group-discussion-use-case-audit.md` only after the proof passes.

### risks and edge cases

- Do not widen into remote-push handling, notification tap routing, or payload
  deep-link changes; those were already handled by other rows.
- Keep the new helper parameters optional so existing integration tests stay
  unchanged.
- Do not fake notification success by bypassing `GroupMessageListener`; the
  proof should still flow through the listener's normal incoming-message path.

### exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart`
  - `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart`
- Named gates:
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`

### known-failure interpretation

- If the removed member still receives a notification while unsubscribed, the
  row remains open.
- If the member receives live messages after rejoin but still no notification,
  the row remains open.
- If the proof requires production notification-routing changes, the session
  widened beyond its intended scope and should be reconsidered.

### done criteria

- A removed member receives no notification for messages sent during removal.
- The same member receives a notification again after rejoin becomes effective.
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart`
  passes.
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart`
  passes.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passes.
- `RJ-005` is updated in the source matrix and breakdown with concrete
  file-and-test evidence, and `11-group-discussion-use-case-audit.md` no
  longer treats rejoin-notification resumption as an open gap.

### scope guard

- Do not redesign notification payloads or notification-open routing in this
  row.
- Do not widen into offline re-invite bootstrap coverage; that belongs to
  `RJ-010`.
- Do not change production notification suppression rules unless the new proof
  shows a real bug.

### accepted differences / intentionally out of scope

- Remote push delivery timing remains out of scope; the row can close with
  local notification proof on the existing incoming-message path.
- Notification copy or preview formatting remains out of scope; the row only
  needs on/off correctness across remove and rejoin.

### dependency impact

- `RJ-005` can close independently once the remove/rejoin notification proof
  lands.
- `CLOSURE-001` depends on this row being truthfully updated after execution.
