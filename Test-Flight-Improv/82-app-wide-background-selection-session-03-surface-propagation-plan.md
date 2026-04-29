# Session 03 Plan: Surface Propagation

# real scope

Propagate the selected app background preference into every current shared-background surface named by doc `82`, using the Session 02 `AppShellController.backgroundPreference` where a live app-shell route exists and explicit constructor parameters where routes are one-off descendants. Keep all non-background navigation, messaging, posts, groups, QR, share, media, and transport behavior unchanged.

# closure bar

This session is closed when Conversation, Posts, Orbit, Share Target Picker, QR Display, First Time Experience, Identity Choice, Create Group Picker, Contact Picker, Group List, Group Conversation, and Group Info can receive the selected `BackgroundPreference`; live app-shell surfaces rebuild from the shared controller; startup/pre-identity paths seed the controller from storage; static inventory proves all shared `AmbientBackground` files pass `preference:`; and focused widget tests for representative non-Feed/pre-identity surfaces pass.

# source of truth

- `Test-Flight-Improv/82-app-wide-background-selection.md`
- `Test-Flight-Improv/82-app-wide-background-selection-session-breakdown.md`
- Session 01 shared `AmbientBackground` contract
- Session 02 shared app-shell background state

# session classification

`implementation-ready`

# exact problem statement

After Sessions 01 and 02, any caller that passes `BackgroundPreference.cosmic` gets cosmic and Settings publishes a selected preference, but most non-Feed/shared-background screens still build `AmbientBackground` with the default preference. Doc `82` requires the selected app background to follow users across current shared-background surfaces.

# files and repos to inspect next

- Pure screens using `AmbientBackground` under `lib/features/**/presentation/screens/`
- Wired route owners for Feed, Posts, Orbit, Conversation, QR Display, QR Scanner pending-share, Share Target Picker, First Time Experience, Identity Choice, Startup Router, and Groups
- `lib/main.dart` notification/share/conversation route entry points
- `test/features/identity/presentation/widgets/ambient_background_test.dart`
- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `test/features/home/presentation/screens/first_time_experience_screen_test.dart`
- `test/features/identity/presentation/screens/identity_choice_screen_test.dart`

# existing tests covering this area

- Static `AmbientBackground` inventory in `ambient_background_test.dart`
- Feed wired background preference tests
- Settings wired/screen tests from Session 02
- Existing surface widget tests for Conversation, First Time Experience, and Identity Choice

# regression/tests to add first

- Tighten static inventory so every shared-background surface file contains both `AmbientBackground(` and `preference:`.
- Add representative widget tests proving `BackgroundPreference.cosmic` renders `CosmicBackground` on Conversation, First Time Experience, and Identity Choice.
- Re-run the Feed background-preference test to prove controller-based Feed behavior remains intact.

# step-by-step implementation plan

1. Add optional `backgroundPreference` constructor parameters with default fallback to every pure shared-background screen that currently owns an `AmbientBackground`.
2. Pass those parameters into the local `AmbientBackground(preference: ...)` call.
3. Wire app-shell-backed surfaces to listen to `AppShellController` and pass its current `backgroundPreference`.
4. Thread static preferences through one-off group, QR display, and nested route constructors.
5. Load the stored background preference during startup before pre-identity routing and seed `AppShellController`.
6. Pass the app-shell controller into pending-share, notification, conversation, posts, orbit, and main route entry points where available.
7. Update focused static and representative widget tests.
8. Format touched Dart files and run targeted tests serially.

# risks and edge cases

- Missing a route entry point can leave a surface on default while direct constructors work.
- Publishing broad controller notifications must not change tab/navigation behavior.
- Pre-identity routes must default cleanly when storage is missing or unknown.
- One-off group descendants may carry the preference by value rather than observing the live controller; that is acceptable because Settings is not opened from those transient descendants in this session.

# exact tests and gates to run

```bash
flutter test test/features/identity/presentation/widgets/ambient_background_test.dart
flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart --plain-name "renders the selected cosmic background"
flutter test test/features/home/presentation/screens/first_time_experience_screen_test.dart
flutter test test/features/identity/presentation/screens/identity_choice_screen_test.dart --plain-name "renders the selected cosmic background before Settings"
flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name "background preference"
```

Run `dart analyze` if the route-constructor churn needs a compile-wide check. Named gates remain for Session 04 unless a direct implementation change touches their domain behavior.

# known-failure interpretation

Direct compile/test failures in touched screens or route constructors are blocking. Device-only integration or performance acceptance belongs to Session 04. Existing generated Xcode/Index artifacts in the working tree are unrelated to this session.

# done criteria

- All current shared-background screens pass a selected preference into `AmbientBackground`.
- Live app-shell routes use the shared `AppShellController.backgroundPreference`.
- Startup/pre-identity routes can reflect a stored valid cosmic preference.
- Representative Conversation and pre-identity widget tests prove non-Feed cosmic rendering.
- Static inventory covers all current shared-background files and asserts `preference:` participation.
- Targeted tests pass or exact environment blocks are documented.

# scope guard

Do not redesign screen contents, add new background options, change localization or telemetry strings, alter route behavior beyond background parameters, or introduce per-screen persistence. Do not add device/performance acceptance in this implementation session.

# accepted differences / intentionally out of scope

Group and QR descendant routes may receive a snapshot preference rather than observing the app shell directly. Full route-smoke, overlay readability, lifecycle stress, and performance evidence remain in Session 04.

# dependency impact

Session 04 depends on this session to make the app-wide behavior available for final smoke, lifecycle, readability, and performance acceptance.

# planning review

The plan is sufficient as-is. It is broad but mechanical, bounded to background preference propagation, and backed by static inventory plus representative non-Feed/pre-identity widget tests.

# structural blockers remaining

None.

# exact docs/files used as evidence

- `Test-Flight-Improv/82-app-wide-background-selection.md`
- `Test-Flight-Improv/82-app-wide-background-selection-session-breakdown.md`
- `lib/features/feed/application/app_shell_controller.dart`
- `lib/features/identity/presentation/widgets/ambient_background.dart`
- `test/features/identity/presentation/widgets/ambient_background_test.dart`

# closure evidence

Outcome: `accepted`.

Completed April 28, 2026. Selected background preference is threaded through all current shared-background surfaces named by doc `82`; startup/pre-identity and one-off route entry points now carry the shared preference; static inventory requires every current shared-background surface to pass `preference:` into `AmbientBackground`.

Verified:

- `flutter test test/features/identity/presentation/widgets/ambient_background_test.dart`
- `flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `flutter test test/features/home/presentation/screens/first_time_experience_screen_test.dart`
- `flutter test test/features/identity/presentation/screens/identity_choice_screen_test.dart`
- `flutter test test/features/posts/phase1/posts_screen_test.dart`
- `flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name "background preference"`
