# 1. Title and Type

- Title: Background-Aware Readable Colors
- Issue type: feature-improvement
- Output doc path: `Test-Flight-Improv/84-background-readable-theme-extension.md`

# 2. Problem Statement

Users should be able to choose future light app backgrounds without losing readable text, icons, controls, cards, or overlays.

Today every selectable background is dark, and the app's current foreground colors are tuned for dark surfaces. The app also has many white text, icon, border, and glass-surface colors embedded directly in screens and widgets. That works for the current dark `Default`, `Cosmic`, and mirrored-cosmic direction, but a light background would make large parts of the app low-contrast or unreadable.

The app needs a shared readable-color contract that follows `BackgroundPreference`, so future light backgrounds can be added without manually restyling each surface or leaving screens visually inconsistent.

# 3. Impact Analysis

- Affected users: users who select a future light background option.
- Affected moments: opening Settings, Feed, Conversation, Posts, Orbit, QR display, Share Target Picker, onboarding, group screens, dialogs, sheets, media pickers, and overlays while a light background is selected.
- Severity today: low, because the currently shipped background choices are dark and match the existing light foreground colors.
- Severity once light backgrounds are added: high readability risk, because core text, icon, control, and card colors can blend into the background.
- Frequency once light backgrounds are added: persistent on every shared-background surface until the selected background changes.
- Product cost: light-background personalization cannot be shipped confidently while readable foreground colors remain dark-background-only.

# 4. Current State

- The app root uses one dark theme and forces dark theme mode.
  Evidence: `lib/main.dart:2564-2572`.
- `AppTheme.darkTheme` uses `Brightness.dark`, a black scaffold background, dark `ColorScheme`, and white or muted-white text colors.
  Evidence: `lib/core/theme/app_theme.dart:8-40`.
- `AppColors` is documented as a dark theme palette. Its background is black, and its primary text colors are white and muted white.
  Evidence: `lib/core/theme/app_colors.dart:3-16`.
- A repository search for `ThemeExtension` and `extension<` found no current app-owned readable-color theme extension in production source.
  Evidence: `rg -n "ThemeExtension|extension<" lib test`.
- `BackgroundPreference` is already carried in app-shell state. `AppShellController` stores the selected background preference and notifies listeners on real changes.
  Evidence: `lib/features/feed/application/app_shell_controller.dart:6-36`.
- `AmbientBackground` receives the selected `BackgroundPreference` and renders the selected visual background. It does not currently provide a matching readable foreground or surface color profile to descendants.
  Evidence: `lib/features/identity/presentation/widgets/ambient_background.dart:7-70`.
- Current shared-background surfaces are tracked by an inventory test: Feed, Conversation, Posts, Settings, Orbit, Share Target Picker, QR Display, First Time Experience, Identity Choice, Create Group Picker, Contact Picker, Group List, Group Conversation, and Group Info.
  Evidence: `test/features/identity/presentation/widgets/ambient_background_test.dart:163-186`.
- Existing app-wide background tests prove background visuals and reduced-motion behavior for the current dark cosmic background, but they do not prove foreground readability changes by background preference.
  Evidence: `test/features/identity/presentation/widgets/ambient_background_test.dart:70-144`.
- Existing Settings-to-Feed smoke proves selecting `Cosmic`, seeing it on Feed, reopening Settings, and switching back to `Default`. It does not cover light-background foreground colors.
  Evidence: `integration_test/settings_background_choice_smoke_test.dart:37-179`.
- Current Feed performance coverage uses concrete frame timing budgets. Steady scroll uses average build time under `8ms`, P99 under `24ms`, and worst build time under `100ms`; background-specific scroll comparison keeps the selected-background average below `max(8ms, default + 2ms)`, P99 below `max(24ms, default * 1.25)`, and worst below `max(100ms, default * 1.25)`.
  Evidence: `integration_test/feed_performance_test.dart:290-328`, `integration_test/feed_performance_test.dart:347-379`, `integration_test/feed_performance_test.dart:398-414`.
