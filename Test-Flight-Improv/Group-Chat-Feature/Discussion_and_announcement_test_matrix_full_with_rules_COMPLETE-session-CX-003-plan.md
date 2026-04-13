# Session CX-003 Plan - Group long-press copy action

## Final verdict

`implementation-ready`

## Final plan

### real scope

- Resolve source row `CX-003` only: supported group rows should copy exact text
  from the long-press surface and dismiss cleanly.
- Keep the change local to the group context overlay and copy snackbar path.

### closure bar

- Long-press on a supported group row exposes copy when text is present.
- Copy writes the exact text to the clipboard and dismisses the overlay once.
- Required direct tests pass.

### source of truth

- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`

### exact tests and gates to run

- `flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart`

