# 223 Review — Fix-List (apply against `223-orbit-expanded-arc-bottom-overhang-scroll-tdd-plan.md`)

Source: 8-agent adversarial workflow audit + lead source-verification + an empirical hit-test repro, 2026-07-08.
Plan is **NOT execution-ready**: the root-cause forensics are accurate, but the chosen fix **mechanism cannot
achieve the stated goal** and its PROD-CRITICAL gate measures the wrong quantity. Core layout sub-bet (growth does
not move `cy`) is **verified sound**; the mechanism built on it is not.

Decisions locked with the user (2026-07-08):
- **Goal = TAPPABILITY, mechanism = grow `boxHeight` DOWNWARD.** The revised plan makes the bottom node
  *hit-testable* (not merely scrolled into view). Grow the canvas SizedBox downward in `OrbitalVisualization`
  (`cy`/top-overhang held fixed); DROP the host-Column spacer.
- **arcWrap>1.0 is IN scope — fix all seats.** The helper scans every `computeOrbitLayout` seat (ring1/ring2/arc);
  add an `arcWrap≥2.5` RED pair; rewrite `TC-223-01`'s oracle to iterate seats.
- Delivery: this fix-list (plan file left for you to apply).

Glossary (terms the plan assumes): **`InnerCircleInteractiveSurface`** = the scrollable Orbit inner-circle host
widget; **`OrbitalVisualization`** = the pure canvas it renders (the `SizedBox(320, boxHeight)` + `Stack`); **sculpt
handles** = the draggable geometry knobs (avatarScale/spacingScale/orbitGap/arcWrap/maxPerArc); **the poke** = the
pixels a node's painted/interactive box extends below `boxHeight`.

Verified facts this list relies on (checked against source + one empirical test):
- `Clip.none` clips **paint, not hit-test**; the `SizedBox`/`Stack` gate hit-testing to `[0, boxHeight]`
  (`orbital_visualization.dart:319-327`; the plan admits this at **L54**). ✅ **Empirically proven**: a node whose
  center sits at `boxHeight+1.4` is NOT tappable at its center but IS tappable at its top sliver, while
  `getBottomRight` still reports the full rect below the box.
- Bottom ring-2 node center = `boxHeight+1.4` at av=1.4/sp=1.5/50 friends (`cy+dy = 160+overhang+161.4`,
  `boxHeight = 320+overhang`). ✅
- Node box is floored to **48px** for tappable seats: `_minTapTargetSize=48` (`orbital_visualization.dart:80`),
  `_tapTargetSize` floors sub-48 tappable avatars (`:468-473`), `OrbitalAvatar` self-floors (`orbital_avatar.dart:105-107`).
  `host()` wires non-null `onFriendTap` (`orbit_sculpt_summon_wired_test.dart:111`). ✅
- Growing `boxHeight` downward keeps `cy`, top-overhang and handle anchors fixed — anchors derive from
  `canvasOrigin + (160 + overhang + a.dy)` (`orbit_sculpt_summon_wired_test.dart:206-209`), not from `boxHeight`'s
  bottom; canvas is top-anchored when expanded (`TC-198F-27` GREEN on HEAD — I ran it). ✅ → INV-223-3 preserved.
- `_compensateScrollForOverhang` is the single scroll writer (`inner_circle_interactive_surface.dart:509-524`);
  `OrbitalVisualization` has exactly one host (`:652`); `feature-host-all` is a real glob
  (`run_host_test_gates.sh:226`); widget file pinned in `groups` (`:274`). ✅ (B-2/B-3 clean.)
- Arc seat `dy = -r·cos(φ)` (`orbit_arc_layout.dart:336`); at `arcWrap=2.5` (bounds `[0.5,2.5]`) arc tips poke
  +150–290px below the ring-2 seat and are wholly outside the hit gate. ✅

---

## §A — Mechanism & goal (the blocker that gates the whole ship)

- **A1.** Rewrite the fix mechanism in **§Real Scope (L58-60)**, **§Files To Inspect (L64-66)** and **§Step-By-Step
  step 4 (L138)**: instead of appending a host-Column spacer, **grow `boxHeight` downward in
  `OrbitalVisualization`**. Concretely in `orbital_visualization.dart:136-143`, add a bottom term and add it to
  `boxHeight` ONLY (leave `cy = _center + overhang` at `:145` untouched):
  ```dart
  final bottomOverhang = overflowExpanded
      ? orbitArcBottomOverhang(memberCount: items.length, geometry: geometry, centerY: _center)
      : 0.0;
  final boxHeight = _size + overhang + bottomOverhang;   // grows DOWNWARD; cx/cy unchanged
  ```
  *Why:* this is the ONLY change that makes the node's poke region **hit-testable** — the `SizedBox(320,boxHeight)`
  hit gate now includes the node — while simultaneously growing the host scroll content (taller canvas ⇒ larger
  `maxScrollExtent`). The host-Column spacer moves the node into *view* but leaves its center below the hit gate
  (proven), so it does not achieve the stated goal (L37 "cannot … interact with"). **Delete the host-Column-spacer
  edit entirely** — it is redundant once `boxHeight` grows.

