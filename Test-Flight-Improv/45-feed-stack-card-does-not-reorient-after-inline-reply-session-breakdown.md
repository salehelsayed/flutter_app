# 45 - Feed Stack Card Does Not Reorient After Inline Reply Session Breakdown

## Decomposition artifact updated

- Artifact path:
  `Test-Flight-Improv/45-feed-stack-card-does-not-reorient-after-inline-reply-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/45-feed-stack-card-does-not-reorient-after-inline-reply.md`
- Decomposition date:
  `2026-04-03`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution

## Recommended plan count

- `1`

## Overall closure bar

Report `45` is closed only when Feed no longer loses the active conversation
target after a successful inline reply, without reopening adjacent unread-truth,
send-path, or host-navigation seams that already have their own closure owners:

- when a user replies inline from a visible 1:1 Feed stack card and that card
  collapses, changes height, or moves to a new sorted position, the viewport
  re-orients to that same card instead of staying anchored to stale surrounding
  content
- the same card remains immediately usable for the next follow-up reply without
  a manual search scroll
- this stays true when the inline composer unfocuses as part of send success
- repeated successful inline replies from the same Feed card do not drift the
  viewport away after the first success
- existing card-state transitions after reply, Feed-only unread truth from
  Report `40`, Feed/Orbit handled-notification truth from Report `44`, and
  general Feed scroll preservation for unrelated Feed/Orbit round trips remain
  intact
- the repo gains direct regression proof for this escaped viewport-continuity
  sequence instead of relying only on adjacent scroll-storage and post-reply
  state tests

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/45-feed-stack-card-does-not-reorient-after-inline-reply.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/00-INDEX.md`
- `Test-Flight-Improv/40-feed-stack-card-keeps-earlier-notification-messages-after-inline-reply-session-breakdown.md`
- `Test-Flight-Improv/44-feed-orbit-notification-desync-session-breakdown.md`

Current repo facts that govern the split:

- `lib/features/feed/presentation/screens/feed_screen.dart` renders Feed through
  one `CustomScrollView` keyed with `PageStorageKey('feed-scroll')`, so the
  current surface preserves a raw scroll offset rather than any per-card
  viewport anchor.
- `lib/features/feed/presentation/screens/feed_screen.dart` partitions unread or
  active threads above the divider and read or replied threads below it, with
  both sections sorted by descending timestamp, so a successful reply can move
  the same thread between sections and change its rendered height.
- `lib/features/feed/presentation/screens/feed_screen.dart` keys cards by
  `ValueKey(item.id)` and provides `findChildIndexCallback`, so the screen
  already has stable card identity that a viewport-follow fix can reuse.
- `lib/features/feed/presentation/screens/feed_wired.dart` tracks a
  `SessionReply` optimistically, then on successful inline reply marks the
  conversation read and refreshes that contact's Feed item, which is the exact
  mutation point that collapses and reorders the card.
- `lib/features/feed/presentation/screens/feed_wired.dart` and
  `lib/features/feed/presentation/widgets/inline_reply_input.dart` already own
  focus handoff for inline reply, but current focus management only requests or
  clears focus; it does not re-anchor the viewport after the card moves.
- `test/features/feed/presentation/screens/feed_screen_test.dart` already proves
  Feed stays sliver-backed through `CustomScrollView`, not an eager
  `SingleChildScrollView`.
- `test/features/feed/presentation/screens/feed_wired_test.dart` already proves
  Feed scroll position survives an inline Feed/Orbit round trip, successful
  inline reply collapses into replied state, and older unread rows do not
  resurface after reply, but no direct test proves `visible card -> successful
  inline reply -> card repositions -> viewport follows the same card`.

Source-of-truth conflicts that materially affected decomposition:

- The proposal intentionally leaves the exact final alignment open. Current repo
  evidence narrows the live seam to Feed-owned viewport management after inline
  reply success, not to shared 1:1 durability or a new shell-navigation
  architecture.
- Report `40` already owns Feed unread-preview truth after inline reply, and
  Report `44` already owns mounted Orbit handled-notification synchronization.
  This report should preserve those seams, not silently reopen them.
- No stable area-specific closure reference already exists for this exact
  viewport seam beyond `00-INDEX.md`, so the doc-scoped breakdown artifact for
  Report `45` should become the reusable closure ledger instead of inventing a
  new matrix doc.

## Evidence collector summary

- The escaped behavior is local to Feed's screen-level viewport ownership and
  the inline-reply success mutation point.
- The likely implementation seam sits in `feed_screen.dart` and
  `feed_wired.dart`, with card/widget files only as conditional helpers if the
  final implementation needs a stronger per-card anchor or post-layout signal.
- The direct regression family is also local to Feed screen tests; no separate
  transport, inbox, or app-root notification evidence gate is needed up front.

## Closure mapper

- Real closure target:
  after a successful inline reply from a visible 1:1 Feed stack card, the user
  stays visually oriented to that same card even if the card collapses or
  reorders.
- Correctness and reliability work:
  Feed viewport reorientation, preservation of existing post-reply card-state
  transitions, and regression proof that the same card remains the active
  interaction target.
- Evidence-only or acceptance-only work:
  none as a separate session; direct proof and closure refresh belong with the
  implementation because this report is only closed when the fix and proof land
  together.
- Explicit non-goals:
  no redesign of Feed/Orbit host navigation, no new generic per-item scroll
  persistence framework, no change to whether the card should collapse after
  reply, no group-card parity work, and no full-conversation-screen behavior
  changes.

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Execution verdict | Matrix / closure docs touched | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `1` | `Feed inline-reply viewport reorientation and proof` | `implementation-ready` | `Test-Flight-Improv/45-feed-stack-card-does-not-reorient-after-inline-reply-session-1-plan.md` | none | `accepted` | `accepted` | `Test-Flight-Improv/45-feed-stack-card-does-not-reorient-after-inline-reply-session-breakdown.md`, `Test-Flight-Improv/00-INDEX.md`; `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md` intentionally stayed unchanged because execution remained local to Feed viewport continuity | One Feed-owned UI seam landed: successful inline reply now re-orients the viewport to the same moved card, direct regressions prove the escaped sequence, and the closure ledger is refreshed. |

## Ordered session breakdown

### Session 1

- Title:
  `Feed inline-reply viewport reorientation and proof`
- Session id:
  `1`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/45-feed-stack-card-does-not-reorient-after-inline-reply-session-1-plan.md`