- Feed empty/loading states currently use dark card surfaces, white borders, white loading bars, and white text directly in the widget tree.
  Evidence: `lib/features/feed/presentation/screens/feed_screen.dart:1148-1275`.
- Settings header and back controls currently use dark translucent surfaces, white borders, and white icons/text directly in the widget tree.
  Evidence: `lib/features/settings/presentation/screens/settings_screen.dart:86-160`.
- Conversation header currently uses a dark gradient plus white and muted-white icon/text colors directly in the widget tree.
  Evidence: `lib/features/conversation/presentation/widgets/conversation_header.dart:38-116`.
- `FeedColors` is a separate dark feed palette with white-tinted card, border, message, and muted-text colors; its comment says it does not modify `AppColors`, and other screens still use the old palette.
  Evidence: `lib/core/theme/feed_colors.dart:3-31`.
- A repository search found many hard-coded dark-background foreground, surface, border, and scrim colors across shared-background surfaces and their overlays, including Feed, Settings, Conversation, Groups, Orbit, Posts, Share, QR, Home, and Identity surfaces.
  Evidence: `rg -n "Color\\.fromRGBO\\(255, 255, 255|Colors\\.white|Colors\\.white70|Colors\\.black|Color\\.fromRGBO\\(10, 10, 15|Color\\.fromRGBO\\(24, 26, 32|Color\\.fromRGBO\\(16, 18, 24" lib/features`.
- A repository search found no current explicit system status/navigation bar style mapping tied to background preference.
  Evidence: `rg -n "SystemChrome|SystemUiOverlayStyle|statusBar|navigationBar|AnnotatedRegion|brightness" lib test integration_test`.
- Existing app-wide background spec `82` already records readability, overlay, reduced-motion, and performance risk for app-wide selected backgrounds. That risk increases when future backgrounds are light rather than dark.
  Evidence: `Test-Flight-Improv/82-app-wide-background-selection.md`.

# 5. Scope Clarification

In scope:

- A selected background preference has a matching shared readable-color theme exposed through Flutter `ThemeExtension`.
- The readable-color theme is derived from `BackgroundPreference` at the app-shell/background boundary, so the selected background visual and selected readable colors stay in sync.
- Current dark backgrounds continue to use readable light foreground colors.
- The minimum readable-color role set is: `textPrimary`, `textSecondary`, `textMuted`, `iconPrimary`, `iconSecondary`, `iconMuted`, `surfaceBase`, `surfaceRaised`, `surfaceSubtle`, `glassSurface`, `glassBorder`, `border`, `divider`, `overlayScrim`, `inputFill`, `inputBorder`, `placeholderText`, `disabledForeground`, `disabledSurface`, `statusBarIconBrightness`, and `navigationBarIconBrightness`.
- Normal text and essential labels meet at least `4.5:1` contrast against their effective surface. Large text, non-text icons, control outlines, focus/selection indicators, and meaningful graphical UI components meet at least `3:1`. Disabled controls may be visually muted, but they must remain identifiable as disabled without becoming confused with active controls.
- Future light backgrounds can declare dark readable foreground colors, lighter or darker adaptive surfaces, visible borders, readable icons, and suitable status/system chrome expectations.
- Shared-background surfaces can render the same content legibly on both dark and light selected backgrounds.
- Settings background choice remains the user-visible place where background preference changes cause both the background visual and readable foreground colors to update.
- Text, icons, disabled states, hints, cards, glass panels, navigation, headers, overlays, dialogs, sheets, and loading states are covered as readability surfaces.
- A representative light-background selected state is required for acceptance even before a production light background option ships. It may be a non-user-visible test fixture or the first production light option, but it must exercise the same `BackgroundPreference`-derived readable theme path as real selections.
- All foreground, border, surface, glass, scrim, and input colors that affect readability on current shared-background surfaces either use the background-aware readable theme or are explicitly classified as background-independent and still pass the contrast expectations above.
- `AppColors` and `FeedColors` may continue to exist for background visuals, product accents, and background-independent colors. Background-sensitive foreground, surface, border, glass, scrim, and input colors on shared-background surfaces are governed by the readable-color theme.
- Glass and translucent panels use readable-theme surface and scrim roles, not only swapped text colors, so they remain visible over light and dark backgrounds.
- White-baked icons or image assets shown on shared-background surfaces either adapt, have a background-aware alternate/tint, sit on a contrasting adaptive surface, or are explicitly proven background-independent by the same contrast expectations.
- Platform system chrome remains visible: light backgrounds use dark status/navigation icons where the platform exposes them, and dark backgrounds use light status/navigation icons where the platform exposes them.
- On a failed background save, the last confirmed saved preference wins: the visible background, readable-color theme, selected-state copy, and system chrome all remain on or return to the last confirmed preference together, while Settings shows the recoverable failure state.
- Accessibility acceptance includes selected-state clarity, non-color-only state communication, and sufficient visible contrast for representative light and dark backgrounds.
- Existing dark background behavior is preserved while establishing acceptance for future light-background choices.

