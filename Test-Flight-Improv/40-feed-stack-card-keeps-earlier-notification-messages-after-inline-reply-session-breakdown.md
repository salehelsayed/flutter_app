# 40 - Feed Stack Card Keeps Earlier Notification Messages After Inline Reply Session Breakdown

## Decomposition artifact updated

- Artifact path:
  `Test-Flight-Improv/40-feed-stack-card-keeps-earlier-notification-messages-after-inline-reply-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/40-feed-stack-card-keeps-earlier-notification-messages-after-inline-reply.md`
- Decomposition date:
  `2026-04-01`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution

## Recommended plan count

- `1`

## Overall closure bar

Report `40` is closed only when the Feed 1:1 stack-card surface becomes
truthful again without widening into unrelated notification-routing or
read-receipt work:

- after a user replies inline from the Feed card, earlier incoming messages
  that were answered by that reply no longer reappear as unread notification
  rows when the same contact sends a later message
- the next reopened stack card shows only post-reply unread context for that
  continuing exchange
- the existing replied/collapsed transition, later reopen-on-incoming behavior,
  and expand-after-reply behavior remain intact
- direct regression proof covers the missing sequence
  `incoming unread -> inline reply from Feed card -> later incoming from same contact`
- the repo’s maintenance docs reflect this as a bounded Feed / Surface
  correction, not as a reopened app-root notification routing program or a new
  sender-visible read-state contract

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/40-feed-stack-card-keeps-earlier-notification-messages-after-inline-reply.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/32-notification-card-interactions-session-breakdown.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/00-INDEX.md`

Current repo facts that govern the split:

- `lib/features/feed/presentation/screens/feed_wired.dart` currently keeps the
  incremental contact-thread update local to `_applyIncomingContactMessageToFeed(...)`,
  which merges the next message into the current in-memory thread and rebuilds
  the feed item from that merged list.
- `lib/features/feed/presentation/screens/feed_wired.dart` currently stores an
  optimistic `SessionReply` before the inline send, then marks the conversation
  read and updates the feed again on send success.
- `lib/features/feed/presentation/screens/feed_wired.dart` clears the
  `SessionReply` again when the next incoming message arrives, so the later
  open-mode preview depends on whatever unread flags remain in that feed-owned
  thread snapshot.
- `lib/features/feed/domain/models/feed_item.dart` and
  `lib/features/feed/presentation/widgets/open_mode_card_body.dart` currently
  render the open card from `thread.unreadMessages`, so stale unread state
  directly expands the visible notification stack.
- `test/features/feed/presentation/screens/feed_wired_test.dart` already
  proves two adjacent contracts:
  - incoming messages clear `SessionReply` so the card can reopen
  - expand-after-inline-reply still works
  but it does not yet prove the full user-visible sequence from Report `40`.
- `test/features/feed/application/feed_projection_test.dart` already proves a
  full mark-read refresh can match a cold load, so any fix that changes
  refresh/snapshot ownership has an existing lower-layer proof family to extend.
- `test/features/feed/domain/utils/group_messages_into_threads_test.dart`
  already proves the state split between `active` and `replied`, which matters
  if final execution changes thread-state derivation rather than only feed-side
  refresh ownership.
- `Test-Flight-Improv/32-notification-card-interactions-session-breakdown.md`
  already closed the old notification-route/callback repro as
  `stale/already-covered`, so this report should stay scoped to feed unread
  projection truth unless current code during planning proves a fresh app-root
  routing dependency.

Source-of-truth conflicts that materially affected decomposition:

- Report `40` uses notification-led language, but adjacent repo evidence shows
  the current live seam is the feed-owned unread projection after inline reply,
  not the older notification-route/callback wiring from Report `32`.
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
  remains an adjacent maintenance reference because feed-originated 1:1 entry
  points still require companion `1to1` gate coverage, but this report does
  not justify reopening the broader 1:1 reliability closure bar by default.

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Closure docs touched | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `1` | `Feed inline-reply unread projection fix and proof` | `implementation-ready` | `Test-Flight-Improv/40-feed-stack-card-keeps-earlier-notification-messages-after-inline-reply-session-1-plan.md` | none | `pending` | `Test-Flight-Improv/40-feed-stack-card-keeps-earlier-notification-messages-after-inline-reply-session-breakdown.md`, `Test-Flight-Improv/00-INDEX.md`, `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md` only if final scope proves a broader shared 1:1 closure update is warranted | One bounded Feed / Surface seam with companion `1to1` gate ownership; no separate evidence-only or acceptance-only slice is required from current repo evidence. |

## Ordered session breakdown

### Session 1

- Title:
  `Feed inline-reply unread projection fix and proof`
- Session id:
  `1`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/40-feed-stack-card-keeps-earlier-notification-messages-after-inline-reply-session-1-plan.md`