- Exact scope:
  - add a Feed-owned viewport-follow mechanism so a successful inline reply on a
    visible 1:1 card re-orients the scroll view around that same card's new
    post-reply location instead of preserving the stale absolute offset
  - preserve current successful inline reply behavior: optimistic session-reply
    state, card collapse or replied presentation, read-marking, and later unread
    projection truth already covered by Report `40`
  - preserve general Feed scroll storage for unrelated Feed/Orbit round trips
    already covered by existing tests
  - add the missing direct regressions for:
    - mid-scroll visible 1:1 Feed card -> successful inline reply -> card
      collapses or reorders -> viewport still keeps that same card visible
    - consecutive successful inline replies from the same card do not let the
      viewport drift away after the first success
  - refresh the doc-scoped closure ledger after code and regressions land
- Why it is its own session:
  - this is one coherent Feed presentation seam with one user-visible closure
    bar
  - it shares one primary direct regression family and one bounded gate contract
  - splitting viewport reorientation, proof, and closure refresh would add
    bookkeeping without independent verification value because the report is not
    closed until all three land together
- Likely code-entry files:
  - `lib/features/feed/presentation/screens/feed_screen.dart`
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/feed/presentation/widgets/feed_card.dart` only if the final
    implementation needs a stronger post-layout anchor or card-level callback
    than the existing keyed sliver entries already provide
  - `lib/features/feed/presentation/widgets/inline_reply_input.dart` only if the
    final implementation needs explicit post-send or focus-settle coordination
    beyond the current `shouldRequestFocus` behavior
- Likely direct tests/regressions:
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
  - `test/features/feed/presentation/screens/feed_screen_test.dart` if the final
    implementation adds screen-level controller or anchoring behavior that
    should be pinned independently
  - `test/features/feed/integration/expanded_collapsed_card_test.dart` only if
    execution changes visible card transition structure rather than only screen
    viewport behavior
  - `test/features/feed/integration/feed_card_flow_test.dart` only if planning
    later proves one higher-layer product-facing flow is needed beyond the
    screen/widget regression
- Likely named gates:
  - `./scripts/run_test_gates.sh feed`
  - companion `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh baseline`
  - `./scripts/run_test_gates.sh transport` only if planning later proves the
    implementation widened into startup, route-open, reconnect, or other
    transport-owned behavior, which current repo evidence does not indicate
- Matrix/closure docs to update when done:
  - required:
    - `Test-Flight-Improv/45-feed-stack-card-does-not-reorient-after-inline-reply-session-breakdown.md`
    - `Test-Flight-Improv/00-INDEX.md`
  - intentionally unchanged unless execution truly widens scope:
    - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- Dependency on earlier sessions:
  - none
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Reviewer pass

- Is the recommended session count sufficient, too coarse, or too fragmented:
  - sufficient; current repo evidence supports one bounded Feed-owned session
- Which proposed sessions should merge:
  - none
- Which proposed sessions must split:
  - none
- What tests or named gates are missing from the decomposition:
  - the missing direct viewport-follow regression in
    `test/features/feed/presentation/screens/feed_wired_test.dart`
  - a screen-level regression in `feed_screen_test.dart` only if final planning
    introduces explicit scroll-controller or ensure-visible ownership there
- Does each session end in a meaningful verified state:
  - yes; Session `1` ends in a user-visible Feed fix, direct proof, and refreshed
    closure ownership
- Is the matrix-update responsibility assigned clearly:
  - yes; the new Report `45` breakdown artifact is the doc-scoped closure owner
    and `00-INDEX.md` is the stable shared closure ledger
- What is the minimum session set that is still safe:
  - `1`

## Arbiter outcome

- Structural blockers:
  - none
- Mergeable sessions:
  - none
- Required splits:
  - none
- Accepted differences:
  - the final viewport alignment can stay implementation-defined as long as the
    same card is clearly re-oriented as the active interaction target
  - group-thread parity stays out of scope
  - broader Feed/Orbit host-navigation or app-shell scroll-restore work stays
    out of scope

## Why this is not fewer sessions

- The report cannot safely collapse to a tests-only or closure-only note because
  the bug is only closed when the viewport-follow fix and its direct proof land
  together.
- One doc-scoped implementation session is the minimum safe set because the
  code seam, regression family, and closure owner are all the same Feed screen
  behavior.

## Why this is not more sessions

- Splitting viewport anchoring, reply-success wiring, and closure refresh into
  separate sessions would be bookkeeping overhead around one user-visible Feed
  seam.
- A separate evidence-gated session is not justified because current code and
  tests already localize the gap to Feed viewport continuity after inline reply.
- A separate acceptance-only session is not justified because this report does
  not validate multiple earlier slices; it validates one local Feed behavior.

## Regression and gate contract

- Use `Test-Flight-Improv/14-regression-test-strategy.md` as the policy
  reference and `Test-Flight-Improv/test-gate-definitions.md` as the execution
  source of truth.
- Add the direct escaped regression first for:
  `visible 1:1 Feed stack card mid-scroll -> successful inline reply -> card
  collapses or reorders -> viewport follows the same card`.
- Preserve adjacent direct proof already covering:
  - Feed scroll storage across Feed/Orbit round trips
  - successful inline reply collapse or replied-state transition
  - Feed unread-preview truth after inline reply from Report `40`
  - mounted Orbit handled-notification truth from Report `44` if the final
    execution touches shared post-reply refresh wiring
- Run:
  - `./scripts/run_test_gates.sh feed`
  - companion `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh baseline`
- Do not widen into `transport` unless later planning proves the implementation
  actually touched startup, reconnect, or notification-open ownership.

## Matrix update contract

- No new matrix doc should be created for this report.
- The reusable closure owner for this seam is the new doc-scoped artifact:
  `Test-Flight-Improv/45-feed-stack-card-does-not-reorient-after-inline-reply-session-breakdown.md`.
- Session `1` owns refreshing:
  - this breakdown artifact with the final acceptance result
  - `Test-Flight-Improv/00-INDEX.md` with the new maintain or residual entry
- Reports `40` and `44` remain adjacent evidence and regression constraints, not
  closure-owner docs for Report `45`, unless execution uncovers a real shared
  residual that genuinely reopens them.
- Closure outcome:
  - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
    stayed untouched because the accepted implementation changed Feed-local
    viewport continuity only, not the broader shared 1:1 reliability bar

## Session 1 closure result

- Execution verdict:
  `accepted`
- Landed scope:
  - `lib/features/feed/presentation/screens/feed_wired.dart` now records a
    one-shot same-contact viewport-follow request only after successful inline
    reply refresh for the affected 1:1 Feed card
  - `lib/features/feed/presentation/screens/feed_screen.dart` now owns the
    same-card reorientation seam through a keyed scrollable wrapper that keeps
    the moved card visible after collapse or reorder, using direct
    `ensureVisible` when mounted and a bounded estimated-offset follow-up when
    the new card location is not mounted yet
  - `test/features/feed/presentation/screens/feed_wired_test.dart` now proves
    the escaped `visible card -> successful inline reply -> moved card stays in
    viewport` sequence while existing adjacent Feed scroll and post-reply
    behavior tests remain green
- Direct proof run on `2026-04-03`:
  - `flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name "successful inline reply reorients the viewport to the same moved feed card"`
  - `flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name "feed scroll position survives an inline orbit round trip"`
  - `flutter test test/features/feed/presentation/screens/feed_screen_test.dart`
  - `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
  - `./scripts/run_test_gates.sh feed`
  - `./scripts/run_test_gates.sh 1to1`
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`
- Operational note:
  - the first plain `./scripts/run_test_gates.sh baseline` invocation stopped
    on Flutter's multiple-device selection requirement before any product-code
    failure surfaced; the supported rerun with `FLUTTER_DEVICE_ID=macos`
    completed green
- Closure outcome:
  - this breakdown artifact plus `Test-Flight-Improv/00-INDEX.md` now carry the
    maintenance-time closure meaning for Report `45`

## Final program acceptance review

- Sessions processed:
  `1`
- Sessions accepted:
  `1`
- Sessions accepted_with_explicit_follow_up:
  none
- Sessions blocked:
  none
- Sessions skipped_due_to_dependency:
  none
- Final program acceptance verdict:
  `closed`
- Final program blocker:
  none
- Why the rollout is safe to complete:
  - successful inline reply now keeps the same moved 1:1 Feed card visible and
    immediately usable instead of leaving the user anchored to stale nearby
    content
  - the landed fix stayed inside the intended Feed-owned seam without reopening
    Report `40` unread truth, Report `44` handled-notification sync, or broader
    Feed/Orbit navigation architecture
  - the direct suites plus `feed`, `1to1`, and macOS-backed `baseline` all
    passed on `2026-04-03`
  - the stable closure docs now encode the narrow maintenance rule for this
    viewport-continuity seam without inventing a new matrix or shared closure
    reference

## Structural blockers remaining

- none

## Accepted differences intentionally left unchanged

- exact post-send card alignment can remain flexible if the same card is kept
  comfortably visible for immediate follow-up interaction
- the exact internal anchoring mechanism remains implementation-defined; the
  maintained contract is same-card visibility and follow-up usability rather
  than pixel-identical post-send positioning
- group-thread behavior, full conversation screen behavior, and unrelated tab
  round-trip scroll persistence stay unchanged

## Exact docs/files used as evidence

- `Test-Flight-Improv/45-feed-stack-card-does-not-reorient-after-inline-reply.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/00-INDEX.md`
- `Test-Flight-Improv/40-feed-stack-card-keeps-earlier-notification-messages-after-inline-reply-session-breakdown.md`
- `Test-Flight-Improv/44-feed-orbit-notification-desync-session-breakdown.md`
- `lib/features/feed/presentation/screens/feed_screen.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/feed/presentation/widgets/feed_card.dart`
- `lib/features/feed/presentation/widgets/inline_reply_input.dart`
- `test/features/feed/presentation/screens/feed_screen_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/features/feed/integration/expanded_collapsed_card_test.dart`
- `test/features/feed/integration/feed_card_flow_test.dart`

## Why the decomposition is safe to send into downstream planning/execution

- The session set is minimal but not under-scoped: one Feed-owned implementation
  session covers the real code seam, the missing direct regressions, and the
  required closure refresh.
- Adjacent but different seams already have closure owners (`40`, `44`, and the
  global `00-INDEX.md`), so this breakdown avoids reopening them without
  evidence.
- The plan file path is doc-scoped and ready for the downstream
  plan -> execution -> closure workflow.
