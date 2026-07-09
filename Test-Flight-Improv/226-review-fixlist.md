# 226 Review — Findings + Fix-List (apply against `226-settings-navbar-orbit-glass-swipe-back-tdd-plan.md`)

Source: 7-agent source-grounded audit (1 domain-risk verifier + 5 dimension assessors + 1 evergreen critic, workflow `wf_a05c3362-ab0`) **plus** orchestrator self-verification of every load-bearing `file:line` against real source. Date: 2026-07-09.

## Verdict

**READY-WITH-TIGHTENING.** Core technical bet **verified sound**; fix **2 material** + **~5 moderate** plan defects (all cheap, no re-plan, no new device work) before execution. Critic verdict: **yes-with-tightening**.

| Your criterion              | Dimension              | Score | Verdict  |
|-----------------------------|------------------------|-------|----------|
| (1) Goal / decisions        | Goal clarity           |  88   | strong   |
| (2) Agile / checkpoints     | Compartmentalization   |  88   | strong   |
| (3) Precise / no-drift      | Anti-drift             |  74   | adequate |
| (4) Eval criteria up front  | Define "good"          |  85   | strong   |
| (5) Tests verify the goal   | Goal-verification      |  78   | adequate |

The two "adequate" dimensions are each capped by one material gap (D3 → the `:702` mislabel; D5 → the vacuous discriminator). Both are cheap edits.

## Is the core bet sound? — YES

The plan's #1 technical bet is: *a `GestureDetector` with `onHorizontalDrag*` wrapping the Settings body reliably qualifies a net-rightward swipe (accumulated `delta.dx` + `DragEndDetails.primaryVelocity`), coexists with the vertical `SingleChildScrollView`, doesn't steal taps, and has a sound raw-`Listener` fallback.*

Domain-risk verifier returned **`material_errors: []`** — all 5 sub-claims **confirmed**:
- A `HorizontalDragGestureRecognizer` and the `Scrollable`'s `VerticalDragGestureRecognizer` disambiguate cleanly by initial drag axis — the canonical horizontal-inside-vertical pattern, **already shipped in this repo** at `swipeable_friend_row.dart:235-240`. The known "GestureDetector loses events under a ScrollView" issue (flutter/flutter#72996) is a *same-axis* case, not this orthogonal one. A stationary tap never crosses `kTouchSlop`, so taps are not stolen.
- For a single-axis recognizer `DragUpdateDetails.delta == Offset(primaryDelta, 0)`, so accumulating `delta.dx` == net horizontal travel; `DragEndDetails.primaryVelocity` is non-null with **positive == rightward**. The plan's qualifier sign is correct and mirrors `feed_wired.dart:2461-2474`.
- The raw-`Listener` fallback (`feed_wired.dart:2376-2494`) is a sound *pattern* transplant (not a literal drop-in): a passive `Listener` never joins the arena, but that is exactly why it **requires** the manual axis guard `dx.abs() <= dy.abs() → return` (`:2403`) — which is part of the referenced code. Dropping feed_wired's interactive controller tracking for a route-pop is a strict, safe simplification.
- `tester.fling`/`tester.timedDrag` (TC-226-08/09/14) reproduce real swipes through the recognizer.
- **Zero** competing horizontal recognizers on the Settings surface (grep clean).

## Material blockers (ranked, each with `file:line` proof + fix)

### M1 — The tab-switch discriminator (TC-226-07/08) is **vacuous** → INV-3 is not actually locked
The plan claims (plan line 125) TC-226-08 "asserts BOTH pop AND tab-switch (distinguishes the new path from a bare `_onBack` pop)." It does not. `app_shell_controller.dart:27` defaults `initialTab` to `orbit` and `switchTo` (`:42`) **no-ops when already-orbit**. File C's harness is specified only as "real AppShellController" (plan line 117) with no non-orbit seed, so "active tab == orbit" is satisfied **on entry** — a handler doing only `Navigator.pop()` (dropping `switchTo`) passes TC-226-07/08 **identically** to `switchTo('orbit')+pop`. Nothing guards the `switchTo` half; INV-3 (plan line 182) is illusory, and the claim at line 125 is false.
**Fix (see A1).** Seed File C's `AppShellController(initialTab: AppShellTab.feed)`, assert the tab **transitioned feed→orbit**, and add the matrix mutation `replace _onSwitchView("orbit") with bare Navigator.pop() → tab stays feed → RED`.

