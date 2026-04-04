# Session MR-011 Plan - Removed member loses notifications

## Final verdict

`acceptance-only`

Current repo evidence already appears to prove the row-owned contract:

- `test/features/groups/application/group_message_listener_test.dart`
  includes `does not notify after self-removal deletes the group`, which
  proves self-removal triggers local cleanup and suppresses later
  notifications for that group.

The safest session is therefore to verify that direct application-level proof
on the current repo state and close the row with evidence only.

## Final plan

### real scope

- Resolve source row `MR-011` only: `Removed member loses notifications`.
- Prefer no production or test edits beyond the narrow row-owned proof that is
  already landed.
- Update only:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md` and
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  after exact evidence is verified.
- Do not widen into mute behavior, visible removed-state notice, or route
  navigation.

### closure bar

- There is direct automated proof that self-removal deletes local group state.
- There is direct automated proof that later incoming traffic for that group
  does not produce a notification.
- The direct test below passes on the current repo state.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- Verified seam files:
  - `test/features/groups/application/group_message_listener_test.dart`
  - `lib/features/groups/application/group_message_listener.dart`

### session classification

`acceptance-only`

### exact tests and gates to run

- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'does not notify after self-removal deletes the group'`

### done criteria

- `MR-011` has exact row-owned evidence for post-removal notification
  suppression.
- No broader mute or route-UX behavior is reopened.
- The matrix and breakdown can truthfully mark the row resolved.
