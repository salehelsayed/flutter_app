# 1. Title and Type

- Title: Settings Light Theme Visual Coverage
- Issue type: `bug`
- Output doc path: `Test-Flight-Improv/88-settings-light-theme-visual-coverage.md`

# 2. Problem Statement

Users who choose the Daylight Lagoon light background are trying to use Settings to manage their profile, background, media quality, nearby sharing, peer ID, and recovery phrase without losing visual clarity.

The Settings page currently does not look consistently good on the light theme. Repo evidence shows some Settings surfaces are light-aware, but several Settings cards and controls still carry dark-theme glass, white text, muted-white labels, and dark-background button assumptions.

This is a problem because Settings is the place where users choose and confirm the light background. If that page itself looks unfinished or hard to read after choosing the light theme, users cannot trust the theme option or confidently manage important account and privacy controls.

# 3. Impact Analysis

- Affected users: anyone who opens Settings while Daylight Lagoon or another light readable theme is active.
- When it appears: Settings header/background picker can appear readable, while lower cards and subcontrols can still look dark-theme styled or low-contrast on the light background.
- Severity: user-visible visual regression on an important account/settings surface. The impact is higher for recovery phrase, peer ID, profile editing, and background preference controls because users rely on those areas for identity and account safety.
- Frequency: likely every time the affected Settings cards are visible under the light theme, based on fixed dark-theme color evidence in the Settings widgets.
- Confusion cost: users may interpret the page as partially themed, broken, or unsafe to use, especially when selected states, helper text, disabled states, and sensitive recovery phrase controls are visually inconsistent.

# 4. Current State

- `lib/features/settings/presentation/screens/settings_screen.dart` wraps Settings in `AmbientBackground` and resolves readable colors for the sticky header. The header title and back button have explicit representative-light test coverage in `test/features/settings/presentation/screens/settings_screen_test.dart`.
- `lib/features/settings/presentation/widgets/background_choice_control.dart` already uses the readable color extension for the background picker card, option rows, selected state, and labels. `test/features/settings/presentation/widgets/background_choice_control_test.dart` verifies representative-light picker chrome and option selection semantics.
- `lib/features/settings/presentation/widgets/image_quality_toggle.dart` still uses fixed dark-theme glass and foreground colors for the card shell, section label, segmented control, selected/unselected options, and description copy.
- `lib/features/settings/presentation/widgets/posts_nearby_settings_card.dart` still uses fixed white and muted-white text, fixed white glass/card borders, and a platform switch without light-theme visual coverage.
- `lib/features/settings/presentation/widgets/settings_peer_id_card.dart` still uses fixed white/muted-white label, peer ID, helper text, copy icon, card surface, and nested peer ID container styling.
- `lib/features/settings/presentation/widgets/settings_recovery_phrase_card.dart` still uses fixed white/muted-white label, card, overlay, word grid, copy/hide actions, and warning/control colors. Existing tests cover reveal/copy/hide behavior, but not readability or visual quality under a light theme.
- `lib/features/settings/presentation/widgets/settings_profile_section.dart` uses a fixed teal camera action, dark border, and white camera icon over the profile avatar. Existing tests cover avatar/profile rendering and edit entry, but not the light-theme visual outcome.
- `lib/features/settings/presentation/widgets/settings_introduction_debug_card.dart` contains the same fixed dark-theme glass and white/muted-white styling. It is optional through `debugSection`; whether it is production-user reachable should remain an implementation-time evidence question.
- `test/features/settings/presentation/widgets/image_quality_toggle_test.dart`, `settings_peer_id_card_test.dart`, `settings_recovery_phrase_card_test.dart`, and `settings_profile_section_test.dart` primarily cover rendering and callbacks, not light-theme contrast or visual completeness.
- `integration_test/settings_background_choice_smoke_test.dart` proves the Settings background choice can switch between background options and return to Feed, but it does not assert that every Settings card looks polished and readable under Daylight Lagoon.
- Background selection is currently modeled as `BackgroundPreference`, not as a Flutter-wide `ThemeMode` change. The preference is saved through secure storage and propagated through `AppShellController.notifyListeners()`, which can rebuild listening app-shell surfaces but should not directly restart transport services.
- `Test-Flight-Improv/87-app-wide-light-theme-readability.md` named Settings as an in-scope light-theme surface and accepted broad local evidence, but the user report indicates the Settings page still needs a dedicated visual coverage pass rather than relying on header/background-picker coverage alone.

