# 158 - Chat/Group Ambient Idle-Glow Suppression (`critic-2`)  (Modification — release-build performance)

Status: IMPLEMENTED host-green (2026-06-24) — see Final Execution Verdict
Spec: free-text intent (no formal spec) — finding `critic-2` from `Test-Flight-Improv/app-smoothness-performance-audit.md` ("Always-mounted chrome blur re-runs over the 60fps-animating ambient background"). Sequenced by `Test-Flight-Improv/157-app-smoothness-structural-roadmap.md` (epic E-A). The Quick Wins (156) and the OS reduce-motion gate (`animations-repaint-4`, 156 QW-3) are already shipped — this plan is the **orthogonal** steady-state idle-animation axis for **default (motion-on)** users on chat/group surfaces.

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-24 | Evidence Collector | ambient_background.dart, conversation_screen.dart, group_conversation_screen.dart, feed_screen.dart, ambient_background_test.dart, run_test_gates.sh | seam confirmed: `_shouldAnimate` (ambient_background.dart:146-151) has no chat-surface term; both chat call sites pass only `preference` | derive RED catalog |
| 2026-06-24 | Planner | (grounding wf_85c86584-4e1 E-A) | host-tier, RED scaffold exists (ambient_background_test TC-04/05 + `ambientControllers`); distinct flag, NOT reduceMotion reuse | emit matrix + steps |
| 2026-06-24 | Reviewer (sufficiency) | this plan | spec-case totality + mutation + literal gates + registration + blind-spot sweep all satisfied | — |
| 2026-06-24 | Arbiter | this plan | no structural blockers; optional sigma leg fenced off | hand to execution |
| 2026-06-24 | Reviewer (2nd pass, 5-agent ground) | ambient_background.dart, conversation_screen.dart, group_conversation_screen.dart, both screen tests, conversation_wired_performance_harness.dart, 16 ambient call sites | 4 findings grounded: F1 RED-ordering contradiction (reorder steps), F2 add source-guard TC-158-00 (16 call sites → only 2 opt in), F3 perf-harness path+host-only correction, F4 preservation-clean (no test asserts ambient animating) + comment-cleanup follow-up | edits applied below — see "Second-Pass Review Incorporation" |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| | contract extraction (git status --short) | | | scope confirmed | |
| | RED tests added | ambient_background_test.dart, conversation_screen_test.dart, group_conversation_screen_test.dart | (cmd proving they FAIL) | RED for expected reason | |
| | implementation | ambient_background.dart, conversation_screen.dart, group_conversation_screen.dart | | scoped files only | |
| | direct GREEN | | | reds now green | |
| | preservation GREEN | | | ambient TC-04/05 + 1to1/feed/groups green | |
| | named gates | | | gate green | |
| | QA (independent) | | | blocking: none/list | verdict |

## Source Of Truth
- Intent: `app-smoothness-performance-audit.md` finding `critic-2` + `.findings.json`; roadmap `157-app-smoothness-structural-roadmap.md` (E-A).
- Gate definitions: `scripts/run_test_gates.sh` (script wins over prose).
- Numbering / index: `Test-Flight-Improv/00-INDEX.md`.

## Session Classification
implementation-ready (host-only for closure).

## Exact Problem Statement
On a 1:1 or group chat surface, the default-background `AmbientBackground` runs an infinite 8-second glow loop (`_controller.repeat()`), repositioning two radial-gradient glow layers every frame. The always-mounted chrome — conversation/group header (`BackdropFilter` sigma 20), composer (sigma 20 / group 12), group name panel (sigma 30) — sits in front of those moving glows. A `BackdropFilter`'s input is the live backdrop, so an animating backdrop makes the blur **un-cacheable**: it re-rasterizes every frame **even when the user is doing nothing**, keeping the GPU warm (battery/heat) and stealing raster budget. 156 QW-3 added an OS reduce-motion gate, so reduce-motion users already get a static glow — but for the default (motion-enabled) user the loop still runs on chat/group surfaces.

What must improve: on a foregrounded chat/group surface, the ambient glow renders its **static** frame (controller not animating) for default users, so the chrome `BackdropFilter`s become cacheable at rest.

What must stay unchanged (→ preserved-green sentinels): the 156 OS reduce-motion gate (TC-04/05 in `ambient_background_test.dart`); the feed `isFeedSurface`+`reduceMotion` entrance semantics (134/135); and the living glow on **every other** ambient surface (orbit, settings, identity, qr, share, posts, groups-list/info) — they must keep animating with motion enabled.

