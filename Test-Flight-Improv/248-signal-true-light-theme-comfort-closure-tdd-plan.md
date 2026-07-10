# 248 - Signal True Light Theme and Warm Comfort Closure

Status: execution-ready
Type: Modification
Spec: free-text intent plus artifacts/signal-theme-ui-audit-2026-07-09/README.md
Classification: implementation-ready
Closure tier: device

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-09 CEST | Evidence Collector | graphify-arch query; app_theme.dart; main.dart; app_shell_controller.dart; startup_router.dart; background_readable_colors.dart; feed_tokens.dart; ambient_background.dart; daylight_lagoon_background.dart | Signal changes custom extensions locally, while the app root remains dark; this explains the pushed-route and modal inconsistency. | Inventory concrete render gaps and existing tests. |
| 2026-07-09 CEST | Device UX Auditor | artifacts/signal-theme-ui-audit-2026-07-09/README.md and 26 captures | Physical Pixel 6 evidence confirms paper-white flattening, dark route/sheet leaks, Orbit hint failure, and debug-card white-on-white. Scanner is an intentional dark exception. | Translate subjective findings into semantic and contrast contracts. |
| 2026-07-09 CEST | Test Planner | plan 221 and its closure evidence; theme, conversation, Orbit, Settings, QR, l10n tests; run_test_gates.sh | Existing tests intentionally pin the pale palette. Host widget/unit tests are causal; physical screenshots remain required UX acceptance because warmth and fatigue are not fully automatable. | Produce one RED-first contract and literal gates. |
| 2026-07-09 CEST | Independent Refute | root theme, modal call sites, chooser persistence, kDebugMode guard, Orbit find, dark preservation tests | Independent Appearance, chooser Apply/Cancel, and density changes are not execution-safe in this change. Flutter modal theme capture is not absent globally; the real issue is caller context above AmbientBackground plus a dark root, with hardcoded exceptions. | Keep those product decisions deferred and close only the confirmed Signal seams. |
| 2026-07-09 CEST | Final Counterexample Review | draft plan; Feed retry/status consumers; startup restore chain; FEED_TESTS; device state | Five material gaps found and patched once: success-text AA, fresh-start composition, false Feed registration, incomplete device runbook, and underspecified light roles. Input-border margin also increased. | Run the blocking sufficiency check, index, and hand off. |

## Problem And Evidence

- Behavior to improve: selecting Signal must produce one coherent, warm, dimensional light appearance across the app instead of a pale wallpaper with dark Material islands.
- Impact: users currently encounter visibly dark pushed routes and overlays, near-white text on near-white controls, debug-only unreadable cards, and a paper-white canvas whose cards and inputs merge together. This harms orientation, readability, and perceived finish.
- Confirmed root cause/current gap:
  - AppTheme exposes only darkTheme at lib/core/theme/app_theme.dart:10-37, and MyApp pins theme: AppTheme.darkTheme plus ThemeMode.dark at lib/main.dart:4974-4984.
  - AmbientBackground replaces only BackgroundReadableColors and FeedTokens inside its subtree at lib/features/identity/presentation/widgets/ambient_background.dart:115-154. A pushed route or modal launched from a context above that subtree falls back to the root dark ThemeData.
  - Signal is deliberately pinned to a white ground with transparent washes at lib/features/identity/presentation/widgets/daylight_lagoon_background.dart:15-31, while an 18-second controller still ticks at :38-89.
  - The conversation overflow popup is independently hardcoded dark at lib/features/conversation/presentation/screens/conversation_wired.dart:4196-4220, and the delete sheet repeats the same pattern at :4567-4695.
  - The Orbit find TextField sets typed text but no hintStyle at lib/features/orbit/presentation/widgets/inner_circle_interactive_surface.dart:1097-1110.
  - Settings diagnostic cards use translucent white structural/text colors throughout settings_introduction_debug_card.dart and settings_transport_diagnostics_card.dart; the parent section is confirmed debug-only by kDebugMode at settings_wired.dart:745-753.
- Existing coverage:
  - test/core/theme/background_readable_colors_signal_test.dart and test/features/identity/presentation/widgets/daylight_lagoon_background_signal_test.dart pin the current pale values and transparent blooms.
  - test/features/feed/presentation/widgets/feed_tokens_tone_test.dart proves local Feed token switching.
  - test/features/theme/dark_preset_preservation_test.dart is the primary adjacent dark-render sentinel.
  - test/features/settings/application/background_preference_use_cases_test.dart proves the existing daylight_lagoon storage token round-trip.
  - A focused 13-file planning probe passed 110 tests, confirming that the current suites preserve the observed design rather than detecting these gaps.
- Intentional expectation flips: ambient_background_test.dart, compose_area_tone_test.dart, empty_conversation_state_tone_test.dart, orbital_visualization_signal_test.dart, background_choice_control_test.dart, and the live-Signal assertion inside dark_preset_preservation_test.dart also contain exact old light values/copy. They are planned assertion REDs to update; their dark halves remain preservation sentinels.
- Missing coverage: no test proves a real light root ThemeData, initial/live root mode selection, filtered controller lifecycle, pushed Contact Profile, Signal attachment/overflow/delete chrome, light Orbit hint contrast, light diagnostics, or representative loaded-card hierarchy.
- Refuted findings:
  - “Add System/Light/Dark now” is refuted as execution-safe scope. Appearance is currently derived from the wallpaper, and no product rule exists for Light with Cosmic/Aurora or Dark with Signal. Plan 221 explicitly deferred this choice.
  - “Flutter modal routes never inherit themes” is false. The observed attachment leak comes from ConversationWired State context above the nested AmbientBackground plus a dark root; overflow/delete also have their own hardcoded colors.
  - “Diagnostics are a release-user P0” is false because they are kDebugMode-only. Their contrast defect is real and remains in scope as debug-build quality.
  - “Reduce row height and redesign the chooser in the same fix” is not causal. Immediate persist-and-close is an existing tested contract, and density/navigation changes are separate layout work.
- Unresolved findings: none blocking. The aesthetic word “comforting” is intentionally closed by the named physical-device comparison after deterministic palette and contrast gates pass.
- Affected production files: lib/core/theme/app_theme.dart; a new small app-shell theme binding under lib/core/theme/; lib/main.dart; background_readable_colors.dart; feed_tokens.dart; daylight_lagoon_background.dart; friend_row.dart; group_row.dart; letter_card.dart; conversation_wired.dart; inner_circle_interactive_surface.dart; connection_status_indicator.dart; the two Settings diagnostic-card widgets; app_en/de/ar.arb and generated l10n.
- Affected test/gate files: focused tests named below. New host tests are AUTO-globbed; conversation_wired_test.dart is already in ONE_TO_ONE_TESTS, and the existing Signal Feed tests are already in FEED_TESTS. No gate-script edit is planned.

## Scope Contract And Guard

### Locked light roles

