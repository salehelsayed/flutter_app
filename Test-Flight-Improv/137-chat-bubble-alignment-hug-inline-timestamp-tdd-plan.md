# 137 - Chat Bubble Alignment, Content-Hug & Inline Timestamp (1:1 + Group)  (Bug)

Status: awaiting-review
Spec: free-text intent (no formal spec) — bug report + screenshot from the user, grounded in source in §Root Cause. `/spec-doc` could formalize it but is not required.

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-21 | Evidence Collector | letter_card.dart, message_run_grouping.dart, conversation_screen.dart, group_conversation_screen.dart, linkable_text.dart, letter_card_test.dart, letter_bubble_test.dart, letter_card_group/one_to_one_test.dart, run_test_gates.sh | All 3 bugs reproduce in `LetterCard._buildBubble`/`_buildBodyChildren`; fix is 100% inside `LetterCard` | verify→refute workflow |
| 2026-06-21 | Planner (verify→refute, 4 agents) | same + run_host_test_gates.sh | Claim1 CONFIRMED; Claim2 REFINED (TWO width drivers — header Row missed); Claim3 REFINED (shared body builder → must suppress footer time) | build matrix |
| 2026-06-21 | Reviewer (sufficiency) | this plan | matrix has zero empty cells; every fix mutation-verified; host-only closure | — |
| 2026-06-21 | Arbiter | this plan | structurally sufficient; host-only; no migration/device-proof | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-06-21 | RED tests added + TC-12 inverted | letter_card_test.dart | 7 RED for documented reasons (TC-A1/W1/W2/W3/T1/T2 + inverted TC-12); guards TC-T3/T4/P1 green on HEAD | RED-first confirmed | implement |
| 2026-06-21 | implementation | letter_card.dart | gutter removed; _buildHeader hug; _buildBodyChildren inlineFooterMeta + suffixSpans; footer restructure | scoped to 1 file | GREEN |
| 2026-06-21 | direct GREEN | letter_card_test.dart | 72/72 pass | reds now green | preservation |
| 2026-06-21 | DEVIATION A (custom span) | letter_card.dart | WidgetSpan U+FFFC placeholder broke find.text(body) in 41 screen tests → `_InlineMetaWidgetSpan` overrides computeToPlainText (no-op) | screen suites recovered | — |
| 2026-06-21 | DEVIATION B (full-row long-press) | letter_card.dart | hugging bubble shrank long-press target; 2 tests press row-center → moved GestureDetector(opaque) to wrap full-width Align when onLongPress!=null (matches swipe-to-reply) | screen suites green | — |
| 2026-06-21 | preservation GREEN | — | conversation_screen 65/65, group_conversation 61/61, feed letter widgets 41/41, message_run_grouping green | sentinels green | gates |
| 2026-06-21 | named gates | run_test_gates.sh (GROUP_TESTS +letter_card_test) | groups 494/494, 1to1 993/993 | gate green | mutation+QA |
| 2026-06-21 | mutation-verified | letter_card.dart (temp, reverted) | header-revert→TC-W1 red (TC-W2 green); footer-revert→TC-W2/T1/T2 red; gutter via RED-first | each fix necessary | QA |
| 2026-06-21 | QA (independent) | — | flutter analyze changed file = 0 issues; git diff --check clean; adversarial /workflow review | blocking: (pending review) | verdict |

## Source Of Truth
- Spec / intent: inline below (user bug report + screenshot) + §Root Cause
- Gate definitions: scripts/run_test_gates.sh (+ scripts/run_host_test_gates.sh for `*-host-all`)
- Discovery/registration: scripts/check_reliability_simulation_discovery.sh (N/A — host-only)
- Numbering / index: Test-Flight-Improv/00-INDEX.md (recent plans 130–136 are NOT indexed there; following that convention, no index entry)

## Session Classification
implementation-ready

## Exact Problem Statement

The redesigned chat bubble (`LetterCard` with `bubbleLayout: true`, introduced in 136) renders incorrectly in both the **1:1** and **group** conversation screens:

1. **Group — incoming continuation bubbles drift toward center.** When a sender (Alice) sends several consecutive messages, the *first* balloon (which shows the avatar+name) is flush-left, but every *continuation* balloon ("bbb", "vvv" in the screenshot) is indented ~42px to the right, so it looks shifted toward center. From the recipient's (Bob's) perspective **all** incoming messages must share the same left edge.
2. **Both surfaces — bubbles do not hug their text.** A short message ("bbb") renders in a bubble stretched to ~78% of the screen width, leaving a large empty gap. Bubbles should shrink-to-fit their content (text + timestamp).
3. **Both surfaces — the timestamp is always on its own line below the text.** It should sit on the **same line** as the message (trailing, WhatsApp/Signal style), and only wrap to a new line when the remaining width can't fit text + timestamp together.

