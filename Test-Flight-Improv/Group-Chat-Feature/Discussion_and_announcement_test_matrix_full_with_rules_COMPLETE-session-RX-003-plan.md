# Session RX-003 Plan - Readable reactor identity

## Final verdict

`implementation-ready`

## Final plan

### real scope

- Resolve source row `RX-003` only: participant inspection must stay readable
  even though stored reactions carry peer IDs rather than usernames.
- Resolve identity from group membership state first and fall back to readable
  peer-id text when a username is unavailable.

### closure bar

- The inspection surface shows `You` for the viewer's reaction.
- Group-member usernames are resolved from membership state.
- Missing usernames fall back to readable truncated peer IDs rather than blank
  or opaque rows.
- Required direct tests pass.

### source of truth

- `lib/features/groups/presentation/widgets/group_reaction_details_sheet.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`

### exact tests and gates to run

- `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'group reaction inspection resolves member usernames and readable peer-id fallback'`