| Role | Exact value | Contract |
|---|---:|---|
| Canvas | #ECE8E1 | Warm mineral/linen ground; pure white is forbidden as the full-screen Signal canvas. |
| Ground gradient | #F4F0EA -> #ECE8E1 -> #E5DED5 at stops 0.0 / 0.62 / 1.0 | Warm center-to-edge depth without a white hotspot. |
| Base surface | #F4F0EA | Section and scaffold surface. |
| Raised surface | #FAF8F3 | Cards, dialogs, sheets, and popups. |
| Subtle/input/outgoing surface | #E1DCE5 | Lavender-grey nesting and bubble separation. |
| Primary / secondary text | #25222B / #56515E | Warm charcoal hierarchy. |
| Small muted text | #65606C | At least 4.5:1 on canvas, base, and subtle surfaces. |
| Placeholder text | #645F6A | At least 4.5:1 on #E1DCE5. |
| Accent / filled success / error | #6045B6 / #2F7755 / #B4232F | Calmer violet, forest-green filled actions with white, and readable destructive red. |
| Small success text/border | #236143 | AA-safe on canvas, subtle surfaces, and the rendered 12%-success status pill; never alpha-fade small success text. |
| Interactive border | #8D83A8 | At least 3:1 on the base/raised control surfaces where it is used. |
| Input border | #7C7297 | About 3.31:1 on #E1DCE5, retaining margin above the 3:1 floor. |
| Decorative surface border/divider | #B3ACBD | Grouping only; never the sole control boundary. |
| Disabled foreground/surface | #6B6672 / #D5D0D9 | At least 3:1 component distinction. |
| Ambient blooms | violet #7C69C8 at alpha 0x17; sage #58A989 at alpha 0x12 | Broad static color fields, not transparent animation. |
| Feed success fill | #DCE9E1 | Loaded system/outgoing Feed bubble fill with #236143 boundary/text and readable warm text. |

### Complete representative-light token mapping

| Token family | Locked mapping |
|---|---|
| textPrimary / iconPrimary | #25222B |
| textSecondary / iconSecondary | #56515E |
| textMuted / iconMuted | #65606C |
| surfaceBase / surfaceRaised / surfaceSubtle | #F4F0EA / #FAF8F3 / #E1DCE5 |
| glassSurface / glassBorder | 0xEEFAF8F3 / #8D83A8 |
| surfaceBorder / divider | #B3ACBD / #B3ACBD |
| border / overlayScrim | #8D83A8 / 0x66000000 |
| inputFill / inputBorder / placeholderText | #E1DCE5 / #7C7297 / #645F6A |
| disabledForeground / disabledSurface | #6B6672 / #D5D0D9 |
| accent / accentIcon | #6045B6 / #FFFFFF |
| ring1 / ring2 / ringGlow | 0x526045B6 / 0x706045B6 / 0x177C69C8 |
| ctaBg / ctaIcon | #6045B6 / #6045B6; the existing FAB glyph remains intentional white |
| ctaMenuFill / ctaMenuBorder / ctaMenuText | #FAF8F3 / #8D83A8 / #25222B |
| navActive / navInactive / navActiveFill | #6045B6 / #65606C / 0x1A6045B6 |
| nodeSelfGlow / nodeContactGlow | #6045B6 / existing semantic red #E5484D |
| composerBarColor / composerInputFill / composerHint | 0xF2F4F0EA / #E1DCE5 / #645F6A |
| sendBg / sendIcon | 0x1F6045B6 / #6045B6 |
| connectedHeading | #236143; full opacity for 11–12.5 px status/retry text |
| emptyHint / emptyDate / emptyDivider / emptyAvatarGlow | #65606C / #65606C / #B3ACBD / #6045B6 |
| micBg / micBorder / micShadow / micIcon | 0x1F6045B6 / #7C7297 / 0x336045B6 / #6045B6 |
| avatarFrameBorder / avatarFrameFill | #B3ACBD / #FAF8F3 |
| system chrome | statusBarIconBrightness and navigationBarIconBrightness are Brightness.dark |
| Feed teal400 / tealFill08 | #6045B6 / 0x146045B6 |
| Feed green500 / greenFill15 | #236143 / #DCE9E1 |
| Feed surfaceSubtle / surfaceRaised / borderSoft / canvas | #E1DCE5 / #FAF8F3 / #B3ACBD / #ECE8E1 |
| Feed textMessage / textMeta | #25222B / #56515E; numeric blur/radius/spacing/leading values stay unchanged |
| Material ColorScheme | primary #6045B6, onPrimary #FFFFFF, secondary #2F7755, onSecondary #FFFFFF, surface #FAF8F3, onSurface #25222B, error #B4232F, onError #FFFFFF, outline #8D83A8, outlineVariant #B3ACBD, surfaceContainerHighest #E1DCE5 |

In scope:

- Add AppTheme.lightTheme with a complete Material light ColorScheme, light text defaults, component themes, BackgroundReadableColors.representativeLight, and FeedTokens.light. Map scaffold/canvas/surface/input/dialog/sheet/popup roles to the locked values.
- Add a small testable AppShellThemeBinding that maps BackgroundPreference.daylightLagoon to ThemeMode.light and all current dark wallpapers to ThemeMode.dark. It must listen only to AppShellChangeKind.background, detach old controllers, and remove its listener on dispose.
- Wrap the root MaterialApp with that binding and provide theme, darkTheme, and the resolved themeMode. Startup restore continues through the existing SecureKeyStore loader and AppShellController.
- Replace the paper-white Signal ground with the locked warm gradient and two visible static blooms. Remove the always-ticking Signal animation; reduced-motion and ordinary mode render the same calm static composition.
- Retune every representative-light semantic role and FeedTokens.light exactly as mapped above. Filled success remains #2F7755 with white content; small success text/borders use #236143 at full opacity. Add a separate surfaceBorder role to BackgroundReadableColors, with a dark value equal to the current rendered border, and use it only for decorative card/bubble outlines. Keep border/inputBorder for controls.
- Prove filled hierarchy on FriendRow, GroupRow, incoming/outgoing LetterCard bubbles, and a loaded Feed system card without changing geometry or density.
- Make Contact Profile, attachment sheet, overflow popup, delete sheet, Settings sheets, Orbit find hint, and debug diagnostics coherent under Signal. Preserve semantic success/warning/destructive colors and behavioral callbacks.
- Change Signal description copy to:
  - English: “A warm mineral sky with soft violet and sage light.”
  - German: “Ein warmer mineralischer Himmel mit sanftem violettem und salbeigrünem Licht.”
  - Arabic: “سماء معدنية دافئة بضوء بنفسجي ومريمي ناعم.”
- Re-capture and review every safe audited state on the connected Pixel 6 at font scales 1.0 and 1.3; redact contact/QR data and never open the recovery phrase.

Must preserve:

- Default, Cosmic, and Aurora resolve to dark ThemeMode and retain current dark token/render literals -> TC-248-02, TC-248-25.
- BackgroundPreference.daylightLagoon and storage token daylight_lagoon remain unchanged -> TC-248-07.
- AppShell tab, identity, and media-quality changes do not rebuild the root theme -> TC-248-04.
- Attachment Cancel and delete Cancel remain side-effect free; delete/introduce/block actions keep their existing behavior -> TC-248-16 through TC-248-18.
- Scanner remains an explicitly black, high-contrast functional camera subtree under a Signal root -> TC-248-24.
- Existing row heights, radii, padding, navigation placement, Orbit geometry, and information density remain unchanged -> TC-248-12 through TC-248-14 plus scope diff inspection.

Hard Do not:

