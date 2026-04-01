# 26 - Long-Press Message Context Menu Session Breakdown

## Decomposition artifact updated

- Artifact path:
  `Test-Flight-Improv/26-long-press-message-context-menu-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/26-long-press-message-context-menu.md`
- Decomposition date:
  `2026-03-30`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution

## Recommended plan count

- `0`
- The smallest safe historical split remains Session `52` and Session `53`,
  but current repo state already covers both slices, so no new plan files
  should be created now.

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Retry attempts used | Final execution verdict | Blocker class | Closure docs touched | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `52` | Shared long-press overlay and Orbit conversation adoption | `stale/already-covered` | `Test-Flight-Improv/26-long-press-message-context-menu-session-52-plan.md` | none | `stale/already-covered` | `0` | `not run; stale/already-covered` | none | `Test-Flight-Improv/26-long-press-message-context-menu-session-breakdown.md` | Historical Orbit/shared-overlay slice is already covered by landed code and current direct-suite evidence, so no spawned planning/execution/closure session was needed in this pipeline run. |
| `53` | Feed/stack adoption, focus parity, and final acceptance | `stale/already-covered` | `Test-Flight-Improv/26-long-press-message-context-menu-session-53-plan.md` | `52` | `stale/already-covered` | `0` | `not run; stale/already-covered` | none | `Test-Flight-Improv/26-long-press-message-context-menu-session-breakdown.md` | Historical feed/focus slice is already covered by landed code and current direct-suite evidence, so no spawned planning/execution/closure session was needed in this pipeline run. |

## Overall closure bar

Report `26` is closed only when the current 1:1 message surfaces expose one
honest long-press contract without reopening stable 1:1 reliability scope:

- Orbit conversations and feed/stack 1:1 cards both show a blurred full-screen
  overlay with anchored reactions above the pressed message and a context menu
  below it.
- Long-press `Reply` works for both incoming and sent messages on those
  surfaces, while swipe-to-reply stays incoming-only.
- Long-press `Copy` copies only message text and stays hidden for textless
  media-only messages.
- Reply activation requests composer focus on both surfaces.
- Reaction selection, `+` picker handoff, background dismissal, and back-button
  dismissal preserve existing semantics.

## Final program acceptance

- Closure verdict:
  `closed`
- Acceptance date:
  `2026-03-30`
- What is now closed:
  - Orbit conversations and feed/stack 1:1 cards already share the same
    blurred long-press overlay contract with anchored reactions, `Reply`, and
    conditional text-only `Copy`
  - long-press `Reply` works for both incoming and sent 1:1 messages on both
    surfaces and still routes through the existing quote-send path
  - composer-focus handoff after long-press reply is already landed on both
    surfaces
- Residual-only items:
  - none
- Still-open items:
  - none
- Reopen only on real regression:
  - if the shared overlay contract, quote/focus handoff, or conditional copy
    behavior regresses on Orbit or feed 1:1 surfaces
  - if the direct widget/screen regressions fail, or if a future production
    change widens into named-gate scope (`baseline`, plus `feed` and companion
    `1to1` when shared quote-send semantics move)

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/26-long-press-message-context-menu.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`

Current repo facts that governed the split:

- `lib/features/conversation/presentation/widgets/message_context_overlay.dart`
  already implements the blurred backdrop, anchored inline `ReactionBar`,
  `Reply`, and conditional `Copy`.
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
  already long-presses `LetterCard` into that overlay, gates copy to non-empty
  text, and requests composer focus after reply.
- `lib/features/feed/presentation/screens/feed_screen.dart`,
  `lib/features/feed/presentation/widgets/feed_card.dart`,
  `lib/features/feed/presentation/widgets/open_mode_card_body.dart`,
  `lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart`, and
  `lib/features/feed/presentation/widgets/scrollable_message_preview.dart`
  already propagate the pressed `ThreadMessage` plus bubble `BuildContext` so
  feed 1:1 cards can reuse the shared overlay on both collapsed and expanded
  paths.
- `lib/features/feed/presentation/screens/feed_wired.dart` already sets both
  `_activeQuoteMessageIds[...]` and `_activeFocusPeerId` inside
  `_onQuoteReply(...)`, so feed long-press reply parity is already wired.
- Group surfaces still intentionally keep the bare reaction-bar path, which
  matches the source doc's out-of-scope guard for non-1:1 surfaces.

Current tests that beat stale prose:

- `test/features/conversation/presentation/widgets/message_context_overlay_test.dart`
- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/features/feed/presentation/screens/feed_screen_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`

