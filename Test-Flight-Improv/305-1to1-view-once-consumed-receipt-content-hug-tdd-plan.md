# 305 - 1:1 Consumed View-Once Receipt Content-Hug Bubble

Status: completed
Type: Modification
Spec: free-text intent with reference screenshot — user request 2026-07-30
Classification: implementation-ready
Closure tier: host
Review: `$tdd-review` completed with in-place corrections (2026-07-30)

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-30 | Evidence Collector | Plan 304 implementation, `DirectPrivateMediaTerminalPlaceholder`, `ConversationScreen`, `LetterCard`, owning widget tests, and `ONE_TO_ONE_TESTS` | The compact receipt still has two expansion drivers: its own infinite width and the empty-text footer row inside `LetterCard` | Define a receipt-only content-hug seam |
| 2026-07-30 | Planner | Current source, Graphify TDD context, tier matrix, plan template, sufficiency checklist, and five passing preservation probes | Use a default-off `LetterCard` content-hug input only for direct `viewOnce + consumed`; retain the footer and every sibling layout | Hand off four-row host contract |
| 2026-07-30 | TDD Reviewer | Plan 305, current source/tests/gates, Graphify review context, and one fresh counterexample audit | The keyed summary `Row` is tightly expanded on HEAD, so both proposed content-width REDs were vacuous; the broad-opt-in mutation also did not reliably alter fallback terminal widths | Measure the icon-to-label visual span, stage the new API without rendering behavior, and assert exact caller opt-in scope |

## Problem And Evidence

- Behavior to improve: the consumed direct view-once receipt now has the right
  eye-off + localized `Photo` content, but its chat bubble still expands to the
  normal 78% bubble cap instead of hugging that short content like a short text
  message.
- Impact: the oversized empty area makes a deliberately minimal receipt look
  like a large media card and visually outweighs the icon and word it contains.
- Confirmed current gap:
  - `DirectPrivateMediaTerminalPlaceholder.build` at
    `lib/features/conversation/presentation/screens/direct_private_media_viewer.dart:398-419`
    gives the consumed view-once container `width: double.infinity`, even
    though its inner `Row` already uses `MainAxisSize.min`.
  - Removing that width alone is insufficient in the real conversation row.
    A consumed attachment has empty message text, so
    `LetterCard._buildBodyChildren` takes the standalone-footer path at
    `lib/features/conversation/presentation/widgets/letter_card.dart:600-665`.
    Its default-max `Row` plus `Expanded` spacer consumes the available width
    so the timestamp/status can align right.
  - `LetterCard._buildBubble` at
    `lib/features/conversation/presentation/widgets/letter_card.dart:808-826`
    supplies a maximum width, not a required width. A narrowly intrinsic-sized
    child can therefore hug content while retaining the existing 78% safety
    cap.
  - The sole real caller builds both the live row and lifted snapshot through
    `buildLetterCard` at
    `lib/features/conversation/presentation/screens/conversation_screen.dart:1289-1330`;
    it retains the exact `privateMediaMode` and terminal state needed for a
    truthful receipt-only opt-in.
- Existing coverage:
  - The passing Plan-304 test
    `direct_private_media_viewer_test.dart::consumed view-once terminal is
    eye-off plus localized Photo only` proves the localized two-element row,
    semantics, RTL order, text scaling, and absence of forbidden content, but
    has no width assertion.
  - The passing Plan-304 production test
    `direct_private_media_card_test.dart::consumed view-once receipt is minimal
    in live and lifted cards while outer reply and delete remain reachable`
    proves the real caller and lifted-card path, but only checks containment
    and actions.
  - Passing baselines
    `letter_card_test.dart::TC-W2 continuation incoming bubble hugs short text`,
    `::TC-W3 outgoing bubble hugs short text and stays right-aligned`, and
    `::constrains bubble max width to ~78% of available width` confirm that
    ordinary content already hugs up to the cap. The passing
    `::TC-T5 empty-text bubble keeps the footer timestamp` confirms that
    empty/media-only rows deliberately retain their standalone footer.