# 5. Scope Clarification

In scope:

- Settings page visual quality and readability under Daylight Lagoon.
- Header, back button, profile/avatar/edit username area, background picker, photo quality card, video quality card, nearby sharing card, peer ID card, recovery phrase card, bottom navigation, and any Settings error/disabled/selected/copied/revealed states visible to users.
- Consistency between top-level Settings chrome and lower Settings cards on the light theme.
- Sensitive controls remaining clearly readable: peer ID copy, recovery phrase hidden/revealed state, copy/hide actions, and warning copy.
- Background switching user journey as observable behavior: selecting Daylight Lagoon should not leave Settings looking partially dark-themed.
- Connection-status non-regression for the background switching journey: selecting Daylight Lagoon from Settings should not disconnect the active transport, trigger an unintended reconnect/resume path, or hide/misrepresent the visible connection state.

Non-goals:

- Redesigning Settings information architecture or changing which settings exist.
- Changing background preference storage, navigation, account identity logic, nearby sharing behavior, media quality behavior, or recovery phrase reveal/copy behavior.
- Changing connection, relay, lifecycle, or transport behavior.
- Defining a new app-wide theme architecture.
- Expanding this spec to Feed, Orbit, Conversation, Groups, QR, Share, or Identity pages except where they are used to verify entering or leaving Settings.

Accepted ambiguities for the later implementation pass:

- Exact visual polish criteria beyond observable readability and consistency should be decided against the existing app design language.
- Whether `settings_introduction_debug_card.dart` is user-reachable in production should be verified before it is treated as mandatory acceptance coverage.
- If a connection issue is observed while changing the background, implementation-time evidence should distinguish an actual transport disconnect from a UI-only status/readability issue or a normal app lifecycle pause/resume.
- Simulator visual evidence may be needed for device-size, safe-area, keyboard, and platform switch rendering, but this spec does not prescribe how that evidence is collected.

# 6. Test Cases

## Happy Path

- With Daylight Lagoon active, Settings opens with a visually coherent light-theme page from header through bottom navigation; the page should not appear half light-themed and half dark-themed.
- The profile area remains readable and polished, including avatar, camera affordance, username display, edit affordance, and username editing state.
- The background picker remains readable and clearly communicates the selected option for Default, Cosmic, Mirrored cosmic, and Daylight Lagoon.
- Photo Quality and Video Quality cards show readable labels, icons, selected/unselected options, and explanatory copy under Daylight Lagoon.
- Nearby Sharing shows readable title, on/off status, explanatory copy, and platform switch state under Daylight Lagoon.
- Peer ID shows readable section label, full peer ID, helper text, copy action, and copied confirmation state under Daylight Lagoon.
- Recovery Phrase shows readable title, warning copy, hidden overlay, tap-to-reveal affordance, revealed 12-word grid, word numbers, Copy/Copied, and Hide controls under Daylight Lagoon.
- Existing dark backgrounds still show Settings with readable dark-theme presentation after switching away from Daylight Lagoon.
- If the app is already online before selecting Daylight Lagoon, the background change preserves the existing connection state and does not force a visible disconnect/reconnect cycle.

## Edge Cases

- Long peer IDs remain readable without clipping, overlap, or unreadable contrast.
- Long usernames and username editing state remain readable on the light theme.
- Recovery phrase hidden and revealed states remain readable without sensitive words visually bleeding through in a confusing way when hidden.
- Copied states for peer ID and recovery phrase are visibly distinct from normal copy states.
- Save-error copy for background choice remains readable on the light theme.
- Settings remains readable when optional sections are absent, such as no peer ID, no mnemonic, no quality controls, or no nearby sharing control.
- Settings remains readable when every optional section is present, including enough vertical content to scroll behind the sticky header and floating navigation.
- Localized Settings labels that are longer than English remain readable and do not overlap their controls.
- The platform switch for nearby sharing is visible and understandable on the light theme in both on and off states.

