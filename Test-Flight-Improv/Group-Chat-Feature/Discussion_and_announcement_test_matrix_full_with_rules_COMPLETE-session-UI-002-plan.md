# Session UI-002 Plan - Shell stability through row enrichment

## Final verdict

`implementation-ready`

## Final plan

### real scope

- Resolve source row `UI-002` only: quote, reaction, media, and replay-style
  enrichment must not create a second shell for the same row.
- Keep this session test-only unless the current row host fails the new
  enrichment regressions.

### closure bar

- A base row starts with one row-local shell.
- The same row still has one row-local shell after reaction and media
  enrichment.
- Required direct tests pass.
- The source matrix row can move from `Partial` to `Covered` only with concrete
  file-and-test evidence tied to `UI-002`.

### source of truth

- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/conversation/presentation/widgets/letter_card.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`

### exact problem statement

- Existing update-path tests covered data enrichment and scroll preservation,
  but they did not prove shell stability for the same rendered row.
- This session adds that row-owned shell proof directly.

### exact tests and gates to run

- `flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart`