- Do not add an Appearance preference, System mode, persistence key, migration, or Signal-dark/Cosmic-light compatibility policy.
- Do not change BackgroundChoiceControl to previews, provisional state, Apply/Cancel, or new persistence semantics.
- Do not globally weaken BackgroundReadableColors.border to make cards softer; add and use surfaceBorder only at named decorative consumers.
- Do not force the QR scanner light, change camera behavior, or restyle intentional white text on accent/error overlays without contrast evidence.
- Do not change card height, empty-state layout, Feed navigation overlap, Move Account layout, networking, repositories, database, crypto, relay, or Go code.
- Do not overwrite unrelated dirty work. lib/main.dart, inner_circle_interactive_surface.dart, conversation_wired_test.dart, startup_router.dart, and run_test_gates.sh already carry concurrent edits.

Deferred / accepted difference:

- Independent System/Light/Dark Appearance -> owner: a separate product-policy Test-Flight-Improv plan after all wallpaper/appearance combinations are specified.
- Background thumbnails and Apply/Cancel -> owner: a separate chooser-interaction plan because it requires provisional persistence and dismissal rules.
- All Chats/Feed density, compact empty panels, Feed-nav overlap, and Move Account composition -> owner: screen-specific layout follow-ups; this plan changes color hierarchy only.
- Debug diagnostic cards may gain small dark-debug chrome differences when moved to shared semantic roles; release dark surfaces remain literal-preserved by TC-248-25.

Dependencies:

