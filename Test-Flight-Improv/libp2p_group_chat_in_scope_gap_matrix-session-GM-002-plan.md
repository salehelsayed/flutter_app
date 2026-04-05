# Session GM-002 Plan - Create/add with offline member bootstrap

## Final verdict

`implementation-ready`

Current repo evidence shows `GM-002` is a proof gap, not a broad runtime gap:

- `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  classifies `GM-002` as `implementation-ready` with `tests only` ownership.
- The repo already proves offline invite fallback, invite bootstrap
  persistence, offline inbox drain after join, and post-bootstrap
  participation, but those proofs live in separate tests.
- The missing row-owned proof is one combined offline-add-then-reconnect path
  showing the invite/bootstrap lands on reconnect and the newly joined member
  can immediately participate according to current product rules.

The smallest safe session is therefore to add one combined reconnect bootstrap
regression, verify the existing `groups` gate still passes, and then update the
row-owned docs truthfully.

## Final plan

### real scope

- Close source row `GM-002` only: prove a user added while offline can
  reconnect, accept/bootstrap from the invite path, drain missed inbox traffic,
  and then send successfully.
- Keep the implementation test-only unless the direct regression disproves the
  current invite/bootstrap path.
- Preferred direct test home:
  - `test/features/groups/application/group_invite_listener_test.dart`
- Update only the row-owned closure docs named by the breakdown after the proof
  lands:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`

### closure bar

- The repo has one direct regression that:
  - processes an invite on reconnect
  - drains missed inbox messages for that group
  - proves the joined member can immediately send after bootstrap
- No production code change is needed unless the regression fails.
- Direct proof passes, and the named `groups` gate passes.
- `GM-002` is updated to `Closed` or `Covered` only after the row docs cite the
  landed evidence.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Current code/tests win over stale prose when they disagree.
- Verified seam files:
  - `lib/features/groups/application/group_invite_listener.dart`
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `test/features/groups/application/group_invite_listener_test.dart`

### session classification

`implementation-ready`

### exact problem statement

- The repo already has the behavior pieces needed for offline-add bootstrap.
- The open gap is narrower: there is still no single row-owned reconnect test
  that proves those pieces work together in sequence for the newly added member.
- This session should not widen into bootstrap gating, reconnect transport
  policy, or later ordering rows.

### regression/tests to add first

- Add one direct reconnect bootstrap regression in
  `test/features/groups/application/group_invite_listener_test.dart` proving an
  offline-added member can reconnect, drain missed inbox state, and then send.

### step-by-step implementation plan

1. Preserve unrelated local edits and keep the session test-only unless the new
   combined proof disproves current behavior.
2. Add the reconnect bootstrap regression in
   `test/features/groups/application/group_invite_listener_test.dart`.
3. Reuse the existing invite listener harness, cursor inbox bridge, and
   in-memory repositories instead of inventing a new fake network seam.
4. Run the direct suite and named gate below.
5. Update the matrix row, breakdown ledger/notes, and
   `09-network-group-messaging.md` only after the landed proof passes.

### risks and edge cases

- Keep the proof tied to reconnect bootstrap of an offline-added member.
- Do not widen into “cannot send before bootstrap completes”; that remains
  `MR-003`.

### exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/features/groups/application/group_invite_listener_test.dart`
- Named gates:
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`

### known-failure interpretation

- If the combined reconnect regression fails, treat that as in-scope evidence
  the repo still has a real bootstrap participation gap.
- If the `groups` gate exposes unrelated failures, keep them separate unless
  they touch invite/bootstrap participation.

### done criteria

- The new reconnect bootstrap regression proves invite acceptance, inbox drain,
  and successful post-bootstrap participation in one row-owned flow.
- The direct suite above passes.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passes.
- `GM-002` is updated in the source matrix and breakdown with concrete
  file-and-test evidence, and `09-network-group-messaging.md` no longer treats
  the row as only partially proven.

### scope guard

- Do not widen into send-before-bootstrap rejection; that remains `MR-003`.
- Do not widen into reconnect ordering or partition-heal behavior; that belongs
  to `GM-016`.
- Do not change runtime invite/bootstrap logic unless the combined regression
  disproves current behavior.

### accepted differences / intentionally out of scope

- Later reconnect churn beyond initial bootstrap remains covered by other rows.
- Deep-link or notification behavior remains outside this session.

### dependency impact

- `GM-002` can close independently once the reconnect bootstrap regression
  lands.
- `CLOSURE-001` depends on this row being truthfully updated after execution.