## Root Cause (verify → refute confirmed)
`ambient_background.dart:146-151` `_shouldAnimate` gates ONLY on: `(a)` non-default preference, `(b)` `isFeedSurface && reduceMotion`, `(c)` `_motionDisabled` (OS reduce-motion). There is **no chat-surface / idle term**. `_syncMotionPreference` (`:84-98`) calls `_controller.repeat()` (`:90`) whenever `_shouldAnimate` is true. `conversation_screen.dart:293` and `group_conversation_screen.dart:194` construct `AmbientBackground(preference: …)` and pass **nothing else** — so for default, motion-on users on a chat surface, `_shouldAnimate` returns true and the loop runs. The chrome `BackdropFilter`s (`conversation_header.dart:35-36` 20/20, `compose_area.dart:313-314` 20/20, `group_compose_area.dart:102-103` 12/12, `group_name_panel.dart:40-41` 30/30) then re-blur every frame because the backdrop moves.

**Refuted / do-NOT-re-introduce** (four kill paths, grounding wf_85c86584-4e1 E-A):
- *Already fixed by 156?* No — QW-3 (`_motionDisabled`, `:84-98`/`:146-151`) is the OS-reduce-motion axis only; its own header comment scopes it to accessibility and "does NOT pause for any non-accessibility reason". `_shouldAnimate` has no chat term.
- *RepaintBoundary (QW-2) already fixes it?* No — the audit fix itself warns a glow RepaintBoundary does NOT cure the backdrop blur; the moving `Positioned` offset still changes what's behind the `BackdropFilter`.
- *Some other path stops the loop on chat surfaces?* No — grep of both chat screens + ambient_background found no `AppLifecycle`/`WidgetsBindingObserver`/idle/foreground seam; `repeat()` at `:90` is gated solely by `_shouldAnimate`.
- *Build-skew?* No — line numbers verified by direct Read of post-156 HEAD.

## Real Scope
**In scope:** (1) add a distinct boolean `isChatSurface` (default `false`) to `AmbientBackground`; (2) add an **additive** term `if (widget.isChatSurface) return false;` to `_shouldAnimate` (so the controller stays at value 0 → the existing static-frame path at `:94-97` renders); (3) pass `isChatSurface: true` from `conversation_screen.dart:293` and `group_conversation_screen.dart:194`.
**Optional, design-gated leg (fenced off, NOT in the core gate):** lower the four chrome `BackdropFilter` sigmas (header/composer 20→~12, group panel 30→~16) — separate slice, needs visual sign-off.
**Out of scope (owning work):** off-screen tab `TickerMode`/active-tab ambient pause → **163** (E-G/E-H); feed reduce-motion entrance → 134/135; all other findings → their 158–164 plans.

## Files To Inspect Next
Production: `lib/features/identity/presentation/widgets/ambient_background.dart` (constructor `:28-35`, `_syncMotionPreference` `:84-98`, `_shouldAnimate` `:146-151`); `lib/features/conversation/presentation/screens/conversation_screen.dart:293`; `lib/features/groups/presentation/screens/group_conversation_screen.dart:194`.
Reference pattern (do not edit): `lib/features/feed/presentation/screens/feed_screen.dart:135-191` (`_reduceMotion` + `isFeedSurface`).
Direct tests: `test/features/identity/presentation/widgets/ambient_background_test.dart` (`wrapAmbient` `:15-33`, `ambientControllers` `:111-117`, TC-04 `:119-128`, TC-05 `:130-139`); `test/features/conversation/presentation/screens/conversation_screen_test.dart`; `test/features/groups/presentation/group_conversation_screen_test.dart`.

## Existing Tests Covering This Area
- `ambient_background_test.dart` TC-04 (disableAnimations → not animating) / TC-05 (motion-on → animating) — exist; the **exact RED scaffold** (extend `wrapAmbient` with a `chatSurface` param, reuse `ambientControllers`). In **FEED_TESTS** (`run_test_gates.sh:101`).
- `conversation_screen_test.dart` — 1:1 widget suite, in **ONE_TO_ONE_TESTS** (`:62`). No `isChatSurface` assertion (MISSING — added here).
- `group_conversation_screen_test.dart` — group widget suite, in **GROUP_TESTS** (`:134`). No `isChatSurface` assertion (MISSING — added here).
Missing coverage gaps: no test asserts a chat-surface ambient is static at rest with motion on; no wiring-lock that either chat screen passes the suppression flag; no guard that the flag does NOT leak to the other 14 ambient surfaces (closed by the new source-wiring TC-158-00).
Already in curated arrays?: yes — all three target files are listed (FEED_TESTS:101, ONE_TO_ONE_TESTS:62, GROUP_TESTS:134); **no new array entry needed**.

