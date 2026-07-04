# 205 - Orbit Find-UX, Visibility, Centering + Orbit2/3 Prototype Cleanup  (Bug + Feature Improvement + Modification)

Status: awaiting-review
Spec: free-text intent (no formal spec) — 7-item user request, 2026-07-04

> Naming note: the user calls the live screen "Orbit3", but the shipped surface is
> `lib/features/orbit/` (the inner-circle default view, iterated by plans 193–203).
> `lib/features/orbit2/` + `lib/features/orbit3/` are **`kDebugMode` mock prototypes**
> (`kOrbit3PrototypeEnabled = kDebugMode`). Items 1–6 fix the **shipped** screen;
> item 7 **deletes** the dead prototypes. Grounding + verify→refute: workflow
> `wf_6a5af21e-829` (1 scout + 7 ground + 7 refute + 1 test-inventory, 0 refuted-away).

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-04 | Evidence Collector | inner_circle_interactive_surface.dart, orbital_visualization.dart, orbit_screen.dart, orbit_search_dock.dart, orbit_view_toggle_button.dart, orbit_arc_layout.dart, background_readable_colors.dart, feed_navigation_bar.dart, app_shell_tab.dart, feed_wired.dart, l10n | 7 seams located + source-confirmed (graph near-empty; all grep+Read) | verify→refute |
| 2026-07-04 | Verify→Refute (wf_6a5af21e-829) | HEAD 6dd9b617 | Item 1 = real gap on the **find pill** (dock red-herring already-fixed); items 2–7 SURVIVE; item 3 lens = 4 faint instances not 2 | derive obligations |
| 2026-07-04 | Planner (2 product forks resolved w/ user) | — | #6 = hide top chrome in edit; #1–2 = find pill only | emit plan |
| | Reviewer (sufficiency) | | | |
| | Arbiter | | (final structural verdict) | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| | contract extraction (git status --short) | | | scope confirmed | |
| | RED tests added | | (cmd proving they FAIL) | RED for expected reason | |
| | implementation | | | scoped files only | |
| | direct GREEN | | (exact cmd) | reds now green | |
| | preservation GREEN | | (exact cmd) | sentinels green | |
| | named gates | | (exact cmd + counts) | gate green | |
| | QA (independent) | | (re-run cmds) | blocking: none/list | verdict |

## Source Of Truth
- Spec / intent: inline below (7-item user request)
- Gate definitions: `scripts/run_test_gates.sh` (script wins over prose), `scripts/run_host_test_gates.sh`
- Discovery/registration: `scripts/check_reliability_simulation_discovery.sh` (no sim rows here)
- Numbering / index: `Test-Flight-Improv/00-INDEX.md`

## Session Classification
implementation-ready (all seams source-verified, all reds mutation-verified, host/widget-only closure)

---

## Exact Problem Statement

Seven user-reported issues on the shipped Orbit screen (`lib/features/orbit/`, default **inner-circle** view) + a cleanup:

1. **No close (X) on the find pill.** When the user opens the inner-circle find pill and searches, there is **no visible X** to return to the normal orbit + dismiss the keyboard (Signal-style). The pill closes **only** via an undiscoverable background tap (`_onBackgroundTap`, `inner_circle_interactive_surface.dart:318` → `_closeFindInternal:491`), which is nearly impossible to hit while the keyboard covers the bottom and the orbit fills the middle.
2. **Find pill too small + floats too far above the keyboard.** Expanded pill is `minHeight:48`, horizontal-only padding, `fontSize:15` (`:919-935`) and is anchored `bottom: bottomInset + (lifted?88:40) + _bandLift` (`:915`). `_bandLift` (persistent-nav clearance, `:237`) is added **unconditionally even when the keyboard is up** and covering that nav band → the pill floats ~40 + `_bandLift` (≈104px at a 92px clearance) above the keyboard. Inconsistent proportions.
3. **Search "lens" icon too faint.** The magnifier renders `colors.iconMuted` (`Color(0xAFC9CED6)` ≈ 69% alpha muted gray) on a near-black surface. **Four** `Icons.search` instances are faint: find-pill expanded (`inner_circle_interactive_surface.dart:927`), find-pill collapsed circle (`:961`), all-chats dock in-pill (`orbit_search_dock.dart:58`), no-results empty-state (`orbit_screen.dart:1102`). (The top-right trigger `orbit_search_trigger.dart:29` already uses `iconPrimary` — bright.)
4. **Orbit sits too high.** The 320×320 canvas ("orbit-viz-canvas") is **top-anchored**: the inner `Stack` (`inner_circle_interactive_surface.dart:552`) has **no `alignment`** (defaults `AlignmentDirectional.topStart`) and the enclosing `SingleChildScrollView` passes unbounded height, so `Center` (`:564`) shrink-wraps to 320 and the Stack top-pins it. The circle center lands ~160px below the safe-area top instead of the vertical middle.
5. **Double-tap name labels are pale.** Labels are Flutter `Text` (`orbital_visualization.dart:355`) styled `fontSize:9, color: readableColors.textMuted` (`:360`) = `Color(0xB8C9CED6)` ≈ 72% translucent gray, **no shadow, no scrim**, raw over the dark canvas → hard to read.
6. **Edit-mode "Reset" hidden behind the top-left icon.** Reset `Positioned(top:8,left:8)` (`inner_circle_interactive_surface.dart:664`, inside `SafeArea` ⇒ physical `safeTop+8`) shares the top-left band with the view-toggle `Positioned(top:padding.top+8,left:16)` 40×40 (`orbit_view_toggle_button.dart:38`). The toggle is a **higher-z screen sibling** (`orbit_screen.dart:402`, Layer 1b) **not gated on edit state**, so it paints over Reset and wins taps. The centered edit **banner** (`:633`, top:12) likewise collides with the top-center QR chrome (`orbit_qr_chrome_buttons.dart:33`).
7. **Delete Orbit2 + Orbit3 prototypes.** 25 dead debug-only lib files + their tests, plus 3 shipped inbound coupling sites and their l10n strings.