- Missing coverage: no test relates the terminal/container or decorated bubble
  width to the actual eye-off + localized-word content span, proves the
  behavior in both message directions, or rejects accidentally applying the
  new intrinsic sizing to every empty/private bubble.
- Confirmed findings:
  - This is a layout projection only; no lifecycle, attachment, cleanup,
    persistence, wire, or localization data is needed.
  - Timestamp and outgoing/incoming status glyphs are part of the bubble's
    existing footer and must remain visible; the final bubble may therefore be
    slightly wider than the icon/text row.
  - The keyed summary is not an intrinsic-content measurement on HEAD. It is a
    `Row` directly under the full-width terminal container and receives tight
    width after the container's padding. Consequently,
    `terminalWidth == summaryRowWidth + 24` and
    `bodyWidth <= summaryRowWidth + 48` can already pass before the fix.
  - Giving every private terminal the proposed `LetterCard` opt-in is not
    reliably caught by sibling width comparisons because fallback terminal
    children retain their own `width: double.infinity`. Exact caller scoping
    must therefore also be asserted at the default-off `LetterCard` seam.
- Refuted findings:
  - “Delete only `width: double.infinity`” is refuted by the standalone footer
    `Row`/`Expanded` expansion path.
  - “Change all empty/media-only bubbles to intrinsic width” is refuted by the
    user-scoped request and the existing `TC-T5` preservation contract.
  - “Use the keyed summary `Row` as the content width” is refuted by its tight
    incoming constraints; the scoped eye-off icon and localized `Text` rects
    are the truthful content anchors.
- Unresolved findings: none.
- Affected production files:
  - `lib/features/conversation/presentation/screens/direct_private_media_viewer.dart`
  - `lib/features/conversation/presentation/screens/conversation_screen.dart`
  - `lib/features/conversation/presentation/widgets/letter_card.dart`
- Affected test/gate files:
  - `test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart`
  - `test/features/conversation/presentation/screens/direct_private_media_card_test.dart`
  - `test/features/conversation/presentation/widgets/letter_card_test.dart`
  - `scripts/run_test_gates.sh` is verification-only; no array edit is needed.

## Graph Grounding Snapshot

- Graph fingerprint / freshness:
  `23ea4d231a395cb6`;
  `stale:lib/features/conversation/presentation/screens/direct_private_media_viewer.dart`.
  The graph retained the correct widget and `LetterCard` anchors; every
  load-bearing conclusion was verified in current source, so no planning-time
  refresh was needed.
- Query / profile:
  `python3 graphify-arch/tdd_context.py query "DirectPrivateMediaTerminalPlaceholder private-terminal-view-once-consumed-summary compact bubble intrinsic width LetterCard direct_private_media_card_test ONE_TO_ONE_TESTS" --profile tdd --budget 700`.
- Anchors:
  - `DirectPrivateMediaTerminalPlaceholder` ->
    `direct_private_media_viewer.dart:369`.
  - `LetterCard` -> `letter_card.dart:40`.
  - `ONE_TO_ONE_TESTS` -> `scripts/run_test_gates.sh:25`.
- Surfaced production/test/gate files:
  `direct_private_media_viewer.dart`, `letter_card.dart`,
  `conversation_screen.dart`, `direct_private_media_viewer_test.dart`, and
  `scripts/run_test_gates.sh`.
- Graph gaps requiring source search: the compact overlay did not surface the
  owning `direct_private_media_card_test.dart`, the standalone footer expansion
  lines, or the exact existing short-text test names; targeted source search
  verified them and their `ONE_TO_ONE_TESTS` membership.
- Reuse rule: anchors may be handed to review/execution; all conclusions still
  require current-source or command evidence.

## Scope Contract And Guard

In scope:

- Remove the explicit infinite width only from the narrow
  `viewOnce + consumed` terminal branch so its terminal container can
  shrink-wrap the keyed eye-off/Photo summary.
