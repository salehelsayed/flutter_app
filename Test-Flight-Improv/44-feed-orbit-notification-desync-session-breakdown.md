# 44 - Feed Clears A Notification While Orbit Still Shows It As Pending Session Breakdown

## Decomposition artifact updated

- Artifact path:
  `Test-Flight-Improv/44-feed-orbit-notification-desync-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/44-feed-orbit-notification-desync.md`
- Decomposition date:
  `2026-04-02`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution

## Recommended plan count

- `1`

## Overall closure bar

Report `44` is closed only when the same handled 1:1 notification state stops
contradicting itself across Feed and Orbit without widening into unrelated
notification-routing or app-shell redesign work:

- when a notification-led Feed stack card is collapsed, Orbit no longer keeps
  presenting that same contact as still carrying the same pending unread/new
  message state
- when that same Feed stack card is handled by a successful inline reply,
  Orbit also stops presenting the earlier handled notification state for that
  contact
- this stays true both when Orbit is already mounted in the shared Feed/Orbit
  host and when Orbit is opened later after Feed already handled the message
- genuinely new later messages still surface normally on both surfaces
- existing Feed-only unread-stack truth from Report `40`, existing Orbit row
  refresh on incoming events, and the shared Feed/Orbit host behavior from
  Report `30` remain intact
- the repo gains direct regression proof for the missing cross-surface
  sequence instead of relying on adjacent single-surface tests alone

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/44-feed-orbit-notification-desync.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/00-INDEX.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/30-swipe-nav-feed-orbit-session-breakdown.md`
- `Test-Flight-Improv/40-feed-stack-card-keeps-earlier-notification-messages-after-inline-reply-session-breakdown.md`

Current repo facts that govern the split:

- `lib/features/feed/presentation/screens/feed_wired.dart` currently marks a
  conversation read after successful inline reply, refreshes only the Feed
  contact snapshot, and separately reloads the total Feed unread count.
- `lib/features/feed/presentation/screens/feed_wired.dart` currently marks a
  thread read when an unread/active Feed card is collapsed, again refreshing
  only the Feed contact snapshot for that card.
- `lib/features/feed/presentation/screens/feed_wired.dart` now owns the shared
  Feed/Orbit mounted-host seam from Report `30`, including `_hasMountedOrbitHost`,
  `_buildOrbitHost()`, and `_onOrbitEmbeddedExit(...)`.
- `lib/features/orbit/presentation/screens/orbit_wired.dart` keeps its own
  in-memory `_activeFriends` / `_archivedFriends` state and refreshes a single
  Orbit row from `_refreshOrbitFriend(...)`.
- `lib/features/orbit/presentation/screens/orbit_wired.dart` currently refreshes
  Orbit friend rows on incoming chat events, contact updates, and Orbit-owned
  route-return `FeedRouteChanges`, but not from Feed-originated read/handled
  actions.
- `lib/features/orbit/application/load_orbit_data_use_case.dart` builds
  `OrbitFriend.unreadCount` from `ConversationThreadSummary.unreadCount`.
- `lib/features/orbit/presentation/widgets/friend_row.dart` presents
  `UnreadCountBadge` when `friend.unreadCount > 0`, so stale Orbit row summary
  state directly becomes stale user-visible unread UI.
- `lib/features/conversation/application/mark_conversation_read_use_case.dart`
  delegates to `messageRepo.markConversationAsRead(...)`.
- `lib/features/conversation/domain/repositories/message_repository_impl.dart`
  currently calls `dbMarkConversationAsRead(contactPeerId)` without emitting a
  repository change event for that read mutation, unlike status/save updates
  that already notify listeners.
- `test/features/feed/presentation/screens/feed_wired_test.dart` already proves
  the Feed-only unread truth sequence from Report `40`, but it does not prove
  Orbit clears the same handled notification state.
- `test/features/orbit/presentation/screens/orbit_wired_test.dart` already
  proves Orbit row refresh from incoming-message events and route-return
  refreshes, but it does not prove Feed-originated notification clearance
  updates Orbit.

Source-of-truth conflicts that materially affected decomposition:

- The report is phrased in notification language, but current repo evidence
  narrows the live seam to cross-surface unread-state synchronization after
  Feed already handled the message, not to app-root notification-open routing.
- Report `30` already closed the shared Feed/Orbit mounted-host and route-return
  seam as a broader navigation rollout. This report should reuse that current
  host truth and stay scoped to handled-notification synchronization rather
  than reopen sibling-surface architecture work.
- Report `40` already closed Feed-only unread preview truth after inline reply.
  Report `44` is the remaining multi-surface consistency gap, not a re-open of
  Feed's internal unread projection by itself.

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Closure docs touched | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `1` | `Feed/Orbit handled-notification sync and proof` | `implementation-ready` | `Test-Flight-Improv/44-feed-orbit-notification-desync-session-1-plan.md` | none | `accepted` | `Test-Flight-Improv/44-feed-orbit-notification-desync-session-breakdown.md`, `Test-Flight-Improv/00-INDEX.md`; `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md` intentionally left unchanged because the landed fix stayed local to Feed/Orbit handled-state sync | One bounded cross-surface seam landed: Feed now pushes targeted handled-contact refreshes into mounted Orbit, direct regressions cover mounted and later-open states, and the closure ledger is refreshed. |

## Ordered session breakdown

### Session 1

- Title:
  `Feed/Orbit handled-notification sync and proof`
- Session id:
  `1`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/44-feed-orbit-notification-desync-session-1-plan.md`
