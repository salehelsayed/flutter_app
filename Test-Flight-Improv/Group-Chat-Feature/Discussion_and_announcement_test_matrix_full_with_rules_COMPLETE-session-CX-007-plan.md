# Session CX-007 Plan - Cross-surface group action parity

## Final verdict

`implementation-ready`

## Final plan

### real scope

- Resolve source row `CX-007` only: the same group long-press action contract
  should hold when the conversation is entered from Orbit, Feed, or a
  notification anchor.
- Keep this session test-only unless a route-specific regression appears.

### closure bar

- Orbit entry reaches the shared group conversation surface and exposes the
  same long-press actions.
- Feed entry reaches the shared group conversation surface and exposes the
  same long-press actions.
- Notification-anchor entry keeps the same long-press action surface on the
  highlighted row.
- Required direct tests pass.

### source of truth

- `test/features/orbit/presentation/screens/orbit_wired_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`

### exact tests and gates to run

- `flutter test --no-pub test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name 'orbit entry keeps group long-press actions aligned with the shared conversation surface'`
- `flutter test --no-pub test/features/feed/presentation/screens/feed_wired_test.dart --plain-name 'feed entry keeps group long-press actions aligned with the shared conversation surface'`
- `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'highlights the targeted message context when opened from a notification anchor'`
