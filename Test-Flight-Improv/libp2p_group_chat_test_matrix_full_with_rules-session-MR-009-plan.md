# Session MR-009 Plan - Removed member loses send permission

## Final verdict

`acceptance-only`

Current repo evidence already appears to prove the row-owned contract:

- `test/features/groups/integration/group_membership_smoke_test.dart`
  includes `removed member cannot send after self-removal cleanup`, which
  proves the removed member's bridge-backed send returns `groupNotFound`,
  persists no outgoing row, and reaches no remaining member.

The safest session is therefore to verify that direct smoke proof on the
current repo state and close the row with evidence only.

## Final plan

### real scope

- Resolve source row `MR-009` only: `Removed member loses send permission`.
- Prefer no production or test edits beyond the narrow row-owned proof that is
  already landed.
- Update only:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md` and
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  after exact evidence is verified.
- Do not widen into removed-state notice, receive blocking, or typing-race
  coverage.

### closure bar

- There is direct automated proof that a removed member cannot successfully
  send through the real bridge-backed path.
- There is direct automated proof that no remaining member receives the
  rejected message.
- The direct test below passes on the current repo state.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- Verified seam files:
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/shared/fakes/group_test_user.dart`
  - `lib/features/groups/application/send_group_message_use_case.dart`

### session classification

`acceptance-only`

### exact tests and gates to run

- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart`

### done criteria

- `MR-009` has exact row-owned evidence for post-removal send rejection.
- No broader removed-state or race behavior is reopened.
- The matrix and breakdown can truthfully mark the row resolved.
