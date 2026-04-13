# Session RX-002 Plan - Non-destructive reaction inspection

## Final verdict

`implementation-ready`

## Final plan

### real scope

- Resolve source row `RX-002` only: chip inspection must not silently remove or
  replace the viewer's existing reaction.
- Keep mutation explicit through long-press reaction bars and full pickers.

### closure bar

- Inline chip taps open inspection, not mutation.
- Existing mutation paths remain explicit and separate.
- Stored reactions stay unchanged after first-tap inspection.
- Required direct tests pass.

### source of truth

- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/feed/presentation/screens/feed_screen.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`

### exact tests and gates to run

- `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'group reaction chips open participant inspection without mutating stored reactions'`
