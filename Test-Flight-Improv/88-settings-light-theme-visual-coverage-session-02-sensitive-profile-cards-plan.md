# Final verdict

Session `02-sensitive-profile-cards` is `implementation-ready` and execution-safe.

The plan is current-doc-only for `Test-Flight-Improv/88-settings-light-theme-visual-coverage.md` and covers only Session 02 from `Test-Flight-Improv/88-settings-light-theme-visual-coverage-session-breakdown.md`.

# real scope

This session migrates Settings identity and sensitive-account cards away from fixed dark-theme glass and white/muted-white foreground assumptions.

In scope:

- `SettingsPeerIdCard` card shell, nested peer ID container, section label, peer ID text, helper text, copy button, copy icon, and copied check state.
- `SettingsRecoveryPhraseCard` card shell, section label, warning copy, hidden overlay, reveal icon/text, word grid, word numbers, word text, copy/copied action, and hide action.
- `SettingsProfileSection` camera affordance border/icon contrast and direct evidence that the existing editable username child remains readable under Daylight and dark readable profiles.
- Direct widget evidence for normal/copied peer ID, hidden/revealed/copied recovery phrase, long peer ID, long username/edit state, and dark-background regressions.

Out of scope:

- Settings background picker, media quality cards, nearby sharing card, debug section, bottom navigation, full-page all-sections acceptance, clipboard platform integration, avatar storage/download, account identity logic, mnemonic reveal/copy semantics, and username persistence.

# closure bar

Session 02 is complete when the profile, peer ID, and recovery phrase Settings controls consume `BackgroundReadableColors` where they sit directly on the selected background, no longer render muted-white-on-light under Daylight Lagoon, and preserve their existing copy/reveal/hide/avatar/username callbacks.

Good enough means direct widget tests prove readable-role usage or contrast-safe colors for Daylight/representative-light and dark readable profiles. Full Settings-page visual closure remains Session 03.

# source of truth

- `Test-Flight-Improv/88-settings-light-theme-visual-coverage.md`
- `Test-Flight-Improv/88-settings-light-theme-visual-coverage-session-breakdown.md`
- `Test-Flight-Improv/88-settings-light-theme-visual-coverage-session-01-controls-cards-plan.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `lib/core/theme/background_readable_colors.dart`
- `lib/features/settings/presentation/widgets/settings_peer_id_card.dart`
- `lib/features/settings/presentation/widgets/settings_recovery_phrase_card.dart`
- `lib/features/settings/presentation/widgets/settings_profile_section.dart`
- `lib/features/home/presentation/widgets/editable_username_widget.dart`
- `test/features/settings/presentation/widgets/settings_peer_id_card_test.dart`
- `test/features/settings/presentation/widgets/settings_recovery_phrase_card_test.dart`
- `test/features/settings/presentation/widgets/settings_profile_section_test.dart`

Current code and tests win over stale prose. The breakdown artifact is the Session 02 scope contract. Named gate membership follows `Test-Flight-Improv/test-gate-definitions.md`.

# existing evidence

- `EditableUsernameWidget` already reads `context.backgroundReadableColors` and uses light-surface readable roles for profile display/edit text.
- `SettingsPeerIdCard` still hardcodes section label, card, nested container, peer ID text, helper text, copy button, and normal icon colors.
- `SettingsRecoveryPhraseCard` still hardcodes section label, card, hidden overlay, reveal affordance, word grid, copy/hide action, and word text colors.
- `SettingsProfileSection` still hardcodes the camera overlay border to the dark background color and the camera icon to white.
- Existing direct tests cover rendering and callbacks, but not readable-role usage under Daylight/representative-light.

# implementation plan

1. Add readable-color wrappers and focused style helpers to the peer ID, recovery phrase, and profile direct widget tests.
2. Add failing representative-light and dark-readable assertions for the peer ID card's card chrome, section label, nested container, peer ID text, helper text, normal copy icon, and copied check icon.
3. Add failing representative-light and dark-readable assertions for the recovery phrase card's card chrome, section label, hidden overlay/reveal affordance, revealed word grid, word numbers/text, copy/copied controls, hide control, and warning color contrast.
4. Add representative-light and dark-readable assertions for `SettingsProfileSection`, focused on the camera overlay border/icon and editable username display/edit text colors.
5. Import `BackgroundReadableColors` in the target Settings widgets.
6. Replace background-sensitive fixed colors with readable roles while preserving layout, blur, dimensions, copy, callback, and animation behavior.
7. Keep semantic behavior and existing localized strings unchanged.
8. Run `dart format` on changed Session 02 files.
9. Run focused Session 02 tests and the already-passing Session 01 tests only if shared helpers are touched.

# exact tests and gates to run

Format:

```bash
dart format \
  lib/features/settings/presentation/widgets/settings_peer_id_card.dart \
  lib/features/settings/presentation/widgets/settings_recovery_phrase_card.dart \
  lib/features/settings/presentation/widgets/settings_profile_section.dart \
  test/features/settings/presentation/widgets/settings_peer_id_card_test.dart \
  test/features/settings/presentation/widgets/settings_recovery_phrase_card_test.dart \
  test/features/settings/presentation/widgets/settings_profile_section_test.dart
