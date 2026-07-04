# 209 - Settings "One Screen" redesign + My QR / Scan migration from Orbit

**Feature Improvement**

User request (2026-07-04): "Under the Orbit screen, when I click on my profile picture, the settings page is opened. I want to migrate the QR code icon and the Scan icon to be part of the settings page, under the main nickname and the profile picture. I also want to improve the settings page."

Chosen direction (from the four-option exhibit `209-settings-qr-scan-migration-mockups.html`): **Option C — "One Screen"**: profile header → two large My QR / Scan tiles → grouped rows with values; the whole page fits a reference viewport without scrolling; the Orbit top-chrome QR pair retires.

---

## 1. Problem Statement

### Current behavior

1. **My QR and Scan live on the Orbit screen's top chrome.** `OrbitQrChromeButtons` renders twin 40×40 icon-only circles at top-center of both Orbit surfaces (`orbit_qr_chrome_buttons.dart:33-53`, mounted at `orbit_screen.dart:602-603`, landed as 196 "Option B"). Their labels ("My QR", "Scan") exist only as accessibility semantics — sighted users see two unlabeled glyphs in the worst thumb-reach zone of the screen.
2. **Settings is now the app's identity surface, but has no path to the QR.** Since 206, tapping the Orbit center self-avatar opens Settings (`orbit_wired.dart:616-644`), which shows the avatar, editable nickname, and the peer ID — everything the QR encodes (`build_qr_payload_use_case.dart:57-103`: `{ns: peerId, pk, rv, ts, un: username, sig}`) — yet neither showing one's own QR nor scanning a friend's is possible from it.
3. **The Settings page is a long, undifferentiated stack of always-expanded control cards.** Render order (`settings_screen.dart:169-240`): profile → Peer ID card → Background chooser (4 always-visible option rows) → Photo Quality segmented control → Video Quality segmented control → Nearby switch card → Move-account card → Recovery-phrase card (→ debug cards). That is roughly 2.5 screens of scrolling on a 390×844 viewport with no section grouping; rarely-changed controls (background wallpaper, recovery phrase) permanently occupy the same visual weight as identity.

### What is missing / insufficient