### M2 — False "nested `SettingsWired` at `:702`" claim → no wrong-route-pop guard for Settings sub-flows
Plan lines 175 and 202 both assert "the nested Settings push (`settings_wired.dart:702`) mounts the same `SettingsWired` and thus inherits the swipe — consistent by construction." **Verified false:** `settings_wired.dart:700-717` pushes `AccountMigrationJourneyWired.oldPhone` (Move-Account), **not** a `SettingsWired`. There is **no** nested Settings — only two `SettingsWired(` sites exist (`orbit_wired.dart:660` nav-bar, `posts_wired.dart:540` `showNavigationBar:false`). Because `_onSwitchView` calls `Navigator.of(context).pop()` (`settings_wired.dart:534`), a body-level pop-gesture leaking while a Settings **sub-flow** is up — Move-Account (`:700`), `_showSettingsSheet` modal sheets (`:553-557`), `_runQrEntry` QR (`:539`) — would pop the **wrong route**. Occlusion (opaque route / `ModalBarrier`) probably makes it benign, but the plan's justification is false, the safety is **accidental not designed**, there is no Stop-if, and `settings_swipe_back_test.dart` (TC-226-07..15) has **zero** case with a sub-route/sheet mounted.
**Fix (see B1/B2/B3).** Delete the false claim; enumerate the real sub-surfaces; add **one** guard test (sub-route/sheet up + rightward fling → `SettingsWired` NOT popped; mutation: move the `GestureDetector` above the barrier → red); add a step-6 Stop-if.

## Moderate tightenings

### T1 — TC-226-15 idempotency mutation is self-contradictory (D3)
Plan line 62 says fire "on drag **END** … exactly once per gesture (latch reset on drag start)", but TC-226-15's mutation (line 145) is "remove the per-gesture latch / fire on every drag-update." `onHorizontalDragEnd` fires **exactly once** per recognized gesture — an end-firing design has **no latch to remove**, so the named mutation cannot re-red it; the non-vacuity proof is invalid. (Conversely the mutation only bites an *update*-firing design, which the prose did not choose.)
**Fix (see C1).** Commit to end-firing: drop "per-gesture latch" at line 62; rewrite the TC-226-15 mutation to `call _onSwitchView in onHorizontalDragUpdate whenever accumulated dx crosses threshold (fires N times) → NavigatorObserver counts >1 pop → red`.

### T2 — TC-226-04 has no mutation for the shadow-**OUTSIDE**-ClipOval invariant (D5)
The plan's own root cause stresses "a clipped shadow is invisible" (line 60), but TC-226-04's mutation column (lines 109/159) only covers `remove BackdropFilter / solid fill` — nothing re-reds a regression that moves the `BoxShadow` **inside** the ClipOval.
**Fix (see C2).** Assert `boxShadow` on the specifically-outer (unclipped) `Container` ancestor of the `ClipOval` (mirror `orbit_search_trigger_test.dart:33-41` `.first`), and add the mutation `move BoxShadow onto the inner clipped Container → outer boxShadow empty → RED`.

### T3 — Two INV-5 preservation sentinels + the 206-enter test are bound to **no** literal gate command (D4/B-9)
Plan line 175 names `intro_notification_orbit_route_test.dart` and `dark_preset_preservation_test.dart` as the sentinels proving "shared defaults unchanged," and line 44 names TC-206-01. **Verified:** both files live outside `test/features/settings/` (in `test/features/push/` and `test/features/theme/`) and are in **no** `GROUP_TESTS`/`FEED_TESTS` array, so no command in the Acceptance Gates block (lines 227-240) runs them. (They *do* reference the shared navbar, so they would catch a leak — they just aren't invoked.)
**Fix (see D1).** Append both files (+ the 206-enter test) to a literal preservation `flutter test` line, or cite an explicit `feature-host-all` run in the gate block.

### T4 — Matrix RED-reason cells say "compile RED / file absent" but the design is stub-first (D4)
Lines 159-161 give the File-A RED reason as "new-widget: file absent (compile RED)", contradicting step 2 (line 189), which creates the `SettingsOrbitNavButton` stub **first** — the file is present when the RED gate runs. The true RED is behavioral "red vs stub" (catalog lines 106-114; gate note line 217).
**Fix (see D2).** Replace the three cells with the behavioral reasons (stub renders a bare box → recipe/tone/Semantics assertions fail).

### T5 — TC-226-16's reopen/latch leg is not independently mutation-verified (D4)
The PROD-CRITICAL reopen assertion (catalog line 150, "center-avatar tap reopens Settings … proves `_settingsRouteActive` released via `whenComplete`") shares TC-226-08's mutation (`remove GestureDetector`, matrix line 171), which reds it via the **first** leg (fling doesn't pop). Nothing proves the reopen assertion itself is non-vacuous.
**Fix (see D3).** Add a dedicated reopen-leg mutation (e.g. force `_settingsRouteActive` to stay true, confirm the reopen assertion reds independently), **or** explicitly document the reopen leg as preservation of untouched `orbit_wired.dart:682-684`.

