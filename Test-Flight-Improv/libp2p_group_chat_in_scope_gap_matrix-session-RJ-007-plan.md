# Session RJ-007 Plan - System event for re-add

## Final verdict

`implementation-ready`

Current repo evidence shows `RJ-007` is a bounded live-timeline gap:

- The repo already broadcasts and applies `member_added` config events so
  membership state converges after re-add.
- The repo already has a live timeline path for synthetic system entries after
  `MR-013`, but that path currently covers only `member_removed`.
- The protocol does not distinguish first-time add from re-add in a separate
  wire type, so the narrowest practical repo-owned fix is to surface readable
  live `member_added` timeline entries on the same existing stream without
  widening into durable system-message history.

## Final plan

### real scope

- Close source row `RJ-007` only: make remaining members see a readable live
  add-event in the conversation timeline when a `member_added` re-add event is
  processed.
- Keep the change bounded to:
  - `lib/features/groups/application/group_message_listener.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/features/groups/presentation/group_conversation_wired_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
- Update only the row-owned closure docs named by the breakdown after proof
  lands:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`

### closure bar

- A live `member_added` event for another peer still updates remaining
  members' local config state.
- The same event now emits a readable live timeline entry on
  `groupMessageStream`.
- Duplicate `member_added` delivery does not emit duplicate timeline entries.
- The conversation UI renders the live add-event entry.
- A real remove -> re-add flow proves a remaining member receives the readable
  add event while the member list converges.
- Direct proof passes, the named `groups` gate passes, and `baseline` passes or
  is recorded truthfully if unrelated drift remains outside this row's write
  scope.
- `RJ-007` is updated to `Closed` or `Covered` only after the docs cite the
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

- Remaining members already converge on the re-added member in local state.
- What remains open is presentation: `member_added` events are still silent in
  the live conversation timeline, so users cannot see `Admin added Charlie`.
- This session should not widen into durable system-message persistence,
  historic replay redesign, or broader invite protocol changes.

### regression/tests to add first

- Change the existing listener regression so `member_added` emits a readable
  timeline event and duplicate delivery still collapses to one visible event.
- Add a conversation-widget regression proving that emitted event renders in
  the conversation UI.
- Add a membership-smoke regression proving a remaining member receives the
  readable add event during a real remove -> re-add flow while the member list
  updates.

### step-by-step implementation plan

1. Preserve unrelated local edits and keep the scope on live add-event
   surfacing only.
2. Extend `GroupMessageListener` so non-self `member_added` events emit a
   readable synthetic `GroupMessage` on the existing live stream.
3. Reuse the existing stale-membership suppression so duplicate
   `member_added` events do not emit duplicate timeline entries.
4. Add the listener proof in
   `test/features/groups/application/group_message_listener_test.dart`.
5. Add the conversation rendering proof in
   `test/features/groups/presentation/group_conversation_wired_test.dart`.
6. Add the real-flow remaining-member proof in
   `test/features/groups/integration/group_membership_smoke_test.dart`.
7. Run the direct suites and named gates below.
8. Update the matrix row, breakdown ledger/notes, and
   `11-group-discussion-use-case-audit.md` only after the proof passes.

### risks and edge cases

- Do not break the already-landed removal timeline behavior from `MR-013`.
- Keep duplicate suppression intact so replayed or repeated `member_added`
  events do not double-emit visible entries.
- Accept that the current protocol carries both first-add and re-add on
  `member_added`; the row closes on the re-add path, but the live-stream change
  applies to that shared wire type.

### exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/integration/group_membership_smoke_test.dart`
- Named gates:
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`

### known-failure interpretation

- If remaining members still receive no `groupMessageStream` event for
  `member_added`, the row remains open.
- If duplicate `member_added` delivery now emits duplicate add events, the row
  regresses `SC-017`.
- If the conversation UI does not render the emitted event, the timeline half
  of the row is still missing.

### done criteria

- Remaining members receive a readable add event on the live UI stream.
- Duplicate `member_added` delivery still collapses to one visible event.
- The conversation UI renders the add event.
- A real remove -> re-add flow proves bystander receipt while membership state
  converges.
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/integration/group_membership_smoke_test.dart`
  passes.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passes.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` passes or is
  recorded truthfully as unrelated drift outside this row's write scope.
- `RJ-007` is updated in the source matrix and breakdown with concrete
  file-and-test evidence, and `11-group-discussion-use-case-audit.md` no
  longer treats add-event visibility as an open gap.

### scope guard

- Do not redesign all membership events into durable chat history in this row.
- Do not widen into notification resumption or offline re-invite bootstrap;
  those belong to `RJ-005` and `RJ-010`.
- Do not change `members_added` or bulk-add UX unless required to keep the
  shared listener contract coherent.

### accepted differences / intentionally out of scope

- Rich custom styling for system add-event entries remains outside this row;
  readable text on the existing timeline path is enough.
- Durable history for past add events after a cold reload remains outside this
  row unless it proves necessary to land the bounded live-stream closure.

### dependency impact

- `RJ-007` can close independently once the live add-event surfacing and proofs
  land.
- `CLOSURE-001` depends on this row being truthfully updated after execution.