**What must improve:** find-pill closeability + sizing + lens contrast; label contrast; vertical centering; unobstructed edit chrome; removal of the two mock prototypes.

**What must stay unchanged (→ preserved-green sentinels):**
- The all-chats `OrbitSearchDock` close/clear behavior (already correct — out of scope).
- Plan 198 **swipe-yield contract**: entering edit still fires `onEditSessionActiveChanged(true)` up to `feed_wired` (`_orbitEditSessionActive`).
- Plan 198 handle-anchor geometry (reads live canvas origin — must survive re-center).
- Plans 193/196/201 chrome geometry when **not** editing (toggle/QR/find-pill insets in the idle state).
- `AppShellController` graceful fallback for an unknown persisted tab.

---

## Root Cause (verify → refute confirmed — HEAD 6dd9b617)

| # | Root cause (file:line) | Verdict |
|---|---|---|
| 1 | Expanded find pill Row is `[lens][TextField]` only — **no X**; sole close path is `_onBackgroundTap` (`inner_circle_interactive_surface.dart:318-324`). `_closeFindInternal` (`:491`) already does collapse+`clear()`+`unfocus()`. | SURVIVES — real gap; fix = additive X → `_closeFind` (`:500`) |
| 2 | `:915` `bottom: bottomInset + (lifted?88:40) + _bandLift`; `_bandLift` (`:237`) unconditional while keyboard up; `minHeight:48`/no vpad/`fontSize:15` (`:919-935`). | SURVIVES |
| 3 | `iconMuted 0xAFC9CED6` on near-black at `:927`, `:961`, `orbit_search_dock.dart:58`, `orbit_screen.dart:1102`. `iconPrimary = 0xFFF8FAFC`. | SURVIVES (refute upgraded 2→4 lenses) |
| 4 | `Stack(:552)` no `alignment` (topStart) + unbounded scroll height ⇒ `Center(:564)` shrink-wraps ⇒ top-anchored. Local center hardcoded 160 (`orbit_arc_layout.dart:22`). | SURVIVES |
| 5 | Label `TextStyle` `:360` = `textMuted 0xB8C9CED6`, no shadow/scrim. | SURVIVES |
| 6 | Toggle (Layer 1b `orbit_screen.dart:402`, higher z, not edit-gated) occludes Reset (`inner_circle_interactive_surface.dart:664`). Screen holds no `_editing` (Stateless `:188`). Edit-active signal **already plumbed** surface→screen `onInnerCircleEditSessionChanged` (`:570`)→wired→feed_wired. | SURVIVES |
| 7 | 3 shipped inbound coupling sites (`app_shell_tab.dart:7/9`, `feed_navigation_bar.dart:5/87-95`, `feed_wired.dart:82-83/2675-2690`); rest reachable only under `kOrbit3PrototypeEnabled = kDebugMode` (`orbit3_prototype.dart:16`). Orbit2 has **zero** shipped inbound refs (imported only by orbit3). | SURVIVES |

**Refuted / do-NOT-re-introduce:**
- ❌ "Item 1 already implemented" — TRUE only for the **all-chats `OrbitSearchDock`** (`orbit_search_dock.dart:86/111` → `_onSearchClose:1927`). The user's surface is the **inner-circle find pill**, which has no X. Do not "fix" the dock for item 1.
- ❌ "Only 2 search lenses exist" — there are **four** faint `iconMuted` lenses (refute correction). A single dock-only swap misses the pill the user sees.
- ❌ "Remove `orbital_avatar` `riseUp`/`entranceDelayMs`/`animateEntrance` as orbit3-dead" — they are **LIVE** (seeded `orbit_arc_layout.dart:346`, used `orbital_visualization.dart:220`). KEEP.
- ❌ "Delete `orbit3_prototype_source_guard_test.dart` is optional" — it `File`-reads the deleted file ⇒ `FileSystemException`; it **must** be deleted with orbit3.
- ❌ "Deletion risks the release build / a Move round-trip" — `kDebugMode`-gated, unreachable at release runtime; Move registry migrates the **shipped** `OrbitGeometryPrefs.storageKey`, not the orphan `orbit3_dimension_preferences_v1`.

