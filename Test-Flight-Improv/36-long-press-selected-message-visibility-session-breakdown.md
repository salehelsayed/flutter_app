# 36 - Long-Press Selected Message Visibility Session Breakdown

## Decomposition artifact updated

- Artifact path:
  `Test-Flight-Improv/36-long-press-selected-message-visibility-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/36-long-press-selected-message-visibility.md`
- Decomposition date:
  `2026-03-31`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution

## Recommended plan count

- `2`

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status |
| --- | --- | --- | --- | --- | --- |
| `1` | Shared selected-message overlay host and conversation adoption | `implementation-ready` | `Test-Flight-Improv/36-long-press-selected-message-visibility-session-1-plan.md` | none | `accepted` |
| `2` | Feed parity, final acceptance, and closure | `implementation-ready` | `Test-Flight-Improv/36-long-press-selected-message-visibility-session-2-plan.md` | `1` | `accepted` |

## Overall closure bar

Report `36` is closed only when the current direct-message long-press overlay
keeps the selected message visually present as the focal element without
reopening broader 1:1 reliability or product-scope work:

- direct conversations and feed thread cards that already use the shared
  long-press overlay keep the pressed message clearly identifiable while the
  overlay is open
- the reaction row and context menu read as anchored to that same message
  instead of detached from it
- overlay entry and positioned state feel continuous and stable, with no
  obvious jump or disappearance of the selected message
- edge clamping near the top and bottom of the viewport preserves message
  identification and keeps the action stack on-screen
- existing reply, copy, edit, delete, reaction, and backdrop-dismiss semantics
  remain intact under their current rules

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/36-long-press-selected-message-visibility.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/12-1to1-chat-use-case-audit.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`

Adjacent historical context:

- `Test-Flight-Improv/26-long-press-message-context-menu-session-breakdown.md`

Current repo facts that now govern downstream work:

- `lib/features/conversation/presentation/widgets/message_context_overlay.dart`
  now accepts positioning data plus action flags/callbacks and an optional
  selected-message host, and renders the blurred backdrop, selected message,
  inline `ReactionBar`, and menu card as one anchored stack.
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
  now passes an inert selected-message `LetterCard` into the shared overlay, so
  direct conversations keep the pressed message visibly present while the
  overlay is open.
- `lib/features/feed/presentation/screens/feed_screen.dart` captures
  `anchorRect` from the pressed `MessageBubble`, rebuilds an inert selected
  `MessageBubble`, and opens the same shared overlay from feed thread cards
  with the landed selected-message host path.
- `lib/features/feed/presentation/widgets/feed_card.dart`,
  `lib/features/feed/presentation/widgets/open_mode_card_body.dart`,
  `lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart`, and
  `lib/features/feed/presentation/widgets/scrollable_message_preview.dart`
  show that feed long-press behavior spans a separate card/message-preview tree
  across collapsed and expanded states.
- Session `1` added direct regression coverage for selected-message visibility,
  anchored ordering, and top/bottom clamping on the shared overlay and
  conversation screen:
  - `test/features/conversation/presentation/widgets/message_context_overlay_test.dart`
  - `test/features/conversation/presentation/screens/conversation_screen_test.dart`
  - `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- Session `2` added direct feed regression coverage for selected-message
  visibility across collapsed and expanded feed paths:
  - `test/features/feed/presentation/screens/feed_screen_test.dart`
  - `test/features/feed/presentation/screens/feed_wired_test.dart`

Current code and tests beat stale prose:

- Report `26` is already functionally landed for reply/copy/delete/reaction
  overlay behavior.
- Report `36` is a narrower follow-up UI presentation bug, not a reopen of the
  broader long-press action feature.

## Ordered session breakdown

### Session 1

- Title:
  `Shared selected-message overlay host and conversation adoption`
