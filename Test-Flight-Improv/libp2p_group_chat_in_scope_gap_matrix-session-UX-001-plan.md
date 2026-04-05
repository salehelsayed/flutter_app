# Session UX-001 Plan - New member history policy

## Final verdict

`implementation-ready`

Current repo evidence shows `UX-001` is a bounded policy-proof gap:

- Existing coverage already shows late joiners do not receive earlier live
  messages automatically.
- Existing invite and replay flows already show a newly added member can be
  bootstrapped and then receive allowed later traffic.
- What remains missing is one row-owned regression that pins the product policy
  explicitly: invite bootstrap does not preload pre-join history, while
  post-join replay still lands.

## Final plan

### real scope

- Close source row `UX-001` only: add one direct regression that proves the
  repo's current policy is future-only history from membership time, plus
  allowed post-join replay.
- Keep the change bounded to:
  - `test/features/groups/integration/invite_round_trip_test.dart`
- Update only the row-owned closure docs named by the breakdown after proof
  lands:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`

### closure bar

- A concrete pre-join group message exists before the new member is invited.
- Handling the invite persists the group, members, and key, but does not
  preload that pre-join history for the new member.
- A post-join replay envelope is accepted after invite bootstrap.
- The new member's visible history contains the post-join replay only, not the
  earlier pre-join message.
- Direct proof passes and the named `groups` gate passes.
- `UX-001` is updated to `Closed` or `Covered` only after docs cite the landed
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

- The repo behavior reads as future-only from membership time, but the matrix
  still lacks one row-owned test that says so explicitly.
- This row does not need a new history product decision or migration; it needs
  a permanent regression that locks the current policy in place.

### regression/tests to add first

- Add one integration regression in
  `test/features/groups/integration/invite_round_trip_test.dart` that:
  - creates real pre-join history on the admin side
  - bootstraps a new member via invite
  - proves the invite loads no pre-join messages
  - proves a later replayed post-join message is still accepted

### step-by-step implementation plan

1. Preserve unrelated local edits and keep the scope on history-policy proof
   only.
2. Add the direct future-only history regression to
   `test/features/groups/integration/invite_round_trip_test.dart`.
3. Reuse the existing invite/bootstrap and replay paths instead of widening
   into new production code.
4. Run the direct suite and named gate below.
5. Update the matrix row, breakdown ledger/notes, and
   `14-regression-test-strategy.md` only after the proof passes.

### risks and edge cases

- Do not widen into a broader "full history sync" or alternative product
  policy. The row closes on the current future-only contract.
- Keep the proof explicit about replay timing: post-join replay is allowed,
  pre-join history is not silently backfilled.
- Avoid reopening unrelated invite, resume, or notification behavior.

### exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart`
- Named gates:
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`

### known-failure interpretation

- If invite bootstrap now backfills pre-join history, the row regresses the
  current product policy.
- If post-join replay is rejected after invite bootstrap, the row remains open.
- If the direct regression cannot distinguish pre-join and post-join history,
  the row is still underspecified.

### done criteria

- One exact regression pins future-only history plus allowed post-join replay.
- `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart`
  passes.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passes.
- `UX-001` is updated in the source matrix and breakdown with concrete
  file-and-test evidence, and the regression strategy doc records the new
  policy-locking regression.

### scope guard

- Do not change production history policy in this row.
- Do not widen into unread counting, bidi rendering, or reconnect convergence;
  those belong to later UX rows.
- Do not redesign inbox replay semantics unless the new regression exposes a
  real defect.

### accepted differences / intentionally out of scope

- Alternative history products such as full-history or limited-backfill remain
  out of scope.
- Real device transport coverage remains out of scope because the current
  deterministic integration path is enough to pin the policy.

### dependency impact

- `UX-001` can close independently once the history-policy regression lands.
- `CLOSURE-001` depends on this row being truthfully updated after execution.