1:1-specific restatement (same three mechanisms): (a) an outgoing message ("Bob sends") should wrap its text and stay right-aligned (it currently over-stretches); (b) the timestamp should be on the same line as the text.

What must improve: incoming bubbles flush-left on both surfaces; bubbles hug content (incoming first-in-run *with* header, incoming continuation, and outgoing); timestamp inline-trailing with last-text-line, wrapping only when there's no room.

What must stay unchanged (→ preserved-green sentinels): the legacy full-width `LetterCard` (`bubbleLayout: false`, used by Feed wrappers) render; the corner-radius stacking (TC-10); align direction (TC-08); the 0.78 max-width *cap* (TC-09); body-top-pad growth (TC-11); reactions tap (TC-15); continuation Semantics label (TC-16); status/transport/edited/quote/media/failed-action behavior; the long-press lifted-snapshot parity (TC-29).

## Root Cause (verify → refute confirmed)

All three live in `lib/features/conversation/presentation/widgets/letter_card.dart`. Both chat screens already pass correct run-grouping flags, and both reuse a single `buildLetterCard` closure for the live card **and** the long-press lifted snapshot (conversation_screen.dart:531/542/593; group_conversation_screen.dart:606/619/674), so a `LetterCard`-level fix covers every path with no screen changes.