- Session id:
  `1`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/36-long-press-selected-message-visibility-session-1-plan.md`
- Exact scope:
  - extend the shared long-press overlay contract so the selected message stays
    visible and visually anchored on the direct conversation surface
  - settle the selected-message positioning behavior together with the reaction
    row and action menu on that surface
  - add or update the shared overlay and conversation regressions for visible
    target-message continuity, edge clamping, and preserved existing actions
- Why it is its own session:
  - the shared overlay host and direct conversation surface are one coherent UI
    seam with the same primary regression family
  - this session can land in a meaningful verified state before feed parity,
    without bundling feed-card-specific routing and gate work into the same
    plan
- Likely code-entry files:
  - `lib/features/conversation/presentation/widgets/message_context_overlay.dart`
  - `lib/features/conversation/presentation/screens/conversation_screen.dart`
  - `lib/features/conversation/presentation/widgets/letter_card.dart`
  - `lib/features/conversation/presentation/widgets/reaction_bar.dart`
- Likely direct tests/regressions:
  - `test/features/conversation/presentation/widgets/message_context_overlay_test.dart`
  - `test/features/conversation/presentation/screens/conversation_screen_test.dart`
  - `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- Likely named gates:
  - `baseline`
  - no companion `1to1` gate unless the implementation unexpectedly widens into
    quote-send, persistence, or shared 1:1 reliability semantics
- Matrix/closure docs to update when done:
  - refresh
    `Test-Flight-Improv/36-long-press-selected-message-visibility-session-breakdown.md`
    with landed status and execution evidence
  - do not reopen `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
    unless the work widens past UI presentation into shared 1:1 correctness
  - do not treat `Test-Flight-Improv/12-1to1-chat-use-case-audit.md` as the
    closure owner for this UI-only seam
- Dependency on earlier sessions:
  - none
- Session `1` closure update (`2026-03-31`):
  - status: `accepted`
  - execution verdict: `accepted`
  - files landed:
    - `lib/features/conversation/presentation/widgets/message_context_overlay.dart`
    - `lib/features/conversation/presentation/screens/conversation_screen.dart`
    - `test/features/conversation/presentation/widgets/message_context_overlay_test.dart`
    - `test/features/conversation/presentation/screens/conversation_screen_test.dart`
    - `test/features/conversation/presentation/screens/conversation_wired_test.dart`
  - direct tests passed:
    - `flutter test test/features/conversation/presentation/widgets/message_context_overlay_test.dart`
    - `flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart`
    - `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart`
  - named gates passed:
    - `./scripts/run_test_gates.sh baseline`
  - closure docs touched:
    - `Test-Flight-Improv/36-long-press-selected-message-visibility-session-breakdown.md`
  - concise note:
    - the shared overlay now keeps the selected direct message visible between
      the reaction row and action menu, with top/bottom clamping covered and
      existing reply/copy/edit/delete/reaction flows preserved

### Session 2

- Title:
  `Feed parity, final acceptance, and closure`
- Session id:
  `2`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/36-long-press-selected-message-visibility-session-2-plan.md`
- Exact scope:
  - carry the selected-message visibility and anchored-overlay contract across
    the feed thread-card surfaces that already use the shared overlay
  - preserve parity across the feed card paths that route long-press through
    collapsed and expanded message previews
  - finish the cross-surface acceptance pass and close the doc-scoped ledger
    for report `36`
- Why it is its own session:
  - feed uses a separate card/message-preview tree and a different direct
    regression family than the conversation surface
  - the feed area has its own named gate contract, so keeping parity/acceptance
    here avoids a single plan with blurred gate ownership
- Likely code-entry files:
  - `lib/features/feed/presentation/screens/feed_screen.dart`
  - `lib/features/feed/presentation/widgets/feed_card.dart`
  - `lib/features/feed/presentation/widgets/open_mode_card_body.dart`
  - `lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart`
  - `lib/features/feed/presentation/widgets/scrollable_message_preview.dart`
  - `lib/features/feed/presentation/widgets/message_bubble.dart`
  - `lib/features/conversation/presentation/widgets/message_context_overlay.dart`
- Likely direct tests/regressions:
  - `test/features/feed/presentation/screens/feed_screen_test.dart`
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
  - `test/features/feed/presentation/widgets/scrollable_message_preview_test.dart`
  - `test/features/feed/integration/feed_card_flow_test.dart`
  - `test/features/feed/integration/expanded_collapsed_card_test.dart`
- Likely named gates:
  - `baseline`
  - `feed`
  - companion `1to1` only if the session widens into changed feed-originated
    quote/send semantics instead of staying on presentation/routing parity