- Plan 221’s Signal semantic-token wiring and unchanged daylight_lagoon storage key are prerequisites already present.
- Current background set from plan 222 is authoritative: Default, Cosmic, and Aurora are dark; Signal/daylightLagoon is light.
- No DB version, SecureKeyStore key, generated native surface, or external service dependency is added.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-248-01 | AppTheme exposes a complete warm light ThemeData and Material component defaults. | test/core/theme/app_theme_test.dart::light theme exposes the locked warm ColorScheme and light extensions | Host unit / ThemeData inspection | HEAD has no lightTheme; after an inert lightTheme scaffold the assertion is RED because brightness/roles are dark -> GREEN exact light brightness, ColorScheme, scaffold, input, dialog, sheet, popup, and extensions. | Return darkTheme or restore any paper-white role -> TC-248-01 red. | flutter test test/core/theme/app_theme_test.dart; AUTO test/core glob; core-host-all. |
| TC-248-02 | Initial root mode is light only for Signal and dark for every current sibling wallpaper. | test/features/theme/app_shell_theme_binding_test.dart::initial controller preference maps Signal to light and every dark preset to dark | Host widget / real AppShellController, inert binding scaffold | HEAD has no root mapping -> GREEN four-preference matrix with daylightLagoon light and Default/Cosmic/Aurora dark. | Map all backgrounds to one mode or omit Aurora -> TC-248-02 red. | flutter test test/features/theme/app_shell_theme_binding_test.dart; AUTO test/features glob; feature-host-all. |
| TC-248-03 | A successful live background change switches root Material brightness Signal -> light -> Aurora dark without remounting the child. | test/features/theme/app_shell_theme_binding_test.dart::background notification switches root brightness live and preserves child state | Host widget / real controller plus stateful child key | HEAD binding scaffold remains dark and no transition occurs -> GREEN brightness flips twice while child state/identity survives. | Remove listener, ignore background kind, or key-recreate child -> TC-248-03 red. | flutter test test/features/theme/app_shell_theme_binding_test.dart --plain-name 'background notification switches root brightness live and preserves child state'; AUTO; feature-host-all. |
| TC-248-04 | Tab, identity, media-quality, and same-value events do not rebuild the root theme. | test/features/theme/app_shell_theme_binding_test.dart::non-background shell events do not rebuild theme builder | GREEN sentinel after TC-248-03 / host widget, seeded feed tab and build counter | The inert scaffold would pass vacuously, so author/run this only after the real background listener exists -> it remains GREEN while only real background mode changes increment the theme builder. | Call setState for every notifyListeners or drop same-mode guard -> TC-248-04 red. | flutter test test/features/theme/app_shell_theme_binding_test.dart --plain-name 'non-background shell events do not rebuild theme builder'; AUTO; feature-host-all. |
| TC-248-05 | Controller replacement/disposal detaches listeners and follows only the new controller. | test/features/theme/app_shell_theme_binding_test.dart::binding swaps and disposes controller listeners without stale updates | Host widget / old and new real controllers | HEAD has no lifecycle binding -> GREEN old controller is inert after replacement, new controller switches mode, and both are inert after unmount. | Omit didUpdateWidget detach/attach or dispose removal -> TC-248-05 red. | flutter test test/features/theme/app_shell_theme_binding_test.dart --plain-name 'binding swaps and disposes controller listeners without stale updates'; AUTO; feature-host-all. |
| TC-248-06 | MyApp actually uses the binding and supplies lightTheme, darkTheme, and resolved themeMode. | test/core/theme/app_root_theme_wiring_test.dart::main root wires AppShellThemeBinding around MaterialApp | Host source-contract / lib/main.dart | HEAD source pins darkTheme/ThemeMode.dark -> GREEN one binding wrapper and the three MaterialApp theme arguments; no fixed dark mode remains. | Remove wrapper or restore ThemeMode.dark -> TC-248-06 red. | flutter test test/core/theme/app_root_theme_wiring_test.dart; AUTO test/core glob; core-host-all. |
| TC-248-07 | Existing Signal storage token still decodes durably with no migration. | test/features/settings/application/background_preference_use_cases_test.dart::returns daylight lagoon when stored value is daylight_lagoon | GREEN sentinel / FakeSecureKeyStore recreation | GREEN on HEAD -> remains GREEN as the durable input to TC-248-28; this row alone does not claim root-theme restoration. | Rename token/key or bypass fromStorageString -> sentinel red. | flutter test test/features/settings/application/background_preference_use_cases_test.dart --plain-name 'returns daylight lagoon when stored value is daylight_lagoon'; AUTO; feature-host-all. |
| TC-248-28 | A stored Signal preference drives a mounted root from its initial dark state to light through the real load/controller/binding chain, and StartupRouter keeps the forwarding call. | test/features/theme/app_shell_theme_binding_test.dart::stored Signal load drives mounted root light plus test/core/theme/app_root_theme_wiring_test.dart::StartupRouter forwards loaded background into AppShellController | Host integration plus source-contract / FakeSecureKeyStore, real loadBackgroundPreference, real AppShellController, mounted binding | With the inert binding scaffold the stored enum loads but root brightness remains dark -> GREEN load -> setBackgroundPreference -> background notification -> light root; source guard pins StartupRouter forwarding. | Remove StartupRouter forwarding or map the loaded Signal to dark -> the corresponding half of TC-248-28 red. | flutter test test/features/theme/app_shell_theme_binding_test.dart --plain-name 'stored Signal load drives mounted root light' && flutter test test/core/theme/app_root_theme_wiring_test.dart --plain-name 'StartupRouter forwards loaded background into AppShellController'; AUTO feature/core globs; feature-host-all and core-host-all. |
| TC-248-08 | Core light roles equal the locked warm palette and pass WCAG role/surface thresholds. | test/core/theme/background_readable_colors_signal_test.dart::representativeLight pins warm mineral roles and passes every effective-surface contrast pair | Host unit / shared contrast helper | HEAD exact paper palette and several proposed values differ -> GREEN exact roles; normal/small text >=4.5:1 and components/interactive borders >=3:1 on actual surfaces. | Restore #FFFFFF/#F4F6FA, use #716B78 globally, or lower any tested pair -> TC-248-08 red. | flutter test test/core/theme/background_readable_colors_signal_test.dart test/core/theme/background_readable_colors_test.dart; AUTO; core-host-all. |
| TC-248-09 | Decorative surfaceBorder is separate from stronger control borders and preserves dark rendering. | test/core/theme/background_readable_colors_signal_test.dart::surface borders are soft only at decorative consumers while controls retain three-to-one borders | Host unit / additive placeholder surfaceBorder in both const token sets | HEAD lacks the role; scaffold it initially equal to border so the value assertion is RED -> GREEN light surfaceBorder #B3ACBD, border #8D83A8, inputBorder #7C7297, dark surfaceBorder equal to prior dark border. | Alias surfaceBorder to border in light or weaken border/inputBorder -> TC-248-09 red. | flutter test test/core/theme/background_readable_colors_signal_test.dart --plain-name 'surface borders are soft only at decorative consumers while controls retain three-to-one borders'; AUTO; core-host-all. |
| TC-248-10 | Signal renders a warm gradient, visible violet/sage blooms, and no running background ticker. | test/features/identity/presentation/widgets/daylight_lagoon_background_signal_test.dart::warm mineral ground has static violet and sage blooms without a ticker | Host widget / direct background, ordinary and disableAnimations MediaQuery | HEAD is white, washes transparent, and tester reports a running animation -> GREEN exact gradient/bloom colors, same static frame in both modes, no running animation, willChange false. | Restore transparent washes, pure white, or a repeating controller -> TC-248-10 red. | flutter test test/features/identity/presentation/widgets/daylight_lagoon_background_signal_test.dart; AUTO test/features glob; feature-host-all. |
| TC-248-11 | FeedTokens.light uses the same warm canvas/surface/text/accent/success vocabulary. | test/features/feed/presentation/widgets/feed_tokens_tone_test.dart::Signal Feed tokens match the locked warm hierarchy | Host unit/widget / AmbientBackground light fixture | HEAD pins pale Feed values -> GREEN canvas #ECE8E1, raised #FAF8F3, subtle #E1DCE5, accent #6045B6, small success text/border #236143, success fill #DCE9E1, readable text/meta, and dark token literals unchanged. | Leave FeedTokens.light pale, use #2F7755 for small canvas text, or alter FeedTokens.dark -> TC-248-11 red. | flutter test test/features/feed/presentation/widgets/feed_tokens_tone_test.dart; already in FEED_TESTS; feed and feature-host-all. |
| TC-248-12 | All Chats friend and group rows use filled light hierarchy plus decorative borders without geometry changes. | test/features/orbit/presentation/widgets/all_chats_signal_hierarchy_test.dart::Signal friend and group rows use warm fills and surfaceBorder at existing geometry | Host widget / real FriendRow and GroupRow light fixtures | HEAD uses pale surfaceSubtle plus strong global border -> GREEN locked filled surface/surfaceBorder, readable small text, and exact existing padding/radius/row bounds. | Use global border, paper-white fill, or change padding/height -> TC-248-12 red. | flutter test test/features/orbit/presentation/widgets/all_chats_signal_hierarchy_test.dart; AUTO; feature-host-all. |
| TC-248-13 | Conversation incoming and outgoing bubbles are visually distinct from canvas and from each other. | test/features/conversation/presentation/widgets/letter_card_test.dart::Signal incoming ivory and outgoing lavender bubbles use decorative borders and readable metadata | Host widget / existing LetterCard incoming/outgoing fixtures | HEAD surfaces use pale values and strong border -> GREEN incoming #FAF8F3, outgoing #E1DCE5, surfaceBorder, readable body/meta, alignment/radius unchanged. | Give both bubbles one fill, use control border, or change geometry -> TC-248-13 red. | flutter test test/features/conversation/presentation/widgets/letter_card_test.dart --plain-name 'Signal incoming ivory and outgoing lavender bubbles use decorative borders and readable metadata'; file already in ONE_TO_ONE_TESTS and GROUP_TESTS; 1to1, groups, feature-host-all. |
| TC-248-14 | A loaded Feed system card has a distinct filled bubble and readable label on the warm canvas. | test/features/feed/presentation/widgets/letter_card_system_signal_test.dart::loaded Signal system card is distinct from warm canvas without a heavy outline | Host widget / real SystemLetter | HEAD expects #EDEEF3 and pale/bright-green roles -> GREEN loaded card uses updated tokens, contrast passes, and fill differs from canvas/raised surface. | Revert Feed values or render transparent/same-as-canvas fill -> TC-248-14 red. | flutter test test/features/feed/presentation/widgets/letter_card_system_signal_test.dart; already in FEED_TESTS; feed and feature-host-all. |
| TC-248-15 | A Contact Profile pushed under Signal receives light root Material and semantic surfaces. | test/features/contact_profile/presentation/screens/contact_profile_screen_test.dart::pushed Contact Profile inherits Signal light ThemeData and warm scaffold | Host widget / Navigator push inside the inert Signal root-binding fixture | On the inert scaffold Signal still yields dark root brightness and the pushed route is dark -> GREEN route brightness light, scaffold/base roles warm, text readable, back behavior unchanged after TC-248-03. | Remove root light theme/extension or hardcode dark scaffold -> TC-248-15 red. | flutter test test/features/contact_profile/presentation/screens/contact_profile_screen_test.dart --plain-name 'pushed Contact Profile inherits Signal light ThemeData and warm scaffold'; AUTO; feature-host-all. |
| TC-248-16 | Attachment sheet is light under Signal and Cancel still only dismisses it. | test/features/conversation/presentation/screens/conversation_wired_test.dart::Signal attachment sheet uses warm semantic roles and Cancel preserves draft | Host widget / existing ConversationWired fakes, root Signal binding | HEAD caller context resolves the dark root -> GREEN raised/base light sheet, readable icons/text, Cancel closes with draft and staged attachments unchanged. | Restore fixed dark root, launch from an unthemed context, or make Cancel mutate draft -> TC-248-16 red. | flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name 'Signal attachment sheet uses warm semantic roles and Cancel preserves draft'; already in ONE_TO_ONE_TESTS; 1to1 and feature-host-all. |
| TC-248-17 | Conversation overflow uses light semantic chrome while introduce/unblock and block/delete colors stay meaningful and readable. | test/features/conversation/presentation/screens/conversation_wired_test.dart::Signal overflow popup uses warm surface with readable semantic actions | Host widget / overflow-capable contact fixture | HEAD popup surface/border are hardcoded dark -> GREEN light raised surface/surfaceBorder, success #2F7755, destructive #B4232F, dark branch literals preserved. | Restore hardcoded dark chrome or use light red/green below 4.5:1 -> TC-248-17 red. | flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name 'Signal overflow popup uses warm surface with readable semantic actions'; already in ONE_TO_ONE_TESTS; 1to1 and feature-host-all. |
| TC-248-18 | Delete-message sheet uses light semantic structure and Cancel/removal options retain behavior. | test/features/conversation/presentation/screens/conversation_wired_test.dart::Signal delete sheet uses warm roles and cancel leaves message unchanged | Host widget / existing incoming-row delete fixture | HEAD sheet/action chrome is hardcoded dark -> GREEN warm surface, decorative borders, readable prompt/cancel and distinct destructive actions; message remains after Cancel. | Restore white-on-dark literals for light or couple Cancel to deletion -> TC-248-18 red. | flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name 'Signal delete sheet uses warm roles and cancel leaves message unchanged'; already in ONE_TO_ONE_TESTS; 1to1 and feature-host-all. |
| TC-248-19 | Orbit find placeholder is explicit and AA-readable on its light field. | test/features/orbit/presentation/widgets/orbit_find_pill_ux_test.dart::Signal find placeholder uses semantic placeholder color with AA contrast | Host widget / representativeLight host and expanded find pill | HEAD hintStyle is null and resolves near-white under the dark root fixture -> GREEN #645F6A hint on its effective light field with >=4.5:1; typed text and close behavior unchanged. | Remove hintStyle or point it to dark/default hint color -> TC-248-19 red. | flutter test test/features/orbit/presentation/widgets/orbit_find_pill_ux_test.dart --plain-name 'Signal find placeholder uses semantic placeholder color with AA contrast'; AUTO; feature-host-all. |
| TC-248-20 | Settings background and photo-quality sheets receive light Material defaults as well as readable extensions. | test/features/settings/presentation/screens/settings_sub_sheets_test.dart::Signal settings sheets use light Material controls and warm semantic surfaces | Host widget / existing SettingsWired fakes and daylightLagoon state | HEAD nested extension is light but root ThemeData remains dark -> GREEN light brightness for sheet controls, warm surfaces, existing success persist-and-close and quality callbacks unchanged. | Remove root light theme, stop re-providing extension, or change immediate commit semantics -> TC-248-20 red. | flutter test test/features/settings/presentation/screens/settings_sub_sheets_test.dart; AUTO; feature-host-all. |
| TC-248-21 | Transport diagnostics are readable under Signal while refresh and privacy behavior remain intact. | test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart::Signal transport diagnostics use semantic light roles and refresh safely | Host widget / representativeLight theme plus real TransportMetrics | HEAD structural/text whites disappear on light -> GREEN warm cards, readable hierarchy, refresh output and redaction assertions remain. | Restore translucent white structural/text roles or expose private values -> TC-248-21 red. | flutter test test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart; AUTO; feature-host-all. |
| TC-248-22 | Introduction diagnostics are readable under Signal and destructive/success actions remain distinct. | test/features/settings/presentation/widgets/settings_introduction_debug_card_test.dart::Signal introduction diagnostics use semantic light roles and preserve action callbacks | Host widget / representativeLight theme, populated/loading/error fixtures | HEAD has no focused test and whites disappear on light -> GREEN semantic surfaces/text plus visible success/error actions and exact refresh/delete callback counts. | Restore white literals, collapse success/error colors, or miswire delete callback -> TC-248-22 red. | flutter test test/features/settings/presentation/widgets/settings_introduction_debug_card_test.dart; new AUTO feature test; feature-host-all. |
| TC-248-29 | Small online/retry success text is AA-readable on the actual alpha-blended status pill and Feed canvas. | test/features/p2p/presentation/widgets/connection_status_indicator_signal_test.dart::Signal online label and debug count meet AA on rendered light pill plus test/features/feed/presentation/screens/feed_focus_test.dart::Signal failed-reply retry text meets AA on Feed canvas | Host widget / connected service with count >0 plus failed session-reply light Feed fixture | HEAD debug count fades connectedHeading to 70% and measures about 2.43:1; proposed #2F7755 would also fail small text -> GREEN #236143 at full opacity for 11/12/12.5px text, with rendered effective-surface contrast >=4.5:1. | Restore withValues(alpha: 0.7), use filled-success #2F7755 as small text, or render the retry on an untested surface -> TC-248-29 red. | flutter test test/features/p2p/presentation/widgets/connection_status_indicator_signal_test.dart --plain-name 'Signal online label and debug count meet AA on rendered light pill' && flutter test test/features/feed/presentation/screens/feed_focus_test.dart --plain-name 'Signal failed-reply retry text meets AA on Feed canvas'; first AUTO feature, second already in FEED_TESTS; feature-host-all and feed. |
| TC-248-23 | Signal’s en/de/ar description truthfully names the warm violet/sage treatment. | test/core/l10n/app_localizations_signal_test.dart::en de ar Signal description is the exact warm mineral copy | Host unit / generated localizations | HEAD says cool porcelain/electric-violet star -> GREEN exact three strings after flutter gen-l10n. | Leave any locale stale or alter generated output without ARB source -> TC-248-23 red. | flutter test test/core/l10n/app_localizations_signal_test.dart; AUTO test/core l10n classification; core-host-all. |
| TC-248-24 | Scanner stays explicitly dark and usable under a Signal light root. | test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart::Signal root keeps scanner black with white camera chrome | GREEN sentinel / existing scanner fakes under AppTheme.lightTheme | After TC-248-01 scaffold this is GREEN on HEAD scanner implementation -> remains black/white with QR-only detection and close/flash affordances. | Replace scanner black/white with ambient light surface roles -> sentinel red. | flutter test test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart --plain-name 'Signal root keeps scanner black with white camera chrome'; AUTO; feature-host-all. |
| TC-248-25 | All dark presets and touched release widgets remain literal-preserved. | test/features/theme/dark_preset_preservation_test.dart::dark background presets resolve to dark readable/feed tokens and dark touched widgets render the transcribed literals | GREEN sentinel / existing dark fixtures extended for new surfaceBorder and overlays | GREEN on HEAD -> remains GREEN for Default/Cosmic/Aurora, root ThemeMode.dark, tokens, bubbles, popup/sheets, and no Signal blooms. | Change a dark token, mount light overlay branch on dark, or map a dark preset to light -> sentinel red. | flutter test test/features/theme/dark_preset_preservation_test.dart; AUTO; feature-host-all. |
| TC-248-26 | Every safe audited Signal state feels warm/dimensional and has no light/dark island at font scale 1.0. | artifacts/signal-theme-ui-acceptance-YYYY-MM-DD/README.md::TC-248-26 Pixel 6 font-scale-1.0 checklist plus numbered screenshots | Manual device acceptance / Pixel 6 21071FDF600CSC, Android 16, 1080x2400, existing local data | Current 2026-07-09 captures visibly fail the stated criteria -> GREEN reviewer records PASS for all named states, no pure-white canvas, clear surface hierarchy, coherent routes/sheets, readable controls, scanner dark. | N/A — aesthetic manual proof; automated TC-248-01..25 plus TC-248-28/29 own causal mutation coverage, and a non-permitted capture omission/failure blocks acceptance. | flutter devices --machine then flutter screenshot -d 21071FDF600CSC -o artifacts/signal-theme-ui-acceptance-YYYY-MM-DD/NN-state-scale-1.0.png per checklist; manual artifact registration. |
| TC-248-27 | The same audited state set remains readable, unclipped, and calm at font scale 1.3, then device scale is restored. | artifacts/signal-theme-ui-acceptance-YYYY-MM-DD/README.md::TC-248-27 Pixel 6 font-scale-1.3 checklist plus numbered screenshots | Manual device acceptance / same physical Pixel with system font_scale 1.3 | HEAD visual set was not captured at 1.3 and cannot establish acceptance -> GREEN every safe state has no clipping/overlap/hidden action or contrast regression, followed by restored font_scale 1.0. | N/A — manual large-text proof; omit a state, accept clipping, or fail to restore 1.0 and TC-248-27 fails. | adb -s 21071FDF600CSC shell settings put system font_scale 1.3; capture each state; adb -s 21071FDF600CSC shell settings put system font_scale 1.0; manual artifact registration. |

