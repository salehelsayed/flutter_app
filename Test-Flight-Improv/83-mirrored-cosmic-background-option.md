# 1. Title and Type

- Title: Mirrored Cosmic Background Option
- Issue type: feature-improvement
- Output doc path: `Test-Flight-Improv/83-mirrored-cosmic-background-option.md`

# 2. Problem Statement

Users should be able to choose the mirrored cosmic background as a third app background option alongside `Default` and the existing `Cosmic` background.

Today the Settings background picker exposes only `Default` and `Cosmic`. A mirrored cosmic Flutter background exists in `Test-Flight-Improv/Background-Feature/cosmic_background_mirrored.dart`, but users cannot select it, save it, reopen Settings with it selected, or see it as the shared app background.

This leaves a provided visual variant unavailable in the personalization flow that already supports app-wide background selection.

# 3. Impact Analysis

- Affected users: users who use the Settings background choice and want a second cosmic visual treatment.
- Affected moments: opening Settings, choosing a background, returning to Feed or another shared-background surface, reopening Settings, and relaunching with a saved background preference.
- Severity: low functional severity because messaging and navigation still work with the existing two backgrounds.
- Product cost: moderate personalization gap because the mirrored visual asset exists but is not part of the selectable background set.
- Frequency: persistent for every user who expects the mirrored cosmic background to be selectable.
- Risk: adding another animated full-screen background increases readability, reduced-motion, animation lifecycle, localization, semantics, persistence, and route-smoke acceptance needs across the existing app-wide background surfaces.

# 4. Current State

- `BackgroundPreference` currently has two values: `defaultBackground` and `cosmic`. They serialize to `default` and `cosmic`, and missing or unknown stored values fall back to `defaultBackground`.
  Evidence: `lib/features/settings/domain/models/background_preference.dart:3-28`.
- The Settings background picker currently renders two options: `Default` and `Cosmic`. Its selected-state logic treats any non-default selected value as the existing cosmic option.
  Evidence: `lib/features/settings/presentation/widgets/background_choice_control.dart:21-101`.
- Current English, German, and Arabic localization keys cover the background section, `Default`, `Cosmic`, selected-state copy, save-failure copy, and the Settings background semantics label. No mirrored cosmic copy exists.
  Evidence: `lib/l10n/app_en.arb:258-266`, `lib/l10n/app_de.arb:258-266`, `lib/l10n/app_ar.arb:258-266`.
- Settings loads the saved background preference, records selection attempts, saves successful changes, updates the app-shell background preference after a successful save, and rolls back visible state on save failure.
  Evidence: `lib/features/settings/presentation/screens/settings_wired.dart:177-240`.
- Settings uses the current background preference as its own full-screen background and renders `BackgroundChoiceControl` inside the Settings content.
  Evidence: `lib/features/settings/presentation/screens/settings_screen.dart:86-193`.
- `AppShellController` stores the in-process selected background preference and notifies listeners only when the value changes.
  Evidence: `lib/features/feed/application/app_shell_controller.dart:6-36`.
- `AmbientBackground` currently switches between the default ambient background and `CosmicBackground`. No current shared-background state represents a mirrored cosmic background.
  Evidence: `lib/features/identity/presentation/widgets/ambient_background.dart:57-70`.
- Current shared-background tests prove `Cosmic` renders on shared-background surfaces, `Default` stays default, disabled animations keep the existing cosmic background static, production code does not import from `Test-Flight-Improv`, and the current shared-background surface inventory uses `AmbientBackground`.
  Evidence: `test/features/identity/presentation/widgets/ambient_background_test.dart:70-186`.
- Existing background preference tests cover serialization, parsing, missing values, unknown values, load, save, and overwrite behavior for `default` and `cosmic` only.
  Evidence: `test/features/settings/application/background_preference_use_cases_test.dart:8-108`.
- Existing Settings picker tests cover two visible options, selected-state icons, tapping `Default` and `Cosmic`, semantics, localization, and failed-save copy for the current two-option picker only.
  Evidence: `test/features/settings/presentation/widgets/background_choice_control_test.dart:30-157`.
