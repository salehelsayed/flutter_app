# 196 - Migrate "My QR" / "Scan" entry points to Orbit top chrome  (Feature Improvement)

Status: implemented (host-green 2026-07-03; device validation via /sims)
Spec: Test-Flight-Improv/196-orbit-qr-scan-entry-migration-spec.md (approved design: mockup alternative B "Quiet Chrome", 196-orbit-qr-scan-entry-mockups.html)

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-02 | Evidence Collector (wf_1bb47e62-6cf, wf_3bf64e03-e20) | orbit_screen/orbit_wired/friends_list_header/toggle/fab/qr_* + full test/gate inventory | seam + lock inventory grounded, spec written | verify→refute |
| 2026-07-03 | Verify→Refute (wf_e3934c6d-a77, 3 agents) | same + SDK hit-test source, ARBs, gates | **A4 REFUTED** (title shares the chrome band — spec §3.2 corrected); A2/A7 adjusted; C1-C7/T1-T6 confirmed | plan |
| 2026-07-03 | Planner | tier-matrix, sufficiency-checklist, plan-template | matrix built; list-header strip-exit chosen as the de-collision design | reviewer |
| 2026-07-03 | Reviewer (sufficiency) | this plan vs checklist | all gates pass; see Reviewer Findings | arbiter |
| | Arbiter | | (final structural verdict) | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-07-03 | baseline (step 0) | — | `git status --short`; l10n_integrity = 3 orbit3 (unchanged); view_split **16/16** (197 added 2 group-ring tests — plan's "14" stale); orbit_wired **74/74**; **inner_circle_items_test PASSES** → 197 lib landed, perf/host quarantine LIFTED | scope confirmed; quarantine note updated | RED |
| 2026-07-03 | RED tests added | +A (orbit_qr_chrome_buttons_test), +B (orbit_qr_entry_migration_test), rewrite #28 (orbit_wired_test:859), rewrite #29 (orbit_view_split:441 → LTR+RTL vertical clearance), parity #30 (orbit_strings_parity) | A: compile-RED (widget missing); B: 0/18 (keys absent); #28/#29 RED (keys absent); #30 GREEN lock 3/3 | RED for documented reasons | implement |
| 2026-07-03 | implementation | +lib/…/orbit_qr_chrome_buttons.dart; orbit_screen.dart (import + Layer 1c mount + first-sliver 8→56 + drop 48px inset + `const FriendsListHeader()`); friends_list_header.dart (title-only, `_PillButton`+params deleted); GROUP_TESTS += B | scoped files only; Stack re-synced against dirty 197 tree | scoped | direct GREEN |
| 2026-07-03 | direct GREEN | A,B,view_split,orbit_wired,parity | A **9/9**, B **18/18**, view_split **16/16**, orbit_wired **74/74**, parity **3/3** | reds now green (fixed 2: TC-11 over-asserted QRDisplayScreen on noIdentity → copy-only; #29 loop State-reuse → `SizedBox` unmount per locale) | preservation |
| 2026-07-03 | preservation GREEN | — | loading 12/12, archived 10/10, intro-route 2/2, qr_display 11/11, qr_scanner 7/7, l10n_integrity delta **0** (same 3 orbit3) | sentinels green | named gates |
| 2026-07-03 | named gates | scripts/run_test_gates.sh | groups **+963 −1** (only ML-004 group-membership flake — passes in isolation, no group test imports my files), feed **283/283**, baseline **113/113**, completeness **1016/1016 PASS** | gate green (ML-004 = pre-existing flake, NOT 196) | QA |
| 2026-07-03 | QA (hygiene) | — | `flutter analyze` 8 changed files = **No issues found!**; `git diff --check` clean; GROUP_TESTS entry present; perf harness now COMPILES (device-gated) | blocking: none | device via /sims |

## Source Of Truth
- Spec: Test-Flight-Improv/196-orbit-qr-scan-entry-migration-spec.md
- Gate definitions: scripts/run_test_gates.sh (script wins over prose)
- Discovery/registration: scripts/check_reliability_simulation_discovery.sh
- Numbering / index: Test-Flight-Improv/00-INDEX.md

## Session Classification
implementation-ready

## Exact Problem Statement
Post-193, Orbit opens on the Inner-Circle surface, but the app's only Orbit-tab entry points to My QR / Scan are pills inside `FriendsListHeader`, mounted only on the all-chats list surface (`orbit_screen.dart:594-598`) and hidden during search (`friends_list_header.dart:37`). The primary contact-growth mechanism of a serverless P2P app is two taps plus mode-discovery away from the default surface. The pills are also bare `GestureDetector`s with zero `Semantics`.

What must improve: twin 40×40 chrome circle buttons (toggle species: `surfaceSubtle` fill, 0.5 hairline, 20px `textPrimary` glyph) at top-center, `top = safeTop+8`, on **both** surfaces; icon-only with `Semantics(button: true, label: l10n.orbit_my_qr / orbit_scan)`; physical (non-mirroring) centered placement; pills removed.

What must stay unchanged (→ preserved-green sentinels): `_onMyQR`/`_onScanQR` handler bodies incl. the B6 `feedClearedRepository`→scanner handoff (`orbit_wired_test.dart:404`), `buildConversationRoute` full-screen pushes, toggle + FAB placement/behavior, 193 view-state locks (default/reset/deep-link), 194 unread indicators, search dock behavior, FTE scan entry, `ScanFriendCard` re-fire, l10n keys in all three ARBs.

## Root Cause (verify → refute confirmed)
Mechanism (feature-improvement "cause" = placement): QR entries are coupled to `FriendsListHeader`, which exists only on the non-default surface — `orbit_screen.dart:594-598` is the sole `FriendsListHeader` ctor site; `OrbitScreen.onMyQR/onScanQR` (`:192-193`, required `:245-246`) are consumed nowhere else (C2 confirmed). `_onMyQR`/`_onScanQR` (`orbit_wired.dart:2079-2093`, `:2130-2201`) read no list/surface state — safe to invoke from the inner circle (C3 confirmed).

**Refuted / adjusted — do NOT re-introduce the naive versions:**
- **A4 REFUTED**: "top-center is free on the list surface" is FALSE — the header row's top edge is exactly `safeTop+8` (first sliver padding `fromLTRB(16,8,16,0)`, `orbit_screen.dart:577-579`); a centered 88px pair intersects the title at every supported width (en ≤ ~458dp; guaranteed under the Ahem font at the 430dp test surface; ar title is right-anchored and collides too). **Design response (this plan): the list header leaves the strip** — first-sliver top padding 8 → 56, the now-purposeless 48px physical-left inset (`:590-593`) is removed, and the RTL lock test is rewritten to the new invariant (vertical clearance). Bonus: this also removes the pre-existing LTR bug where the Scan pill's right ~36px sits under the FAB's tap footprint, and the 320dp header-row overflow.
- **A2 adjusted**: no double-tap/re-entry guard exists at any layer (bare `Navigator.push`, no debounce) — double-push is possible **today** via the pills. Inherited knowingly; see Accepted Differences.
- **A7 adjusted**: the ORBIT perf harness is currently **non-compiling** — a concurrent 197 session's `integration_test/orbit_performance_harness.dart:16,:204` + `test/features/orbit/application/inner_circle_items_test.dart:5` import a not-yet-existing `lib/features/orbit/application/inner_circle_items.dart`. Perf gate + full `feature-host-all` sweep are quarantined until 197 lands (Known-Failure Interpretation).
- **T2 nuance**: pill removal alone does NOT flip the RTL lock (`orbit_view_split_test.dart:388-413` measures the whole header rect whose left edge is parent-padding-determined); it flips only when the 48px inset is removed — which this plan does, so the rewrite is mandatory, not optional.
- Chrome layer MUST be inserted **before** `ExpandableFab` in the body Stack (`orbit_screen.dart:480-496` is last child) — scrim precedence (A5/C4) holds only then.
- New chrome MUST use l10n getters for labels — `l10n_integrity_test.dart:105-108` catches `label: '…'`/`tooltip: '…'` literals and the literal-scan's violation delta would grow.

## Real Scope
In scope: new `OrbitQrChromeButtons` widget (top-center pair); mount in `orbit_screen.dart` Stack (Layer 1c, before FAB) on both surfaces fed by the existing `onMyQR`/`onScanQR`; list-surface strip-exit (top padding 8→56, drop 48px inset); `FriendsListHeader` reduced to title-only (params `onMyQR`/`onScanQR`/`searchActive` removed); rewrite of the two superseded locks; parity-test extension; new widget + wired test files.
Out of scope (owner in parens): double-tap guard on QR pushes (follow-up, unowned — see Accepted Differences); `QRActionCards` dead-code deletion (cleanup session); `ownPeerId ''` fallback redesign (existing contract, locked as-is); 197 inner-circle-rings work (concurrent session); orbit3 l10n literals (pre-existing RED).

## Files To Inspect Next
Production: `lib/features/orbit/presentation/screens/orbit_screen.dart` (:339-501 Stack, :507-559 inner surface, :564-631 list surface), `lib/features/orbit/presentation/widgets/friends_list_header.dart`, `lib/features/orbit/presentation/widgets/orbit_view_toggle_button.dart` (donor), `lib/features/orbit/presentation/screens/orbit_wired.dart` (:2079-2201, :2300-2301 — read-only), `lib/features/groups/presentation/widgets/expandable_fab.dart` (:146-155 scrim — read-only).
Direct tests: `test/features/orbit/presentation/screens/orbit_wired_test.dart` (:859-873, :374-377 helper), `orbit_view_split_test.dart` (:388-413, harness :71-244), `test/l10n/orbit_strings_parity_test.dart` (:18-24), `test/l10n/l10n_integrity_test.dart`.
Dependency-only context: `orbit_screen_loading_test.dart`/`orbit_screen_archived_groups_test.dart`/`intro_notification_orbit_route_test.dart`/`integration_test/orbit_performance_harness.dart` (bare-pump ctor sites — compile-coupled, keep `onMyQR`/`onScanQR` params), `qr_display_wired_test.dart`, `qr_scanner_wired_test.dart` (BASELINE:10).

## Existing Tests Covering This Area
- `orbit_wired_test.dart::friends list header shows QR buttons` (:859) — the ONLY test that flips on pill removal (T5 sweep: exactly one) → rewritten here.
- `orbit_view_split_test.dart::all-chats header clears the top-left toggle in RTL` (:388) — flips only when the 48px inset goes → rewritten here.
- `orbit_view_split_test.dart` 14 tests — 193 locks (default entry, toggle round-trip, semantics flip, remount, re-entry reset) — sentinels.
- `orbit_wired_test.dart::B6…feedClearedRepository` (:404) — scanner-handoff sentinel.
- `qr_display_wired_test.dart` (12) / `qr_scanner_wired_test.dart` (7, BASELINE_TESTS:10) — destination sentinels.
- Inner-circle purity test (`orbit_view_split_test.dart:282-292`) asserts absence by TYPE list only — does NOT lock new chrome (T5.7): per-surface chrome locks are NEW coverage.
Missing coverage gaps: no `friends_list_header_test.dart`, no widget-tier pill lock, no a11y lock on QR entries, no per-surface QR-chrome locks — all filled below.
Already in curated arrays: orbit_wired_test (GROUP_TESTS:227), orbit_view_split_test (:241), orbit_unread_indicator_wired_test (:246), orbit_strings_parity_test (:247); qr_scanner_wired_test (BASELINE:10); feed suite (FEED_TESTS:155-191).

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

New file A — `test/features/orbit/presentation/widgets/orbit_qr_chrome_buttons_test.dart` (widget tier, 9 tests):
1. `renders two 40px chrome circles with toggle-species tokens` — pump `OrbitQrChromeButtons` in a `MaterialApp`+theme-extension wrap (donor: `orbit_close_button_test.dart`). RED: widget/file does not exist (compile fail = RED). GREEN: two `ValueKey('orbit-my-qr-button')`/`ValueKey('orbit-scan-button')` containers, 40×40, `BoxShape.circle`, `surfaceSubtle` fill, 0.5 border. Mutation: revert widget creation → red.
2. `shows qr_code and camera_alt_outlined at 20px textPrimary` — RED same. Mutation: swap icon/size → red.
3. `exposes button semantics labeled from l10n (en)` — `ensureSemantics()` (in-body dispose, cat.6); `find.bySemanticsLabel('My QR')`/`('Scan')` + button flag. RED same. Mutation: drop `Semantics` wrapper → red.
4. `semantics labels localize (ar)` — pump locale `ar`; labels 'رمزي'/'مسح'. Mutation: hardcode English label → red (also grows literal-scan delta).
5. `tap My QR fires onMyQR only` — spy callbacks. Mutation: cross-wire callbacks → red.
6. `tap Scan fires onScanQR only` — same inverted.
7. `keeps physical order under RTL` — `Directionality.rtl`: MyQR.center.dx < Scan.center.dx. Mutation: use a direction-following Row without a fixed `textDirection` → red.
8. `resolves the light readable tone on daylight preference` — light `surfaceSubtle`/dark `textPrimary` (donor: toggle/close-button daylight tests). Mutation: hardcode dark tokens → red.
9. `pair is centered with an 8px gap at top safeTop+8` — padded `MediaQuery`; rects symmetric about center ±1, gap 8, top = padding.top+8. Mutation: change offset/gap → red.

New file B — `test/features/orbit/presentation/screens/orbit_qr_entry_migration_test.dart` (wired host; clone `buildOrbitWired`/`pumpOrbitFrames`/`setLargeTestSurface`/`switchToAllChats` harness from `orbit_view_split_test.dart:71-244`; **bounded pumps only, never pumpAndSettle**; 18 tests):
10. `TC-01/02: inner-circle default shows the centered QR chrome pair` — RED: keys absent on HEAD (A1 confirmed: no chrome exists). GREEN: both keys present on the default surface, top row geometry. Mutation: unmount Layer 1c → red.
11. `TC-03: 320dp width keeps toggle, pair, and FAB disjoint` — surface 320×690@1.0; pairwise rect intersections empty; all hit-testable. Mutation: widen pair/gap or shift offsets → red.
12. `TC-04: RTL keeps the pair centered, ordered, and clear of toggle/FAB` — locale ar. RED: keys absent. Mutation: directional positioning → red.
13. `TC-06: bare OrbitScreen (onToggleView null, viewMode innerCircle) still mounts the chrome` — bare pump (donor: loading_test helper). Mutation: gate chrome on `onToggleView != null` → red (locks the C6 perf-harness caveat: chrome must not use the toggle's nullability pattern).
14. `TC-07: tap My QR pushes the QR display and pop returns to the inner circle` — RED: key absent. GREEN: `QRDisplayScreen` present after tap; after pop `OrbitalVisualization` present, list absent. Mutation: unwire `onMyQR` from chrome → red.
15. `TC-08: tap Scan pushes the scanner (B6 dep set intact)` — GREEN: `QRScannerScreen` present (construction proves the ~25-dep set incl. feedClearedRepository). Mutation: unwire `onScanQR` → red.
16. `TC-09: ScanFriendCard inside the pushed QR display still opens the scanner` — tap chrome My QR → tap ScanFriendCard → scanner. Mutation: drop `onScanPressed: _onScanQR` thread → red. (Discriminator: asserts the *display→scanner* path, not the direct chrome→scanner path — both end on `QRScannerScreen`, so the test first asserts `QRDisplayScreen` present and taps `ScanFriendCard`, never the chrome Scan key.)
17. `TC-10: Scan tap before identity load opens the scanner without crashing` — identity fake pending/null; existing `ownPeerId ''` contract locked as-is. Mutation: n/a-guard (locks existing behavior; goes red if a throwing guard is added — deliberate).
18. `TC-11: My QR without identity shows the display's noIdentity state` — null-identity fake; assert error-state copy (donor: `qr_display_wired_test.dart:88`). Mutation: break the repo/bridge pass-through → red.
19. `TC-12: open FAB scrim eats a tap at the chrome position` — open GlowFab, tap at My QR key's global center via `tester.tapAt`; GREEN: menu closes ('New Group' gone), NO `QRDisplayScreen`. Mutation: move chrome layer AFTER ExpandableFab in the Stack → red (INV-196-6).
20. `TC-13: all-chats header carries no QR pills` — switchToAllChats; RED on HEAD: `find.text('My QR')` finds the pill (test asserts findsNothing → red today). GREEN after removal. Mutation: restore pills → red.
21. `TC-14: chrome pair present and functional on the all-chats surface` — tap My QR from list view → display. Mutation: mount chrome per-surface (inner only) → red.
22. `TC-15: active search keeps the chrome tappable` — activate search via trigger; tap Scan → scanner. Mutation: re-introduce a searchActive-hiding rule → red.
23. `TC-17: intros deep link (initialFilterTab 'intros') lands with working chrome` — `OrbitWired(initialFilterTab: 'intros')`; list surface + chrome tap works (A8: preserves today's access). Mutation: gate chrome on viewMode → red.
24. `TC-21: Feed→Orbit re-entry reset re-mounts the inner circle with chrome present` — appShellController rising edge (donor: view_split :584). Mutation: chrome tied to list-surface subtree → red.
25. `TC-22: rapid toggle round-trips keep exactly one chrome pair` — flip 4×; `findsOneWidget` per key each stop. Mutation: mount a second pair inside a surface builder → red.
26. `TC-23: fresh remount (SizedBox) reconstructs the chrome on the default surface` — cat.12 trick (view_split :575). Mutation: stateful latch that survives only warm rebuilds → red.
27. `TC-24: scrolling the list under the chrome keeps it fixed and tappable` — drag list 300px; chrome rect unchanged; tap Scan → scanner. Mutation: put chrome inside the CustomScrollView → red.

Rewrites (in place, same files/gates):
28. `orbit_wired_test.dart:859` → rename `orbit chrome exposes QR entries on both surfaces; the header has no pills`: assert chrome keys on inner circle AND after switchToAllChats, plus `find.text('My QR')`/`find.text('Scan')` findsNothing (T1: Semantics labels create no Text). RED on HEAD in its new form (keys absent + pill Texts present). Mutation: restore pills or unmount chrome → red.
29. `orbit_view_split_test.dart:388` → rename `all-chats header clears the top chrome strip (LTR+RTL)`: `headerRect.top >= toggleRect.bottom` AND header∩pairRect = ∅, run in both locales (replaces the stale left-edge assert whose pill justification dies; T2). RED on HEAD: header top == toggle top (same band). Mutation: revert first-sliver padding 56→8 → red.
30. `test/l10n/orbit_strings_parity_test.dart:18-24` → add `orbit_my_qr`, `orbit_scan` to the key list (ARB presence + generated-API blocks). **GREEN-on-HEAD lock** (T3), mutation-verified: delete `orbit_my_qr` from `app_ar.arb` → red. Keeps the keys live once the pills (their only current consumers) are gone.

## Test Coverage Matrix  (ZERO empty cells)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-196-01 | UI render | widget + wired | A#1,A#2 / B#10 | widget absent / keys absent | delete widget / unmount layer | `flutter test <A>` + `<B>` | AUTO (glob) / AUTO + **add B to GROUP_TESTS** |
| TC-196-02 | geometry | widget | A#9 | widget absent | change offset/gap | `flutter test <A>` | AUTO (glob) |
| TC-196-03 | boundary geometry | wired | B#11 | keys absent | shift offsets | `flutter test <B>` | AUTO + GROUP_TESTS |
| TC-196-04 | RTL | widget + wired | A#7 / B#12 | widget/keys absent | directional Row/Positioned | `flutter test <A>` `<B>` | AUTO / AUTO + GROUP_TESTS |
| TC-196-05 | theming | widget | A#8 | widget absent | hardcode dark tokens | `flutter test <A>` | AUTO (glob) |
| TC-196-06 | ctor nullability | wired (bare pump) | B#13 | keys absent | gate on onToggleView | `flutter test <B>` | AUTO + GROUP_TESTS |
| TC-196-07 | route push | wired | B#14 | keys absent | unwire onMyQR | `flutter test <B>` | AUTO + GROUP_TESTS |
| TC-196-08 | route push + B6 | wired | B#15 + sentinel `orbit_wired_test.dart:404` | keys absent | unwire onScanQR | `flutter test <B>`; `./scripts/run_test_gates.sh groups` | AUTO + GROUP_TESTS / already GROUP_TESTS:227 |
| TC-196-09 | nested thread | wired | B#16 | keys absent | drop onScanPressed thread | `flutter test <B>` | AUTO + GROUP_TESTS |
| TC-196-10 | boundary (identity) | wired | B#17 | keys absent | add throwing guard | `flutter test <B>` | AUTO + GROUP_TESTS |
| TC-196-11 | boundary (identity) | wired | B#18 | keys absent | break repo pass-through | `flutter test <B>` | AUTO + GROUP_TESTS |
| TC-196-12 | z-order/scrim | wired | B#19 | keys absent | mount chrome after FAB | `flutter test <B>` | AUTO + GROUP_TESTS |
| TC-196-13 | pill removal | wired | B#20 + rewrite #28 | pills PRESENT on HEAD (findsNothing red) | restore pills | `flutter test <B>`; `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart` | AUTO + GROUP_TESTS / GROUP_TESTS:227 |
| TC-196-14 | sibling surface | wired | B#21, #28 | keys absent | inner-only mount | `flutter test <B>` | AUTO + GROUP_TESTS |
| TC-196-15 | search interaction | wired | B#22 | keys absent | searchActive hiding | `flutter test <B>` | AUTO + GROUP_TESTS |
| TC-196-16 | RTL/vertical clearance | wired | rewrite #29 | header top == toggle top (same band) | revert padding 56→8 / restore 48px inset semantics | `flutter test test/features/orbit/presentation/screens/orbit_view_split_test.dart` | already GROUP_TESTS:241 |
| TC-196-17 | deep link | wired | B#23 | keys absent | viewMode-gate chrome | `flutter test <B>` | AUTO + GROUP_TESTS |
| TC-196-18 | a11y | widget | A#3, A#4 | no semantics nodes | drop Semantics | `flutter test <A>` | AUTO (glob) |
| TC-196-19 | l10n parity | plain test | rewrite #30 | GREEN-on-HEAD lock | delete key from app_ar.arb | `flutter test test/l10n/orbit_strings_parity_test.dart` | already GROUP_TESTS:247 |
| TC-196-20 | l10n integrity delta | plain test (sentinel) | `l10n_integrity_test.dart:45` | pre-existing RED (3 orbit3) — assert **no growth** | hardcode a chrome label | `flutter test test/l10n/l10n_integrity_test.dart` (expect same 3 violations) | host-all glob (existing) |
| TC-196-21 | 193 transition | wired | B#24 + view_split :584 sentinel | keys absent | list-subtree mount | `flutter test <B>`; groups gate | AUTO + GROUP_TESTS / :241 |
| TC-196-22 | transition idempotence | wired | B#25 | keys absent | per-surface duplicate mount | `flutter test <B>` | AUTO + GROUP_TESTS |
| TC-196-23 | lifecycle remount | wired | B#26 | keys absent | warm-only latch | `flutter test <B>` | AUTO + GROUP_TESTS |
| TC-196-24 | scroll/z-order | wired | B#27 | keys absent | chrome inside scroll view | `flutter test <B>` | AUTO + GROUP_TESTS |
| TC-196-25 | perf | perf harness (integration_test, host-desktop sim) | existing ORBIT budgets (sentinel) | **quarantined: harness non-compiling (197)** | n/a (sentinel) | `./scripts/run_test_gates.sh performance` (PERF_TARGET=ORBIT) **after 197 lands** | existing PERF_TARGET=ORBIT dispatch — no new case |
| TC-196-26 | simulator sentinel | simulator | `integration_test/cold_start_message_render_simulator_test.dart` (unchanged) | GREEN sentinel | n/a (sentinel) | run directly per OPTIONAL_MANUAL_TESTS:311 (needs booted sim) | existing OPTIONAL_MANUAL_TESTS:311 |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability:** chrome is stateless; remount reconstruction locked by B#26 (cat.12) and re-entry reset by B#24. No persisted derived state introduced.
- **Sibling-surface consistency:** the capability exists identically on both surfaces + deep-link route — B#10/#21/#23 and rewrite #28 assert all three. Search-active asymmetry vs old pills is deliberate AND test-locked (B#22).
- **Destructive-action side-effects:** the destructive edit is pill removal — B#20/#28 assert what is removed; preserved artifacts asserted: title (loading_test :294 sentinel + #29), filter toggle & intro banner (view_split/archived sentinels), l10n keys stay live (#30), RTL clearance (#29). `_PillButton`/params deleted with the widget — sole-consumer proof A3/C2.
- **Invariant re-verification under new transitions:** no new state transitions added; every existing transition that rebuilds the tree (toggle flip, re-entry reset, remount, search open) re-verifies chrome presence via B#22/#24/#25/#26; scrim invariant re-checked in the FAB-open transition (B#19).

## Invariants (locked by tests)
- INV-196-1 chrome pair on both surfaces + deep-link route → B#10/#21/#23, #28
- INV-196-2 no QR pills in the header → B#20, #28
- INV-196-3 icon-only chrome has l10n-sourced button semantics → A#3/#4; literal-scan delta stays 3 (TC-196-20)
- INV-196-4 pair centered/physical-order, disjoint from toggle & FAB down to 320dp → A#7/#9, B#11/#12
- INV-196-5 list header clears the chrome strip vertically (LTR+RTL) → #29
- INV-196-6 chrome layer precedes ExpandableFab (open scrim wins) → B#19
- INV-196-7 handler bodies + destinations unchanged (B6, ScanFriendCard thread, noIdentity, ownPeerId contract) → B#15-18 + :404 sentinel
- INV-196-8 `orbit_my_qr`/`orbit_scan` live in en/ar/de → #30
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. `git status --short` snapshot (dirty 194/197 tree — record; revert NOTHING outside scope). Run baseline controls (gates section step 0) to fingerprint pre-existing reds (l10n literal-scan 3; 197 compile breaks).
2. Add RED tests: new files A and B, rewrite #28/#29 (their new forms), parity extension #30. Run the focused commands; confirm A/B fail (missing widget/keys), #28 fails (pills present / keys absent), #29 fails (same-band geometry), #30 green (lock).
3. Create `lib/features/orbit/presentation/widgets/orbit_qr_chrome_buttons.dart`: stateless `OrbitQrChromeButtons({required onMyQR, required onScanQR})` → `Positioned(top: MediaQuery.padding.top + 8, left: 0, right: 0)` → centered `Row` with **fixed `textDirection: TextDirection.ltr`** (physical order), two 40×40 circle buttons (toggle tokens via `context.backgroundReadableColors`), 8px `SizedBox`, `ValueKey('orbit-my-qr-button')`/`ValueKey('orbit-scan-button')`, `Semantics(button: true, label: l10n.orbit_my_qr / l10n.orbit_scan)`, `HitTestBehavior.opaque` on the buttons only (the full-width band must stay tap-transparent outside them).
4. `orbit_screen.dart`: mount `OrbitQrChromeButtons(onMyQR: onMyQR, onScanQR: onScanQR)` as Layer 1c — immediately after the toggle layer (:359-367), **before** every later layer; ExpandableFab stays the last child. Stop-if: any 197-session edit has restructured the Stack → re-sync, do not force.
5. `orbit_screen.dart` list surface: first-sliver padding `fromLTRB(16, 8, 16, 0)` → `fromLTRB(16, 56, 16, 0)`; delete the 48px inset Padding + its RTL comment (:583-593); update `FriendsListHeader(...)` ctor call to title-only.
6. `friends_list_header.dart`: remove `onMyQR`/`onScanQR`/`searchActive` params, the pill row, and `_PillButton` (sole-consumer proofs C2/A3). Keep widget name + title.
7. Rerun direct (A, B, orbit_wired_test, view_split, parity) → preservation sentinels → named gates (section below). Stop-if: any failure outside Known-Failure Interpretation → replan, do not hack.

## Risks And Edge Cases
- Concurrent 197 session actively edits the same files (`orbit_screen.dart`, perf harness, GROUP_TESTS) → snapshot + re-diff before committing; perf gate deferred (pinned by TC-196-25 quarantine).
- Chrome band must not block inner-circle content that can drift into the strip on very short viewports → buttons-only hit-testing (step 3) + B#27 scroll-under.
- `tester.tap` misses if chrome overlapped the toggle at test-surface geometry → B#11 disjointness at 320dp guards the whole suite's `switchToAllChats` taps.
- Double-push on rapid double-tap (A2) — pre-existing, now more reachable → Accepted Differences (follow-up named).
- Ahem-font width inflation makes title-collision worse in tests than prod → #29 asserts vertical clearance (band exit), which is font-independent.

## Device/Relay Proof Profile
host-only for closure (pure chrome UI: no OS boundary, no crypto, no multi-device, no relay). PROD-CRITICAL leg = B#14/#15 (wired tap → real route push through `_onMyQR`/`_onScanQR`) — unit/widget rows alone are NOT sufficient; the wired file must be green in the groups gate. Optional device evidence (per house practice): one screenshot run on a booted simulator after GREEN (`/run` or manual) — not a closure gate. No relay. No DB migration (no `DB v##`).

## Acceptance Gates  (literal — copy/paste)
```bash
# 0. Baseline control (BEFORE any edits — fingerprint pre-existing dirt)
git status --short
flutter test test/l10n/l10n_integrity_test.dart               # expect: +1 -1 (3 orbit3 literal violations — pre-existing)
flutter test test/features/orbit/presentation/screens/orbit_view_split_test.dart   # expect: 14/14 green
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart        # expect: green (count = tree baseline; record it)
# KNOWN 197 BREAKAGE (must fail to COMPILE, not for 196 reasons):
flutter test test/features/orbit/application/inner_circle_items_test.dart          # expect: compile error (missing inner_circle_items.dart)

# 1. RED (after adding tests, before production edits) — must FAIL for the documented reasons
flutter test test/features/orbit/presentation/widgets/orbit_qr_chrome_buttons_test.dart      # RED: widget file missing
flutter test test/features/orbit/presentation/screens/orbit_qr_entry_migration_test.dart     # RED: chrome keys absent; pills present
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name 'orbit chrome exposes QR entries on both surfaces; the header has no pills'   # RED
flutter test test/features/orbit/presentation/screens/orbit_view_split_test.dart --plain-name 'all-chats header clears the top chrome strip (LTR+RTL)'                 # RED
flutter test test/l10n/orbit_strings_parity_test.dart          # GREEN (lock, not RED — mutation-verified per plan)

# 2. Direct GREEN (after implementation)
flutter test test/features/orbit/presentation/widgets/orbit_qr_chrome_buttons_test.dart      # expect 9/9
flutter test test/features/orbit/presentation/screens/orbit_qr_entry_migration_test.dart     # expect 18/18
flutter test test/features/orbit/presentation/screens/orbit_view_split_test.dart             # expect 14/14
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart                  # expect: baseline count (one test rewritten, same total)
flutter test test/l10n/orbit_strings_parity_test.dart                                        # expect 3/3

# 3. Preservation sentinels (0 failures each)
flutter test test/features/orbit/presentation/screens/orbit_screen_loading_test.dart
flutter test test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart
flutter test test/features/push/application/intro_notification_orbit_route_test.dart
flutter test test/features/qr_code/presentation/screens/qr_display_wired_test.dart           # expect 12/12
flutter test test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart           # expect 7/7
flutter test test/l10n/l10n_integrity_test.dart                # expect: SAME +1 -1, violation list unchanged (3 orbit3 — NO growth)

# 4. Named gates (script counts are authoritative)
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh feed
./scripts/run_test_gates.sh baseline
./scripts/run_host_test_gates.sh feature-host-all   # QUARANTINE: inner_circle_items_test compile failure = 197's, NOT 196's (re-run --only after 197 lands)

# 5. Perf lane — DEFERRED until 197 restores the harness compile (A7):
./scripts/run_test_gates.sh performance             # PERF_TARGET=ORBIT included; run post-197 (use `performance`, not `performance-host` — 194 memory)

# 6. Registration verification
grep -n "orbit_qr_entry_migration_test.dart" scripts/run_test_gates.sh    # must show GROUP_TESTS entry
./scripts/run_test_gates.sh completeness-check                            # new files classify (feature-local pattern :702)

# 7. Hygiene
flutter analyze            # 0 NEW issues vs step-0 baseline
git diff --check
```

# Simulator sentinel (optional-manual, needs a booted sim; unchanged file):
# flutter test integration_test/cold_start_message_render_simulator_test.dart -d <SIM_ID>

## Known-Failure Interpretation
- Expected RED (pre-fix): files A and B, rewritten #28/#29 — for the reasons documented per test.
- Pre-existing dirty (NOT 196): l10n literal-scan 3 orbit3 violations; any drift in the 194-touched files recorded at step 0.
- **197 quarantine (NOT 196, NOT product):** compile failures in `integration_test/orbit_performance_harness.dart` and `test/features/orbit/application/inner_circle_items_test.dart` (missing `inner_circle_items.dart`) — block `performance` and part of `feature-host-all`; re-run after the 197 session lands its lib file.
- Environment blocker (NOT product): missing booted simulator for the optional cold-start sentinel.
- Scope drift (BLOCKING): any failure outside the above — especially in view_split's 193 locks, B6, or qr_* destination suites.

## Done Criteria
- [ ] RED added first; A/B/#28/#29 failed for the documented reasons (evidence in Execution Progress).
- [ ] Mutation-verified: each production edit has its named re-red revert (matrix column).
- [ ] Direct GREEN: A 9/9, B 18/18, view_split 14/14, orbit_wired baseline count, parity 3/3.
- [ ] Preservation sentinels + groups/feed/baseline gates green; literal-scan delta = 0.
- [ ] `orbit_qr_entry_migration_test.dart` appended to GROUP_TESTS and visible in the groups gate run; completeness-check green.
- [ ] flutter analyze 0 new; git diff --check clean; no Scope Guard violations.
- [ ] Perf lane re-run recorded post-197 (deferred item, tracked — not silently dropped).

## Scope Guard (hard "Do not")
- Do not modify `_onMyQR`/`_onScanQR` bodies, `QRDisplayWired`/`QRScannerWired`, or `buildConversationRoute`.
- Do not add a double-tap/debounce guard (follow-up owns it; adding one flips B#17's contract deliberately — replan first).
- Do not touch `integration_test/orbit_performance_harness.dart`, `inner_circle_items_*`, or anything 197 owns.
- Do not delete `QRActionCards` or its test (cleanup session owns it).
- Do not edit orbit3 files or "fix" the pre-existing literal-scan RED.
- Do not change toggle/FAB placement, 193 view-state seams, or 194 indicator code.
- Do not remove the overflow suppressions in feed/orbit suites (they become inert, not wrong).

## Accepted Differences / Intentionally Out Of Scope
- **Double-push on rapid double-tap** (A2): pre-existing at every layer; chrome widens exposure to the default surface. Follow-up candidate: route-guard in `_onMyQR`/`_onScanQR` (unowned). Locked-as-is by B#17's no-crash contract.
- **`ownPeerId ''` pre-identity window** (`orbit_wired.dart:2149`): existing contract, now more reachable; locked as-is by B#17. Redesign belongs to a scanner-hardening session.
- **Pill visual tokens** (`#157A39` accent family) leave the codebase with `_PillButton`; the chrome uses toggle tokens per the approved mockup (spec color note stands: no re-styling here).
- **194 chrome-vs-lit-node aesthetics** on the inner circle: mockup-approved; no test on "looks good".

## Dependency Impact
- 197 (orbit groups on inner-circle rings, concurrent) shares `orbit_screen.dart`'s Stack and the perf harness — 196's Layer-1c insertion is additive; sequence the perf gate after 197. If 197 lands first, re-diff step-4/5 anchors.
- Any future QR-entry work (e.g. settings) should reuse `OrbitQrChromeButtons`' semantics/l10n pattern; `orbit_my_qr`/`orbit_scan` keys are now chrome-owned (parity-locked by #30).

## Reviewer Findings
Sufficiency checklist run 2026-07-03 (planner-executed): all 26 spec TCs have matrix rows with zero empty tier/mutation/gate/registration cells; 2 GREEN-on-HEAD locks (#30, TC-196-20) explicitly marked and mutation-verified; blind-spot sweep has a row or justified N/A for all four classes; PROD-CRITICAL leg named (B#14/#15 in groups gate); refuted findings recorded (A4 title collision → design changed; A2/A7 adjusted); known-failure interpretation covers the 197 quarantine and the pre-existing l10n RED; dirty-tree snapshot is gate step 0. Residual risks: concurrent-session drift on `orbit_screen.dart` (mitigated by step-1 snapshot + step-4 stop-if) and deferred perf lane (tracked in Done Criteria, not dropped).

## Arbiter Decision
Structural blockers: none. | Deferred details: perf-lane run post-197; optional sim screenshot evidence. | Accepted differences: double-tap inheritance, ownPeerId window, pill token removal (all named above with owners).

## Final Execution Verdict
Verdict: **GREEN (host-complete)** | Files changed: 3 prod (`orbit_qr_chrome_buttons.dart` new, `orbit_screen.dart`, `friends_list_header.dart`) + 5 test/infra (`orbit_qr_chrome_buttons_test.dart` new, `orbit_qr_entry_migration_test.dart` new, `orbit_wired_test.dart` #28, `orbit_view_split_test.dart` #29, `orbit_strings_parity_test.dart` #30, `run_test_gates.sh` GROUP_TESTS) | Tests run: A 9/9, B 18/18, view_split 16/16, orbit_wired 74/74, parity 3/3, all preservation sentinels green, groups/feed/baseline/completeness gates green | Blocking: none (groups gate's single −1 = ML-004 group-membership flake, proven pre-existing: passes in isolation, no group test depends on any changed file) | QA verdict: analyze clean, git diff --check clean, l10n literal-scan delta 0. | Non-blocking follow-ups (owner): double-tap route guard (unowned follow-up); QRActionCards deletion (cleanup session); perf lane (`./scripts/run_test_gates.sh performance` PERF_TARGET=ORBIT) — quarantine LIFTED (197 `inner_circle_items.dart` landed, harness compiles), device/perf validation folded into the `/sims` device run.
