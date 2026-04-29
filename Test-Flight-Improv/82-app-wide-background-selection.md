# 1. Title and Type

- Title: App-Wide Background Selection
- Issue type: feature-improvement
- Output doc path: `Test-Flight-Improv/82-app-wide-background-selection.md`

# 2. Problem Statement

Users expect the background they choose in Settings to become their app background, not only the Feed background.

Today the app has a background preference with `Default` and `Cosmic`, but the current cosmic behavior is Feed-only. Other shared-background screens continue to show the default background even when `Cosmic` is the saved selection.

This makes the Settings background choice feel inconsistent: the selected option appears to be a Feed-specific preference even though it is presented as an app background.

# 3. Impact Analysis

- Affected users: users who select a non-default background in Settings.
- Affected moments: navigating from Feed to Conversation, Posts, Settings, Orbit, QR display, share target picker, onboarding, group screens, and any other surface that uses the shared app background.
- Severity: moderate UX inconsistency because the selected background does not follow the user across the app.
- Frequency: persistent after a user selects `Cosmic`; every non-Feed shared-background surface shows a different background than the selected preference.
- Risk: app-wide application broadens visual, readability, reduced-motion, animation-lifecycle, and performance exposure beyond Feed.

# 4. Current State

- `BackgroundPreference` currently contains `defaultBackground` and `cosmic`; it serializes `cosmic` to the stored value `cosmic`, and missing or unknown values still fall back to `defaultBackground`.
  Evidence: `lib/features/settings/domain/models/background_preference.dart:1-29`.
- Settings already exposes both `Default` and `Cosmic` in the background picker and reports selected state through visible and semantic labels.
  Evidence: `lib/features/settings/presentation/widgets/background_choice_control.dart:20-120`, `lib/l10n/app_en.arb:258-266`.
- Settings background changes currently emit background preference attempt, saved, and save-error flow events from the selection flow.
  Evidence: `lib/features/settings/presentation/screens/settings_wired.dart:186-229`, `test/features/settings/presentation/screens/settings_wired_test.dart:530-621`.
- Feed receives a `backgroundPreference`, passes it to `AmbientBackground`, and marks itself as the Feed surface.
  Evidence: `lib/features/feed/presentation/screens/feed_screen.dart:127-141`, `lib/features/feed/presentation/screens/feed_wired.dart:556-561`, `lib/features/feed/presentation/screens/feed_wired.dart:3002-3044`.
- `AmbientBackground` currently renders `CosmicBackground` only when the preference is `cosmic` and the surface is marked as Feed; otherwise it falls back to the default ambient background.
  Evidence: `lib/features/identity/presentation/widgets/ambient_background.dart:8-18`, `lib/features/identity/presentation/widgets/ambient_background.dart:57-78`.
- The current `AmbientBackground` widget test asserts the Feed-only behavior by expecting cosmic on Feed and default on non-Feed surfaces with a cosmic preference.
  Evidence: `test/features/identity/presentation/widgets/ambient_background_test.dart:70-122`.
- That Feed-only preference matrix is current behavior, not the desired behavior for this spec; app-wide selection supersedes the older Feed-only expectation.
  Evidence: `test/features/identity/presentation/widgets/ambient_background_test.dart:70-122`, `Test-Flight-Improv/81-feed-cosmic-background-option.md:60-88`.
- Settings currently wraps itself in `AmbientBackground` with `defaultBackground`, so Settings does not visually reflect a saved `Cosmic` preference as a full-screen background.
  Evidence: `lib/features/settings/presentation/screens/settings_screen.dart:81-88`.
