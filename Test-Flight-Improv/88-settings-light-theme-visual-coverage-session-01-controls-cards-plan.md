# Final verdict

Session `01-controls-cards` is `implementation-ready` and execution-safe.

The plan is current-doc-only for `Test-Flight-Improv/88-settings-light-theme-visual-coverage.md` and only covers Session 01 from `Test-Flight-Improv/88-settings-light-theme-visual-coverage-session-breakdown.md`.

# real scope

This session migrates only the Settings media-quality cards and nearby-sharing card away from fixed dark-theme glass and white/muted-white foreground assumptions.

In scope:

- `ImageQualityToggle` card shell, border, section icon, section label, segmented-control container, selected/unselected options, and description copy.
- Both production uses of `ImageQualityToggle` in `SettingsScreen`: photo quality and video quality.
- `PostsNearbySettingsCard` card shell, border, title, on/off status copy, helper copy, and switch-visible states.
- Direct widget evidence for media-quality compressed/original states, video icon/custom label behavior, nearby sharing on/off states, Daylight/representative-light readability, dark-background regression rendering, and preserved callbacks.

Out of scope:

- Settings persistence, background selection, profile/avatar editing, peer ID, recovery phrase, debug section, bottom navigation, posts delivery, nearby eligibility, location refresh semantics, repository behavior, route wiring, and full-page acceptance.

# closure bar

Session 01 is complete when the photo quality, video quality, and nearby-sharing Settings controls consume `BackgroundReadableColors` from the ambient readable theme, no longer render dark-glass-on-light or muted-white-on-light under Daylight Lagoon, and still preserve their existing callbacks and selected/on/off state behavior.

Good enough means direct widget tests prove readable-role usage or contrast-safe colors for the target card surfaces and text in both representative-light and dark readable profiles. Full Settings-page visual closure remains Session 03.

# source of truth