## Nits

- **N1** — Test named `'renders FeedNavigationBar'` at `settings_screen_test.dart:147` is not addressed; step 5 updates only the `byType` targets at `:150/:246/:307`. Rename the `:147` test when swapping its target.
- **N2** — `orbit_settings_entry_test.dart` direct-GREEN expectation (line 225) is "all pass" with no numeric floor; the three new files pin exact counts. Inventory the file's case count `N` and pin to `N+1`.
- **N3** — TC-226-06 is listed as fully RED-on-HEAD (line 244), but the stub "wires onTap only" (line 189), so only the Semantics-label half reds at HEAD. Note this in catalog A3.
- **N4** (from domain verifier) — Plan says "wrap the Scaffold body in `settings_wired.dart`" (line 62), but the Scaffold + navbar `Positioned` actually live in `settings_screen.dart:297-308`; the `settings_wired.dart:778` Scaffold body **is** `SettingsScreen`. Clarify the wrap point (wrapping `SettingsScreen` inside the wired Scaffold is fine — arena semantics hold either way).
- **N5** (test-authoring) — TC-226-09 slow-drag must exceed `0.28 × viewport` (**224px** on the default 800-wide test viewport) at low velocity, and the `0.28w` arm must read `MediaQuery` width at drag-end (feed_wired uses `_hostViewportWidth`).
- **N6** (defensive, currently CLEAR) — A tap-through sentinel ("tap a Settings control after the wrap → its callback still fires") and a fling-start-point note (TC-226-08 flings from `SettingsScreen` center; prefer `flingFrom` on known-inert chrome to avoid environment fragility) would be cheap insurance. The horizontal-sub-widget arena concern is **empirically clear** (grep found zero horizontal-drag controls in Settings).

## Evergreen blind-spot sweep

| Class | Hit? | Evidence | Fix |
|---|---|---|---|
| B-1 rollback/downgrade brick | **N-A** | Pure-Flutter UI; no persisted data / on-disk format / schema bump (plan:207,254). | — |
| B-2 undercounted sibling sites | **HIT** | `SettingsWired` sites correctly counted (2), but plan:175/202 assert a nonexistent 3rd (`:702` = Move-Account). Real sub-surfaces (Move/sheets/QR) unenumerated + untested. | M2 |
| B-3 off-target line numbers | **HIT** | Isolated to `:702` (cited twice). **All other** anchors confirmed correct against source. | M2 |
| B-4 un-verifiable goal gate | **clear** | UI wins host-verifiable (TC-226-01/04/05/08/16); the only host-unjudgeable item (BackdropFilter look) is a non-gating manual screenshot (plan:196,208,255). | — |
| B-5 migration atomicity | **N-A** | No migration; only a per-gesture drag accumulator reset on drag start. | — |
| B-6 durable-marker survival | **N-A** | `showNavigationBar` is a runtime constructor param (default true), not a persisted flag. | — |
| B-7 #1 risk domain-verified | **clear** | Gesture-arena risk pinned by TC-226-12 + real named fallback; domain verifier confirmed sound. *Caveat:* plan **mis-ranks** risks — the wrong-route pop (M2) is higher-consequence than the stated #1 and has no Stop-if. | M2 (Stop-if) |
| B-8 PROD-CRITICAL host-only | **clear** | TC-226-16 is a full Orbit→Settings route-stack host test; host-green is legitimate closure for this UI-only change. *Caveat:* reopen leg not independently mutation-verified → T5. | T5 |
| B-9 "unchanged" = untested | **HIT** | Two INV-5 sentinels + 206-enter test bound to no literal gate command (T3); INV-3 discriminator vacuous (M1). Most other preservation claims **are** sentinel-guarded. | M1, T3 |
| B-10 cross-platform parity in prose | **clear** | RTL parity is **run** (TC-226-14, ar locale + mutation); dark/light tone parity is **run** (TC-226-04 vs 05, literal ARGB). No per-OS behavioral claim. | — |

## What the plan does WELL (keep these)