- Current shared-background surfaces include Feed, Conversation, Posts, Settings, Orbit, Share Target Picker, QR Display, First Time Experience, Identity Choice, Create Group Picker, Contact Picker, Group List, Group Conversation, and Group Info.
  Evidence: `test/features/identity/presentation/widgets/ambient_background_test.dart:166-188`, `lib/features/feed/presentation/screens/feed_screen.dart:138`, `lib/features/conversation/presentation/screens/conversation_screen.dart:244`, `lib/features/posts/presentation/screens/posts_screen.dart:62`, `lib/features/settings/presentation/screens/settings_screen.dart:86`, `lib/features/orbit/presentation/screens/orbit_screen.dart:316`, `lib/features/share/presentation/screens/share_target_picker_screen.dart:112`, `lib/features/qr_code/presentation/screens/qr_display_screen.dart:102`, `lib/features/home/presentation/screens/first_time_experience_screen.dart:126`, `lib/features/identity/presentation/screens/identity_choice_screen.dart:114`, `lib/features/groups/presentation/screens/create_group_picker_screen.dart:83`, `lib/features/groups/presentation/screens/contact_picker_screen.dart:67`, `lib/features/groups/presentation/screens/group_list_screen.dart:43`, `lib/features/groups/presentation/screens/group_conversation_screen.dart:144`, `lib/features/groups/presentation/screens/group_info_screen.dart:52`.
- The prior Feed cosmic spec explicitly scoped cosmic to Feed and out of non-Feed surfaces. This spec supersedes that surface limitation.
  Evidence: `Test-Flight-Improv/81-feed-cosmic-background-option.md:60-88`, `Test-Flight-Improv/81-feed-cosmic-background-option.md:142-167`.

# 5. Scope Clarification

In scope:

- The selected background preference applies to every current shared-background surface that uses `AmbientBackground`.
- Selecting `Cosmic` in Settings makes `Cosmic` visible on Feed, Conversation, Posts, Settings, Orbit, Share Target Picker, QR Display, First Time Experience, Identity Choice, Create Group Picker, Contact Picker, Group List, Group Conversation, and Group Info.
- Shared-background visibility is determined by the selected background preference, not by whether the current screen is Feed.
- Settings itself is a shared-background surface: reopening Settings with `Cosmic` selected shows the full Settings screen on the cosmic background while keeping the picker readable and the selected state clear.
- While the user is in Settings, a successful background selection updates the Settings full-screen background in the same Settings session; the user does not need to leave and reopen Settings to see the selected background there.
- Selecting `Default` in Settings restores the existing default ambient background on all shared-background surfaces.
- Missing or unknown stored background values still resolve to `Default` everywhere.
- Reopening Settings after any successful background selection shows the saved option selected.
- Returning from Settings to an already-mounted route reflects the selected background without requiring app restart.
- Pre-identity and first-time surfaces reflect a stored valid preference when one exists; users with no stored preference still see `Default`.
- Example pre-identity path: a user selects `Cosmic`, later deletes or resets identity without wiping the local background preference, and returns to Identity Choice or First Time Experience.
- Shared-background screens added later inherit the selected background unless a future spec explicitly excludes that surface.
- `Cosmic` readability, reduced-motion behavior, animation lifecycle, and visual acceptance apply across the shared-background surfaces, not only Feed.
- `Cosmic` star fields may regenerate per surface and per remount; visible star-position differences while navigating are accepted as long as the transition does not flash blank, stack duplicate backgrounds, or produce lifecycle errors.
- Dialogs, bottom sheets, and overlays opened over a selected background keep their existing modal, scrim, and surface behavior; they are not separate background surfaces, and their content remains readable over the underlying selected background.
- Background flow telemetry remains tied to selection attempt, successful save, and failed save; app-wide application does not require per-surface render or apply flow events.
- Acceptance may use shared-background widget coverage plus representative route/smoke coverage and call-site inventory; it does not require one full route smoke test per surface.
- Inventory acceptance means an auditable list of every current shared-background surface named in this spec, with each surface marked as covered by selected-background behavior or intentionally excluded by a later spec.

Non-goals:

- Adding background options beyond `Default` and `Cosmic`.
- Introducing per-screen, per-chat, per-group, per-post, or contact-specific backgrounds.
- Applying background choices to screens or modals that do not use the shared `AmbientBackground` surface.
- Adding new modal, dialog, bottom-sheet, or overlay background designs.
- Redesigning non-background content, navigation, chat/message behavior, posts behavior, group behavior, onboarding copy, or Settings layout.
- Syncing or restoring the background preference through identity restore, relay state, contacts, backup, or cross-device account state.
- Adding new app locales beyond Arabic, German, and English.

