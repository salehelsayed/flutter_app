# 1. Title and Type

- Title: Feed Cosmic Background Option
- Issue type: feature-improvement
- Output doc path: `Test-Flight-Improv/81-feed-cosmic-background-option.md`

# 2. Problem Statement

Users should be able to choose the new cosmic background from Settings and see it on the Feed screen.

The app now has a default background-choice foundation, and a draft `CosmicBackground` widget exists in the repo, but that cosmic design is not a production Settings option and Feed still renders the default ambient background.

This leaves the new visual design unavailable to users and prevents the Feed background preference from proving the multi-background behavior that the Settings background choice was designed to support.

# 3. Impact Analysis

- Affected users: users who want to personalize the Feed background.
- Affected moments: opening Settings, selecting a Feed background, returning to Feed, reopening Settings, and relaunching with a saved background preference.
- Severity: low functional severity because messaging and Feed content can still work with the default background.
- Product cost: moderate personalization gap because a provided background design exists but is not selectable or visible in the intended Feed context.
- Risk: visual and animation regressions are possible because both the current default background and the new cosmic background use animated layers behind interactive Feed content.

# 4. Current State

- The existing background preference model has only one user-facing value: `defaultBackground`. It serializes to `default`, and missing or unknown stored values parse back to `defaultBackground`.
  Evidence: `lib/features/settings/domain/models/background_preference.dart:1-25`.
- Background preference load/save exists through `SecureKeyStore`.
  Evidence: `lib/features/settings/application/background_preference_use_cases.dart:4-23`.
- Settings already loads, saves, emits flow events for, and displays the current background preference, but the visible control currently contains only `Default`.
  Evidence: `lib/features/settings/presentation/screens/settings_wired.dart:76-92`, `lib/features/settings/presentation/screens/settings_wired.dart:177-238`, `lib/features/settings/presentation/screens/settings_screen.dart:36-38`, `lib/features/settings/presentation/screens/settings_screen.dart:188-194`, `lib/features/settings/presentation/widgets/background_choice_control.dart:20-97`.
- Current background localization keys exist for the Settings background section and the `Default` option in Arabic, German, and English. No cosmic option copy exists yet.
  Evidence: `lib/l10n/app_en.arb:258-263`, `lib/l10n/app_de.arb:258-263`, `lib/l10n/app_ar.arb:258-263`.
- The shared `AmbientBackground` accepts a `BackgroundPreference`, but its switch currently renders only the default ambient treatment.
  Evidence: `lib/features/identity/presentation/widgets/ambient_background.dart:7-15`, `lib/features/identity/presentation/widgets/ambient_background.dart:40-49`, `lib/features/identity/presentation/widgets/ambient_background.dart:52-125`.
- Feed wraps its content in `AmbientBackground` without passing a user background preference, so Feed currently shows the default background regardless of any saved preference.
  Evidence: `lib/features/feed/presentation/screens/feed_screen.dart:127-136`.
- Settings currently passes its selected background preference to its own `AmbientBackground`, so Settings can visually reflect the current default-only preference.
  Evidence: `lib/features/settings/presentation/screens/settings_screen.dart:81-88`.
- The repo-local cosmic design exists as `CosmicBackground`, a standalone stateful widget with a deep cosmic radial gradient, drifting violet/teal/pink blooms, twinkling stars, and caller-provided child content.
  Evidence: `Test-Flight-Improv/Background-Feature/cosmic_background.dart:1-18`, `Test-Flight-Improv/Background-Feature/cosmic_background.dart:24-56`, `Test-Flight-Improv/Background-Feature/cosmic_background.dart:97-126`, `Test-Flight-Improv/Background-Feature/cosmic_background.dart:162-270`.
- The provided cosmic file currently lives under `Test-Flight-Improv/Background-Feature/`, and its header describes it as a standalone drop-in Flutter port. No production app source currently owns a cosmic background option.
  Evidence: `Test-Flight-Improv/Background-Feature/cosmic_background.dart:1-11`, `lib/features/settings/domain/models/background_preference.dart:1-25`, `lib/features/identity/presentation/widgets/ambient_background.dart:40-49`.