```

Focused direct tests:

```bash
flutter test test/features/settings/presentation/widgets/settings_peer_id_card_test.dart
flutter test test/features/settings/presentation/widgets/settings_recovery_phrase_card_test.dart
flutter test test/features/settings/presentation/widgets/settings_profile_section_test.dart
```

Named gates:

- No named gate is required by default because Session 02 is Settings-local presentation and widget behavior.
- Run `./scripts/run_test_gates.sh completeness-check` only if gate definitions are edited or if implementation adds a new integration/cross-feature/core-service test.

# known-failure interpretation

Failures in the focused Session 02 widget tests are blocking.

Broader test failures are not part of this session unless the touched files caused them. Existing generated cache files and unrelated dirty worktree entries are not Session 02 evidence and must not be cleaned or reverted.

# done criteria

- `SettingsPeerIdCard`, `SettingsRecoveryPhraseCard`, and `SettingsProfileSection` no longer rely on fixed dark-theme foreground/surface assumptions for their target Daylight-visible chrome.
- Existing copy, reveal, hide, avatar, and username edit callbacks still pass.
- Representative-light and dark-readable direct widget evidence passes for the target sensitive/profile states.
- No Session 03 full-page acceptance or debug-section migration is attempted.

# closure/update contract

After implementation and QA, update this plan with closure notes and update the Session 02 row in `Test-Flight-Improv/88-settings-light-theme-visual-coverage-session-breakdown.md`. Final source-doc closure remains Session 03.

# closure result

Status: `accepted`

Implementation summary:

- `SettingsPeerIdCard` now consumes `BackgroundReadableColors` for its section label, glass card, nested peer ID container, peer ID text, helper text, copy button, and normal copy icon. The copied check uses a darker teal on light surfaces.
- `SettingsRecoveryPhraseCard` now consumes readable roles for its section label, glass card, warning copy, hidden overlay, reveal affordance, word grid, word labels, copy/copied action, and hide action. Warning and copied accents use darker variants on light surfaces.
- `SettingsProfileSection` now adapts the camera affordance border to the readable surface and uses a darker teal on light surfaces. Existing editable username readable-role behavior is covered by Settings profile tests.
- Direct tests now cover representative-light and dark-readable states for profile, peer ID, and recovery phrase widgets while preserving copy, reveal, hide, avatar, and username-edit callbacks.

Verification:

- `flutter test test/features/settings/presentation/widgets/settings_peer_id_card_test.dart` passed.
- `flutter test test/features/settings/presentation/widgets/settings_recovery_phrase_card_test.dart` passed.
- `flutter test test/features/settings/presentation/widgets/settings_profile_section_test.dart` passed.

Notes:

- No named gate was required because the accepted changes stayed Settings-local and presentation-only.
