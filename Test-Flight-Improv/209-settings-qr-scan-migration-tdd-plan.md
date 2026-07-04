# 209 - Settings "One Screen" redesign + My QR / Scan migration from Orbit  (Feature Improvement)

Status: awaiting-review
Spec: Test-Flight-Improv/209-settings-qr-scan-migration-spec.md (incl. §7 Amendments) · Mockup: Test-Flight-Improv/209-settings-qr-scan-migration-mockups.html (Option C)

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-04 | Evidence Collector | wf_32ecdb30-15d (3 explorers) + Explore sweep + wf_6454f379-fa7 (3 ground + 4 refute) | seam, dep tables, harness, l10n mechanics all file:line-verified | plan |
| 2026-07-04 | Planner | qr_scanner_wired.dart, settings_wired/screen, orbit_wired/screen, run_test_gates.sh, l10n suites | host-callback architecture chosen (see Root Cause §design); avatar 72; scanner internals untouched | matrix |
| 2026-07-04 | Reviewer (sufficiency) | this plan vs sufficiency-checklist | all gates pass; 2 refuted spec premises recorded as spec §7 amendments | arbiter |
| 2026-07-04 | Arbiter | — | no structural blockers; host-only closure | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| | contract extraction (git status --short) | | | scope confirmed | |
| | RED tests added | | | RED for expected reason | |
| | implementation | | | scoped files only | |
| | direct GREEN | | | | |
| | preservation GREEN | | | | |
| | named gates | | | | |
| | QA (independent) | | | | |

## Source Of Truth
- Spec: Test-Flight-Improv/209-settings-qr-scan-migration-spec.md (with §7 Amendments)
- Gate definitions: scripts/run_test_gates.sh (script wins over prose)
- Discovery/registration: scripts/check_reliability_simulation_discovery.sh (no sim rows in this plan)
- Numbering / index: Test-Flight-Improv/00-INDEX.md

## Session Classification
implementation-ready

## Exact Problem Statement

My QR + Scan live as icon-only 40×40 chrome circles at the top of both Orbit surfaces (`orbit_qr_chrome_buttons.dart`, mounted `orbit_screen.dart:600-603`) — worst reach zone, labels screen-reader-only, invisible from Settings. Since 206 the Orbit center avatar opens Settings, making Settings the identity surface — yet it has no path to the QR that encodes exactly the identity it displays. Settings itself is ~2.5 screens of ungrouped, always-expanded cards (`settings_screen.dart:169-240`).

What must improve: (1) My QR + Scan render as two large, labeled, RTL-mirroring tiles directly under the profile header in Settings; (2) the page becomes "One Screen": IDENTITY group (peer-ID row w/ copy, recovery-phrase row) + PREFERENCES group (background / photo / video rows with at-rest values opening focused sub-sheets, inline nearby switch, move-account row), zero scroll at 390×844 / textScale 1.0 / debug-cards-excluded; (3) the Orbit chrome pair retires.

What must stay unchanged (→ preserved-green sentinels): `qr_scanner_wired.dart` + `qr_display_wired.dart` internals and the post-scan `pushAndRemoveUntil → fresh FeedWired` contract (BASELINE gate `qr_scanner_wired_test` untouched); 206 center-avatar entry mechanics + `_settingsRouteActive` latch + single-mechanism change kinds (INV-206-1..6); FTE onboarding scanner (`first_time_experience_wired.dart:552`); nearby switch semantics (`settings_wired_posts_nearby_test`); `settings-move-account-action` key + "Settings" title + "Share People Nearby" text (`orbit_settings_entry_test` TC-206-02/23); `orbit_my_qr`/`orbit_scan` ARB keys in en/ar/de (parity suite getters).

## Root Cause (verify → refute confirmed)

Not a bug — a placement/IA decision (196 Option B) superseded by 206 making Settings the identity surface. The migration seam, verified on HEAD:

- Chrome: `orbit_qr_chrome_buttons.dart` (keys :42/:49), mount `orbit_screen.dart:602-603`, callbacks threaded as REQUIRED params through TWO layers (`orbit_screen.dart:205-206/:274-275` + `_OrbitScreenView :396-397/:450-451`), values `orbit_wired.dart:2439-2440`.
- Handlers: `_onMyQR` `orbit_wired.dart:2220-2234` (only `QRDisplayWired` push app-wide, :2223); `_onScanQR` :2271-2342 (34/37 scanner params are direct `widget.*` forwards; `ownPeerId` from state :2290; `onMigrationQrScanned` built inline :2313-2337; post-scan `.then(_applyRouteChanges)` :2341).
- Scanner dep reality (`qr_scanner_wired.dart:61-139`): 37 params; the scan/parse/migration flow itself needs only 8 (bridge, contactRepo, identityRepo, p2pService, chatMessageListener, ownPeerId, downloadProfilePictureFn?, onMigrationQrScanned?) — the other 29 exist for the success-dialog FeedWired rebuild (:384-434) + share route (:530-556), guarded by five `_missing*` StateErrors (:558-582).
- `SettingsWired` ctor (14 params, `settings_wired.dart:42-76`) owns ZERO of the 24-dep scanner gap.

