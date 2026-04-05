# Session SC-005 Plan - Group key/epoch updates correctly on re-invite

## Final verdict

`implementation-ready`

Current repo evidence shows `SC-005` is a proof gap, not a broad behavior gap:

- `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  classifies `SC-005` as `implementation-ready` with `tests only` ownership.
- `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md` already says a
  rejoined member can resume on epoch `2`, but the current smoke proof seeds
  the fresh key manually instead of proving the remove->reinvite path end to
  end.
- `test/features/groups/integration/invite_round_trip_test.dart` already covers
  the real `sendGroupInvite(...)` and `handleIncomingGroupInvite(...)` flow, so
  it is the tightest home for the missing deterministic proof.
- `test/features/groups/application/member_removal_integration_test.dart` now
  proves removal rotates to epoch `2`, which gives this row an execution-safe
  base to build on.

The smallest safe session is therefore to add one deterministic remove->rotate
->reinvite regression using the real invite send/handle flow, verify the
rejoined member adopts the rotated epoch for its first send, and then update
the row-owned docs truthfully.

## Final plan

### real scope

- Close source row `SC-005` only: prove that a removed member who is re-invited
  receives the current rotated key/epoch rather than stale removed
  credentials.
- Keep the implementation test-only unless current code disproves the matrix
  note.
- Preferred direct test home:
  - `test/features/groups/integration/invite_round_trip_test.dart`
- Update only the row-owned closure docs named by the breakdown after the proof
  lands:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`

### closure bar

- The repo has one direct deterministic regression that:
  - removes a member
  - rotates the group key to a new epoch
  - re-invites that member using the real invite send/handle path
  - proves the rejoined member persists the rotated epoch/key
  - proves the rejoined member’s first subsequent send uses the rotated epoch
- No transport/startup changes are introduced.
- Direct proof passes, and the named `groups` gate passes.
- `SC-005` is updated to `Closed` or `Covered` only after the row docs cite the
  landed test evidence.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Current code/tests win over stale prose when they disagree.
- Verified seam files:
  - `lib/features/groups/application/send_group_invite_use_case.dart`
  - `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `test/features/groups/integration/invite_round_trip_test.dart`
  - `test/features/groups/application/member_removal_integration_test.dart`

### session classification

`implementation-ready`

### exact problem statement

- The repo already proves rejoined members can operate on a newer epoch, but
  the existing smoke proof injects the fresh key manually.
- The missing proof is narrower: a deterministic remove->reinvite flow using
  the current invite send/handle contract must show that the rejoined member
  adopts the rotated key/epoch from the invite itself.
- This session should not widen into startup/rejoin recovery or stale-event
  ordering work.

### regression/tests to add first

- Add one deterministic integration regression in
  `test/features/groups/integration/invite_round_trip_test.dart` proving:
  - removal rotates the group key from epoch `1` to epoch `2`
  - the reinvite payload uses epoch `2`
  - `handleIncomingGroupInvite(...)` persists epoch `2`
  - the rejoined member’s first subsequent `sendGroupMessage(...)` uses epoch
    `2`

### step-by-step implementation plan

1. Preserve unrelated local edits and keep the change test-only unless existing
   behavior disproves the matrix note.
2. Add the deterministic remove->rotate->reinvite regression in
   `test/features/groups/integration/invite_round_trip_test.dart`.
3. Reuse the existing invite round-trip harness, fake P2P service, and
   in-memory repositories instead of inventing a new harness.
4. Run the direct suite and named gate below.
5. Update the matrix row, breakdown ledger/notes, and
   `09-network-group-messaging.md` only after the landed proof passes.

### risks and edge cases

- Do not overclaim broader stale-state convergence; this row is about the
  rotated key/epoch on re-invite, not all reconnect behavior.
- The proof must avoid manually seeding the rejoined member’s fresh key outside
  the real invite handling path.
- Avoid changing production code unless the existing repo behavior contradicts
  the row note.

### exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart`
- Named gates:
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`

### known-failure interpretation

- There is no accepted difference that allows rejoined members to keep using a
  stale removed-era key after the current invite flow completes.
- If the new deterministic regression fails, treat that as in-scope.
- If the `groups` gate exposes unrelated pre-existing failures, keep them
  separate unless they touch the remove / rotate / re-invite seam.

### done criteria

- The new deterministic regression proves the rejoined member adopts and uses
  the rotated epoch through the real invite send/handle path.
- The direct suite above passes.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passes.
- `SC-005` is updated in the source matrix and breakdown with concrete
  file-and-test evidence, and `09-network-group-messaging.md` no longer treats
  this row as only partially proven.

### scope guard

- Do not change startup, resume, or rejoin-topic orchestration in this session.
- Do not widen into offline bystander membership replay; that remains `MR-024`
  / `SC-007`.
- Do not broaden into transport/authentication changes.

### accepted differences / intentionally out of scope

- Reconnect ordering and broader stale-client convergence still belong to later
  rows.
- The proof may stay at fake-P2P / repo-local integration level without adding
  device-bound transport coverage.

### dependency impact

- `SC-005` can close independently once the deterministic invite proof lands.
- `CLOSURE-001` depends on this row being truthfully updated after execution.