Targeted direct-suite revalidation reran on `2026-03-30` in the current
workspace:

```bash
flutter test \
  test/features/conversation/presentation/widgets/message_context_overlay_test.dart \
  test/features/conversation/presentation/screens/conversation_screen_test.dart \
  test/features/conversation/presentation/screens/conversation_wired_test.dart \
  test/features/feed/presentation/screens/feed_screen_test.dart \
  test/features/feed/presentation/screens/feed_wired_test.dart
```

Result: passed (`129` tests).

Source-of-truth conflicts that materially affected decomposition:

- The proposal's current-state prose is stale. The repo already ships the
  shared long-press overlay, blurred backdrop, `Reply`, and conditional `Copy`
  on both Orbit and feed 1:1 surfaces.
- The existing breakdown artifact had drifted into execution-history state with
  non-skill statuses such as `accepted`. This rewrite restores a pure
  decomposition artifact using skill-allowed classifications.
- No stable overlay-specific matrix or closure doc already exists for this
  area, so this artifact remains the live doc-scoped ledger.

## Reviewer pass

- Sufficiency:
  `0` new plans is sufficient because current code plus passing direct
  regressions already satisfy the closure bar. If a regression reopens this
  report later, the historical two-slice split remains the minimum safe split.
- Merge candidates:
  none.
- Required splits:
  none.
- Missing tests or named gates:
  none for current acceptance. A future reopen still uses direct widget/screen
  tests plus `baseline`, and feed-side reopen still uses `feed` with companion
  `1to1` when quoted-send semantics move.
- Meaningful verified state:
  yes. Both historical slices already end in independently verifiable states.
- Matrix responsibility:
  clear. This artifact remains the live ledger for the area.
- Minimum safe session set:
  `0` new plans now; otherwise reopen as Session `52` and Session `53`, not one
  monolith.

## Arbiter outcome

- Structural blockers:
  none.
- Mergeable sessions:
  none.
- Required splits:
  none.
- Accepted differences:
  - swipe-to-reply remains incoming-only
  - group and announcement long-press paths stay on the existing bare
    reaction-bar flow
  - no new named gate or generic UI matrix doc is needed
  - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
    stays a scope guard, not a feature-closure owner for this UI report

## Ordered session breakdown

### Session 52

- Title:
  `Shared long-press overlay and Orbit conversation adoption`
- Session id:
  `52`
- Session classification:
  `stale/already-covered`
- Intended plan file:
  `Test-Flight-Improv/26-long-press-message-context-menu-session-52-plan.md`
- Exact scope:
  - settle the shared long-press overlay host with blurred backdrop, anchored
    inline reactions, and `Reply` / text-only `Copy`
  - adopt that overlay on the Orbit conversation surface
  - wire long-press `Reply` for both incoming and sent 1:1 messages through
    the existing quote flow
  - request composer focus after long-press reply
- Why it is its own session:
  - the shared overlay host plus Orbit consumer are one coherent seam with
    conversation-specific direct regressions
  - feed adoption uses a different callback and focus-state seam
- Likely code-entry files:
  - `lib/features/conversation/presentation/widgets/message_context_overlay.dart`
  - `lib/features/conversation/presentation/widgets/reaction_bar.dart`
  - `lib/features/conversation/presentation/screens/conversation_screen.dart`
  - `lib/features/conversation/presentation/screens/conversation_wired.dart`
  - `lib/features/conversation/presentation/widgets/compose_area.dart`
- Likely direct tests/regressions:
  - `test/features/conversation/presentation/widgets/message_context_overlay_test.dart`
  - `test/features/conversation/presentation/screens/conversation_screen_test.dart`
  - `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- Likely named gates:
  - `baseline` if a future reopen changes production code
  - no `1to1` unless a future reopen widens into shared quoted-message
    send/persist semantics
- Matrix/closure docs to update when done:
  - refresh this breakdown artifact only if the session is reopened
  - update `Test-Flight-Improv/test-gate-definitions.md` only if a new
    maintained integration or cross-feature suite is added
  - do not reopen
    `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
    unless shared 1:1 reliability semantics truly change