- Existing integration smoke covers selecting `Cosmic`, seeing it on Feed, reopening Settings with `Cosmic` selected, switching back to `Default`, and seeing Feed return to default.
  Evidence: `integration_test/settings_background_choice_smoke_test.dart:37-179`.
- The mirrored cosmic background artifact exists only under `Test-Flight-Improv/Background-Feature/`. Its header describes a standalone Flutter port with a deep cosmic radial gradient, swapped teal/violet corners, a wider violet bloom, a pink accent, 70 twinkling stars, and caller-provided child content.
  Evidence: `Test-Flight-Improv/Background-Feature/cosmic_background_mirrored.dart:1-19`, `Test-Flight-Improv/Background-Feature/cosmic_background_mirrored.dart:32-66`.
- The mirrored artifact currently owns a repeating drift controller, starts a stopwatch, and generates random star positions on mount.
  Evidence: `Test-Flight-Improv/Background-Feature/cosmic_background_mirrored.dart:69-99`.
- No production code or current test references `CosmicBackgroundMirrored` or `cosmic_background_mirrored.dart`.
  Evidence: `rg -n "CosmicBackgroundMirrored|cosmic_background_mirrored|mirrored" lib test integration_test Test-Flight-Improv/Background-Feature`.

# 5. Scope Clarification

In scope:

- Settings presents three user-selectable background options: `Default`, existing `Cosmic`, and mirrored cosmic.
- A user can select mirrored cosmic, see that option clearly selected, leave Settings, return, and still see it selected after a successful save.
- A user with mirrored cosmic selected sees the mirrored cosmic treatment on the same shared-background surfaces that already honor app-wide selected background behavior.
- A user can switch from mirrored cosmic back to `Default` or existing `Cosmic`, and the visible background follows the latest successfully saved selection.
- Missing or unknown stored background values still resolve to `Default`.
- Failed mirrored-background saves remain honest: Settings must not claim a mirrored selection that the rest of the app will not use.
- Existing `Default` and existing `Cosmic` behavior remain available and recognizable.
- The mirrored background remains behind screen content and does not block navigation, Settings controls, Feed cards, chat content, group screens, QR display, share picker, onboarding, or overlays.
- The mirrored background respects the same app-level accessibility expectations as the existing background choices: readable content, accessible selected state, meaningful localized labels, and reduced-motion acceptance.
- The mirrored visual is treated as product-owned app behavior at runtime; production app behavior must not depend on importing a widget directly from `Test-Flight-Improv/`.
- Acceptance may use a combination of unit, widget, integration, smoke, simulator, visual, and performance evidence when justified by the user-visible risk.

Non-goals:

- Adding more than one new background option.
- Removing or renaming the existing `Default` or `Cosmic` options.
- Introducing per-screen, per-chat, per-group, per-post, or contact-specific backgrounds.
- Syncing the background preference across devices, relays, backups, identities, or accounts.
- Redesigning Settings, Feed, Conversation, Posts, Orbit, Share, QR, onboarding, or group content beyond the added selectable background.
- Changing message, post, notification, transport, group, media-quality, nearby-sharing, identity, or recovery behavior.
- Defining a new visual design beyond the provided mirrored cosmic artifact and necessary product acceptance constraints.
- Requiring identical star placement across separate mounts or app launches.

Accepted ambiguities to leave open for the later implementation pass:

- The final user-facing option label, as long as users can distinguish it from the existing `Cosmic` option.
- The final stored identifier, as long as a shipped mirrored-background value remains compatible and unknown values continue to fall back to `Default`.
- The exact preview treatment in the Settings picker, if any.
- The exact visual tolerance for mirrored bloom placement, star distribution, and animation timing, as long as the mirrored treatment is recognizable and content remains readable.
- The exact representative route set for smoke coverage, as long as it includes Settings plus at least one shared-background surface and the inventory continues to account for the remaining surfaces.

# 6. Test Cases

## Happy Path

- A user opens Settings with no saved background preference and sees three background options, with `Default` selected.
  Acceptance evidence: widget or integration coverage for option visibility and selected state.
- A user selects mirrored cosmic in Settings and immediately sees the mirrored option selected without ambiguity against the existing `Cosmic` option.
  Acceptance evidence: widget or integration coverage for the three-option selected state.
