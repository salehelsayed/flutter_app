# Session MR-022 Plan - Member can leave group

## Final verdict

`acceptance-only`

Current repo evidence already appears to prove the row-owned contract:

- `test/features/groups/integration/group_edge_cases_smoke_test.dart`
  includes `leave group voluntarily — user stops receiving`, which proves the
  leaving member no longer receives post-leave traffic while remaining members
  continue normally
- `test/features/groups/application/leave_group_use_case_test.dart` proves
  leave cleans up the group, members, and keys locally

The safest session is therefore to verify those direct seams on the current
repo state and close the row with evidence only.

## Final plan

### real scope

- Resolve source row `MR-022` only: `Member can leave group`.
- Prefer no production or test edits.
- Update only:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md` and
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  after exact evidence is verified.
- Do not widen into admin leave flow or last-admin protection.

### closure bar

- There is direct automated proof that a non-admin member can leave.
- There is direct automated proof that the member stops receiving later group
  messages.
- There is direct automated proof that local group/member/key data are cleaned
  up on leave.
- The direct tests below pass on the current repo state.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- Verified seam files:
  - `test/features/groups/integration/group_edge_cases_smoke_test.dart`
  - `test/features/groups/application/leave_group_use_case_test.dart`
  - `lib/features/groups/application/leave_group_use_case.dart`

### session classification

`acceptance-only`

### exact tests and gates to run

- `flutter test --no-pub test/features/groups/integration/group_edge_cases_smoke_test.dart --plain-name 'leave group voluntarily — user stops receiving'`
- `flutter test --no-pub test/features/groups/application/leave_group_use_case_test.dart`

### done criteria

- `MR-022` has exact row-owned leave-group evidence.
- No broader admin-leave or transfer behavior is reopened.
- The matrix and breakdown can truthfully mark the row resolved.