- **Factual scaffolding is otherwise exact.** Every cited `file:line` except `:702` was independently confirmed against source: the glass recipe (`orbit_search_trigger.dart:26-57`), all four glass tokens (`background_readable_colors.dart:128-129`/`183-184`, dark/light `iconPrimary` `:122`/`:177`), the `FeedNavigationBar` mount (`settings_screen.dart:303`), `_onSwitchView` (`settings_wired.dart:532-535`), the bare `PageRouteBuilder` (`settings_route_transition.dart:7-34`), the `whenComplete` latch (`orbit_wired.dart:682-684`), the threshold constants (`feed_wired.dart:247-249` = 0.28 / 900), sibling surfaces, l10n `nav_orbit`, `assets/icons/nav_orbit.svg`, and the `orbit_search_trigger_test.dart` TC-212-08 clone pattern.
- **The #1 technical bet is domain-verified sound** with an exact in-repo precedent (`swipeable_friend_row.dart:235-240`) — rare and valuable.
- **Strong compartmentalization** (D2 88): three clean slices (glass widget → Feed-removal swap → swipe seam), each with its own file and GREEN checkpoint; the risky slice is ordered **last** and isolated with a concrete named fallback (feature-30 raw `Listener`).
- **"Good" defined up front** (D4 85): glass token **values pinned** as literal ARGB; dual-tone coverage **derived** from the goal; 16-row matrix with (almost) zero empty cells; RED reasons + known-failure interpretation + dirty-tree snapshot pre-stated.
- **Strong over-trigger sentinel suite:** leftward fling, under-threshold drag, vertical-scroll coexistence, flag-off, RTL — each with a **named non-vacuous mutation**.
- **Honest closure discipline:** host-only justified (UI-only, no OS boundary/DB/crypto/relay); the single host-unjudgeable item (BackdropFilter *look*) correctly demoted to a non-gating manual sim screenshot; hard Scope Guard "Do not" list protecting the 5 shared-default suites.

## User-owned decisions to confirm **before execution** (not blockers for this document)

1. **Swipe feel** — the plan interprets "swipe right returns to Orbit" as a **discrete over-threshold gesture** firing the canned **280ms** pop, **not** an interactive finger-tracked drag (tracking is scoped to "future polish", plan:69,272). If you pictured an iOS-style tracked edge drag, confirm now — otherwise the feature can ship "green" yet miss the felt goal.
2. **RTL direction** — the plan locks **physical** left→right (dx>0) even under RTL (TC-226-14), overriding the common RTL-mirroring convention for back-gestures. Confirm physical-direction is intended, or flag for mirroring.

*(No release-risk or "done-number" decision is needed — this is a reversible, non-persisted UI change with no perf metric.)*

---

# Fix-List (exact edits)

Glossary: *Move-Account* = the account-migration ("move to new phone") feature; *feature-30* = the Feed↔Orbit host swipe; *the shell* = `AppShellController` (the feed/orbit tab owner).

## §A — Make INV-3 genuinely locked (material)
- **A1.** In the File C harness spec (plan line 117) change "real `AppShellController`" to **`AppShellController(initialTab: AppShellTab.feed)`**. Rewrite TC-226-07 and TC-226-08 GREEN assertions to require the tab **was `feed` before the gesture and became `orbit` after** (not merely "== orbit"). Add a matrix mutation column entry for both rows (plan lines 162-163): **`replace _onSwitchView("orbit") with a bare Navigator.pop() → tab stays feed → RED`**. *Why:* the current harness starts at the controller's default (orbit) where `switchTo('orbit')` is a no-op, so a `pop()`-only handler passes identically — the discriminator the plan claims (line 125) does not exist until the pre-state is non-orbit.

## §B — Real sub-surface enumeration + wrong-route-pop guard (material)
- **B1.** Delete the false "nested `SettingsWired` at `:702`" claim at plan lines **175** and **202**. Replace with the true enumeration: Move-Account journey (`settings_wired.dart:700`, opaque route → occludes body), `_showSettingsSheet` modal sheets (`:553-557`, `ModalBarrier` absorbs), `_runQrEntry` QR entries (`:539`). *Why:* `:702` pushes `AccountMigrationJourneyWired.oldPhone`, not `SettingsWired` — the plan's justification for skipping sub-surface analysis is factually void.
- **B2.** Add **one** guard case to `settings_swipe_back_test.dart`: push a stand-in sub-route (or show a modal sheet) over Settings, fling rightward, assert `SettingsWired` is **NOT** popped **and** the sub-surface is unaffected. Mutation: **`move the GestureDetector above the sub-route barrier → red`**. *Why:* converts accidental occlusion-safety into a locked invariant; `_onSwitchView` calls `Navigator.pop()`, so a leak pops the wrong route — the highest-consequence failure of this change.
- **B3.** Add a step-6 Stop-if (plan line 193 area): *"If any pushed Settings sub-route/sheet (Move-Account `:700`, `_showSettingsSheet` `:553`, `_runQrEntry` `:539`) does not fully occlude the body, gate the `GestureDetector` off while a sub-route is active — mirror the existing `_moveRouteActive`/`_qrRouteActive` latches."*

