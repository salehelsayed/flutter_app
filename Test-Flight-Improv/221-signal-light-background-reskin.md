# 221 - Replace the "Daylight Lagoon" Light Background with the "Signal" Palette

**Type: Feature Improvement** (UI / theming / accessibility)

> Approved design: `Test-Flight-Improv/221-light-ground-palette-alternatives-mockups.html` — the **Signal** column. This spec covers **problem + test cases only**. No solution, file edits, or implementation steps.

---

## 1. Problem Statement

The app ships four user-selectable background presets (Settings → Background): `defaultBackground`, `cosmic`, `cosmicMirrored`, and **`daylightLagoon`** — the *only* light preset. On the current Daylight Lagoon ground (`Colors.white` base + drifting violet/teal/pink pastel blooms) the UI is effectively unusable: content has no contrast to hold onto and several strings are literally invisible.

Five concrete, reproducible failures (see device screenshots for Orbit, Feed, Chat):

1. **Ghost text.** Hint/placeholder/meta text renders near-white on white and is unreadable:
   - Feed "tap to say hi" pill — mint fill with near-white label.
   - Chat composer placeholder "Write something…".
   - Chat empty-conversation hint "Send the first letter to start the conversation".
   - Feed "Connected" meta label.
2. **Vanishing orbit rings.** The two concentric dashed rings are painted in pale teal `0x4081E6D9` (α 0.25) and purple `0x33A78BFA` (α 0.20) tuned for dark grounds; on white they nearly disappear, destroying the "orbit" structure.
3. **Dead node glows.** Node halos are weak/washed out, so the "living constellation" metaphor falls flat on the light ground.
4. **Muddy ambient.** The violet/teal/pink blooms read as a smudge rather than intentional atmosphere.
5. **Black chat slab.** The chat composer bar is a hardcoded near-black gradient (`rgba(10,10,15,0.95)`) sitting directly against the white body — a jarring clash.

