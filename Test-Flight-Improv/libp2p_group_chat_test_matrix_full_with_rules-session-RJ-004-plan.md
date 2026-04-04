# Session RJ-004 Plan - Re-invited member can receive again

## Final verdict

`implementation-ready`

Current repo facts already covered post-removal receive blocking, but the row
still needed one direct rejoin proof that the same member receives new traffic
again after being added back.

The smallest safe session was to extend the removed-then-rejoin smoke flow and
close the row against that exact post-rejoin receive contract.

## Final plan

### real scope

- Resolve source row `RJ-004` only: `Re-invited member can receive again`.
- Limit new regression work to
  `test/features/groups/integration/group_membership_smoke_test.dart`.
- Reuse the existing add-member and membership-listener contracts instead of
  introducing new production work.
- Update only the row truth in the matrix and breakdown after exact evidence is
  verified.
- Do not widen into history policy or offline rejoin scope.

### closure bar

- Direct proof exists that the re-added member receives new post-rejoin
  traffic.
- The proof is tied to the same removed-then-rejoin flow as the row contract.

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

- `RJ-004` has exact row-owned post-rejoin receive proof.
- No broader rejoin architecture is reopened.
- The matrix and breakdown can truthfully mark the row resolved.
