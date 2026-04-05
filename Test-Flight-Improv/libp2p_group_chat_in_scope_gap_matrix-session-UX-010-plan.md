# Session UX-010 Plan - Member list consistency after reconnect

## Final verdict

`implementation-ready`

Current repo evidence shows `UX-010` is a bounded reconnect-proof gap:

- Existing membership tests already prove live member-list convergence on add
  and remove.
- Existing recovery tests already prove topic rejoin and inbox drain restore
  missed traffic on reconnect.
- What remains missing is one row-owned regression that combines membership
  churn while a peer is offline, then proves reconnect plus inbox drain brings
  that peer to the same final member/admin list and metadata as the peers that
  stayed current.

## Final plan

### real scope

- Close source row `UX-010` only: add one recovery regression that compares the
  final converged group state across peers after offline membership churn.
- Keep the change bounded to:
  - `test/features/groups/integration/group_resume_recovery_test.dart`
- Update only the row-owned closure docs named by the breakdown after proof
  lands:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`

### closure bar

- One peer misses at least two membership changes while offline.
- Reconnect uses the existing rejoin-plus-inbox-drain recovery path.
- After recovery, the offline peer's member/admin list and core metadata match
  the peers that stayed current.
- Direct proof passes and the named `groups` gate passes.
- `UX-010` is updated to `Closed` or `Covered` only after docs cite the landed
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

- The repo already handles the pieces, but the matrix still lacks one direct
  reconnect-after-membership-churn comparison across peers.
- This row should lock the current convergence behavior in place, not redesign
  recovery sequencing.

### regression/tests to add first

- Add one integration regression in
  `test/features/groups/integration/group_resume_recovery_test.dart` that:
  - takes one member offline
  - applies removal plus add churn while that member is away
  - replays the missed membership system events through inbox drain on
    reconnect
  - compares the final member list, roles, and key metadata across peers

### step-by-step implementation plan

1. Preserve unrelated local edits and keep the scope on reconnect convergence
   proof only.
2. Add the combined churn-and-reconnect regression to
   `test/features/groups/integration/group_resume_recovery_test.dart`.
3. Reuse the existing `rejoinGroupTopics(...)` and
   `drainGroupOfflineInbox(...)` seams instead of widening into production
   changes.
4. Run the direct suite and named gate below.
5. Update the matrix row, breakdown ledger/notes, and
   `14-regression-test-strategy.md` only after the proof passes.

### risks and edge cases

- Keep the replay envelopes faithful to the existing `member_removed` and
  `member_added` wire shape.
- Compare final state across peers, not just the recovered peer in isolation.
- Avoid widening into admin-role mutation flows unless needed to keep the
  metadata comparison honest.

### exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart`
- Named gates:
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`

### known-failure interpretation

- If the recovered peer still has stale members or roles, the row remains open.
- If reconnect resumes live delivery but misses the prior membership churn, the
  row remains open.
- If the peers disagree on final metadata after recovery, the row remains open.

### done criteria

- One exact regression proves reconnect-after-membership-churn convergence
  across peers.
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart`
  passes.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passes.
- `UX-010` is updated in the source matrix and breakdown with concrete
  file-and-test evidence, and the regression strategy doc records the new
  convergence lock.

### scope guard

- Do not change production recovery or membership code unless the new
  regression exposes a real defect.
- Do not widen into large-message/attachment behavior; that belongs to `UX-007`.
- Do not add separate UI-only member-list tests if the recovery integration
  regression already closes the row.

### accepted differences / intentionally out of scope

- Transport-level failover and multi-device permutations remain out of scope.
- Removal of the offline peer itself remains covered by other rows and is not
  the focus here.

### dependency impact

- `UX-010` can close independently once the reconnect-convergence regression
  lands.
- `CLOSURE-001` depends on this row being truthfully updated after execution.