- Matrix/closure docs to update when done:
  - finalize
    `Test-Flight-Improv/36-long-press-selected-message-visibility-session-breakdown.md`
    as the closure ledger for this report
  - keep `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
    as a scope guard only unless shared 1:1 correctness unexpectedly changes
- Dependency on earlier sessions:
  - `1`
- Session `2` dependency refresh after Session `1`:
  - the shared overlay contract now exposes the selected-message host needed
    for feed parity work
  - Session `2` should refresh against the landed `MessageContextOverlay` and
    `ConversationScreen` implementation before choosing the smallest safe feed
    adoption path
- Session `2` closure update (`2026-03-31`):
  - status: `accepted`
  - execution verdict: `accepted`
  - files landed:
    - `lib/features/feed/presentation/screens/feed_screen.dart`
    - `test/features/feed/presentation/screens/feed_screen_test.dart`
    - `test/features/feed/presentation/screens/feed_wired_test.dart`
  - direct tests passed:
    - `flutter test test/features/feed/presentation/screens/feed_screen_test.dart`
    - `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
    - `flutter test test/features/feed/presentation/widgets/scrollable_message_preview_test.dart`
    - `flutter test test/features/feed/integration/feed_card_flow_test.dart`
    - `flutter test test/features/feed/integration/expanded_collapsed_card_test.dart`
  - named gates passed:
    - `./scripts/run_test_gates.sh baseline`
    - `./scripts/run_test_gates.sh feed`
  - conditional gates not required:
    - `./scripts/run_test_gates.sh 1to1` was not needed because the landed
      change stayed on overlay presentation and feed routing parity rather than
      widening into feed-originated send/reply correctness
  - closure docs touched:
    - `Test-Flight-Improv/36-long-press-selected-message-visibility-session-breakdown.md`
  - concise note:
    - feed thread cards now keep the selected message visibly present inside the
      shared overlay across collapsed and expanded routes while preserving
      existing reply/copy/edit/delete/reaction behavior

## Why this is not fewer sessions

- One monolithic plan would mix the shared overlay/conversation seam with the
  feed card parity seam, even though they have different direct regressions and
  different named gate expectations.
- The feed surface spans its own card-body and preview-routing tree. Keeping it
  in Session `2` makes the closure bar and gate ownership explicit instead of
  burying feed-specific work inside a larger UI plan.
- Session `1` still ends in a meaningful verified state: the shared overlay
  plus direct conversation surface can prove selected-message visibility and
  anchored continuity without waiting for feed adoption.

## Why this is not more sessions

- Splitting the shared overlay host away from the conversation surface would
  create an implementation slice with weak standalone verification value.
- Splitting collapsed-feed and expanded-feed work into separate sessions would
  be bookkeeping overhead because both ride the same feed card/preview routing
  seam and the same `feed` gate family.
- A separate acceptance-only or closure-only session would not add independent
  verification value beyond bundling final closure into Session `2`.

## Regression and gate contract

- Per `Test-Flight-Improv/14-regression-test-strategy.md`, each session should
  add the exact direct regression for the bug seam first, then run the direct
  suite for the changed files.
- Session `1` should run the direct overlay/conversation widget-screen suite and
  `./scripts/run_test_gates.sh baseline` because Flutter production UI code is
  changing.
- Session `2` should run the direct feed suite, `./scripts/run_test_gates.sh baseline`,
  and `./scripts/run_test_gates.sh feed` because feed cards and message preview
  surfaces are changing.
- Companion `./scripts/run_test_gates.sh 1to1` is not part of the default split
  for this report. It becomes required only if implementation drifts into
  feed-originated quote/send semantics or other shared 1:1 correctness paths.
- No new named gate is justified for this UI-only bug. Existing gate definitions
  already provide the right bounded coverage model.

## Matrix update contract

- No stable overlay-specific matrix or closure doc currently owns this seam.
- `Test-Flight-Improv/12-1to1-chat-use-case-audit.md` and
  `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md` are
  scope guards and evidence docs, not the closure owner for report `36`.
- The doc-scoped artifact
  `Test-Flight-Improv/36-long-press-selected-message-visibility-session-breakdown.md`
  is the live ledger and must be updated during downstream closure.
