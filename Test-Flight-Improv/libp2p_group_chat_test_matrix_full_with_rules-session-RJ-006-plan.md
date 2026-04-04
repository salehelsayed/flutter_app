# Session RJ-006 Plan - Rejoin clears removed state

## Final verdict

`implementation-ready`

Current repo facts suggested this row might need product work, but the current
contract already clears removed state by deleting the group on removal and then
recreating an active group when the user is added back. The missing piece was a
row-owned proof of that surfaced active-state contract.

The safest session was therefore to add one direct removed-then-rejoin smoke
test and pair it with the existing invite-list refresh proof, instead of
inventing a new removed-banner architecture.

## Final plan

### real scope

- Resolve source row `RJ-006` only: `Rejoin clears removed state`.
- Limit new regression work to
  `test/features/groups/integration/group_membership_smoke_test.dart`.
- Reuse existing surfaced-group refresh proof from
  `test/features/groups/presentation/group_list_wired_test.dart`.
- Update only the row truth in the matrix and breakdown after exact evidence is
  verified.
- Do not widen into archived-group UX or persistent removed-banner work.

### closure bar

- Direct proof exists that the previously removed group becomes active again
  after re-add.
- Direct proof exists that live send/receive is restored on the recreated
  group.
- Direct proof exists that the surfaced group list refreshes on joined-group
  events.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- Verified seam files:
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/features/groups/presentation/group_list_wired_test.dart`

### session classification

`implementation-ready`

### exact tests and gates to run

- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'removed member can be re-added with current state and resumes send/receive'`
- `flutter test --no-pub test/features/groups/presentation/group_list_wired_test.dart --plain-name 'refreshes group list when groupInviteListener emits'`

### done criteria

- `RJ-006` is closed against the current recreate-on-reinvite contract.
- The row is not overclaimed as a persistent-banner reset flow.
- The matrix and breakdown can truthfully mark the row resolved.