- Add a default-off, clearly named `LetterCard` input such as
  `hugPrivateContentBubble` and use intrinsic sizing only for that opt-in
  bubble contents, inside the existing maximum-width cap.
- Pass the opt-in from the direct `ConversationScreen` caller only when
  `message.privateMediaMode == PrivateMediaMode.viewOnce` and
  `message.privateMediaState == PrivateMediaLifecycleState.consumed`.
- Apply the same size to incoming/outgoing live cards and the rebuilt lifted
  snapshot while retaining physical left/right message alignment.
- Keep the existing timestamp, transport/delivery glyph, padding, border,
  rounded corners, long-press, and swipe behavior.

Must preserve:

- The Plan-304 eye-off + localized `Photo` row, one combined semantic receipt,
  and zero inline Reply/Info/Delete/Open/media/lifecycle copy ->
  `TC-305-01/02`.
- Expired, unsupported, protected-consumed, protected, disappearing, and
  available private cards keep their current sizing and content ->
  `TC-305-03`.
- Ordinary short text continues to hug, long content remains width-capped, and
  ordinary empty/media-only bubbles keep their standalone timestamp behavior ->
  `TC-305-04`.
- Outer Reply/Delete remain reachable and attachmentless Info stays absent ->
  `TC-305-02`.

Hard `Do not`:

- Do not hard-code a final bubble width or size it from English text metrics.
- Do not hide, move outside, or duplicate the timestamp/status footer to obtain
  a smaller rectangle.
- Do not wrap all `LetterCard` bubbles or all private-media bubbles in
  `IntrinsicWidth`; the opt-in must be receipt-specific and default false.
- Do not change terminal state derivation, cleanup, attachment retention,
  lifecycle/controller/protection logic, database/schema, wire format,
  localization resources, groups, or announcements.

Deferred / accepted difference:

- The bubble is content-hugging, not exactly equal to the icon/text row:
  existing horizontal padding plus timestamp/status may determine a slightly
  wider minimum. This matches short-text bubble behavior and is accepted.
- Content-hugging other empty/media-only bubbles is deferred to an unallocated
  general bubble-layout plan because it is outside this direct consumed-receipt
  request.
- Plan 304's accepted legacy consumed view-once-video label remains `Photo`;
  this plan changes no label or terminal-kind policy.

Dependencies:

- Completed Plan 304 owns the visual/interaction receipt contract. This plan
  changes only its outer size and must stop for re-grounding if the keyed
  summary, required mode input, or no-inline-actions contract is absent.
- Completed Plan 303 remains the upstream image-only new-composition contract
  and is unchanged.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-305-01 | The consumed view-once terminal itself shrink-wraps the localized eye-off/Photo content in en/de/ar at 1.3x text scale for both directions | Extend `test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart::consumed view-once terminal is eye-off plus localized Photo only` with terminal-to-visual-content-span width assertions | widget / `WidgetTester`, existing locale × direction matrix and scoped icon/label finders | causal assertion RED: terminal width fills its available surface because of `double.infinity` -> GREEN: terminal width equals the span from the outer edge of the eye-off icon to the outer edge of the localized `Text`, plus existing 12px horizontal padding per side, within a 1px tolerance and with no overflow | restore `width: double.infinity` in the narrow branch -> TC-305-01 red | `flutter test test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart --plain-name 'consumed view-once terminal is eye-off plus localized Photo only'`; existing `ONE_TO_ONE_TESTS`, AUTO feature glob, no registration edit |
