# Session SC-011 Plan - Post-removal store-and-forward cut-off

## Final verdict

`implementation-ready`

Current repo evidence shows `SC-011` is a proof gap, not a broad runtime gap:

- `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  classifies `SC-011` as `implementation-ready` with `tests only` ownership.
- `MR-014` already proved replayed self-removal routes through
  `GroupMessageListener` and deletes the local group state during inbox drain.
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  already stops draining a group as soon as replayed system removal deletes the
  group locally.
- The missing row-owned proof is one direct regression showing queued
  post-removal inbox traffic is cut off and never reaches the removed peer.

The smallest safe session is therefore to add one inbox-drain regression on the
post-removal cut-off seam, verify the existing `groups` gate still passes, and
then update the row-owned docs truthfully.

## Final plan

### real scope

- Close source row `SC-011` only: prove that once inbox replay delivers the
  removed peer's `member_removed` system envelope, later queued messages for
  that group are not persisted to the removed peer.
- Keep the implementation test-only unless the direct regression disproves the
  current drain behavior.
- Preferred direct test home:
  - `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- Update only the row-owned closure docs named by the breakdown after the proof
  lands:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`

### closure bar

- The repo has one direct regression that:
  - replays a `member_removed` system envelope for the local peer during inbox
    drain
  - proves the local group is deleted and `group:leave` runs
  - proves later queued messages are not persisted after that removal
  - proves drain does not continue to later cursor pages for the deleted group
- No production code change is needed unless the regression fails.
- Direct proof passes, and the named `groups` gate passes.
- `SC-011` is updated to `Closed` or `Covered` only after the row docs cite
  the landed test evidence.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Current code/tests win over stale prose when they disagree.
- Verified seam files:
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`

### session classification

`implementation-ready`

### exact problem statement

- The repo already replays offline self-removal through the live listener path
  and stops draining once the group is deleted locally.
- The open gap is narrower: there is not yet one row-owned regression proving
  that queued post-removal messages on the relay inbox never reach that removed
  peer after the replayed removal lands.
- This session should not widen into live publish ordering or remove-vs-send
  boundary work; those belong to other rows.

### regression/tests to add first

- Add one direct inbox-drain regression in
  `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  proving replayed self-removal cuts off later queued messages and later cursor
  pages for that group.

### step-by-step implementation plan

1. Preserve unrelated local edits and keep the session test-only unless the
   regression exposes a real behavior gap.
2. Add the post-removal inbox-drain regression in
   `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`.
3. Reuse the existing cursor inbox bridge, listener harness, and in-memory
   repositories instead of inventing a new harness.
4. Run the direct suite and named gate below.
5. Update the matrix row, breakdown ledger/notes, and
   `09-network-group-messaging.md` only after the landed proof passes.

### risks and edge cases

- Keep the proof tied to queued delivery after replayed self-removal; broader
  remove-vs-send ordering remains outside this row.
- Avoid widening into transport or live pubsub fan-out behavior unless the
  direct replay regression disproves current drain semantics.

### exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- Named gates:
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`

### known-failure interpretation

- If the new regression fails, treat that as in-scope evidence that inbox drain
  can still deliver queued post-removal traffic to a removed peer.
- If the `groups` gate exposes unrelated pre-existing failures, keep them
  separate unless they touch the inbox-drain/removal cut-off seam.

### done criteria

- The new regression proves replayed self-removal cuts off later queued
  messages and later cursor pages for that group.
- The direct suite above passes.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passes.
- `SC-011` is updated in the source matrix and breakdown with concrete
  file-and-test evidence, and `09-network-group-messaging.md` no longer treats
  this row as open.

### scope guard

- Do not widen into remove-vs-send ordering; that remains `MR-015` and
  `SC-012`.
- Do not broaden into stale-event rollback or signed-event validation.
- Do not widen into notification behavior; that belongs to `SC-010` and
  `GM-011`.

### accepted differences / intentionally out of scope

- Live post-removal fan-out remains covered by existing integration tests.
- Relay retention policy details remain unchanged in this session.

### dependency impact

- `SC-011` can close independently once the inbox-drain cut-off regression
  lands.
- `CLOSURE-001` depends on this row being truthfully updated after execution.
