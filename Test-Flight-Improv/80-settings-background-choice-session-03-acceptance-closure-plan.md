# Session 03 Plan: Acceptance And Closure

# Real scope

Validate the landed default-background choice end to end enough to close doc `80`: shared default rendering, Settings reopen behavior, semantics/localization evidence, early onboarding surfaces, static shared-background call-site inventory, one representative Feed-to-Settings smoke, and final docs.

Out of scope: new background variants, additional artwork, per-surface route smoke for all 14 surfaces, and changes to feed/navigation behavior.

# Closure bar

This session is done when direct tests prove the default background still renders the recognizable black/green/red treatment, Settings reopens with `Default` selected, pre-Settings onboarding surfaces render the shared background, the 14 current shared-background call sites remain on `AmbientBackground`, a device/emulator smoke confirms Settings over a representative Feed surface when a target is available, and the breakdown/source doc record a final verdict.

# Source of truth

Current code/test evidence wins. The source doc allows shared-path proof plus inventory instead of 14 separate route smoke tests. `flutter devices` showed Android/iOS simulator targets are available, so a lightweight device smoke should be attempted.

# Session classification

`acceptance-only`

# Exact problem statement

The feature implementation is landed, but closure still needs combined evidence that the Settings picker did not drift the default background, that early surfaces without a saved preference remain valid, and that the doc reaches a persisted final verdict.

# Files and repos to inspect next

- `test/features/identity/presentation/widgets/ambient_background_test.dart`
- `test/features/identity/presentation/screens/identity_choice_screen_test.dart`
- `test/features/home/presentation/screens/first_time_experience_screen_test.dart`
- `integration_test/settings_background_choice_smoke_test.dart`
- `Test-Flight-Improv/80-settings-background-choice.md`
- `Test-Flight-Improv/80-settings-background-choice-session-breakdown.md`

# Existing tests covering this area

Sessions 01 and 02 added direct preference, background widget, Settings screen, Settings wired, localization, semantics, save failure, and telemetry coverage.

# Regression/tests to add first

- Strengthen the ambient widget test with static call-site inventory and default glow-color checks.
- Add direct pre-Settings onboarding surface checks for `IdentityChoiceScreen` and `FirstTimeExperienceScreen`.
- Add a lightweight integration smoke for Feed surface -> Settings -> close/reopen.

# Step-by-step implementation plan

1. Extend `ambient_background_test.dart` to assert base color, default glow colors, and the current call-site inventory.
2. Add or extend onboarding screen tests to assert `AmbientBackground` appears before Settings can be used.
3. Add integration smoke for Settings background choice over a representative Feed surface.
4. Run direct tests and the device smoke on one available target.
5. Update source and breakdown docs with evidence and final verdict.

# Risks and edge cases

Device smoke can fail for environment reasons unrelated to the feature. If that happens, record the exact command and failure while keeping host-side widget evidence explicit. Avoid `pumpAndSettle` around animated backgrounds.

# Exact tests and gates to run

- `flutter test test/features/settings/application/background_preference_use_cases_test.dart test/features/identity/presentation/widgets/ambient_background_test.dart`
- `flutter test test/features/settings/presentation/widgets/background_choice_control_test.dart test/features/settings/presentation/screens/settings_screen_test.dart test/features/settings/presentation/screens/settings_wired_test.dart`
- `flutter test test/features/identity/presentation/screens/identity_choice_screen_test.dart test/features/home/presentation/screens/first_time_experience_screen_test.dart`
- `flutter test integration_test/settings_background_choice_smoke_test.dart -d emulator-5554`

No named gate is required because no Feed/AppShell/startup routing code or gate definitions are changed.

# Known-failure interpretation

Direct host-side test failures are blocking. Device smoke infrastructure failures are recorded as environment blockers only if host-side direct evidence still passes and the failure is unrelated to the changed files.

# Done criteria

- Direct host-side tests pass.
- Device smoke passes, or exact environment failure is recorded.
- Source doc records completed evidence.
- Breakdown ledger marks all sessions accepted and records a final verdict of `closed`, `accepted_with_explicit_follow_up`, `residual_only`, or `stale/already-covered`.

# Scope guard

Do not add broad app-shell integration, alter Feed behavior, or create a new matrix doc.

# Accepted differences / intentionally out of scope

Only one representative mounted-route smoke is required; the remaining surfaces are covered through the shared widget and static inventory.

# Dependency impact

This is the final acceptance session for doc `80`.

# Execution result

Verdict: `accepted`

Evidence:

- Strengthened `test/features/identity/presentation/widgets/ambient_background_test.dart` with default glow-color proof and static 14-surface `AmbientBackground` inventory.
- Extended `test/features/identity/presentation/screens/identity_choice_screen_test.dart`.
- Added `test/features/home/presentation/screens/first_time_experience_screen_test.dart`.
- Added `integration_test/settings_background_choice_smoke_test.dart`.
- Updated `Test-Flight-Improv/80-settings-background-choice.md` with final closure status.
- `flutter test test/features/settings/application/background_preference_use_cases_test.dart test/features/identity/presentation/widgets/ambient_background_test.dart test/features/settings/presentation/widgets/background_choice_control_test.dart test/features/settings/presentation/screens/settings_screen_test.dart test/features/settings/presentation/screens/settings_wired_test.dart test/features/identity/presentation/screens/identity_choice_screen_test.dart test/features/home/presentation/screens/first_time_experience_screen_test.dart` passed.
- `flutter test integration_test/settings_background_choice_smoke_test.dart -d emulator-5554` passed.