| TC-305-02 | Real incoming/outgoing consumed view-once bubbles opt into receipt-only hugging, contain the summary/footer without clipping, remain left/right aligned, and the lifted snapshot retains the same compact sizing seam while outer Reply/Delete stay reachable | Extend `test/features/conversation/presentation/screens/direct_private_media_card_test.dart::consumed view-once receipt is minimal in live and lifted cards while outer reply and delete remain reachable` with incoming + outgoing models, exact live/lifted `LetterCard` opt-in assertions, and live decorated-body geometry | widget / existing `pumpConversation`, local models with `transport: direct`, callback spies, a row-scoped `LetterCard` finder, and the selected-message subtree | GREEN seam: both live consumed view-once cards and the lifted descendant expose `hugPrivateContentBubble == true` while rendering is unchanged; causal assertion RED: each live decorated body is far wider than its scoped icon-to-label visual span -> GREEN: each body contains that span, is at least visual span + 24px and at most visual span + 48px for terminal padding/footer metadata, incoming stays left, outgoing stays right, time plus incoming transport/outgoing status remain visible, and the lifted copy retains one summary/no inline controls | omit the exact `ConversationScreen` opt-in or remove its narrow `LetterCard` intrinsic wrapper -> TC-305-02 width assertion red; override the rebuilt selected card to default false -> its lifted seam assertion reds; clip below the content minimum -> its containment/lower bound reds | `flutter test test/features/conversation/presentation/screens/direct_private_media_card_test.dart --plain-name 'consumed view-once receipt is minimal in live and lifted cards while outer reply and delete remain reachable'`; existing `ONE_TO_ONE_TESTS`, AUTO feature glob |
| TC-305-03 | Other private rows keep the opt-in false; terminal siblings retain their non-compact widths, generic/state copy, and inline actions | Extend `test/features/conversation/presentation/screens/direct_private_media_card_test.dart::non-view-once terminal cards retain generic copy and actions` with a consumed-view-once comparator, false terminal-sibling opt-in assertions, and meaningful post-fix width separation; extend `::private media renders one cohesive in-bubble card, never an empty bubble` with false opt-in assertions for its existing available protected and view-once rows | widget / existing protected-consumed, expired, unsupported, protected-available, and view-once-available models plus one consumed-view-once comparator | GREEN after behavior-neutral seam preparation and after fix: consumed view-once is the sole `true` opt-in; view-once available, protected available/consumed, expired, and unsupported are `false`; terminal siblings remain materially wider after implementation and keep all expected content/actions | set the new hug input from mode alone, state alone, or every private slot instead of exact `viewOnce + consumed` -> at least one false-scope assertion reds even where a full-width child would mask the mistake geometrically | `flutter test test/features/conversation/presentation/screens/direct_private_media_card_test.dart --plain-name 'non-view-once terminal cards retain generic copy and actions'`; `flutter test test/features/conversation/presentation/screens/direct_private_media_card_test.dart --plain-name 'private media renders one cohesive in-bubble card, never an empty bubble'`; existing `ONE_TO_ONE_TESTS`, AUTO feature glob |
| TC-305-04 | Ordinary bubble sizing, maximum-width cap, and standalone footer contract do not change | Existing `test/features/conversation/presentation/widgets/letter_card_test.dart::TC-W2 continuation incoming bubble hugs short text`, `::TC-W3 outgoing bubble hugs short text and stays right-aligned`, `::constrains bubble max width to ~78% of available width`; extend `::TC-T5 empty-text bubble keeps the footer timestamp` to retain the default 78%-cap geometry when the new opt-in is false | widget / `WidgetTester`, existing `buildBubble` fixture | GREEN sentinel on HEAD and after fix: short text stays under its content-hug bound, long content remains capped, and default empty content keeps timestamp and prior capped width | make intrinsic content hugging unconditional/default true -> TC-T5 width assertion reds; remove the maximum cap -> max-width test reds; remove the footer to force shrink -> TC-T5 timestamp assertion reds | `flutter test test/features/conversation/presentation/widgets/letter_card_test.dart --plain-name 'TC-W2 continuation incoming bubble hugs short text'`; `flutter test test/features/conversation/presentation/widgets/letter_card_test.dart --plain-name 'TC-W3 outgoing bubble hugs short text and stays right-aligned'`; `flutter test test/features/conversation/presentation/widgets/letter_card_test.dart --plain-name 'constrains bubble max width to ~78% of available width'`; `flutter test test/features/conversation/presentation/widgets/letter_card_test.dart --plain-name 'TC-T5 empty-text bubble keeps the footer timestamp'`; existing `ONE_TO_ONE_TESTS`, AUTO feature glob |

