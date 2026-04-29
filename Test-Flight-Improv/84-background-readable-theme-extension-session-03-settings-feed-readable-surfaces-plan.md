# Session 03 Plan: Settings And Feed Readable Surfaces

## real scope

Migrate representative Settings and Feed background-sensitive surfaces to readable roles. Preserve Settings picker behavior, localization, failed-save copy, Feed loading/empty behavior, navigation, cards, and message flows.

## closure bar

Settings header and background picker plus Feed empty/loading states use readable-theme foreground, surface, border, icon, and disabled/loading roles under both dark and representative light profiles.

## source of truth

- `Test-Flight-Improv/84-background-readable-theme-extension.md`
- `lib/features/settings/presentation/screens/settings_screen.dart`
- `lib/features/settings/presentation/widgets/background_choice_control.dart`
- `lib/features/feed/presentation/screens/feed_screen.dart`

## session classification

`implementation-ready`

## exact problem statement

Settings and Feed contained dark-background-only white/dark hard-coded colors in header, picker, empty, loading, border, and progress states.

## files and repos to inspect next

- `test/features/settings/presentation/screens/settings_screen_test.dart`
- `test/features/settings/presentation/widgets/background_choice_control_test.dart`
- `test/features/feed/presentation/screens/feed_screen_test.dart`

## existing tests covering this area

Existing tests covered Settings picker behavior, Settings screen basics, and Feed loading/empty behavior, but not representative light readable roles.

## regression/tests to add first

Add widget assertions for representative light role usage in Settings header, Settings background picker, and Feed loading/empty states.

## step-by-step implementation plan

1. Convert Settings header and back control to readable glass, border, icon, and text roles.
2. Convert `BackgroundChoiceControl` card, title, options, selected/unselected text, and borders to readable roles.
3. Convert Feed empty/loading cards, loading status, spinner, text, and skeleton bars to readable roles.
4. Add representative light tests for these migrated elements.

## risks and edge cases

The background picker's green selected check remains a product accent and must stay visible. Feed behavior and message/card flows must not change.

## exact tests and gates to run

- `flutter test --no-pub test/features/settings/presentation/widgets/background_choice_control_test.dart test/features/settings/presentation/screens/settings_screen_test.dart test/features/feed/presentation/screens/feed_screen_test.dart`
- No named gate required unless Feed behavior changes beyond colors.

## known-failure interpretation

Analyzer reports existing non-blocking issues in `feed_screen.dart` and long-lived tests when those files are analyzed directly; passing targeted widget tests are the session evidence.

## done criteria

Representative Settings and Feed migrated elements use readable roles and targeted tests pass.

## scope guard

Do not change Feed card semantics, inline reply, message actions, media flows, Settings persistence, image quality, nearby sharing, or profile behavior.

## accepted differences / intentionally out of scope

Exhaustive migration of every Settings child card and every Feed card subcomponent is left to the final inventory follow-up before a production light background ships.

## dependency impact

Session `05` must classify any remaining hard-coded Settings/Feed colors as background-aware, background-independent, or explicit follow-up.

## closure result

`accepted_with_explicit_follow_up`

Evidence:

- Updated `lib/features/settings/presentation/screens/settings_screen.dart`.
- Updated `lib/features/settings/presentation/widgets/background_choice_control.dart`.
- Updated `lib/features/feed/presentation/screens/feed_screen.dart`.
- Extended Settings and Feed widget tests.
- Passing focused surface suite including Settings and Feed tests.