- The two contact-growth actions (show my QR, scan a friend's) are disconnected from the identity they operate on and are minimally discoverable.
- The Settings page has no information hierarchy: no grouping, no at-a-glance values, no way to see the whole surface at once.

### Who is affected

All users, both platforms (iOS + Android), both Orbit surfaces (inner-circle and all-chats), every time they add a friend by QR or open Settings. RTL (Arabic) users additionally get a forced-LTR chrome pair today (`orbit_qr_chrome_buttons.dart:38`).

---

## 2. Impact Analysis

- **Severity:** degrades experience (discoverability + navigation efficiency). No data loss, no crash, no security issue.
- **Frequency:** every QR-based contact add and every Settings visit.
- **Workarounds:** none for "QR from Settings" (the user must back out of Settings, find the unlabeled orbit chrome). Scrolling is the only way to survey Settings.

| Scenario | Today | Consequence |
|---|---|---|
| User in Settings wants to show their QR | No affordance anywhere on the page | Must pop to Orbit, locate icon-only chrome at top |
| User wants to scan a friend's code | 40px unlabeled glyph, top-center reach zone | Low discoverability; label is screen-reader-only |
| User checks which background / quality is active | Must scroll to each card; selection state only visible inside the expanded control | ~2.5 screens of scanning for a 1-line answer |
| User on RTL locale | Orbit chrome pair forced LTR (geometric compromise) | Non-mirrored UI in a context that no longer requires it |
| Orbit ceremony | 4 floating chrome circles compete at top of the constellation | Visual noise on the app's signature screen |

---

## 3. Current State

### 3.1 Key files

| File | Role | Key lines |
|---|---|---|
| `lib/features/orbit/presentation/widgets/orbit_qr_chrome_buttons.dart` | The twin QR/Scan chrome circles (retires) | keys `orbit-my-qr-button` :42 / `orbit-scan-button` :49; `Semantics(button)` :76-78; forced `TextDirection.ltr` :38; layer contract docstring :5-19 |
| `lib/features/orbit/presentation/screens/orbit_screen.dart` | Mounts the chrome pair, hidden while inner-editing (205 item 6) | :600-603 |
| `lib/features/orbit/presentation/screens/orbit_wired.dart` | `_onMyQR` :2220-2234 (pushes `QRDisplayWired` :2223 — the ONLY push site app-wide); `_onScanQR` :2271-2342 (pushes `QRScannerWired` :2275); post-scan refresh `.then(_applyRouteChanges)` :2341; `externalRouteChangesListenable` :2253-2268; `AppShellChangeKind.identity` consumer :538 | |
| `lib/features/orbit/presentation/widgets/qr_action_cards.dart` | Dead pre-196 widget, referenced only by its own test | whole file |
| `lib/features/settings/presentation/screens/settings_screen.dart` | Pure-UI Settings page; sticky glass header :107-161; card order :169-240; nav pill mount :248-259 | |
| `lib/features/settings/presentation/screens/settings_wired.dart` | All Settings behavior: copy peerId :142-154, mnemonic reveal :156-180, background :201-255, photo/video quality :257-284, nearby :294-310, username :399-438, avatar :440-500, move account :507-530, debug cards :537-573, nav switch :502-505 | |
| `lib/features/settings/presentation/widgets/*` | `settings_profile_section.dart` (avatar 100px + 32px teal badge), `settings_peer_id_card.dart`, `background_choice_control.dart`, `image_quality_toggle.dart`, `posts_nearby_settings_card.dart`, `settings_move_account_card.dart`, `settings_recovery_phrase_card.dart`, 2 debug cards | each used ONLY by `settings_screen.dart` (verified; contact-profile has its own private `_buildPeerIdCard` copy in `lib/features/contact_profile/presentation/screens/contact_profile_screen.dart`, not the widget) |
| `lib/features/qr_code/presentation/screens/qr_display_wired.dart` | QR display; needs only identityRepo + bridge + backgroundPreference + `onScanPressed` cross-link | :21 |
| `lib/features/qr_code/presentation/screens/qr_scanner_wired.dart` | Scanner; ~30 deps whose bulk exists to rebuild a fresh `FeedWired` after the success dialog :384-434; five `_missing*` StateErrors :558-582; account-migration-QR branch :155 | |
| `lib/features/feed/application/app_shell_controller.dart` | `AppShellChangeKind { tab, background, identity, mediaQuality }` :14; consumers `feed_wired.dart:2477/2481/2492`, `orbit_wired.dart:538` | |
| `lib/features/posts/presentation/screens/posts_wired.dart` | Second Settings entry point (`showNavigationBar: false`) | :539 |
| `lib/features/first_time_experience/.../first_time_experience_wired.dart` | Independent `QRScannerWired` push site (onboarding) — NOT an orbit chrome dependent | :552 |

### 3.2 Data flow today

- **My QR:** chrome tap → `orbit_wired._onMyQR` → push `QRDisplayWired` (payload from `build_qr_payload_use_case.dart:57-103`; ML-KEM key deliberately excluded :55-56). Its embedded `ScanFriendCard` ("Scan a friend's code") cross-links to the same `_onScanQR`.
- **Scan:** chrome tap → `orbit_wired._onScanQR` → push `QRScannerWired`. Scan result branches: (a) account-migration pairing QR → `onMigrationQrScanned` → `AccountMigrationJourneyWired.oldPhone` (`orbit_wired.dart:2313-2337`); (b) contact QR → parse/validate (24h expiry, self-scan rejection, Ed25519 verify in `parse_qr_payload_use_case.dart`) → `addContact` → success dialog → OK does `pushAndRemoveUntil` into a freshly-built `FeedWired` (`qr_scanner_wired.dart:384-434`) + fire-and-forget mutual `sendContactRequest` + profile-picture download; (c) invalid/expired/self → error snackbars. Orbit refreshes its data on scanner pop via `.then(_applyRouteChanges)`.
- **Settings changes** propagate by a single mechanism: `SettingsWired` fires `AppShellChangeKind.identity` / `.mediaQuality` / background setter on the shared `AppShellController`; `FeedWired` and `OrbitWired` consume (206's INV-206-6; no `.then` duplicates).

### 3.3 Constraints

- **l10n:** `orbit_my_qr` ("My QR"/"رمزي"), `orbit_scan` ("Scan"/"مسح") exist in en/ar/de (INV-196-8). 47 `settings_*` keys with en/ar parity, including `settings_share_nearby(_on/_off/_desc)`, `settings_move_account_*` incl. "Start move", `settings_recovery_*`, `settings_peer_id_*`. `l10n_integrity_test.dart:45` forbids new hardcoded UI literals in feature widgets.
- **Accessibility:** both chrome buttons expose `Semantics(button: true)` with l10n labels; the 206 center-avatar entry requires ≥48px + button semantics.
- **No feature flags, no golden tests, no TODO/FIXME, no skipped tests** in the settings/qr_code/orbit-chrome areas.
- **196 invariants** (from `196-orbit-qr-scan-entry-migration-tdd-plan.md:147-154`): INV-196-1/4/5/6 (chrome placement/geometry/layering on Orbit) are what this change retires; **INV-196-7 (handler bodies + destination contracts: B6 dep bundle, ScanFriendCard thread, noIdentity state, ownPeerId self-scan rejection) and INV-196-8 (strings live in en/ar/de) must survive at the new host.**
- **206 invariants** (from `206-orbit-center-avatar-settings-entry-tdd-plan.md:230-235`): INV-206-1..6 all constrain this change — center-avatar entry mechanics, single-flight `_settingsRouteActive` latch, idle-surface-only open, and single-mechanism change-kind propagation stay untouched. `orbit_settings_entry_test.dart` (GROUP_TESTS gate) asserts the orbit-opened Settings page shows the title "Settings", the nearby control, and key `settings-move-account-action` (TC-206-02/23).

### 3.4 Existing tests that lock the current layout (inventory, factual)

| Test file | Gate | Fate under this change |
|---|---|---|
| `test/features/orbit/presentation/widgets/orbit_qr_chrome_buttons_test.dart` (10 tests) | auto-glob | Entire file targets the retiring widget |
| `test/features/orbit/.../orbit_qr_entry_migration_test.dart` (19 tests, 196 suite) | GROUP_TESTS (`run_test_gates.sh:254`) | Every chrome-on-orbit assertion (keys, `find.text('My QR')`) targets removed UI; destination-contract assertions (TC-07/08/09/10/11) express behavior that must be re-locked at the new host |
| `test/features/settings/.../settings_screen_test.dart` (15 tests) | auto-glob | Layout assertions (always-expanded cards, section titles, `background-choice-*` keys) target the replaced layout |
| `test/features/settings/.../settings_wired_test.dart` (20 tests) | auto-glob | Behavior locks survive conceptually; finders assume inline controls (copy icons, "Tap to reveal", quality segments, background options) |
| `test/features/settings/.../settings_wired_posts_nearby_test.dart` (3 tests) | auto-glob | Survives if inline switch + "Share People Nearby" text kept |
| `settings_profile_section_test.dart` (11), `settings_peer_id_card_test.dart` (9), `settings_recovery_phrase_card_test.dart` (12), `posts_nearby_settings_card_test.dart` (3) | auto-glob | Widget-level; survive to the extent widgets are reused |
| `test/features/orbit/.../orbit_settings_entry_test.dart` (14 tests, 206 suite) | GROUP_TESTS (:231) | Entry mechanics survive; TC-206-02/23 assert Settings-page content (title, nearby text, move key) |
| `qr_display_wired_test.dart` (12), `qr_scanner_wired_test.dart` (7, BASELINE gate :10) | BASELINE/auto | Screen-internal; survive. `qr_scanner_wired_test` "forwards Move Account runner into feed" locks the post-scan FeedWired-rebuild contract |
| `qr_action_cards_test.dart` (6) | auto-glob | Tests a dead widget |

---

## 4. Scope Clarification

| Area | Status | Note |
|---|---|---|
| Settings page layout (One Screen: profile header → QR/Scan tiles → grouped rows with values → sub-sheets) | **IN SCOPE** | The redesign itself |
| My QR + Scan entry points: remove from Orbit chrome, add to Settings under avatar+nickname | **IN SCOPE** | The migration itself |
| `OrbitQrChromeButtons` retirement + its `orbit_screen` mount + its tests | **IN SCOPE** | |
| Dead `qr_action_cards.dart` + its test | **IN SCOPE** (removal) | Already unreferenced |
| Post-scan navigation contract when the scanner is launched from Settings | **IN SCOPE** (behavior must be defined + tested; see TC group F) | Outcome-level only; how it is achieved is a solution decision |
| Orbit data refresh after a scan performed from Settings | **IN SCOPE** (outcome: orbit reflects the new contact) | Mechanism is a solution decision |
| `QRDisplayWired` / `QRScannerWired` internal behavior (payload build/parse, camera, success dialog content, mutual add, expiry/signature rules) | **OUT OF SCOPE — must not change** | INV-196-7 |
| QR payload format | **OUT OF SCOPE — must not change** | `{ns,pk,rv,ts,un,sig}`, 24h expiry |
| First-time-experience onboarding scanner entry (`first_time_experience_wired.dart:552`) | **OUT OF SCOPE — must not break** | Independent push site |
| Account-migration journey internals; migration-QR handling from the migration screens | **OUT OF SCOPE** | Only the Settings-hosted scanner's migration branch is in scope (must keep working) |
| 206 center-avatar → Settings entry (detector, latch, idle-only rule) | **OUT OF SCOPE — must not change** | INV-206-1..5 |
| `AppShellChangeKind` propagation mechanism | **OUT OF SCOPE — must not change** | INV-206-6; the redesigned controls must keep firing the same kinds |
| Contact-profile screen's private peer-ID card | **OUT OF SCOPE** | Own copy, not the settings widget |
| Nav pill design/behavior; `showNavigationBar:false` posts entry | **OUT OF SCOPE — must not break** | |
| Ambient/cosmic backgrounds, readable-tone system | **OUT OF SCOPE** | Page keeps rendering on `AmbientBackground` |
| Debug cards (introductions, transport diagnostics) | **UNCHANGED in content**; their placement on the redesigned page is in scope | kDebugMode only |
| Orbit find-UX, sculpt/edit, unread indicators, groups-on-rings | **OUT OF SCOPE** | Only the chrome pair leaves the orbit Stack |

Explicitly **not** prescribed by this spec: widget structure, file organization, whether sub-sheets are modal sheets / routes / expanding cards (they are called "focused sub-surfaces" in the tests — any presentation that satisfies the test cases is acceptable), and how the scanner's dependency bundle is threaded.

---

## 5. Test Cases

Reference viewport = 390×844 logical (iPhone 14/15-class), `en` locale, dark default background, unless stated. "Tile" = the My QR / Scan affordances under the profile header; "row" = a grouped-list entry with optional value; "sub-surface" = the focused UI a row opens.

### Group A — My QR / Scan entries in Settings

- **TC-209-01** Open Settings via the Orbit center avatar. Under the profile picture and nickname, two large tappable affordances labeled with the localized strings for `orbit_my_qr` ("My QR") and `orbit_scan` ("Scan") are visible without scrolling. Both labels are visible text (not semantics-only), and each affordance's hit target is at least 44×44 pt.
- **TC-209-02** Tap "My QR" → the QR display screen opens and reaches its success state (QR code rendered) for a user with a complete identity. Closing it returns to the same Settings page (no re-entry, no duplicate route).
- **TC-209-03** Tap "Scan" → the QR scanner screen opens (camera surface + overlay). Dismissing it without scanning returns to Settings unchanged.
- **TC-209-04** With NO identity available, tap "My QR" → the QR display's existing no-identity state renders (INV-196-7 parity with today's `noIdentity` behavior). No crash.
- **TC-209-05** Rapid double-tap on "My QR" (two taps within one frame budget) pushes exactly one route.
- **TC-209-06** Both tiles expose `button` semantics with the same localized labels, and are focusable/activatable via accessibility tools (parity with the semantics the orbit chrome had, `orbit_qr_chrome_buttons_test` L94-129 equivalents).
- **TC-209-07** In the `ar` locale, the tile labels render the Arabic strings ("رمزي" / "مسح") and the pair mirrors with the page's RTL text direction (unlike the orbit chrome's forced LTR — the Settings surface follows ambient directionality). Both remain tappable.
- **TC-209-08** Settings opened from the Posts screen entry (`showNavigationBar: false` variant) shows the same two tiles, and both work. The nav pill remains hidden in that variant.
- **TC-209-09** Inside the QR display screen, the "Scan a friend's code" cross-link still opens the scanner (the display→scan loop survives re-hosting; INV-196-7).

