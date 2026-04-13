# Session CX-006 Plan - Preserve swipe, reactions, and row rendering

## Final verdict

`implementation-ready`

## Final plan

### real scope

- Resolve source row `CX-006` only: the richer group long-press surface must
  preserve swipe-to-quote, reaction toggles, and the current row-render path.
- Treat this as a regression-proof session, not a feature expansion.

### closure bar

- Swipe-to-quote still wraps supported incoming group rows.
- Long-press reaction selection still routes through the existing reaction
  callback.
- Current row rendering remains intact while the overlay is added.
- Required direct tests pass.

### source of truth

- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`

### exact tests and gates to run

- `flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart`

