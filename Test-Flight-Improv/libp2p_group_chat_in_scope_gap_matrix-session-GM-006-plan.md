# Session GM-006 Plan - Sequential same-sender ordering

## Final verdict

`implementation-ready`

Current repo evidence shows `GM-006` is an exact proof gap, not a behavior gap:

- `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  classifies `GM-006` as `implementation-ready` with `tests only` ownership.
- Storage and repository seams already sort group messages chronologically by
  timestamp, and existing smoke coverage observes ordered incoming texts.
- The missing row-owned proof is narrower: one exact three-user regression
  showing that when A sends `M1` then `M2`, both B and C display `M1` before
  `M2` according to the repo's current timestamp-based ordering rule.

The smallest safe session is therefore to add one explicit same-sender ordering
regression, verify the named `groups` gate still passes, and then update the
row-owned docs truthfully.

## Final plan

### real scope

- Close source row `GM-006` only: prove that back-to-back same-sender messages
  are displayed in chronological order for both recipients in the current
  fake-network three-user seam.
- Keep the session test-only unless the new proof disproves the current
  ordering behavior.
- Preferred direct test home:
  - `test/features/groups/integration/group_messaging_smoke_test.dart`
- Update only the row-owned closure docs named by the breakdown after the proof
  lands:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`

### closure bar

- The repo has one direct regression that:
  - creates a three-user live group
  - sends `M1` then `M2` from the same sender
  - proves both recipients read `M1` before `M2`
- No production code change is needed unless the regression fails.
- Direct proof passes, and the named `groups` gate passes.
- `GM-006` is updated to `Closed` or `Covered` only after the row docs cite the
  landed evidence.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Current code/tests win over stale prose when they disagree.
- Verified seam files:
  - `test/features/groups/integration/group_messaging_smoke_test.dart`
  - `test/shared/fakes/in_memory_group_message_repository.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`

### session classification

`implementation-ready`

### exact problem statement

- The repo already orders stored messages chronologically and existing smoke
  coverage shows ordered incoming texts in broader flows.
- The open gap is narrower: the repo still lacks one exact row-owned proof for
  the same-sender `M1 -> M2` path across both non-sender recipients.
- This session should not widen into partition-heal ordering, remove-vs-send
  boundaries, or strict total-order guarantees beyond the app's current rule.

### regression/tests to add first

- Add one direct three-user same-sender ordering regression in
  `test/features/groups/integration/group_messaging_smoke_test.dart` proving
  both recipients display `M1` before `M2`.

### step-by-step implementation plan

1. Preserve unrelated local edits and keep the session test-only unless the new
   proof disproves the current ordering rule.
2. Add the same-sender ordering regression in
   `test/features/groups/integration/group_messaging_smoke_test.dart`.
3. Keep the assertion pinned to the repo's timestamp-based ordering rule and
   avoid flakiness from same-millisecond collisions.
4. Run the direct suite and named gate below.
5. Update the matrix row, breakdown ledger/notes, and
   `09-network-group-messaging.md` only after the landed proof passes.

### risks and edge cases

- Keep the proof tied to the current chronological ordering rule, not a stronger
  strict-order contract the repo does not claim.
- Avoid concurrent same-millisecond sends because the in-memory test seam uses
  timestamp-based ordering and millisecond-derived outgoing ids.

### exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart`
- Named gates:
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`

### known-failure interpretation

- If the new regression fails, treat that as in-scope evidence that the repo
  does not yet uphold even its documented chronological ordering rule.
- If the `groups` gate exposes unrelated failures, keep them separate unless
  they touch live message ordering.

### done criteria

- The new regression proves both recipients display same-sender `M1` before
  `M2`.
- The direct suite above passes.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passes.
- `GM-006` is updated in the source matrix and breakdown with concrete
  file-and-test evidence, and `09-network-group-messaging.md` no longer treats
  ordering as only partially proven for this row.

### scope guard

- Do not widen into partition-heal behavior; that remains `GM-016`.
- Do not widen into remove-vs-send ordering; that remains `MR-015` and
  `SC-012`.
- Do not change runtime ordering logic unless the new proof disproves the
  current behavior.

### accepted differences / intentionally out of scope

- The repo still does not claim a strict total-order guarantee across arbitrary
  concurrent senders.
- Notification, deep-link, and reconnect boundary behavior remain outside this
  session.

### dependency impact

- `GM-006` can close independently once the same-sender ordering regression
  lands.
- `CLOSURE-001` depends on this row being truthfully updated after execution.