Non-goals:

- Adding a new production light background option in this spec.
- Redesigning the app's visual identity, typography, navigation, cards, message bubbles, group UI, media UI, or Settings layout.
- Replacing every product accent color or state color that is already readable on both light and dark backgrounds.
- Changing background preference storage semantics beyond the need for readable colors to follow the selected preference.
- Adding cross-device, backup, identity-restore, or account-level syncing for readable color state.
- Requiring a full route smoke test for every shared-background surface before a light background option exists.

Accepted ambiguities to leave open for the later implementation pass:

- The exact light-background palette values, as long as representative light-background screens meet the contrast targets and are visibly consistent.
- The exact first light background design that will consume the readable-color theme.
- The exact order in which shared-background surfaces reach acceptance, as long as light-background states do not ship unreadable.

# 6. Test Cases

## Happy Path

- A user selects a dark background and sees the current light text, icon, card, border, and overlay treatment remain readable.
  Existing partial coverage: current background widget and Settings smoke tests cover dark background visibility, but not foreground adaptation.
  Acceptance evidence: widget coverage for representative dark-background foreground colors and contrast.
- A user selects a light-background preference and sees dark readable foreground colors on representative shared-background surfaces.
  Acceptance evidence: unit coverage for preference-to-readable-theme mapping plus widget coverage showing readable text/icons/surfaces with the representative light selected state.
- A user changes from a dark background to a light background in Settings and sees both the background visual and readable foreground treatment change together.
  Acceptance evidence: widget coverage for live Settings feedback after a successful background change, plus integration coverage for Settings-to-Feed foreground/background consistency.
- A user changes from a light background back to a dark background and sees foreground colors return to the current dark-background readable treatment.
  Acceptance evidence: widget coverage for bidirectional background/readability switching.
- Feed, Settings, Conversation, and one group or Orbit surface remain readable with the light-background readable theme active.
  Acceptance evidence: widget or visual coverage across these representative surface categories.
- Dialogs, bottom sheets, media pickers, message overlays, and loading states remain readable over both light and dark selected backgrounds.
  Acceptance evidence: representative widget or visual coverage for overlays and transient UI.
- Status and navigation chrome remain visible when switching between dark and light selected-background states.
  Acceptance evidence: unit or widget coverage for the resolved system chrome style, plus simulator coverage if the selected target platform exposes system bars in the test environment.
- Feed scroll performance with a representative light selected background stays within the current Feed performance budget: average build time under `8ms`, P99 under `24ms`, and worst build time under `100ms`, or within the current selected-background comparison budget of average below `max(8ms, default + 2ms)`, P99 below `max(24ms, default * 1.25)`, and worst below `max(100ms, default * 1.25)`.
  Acceptance evidence: performance integration coverage using the current Feed frame-timing harness.

