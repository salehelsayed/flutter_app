# 32 - Notification Card Interactions Session Breakdown

## Decomposition artifact updated

- Artifact path:
  `Test-Flight-Improv/32-notification-card-interactions-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/32-notification-card-interactions.md`
- Decomposition date:
  `2026-03-31`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution

## Recommended plan count

- `0`
- The smallest safe historical split is one notification-route audit slice and
  one feed open-mode interaction slice, but current repo state already covers
  both, so no new plan files should be created unless a fresh repro proves the
  current evidence wrong.

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Retry attempts used | Final execution verdict | Blocker class | Closure docs touched | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `1` | Notification route boundary and stale-repro audit | `stale/already-covered` | `Test-Flight-Improv/32-notification-card-interactions-session-1-plan.md` | none | `stale/already-covered` | `0` | `not run; stale/already-covered` | none | `Test-Flight-Improv/32-notification-card-interactions-session-breakdown.md` | Confirmed `stale/already-covered` on `2026-03-31`: current `lib/main.dart` still routes conversation targets directly to `ConversationWired` and group targets directly to `GroupConversationWired`, and `flutter test test/integration/notification_deeplink_integration_test.dart` passed. |
| `2` | Feed open-mode interaction parity and closure | `stale/already-covered` | `Test-Flight-Improv/32-notification-card-interactions-session-2-plan.md` | `1` | `stale/already-covered` | `0` | `not run; stale/already-covered` | none | `Test-Flight-Improv/32-notification-card-interactions-session-breakdown.md` | Confirmed `stale/already-covered` on `2026-03-31`: `OpenModeCardBody`, `FeedCard`, and `FeedWired` still expose the current open-mode avatar/view-conversation and collapse seams, and the targeted direct suites passed (`open_mode_card_body_test.dart`, `expanded_collapsed_card_test.dart`, and the `feed_wired_test.dart` collapse/view-earlier cases). |

## Overall closure bar

Report `32` is closed only when current repo evidence shows the original
notification-opened Feed repro is no longer the live product path, and the
remaining open-mode card interactions already behave honestly on the current
surfaces:

- conversation and group notification taps route into their full conversation
  surfaces instead of depending on a Feed card to become interactive first
- feed open-mode cards still expose working avatar/view-conversation and
  collapse interactions on the live manual and live-message paths
- feed-to-conversation handoff, unread/open-mode collapse behavior, and group
  parity remain intact
- no new bootstrap, inbox-drain, or transport fallback regressions are
  introduced while validating this stale report

## Final program acceptance

- Closure verdict:
  `closed`
- Acceptance date:
  `2026-03-31`
- What is now closed:
  - conversation and group notification taps no longer depend on Feed to host
    an already-open card first; current app-root routing opens the full
    conversation surfaces directly
  - the feed-side open-mode avatar/view-conversation and collapse interactions
    are already wired and still pass the focused direct widget/screen/
    integration evidence suite
  - report `32` therefore closes as a stale reproduction against the current
    repo rather than a missing implementation slice
- Residual-only items:
  - none
- Still-open items:
  - none
