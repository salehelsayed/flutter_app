# 1. Title and Type

- Title: Daylight Lagoon Background Option
- Issue type: feature-improvement
- Output doc path: `Test-Flight-Improv/86-daylight-lagoon-background-option.md`

# 2. Problem Statement

Users should be able to choose the new `Daylight Lagoon` light background from Settings alongside the existing `Default`, `Cosmic`, and `Mirrored cosmic` choices.

Today the Daylight Lagoon background exists only as a Test-Flight artifact, while the production background picker, saved background preference, app-wide ambient background, and localized Settings copy only know about the current dark background choices. If Daylight Lagoon is added as a visual background without also selecting light-background readable colors, the app's existing dark-background foreground treatment can make text, icons, controls, glass panels, overlays, and system chrome difficult to read on the white and pastel background.

Spec `84` has already implemented the shared `ThemeExtension` readable-color boundary. This new light background option must consume that contract as a real production selection, so the selected background visual and selected readable foreground treatment stay aligned.

# 3. Impact Analysis

- Affected users: users who choose Daylight Lagoon as their app background.
- Affected moments: Settings background choice, Feed, Conversation, Posts, Orbit, QR display, Share Target Picker, onboarding, group screens, dialogs, sheets, media pickers, message overlays, loading states, and system status/navigation chrome while Daylight Lagoon is active.
- Severity if shipped without readable-color adaptation: high, because important labels and controls can become low-contrast or unreadable over a light background.
- Frequency after selection: persistent across shared-background surfaces until the user changes the background again.
- Product cost: the first production light background cannot ship safely unless it proves the readable-color ThemeExtension from spec `84` works with a real user-selectable light preference.
- Regression risk: current dark backgrounds must keep their existing dark-background readable appearance while the light option gets a different foreground treatment.

# 4. Current State

- The Daylight Lagoon artifact exists at `Test-Flight-Improv/Background-Feature/daylight_lagoon_background.dart`. It is described as the light-mode counterpart of `CosmicBackground`, with a pure white base, violet/teal/pink drifting blooms, an `18s` animation loop, and no starfield because stars do not read on a bright sky.
  Evidence: `Test-Flight-Improv/Background-Feature/daylight_lagoon_background.dart:1-14`, `Test-Flight-Improv/Background-Feature/daylight_lagoon_background.dart:41-49`, `Test-Flight-Improv/Background-Feature/daylight_lagoon_background.dart:61-90`, `Test-Flight-Improv/Background-Feature/daylight_lagoon_background.dart:133-143`.
- A repository search found no production reference to `DaylightLagoonBackground`, `daylight_lagoon`, or Daylight Lagoon outside the artifact.
  Evidence: `rg -n "DaylightLagoon|daylight_lagoon|daylight lagoon|lagoon" lib test integration_test Test-Flight-Improv`.
- `BackgroundPreference` currently contains only `defaultBackground`, `cosmic`, and `cosmicMirrored`, with stored values `default`, `cosmic`, and `cosmic_mirrored`. Missing or unknown stored values fall back to `defaultBackground`.
  Evidence: `lib/features/settings/domain/models/background_preference.dart:3-34`.
- Background preference storage tests currently cover only the three existing values plus missing and unknown fallbacks.
  Evidence: `test/features/settings/application/background_preference_use_cases_test.dart:7-42`, `test/features/settings/application/background_preference_use_cases_test.dart:45-91`, `test/features/settings/application/background_preference_use_cases_test.dart:94-145`.
- `BackgroundChoiceControl` currently renders three options and resolves selected-state copy for those three options only.
  Evidence: `lib/features/settings/presentation/widgets/background_choice_control.dart:24-32`, `lib/features/settings/presentation/widgets/background_choice_control.dart:76-123`.
- Localized Settings background copy exists for `Default`, `Cosmic`, and `Mirrored cosmic` in English, German, and Arabic. There is no Daylight Lagoon label, description, or selected-state copy yet.
  Evidence: `lib/l10n/app_en.arb:258-269`, `lib/l10n/app_de.arb:258-269`, `lib/l10n/app_ar.arb:258-269`.