## Regressions To Preserve

- Preservation/regression: tapping each background option still reports the selected background and updates the selected indicator.
- Preservation/regression: Settings background selection still persists or reports save failure as it does today.
- Preservation/regression: Settings background selection does not call connection, relay, lifecycle resume, or transport restart paths as part of the visual change.
- Preservation/regression: connection indicators and online/offline copy remain readable after selecting Daylight Lagoon, so a healthy connection is not mistaken for a broken one.
- Preservation/regression: image and video quality toggles still call their selection callbacks and show the correct selected option.
- Preservation/regression: nearby sharing still toggles on and off without changing the meaning of the setting.
- Preservation/regression: profile avatar rendering, camera tap, and username edit submission still work.
- Preservation/regression: peer ID copy and copied icon state still work.
- Preservation/regression: recovery phrase reveal, copy, copied, and hide controls still work.
- Preservation/regression: Settings back navigation and bottom navigation remain usable with the light theme active.
- Bug regression: with Daylight Lagoon active, no Settings card title, helper text, option label, selected state, peer ID, recovery phrase word, warning copy, icon, border, or control may appear as pale white/muted-white-on-light or dark-glass-on-light in a way that recreates the reported “Settings page did not look well on the light theme” failure.

## Existing Coverage And Gaps

- Existing direct tests partially cover Settings header and background picker readability.
- Existing direct tests cover many Settings callbacks and rendered labels.
- Existing integration smoke covers choosing backgrounds from Settings and returning to Feed.
- Gap: no current evidence appears to prove that switching Settings to Daylight Lagoon preserves active connection state and keeps connection indicators readable.
- Gap: no current direct test appears to cover all Settings cards under Daylight Lagoon as a complete visible page.
- Gap: no current direct test appears to cover light-theme readability for image/video quality cards, nearby sharing, peer ID, recovery phrase hidden/revealed states, or profile edit state.
- Gap: no current acceptance evidence appears to cover full Settings page visual quality on a representative mobile viewport with all optional sections present.

Required acceptance evidence:

- Direct widget evidence for every user-visible Settings card and state named in this spec.
- Integration or smoke evidence that the Settings background choice journey still works and that Settings remains visually coherent after selecting Daylight Lagoon.
- Integration or smoke evidence that selecting Daylight Lagoon does not trigger an unintended connection loss/reconnect and does not visually obscure the current connection status.
- Simulator evidence if mobile viewport, safe area, keyboard, platform switch, or full-page scroll behavior cannot be credibly accepted from direct widget evidence alone.

# 7. Implementation Closure - 2026-04-29

Status: `closed`

Implemented and verified through `Test-Flight-Improv/88-settings-light-theme-visual-coverage-session-breakdown.md`.

Accepted evidence:

- `ImageQualityToggle` and `PostsNearbySettingsCard` now consume `BackgroundReadableColors` for Daylight-visible card chrome and text; focused widget and wired nearby-sharing behavior tests pass.
- `SettingsPeerIdCard`, `SettingsRecoveryPhraseCard`, and `SettingsProfileSection` now consume readable roles or contrast-safe light-surface accents for peer ID, recovery phrase hidden/revealed/copied states, and profile camera/username states; focused widget tests pass.
- `settings_screen_test.dart` now covers Daylight Lagoon with every normal Settings section present and optional sections absent.
- `settings_wired_test.dart` now includes a background-selection non-interference check proving Daylight selection does not call P2P start/stop/reinitialize/dial paths.
- `integration_test/settings_background_choice_smoke_test.dart -d macos` passed and covers the Settings background journey through Daylight Lagoon and back to dark/default backgrounds.

Explicit residual:

- Device-specific screenshot evidence for physical safe areas, route-transition screenshots, keyboard placement, platform-switch native rendering, and system chrome remains release-QA visual evidence only. Local direct and macOS smoke evidence closed the repo-owned implementation and regression contract.
