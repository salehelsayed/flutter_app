# 1. Title and Type

- Title: Settings Background Choice
- Issue type: feature-improvement
- Output doc path: `Test-Flight-Improv/80-settings-background-choice.md`

# 2. Problem Statement

Users need a place in Settings to choose the app background they want to use. Today the app shows one ambient background everywhere, but Settings does not expose it as a user-selectable preference.

This makes the current background feel fixed rather than intentional. It also leaves no user-visible home for future background options once additional backgrounds are introduced.

# 3. Impact Analysis

- Affected users: any user who wants to personalize the app's visual background.
- Affected moments: opening Settings, returning to any app surface that uses the shared background, and expecting visual preferences to persist across sessions.
- Severity: low functional severity because core messaging, posts, recovery, and profile flows still work.
- Product cost: moderate UX limitation because personalization is absent from the one screen where users already manage preferences.
- Frequency: persistent for all users; there is currently no settings path for background choice.

# 4. Current State

- `SettingsScreen` is the visible Settings surface. It wraps the screen in `AmbientBackground` and renders profile, peer ID, photo quality, video quality, nearby sharing, recovery phrase, and optional debug content, but no background or appearance choice is visible.
  Evidence: `lib/features/settings/presentation/screens/settings_screen.dart:15-19`, `lib/features/settings/presentation/screens/settings_screen.dart:78-80`, `lib/features/settings/presentation/screens/settings_screen.dart:164-218`.
- `SettingsWired` loads Settings state for identity, photo quality, video quality, and nearby sharing. Its build path passes those values into `SettingsScreen`; there is no current background-selection state in this Settings flow.
  Evidence: `lib/features/settings/presentation/screens/settings_wired.dart:82-90`, `lib/features/settings/presentation/screens/settings_wired.dart:162-194`, `lib/features/settings/presentation/screens/settings_wired.dart:418-453`.
- Feed opens Settings by pushing a Settings route over the existing Feed route. When Settings closes, Feed remains the route underneath and currently refreshes identity plus media-quality preferences, but there is no current background-selection return behavior.
  Evidence: `lib/features/feed/presentation/screens/feed_wired.dart:2519-2543`, `lib/features/settings/presentation/screens/settings_wired.dart:414-455`.
- The shared secure key-value API exposes asynchronous writes that can fail like any async storage operation. Existing Settings media-quality changes update visible state before awaiting the secure-storage write; no background-specific failed-save behavior exists today.
  Evidence: `lib/core/secure_storage/secure_key_store.dart:6-10`, `lib/features/settings/presentation/screens/settings_wired.dart:171-194`.
- Production secure preference storage is local platform storage backed by iOS Keychain or Android EncryptedSharedPreferences. Existing preference loaders treat missing stored values as defaults.
  Evidence: `lib/core/secure_storage/flutter_secure_key_store.dart:7-24`, `lib/features/settings/application/image_quality_preference_use_cases.dart:4-12`, `lib/features/settings/application/image_quality_preference_use_cases.dart:25-33`.
- The app has shared flow-event instrumentation and Settings already emits flow events for screen initialization, load errors, username updates, username errors, and avatar-pick errors. There is no current background-selection telemetry because the background-selection flow does not exist.
  Evidence: `lib/core/utils/flow_event_emitter.dart:1-27`, `lib/features/settings/presentation/screens/settings_wired.dart:82-115`, `lib/features/settings/presentation/screens/settings_wired.dart:320-397`.
- Existing Settings preference behavior already includes persisted media-quality choices from Settings, with storage parsing that falls back to a default value for missing or unknown stored values.
  Evidence: `lib/features/settings/application/image_quality_preference_use_cases.dart:4-22`, `lib/features/settings/application/image_quality_preference_use_cases.dart:25-45`, `lib/features/settings/domain/models/image_quality_preference.dart:7-23`.
- The current shared background widget has one visible look: a black base with animated green and red glow elements. It accepts only a child widget, so there is no user-facing variant exposed today.
  Evidence: `lib/features/identity/presentation/widgets/ambient_background.dart:5-12`, `lib/features/identity/presentation/widgets/ambient_background.dart:38-96`.
- The current shared background animation is stateful: `AmbientBackground` owns an `AnimationController`, repeats it on an 8-second loop, and disposes it with the widget state.
  Evidence: `lib/features/identity/presentation/widgets/ambient_background.dart:18-34`, `lib/features/identity/presentation/widgets/ambient_background.dart:44-94`.