- `CosmicBackground` owns its own animation lifecycle: an 18-second repeating controller, a stopwatch, and randomly generated stars on mount.
  Evidence: `Test-Flight-Improv/Background-Feature/cosmic_background.dart:62-87`, `Test-Flight-Improv/Background-Feature/cosmic_background.dart:90-94`.
- The cosmic design depends on continuous motion for drifting blooms and twinkling stars, and the current default background also uses a repeating animation. The spec has picker accessibility coverage, but no current cosmic-background reduced-motion expectation.
  Evidence: `Test-Flight-Improv/Background-Feature/cosmic_background.dart:4-8`, `Test-Flight-Improv/Background-Feature/cosmic_background.dart:109-126`, `Test-Flight-Improv/Background-Feature/cosmic_background.dart:240-270`, `lib/features/identity/presentation/widgets/ambient_background.dart:21-31`, `lib/features/identity/presentation/widgets/ambient_background.dart:67-118`.
- The provided cosmic design generates its star positions on mount, so exact star placement is not currently stable across separate widget mounts.
  Evidence: `Test-Flight-Improv/Background-Feature/cosmic_background.dart:77-87`.
- Feed already has performance-sensitive integration coverage that collects frame timings and enforces scroll performance thresholds.
  Evidence: `integration_test/feed_performance_test.dart:201-203`, `integration_test/feed_performance_test.dart:279-317`, `integration_test/feed_performance_test.dart:326-352`.
- Identity Choice and First Time Experience currently render `AmbientBackground` without reading a user background preference; startup routes to those surfaces when identity is missing or when an identity has no contacts.
  Evidence: `lib/features/identity/application/startup_decision.dart:34-60`, `lib/features/identity/presentation/screens/identity_choice_screen.dart:110-115`, `lib/features/home/presentation/screens/first_time_experience_screen.dart:126-127`.
- Existing tests cover the default-only background preference model, Settings control, Settings persistence, failed-save behavior, flow events, localization, default `AmbientBackground`, and a default Settings-over-Feed integration smoke.
  Evidence: `test/features/settings/application/background_preference_use_cases_test.dart:7-87`, `test/features/settings/presentation/widgets/background_choice_control_test.dart:30-101`, `test/features/settings/presentation/screens/settings_screen_test.dart:97-109`, `test/features/settings/presentation/screens/settings_wired_test.dart:472-590`, `test/features/identity/presentation/widgets/ambient_background_test.dart:10-77`, `integration_test/settings_background_choice_smoke_test.dart:36-142`.
- The prior background-choice spec explicitly parked real multi-background behavior for a later variant acceptance pass.
  Evidence: `Test-Flight-Improv/80-settings-background-choice.md:149-170`.

# 5. Scope Clarification

In scope:

