# Session RJ-008 Plan - Rejoined member sees current membership and admins

## Final verdict

`implementation-ready`

Current repo facts already owned current-state invite bootstrap, but the row
still lacked one direct regression proving that a rejoined member sees the
latest member/admin set and current key epoch after being added back.

The safest session was to add one removed-then-rejoin smoke proof and reuse the
existing invite-bootstrap persistence test, rather than broadening into new
membership architecture.

## Final plan

### real scope

- Resolve source row `RJ-008` only: `Rejoined member sees current membership and admins`.
- Limit new regression work to
  `test/features/groups/integration/group_membership_smoke_test.dart`.
- Reuse existing invite-bootstrap persistence proof in
  `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`.
- Update only the row truth in the matrix and breakdown after exact evidence is
  verified.
- Do not widen into admin-transfer or metadata-editing scope.

### closure bar

- Direct proof exists that the rejoined member sees the latest member list.
- Direct proof exists that the current admin role assignments are preserved.
- Direct proof exists that the rejoined member has the current key epoch.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- Verified seam files:
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`

### session classification

`implementation-ready`

### exact tests and gates to run

- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'removed member can be re-added with current state and resumes send/receive'`
- `flutter test --no-pub test/features/groups/application/handle_incoming_group_invite_use_case_test.dart --plain-name 'persists group, members, and key for a valid invite payload'`

### done criteria

- `RJ-008` has exact row-owned current-state proof.
- The row closes on direct membership/admin/key assertions.
- The matrix and breakdown can truthfully mark the row resolved.
