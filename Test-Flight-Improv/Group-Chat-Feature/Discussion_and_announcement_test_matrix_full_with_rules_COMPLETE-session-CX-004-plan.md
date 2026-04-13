# Session CX-004 Plan - Honest hidden edit/delete actions

## Final verdict

`implementation-ready`

## Final plan

### real scope

- Resolve source row `CX-004` only: unsupported group edit/delete actions stay
  hidden while the rest of the context surface still opens.
- Do not invent group edit/delete support.

### closure bar

- Long-press still opens the group context surface.
- Reply/copy/inspection remain available where supported.
- Edit/delete are absent from the group surface.
- Required direct tests pass.

### source of truth

- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`

### exact tests and gates to run

- `flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart`

