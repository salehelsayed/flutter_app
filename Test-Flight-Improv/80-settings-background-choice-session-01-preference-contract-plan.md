# Session 01 Plan: Default Background Preference Contract

# Real scope

Add the default-only background preference model and secure-storage use cases, and make the shared `AmbientBackground` accept the preference without changing its current visible treatment.

Out of scope: non-default artwork, app-wide state propagation, Settings UI picker, localization, telemetry, simulator smoke, and route-specific special cases.

# Closure bar

This session is done when missing, `default`, and unknown stored values resolve to `Default`; saving writes the canonical `default` value; overwrite behavior is covered; and `AmbientBackground` still renders the existing default background through a typed preference contract.

# Source of truth

Current code and tests win over stale docs. `Test-Flight-Improv/80-settings-background-choice.md` defines product intent. `Test-Flight-Improv/80-settings-background-choice-session-breakdown.md` defines this session boundary.

# Session classification

`implementation-ready`

# Exact problem statement

The app has a shared default ambient background but no typed background preference contract. Settings cannot safely wire a background choice until persistence and default fallback behavior exist.

# Files and repos to inspect next

- `lib/features/settings/domain/models/image_quality_preference.dart`
- `lib/features/settings/application/image_quality_preference_use_cases.dart`
- `lib/features/identity/presentation/widgets/ambient_background.dart`
- `test/features/settings/application/image_quality_preference_use_cases_test.dart`

# Existing tests covering this area

Image/video quality preference tests already cover the secure-storage pattern, but no background preference tests exist. No current test locks `AmbientBackground` to a typed background choice.

# Regression/tests to add first

- `test/features/settings/application/background_preference_use_cases_test.dart` for missing/default/unknown parse, save, and overwrite.
- `test/features/identity/presentation/widgets/ambient_background_test.dart` for the default typed contract and unchanged base background.

# Step-by-step implementation plan

1. Add `BackgroundPreference.defaultBackground` with storage key `background_preference`, storage value `default`, and default fallback parsing.
2. Add load/save use cases using `SecureKeyStore`.
3. Add optional `preference` to `AmbientBackground`, defaulting to `BackgroundPreference.defaultBackground`, and keep rendering the current default treatment.
4. Add direct tests for parsing/storage and default rendering.
5. Run the direct tests for the new files.

# Risks and edge cases

Unknown storage values must not break Settings or early onboarding. The `AmbientBackground` constructor change must preserve every existing call site through a default parameter.

# Exact tests and gates to run

- `flutter test test/features/settings/application/background_preference_use_cases_test.dart`
- `flutter test test/features/identity/presentation/widgets/ambient_background_test.dart`

No named gate is required because this session only touches feature-local use cases and an additive shared-widget constructor parameter.

# Known-failure interpretation

Failures in the new direct tests are blocking. Unrelated analyzer or generated-cache noise is not part of this session unless it is caused by the changed files.

# Done criteria

- New background preference model and use cases compile.
- Direct use-case tests pass.
- Direct ambient-background widget test passes.
- Breakdown ledger records Session 01 as accepted or closed with evidence.

# Scope guard

Do not add fake variants, previews, global notifiers, route rewiring, Settings UI, or localization in this session.

# Accepted differences / intentionally out of scope

Only the default background is implemented. Future non-default variants remain a later release concern.

# Dependency impact

Session 02 depends on this typed preference contract for Settings picker load/save wiring.

# Execution result

Verdict: `accepted`

Evidence:

- Added `lib/features/settings/domain/models/background_preference.dart`.
- Added `lib/features/settings/application/background_preference_use_cases.dart`.
- Updated `lib/features/identity/presentation/widgets/ambient_background.dart` with an additive typed default preference contract.
- Added `test/features/settings/application/background_preference_use_cases_test.dart`.
- Added/extended `test/features/identity/presentation/widgets/ambient_background_test.dart`.
- `flutter test test/features/settings/application/background_preference_use_cases_test.dart test/features/identity/presentation/widgets/ambient_background_test.dart` passed.