---

## Real Scope

**In scope (shipped `lib/features/orbit/` + deletion):**
- Item 1: add a trailing **X** to the expanded find pill → `_closeFind` (collapse + keyboard dismiss). New l10n `orbit_find_close`.
- Item 2: enlarge the expanded find pill (`minHeight`≈56, vertical padding, `fontSize`≈16, icon 22) + anchor it just above the keyboard when the keyboard is up (drop the base gap to ~10 and zero `_bandLift`).
- Item 3: swap all **four** faint search lenses `iconMuted → iconPrimary`.
- Item 4: `Stack(alignment: Alignment.center, …)` at `:552` (pure safe-area center).
- Item 5: label `TextStyle` `textMuted → textPrimary` + drop shadow (+ `fontWeight w600`).
- Item 6: hide the view-toggle (Layer 1b) **and** QR chrome (Layer 1c) while the inner-circle surface is in edit mode; preserve the upward edit-active forward.
- Item 7: delete `lib/features/orbit2/` + `lib/features/orbit3/` (25 files) + their tests; edit the 3 coupling sites + `feed_navigation_bar_test.dart`; remove `orbit2_*`/`orbit3_*`/`nav_orbit3` l10n keys via ARB + `flutter gen-l10n`.

**Out of scope (owning work named):**
- All-chats `OrbitSearchDock` X/sizing (already correct; user chose "find pill only"). *Follow-up "orbit-search-dock-keyboard-gap" if desired.*
- Optical upward bias for item 4 (pure `Alignment.center` shipped; a `-0.08` bias is a tunable follow-up if it "feels low").
- Comment-only "Orbit2/Orbit3" mentions in shipped `orbital_avatar.dart`/`orbit_geometry_prefs*.dart` (cosmetic scrub, non-blocking).
- One-shot delete of the orphan `orbit3_dimension_preferences_v1` on-device key (harmless dead data; *follow-up "orbit3-key-cleanup"*).

---

## Files To Inspect Next
**Production (edit):**
- `lib/features/orbit/presentation/widgets/inner_circle_interactive_surface.dart` — items 1 (`:916-944`), 2 (`:915`,`:919-935`), 3 (`:927`,`:961`), 4 (`:552`).
- `lib/features/orbit/presentation/widgets/orbital_visualization.dart` — item 5 (`:360`).
- `lib/features/orbit/presentation/screens/orbit_screen.dart` — item 3 (`:1102`), item 6 (Stateless→Stateful `:188`; gate Layer 1b `:402` + Layer 1c `:414`; intercept `:570`).
- `lib/features/orbit/presentation/widgets/orbit_search_dock.dart` — item 3 (`:58`).
- `lib/features/feed/domain/models/app_shell_tab.dart`, `lib/features/feed/presentation/widgets/feed_navigation_bar.dart`, `lib/features/feed/presentation/screens/feed_wired.dart` — item 7 coupling.
- `lib/l10n/app_en.arb` / `app_de.arb` / `app_ar.arb` (+ `flutter gen-l10n`) — item 1 add `orbit_find_close`; item 7 remove `nav_orbit3` + 12 `orbit2_*` + 13 `orbit3_*`.

**Direct tests:** `test/features/orbit/presentation/widgets/orbital_arcs_test.dart` (item 5), `orbit_search_dock_test.dart` (item 3 dock), `test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart` (items 4/6 + churn re-baseline), `test/l10n/orbit_strings_parity_test.dart` (item 1 key, `newOrbitKeys` `:18`), `test/features/feed/presentation/widgets/feed_navigation_bar_test.dart` (item 7).
**New tests:** `orbit_find_pill_ux_test.dart` (items 1/2/3), `orbit_prototypes_removed_guard_test.dart` (item 7).

## Existing Tests Covering This Area
- `orbital_arcs_test.dart::TC-198-53` — label **presence** only (no color lock) → item 5 fix unblocked (exists).
- `orbit_sculpt_summon_wired_test.dart` — TC-198F-01..25 handle anchors (read **live** canvas origin → survive re-center); **TC-198F-04** 340px band (`:743-771`, **CHURNS** on re-center → re-baseline); TC-201-03 find-pill inset `closeTo(16,2)`+height`>=48` (`:1714-1718`, survives: still 16, 56≥48); TC-198F-17/18 bottom-band re-flow (`:1155`,`:1193`, **may churn** on pill resize/anchor). Reset key `orbit-edit-reset` (`:247/:329/:426/:671/:1365`).
- `orbit_view_split_test.dart` — view-toggle geometry + RTL locks (`:414-482`) — **not** edit-mode → item 6 (hide only while editing) does not churn these.
- `orbit_search_dock_test.dart` — dock icon/TextField presence, no geometry (survives).
- `orbit3_prototype_source_guard_test.dart`, `test/features/orbit3/**` (11 `_test`), `test/features/orbit2/orbit2_models_test.dart` — **DELETE** (item 7).
- `feed_navigation_bar_test.dart` — imports `orbit3_prototype.dart`, asserts `2 + (kOrbit3?1:0)` tabs — **EDIT** to flat 2 (item 7).