- Session `2` owns the final closure update for that ledger after cross-surface
  acceptance is complete.

## Reviewer pass

- Is the recommended session count sufficient, too coarse, or too fragmented?
  - sufficient
- Which proposed sessions should merge?
  - none
- Which proposed sessions must split?
  - none
- What tests or named gates are missing from the decomposition?
  - none structurally; Session `1` needs direct overlay/conversation regressions
    plus `baseline`, and Session `2` needs direct feed regressions plus
    `baseline` and `feed`
- Does each session end in a meaningful verified state?
  - yes
- Is the matrix-update responsibility assigned clearly?
  - yes
- What is the minimum session set that is still safe?
  - `2`

## Arbiter outcome

- Structural blockers:
  - none
- Mergeable sessions:
  - none
- Required splits:
  - none
- Accepted differences:
  - group and announcement long-press flows stay on their current
    reaction-only path
  - existing reply, copy, edit, delete, and reaction eligibility rules stay
    unchanged
  - exact animation tokens, blur values, and rendering strategy stay open for
    the later plan/execution pass as long as the source doc's user-visible
    contract is met

## Structural blockers remaining

- none

## Accepted differences intentionally left unchanged

- `Test-Flight-Improv/26-long-press-message-context-menu-session-breakdown.md`
  remains historical context only; report `36` does not reopen the broader
  long-press action feature.
- This decomposition does not widen into transport, retry, quote-send, or other
  shared 1:1 reliability semantics.
- No new shared UI matrix doc is introduced for this seam.

## Exact docs/files used as evidence

- `Test-Flight-Improv/36-long-press-selected-message-visibility.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/12-1to1-chat-use-case-audit.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/26-long-press-message-context-menu-session-breakdown.md`
- `lib/features/conversation/presentation/widgets/message_context_overlay.dart`
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
- `lib/features/conversation/presentation/widgets/letter_card.dart`
- `lib/features/conversation/presentation/widgets/reaction_bar.dart`
- `lib/features/feed/presentation/screens/feed_screen.dart`
- `lib/features/feed/presentation/widgets/feed_card.dart`
- `lib/features/feed/presentation/widgets/open_mode_card_body.dart`
- `lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart`
- `lib/features/feed/presentation/widgets/scrollable_message_preview.dart`
- `lib/features/feed/presentation/widgets/message_bubble.dart`
- `test/features/conversation/presentation/widgets/message_context_overlay_test.dart`
- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/features/feed/presentation/screens/feed_screen_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/features/feed/presentation/widgets/scrollable_message_preview_test.dart`
- `test/features/feed/integration/feed_card_flow_test.dart`
- `test/features/feed/integration/expanded_collapsed_card_test.dart`

## Downstream execution path status

- Session `1` completed planning, execution/QA, and closure with an `accepted`
  result.
- Session `2` completed planning, execution/QA, and closure with an `accepted`
  result.
- No further downstream execution remains for report `36`.

## Final program acceptance

- Final program verdict:
  - `closed`
- Docs updated:
  - `Test-Flight-Improv/36-long-press-selected-message-visibility-session-breakdown.md`
  - `Test-Flight-Improv/36-long-press-selected-message-visibility-session-1-plan.md`
  - `Test-Flight-Improv/36-long-press-selected-message-visibility-session-2-plan.md`
- What is now considered closed:
  - direct conversation and feed thread-card long-press overlays keep the
    selected message visibly present as the focal element
  - the reaction row and context menu remain anchored to that selected message
    across the landed conversation and feed routes
  - top/bottom clamping remains covered on the shared overlay path
  - existing reply, copy, edit, delete, reaction, and backdrop-dismiss behavior
    stayed intact under current rules
- Residual-only items:
  - none
- Still-open items:
  - none within report `36` scope
- Accepted differences:
  - group and announcement long-press flows remain on their current
    reaction-only path
  - exact animation tokens and visual tuning remain implementation details, not
    closure blockers, because the user-visible anchored-message contract now
    holds on the covered surfaces
- Why the rollout is safe to complete:
  - both runnable sessions reached `accepted`
  - the direct conversation and feed suites passed
  - the required `baseline` and `feed` gates passed
  - no shared 1:1 correctness path changed, so not running `1to1` remained
    consistent with the gate contract
