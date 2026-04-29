# Session 01 Plan: Readable Theme Contract

## real scope

Add the app-owned readable-color `ThemeExtension`, resolver, system chrome style mapping, and role-level contrast tests. Do not migrate broad screen color usage in this session.

## closure bar

`BackgroundReadableColors` exposes the minimum source-doc roles, current dark `BackgroundPreference` values resolve to the dark readable profile, a representative light fixture resolves through the same resolver, and tests prove role contrast plus system bar brightness.

## source of truth

- `Test-Flight-Improv/84-background-readable-theme-extension.md`
- `Test-Flight-Improv/84-background-readable-theme-extension-session-breakdown.md`
- `lib/core/theme/app_theme.dart`
- `lib/features/settings/domain/models/background_preference.dart`

## session classification

`implementation-ready`

## exact problem statement

There was no production `ThemeExtension` for readable foreground, surface, border, glass, input, disabled, or system chrome roles, so future light backgrounds had no shared contrast contract.

## files and repos to inspect next

- `lib/core/theme/background_readable_colors.dart`
- `lib/core/theme/app_theme.dart`
- `test/core/theme/background_readable_colors_test.dart`

## existing tests covering this area

No prior app-owned readable-color extension tests existed.

## regression/tests to add first

Add unit tests for preference resolution, representative light fixture resolution, system chrome brightness, and contrast thresholds for every minimum role.

## step-by-step implementation plan

1. Add `BackgroundReadableColors` as a `ThemeExtension`.
2. Add dark and representative light readable profiles.
3. Add preference/tone resolver and `SystemUiOverlayStyle` mapping.
4. Register the dark extension in `AppTheme.darkTheme`.
5. Add contrast and resolver tests.

## risks and edge cases

The representative light state must not expose an unfinished user-visible background choice. Current `Default`, `Cosmic`, and mirrored cosmic must remain dark-readable.

## exact tests and gates to run

- `flutter test --no-pub test/core/theme/background_readable_colors_test.dart`
- No named gate required unless gate docs change.

## known-failure interpretation

Pre-existing analyzer issues outside the new theme files do not block this session unless this session introduces them.

## done criteria

Theme extension exists, role tests pass, and current dark preferences resolve to dark readable colors.

## scope guard

Do not redesign app theme, typography, product accents, or screen layouts.

## accepted differences / intentionally out of scope

The representative light profile is test-only plumbing until a production light background is separately specified.

## dependency impact

Later sessions consume `context.backgroundReadableColors` and the selected-background boundary can install this extension.

## closure result

`accepted`

Evidence:

- Added `lib/core/theme/background_readable_colors.dart`.
- Updated `lib/core/theme/app_theme.dart`.
- Added `test/core/theme/background_readable_colors_test.dart`.
- Passing: `flutter test --no-pub test/core/theme/background_readable_colors_test.dart`.
