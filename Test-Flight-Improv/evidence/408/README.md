# Plan 408 evidence — killed-app missed-call card (2026-09-05)

Plan 406 gave the killed-app path its history row but no notification. That is
the case where a card matters most: there is no open app in which to notice the
call, so without one the user's only signal was a ring that appeared and
vanished.

| File | What it proves |
|---|---|
| `dart_headless_card_green_2026-09-05.txt` | GREEN: 1417 passing, 0 failing across the call, bootstrap and notification suites |

## What was built

- `HeadlessMissedCallNotification` (`lib/core/notifications/`) initialises its
  own plugin in the background isolate, as `background_message_handler.dart`
  does: a background `FlutterEngine` has its own module globals, so the
  foreground plugin's initialization and channels do not exist there.
  TC-408-01..05: initialises once rather than per call, creates EVERY channel
  (one never created posts nothing at all on Android 8+), publishes on the
  calls channel under the same `call:`-namespaced id as the foreground path so
  the two converge instead of stacking, and never throws on a platform failure.
- `recordHeadlessTerminalCall` (`lib/features/call/application/`) turns one
  terminal call into the row and the card. TC-408-10..14.

## The two decisions worth keeping

**The card is awaited.** The headless isolate tears down as soon as its session
finishes, so a fire-and-forget post would race that teardown (TC-408-12 pins
this: the returned future must not complete before the post does).

**A replay posts no second card.** The projection is idempotent, but telling
the user twice is not; the repository is read BEFORE projecting so `inserted`
is truthful (TC-408-11).

Also pinned: a failing card never loses the row (TC-408-13), and a terminate
whose clock predates its invite still constructs, because `CallHistoryEntry`
refuses a non-monotonic pair (TC-408-14).

## Harness note

The mocked plugin first returned `null` where `initialize` expects a `bool`,
which threw inside the plugin rather than exercising the code under test. The
mock was fixed, not the production path — the same trap the existing
`local_notification_support_test.dart` documents for `getNotificationChannels`.