- Exact scope:
  - make the 1:1 Feed card stop resurfacing pre-reply incoming messages as
    unread notification content after the user already replied inline from that
    same card
  - preserve the existing session-reply collapse, later reopen-on-incoming,
    and expand-after-reply behaviors that current tests already cover
  - add the missing direct regression for the exact escaped sequence from
    Report `40`, plus the smallest adjacent proof needed for longer same-card
    exchanges if current code proves that path shares the same seam
  - refresh the doc-scoped closure ledger after code and regressions land
- Why it is its own session:
  - this is one coherent Feed / Surface seam centered on feed-owned unread
    projection after an inline reply
  - it shares one primary direct regression family, one named-gate contract,
    and one user-visible closure bar
  - splitting code, regressions, and closure refresh would add bookkeeping
    without independent verification value because the bug only becomes
    meaningfully closed when all three land together
- Likely code-entry files:
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/feed/domain/models/feed_item.dart` only if the final fix
    needs a narrow unread-preview contract adjustment
  - `lib/features/feed/application/load_contact_feed_snapshot_use_case.dart`
    and `lib/features/feed/application/feed_projection.dart` only if the final
    fix needs fresh-snapshot parity rather than the current local merge path
  - `lib/features/feed/presentation/widgets/open_mode_card_body.dart` only if
    the final fix needs a small preview-threading adjustment
- Likely direct tests/regressions:
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
  - `test/features/feed/application/feed_projection_test.dart` if execution
    changes snapshot/refresh ownership
  - `test/features/feed/domain/utils/group_messages_into_threads_test.dart` if
    execution changes conversation-state derivation
  - `test/features/feed/integration/feed_card_flow_test.dart` or
    `test/features/feed/integration/expanded_collapsed_card_test.dart` only if
    the final plan needs one higher-layer product-facing proof beyond the
    screen-level regression
- Likely named gates:
  - `./scripts/run_test_gates.sh feed`
  - companion `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh baseline`
  - `./scripts/run_test_gates.sh transport` only if planning later proves the
    implementation widened into bootstrap, reconnect, inbox-drain, or
    transport-fallback wiring
- Matrix/closure docs to update when done:
  - required:
    - `Test-Flight-Improv/40-feed-stack-card-keeps-earlier-notification-messages-after-inline-reply-session-breakdown.md`
    - `Test-Flight-Improv/00-INDEX.md`
  - conditional:
    - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
      only if the landed change materially alters the broader shared 1:1
      closure claim rather than staying local to Feed unread projection
- Dependency on earlier sessions:
  - none
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Reviewer pass

- Is the recommended session count sufficient, too coarse, or too fragmented:
  - sufficient; current repo evidence supports one bounded implementation-ready
    slice
- Which proposed sessions should merge:
  - none
- Which proposed sessions must split:
  - none
- What tests or named gates are missing from the decomposition:
  - the exact escaped-sequence regression in
    `test/features/feed/presentation/screens/feed_wired_test.dart` is still
    missing and must be added during execution
  - lower-layer feed projection or state-derivation tests are conditional,
    based on final code-entry ownership
- Does each session end in a meaningful verified state:
  - yes; Session `1` ends in a real product-visible fix with direct proof, the
    named gates, and closure-ledger refresh
- Is the matrix-update responsibility assigned clearly:
  - yes; this breakdown artifact is the doc-scoped closure ledger, with
    `00-INDEX.md` required and the broad 1:1 closure reference conditional
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
  - app-root notification routing from Report `32` stays out of scope unless a
    later planning pass finds fresh evidence that current execution still
    depends on that seam
  - group-thread stack cards stay out of scope
  - sender-visible read receipts and other broader messaging product features
    stay out of scope

## Why this is not fewer sessions

- This cannot safely collapse to chat-only guidance because the report still
  describes a live product-visible bug and the repo is still missing the exact
  direct regression that would keep it from returning.
- One doc-scoped implementation session is the minimum safe set because the
  bug is only meaningfully closed when the feed behavior, the direct proof, and
  the closure ledger all land together.

## Why this is not more sessions

- Splitting “feed unread refresh ownership,” “card preview behavior,” and
  “closure refresh” into separate sessions would be bookkeeping overhead: the
  current evidence points to one feed-owned seam and one gate contract.
- A separate evidence-gated notification-routing session is not justified up
  front because Report `32` already closed that adjacent route/callback seam as
  stale/already-covered.
- A separate acceptance-only session is not justified unless later planning
  proves this bug cannot be trusted without a broader multi-surface harness.
  Current repo evidence does not require that split.

## Regression and gate contract

- Use `Test-Flight-Improv/14-regression-test-strategy.md` as the policy
  reference and `Test-Flight-Improv/test-gate-definitions.md` as the execution
  source of truth.
- Add the exact escaped-sequence regression first for:
  `incoming unread -> inline reply from Feed card -> later incoming from same contact`.
- Run the exact direct suites for all touched files.
- Run `./scripts/run_test_gates.sh feed` because this changes feed cards,
  inline reply behavior, or feed-owned message preview truth.
- Run companion `./scripts/run_test_gates.sh 1to1` because Feed still enters
  the shared 1:1 send path.
- Run `./scripts/run_test_gates.sh baseline` because Flutter production code is
  expected to change.
- Run `./scripts/run_test_gates.sh transport` only if the final implementation
  widens into lifecycle/bootstrap/reconnect/inbox-drain behavior.
- Do not change named gate membership by default; this report should use the
  current frozen gate lists plus its new direct regression.

## Matrix update contract

- No separate stable Feed-surface closure reference currently owns this unread
  preview seam.
- This breakdown artifact is therefore the live doc-scoped closure ledger for
  Report `40`.
- Session `1` owns the closure refresh during its downstream
  `$implementation-closure-audit-orchestrator` pass.
- Required maintenance updates after execution:
  - this breakdown artifact
  - `Test-Flight-Improv/00-INDEX.md`
- Conditional maintenance update:
  - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
    only if the landed implementation proves this bug changed a broader shared
    1:1 closure claim instead of staying local to Feed unread projection
- Do not create a new matrix doc for this bug.

## Structural blockers remaining

- none

## Accepted differences intentionally left unchanged

- no reopen of the app-root notification routing program from Report `32`
- no group-thread parity expansion
- no sender-visible read-receipt or typing-indicator scope
- no new named gate definitions by default
- no new stable matrix doc

## Exact docs/files used as evidence

- `Test-Flight-Improv/40-feed-stack-card-keeps-earlier-notification-messages-after-inline-reply.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/32-notification-card-interactions-session-breakdown.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/00-INDEX.md`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/feed/domain/models/feed_item.dart`
- `lib/features/feed/presentation/widgets/open_mode_card_body.dart`
- `lib/features/feed/application/load_contact_feed_snapshot_use_case.dart`
- `lib/features/feed/application/feed_projection.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/features/feed/application/feed_projection_test.dart`
- `test/features/feed/domain/utils/group_messages_into_threads_test.dart`

## Why the decomposition is safe to send into downstream planning/execution

- The bug is already narrowed to a live Feed / Surface seam with known
  code-entry files and known direct-test families.
- One doc-scoped session is enough to leave the repo in a meaningful verified
  state: land the unread-projection fix, add the exact escaped-sequence
  regression, run the required gates, and refresh the closure ledger.
- There are no unresolved structural blockers, external dependencies, or
  missing ownership questions that require a second decomposition pass before
  planning.
