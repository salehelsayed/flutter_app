# Session 02 Plan: Selected Theme Propagation

## real scope

Install the readable-color extension at the selected-background boundary and expose matching system chrome style. Keep production preference behavior unchanged.

## closure bar

`AmbientBackground` resolves readable colors from the same `BackgroundPreference` used for the visual background, installs them in `Theme`, and wraps descendants in `AnnotatedRegion<SystemUiOverlayStyle>`.

## source of truth

- `Test-Flight-Improv/84-background-readable-theme-extension.md`
- `lib/features/identity/presentation/widgets/ambient_background.dart`
- `test/features/identity/presentation/widgets/ambient_background_test.dart`

## session classification

`implementation-ready`

## exact problem statement

The shared background widget rendered the selected visual but did not give descendants a matching readable-color profile or system chrome contract.

## files and repos to inspect next

- `lib/features/identity/presentation/widgets/ambient_background.dart`
- `test/features/identity/presentation/widgets/ambient_background_test.dart`

## existing tests covering this area

Ambient background tests already covered default/cosmic/mirrored visual rendering and surface inventory, but not readable extension propagation.

## regression/tests to add first

Add widget tests proving descendants receive dark readable colors for current dark preferences and that system chrome icon brightness is resolved.

## step-by-step implementation plan

1. Resolve `BackgroundReadableColors` in `AmbientBackground`.
2. Install the extension through `Theme.copyWith`.
3. Add `AnnotatedRegion<SystemUiOverlayStyle>`.
4. Add a test-only readable-tone override for representative light fixtures without adding a production light option.
5. Extend ambient tests for readable extension propagation.

## risks and edge cases

Theme extension installation must preserve other theme extensions and must not change child layout, hit testing, or background animation behavior.

## exact tests and gates to run

- `flutter test --no-pub test/features/identity/presentation/widgets/ambient_background_test.dart`
- No named gate required.

## known-failure interpretation

Existing broad analyzer warnings in unrelated Feed/tests remain outside this session.

## done criteria

Ambient descendants can read the profile via `context.backgroundReadableColors`, and existing dark background tests continue to pass.

## scope guard

Do not change background preference storage, Settings save behavior, or visual background implementation.

## accepted differences / intentionally out of scope

Failed-save rollback remains covered by existing Settings wired state tests and by the unchanged preference state source; this session only installs the theme at the visual boundary.

## dependency impact

Settings, Feed, Conversation, Orbit, and later surfaces can consume readable roles from inherited theme.

## closure result

`accepted`

Evidence:

- Updated `lib/features/identity/presentation/widgets/ambient_background.dart`.
- Extended `test/features/identity/presentation/widgets/ambient_background_test.dart`.
- Passing: `flutter test --no-pub test/features/identity/presentation/widgets/ambient_background_test.dart`.