- A user selects mirrored cosmic, leaves Settings, reopens Settings, and sees mirrored cosmic still selected.
  Acceptance evidence: unit or integration coverage that a saved mirrored preference loads back into visible Settings state.
- A user selects mirrored cosmic, returns to Feed, and sees the mirrored cosmic treatment behind Feed content.
  Acceptance evidence: integration, smoke, or simulator coverage for the Settings-to-Feed journey.
- A user with mirrored cosmic selected opens a representative non-Feed shared-background surface and sees the mirrored cosmic treatment there too.
  Acceptance evidence: widget, integration, smoke, or simulator coverage for at least one non-Feed shared-background surface.
- A user switches from mirrored cosmic to existing `Cosmic` and sees the existing cosmic treatment, not the mirrored treatment.
  Acceptance evidence: widget, visual, or integration coverage that both cosmic variants remain distinguishable.
- A user switches from mirrored cosmic to `Default` and sees the original default ambient background again.
  Acceptance evidence: widget or integration coverage that all three choices produce the expected visible selected background.

## Edge Cases

- A missing stored background preference shows `Default` selected and does not show mirrored cosmic by mistake.
  Existing partial coverage: current unit tests cover missing values for the two-option model.
  Acceptance evidence: unit or widget coverage for the expanded three-option model.
- An unrecognized stored background value shows `Default` selected and does not break Settings or shared-background rendering.
  Existing partial coverage: current unit tests cover unknown values for the two-option model.
  Acceptance evidence: unit or widget coverage for unknown values after the mirrored option exists.
- A stored mirrored-background value survives reload and app-shell propagation without becoming existing `Cosmic` or `Default`.
  Acceptance evidence: unit or integration coverage for persistence and visible selected state.
- If saving mirrored cosmic fails, Settings returns to the last confirmed saved background or shows a recoverable failure state and does not leave the rest of the app on a different claimed background.
  Existing partial coverage: current Settings tests cover failed-save behavior for the existing picker.
  Acceptance evidence: widget or integration coverage for failed saves when the mirrored option is selected.
- Rapidly switching among `Default`, existing `Cosmic`, and mirrored cosmic does not crash, freeze, flash a blank background, stack duplicate animated layers, or leave selected-state indicators inconsistent.
  Acceptance evidence: widget or integration coverage for rapid three-option switching.
- With platform reduced-motion or disabled-animation preference active, mirrored cosmic remains recognizable and readable without continuous drift or twinkle motion.
  Existing partial coverage: current shared-background tests cover disabled animations for existing `Cosmic`.
  Acceptance evidence: widget, integration, or simulator coverage for mirrored cosmic reduced-motion state.
- Localized Settings builds for Arabic, German, and English show meaningful mirrored-background labels and selected-state copy instead of raw keys or blank text.
  Existing partial coverage: current picker tests cover localized `Default` and `Cosmic` copy.
  Acceptance evidence: widget or integration localization coverage for the third option.
- Assistive technologies can identify the background setting, all three options, and the selected option without relying only on color or position.
  Existing partial coverage: current picker tests cover semantics for the two-option picker.
  Acceptance evidence: widget or integration semantics coverage for the three-option picker.
- Mirrored cosmic remains readable behind representative content states: empty Feed, populated Feed, Settings, chat surfaces, group surfaces, onboarding, QR display, share picker, and overlays.
  Acceptance evidence: representative widget, visual, smoke, or simulator coverage across surface categories.
- Feed scrolling and common interactions remain within established expectations with mirrored cosmic selected.
  Existing partial coverage: Feed performance coverage exists for the current background choices.
  Acceptance evidence: performance, integration, or simulator coverage with mirrored cosmic selected.

## Regressions To Preserve

- Preservation/regression: users who never select a non-default background continue to see the existing default ambient treatment.
  Existing partial coverage: current default `AmbientBackground` and Settings smoke tests cover default behavior.
- Preservation/regression: existing `Cosmic` remains selectable, persists as `cosmic`, renders the existing cosmic visual, honors reduced motion, and stays distinguishable from mirrored cosmic.
  Existing partial coverage: current preference, picker, shared-background, and smoke tests cover existing `Cosmic`.