**Design decision (the architecture the whole plan hangs on): host-built callbacks, not dep threading.** `SettingsWired` gains two optional `Future<void> Function()` params — `onMyQrRequested` / `onScanQrRequested` — and renders the tiles ONLY when both are non-null (conditional mount, INV-206-1 pattern). OrbitWired passes closures wrapping its existing `_onMyQR`/`_onScanQR` at the push site (:624-638). Consequences, all evidence-backed:
- Handler bodies + destination contracts move zero lines → INV-196-7 preserved verbatim; `.then(_applyRouteChanges)` keeps working (routes push onto the same root navigator, on top of Settings; pop results still reach orbit's `.then`).
- `qr_scanner_wired.dart` untouched → BASELINE tests 5p/5q/:321 (`find.byType(FeedWired)` :316, runner forward :354-355) stay green with zero edits.
- Post-scan success still `pushAndRemoveUntil((route) => false)` → the Settings route is destroyed with the rest of the stack; the fresh FeedWired re-reads repos, so Orbit shows the new contact on next visit (TC-209-38's outcome). The `_settingsRouteActive` latch releases via its existing `.whenComplete` when the route is removed.
- Dead posts entry (`posts_wired.dart:539`) passes nothing → tiles hidden there; zero PostsWired edits.

**Refuted / do-NOT-re-introduce** (adversarial pass wf_6454f379-fa7):
1. ~~"posts_wired:539 is a production Settings entry"~~ — REFUTED: `PostsWired(` is constructed nowhere in `lib/` (only its own definition :93 + tests). It also structurally cannot host the scanner (`contactRequestRepository`/`contactRequestListener` absent from its ctor entirely). Do not thread scanner deps through PostsWired. → spec §7.1.
2. ~~"One Screen fits with the 100px avatar + current profile paddings"~~ — REFUTED by px budget: content ~688px vs ceiling 630px (header 120 = safe-top 47 + glass bar 73; nav clearance 94). Fits ONLY as a pinned-constants design: avatar 72, profile padding 10/14, 44px custom rows (ListTile 56/48 is fatal), `MaterialTapTargetSize.shrinkWrap` on the nearby Switch, tiles ≤72px → ~625px, +2..5px slack. → spec §7.2. Do not use ListTile for rows; do not leave the Switch at `.padded`.
3. ~~"post-scan nav can be rewritten to switchTo(feed)+pop"~~ — REFUTED: kills BASELINE deterministically (`qr_scanner_wired_test` :316/:354-355 assert the fresh FeedWired + runner identity; the file pumps QRScannerWired directly, host-independent). Keep the rebuild contract; host from Settings via callbacks.
4. "chrome removal is contained" — SURVIVES: zero non-test references to the widget/keys outside the pair (`orbit_screen.dart:24/:603/:789` only); TC-17's production twin (`main.dart:4252/4295` intros deep link) never touches the chrome; the Stack has no index-based child logic; ExpandableFab scrim is self-contained (`expandable_fab.dart:147-149`). Residues to sweep: required `onMyQR/onScanQR` params at 2 layers; stale comments `orbit_screen.dart:786-792` + `:314-318` (the 56px list top-padding itself STAYS — the toggle still lives at safeTop+8); `onScanPressed` re-thread obligation (the display→scan loop is nullable at every layer and would silently degrade — must be wired in the new closures).
5. "row values are synchronously available" — REFUTED (nuanced): first frame renders compile-time defaults until the SecureKeyStore futures resolve (`settings_wired.dart:90-110`, loaders :182-199/:267-274). It is a stale-default flash, never empty — same accepted pattern as the `'Username'` placeholder (:588). Accepted; value tests assert post-settle.

## Real Scope

In scope: `SettingsScreen`/`SettingsWired` One-Screen restructure + 2 new leaf widgets + sub-sheets reusing the existing control widgets; `SettingsWired` `onMyQrRequested`/`onScanQrRequested` params + `_qrRouteActive` latch; orbit closure wiring + chrome retirement (widget, mount, 2-layer params, comments); deletion of dead `qr_action_cards.dart`+test; 2 new l10n keys (en/ar/de) + gen-l10n; test rewrites per catalog.
Out of scope (owner): `qr_scanner_wired.dart`/`qr_display_wired.dart` internals (196/BASELINE own); AccountMigration journey (Move feature owns); FTE scanner (FTE owns); orbit find/sculpt/unread (198/201/205 own); `AppShellChangeKind` mechanism (206 owns); contact-profile private peer-ID card (its own copy); PostsWired revival (dead code — future session if ever).

## Files To Inspect Next

Production: `lib/features/settings/presentation/screens/settings_screen.dart`, `settings_wired.dart`; `lib/features/settings/presentation/widgets/*` (all 9); `lib/features/orbit/presentation/screens/orbit_wired.dart` (:616-644, :2220-2342, :2427-2440), `orbit_screen.dart` (:24, :205-206, :274-275, :342-343, :396-397, :450-451, :600-603, :786-792), `lib/features/orbit/presentation/widgets/orbit_qr_chrome_buttons.dart` (delete), `qr_action_cards.dart` (delete); `lib/l10n/app_{en,ar,de}.arb`.
Direct tests: the 11 files in "Existing Tests" below. Dependency-only context: `qr_scanner_wired.dart`, `qr_display_wired.dart`, `app_shell_controller.dart`, `nav_bar_theme.dart`, `friend_row.dart:55-61` + `posts_screen.dart:296-323` (row styling precedents), `conversation_wired.dart:2927-3008` + `full_emoji_picker.dart:53-68` + `friend_picker_wired.dart:171-209` (sheet + tone precedents).

## Existing Tests Covering This Area

| Test (declared count) | Covers | Fate |
|---|---|---|
| `test/features/orbit/presentation/widgets/orbit_qr_chrome_buttons_test.dart` (9) | the retiring widget | DELETE with widget |
| `test/features/orbit/presentation/widgets/qr_action_cards_test.dart` (6) | dead pre-196 widget | DELETE with widget |
| `test/features/orbit/presentation/screens/orbit_qr_entry_migration_test.dart` (18, GROUP_TESTS :254) | chrome-on-orbit + destination contracts | REWRITE IN PLACE (same path → zero array edits): orbit-side inversions + settings-host full chain |
| `test/features/settings/presentation/screens/settings_screen_test.dart` (14, flat) | current layout | REWRITE: header/back tests (:72/:84/:107) survive; section-presence (:117-155), background-picker (:161-233), full-page (:235-338) re-target rows/One-Screen |
| `test/features/settings/presentation/screens/settings_wired_test.dart` (19) | behaviors | UPDATE finders (peer-copy :399, mnemonic :422/:455 → sheet, quality :506/:595 → rows+sheets, background :633-846 → sheet path); KEEP verbatim: move :516/:540, nav-pop :848, 206 kind locks :907/:930/:970 |
| `settings_wired_posts_nearby_test.dart` (3) | inline nearby switch | SURVIVES (title + Switch preserved; row uses shrinkWrap — verify `find.byType(Switch)` still lands) |
| `settings_profile_section_test.dart` (11) | avatar/badge/username | survives unless it pins size-100 — inspect; adjust only the size assert if present |
| `settings_peer_id_card_test.dart` (9), `settings_recovery_phrase_card_test.dart` (12), `posts_nearby_settings_card_test.dart` (3), `background_choice_control` behavior via settings tests, `image_quality_toggle` via settings tests | control widgets | SURVIVE — widgets reused as-is inside sheets |
| `orbit_settings_entry_test.dart` (14, GROUP_TESTS :231) | 206 entry + Settings content | SURVIVES BY DESIGN (title, 'Share People Nearby', `settings-move-account-action` key all preserved) — preservation sentinel |
| `qr_display_wired_test.dart` (11), `qr_scanner_wired_test.dart` (7, BASELINE :10) | QR screens | UNTOUCHED — preservation sentinels |
| `test/l10n/orbit_strings_parity_test.dart` (5, GROUP_TESTS :259), `l10n_integrity_test.dart` (2) | ARB parity + literal scan | orbit keys KEPT (getters remain consumed by tiles); new settings_* keys land in all 3 ARBs atomically |

Missing coverage gaps filled by this plan: no test anywhere asserts Settings→QR reachability, page-level grouping, at-rest values, no-scroll, sub-sheet parity, settings-host scan chain, textScale, or reopen-value durability.

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

New files are all `test/features/settings/presentation/screens|widgets/**` or rewrites of existing paths → AUTO (glob) unless noted. Viewport helper: copy `feed_screen_test.dart:13-18` `setPhoneViewport` (390×844, dpr 1.0). Text-scale has NO repo precedent — use `tester.platformDispatcher.textScaleFactorTestValue = 1.5` + `addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue)`.

1. `test/features/settings/presentation/widgets/settings_qr_tiles_test.dart` (NEW)
   - T1 `renders My QR and Scan tiles with visible labels` — pumps SettingsScreen w/ both callbacks; finds `ValueKey('settings-my-qr-tile')`, `ValueKey('settings-scan-tile')`, `find.text('My QR')`, `find.text('Scan')`. RED: keys/widget don't exist. Re-red: revert E1/E3 tile mount.
   - T2 `labels localize and mirror under ar RTL` — ar locale; finds 'رمزي'/'مسح'; asserts tile x-order flips vs LTR (getTopLeft comparison). RED: no tiles. Re-red: revert E1 (or force LTR → order assert flips).
   - T3 `tiles expose button semantics` — SemanticsTester: two nodes, `hasAction(tap)`, labels from l10n. RED: no nodes.
   - T4 `taps fire host callbacks exactly once` — spies; tap each; counts 1/1, cross-count 0. RED: no tiles.
   - T5 `rapid double-tap fires once` — callback returns un-completed Future (Completer); 2 taps in one frame → count 1 (`_qrRouteActive` latch). RED: no latch. Re-red: remove latch in E4 → count 2.
   - T6 `tiles absent when callbacks null` — pumps without callbacks (posts-entry parity, spec §7.1); both keys `findsNothing`. RED (trivially green on HEAD? NO — asserted against the NEW SettingsScreen ctor; on HEAD the params don't compile → RED as compile failure, documented). Re-red: unconditional mount → findsOneWidget.
   - T7 `tile hit targets ≥44px` — `tester.getSize(...)` both ≥ Size(44,44). Re-red: shrink tile below 44.
2. `test/features/settings/presentation/screens/settings_one_screen_layout_test.dart` (NEW)
   - T1 `whole page fits 390×844 with zero scroll` — full SettingsScreen (peerId, 12-word mnemonic, all callbacks, tiles, `debugSection: null`); `tester.widget<Scrollable>` position `maxScrollExtent == 0`. REAL text metrics (default test font), textScale 1.0. RED on HEAD: current stack ≫ viewport (maxScrollExtent > 0). Re-red: ANY constant regression (row >44, avatar back to 100, Switch `.padded`).
   - T2 `grouped rows with keys render in order` — finds `settings-row-peer-id`, `settings-row-recovery`, `settings-row-background`, `settings-row-photo-quality`, `settings-row-video-quality`, `settings-row-nearby`, `settings-move-account-action` + IDENTITY/PREFERENCES section labels (new l10n). RED: none exist.
   - T3 `rows show persisted at-rest values after settle` — SettingsWired + FakeSecureKeyStore seeded cosmic/original/original; pumpAndSettle; row values 'Cosmic'/'Original'/'Original'. RED: rows don't exist. Re-red: revert E4 value plumbing → defaults shown.
   - T4 `667pt viewport scrolls with every row reachable` — Size(390,667); maxScrollExtent > 0; scrollUntilVisible(move row); `tester.takeException() == null`. RED: rows absent.
   - T5 `textScale 1.5 lays out without overflow` — takeException null; move row reachable (scroll allowed). RED: rows absent. (First textScale test in repo — pattern stated above.)
   - T6 `daylight tone renders light readable roles on rows` — mirror of settings_screen_test :209 technique against the new rows. RED: rows absent.
   - T7 `ar full-page RTL renders without overflow` — takeException null; chevrons/l10n present. RED: rows absent.
   - T8 `row value updates in place after sub-sheet change` — open background sheet, pick Cosmic, sheet closes → `settings-row-background` value text 'Cosmic'. RED: no sheet. Re-red: revert E4 row-value rebind.
   - T9 `reopen reconstructs values from storage` (blind-spot: durability) — change to Cosmic; dispose (pumpWidget different tree); re-pump SettingsWired same store; settle → 'Cosmic'. RED: rows absent. Re-red: value read from ephemeral state only.
3. `test/features/settings/presentation/screens/settings_sub_sheets_test.dart` (NEW)
   - T1 `background row opens sheet with 4 options, selection marked` — reuses `BackgroundChoiceControl` inside (find.byType); check on Default. RED: no sheet.
   - T2 `selecting Cosmic persists, updates shell, closes to updated row` — FakeSecureKeyStore write + `appShellController.backgroundPreference == cosmic`. Re-red: revert E4 `_onBackgroundPreferenceChanged` reuse.
   - T3 `background save failure reverts and surfaces existing error` — failing store; row back to 'Default'; `find.text('Background choice could not be saved')`. RED: no sheet path. (Preserves settings_wired_test :795 semantics at the new seam.)
   - T4 `photo sheet parity: options+helper, Original fires mediaQuality kind once` — listener spy on AppShellController counts exactly 1 `AppShellChangeKind.mediaQuality`. Discriminator: kind == mediaQuality AND NOT identity. Re-red: fire duplicate kind (INV-206-6 guard).
   - T5 `video sheet independent of photo` — set video Original; photo row still 'Compressed'. Re-red: cross-wire the two handlers.
   - T6 `recovery row opens sheet: warning, blur, reveal, copy 'Copied!', hide re-blurs` — reuses `SettingsRecoveryPhraseCard` + existing `_onToggleMnemonic/_onCopyMnemonic/_onHideMnemonic`. RED: no sheet. Also asserts first mnemonic word `findsNothing` on the main page at rest (never-on-page lock).
   - T7 `recovery row absent when mnemonic ≠ 12 words` — parity with today's gate (settings_screen.dart:228-238 logic relocated). Re-red: unconditional row.
   - T8 `sheet dismissed without choice changes nothing` — open background sheet, barrier-dismiss; store write-count 0; row 'Default'.
   - T9 `mid-save back-nav is safe` — delayed-completion fake store; select then immediately pop; no exception; final row matches persisted outcome. (Blind-spot: lifecycle under in-flight save.)
4. `test/features/orbit/presentation/screens/orbit_qr_entry_migration_test.dart` (REWRITE IN PLACE — stays at GROUP_TESTS :254; harness `buildOrbitWired` + fake bundle kept)
   - T1 `inner-circle surface has no QR chrome; toggle and create button intact` — keys `orbit-my-qr-button`/`orbit-scan-button` findsNothing; `orbit-view-toggle` + ExpandableFab findsOneWidget. RED on HEAD: chrome present. Re-red: remount chrome.
   - T2 `all-chats surface has no QR chrome and no header pills` — same inversion + `find.text('My QR')` findsNothing (196 INV-196-2 outcome kept). RED: present.
   - T3 `tap at old chrome position performs background behavior only` — tapAt top-center (safeTop+8+20); no new route pushed (navigator observer). RED: QRDisplay opens. (Dead hit-region lock.)
   - T4 `intros deep link still forces all-chats` — `initialFilterTab:'intros'` → `find.byType(OrbitalVisualization)` findsNothing (TC-17's surviving assertion; chrome asserts inverted). GREEN-on-HEAD sentinel within a red file — documented.
   - T5 `feed→orbit re-entry renders chromeless without exceptions` — tab-switch churn; takeException null; keys findsNothing. RED: chrome remounts.
   - T6 PROD-CRITICAL `full chain: center avatar → Settings tiles → Scan → valid QR → success → fresh FeedWired with forwarded runner` — self-avatar tap (`orbit-center-self-avatar`), Settings opens, `settings-scan-tile` tap, `QRScannerScreen.onScanned(validQr)` direct-fire (qr_scanner_wired_test :342 technique), 'Added to your circle!' OK → `find.byType(FeedWired)` + `same(runner)` on `accountMigrationRunTransfer` + contact present in shared InMemoryContactRepository (TC-209-37/38/39 outcome; fresh tree re-reads the repo — orbit load path already locked by orbit_wired_test). RED: no tiles in Settings. Re-red: revert E5 closure wiring.
   - T7 `migration QR from settings-hosted scanner routes to old-phone journey` — `isAccountMigrationPairingQr` payload → `AccountMigrationJourneyWired` present (orbit's :2313-2337 handler reached through the closure). RED: no tiles.
   - T8 `My QR from Settings reaches display; close returns to same Settings; ScanFriendCard cross-link opens scanner` — INV-196-7 loop at new host (`onScanPressed` re-threaded). RED: no tiles. Re-red: drop `onScanPressed` from the closure → ScanFriendCard tap does nothing.
   - T9 `My QR with no identity shows noIdentity state` — unseeded identity repo → existing state text. RED: no tiles.
   - T10 `scan before identity load follows today's contract` — delayed identity future; no crash; defined state (196 TC-10 parity, ownPeerId `''` path).
5. `test/features/settings/presentation/screens/settings_screen_test.dart` (REWRITE, flat) — keep :72 title / :84 header roles / :107 back; replace section-presence + background-picker + full-page tests with row-based equivalents (presence gated on callbacks: peer-id row hidden when peerId null; recovery row hidden when mnemonic null; nav bar test kept). RED: new finders absent on HEAD.
6. `test/features/settings/presentation/screens/settings_wired_test.dart` (UPDATE) — retarget: peer-copy via `settings-row-peer-id` trailing copy (2s check revert semantics kept), mnemonic tests through the sheet, quality tests through rows+sheets, background persist/telemetry/no-restart/failure tests through the sheet path. KEEP VERBATIM: :516/:540 move tests (key unchanged), :848 nav-pop, :907/:930/:970 change-kind locks. RED: old finders vanish only after E3 — the UPDATED assertions are red on HEAD.
7. Deletions with their widgets: `orbit_qr_chrome_buttons_test.dart`, `qr_action_cards_test.dart` (files under test/features/orbit/presentation/widgets/ — auto-glob, no arrays reference them; verified).

## Test Coverage Matrix  (ZERO empty cells)

All rows: widget tier (pure Flutter UI; no DB/crypto/OS boundary — host-only closure). Gate `A` = `./scripts/run_host_test_gates.sh feature-host-all`; gate `G` = `./scripts/run_test_gates.sh groups`; gate `B` = `./scripts/run_test_gates.sh baseline`. Registration `AUTO` = auto-glob `test/features/**`; `:254` = already-listed path in GROUP_TESTS (rewrite in place).

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Gate | Registration |
|---|---|---|---|---|---|---|---|
| TC-209-01 | UI render | widget | qr_tiles::T1 + one_screen::T1(no-scroll co-assert) | tiles absent | revert E1/E3 | A | AUTO |
| TC-209-02 | nav contract | widget | orbit_qr_entry_migration::T8 | no tiles in Settings | revert E5 | G | :254 |
| TC-209-03 | nav contract | widget | orbit_qr_entry_migration::T6 (scanner leg) + qr_tiles::T4 | no tiles | revert E5 | G | :254 |
| TC-209-04 | error state | widget | orbit_qr_entry_migration::T9 | no tiles | revert E5 | G | :254 |
| TC-209-05 | concurrency | widget | qr_tiles::T5 | no latch | remove `_qrRouteActive` | A | AUTO |
| TC-209-06 | a11y | widget | qr_tiles::T3 | no semantics nodes | strip Semantics in E1 | A | AUTO |
| TC-209-07 | l10n/RTL | widget | qr_tiles::T2 | no ar labels | force LTR in E1 | A | AUTO |
| TC-209-08 (§7.1) | conditional mount | widget | qr_tiles::T6 | new ctor params absent (compile RED) | unconditional mount | A | AUTO |
| TC-209-09 | cross-link loop | widget | orbit_qr_entry_migration::T8 (ScanFriendCard leg) | onScanPressed unthreaded | drop onScanPressed in closure | G | :254 |
| TC-209-10 | removal | widget | orbit_qr_entry_migration::T1 | chrome present | remount chrome | G | :254 |
| TC-209-11 | removal | widget | orbit_qr_entry_migration::T2 | chrome present | remount | G | :254 |
| TC-209-12 | 206 preservation | widget | orbit_settings_entry_test (existing 14) | n/a — sentinel stays green | break center detector | G | :231 (existing) |
| TC-209-13 | dead hit-region | widget | orbit_qr_entry_migration::T3 | chrome eats the tap → route pushes | leave a phantom detector | G | :254 |
| TC-209-14 | lifecycle | widget | orbit_qr_entry_migration::T5 | chrome remounts | remount | G | :254 |
| TC-209-15 (§7.3) | layout budget | widget | one_screen::T1 | maxScrollExtent > 0 today | row 56px / avatar 100 / Switch .padded | A | AUTO |
| TC-209-16 | value display | widget | one_screen::T3 | rows absent | unbind values → defaults | A | AUTO |
| TC-209-17 | value refresh | widget | one_screen::T8 | no sheet | drop row rebind | A | AUTO |
| TC-209-18 (§7.2) | profile parity | widget | settings_profile_section_test (existing 11) + settings_wired::(:907/:970 kept) | n/a — sentinels; adjust only a size assert if pinned | break onPickAvatar wiring | A | AUTO (existing) |
| TC-209-19 | header parity | widget | settings_screen_test::(title/back kept) | n/a — sentinel | remove title | A | AUTO |
| TC-209-20 | small viewport | widget | one_screen::T4 | rows absent | make column non-scrollable | A | AUTO |
| TC-209-21 | text scale | widget | one_screen::T5 | rows absent | fixed-height clip → overflow | A | AUTO |
| TC-209-22 | tone | widget | one_screen::T6 | rows absent | hardcode dark colors | A | AUTO |
| TC-209-23 | debug reachability | widget | settings_wired_test::(:334 debug-card test kept, retargeted to last-slot) | n/a — sentinel | drop debugSection slot | A | AUTO |
| TC-209-24 | sub-sheet content | widget | sub_sheets::T1 | no sheet | omit an option | A | AUTO |
| TC-209-25 | persist+propagate | widget | sub_sheets::T2 | no sheet | skip setBackgroundPreference | A | AUTO |
| TC-209-26 | failure revert | widget | sub_sheets::T3 | no sheet path | drop revert | A | AUTO |
| TC-209-27 | quality sheet + kind | widget | sub_sheets::T4 (discriminator: mediaQuality AND NOT identity, count==1) | no sheet | duplicate kind fire | A | AUTO |
| TC-209-28 | independence | widget | sub_sheets::T5 | no sheet | cross-wire handlers | A | AUTO |
| TC-209-29 | recovery parity | widget | sub_sheets::T6 | no sheet | skip re-blur | A | AUTO |
| TC-209-30 | conditional recovery | widget | sub_sheets::T7 | row unconditional? RED: row absent on HEAD | unconditional row | A | AUTO |
| TC-209-31 | dismiss-no-change | widget | sub_sheets::T8 | no sheet | write-on-open | A | AUTO |
| TC-209-32 | in-flight save | widget | sub_sheets::T9 | no sheet | drop mounted-guard | A | AUTO |
| TC-209-33 | peer-ID copy | widget | settings_wired_test::(peer-copy retargeted) — full ID on clipboard, 2s check | old finder gone / new row absent | copy truncated string | A | AUTO |
| TC-209-34 | nearby inline | widget | settings_wired_posts_nearby_test (existing 3, sentinel) + one_screen::T2 (`settings-row-nearby`) | row absent | move switch into a sheet | A | AUTO |
| TC-209-35 | move row + key | widget | settings_wired_test::(:516/:540 kept) + orbit_settings_entry::TC-206-23 (sentinel) | key vanishes if re-keyed | re-key the action | A + G | AUTO + :231 |
| TC-209-36 | move single-flight | widget | settings_wired_test::(new assert on :516 test — double-tap pushes once) | no guard on HEAD? verify — if guarded, sentinel | remove guard | A | AUTO |
| TC-209-37 | PROD-CRITICAL chain | widget | orbit_qr_entry_migration::T6 | no tiles | revert E5 | G | :254 |
| TC-209-38 | post-scan data | widget | orbit_qr_entry_migration::T6 (repo-contains + fresh-tree assert) | no tiles | drop addContact (out of scope — sentinel via qr_scanner_wired_test) | G + B | :254 + :10 |
| TC-209-39 | side effects | widget | qr_scanner_wired_test (existing, sentinel — mutual add + avatar dl) | n/a untouched | — (sentinel) | B | :10 (existing) |
| TC-209-40 | migration QR | widget | orbit_qr_entry_migration::T7 | no tiles | drop onMigrationQrScanned from closure | G | :254 |
| TC-209-41 | invalid/expired/self | widget | qr_display/scanner sentinels (parse path untouched) + T6 uses valid-QR only | n/a — parser untouched | — (sentinel: qr_scanner_wired_test) | B | :10 |
| TC-209-42 | pre-identity scan | widget | orbit_qr_entry_migration::T10 | no tiles | break '' ownPeerId path | G | :254 |
| TC-209-43 | FTE unaffected | widget | existing FTE tests (sentinel; zero FTE edits) | n/a | — | A | AUTO (existing) |
| TC-209-44 | change kinds | widget | settings_wired_test::(:907/:930/:970 kept verbatim) | n/a — sentinels | fire duplicate/.then | A | AUTO |
| TC-209-45 | l10n integrity | unit | test/l10n/l10n_integrity_test.dart + orbit_strings_parity_test (both existing) | new literals/keys break them if done wrong | hardcode a tile label | `flutter test test/l10n/` | pinned :259 + manual cmd |
| TC-209-46 | RTL page | widget | one_screen::T7 | rows absent | force LTR | A | AUTO |
| TC-209-47 | nav + latch | widget | settings_wired_test::(:848 kept) + orbit_settings_entry (latch tests, sentinel) | n/a — sentinels | stick the latch | A + G | AUTO + :231 |
| TC-209-48 | session cleanup | widget | one_screen::T9 + sub_sheets::T8/T9 combined flow | rows absent | leak sheet route | A | AUTO |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability:** one_screen::T9 (reopen reconstructs persisted values through a fresh mount). Covered.
- **Sibling-surface consistency:** the tiles gate as a PAIR — both render or neither (qr_tiles::T6 asserts both absent together; no My-QR-only asymmetry from a degraded host). Covered.
- **Destructive-action side-effects:** the only deletions are code (chrome/dead widget) — locked by orbit_qr_entry_migration::T1/T2/T3 asserting what remains (toggle, FAB, padding) not just absence. Recovery re-blur asserted in sub_sheets::T6. Covered.
- **Invariant re-verification under new transitions:** the new transition is "scanner success destroys the Settings route" — the latch cannot stick because the whole orbit-hosting tree is replaced (fresh FeedWired), asserted in T6; the surviving-tree case (scanner dismissed) re-verified by T8's close-returns-to-Settings + orbit_settings_entry latch sentinels. Covered.

## Invariants (locked by tests)
- INV-209-1: Settings tiles mount ONLY when the host supplies both QR callbacks → qr_tiles::T6.
- INV-209-2: `qr_scanner_wired.dart`/`qr_display_wired.dart` are byte-untouched; post-scan contract unchanged → BASELINE sentinel (qr_scanner_wired_test 7/7) + `git diff --name-only` check in QA.
- INV-209-3: One-Screen fit is a pinned-constants contract (avatar 72, rows 44, tiles ≤72, Switch shrinkWrap) → one_screen::T1.
- INV-209-4: `settings-move-account-action` key + 'Settings' title + 'Share People Nearby' text survive → orbit_settings_entry_test (existing).
- INV-196-7 (inherited): destination contracts at the new host → orbit_qr_entry_migration::T6-T10.
- INV-196-8 (inherited): `orbit_my_qr`/`orbit_scan` stay in en/ar/de → orbit_strings_parity_test (existing).
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. `git status --short` snapshot (dirty tree expected — 206-era working-tree edits; record).
2. Add RED tests (catalog files 1-4 + rewrites 5-6); run focused commands; confirm RED for documented reasons (compile-RED where new ctor params are asserted is acceptable and documented).
3. **E1** `lib/features/settings/presentation/widgets/settings_qr_tiles.dart` (NEW): two glass tiles, keys `settings-my-qr-tile`/`settings-scan-tile`, `l10n.orbit_my_qr`/`l10n.orbit_scan` visible labels, `Semantics(button)`, ≥44px targets, ambient text direction (NO forced LTR), styling per friend_row.dart:55-61 tokens.
4. **E2** `lib/features/settings/presentation/widgets/settings_group.dart` (NEW): `SettingsGroupCard(label, children)` + `SettingsListRow(key, icon, label, value?, trailing)` — 44px min-height custom rows (NOT ListTile), divider `rgba(255,255,255,0.12)`, chevron/switch/copy trailings.
5. **E3** `settings_screen.dart`: One-Screen column — profile (avatar 72, padding 10/14 via SettingsProfileSection param or edit), tiles (conditional), IDENTITY group (peer-id row `settings-row-peer-id` w/ copy trailing reusing onCopyPeerId/isPeerIdCopied; recovery row `settings-row-recovery` gated 12-words), PREFERENCES group (background/photo/video rows w/ value strings, nearby row `settings-row-nearby` w/ `Switch.adaptive(materialTapTargetSize: shrinkWrap)`, move row keyed `settings-move-account-action`), `?debugSection` last; header/nav/AmbientBackground/bottom-padding rules unchanged. New ctor params: row callbacks + value strings (or enums) + `onMyQr`/`onScan` VoidCallbacks.
6. **E4** `settings_wired.dart`: `onMyQrRequested`/`onScanQrRequested` optional `Future<void> Function()` params + `_qrRouteActive` latch (mirror `_settingsRouteActive`); sheet launchers `_openBackgroundSheet`/`_openPhotoQualitySheet`/`_openVideoQualitySheet`/`_openRecoverySheet` via `showModalBottomSheet` (P1/P2 style: `surfaceBase` bg, top-radius 16, divider border) hosting the EXISTING widgets (`BackgroundChoiceControl`, `ImageQualityToggle`, `SettingsRecoveryPhraseCard`) with tone via `BackgroundReadableColors.resolve(_currentBackgroundPreference)` + `Theme(extensions:)` (friend_picker_wired.dart:171-209 precedent); existing handlers reused verbatim (single mechanism, INV-206-6); StatefulBuilder/setState relay so in-sheet selection re-renders.
7. **E5** `orbit_wired.dart`: at :624-638 add `onMyQrRequested: () => _onMyQR()`, `onScanQrRequested: () => _onScanQR()` (bodies :2220-2342 unchanged — `.then(_applyRouteChanges)` and `onScanPressed: _onScanQR` cross-link intact); delete :2439-2440 props + :2427 args.
8. **E6** `orbit_screen.dart`: remove import :24, mount :602-603, required `onMyQR`/`onScanQR` at both layers (:205-206/:274-275/:342-343/:396-397/:450-451); comment sweep :786-792 (KEEP the 56px padding) + :314-318 docstring.
9. **E7** delete `orbit_qr_chrome_buttons.dart`, `qr_action_cards.dart` + their two test files (no gate array references either — verified).
10. **E8** l10n: add `settings_section_identity`, `settings_section_preferences` to en/ar/de ARBs atomically; `flutter gen-l10n`; commit generated files. (Tile labels reuse orbit keys — no deletions.)
11. Stop-if: any edit wants to touch `qr_scanner_wired.dart`/`qr_display_wired.dart` → replan (INV-209-2); any fit failure at T1 → adjust pinned constants, never the assertion.
12. Rerun direct → preservation → named gates (below).

## Risks And Edge Cases
- Razor-thin fit budget (+2..5px) → one_screen::T1 with real metrics; Dynamic-Island-class 393×852 margin ~0 — accepted (spec pins 390×844); T4 proves graceful scroll below.
- Stale-default value flash before storage settles → accepted (username precedent); tests assert post-settle only.
- Sheet context lacks ambient readable-colors extension → Theme-extension wrap per FriendPicker precedent; sub_sheets::T1/T6 + one_screen::T6 catch tone regressions.
- `settings_wired_posts_nearby_test` Switch finder vs shrinkWrap row → verify early; adjust row not the sentinel.
- Rewriting a GROUP_TESTS-pinned file in place: file must never be deleted/renamed (gate `flutter test` fails on missing path) — rewrite only.

## Device/Relay Proof Profile
host-only for closure (pure Flutter UI/nav; no DB migration, no crypto, no OS boundary, no relay — same class as 205/206/208). No /sims scenario. Deferred device work: none.

## Acceptance Gates  (literal)
```bash
# RED (before production edits) — must FAIL for documented reasons
flutter test test/features/settings/presentation/widgets/settings_qr_tiles_test.dart
flutter test test/features/settings/presentation/screens/settings_one_screen_layout_test.dart
flutter test test/features/settings/presentation/screens/settings_sub_sheets_test.dart
flutter test test/features/orbit/presentation/screens/orbit_qr_entry_migration_test.dart

# Direct GREEN (after E1-E8)
flutter test test/features/settings/ test/features/orbit/presentation/screens/orbit_qr_entry_migration_test.dart test/features/orbit/presentation/screens/orbit_settings_entry_test.dart
# expect: all pass; settings suite grows by ~25 new tests (record actuals)

# Preservation sentinels
./scripts/run_test_gates.sh baseline    # qr_scanner_wired_test 7/7 inside — MUST be untouched-green
./scripts/run_test_gates.sh feed        # expect: green (last recorded total 285-290 range; re-record)
./scripts/run_test_gates.sh groups      # expect: green (last recorded ~1055; delta = rewritten :254 file + deleted chrome tests; re-record)
flutter test test/l10n/                 # parity + integrity: 7/7 (orbit keys kept; 2 new settings_* keys in all 3 ARBs)
flutter test test/features/settings/presentation/screens/settings_wired_posts_nearby_test.dart   # 3/3
./scripts/run_host_test_gates.sh feature-host-all   # 0 failures

# Hygiene
git diff --name-only | grep -E 'qr_scanner_wired\.dart|qr_display_wired\.dart' && echo 'INV-209-2 VIOLATION' || true
flutter analyze            # 0 new issues
git diff --check
```

## Known-Failure Interpretation
- Expected RED: the 4 catalog files above before E1-E8 (incl. compile-RED on new ctor params — documented, acceptable).
- Pre-existing dirty tree: 206-era working-tree modifications (`orbit_wired.dart`, `group_list_wired.dart`, tests, graphify meta, `info.plist`) — do NOT revert.
- Environment blocker (NOT product): none expected (host-only).
- Scope drift (BLOCKING): any diff in `qr_scanner_wired.dart`/`qr_display_wired.dart`/FTE/AccountMigration files.

## Done Criteria
- [ ] RED added first, failed for documented reasons.
- [ ] Every edit mutation-verified per matrix.
- [ ] Direct GREEN + all preservation sentinels + named gates green; new totals recorded in this doc.
- [ ] No migration (none needed) · no sim/device rows (host-only class).
- [ ] All new tests auto-globbed or riding existing pinned paths (:254/:231) — zero array edits required; verified via gate runs.
- [ ] flutter analyze 0 new; git diff --check clean; INV-209-2 grep clean.

## Scope Guard (hard "Do not")
- Do not edit `qr_scanner_wired.dart` or `qr_display_wired.dart` (BASELINE + 196 own the contracts).
- Do not thread scanner deps through `SettingsWired`/`PostsWired` ctors (refuted architecture; host-callback design only).
- Do not delete or rename `orbit_qr_entry_migration_test.dart` (GROUP_TESTS :254 path) — rewrite in place.
- Do not remove `orbit_my_qr`/`orbit_scan` from any ARB (parity getters + tiles consume them).
- Do not touch the 206 center-avatar detector, latch, or change-kind enum/consumers.
- Do not use ListTile for rows or leave the nearby Switch at `.padded` (fit budget).
- Do not add a `.then`-based settings-change refresh anywhere (INV-206-6 / INV-203-1 lesson).

## Accepted Differences / Intentionally Out Of Scope
- Posts-entry Settings shows NO QR tiles (dead host, cannot supply deps) — spec §7.1; revisit only if PostsWired ever ships.
- First-frame stale-default row values until secure storage settles — existing app pattern (username placeholder).
- 393×852 (Dynamic Island) fit margin ~0px — spec pins 390×844; taller-safe-area devices may scroll by a few px.
- textScale between 1.0 and 1.5 unspecified by spec — T5 locks 1.5 no-overflow only.
- `orbit_qr_share`/`orbit_qr_scan_desc` ARB keys may become orphaned — left in place (parity-safe), cleanup owned by a future l10n-hygiene pass.

## Dependency Impact
- 206 depends on this keeping the Settings entry + latch intact (locked by orbit_settings_entry_test staying pinned-green).
- 196's chrome invariants INV-196-1/4/5/6 are formally RETIRED by this plan; INV-196-7/8 transfer to the rewritten :254 file — 00-INDEX rows for 196 remain historical record.
- Future "scan-returns-to-Settings" UX (if ever wanted) must be an additive optional success-nav override on QRScannerWired with default-preserving semantics — recorded here so it is not attempted as a rewrite (BASELINE kill).

## Reviewer Findings
Sufficiency self-check (references/sufficiency-checklist.md): spec-case totality — all 48 TCs mapped (48 matrix rows, several sharing tests by design; zero orphans). Every INV has a named test. Mutations named per row. No vacuous coverage: reds documented against HEAD; kind-discriminator asserted (T4: mediaQuality AND NOT identity). No DB migration → migration gate N/A. No OS/crypto/multi-device boundary → sim/device gate N/A (host-only class, precedent 205/206/208). PROD-CRITICAL leg named (orbit_qr_entry_migration::T6). Preservation sentinels named with commands. Literal gates present. Registration: all AUTO or existing pinned paths — zero array edits, verified against run_test_gates.sh mechanics (arrays fail on missing paths; no counts asserted). Known-failure interpretation + dirty-tree snapshot planned. Refuted findings recorded (3) with do-not-re-introduce guards. Blind-spot sweep: 4/4 covered with named tests.

## Arbiter Decision
Structural blockers: none. Deferred details: exact new-test totals recorded at execution; settings_profile_section_test size-assert inspection at execution. Accepted differences: as listed. Hand off to execution.

## Final Execution Verdict
Verdict: (pending execution)