### Test Notes

- TC-305-01 must not use the keyed summary `Row` width: that row is already
  tightly expanded on HEAD. Compute
  `visualSpan = max(iconRect.right, labelRect.right) -
  min(iconRect.left, labelRect.left)` from the existing scoped icon and
  localized-label finders, then compare `terminalWidth` with
  `visualSpan + 24`.
- TC-305-02 should compute that same visual span inside each live private slot.
  The body must geometrically contain both content rects and fall between
  `visualSpan + 24` and `visualSpan + 48`. The upper delta accommodates the
  terminal's 24px horizontal padding plus unchanged footer metadata without
  pinning an English final width; it fails the current cap-sized bubble by a
  wide margin.
- Extend the local `privateMessage` fixture with an optional `transport` and
  use `direct` for both models. Assert the exact timestamp plus incoming
  transport and outgoing status glyphs so “footer/status remain visible” is
  executable rather than narrative.
- Geometry assertions for the lifted snapshot must not use painted coordinates
  after `FittedBox` scaling. The live row owns the causal width assertion; the
  lifted copy proves the same keyed content and interaction omissions.
- Add a small `liveLetterCard(messageId)` finder scoped under
  `ValueKey('msg-$messageId')`. TC-305-02 asserts the intended incoming and
  outgoing cards opt in and the `LetterCard` under
  `MessageContextOverlay.selectedMessageKey` also opts in. TC-305-03 asserts
  the existing view-once-available and protected-available cards plus
  protected-consumed, expired, and unsupported cards do not. Reuse those
  fixtures rather than adding an exhaustive policy matrix: consumed view-once,
  view-once available, and protected consumed are the minimal true,
  state-boundary, and mode-boundary cases for the exact conjunction. The
  structural seam proof is justified because internal infinite widths would
  otherwise make broad plumbing behaviorally invisible.
- TC-305-03 should retain sibling width separation in the same viewport as a
  post-fix behavioral sentinel instead of pinning theme/font-specific absolute
  widths.
- Stage the new default-off property and exact caller plumbing before adding
  assertions, but do not consult it in rendering. Run the existing Plan-304
  viewer/card tests GREEN. This keeps the subsequent TC-305-01/02 failures
  causal width REDs rather than compile failures.

## Implementation Steps

1. Snapshot `git status --short` and record the completed Plans 303-304 plus
   unrelated dirty files. Preserve them; do not reformat or absorb them into
   Plan 305.
2. Prepare the behavior-neutral seam: add default-false
   `LetterCard.hugPrivateContentBubble`, pass it from the sole direct
   `buildLetterCard` using the exact `viewOnce + consumed` predicate, and do
   not read it in `LetterCard` rendering yet. Run the existing Plan-304
   viewer/card tests and `TC-T5` GREEN.
3. Add TC-305-01/02 visual-span geometry assertions, exact live/lifted true
   opt-in checks, and TC-305-03/04 false/default preservation assertions,
   reusing the existing available protected/view-once fixtures for the
   state boundary. Run the two causal commands and require assertion REDs for
   width only; exact caller-scope and all Plan-304 visual/action assertions
   must be green.
4. In the consumed view-once early branch of
   `DirectPrivateMediaTerminalPlaceholder.build`, remove only its
   `width: double.infinity`; leave the fallback terminal width unchanged.
5. Make `LetterCard` apply `IntrinsicWidth` only when the prepared opt-in is
   true, to the bubble contents inside the existing
   `ConstrainedBox(maxWidth: ...)`. Stop-if: the footer cannot retain
   right-aligned timestamp/status without changing other bubble modes, or
   intrinsic measurement leaks to default bubbles.
