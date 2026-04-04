# Session RJ-002 Plan - Non-admin cannot re-invite

## Final verdict

`acceptance-only`

Current repo evidence already showed that re-invite uses the same admin-gated
add-member permission seam as a first-time add, so the safest session was to
verify that shared rejection proof and close the row without code changes.

## Final plan

### real scope

- Resolve source row `RJ-002` only: `Non-admin cannot re-invite`.
- Prefer no production or test edits.
- Reuse the existing add-member permission proof rather than inventing a
  re-invite-specific permission path.
- Update only the row truth in the matrix and breakdown after exact evidence is
  verified.
- Do not widen into UI affordance redesign or invite transport behavior.

### closure bar

- Direct proof exists that non-admin callers are rejected at the shared
  add-member seam used for re-invites.
- The row is not overclaimed beyond that permission contract.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- Verified seam files:
  - `test/features/groups/application/add_group_member_use_case_test.dart`
  - `lib/features/groups/application/add_group_member_use_case.dart`

### session classification

`acceptance-only`

### exact tests and gates to run

- `flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart --plain-name 'rejects when caller is not admin'`

### done criteria

- `RJ-002` is truthfully closed at the shared permission seam.
- No separate re-invite-only behavior is invented.
- The matrix and breakdown can safely move on.