### Test Notes

- TC-248-03 discriminator: assert Theme.of(childContext).brightness changes while a state counter inside the same keyed child keeps its value; a route remount is not an acceptable substitute.
- TC-248-04 seeds AppShellController(initialTab: AppShellTab.feed) so switchTo(orbit) is a real notification, not a same-tab no-op. Identity and media-quality notifications are also real.
- TC-248-28 writes daylight_lagoon to FakeSecureKeyStore, mounts the initially-dark binding, calls the real loader, forwards its result to the real controller, and observes light brightness. Its source-contract sibling pins that StartupRouter still performs the same forwarding after initialShareIntentCapture.
- TC-248-08 measures roles against the surface where production renders them. surfaceBorder is explicitly decorative and is not mislabeled as a 3:1 control boundary. The test must include filled-success white content, small success text on canvas/subtle/success-fill, and every alpha-blended component surface.
- TC-248-08/10 intentionally update the old light-value assertions in ambient_background_test.dart, compose_area_tone_test.dart, empty_conversation_state_tone_test.dart, orbital_visualization_signal_test.dart, and the live-Signal case in dark_preset_preservation_test.dart. Do not weaken or relabel their dark assertions.
- TC-248-16 starts with non-empty text and a staged attachment, opens the sheet, taps Cancel, and asserts both survive. This distinguishes dismissal from accidental clearing.
- TC-248-17 must inspect the PopupMenu route’s rendered Material/shape and action Text/Icon colors; reading only the token object is insufficient.
- TC-248-18 extends the existing canceling-the-delete-sheet fixture so the behavioral row and visual row share the same real path.
- TC-248-29 computes contrast from the rendered pill decoration after alpha blending, not from the raw token alone. The connection-count fixture uses connectionCount > 0 so the 11px debug text is present.
- TC-248-26/27 required PASS state list: Signal Settings, Orbit, All Chats with loaded rows, Intros, Archived, conversation with loaded bubbles, empty conversation, overflow, attachment sheet, Contact Profile, create menu, new-group picker, chat search, Orbit find, loaded Feed, focused Feed composer, redacted My QR, live scanner, photo-quality sheet, Move Account, introduction picker, selected background chooser, and lower Settings diagnostics. The Android camera-permission prompt is the only allowed N/A: when permission is already granted, record the dumpsys granted=true line and do not revoke user state; when it is not granted, opening Scanner must show and capture the prompt as PASS. Any other N/A/omission blocks acceptance. Recovery phrase and destructive completions remain forbidden.