**Who is affected:** every user who selects Daylight Lagoon (the app's sole light option), on both iOS and Android. **When:** every render of every screen while that preset is active. Failure #1 is an accessibility defect (text fails WCAG AA contrast). There is **no workaround** other than abandoning the light preset entirely.

**Naming defect (secondary):** the preset's description string — *"A bright lagoon sky with soft pastel blooms"* — describes exactly the look being removed and will be factually wrong after the re-skin.

---

## 2. Impact Analysis

| Failure | Severity | Frequency | User-visible consequence | Workaround |
|---|---|---|---|---|
| #1 Ghost text | **Blocks use** (WCAG AA fail) | Every render, light preset | Cannot read hints, placeholders, meta, the Feed CTA pill | Switch off light preset |
| #2 Vanishing rings | Degrades | Every Orbit render, light preset | Orbit structure/affordance lost | Switch off light preset |
| #3 Dead glows | Degrades (cosmetic-adjacent) | Every render with nodes | Nodes look flat/dead | Switch off light preset |
| #4 Muddy ambient | Cosmetic | Every render, light preset | Background looks unfinished | Switch off light preset |
| #5 Black chat slab | Degrades | Every Chat render, light preset | Composer clashes; feels broken | Switch off light preset |

Contrast, measured on the current `representativeLight` / Feed / composer values (approximate, on the relevant local ground):

| Element | Current | Target (Signal) | AA (≥4.5 body / ≥3 large) |
|---|---|---|---|
| Feed "tap to say hi" pill text | ~1.4:1 | ≥6.9:1 | Fail → Pass |
| Chat placeholder | ~2.1:1 | ≥4.7:1 | Fail → Pass |
| Orbit rings vs ground | ~1.2:1 | ~3–4:1 (decorative) | Invisible → Visible |
| Body ink (textPrimary) | already dark | 15.3:1 | Pass → Pass |

---

## 3. Current State

### 3.1 Preset selection & tone mapping

| Concern | Location | Current behavior |
|---|---|---|
| Enum + storage key | `lib/features/settings/domain/models/background_preference.dart:7,21,36` | `daylightLagoon` ↔ storage string `'daylight_lagoon'` |
| Tone mapping | `lib/core/theme/background_readable_colors.dart:104-126` | `resolve()` → `toneForPreference()` maps `daylightLagoon → representativeLight`; the 3 dark presets → `dark` |
| Wiring | `lib/features/identity/presentation/widgets/ambient_background.dart:113-147` | `build()` switch selects the ground widget, injects the resolved `BackgroundReadableColors` `ThemeExtension`, sets `AnnotatedRegion<SystemUiOverlayStyle>` |

### 3.2 The light ground

`lib/features/identity/presentation/widgets/daylight_lagoon_background.dart`: `baseColor = Colors.white` (L19), `violetBloom 0xFF818CF8` (L20), `tealBloom 0xFF81E6D9` (L21), `pinkBloom 0xFFF472B6` (L22); `_DaylightLagoonPainter` paints the three blooms at α 0.30 / 0.22 / 0.18 (L146/157/168). Reduced-motion (`disableAnimations || accessibleNavigation`) freezes to a static frame (L65-81).

### 3.3 `representativeLight` readable tokens

`lib/core/theme/background_readable_colors.dart:80-102` — the token set (`textPrimary 0xFF101318`, `placeholder 0xFF566173`, `inputFill 0xFFFFFFFF`, surfaces, glass, borders, `statusBarIconBrightness: dark`). Consumed app-wide via `context.backgroundReadableColors` / `isLightSurface`. **Scope-safety (verified):** in production `representativeLight` is reachable **only** through the `daylightLagoon` arm — no other screen forces it. Editing its *values* therefore affects only the light preset in production.

### 3.4 What is already tone-aware vs. hardcoded-global

This is the crux of the FULL scope: the light preset cannot be fully realized by editing `representativeLight` alone, because many elements ignore tone.

| Element | Source (file:line) | Current color | Tone-aware today? |
|---|---|---|---|
| Contact ring borders, node name text | `orbital_visualization.dart:116-117,394-401` | from `readableColors.border` / `textPrimary` | **Yes** (flips with `representativeLight`) |
| Find pill / chips chrome | `inner_circle_interactive_surface.dart:~1029,1082,1169` | `glassSurface`/`glassBorder` | **Yes** |
| Settings background-choice chrome | `background_choice_control.dart:188,204-235` | `backgroundReadableColors` roles | **Yes** |
| Online pill text/opacity | `connection_status_indicator.dart:152-200` | base hue Material green/amber/grey; text darkens on light | **Partial** (hue global, text/opacity tone-aware) |
| **Orbit rings + glow** | `orbital_ring_painter.dart:42-44` | `_tealDash 0x4081E6D9`, `_purpleDash 0x33A78BFA`, `_tealGlow 0x1481E6D9` (static const; painter takes no color params) | **No — global** |
| **CTA "+" (GlowFab)** | `glow_fab.dart:25,27,32`; `expandable_fab.dart:101,152,173-183` | bg `0xFF1A1A2E`, border/glow `0xFF64B5F6`, white icons, black scrim | **No — global** |
| **Nav bar (whole theme)** | `nav_bar_theme.dart:15-64` | bar white α .18/.10, active/inactive `Colors.white*`, badge `0xFFFF3B30→0xFFE0342A` | **No — global** |
| Avatar glow | `user_avatar.dart:180-201` + `ring_avatar_generator.dart:280-289` | per-peer HSL glow (deterministic) | **No — global** |
| Avatar photo-frame | `user_avatar.dart:214-249` | border white .35, fill `rgba(22,24,30,.7)` | **No — global** |
| Unread orbit accent | `unread_orbit_indicator.dart:40` | `kUnreadAccent 0xFF1DB954` (green) | **No — deliberately theme-independent** (asserted by TC-194-30) |
| **Feed pill / "Connected" / check** | `letter_card_system.dart:33-61`, `letter_bubble.dart:224-230`, tokens in `feed_tokens.dart:79-104` | `FeedTokens.dark` only: `green500 0xFF22C55E`, `greenFill15 0x2622C55E`, `textMeta 0xB8C9CED6` | **No — global.** `FeedTokens.dark` is the ONLY variant; registered in `app_theme.dart:35`; `ambient_background.dart` never swaps a light FeedTokens → the **entire Feed surface is tone-blind** |
| **Chat composer bar** | `compose_area.dart:318-322,401-450,502-522` | bar `[transparent→rgba(10,10,15,.95)]`, field white .06, hint white .2/.3, send `0xFF1DB954` | **No — global** |
| **Chat "Connected!" + empty hint** | `empty_conversation_state.dart:62-91,130-182` | title `0xFF1DB954`, hint white .5, date white .35, avatar glow teal | **No — global** |
| **Mic button** | `voice_record_button.dart:26,73-111` | `0xFF1DB954` green | **No — global** |

### 3.5 Design target — the Signal palette (approved)

| Token | Signal value | Contrast on Signal ground |
|---|---|---|
| Ground base | `#EDEEF3` porcelain, radial `#F5F6FA→#EEEFF4→#E7E9F0` | — |
| Ambient washes | violet `rgba(90,36,224,0.05)` top-right; blue `rgba(46,90,200,0.04)` bottom-left (2 only) | — |
| textPrimary | `#16181F` | 15.3:1 (AAA) |
| textSecondary | `#4A4E5C` | 7.15:1 (AA) |
| textMuted / hint | `#656A79` | 4.66:1 (AA) |
| placeholder | `#6A6F7E` on input `#F7F8FB` | 4.72:1 (AA) |
| Orbit rings | ink-violet `rgba(70,58,150,0.28)` outer / `rgba(70,58,150,0.38)` inner | ~3–4:1 (decorative, visible) |
| Accent (CTA +, nav-active, mic) | electric violet `#5A24E0` | — |
| Node self | `#5A24E0`, glow `rgba(90,36,224,0.50)` | — |
| Node contact/target | `#E5484D`, glow `rgba(229,72,77,0.45)` | — |
| Connected/online green | `#0C7C46`; pill bg `#DFF3E9`, pill text `#0A5D34` | 6.9:1 (AA) |
| Chat bar | porcelain `#E6E7EE`, white input well `#F7F8FB` | — |
| Status/nav-bar icons | dark (light surface) | — |

Semantic node meaning is unchanged everywhere: **contact = red/target, self = violet, connected/online = green.**

### 3.6 l10n & tests

- **l10n:** keys `settings_background_daylight_lagoon` / `_desc` / `_selected` in `lib/l10n/app_en.arb:407-409` (+ `app_de.arb`, `app_ar.arb`). `lib/l10n/app_localizations*.dart` are **generated** (`flutter gen-l10n`, per root `l10n.yaml`) — regenerated, never hand-edited.
- **Existing tests (targets):** `test/core/theme/background_readable_colors_test.dart` (mapping + **WCAG contrast gate** L88-110 — note it measures text against `surfaceBase 0xF7FFFFFF` / `inputFill 0xF2FFFFFF`, **not** the `#EDEEF3` ground, and its field list is fixed so new tokens don't auto-enroll); `test/features/identity/presentation/widgets/ambient_background_test.dart` (asserts `DaylightLagoonBackground` present + **`decoration.color == Colors.white` L408**; siblings to preserve: `==representativeLight` L396, `statusBarIconBrightness dark` L402); `test/features/settings/presentation/widgets/background_choice_control_test.dart` (asserts literal **`find.text('Daylight Lagoon')` L54**); `test/features/orbit/presentation/widgets/orbital_visualization_test.dart` (TC-194-30: unread accent stays green); `test/features/p2p/presentation/widgets/connection_status_indicator_test.dart`; `integration_test/settings_background_choice_smoke_test.dart`. **No golden/screenshot tests exist** for any background/theme.
- **Absent coverage:** no test for `daylight_lagoon_background`, `orbital_ring_painter`, `nav_bar_theme`, `glow_fab`, `compose_area`, `empty_conversation_state`, or Feed-surface legibility on a light ground.

---

## 4. Scope Clarification

| Area | Status |
|---|---|
| `daylightLagoon` preset visual identity → Signal (ground, ambient, ink, rings, node glows, accent, nav, CTA, online pill, Feed pill/labels, chat composer + empty state + mic) | **In scope** |
| Rename display **label** "Daylight Lagoon" → "Signal" and description → "A cool porcelain sky with one electric-violet star." (en/de/ar) | **In scope** |
| Enum value name & **storage key `'daylight_lagoon'`** | **Unchanged** (no migration; existing selections keep resolving to the re-skinned preset) |
| The 3 dark presets (`defaultBackground`, `cosmic`, `cosmicMirrored`) | **Must stay pixel-identical** — any newly tone-aware global must default to today's exact constants |
| Semantic node color *meaning* (red contact / violet self / green connected) | **Unchanged** |
| Unread-orbit accent green (`kUnreadAccent`) staying a theme-independent signal | **Unchanged** (stays green on all grounds) |
| Orbit geometry / layout / ring radii / node seating | **Unchanged** (colors only) |
| Adding/removing background presets; a user-facing light/dark auto mode | **Out of scope** |
| Dark-theme visual tuning | **Out of scope** |

---

## 5. Test Cases

IDs `TC-221-NN`. Behavior-focused and falsifiable. "Light preset" = the re-skinned Signal preset (storage key `daylight_lagoon`); "a dark preset" = one of the 3 dark grounds. Contrast assertions use the standard WCAG formula already used by `background_readable_colors_test`.

### Group A — Ground & ambient (fixes #4)
- **TC-221-01** With the light preset active, the shared ground base is the Signal porcelain (`#EDEEF3` family), **not** `Colors.white`. (Regression target: `ambient_background_test` white-base assertion must be updated to the new base.)
- **TC-221-02** The light ground shows at most two low-opacity ambient washes (violet + blue); the previous teal and pink blooms are absent.
- **TC-221-03** With OS reduce-motion on (`disableAnimations`/`accessibleNavigation`), the light ground renders a **static** frame (no animation controller running) and still shows the Signal ground + washes.
- **TC-221-04** Switching from a dark preset to the light preset at runtime (Settings) repaints the ground to Signal within one frame, with no leftover pastel blooms.

### Group B — Text legibility & contrast (fixes #1, the accessibility core)
- **TC-221-05** On the Signal ground, `textPrimary` contrast ≥ 7:1 (AAA target 15.3:1); `textSecondary` ≥ 4.5:1; `textMuted` ≥ 4.5:1.
- **TC-221-06** The `representativeLight` **input placeholder** color has ≥ 4.5:1 contrast against `inputFill`.
- **TC-221-07** The existing WCAG contrast gate in `background_readable_colors_test` passes for the new Signal `representativeLight` (no token regresses below its required threshold).
- **TC-221-08** Feed "tap to say hi" pill: label text ≥ 4.5:1 against the pill fill on the light preset (currently ~1.4:1). The label is visibly readable in a widget render.
- **TC-221-09** Feed "Connected" meta label and the verified-check are legible (≥ 4.5:1 / clearly visible) on the light preset.
- **TC-221-10** Chat composer placeholder "Write something…" is ≥ 4.5:1 against the composer input fill on the light preset.
- **TC-221-11** Chat empty-conversation hint "Send the first letter to start the conversation" is ≥ 4.5:1 on the light preset.
- **TC-221-12** Chat "Connected!" heading is legible (green `#0C7C46`-family) with ≥ 3:1 large-text contrast on the light preset.

### Group C — Orbit rings visible (fixes #2)
- **TC-221-13** On the light preset the two orbit rings render in the Signal ink-violet family at a weight giving ≥ 3:1 against the ground (i.e. clearly visible), not the pale teal/purple.
- **TC-221-14** On each of the 3 dark presets the rings render in the **exact current** teal `0x4081E6D9` / purple `0x33A78BFA` / glow `0x1481E6D9` — pixel-identical to today.
- **TC-221-15** The `198` overflow arcs inherit the same tone-appropriate ring colors as the two base rings (still alternating outer/inner) on both light and dark.

### Group D — Node glows & semantics (fixes #3)
- **TC-221-16** On the light preset, the self node and contact nodes show a visible glow halo (stronger than today's washed-out light-ground appearance).
- **TC-221-17** Node semantic hues are preserved on every preset: contact/target reads red, self reads violet, connected/online reads green.
- **TC-221-18** The unread-orbit indicator accent stays green (`kUnreadAccent`) on the light preset (TC-194-30 must still pass).

### Group E — Accent (electric violet)
- **TC-221-19** On the light preset the CTA "+" button (GlowFab) uses the Signal electric-violet accent (not the dark `0xFF1A1A2E`/blue), and its icon stays legible against it.
- **TC-221-20** On the light preset the active nav-bar tab and the composer mic button use the Signal accent and remain legible.
- **TC-221-21** On the 3 dark presets the CTA, nav bar, and mic render pixel-identical to today.

### Group F — Chat composer harmonized (fixes #5)
- **TC-221-22** On the light preset the composer bar background is a light porcelain surface (not the near-black `rgba(10,10,15,.95)` slab); it visually belongs to the light ground.
- **TC-221-23** On the light preset the composer input field, attach "+", and icons are legible on the light bar.
- **TC-221-24** On the 3 dark presets the composer bar is pixel-identical to today.

### Group G — Feed surface legibility
- **TC-221-25** On the light preset the Feed letter card system (system bubble / "tap to say hi") renders legibly end-to-end (fill + border + text all readable), given that `FeedTokens.dark` is the only variant today.
- **TC-221-26** On the 3 dark presets the Feed surface renders pixel-identical to today.

### Group H — Online status pill
- **TC-221-27** On the light preset the "Online" pill text/dot/fill are legible (≥ 4.5:1 text) while keeping the green "online" semantic; connecting=amber, offline=muted still read correctly.

### Group I — Naming & settings
- **TC-221-28** The Settings background list shows the label **"Signal"** (not "Daylight Lagoon") in en; the description reads the new porcelain/violet copy. (Regression target: `background_choice_control_test` literal text must be updated.)
- **TC-221-29** de and ar localizations show translated "Signal" label + description; no missing-key fallback to the raw key.
- **TC-221-30** Selecting "Signal" persists storage string `'daylight_lagoon'`; a fresh app launch restores the Signal preset from that stored value.
- **TC-221-31** A user who had `'daylight_lagoon'` stored **before** this change still resolves to the (now re-skinned) Signal preset after upgrade — no reset to default, no crash on the unchanged key.
- **TC-221-32** The selected-state check icon and picker chrome remain legible on the light preset within the settings sheet.

### Group J — Regression: dark presets & live switching
- **TC-221-33** For each of `defaultBackground`, `cosmic`, `cosmicMirrored`: the ground, rings, nodes, nav, CTA, composer, Feed, and all `dark` readable tokens are unchanged vs. the pre-change build (`toneForPreference` still returns `dark`; `BackgroundReadableColors.dark` values untouched).
- **TC-221-34** Toggling Settings between Signal and each dark preset repeatedly leaves no stale colors, ghost blooms, or wrong-tone chrome on any surface.
- **TC-221-35** Backgrounding/foregrounding the app and rotating the device on the light preset preserves the Signal appearance (no revert to white or to dark chrome).

### Group K — Cross-screen coverage (light preset legible everywhere)
- **TC-221-36** Orbit home: rings, nodes, labels, CTA, nav, find pill, online pill all legible on the light preset.
- **TC-221-37** Feed: title, cards, pill, connection row all legible on the light preset.
- **TC-221-38** 1:1 Chat: header, connected/empty state, composer, mic all legible on the light preset.
- **TC-221-39** Settings, Group list/info, Posts, Introduction, QR, Account-migration screens: primary text, surfaces, inputs, and icons are legible on the light preset (no white-on-white, no dark-on-dark).

### Group L — Platform chrome
- **TC-221-40** On the light preset the OS status-bar and navigation-bar icons render **dark** (`statusBarIconBrightness == Brightness.dark`) on iOS and Android; on the 3 dark presets they stay light.

### Group M — End-to-end / device
- **TC-221-41** On a physical iPhone and a physical Android: select Signal, then visit Orbit, Feed, and a 1:1 Chat. All five original failures (ghost text, vanishing rings, dead glows, muddy ambient, black chat slab) are visibly resolved; a reviewer confirms every string in Group B is readable.
- **TC-221-42** Full host widget-test gate (`flutter test` over the theme/background/orbit/feed/conversation suites listed in §3.6) passes green after the change, including the updated assertions in TC-221-01/07/08/28.

---

### Evidence-thin areas (flag for implementer)
- **Feed surface (`FeedTokens`)** has no light variant and is never swapped by preference — Group G legibility is currently impossible without introducing a light path; the spec asserts the *outcome* (legible), leaving the mechanism to the plan.
- **Avatar glow** (`glowColorForPeerId`) is per-peer deterministic HSL; whether it needs a light-ground adjustment beyond "visible halo" (TC-221-16) is a judgment call for the design/plan.
- No golden tests exist, so Group C/D/E/F "pixel-identical" dark-preset regressions (TC-221-14/21/24/26/33) must be asserted via **color-value equality** in widget tests (and device spot-check TC-221-41), not screenshots.
