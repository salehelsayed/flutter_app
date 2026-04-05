# Session UX-005 Plan - Unread count correctness

## Final verdict

`implementation-ready`

Current repo evidence shows `UX-005` is a bounded orchestration-proof gap:

- Existing repository tests already prove unread counting and read-marking in
  isolation.
- Existing recovery tests already prove duplicate inbox drain and retry
  delivery behavior separately.
- What remains missing is one row-owned end-to-end regression that combines
  duplicate recovery, retry recovery, and read clearing without double-counting
  unread state.

## Final plan

### real scope

- Close source row `UX-005` only: add one direct recovery regression that pins
  unread behavior across duplicate inbox drain, retry success, and mark-as-read.
- Keep the change bounded to:
  - `test/features/groups/integration/group_resume_recovery_test.dart`
- Update only the row-owned closure docs named by the breakdown after proof
  lands:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`

### closure bar

- One live incoming group message increments unread to `1`.
- Replaying the same message through inbox drain does not increase unread or
  create a second row.
- A publish failure does not increment receiver unread.
- Retrying that failed message increments unread exactly once when delivery
  finally succeeds.
- Opening/marking the group as read clears unread back to `0`.
- Direct proof passes and the named `groups` gate passes.
- `UX-005` is updated to `Closed` or `Covered` only after docs cite the landed
  regression.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Current code/tests win over stale prose when they disagree.

### session classification

`implementation-ready`

### exact problem statement

- The repo already looks correct, but the matrix still lacks one explicit
  unread regression that spans the duplicate, retry, and reconnect-shaped
  orchestration seams together.
- This row should lock the existing unread contract in place, not redesign
  unread storage or presentation.

### regression/tests to add first

- Add one integration regression in
  `test/features/groups/integration/group_resume_recovery_test.dart` that:
  - sends one live message
  - replays that same message through inbox drain
  - forces one failed publish and retries it
  - marks the group as read and checks unread clears

### step-by-step implementation plan

1. Preserve unrelated local edits and keep the scope on unread accounting proof
   only.
2. Add the combined unread recovery regression to
   `test/features/groups/integration/group_resume_recovery_test.dart`.
3. Reuse existing inbox-drain and retry helpers instead of widening into new
   production code.
4. Run the direct suite and named gate below.
5. Update the matrix row, breakdown ledger/notes, and
   `14-regression-test-strategy.md` only after the proof passes.

### risks and edge cases

- Do not widen into badge UI wiring or notification presentation; the row can
  close at the repository/integration layer.
- Keep the duplicate check tied to message identity so the regression remains
  meaningful if text repeats.
- Avoid reopening broader retry semantics beyond unread correctness.

### exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart`
- Named gates:
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`

### known-failure interpretation

- If unread increases on duplicate inbox drain, the row remains open.
- If unread changes before retry actually succeeds, the row remains open.
- If mark-as-read leaves residual unread after the combined flow, the row
  remains open.

### done criteria

- One exact regression proves unread correctness across duplicate, retry, and
  read-clear flows.
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart`
  passes.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passes.
- `UX-005` is updated in the source matrix and breakdown with concrete
  file-and-test evidence, and the regression strategy doc records the new
  unread-locking recovery regression.

### scope guard

- Do not change production unread code unless the new regression exposes a real
  defect.
- Do not widen into new UI badge tests or push-specific logic in this row.
- Do not redesign retry persistence or inbox drain behavior here.

### accepted differences / intentionally out of scope

- Visual unread badge rendering remains covered elsewhere.
- Device-specific notification counter behavior remains out of scope.

### dependency impact

- `UX-005` can close independently once the unread regression lands.
- `CLOSURE-001` depends on this row being truthfully updated after execution.