6. Make no gate-array edit: all three test files are already literal
   `ONE_TO_ONE_TESTS` members and host-auto-discovered.
7. Run focused GREEN, Graphify affected discovery, the curated `1to1` lane,
   hygiene, and one incremental architecture refresh.

## Risks And Blind Spots

- Removing only the terminal width leaves the standalone footer expanding the
  bubble -> guarded by real-caller TC-305-02.
- A global `IntrinsicWidth` could change every chat bubble and add unnecessary
  intrinsic-layout cost -> exact `LetterCard` opt-in assertions plus
  TC-305-03/04.
- Measuring the tightly expanded summary `Row` would let the pre-fix layout
  satisfy both causal bounds -> TC-305-01/02 use the scoped icon-to-label
  visual span instead.
- Timestamp/status could disappear or drift left while the bubble shrinks ->
  TC-305-02 retains visible footer metadata and directional alignment.
- RTL or larger text could overflow a too-tight receipt -> TC-305-01 retains
  the Plan-304 en/de/ar × direction matrix at 1.3x.
- Lifted context content could diverge from the live row -> TC-305-02 exercises
  the shared `buildLetterCard` factory and asserts the selected descendant
  carries the same true sizing seam without using scaled painted coordinates.
- Lifecycle / derived-state durability: N/A — no state derivation, transition,
  hydration, or restart behavior changes.
- Sibling-surface consistency: TC-305-03 covers the direct private
  mode/state predicate boundaries and TC-305-04 covers ordinary bubbles;
  group/announcement callers never receive the new opt-in.
- Destructive-action side effects: N/A — delete/cleanup code is unchanged;
  TC-305-02 retains outer Delete callback dispatch.
- Invariant re-verification under new transitions: N/A — this plan adds no
  transition, reset, release, or re-entry path.

## Gate Cadence

- Per-plan closure: the three focused widget files, exact preservation
  sentinels, Graphify affected host tests, and `./scripts/run_test_gates.sh
  1to1`.
- No `core-host-all`, `feature-host-all`, device, relay, SQLCipher, or
  performance family sweep is justified for this receipt-only layout change.
- Do not run full `host-all` as a Plan-305 acceptance command. The completed
  Plans 303-305 direct view-once presentation batch owns one separate
  `./scripts/run_host_test_gates.sh host-all` run after Plan 305 is integrated;
  final rollout/release closure owns the final full run.
- Shared tests outside feature/core globs: N/A — every planned test is under
  `test/features/**` and is already curated into `ONE_TO_ONE_TESTS`.

## Acceptance Gates