- Settings exposes both `Default` and `Cosmic` as selectable background options.
- Settings confirms the `Cosmic` selection through the picker selected state and any contained option preview; the Settings route itself is not the full-screen cosmic background.
- The cosmic design is available from production app code before release; production runtime and tests do not depend on importing a background widget from `Test-Flight-Improv/`.
- `Default` remains selected when no saved background preference exists.
- Once shipped, the stored `Cosmic` identifier is a permanent compatibility contract; future changes must continue to recognize it or intentionally migrate it.
- Selecting `Cosmic` from Settings persists the selection and shows `Cosmic` selected when Settings is reopened.
- Selecting `Cosmic` changes the Feed screen background to the cosmic design.
- Selecting `Default` after `Cosmic` returns Feed to the existing default ambient background.
- Returning from Settings to an already-mounted Feed route reflects the selected background without requiring app restart.
- Only the Feed surface renders the cosmic background. Every other shared-background surface — Conversation, Posts, Orbit, Settings, QR display, share target picker, Identity Choice, First Time Experience, Create Group Picker, Contact Picker, Group List, Group Conversation, Group Info, and any future shared-background screen — shows the default background regardless of the stored preference. Feed sub-routes opened from Feed (such as Conversation, post detail, or profile detail) are not Feed for this purpose.
- The "only Feed renders cosmic" rule is enforced as a single filter inside the shared `AmbientBackground` widget rather than at each call site: callers always pass the stored preference, and the widget falls back to default when the calling surface is not Feed (signaled by an explicit per-call Feed flag). Adding a new shared-background surface in the future inherits the default behavior automatically without per-screen opt-out.
- The cosmic background remains visually behind Feed content and does not block Feed header, cards, empty state, inline replies, reactions, navigation, or Settings access.
- Feed scrolling and common Feed interactions remain within the existing performance expectations when `Cosmic` is selected.
- Missing or unknown stored background values still resolve to `Default`.
- Identity Choice and First Time Experience continue to show the default background even if a stored background preference is `Cosmic`.
- Failed background-preference saves do not leave the user believing `Cosmic` was persisted when it was not.
- Background-choice success and failed-save outcomes remain observable through non-sensitive flow telemetry.
- Arabic, German, and English Settings builds show meaningful copy for both `Default` and `Cosmic`.
- The Settings background selector remains accessible: assistive technologies can identify the control, each option, and which option is selected.
- The cosmic design has enough Feed readability acceptance to prove text, icons, cards, badges, and controls remain usable over it.
- When platform reduced-motion or disabled-animation preference is active, the cosmic Feed background remains recognizable and readable without continuous drift or twinkle motion.
- At least one simulator or emulator smoke run confirms selecting `Cosmic` in Settings and seeing it on Feed.

Non-goals:

- Adding background options beyond `Default` and `Cosmic`.
- Applying `Cosmic` as a persistent background to Conversation, Posts, Orbit, QR, share, onboarding, group, or other non-Feed surfaces; any Settings preview remains part of the picker experience.
- Making star positions persist identically across separate Feed mounts.
- Redesigning Feed cards, Feed navigation, Feed header, chat/message behavior, reactions, media behavior, profile behavior, or Settings layout beyond the background option itself.
- Changing the visual design of the provided cosmic background beyond what is needed for app fit and readability acceptance.
- Auditing or changing reduced-motion behavior across all non-cosmic app animations.
- Syncing or restoring the background preference through identity restore, relay state, contacts, backup, or cross-device account state.
- Adding new app locales beyond Arabic, German, and English.

Accepted ambiguities for a later implementation pass:

- The exact user-facing option label, such as `Cosmic`, `Cosmic Sky`, or another short localized name.
- The exact contained preview treatment for background options in Settings, if any.
- The exact telemetry event names and detail schema, as long as success and failure are distinguishable without sensitive or user-generated content.
- The exact storage identifier for the cosmic preference before release, as long as the shipped identifier becomes permanent and unknown values still fall back to `Default`.
- The exact production source location and file name for the cosmic background, as long as the app owns it under production source and acceptance tests can render it without importing from `Test-Flight-Improv/`.
- The exact visual or golden tolerance for cosmic animation, star placement, and bloom drift, as long as acceptance proves the recognizable cosmic treatment and Feed readability. Star positions may differ between Feed mounts and should not be treated as a regression by themselves.
- The exact reduced-motion visual treatment, such as a static gradient, frozen bloom/starfield frame, or another non-distracting state, as long as continuous background motion stops when platform reduced-motion or disabled-animation preference is active.

# 6. Test Cases

## Happy Path

- A user opens Settings with no saved background preference and sees both `Default` and `Cosmic`, with `Default` selected.
  Acceptance evidence: widget or integration coverage for Settings option visibility and selected state.
- A user selects `Cosmic` in Settings and sees `Cosmic` selected in the picker without the full Settings route becoming the cosmic Feed background.
  Acceptance evidence: widget or integration coverage for Settings selected state and Settings readability while `Cosmic` is selected.
- A user selects `Cosmic`, leaves Settings, reopens Settings, and sees `Cosmic` still selected.
  Acceptance evidence: unit or integration coverage that the saved cosmic preference loads back into the visible Settings state.
