# Session SC-004 Plan - Group key/epoch rotates on removal

## Final verdict

`implementation-ready`

Current repo evidence shows `SC-004` is a proof gap, not a broad behavior gap:

- `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  classifies `SC-004` as `implementation-ready` with `tests only` ownership.
- `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md` already says
  the remove flow rotates and distributes a new key, but lacks one exact
  regression proving the first real post-removal send already uses that rotated
  epoch.
- `test/features/groups/application/member_removal_integration_test.dart`
  already proves the bridge command sequence and rotated-key distribution, so it
  is the tightest home for the missing boundary proof.
- `lib/features/groups/application/remove_group_member_use_case.dart`,
  `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`,
  and `lib/features/groups/application/send_group_message_use_case.dart` already
  expose the exact seam needed for a deterministic repo-local regression.

The smallest safe session is therefore to add one deterministic removal-boundary
regression, verify the existing groups gate still passes, and then update the
row-owned docs truthfully.

## Final plan

### real scope

- Close source row `SC-004` only: prove that after a member-removal flow
  rotates the group key, the first subsequent real send uses the rotated epoch.
- Keep the implementation test-only unless current code disproves the matrix
  note.
- Preferred direct test home:
  - `test/features/groups/application/member_removal_integration_test.dart`
- Update only the row-owned closure docs named by the breakdown after the proof
  lands:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`

### closure bar

- The repo has one direct deterministic regression that:
  - removes a member
  - rotates/distributes the next key
  - performs the first subsequent real group send
  - proves the send persists and inbox-stores the rotated epoch rather than the
    pre-removal epoch
- No ordering or transport changes are introduced.
- Direct proof passes, and the named `groups` gate passes.
- `SC-004` is updated to `Closed` or `Covered` only after the row docs cite the
  landed test evidence.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Current code/tests win over stale prose when they disagree.
- Verified seam files:
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `test/features/groups/application/member_removal_integration_test.dart`
  - `test/features/groups/application/send_group_message_use_case_test.dart`

### session classification

`implementation-ready`

### exact problem statement

- The current repo already proves removal triggers key rotation and
  distribution.
- The open gap is narrower: there is not yet one exact row-owned proof that the
  first real post-removal send already uses the rotated epoch.
- This session should not widen into ordering arbitration or transport timing;
  those belong to other rows such as `SC-012`.

### regression/tests to add first

- Add one deterministic regression in
  `test/features/groups/application/member_removal_integration_test.dart`
  proving:
  - an initial epoch exists before removal
  - the removal + rotation path promotes a new epoch
  - the first subsequent `sendGroupMessage(...)` uses the new epoch in the
    saved message and relay-inbox payload

### step-by-step implementation plan

1. Preserve unrelated local edits and keep the change test-only unless existing
   behavior disproves the matrix note.
2. Add the deterministic removal-boundary regression in
   `test/features/groups/application/member_removal_integration_test.dart`.
3. Reuse existing fake bridge helpers and in-memory repositories instead of
   inventing a new harness.
4. Run the direct suites and named gate below.
5. Update the matrix row, breakdown ledger/notes, and
   `09-network-group-messaging.md` only after the landed proof passes.

### risks and edge cases

- Do not overclaim strict ordering semantics; this row is about the rotated
  epoch after removal, not about every possible in-flight interleaving.
- The proof must demonstrate the first real post-removal send, not merely that
  a later send can use a newer key after manual setup.
- Avoid changing production code unless the existing repo behavior contradicts
  the row note.

### exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart`
  - `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart`
- Named gates:
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`

### known-failure interpretation

- There is no accepted difference that allows post-removal traffic to keep
  using the pre-removal epoch once the rotation flow has completed.
- If the new deterministic regression fails, treat that as in-scope.
- If the `groups` gate exposes unrelated pre-existing failures, keep them
  separate unless they touch the removal / rotation / send seam.

### done criteria

- The new deterministic regression proves the first post-removal send uses the
  rotated epoch.
- The direct suites above pass.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passes.
- `SC-004` is updated in the source matrix and breakdown with concrete
  file-and-test evidence, and `09-network-group-messaging.md` no longer treats
  this row as only partially proven.

### scope guard

- Do not change transport, startup, or replay wiring in this session.
- Do not widen into stale-event ordering or removal-vs-send race arbitration.
- Do not broaden into re-invite key rollover work; that remains `SC-005`.

### accepted differences / intentionally out of scope

- Ordering remains best-effort outside the completed removal-then-send proof.
- Richer revocation timing guarantees still belong to later security rows.

### dependency impact

- `SC-004` can close independently.
- `CLOSURE-001` depends on this row being truthfully updated after execution.
