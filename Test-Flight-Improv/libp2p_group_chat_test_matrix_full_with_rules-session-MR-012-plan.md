# Session MR-012 Plan - Removed member is notified

## Final verdict

`implementation-ready`

Current repo facts showed row `MR-012` was a real product gap:

- the removal listener already deleted the group and emitted
  `groupRemovedStream`, but the active conversation surface did not react with
  any explicit notice
- the current UX therefore removed the data without telling the user why the
  conversation disappeared

The smallest safe session was therefore to wire the existing
`groupRemovedStream` into the active group conversation route so the user sees
an explicit notice and is navigated away from the deleted conversation.

## Final plan

### real scope

- Resolve source row `MR-012` only: `Removed member is notified`.
- Limit production edits to
  `lib/features/groups/presentation/screens/group_conversation_wired.dart`.
- Limit regression edits to
  `test/features/groups/presentation/group_conversation_wired_test.dart`.
- Reuse the existing `groupRemovedStream` and current route stack instead of
  inventing a new removed-state architecture.
- Update only the row truth in
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md` and
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  after exact evidence is verified.
- Do not widen into offline removal, last-admin protection, or archived-group
  product work.

### closure bar

- When the open group conversation receives a self-removal event for the
  current group, the user sees explicit removed-state copy.
- The user is navigated out of the deleted conversation so the input is no
  longer usable.
- The direct widget test below passes.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- Verified seam files:
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `test/features/groups/presentation/group_conversation_wired_test.dart`
  - `lib/features/groups/application/group_message_listener.dart`

### session classification

`implementation-ready`

### exact tests and gates to run

- `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'current group removal shows a notice and exits the conversation route'`

### done criteria

- `MR-012` has exact row-owned removed-state notice evidence.
- The product delta is limited to reacting to the existing removal stream.
- The matrix and breakdown can truthfully mark the row resolved.