- `AmbientBackground` already resolves `BackgroundReadableColors` from the selected `BackgroundPreference` at the background boundary, wraps descendants with that readable theme, and applies the matching `SystemUiOverlayStyle`.
  Evidence: `lib/features/identity/presentation/widgets/ambient_background.dart:61-92`.
- `AmbientBackground` currently switches only among the default ambient background, `CosmicBackground`, and `CosmicBackgroundMirrored`.
  Evidence: `lib/features/identity/presentation/widgets/ambient_background.dart:68-77`.
- `BackgroundReadableColors` is already implemented as a `ThemeExtension` with dark and representative-light profiles, shared readable roles, preference resolution, and system chrome mapping. The representative-light profile uses dark text/icons and dark status/navigation icon brightness.
  Evidence: `lib/core/theme/background_readable_colors.dart:5-30`, `lib/core/theme/background_readable_colors.dart:56-102`, `lib/core/theme/background_readable_colors.dart:104-136`.
- Every current `BackgroundPreference` resolves to the dark readable profile. Daylight Lagoon is the first production light option that needs a non-dark readable tone.
  Evidence: `lib/core/theme/background_readable_colors.dart:115-123`, `test/core/theme/background_readable_colors_test.dart:7-18`.
- Readability tests already establish the spec `84` contrast targets: normal text and essential labels at least `4.5:1`; icons, borders, input borders, disabled components, and meaningful non-text UI at least `3:1`.
  Evidence: `test/core/theme/background_readable_colors_test.dart:65-123`, `Test-Flight-Improv/84-background-readable-theme-extension.md:63-82`.
- Settings already uses readable colors for the header, back button, glass panel, and background picker chrome. Existing widget coverage proves the picker can render with the representative-light readable roles, but it does not include a real Daylight Lagoon option.
  Evidence: `lib/features/settings/presentation/screens/settings_screen.dart:88-156`, `lib/features/settings/presentation/widgets/background_choice_control.dart:45-72`, `lib/features/settings/presentation/widgets/background_choice_control.dart:180-227`, `test/features/settings/presentation/widgets/background_choice_control_test.dart:39-102`.
- Existing Settings-to-Feed smoke coverage exercises selecting `Mirrored cosmic`, reopening Settings, selecting `Cosmic`, and switching back to `Default`. It does not exercise a production light background or light-readable foregrounds.
  Evidence: `integration_test/settings_background_choice_smoke_test.dart:38-224`.
- Existing ambient-background widget coverage proves current dark backgrounds render, current dark readable colors are exposed, and `Cosmic` plus `Mirrored cosmic` honor disabled animations with static paint. It does not cover Daylight Lagoon.
  Evidence: `test/features/identity/presentation/widgets/ambient_background_test.dart:34-118`, `test/features/identity/presentation/widgets/ambient_background_test.dart:162-247`.
- Current shared-background surfaces are tracked by an inventory test: Feed, Conversation, Posts, Settings, Orbit, Share Target Picker, QR Display, First Time Experience, Identity Choice, Create Group Picker, Contact Picker, Group List, Group Conversation, and Group Info.
  Evidence: `test/features/identity/presentation/widgets/ambient_background_test.dart:271-294`.
- Settings failed-save handling currently reverts the visible selected preference to the previous preference and shows localized failure copy.
  Evidence: `lib/features/settings/presentation/screens/settings_wired.dart:187-240`.
- Spec `84` is implemented and explicitly records follow-up work before shipping a production light background: exhaustive migration/classification for remaining background-sensitive colors, Settings-to-surface integration coverage for a real production light background, and transient overlay coverage.
  Evidence: `Test-Flight-Improv/84-background-readable-theme-extension.md:171-203`.

# 5. Scope Clarification

In scope:

