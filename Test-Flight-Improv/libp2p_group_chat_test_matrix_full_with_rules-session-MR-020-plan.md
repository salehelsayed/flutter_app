# Session MR-020 Plan - At least one admin remains

## Final verdict

`acceptance-only`

Current repo evidence shows this row is still an explicit product gap rather
than already-covered behavior:

- `Test-Flight-Improv/11-group-discussion-use-case-audit.md` explicitly notes
  that groups can become leaderless if the original admin leaves
- `lib/features/groups/application/leave_group_use_case.dart` still leaves the
  group unconditionally, with no last-admin guard
- the current leave-flow tests prove the action succeeds, which confirms the
  missing protection rather than the desired block

The safest session is therefore to close the row truthfully as an open
repo-owned gap instead of overclaiming the existing leave flow as leader-safe.

## Final plan

### real scope

- Resolve source row `MR-020` only: `At least one admin remains`.
- Prefer no production or test edits.
- Update only:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md` and
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  so the row is truthfully classified as still open on the current repo state.
- Do not widen into admin-transfer implementation or leadership reassignment in
  this session.

### closure bar

- The row is not overclaimed as already covered.
- The matrix and breakdown explicitly record that last-admin protection remains
  missing in the current repo-owned contract.
- Supporting direct evidence below is cited honestly.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- Verified seam files:
  - `lib/features/groups/application/leave_group_use_case.dart`
  - `test/features/groups/application/leave_group_use_case_test.dart`
  - `test/features/groups/presentation/group_info_wired_test.dart`

### session classification

`acceptance-only`

### exact tests and gates to run

- `flutter test --no-pub test/features/groups/application/leave_group_use_case_test.dart`
- `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart`

### done criteria

- `MR-020` is truthfully documented as an open last-admin protection gap.
- Existing successful leave behavior is not misrepresented as leader-safe.
- The matrix and breakdown can safely move on.
