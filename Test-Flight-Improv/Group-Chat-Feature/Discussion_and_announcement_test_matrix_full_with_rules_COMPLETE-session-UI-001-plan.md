# Session UI-001 Plan - Single-shell group message rendering

## Final verdict

`implementation-ready`

## Final plan

### real scope

- Resolve source row `UI-001` only: each rendered group message must stay one
  clear bubble without a doubled or stacked-card shell.
- Treat this as proof-first work. If the current row host is already single-shell,
  add direct row-owned regressions instead of inventing new rendering code.

### closure bar

- Base text rows prove one row-local shell.
- Quoted and reaction-bearing rows prove one row-local shell.
- Media rows prove one row-local shell.
- Required direct tests pass.
- The source matrix row can move from `Open` to `Covered` only with concrete
  file-and-test evidence tied to `UI-001`.

### source of truth

- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/conversation/presentation/widgets/letter_card.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`

### exact problem statement

- Earlier whole-screen blur counting was too broad because it included the
  composer backdrop and list virtualization effects.
- The row-owned contract is narrower: each message row must own exactly one
  bubble shell.

### exact tests and gates to run

- `flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart`
