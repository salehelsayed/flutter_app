# Session CX-002 Plan - Group long-press reply path

## Final verdict

`implementation-ready`

## Final plan

### real scope

- Resolve source row `CX-002` only: group long-press reply should enter the
  existing quote-reply path for supported messages.
- Reuse the shared context overlay instead of adding a second reply entry
  model for groups.

### closure bar

- Long-press on a supported group row exposes a reply action.
- Tapping reply calls the existing group quote-reply callback with the correct
  message id.
- Required direct tests pass.

### source of truth

- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`

### exact tests and gates to run

- `flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart`