## RED Test Catalog  (tests added before the behavior term + call-site wiring — INV-RED-FIRST; the surface-only `isChatSurface` prop lands first, step 2, so the wiring-lock tests compile — see Step-By-Step)
0. `ambient_background_test.dart`::`TC-158-00: only the two chat screens opt into isChatSurface (source-wiring lock)`
   - Tier: source-text / wiring-lock (idiomatic here — cf. `test/features/orbit/presentation/orbit2_prototype_source_guard_test.dart`, `test/core/lifecycle/main_resume_group_upload_wiring_test.dart`).
   - Shape/setup: read the source of `conversation_screen.dart` + `group_conversation_screen.dart`, assert each contains exactly one `isChatSurface: true`; then scan the other 14 `AmbientBackground(` call sites (`settings`, `first_time_experience`, `orbit`, `posts`, `identity_choice`, `sent_confirmation`, `group_info`, `create_group_picker`, `group_list`, `contact_picker`, `feed`, `account_migration_journey`, `share_target_picker`, `qr_display`) and assert NONE passes `isChatSurface: true`.
   - RED on HEAD because: `isChatSurface` does not exist and no call site uses it → the "exactly one in each chat screen" assertion fails (0 found).
   - GREEN after fix asserts: exactly two opt-ins, both on chat screens; zero leakage to the other 14 surfaces (locks the Scope-Guard "only the two chat call sites opt in" + INV-2).
   - Mutation that re-reds: remove either `isChatSurface: true` arg (count→1) OR add `isChatSurface: true` to any non-chat surface (leakage) → RED.
1. `ambient_background_test.dart`::`TC-158-01: chat surface does not animate the glow with motion enabled`
   - Tier: host widget.
   - Shape/setup: extend `wrapAmbient` with `bool chatSurface = false` → pass `isChatSurface: chatSurface` to `AmbientBackground`. Pump `wrapAmbient(chatSurface: true, disableAnimations: false)`, `pump()`. Assert `ambientControllers(tester).first.isAnimating` is `false`. Re-pump the same config (`tester.pump()` after a no-op rebuild) and re-assert `false` (didUpdateWidget/didChangeDependencies stay static).
   - RED on HEAD because: `isChatSurface` does not exist; `wrapAmbient` cannot pass it, and `_shouldAnimate` has no term for it → with motion on the controller `repeat()`s → `isAnimating` is `true`.
   - GREEN after fix asserts: `isAnimating == false` (static glow frame) on a chat surface with motion enabled.
   - Mutation that re-reds: revert the `if (widget.isChatSurface) return false;` term in `_shouldAnimate` → loop runs → `isAnimating` true → RED.
2. `ambient_background_test.dart`::`TC-158-02: non-chat surface still animates with motion enabled (no over-suppression)`
   - Tier: host widget.
   - Shape/setup: `wrapAmbient(chatSurface: false, disableAnimations: false)` (default), `pump()`; assert `ambientControllers(tester).first.isAnimating == true` (mirrors TC-05).
   - GREEN on HEAD (preservation / over-suppression guard, NOT RED-first): passes with current behavior. It goes RED only if a naive fix gates ALL surfaces (regressing orbit/settings/identity/share/qr/posts/groups-list living glow).
   - GREEN after fix asserts: default surfaces keep animating.
   - Mutation that re-reds: change the new term to gate unconditionally (drop the `widget.isChatSurface` check) → non-chat surfaces stop animating → RED.
3. `ambient_background_test.dart`::`TC-158-03: 156 reduce-motion gate still wins on a chat surface (additive, not replacing)`
   - Tier: host widget.
   - Shape/setup: `wrapAmbient(chatSurface: true, disableAnimations: true)`, `pump()`; assert `isAnimating == false`. Pair with the unchanged TC-04 (`chatSurface:false, disableAnimations:true → false`).
   - GREEN on HEAD (preservation lock, NOT RED-first): passes via the 156 `_motionDisabled` term — locks that the new term is OR-combined (additive), not a replacement that could short-circuit the reduce-motion clause.
   - GREEN after fix asserts: both gates agree (still static).
   - Mutation that re-reds: replace the `_motionDisabled` clause with the chat-surface clause (non-additive) → a chat+reduce-motion case could flip → RED (and TC-04 reds).