- Reopen only on real regression:
  - if notification conversation/group taps stop routing into
    `ConversationWired` / `GroupConversationWired` and start depending on a
    feed-open-card path again
  - if open-mode avatar/view-conversation or collapse behavior regresses on the
    live feed surfaces
  - if the direct notification/feed suites fail, or if future app-root changes
    touching notification/bootstrap wiring stop passing `baseline`

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/32-notification-card-interactions.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`

Current repo facts that governed the split:

- `lib/main.dart` currently routes
  `NotificationRouteTargetKind.conversation` directly into
  `ConversationWired` and `NotificationRouteTargetKind.group` directly into
  `GroupConversationWired`, so the source report's "notification opens Feed
  with an already-open card" reproduction is stale against current app-root
  behavior unless a fresh external repro proves otherwise.
- `test/integration/notification_deeplink_integration_test.dart` already
  covers the notification boundary sequencing for conversation and group route
  targets through prepare/drain/route dispatch, which makes the notification
  seam an evidence/closure problem rather than an obvious implementation gap.
- `lib/features/feed/presentation/widgets/feed_card.dart` already passes
  `onViewFullConversation` and `onToggleExpand` into the open-mode body, so
  the current feed code does not show a notification-only null-callback seam.
- `lib/features/feed/presentation/widgets/open_mode_card_body.dart` already
  wires avatar taps to `onViewEarlier`, and
  `test/features/feed/presentation/widgets/open_mode_card_body_test.dart`
  already proves the avatar callback fires.
- `lib/features/feed/presentation/screens/feed_wired.dart` already routes
  `_onViewFullConversation(...)` into `_onReplyToMessage(...)`, which pushes
  `ConversationWired`, and `_onToggleExpand(...)` already marks unread open
  cards read and collapses them without leaving the collapsed card expanded.
- `test/features/feed/presentation/screens/feed_wired_test.dart` already
  covers open-mode collapse for 1:1 and group cards plus the delayed
  "View earlier messages" navigation handoff.
- `test/features/feed/integration/expanded_collapsed_card_test.dart` already
  covers the feed-card interaction seam for collapse and view-full-conversation
  behavior.
- `Test-Flight-Improv/test-gate-definitions.md` keeps
  `test/integration/notification_deeplink_integration_test.dart` outside the
  frozen named gates as an optional/manual direct suite, while feed-surface
  changes still belong to the `feed` gate and companion `1to1` only when the
  feed can enter the shared send path.

Source-of-truth conflicts that materially affected decomposition:

- The source report's reproduction narrative assumes a notification-opened
  conversation lands on Feed first, but current `lib/main.dart` routes
  conversation and group notifications directly into their full conversation
  surfaces.
- The source report speculates about feed callback initialization timing, but
  current widget wiring passes the callbacks synchronously and the existing
  widget/screen tests already exercise the relevant open-mode callback seams.

## Reviewer pass

- Sufficiency:
  `2` historical slices are sufficient. The stale notification-route seam and
  the already-covered feed interaction seam have different code-entry files and
  different direct-suite evidence, so they should stay distinguishable even
  though neither warrants a new implementation session.
- Merge candidates:
  none.
- Required splits:
  none.
- Missing tests or named gates:
  none at decomposition time. A future reopen should use the notification
  direct suite, the feed widget/screen/integration suites, `feed` when feed
  surface behavior changes, companion `1to1` only if the feed send path moves,
  and `baseline` if app-root notification/bootstrap wiring changes.
- Meaningful verified state:
  yes. The notification route seam can be closed from current app-root
  evidence, and the feed interaction seam can be closed from current
  widget/screen/integration evidence without inventing a speculative fix.
- Matrix responsibility:
  clear. No separate stable closure reference exists for this stale report yet,
  so this breakdown artifact is the live doc-scoped closure ledger.
- Minimum safe session set:
  `2`.

## Arbiter outcome

- Structural blockers:
  none.
- Mergeable sessions:
  none.
- Required splits:
  none.
- Accepted differences:
  - conversation and group notification taps now open their full conversation
    surfaces directly instead of depending on Feed to host an already-open card
  - notification-route validation stays a direct-suite boundary, not a frozen
    named gate member, unless future work widens that scope
  - blocked-contact notification/card behavior remains governed by the
    existing card/blocking semantics and is not expanded here without a fresh
    repro

## Ordered session breakdown

### Session 1

- Title:
  `Notification route boundary and stale-repro audit`
- Session id:
  `1`
- Session classification:
  `stale/already-covered`
- Intended plan file:
  `Test-Flight-Improv/32-notification-card-interactions-session-1-plan.md`
- Exact scope:
  - confirm whether the current app-root notification path still reproduces the
    report's "Feed opens with an already-open card" narrative
  - anchor the current route boundary in repo evidence rather than stale prose
  - avoid speculative feed-card fixes unless current routing evidence says Feed
    still owns the notification-opened interaction path
- Why it is its own session:
  - the app-root notification route boundary lives in `lib/main.dart` and the
    notification dispatch tests, not in the feed-card widget tree
  - if this slice stays stale/already-covered, the feed implementation should
    not be reopened just because the old bug report mentions Feed
- Likely code-entry files:
  - `lib/main.dart`
  - `lib/core/notifications/notification_route_dispatch.dart`
  - `lib/core/notifications/notification_route_target.dart`
- Likely direct tests/regressions:
  - `test/integration/notification_deeplink_integration_test.dart`
- Likely named gates:
  - none by default
  - `./scripts/run_test_gates.sh baseline` only if a future reopen edits
    app-root notification/bootstrap wiring
  - `./scripts/run_test_gates.sh transport` only if a future reopen changes
    inbox-drain, bootstrap, reconnect, or transport-fallback behavior
- Matrix/closure docs to update when done:
  - refresh this breakdown artifact's session ledger
- Dependency on earlier sessions:
  - none

### Session 2

- Title:
  `Feed open-mode interaction parity and closure`
- Session id:
  `2`
- Session classification:
  `stale/already-covered`
- Intended plan file:
  `Test-Flight-Improv/32-notification-card-interactions-session-2-plan.md`
- Exact scope:
  - confirm the current feed open-mode avatar/view-conversation and collapse
    seams are already wired and covered on the live manual and live-message
    paths
  - treat notification-opened Feed behavior as stale unless Session `1`
    disproves the current direct-route evidence
  - keep this report from reopening feed-card work that current widget/screen
    regressions already pin
- Why it is its own session:
  - feed interaction parity lives in `FeedCard`, `OpenModeCardBody`,
    `FeedWired`, and feed widget/screen/integration suites rather than the
    app-root notification dispatcher
  - it needs different reopen evidence and different named gates from Session
    `1`
- Likely code-entry files:
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/feed/presentation/widgets/feed_card.dart`
  - `lib/features/feed/presentation/widgets/open_mode_card_body.dart`
  - `lib/features/feed/presentation/widgets/scrollable_message_preview.dart`
