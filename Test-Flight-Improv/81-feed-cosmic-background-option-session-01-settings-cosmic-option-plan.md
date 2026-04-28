# Session 01 Plan: Cosmic Preference and Settings Option

# real scope

Add the shipped `cosmic` background preference value and expose it in the existing Settings background chooser.

In scope:

- permanent `cosmic` storage serialization and parsing
- null and unknown stored values still resolving to `Default`
- Settings picker shows `Default` and `Cosmic`
- failed-save honesty remains true for the cosmic path
- background-choice flow events distinguish `cosmic` success/failure without sensitive data
- Arabic, German, and English copy exists for the cosmic option
- picker semantics expose the control, both options, and selected state

Out of scope:

- production cosmic artwork or `AmbientBackground` rendering changes
- Feed loading or live refresh
- performance and simulator smoke closure
- applying cosmic to non-Feed routes

# closure bar

This session is done when `BackgroundPreference.cosmic` round-trips through storage, Settings can select and persist `Cosmic`, failed saves revert or clearly fail without false persistence, Settings itself remains on the default background treatment, localized copy resolves for Arabic/German/English, option semantics are discoverable, and the direct Settings/domain tests pass.

# source of truth

- `Test-Flight-Improv/81-feed-cosmic-background-option.md`
- `Test-Flight-Improv/81-feed-cosmic-background-option-session-breakdown.md`
- `Test-Flight-Improv/80-settings-background-choice-session-breakdown.md`
- current code and tests in `lib/features/settings/`
- `Test-Flight-Improv/test-gate-definitions.md` for named gate decisions

Current code and tests win over stale prose. The source doc defines product intent unless current repo evidence proves a requirement stale.

# session classification

`implementation-ready`

# exact problem statement

The default background preference foundation exists, but production code only recognizes and displays `Default`. Users cannot choose the provided cosmic background design because there is no permanent stored `cosmic` value, Settings option, localized copy, semantics, or telemetry proof for that non-default selection.

# files and repos to inspect next

- `lib/features/settings/domain/models/background_preference.dart`
- `lib/features/settings/application/background_preference_use_cases.dart`
- `lib/features/settings/presentation/widgets/background_choice_control.dart`
- `lib/features/settings/presentation/screens/settings_screen.dart`
- `lib/features/settings/presentation/screens/settings_wired.dart`
- `lib/l10n/app_en.arb`
- `lib/l10n/app_de.arb`
- `lib/l10n/app_ar.arb`
- generated localization files under `lib/l10n/` if committed
- `test/features/settings/application/background_preference_use_cases_test.dart`
- `test/features/settings/presentation/widgets/background_choice_control_test.dart`
- `test/features/settings/presentation/screens/settings_screen_test.dart`
- `test/features/settings/presentation/screens/settings_wired_test.dart`

# existing tests covering this area

Existing doc 80 tests cover default-only parsing, save/load, Settings display, failed save, flow events, localization, semantics, and default Settings-over-Feed smoke. They do not cover `cosmic` parsing, a second Settings option, or non-default telemetry.

# regression/tests to add first

- Extend `background_preference_use_cases_test.dart` for `cosmic` parse, save, and overwrite.
- Extend `background_choice_control_test.dart` for both options, selected state, tap callback, and semantics.
- Extend `settings_screen_test.dart` for `Cosmic` selected state while the route background stays default.
- Extend `settings_wired_test.dart` for save/reopen, failed-save, and flow events with `cosmic`.
- Add or extend localization assertions for Arabic/German/English cosmic copy.

# step-by-step implementation plan

1. Add `BackgroundPreference.cosmic` with storage value `cosmic`; keep null/unknown fallback to default.
2. Extend Settings background localization keys in English, German, and Arabic, then regenerate committed localization output if required.
3. Update `BackgroundChoiceControl` to render both options with stable keys and semantics.
4. Ensure `SettingsScreen` does not make its full route cosmic in this session. If needed, force the route-level `AmbientBackground` to default while keeping the selected value in the picker.
5. Verify `SettingsWired` existing save/revert telemetry path works for `cosmic`; patch only if tests expose a gap.
6. Run the direct Settings/domain tests.

# risks and edge cases

- The storage identifier becomes permanent once shipped; do not rename it later without a migration.
- Failed saves must not leave the UI or reopen path claiming `Cosmic` persisted.
- Settings currently passes the selected preference to `AmbientBackground`; this must not turn Settings into the cosmic full-screen surface.
- Semantics must not rely only on color or iconography.

# exact tests and gates to run

Direct tests:

- `flutter test test/features/settings/application/background_preference_use_cases_test.dart`
- `flutter test test/features/settings/presentation/widgets/background_choice_control_test.dart`
- `flutter test test/features/settings/presentation/screens/settings_screen_test.dart`
- `flutter test test/features/settings/presentation/screens/settings_wired_test.dart`

Named gates:

- No named gate is required by default. Run `./scripts/run_test_gates.sh completeness-check` only if gate definitions or classification docs are edited.

# known-failure interpretation

Failures in the direct Settings/domain tests are blocking for this session. Failures from unrelated existing generated-cache or simulator state are not session blockers unless caused by touched files.

# done criteria

- `BackgroundPreference.cosmic` stores and loads `cosmic`.
- Settings displays `Default` and `Cosmic`, and selecting each updates the picker state.
- Failed cosmic save remains honest.
- Flow events distinguish `cosmic` attempts and outcomes.
- Arabic/German/English cosmic strings resolve.
- Direct tests pass or a real blocker is recorded.
- The breakdown ledger records Session `01-settings-cosmic-option` outcome.

# scope guard

Do not port the cosmic painter, change Feed, change non-Feed surface filtering, add global background notifiers, redesign Settings, add extra background options, or broaden into performance/smoke work in this session.

# accepted differences / intentionally out of scope

The exact final marketing label can be simple `Cosmic`/localized equivalent in this session. Visual preview treatment is optional and should not expand into production background rendering.

# dependency impact

Sessions `02`, `03`, and `04` depend on this shipped preference value and Settings option. If this session blocks, later sessions should not implement cosmic rendering or Feed plumbing against a speculative value.

# execution result

Verdict: `accepted`

Evidence:

- Added `BackgroundPreference.cosmic` with canonical storage value `cosmic` and preserved null/unknown fallback to `defaultBackground`.
- Extended the Settings background picker to render `Default` and `Cosmic` with stable keys and selected-state semantics.
- Kept the Settings route-level `AmbientBackground` on `defaultBackground`; the selected preference remains visible in the picker without making Settings itself cosmic.
- Added Arabic, German, and English cosmic option copy and regenerated committed localization output.
- Extended direct tests for storage round-trip, two-option picker state, semantics, localization, Settings screen selected state, SettingsWired persistence, and success/failure flow telemetry.

Verification:

- `flutter test test/features/settings/application/background_preference_use_cases_test.dart test/features/settings/presentation/widgets/background_choice_control_test.dart test/features/settings/presentation/screens/settings_screen_test.dart test/features/settings/presentation/screens/settings_wired_test.dart`
  - Result: passed on April 28, 2026.

Closure:

- Session `01-settings-cosmic-option` is accepted.
- No named gate was required because no gate definitions, cross-feature route orchestration, or Feed behavior changed in this session.