4. `conversation_screen_test.dart`::`TC-158-04: 1:1 conversation passes isChatSurface to AmbientBackground`
   - Tier: host widget.
   - Shape/setup: pump `ConversationScreen` with required props; `expect(tester.widget<AmbientBackground>(find.byType(AmbientBackground)).isChatSurface, isTrue);`.
   - RED on HEAD because: `conversation_screen.dart:293` passes only `preference`; `isChatSurface` absent → defaults to `false` → assertion fails. The prop is added FIRST (step 2) so this test compiles cleanly; the `_shouldAnimate` term (step 4) and the call-site wiring (step 5) land afterward, so the RED here is a genuine wiring failure, not a compile error.
   - GREEN after fix asserts: the 1:1 screen wires `isChatSurface: true`.
   - Mutation that re-reds: remove the `isChatSurface: true` arg at `conversation_screen.dart:293` → flag false → RED.
5. `group_conversation_screen_test.dart`::`TC-158-05: group conversation passes isChatSurface to AmbientBackground`
   - Tier: host widget.
   - Shape/setup: pump `GroupConversationScreen` with required props; `expect(tester.widget<AmbientBackground>(...).isChatSurface, isTrue);`.
   - RED on HEAD because: `group_conversation_screen.dart:194` passes only `preference`.
   - GREEN after fix asserts: the group screen wires `isChatSurface: true`.
   - Mutation that re-reds: remove the arg at `group_conversation_screen.dart:194` → RED.
6. *(OPTIONAL — only if the sigma leg is taken)* `conversation_screen_test.dart` / `group_conversation_screen_test.dart`::`TC-158-06: chat chrome BackdropFilter sigma at/below target`
   - Tier: host widget. Find each chrome `BackdropFilter`, read its `ImageFilter`, assert sigma ≤ target.
   - RED on HEAD because: dormant until sigmas are lowered (the optional leg). Restore original sigma constants → re-reds.

## Test Coverage Matrix  (ZERO empty cells in tier / mutation / gate / registration)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-158-00 | only the two chat screens opt in (no leakage to the other 14 ambient surfaces) | source-text / wiring-lock | ambient_background_test.dart::TC-158-00 | `isChatSurface` absent + no call site uses it → "one per chat screen" fails | remove either chat-screen arg, or add the flag to any non-chat surface | `./scripts/run_test_gates.sh feed` | AUTO (glob) + FEED_TESTS:101 |
| TC-158-01 | chat surface static at rest, motion on | host widget | ambient_background_test.dart::TC-158-01 | no `isChatSurface` term → loop runs | revert `_shouldAnimate` chat term | `./scripts/run_test_gates.sh feed` | AUTO (glob) + already in FEED_TESTS:101 |
| TC-158-02 | non-chat surfaces keep animating | host widget | ambient_background_test.dart::TC-158-02 | preservation (green on HEAD); reds if all surfaces gated | gate term unconditionally | `./scripts/run_test_gates.sh feed` | AUTO + FEED_TESTS:101 |
| TC-158-03 | 156 reduce-motion gate preserved (additive) | host widget | ambient_background_test.dart::TC-158-03 | preservation (green on HEAD); reds if term replaces reduce-motion clause | replace `_motionDisabled` clause with chat clause | `./scripts/run_test_gates.sh feed` | AUTO + FEED_TESTS:101 |
| TC-158-04 | 1:1 wires the flag | host widget | conversation_screen_test.dart::TC-158-04 | prop exists (step 2) so it compiles; call site passes only `preference` → flag defaults `false` | remove arg at conversation_screen.dart:293 | `./scripts/run_test_gates.sh 1to1` | AUTO + ONE_TO_ONE_TESTS:62 |
| TC-158-05 | group wires the flag | host widget | group_conversation_screen_test.dart::TC-158-05 | prop exists (step 2) so it compiles; call site passes only `preference` → flag defaults `false` | remove arg at group_conversation_screen.dart:194 | `./scripts/run_test_gates.sh groups` | AUTO + GROUP_TESTS:134 |
| TC-158-06 (opt) | chrome sigma ≤ target | host widget | conversation_screen_test.dart / group_conversation_screen_test.dart::TC-158-06 | dormant unless sigmas lowered | restore original sigma constants | `./scripts/run_test_gates.sh 1to1` / `groups` | AUTO + existing arrays |