### Group B — Orbit chrome retirement

- **TC-209-10** The Orbit inner-circle surface renders NO element with key `orbit-my-qr-button` or `orbit-scan-button`, and no visible "My QR"/"Scan" affordance, while the view toggle (top-left) and create button (top-right) remain exactly where they were.
- **TC-209-11** The Orbit all-chats surface likewise renders no QR/Scan chrome, and the all-chats header stays pill-free (196's INV-196-2 outcome preserved — the pills do not resurrect there either).
- **TC-209-12** Orbit center-avatar tap still opens Settings from an idle surface; mid-edit tap still only dismisses the edit session (206 behavior untouched: INV-206-1/4/5).
- **TC-209-13** With the chrome gone, the top strip has no dead hit-regions: a tap at the old chrome position (top-center, safeArea+8) on the inner-circle surface performs the background/default behavior, not a phantom QR action.
- **TC-209-14** Feed→Orbit→Feed tab switching and orbit re-entry render no chrome and produce no exceptions (replaces the remount coverage of 196 TC-21/22/23 with the inverted expectation).

### Group C — One-Screen layout

- **TC-209-15** On the reference viewport, the full Settings page — profile header, both tiles, an IDENTITY group (peer ID row, recovery-phrase row), a PREFERENCES group (background row, photo-quality row, video-quality row, nearby switch row, move-account row) — is entirely visible with no scrolling required (no scrollable extent below the fold, or scroll offset 0 == max extent).
- **TC-209-16** Every value-bearing row shows its current value at rest: background row shows the active choice's display name (e.g. "Default"), photo-quality row shows "Compressed"/"Original", video-quality row likewise. Values reflect persisted preferences on cold open (e.g. saved "Cosmic" + "Original" render as those values without opening any sub-surface).
- **TC-209-17** After changing a preference in a sub-surface and returning, the row's value text updates in place (e.g. Background: "Default" → "Cosmic") without reopening the page.
- **TC-209-18** Profile header parity: the avatar renders at its current size class with the camera badge; tapping the badge starts the existing avatar-pick flow (optimistic preview, failure snackbar "Failed to upload profile picture" reverts). Nickname tap enters inline editing with the same validation (30-char max, allowed charset incl. Arabic); commit fires the identity change kind consumed by Feed and Orbit (TC-206-19a parity).
- **TC-209-19** The sticky header still shows the centered title "Settings" with the circular back button popping the route (keeps `orbit_settings_entry_test` TC-206-02 green on the title assertion).
- **TC-209-20** On a shorter viewport (e.g. 390×667, iPhone SE class), the page scrolls normally and every row and both tiles remain reachable; no RenderFlex overflow errors are thrown.
- **TC-209-21** With system text scale at 1.5×, the page lays out without overflow exceptions; rows may wrap or the page may become scrollable, but every control remains reachable and tappable.
- **TC-209-22** On the Daylight Lagoon (light-tone) background preference, all rows, tiles, labels, and values use the light readable tone (parity with today's readable-tone switching; no white-on-white/black-on-black).
- **TC-209-23** In debug builds, the introduction-debug and transport-diagnostics surfaces are still reachable from the Settings page; in release builds they are absent.

### Group D — Sub-surfaces (background, photo quality, video quality, recovery phrase)

- **TC-209-24** Tapping the Background row opens a focused sub-surface listing exactly the four options with their existing localized names and descriptions (Default / Cosmic / Mirrored cosmic / Daylight Lagoon), with the active one marked selected.
- **TC-209-25** Selecting "Cosmic" in the background sub-surface: the app background changes (same observable effect as today's inline chooser), the persisted preference is saved, and returning to the page shows Background · "Cosmic".
- **TC-209-26** Background save failure (persistence layer errors): the selection visibly reverts to the previous choice and the existing error message ("Background choice could not be saved") is surfaced. The row value returns to the old choice.
- **TC-209-27** Tapping the Photo-quality row opens a focused sub-surface with the two options ("Compressed"/"Original") and the existing helper text for the active option; choosing "Original" persists, fires `AppShellChangeKind.mediaQuality` exactly once, and the row value reads "Original" on return.
- **TC-209-28** Video quality: same as TC-209-27 for the video control (independent persistence — changing video quality does not alter the photo-quality row's value).
- **TC-209-29** Tapping the Recovery-phrase row opens a focused sub-surface with: the red warning text, the 12 numbered words hidden behind the blur/"Tap to reveal" scrim, reveal on tap, "Copy to clipboard" (with "Copied!" confirmation) and "Hide" re-blurring — full behavior parity with today's card. The phrase is NEVER visible on the main One-Screen page itself.
- **TC-209-30** Recovery-phrase sub-surface is only offered when the stored mnemonic splits to exactly 12 words (parity with today's conditional render); otherwise the row is absent (or disabled — either way, no broken sub-surface opens).
- **TC-209-31** Dismissing any sub-surface without choosing anything leaves the persisted preference and row value unchanged.
- **TC-209-32** State-transition safety: open the Background sub-surface, select an option, and immediately navigate back before the async save completes → no crash; the final row value matches the eventually-persisted state (optimistic value or reverted value per TC-209-26 — never a stale third state).

### Group E — Inline rows (peer ID, nearby, move account)

- **TC-209-33** The Peer ID row shows a (possibly truncated) representation of the peer ID and a copy affordance; activating copy places the FULL peer ID string on the clipboard and shows a transient confirmation (check-style feedback that reverts within ~2s — parity with today's card).
- **TC-209-34** The "Share People Nearby" control remains a single-tap inline switch (no sub-surface) with its localized title visible; toggling ON drives the nearby-location refresh path and toggling OFF drives the sharing-disabled path, exactly as today (`settings_wired_posts_nearby_test` behaviors stay green: switch present, On/Off state text or equivalent state indication).
- **TC-209-35** The Move-account row opens the account-migration old-phone journey, remains reachable without scrolling on the reference viewport, and keeps a stable key (`settings-move-account-action` or a documented replacement that TC-206-23's gate is updated to) — the action must remain locked by the 206 GROUP_TESTS gate.
- **TC-209-36** Move-account single-flight: double-tapping the row pushes exactly one migration route.

### Group F — Scan flows hosted from Settings

- **TC-209-37** Scanning a VALID contact QR from the Settings-hosted scanner: the contact is added, the success dialog appears, and confirming it lands the user on a functioning Feed surface where the new contact's conversation can be opened. No `_missing*` StateError fires anywhere in the flow.
- **TC-209-38** After TC-209-37, navigating to Orbit shows the new contact on the constellation without requiring an app restart (replaces the retired `.then(_applyRouteChanges)` guarantee with an outcome-level lock).
- **TC-209-39** The post-scan mutual-add and profile-picture side effects still fire (contact request sent to the scanned peer; avatar download attempted) — parity with `qr_scanner_wired.dart:255-258` behavior.
- **TC-209-40** Scanning an ACCOUNT-MIGRATION pairing QR from the Settings-hosted scanner routes into the old-phone migration journey (`AccountMigrationJourneyWired.oldPhone`), exactly as the orbit-hosted branch does today.
- **TC-209-41** Scanning one's OWN QR shows the existing self-scan rejection error; scanning an EXPIRED (>24h `ts`) payload shows the expiry error; a malformed payload shows the invalid-format error. In all three cases the user remains in/returns to a working scanner or Settings context — no crash, no half-added contact.
- **TC-209-42** Scanning before the local identity is loaded (early after cold start) behaves per today's contract (INV-196-7 parity with 196 TC-10): no crash, defined error or wait state.
- **TC-209-43** The onboarding (first-time-experience) scanner entry still works end-to-end and is unaffected by the orbit chrome removal.

### Group G — Regression: propagation, l10n, gates

- **TC-209-44** After an avatar or nickname change in redesigned Settings, Feed and Orbit both reflect it via the single change-kind mechanism (no duplicate refresh path is introduced; INV-206-6). Equivalent locks for `.mediaQuality` (feed consumer) stay green.
- **TC-209-45** l10n integrity: the redesigned page introduces no hardcoded UI literals (l10n_integrity literal-scan stays at its current baseline); "My QR"/"Scan" reuse `orbit_my_qr`/`orbit_scan`; any NEW strings (group headers, sub-surface titles) exist in en, ar, and de (INV-196-8 discipline).
- **TC-209-46** Full `ar` RTL pass of the One-Screen page: groups, rows, values, chevron/affordance sides, and both tiles mirror correctly; peer-ID text (latin ID) remains readable; no overflow.
- **TC-209-47** The always-on nav pill (default entry) still switches tabs and pops Settings (`switchTo` + pop parity); returning to Orbit after tab-switching from redesigned Settings does not leave the single-flight latch stuck (a second center-avatar tap opens Settings again).
- **TC-209-48** Cleanup: no orphaned routes or stuck states after exercising every sub-surface and both QR screens in one session — returning to the One-Screen page each time with consistent values, and Settings can be closed with a single back action at the end.

---

## 6. Evidence gaps / notes for the solution author

- The exact presentation of "focused sub-surfaces" (sheet vs route vs expanding row) is deliberately unspecified; TC groups C/D only constrain observable behavior (row values at rest, full parity of control behavior inside the sub-surface, no-scroll on the reference viewport).
- The post-scan "lands on a functioning Feed" outcome (TC-209-37) is intentionally implementation-agnostic: today's contract rebuilds `FeedWired` from a ~30-dep bundle; the 209 mockup's shared notes sketch an alternative. Either satisfies the TC as long as no `_missing*` StateError can fire and `qr_scanner_wired_test`'s move-account-runner contract (BASELINE gate) is preserved or consciously re-baselined.
- `orbit_qr_entry_migration_test.dart` (GROUP_TESTS :254) and `orbit_qr_chrome_buttons_test.dart` lock the UI this spec removes; their destination-contract content (196 TC-07..11) is re-expressed here as TC-209-02/03/04/09/42. The gate registration itself will need updating — flagged for the TDD plan, not prescribed here.

---

## 7. Amendments (2026-07-04, post verify→refute — see 209 tdd-plan §Root Cause)

1. **TC-209-08 premise corrected:** `PostsWired` is constructed nowhere in production `lib/` (only in tests) — `posts_wired.dart:539` is a dead, test-locked Settings entry, not a live one, and it can never supply the scanner dependency bundle (`contactRequestRepository`/`contactRequestListener` absent from `PostsWired` entirely). TC-209-08 is re-scoped: at the posts-entry `SettingsWired` variant the QR/Scan tiles are **absent** (conditional mount on host-supplied capability, mirroring INV-206-1), and the `showNavigationBar:false` behavior is unchanged.
2. **TC-209-18 avatar wording resolved:** "current size class" is superseded by the user-chosen Option C mockup, which draws the avatar at **72 px**. Behavior parity (camera badge, pick flow, nickname editing, identity change-kind) is unchanged; only the size and profile paddings shrink — the honest px budget shows 100 px cannot satisfy TC-209-15 without gutting every other constant.
3. **TC-209-15 qualified:** the zero-scroll assertion holds for the reference viewport at **textScale 1.0 with debug cards excluded** (debug cards only exist in `kDebugMode`, and `flutter test` always runs debug — the no-scroll test must pump the page without the debug section). Debug builds with debug cards may scroll; TC-209-23 covers their reachability.