Accepted ambiguities to leave open:

- For non-Settings surfaces already mounted underneath Settings, whether the hidden route updates immediately or when it next becomes visible can stay open, as long as returning from Settings to that route reflects the selected background.
- The exact route set used for representative smoke coverage, as long as it includes Feed plus at least one non-Feed shared-background surface and the inventory proves the remaining surfaces use the shared path.
- The exact visual or golden tolerance for cosmic animation, star placement, and bloom drift across surfaces, as long as the selected background is recognizable and content remains readable.
- The exact reduced-motion visual treatment for cosmic, as long as continuous drift or twinkle motion stops when platform reduced-motion or disabled-animation preference is active.

# 6. Test Cases

## Happy Path

- A user selects `Cosmic` in Settings, returns to Feed, and sees the cosmic background.
  Acceptance evidence: integration or simulator coverage for the Settings-to-Feed journey.
- A user selects `Cosmic` in Settings and, after the successful selection, sees the Settings full-screen background change to cosmic without leaving Settings.
  Acceptance evidence: widget or integration coverage for live Settings background feedback after successful selection.
- A user with `Cosmic` selected opens Settings again and sees the full Settings screen on the cosmic background, with `Cosmic` selected and the picker still readable.
  Acceptance evidence: widget or integration coverage for Settings selected state, full-screen visible background, and picker readability.
- A user with `Cosmic` selected opens a representative non-Feed shared-background screen and sees the cosmic background there too.
  Acceptance evidence: widget, integration, smoke, or simulator coverage for at least one non-Feed surface.
- A user changes the selection back to `Default` and sees the default ambient background across Feed and representative non-Feed shared-background screens.
  Acceptance evidence: integration or widget coverage for both selected options.
- Every current shared-background surface is accounted for by an auditable inventory that confirms it participates in the selected-background path or records an intentional exclusion in a later spec.
  Acceptance evidence: static or reviewed inventory listing all shared-background surfaces named by this spec.

## Edge Cases

- A missing stored background preference shows `Default` on all shared-background surfaces.
  Acceptance evidence: unit or widget coverage for missing preference behavior.
- An unknown stored background preference shows `Default` on all shared-background surfaces and does not break navigation.
  Acceptance evidence: unit or widget coverage for unknown preference behavior.
- A stored `Cosmic` preference is reflected on Identity Choice and First Time Experience when those surfaces appear after a prior valid selection.
  Acceptance evidence: widget, integration, or smoke coverage for pre-identity/first-time surfaces with a stored valid preference.
- A stored `Cosmic` preference is reflected on Identity Choice or First Time Experience after the user previously selected `Cosmic` and later returns to onboarding without wiping local background preference storage.
  Acceptance evidence: widget, integration, or smoke coverage for that pre-identity reachability path.
- If saving a changed background selection fails, Settings does not claim a selected background that the rest of the app will not use; the user remains on the last successfully saved background or sees a recoverable failure state.
  Acceptance evidence: widget or integration coverage for failed-save behavior and the resulting selected background across representative surfaces.
- After reinstall or any local secure-store wipe, the missing background preference resolves to `Default` across all shared-background surfaces.
  Acceptance evidence: unit, widget, or integration coverage for wiped or missing local preference state.
- Rapidly switching between `Default` and `Cosmic` in Settings does not crash, freeze, leak visible duplicate animated layers, or leave different shared-background surfaces on different selected backgrounds.
  Acceptance evidence: widget or integration coverage of rapid selection changes plus representative navigation.
- Rapid navigation across shared-background surfaces with `Cosmic` selected does not crash, report animation lifecycle or ticker-disposal errors, leave orphaned animated background activity, or show stacked duplicate background layers; cosmic star fields may differ between surfaces or remounts.
  Acceptance evidence: widget, integration, smoke, or simulator coverage that mounts and disposes multiple shared-background surfaces in quick succession with `Cosmic` selected.
