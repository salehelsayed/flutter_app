# Session 01 Plan: Mirrored Preference Storage Plus Settings Third Option

## real scope

Add one mirrored cosmic background preference value and expose it as a third Settings background choice. This session owns storage serialization/parsing, Settings picker option rendering, localized copy, selected-state semantics, failed-save honesty for the new enum value, and focused tests for those seams.

This session does not port or render the mirrored cosmic background in production. Until Session `02`, shared rendering may still treat the new value as the existing non-default visual or compile-safe fallback only where necessary.

## closure bar

The session is complete when `BackgroundPreference` can serialize, parse, load, save, and overwrite a stable mirrored value while preserving `default` and `cosmic`; Settings shows `Default`, `Cosmic`, and mirrored cosmic as distinguishable localized options; the control-level semantics value reflects the selected option without collapsing all non-default values into `Cosmic`; tapping any option emits the correct enum; and direct tests cover missing/unknown fallback, mirrored persistence, locale copy, semantics, and error-copy display.

## source of truth

- Primary product intent: `Test-Flight-Improv/83-mirrored-cosmic-background-option.md`
- Session split: `Test-Flight-Improv/83-mirrored-cosmic-background-option-session-breakdown.md`
- Current implementation wins on exact APIs and generated l10n shape.
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` decide named gate membership if named gates become relevant.

## session classification

`implementation-ready`

## exact problem statement

Settings currently exposes only `Default` and `Cosmic`, and `BackgroundPreference` only stores `default` and `cosmic`. The picker's control-level selected-state logic treats every non-default value as existing `Cosmic`, which would be wrong once a third option exists. Users need a distinguishable mirrored cosmic option that can be selected, persisted, reloaded, localized, and represented honestly when saving fails.

## files and repos to inspect next

- `lib/features/settings/domain/models/background_preference.dart`
- `lib/features/settings/application/background_preference_use_cases.dart`
- `lib/features/settings/presentation/widgets/background_choice_control.dart`
- `lib/l10n/app_en.arb`
- `lib/l10n/app_de.arb`
- `lib/l10n/app_ar.arb`
- `lib/l10n/app_localizations*.dart`
- `test/features/settings/application/background_preference_use_cases_test.dart`
- `test/features/settings/presentation/widgets/background_choice_control_test.dart`
- `test/features/posts/phase1/app_shell_controller_test.dart`
- Dirty pre-existing tests to avoid overwriting without care: `test/features/settings/presentation/screens/settings_screen_test.dart`, `test/features/settings/presentation/screens/settings_wired_test.dart`

## existing tests covering this area

- `background_preference_use_cases_test.dart` covers two-value serialization, parsing, load, save, and overwrite.
- `background_choice_control_test.dart` covers two-option visibility, tapping, selected icons, semantics, supported locales, and error copy.
- `app_shell_controller_test.dart` covers background preference notification behavior for the existing enum.

Current gaps are mirrored storage, mirrored load/save/overwrite, three-option picker visibility, mirrored selected semantics, mirrored tapping, locale copy, and notification behavior for a mirrored initial or changed preference.

## regression/tests to add first

- Expand `background_preference_use_cases_test.dart` to assert the mirrored storage string, parsing, loading, saving, and overwrite behavior.
- Expand `background_choice_control_test.dart` to assert all three options render, mirrored has its own selected icon/key, tapping mirrored emits `BackgroundPreference.cosmicMirrored`, and semantics value is mirrored-specific.
- Expand locale coverage to include mirrored copy in English, German, and Arabic.
- Expand `app_shell_controller_test.dart` only enough to prove the controller accepts/notifies for the mirrored enum.

## step-by-step implementation plan

1. Add `cosmicMirrored` to `BackgroundPreference` with stable storage string `cosmic_mirrored`; preserve `default` and `cosmic` strings and null/unknown fallback.
2. Add mirrored background localization keys to all committed ARB files.
3. Regenerate or update committed generated localization Dart files so the new getters compile.
4. Update `BackgroundChoiceControl` to derive selected labels with a switch and render a third option with distinct keys and mirrored copy.
5. Add or update focused tests for storage, picker UI, semantics, locale copy, tapping, error copy, and app-shell controller behavior.
6. Run the focused direct tests.
7. Update this plan and the breakdown ledger with exact evidence and status.

## risks and edge cases

- The selected-state semantics must not collapse mirrored into existing `Cosmic`.
- Unknown stored values must still fall back to `defaultBackground`.
- Existing `default` and `cosmic` storage strings must not change.
- Localization generated files must stay in sync with ARB keys.
- Pre-existing dirty Settings screen/wired tests must not be overwritten.

## exact tests and gates to run

- `flutter test test/features/settings/application/background_preference_use_cases_test.dart`
- `flutter test test/features/settings/presentation/widgets/background_choice_control_test.dart`
- `flutter test test/features/posts/phase1/app_shell_controller_test.dart`

No named gate is required for this session unless implementation edits gate definitions, integration tests, or cross-feature route wiring.

## known-failure interpretation

Failures in the direct tests above are session-blocking unless they are proven pre-existing by rerunning before the change or isolated to unrelated dirty user edits. Generated l10n compile errors are blocking for this session. Device-only or simulator-only failures are not expected in Session `01`.

## done criteria

- Stable mirrored enum storage string exists and is tested.
- Settings picker renders and emits three distinct options.
- Control and option semantics identify the mirrored selected state.
- English, German, and Arabic mirrored copy resolves without raw keys.
- Focused direct tests pass or exact blockers are recorded.
- Session ledger records Session `01` as accepted only with concrete evidence.

## scope guard

Do not port `cosmic_background_mirrored.dart` into production, change `AmbientBackground` rendering semantics beyond compile-safe enum handling if required, alter Feed or route propagation, redesign Settings, change telemetry event names, or modify unrelated Settings/media/identity behavior.

## accepted differences / intentionally out of scope

The final visual treatment, reduced-motion behavior, shared-background renderer integration, integration smoke, visual readability, and performance evidence are intentionally deferred to Sessions `02` and `03`.

## dependency impact

Session `02` depends on the mirrored enum and localization names landed here. If this session changes the enum name or storage string, Session `02` and Session `03` must use the final landed value rather than the earlier decomposition wording.

## reviewer pass

The plan is sufficient with one accepted limitation: Settings wired save-failure behavior is already enum-generic, so this session only adds direct coverage if a focused test can be changed without overwriting pre-existing dirty files. Otherwise the direct picker and persistence tests prove the new enum seam, and broader wired smoke remains in Session `03`.

## arbiter verdict

No structural blockers remain. The plan is safe to implement now with direct feature-local tests and without entering Session `02` rendering scope.

## execution result

Session `01-settings-preference-option` is accepted.

Landed changes:

- Added `BackgroundPreference.cosmicMirrored` with stable storage string `cosmic_mirrored`, while preserving `default`, `cosmic`, and null/unknown fallback to `defaultBackground`.
- Added English, German, and Arabic mirrored cosmic Settings copy and regenerated committed l10n output.
- Updated `BackgroundChoiceControl` to render a third mirrored option with distinct keys, selected icon, selected semantics, and tap callback.
- Added the compile-safe `AmbientBackground` enum case needed for the new value; the real mirrored production renderer remains Session `02`.
- Expanded focused storage, Settings picker, localization, semantics, and app-shell controller tests.

Verification:

- Passed: `flutter test test/features/settings/application/background_preference_use_cases_test.dart test/features/settings/presentation/widgets/background_choice_control_test.dart test/features/posts/phase1/app_shell_controller_test.dart`

Residual for later sessions:

- Session `02` must replace the compile-safe mirrored renderer fallback with a production-owned mirrored visual.
- Session `03` must run combined Settings-to-Feed/non-Feed smoke, readability, performance, inventory, and final docs closure.