- **RC-1 (group #1) — CONFIRMED.** `_buildBubble` wraps every incoming bubble in `Align(centerLeft)` (letter_card.dart:535-536). For continuation balloons it returns `Row[ SizedBox(width: 42), Flexible(constrained) ]` (letter_card.dart:548-557), while the first/headered balloon returns `constrained` directly (letter_card.dart:558). The avatar is painted *inside* the header (letter_card.dart:252-260), so the first bubble's left edge is at x≈0 while continuations start at x≈42 → visible center-drift. The 42px `SizedBox` is the only width literal in 40–46 in the whole widget (enumerated: 60,60,3,10,4,8,6,4,**42**,16,8,2,8), so the drift has exactly one source. Because 1:1 passes `showAvatar: false` unconditionally (conversation_screen.dart:545) and `messageRunChrome` only returns `showAvatar:true` for the first *group incoming* balloon (message_run_grouping.dart:62-69), **every** 1:1 incoming bubble also takes this gutter branch (indented with no avatar to justify it).

- **RC-2 (bug #2 width) — REFINED (TWO drivers).** Measured rendered bubble width at a 400px slot (cap = 312):
  - Footer `Row` (letter_card.dart:435) defaults to `mainAxisSize.max` and its first child is `Expanded(child: reactions-or-SizedBox.shrink())` (letter_card.dart:438) → forces full cap width. This drives **continuation/header-hidden** bubbles.
  - **Header `Row`** (letter_card.dart:255) *also* defaults to `mainAxisSize.max` and its sender-name child is `Expanded` (letter_card.dart:262) → forces full cap width whenever the header is visible. This drives **first-in-run/headered** bubbles and was missed by the initial hypothesis.
  - Evidence: HEAD short text "bbb" + header visible = **312.0** (cap); footer-fix-only + header visible = **310** (still not hugging); footer-fix + header hidden = **112.75** (hugs); both footer+header fixed + header visible = **145.25** (hugs name+text). So a footer-only fix is insufficient — both Rows must be bubble-scoped. The 0.78 `ConstrainedBox` cap (letter_card.dart:537-545) is correct and stays.

- **RC-3 (bug #3 / 1:1 #2 inline time) — REFINED (shared body builder).** The timestamp is a child of the footer `Padding`+`Row` (letter_card.dart:433-483), which is a **separate** `Column` element below the body-text `Padding` (letter_card.dart:334-363) → always its own line. `LinkableText` already exposes `suffixSpans`, appended *after* the body spans into `Text.rich(TextSpan(children:[...prefix, ...body, ...suffix]))` (linkable_text.dart:122-133); a trailing `WidgetSpan` is laid out inline by the paragraph engine and wraps **atomically** to a new line only when the last line is full — exactly the requested behavior. Caveats that make this REFINED: `_buildBodyChildren` is **shared** by the bubble (letter_card.dart:515) and legacy (letter_card.dart:235) paths and emits the footer time *unconditionally*, so the fix must thread a flag that (a) adds the inline suffix **and** (b) suppresses the footer time in bubble mode (else the time double-renders); the `isDeleted`/empty-text body uses a plain `Text` (no `suffixSpans`) so those branches keep the footer time; and edited/status must fold into the *same* `WidgetSpan` so they stay adjacent to the time on the wrapped unit.

Refuted / do-NOT-re-introduce:
- "Footer `Expanded` is the *only* width driver" — **REFUTED by measurement**; the header `Row`+`Expanded` is an independent driver for headered bubbles. Any fix that touches only the footer leaves group first-in-run bubbles full-width.
- "Removing the footer `Expanded` alone makes it hug" — **REFUTED**; the `Row` also defaults to `mainAxisSize.max`, so it must additionally be `mainAxisSize.min` (and Expanded→Flexible).
- "Legacy footer right-align/Expanded is locked by existing tests" — **REFUTED**; legacy tests only assert "shares a Row"/"in a Row" (no Expanded/dx assertion), so a naive *shared* edit would silently break the legacy full-width card with no RED → the fix MUST be bubble-scoped and a legacy-width preservation test MUST be added.
- "A `WidgetSpan` timestamp can't wrap when the line is full" — **REFUTED**; it wraps as an atomic box (the intended behavior).
- It is NOT a build-skew artifact: the mechanisms are present in HEAD source and measured live.

## Real Scope

In scope (single file): `lib/features/conversation/presentation/widgets/letter_card.dart`
- `_buildBubble`: remove the `if (isIncoming && !showAvatar)` gutter branch → always `return constrained;`.
- Bubble-scope `_buildHeader` (new `bool hug`): `mainAxisSize.min` + sender-name `Expanded`→`Flexible` when hugging.
- Bubble-scope `_buildBodyChildren` (new flag, e.g. `bool inlineFooterMeta`): when true & `!isDeleted` & `text.isNotEmpty`, render time(+edited+status) as a trailing `WidgetSpan` via `LinkableText.suffixSpans`, and **suppress** the time/edited/status segment of the footer `Row`; make the bubble footer `mainAxisSize.min` and keep only a hugging reactions `Wrap` (drop the footer entirely when reactions are empty). Keep `isDeleted`/empty-text/media-only on the existing footer-time path.
- Keep the 0.78 `ConstrainedBox` cap; keep `Align` direction; keep corner-radius stacking.

Test changes: extend `test/features/conversation/presentation/widgets/letter_card_test.dart`; **invert TC-12** (gutter → no-gutter); add `letter_card_test.dart` to `GROUP_TESTS` (manual registration).

Out of scope (owning work):
- The Feed preview widgets (`LetterBubble`, `LetterCardGroup/OneToOne/System` in `lib/features/feed/presentation/widgets/`) — distinct classes, no `bubbleLayout`; their tests are preservation sentinels only.
- Reaction *placement* redesign, swipe-to-quote, context-overlay layout — unrelated; not touched.
- Any DB / transport / crypto / notification behavior — none involved.

## Files To Inspect Next
Production (entry/use-case, models, helpers):
- `lib/features/conversation/presentation/widgets/letter_card.dart` — `_buildBubble` (487-562), `_buildHeader` (251-288), `_buildBodyChildren` (293-485), `_bubbleBorderRadius` (569-591) [the ONLY edited file]
- `lib/shared/widgets/linkable_text.dart` — `suffixSpans` assembly (122-133) [read-only; consumed, not edited]
- `lib/features/conversation/domain/utils/message_run_grouping.dart` — `messageRunChrome` (62-69) [read-only; explains showAvatar policy]
Dependency-only context (NO change — confirm flags already correct):
- `lib/features/conversation/presentation/screens/conversation_screen.dart:531-598`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart:606-679`
Direct tests:
- `test/features/conversation/presentation/widgets/letter_card_test.dart` (extend bubble-layout group; invert TC-12)

## Existing Tests Covering This Area
- `letter_card_test.dart` "bubble layout (136 Phase 2)" group — TC-08 align, TC-09 max-width *cap*, TC-10 corners, TC-11 body-top-pad, **TC-12 gutter (MUST INVERT)**, TC-14 longpress, TC-15 reactionTap, TC-16 semantics (exists; mostly preservation).
- `letter_card_test.dart` legacy footer tests (lines 574-628) + TC-13 preservation (1381) — exist; preservation sentinels for `bubbleLayout:false`.
- `message_run_grouping_test.dart` — run-boundary logic (exists; unaffected, preservation).
- `letter_bubble_test.dart`, `letter_card_group_test.dart`, `letter_card_one_to_one_test.dart`, `letter_card_system_test.dart` — FEED widgets (exist; preservation only — different classes).
- `conversation_screen_test.dart` / `group_conversation_screen_test.dart` — screen-level (exist; preservation).

Missing coverage gaps (this plan fills):
- No test asserts incoming continuation bubbles are flush-left (TC-12 asserts the *opposite*).
- No test asserts the **rendered** bubble width hugs content (TC-09 only checks the constraint value, passes on HEAD).
- No test asserts the timestamp shares the text's line (inline) in bubble mode.
- No test guards the legacy full-width card *width* against bubble-scoping leakage.

Already in curated family arrays? `letter_card_test.dart` → `ONE_TO_ONE_TESTS` (run_test_gates.sh:61) only. `message_run_grouping_test.dart` → `ONE_TO_ONE_TESTS:60` + `GROUP_TESTS:126`. The feed letter_* tests → `FEED_TESTS:81-84`. → **Add `letter_card_test.dart` to `GROUP_TESTS`** so the group gate exercises the group-specific bubble fixes.

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

All in `test/features/conversation/presentation/widgets/letter_card_test.dart`. Use the existing `buildBubble(...)` helper (it mounts `LetterCard(bubbleLayout:true)` inside `Center > SizedBox(width) > SingleChildScrollView`). Add a small helper to read the painted bubble `Container` width via its `RenderBox`, and to get `tester.getTopLeft(find.byType(ClipRRect))`. Assert generous bounds (font metrics vary), never exact pixels.

1. `letter_card_test.dart`::`TC-A1 incoming first and continuation balloons share the same left edge`
   - Tier: widget
   - Shape/setup: pump first balloon (`isIncoming:true, showAvatar:true, showSenderName:true, isFirstInGroup:true, isLastInGroup:false, text:'same text'`); record `getTopLeft(ClipRRect).dx`. Pump continuation (`showAvatar:false, showSenderName:false, isFirstInGroup:false`) with **identical text/width**; record its `dx`.
   - RED on HEAD because: continuation `dx ≈ first.dx + 42` (gutter Row), so `closeTo(first.dx, 1.0)` fails.
   - GREEN after fix asserts: `continuation.dx` is `closeTo(first.dx, 1.0)` (both flush-left).
   - Mutation that re-reds: re-add the `if (isIncoming && !showAvatar)` `SizedBox(width:42)` Row → RED.
   - Note: scope `find.byType(ClipRRect)` to the LetterCard's outer bubble (`.first`; a plain-text bubble has one); use identical text so constrained widths match.

2. `letter_card_test.dart`::`TC-12 (INVERTED) continuation incoming balloon has NO ~42px leading gutter`
   - Tier: widget
   - Shape/setup: same continuation balloon as the existing TC-12 (`isIncoming:true, showAvatar:false, isFirstInGroup:false, isLastInGroup:true`).
   - RED on HEAD because: the existing assertion `expect(hasGutter, isTrue)` is the *current* behavior — after inverting to `expect(hasGutter, isFalse)` it fails on HEAD (a 40–46px `SizedBox` is present).
   - GREEN after fix asserts: no `SizedBox` with `40 <= width <= 46` exists.
   - Mutation that re-reds: re-add the gutter → RED.

3. `letter_card_test.dart`::`TC-W1 group first-in-run headered bubble hugs short text`
   - Tier: widget
   - Shape/setup: `buildBubble(width:400, isIncoming:true, showAvatar:true, showSenderName:true, text:'bbb')`; read painted bubble Container width.
   - RED on HEAD because: header `Row`+`Expanded` forces width = 312 (cap) → `lessThan(200)` fails.
   - GREEN after fix asserts: width `< 200` (hugs name+text; measured ~145).
   - Mutation that re-reds: revert header `mainAxisSize.min`/name-`Flexible` (back to max+Expanded) → RED.
   - Distinct driver note: this case fails on HEAD even *with* a footer-only fix — it locks the **header** driver specifically.

4. `letter_card_test.dart`::`TC-W2 continuation/1:1 incoming bubble hugs short text`
   - Tier: widget
   - Shape/setup: `buildBubble(width:400, isIncoming:true, showAvatar:false, showSenderName:false, text:'bbb')`; read painted width.
   - RED on HEAD because: footer `Row`+`Expanded` forces 312 → `lessThan(200)` fails.
   - GREEN after fix asserts: width `< 200` (measured ~112).
   - Mutation that re-reds: revert footer `mainAxisSize.min`/re-add footer `Expanded`/keep footer time → RED.

5. `letter_card_test.dart`::`TC-W3 outgoing 1:1 bubble hugs short text and stays right-aligned`
   - Tier: widget
   - Shape/setup: `buildBubble(width:400, isIncoming:false, showAvatar:false, showSenderName:false, text:'ok', status:'sent')`; read painted width; read `bubbleAlign(tester).alignment`.
   - RED on HEAD because: width = 312 → `lessThan(200)` fails (alignment already `centerRight`).
   - GREEN after fix asserts: width `< 200` AND `alignment == Alignment.centerRight`.
   - Mutation that re-reds: revert footer/header hug → RED on width.

6. `letter_card_test.dart`::`TC-T1 timestamp renders inline within the body text (incoming continuation)`
   - Tier: widget
   - Shape/setup: `buildBubble(isIncoming:true, showAvatar:false, showSenderName:false, text:'bbb', time:'9:57 AM')`.
   - RED on HEAD because: `find.text('9:57 AM')` resolves to a standalone footer `Text` that is **not** a descendant of the body `LinkableText`'s `RichText`; assert `find.descendant(of: find.byType(LinkableText), matching: find.text('9:57 AM'))` is `findsOneWidget` → fails on HEAD.
   - GREEN after fix asserts: the time `Text` is a descendant of the body `LinkableText` (inside the trailing `WidgetSpan`) AND `find.text('9:57 AM')` is `findsOneWidget` (no double-render).
   - Mutation that re-reds: revert the `suffixSpans` wiring / un-suppress the footer time → RED (not-descendant, or findsNWidgets(2)).

7. `letter_card_test.dart`::`TC-T2 outgoing inline timestamp keeps the status tick adjacent in the body`
   - Tier: widget
   - Shape/setup: `buildBubble(isIncoming:false, showAvatar:false, showSenderName:false, text:'ok', time:'9:57 AM', status:'sent')`.
   - RED on HEAD because: the status icon + time live in the separate footer Row, not inside the body `RichText`; assert both the time `Text` and `Icon(Icons.done_rounded)` are descendants of the body `LinkableText` → fails on HEAD.
   - GREEN after fix asserts: time `Text` and the status `Icon` are both descendants of the body `LinkableText` (folded into one trailing `WidgetSpan`).
   - Mutation that re-reds: move status/time back to the footer Row → RED.

## Guard / Preservation Test Catalog  (GREEN-stays-GREEN; mutation-verified against the FIX, not HEAD)

8. `letter_card_test.dart`::`TC-T3 long text wraps the inline timestamp without overflow`
   - Tier: widget. Setup: `buildBubble(width:240, isIncoming:true, showAvatar:false, text:<long single word>, time:'9:57 AM')`.
   - RED reason on HEAD: N/A — guard. (HEAD also renders without overflow because the time is a separate row.)
   - GREEN asserts: `tester.takeException()` is null AND `find.text('9:57 AM')` is `findsOneWidget`.
   - Mutation that re-reds: implement the inline time as a non-wrapping `Row([text, time])` instead of a `WidgetSpan` suffix → RenderFlex overflow → RED. (Locks "wraps when no room".)

9. `letter_card_test.dart`::`TC-T4 deleted/empty-text bubble keeps the footer timestamp`
   - Tier: widget. Setup: `buildBubble(isIncoming:true, showAvatar:false, isDeleted:true, text:'This message was deleted', time:'9:57 AM')`.
   - RED reason on HEAD: N/A — guard for the RC-3 caveat (isDeleted uses plain `Text`, no `suffixSpans`).
   - GREEN asserts: `find.text('9:57 AM')` is `findsOneWidget` (still rendered via footer path), no exception.
   - Mutation that re-reds: route the deleted branch through the inline path (which drops the time, since plain `Text` has no `suffixSpans`) → time missing → RED.

10. `letter_card_test.dart`::`TC-P1 (NEW preservation) legacy full-width card still fills width & keeps footer time`
    - Tier: widget. Setup: `buildTestWidget(isIncoming:true, text:'bbb')` (default `bubbleLayout:false`) inside a fixed-width slot; read the painted card width and the footer time location.
    - RED reason on HEAD: N/A — preservation; would RED if bubble-scoping leaks into legacy.
    - GREEN asserts: legacy card width fills (≈ slot width, `greaterThan(0.8 * slotWidth)`) AND the time `Text` is NOT a descendant of the body `LinkableText` (still in the footer Row).
    - Mutation that re-reds: apply `mainAxisSize.min`/`Flexible`/inline-time **unconditionally** (not bubble-scoped) → legacy card shrinks / time goes inline → RED.

## Test Coverage Matrix  (ZERO empty cells in tier / mutation / gate / registration)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| RC-1 group #1 flush-left | UI geometry | widget | letter_card_test.dart::TC-A1 | continuation.dx = first.dx+42 | re-add 42px gutter Row | `flutter test test/features/conversation/presentation/widgets/letter_card_test.dart` | AUTO (glob, test/features/**) |
| RC-1 (per-position lock) | UI structure | widget | letter_card_test.dart::TC-12 (inverted) | existing asserts gutter present | re-add gutter | same | AUTO (glob) |
| RC-2 width (header driver) | UI render width | widget | letter_card_test.dart::TC-W1 | header Row+Expanded → 312 | revert header min/Flexible | same | AUTO (glob) |
| RC-2 width (footer driver) | UI render width | widget | letter_card_test.dart::TC-W2 | footer Row+Expanded → 312 | revert footer min / re-add Expanded | same | AUTO (glob) |
| RC-2 / 1:1 outgoing hug | UI render width+align | widget | letter_card_test.dart::TC-W3 | outgoing width → 312 | revert footer/header hug | same | AUTO (glob) |
| RC-3 inline time (incoming) | UI structure | widget | letter_card_test.dart::TC-T1 | time is footer Text, not in body RichText | revert suffixSpans / un-suppress footer | same | AUTO (glob) |
| RC-3 inline time (outgoing+status) | UI structure | widget | letter_card_test.dart::TC-T2 | time+status in footer, not body | move status/time back to footer | same | AUTO (glob) |
| RC-3 wrap-when-no-room | UI layout robustness | widget (guard) | letter_card_test.dart::TC-T3 | N/A (guard) | non-wrapping Row impl → overflow | same | AUTO (glob) |
| RC-3 deleted/empty footer keep | UI branch guard | widget (guard) | letter_card_test.dart::TC-T4 | N/A (guard) | route deleted via inline → time dropped | same | AUTO (glob) |
| Legacy preservation | UI scoping guard | widget (preservation) | letter_card_test.dart::TC-P1 | N/A (preservation) | apply hug/inline unconditionally → legacy shrinks | `./scripts/run_test_gates.sh 1to1` | AUTO (glob) + already in ONE_TO_ONE_TESTS:61 |
| Group-surface coverage | curated gate | widget | letter_card_test.dart (whole file) | (covered by rows above) | (n/a) | `./scripts/run_test_gates.sh groups` | **add letter_card_test.dart to GROUP_TESTS array (run_test_gates.sh ~line 128)** |

## Invariants (locked by tests)
- INV-1: All incoming bubble balloons (first, continuation, 1:1) share the same left edge → TC-A1 + TC-12(inverted).
- INV-2: A short-text bubble hugs its content on every code path — headered (TC-W1), continuation (TC-W2), outgoing (TC-W3).
- INV-3: Timestamp (+edited+status) is inline-trailing the body text in bubble mode (TC-T1, TC-T2), wraps atomically when no room (TC-T3), and never double-renders (TC-T1 findsOneWidget).
- INV-4: `isDeleted`/empty-text bubbles keep the footer timestamp (TC-T4).
- INV-5: The legacy `bubbleLayout:false` card is byte-for-byte unchanged in width + footer (TC-P1, TC-13).
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every RED row above.

## Step-By-Step Implementation Plan
1. Snapshot dirty tree: `git status --short` (record the pre-existing `new-feed` modifications so nothing unrelated is reverted).
2. Add RED tests TC-A1, TC-W1, TC-W2, TC-W3, TC-T1, TC-T2 + invert TC-12; add guards TC-T3, TC-T4 and preservation TC-P1. Run focused → confirm each RED fails for its documented reason (width=312, dx delta=42, time-not-in-body).
3. `_buildBubble` (letter_card.dart:537-561): delete the `if (isIncoming && !showAvatar)` gutter block; always `return constrained;`. Keep `Align` + `ConstrainedBox(0.78)`.
4. `_buildHeader` (letter_card.dart:251-288): add `{bool hug = false}`; when `hug`, set the `Row` `mainAxisSize: MainAxisSize.min` and change the sender-name `Expanded`→`Flexible`. Call with `hug: true` from `_buildBubble` (letter_card.dart:514); legacy caller (letter_card.dart:234) keeps `hug:false`.
5. `_buildBodyChildren` (letter_card.dart:293-485): add `{bool inlineFooterMeta = false}`. When `true` & `!isDeleted` & `text.isNotEmpty`: (a) build a metadata `WidgetSpan` (alignment baseline/middle) wrapping a tiny `Row(mainAxisSize.min, [SizedBox(6), Text(time,11px,textMuted), if(isEdited) edited Text, if(!isIncoming && status!=null) status Icon])`; pass it as `LinkableText.suffixSpans`; (b) **omit** the time/edited/status segment from the footer `Row`; (c) make the footer `Row` `mainAxisSize.min` and keep only the reactions `Wrap`, dropping the whole footer `Padding` when reactions are empty. Pass `inlineFooterMeta: true` from `_buildBubble` (letter_card.dart:515); legacy caller keeps `false`.
   - Stop-if: the `WidgetSpan` time doesn't wrap / overflows at narrow width (TC-T3) → re-check `PlaceholderAlignment`/that the suffix is a single atomic span, do NOT wrap it in a fixed `Row` sibling. Replan, don't hack.
6. Rerun direct REDs → GREEN; then preservation (legacy + feed + screens) → GREEN; then named gates.
7. Add `letter_card_test.dart` to `GROUP_TESTS` (run_test_gates.sh ~line 128); run the group gate.

## Risks And Edge Cases
- **Legacy leakage** (shared `_buildHeader`/`_buildBodyChildren`): a min/Flexible/inline change applied unconditionally silently breaks the full-width Feed card with no native RED → pinned by TC-P1 (+ TC-13).
- **Double-render of timestamp** if the footer time isn't suppressed in bubble mode → pinned by TC-T1 `findsOneWidget`.
- **isDeleted/empty-text/media-only** can't carry `suffixSpans` (plain `Text`/no body text) → keep footer time → pinned by TC-T4.
- **RTL**: the `WidgetSpan` inherits `detectTextDirection(text)`; an LTR clock in an RTL bubble sits at the logical line end (expected WhatsApp behavior). Do NOT assert exact x-offset in tests (flaky) — assert tree structure.
- **Reactions** stay a footer `Wrap` (hugging), not inline → TC-15 (tap) stays green; verify a reactions+inline-time bubble still hugs.
- **Pixel-width flakiness**: assert generous bounds (`< 200`, `closeTo(...,1.0)`), never exact font metrics.
- **ClipRRect ambiguity**: media bubbles nest ClipRRects — use plain-text bubbles for geometry tests and `.first`/LetterCard-scoped finders.

## Device/Relay Proof Profile
host-only for closure. These are pure widget-layout bugs (no OS boundary, crypto, DB, transport, migration), fully determinable in `flutter test` widget tests. No `/sims`, no device-proof, no migration.
Optional (not a gate): visual confirmation on a sim/device of the group screenshot scenario (Alice 3 consecutive messages → all flush-left, hugging, inline time). Deferred device work: none required.

## Acceptance Gates  (literal — copy/paste, with expected counts)
```bash
# Dirty-tree snapshot (record; do not revert unrelated new-feed changes)
git status --short

# RED (before production edits) — must FAIL for the documented reason
flutter test test/features/conversation/presentation/widgets/letter_card_test.dart \
  --plain-name 'TC-A1'        # continuation.dx == first.dx fails (delta 42)
flutter test test/features/conversation/presentation/widgets/letter_card_test.dart \
  --plain-name 'hugs short text'   # rendered width 312 > 200 → fails (TC-W1/W2/W3)
flutter test test/features/conversation/presentation/widgets/letter_card_test.dart \
  --plain-name 'inline'       # time not a descendant of body LinkableText → fails (TC-T1/T2)

# Direct GREEN (after fix) — the whole LetterCard suite
flutter test test/features/conversation/presentation/widgets/letter_card_test.dart
# expect: all bubble-layout + legacy + new TC-A1/W1/W2/W3/T1/T2/T3/T4/P1 pass

# Preservation sentinels (must stay green)
flutter test test/features/feed/presentation/widgets/letter_bubble_test.dart \
             test/features/feed/presentation/widgets/letter_card_group_test.dart \
             test/features/feed/presentation/widgets/letter_card_one_to_one_test.dart \
             test/features/feed/presentation/widgets/letter_card_system_test.dart
flutter test test/features/conversation/domain/utils/message_run_grouping_test.dart

# Named per-surface gates for the touched subsystem
./scripts/run_test_gates.sh 1to1            # letter_card_test.dart already listed (line 61)
./scripts/run_test_gates.sh groups          # AFTER adding letter_card_test.dart to GROUP_TESTS

# Host-all auto-glob sweep (new tests are picked up with no array edit)
./scripts/run_host_test_gates.sh feature-host-all

# Hygiene
flutter analyze            # 0 new issues
git diff --check
```

## Known-Failure Interpretation
- Expected RED (pre-fix): TC-A1, TC-W1, TC-W2, TC-W3, TC-T1, TC-T2, and inverted TC-12 — for the documented reasons (delta 42, width 312, time not in body).
- Pre-existing dirty: the `new-feed` branch has many unrelated modified/deleted files (feed redesign, graphify-arch outputs) — record in the dirty-tree snapshot; do NOT revert.
- Environment blocker (NOT product): none (host-only).
- Scope drift (BLOCKING): any failure outside `letter_card.dart` + `letter_card_test.dart` + the one `GROUP_TESTS` line; any change to the legacy/Feed render; any regression in screen/feed/run-grouping suites.

## Done Criteria
- [x] RED added first (TC-A1/W1/W2/W3/T1/T2 + inverted TC-12), failed for the expected reason (delta-42 / width-312 / time-not-in-body).
- [x] Mutation-verified: each fix has a named re-red revert — gutter (RED-first), header `hug:false`→TC-W1 red, footer `inlineFooterMeta:false`→TC-W2/T1/T2 red, reacted-hug `Align`→TC-W4 red(312).
- [x] Direct GREEN (letter_card 74/74) + preservation sentinels (legacy TC-13/TC-P1, feed 41/41, run-grouping, screens 65/65 + 61/61) + named gates (1to1 993/993, groups 496/496) pass.
- [x] No migration (none needed); host-only closure (no device-proof).
- [x] `letter_card_test.dart` added to `GROUP_TESTS`; verified present in a `groups` gate run (496 incl. its 74) + completeness-check 936/936 PASS.
- [x] `flutter analyze` 0 new on the changed file; `git diff --check` clean; no Scope Guard violations (session edits confined to letter_card.dart + letter_card_test.dart + 1 GROUP_TESTS line).

## Scope Guard (hard "Do not")
- Do not edit the Feed widgets (`LetterBubble`, `LetterCard{Group,OneToOne,System}`) — different classes; Feed owns them.
- Do not change the legacy `bubbleLayout:false` render path (header/footer/Expanded/width) — guarded by TC-13 + TC-P1.
- Do not modify the conversation/group screens (flags already correct) or `LinkableText` (consume `suffixSpans`, don't change it).
- Do not move reactions inline; do not touch corner-radius stacking, align direction, the 0.78 cap, status/transport/quote/media/failed-action logic.
- Do not introduce a feature flag — this is a straight bug fix with no rollout risk.

## Accepted Differences / Intentionally Out Of Scope
- Reversing 136's "indent continuation under the avatar" group design is **intentional** (user-requested flush-left); TC-12 is deliberately inverted, not accidentally broken.
- True last-line-trailing for *multi-line* text relies on the paragraph engine wrapping the atomic `WidgetSpan`; we assert tree structure + no-overflow, not pixel-exact last-line placement (golden tests are font-flaky) — acceptable.
- Screen-level integration tests for the run scenario are not added (the bug is purely in `LetterCard`; both screens reuse the same `buildLetterCard` for live + lifted snapshot, so widget-tier coverage is sufficient). Existing screen suites remain preservation sentinels.

## Dependency Impact
- None downstream. The long-press lifted snapshot (TC-29) inherits the fix automatically (same `buildLetterCard` closure) and must stay green.

## Reviewer Findings
Sufficiency: every user-reported bug maps to ≥1 mutation-verified RED at the widget tier; the REFINED two-driver width root cause is locked by TWO independent REDs (TC-W1 header, TC-W2 footer) so a footer-only fix cannot pass; legacy leakage (untested on HEAD) is closed by the new TC-P1 preservation test with a concrete re-red mutation; inline-time double-render and isDeleted regressions are guarded (TC-T1 findsOneWidget, TC-T4). Matrix has zero empty cells. Host-only closure is correct (no boundary/crypto/DB). One manual registration step (GROUP_TESTS) is named and gate-verifiable.

## Arbiter Decision
Structural blockers: none. Deferred details: optional on-device visual confirmation (not a gate). Accepted differences: 136 group-indent reversal (intended); pixel-exact multi-line trailing not asserted. Verdict: structurally sufficient — hand off to execution.

## Final Execution Verdict
Verdict: **SHIPPED (host-green)** | Files changed (this session): lib/features/conversation/presentation/widgets/letter_card.dart, test/features/conversation/presentation/widgets/letter_card_test.dart, scripts/run_test_gates.sh (GROUP_TESTS +1 line) | Tests run (+counts): letter_card 74/74, conversation_screen 65/65, group_conversation 61/61, feed letter widgets 41/41, message_run_grouping green, groups gate 496/496, 1to1 gate 993/993, completeness-check 936/936; flutter analyze (changed file) 0 issues; git diff --check clean | Blocking: none | QA verdict: 4-dim adversarial /workflow review → SHIP-WITH-FOLLOWUPS; both plan deviations verified sound; the one MEDIUM (reacted bubbles didn't hug) was FIXED in-session + locked by TC-W4; two LOW coverage holes closed (TC-T5 empty-text footer time, TC-T2 inline status semantics).

### Plan deviations (each made to AVOID regressing ~41 screen preservation tests; both kept inside letter_card.dart)
- **`_InlineMetaWidgetSpan`** (custom `WidgetSpan`, `computeToPlainText` no-op): the plan's bare `suffixSpans`/`WidgetSpan` injects a U+FFFC placeholder into the body paragraph's `toPlainText()`, which broke `find.text(exactBody)` across ~41 conversation/group screen tests (and would degrade screen-reader text extraction). Suppressing the placeholder keeps the body matchable by its exact string; the inline time/status remain real descendant widgets (so TC-T1/T2 + a11y still hold). No clean alternative exists — proper text wrapping requires real body spans + an inline span, which always pollutes `toPlainText`.
- **Full-row long-press** (`GestureDetector(opaque)` wrapping the full-width `Align`, only when `onLongPress != null`): hugging shrank the bubble, so a bubble-scoped long-press became a tiny target and 2 screen tests that long-press the keyed full-width row center stopped opening the overlay. The full-row gesture matches the existing full-row swipe-to-reply (`SwipeToQuoteBubble`) hit area; deleted rows / lifted snapshot (onLongPress null) return the bare `Align` unchanged (TC-29 parity).

Non-blocking follow-ups (owner): optional on-device visual check (Alice 3 consecutive msgs → flush-left + hug + inline time).
