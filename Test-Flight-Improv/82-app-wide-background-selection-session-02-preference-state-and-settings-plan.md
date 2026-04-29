# Session 02 Plan: Preference State And Settings

# real scope

Add selected background preference state to the existing app shell controller, publish successful Settings saves through that controller, and let `SettingsScreen` use its current selected preference for the full-screen background. Keep storage strings, localization, semantics, and flow telemetry unchanged.

# closure bar

This session is closed when the app shell has a defaulting `backgroundPreference`, Settings loads storage into both local UI state and the shared shell state, successful Settings selections update the shared state and the Settings full-screen background, failed saves revert honestly, and focused Settings/app-shell tests pass.

# source of truth

- `Test-Flight-Improv/82-app-wide-background-selection.md`
- `Test-Flight-Improv/82-app-wide-background-selection-session-breakdown.md`
- Session 01 plan and landed shared `AmbientBackground` behavior
- Current code/tests beat older Feed-only doc `81` prose.

# session classification

`implementation-ready`

# exact problem statement

Settings already persists `Default` and `Cosmic`, but `SettingsScreen` always renders `AmbientBackground(defaultBackground)`. Feed also keeps its own `_backgroundPreference` state loaded from storage. App-wide behavior needs one in-process selected preference notifier so Settings can update mounted route consumers only after a successful save.

# files and repos to inspect next

- `lib/features/feed/application/app_shell_controller.dart`
- `lib/features/settings/presentation/screens/settings_screen.dart`
- `lib/features/settings/presentation/screens/settings_wired.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `test/features/posts/phase1/app_shell_controller_test.dart`
- `test/features/settings/presentation/screens/settings_screen_test.dart`
- `test/features/settings/presentation/screens/settings_wired_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`

# existing tests covering this area

- Settings widget/wired tests cover picker state, persistence, failure honesty, and flow telemetry.
- Feed wired tests cover stored cosmic load and Settings-return refresh.
- App shell controller tests cover tab switching only.

# regression/tests to add first

- Add app shell controller tests for default background, explicit initial background, and change notifications.
- Add Settings screen coverage that `currentBackgroundPreference: cosmic` renders the cosmic full-screen background.
- Add Settings wired coverage that a successful in-session cosmic selection updates the visible background and shared controller state.
- Keep failed-save coverage proving storage and visible state do not claim cosmic after failure.

# step-by-step implementation plan

1. Extend `AppShellController` with `backgroundPreference`, an optional constructor initial value, and `setBackgroundPreference`.
2. Update `FeedWired` to read the selected preference from `AppShellController` and to publish loaded storage values into the controller.
3. Update `SettingsScreen` to pass `currentBackgroundPreference` to `AmbientBackground`.
4. Update `SettingsWired` to publish loaded and successfully saved preferences into `AppShellController`; do not publish failed saves.
5. Add/update focused tests.

# risks and edge cases

- Publishing before save success could make hidden routes show a value that failed to persist.
- Duplicate controller notifications should be suppressed for unchanged values.
- Feed’s existing listener handles app shell notifications for tab changes; background notifications must still rebuild Feed.
- The first storage load must still default missing or unknown values to default.

# exact tests and gates to run

```bash
flutter test test/features/posts/phase1/app_shell_controller_test.dart
flutter test test/features/settings/presentation/screens/settings_screen_test.dart
flutter test test/features/settings/presentation/screens/settings_wired_test.dart
flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name "background preference"
```

Named gates: none by default. Run Feed / Surface Gate only if implementation changes Feed behavior beyond receiving controller state.

# known-failure interpretation

Direct suite failures are blocking unless proven unrelated to touched files. The Feed filtered run may include only tests matching `background preference`; broader Feed suite remains for later sessions or final acceptance.

# done criteria

- Shared background preference state exists and notifies only on real changes.
- Settings full-screen background reflects current selected preference.
- Successful saves update shared state; failed saves do not leave shared state or UI claiming the failed preference.
- Direct tests pass or exact environment blocks are documented.

# scope guard

Do not propagate the selected preference into every non-Feed surface in this session. Do not change storage values, l10n keys, semantics text, or telemetry event names. Do not add per-surface render telemetry.

# accepted differences / intentionally out of scope

Using the existing `AppShellController` is accepted for this session because it is already a shared notifier passed through Feed/Settings app-shell flows. Broader pre-identity and one-off route propagation stays in Session 03.

# dependency impact

Session 03 depends on this shared state source to pass the selected preference through constructors without independent storage reads at every screen.

# planning review

The plan is sufficient with no structural blockers. It keeps state publishing behind successful persistence and leaves broad call-site wiring for the next session.

# structural blockers remaining

None.

# exact docs/files used as evidence

- `Test-Flight-Improv/82-app-wide-background-selection.md`
- `Test-Flight-Improv/82-app-wide-background-selection-session-breakdown.md`
- `lib/features/feed/application/app_shell_controller.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/settings/presentation/screens/settings_screen.dart`
- `lib/features/settings/presentation/screens/settings_wired.dart`
- `test/features/settings/presentation/screens/settings_screen_test.dart`
- `test/features/settings/presentation/screens/settings_wired_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`

# closure evidence

Outcome: `accepted`.

Completed April 28, 2026. `AppShellController` owns the selected background preference, Settings publishes loaded and successfully saved preferences, Settings renders its selected full-screen background, failed saves remain honest, and Feed consumes the shared controller state.

Verified:

- `flutter test test/features/posts/phase1/app_shell_controller_test.dart`
- `flutter test test/features/settings/presentation/widgets/background_choice_control_test.dart`
- `flutter test test/features/settings/presentation/screens/settings_screen_test.dart`
- `flutter test test/features/settings/presentation/screens/settings_wired_test.dart`
- `flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name "background preference"`
