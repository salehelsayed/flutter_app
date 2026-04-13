# Session CX-005 Plan - Local actions without reactions

## Final verdict

`implementation-ready`

## Final plan

### real scope

- Resolve source row `CX-005` only: local-only long-press actions stay
  available when group reactions are unavailable.
- Cover both pure screen behavior and wired `reactionRepo == null` behavior.

### closure bar

- Group long-press still opens when reactions are unavailable.
- Reply/copy remain available without a reaction bar.
- Required direct tests pass.

### source of truth

- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`

### exact tests and gates to run

- `flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart`
- `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart`