- Preservation/regression: the Settings background picker remains clear, localized, and accessible after moving from two options to three.
  Existing partial coverage: current picker tests cover two-option copy, selected state, and semantics.
- Preservation/regression: failed-save handling and background preference telemetry remain non-sensitive and accurately distinguish attempt, success, and failure outcomes.
  Existing partial coverage: current Settings wired tests cover background save success and failure events.
- Preservation/regression: choosing or viewing background options does not alter media-quality, nearby sharing, identity, contact, message, post, transport, notification, or group state.
  Existing partial coverage: adjacent Settings and flow tests cover these surfaces independently.
- Preservation/regression: the shared-background surface inventory remains accounted for when another background option is added.
  Existing partial coverage: current shared-background inventory test lists Feed, Conversation, Posts, Settings, Orbit, Share Target Picker, QR Display, First Time Experience, Identity Choice, Create Group Picker, Contact Picker, Group List, Group Conversation, and Group Info.
- Preservation/regression: production app behavior does not import runtime background widgets directly from `Test-Flight-Improv/`.
  Existing partial coverage: current shared-background tests reject production imports from `Test-Flight-Improv`.

Current test gaps:

- No current saved preference behavior or persistence test represents mirrored cosmic.
- No current Settings picker test can find or select a third background option.
- No current localization or semantics coverage exists for a mirrored-background option.
- No current production shared-background behavior renders mirrored cosmic.
- No current smoke confirms selecting mirrored cosmic in Settings and seeing it on Feed or another shared-background surface.
- No current reduced-motion, visual, or performance evidence covers the mirrored cosmic treatment.

# 7. Completion Evidence - April 28, 2026

Final verdict: `closed`.

The rollout implemented the mirrored cosmic background option as product-owned app behavior:

- `BackgroundPreference.cosmicMirrored` stores as `cosmic_mirrored`, reloads from secure storage, overwrites existing values, and preserves null/unknown fallback to `defaultBackground`.
- Settings now renders three localized options: `Default`, `Cosmic`, and `Mirrored cosmic`, with distinct selected icons, selected semantics, and tap callbacks.
- English, German, and Arabic localization output includes mirrored option label, description, and selected-state copy.
- `CosmicBackgroundMirrored` now lives under `lib/features/identity/presentation/widgets/` and follows the production cosmic lifecycle with deterministic stars, reduced-motion static paint, repaint boundaries, and stable root/painter keys.
- `AmbientBackground` maps default, existing cosmic, and mirrored cosmic to distinct treatments without importing runtime widgets from `Test-Flight-Improv/`.

Acceptance evidence:

- Passed: `flutter test test/features/settings/application/background_preference_use_cases_test.dart test/features/settings/presentation/widgets/background_choice_control_test.dart test/features/posts/phase1/app_shell_controller_test.dart test/features/identity/presentation/widgets/ambient_background_test.dart test/features/feed/presentation/screens/feed_screen_test.dart test/features/conversation/presentation/screens/conversation_screen_test.dart`
- Passed: `flutter test integration_test/settings_background_choice_smoke_test.dart -d macos`
  - Covered Feed -> Settings -> Mirrored cosmic -> Feed -> reopen Settings -> existing `Cosmic` -> Feed -> `Default` restore.
  - The macOS runner emitted `Failed to foreground app; open returned 1`, but the test completed green.
- Passed: `flutter test integration_test/feed_performance_test.dart -d macos`
  - Existing cosmic default baseline Avg/P90/P99/Worst: `2.31/3.45/8.67/13.17ms`.
  - Existing cosmic scroll Avg/P90/P99/Worst: `2.08/4.54/8.57/11.45ms`.
  - Mirrored cosmic default baseline Avg/P90/P99/Worst: `2.00/3.30/7.23/7.45ms`.
  - Mirrored cosmic scroll Avg/P90/P99/Worst: `1.85/3.43/7.67/10.87ms`.

Residual-only follow-up:

- Mobile-device and heavy Conversation-specific performance validation remains optional release-confidence evidence. The macOS direct, smoke, and performance evidence above closes the implementation and acceptance scope for this doc.