## Edge Cases

- A missing stored background preference uses the current dark-readable foreground treatment with the `Default` background.
  Existing partial coverage: current preference tests cover missing background preference fallback.
  Acceptance evidence: unit or widget coverage that readable colors follow the same fallback.
- An unknown stored background preference uses the current dark-readable foreground treatment with the `Default` background and does not produce unreadable UI.
  Existing partial coverage: current preference tests cover unknown background preference fallback.
  Acceptance evidence: unit or widget coverage that readable colors follow the same fallback.
- A failed background save keeps or restores the last confirmed saved background and readable foreground treatment together, including selected-state copy and system chrome.
  Existing partial coverage: current Settings tests cover failed-save honesty for background preference.
  Acceptance evidence: widget or integration coverage for failed-save readability state.
- Rapid switching among dark and light background preferences does not leave stale foreground colors, mixed readable palettes, or unreadable intermediate UI.
  Acceptance evidence: widget or integration coverage for rapid preference changes.
- Reduced-motion or disabled-animation mode still uses the correct readable foreground treatment for the selected background.
  Existing partial coverage: current cosmic tests cover static paint for disabled animations.
  Acceptance evidence: widget or simulator coverage for readable colors with reduced motion active.
- Localized Arabic, German, and English Settings builds keep background option labels, selected-state copy, and readable foreground colors legible on light and dark backgrounds.
  Existing partial coverage: current Settings picker tests cover localized background labels for current options.
  Acceptance evidence: widget or integration localization coverage with representative light and dark foreground treatments.
- Assistive technologies can still identify selected background options and controls after readable colors become background-aware.
  Existing partial coverage: current Settings picker tests cover two-option semantics.
  Acceptance evidence: widget or integration semantics coverage for background-aware readable states.

## Regressions To Preserve

- Preservation/regression: current `Default`, existing `Cosmic`, and mirrored-cosmic dark backgrounds keep their current readable light foreground appearance unless a later visual spec intentionally changes them.
- Preservation/regression: selecting or viewing background options does not alter media-quality, nearby sharing, identity, contact, message, post, transport, notification, or group state.
- Preservation/regression: app-wide selected-background behavior from spec `82` remains intact: the selected background preference still determines the shared-background visual on current shared-background surfaces.
- Preservation/regression: the Settings background picker remains clear, accessible, and localized while readable colors adapt to background preference.
- Preservation/regression: Feed performance and conversation interaction performance remain within established expectations after readable colors become background-aware.
- Preservation/regression: visual or golden-style evidence for animated backgrounds remains stable by using bounded, deterministic, or reduced-motion states rather than waiting for a looping animation to settle.

Minimum acceptance evidence:

- Unit coverage is required for deriving the readable-color theme and system chrome style from `BackgroundPreference`, including missing and unknown preference fallbacks.
- Unit or widget contrast evidence is required for every minimum readable-color role against its intended dark and representative light effective surfaces.
- Widget coverage is required for Settings, Feed, Conversation, and at least one Group or Orbit surface with both dark and representative light readable themes.
- Integration coverage is required for a Settings background change returning to Feed with the background visual and readable colors in sync.
- Static or reviewed inventory evidence is required for current shared-background surfaces: each foreground, border, surface, glass, scrim, input, and icon color that affects readability is either background-aware or explicitly classified as background-independent with passing contrast.
- Performance integration evidence is required for Feed when background-aware readable colors touch Feed rendering paths, using the concrete frame budgets named in this spec.

Current test gaps:

- No current test proves any `ThemeExtension` readable-color value is derived from `BackgroundPreference`.
- No current test proves foreground colors change when background preference changes.
- No current light-background fixture or representative light-background acceptance exists.
- No current shared-background test checks readable text, icon, surface, border, overlay, or status/system chrome colors.
- No current Settings-to-surface smoke covers foreground readability after a background preference change.
- No current inventory identifies which hard-coded dark-background foreground colors must become background-aware before light backgrounds ship.

