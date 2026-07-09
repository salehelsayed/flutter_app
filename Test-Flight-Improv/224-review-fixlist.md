# 224 Review — Fix-List (apply against `224-orbit-side-arc-tap-dead-zone-tdd-plan.md`)

Source: 8-agent source-verified audit (workflow `wf_6b468424-7f9`) + lead-auditor Python reproduction of the full geometry, 2026-07-09. Plan is **execution-ready with tightening** — the **core bet is source-verified SOUND** (root cause, 3-site X-centre enumeration, all G0–G4 anchors, INV-224-5 stale-measurement invariance, and host-green=closure all hold). Every item below is a documentation / mutation-attribution / seam-precision fix; **none changes the fix mechanism or blocks execution.**

Glossary for anyone new to this area:
- **The dead zone**: on the Orbit inner-circle, an arc avatar on the left/right *flank* is painted but its tap-center falls outside the fixed-width 320px canvas box, so Flutter's `RenderBox.hitTest` rejects the tap (it checks `size.contains(position)` before descending) and the tap falls through to the opaque background gesture layer (= tap-away).
- **The fix**: grow the canvas box *width* to the seats (never clamp the seats to the box), mirroring the existing vertical-overhang mechanism, and shift the paint centre `cx` right by the same overhang so every consumer tracks.
- **`av/sp/cv/pr/og`** = avatarScale / spacingScale / arcWrap / maxPerArc / orbitGap knobs.

## Decisions locked with the user (2026-07-09)
- **Narrow-phone (≤375dp) coverage = BOTH**: add a ≤375dp boundary fixture that locks the accepted dead-band, AND add an explicit "automated closure scoped to width ≥390dp" note to Done Criteria plus a required manual device-sanity check on the actual reporting device.
- **Delivery = this fix-list** (plan file left untouched; apply these before execution).
- No release-risk decision needed (host-only, no migration, nothing irreversible). No "done number" decision needed (goal is boolean tappability, not a metric).

## Verified facts this list relies on (I reproduced each against real source / the real layout engine)
- Root cause SOUND — `orbital_visualization.dart:326-336` `SizedBox(width:_size=320, height:boxHeight)` wraps `Stack(Clip.none)`; `cx=_center(160)` at `:151`; width never grows. `Clip.none` paints-but-doesn't-hit; tap falls to the sibling background `GestureDetector` at `inner_circle_interactive_surface.dart:653-662` → `_onBackgroundTap` (`:346-354`). ✅
- **Complete** X-centre enumeration — the ONLY three surface sites hardcoding `kOrbitCanvasCenter` on the X axis are `:516` (drag centre, 1st `Offset` arg), `:896` (handle anchor), `:957` (value bubble). Grep found no 4th X site and no bare `160` literal in orbit prod. ✅
- All 5 cited `cx`-consumers track `cx`: `viz:184/:200/:259/:313/:441`. ✅
- Geometry anchors (Python, matched to `computeOrbitLayout`): G0 edge |dx|=177·sin(1.25)=**167.9703** → so **31.9703** → box **383.94**; G1 **0.0** (|dx| 135.19); G2 **10.14**; G3 **34.0** (arc1 pinch → |dx| exactly 170); G4 **58.19** (clamps to box 390, cx 195, edges {0.81, 389.19}). ✅
- `_CanvasMeasurement` at `:108-121` has `{origin, scrollOffset, signature}` and **no width field**; `_canvasOriginNow` (`:330-335`) returns an **Offset only** (scroll-corrects Y only). ✅
- E4 donor lines hardcode `160` for the X centre: `orbit_sculpt_summon_wired_test.dart:256`, `:1000`, `:1715`. ✅

---

## §A — Mutation column: RUN every mutation, correct the four wrong/inert cells
> The mutation-revert column is the plan's closure *evidence*. Two deltas are numerically/attribution wrong and two are structurally inert — a signal that mutations were reasoned, not executed. **Instruction to the executor: RUN every mutation for real; do not trust the documented deltas — at least four will surprise you.**