- **A2.** Relax the **Scope Guard (L201)** and the read-only note (**L65**) and Stop-if (**L138**): change "do not
  modify … `boxHeight`" / "do not change `boxHeight`/`cy`" to **"do not change `cy = _center + overhang`, the
  top-overhang (`orbitArcOverhang`'s return), or any handle anchor; growing `boxHeight` DOWNWARD by the bottom
  overhang is required and is anchor-safe."** *Why:* the current guard forecloses the only correct mechanism;
  freezing `boxHeight`'s bottom is over-broad — the real invariant is `cy`/top-overhang/anchors (INV-223-3), which
  downward growth preserves.

- **A3.** Reword **INV-223-3 (L130)** accordingly: "`cy`, the top-shift overhang, and every handle anchor are
  UNCHANGED (the fix grows `boxHeight` **below** `cy` only)". Keep its named sentinels but see §D (they are currently
  inert).

---

## §B — Make the PROD-CRITICAL test measure the goal (hit-testability, not geometry)

- **B1.** Rewrite **`TC-223-02` (L91-96)** from a `getBottomRight ≤ viewportBottom + 0.5` geometry assertion into a
  **real interaction assertion**: after seeding geometry, expanding, and scrolling to `maxScrollExtent`, locate the
  bottom-most node (see B2), `await tester.tap(find.byKey(ValueKey('orbit-node-$idx')))` **at its center**, `await
  settle`, and assert the friend's tap fired (`expect(tappedFriends, contains(<that friend id>))`). *Why:*
  `getBottomRight` passes even when the avatar center is non-hit-testable (proven); only a real tap discriminates
  "visible" from "tappable" — the actual user-facing win.
  - Keep the non-vacuous RED discriminator: on HEAD assert BOTH `pos.maxScrollExtent > 0` (there IS scroll) AND the
    center tap does NOT reach the friend (it falls through to the opaque background detector at
    `inner_circle_interactive_surface.dart:636-644`), proving "scrollable-but-not-interactive", not "not scrollable".
    Note a stray idle single-tap on the background is a no-op (`_onBackgroundTap`, `:343-351`) — assert
    `tappedFriends` stays empty on HEAD, becomes non-empty after the fix.

- **B2.** In `TC-223-02` and the new arc case (§C), pick the bottom-most node by scanning **ALL** `orbit-node-$i`
  (ring AND arc, i.e. `i in 0..items.length-1`, or all mounted `orbit-node-*` keys), not `i in 5..12`. *Why:* the
  `5..12` range is ring-2-only and structurally assumes ring-2 is bottom-most — false once arcWrap>1.0 (§C).

---

## §C — Reconcile the helper contract; cover the full geometry space (F1 + F2)

- **C1.** Define **`orbitArcBottomOverhang`** (new pure fn in `orbit_arc_layout.dart`) to **scan every
  `computeOrbitLayout` seat** and floor each seat's half-extent to the tap target:
  ```dart
  // returns max(0, over all seats of: seat.dy + max(seat.avatarSize, kOrbitMinTapTarget)/2 - centerY)
  ```
  (`kOrbitMinTapTarget` already lives in this file at `:31`.) *Why (F1):* the rendered node box is the 48px tap box,
  not the visual avatar — sizing to `avatar/2` leaves the bottom 3px (and, without §A, the whole center) outside the
  hit gate. Assume tappable (every node on this surface is: `onFriendTap`/`onGroupTap` are required non-null; the
  domain layer cannot see tappability). *Why (F2):* scanning all seats covers arc tips that fall below ring-2 at
  high arcWrap.

- **C2.** Rewrite **`TC-223-01`'s GREEN oracle (L88)**: replace the ring-2 closed form
  `cy + r2·sinθ + avatar/2` with an **iterate-all-seats** oracle
  `max(0, maxSeat(seat.dy + max(seat.avatarSize, kOrbitMinTapTarget)/2) − centerY)` computed from
  `computeOrbitLayout` for the same geometry. Assertions: `closeTo(25.4, 1)` at
  `defaults.copyWith(avatarScale:1.4, spacingScale:1.5)`; `== 0` at `defaults`. *Why:* pins a single-valued,
  tap-box-based contract that both `TC-223-01` and `TC-223-02` agree on (kills the 3px mutual inconsistency), and
  matches the all-seats helper.

- **C3.** Add an **arcWrap RED pair** (new `TC-223-05`):
  - domain: `orbitArcBottomOverhang(memberCount: 50, geometry: defaults.copyWith(arcWrap: 2.5), centerY: 160) > 100`
    (arc tips droop far below; a ring-2-only impl returns ~0 → RED-then-GREEN).
  - widget: seed `arcWrap: 2.5`, ~50 friends, expand, scroll to max, tap the bottom-most **arc** node's center,
    assert its friend tap fired. *Why:* the only test that discriminates a correct all-seats helper from the
    tempting ring-2-only shortcut that passes all four existing tests. Add the row to the matrix + INV list.

