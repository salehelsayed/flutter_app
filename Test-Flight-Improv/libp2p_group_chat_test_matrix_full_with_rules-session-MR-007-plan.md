# Session MR-007 Plan - Remove member confirmation

## Final verdict

`implementation-ready`

Current repo facts showed row `MR-007` was a real product gap:

- the group-info remove flow called straight into member removal without any
  confirmation step
- the existing widget tests proved the remove action worked, but not that the
  UI warned about the consequence or required an explicit confirm before state
  changed

The smallest safe session was therefore to add a narrow confirm/cancel dialog
to the existing group-info remove flow and tighten the widget tests around it.

## Final plan

### real scope

- Resolve source row `MR-007` only: `Remove member confirmation`.
- Limit production edits to
  `lib/features/groups/presentation/screens/group_info_wired.dart`.
- Limit regression edits to
  `test/features/groups/presentation/group_info_wired_test.dart`.
- Reuse the existing remove-member wiring after confirmation instead of
  redesigning the membership UI.
- Update only the row truth in
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md` and
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  after exact evidence is verified.
- Do not widen into removed-state notice, last-admin protection, or promotion
  work.

### closure bar

- Tapping remove opens an explicit confirmation dialog before any bridge or
  repo mutation happens.
- The dialog copy clearly states the member will stop receiving new messages.
- Confirming the dialog preserves the existing successful remove flow.
- The direct widget tests below pass.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
- Current code and tests beat stale prose when they disagree.
- Verified seam files:
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
  - `test/features/groups/presentation/group_info_wired_test.dart`

### session classification

`implementation-ready`

### exact problem statement

- The row requires a user-visible confirmation step before a member is removed.
- The repo-owned product surface lacked that confirmation entirely, so the row
  could not be truthfully classified as already covered.

### files and repos to inspect next

- Primary product seam:
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Primary regression target:
  - `test/features/groups/presentation/group_info_wired_test.dart`

### existing tests covering this area

- The widget suite already proved remove success, broadcast, key rotation, and
  ordering once removal starts.
- Missing before this session:
  - explicit confirmation dialog copy
  - proof that removal only proceeds after confirm

### regression/tests to add first

- Add the narrowest widget assertions proving:
  - tapping remove opens the confirmation dialog
  - the dialog shows explicit consequence copy
  - confirming the dialog continues into the existing remove flow
- Only if that exposes a real bug, patch the minimal product seam needed to
  satisfy it.

### step-by-step implementation plan

1. Re-read the existing group-info remove flow and widget tests.
2. Wrap the remove action in a confirmation dialog with explicit copy.
3. Update the existing remove-path widget tests to confirm the dialog first.
4. Run the direct tests below.
5. Update the matrix row note and breakdown ledger only after evidence is
   verified.

### risks and edge cases

- Overclaim risk: a visible dialog is not enough unless confirm is required
  before the remove path starts.
- Scope risk: do not redesign the group-info screen or the downstream remove
  mechanics.

### exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart`
- Named gates:
  - none unless a production-code change outside the widget seam is required

### known-failure interpretation

- Treat missing dialog copy, immediate removal before confirmation, or broken
  existing remove behavior after confirmation as current-session blockers.

### done criteria

- `MR-007` has exact row-owned confirmation proof.
- The product delta is limited to the narrow confirmation layer.
- Required direct tests pass.
- The source matrix and breakdown can truthfully mark the row resolved.

### scope guard

- Non-goals:
  - cancel-path row closure bookkeeping for `MR-007B`
  - removed-state notice UX
  - admin-transfer or last-admin logic

### accepted differences / intentionally out of scope

- `MR-007` does not own the cancel no-op row, even though the dialog
  implementation naturally enables it.
- `MR-007` does not claim any protocol-layer authorization work.

### dependency impact

- A truthful `MR-007` resolution should make `MR-007B` evidence-only when that
  later P1 session is reached.
