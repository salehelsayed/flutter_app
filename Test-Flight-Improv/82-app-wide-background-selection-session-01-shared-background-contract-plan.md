# Session 01 Plan: Shared Background Contract

# real scope

Change only the shared `AmbientBackground` contract and its direct tests so `BackgroundPreference.cosmic` renders the production cosmic background on any shared-background surface. Keep default preference behavior, missing/unknown storage fallback, child layout, hit testing, and reduced-motion behavior unchanged.

# closure bar

This session is closed when a caller that passes `BackgroundPreference.cosmic` gets `CosmicBackground` without needing the Feed flag, default preference still gets the existing ambient treatment, reduced-motion cosmic remains static and recognizable, the current shared-background surface inventory remains audited, and the direct shared-widget/domain tests pass.

# source of truth

- `Test-Flight-Improv/82-app-wide-background-selection.md`
- `Test-Flight-Improv/82-app-wide-background-selection-session-breakdown.md`
- Current code/tests beat stale doc `81` Feed-only prose.
- `Test-Flight-Improv/test-gate-definitions.md` governs named gates.

# session classification

`implementation-ready`

# exact problem statement

`AmbientBackground` currently renders cosmic only when `preference == cosmic` and `isFeedSurface == true`. Doc `82` supersedes that Feed-only restriction: selected background preference must determine the shared app background wherever callers provide the selected preference.

# files and repos to inspect next

- `lib/features/identity/presentation/widgets/ambient_background.dart`
- `lib/features/identity/presentation/widgets/cosmic_background.dart`
- `test/features/identity/presentation/widgets/ambient_background_test.dart`
- `test/features/settings/application/background_preference_use_cases_test.dart`

# existing tests covering this area

- `ambient_background_test.dart` currently covers default ambient rendering, Feed-only cosmic, non-Feed cosmic filtering, reduced-motion cosmic, production-source import safety, and surface inventory.
- `background_preference_use_cases_test.dart` covers missing/default/cosmic/unknown parsing and save/load behavior.

# regression/tests to add first

Update the existing direct widget tests before or with the implementation:

- replace the obsolete non-Feed cosmic fallback assertion with a non-Feed cosmic render assertion
- assert cosmic can render without `isFeedSurface`
- keep default and reduced-motion assertions
- keep static call-site inventory proof

# step-by-step implementation plan

1. Update `AmbientBackground` so `cosmic` preference renders `CosmicBackground` independent of `isFeedSurface`.
2. Keep the optional `isFeedSurface` constructor parameter temporarily for source compatibility with existing call sites.
3. Update the cosmic background doc comment from Feed-specific wording to shared app wording.
4. Update direct widget tests for app-wide selected-background behavior.
5. Run the direct tests listed below.

# risks and edge cases

- A stale Feed-only assertion could hide the new contract.
- Stopping the default ambient animation when switching to cosmic must still work.
- Reduced-motion cosmic should remain static.
- Removing `isFeedSurface` immediately would force broad call-site churn better handled in later sessions.

# exact tests and gates to run

Direct tests:

```bash
flutter test test/features/identity/presentation/widgets/ambient_background_test.dart
flutter test test/features/settings/application/background_preference_use_cases_test.dart
```

Named gates: none unless gate definitions are edited, which this session should avoid.

# known-failure interpretation

Failures in the two direct suites are blocking for this session unless they are proven unrelated pre-existing infrastructure failures. Existing build/index artifacts outside the doc 82 scope are unrelated.

# done criteria

- Direct shared-widget tests encode app-wide cosmic behavior.
- Default, reduced-motion, production import, and call-site inventory tests remain covered.
- Direct tests pass or any environment block is recorded with exact command and failure.
- This plan and the breakdown ledger are updated with closure evidence.

# scope guard

Do not wire saved preferences into Settings, Feed, Conversation, Posts, Orbit, QR, Share, onboarding, or group surfaces in this session. Do not introduce a new app-wide state controller here. Do not alter background storage strings, telemetry, localization, or non-background behavior.

# accepted differences / intentionally out of scope

Keeping `isFeedSurface` as a compatibility parameter is acceptable in this session. Later sessions may remove or ignore it when broad call-site propagation is safe.

# dependency impact

Sessions `02` and `03` depend on this contract because their callers can pass the selected preference without worrying about a Feed-only filter.

# planning review

The plan is sufficient as-is. It is narrow, has a direct regression seam, avoids broad constructor churn, and gives later sessions a stable shared widget contract.

# structural blockers remaining

None.

# exact docs/files used as evidence

- `Test-Flight-Improv/82-app-wide-background-selection.md`
- `Test-Flight-Improv/82-app-wide-background-selection-session-breakdown.md`
- `lib/features/identity/presentation/widgets/ambient_background.dart`
- `test/features/identity/presentation/widgets/ambient_background_test.dart`
- `test/features/settings/application/background_preference_use_cases_test.dart`

# closure evidence

Outcome: `accepted`.

Completed April 28, 2026. `BackgroundPreference.cosmic` now renders `CosmicBackground` on any shared-background surface while default preference keeps the existing ambient treatment.

Verified:

- `flutter test test/features/identity/presentation/widgets/ambient_background_test.dart`
- `flutter test test/features/settings/application/background_preference_use_cases_test.dart`