- With platform reduced-motion or disabled-animation preference active, `Cosmic` remains recognizable and readable across representative shared-background surfaces without continuous drift or twinkle motion.
  Acceptance evidence: widget, integration, or simulator coverage for reduced-motion state.
- Localized Settings builds for Arabic, German, and English still show meaningful background option labels and selected-state copy after the selection becomes app-wide.
  Acceptance evidence: static, widget, or integration localization coverage.
- The background picker remains accessible: assistive technologies can identify `Default`, `Cosmic`, and the selected option without relying only on color or position.
  Acceptance evidence: widget or integration semantics coverage.

## Regressions To Preserve

- Preservation/regression: users who never select `Cosmic` continue to see the existing default ambient background on every shared-background surface.
  Acceptance evidence: shared default-background coverage plus representative route/smoke coverage.
- Preservation/regression: the unchanged `Default` background remains visually recognizable as the existing ambient treatment, not merely a non-crashing fallback.
  Acceptance evidence: stable visual or golden-style coverage for the default background on representative shared-background surfaces.
- Preservation/regression: Feed, Conversation, Posts, Settings, Orbit, QR display, share target picker, onboarding, and group flows remain readable and usable with `Cosmic` selected.
  Acceptance evidence: representative widget, smoke, visual, golden-style, or simulator coverage across surface categories.
- Preservation/regression: choosing or viewing the background setting does not alter media-quality, nearby sharing, identity, contact, message, post, transport, notification, or group state.
  Acceptance evidence: existing adjacent preference and flow tests continue to pass.
- Preservation/regression: Feed performance remains within established expectations with `Cosmic` selected, and broad app navigation does not introduce visible background-related jank.
  Acceptance evidence: existing Feed performance coverage with `Cosmic`, plus representative smoke coverage for non-Feed navigation.
- Preservation/regression: Conversation performance remains within established expectations with `Cosmic` selected during message-list interaction and compose/typing activity.
  Acceptance evidence: Conversation performance coverage with `Cosmic` selected, or equivalent heavy non-Feed chat-surface performance evidence.
- Preservation/regression: opening dialogs, sheets, message context overlays, or other existing overlays on top of a `Cosmic` surface keeps overlay content readable and does not introduce a second independent background layer.
  Acceptance evidence: representative overlay readability coverage on a `Cosmic` shared-background surface.
- Preservation/regression: visual or golden-style coverage for animated backgrounds uses a stable bounded frame, deterministic visual state, or reduced-motion state rather than waiting for a looping animation to settle.
  Acceptance evidence: visual/golden-style coverage that is stable across runs.

## Recommended QA Bar

- Unit coverage for background preference parsing and serialization: missing, `default`, `cosmic`, and unknown values.
- Shared-background coverage that `Cosmic` is visible on the current shared-background surfaces when the selected preference is `cosmic`.
- Shared-background coverage that `Default` is visible on the current shared-background surfaces when the selected preference is missing, unknown, or `default`.
- Widget or integration coverage that Settings shows both options, persists `Cosmic`, reopens with `Cosmic` selected, and then persists `Default`.
- Widget or integration coverage that Settings itself uses the selected full-screen background while the picker remains readable.
- Widget or integration coverage that Settings changes its own full-screen background during the active Settings session after a successful selection.
- Widget or integration coverage for failed background-save behavior that avoids inconsistent selected state between Settings and other shared-background surfaces.
- Integration or simulator coverage for Settings selecting `Cosmic`, returning to an already-mounted route, and seeing the selected background reflected.
- Widget, smoke, or simulator coverage for rapid navigation across multiple shared-background surfaces with `Cosmic` selected, including clean disposal of animated background activity.
- Representative non-Feed route smoke coverage with `Cosmic` selected.
- Conversation or equivalent heavy non-Feed chat-surface performance coverage with `Cosmic` selected.
- Representative overlay readability coverage with `Cosmic` selected.
- Static or reviewed inventory for all current shared-background surfaces, listing each covered or intentionally excluded surface.
- Reduced-motion coverage for `Cosmic` on representative shared-background surfaces.
- Readability/visual coverage for representative surface categories: Feed/list, Conversation/chat, Posts/social, Settings/preferences, onboarding/pre-identity, and Groups.
- Flow telemetry coverage for selection attempt, success, and failed-save outcomes after the selection becomes app-wide; no per-surface render/apply telemetry is expected.
- Localization and semantics coverage for Arabic, German, and English background picker copy.

