# Session RX-004 Plan - Reaction inspection entry parity

## Final verdict

`implementation-ready`

## Final plan

### real scope

- Resolve source row `RX-004` only: Orbit and Feed entry points must preserve
  the same reaction-inspection contract on the shared group conversation
  surface.

### closure bar

- Orbit entry opens the shared group conversation and preserves reaction
  inspection.
- Feed entry opens the shared group conversation and preserves reaction
  inspection.
- The same participant-inspection surface appears in both routes.
- Required direct tests pass.

### source of truth

- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/features/orbit/presentation/screens/orbit_wired_test.dart`

### exact tests and gates to run

- `flutter test --no-pub test/features/feed/presentation/screens/feed_wired_test.dart --plain-name 'feed entry keeps group reaction inspection aligned with the shared conversation surface'`
- `flutter test --no-pub test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name 'orbit entry keeps group reaction inspection aligned with the shared conversation surface'`