**Missing coverage gaps:** find-pill close affordance; find-pill keyboard anchoring; lens contrast; label contrast; canvas vertical center; edit-mode chrome suppression; prototype-removal guard.
**Already in curated arrays?** `orbit_sculpt_summon_wired_test.dart` (GROUP_TESTS `:254`), `orbit_strings_parity_test.dart` (GROUP_TESTS `:255`). All other `test/features/orbit/**` reach a runner via the `feature-host-all` glob only.

---

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

1. **`test/features/orbit/presentation/widgets/orbit_find_pill_ux_test.dart`::TC-205-01 find pill exposes a close X that collapses + dismisses keyboard**
   - Tier: widget. Setup: pump `InnerCircleInteractiveSurface` (13 friends) inside `MaterialApp` w/ `BackgroundReadableColors.dark` + l10n; tap `ValueKey('orbit-find-pill')` to open; enter text; `find.byKey(ValueKey('orbit-find-close'))`.
   - RED on HEAD because: no such key exists (pill Row is `[lens][TextField]`, `:925-944`) → `findsNothing`.
   - GREEN asserts: `findsOneWidget`; tapping it → `find.byKey(ValueKey('orbit-find-pill'))` reverts to the 44px collapsed circle **and** the `TextField` is gone (keyboard-dismiss proxy: `EditableText`/focused field no longer present, or `find.byType(TextField)` findsNothing).
   - Mutation that re-reds: remove the X `GestureDetector` from the Row → red.
   - Discriminator: assert collapse via `orbit-find-pill` circle reappearing **AND** `TextField` absent (distinguishes "cleared but still open" from "closed").

2. **…::TC-205-02 find pill sits just above the keyboard (no unconditional band lift)**
   - Tier: widget. Setup: pump surface inside `MediaQuery(viewInsets: EdgeInsets.only(bottom:300))` + `bottomClearance: 92`; open pill.
   - RED on HEAD: `gap = (screenH - 300) - tester.getRect(orbit-find-pill).bottom == 40 + max(0,92-28)=104` → `expect(gap, lessThanOrEqualTo(12))` fails.
   - GREEN asserts: `gap <= 12`.
   - Mutation: revert the `:915` anchor change → gap 104 → red.

3. **…::TC-205-03 expanded find pill is comfortably sized**
   - Tier: widget. RED on HEAD: `tester.getSize(orbit-find-pill).height == 48` → `expect(height, greaterThanOrEqualTo(56))` fails.
   - GREEN: height ≥ 56; TextField `style.fontSize == 16`.
   - Mutation: revert `minHeight`/`fontSize` → red.

4. **…::TC-205-04 all faint search lenses use iconPrimary**
   - Tier: widget. Setup: pump surface (find pill collapsed + expanded) + `OrbitSearchDock` + no-results state.
   - RED on HEAD: the expanded-pill lens `Icon.color == iconMuted (0xAFC9CED6)` → `expect(color, BackgroundReadableColors.dark.iconPrimary)` fails.
   - GREEN: all four lenses (`:927`,`:961`,`orbit_search_dock.dart:58`,`orbit_screen.dart:1102`) `== iconPrimary (0xFFF8FAFC)`.
   - Mutation: revert any one swap → that assertion reds.

5. **`orbit_sculpt_summon_wired_test.dart`::TC-205-05 orbit canvas is vertically centered**
   - Tier: widget (wired). Setup: pump `OrbitScreen` inner-circle in a tall viewport (e.g. 400×900); `origin = canvasOrigin(tester)` (`getTopLeft('orbit-viz-canvas')`); `centerY = origin.dy + 160`; `mid = surfaceRect.center.dy`.
   - RED on HEAD: top-anchored → `centerY ≈ safeTop+160`, far above `mid` → `expect((centerY - mid).abs(), lessThan(40))` fails.
   - GREEN: within 40px of mid.
   - Mutation: revert `Stack(alignment: Alignment.center)` → red.

6. **`orbit_sculpt_summon_wired_test.dart`::TC-205-06 entering edit hides toggle + QR chrome, Reset unobstructed**
   - Tier: widget (wired). Setup: pump `OrbitScreen` inner-circle with `onToggleView` + `onMyQR`/`onScanQR` wired; long-press empty space → edit.
   - RED on HEAD: `find.byKey(ValueKey('orbit-view-toggle'))` **findsOneWidget** and QR chrome present during edit → `expect(findsNothing)` fails; also `rReset.overlaps(rToggle)` true.
   - GREEN: toggle + QR `findsNothing` while `_editing`; Reset (`orbit-slot-edit-reset`) hit-test reaches `_reset` (tap at Reset center invokes reset).
   - Mutation: revert the `!editing` gate on Layer 1b/1c → toggle present → red.

