# Session 02 Plan: Settings Background Picker

# Real scope

Add the visible Settings background choice for the existing `Default` background, wire it to secure-storage load/save, expose localized copy and semantics, and emit non-sensitive flow telemetry for save attempts and outcomes.

Out of scope: non-default backgrounds, preview artwork, app-wide live theme switching, route-transition changes, Feed/AppShell handoff changes, and simulator smoke closure.

# Closure bar

This session is done when Settings shows `Background` with `Default` selected, tapping `Default` persists `background_preference=default`, reopening Settings still shows `Default`, failed writes show honest failure state and do not persist false success, Arabic/German/English labels resolve, and telemetry distinguishes success from failure without sensitive content.

# Source of truth

Current Settings code and tests define implementation patterns. `Test-Flight-Improv/80-settings-background-choice.md` defines acceptance. Session 01 provides the typed preference contract.

# Session classification

`implementation-ready`

# Exact problem statement

Settings has no user-visible place to choose the shared app background. The background preference contract now exists, but the screen does not load it, render it, save it, localize it, expose it accessibly, or report save outcomes.

# Files and repos to inspect next

- `lib/features/settings/presentation/screens/settings_screen.dart`
- `lib/features/settings/presentation/screens/settings_wired.dart`
- `lib/features/settings/presentation/widgets/image_quality_toggle.dart`
- `lib/l10n/app_*.arb`
- `test/features/settings/presentation/screens/settings_screen_test.dart`
- `test/features/settings/presentation/screens/settings_wired_test.dart`

# Existing tests covering this area

Settings tests cover title, back navigation, profile/peer/recovery visibility, bottom nav, media toggles, and video-quality persistence. No test covers background choice, failed-save honesty, or background telemetry.

# Regression/tests to add first

- Widget tests for the background control visible text, selected state, tap callback, semantics, and localized strings.
- Settings screen test proving the control appears while existing sections remain.
- Settings wired tests for load/save, failed write behavior, and flow events.

# Step-by-step implementation plan

1. Add localized background-choice strings to English, German, and Arabic ARB files and regenerate committed localization output.
2. Add a pure `BackgroundChoiceControl` widget with a single selectable default option and explicit semantics.
3. Add `SettingsScreen` parameters for current background preference, change callback, and save-error text; render the control in the Settings scroll content.
4. Wire `SettingsWired` to load/save the preference, revert or retain last confirmed state on failure, show failure copy, and emit attempt/success/failure events.
5. Add direct widget and wired tests.
6. Run direct Settings/background tests.

# Risks and edge cases

The only current option is already selected, so tapping it must still be a valid save attempt for persistence and telemetry. Write failures must not appear as successful persistence. Semantics must not rely only on color or selected styling.

# Exact tests and gates to run

- `flutter test test/features/settings/presentation/widgets/background_choice_control_test.dart`
- `flutter test test/features/settings/presentation/screens/settings_screen_test.dart`
- `flutter test test/features/settings/presentation/screens/settings_wired_test.dart`
- Session 01 direct tests if shared files are touched again.

No named gate is required unless this session changes Feed/AppShell routing or gate definition docs.

# Known-failure interpretation

Failures in the direct Settings/background suites are blocking. Unrelated dirty Xcode index/build artifacts are ignored.

# Done criteria

- Settings displays localized `Background` and `Default`.
- Selecting `Default` writes the canonical storage value.
- Failed writes show localized failure copy and do not persist.
- Flow event tests observe success and failure outcomes.
- Existing Settings tests still pass.

# Scope guard

Do not add fake future options, custom artwork, global app background state, or route smoke tests in this session.

# Accepted differences / intentionally out of scope

The current implementation persists only the default option. Future non-default variants still need their own contrast/readability and live-update acceptance.

# Dependency impact

Session 03 can validate visual/default-route evidence and closure only after this visible Settings path lands.

# Execution result

Verdict: `accepted`

Evidence:

- Added `lib/features/settings/presentation/widgets/background_choice_control.dart`.
- Updated `lib/features/settings/presentation/screens/settings_screen.dart`.
- Updated `lib/features/settings/presentation/screens/settings_wired.dart`.
- Added English, German, and Arabic background-choice strings and regenerated `lib/l10n/app_localizations*.dart`.
- Added `test/features/settings/presentation/widgets/background_choice_control_test.dart`.
- Extended `test/features/settings/presentation/screens/settings_screen_test.dart`.
- Extended `test/features/settings/presentation/screens/settings_wired_test.dart`.
- `flutter test test/features/settings/presentation/widgets/background_choice_control_test.dart test/features/settings/presentation/screens/settings_screen_test.dart test/features/settings/presentation/screens/settings_wired_test.dart` passed.