- Daylight Lagoon is a user-selectable app background in Settings alongside the existing dark options.
- The Daylight Lagoon selection is saved, reloaded, and reflected as selected when Settings is reopened.
- The selected Daylight Lagoon background appears on the app's shared-background surfaces through the same app-wide selected-background behavior used by the existing options.
- Daylight Lagoon keeps the artifact's user-visible visual identity: bright white/light base, soft violet/teal/pink lagoon blooms, and no starfield.
- Daylight Lagoon uses a light-background readable foreground treatment derived from `BackgroundPreference` through the spec `84` `ThemeExtension` boundary.
- Text, icons, disabled states, hints, cards, glass panels, navigation, headers, overlays, dialogs, sheets, loading states, and meaningful image/icon assets remain readable over Daylight Lagoon.
- Normal text and essential labels meet at least `4.5:1` contrast against their effective surface. Large text, icons, control outlines, focus/selection indicators, and meaningful non-text UI components meet at least `3:1`.
- Platform chrome remains visible while Daylight Lagoon is active: light backgrounds use dark status/navigation icons where the platform exposes them.
- A failed Daylight Lagoon save follows the existing last-confirmed-preference rule: visible background, readable-color theme, selected-state copy, and system chrome remain on or return to the last confirmed saved preference together while the user sees the recoverable failure state.
- Reduced-motion or disabled-animation mode keeps Daylight Lagoon recognizable without requiring continuous motion.
- Current `Default`, `Cosmic`, and `Mirrored cosmic` behavior stays visually and semantically intact.
- Production code does not depend on importing the Test-Flight artifact path directly.

Non-goals:

- Adding additional background choices beyond Daylight Lagoon.
- Replacing the already-implemented spec `84` readable-color contract.
- Redesigning the app's visual identity, typography, navigation, cards, message bubbles, group UI, media UI, or Settings layout beyond making the Daylight Lagoon state readable.
- Creating a separate full app light theme or changing the app's global `ThemeMode`.
- Changing background preference sync semantics across devices, backups, identity restore, or account-level state.
- Redesigning product accent colors that already remain readable on both dark and light backgrounds.

Accepted ambiguities to leave open for the later implementation pass:

- The exact production Dart file path and class name for Daylight Lagoon, as long as production code does not import from `Test-Flight-Improv`.
- The exact persisted storage token, as long as it is stable, distinct from existing tokens, round-trips correctly, and preserves existing stored values.
- The exact Daylight Lagoon option order in Settings, as long as it is visible with the other background choices and its selected state is clear.
- The exact final bloom opacity or animation tuning, as long as it remains recognizably Daylight Lagoon and passes readability and performance acceptance.
- Whether Daylight Lagoon uses the current representative-light readable profile exactly or a stricter Daylight-specific profile through the same readable-role contract, as long as the observable contrast and system chrome expectations pass.

# 6. Test Cases

## Happy Path

- A user opens Settings with no saved background preference and sees `Default`, `Cosmic`, `Mirrored cosmic`, and `Daylight Lagoon`, with `Default` selected.
  Existing partial coverage: current Settings picker widget coverage proves the three existing options, selected icon, localized labels, and semantics.
  Gap: no current Settings picker coverage includes Daylight Lagoon.
- A user selects Daylight Lagoon in Settings and immediately sees a bright lagoon-style background with readable dark foreground text, icons, selection state, borders, and glass surfaces.
  Acceptance evidence: widget coverage for visible Daylight Lagoon selection and direct readable-role contrast evidence.
- A user returns from Settings to Feed after selecting Daylight Lagoon and sees the Daylight Lagoon visual background with the matching light-background readable foreground treatment.
  Acceptance evidence: integration coverage for Settings-to-Feed background/readable-color synchronization.
- A user reopens Settings after selecting Daylight Lagoon and sees Daylight Lagoon still selected, with localized selected-state copy and readable Settings chrome.
  Acceptance evidence: integration or smoke coverage for persistence and selected-state reload.
- A user switches from Daylight Lagoon back to `Default`, `Cosmic`, or `Mirrored cosmic` and sees the current dark-background readable treatment restored.
  Acceptance evidence: widget or integration coverage for light-to-dark and dark-to-light switching.
- Daylight Lagoon is visible on representative shared-background surfaces beyond Settings and Feed, including Conversation and at least one Group or Orbit surface, with readable foregrounds.
  Acceptance evidence: widget or visual coverage across representative shared-background surface categories.