## Implementation Steps

1. Snapshot git status --short and save a scoped diff of every overlapping dirty file. Stop if an unrelated edit cannot be preserved; do not reset or replace it.
2. Root RED phase:
   - Add an inert AppTheme.lightTheme scaffold that delegates to darkTheme, plus an AppShellThemeBinding scaffold that always yields ThemeMode.dark and does not listen. This makes TC-248-01..03 behavioral assertion REDs rather than missing-symbol compile failures.
   - Add app_theme_test.dart, app_shell_theme_binding_test.dart, and app_root_theme_wiring_test.dart. Also add the pushed Contact Profile, attachment-sheet, and Settings-sheet fixtures from TC-248-15/16/20 against this inert root before implementing it; record that each still observes dark Material.
   - Implement the resolver, filtered listener lifecycle, AppTheme.lightTheme, and narrow main.dart wrapper. Run TC-248-01..07, TC-248-15/16/20, and TC-248-28 GREEN before palette edits.
   - Add/run TC-248-04 only after TC-248-03 is GREEN; it is a non-vacuous preservation sentinel for the now-active listener.
   - Stop-if: MaterialApp cannot preserve Navigator/StartupRouter state through a mode change; prove and resolve that lifecycle before continuing.
3. Palette RED phase:
   - Update the exact palette/contrast assertions first.
   - Add surfaceBorder structurally to field/constructor/copyWith/lerp with placeholder values equal to border, run the semantic RED, then assign the locked light and literal-preserving dark values.
   - Retune BackgroundReadableColors.representativeLight, FeedTokens.light, and Material ColorScheme from one locked mapping. Do not touch dark values.
4. Background RED phase:
   - Flip the existing white/transparent tests to exact warm gradient/blooms and assert tester.hasRunningAnimations is false.
   - Convert DaylightLagoonBackground to a static composition, rename blueWash/painter input to sageWash if needed, remove the controller/ticker/math drift, and keep RepaintBoundary with willChange false.
5. Filled-hierarchy RED phase:
   - Add/update TC-248-12..14, then switch only FriendRow, GroupRow, and LetterCard decorative outlines to surfaceBorder. Retune the existing loaded Feed Signal test through FeedTokens; preserve all geometry.
6. Propagation/overlay RED phase:
   - TC-248-15/16/20 were authored RED in the root phase and should now be GREEN. Add TC-248-17..19, TC-248-21/22, and TC-248-29 before their independent edits.
   - Root light fixes Contact Profile, attachment sheet, and Material defaults. Replace only the light branches of overflow/delete hardcodes with semantic roles; keep transcribed current dark constants on dark. Add the Orbit hintStyle.
   - Set connectedHeading and FeedTokens.green500 to #236143. Remove the 70% alpha from the 11px ready-state count so both it and the 12px label are measured at full semantic opacity.
   - Stop-if: a sheet is launched from a context that still cannot observe the root mode after TC-248-03; fix that exact caller seam rather than wrapping the whole feature in another ad hoc Theme.
7. Debug/l10n RED phase:
   - Add the light fixtures for both diagnostic cards and replace structural/text whites with BackgroundReadableColors roles; preserve action callbacks and privacy assertions.
   - Change the three ARBs, run flutter gen-l10n, and make the exact l10n test GREEN.
8. Preservation phase: add/extend TC-248-24/25 after the additive light root exists, then run them after every subsequent production slice. Inspect the dark overlay branches directly.
9. Harness registration: no family-array edit is expected. Run completeness-check; if a new test is unmatched, add the narrow classifier/glob required by the harness and document why.
10. Device acceptance:
    - Recheck the Pixel, build and install with flutter build apk --debug plus adb install -r so app data is preserved, verify com.mknoon.app in dumpsys, launch it, select Signal through production Settings, force-stop, and launcher-start once to prove stored restore.
    - Create artifacts/signal-theme-ui-acceptance-YYYY-MM-DD/README.md with device/build/commit, exact checklist, result per state, and paired scale-1.0/1.3 screenshot names.
    - Compare against artifacts/signal-theme-ui-audit-2026-07-09, redact contact/QR data, never open the recovery phrase, apply the single camera-prompt PASS/N/A rule from Test Notes, and restore the original font_scale in a shell trap/finally step.
11. Run focused GREEN, curated families, complete host gates, hygiene, and the physical acceptance profile. Update graphify-out with graphify update . and app architecture with ./graphify-arch/refresh_arch_graph.sh after code changes.

## Risks And Blind Spots