## Blind-Spot Sweep  (evergreen classes — row added OR justified N/A)
- **Lifecycle / derived-state durability:** the suppression is derived from a widget prop (`isChatSurface`) and recomputed every `build`/`didChangeDependencies`/`didUpdateWidget` via `_syncMotionPreference` — there is **no persisted/latched derived state**. Covered by TC-158-01's re-pump assertion (a rebuild keeps it static). No reopen/restart test needed (nothing persists).
- **Sibling-surface consistency:** the new gate is a suppression that must apply to **both** chat surfaces (TC-158-04 1:1 + TC-158-05 group) and must **not** leak to the parallel ambient surfaces (the other 14 `AmbientBackground` call sites) — locked behaviorally by TC-158-02 (default flag false → still animates) AND by the source-wiring lock TC-158-00 (only the two chat screens pass `isChatSurface: true`). The asymmetry (chat suppresses, others don't) is deliberate and test-locked.
- **Destructive-action side-effects:** N/A — no delete/cleanup/cancel path; pure animation-gating + two call-site args.
- **Invariant re-verification under new transitions:** the new term is OR-combined into `_shouldAnimate`; TC-158-03 + the unchanged 156 TC-04/TC-05 re-verify that the reduce-motion invariant and the default-animates invariant still hold under the new term (no short-circuit of the `_motionDisabled` or feed-`reduceMotion` clauses).

## Invariants (locked by tests)
- INV-1: a foregrounded chat/group ambient glow controller is NOT animating with motion enabled → TC-158-01.
- INV-2: non-chat ambient surfaces keep their living glow with motion enabled → TC-158-02.
- INV-2b: ONLY the two chat call sites pass `isChatSurface: true`; none of the other 14 ambient surfaces opt in (source-wiring lock) → TC-158-00.
- INV-3 (156 preservation): OS reduce-motion still forces a static glow on every surface, and the new term is additive → TC-158-03 + existing TC-04/TC-05 (kept green).
- INV-4: both the 1:1 and group screens pass the suppression flag → TC-158-04, TC-158-05.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. Snapshot `git status --short` (dirty-tree baseline; the `performance` branch already carries 156's uncommitted work — do not revert it).
2. **Surface-only prop first (so the wiring-lock RED tests compile).** `ambient_background.dart`: add `final bool isChatSurface;` to the widget + `this.isChatSurface = false` to the const constructor (`:28-35`). Do **NOT** yet touch `_shouldAnimate` — with the default `false` and no term, behavior is byte-identical, so this is not the behavior change (it only lets `tester.widget<AmbientBackground>(...).isChatSurface` compile in TC-158-04/05). This is the standard "interface before implementation" shape; INV-RED-FIRST is still honored because the behavior term (step 4) and the call-site wiring (step 5) land AFTER the tests.
3. **Add the tests, run RED.** Extend `wrapAmbient` in `ambient_background_test.dart` with `bool chatSurface = false` → `isChatSurface: chatSurface`. Add the source-guard **TC-158-00** (RED — no call site opts in yet); the behavior **TC-158-01** (RED — `_shouldAnimate` has no term yet → chat surface still animates); the preservation guards **TC-158-02 / TC-158-03** (GREEN on HEAD — they only red under an over-suppressing/non-additive fix); and the wiring locks **TC-158-04** (conversation) + **TC-158-05** (group) (RED — call sites pass only `preference`, so `isChatSurface` defaults to `false`). Run the focused commands; confirm **TC-158-00/01/04/05 FAIL for the documented reason** and **TC-158-02/03 PASS** (preservation). The tests compile because step 2 added the prop.
4. **Add the behavior term.** `ambient_background.dart`: add, as the term immediately after `if (!_usesDefaultBackground) return false;` in `_shouldAnimate` (`:146-151`): `if (widget.isChatSurface) return false;`. (The static-frame render at `:94-97` already handles value 0 — no other change.) → TC-158-01 goes GREEN.
5. **Wire the two call sites.** `conversation_screen.dart:293`: add `isChatSurface: true,`. `group_conversation_screen.dart:194`: add `isChatSurface: true,`. → TC-158-00/04/05 go GREEN.
6. Rerun direct → preservation → named gates (below). Stop-if: TC-158-02 or the existing ambient TC-04/TC-05 go RED → the term is not additive/over-suppresses → fix the `_shouldAnimate` ordering, do not weaken the tests.
7. *(OPTIONAL leg, separate commit, design sign-off)* lower chrome sigmas + add TC-158-06. Skippable without blocking the core fix.

## Risks And Edge Cases
- **Semantic overload** — reusing `reduceMotion:true` from chat screens would (a) mislabel a perf fix as accessibility and (b) only fire on `isFeedSurface` (`:148`), never on chat. → pinned by using a **distinct** `isChatSurface` flag with its own term (TC-158-01).
- **Over-suppression** — gating in the widget default instead of per-call-site would freeze orbit/settings/identity/share/qr/posts/groups-list glows. → pinned by TC-158-02 (default false animates) and the const default `isChatSurface = false`.
- **Blur not fully cured while active** — stopping the idle glow removes the **idle-frame** re-blur (the `critic-2` steady-state claim); active scrolling/typing still re-blurs by design (other in-frame changes behind the chrome). Scope the claim to at-rest. (Document; not a test.)
- **Optional sigma leg is a visual change** → fenced into a separate slice with TC-158-06 so the perf gate (controller-not-animating) ships without waiting on design.

## Device/Relay Proof Profile
**host-only for closure.** The load-bearing logic (controller not animating + static frame) is fully host-coverable. The actual battery/heat/GPU-blur-cost claim is only observable on a device/profiler — **optional, deferred**: extend `registerConversationPerf` (defined in `integration_test/conversation_wired_performance_harness.dart:1060`, reached via the `CONVERSATION` `PERF_TARGET`) with an idle-frame raster-time assertion. **Caveat:** that harness early-returns when `Platform.isAndroid || Platform.isIOS` (`:1062-1066`), so it executes only on the desktop/flutter-tester host — `flutter test integration_test/performance_harness.dart --dart-define=PERF_TARGET=CONVERSATION` captures **host** evidence, NOT a physical-device/sim-target measurement; a true on-device idle-frame raster reading would require lifting that guard (extra harness work). Confirmatory, not gating.

## Acceptance Gates  (literal — copy/paste, with expected counts)
```bash
# RED (before production edits) — must FAIL for the documented reason
flutter test test/features/identity/presentation/widgets/ambient_background_test.dart --plain-name 'TC-158-01'
flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart --plain-name 'TC-158-04'
flutter test test/features/groups/presentation/group_conversation_screen_test.dart --plain-name 'TC-158-05'

# Direct GREEN (after fix)
flutter test test/features/identity/presentation/widgets/ambient_background_test.dart
flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart
flutter test test/features/groups/presentation/group_conversation_screen_test.dart

# Preservation sentinels (must stay green) — 156 baselines.
# NOTE: counts are full-gate run totals (a FLOOR), not test-array lengths; the new tests INCREMENT them — treat as ">=", not exact equality.
./scripts/run_test_gates.sh 1to1        # expect: >=1200 (156 floor) + new TC-158-04
./scripts/run_test_gates.sh feed        # expect: >=230 (156 floor) + new TC-158-00..03
./scripts/run_test_gates.sh groups      # expect: >=882 (156 floor) + new TC-158-05
./scripts/run_host_test_gates.sh feature-host-all   # expect: exit 0

# Hygiene
flutter analyze            # 0 new issues (5 pre-existing per 156 verdict)
git diff --check
```

## Known-Failure Interpretation
- Expected RED: TC-158-00/01/04/05 before the fix (TC-158-00 source-lock + TC-158-01 behavior + TC-158-04/05 wiring).
- TC-158-02/03 + existing ambient TC-04/05 are **preservation** — green before AND after; a RED here = over-suppression or non-additive term (BLOCKING, fix the code).
- **Preservation is verified-clean for the core fix:** no existing test in `conversation_screen_test.dart` or `group_conversation_screen_test.dart` asserts the ambient IS animating (zero `isAnimating`/controller-running assertions; all use bounded `pump(duration)` loops). So passing `isChatSurface: true` (static glow) does NOT red any existing chat-screen test — the only new GREENs are TC-158-00/01/04/05.
- Pre-existing dirty: 156's uncommitted `performance`-branch changes + `graphify-*` artifacts — do NOT revert.
- Pre-existing analyze: 5 known issues per 156 (mediaTapHandler closure + 4 group `withOpacity`) — not new.
- Scope drift (BLOCKING): any failure outside `ambient_background.dart` / the two chat screens / their three test files.

## Done Criteria
- [ ] RED (TC-158-00/01/04/05) added (after the surface-only prop, step 2), failed for the expected reason; TC-158-02/03 green.
- [ ] Each fix mutation-verified (re-red reverts named in the matrix).
- [ ] Direct GREEN + preservation (ambient TC-04/05, TC-158-02/03) + 1to1/feed/groups gates pass.
- [ ] No migration (none needed).
- [ ] flutter analyze 0 new; git diff --check clean; no Scope Guard violations.

## Scope Guard (hard "Do not")
- Do not change feed `isFeedSurface`/`reduceMotion` semantics (134/135 own them).
- Do not gate suppression at the widget default — `isChatSurface` defaults to `false`; only the two chat call sites opt in.
- Do not reuse `reduceMotion` for chat suppression (semantic overload + wrong surface).
- Do not add a `WidgetsBindingObserver`/idle-timer to `AmbientBackground` — gate by surface (static by construction).
- Do not touch the 156-shipped ambient work (`_motionDisabled`, RepaintBoundary) except to add the additive term.
- Do not pull in the off-screen tab `TickerMode`/active-tab pause — that is **163** (E-G/E-H).

## Accepted Differences / Intentionally Out Of Scope
- **Chrome sigma-lowering (TC-158-06)** — optional, design-gated, separate slice; the core perf win (controller not animating) ships without it.
- **Active-scroll/typing re-blur** — not addressed; only idle/at-rest is in scope (the `critic-2` steady-state claim).
- **Off-screen tab ambient pause** — owned by 163.
- **Device perf proof** — deferred (optional `CONVERSATION` PERF_TARGET idle-frame assertion; host-only unless the Android/iOS early-return is lifted).
- **Stale "ambient repeats forever" test comments** — `conversation_screen_test.dart` (e.g. `:161-163`, `:318-319`, `:2262`, `:2332`) and `integration_test/conversation_swipe_back_proof_test.dart` (`:88-93`) say the ConversationScreen ambient "repeats forever / never settles" and therefore use bounded `pump(duration)` instead of `pumpAndSettle`. After this fix the chat-surface ambient is **static**, so that *specific* rationale is stale. Comment-only cleanup is a **non-gating follow-up** (deliberately NOT in this slice, to keep the core diff to the three named test files). The corrected comment must NOT imply `pumpAndSettle` is now safe — bounded pumps are still required for other in-screen animations (letter-card entrance, composer fades) and for integration-binding idle scheduling; reword to "the chat-surface AMBIENT is static, but other animations remain", not "animation is now static (allowing pumpAndSettle)".

## Dependency Impact
- **163 (E-G/E-H)** also edits `ambient_background.dart` `_shouldAnimate` (adds an active-tab term + shell `TickerMode`). Land **158 before 163** so 163 extends a known `_shouldAnimate` shape (additive terms compose; do not collide). 158 is otherwise disjoint from all other plans.

## Reviewer Findings
Sufficiency self-check PASS: (a) every behavior (chat-static, non-chat-animates, reduce-motion-preserved, 1:1-wired, group-wired) has a named host test at the right tier; (b) each behavior-bearing edit (the `_shouldAnimate` term, the two call-site args) has a RED + named re-red mutation; (c) no migration/OS-boundary/crypto/relay path → host-only closure is correct; (d) all three test files are already in curated arrays (no registration gap); (e) the optional sigma leg is explicitly fenced as non-gating; (f) matrix has zero empty cells; (g) blind-spot sweep: durability (re-pump assertion), sibling-surface (TC-158-02/04/05), destructive (N/A justified), invariant-re-verify (TC-158-03 + kept TC-04/05) all addressed. Thin-evidence area: none — RED scaffold (`ambientControllers`, TC-04/05) already exists and is proven.

## Arbiter Decision
Structural blockers: none. Deferred details: optional sigma leg (design sign-off) + optional device perf proof. Accepted differences: idle-only scope; off-screen pause → 163. Implementation-ready; hand to execution. Land before 163.

## Second-Pass Review Incorporation (2026-06-24, 5-agent grounding wf)
Grounded 4 external review findings against HEAD before editing:
- **F1 (High, RED ordering) — INCORPORATED.** Confirmed: `AmbientBackground` has no `isChatSurface` field (`:28-35`), and neither chat-screen test imports `AmbientBackground`, so TC-158-04/05 cannot compile RED-first. Step-By-Step reordered to **prop-first (step 2) → tests+RED (step 3) → behavior term (step 4) → wiring (step 5)**; INV-RED-FIRST preserved (behavior + wiring still land after the tests). Matrix + catalog notes updated; the self-contradicting TC-158-04 "author after the prop" aside is now consistent with the steps.
- **F2 (Medium, source-leak guard) — INCORPORATED as core TC-158-00.** Confirmed 16 `AmbientBackground(` call sites; only `conversation_screen.dart:293` + `group_conversation_screen.dart:194` should opt in. Source-wiring-lock tests are idiomatic here (`orbit2_prototype_source_guard_test.dart`, `main_resume_group_upload_wiring_test.dart`). New TC-158-00 locks "exactly two opt-ins, zero leakage to the other 14 surfaces" — closes the Scope-Guard/INV-2 gap that the widget-default TC-158-02 alone did not (added as INV-2b).
- **F3 (Medium, stale device-proof note) — PARTIALLY INCORPORATED.** Fixed the wrong file attribution (`registerConversationPerf` lives in `conversation_wired_performance_harness.dart:1060`, not `performance_harness.dart`) and clarified the `Platform.isAndroid||isIOS` early-return (`:1062-1066`) → host-only execution. (The reviewer's "a sim run is a no-op" was itself imprecise; corrected to the accurate host-vs-device distinction.) Section stays optional/non-gating.
- **F4 (Low, stale test comments) — INCORPORATED + preservation win.** Confirmed the "ambient repeats forever" comments AND — critically — that NO existing chat-screen test asserts the ambient IS animating, so the core fix is preservation-safe (added to Known-Failure Interpretation). Stale comment cleanup logged as a non-gating follow-up with an explicit "do not encourage pumpAndSettle" caveat (Accepted Differences).
- Adversarial sweep also reworded the confusing "RED on HEAD because: PASSES" phrasing on the preservation tests (TC-158-02/03 → "GREEN on HEAD"), and flagged the acceptance-gate counts as floors (now annotated `>=`). Plan-163 ordering re-confirmed sound (158 adds the 4th `_shouldAnimate` clause; 163 extends to the 5th).

## Final Execution Verdict
Verdict: **SHIPPED host-green (2026-06-24)** | Files changed: `ambient_background.dart` (add `isChatSurface` prop + additive `_shouldAnimate` term), `conversation_screen.dart` + `group_conversation_screen.dart` (wire `isChatSurface: true`), **`group_conversation_wired.dart` (BEYOND-PLAN fix — see below)**; tests `ambient_background_test.dart` (+TC-158-00..03, `wrapAmbient(chatSurface:)`), `conversation_screen_test.dart` (+TC-158-04), `group_conversation_screen_test.dart` (+TC-158-05) | Tests run: RED checkpoint TC-158-00/01/04/05 FAILED for documented reasons + TC-158-02/03 PASSED → all GREEN after fix; **both mutations verified** (over-suppression `return false` → TC-05+TC-158-02 RED; non-additive drop-`_motionDisabled` → TC-04 RED, TC-158-01/03 stay GREEN); gates **feed +234**, **1to1 +1201**, **groups +883** (≥882 floor; was +880-3 pre-wired-fix), **feature-host-all exit 0** (0 failures); analyze **0 new** (9 pre-existing: 4 group `withOpacity`, 1 conv closure, 4 wired lints), `git diff --check` clean | Blocking: none | QA verdict: PASS host-only | Non-blocking follow-ups: (a) optional sigma-lowering leg (TC-158-06) — design sign-off, not taken; (b) optional device idle-frame raster proof — deferred; (c) stale "ambient repeats forever" comments in `conversation_screen_test.dart`/`conversation_swipe_back_proof_test.dart` — comment-only cleanup not taken (per plan's non-gating note).

### BEYOND-PLAN: `group_conversation_wired.dart` `scheduleFrame()` fix (blind-spot the plan missed)
The plan's "preservation verified-clean" claim only inspected `group_conversation_screen.dart` **(the screen widget test)** — it did NOT check `group_conversation_wired.dart`/`group_conversation_wired_test.dart`. Suppressing the group ambient broke **3 wired tests** (B5 self-removed read-only-in-place; retained self-removal banner-not-toast; current-group-removal route-exit). Root cause: `WidgetTester.pump()` only draws a frame when `hasScheduledFrame` is true; the `groupRemovedStream` listener defers via `WidgetsBinding.addPostFrameCallback` **without scheduling a frame**, and the always-on ambient `repeat()` ticker had been silently keeping `hasScheduledFrame` true forever. With the idle glow suppressed, on an otherwise-idle conversation the deferred `_handleCurrentGroupRemoved` (read-only flip / route pop) **never fired** (proven: even 200 fake-pumps did not flip it — so it is NOT a frame-count race; it is a missing-frame-schedule). This is a **real (if minor) production responsiveness regression**, not just a test artifact. Fix: call `WidgetsBinding.instance.scheduleFrame()` when registering that deferred handler so it runs promptly on an idle, glow-suppressed screen. The dissolve path was unaffected because it rides the message stream (list rebuild → self-schedules a frame); the 1:1 surface was unaffected (1to1 gate green). `group_conversation_wired_test.dart` now passes 163/163 WITH the suppression, **no assertion weakened**.