- Status and navigation chrome remain visible while Daylight Lagoon is selected.
  Acceptance evidence: unit or widget evidence for the resolved chrome style, plus simulator coverage when the target platform exposes system bars in the test environment.
- Feed scroll performance with Daylight Lagoon selected stays within the existing Feed background performance budget from spec `84`: average build time under `8ms`, P99 under `24ms`, and worst build time under `100ms`, or within the selected-background comparison budget of average below `max(8ms, default + 2ms)`, P99 below `max(24ms, default * 1.25)`, and worst below `max(100ms, default * 1.25)`.
  Acceptance evidence: performance integration coverage using the existing Feed frame-timing budget.

## Edge Cases

- A missing stored background preference still uses the `Default` background and dark readable treatment.
  Existing partial coverage: current preference and readable-color tests cover missing preference fallback for existing values.
- An unknown stored background preference still falls back to `Default` with dark readable treatment and does not show stale Daylight Lagoon copy or colors.
  Existing partial coverage: current preference and readable-color tests cover unknown preference fallback for existing values.
- A failed save after the user taps Daylight Lagoon does not leave the visible background and readable colors mismatched. The last confirmed saved preference controls the visible background, readable-color theme, selected-state copy, and system chrome together.
  Existing partial coverage: current Settings failed-save behavior reverts to the previous preference and shows failure copy.
- Rapid switching between Daylight Lagoon and dark backgrounds does not leave mixed foreground colors, stale selected indicators, stale system chrome, or unreadable intermediate UI.
  Acceptance evidence: widget or integration coverage for repeated dark/light changes.
- Reduced-motion or disabled-animation mode renders Daylight Lagoon without continuous drift while preserving the selected background identity and readable foreground treatment.
  Existing partial coverage: current cosmic and mirrored-cosmic disabled-animation tests cover the dark animated backgrounds.
- English, German, and Arabic Settings builds show Daylight Lagoon label, description, selected-state copy, and accessibility semantics without raw localization keys or clipped selected-state text.
  Existing partial coverage: current Settings picker localization coverage handles the existing options.
- Glass panels, translucent surfaces, overlays, dialogs, sheets, media pickers, message overlays, and loading states remain legible over Daylight Lagoon and do not rely on white-only foreground assumptions.
  Acceptance evidence: representative widget or visual coverage for transient UI and background-sensitive surfaces.
- White-baked or light-only assets shown on shared-background surfaces remain identifiable over Daylight Lagoon by adapting, sitting on a contrasting surface, or being proven background-independent by the same contrast targets.
  Acceptance evidence: static or reviewed inventory evidence for user-visible assets on shared-background surfaces.

## Regressions To Preserve

- Preservation/regression: `Default`, `Cosmic`, and `Mirrored cosmic` remain selectable, persistable, localized, and visually unchanged unless a separate visual spec changes them.
- Preservation/regression: current dark background preferences continue to resolve to dark-readable foreground colors, while Daylight Lagoon resolves to light-background readable colors.
- Preservation/regression: app-wide selected-background behavior remains intact across the shared-background surface inventory.
- Preservation/regression: current Settings-to-Feed smoke behavior for the existing options remains intact after Daylight Lagoon is added.
- Preservation/regression: readable-color roles and contrast thresholds from spec `84` remain enforced for both dark and light selected backgrounds.
- Preservation/regression: selecting or viewing Daylight Lagoon does not alter media quality, nearby sharing, identity, contacts, messages, posts, transport, notification, or group state.
- Preservation/regression: production source continues to avoid direct imports from `Test-Flight-Improv`.

Minimum acceptance evidence:

- Unit evidence is required for Daylight Lagoon preference round-trip behavior, missing and unknown fallback behavior, readable-tone resolution, and system chrome expectations.
- Widget evidence is required for Settings option visibility, selected state, localized copy, semantics, Daylight Lagoon ambient rendering, and foreground/readable-color synchronization.
- Widget or visual evidence is required for representative Settings, Feed, Conversation, and at least one Group or Orbit surface with Daylight Lagoon selected.
- Integration evidence is required for selecting Daylight Lagoon in Settings, returning to Feed with the light background and readable colors synchronized, reopening Settings with Daylight Lagoon still selected, and switching back to a dark background.
- Static or reviewed inventory evidence is required for remaining background-sensitive foreground, border, surface, glass, scrim, input, icon, dialog, sheet, media picker, message overlay, loading, and asset colors across shared-background surfaces before the production light option is considered complete.
- Performance integration evidence is required for Daylight Lagoon on Feed using the concrete frame budgets named above.