7. **`orbit_sculpt_summon_wired_test.dart`::TC-205-07 edit-active still forwarded upward (198 swipe-yield preserved)**
   - Tier: widget (wired). Setup: pump `OrbitWired` with `onEditSessionActiveChanged` spy; enter edit.
   - RED on HEAD: N/A as a fix-red — this is the **preservation** guard for item 6's Stateless→Stateful refactor. It must stay GREEN; it goes RED **only if** the refactor drops the forward (i.e. it re-reds when the intercept forgets to call `widget.onInnerCircleEditSessionChanged`).
   - GREEN asserts: spy received `true` on enter, `false` on exit.
   - Mutation: in the new intercept, drop the `widget.onInnerCircleEditSessionChanged?.call(active)` line → red (proves the intercept preserves the contract).

8. **`orbital_arcs_test.dart`::TC-205-08 double-tap labels are high-contrast**
   - Tier: widget. Setup: `expandable(_friends(13), labelsVisible: true)`; read the label `Text` style.
   - RED on HEAD: `style.color == textMuted (0xB8C9CED6)` and `style.shadows == null` → `expect(color, textPrimary)` + `expect(shadows, isNotEmpty)` fail.
   - GREEN: `color == textPrimary`, `shadows` non-empty.
   - Mutation: revert `:360` → red.

9. **`test/features/orbit/presentation/orbit_prototypes_removed_guard_test.dart`::TC-205-09 prototypes removed**
   - Tier: host (dart:io). RED on HEAD: `Directory('lib/features/orbit3').existsSync()` true, `AppShellTab.values` contains `'orbit3'`, nav-bar source contains `'orbit3'`.
   - GREEN: `orbit2`+`orbit3` dirs gone; `AppShellTab.values == {'feed','orbit'}`; `File('…/feed_navigation_bar.dart').readAsStringSync()` `isNot(contains('orbit3'))`.
   - Mutation: restore any deleted dir / the `orbit3` const → red.

10. **`feed_navigation_bar_test.dart`::TC-205-10 nav bar shows exactly 2 tabs, no Orbit3/Orbit2**
    - Tier: widget. RED on HEAD: `expectedButtons = 2 + (kOrbit3PrototypeEnabled?1:0)` = 3 under debug; `find.text('Orbit3')` findsOneWidget.
    - GREEN (after edit): flat `2`; `find.text('Orbit3')` + `find.text('Orbit2')` findsNothing.
    - Mutation: re-add the gated NavBarButton block → red.