- Excluding the widget constructor itself, `AmbientBackground` currently appears on 14 screen surfaces: Feed, Conversation, Posts, Settings, Orbit, Share Target Picker, QR Display, First Time Experience, Identity Choice, Create Group Picker, Contact Picker, Group List, Group Conversation, and Group Info.
  Evidence: `lib/features/feed/presentation/screens/feed_screen.dart:135`, `lib/features/conversation/presentation/screens/conversation_screen.dart:244`, `lib/features/posts/presentation/screens/posts_screen.dart:62`, `lib/features/settings/presentation/screens/settings_screen.dart:78`, `lib/features/orbit/presentation/screens/orbit_screen.dart:316`, `lib/features/share/presentation/screens/share_target_picker_screen.dart:112`, `lib/features/qr_code/presentation/screens/qr_display_screen.dart:102`, `lib/features/home/presentation/screens/first_time_experience_screen.dart:126`, `lib/features/identity/presentation/screens/identity_choice_screen.dart:114`, `lib/features/groups/presentation/screens/create_group_picker_screen.dart:83`, `lib/features/groups/presentation/screens/contact_picker_screen.dart:67`, `lib/features/groups/presentation/screens/group_list_screen.dart:43`, `lib/features/groups/presentation/screens/group_conversation_screen.dart:144`, `lib/features/groups/presentation/screens/group_info_screen.dart:52`.
- `IdentityChoice` is reached when startup finds no identity, and it already renders `AmbientBackground` before the user has created an identity or reached Settings.
  Evidence: `lib/features/identity/application/startup_decision.dart:34-43`, `lib/features/identity/presentation/startup_router.dart:404-467`, `lib/features/identity/presentation/screens/identity_choice_screen.dart:112-115`.
- `FirstTimeExperience` is reached for users with an identity and no contacts, and also after identity generation succeeds. It also renders `AmbientBackground` before the user has normally had a chance to choose a background in Settings.
  Evidence: `lib/features/identity/application/startup_decision.dart:45-60`, `lib/features/identity/presentation/startup_router.dart:362-401`, `lib/features/identity/presentation/startup_router.dart:418-459`, `lib/features/identity/application/generate_identity_use_case.dart:158-168`, `lib/features/home/presentation/screens/first_time_experience_screen.dart:126-127`.
- Localized Settings copy exists for current preference controls such as Photo Quality, Video Quality, and nearby sharing. The generated localization configuration uses `app_en.arb` as the template and currently supports Arabic, German, and English via `app_ar.arb`, `app_de.arb`, and `app_en.arb`; no current localized background-choice copy appears in those Settings strings.
  Evidence: `l10n.yaml:1-3`, `lib/l10n/app_localizations.dart:97-100`, `lib/l10n/app_en.arb:257-262`, `lib/l10n/app_en.arb:326-330`, `lib/l10n/app_de.arb:258-326`, `lib/l10n/app_ar.arb:258-326`.
- Existing Settings tests cover title rendering, back navigation, profile/peer/recovery visibility, the bottom navigation bar, media-quality toggles, and persisted video quality loading. They do not cover background selection.
  Evidence: `test/features/settings/presentation/screens/settings_screen_test.dart:31-90`, `test/features/settings/presentation/screens/settings_wired_test.dart:410-455`.
- Existing repo-local references use visual or golden-style proof for UI-shell visual regressions when appearance, not just behavior, is the risk. No current test evidence was found that locks the default `AmbientBackground` appearance itself as a visual baseline.
  Evidence: `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules.md:191`, `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md:415`.
- The older Settings product spec describes Settings as a single scrollable place for profile, identity, and recovery controls with a dark glass aesthetic, but it does not describe background choice.
  Evidence: `UI-11-Settings/settings-spec.md:1-14`, `UI-11-Settings/settings-spec.md:79-89`.
- The older Settings product spec includes accessibility notes for tap targets, upload controls, hidden recovery text, warning contrast, and copy confirmation, but no current spec or code path defines screen-reader semantics for a background picker or readability criteria for future background variants.
  Evidence: `UI-11-Settings/settings-spec.md:401-407`, `lib/features/settings/presentation/screens/settings_screen.dart:164-218`, `lib/features/settings/presentation/widgets/image_quality_toggle.dart:46-89`, `lib/features/settings/presentation/widgets/image_quality_toggle.dart:108-137`.

# 5. Scope Clarification

In scope:

