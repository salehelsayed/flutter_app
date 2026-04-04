# Session RJ-003 Plan - Re-invited member can send again

## Final verdict

`implementation-ready`

Current repo facts already owned removal and re-add primitives, but the row did
not yet have one direct regression proving that the re-added member can send on
the current group state again.

The smallest safe session was to add one removed-then-rejoin smoke proof and
close the row against that exact send contract.

## Final plan

### real scope

- Resolve source row `RJ-003` only: `Re-invited member can send again`.
- Limit new regression work to
  `test/features/groups/integration/group_membership_smoke_test.dart`.
- Reuse existing add-member and invite-bootstrap contracts instead of adding
  new production behavior.
- Update only the row truth in the matrix and breakdown after exact evidence is
  verified.
- Do not widen into offline rejoin or notification resume scope.

### closure bar

- Direct proof exists that the re-added member sends successfully after
  bootstrap.
- Direct proof exists that the current members receive that post-rejoin send.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- Verified seam files:
  - `test/features/groups/integration/group_membership_smoke_test.dart`

### session classification

`implementation-ready`

### exact tests and gates to run

- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'removed member can be re-added with current state and resumes send/receive'`

### done criteria

- `RJ-003` has exact row-owned post-rejoin send proof.
- The row closes on live usability evidence, not an inferred contract.
- The matrix and breakdown can truthfully mark the row resolved.