- Dependency on earlier sessions:
  - none
- Current evidence:
  - `ConversationScreen._showMessageContextOverlay(...)` now opens the shared
    overlay from `LetterCard` long press and gates copy to non-empty text
  - `ConversationScreen._handleReplyAction(...)` requests composer focus after
    long-press reply
  - the `2026-03-30` targeted `flutter test` run passed the direct overlay and
    Orbit conversation/wired regressions

### Session 53

- Title:
  `Feed/stack adoption, focus parity, and final acceptance`
- Session id:
  `53`
- Session classification:
  `stale/already-covered`
- Intended plan file:
  `Test-Flight-Improv/26-long-press-message-context-menu-session-53-plan.md`
- Exact scope:
  - propagate one coherent long-press contract through feed cards so the host
    receives the selected `ThreadMessage` plus bubble `BuildContext`
  - adopt the shared overlay for 1:1 feed cards in both collapsed and expanded
    modes
  - wire long-press `Reply` for both incoming and sent feed messages
  - set focus state so the inline composer requests focus after long-press
    reply
  - preserve group long-press reaction-only behavior and incoming-only
    swipe-to-reply
- Why it is its own session:
  - feed still uses a different host seam from Orbit: callback propagation,
    card modes, and feed focus state are separate from the conversation
    surface
  - this slice carries the feed-specific regression family and gate rules
- Likely code-entry files:
  - `lib/features/feed/presentation/screens/feed_screen.dart`
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/feed/presentation/widgets/feed_card.dart`
  - `lib/features/feed/presentation/widgets/open_mode_card_body.dart`
  - `lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart`
  - `lib/features/feed/presentation/widgets/scrollable_message_preview.dart`
  - `lib/features/feed/presentation/widgets/message_bubble.dart`
- Likely direct tests/regressions:
  - `test/features/feed/presentation/screens/feed_screen_test.dart`
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
  - `test/features/feed/presentation/widgets/feed_card_test.dart`
  - `test/features/feed/presentation/widgets/scrollable_message_preview_test.dart`
  - `test/features/feed/presentation/widgets/message_bubble_test.dart`
- Likely named gates:
  - `feed` if a future reopen changes feed interaction code
  - companion `1to1` if a future reopen affects quoted-send semantics
  - `baseline` if production code changes
- Matrix/closure docs to update when done:
  - refresh this breakdown artifact only if the session is reopened
  - update `Test-Flight-Improv/test-gate-definitions.md` only if a new
    maintained integration or cross-feature suite is added
  - keep
    `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
    unchanged unless shared reliability semantics move
- Dependency on earlier sessions:
  - `52`
- Current evidence:
  - `FeedScreen._showMessageContextOverlay(...)` already reuses the shared
    overlay for 1:1 feed cards and gates copy to non-empty text
  - `FeedCard`, `OpenModeCardBody`, `CollapsedModeCardBody`, and
    `ScrollableMessagePreview` already pass the pressed message plus bubble
    context through the feed surface
  - `FeedWired._onQuoteReply(...)` already sets quote state and
    `_activeFocusPeerId`, so long-press reply focuses the feed composer
  - the `2026-03-30` targeted `flutter test` run passed the direct feed
    screen/wired regressions, including incoming and sent long-press reply
    coverage

## Why this is not fewer sessions

- No new plans are needed because the repo already satisfies the closure bar.
- If this report is reopened later, collapsing the historical split into one
  session would blur two different seams:
  Orbit/shared-overlay adoption versus feed callback/focus adoption.
- Those two seams have different direct regression families and different gate
  triggers, so one reopened mega-session would be unsafe.

## Why this is not more sessions

- Splitting `Reply`, `Copy`, blur/backdrop, and focus wiring into separate
  sessions would be bookkeeping only; they move together as one surface-level
  overlay contract.
- A separate acceptance-only or closure-only session is unnecessary because
  this artifact already serves as the live ledger for the area.
- Groups and announcements should not become extra sessions unless a real
  regression forces them back into scope.

## Regression and gate contract

- Apply `Test-Flight-Improv/14-regression-test-strategy.md` seam-first, not
  test-case-count-first.
- Apply `Test-Flight-Improv/test-gate-definitions.md` as the named-gate source
  of truth.
