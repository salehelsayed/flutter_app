# Session MR-010 Plan - Removed member loses receive permission

## Final verdict

`acceptance-only`

Current repo evidence already appears to prove the row-owned contract:

- `test/features/groups/integration/group_membership_smoke_test.dart`
  includes `admin removes member — removed member stops receiving messages`,
  which proves the removed member keeps only pre-removal incoming traffic while
  remaining members continue to receive post-removal messages.

The safest session is therefore to verify that direct smoke proof on the
current repo state and close the row with evidence only.

## Final plan

### real scope

- Resolve source row `MR-010` only: `Removed member loses receive permission`.
- Prefer no production or test edits.
- Update only:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md` and
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  after exact evidence is verified.
- Do not widen into send blocking, removed-state notice, or offline removal.

### closure bar

- There is direct automated proof that the removed member receives no
  post-removal group message.
- There is direct automated proof that remaining members continue to receive
  the post-removal traffic.
- The direct test below passes on the current repo state.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- Verified seam files:
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/shared/fakes/group_test_user.dart`

### session classification

`acceptance-only`

### exact tests and gates to run

- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart`

### done criteria

- `MR-010` has exact row-owned evidence for post-removal receive blocking.
- No broader remove-state or offline behavior is reopened.
- The matrix and breakdown can truthfully mark the row resolved.
