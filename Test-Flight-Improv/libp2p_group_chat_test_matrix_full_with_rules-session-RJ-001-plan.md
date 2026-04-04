# Session RJ-001 Plan - Admin can re-invite removed member

## Final verdict

`implementation-ready`

Current repo facts already owned the add-member plus invite-bootstrap seam, but
they did not yet leave one row-owned proof that the same removed identity can
be added back and resume current group use.

The safest session was therefore to add one narrow removed-then-rejoin smoke
regression and close the row against the existing invite/bootstrap contracts.

## Final plan

### real scope

- Resolve source row `RJ-001` only: `Admin can re-invite removed member`.
- Limit new regression work to
  `test/features/groups/integration/group_membership_smoke_test.dart`.
- Reuse existing invite-bootstrap proofs in
  `test/features/groups/presentation/contact_picker_wired_test.dart` and
  `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`.
- Update only the row truth in the matrix and breakdown after exact evidence is
  verified.
- Do not widen into offline re-invite, notification resume, or admin-transfer
  scope.

### closure bar

- Direct proof exists that a removed member can be added back to the same group.
- Direct proof exists that the re-invite path still carries the latest key
  material.
- Direct proof exists that invite bootstrap persists fresh group state.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- Verified seam files:
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/features/groups/presentation/contact_picker_wired_test.dart`
  - `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`

### session classification

`implementation-ready`

### exact tests and gates to run

- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'removed member can be re-added with current state and resumes send/receive'`
- `flutter test --no-pub test/features/groups/presentation/contact_picker_wired_test.dart --plain-name 'confirming invite sends groupKey and keyEpoch from latest key'`
- `flutter test --no-pub test/features/groups/application/handle_incoming_group_invite_use_case_test.dart --plain-name 'persists group, members, and key for a valid invite payload'`

### done criteria

- `RJ-001` has exact row-owned re-invite proof.
- The row is closed on the existing add-member plus invite-bootstrap contract.
- The matrix and breakdown can truthfully mark the row resolved.