- Root MaterialApp rebuild could reset Navigator/home state -> TC-248-03 requires preserved keyed child state and live two-way switching; the binding rebuilds only the Material configuration.
- AppShellController is a broad notifier -> TC-248-04/05 lock change-kind filtering, replacement, no-op, and disposal.
- A softer card outline could weaken controls -> TC-248-09 separates surfaceBorder from border/inputBorder and names only three consumer families.
- One warm token could pass against the canvas but fail on lavender -> TC-248-08 measures all actual effective surfaces, including small muted/placeholder text.
- Filled success can be accessible while small green text is not -> TC-248-29 separates #2F7755 filled actions from #236143 success text/borders and forbids alpha-fading the small count.
- Static blooms could accidentally retain a silent ticker -> TC-248-10 asserts no running animation and willChange false in both motion modes.
- Root light alone cannot fix independent literals -> TC-248-17/18/21/22 inspect the rendered popup/sheet/cards.
- Physical screenshots can expose secrets -> device checklist requires redaction, forbids recovery phrase, and preserves the current identity/data.
- Lifecycle / derived-state durability: TC-248-02, TC-248-03, TC-248-05, GREEN sentinel TC-248-07, and integrated TC-248-28 cover initial mount, stored decode, real load/controller/binding restore, live transition, controller replacement, and dispose.
- Sibling-surface consistency: TC-248-15 through TC-248-22 cover pushed route, attachment, popup, destructive sheet, Settings sheets, Orbit search, and both debug-card siblings. Scanner is deliberately asymmetric under TC-248-24.
- Destructive-action side effects: TC-248-16 and TC-248-18 assert cancellation preserves draft/attachments/message; production delete behavior is not changed.
- Invariant re-verification under new transitions: TC-248-03 switches dark -> Signal -> dark on one mount; TC-248-25 repeats all dark preset resolution after the transition.

## Device/Relay Proof Profile

- Profile: single-device manual visual acceptance.
- Boundary being proven: real Android rendering, system font scaling, Material route/sheet composition, and the qualitative warm/dimensional result that token tests cannot fully prove.
- Live availability check: flutter devices --machine plus adb devices -l on 2026-07-09 observed supported physical Pixel 6 21071FDF600CSC, Android 16/API 36, USB attached; wm size 1080x2400 and font_scale 1.0. Recheck at execution.
- Required setup: Pixel 6 with current local identity/test data; exact commands flutter build apk --debug, adb -s 21071FDF600CSC install -r build/app/outputs/flutter-apk/app-debug.apk, and adb launcher start below; com.mknoon.app must be verified by dumpsys; Signal selected through Settings; no data clear/uninstall; contact and QR identifiers redacted.
- Closure role: required UX acceptance evidence after host causal gates; never a substitute for failed automated contrast, lifecycle, or widget tests.
- FLUTTER_DEVICE_ID: 21071FDF600CSC is sufficient for this single-device visual profile.
- Registration: manual checklist and numbered images in artifacts/signal-theme-ui-acceptance-YYYY-MM-DD/README.md; every required state is PASS. Only the OS-owned camera prompt may be N/A, and only with a recorded CAMERA granted=true dumpsys line. No classify_path or integration_test claim.
- Discovery command: flutter devices --machine -> Pixel 6 21071FDF600CSC must be listed supported and attached.
- Closure command pattern: use the exact build/install/start/cold-restart block and flutter screenshot -d 21071FDF600CSC -o artifacts/signal-theme-ui-acceptance-YYYY-MM-DD/NN-state-scale-X.png after manually navigating each checklist state; every required row must be PASS and the shell trap must restore original font_scale 1.0.
- Deferred device work: none for this plan. A second platform is optional follow-up, not claimed closure.

## Acceptance Gates

~~~bash
# Snapshot before execution; preserve unrelated/concurrent changes.
git status --short

# First behavioral RED after the inert binding scaffold; expect non-zero because
# the child still observes Brightness.dark after Signal is selected.
flutter test test/features/theme/app_shell_theme_binding_test.dart \
  --plain-name 'background notification switches root brightness live and preserves child state'

# Palette/background REDs before their production edits; expect non-zero for
# exact paper-white/transparent/ticker values, not compilation.
flutter test \
  test/core/theme/background_readable_colors_signal_test.dart \
  test/features/identity/presentation/widgets/daylight_lagoon_background_signal_test.dart

# Focused root/palette GREEN; expect exit 0 and zero failed tests.
flutter test \
  test/core/theme/app_theme_test.dart \
  test/core/theme/app_root_theme_wiring_test.dart \
  test/features/theme/app_shell_theme_binding_test.dart \
  test/core/theme/background_readable_colors_signal_test.dart \
  test/core/theme/background_readable_colors_test.dart \
  test/features/identity/presentation/widgets/daylight_lagoon_background_signal_test.dart \
  test/features/feed/presentation/widgets/feed_tokens_tone_test.dart

# Focused surface GREEN; expect exit 0 and zero failed tests.
flutter test \
  test/features/orbit/presentation/widgets/all_chats_signal_hierarchy_test.dart \
  test/features/conversation/presentation/widgets/letter_card_test.dart \
  test/features/feed/presentation/widgets/letter_card_system_signal_test.dart \
  test/features/contact_profile/presentation/screens/contact_profile_screen_test.dart \
  test/features/orbit/presentation/widgets/orbit_find_pill_ux_test.dart \
  test/features/settings/presentation/screens/settings_sub_sheets_test.dart \
  test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart \
  test/features/settings/presentation/widgets/settings_introduction_debug_card_test.dart \
  test/features/p2p/presentation/widgets/connection_status_indicator_signal_test.dart \
  test/features/feed/presentation/screens/feed_focus_test.dart \
  test/core/l10n/app_localizations_signal_test.dart

# Conversation overlays; expect each named test selected and zero failures.
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart \
  --plain-name 'Signal attachment sheet uses warm semantic roles and Cancel preserves draft'
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart \
  --plain-name 'Signal overflow popup uses warm surface with readable semantic actions'
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart \
  --plain-name 'Signal delete sheet uses warm roles and cancel leaves message unchanged'

# Preservation; expect exit 0 and the scanner/dark sentinels selected.
flutter test test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart \
  --plain-name 'Signal root keeps scanner black with white camera chrome'
flutter test test/features/theme/dark_preset_preservation_test.dart
flutter test test/features/settings/application/background_preference_use_cases_test.dart \
  --plain-name 'returns daylight lagoon when stored value is daylight_lagoon'

# Named families and complete host inventory; each must exit 0 with zero failures
# and completeness-check must classify every new test.
./scripts/run_test_gates.sh core-host-all
./scripts/run_test_gates.sh feature-host-all
./scripts/run_test_gates.sh feed
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check

# Touched-surface analyzer must report no issues. Full flutter analyze is also
# run and any existing unrelated debt is compared with the pre-edit snapshot.
flutter analyze \
  lib/core/theme \
  lib/main.dart \
  lib/features/identity/presentation/widgets/daylight_lagoon_background.dart \
  lib/features/orbit/presentation/widgets/friend_row.dart \
  lib/features/orbit/presentation/widgets/group_row.dart \
  lib/features/orbit/presentation/widgets/inner_circle_interactive_surface.dart \
  lib/features/p2p/presentation/widgets/connection_status_indicator.dart \
  lib/features/conversation/presentation/widgets/letter_card.dart \
  lib/features/conversation/presentation/screens/conversation_wired.dart \
  lib/features/settings/presentation/widgets/settings_introduction_debug_card.dart \
  lib/features/settings/presentation/widgets/settings_transport_diagnostics_card.dart