- A user selects `Cosmic` in Settings, returns to Feed, and sees the cosmic background behind Feed content.
  Acceptance evidence: integration coverage of the Settings-to-Feed journey.
- The app renders the cosmic Feed background from production app source rather than from the `Test-Flight-Improv/` design artifact.
  Acceptance evidence: static, widget, or integration coverage that the production app path can render the cosmic background without importing from the spec/docs directory.
- A user selects `Default` after previously selecting `Cosmic`, returns to Feed, and sees the original default ambient background again.
  Acceptance evidence: integration or widget coverage that both options produce the expected visible Feed background state.
- A successful `Cosmic` selection is reflected in flow-event telemetry with a non-sensitive selected-option identifier and success outcome.
  Acceptance evidence: unit or integration coverage that observes the emitted flow telemetry.
- A stored shipped `Cosmic` value continues to load as `Cosmic`; unknown values still fall back to `Default`.
  Acceptance evidence: unit coverage for stored-value compatibility.

## Edge Cases

- A missing stored background preference is treated as `Default` and does not show `Cosmic` selected by mistake.
  Acceptance evidence: unit coverage for missing preference behavior.
- An unrecognized stored background value is treated as `Default` and does not break Settings or Feed.
  Acceptance evidence: unit coverage for unknown preference behavior.
- If saving `Cosmic` fails, Settings communicates that the change did not persist or returns to the last confirmed saved selection, and reopening Settings shows the last saved/default option rather than a false `Cosmic` success.
  Acceptance evidence: unit or integration coverage for failed-save behavior and failed-save telemetry.
- Rapidly selecting `Default` and `Cosmic` while Settings is open does not crash, freeze, flash a blank Feed background after return, or report animation lifecycle errors.
  Acceptance evidence: widget or integration coverage around visible selection changes and returning to Feed.
- Feed remains readable and usable with `Cosmic` behind empty Feed, populated Feed, and interactive Feed controls.
  Acceptance evidence: widget, smoke, visual, golden-style, or simulator coverage across representative Feed states.
- Feed scroll and common Feed interaction performance remain within the established Feed performance expectations when `Cosmic` is selected.
  Acceptance evidence: performance integration or simulator coverage that exercises Feed with `Cosmic` selected.
- With platform reduced-motion or disabled-animation preference active, Feed remains readable and usable with `Cosmic` selected, and the cosmic background no longer relies on continuous drift or twinkle motion.
  Acceptance evidence: widget, integration, or simulator coverage that exercises the reduced-motion state.
- A user with a stored `Cosmic` preference who reaches Identity Choice or First Time Experience sees the default background on those pre-Feed surfaces.
  Acceptance evidence: widget, integration, or smoke coverage for those startup surfaces with a stored non-default background preference.
- With `cosmic` as the stored preference, opening Conversation from Feed shows the default background, not cosmic.
  Acceptance evidence: widget or integration coverage for the Feed-to-Conversation transition with a stored cosmic preference.
- `AmbientBackground` renders the cosmic visual treatment only when the call site identifies as Feed and the stored preference is `cosmic`; for all other combinations — non-Feed call site with cosmic preference, non-Feed call site with default, Feed call site with default — it renders the default treatment.
  Acceptance evidence: widget unit coverage exercising all four combinations of (Feed flag × stored preference).
- Localized Settings builds for Arabic, German, and English show meaningful `Cosmic` option labels and descriptions instead of raw keys or blank text.
  Acceptance evidence: static, widget, or integration coverage that localized copy resolves for all currently supported locales.
- A screen-reader or semantics inspection can identify the background setting, `Default`, `Cosmic`, and the selected option without relying on color or position alone.
  Acceptance evidence: widget or integration semantics coverage.
- A simulator or emulator smoke run confirms Settings can select `Cosmic`, Feed shows the cosmic background, Settings can reopen with `Cosmic` still selected, and switching back to `Default` restores the default Feed background.
  Acceptance evidence: simulator or emulator smoke coverage.