- `Test-Flight-Improv/88-settings-light-theme-visual-coverage.md`
- `Test-Flight-Improv/88-settings-light-theme-visual-coverage-session-breakdown.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `lib/core/theme/background_readable_colors.dart`
- `lib/features/settings/presentation/screens/settings_screen.dart`
- `lib/features/settings/presentation/widgets/image_quality_toggle.dart`
- `lib/features/settings/presentation/widgets/posts_nearby_settings_card.dart`
- `test/features/settings/presentation/widgets/image_quality_toggle_test.dart`
- `test/features/settings/presentation/screens/settings_wired_posts_nearby_test.dart`

Current code and tests win over stale prose. The breakdown artifact is the Session 01 scope contract. `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` decide named gate membership.

# session classification

`implementation-ready`

# exact problem statement

Doc `88` identifies Settings as visually incomplete under the Daylight Lagoon light background. Session 01 isolates the lower ordinary control cards that still carry dark-theme assumptions:

- `ImageQualityToggle` uses fixed white glass, fixed dark segmented fill, white selected labels, muted-white unselected labels, and muted-white descriptions.
- `PostsNearbySettingsCard` uses fixed white glass, white title text, muted-white status/helper text, and has no Daylight visual evidence for its switch states.

User-visible behavior must improve so these ordinary controls look coherent and readable on Daylight Lagoon while their selection and toggle semantics stay unchanged.

# evidence collector notes

- `SettingsScreen` already resolves `BackgroundReadableColors` from `currentBackgroundPreference`, wraps content in `AmbientBackground`, and passes photo/video/nearby controls only when their callbacks are available.
- `ImageQualityToggle` currently owns its own fixed dark-theme styling rather than reading `context.backgroundReadableColors`.
- `PostsNearbySettingsCard` currently owns its own fixed dark-theme styling rather than reading `context.backgroundReadableColors`.
- Existing `image_quality_toggle_test.dart` verifies labels, icon, selected font weight, and callbacks, but not readable roles or light-theme styling.
- Existing `settings_wired_posts_nearby_test.dart` verifies repository writes, interactive refresh when enabling, and inactive publication/clearing when disabling nearby sharing, but not Daylight readability.
- `BackgroundChoiceControl` is the nearest Settings-local readable-role pattern: it reads `context.backgroundReadableColors` and tests representative-light roles directly.
- Named gates are not required for Settings-local presentation changes. The Posts / Privacy Gate applies only if implementation changes posts delivery, nearby presence, privacy filters, or replay behavior.

# files and repos to inspect next

Production target files:

- `lib/features/settings/presentation/widgets/image_quality_toggle.dart`
- `lib/features/settings/presentation/widgets/posts_nearby_settings_card.dart`

Direct test target files:

- `test/features/settings/presentation/widgets/image_quality_toggle_test.dart`
- `test/features/settings/presentation/widgets/posts_nearby_settings_card_test.dart` if a new direct nearby-card widget suite is needed for clean visual-role assertions.
- `test/features/settings/presentation/screens/settings_wired_posts_nearby_test.dart` for existing behavior-preservation coverage.
- `test/features/settings/presentation/screens/settings_screen_test.dart` only if the executor needs a narrow composition assertion proving both quality controls and nearby sharing appear under `SettingsScreen`.

Do not inspect or edit Session 02/03 target widgets unless Session 01 tests prove a shared helper must be adjusted.

# target files

Expected production edits:

- `lib/features/settings/presentation/widgets/image_quality_toggle.dart`
- `lib/features/settings/presentation/widgets/posts_nearby_settings_card.dart`

Expected test edits/additions:

- `test/features/settings/presentation/widgets/image_quality_toggle_test.dart`
- `test/features/settings/presentation/widgets/posts_nearby_settings_card_test.dart`
- Keep `test/features/settings/presentation/screens/settings_wired_posts_nearby_test.dart` behavior tests passing; edit only if the production change requires a narrow assertion update.

Expected docs after implementation:

- This plan file may receive closure notes.
- `Test-Flight-Improv/88-settings-light-theme-visual-coverage-session-breakdown.md` should be updated by the closure pass with Session 01 status and verification.
- Do not update source doc `88` in Session 01 unless execution discovers the source doc is materially stale. Final source-doc closure belongs to Session 03.

# existing tests covering this area

- `test/features/settings/presentation/widgets/image_quality_toggle_test.dart` covers default/custom labels, custom icon, selected compressed/original font weights, and `onChanged` callbacks.
- `test/features/settings/presentation/screens/settings_wired_posts_nearby_test.dart` covers nearby sharing repository mutation, enabling refresh, and disabling cleanup behavior through `SettingsWired`.
- `test/features/settings/presentation/screens/settings_screen_test.dart` covers Settings header representative-light readable roles and Daylight background selection, but not the target lower cards.
- `test/core/theme/background_readable_colors_test.dart` covers the readable color roles and contrast helpers at the theme-extension level.
- `test/features/settings/presentation/widgets/background_choice_control_test.dart` provides a Settings-local testing pattern for representative-light readable-role assertions.

Missing coverage:

- No direct test currently proves `ImageQualityToggle` uses readable surfaces, borders, icons, labels, selected/unselected options, and descriptions under representative-light or Daylight.
- No direct test currently proves `PostsNearbySettingsCard` uses readable surfaces, borders, title/status/helper copy, and visible on/off switch states under representative-light or Daylight.
- No dark-background regression test currently proves the same migrated target cards remain readable on the dark readable profile.

# regression/tests to add first

Add or tighten tests before the production styling edits:

1. In `image_quality_toggle_test.dart`, add a wrapper that can inject `BackgroundReadableColors.dark` or `BackgroundReadableColors.representativeLight` through `ThemeData.extensions`.
2. Add a representative-light test for `ImageQualityToggle` asserting the card surface/border, section icon/label, selected option, unselected option, segmented-control surface, and description use readable roles or intentionally contrast-safe colors.
3. Add a dark-readable regression test for `ImageQualityToggle` asserting the same key foreground/surface roles remain dark-profile readable.
4. Keep existing compressed/original callback tests and selected font-weight tests intact.
5. Add a direct nearby-card widget suite, preferably `posts_nearby_settings_card_test.dart`, with a readable-colors wrapper.
6. Add representative-light nearby-card tests for off and on states, including title, status copy, helper copy, card surface/border, switch presence, and callback on toggle.
7. Add a dark-readable nearby-card regression test for the same visible text roles.
8. Keep `settings_wired_posts_nearby_test.dart` as behavior-preservation proof for repository writes, refresh, and disabling cleanup.

# step-by-step implementation plan

1. Add failing readable-role tests for `ImageQualityToggle` and `PostsNearbySettingsCard` as described above.
2. Import `BackgroundReadableColors` where needed in the target widgets.
3. In `ImageQualityToggle.build`, read `final readableColors = context.backgroundReadableColors`.
4. Replace card shell, border, icon, label, segmented container, selected/unselected option, and description colors with readable roles. Preserve dimensions, padding, `BackdropFilter`, `AnimatedContainer` duration, labels, selected logic, and callbacks.
5. Pass readable colors into the private option builder rather than resolving theme state separately inside every option if that keeps the widget small and testable.
6. In `PostsNearbySettingsCard.build`, read `final readableColors = context.backgroundReadableColors`.
7. Replace card shell, border, title, status, and helper text colors with readable roles. Keep layout, copy, `Switch.adaptive`, and `onChanged` semantics.
8. If the default adaptive switch is low contrast in tests or visual inspection, set only the switch color/theme properties required to make on/off states visible against the readable surface. Do not change the value source or callback.
9. Run `dart format` on changed Dart files.
10. Run the focused direct tests. If a direct role assertion is brittle because Flutter internals differ across platforms, replace it with a higher-level assertion against the explicit widget style or a contrast-helper assertion on the concrete colors the widget owns.
11. Stop after Session 01 target cards are fixed. Do not migrate peer ID, recovery phrase, profile, debug, or full-page acceptance in this session.

# risks and edge cases

- `Switch.adaptive` can render differently by platform, so tests should prove the switch exists, preserves callback behavior, and uses explicit contrast-safe styling only where the widget controls it.
- `ImageQualityToggle` is reused for photo and video quality; tests must cover custom label/icon so the video instance is not accidentally regressed.
- The selected option needs a visible selected surface and text weight without relying on white-on-glass assumptions.
- Description copy is small text; it must use a readable muted role with acceptable contrast on the target card surface.
- Dark readable profile must not become over-bright or lose the existing glass style after replacing fixed white opacity values.
- Nearby sharing behavior tests are asynchronous through `SettingsWired`; visual work must not change repository, location refresh, or disabling cleanup semantics.

# exact tests and gates to run

Format:

```bash
dart format \
  lib/features/settings/presentation/widgets/image_quality_toggle.dart \
  lib/features/settings/presentation/widgets/posts_nearby_settings_card.dart \
  test/features/settings/presentation/widgets/image_quality_toggle_test.dart \
  test/features/settings/presentation/widgets/posts_nearby_settings_card_test.dart \
  test/features/settings/presentation/screens/settings_wired_posts_nearby_test.dart