- Likely direct tests/regressions:
  - `test/features/feed/presentation/widgets/open_mode_card_body_test.dart`
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
  - `test/features/feed/integration/expanded_collapsed_card_test.dart`
- Likely named gates:
  - none for the current stale/already-covered verdict
  - `./scripts/run_test_gates.sh feed` if a future reopen changes feed cards,
    feed composer, or feed-to-conversation handoff
  - companion `./scripts/run_test_gates.sh 1to1` only if that future reopen
    also changes feed-originated 1:1 send entry
- Matrix/closure docs to update when done:
  - refresh this breakdown artifact's session ledger
- Dependency on earlier sessions:
  - `1`

## Why this is not fewer sessions

- The stale notification-route seam and the feed interaction seam live in
  different files, use different direct regressions, and reopen under
  different gate rules. Bundling them into one historical slice would blur
  whether a future regression belongs to app-root notification dispatch or the
  feed widget tree.

## Why this is not more sessions

- No current repo evidence justifies splitting 1:1 versus group notification
  routing into separate sessions; both are handled by the same app-root route
  target switch.
- No current repo evidence justifies splitting avatar taps, "View earlier",
  and collapse into separate feed sessions; they are all part of the same
  already-covered open-mode interaction seam.
- Because the report is stale/already-covered, adding acceptance-only or
  closure-only sessions now would create bookkeeping without new verified
  value.

## Regression and gate contract

- If a future reopen touches notification route dispatch, rerun
  `test/integration/notification_deeplink_integration_test.dart` and
  `./scripts/run_test_gates.sh baseline`.
- If a future reopen touches feed open-mode card interactions or
  feed-to-conversation handoff, rerun the direct feed widget/screen/integration
  suites and `./scripts/run_test_gates.sh feed`.
- Add companion `./scripts/run_test_gates.sh 1to1` only when a future feed
  reopen changes a feed-originated 1:1 send path rather than pure navigation
  or collapse behavior.
- `./scripts/run_test_gates.sh transport` stays out unless bootstrap,
  inbox-drain, reconnect, or transport fallback wiring actually changes.
- `./scripts/run_test_gates.sh completeness-check` is only required if future
  work edits `Test-Flight-Improv/test-gate-definitions.md` or reclassifies
  tests.

## Matrix update contract

- No stable notification-card closure reference exists for this area yet, so
  this breakdown artifact is the live doc-scoped ledger.
- The final closure pass may update `Test-Flight-Improv/00-INDEX.md` or
  `Test-Flight-Improv/17-roadmap-closure-audit.md` if folder-level status
  would otherwise stay stale after closing this report.

## Downstream execution path

- No new session plans should be created now because both historical sessions
  remain `stale/already-covered`.
- The next pipeline step should verify the stale/already-covered session ledger
  is still honest, then run one final whole-doc acceptance/closure pass.

## Program rollout ledger

- Breakdown artifact used:
  `Test-Flight-Improv/32-notification-card-interactions-session-breakdown.md`
- Spawned-agent isolation used:
  `yes` for the attempted decomposition and pipeline passes; both no-progressed
  and were replaced with the single bounded local decomposition and pipeline
  fallbacks
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
  `Test-Flight-Improv/32-notification-card-interactions-session-breakdown.md`
- Final blocker note:
  none

## Structural blockers remaining

- none

## Accepted differences intentionally left unchanged

- conversation and group notifications open their full conversation surfaces
  directly rather than opening Feed first
- notification route validation stays a direct-suite boundary rather than a
  frozen named gate member
- feed open-mode interactions continue to be validated by the existing
  widget/screen/integration coverage unless a fresh repro proves a missing seam

## Exact docs/files used as evidence

- `Test-Flight-Improv/32-notification-card-interactions.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `lib/main.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/feed/presentation/widgets/feed_card.dart`
- `lib/features/feed/presentation/widgets/open_mode_card_body.dart`
- `lib/features/feed/presentation/widgets/scrollable_message_preview.dart`
- `test/integration/notification_deeplink_integration_test.dart`
- `test/features/feed/presentation/widgets/open_mode_card_body_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/features/feed/integration/expanded_collapsed_card_test.dart`