- Settings exposes a user-visible background choice control.
- The current single background is represented to users as `Default`.
- A user with no saved preference sees `Default` selected.
- The chosen background remains selected after leaving and reopening Settings.
- The selected `Default` background remains the app-wide shared background for every current screen surface that uses `AmbientBackground`; acceptance can prove this through shared background behavior and call-site inventory rather than one full route smoke test per surface.
- Failed background-preference saves do not leave the user believing an unsaved background was successfully persisted.
- Background-choice attempts and save outcomes are observable through the existing flow-event telemetry without logging sensitive or user-generated content.
- Early onboarding surfaces that appear before a user can normally choose a background still show a valid `Default` background when no saved background preference exists.
- Fresh installs, reinstalls, identity restores, or platform storage states with no saved background preference show `Default`; this is expected behavior, not a user-visible regression.
- Background-choice labels and option text resolve for every currently supported locale: Arabic, German, and English.
- The background-choice control is accessible to assistive technologies: users can identify the control purpose, available options, and selected option without relying only on visual styling.
- The current `Default` background preserves existing Settings readability; each future non-default background variant must define its own contrast/readability acceptance before release.
- The Settings choice remains ready to present more background options later without changing the user-facing concept.

Non-goals:

- Creating additional background artwork or visual themes beyond the existing default background.
- Changing profile photo, peer ID, recovery phrase, media quality, nearby sharing, or debug-introduction behavior.
- Changing notification, transport, database, identity, or messaging behavior.
- Changing the app's core dark theme, typography, navigation structure, or route transitions.
- Introducing per-chat, per-group, per-post, or contact-specific backgrounds.
- Adding new app locales beyond Arabic, German, and English.
- Syncing or restoring the background preference through identity restore, relay state, contacts, backup, or cross-device account state.
- Certifying text/icon contrast or readability for future non-default backgrounds that are not introduced by this default-only change.
- Requiring test-only fake background variants or extra visual-option scaffolding just to simulate a future multi-background release.

Accepted ambiguities for a later implementation pass:

- The exact visual treatment of the picker on small screens.
- Whether the control is labeled `Background`, `App Background`, or grouped under a broader appearance label.
- How future non-default background options will be named and previewed.
- Whether a valid background preference saved from a previous app state should be honored on pre-identity `IdentityChoice`; this spec only requires a valid `Default` appearance when no saved preference exists.
- For a future non-default option, whether the selected background should visibly change behind the Settings route before the user leaves Settings.
- The exact failed-save presentation, such as inline copy, toast/snackbar, or reverting selection timing, as long as the user-visible result is not silent false success.
- The exact flow-event names and detail schema, as long as acceptance evidence can distinguish successful background changes from failed saves without exposing sensitive or user-generated content.
- The exact accessibility wording and widget role for the background control, as long as assistive technologies expose the control purpose, available options, and selected state.
- The exact contrast/readability thresholds for future non-default backgrounds; this spec only requires those thresholds to be defined when a future variant is introduced.

# 6. Test Cases

## Happy Path

- A user opens Settings with no prior background preference and sees a background choice control with `Default` selected.
  Acceptance evidence: unit coverage for the default preference rule; integration coverage that Settings visibly presents the selected default state.
- A user selects `Default`, leaves Settings, reopens Settings, and still sees `Default` selected.
  Acceptance evidence: integration coverage that the visible selection persists across the Settings journey.
- A successful background selection is reflected in flow-event telemetry with a non-sensitive selected-option identifier and a success outcome.
  Acceptance evidence: unit or integration coverage that observes the emitted flow telemetry for a successful background change.
- A user returns from Settings to a representative already-mounted route, such as Feed, with the visible background still consistent with the selected option.
  Acceptance evidence: shared background widget/state-path coverage plus one representative mounted-route journey; the 14-surface inventory remains a product coverage checklist, not a requirement for 14 separate route smoke tests.
- When only the default background exists, the control does not imply unavailable backgrounds or lead to a dead end.
  Acceptance evidence: integration coverage that all visible options are selectable and resolve to a valid selected state.

## Edge Cases

- A missing stored background preference is treated as `Default` and does not show an empty or broken Settings state.
  Acceptance evidence: unit coverage for missing preference behavior.
- After a fresh install, reinstall, identity restore, or any platform state where no saved local background preference exists, Settings and shared-background surfaces show `Default` rather than trying to infer a previous choice.
  Acceptance evidence: unit coverage for absent local preference behavior; smoke or integration coverage that the user-visible default state is stable after an identity restore path.
- An unrecognized stored background value is treated as `Default` and does not break Settings or the app background.
  Acceptance evidence: unit coverage for unknown preference behavior.
- A first-run user who reaches Identity Choice before creating an identity sees the valid `Default` background and no missing-preference artifact.
  Acceptance evidence: smoke coverage of the pre-identity onboarding surface.
- A user who reaches First Time Experience before ever opening Settings sees the valid `Default` background and no missing-preference artifact.
  Acceptance evidence: smoke coverage of the first-time setup surface.
- If saving a newly selected background fails, the user does not get silent success: Settings communicates that the change did not persist or returns to the last confirmed saved selection, and reopening Settings shows the last saved/default background rather than the failed choice.
  Acceptance evidence: unit coverage for failed-save preference behavior; integration coverage that the Settings UI remains honest after a failed selection; flow-event evidence that the failed save is observable.
