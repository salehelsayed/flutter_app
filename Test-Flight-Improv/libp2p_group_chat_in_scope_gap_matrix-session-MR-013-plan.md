# Session MR-013 Plan - Remaining members see removal system event

## Final verdict

`implementation-ready`

Current repo evidence shows `MR-013` is a bounded live-timeline gap:

- `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  classifies `MR-013` as `implementation-ready` with `code changes and tests`
  ownership.
- The repo already proves the membership state side of removal: remaining
  members process `member_removed` config events and converge on the updated
  member list.
- The remaining row-owned gap is narrower: `GroupMessageListener` explicitly
  keeps `member_removed` off the UI message stream, so the conversation
  timeline never receives a readable removal event such as `Admin removed
  Charlie`.

The smallest safe session is therefore to synthesize a readable
`member_removed` timeline entry for remaining members on the live group
message stream, add one listener proof for the emitted event, add one
conversation-screen proof that the stream-rendered event appears in the UI,
add one membership-smoke proof that a remaining member receives that event
during the real removal flow, then update the row-owned docs truthfully.

## Final plan

### real scope

- Close source row `MR-013` only: make remaining members see a readable
  removal event in the live conversation timeline while preserving existing
  membership convergence behavior.
- Keep the change bounded to:
  - `lib/features/groups/application/group_message_listener.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/features/groups/presentation/group_conversation_wired_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
- Update only the row-owned closure docs named by the breakdown after the
  proof lands:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`

### closure bar

- A `member_removed` event for another peer still updates the remaining
  members' local config state.
- The same event now emits a readable timeline entry on
  `groupMessageStream` for remaining members.
- The conversation UI renders that live stream event.
- A real remove flow in the membership smoke harness proves a remaining member
  receives the readable removal event while their member list also updates.
- Direct proof passes, and the named gates below pass or are recorded
  truthfully if an unrelated failure remains outside this row's write scope.
- `MR-013` is updated to `Closed` or `Covered` only after the docs cite the
  landed evidence.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Current code/tests win over stale prose when they disagree.

### session classification

`implementation-ready`

### exact problem statement

- Remaining members already converge on the updated member list after removal.
- What remains open is presentation: the removal event never reaches the live
  conversation stream, so the timeline cannot show `A removed C`.
- This session should not widen into durable system-message history redesign,
  custom system-message widgets, or broader membership-event persistence work.

### regression/tests to add first

- Add a listener regression proving `member_removed` emits a readable timeline
- event for remaining members.
- Add a conversation-widget regression proving that emitted event renders in
  the conversation UI.
- Add a membership-smoke regression proving a real bystander receives the
  readable event during the remove flow.

### step-by-step implementation plan

1. Preserve unrelated local edits and keep the scope on live removal-event
   surfacing only.
2. Extend `GroupMessageListener` so non-self `member_removed` events emit a
   readable synthetic `GroupMessage` for the UI stream.
3. Add the listener proof in
   `test/features/groups/application/group_message_listener_test.dart`.
4. Add the conversation rendering proof in
   `test/features/groups/presentation/group_conversation_wired_test.dart`.
5. Add the real-flow bystander proof in
   `test/features/groups/integration/group_membership_smoke_test.dart`.
6. Run the direct suites and named gates below.
7. Update the matrix row, breakdown ledger/notes, and
   `11-group-discussion-use-case-audit.md` only after the proof passes.

### risks and edge cases

- Do not emit the synthetic timeline event for self-removal, because that path
  still exits the group immediately.
- Keep duplicate/stale membership-event suppression intact so replayed removal
  events do not double-emit the timeline entry.
- Avoid redesigning the screen layer; the existing conversation message stream
  and rendering path are sufficient.

### exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/integration/group_membership_smoke_test.dart`
- Named gates:
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` because the
    session changes live timeline presentation behavior

### known-failure interpretation

- If remaining members still receive no `groupMessageStream` event for
  `member_removed`, the row remains open.
- If the conversation UI does not render the emitted event, the timeline half
  of the row is still missing.
- If the self-removal path starts showing a synthetic message before exit, the
  session widened the behavior incorrectly.

### done criteria

- Remaining members receive a readable removal event on the live UI stream.
- The conversation UI renders that event.
- A real removal flow proves bystander receipt while membership state still
  converges.
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/integration/group_membership_smoke_test.dart`
  passes.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passes.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` passes or is
  recorded truthfully as unrelated drift outside this row's write scope.
- `MR-013` is updated in the source matrix and breakdown with concrete
  file-and-test evidence, and `11-group-discussion-use-case-audit.md` no
  longer treats removal-event visibility as an open gap.

### scope guard

- Do not redesign all system messages into durable chat history in this row.
- Do not alter add-member or key-rotation event presentation.
- Do not widen into offline bystander sync or admin-change propagation.

### accepted differences / intentionally out of scope

- Rich custom styling for system timeline entries remains outside this row;
  readable text in the existing timeline path is enough.
- Durable history for past removal events after a cold reload remains outside
  this row unless it proves necessary to land the bounded live-stream closure.

### dependency impact

- `MR-013` can close independently once the live removal-event surfacing and
  proofs land.
- `CLOSURE-001` depends on this row being truthfully updated after execution.
