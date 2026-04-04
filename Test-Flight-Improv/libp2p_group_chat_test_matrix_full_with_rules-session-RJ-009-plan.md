# Session RJ-009 Plan - Removed-period history is not exposed by default

## Final verdict

`evidence-gated`

Current repo facts suggested this row should close on honest history-policy
evidence rather than on a broad implementation claim. The main question was
whether rejoin restores current state while leaving removed-period traffic
inaccessible by default.

The safest session was to add one direct removed-then-rejoin smoke proof and
classify the row from that evidence.

## Final plan

### real scope

- Resolve source row `RJ-009` only: `Removed-period history is not exposed by default`.
- Limit new regression work to
  `test/features/groups/integration/group_membership_smoke_test.dart`.
- Use the smoke flow to distinguish pre-removal, removed-period, and
  post-rejoin traffic explicitly.
- Update only the row truth in the matrix and breakdown after exact evidence is
  verified.
- Do not widen into a new history-backfill product policy or transport
  redesign.

### closure bar

- Direct proof exists that removed-period traffic is not shown after rejoin.
- The row is classified truthfully against current repo behavior.
- No undocumented backfill policy is invented.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- Verified seam files:
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `lib/features/groups/application/leave_group_use_case.dart`

### session classification

`evidence-gated`

### exact tests and gates to run

- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'removed member can be re-added with current state and resumes send/receive'`

### done criteria

- `RJ-009` is closed from direct repo-owned evidence, not inference alone.
- The row truth explicitly states what history remains visible and what does not.
- The matrix and breakdown can safely move on.