flutter analyze
git diff --check

# Device discovery plus data-preserving build/install/start. Expect the Pixel
# to remain listed, install -r to succeed, package metadata to be present, and
# pidof to return a running process. Never uninstall or clear package data.
flutter devices --machine
flutter build apk --debug
adb -s 21071FDF600CSC install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s 21071FDF600CSC shell dumpsys package com.mknoon.app \
  | rg 'versionCode=|versionName=|lastUpdateTime='
adb -s 21071FDF600CSC shell monkey \
  -p com.mknoon.app -c android.intent.category.LAUNCHER 1
adb -s 21071FDF600CSC shell pidof com.mknoon.app

# Record the OS-owned permission state. If granted=true, mark only the camera
# permission-prompt row N/A and do not revoke it. If false, opening Scanner must
# display the prompt and that state is a required PASS capture.
adb -s 21071FDF600CSC shell dumpsys package com.mknoon.app \
  | rg 'android.permission.CAMERA: granted='

# Select Signal manually through Settings, then prove stored cold-restart
# restoration without clearing data.
adb -s 21071FDF600CSC shell am force-stop com.mknoon.app
adb -s 21071FDF600CSC shell monkey \
  -p com.mknoon.app -c android.intent.category.LAUNCHER 1
adb -s 21071FDF600CSC shell pidof com.mknoon.app

# Capture all required states at 1.0 and 1.3. The trap plus explicit final
# restore protect device state even if a later capture command fails.
ACCEPT_DIR="artifacts/signal-theme-ui-acceptance-$(date +%F)"
mkdir -p "$ACCEPT_DIR"
original_font_scale=$(adb -s 21071FDF600CSC shell settings get system font_scale)
test "$original_font_scale" = "1.0"
trap 'adb -s 21071FDF600CSC shell settings put system font_scale "$original_font_scale" >/dev/null' EXIT
adb -s 21071FDF600CSC shell settings put system font_scale 1.0
flutter screenshot -d 21071FDF600CSC \
  -o "$ACCEPT_DIR/NN-state-scale-1.0.png"
adb -s 21071FDF600CSC shell settings put system font_scale 1.3
flutter screenshot -d 21071FDF600CSC \
  -o "$ACCEPT_DIR/NN-state-scale-1.3.png"
adb -s 21071FDF600CSC shell settings put system font_scale "$original_font_scale"
test "$(adb -s 21071FDF600CSC shell settings get system font_scale)" = "$original_font_scale"
trap - EXIT
~~~

## Execution Interpretation And Done Criteria

- Expected RED: TC-248-03 and TC-248-28 observe Brightness.dark after live/stored daylightLagoon updates with the inert binding; TC-248-08/10 observe the old paper palette, transparent blooms, and running ticker; TC-248-29 measures the 70%-alpha 11px count below AA.
- Green sentinel: TC-248-07 preserves daylight_lagoon persistence; TC-248-24 preserves the dark scanner; TC-248-25 preserves all dark preset/touched-widget literals.
- Pre-existing dirty tree / known failure: the planning snapshot already contains many unrelated modified/untracked files, including overlapping lib/main.dart, inner_circle_interactive_surface.dart, conversation_wired_test.dart, startup_router.dart, and scripts/run_test_gates.sh. Execution records the exact snapshot and classifies failures as expected RED, baseline dirt, environment, or scope drift before editing them.
- Environment blocker: none at planning time; Pixel 6 21071FDF600CSC is attached. A later disconnect blocks only TC-248-26/27 and therefore blocks final visual acceptance, not host diagnosis.
- Scope drift: any new preference/storage key, DB version, chooser workflow, layout/density/navigation change, scanner-light change, network/repository/Go edit, or loss of unrelated dirty work blocks completion.

- [ ] All 29 behavior rows have the named automated or manual evidence.
- [ ] Representative causal mutations are run and re-red at the root binding/restore, palette, background ticker, small-success alpha, overlay literal, and Orbit hint seams.
- [ ] Focused, family, core/feature host, completeness, and touched-analyzer gates pass with zero new failures/issues.
- [ ] New tests are AUTO-classified or their narrow required registration is recorded.
- [ ] Pixel 6 scale-1.0 and scale-1.3 artifact checklists pass, secrets are redacted, and font_scale is restored to 1.0.
- [ ] No migration is introduced and the Scope Contract And Guard is respected.

## Handoff

- First causal RED command: flutter test test/features/theme/app_shell_theme_binding_test.dart --plain-name 'background notification switches root brightness live and preserves child state' after adding the explicitly inert dark-only binding scaffold.
- Preservation command: flutter test test/features/theme/dark_preset_preservation_test.dart && flutter test test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart --plain-name 'Signal root keeps scanner black with white camera chrome'.
- Manual registration: TC-248-26 and TC-248-27 in artifacts/signal-theme-ui-acceptance-YYYY-MM-DD/README.md, with every required state PASS at both font scales; only the camera prompt may be N/A with recorded granted=true evidence.
- Migration: none; no DB version or new SecureKeyStore key.
- Boundary closure: host unit/widget tests are causal; final closure additionally requires the named single-Pixel visual profile.
- Unresolved evidence: none at planning time.

## Reviewer Findings

- An internal tdd-plan counterexample pass (not the formal tdd-review skill) found five material draft gaps: #2F7755 used as small success text failed AA; fresh-start restoration was overclaimed by a storage-only test; the background test had a false FEED_TESTS claim; the device runbook lacked literal install/restart and PASS/N/A rules; and many semantic light roles were still unspecified.
- The plan now separates #2F7755 filled success from #236143 small success text, adds rendered connection/Feed contrast proof, adds the real load/controller/binding restore composition plus StartupRouter source guard, corrects AUTO registration, locks every light token family, increases input-border margin, and makes the Pixel runbook deterministic.
- No reviewer blocker or unresolved evidence remains after that single structural fix pass. A formal tdd-review counterexample audit is still available before execution.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | not started | - | - | - | awaiting accepted/reviewed plan | contract extraction |
| 2026-07-10 | ALL host phases DONE | app_theme.dart, app_shell_theme_binding.dart (new), main.dart, background_readable_colors.dart, feed_tokens.dart, daylight_lagoon_background.dart, friend_row/group_row/letter_card, conversation_wired.dart, inner_circle_interactive_surface.dart, connection_status_indicator.dart, both diagnostic cards, en/de/ar ARB + gen-l10n, + all named tests | core-host-all exit 0; feature-host-all 168 pass + 1 sqlite3-github env flake (passes on retry, 112 tests isolated); feed/1to1/groups all "All tests passed"; completeness-check 1076/1076; touched-file `flutter analyze` clean; `git diff --check` clean | All 27 AUTOMATED rows (TC-01..25, 28, 29) GREEN. Each seam's mutation-sensitivity verified (binding-inert→dark RED, palette/ticker RED, 0.7-alpha→2.9:1 RED). No straggler old-literal tests; no external surfaceBorder constructors. | Device TC-26/27 (Pixel 6 24-state visual, scale 1.0/1.3) HANDED OFF — manual aesthetic sign-off + a concurrent session was live-editing android/ios on the shared tree, so a clean device build was deferred. Runbook + checklist at artifacts/signal-theme-ui-acceptance-2026-07-10/README.md. |