11. **`orbit_strings_parity_test.dart`::TC-205-11 l10n: orbit_find_close added, orbit2/3 keys removed, parity holds**
    - Tier: host (l10n parity). RED on HEAD: `orbit_find_close` absent from `newOrbitKeys` + ARBs (getter doesn't exist → compile/RED); after item 7, any orbit2/3 key left in only one locale breaks parity.
    - GREEN: `orbit_find_close` present in en/ar/de + `newOrbitKeys`; **no** `orbit2_*`/`orbit3_*`/`nav_orbit3` keys remain in any ARB; en/de/ar key-set parity holds.
    - Mutation: remove `orbit_find_close` from one ARB → parity red.

12. **`orbit_prototypes_removed_guard_test.dart`::TC-205-12 AppShellController degrades a stale 'orbit3' tab to feed**
    - Tier: host (unit). RED on HEAD: with `orbit3` still in `values`, `AppShellController(initialTab:'orbit3').activeTab == 'orbit3'` → `expect(activeTab, 'feed')` fails.
    - GREEN: after removing `orbit3` from `values`, `isValid('orbit3')` false → `activeTab == feed`.
    - Mutation: leave `orbit3` in `values` → red.

---

## Test Coverage Matrix  (zero empty cells in tier / mutation / gate / registration)

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| #1 find X | widget gesture + focus | widget | `orbit_find_pill_ux_test.dart::TC-205-01` | no `orbit-find-close` key | remove X widget | `run_host_test_gates.sh feature-host-all` | AUTO (glob) |
| #1 l10n key | string parity | host | `orbit_strings_parity_test.dart::TC-205-11` | getter/key absent | drop key one locale | `flutter test test/l10n/orbit_strings_parity_test.dart` | **already GROUP_TESTS `:255`**; append to `newOrbitKeys` `:18` |
| #2 anchor | layout vs viewInsets | widget | `orbit_find_pill_ux_test.dart::TC-205-02` | gap=104>12 | revert `:915` | `run_host_test_gates.sh feature-host-all` | AUTO (glob) |
| #2 size | layout metrics | widget | `orbit_find_pill_ux_test.dart::TC-205-03` | height=48<56 | revert `:919/:934` | ″ | AUTO (glob) |
| #3 lens | icon color token | widget | `orbit_find_pill_ux_test.dart::TC-205-04` | `iconMuted` | revert a swap | ″ | AUTO (glob) |
| #4 center | Stack alignment | widget/wired | `orbit_sculpt_summon_wired_test.dart::TC-205-05` | top-anchored | revert `:552` | `run_test_gates.sh groups` | **GROUP_TESTS `:254`** (existing pin) |
| #4 churn | band re-baseline | widget/wired | `orbit_sculpt_summon_wired_test.dart::TC-198F-04` (re-baseline) | band assumes top-anchor | n/a (re-baseline) | ″ | GROUP_TESTS `:254` |
| #5 label | text style | widget | `orbital_arcs_test.dart::TC-205-08` | `textMuted`+null shadow | revert `:360` | `run_host_test_gates.sh feature-host-all` | AUTO (glob) |
| #6 hide chrome | screen state gate | widget/wired | `orbit_sculpt_summon_wired_test.dart::TC-205-06` | toggle/QR present in edit | revert `!editing` gate | `run_test_gates.sh groups` | GROUP_TESTS `:254` |
| #6 preserve 198 | callback contract | widget/wired | `orbit_sculpt_summon_wired_test.dart::TC-205-07` | (preservation) reds if forward dropped | drop forward in intercept | ″ | GROUP_TESTS `:254` |
| #7 removal | fs + enum guard | host | `orbit_prototypes_removed_guard_test.dart::TC-205-09` | dirs/const exist | restore dir/const | `run_host_test_gates.sh feature-host-all` | AUTO (glob) |
| #7 nav bar | widget tab count | widget | `feed_navigation_bar_test.dart::TC-205-10` | 3 tabs / Orbit3 shown | re-add gated block | ″ | AUTO (glob) |
| #7 l10n purge | parity | host | `orbit_strings_parity_test.dart::TC-205-11` + `l10n_integrity_test.dart` | orbit2/3 keys asymmetric | leave key one locale | `flutter test test/l10n/l10n_integrity_test.dart` | l10n direct-suite (`run_test_gates.sh:665`); parity **GROUP_TESTS `:255`** |
| #7 degrade | controller fallback | unit | `orbit_prototypes_removed_guard_test.dart::TC-205-12` | orbit3 valid | keep orbit3 in `values` | `run_host_test_gates.sh feature-host-all` | AUTO (glob) |

---

## Blind-Spot Sweep  (evergreen classes — row or justified N/A)
- **Lifecycle / derived-state durability:** Item 6 adds `OrbitScreen._innerEditing` (in-memory, derived from the surface signal). It is **transient by design** — every fresh mount starts idle; entering edit is user-driven, not restored. TC-205-06 asserts reconstruction from the signal each session. **N/A for persistence** (no reopen requirement; the edit session is never persisted). Item 2 anchor reads live `viewInsets` each build (no derived latch). ✔ covered / justified.
- **Sibling-surface consistency:** Item 3 lens fix must hit **all four** faint lenses (find-pill ×2, dock, no-results) — TC-205-04 enumerates them; asymmetry (fix one, miss three) is the exact refute finding. Item 6 chrome-hide applies to **both** Layer 1b (toggle) **and** Layer 1c (QR) — TC-205-06 asserts both gone. ✔
- **Destructive-action side-effects:** Item 7 — TC-205-09 asserts **what is removed** (both dirs, the `orbit3` enum member, source refs), TC-205-11 asserts the **l10n keys are gone across all locales**, TC-205-10 asserts the **nav tab is gone**. KEEP-list (`orbital_avatar` live params) protected by the existing `feature-host-all` suite still compiling+passing. ✔
- **Invariant re-verification under new transitions:** Item 6 adds the edit→idle transition at the **screen** level (not just the surface). TC-205-06 asserts the FULL post-enter state (toggle absent, QR absent, Reset reachable); a **new** guard TC-205-07 asserts the edit→idle exit **still forwards** the 198 signal both directions (the invariant the pre-existing swipe-yield relied on). ✔

---

## Invariants (locked by tests)
- **INV-1** Find pill has a discoverable close that collapses **and** dismisses the keyboard → TC-205-01.
- **INV-2** Find pill anchors within ~12px of the keyboard top when the keyboard is up → TC-205-02.
- **INV-3** No orbit search lens renders `iconMuted` → TC-205-04.
- **INV-4** Orbit canvas center is within ~40px of the surface vertical midpoint → TC-205-05.
- **INV-5** Double-tap labels render `textPrimary` with a shadow → TC-205-08.
- **INV-6** While the inner-circle surface is editing, the view-toggle and QR chrome are unmounted → TC-205-06.
- **INV-7 (preservation)** Entering/leaving edit still forwards `onEditSessionActiveChanged` to the host (198 swipe-yield) → TC-205-07.
- **INV-8** `AppShellTab.values == {feed, orbit}`; no orbit2/orbit3 source, tests, or l10n keys remain → TC-205-09/10/11/12.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row.

---

## Step-By-Step Implementation Plan
1. **RED first.** Add TC-205-01..12 (new files + edits). Run the focused commands (Acceptance Gates §RED); confirm each fails for its documented reason. Re-baseline **TC-198F-04** to the centered canvas (or convert to a live-origin relative assertion) — this is expected churn, not a fix.
2. **Item 1 (find X):** in `inner_circle_interactive_surface.dart` expanded pill Row (`:925-944`) append, after the `Expanded(TextField)`, a `GestureDetector(key: ValueKey('orbit-find-close'), behavior: opaque, onTap: _closeFind, child: Semantics(button:true, label: l10n.orbit_find_close, child: Icon(Icons.close, size:20, color: colors.iconPrimary)))`. Add `orbit_find_close` to en/ar/de ARB + `newOrbitKeys`; `flutter gen-l10n`.
3. **Item 2 (anchor+size):** `:915` → `final kbUp = bottomInset > 0; bottom: bottomInset + (lifted ? 88.0 : (kbUp ? 10.0 : 40.0)) + (kbUp ? 0.0 : _bandLift)`. `:919-920` → `constraints: BoxConstraints(minHeight: 56)`, `padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12)`. `:934` fontSize 15→16.
4. **Item 3 (lens):** swap `colors.iconMuted → colors.iconPrimary` at `inner_circle_interactive_surface.dart:927` & `:961`, `orbit_search_dock.dart:58`, `orbit_screen.dart:1102`. (Item 2 already bumped `:927` icon size to 22.)
5. **Item 4 (center):** `inner_circle_interactive_surface.dart:552` `Stack(` → `Stack(alignment: Alignment.center,`. **Stop-if:** arch-overflow expansion no longer scrolls (content > viewport) → verify the `SingleChildScrollView` still scrolls with the centered Stack before proceeding.
6. **Item 5 (label):** `orbital_visualization.dart:360` `color: readableColors.textMuted` → `readableColors.textPrimary`, add `fontWeight: FontWeight.w600`, `shadows: const [Shadow(blurRadius: 3, color: Color(0xCC000000))]`.
7. **Item 6 (hide chrome):** convert `OrbitScreen` (`:188`) StatelessWidget → StatefulWidget (move ctor fields to `widget.`). Add `bool _innerEditing = false` + `void _onInnerEdit(bool a){ setState(() => _innerEditing = a); widget.onInnerCircleEditSessionChanged?.call(a); }`. Wire the surface's `onEditSessionActiveChanged: _onInnerEdit` (`:570`). Gate Layer 1b (`:402`) `if (onToggleView != null && !_innerEditing)` and Layer 1c (`:414`) `if (!_innerEditing) OrbitQrChromeButtons(...)`. **Stop-if:** any non-edit test loses the toggle/QR → the gate leaked; the gate must be edit-only.
8. **Item 7 (delete):** delete `lib/features/orbit2/` + `lib/features/orbit3/`; edit `app_shell_tab.dart` (`:5-7` const, `:9` values), `feed_navigation_bar.dart` (`:5` import, `:87-95` block), `feed_wired.dart` (`:82-83` imports, `:2675-2690` mount); delete `test/features/orbit3/**` + `test/features/orbit2/orbit2_models_test.dart` + `orbit3_prototype_source_guard_test.dart`; edit `feed_navigation_bar_test.dart` (drop import, `expectedButtons=2`, Orbit3 findsNothing, keep Orbit2 findsNothing); remove `nav_orbit3`+`orbit2_*`+`orbit3_*` from the 3 ARBs; `flutter gen-l10n`.
9. Rerun **direct → preservation → named gates** (§Acceptance Gates). `flutter analyze` (0 new), `git diff --check`.

---

## Risks And Edge Cases
- **Item 4 × arch overflow:** centering a >viewport-tall canvas inside the scroll view — pinned by TC-205-05 (short-population center) + manual verification that overflow-expanded still scrolls. → Stop-if in step 5.
- **Item 6 refactor churn:** Stateless→Stateful on the central projection screen; the ~4 bare-`OrbitScreen` pump sites keep the same constructor (no break) but confirm they still compile. `orbit_sculpt_summon_wired_test.dart` may have an incidental "toggle present during edit" assertion → audit + adjust in-slice.
- **Item 2 churn:** TC-198F-17/18 bottom-band re-flow rects move with the taller/anchored pill → re-baseline if red (expected). TC-201-03/04 insets (16) + height(≥48) survive (56≥48).
- **Item 7 l10n atomicity:** a key removed from only one ARB fails `l10n_integrity` parity → remove from all three together, then `gen-l10n`. → pinned by TC-205-11.

## Device/Relay Proof Profile
**host-only for closure.** No OS-boundary / crypto / relay / multi-device seam — every change is pure Flutter UI/layout/state + dead-code deletion. No `DB v##`, no migration, no simulator/device row.
- Recommended (non-gating) visual check: one iOS-sim screenshot of the inner-circle view confirming the re-centered orbit + brighter lens + readable labels + find-pill-on-keyboard + edit-mode chrome hidden. (Optional `/run` or `verify` skill; not a closure gate.)

## Acceptance Gates  (literal — copy/paste, with expected counts)
```bash
# RED (before production edits) — must FAIL for the documented reason
flutter test test/features/orbit/presentation/widgets/orbit_find_pill_ux_test.dart
flutter test test/features/orbit/presentation/screens/orbit_sculpt_summon_wired_test.dart --plain-name 'TC-205'
flutter test test/features/orbit/presentation/widgets/orbital_arcs_test.dart --plain-name 'TC-205-08'
flutter test test/features/orbit/presentation/orbit_prototypes_removed_guard_test.dart
flutter test test/l10n/orbit_strings_parity_test.dart --plain-name 'TC-205-11'

# Direct GREEN (after fix)
flutter test test/features/orbit/presentation/widgets/orbit_find_pill_ux_test.dart
flutter test test/features/orbit/presentation/orbit_prototypes_removed_guard_test.dart

# Preservation sentinels + named gate (orbit cluster + l10n)
./scripts/run_test_gates.sh groups            # orbit_sculpt_summon_wired + orbit_strings_parity + view_split + unread + qr  (expect: all pass; re-baseline TC-198F-04)
./scripts/run_test_gates.sh feed              # feed_navigation_bar_test 2-tab expectation
flutter test test/l10n/l10n_integrity_test.dart          # en/de/ar parity after orbit2/3 key purge
flutter test test/l10n/orbit_strings_parity_test.dart    # orbit_find_close present; orbit2/3 absent

# Whole host feature suite (auto-globs the new widget/guard tests; confirms nothing else red)
./scripts/run_host_test_gates.sh feature-host-all

# Hygiene
flutter analyze            # 0 new issues
git diff --check
```

## Known-Failure Interpretation
- **Expected RED:** TC-205-01..06, 08..12 before their fixes; TC-198F-04 pre-re-baseline.
- **Pre-existing dirty:** `l10n_integrity` literal-scan RED from **prior orbit3 debt** (recorded in plan 203) — deleting orbit3 should *clear* that specific debt; if any unrelated pre-existing literal-scan red remains, it is not this plan's regression. Snapshot `git status --short` first.
- **Environment blocker (NOT product):** none (no sim/device).
- **Scope drift (BLOCKING):** any red outside `lib/features/orbit/**`, the 3 feed coupling files, `lib/l10n/**`, or the enumerated tests.

## Done Criteria
- [ ] RED added first, failed for the expected reason.
- [ ] Mutation-verified (each fix has a re-red revert; TC-205-07 re-reds if the 198 forward is dropped).
- [ ] Direct GREEN + preservation sentinels + `groups`/`feed`/`feature-host-all` + l10n suites pass.
- [ ] No DB migration (N/A); no device-proof (N/A — host-only).
- [ ] Every new test's registration verified: `orbit_find_pill_ux_test.dart` + `orbit_prototypes_removed_guard_test.dart` show under `feature-host-all`; `orbit_find_close` appended to `newOrbitKeys`.
- [ ] `flutter analyze` 0 new; `git diff --check` clean; no Scope Guard violations.

## Scope Guard (hard "Do not")
- Do **not** touch the all-chats `OrbitSearchDock` close/clear **logic** (item 1 is find-pill only; a lens color swap at `:58` is the sole permitted dock edit).
- Do **not** remove `orbital_avatar` `riseUp`/`entranceDelayMs`/`animateEntrance` (LIVE).
- Do **not** flip `kOrbit3PrototypeEnabled` or add any new prototype — delete outright.
- Do **not** persist the edit session or add an optical center bias (both are named follow-ups).
- Do **not** hide the toggle/QR outside edit mode (would churn 193/196 geometry locks).

## Accepted Differences / Intentionally Out Of Scope
- All-chats `OrbitSearchDock` keyboard-gap/X-sizing — *follow-up "orbit-search-dock-keyboard-gap"*.
- Item-4 optical upward bias — *tunable follow-up*.
- Orphan on-device `orbit3_dimension_preferences_v1` key — *follow-up "orbit3-key-cleanup"*.
- Comment-only Orbit2/3 mentions in shipped files — cosmetic, non-blocking.

## Dependency Impact
- None downstream. Item 7 removes debug-only surfaces; `feed_wired`/`feed_navigation_bar`/`app_shell_tab` compile identically in release (kDebugMode-gated code was already release-inert).

## Reviewer Findings
_(pending sufficiency review)_

## Arbiter Decision
_(pending)_

## Final Execution Verdict
_(pending execution)_