- Exact scope:
  - make Orbit stop presenting the same contact as still carrying a pending
    unread/new-message notification after Feed already handled that same
    notification by collapse or successful inline reply
  - preserve current Feed stack-card behavior for collapse, session-reply,
    reopen-on-new-incoming, and post-reply unread truth that Report `40`
    already narrowed
  - preserve current Orbit row refresh behavior for genuine incoming events and
    Orbit-owned route returns while adding the missing Feed-originated sync
  - add the missing direct regressions for:
    - Feed handles notification -> Orbit already mounted -> Orbit reflects the
      cleared state in the same session
    - Feed handles notification -> Orbit opened later -> Orbit first render
      reflects the cleared state
  - refresh the doc-scoped closure ledger after code and regressions land
- Why it is its own session:
  - this is one coherent cross-surface Feed/Orbit unread-state seam with one
    user-visible closure bar
  - it shares one primary direct regression family and one bounded maintenance
    contract
  - splitting code, proof, and closure refresh would add bookkeeping without
    independent verification value because the report only becomes closed when
    Orbit and Feed agree again under direct regression
- Likely code-entry files:
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/orbit/presentation/screens/orbit_wired.dart`
  - `lib/features/feed/domain/models/feed_route_changes.dart` only if final
    execution reuses the existing inline-host refresh contract
  - `lib/features/orbit/application/load_orbit_data_use_case.dart` only if
    final execution changes how Orbit rebuilds row summaries
  - `lib/features/orbit/presentation/widgets/friend_row.dart` only if final
    execution needs a narrow Orbit-row presentation adjustment rather than
    summary-truth correction alone
  - `lib/features/conversation/application/mark_conversation_read_use_case.dart`
    and `lib/features/conversation/domain/repositories/message_repository_impl.dart`
    only if the final fix needs shared read-mutation notification rather than a
    Feed/Orbit local refresh seam
- Likely direct tests/regressions:
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
  - `test/features/orbit/presentation/screens/orbit_wired_test.dart`
  - `test/features/feed/integration/expanded_collapsed_card_test.dart` only if
    final execution needs one higher-layer product-facing collapse proof
  - `test/features/feed/integration/feed_card_flow_test.dart` only if final
    execution changes visible Feed card structure rather than only cross-surface
    sync wiring
  - `test/integration/notification_deeplink_integration_test.dart` only if
    planning later proves the implementation necessarily widens back into
    notification-open entry wiring instead of staying on handled-state sync
- Likely named gates:
  - `./scripts/run_test_gates.sh feed`
  - companion `./scripts/run_test_gates.sh 1to1` if the landed change touches
    Feed's inline reply completion or other shared 1:1 entry behavior instead
    of staying purely on local refresh wiring
  - `./scripts/run_test_gates.sh baseline`
  - `./scripts/run_test_gates.sh transport` only if planning later proves the
    fix widened into startup, inbox-drain, reconnect, or app-root notification
    routing behavior
- Matrix/closure docs to update when done:
  - required:
    - `Test-Flight-Improv/44-feed-orbit-notification-desync-session-breakdown.md`
    - `Test-Flight-Improv/00-INDEX.md`
  - conditional:
    - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
      only if the landed implementation materially changes the broader shared
      1:1 closure claim instead of staying local to Feed/Orbit handled-state
      sync
- Dependency on earlier sessions:
  - none
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Reviewer pass

- Is the recommended session count sufficient, too coarse, or too fragmented:
  - sufficient; current repo evidence supports one bounded implementation-ready
    cross-surface seam
- Which proposed sessions should merge:
  - none
- Which proposed sessions must split:
  - none
- What tests or named gates are missing from the decomposition:
  - the missing direct cross-surface regressions in
    `test/features/feed/presentation/screens/feed_wired_test.dart` and/or
    `test/features/orbit/presentation/screens/orbit_wired_test.dart` must be
    added during execution
  - higher-layer Feed integration proof is conditional, based on final code
    ownership
- Does each session end in a meaningful verified state:
  - yes; Session `1` ends in a real product-visible fix with direct proof and
    refreshed closure ownership
- Is the matrix-update responsibility assigned clearly:
  - yes; this breakdown artifact is the doc-scoped closure ledger, with
    `00-INDEX.md` required and the stable 1:1 closure reference conditional
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
  - app-root notification-open routing stays out of scope unless a later
    planning pass proves current execution cannot close the bug without it
  - broader unread-badge architecture redesign stays out of scope
  - group-thread and introduction-surface parity stay out of scope

## Why this is not fewer sessions

- This cannot safely collapse to a chat-only or Orbit-only note because the
  bug is only meaningful as a disagreement between two mounted product
  surfaces.
- One doc-scoped implementation session is the minimum safe set because the
  report is only closed when the cross-surface sync change, the direct
  regression proof, and the closure ledger refresh all land together.

## Why this is not more sessions

- Splitting "Feed-originated handled-state propagation," "Orbit row summary
  refresh," and "closure refresh" into separate sessions would be bookkeeping
  overhead: current evidence points to one shared user-visible failure seam.
- A separate evidence-gated notification-routing session is not justified up
  front because current repo evidence narrows the live issue to handled-state
  sync after Feed already showed the message.
- A separate acceptance-only session is not justified unless later planning
  proves this seam cannot be trusted without broader app-root or device-backed
  proof, which current repo evidence does not require.

## Regression and gate contract

- Use `Test-Flight-Improv/14-regression-test-strategy.md` as the policy
  reference and `Test-Flight-Improv/test-gate-definitions.md` as the execution
  source of truth.
- Add the direct regression first for the escaped cross-surface sequence:
  `notification-led Feed stack card -> collapse or successful inline reply ->
  Orbit no longer shows the same handled notification state`.
- Run the exact direct suites for all touched files.
- Run `./scripts/run_test_gates.sh feed` because this report changes Feed card
  handling or Feed/Orbit surface truth.
- Run companion `./scripts/run_test_gates.sh 1to1` if the landed change touches
  shared inline-reply completion or other 1:1 entry behavior rather than
  staying purely on local refresh wiring.
- Run `./scripts/run_test_gates.sh baseline` because Flutter production code is
  expected to change.
- Do not run `transport` unless the final implementation actually widens into
  bootstrap, inbox-drain, reconnect, or notification-open routing behavior.
- Do not widen the frozen named gate lists by default; keep any new high-value
  cross-surface regressions as direct suites unless a later gate-definition
  change is explicitly justified.

## Matrix update contract

- No separate stable closure reference currently owns this exact Feed-handled
  notification sync seam across Feed and Orbit.
- This breakdown artifact is now the doc-scoped closure-owner ledger for
  landed Report `44` behavior.
- Session `1` completed planning, execution, QA, and closure against this
  artifact.
- Required maintenance updates after execution:
  - this breakdown artifact
  - `Test-Flight-Improv/00-INDEX.md`
- Conditional maintenance update:
  - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
    only if the landed implementation changes a broader shared 1:1 closure
    claim instead of staying local to Feed/Orbit handled-notification truth
- Closure outcome:
  - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
    stayed untouched because the accepted implementation reused the existing
    shared-host and inline-reply contracts instead of changing the broader
    1:1 reliability closure bar
- Do not create a new matrix doc for this bug.

## Downstream execution path

- Session `1` completed through planning, execution, and closure and is
  `accepted`.
- No executable sessions remain for Report `44`.
- This breakdown is now the maintenance-time closure-owner artifact for
  Report `44`.

## Pipeline run status

- Pipeline controller run date:
  `2026-04-02`
- Planning outcome:
  - the spawned decomposition child no-progressed under bounded wait, so the
    controller created this reusable breakdown artifact locally
  - the spawned planning/execution path also no-progressed under bounded wait,
    so the controller created the doc-scoped plan artifact locally at
    `Test-Flight-Improv/44-feed-orbit-notification-desync-session-1-plan.md`
    and continued with a bounded local implementation/QA pass
- Execution / QA outcome:
  - the accepted landing updated:
    - `lib/features/feed/presentation/screens/feed_wired.dart`
    - `lib/features/orbit/presentation/screens/orbit_wired.dart`
    - `test/features/feed/presentation/screens/feed_wired_test.dart`
  - the landed fix stayed inside the intended one-session seam:
    Feed now emits targeted `FeedRouteChanges` into the mounted Orbit host when
    Feed handles a 1:1 notification by collapse or successful inline reply, and
    Orbit reuses its existing targeted friend refresh path to clear the stale
    row state
  - direct proof run on `2026-04-02`:
    - `flutter test --no-pub test/features/feed/presentation/screens/feed_wired_test.dart`
    - `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart`
    - `./scripts/run_test_gates.sh feed`
    - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh 1to1`
    - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`
  - operational note:
    - the first direct rerun of `feed_wired_test.dart` hit a transient macOS
      native-assets universal-binary file-move failure under
      `build/native_assets/macos`; the immediate rerun against the warmed build
      state passed, so this was treated as spent tool friction rather than a
      product blocker
    - the macOS-backed `baseline` integration runs reported
      `Failed to foreground app; open returned 1` during app startup, but the
      gate itself completed green and the underlying test suites passed
- Closure outcome:
  - the report is now closed through this breakdown plus the refreshed
    `Test-Flight-Improv/00-INDEX.md`
- Final program acceptance verdict:
  `closed`
- Final program blocker:
  none

## Structural blockers remaining

- none

## Accepted differences intentionally left unchanged

- no reopen of app-root notification-open routing by default
- no reopen of the broader shared-host navigation rollout from Report `30`
- no unread-architecture redesign beyond what is required to make Feed and
  Orbit stop contradicting each other for the same handled notification
- no group-thread or intro-surface scope expansion

## Exact docs/files used as evidence

- `Test-Flight-Improv/44-feed-orbit-notification-desync.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/00-INDEX.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/30-swipe-nav-feed-orbit-session-breakdown.md`
- `Test-Flight-Improv/40-feed-stack-card-keeps-earlier-notification-messages-after-inline-reply-session-breakdown.md`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/feed/presentation/screens/feed_screen.dart`
- `lib/features/feed/domain/models/feed_route_changes.dart`
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `lib/features/orbit/application/load_orbit_data_use_case.dart`
- `lib/features/orbit/presentation/widgets/friend_row.dart`
- `lib/features/conversation/application/mark_conversation_read_use_case.dart`
- `lib/features/conversation/domain/repositories/message_repository_impl.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/features/orbit/presentation/screens/orbit_wired_test.dart`

## Why the breakdown is now safe as the closure reference

- Session `1` stayed at the minimum safe size: one shared Feed/Orbit handled
  notification-state seam with no follow-on routing or architecture phase
  required.
- The accepted maintenance-time proof is explicit and repeatable:
  `feed_wired_test.dart`, `orbit_wired_test.dart`,
  `./scripts/run_test_gates.sh feed`,
  `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh 1to1`, and
  `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`.
- The retryable spawned-step stalls and the one spent native-assets rerun are
  preserved here so future work does not mistake operational friction for a
  still-open product gap.
- Later work should reopen Report `44` only on a real regression where Feed
  and Orbit again disagree about the same handled 1:1 notification, not to
  reopen app-root notification routing, unread architecture, or broader
  shared-host navigation scope.