- **C4.** In the problem statement (**L35/L37**) and Root-Cause §3 (**L49**), state that the interactive bottom poke
  is **spacingScale-driven** (and arcWrap-driven); avatarScale moves only the top-overhang and the *visual* avatar,
  not the 48px tap-box bottom (ring-2 avatar `30×1.4=42 < 48` floors to 48 for all avatarScale). *Why:* the current
  dual-knob "avatarScale and/or spacingScale" framing mis-attributes the primary defect and invites keying the
  helper off avatarScale.

---

## §D — Make preservation real (the sentinels are currently inert)

- **D1.** Add a preservation sentinel (new `TC-223-06`) at **`spacingScale≈1.5`, expanded, scrollable** (e.g.
  `host(_friends(80))` with seeded `sp=1.5`): re-verify handle seating (`expectedCenter` for the visible knobs) AND
  planted centre-avatar during an sp drag, **with the bottom growth active**. *Why (B-7/B-9):* `TC-198-71/72/F-27`
  all run at `sp=1.0` where the new bottom term is `107.6·sp−136 ≤ 0` (zero) and the extended
  `avatarScale/spacingScale` compensation branch is never taken — "stays green" proves nothing about the changed
  code. This is the plan's stated #1 risk (handle seating) and it is currently unguarded in the perturbed regime.

- **D2.** Add **`TC-198F-02`** to the preservation-gate command block (**L169-172**) and Done Criteria (**L193**),
  since INV-223-3 (L130) names it. *Why:* an invariant "locked by" a test never explicitly run invites skipping it.

---

## §E — Fix the over-growth guard and the compensation edge (F4 + over-growth)

- **E1.** Retarget **`TC-223-04` (L106-111)** from 8-friends-collapsed to an **expanded-but-fits** population where
  `boxHeight` sits just under the 600px test viewport with poke==0 (e.g. **50 friends at `defaults`**, expanded:
  `boxHeight ≈ 561 < 600`, arc tips poke up, ring-2 fits ⇒ bottom overhang 0). Assert `maxScrollExtent == 0`.
  Mutation = **"grow `boxHeight` by an unconditional constant (e.g. +48) regardless of the poke"** → content tips
  past 600 → `maxScrollExtent > 0` → RED. *Why:* the 8-friend case is collapsed, so the `overflowExpanded` gate +
  `ConstrainedBox(minHeight:viewport)` floor make it pass for ANY spacer — the named mutation cannot re-red it, so
  INV-223-4 is not actually locked.

- **E2.** Address the sp-shrink-at-bottom over-jump: extend **step 5 (L139)** and **INV-223-2 (L129)** to either
  (a) **acknowledge** the residual — like `TC-198F-27` acknowledges the og short-stack, state INV-223-2 holds
  "except at the bottom scroll edge under sp-shrink, where the sp-coupled content change (ΔS≈8px/step) exceeds the
  top-overhang compensation and the position clamps; recovery is the steppers" — OR (b) compensate ΔS in
  `_compensateScrollForOverhang` (`:512`, currently `delta = Δ top-overhang` only). Add a shrink-at-bottom sp
  assertion if (b). *Why:* extending compensation to `spacingScale` + the sp-coupled bottom growth breaks the single
  writer's "content grows by exactly delta" clamp invariant (`:516-521`) on shrink; `TC-223-03` only *grows* sp, so
  this is untested and INV-223-2's unconditional "planted" is unachievable at the bottom edge.

- **E3.** Either drop **`avatarScale`** from step 5's compensation-guard extension (keep `spacingScale` only) and
  reword INV-223-2 to spacingScale-only, OR add a focused assertion that an avatarScale drag issues the same
  `Δoverhang` scroll jump. *Why:* avatarScale's overhang swing is ~6.8px over its full range (`av/2` term in
  `orbitArcOverhang`, `:243`) — below the <8px drift threshold, so the added branch is untested and arguably dead.

---

## §F — Nits / hygiene

- **F1.** Mark the **Planning Progress table (L7-12)** as provenance/non-gating (it narrates the authoring workflow
  with no verifiable per-row artifact, unlike the real Acceptance Gates).
- **F2.** After the mechanism change, the "canvas Column" seam ambiguity (host `Center→Column` vs
  `OrbitalVisualization`'s internal Column) is **mooted** — the edit is unambiguously `boxHeight` in
  `orbital_visualization.dart:143`. Remove the stale "append to the canvas Column" wording.
- **F3.** Record in "Refuted / do-NOT-re-introduce" that **F3 (the feared Center up-shift) was empirically
  refuted** (`TC-198F-27` GREEN; canvas top-anchored when expanded) — so no Center-recentering compensation is
  needed.

---

## Priority order to apply
1. **§A (mechanism) + §B (tap-based PROD-CRITICAL gate)** — without these the plan ships something that does not fix
   the bug and cannot detect that it didn't. This is the ship-gate.
2. **§C (helper contract + arcWrap coverage)** — reconcile the mutually-inconsistent gates and cover the full,
   user-reachable geometry space; otherwise a green plan leaves the same defect live.
3. **§D (real preservation) + §E (over-growth guard + compensation edge)** — make the safety net and the guards
   actually exercise the changed code.
4. **§F (nits/hygiene)** — provenance labeling, stale-wording cleanup.
