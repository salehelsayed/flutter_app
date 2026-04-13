# Session RX-001 Plan - Group reaction participant inspection

## Final verdict

`implementation-ready`

## Final plan

### real scope

- Resolve source row `RX-001` only: tapping a visible group reaction chip must
  reveal who reacted and with which emoji instead of exposing counts only.
- Use one shared participant-inspection surface across shared group
  conversation entry points.

### closure bar

- Group reaction chips open a readable participant-inspection surface.
- The inspection surface shows participant identity and the tapped emoji.
- Feed and Orbit entry points reach the same inspection contract on the shared
  group conversation surface.
- Required direct tests pass.

### source of truth

- `lib/features/groups/presentation/widgets/group_reaction_details_sheet.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/features/orbit/presentation/screens/orbit_wired_test.dart`

### exact tests and gates to run

- `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'group reaction chips open participant inspection without mutating stored reactions'`
- `flutter test --no-pub test/features/feed/presentation/screens/feed_wired_test.dart --plain-name 'feed entry keeps group reaction inspection aligned with the shared conversation surface'`
- `flutter test --no-pub test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name 'orbit entry keeps group reaction inspection aligned with the shared conversation surface'`