## Current Test Gaps

- Current `AmbientBackground` tests assert Feed-only cosmic behavior rather than app-wide selected-background behavior.
- Current Feed-flag-by-preference truth-table coverage is obsolete under this spec and needs replacement with app-wide selected-background coverage.
- Current Settings code renders its own background as `Default` even when `Cosmic` is selected.
- Current non-Feed shared-background surfaces do not observe the saved background preference.
- No current test proves that `Cosmic` appears on Conversation, Posts, Settings, Orbit, QR display, share target picker, onboarding, or group screens.
- No current test proves pre-identity or first-time surfaces reflect a stored valid non-default preference.
- No current app-wide smoke confirms that returning from Settings keeps all shared-background surfaces consistent with the selected background.
- No current lifecycle stress coverage proves rapid navigation across several shared-background surfaces with `Cosmic` selected cleans up animated background activity without errors.
- No current performance coverage proves a heavy non-Feed chat surface remains within expectations with `Cosmic` selected.
- No current overlay coverage proves dialogs, sheets, or message context overlays remain readable over `Cosmic`.

# 7. Implementation Closure

Status as of April 28, 2026: `accepted_with_explicit_follow_up`.

Implemented:

- `AmbientBackground` now renders `CosmicBackground` for `BackgroundPreference.cosmic` on any shared-background surface, not only Feed.
- `AppShellController` owns the in-process selected background preference and notifies mounted app-shell routes on real changes.
- Settings loads the saved preference into the shared controller, uses the selected preference for its own full-screen background, updates that background after successful saves, and leaves failed saves honest.
- The selected preference is threaded into the current shared-background surfaces named by this spec: Feed, Conversation, Posts, Settings, Orbit, Share Target Picker, QR Display, First Time Experience, Identity Choice, Create Group Picker, Contact Picker, Group List, Group Conversation, and Group Info.
- Startup/pre-identity routing seeds the shared controller from secure storage before deciding whether to show Identity Choice, First Time Experience, share target picker, or Feed.

Accepted evidence:

- `flutter test test/features/identity/presentation/widgets/ambient_background_test.dart`
- `flutter test test/features/settings/application/background_preference_use_cases_test.dart`
- `flutter test test/features/posts/phase1/app_shell_controller_test.dart`
- `flutter test test/features/settings/presentation/widgets/background_choice_control_test.dart`
- `flutter test test/features/settings/presentation/screens/settings_screen_test.dart`
- `flutter test test/features/settings/presentation/screens/settings_wired_test.dart`
- `flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name "background preference"`
- `flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `flutter test test/features/home/presentation/screens/first_time_experience_screen_test.dart`
- `flutter test test/features/identity/presentation/screens/identity_choice_screen_test.dart`
- `flutter test test/features/posts/phase1/posts_screen_test.dart`
- `flutter test integration_test/settings_background_choice_smoke_test.dart -d macos`
- `flutter test integration_test/feed_performance_test.dart -d macos`

Analyzer status:

- `flutter analyze` completed with existing repo-wide lint/warning debt and exited nonzero with `1706 issues found`.
- A narrowed touched-file analyzer pass reported no implementation errors, but still exited nonzero because touched files already contain warnings/infos such as deprecated `withOpacity`, existing group nullability warnings, and unused imports in `main.dart`.

Explicit follow-up:

- Run device-backed mobile smoke/performance on a chosen iOS or Android target for the same Settings background journey.
- Add or run heavy Conversation-specific performance evidence with `Cosmic` selected if release confidence requires a non-Feed chat performance number beyond the passing Conversation widget suite.