```

Focused direct tests:

```bash
flutter test test/features/settings/presentation/widgets/image_quality_toggle_test.dart
flutter test test/features/settings/presentation/widgets/posts_nearby_settings_card_test.dart
flutter test test/features/settings/presentation/screens/settings_wired_posts_nearby_test.dart
```

Conditional direct test:

```bash
flutter test test/features/settings/presentation/screens/settings_screen_test.dart
```

Run the conditional direct test only if `SettingsScreen` composition or helpers are touched.

Named gates:

- No named gate is required by default because Session 01 is Settings-local presentation and widget coverage.
- Run `./scripts/run_test_gates.sh posts` only if implementation changes posts delivery, nearby presence, privacy filters, replay behavior, `PostsPrivacySettingsRepository`, `NearbyLocationService`, or nearby-sharing application semantics.
- Run `./scripts/run_test_gates.sh completeness-check` only if gate definitions are edited or if implementation adds a new integration/cross-feature/core-service test that requires explicit classification. A new feature-local widget test under `test/features/settings/presentation/widgets/` does not by itself require gate-doc edits.

# known-failure interpretation

Failures in the focused Session 01 widget tests are blocking.

Failures in `settings_wired_posts_nearby_test.dart` are blocking if they involve nearby sharing rendering, repository writes, refresh, or disabling cleanup.

Named-gate failures are not part of this session unless a conditional gate is run because the implementation touched that gate's behavior. If a conditional gate exposes pre-existing failures unrelated to Session 01 touched files, record the command, failing test names, and why they are unrelated rather than expanding the session.

The existing dirty worktree and generated Xcode/Flutter cache files are not evidence of Session 01 regressions and must not be reverted or cleaned as part of this plan.

# done criteria

- `ImageQualityToggle` consumes `BackgroundReadableColors` for its target card, text, icon, segmented, selected, unselected, and description roles.
- `PostsNearbySettingsCard` consumes `BackgroundReadableColors` for its target card, title/status/helper text, border, and any explicitly controlled switch colors.
- Fixed dark-glass-on-light and muted-white-on-light assumptions are removed from the Session 01 target visual surfaces.
- Photo quality and video quality compressed/original states still render correctly and still call `onChanged` with the selected `ImageQualityPreference`.
- Nearby sharing off/on states still render correctly and still call `onChanged`; `SettingsWired` behavior tests for repository writes, enabling refresh, and disabling cleanup still pass.
- Representative-light and dark-readable direct widget evidence passes for both target cards.
- No Session 02/03 widgets or unrelated rollout docs are changed.
- Closure pass updates only the Session 01 plan/closure notes and the Session 01 row in the breakdown ledger unless new durable integration coverage was added.

# scope guard

Do not change:

- `SettingsWired` application behavior unless a test reveals a direct Session 01 wiring break caused by the presentation change.
- background preference storage, background picker behavior, Settings navigation, profile/avatar/username behavior, peer ID copy behavior, recovery phrase reveal/copy/hide behavior, or debug-section behavior.
- posts delivery, nearby post eligibility, location permission policy, location refresh timing, privacy persistence, replay behavior, or transport behavior.
- source doc `88`, Session 02/03 plans, prior rollout docs, gate definitions, or integration coverage inventory during this planning-only turn.

Overengineering for this session includes creating a new app-wide theme architecture, adding visual goldens, broadening to all Settings cards, changing localization strings, or refactoring Settings layout beyond the two target widgets.

# accepted differences / intentionally out of scope

- Full Settings page all-sections-present evidence, optional absence states, background-choice journey evidence, simulator/device screenshots, safe-area proof, and debug-section classification remain Session 03.
- Profile/avatar editing, peer ID, and recovery phrase readability remain Session 02.
- The adaptive switch may keep platform-native geometry. Session 01 only requires visible, understandable on/off states and preserved behavior, not a custom switch redesign.
- Existing media-quality labels, descriptions, and animation behavior stay unchanged even if the visual role mapping changes.

# dependency impact

Session 02 depends on Session 01 to remove the ordinary lower-control card gap before sensitive identity and recovery cards are migrated.

Session 03 depends on Sessions 01 and 02 to run full Settings composition and journey acceptance without redoing individual card migrations.

If Session 01 cannot prove readable-role coverage for either target widget, Sessions 02 and 03 should remain blocked or refreshed before execution.

# closure/update contract

This planning turn writes only this plan file.

After implementation and QA, the closure pass should:

- add a concise verification note to this plan or adjacent closure notes with commands run and results;
- update the Session 01 row in `Test-Flight-Improv/88-settings-light-theme-visual-coverage-session-breakdown.md` with status, final execution verdict, blocker class, and closure docs touched;
- update `Test-Flight-Improv/02-integration-test-coverage.md` only if new durable integration coverage is actually added;
- leave source doc `88` final closure to Session 03 unless Session 01 discovers the doc is materially stale.

# reviewer pass

Reviewer verdict: sufficient as-is.

Missing files, tests, regressions, or gates: none structurally. The only implementation-time choice is whether nearby-card visual assertions live in a new direct widget suite or a narrow existing Settings test; the plan prefers a new widget suite and still keeps wired behavior tests as preservation proof.

Stale or incorrect assumptions: none found against current code. The Session 01 breakdown matches the current hardcoded colors in both target widgets.

Overengineering check: the plan avoids app-wide theme redesign, full-page acceptance, goldens, and sensitive-card migration.

Decomposition check: the plan is small enough for implementation because it owns two widgets, focused widget tests, and one existing behavior suite.

# arbiter result

Structural blockers remaining: none.

Incremental details intentionally deferred:

- Exact switch color property selection is left to implementation because Flutter platform switch internals vary.
- Whether `settings_screen_test.dart` needs a narrow composition assertion is conditional on actual implementation edits.

Accepted differences intentionally left unchanged:

- Session 01 does not close the full Settings visual bug by itself; it closes only ordinary media/nearby control cards.
- Session 01 does not touch sensitive identity/recovery cards or final journey evidence.

# exact docs/files used as evidence

- `Test-Flight-Improv/88-settings-light-theme-visual-coverage.md`
- `Test-Flight-Improv/88-settings-light-theme-visual-coverage-session-breakdown.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `lib/core/theme/background_readable_colors.dart`
- `lib/features/settings/presentation/screens/settings_screen.dart`
- `lib/features/settings/presentation/widgets/background_choice_control.dart`
- `lib/features/settings/presentation/widgets/image_quality_toggle.dart`
- `lib/features/settings/presentation/widgets/posts_nearby_settings_card.dart`
- `test/core/theme/background_readable_colors_test.dart`
- `test/features/settings/presentation/widgets/background_choice_control_test.dart`
- `test/features/settings/presentation/widgets/image_quality_toggle_test.dart`
- `test/features/settings/presentation/screens/settings_screen_test.dart`
- `test/features/settings/presentation/screens/settings_wired_posts_nearby_test.dart`