Current test gaps:

- No current production model, storage, or Settings picker test includes Daylight Lagoon.
- No current production ambient-background test renders Daylight Lagoon.
- No current test proves a real production `BackgroundPreference` resolves to light-background readable colors.
- No current Settings-to-Feed smoke covers a production light background or light-readable foregrounds.
- No current Daylight Lagoon coverage proves reduced-motion behavior, system chrome visibility, or Feed performance.
- No current test proves localized Daylight Lagoon copy or accessibility semantics in English, German, and Arabic.

# 7. Closure Update - April 28, 2026

Final verdict: `accepted_with_explicit_follow_up`

Doc `86` is accepted with the production Daylight Lagoon option implemented and verified. The earlier "Current test gaps" list above is now historical for the pre-implementation state.

What landed:

- `BackgroundPreference.daylightLagoon` with stable storage token `daylight_lagoon`.
- Production `DaylightLagoonBackground` under `lib/features/identity/presentation/widgets/`, using the bright white base, pastel violet/teal/pink blooms, no starfield, and reduced-motion static rendering.
- `AmbientBackground` support for Daylight Lagoon, including light-readable foreground roles and dark status/navigation icon brightness through `BackgroundReadableColors`.
- English, German, and Arabic Settings labels, descriptions, selected-state copy, and accessibility semantics.
- Settings picker visibility, selection, save/reload, failed-save honesty, and existing dark-background preservation.
- Representative Daylight coverage for Settings, Feed, Conversation, and Orbit shared-background surfaces.
- Settings-to-Feed integration smoke coverage for Daylight selection, Feed rendering, Settings reopen persistence, and switch back to dark backgrounds.
- Feed performance coverage for Daylight Lagoon against a same-run default baseline.

Verification recorded:

- `flutter test test/features/settings/application/background_preference_use_cases_test.dart test/features/settings/presentation/widgets/background_choice_control_test.dart test/features/identity/presentation/widgets/ambient_background_test.dart test/core/theme/background_readable_colors_test.dart`
- `flutter test test/features/settings/presentation/screens/settings_screen_test.dart test/features/settings/presentation/screens/settings_wired_test.dart`
- `flutter test test/features/settings/presentation/screens/settings_screen_test.dart test/features/feed/presentation/screens/feed_screen_test.dart test/features/conversation/presentation/screens/conversation_screen_test.dart test/features/orbit/presentation/screens/orbit_screen_loading_test.dart`
- `flutter test test/features/settings/application/background_preference_use_cases_test.dart test/features/settings/presentation/widgets/background_choice_control_test.dart test/features/settings/presentation/screens/settings_screen_test.dart test/features/settings/presentation/screens/settings_wired_test.dart test/features/identity/presentation/widgets/ambient_background_test.dart test/core/theme/background_readable_colors_test.dart test/features/feed/presentation/screens/feed_screen_test.dart test/features/conversation/presentation/screens/conversation_screen_test.dart test/features/orbit/presentation/screens/orbit_screen_loading_test.dart`
- `flutter test -d emulator-5554 integration_test/settings_background_choice_smoke_test.dart`
- `flutter test -d emulator-5554 integration_test/feed_performance_test.dart`

Feed performance evidence on Android emulator `emulator-5554`:

- Default baseline for Daylight Lagoon scroll: Avg/P99/Worst `2.42/8.16/11.51ms`
- Daylight Lagoon scroll: Avg/P99/Worst `2.09/8.83/10.09ms`

Accepted follow-up:

- If release QA requires image-level assurance for every remaining background-sensitive asset, run a visual/screenshot inventory sweep across the full shared-background surface list. No code-owned blocker remains in this doc.
