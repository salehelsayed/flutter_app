# Session 03 Plan: Feed Preference Wiring and Settings Return Refresh

# real scope

Wire the saved background preference into Feed only, using the central `AmbientBackground.isFeedSurface` filter from Session 02.

In scope:

- load the stored background preference in `FeedWired`
- pass the current preference to `FeedScreen`
- pass `isFeedSurface: true` from Feed's `AmbientBackground` call
- reload the preference after returning from Settings
- prove stored `cosmic` shows the cosmic Feed background and switching back to default restores the default Feed background

Out of scope:

- cosmic painter changes
- Settings picker changes beyond using the existing route return
- Feed card/message behavior changes
- performance and simulator smoke closure
- applying cosmic to Conversation or other non-Feed routes

# closure bar

This session is done when Feed loads a stored `cosmic` preference, renders the production cosmic background only through the Feed opt-in, refreshes after returning from Settings without app restart, can restore the default preference, and direct Feed/Settings journey tests pass.

# source of truth

- `Test-Flight-Improv/81-feed-cosmic-background-option.md`
- `Test-Flight-Improv/81-feed-cosmic-background-option-session-breakdown.md`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/feed/presentation/screens/feed_screen.dart`
- `lib/features/identity/presentation/widgets/ambient_background.dart`
- `test/features/feed/presentation/screens/feed_screen_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`

Current production code and tests win over stale doc assumptions.

# session classification

`implementation-ready`

# exact problem statement

Settings can now save `cosmic` and `AmbientBackground` can render cosmic for Feed, but Feed does not load or pass the saved preference. Returning from Settings to an already-mounted Feed route still leaves Feed on its previous background until the route rebuilds from some other state.

# files and repos to inspect next

- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/feed/presentation/screens/feed_screen.dart`
- `test/features/feed/presentation/screens/feed_screen_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `integration_test/settings_background_choice_smoke_test.dart` only if the session extends route-journey smoke now

# existing tests covering this area

`feed_screen_test.dart` covers Feed layout, empty/loading states, cards, inline replies, reactions, and navigation behavior. `feed_wired_test.dart` covers broad Feed orchestration. No current Feed test proves a stored background preference changes Feed or refreshes after Settings returns.

# regression/tests to add first

- Extend `feed_screen_test.dart` to prove `BackgroundPreference.cosmic` renders `CosmicBackground` through Feed and default remains default.
- Extend `feed_wired_test.dart` to prove a stored `cosmic` value loads into Feed.
- Add a focused Settings-return journey in `feed_wired_test.dart` if practical: open Settings from the Feed avatar, choose `Cosmic`, pop back, and assert Feed now renders cosmic.

# step-by-step implementation plan

1. Add `backgroundPreference` to `FeedScreen`, defaulting to `BackgroundPreference.defaultBackground`.
2. Pass `backgroundPreference` and `isFeedSurface: true` to Feed's `AmbientBackground`.
3. Import background preference load/model APIs into `FeedWired`.
4. Add `_backgroundPreference` state and `_loadBackgroundPreference()`.
5. Call `_loadBackgroundPreference()` on init and after the Settings route returns.
6. Pass `_backgroundPreference` into `FeedScreen`.
7. Add direct Feed tests and run them.

# risks and edge cases

- Feed should not refresh unrelated messaging state or clear composer/focus while reloading the background preference.
- The Settings return callback already reloads identity and media preferences; adding background reload should remain additive.
- Conversation and other sub-routes still rely on their own `AmbientBackground` calls with the default non-Feed flag.

# exact tests and gates to run

Direct tests:

- `flutter test test/features/feed/presentation/screens/feed_screen_test.dart`
- `flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name "loads stored cosmic background preference into Feed"`
- `flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name "refreshes background preference after returning from Settings"`

Named gates:

- `./scripts/run_test_gates.sh feed` only if the implementation changes Feed card/composer/handoff behavior beyond background preference plumbing.
- No `1to1` gate unless feed-originated send/retry/conversation behavior changes.

# known-failure interpretation

Failures in the added Feed background tests are blocking. Existing broad Feed tests that fail due to unrelated known state should be triaged but not misclassified as background regressions unless the failure touches the files changed here.

# done criteria

- Feed accepts and passes a background preference to `AmbientBackground` with `isFeedSurface: true`.
- `FeedWired` loads the stored preference on init and after Settings returns.
- Direct Feed tests pass.
- The breakdown ledger records Session `03-feed-preference-wiring` outcome.

# scope guard

Do not change Feed message sending, inline reply, reactions, card expansion, Orbit swipe behavior, or conversation routing. Do not run or alter performance/simulator closure here unless a direct regression needs it.

# accepted differences / intentionally out of scope

This session proves the route refresh behavior through a focused widget journey. Full simulator smoke and Feed performance remain Session `04`.

# dependency impact

Session `04-acceptance-performance-closure` depends on this route wiring to run the final Settings-to-Feed smoke and performance/readability acceptance.

# execution result

Verdict: `accepted`

Evidence:

- Added `FeedScreen.backgroundPreference`, defaulting to `defaultBackground`.
- Feed now calls `AmbientBackground` with the stored preference and `isFeedSurface: true`.
- Added `_backgroundPreference` state to `FeedWired`.
- `FeedWired` loads the background preference on init and reloads it after returning from Settings.
- Added `feed_screen_test.dart` coverage for cosmic and default Feed background rendering.
- Added focused `feed_wired_test.dart` coverage for stored cosmic loading and Settings-return refresh.

Verification:

- `flutter test test/features/feed/presentation/screens/feed_screen_test.dart test/features/feed/presentation/screens/feed_wired_test.dart --plain-name "background"`
  - Result: passed on April 28, 2026. This selected the new background preference tests plus the existing group background-task test whose name also matches `background`.
- `flutter test test/features/feed/presentation/screens/feed_screen_test.dart`
  - Result: passed on April 28, 2026.

Closure:

- Session `03-feed-preference-wiring` is accepted.
- No `1to1` gate was required because this session did not change feed-originated send, retry, upload, inbox, or conversation handoff behavior.