# why the plan is safe to implement now

The target surface is bounded to two Settings-local presentation widgets with existing callback and wired behavior tests. The surrounding `SettingsScreen` already provides the ambient readable theme, and the repo already has a readable-role pattern in `BackgroundChoiceControl`. The gate contract is explicit, the stop line excludes later Settings cards and full-page acceptance, and closure updates are limited to the Session 01 plan/breakdown unless implementation adds durable integration evidence.

# closure result

Status: `accepted`

Implementation summary:

- `ImageQualityToggle` now reads `context.backgroundReadableColors` and uses readable roles for the card shell, border, icon, label, segmented-control surface, selected/unselected option text, selected surface, and description copy.
- `PostsNearbySettingsCard` now reads `context.backgroundReadableColors` and uses readable roles for the card shell, border, title, on/off status, and helper copy while preserving the adaptive switch value and callback.
- Added direct nearby-sharing card widget coverage and expanded media-quality widget tests for representative-light and dark readable roles.

Verification:

- `flutter test test/features/settings/presentation/widgets/posts_nearby_settings_card_test.dart` passed.
- `flutter test test/features/settings/presentation/screens/settings_wired_posts_nearby_test.dart` passed.
- `flutter test test/features/settings/presentation/widgets/image_quality_toggle_test.dart` passed.

Notes:

- An earlier parallel test attempt hit Flutter's startup lock/native asset setup (`lipo`) while multiple Flutter commands were running; the same focused tests were rerun sequentially and passed.
- No named gate was required because the accepted changes stayed Settings-local and presentation-only.