## Regressions To Preserve

- Preservation/regression: users who never select `Cosmic` continue to see the existing default ambient background on Feed.
  Existing partial coverage: default `AmbientBackground` and default Settings-over-Feed smoke tests already cover the default-only path.
- Preservation/regression: Feed header, Feed cards, bottom navigation, Settings access, inline reply, reactions, editing, deleting, attachments, and group-thread entry points remain usable after `Cosmic` becomes selectable.
  Acceptance evidence: representative Feed widget or smoke coverage over the cosmic background.
- Preservation/regression: Settings profile, peer ID, recovery phrase, Photo Quality, Video Quality, nearby sharing, and bottom navigation behavior remain visible and usable after the `Cosmic` option appears.
  Existing partial coverage: existing Settings tests cover these Settings surfaces.
- Preservation/regression: choosing or viewing the background setting does not alter media-quality, nearby sharing, identity, contact, message, post, transport, notification, or group state.
  Acceptance evidence: existing adjacent preference and Feed tests continue to pass.
- Preservation/regression: non-Feed surfaces outside any Settings picker preview continue to render their existing default background behavior, including when the stored preference is `Cosmic`.
  Acceptance evidence: widget-level filter coverage on `AmbientBackground` plus representative smoke coverage on at least one non-Feed shared-background surface with a stored cosmic preference.

## Recommended QA Bar

- Unit coverage for background preference parsing and serialization: missing, `default`, `cosmic`, and unknown values.
- Unit or use-case coverage for loading and saving the cosmic preference through secure storage.
- Static, widget, or integration coverage that the cosmic background used by Feed is production app source, not a runtime import from `Test-Flight-Improv/`.
- Widget coverage that Settings shows `Default` and `Cosmic`, with correct selected-state behavior.
- Widget unit coverage of the `AmbientBackground` filter rule across all four combinations of (Feed flag × stored preference): the cosmic visual treatment renders only for (Feed + cosmic); every other combination renders default.
- Widget or integration semantics coverage for the two-option picker.
- Widget, visual, or golden-style coverage that the default background remains unchanged.
- Widget, visual, golden-style, or smoke coverage that the cosmic background renders its recognizable gradient, blooms, stars, and child content.
- Visual or golden-style coverage for the animated cosmic background uses a stable bounded frame, deterministic visual state, or reduced-motion state; it does not expect a looping background animation to naturally settle.
- Performance coverage that Feed scrolling and common interactions remain within the established Feed performance expectations with `Cosmic` selected.
- Widget, integration, or simulator coverage that the cosmic background honors platform reduced-motion or disabled-animation preference.
- Integration coverage for Settings selecting `Cosmic`, returning to Feed, reopening Settings, and switching back to `Default`.
- Failed-save coverage for the `Cosmic` selection path.
- Flow telemetry coverage for `Cosmic` success and failed-save outcomes.
- Localization coverage for Arabic, German, and English cosmic option copy.
- Simulator or emulator smoke coverage for the Settings-to-Feed cosmic journey.

## Current Test Gaps

- No current production background preference value represents `Cosmic`.
- No current production app source owns the provided cosmic background design; the available file is under `Test-Flight-Improv/Background-Feature/`.
- No current Settings test can find a `Cosmic` option because only `Default` exists.
- No current Feed test proves a saved background preference changes the Feed background.
- No current test asserts that `AmbientBackground` filters cosmic to default when called from a non-Feed surface.
- No current production test covers the provided `CosmicBackground` widget.
- No current test or acceptance evidence covers reduced-motion behavior for the cosmic background.
- No current test or acceptance evidence covers Feed performance with the cosmic background selected.
- No current test confirms Identity Choice or First Time Experience keep the default background when a stored preference is `Cosmic`.
- No current visual test strategy accounts for random star placement or looping cosmic animation.
- No current localization keys exist for a cosmic background option.
- No current telemetry assertion covers a non-default background selection.
- No current simulator or emulator smoke covers selecting a non-default background and seeing it on Feed.
