# Session RJ-010 Plan - Re-invite while removed member is offline

## Final verdict

`implementation-ready`

Current repo evidence shows `RJ-010` is a bounded exact-proof gap:

- The repo already proves re-invites can rotate to a fresh epoch and restore
  current group/key state.
- The repo already proves removed members do not keep receiving removed-period
  traffic and can resume active use after rejoin.
- What remains missing is one row-owned regression that makes the re-add happen
  while the removed member is offline, forces invite delivery onto the inbox
  fallback, and only then processes the invite on later reconnect.

## Final plan

### real scope

- Close source row `RJ-010` only: add the narrowest offline re-invite
  regression proving inbox-fallback delivery during offline state and later
  reconnect bootstrap onto the rotated key.
- Keep the change bounded to:
  - `test/features/groups/integration/invite_round_trip_test.dart`
- Update only the row-owned closure docs named by the breakdown after proof
  lands:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`

### closure bar

- The removed member is offline when the admin re-invites them.
- `sendGroupInvite(...)` falls back to inbox storage instead of direct send.
- The later reconnect path handles that stored invite and restores the group,
  members, and rotated key state.
- The rejoined member can send again on the rotated epoch after reconnect.
- Direct proof passes and the named `groups` gate passes.
- `RJ-010` is updated to `Closed` or `Covered` only after docs cite the landed
  regression.

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

- Existing coverage proves rejoin rotation and allowed post-rejoin access, but
  it does not make the re-add happen while the removed member is offline and
  later reconnecting from invite inbox delivery.
- This row does not require new production logic if the current invite fallback
  and invite-handling path already support the scenario.

### regression/tests to add first

- Add one integration regression in
  `test/features/groups/integration/invite_round_trip_test.dart` that:
  - removes a member and rotates the key
  - forces `sendGroupInvite(...)` onto inbox fallback while that member is
    offline
  - processes the stored invite later
  - proves the rejoined member resumes sending on the rotated epoch

### step-by-step implementation plan

1. Preserve unrelated local edits and keep the scope on offline re-invite proof
   only.
2. Add the exact inbox-fallback re-invite regression to
   `test/features/groups/integration/invite_round_trip_test.dart`.
3. Reuse the existing rotated-epoch assertions instead of widening into new
   product behavior or helper abstractions.
4. Run the direct suite and named gate below.
5. Update the matrix row, breakdown ledger/notes, and
   `11-group-discussion-use-case-audit.md` only after the proof passes.

### risks and edge cases

- Do not widen into runtime recovery, topic rejoin orchestration, or live
  message replay changes; this row is about the invite bootstrap path.
- Keep the test honest about offline delivery by asserting inbox fallback
  happened instead of direct send.
- Avoid reopening `SC-005`; this row consumes the rotated-epoch behavior
  already proven there and only adds the offline re-invite proof.

### exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart`
- Named gates:
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`

### known-failure interpretation

- If the invite still requires direct delivery, the offline re-invite path is
  not proven.
- If the reconnect handler does not restore the rotated key or group config,
  the row remains open.
- If the rejoined member cannot send on the rotated epoch after reconnect, the
  row regresses the practical rejoin contract.

### done criteria

- One exact regression proves offline re-invite via inbox fallback and later
  reconnect bootstrap.
- `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart`
  passes.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passes.
- `RJ-010` is updated in the source matrix and breakdown with concrete
  file-and-test evidence, and the audit doc no longer treats offline re-invite
  proof as missing.

### scope guard

- Do not change production invite, recovery, or listener code unless the new
  regression exposes a real repo bug.
- Do not widen into notification resumption or live add-event presentation;
  those belong to `RJ-005` and `RJ-007`.
- Do not redesign inbox or replay semantics in this row.

### accepted differences / intentionally out of scope

- Broader reconnect UX and loading-state behavior remain outside this row.
- Multi-device or multi-page inbox recovery remains outside this row unless the
  exact offline re-invite regression exposes a concrete defect.

### dependency impact

- `RJ-010` can close independently once the offline re-invite regression lands.
- `CLOSURE-001` depends on this row being truthfully updated after execution.