- **A1. TC-224-02 (plan line 97 & matrix line 118) — correct `25.57` → `31.77`.** The avatar-only scan at G0 is `167.9703 + 47.6/2 − 160 = 31.77` (arc avatar `clamp(34·1.4,20,52)=47.6` is only 0.4px under the 48 floor). It still reds vs `closeTo(31.9703, 0.05)` but by **~0.15px past the tolerance edge**, not the ~6px `25.57` implies. Edit the parenthetical to `(would give 31.77 — ~0.15px under; robust tap-floor proof is TC-224-06)`. *Why:* a wrong number erodes executor trust and the razor margin means a later tolerance-widen silently neuters this cell.

- **A2. TC-224-02 tap-floor coverage — point at TC-224-06.** Note in the row that the *robust* tap-floor discriminator is **TC-224-06** (G2, av=0.6: avatar-only collapses to `0.0` vs expected `10.14`, a ~10px margin). *Why:* keeps the matrix from overstating TC-224-02's power.

- **A3. TC-224-12 (plan line 107 & matrix line 128) — change "revert any of E1/E2/E3a → red" to "revert E1 or E2 → red".** **The E3a leg is FALSE** (proven): at TC-224-12's geometry (av1.4/og1.5/cv1.0/n50) every full arc pinches to |dx|=170; reverting E3a alone restores `padding: horizontal 24` → content 342 → cap 11 → `cx=171` → edge-seat center at local **1.0px, still inside [0,342]** → tap fires → **TC-224-12 stays GREEN**. Add: "E3a's no-op discriminator is **TC-224-13** (release band cv=2.5, needs cap ≥ 17)." *Why:* an executor who mutates E3a and sees green will distrust the harness or skip the E3a check.

- **A4. TC-224-03 & TC-224-05 (plan lines 98, 100) — the `.abs()` mutation is structurally INERT.** Arc layouts are **symmetric about the vertical** (full arc `start=-phiMax`; partial arc centered), so `dx ∈ [−170,+170]` and signed-max ≡ abs-max — dropping `.abs()` leaves the result unchanged (verified: G3 34.0=34.0, G0 31.97=31.97) → the mutant **never reds** at any real geometry. Do ONE of:
  - (preferred) Keep `.abs()` in E1 as *defensive-but-redundant* and re-label these mutations: TC-224-03's real guard is its GREEN value `closeTo(34.0, 0.05)` (proves the default-knob overhang); give TC-224-03 an *effective* mutation instead, e.g. `cap the scan at kOrbitPinchHalfWidth` or `return raw (un-floored) side` → reds. For TC-224-05, exercise `.abs()` with a **synthetic asymmetric seat list** (hand-built, not via `computeOrbitLayout`) so the mirror-invariance law is actually mutation-tested; otherwise mark TC-224-05 as a weak/near-tautological row (the fn is mirror-independent by construction — it never takes a `mirrored` param).
  - *Why:* two more inert mutation cells compound the "reasoned not run" signal; the fix keeps the guard honest.