```bash
# Snapshot before execution; preserve completed Plans 303-304 and unrelated work.
git status --short

# After behavior-neutral seam preparation but before test edits, these existing
# Plan-304/default-layout baselines remain GREEN.
flutter test \
  test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart \
  --plain-name 'consumed view-once terminal is eye-off plus localized Photo only'
flutter test \
  test/features/conversation/presentation/screens/direct_private_media_card_test.dart \
  --plain-name 'consumed view-once receipt is minimal in live and lifted cards while outer reply and delete remain reachable'
flutter test \
  test/features/conversation/presentation/widgets/letter_card_test.dart \
  --plain-name 'TC-T5 empty-text bubble keeps the footer timestamp'

# After adding the new assertions but before rendering edits, each causal test
# must fail only on the icon-to-label visual-span width relationship, not
# compilation, localization, missing controls, or overflow.
flutter test \
  test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart \
  --plain-name 'consumed view-once terminal is eye-off plus localized Photo only'
flutter test \
  test/features/conversation/presentation/screens/direct_private_media_card_test.dart \
  --plain-name 'consumed view-once receipt is minimal in live and lifted cards while outer reply and delete remain reachable'

# Preservation stays GREEN at RED and after implementation.
flutter test \
  test/features/conversation/presentation/screens/direct_private_media_card_test.dart \
  --plain-name 'non-view-once terminal cards retain generic copy and actions'
flutter test \
  test/features/conversation/presentation/screens/direct_private_media_card_test.dart \
  --plain-name 'private media renders one cohesive in-bubble card, never an empty bubble'
flutter test \
  test/features/conversation/presentation/widgets/letter_card_test.dart \
  --plain-name 'TC-W2 continuation incoming bubble hugs short text'
flutter test \
  test/features/conversation/presentation/widgets/letter_card_test.dart \
  --plain-name 'TC-W3 outgoing bubble hugs short text and stays right-aligned'
flutter test \
  test/features/conversation/presentation/widgets/letter_card_test.dart \
  --plain-name 'constrains bubble max width to ~78% of available width'
flutter test \
  test/features/conversation/presentation/widgets/letter_card_test.dart \
  --plain-name 'TC-T5 empty-text bubble keeps the footer timestamp'

# Focused GREEN; each exits 0 with zero failed tests.
flutter test \
  test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart
flutter test \
  test/features/conversation/presentation/screens/direct_private_media_card_test.dart
flutter test \
  test/features/conversation/presentation/widgets/letter_card_test.dart

# Affected discovery and curated direct-conversation gate.
python3 graphify-arch/tdd_context.py affected \
  lib/features/conversation/presentation/screens/direct_private_media_viewer.dart \
  lib/features/conversation/presentation/screens/conversation_screen.dart \
  lib/features/conversation/presentation/widgets/letter_card.dart \
  --budget 600
./scripts/run_test_gates.sh 1to1

# Hygiene and graph maintenance.
flutter analyze
git diff --check
./graphify-arch/refresh_arch_graph.sh --incremental
```

Semantic outcomes:

- The two causal tests RED only because the current terminal/decorated body is
  much wider than the scoped eye-off-icon-to-localized-label visual span.
- GREEN proves content-relative sizing across localization/direction without
  hiding timestamp/status or weakening the Plan-304 receipt.
- Scope assertions prove the opt-in is exact and default false even for
  siblings whose full-width children would mask broad plumbing.
- The actual `1to1` run verifies existing registration and finishes with zero
  failed legs; analysis reports no new issues and diff hygiene is clean.

## Execution Interpretation And Done Criteria

- Expected RED: after behavior-neutral API plumbing, TC-305-01 and TC-305-02
  fail their icon-to-label visual-span width relationships on the current
  cap-sized receipt.
- Green sentinel: TC-305-03/04 and all pre-existing Plan-304 content,
  semantics, interaction, RTL, and overflow assertions.
- Pre-existing dirty tree / known failure: completed Plans 303-304 and
  unrelated workspace changes are present; the five planning-time baseline
  probes named above passed. No product baseline failure is known.
- Environment blocker: none; host-only layout closure requires no simulator,
  device, relay, SQLCipher, native callback, or real crypto.
- Scope drift: global bubble intrinsic sizing, footer removal, hard-coded
  localized widths, or any lifecycle/storage/wire change blocks completion and
  requires re-planning.

- [x] Every behavior has a named test or justified proof.
- [x] Behavior-neutral seam plumbing stays GREEN before causal assertions are
      introduced.
- [x] Causal RED, focused GREEN, and representative mutation re-red are
      recorded.
- [x] Preservation tests, affected tests, and `1to1` pass with their semantic
      outcomes.
- [x] Existing harness registration is verified; no duplicate entry is added.
- [x] No migration or device/relay proof is introduced.
- [x] `flutter analyze` has no new issues; `git diff --check` is clean.
- [x] Scope Contract And Guard is respected.

## Handoff

- First causal RED command:
  `flutter test test/features/conversation/presentation/screens/direct_private_media_card_test.dart --plain-name 'consumed view-once receipt is minimal in live and lifted cards while outer reply and delete remain reachable'`.
- Preservation command:
  `flutter test test/features/conversation/presentation/screens/direct_private_media_card_test.dart --plain-name 'non-view-once terminal cards retain generic copy and actions'`.
- Manual registration: none; viewer/card/`LetterCard` test files are existing
  `ONE_TO_ONE_TESTS` members and host-auto-discovered.
