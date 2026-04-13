# Session RX-005 Plan - Inline Feed reaction coherence

## Final verdict

`implementation-ready`

## Final plan

### real scope

- Resolve source row `RX-005` only: inline Feed group-thread cards must route
  reaction chips through honest inspection behavior without diverging from the
  shared conversation contract.
- Preserve announcement-reader read-only compose semantics while keeping chip
  inspection available.

### closure bar

- Inline discussion cards route reaction chips to inspection.
- Inline announcement-reader cards stay read-only and still route reaction chips
  to inspection.
- Feed-to-conversation entry parity remains covered on the shared group surface.
- Required direct tests pass.

### source of truth

- `lib/features/feed/presentation/screens/feed_screen.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `test/features/feed/presentation/screens/feed_screen_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`

### exact tests and gates to run

- `flutter test --no-pub test/features/feed/presentation/screens/feed_screen_test.dart --plain-name 'inline group reaction chips route through the dedicated inspection callback'`
- `flutter test --no-pub test/features/feed/presentation/screens/feed_screen_test.dart --plain-name 'announcement reader cards keep inline reaction inspection available while compose stays read-only'`
- `flutter test --no-pub test/features/feed/presentation/screens/feed_wired_test.dart --plain-name 'feed entry keeps group reaction inspection aligned with the shared conversation surface'`