- Settings remains usable when opened from a context without the bottom navigation bar, such as an in-app settings route used for a specific task.
  Acceptance evidence: integration coverage that the Settings content still exposes the background choice and preserves the existing close/back behavior.
- Localized Settings builds for Arabic, German, and English show meaningful background-choice labels and option text instead of raw keys or blank text.
  Acceptance evidence: integration coverage that visible Settings copy resolves for all currently supported locales.
- A screen-reader or semantics inspection can identify the background setting, the available option list, and the selected `Default` option without relying on color or position alone.
  Acceptance evidence: widget or integration semantics coverage for the background-choice control.

## Regressions To Preserve

- Preservation/regression: profile, peer ID, recovery phrase, Photo Quality, Video Quality, nearby sharing, and bottom navigation behavior remain visible and usable after the background choice appears.
  Existing partial coverage: `settings_screen_test.dart` and `settings_wired_test.dart` already cover these Settings surfaces.
- Preservation/regression: choosing or viewing the background setting does not alter media-quality preferences.
  Existing partial coverage: media-quality preference tests already cover image/video quality persistence separately.
- Preservation/regression: current users who never interact with the new control continue to see the existing default ambient background on Feed, Conversation, Posts, Settings, Orbit, Share Target Picker, QR Display, First Time Experience, Identity Choice, Create Group Picker, Contact Picker, Group List, Group Conversation, and Group Info.
  Acceptance evidence: shared default-background rendering coverage plus static or reviewed call-site evidence that the listed surfaces still use the shared background; add direct route smoke only for representative surfaces or any intentionally special-cased surface.
- Preservation/regression: the existing animated default background remains visually valid when `Default` is selected.
  Acceptance evidence: visual or golden-style regression coverage that the default selected state still renders the same recognizable background treatment, plus shared-path or representative-route evidence that the default background is used by app surfaces.
- Preservation/regression: adding the Settings background control does not reduce the readability of existing Settings text, icons, or selected-state affordances when `Default` is selected.
  Acceptance evidence: visual or golden-style coverage for the default Settings state, plus semantics coverage for the selected background option.

## Future Variant Acceptance

- When a later release introduces more than one real background option, a user can open Settings from Feed, change the selected background, go back, and see that the already-mounted Feed surface underneath Settings reflects the selected background without requiring app restart or a new route mount.
  Future acceptance evidence: integration coverage of the Settings route returning to an already-mounted Feed route after selecting a non-default background.
- When a later release introduces more than one real background option, repeatedly switching back and forth between options while Settings is open does not crash, freeze, flash a blank background, duplicate animated background layers, or report animation lifecycle errors.
  Future acceptance evidence: integration coverage of rapid visible selection changes while the background animation is active.
- Each future non-default background defines its own readable-content and contrast acceptance before release.
  Future acceptance evidence: visual, golden-style, or documented contrast/readability coverage for the new variant.

## Recommended Default-MVP QA Bar

- Unit test background-choice parsing: missing value, `default`, and unknown value all resolve to `Default`.
- Unit or use-case test background preference load/save through `SecureKeyStore`.
- Widget test Settings shows the background control with `Default` selected.
- Widget or semantics test the selector exposes an accessible label and selected state.
- Widget, smoke, visual, or golden-style test `AmbientBackground` still renders the default treatment unchanged.
- Integration or widget test Settings can reopen with `Default` still selected.
- Unit or widget test failed `SecureKeyStore` write behavior so the UI does not report silent success.
- Unit or integration test background-choice flow telemetry for success and failed-save outcomes, unless the implementation explicitly removes telemetry from this spec.
- Static, unit, or widget coverage that Arabic, German, and English background-choice strings resolve to non-empty localized copy.
- Static or reviewed call-site inventory confirms the current shared-background surfaces still use the shared `AmbientBackground` path; this does not require one route smoke test per surface.

## Current Test Gaps

- No current test appears to assert that Settings contains any background or appearance preference.
- No current test appears to assert a persisted background choice.
- No current test or inventory check appears to assert that the selected `Default` background reaches the shared `AmbientBackground` path used by the current app surfaces.
- No current test appears to assert user-visible behavior when saving a Settings background preference fails.
- No current test appears to assert background-choice localization across Arabic, German, and English.
- No current test appears to assert flow-event telemetry for background-choice success or failed-save outcomes.
- No current visual or golden-style test appears to lock the default `AmbientBackground` treatment against accidental visual drift.
- No current semantics/accessibility test appears to assert that a Settings background chooser is labeled and exposes selected state for assistive technologies.
- No existing test or variant evidence defines contrast/readability expectations for future non-default background variants.