# 7. Rollout Result - 2026-04-28

Verdict: `accepted_with_explicit_follow_up`

Implemented:

- Added app-owned `BackgroundReadableColors` as a Flutter `ThemeExtension` with the minimum readable roles named by this spec.
- Added dark and representative light readable profiles, preference/tone resolution, a `BuildContext` accessor, and `SystemUiOverlayStyle` mapping.
- Registered the dark readable profile in `AppTheme.darkTheme`.
- Updated `AmbientBackground` so descendants receive a readable profile from the same selected `BackgroundPreference` used for the visual background.
- Added a test-only representative light fixture path without adding a production light background option.
- Migrated representative Settings header/background picker, Feed empty/loading states, Conversation header, and Orbit helper/loading states to readable roles.

Evidence:

- `flutter test --no-pub test/core/theme/background_readable_colors_test.dart` passed.
- `flutter test --no-pub test/features/identity/presentation/widgets/ambient_background_test.dart` passed.
- `flutter test --no-pub test/features/settings/presentation/widgets/background_choice_control_test.dart test/features/settings/presentation/screens/settings_screen_test.dart test/features/feed/presentation/screens/feed_screen_test.dart test/features/conversation/presentation/widgets/conversation_header_test.dart test/features/orbit/presentation/screens/orbit_screen_loading_test.dart` passed.
- `flutter analyze --no-pub lib/core/theme/background_readable_colors.dart lib/core/theme/app_theme.dart lib/features/identity/presentation/widgets/ambient_background.dart test/core/theme/background_readable_colors_test.dart test/features/identity/presentation/widgets/ambient_background_test.dart` passed.
- `flutter test --no-pub -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/settings_background_choice_smoke_test.dart` passed on the iPhone 17 Pro simulator.
- `flutter test --no-pub -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/feed_performance_test.dart` passed on the iPhone 17 Pro simulator. Feed scroll remained within the named budget: average `2.86ms`, P99 `10.89ms`, worst `19.38ms`; cosmic selected scroll average `1.90ms`, P99 `8.05ms`, worst `8.18ms`; mirrored cosmic selected scroll average `1.65ms`, P99 `7.56ms`, worst `8.66ms`.

Explicit follow-up before shipping a production light background:

- Complete exhaustive static inventory migration/classification for remaining hard-coded foreground, border, surface, glass, scrim, input, icon, dialog, sheet, media picker, message overlay, and loading colors across every shared-background surface.
- Extend Settings-to-surface integration coverage to exercise a real production light background once one exists, including dark-to-light and light-to-dark foreground/background synchronization.
- Add transient overlay coverage for dialogs, sheets, media pickers, and message overlays under the representative light profile or the first production light option.

Reason this can stay accepted with follow-up:

- No production light background option was shipped by this pass.
- Current dark `Default`, `Cosmic`, and mirrored cosmic behavior stays on the dark readable profile.
- The shared readable-color contract, selected-background propagation point, representative light fixture, direct contrast evidence, Settings smoke, and Feed performance evidence are now in place for later light-background rollout work.

## Doc 86 Follow-up Resolution - 2026-04-28

Doc `86` shipped the first production light background option, Daylight Lagoon, through the readable-color contract from this doc. It added real production light-background Settings-to-Feed smoke coverage, representative Settings/Feed/Conversation/Orbit widget coverage with the real Daylight preference, and Feed performance coverage for Daylight Lagoon on Android emulator `emulator-5554`.

The broad follow-up above is now narrowed to release-QA visual/screenshot inventory only if image-level proof is required for every remaining background-sensitive asset. The code-owned readable-color contract, propagation point, and first real light-background integration evidence are no longer open blockers.