## §C — Repair mutation-verification integrity (moderate)
- **C1.** Commit to **end-firing**: at plan line 62 drop the "per-gesture latch (latch reset on drag start)" language, keeping "on drag END qualify … fire `_onSwitchView('orbit')` once." Rewrite the TC-226-15 mutation (line 145) to **`call _onSwitchView in onHorizontalDragUpdate whenever accumulated dx crosses threshold (fires N times) → NavigatorObserver counts >1 pop → red`**. *Why:* `onHorizontalDragEnd` fires once per gesture, so "remove the per-gesture latch" has nothing to remove and cannot re-red an end-firing design.
- **C2.** In TC-226-04 (catalog line 106, matrix line 159) assert `boxShadow` on the **outer unclipped** `Container` (ancestor of the `ClipOval`; mirror `orbit_search_trigger_test.dart:33-41` `.first`) and add mutation **`move BoxShadow onto the inner clipped Container → outer boxShadow empty → RED`**. *Why:* the plan's own "clipped shadow is invisible" invariant is otherwise unguarded.

## §D — Bind the preservation gates + matrix hygiene (moderate + nits)
- **D1.** Append to a literal preservation line in the Acceptance Gates block (plan lines 229-231): `test/features/push/application/intro_notification_orbit_route_test.dart` and `test/features/theme/dark_preset_preservation_test.dart` (and the TC-206-01 slide-up-enter test). *Why:* both are named INV-5 sentinels (line 175) but sit outside `test/features/settings/` and outside `GROUP_TESTS`/`FEED_TESTS`, so no plan command runs them.
- **D2.** Replace the three "compile RED / file absent" cells (matrix lines 159-161) with the catalog's behavioral RED reasons (stub renders a bare box → recipe/tone/Semantics assertions fail). *Why:* step 2 creates the stub first, so the file is present at RED time.
- **D3.** TC-226-16 (line 150): add a reopen-leg-specific mutation **or** document the reopen assertion as preservation of untouched `orbit_wired.dart:682-684`. *Why:* it currently shares TC-226-08's mutation, which reds it via the fling leg only.
- **D4.** N1–N5 above: rename the `settings_screen_test.dart:147` test; pin `orbit_settings_entry_test.dart` to `N+1`; note TC-226-06 is only half-red vs the stub; clarify the GestureDetector wrap point (N4); add the 224px/`MediaQuery`-width test-authoring note (N5).

## Priority order to apply
1. **M1 (§A) + M2 (§B)** — the two material defects: make INV-3's discriminator real, and guard against the wrong-route pop while a Settings sub-flow is up.
2. **C1, C2 (§C)** — restore mutation-verification integrity (latch/end-fire contradiction; shadow-placement).
3. **D1 (§D)** — bind the unbound preservation sentinels to a runnable command.
4. **D2, D3, D4 (§D)** — matrix prose, TC-226-16 reopen-leg, and the nits.

## Verified facts this list relies on (checked against source in this audit)
- `settings_wired.dart:700-717` pushes `AccountMigrationJourneyWired.oldPhone` (Move-Account) via `buildSettingsSlideUpRoute` — **not** `SettingsWired`. ✅
- Only two `SettingsWired(` construction sites: `orbit_wired.dart:660` (nav bar) and `posts_wired.dart:540` (`showNavigationBar:false` at `:554`). ✅
- `app_shell_controller.dart:27` default `initialTab = orbit`; `:41-48` `switchTo` no-ops on invalid/same tab. ✅
- `_onSwitchView` = `appShellController.switchTo(tab)` + `Navigator.of(context).pop()` (`settings_wired.dart:532-535`). ✅
- `intro_notification_orbit_route_test.dart` (test/features/push/) + `dark_preset_preservation_test.dart` (test/features/theme/) are in **no** `run_test_gates.sh` array and reference the shared navbar. ✅
- Glass recipe + all four tokens, `FeedNavigationBar` mount (`:303`), route transition (bare `PageRouteBuilder`, 420/280ms), `whenComplete` latch (`:682-684`), thresholds (0.28/900), l10n `nav_orbit`, `nav_orbit.svg`, TC-212-08 clone pattern — all **confirmed** accurate. ✅
- In-repo horizontal-inside-vertical precedent: `swipeable_friend_row.dart:235-240`; zero competing horizontal recognizers in `lib/features/settings/`. ✅