## §B — Pin the E3(b) measured-width seam (under-specified)
- **B1. Spell out how `m.width` reaches the three centre-X sites (plan line 156).** `m.width` is in scope at **none** of `:516/:896/:957` today — each has only the derived `origin` `Offset`. Concretely:
  1. Add `final double width;` to `_CanvasMeasurement` (`:108-121`), require it in the ctor.
  2. In `_measureCanvasNow` (`:300-304`) capture it from the same measurement instant: `width: canvasObj.size.width` (the `_canvasKey` SizedBox = the grown box).
  3. Add `double? get _canvasWidthNow => _canvasMeasurement?.width;` next to `_canvasOriginNow`.
  4. Thread a `double width` param into `_buildAnchoredHandle` and `_buildValueBubble` from the handle-layer `ListenableBuilder` (`:817-846`, feed from `:820`); at the arcWrap drag centre `:514-516` read `_canvasMeasurement?.width ?? kOrbitCanvasSize`.
  - **Guard rail:** width is **scroll-INVARIANT** — do NOT scroll-correct it like origin, and NEVER substitute the compile-time `kOrbitCanvasSize=320` for the *measured* width (that silently defeats the grown-box fix; only TC-224-14's post-fix mutation would catch it). *Why:* the plan's `origin.dx + m.width/2` shorthand maps to no existing variable; the executor must not improvise this seam.

## §C — X-only constant discipline (edit-hazard guard)
- **C1. Add a "change X only, leave Y" rule to E3(b) / Scope Guard.** `kOrbitCanvasCenter` occurs **6× in the surface**, and **twice inside one `Offset` at `:516`** (`Offset(kOrbitCanvasCenter /*X→width/2*/, kOrbitCanvasCenter + _currentOverhang /*Y, KEEP*/)`). Verbatim rule to add: *"No `replace_all`. Change ONLY the X-axis occurrences: `:516` 1st arg, `:896`, `:957`. Leave the Y-axis uses untouched: `:274`, `:516` 2nd arg, `:897`, `:958`."* *Why:* a `replace_all` or an inattentive `:516` edit corrupts the vertical anchor / arcWrap-angle math — fatal for a plan whose whole thesis is "grow X, leave Y".

## §D — Narrow-phone (≤375dp) accepted-difference (user chose BOTH)
- **D1. Add a ≤375dp boundary fixture.** New row (widget tier, sculpt or arcs file) at a 360/375dp surface (`tester.view.physicalSize`), high-arcWrap geometry (cv≥1.6 so |dx| can exceed the clamp). Assert: (a) the near-in seats (center inside the clamped box) still fire `onFriendTap`; (b) the documented dead-set edge seat's **left edge is expected-OUTSIDE** the box (locks the accepted difference so a regression that *widens* the dead band reds). *Why:* today every hit-test fixture runs ≥390dp (TC-224-12/-13) or the 800dp arcs default — the (187.5, 194] dead-band on common 360–375dp phones (iPhone mini/SE) is guarded by **nothing**, and the user hit this at non-default knobs on a device of unverified width.
- **D2. Scope automated closure to ≥390dp in Done Criteria + require device sanity.** Add to Done Criteria: *"Automated tappability closure is scoped to viewport width ≥390dp; ≤375dp high-arcWrap seats beyond the clamp are an Accepted Difference (line 221), boundary-locked by [D1]."* Promote the manual device-sanity check (line 169) from "recommended" to **required on the actual reporting device** before calling the bug fixed. *Why:* honest scoping + a real-device confirmation on the width that produced the report.

## §E — Precision nits (low stakes, quick)
- **E1. `_CanvasMeasurement` citation.** Change `:103-107` (that range is the doc comment) → `:108-121` (class body) at plan lines 62 and 156. *Why:* citation precision.
- **E2. Baseline provenance.** Add a captured-count row to the Execution Progress table (`flutter test test/features/orbit/` → "533 passed") and hedge line 185 like line 188 (*"script output wins"*), so a ±few drift from loop-generated cases reconciles against "0 fail" rather than reading as a failure. (Independent grep = 529 raw `test()/testWidgets()` decls, so 533 runtime is plausible/captured, not fabricated.)
- **E3. TC-224-17 pre-commit its acceptance.** It's currently "finder-RED *if* asserted via a new Padding key; otherwise preserved-green" (line 112). Pick one: add a stable `Padding` `ValueKey` and assert `horizontal==24` (finder-RED if absent), OR declare it preserved-green with the drop-hint-padding mutation as its sole guard. *Why:* the one non-committed cell in an otherwise fully-specified matrix.

---

## Priority order to apply
1. **§A (mutation correctness) + §B (E3b seam)** — these protect the fix's *evidence* and prevent a silently-defeated grown-box path; apply before writing any code.
2. **§C (constant discipline)** — one-line guard that prevents a fatal Y-axis corruption during the edit.
3. **§D (narrow-phone, BOTH)** — locks the only real coverage gap and sets honest closure scope + device proof.
4. **§E (nits)** — citation, baseline provenance, TC-224-17 disposition.

None of the above alters E1–E4's mechanism, the geometry, or the core bet. After applying §A–§D, re-run the RED→GREEN→mutation loop **executing every mutation** (do not reason them), and the plan is clean to ship host-only.