- Migration: none.
- Boundary closure: host-only widget proof; no simulator/device/relay/crypto/
  SQLCipher/OS callback claim.
- Unresolved evidence: none.

## Reviewer Findings

Core implementation bet: confirmed. Removing the narrow terminal's infinite
width plus a default-off, exact-caller `LetterCard` intrinsic-sizing seam is the
smallest production change that addresses both known expansion drivers.

Meaningful corrections applied:

1. Replaced both keyed-summary-`Row` width formulas. Tight constraints already
   expand that row on HEAD, so the original TC-305-01/02 assertions could pass
   without the fix. Both tests now derive the actual visual content span from
   the scoped eye-off icon and localized label; TC-305-02 also has containment
   and lower bounds to reject clipping.
2. Replaced the vacuous broad-opt-in width mutation with exact
   `LetterCard.hugPrivateContentBubble` assertions. The minimal matrix is one
   true case plus view-once-available and protected-consumed state/mode
   boundaries, with expired and unsupported fixtures already present.
3. Added a lifted-descendant opt-in assertion. This proves the rebuilt
   selected card carries the same seam while avoiding invalid painted-geometry
   comparisons below the overlay's `FittedBox`.
4. Staged the new default-off API and exact caller plumbing as
   behavior-neutral GREEN preparation before causal assertions. The planned
   REDs now fail on width behavior, not on a missing constructor field.
5. Made footer preservation executable with explicit transport/status fixtures
   and exact timestamp/glyph assertions.

Deliberately not added: golden tests, device legs, a new test file, gate-array
edits, performance sweeps, or an exhaustive matrix of every private policy.
They do not add causal confidence beyond the focused host widget contracts for
this receipt-only layout change.

| Review lens | Result after correction |
|---|---|
| L1 — intent-to-assertion alignment | clear — visual-span geometry now measures the requested icon/text-sized receipt |
| L2 — coverage and preservation | clear — live directions, lifted seam, exact mode/state boundaries, footer metadata, ordinary bubbles, and fallback terminals are covered |
| L3 — falsifiability and mutations | clear — full-width restoration, missing/over-broad opt-in, lifted divergence, clipping, global intrinsic sizing, cap removal, and footer removal each have a discriminating failure |
| L4 — execution and boundary closure | clear — existing host fixtures and literal `ONE_TO_ONE_TESTS` registration are sufficient; no external boundary is touched |
| L5 — integrated-environment proof | N/A — no device, relay, native callback, persistence, crypto, or migration claim changes |

Final verdict: **ready**. Disposition: execute the revised four-case contract;
no user decision or plan split is required.

## Execution Progress

| Stage | State | Evidence |
|---|---|---|
| Seam | complete | Added the default-false `LetterCard.hugPrivateContentBubble` input and exact direct `viewOnce + consumed` caller plumbing without reading it in rendering. The existing Plan-304 viewer/card tests and default empty-footer sentinel remained green. |
| RED | complete | After adding visual-span assertions, the viewer failed at 320px versus about 148px and the real conversation body failed at about 677px versus the compact upper bound. All six exact sibling/default preservation sentinels stayed green. |
| GREEN | complete | Removed only the consumed view-once terminal's infinite width and applied `IntrinsicWidth` only behind the new opt-in within the existing cap. The viewer, card, and `LetterCard` files passed 30, 5, and 116 tests. Restoring the terminal width, broadening the caller predicate, and making intrinsic sizing unconditional each re-redded its owning causal/scope test before restoration. |
| Closure | complete | Graphify affected discovery was reviewed; the `1to1` lane passed 2,517 Flutter tests plus its relay Go contract/test. `flutter analyze` reported no issues, formatting and `git diff --check` were clean, and the incremental architecture graph refresh completed. |
| Batch | complete | The separately owned completed-Plans-303–305 `host-all` sweep passed all 1,283 isolated host commands, including its final Go contract tails. |