- Current acceptance proof includes the passing direct widget/screen tests run
  on `2026-03-30` for the shared overlay, Orbit, and feed seams.
- If Session `52` is ever reopened, rerun the direct conversation regressions
  above and `baseline` if production Flutter code changes.
- If Session `53` is ever reopened, rerun the direct feed regressions above,
  plus `feed`, companion `1to1` when quoted-send semantics move, and
  `baseline` if production Flutter code changes.
- Do not invent a new named gate for this report.

## Matrix update contract

- No stable overlay-specific matrix or closure doc exists today.
- This breakdown artifact remains the live doc-scoped ledger for Report `26`.
- If a later regression reopens the work, the final reopened session owns the
  ledger refresh here.
- Update `Test-Flight-Improv/test-gate-definitions.md` only if execution adds a
  new maintained integration or cross-feature suite that must be classified
  permanently.
- Keep
  `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
  unchanged unless shared 1:1 reliability semantics truly change.

## Downstream execution path

- No current downstream planning/execution is required because recommended plan
  count is `0`.
- If Session `52` is ever reopened, send it through:
  `$implementation-plan-orchestrator` ->
  `$implementation-execution-qa-orchestrator` ->
  `$implementation-closure-audit-orchestrator`
- If Session `53` is ever reopened, send it through:
  `$implementation-plan-orchestrator` ->
  `$implementation-execution-qa-orchestrator` ->
  `$implementation-closure-audit-orchestrator`
  after refreshing it against landed code and reopened Session `52` state.

## Structural blockers remaining

- none

## Accepted differences intentionally left unchanged

- Swipe-to-reply remains incoming-only.
- Group and announcement long-press paths remain reaction-only unless a real
  regression later brings them back into scope.
- No new named gate, generic UI matrix doc, or 1:1 reliability closure refresh
  is required for the current repo state.
- This artifact keeps the historical doc-scoped plan paths only as safe reopen
  handles; it does not recommend creating or rerunning them now.

## Exact docs/files used as evidence

Docs:

- `Test-Flight-Improv/26-long-press-message-context-menu.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`

Production files:

- `lib/features/conversation/presentation/widgets/message_context_overlay.dart`
- `lib/features/conversation/presentation/widgets/reaction_bar.dart`
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/conversation/presentation/widgets/compose_area.dart`
- `lib/features/feed/presentation/screens/feed_screen.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/feed/presentation/widgets/feed_card.dart`
- `lib/features/feed/presentation/widgets/open_mode_card_body.dart`
- `lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart`
- `lib/features/feed/presentation/widgets/scrollable_message_preview.dart`
- `lib/features/feed/presentation/widgets/message_bubble.dart`

Tests:

- `test/features/conversation/presentation/widgets/message_context_overlay_test.dart`
- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/features/feed/presentation/screens/feed_screen_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/features/feed/presentation/widgets/feed_card_test.dart`
- `test/features/feed/presentation/widgets/scrollable_message_preview_test.dart`
- `test/features/feed/presentation/widgets/message_bubble_test.dart`

Verification command:

- the targeted `flutter test` command listed above, executed on `2026-03-30`

## Why the decomposition is safe to send into downstream planning/execution

- There is no structural blocker.
- The source proposal is stale about current implementation state, and current
  code plus passing direct regressions beat that stale prose.
- The artifact now preserves only doc-scoped plan paths, not generic shared
  plan paths.
- The ledger clearly distinguishes between `0` recommended new plans now and
  the historical two-slice reopen structure if future regressions appear.

## Program rollout ledger

- Breakdown artifact used:
  `Test-Flight-Improv/26-long-press-message-context-menu-session-breakdown.md`
- Spawned-agent isolation used:
  `yes` for the final whole-program acceptance/closure pass; no per-session
  planning/execution/closure agents were required because both historical
  sessions remained `stale/already-covered`
- Sessions processed:
  `2/2`
- Sessions accepted:
  `0`
- Sessions accepted_with_explicit_follow_up:
  `0`
- Sessions blocked:
  `0`
- Sessions stale/already-covered:
  `2`
- Sessions skipped_due_to_dependency:
  `0`
- Session recovery retries used:
  `0`
- Final program acceptance verdict:
  `closed`
- Stable docs updated:
  `Test-Flight-Improv/26-long-press-message-context-menu-session-breakdown.md`
- Final blocker note:
  none
