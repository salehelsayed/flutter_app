# 67 - Group and Announcement Send-Then-Lock Parity Session Breakdown

## Decomposition artifact updated

- Artifact path:
  `Test-Flight-Improv/67-group-announcement-send-then-lock-parity-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/67-group-announcement-send-then-lock-parity.md`
- Decomposition date:
  `2026-04-06`
- Sessions `1` through `4` status:
  `accepted`; this artifact is the stable closure-owner record for Report `67`,
  and future work should reopen only on real regressions.
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution

## Final program acceptance verdict

- Final program state:
  `closed`
- Program-level verdict:
  the combined Sessions `1` through `4` rollout meets the overall closure bar
  for Report `67`
- Why:
  - shared group text sends now keep live-peer publish success `pending` until
    inbox custody is durably closed, while zero-peer or already-inbox-backed
    completion can still close `sent`
  - main conversation, feed inline reply, share-to-group, and announcement
    admin text send entry points now share one interruption-safe sender
    contract
  - rapid pause/resume recovery now explicitly includes
    `retryFailedGroupInboxStores(...)` and closes the same mixed-topology
    pending sender row exactly once without a second publish
  - the stable group and announcement closure refs now match the landed
    sender-trust contract without widening scope into per-recipient ACK
    semantics, true background upload guarantees, or announcement product
    redesign
- Acceptance evidence:
  - Sessions `1`, `2`, `3`, and `4` are all accepted in the session ledger
  - Session `4` reran the focused direct parity suites and named gates:
    - `flutter test test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`
    - `flutter test test/features/groups/integration/group_resume_recovery_test.dart -r expanded`
    - `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
    - `flutter test test/features/share/application/share_batch_delivery_coordinator_test.dart`
    - `./scripts/run_test_gates.sh groups`
    - `./scripts/run_test_gates.sh feed`
    - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh transport`
  - ordinary-group conversation text now has direct lock/unmount parity proof
    with live peers and with zero peers
  - durable-media-specific bg-task behavior remains covered in
    `test/features/groups/presentation/group_conversation_wired_test.dart`;
    this text-parity suite no longer duplicates those brittle cases
- Still-open implementation items for this rollout:
  - none
- Accepted differences preserved at program level:
  - no per-recipient ACK or read-receipt promise
  - no true background upload architecture
  - no announcement auth redesign
  - durable-media bg-task proof remains owned by the dedicated durable-media
    suite rather than this text-parity acceptance slice

## Recommended plan count

- `4`

## Overall closure bar

Report `67` is closed only when group chats and announcements own one honest
sender-trust send-then-lock contract for current text sending, rather than
relying on a mix of stronger 1:1 expectations, partial group durability, and
surface-specific exceptions:

- after tap-send, an immediate lock/background still leaves exactly one durable
  outgoing sender row and never forces rewrite/resend
- online members receive exactly one copy and offline members recover exactly
  one copy later without sender-side duplicate rows or mixed live-plus-backlog
  duplicate delivery
- live-peer publish success does not look durably closed while offline-member
  custody still depends on unresolved local recovery state
- group pause/resume and online retry continue to rejoin, drain, recover, and
  retry in the intended order while completing interrupted sender work exactly
  once
- the same interruption-safe expectation holds across the currently reachable
  group or announcement text send surfaces, not only the main conversation
  screen
- announcement admin-only writer enforcement and receipt-less group status
  honesty remain intact
- Report `67` does not widen into per-recipient ACK/read-receipt semantics,
  true background upload architecture, or announcement product-scope redesign

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/67-group-announcement-send-then-lock-parity.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `Test-Flight-Improv/21-announcement-reliability-closure-reference.md`

Current repo facts that govern the split:

- `send_group_message_use_case.dart` already pre-persists outgoing rows with
  `status='sending'`, `wireEnvelope`, `inboxStored`, and
  `inboxRetryPayload`, but the current `topicPeers > 0` and legacy-success
  paths still return `sent` before inbox completion is durably closed
- `send_group_message_use_case_test.dart` already codifies that live-peer
  branch behavior, so parity work must reopen the core sender contract rather
  than pretending the current behavior is only a documentation gap
- `group_conversation_wired.dart` already wraps main conversation text and
  voice sends in `bg:begin/bg:end`, and
  `group_conversation_wired_bg_task_test.dart` already proves announcement
  admin lock/unmount behavior with peers and with zero peers
- `feed_wired.dart` routes inline group reply through `sendGroupMessage(...)`
  without the same explicit background-task wrapper, and current
  `feed_wired_test.dart` coverage is optimistic/failure UI oriented rather than
  send-then-lock parity oriented
- `share_batch_delivery_coordinator.dart` can still reach group sending from an
  in-app share surface after uploads, so parity cannot be truthfully scoped to
  only the fully expanded group conversation screen
- `handle_app_resumed.dart` and `pending_message_retrier.dart` already encode a
  meaningful group recovery ordering contract, and ordering tests already pin
  that contract in `handle_app_resumed_upload_ordering_test.dart` and
  `pending_message_retrier_upload_ordering_test.dart`
- `group_resume_recovery_test.dart` already proves meaningful reader recovery,
  partial-delivery catch-up, and announcement widget lifecycle behavior, but it
  still does not give ordinary group text the same direct rapid
  lock/unlock exact-once sender proof that `send_then_lock_delivery_test.dart`
  gives to 1:1 chat
- current receiver-side duplicate protection is already message-id based in the
  group stack, so this rollout should strengthen sender closure without
  re-opening duplicate-delivery handling from scratch

Source-of-truth conflicts that materially affected decomposition:

- the source doc asks for parity with the existing 1:1 trust expectation, not a
  new per-recipient proof protocol; maintained closure refs `20` and `21`
  intentionally stop short of that claim today, so the rollout must strengthen
  sender-trust closure without inventing ACK semantics
- current code and tests explicitly accept early-return live-peer success in
  the shared group send use case, so the core sender-row contract must be its
  own session instead of being buried inside acceptance-only proof
- the source doc leaves auxiliary surfaces slightly open-ended, but current repo
  evidence shows feed inline reply and share-to-group are real reachable send
  paths; the split keeps those surfaces in scope so "parity" does not silently
  mean "main conversation only"

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Closure docs touched | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `1` | `Tighten the shared live-peer group send closure contract` | `implementation-ready` | `Test-Flight-Improv/67-group-announcement-send-then-lock-parity-session-1-plan.md` | none | `accepted` | `Test-Flight-Improv/67-group-announcement-send-then-lock-parity-session-breakdown.md` | Accepted on `2026-04-06`: live-peer and legacy publish success now stay `pending` until inbox custody closes, background inbox completion plus `retryFailedGroupInboxStores(...)` promote the row back to `sent`, direct send and inbox-retry regressions were refreshed, and `./scripts/run_test_gates.sh groups` plus `./scripts/run_test_gates.sh baseline` passed. |
| `2` | `Bring every current group or announcement text send surface onto the same interruption-safe entry contract` | `implementation-ready` | `Test-Flight-Improv/67-group-announcement-send-then-lock-parity-session-2-plan.md` | `1` | `accepted` | `Test-Flight-Improv/67-group-announcement-send-then-lock-parity-session-breakdown.md`, `Test-Flight-Improv/67-group-announcement-send-then-lock-parity-session-2-plan.md` | Accepted on `2026-04-06`: feed inline group reply now owns `bg:begin/bg:end`, share-to-group now owns the same background-task contract, group-share results no longer overstate a returned `pending` sender row as fully sent, direct feed/share regressions were added or refreshed, and `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh feed`, plus `./scripts/run_test_gates.sh baseline` passed. |
| `3` | `Make group sender recovery exact-once across pause/resume and online retry while preserving ordering` | `implementation-ready` | `Test-Flight-Improv/67-group-announcement-send-then-lock-parity-session-3-plan.md` | `1` | `accepted` | `Test-Flight-Improv/67-group-announcement-send-then-lock-parity-session-breakdown.md`, `Test-Flight-Improv/67-group-announcement-send-then-lock-parity-session-3-plan.md` | Accepted on `2026-04-06`: group recovery ordering now explicitly includes `retryFailedGroupInboxStores(...)`, the shared lifecycle helper can drive that final retry step during rapid-cycle tests, a new ordinary-group mixed live/offline pause-resume proof closes the same pending row exactly once without a second publish, and `./scripts/run_test_gates.sh groups`, `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh transport`, plus `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` passed. |
| `4` | `Land the missing parity proofs and refresh maintained closure references` | `acceptance-only` | `Test-Flight-Improv/67-group-announcement-send-then-lock-parity-session-4-plan.md` | `1`, `2`, `3` | `accepted` | `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`, `Test-Flight-Improv/21-announcement-reliability-closure-reference.md`, `Test-Flight-Improv/67-group-announcement-send-then-lock-parity-session-breakdown.md` | Accepted on `2026-04-06`: ordinary-group conversation text now has direct lock/unmount parity proof with live peers and with zero peers, the mixed-topology rapid pause/resume proof plus the Session `2` feed/share caller proofs were rerun and passed, closure refs `20` and `21` were refreshed, and `flutter test test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`, `flutter test test/features/groups/integration/group_resume_recovery_test.dart -r expanded`, `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`, `flutter test test/features/share/application/share_batch_delivery_coordinator_test.dart`, `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh feed`, and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh transport` all passed; durable-media-specific bg-task coverage remains owned by `test/features/groups/presentation/group_conversation_wired_test.dart`. |

## Pipeline progress

- `2026-04-06`: Session `1` accepted after creating the doc-scoped plan at
  `Test-Flight-Improv/67-group-announcement-send-then-lock-parity-session-1-plan.md`,
  tightening `sendGroupMessage(...)` and `retryFailedGroupInboxStores(...)` so
  unresolved inbox custody stays `pending`, refreshing the direct send/inbox
  retry proofs, updating the sender-state expectation in
  `group_resume_recovery_test.dart`, and passing:
  - `flutter test test/features/groups/application/send_group_message_use_case_test.dart`
  - `flutter test test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
  - `flutter test test/features/groups/integration/group_resume_recovery_test.dart -r expanded`
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh baseline`
- `2026-04-06`: Session `2` is now the next runnable session and must refresh
  the caller-surface parity plan against the accepted Session `1` sender-state
  contract before any further implementation.
- `2026-04-06`: Session `2` accepted after creating the doc-scoped plan at
  `Test-Flight-Improv/67-group-announcement-send-then-lock-parity-session-2-plan.md`,
  wrapping feed inline group reply and share-to-group in the same
  `bg:begin/bg:end` contract already used by the main conversation surface,
  tightening group-share result classification so live-peer `pending` rows stay
  queued instead of reading fully sent, repairing the affected feed fixtures to
  seed a real latest group key, and passing:
  - `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
  - `flutter test test/features/share/application/share_batch_delivery_coordinator_test.dart`
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh feed`
  - `./scripts/run_test_gates.sh baseline`
- `2026-04-06`: Session `3` is now the next runnable session and must refresh
  its pause/resume and retrier assumptions against the accepted Session `1`
  sender-state contract plus the accepted Session `2` caller-entry parity.
- `2026-04-06`: Session `3` accepted after creating the doc-scoped plan at
  `Test-Flight-Improv/67-group-announcement-send-then-lock-parity-session-3-plan.md`,
  extending the group lifecycle helper and direct resume-order proof to include
  `retryFailedGroupInboxStores(...)`, adding an ordinary-group rapid
  pause/resume mixed live/offline exact-once regression in
  `group_resume_recovery_test.dart`, and passing:
  - `flutter test test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
  - `flutter test test/features/groups/integration/group_resume_recovery_test.dart -r expanded`
  - `./scripts/run_test_gates.sh groups`
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh transport`
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`
- `2026-04-06`: Session `4` is now the next runnable session and must turn the
  remaining ordinary-group conversation parity gap plus maintained closure-doc
  understatement into final accepted proof and program closure.
- `2026-04-06`: Session `4` accepted after creating the doc-scoped plan at
  `Test-Flight-Improv/67-group-announcement-send-then-lock-parity-session-4-plan.md`,
  adding the missing ordinary-group text lock/unmount parity proofs in
  `group_conversation_wired_bg_task_test.dart`, rerunning the mixed-topology
  rapid pause/resume proof plus the feed/share caller suites, refreshing the
  maintained closure refs `20` and `21`, and passing:
  - `flutter test test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`
  - `flutter test test/features/groups/integration/group_resume_recovery_test.dart -r expanded`
  - `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
  - `flutter test test/features/share/application/share_batch_delivery_coordinator_test.dart`
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh feed`
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh transport`
- `2026-04-06`: Report `67` is now `closed`; all planned sessions are accepted
  and no still-open implementation items remain for this rollout.

## Ordered session breakdown

### Session 1

- Title:
  `Tighten the shared live-peer group send closure contract`
- Session id:
  `1`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/67-group-announcement-send-then-lock-parity-session-1-plan.md`
- Exact scope:
  - tighten the shared `sendGroupMessage(...)` sender contract so a live-peer
    publish path does not look durably closed while offline custody or inbox
    completion is still unresolved
  - keep sender-visible row state and retry-owned payloads honest until the
    send is actually closed, without widening into a new recipient-receipt
    protocol
  - preserve the already-correct zero-peer durable inbox path, timeout-to-inbox
    fallback behavior, announcement admin-only eligibility, and existing
    receiver-side dedupe semantics
  - update the existing direct send-use-case regressions so the repo stops
    encoding "return `sent` before inbox completion" as the intended live-peer
    contract
- Why it is its own session:
  - this is the core sender-persistence seam the source doc is reopening, and
    both caller-surface parity and pause/resume exact-once work depend on it
  - it has an existing focused direct regression family in
    `send_group_message_use_case_test.dart`, so it can be landed and verified
    independently before touching UI callers or runtime recovery ordering
- Likely code-entry files:
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/domain/models/group_message.dart` only if the local
    sender-state contract needs a tighter explicit representation
  - `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
    only if persistence/update semantics need to reflect the tightened contract
- Likely direct tests/regressions:
  - `test/features/groups/application/send_group_message_use_case_test.dart`
  - `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
    if retry-owned inbox-closure semantics change materially
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh baseline`
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/67-group-announcement-send-then-lock-parity-session-breakdown.md`
- Dependency on earlier sessions:
  - none

### Session 2

- Title:
  `Bring every current group or announcement text send surface onto the same interruption-safe entry contract`
- Session id:
  `2`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/67-group-announcement-send-then-lock-parity-session-2-plan.md`
- Exact scope:
  - make the main group conversation surface, feed inline group reply, and the
    current in-app share-to-group path all use one equivalent interruption-safe
    sender entry contract for text sends
  - add or preserve background-task ownership wherever a current caller can be
    backgrounded between tap-send and durable handoff
  - keep existing feed optimistic UI and failure-restore behavior truthful while
    bringing that surface up to the same send-then-lock bar
  - keep share batching behavior and announcement reader read-only behavior
    intact rather than widening into general share UX or auth redesign work
- Why it is its own session:
  - caller-surface parity is a different seam from the shared sender-row
    contract and uses different direct tests and named gates
  - splitting it away from Session `1` prevents the core send contract change
    from being buried inside unrelated feed/share surface edits
- Likely code-entry files:
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/share/application/share_batch_delivery_coordinator.dart`
- Likely direct tests/regressions:
  - `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
  - `test/features/share/application/share_batch_delivery_coordinator_test.dart`
  - `test/features/share/integration/share_to_contact_smoke_test.dart` only if
    the current share flow remains the best existing integration harness for
    group-target parity; otherwise add one new narrow group-share direct suite
    next to it
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh feed`
  - `./scripts/run_test_gates.sh baseline`
  - `./scripts/run_test_gates.sh 1to1` if the feed send-entry seam shared with
    1:1 chat is touched materially
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/67-group-announcement-send-then-lock-parity-session-breakdown.md`
- Dependency on earlier sessions:
  - `1`

### Session 3

- Title:
  `Make group sender recovery exact-once across pause/resume and online retry while preserving ordering`
- Session id:
  `3`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/67-group-announcement-send-then-lock-parity-session-3-plan.md`
- Exact scope:
  - preserve the intended group recovery ordering across resume and online retry:
    rejoin topics, drain group inbox, recover stuck sends, retry incomplete
    uploads, retry failed sends, then retry failed inbox stores
  - make interrupted or partially closed group text sends finish or retry
    exactly once from durable local state instead of relying on ambiguous
    sender rows
  - keep existing 1:1 recovery semantics, intro retry behavior, and
    announcement auth unchanged unless a narrow shared-runtime compatibility
    update is unavoidable
  - add the missing sender-oriented rapid pause/resume and mixed-topology
    recovery proof that mirrors the current 1:1 exact-once trust bar without
    overclaiming per-recipient proof
- Why it is its own session:
  - this is the lifecycle/retrier seam, with different blast radius and direct
    regression families from both the shared send use case and the caller
    surfaces
  - exact-once across repeated pause/resume cycles is a runtime repair contract,
    not just a send-path return-value contract
- Likely code-entry files:
  - `lib/core/lifecycle/handle_app_resumed.dart`
  - `lib/core/services/pending_message_retrier.dart`
  - `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`
  - `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
  - `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`
- Likely direct tests/regressions:
  - `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
  - `test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart`
  - `test/core/services/pending_message_retrier_test.dart`
  - `test/core/services/pending_message_retrier_upload_ordering_test.dart`
  - `test/core/services/pending_message_retrier_stuck_sending_test.dart`
  - `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`
  - `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh transport`
  - `./scripts/run_test_gates.sh baseline`
  - `./scripts/run_test_gates.sh 1to1` if shared retrier or lifecycle code for
    direct chat is touched materially
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/67-group-announcement-send-then-lock-parity-session-breakdown.md`
- Dependency on earlier sessions:
  - `1`

### Session 4

- Title:
  `Land the missing parity proofs and refresh maintained closure references`
- Session id:
  `4`
- Session classification:
  `acceptance-only`
- Intended plan file:
  `Test-Flight-Improv/67-group-announcement-send-then-lock-parity-session-4-plan.md`
- Exact scope:
  - add direct ordinary-group text lock/unmount proof with live peers and with
    zero peers so parity is no longer announcement-only
  - add direct sender-perspective mixed live-member/offline-member proof and
    rapid repeated pause/resume exact-once proof for ordinary group text
  - add caller-parity proof for feed inline group reply and for the current
    share-to-group path if that surface remains supported after Session `2`
  - rerun the focused direct suites and the required named gates, then refresh
    the maintained closure refs so group and announcement reliability stop
    understating this sender-trust parity contract
- Why it is its own session:
  - this is the cross-family acceptance layer spanning the earlier send,
    surface, and runtime slices; it should close only after those slices land
  - keeping proof-plus-doc refresh separate prevents the implementation
    sessions from silently claiming parity without the final direct evidence and
    maintained-doc alignment
- Likely code-entry files:
  - `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
  - `test/features/share/application/share_batch_delivery_coordinator_test.dart`
  - `test/features/share/integration/share_to_contact_smoke_test.dart` only if
    it remains the right existing integration harness for group-target proof
  - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
  - `Test-Flight-Improv/21-announcement-reliability-closure-reference.md`
  - `Test-Flight-Improv/67-group-announcement-send-then-lock-parity-session-breakdown.md`
- Likely direct tests/regressions:
  - `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
  - `test/features/share/application/share_batch_delivery_coordinator_test.dart`
  - one new narrow group-share integration proof only if the current share
    integration harness cannot truthfully cover group-target send-then-lock
    behavior
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh feed`
  - `./scripts/run_test_gates.sh transport`
  - `./scripts/run_test_gates.sh baseline` only if this final pass still lands
    production Flutter code
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
  - `Test-Flight-Improv/21-announcement-reliability-closure-reference.md`
  - `Test-Flight-Improv/67-group-announcement-send-then-lock-parity-session-breakdown.md`
- Dependency on earlier sessions:
  - `1`
  - `2`
  - `3`

## Why this is not fewer sessions

- One or two sessions would be unsafe because the work spans three different
  core seams with different direct regressions and different blast radius:
  shared sender persistence, caller-surface entry behavior, and
  lifecycle/retrier recovery ordering.
- Session `1` must stand alone because the current group send use case and its
  focused direct tests explicitly encode the live-peer early-return contract
  that Report `67` is reopening.
- Session `3` must stay separate from Sessions `1` and `2` because
  pause/resume and online retry exact-once behavior touches shared runtime
  ordering and can require `transport` and possibly `1to1` gate work even when
  the UI callers remain unchanged.
- Session `4` must stay separate so parity is not declared closed without the
  missing direct ordinary-group, mixed-topology, rapid-cycle, and caller-parity
  proofs plus the maintained closure-ref refresh.

## Why this is not more sessions

- Splitting main conversation, feed inline reply, and share-to-group into three
  separate sessions would be bookkeeping without independent verification
  value; they are one caller-parity seam with overlapping direct tests and the
  same user-visible closure bar.
- Splitting resume ordering from exact-once recovery would artificially divide a
  single lifecycle/retrier runtime seam whose proof already lives in adjacent
  lifecycle and retrier suites.
- Splitting acceptance from maintained closure-doc refresh would create a
  docs-only tail without independent verification value; Session `4` already
  closes on proof-plus-doc alignment.
- No extra architecture-only session is justified at decomposition time for a
  specific bridge shape, status label, or below-Dart atomization strategy. The
  source doc requires truthful sender closure, not one preselected internal
  implementation.

## Regression and gate contract

- Follow the direct-regression-first policy from
  `Test-Flight-Improv/14-regression-test-strategy.md`.
- Session `1` must update or add the focused direct send-use-case regressions
  before the tightened live-peer closure contract is considered complete.
- Session `2` must preserve the existing announcement bg-task proof and feed
  optimistic/failure behavior while adding caller-parity proof for any surface
  whose interruption-safety contract changes.
- Session `3` must preserve the explicit ordering tests in
  `test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart` and
  `test/core/services/pending_message_retrier_upload_ordering_test.dart` while
  adding the missing ordinary-group exact-once sender proof.
- Session `4` must rerun the focused acceptance suites and the named gates
  required by the landed sessions before the maintained closure references are
  refreshed.
- Named-gate source of truth stays
  `Test-Flight-Improv/test-gate-definitions.md`.
- Expected named-gate ownership by seam:
  - Session `1`: `groups`, `baseline`
  - Session `2`: `groups`, `feed`, `baseline`, and `1to1` if feed send-entry
    work affects direct-chat send paths
  - Session `3`: `groups`, `transport`, `baseline`, and `1to1` if shared
    direct-chat lifecycle/retrier behavior changes
  - Session `4`: `groups`, `feed`, `transport`, plus `baseline` only if the
    final pass still lands production Flutter code

## Matrix update contract

- Reuse the existing stable closure references for this area:
  `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
  and
  `Test-Flight-Improv/21-announcement-reliability-closure-reference.md`.
- Do not invent a new group-parity matrix doc for Report `67`.
- Session `4` owns the maintained closure refresh after Sessions `1` through
  `3` are accepted and the missing parity proofs are real.
- The session breakdown itself must be refreshed after each accepted session so
  later planning/execution inherits the latest landed repo truth.
- If a later accepted landing keeps any surface intentionally narrower than the
  proposal's parity bar, record that explicitly as an accepted difference in
  this breakdown and in the maintained closure refs rather than leaving it
  implicit.

## Downstream execution path

### Session 1

- next:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

### Session 2

- refresh against landed Session `1` code before planning
- next:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

### Session 3

- refresh against landed Session `1` code and any already-landed Session `2`
  surface changes before planning
- next:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

### Session 4

- run only after Sessions `1`, `2`, and `3` are accepted
- next:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Structural blockers remaining

- none
- Mergeable sessions: none
- Required splits: none

## Accepted differences intentionally left unchanged

- no per-recipient ACK or read-receipt promise:
  Report `67` closes on sender-trust parity, not on 1:1-style recipient proof
- no mandatory below-Dart atomic bridge redesign at decomposition time:
  planning may choose a bridge/package seam if needed, but the source doc does
  not require one specific internal architecture
- no forced status-label redesign by decomposition alone:
  the rollout must make sender closure honest, but it does not need to pre-pick
  one exact state name here
- no expansion into media/background-upload product guarantees:
  this report is for current text send-then-lock parity
- no announcement auth redesign:
  existing admin-only writer enforcement must remain, not be reopened
- no duplicate durable-media bg-task acceptance in this report:
  text-send parity is proven in
  `group_conversation_wired_bg_task_test.dart`, while durable-media-specific
  bg-task coverage remains in
  `test/features/groups/presentation/group_conversation_wired_test.dart`

## Exact docs/files used as evidence

- `Test-Flight-Improv/67-group-announcement-send-then-lock-parity.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `Test-Flight-Improv/21-announcement-reliability-closure-reference.md`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/share/application/share_batch_delivery_coordinator.dart`
- `lib/core/lifecycle/handle_app_resumed.dart`
- `lib/core/services/pending_message_retrier.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
- `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/features/share/application/share_batch_delivery_coordinator_test.dart`
- `test/features/share/integration/share_to_contact_smoke_test.dart`
- `test/core/services/pending_message_retrier_test.dart`
- `test/core/services/pending_message_retrier_upload_ordering_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
- `test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart`
- `test/shared/helpers/lifecycle_helpers.dart`
- `test/shared/fakes/fake_media_file_manager.dart`
- `test/features/conversation/integration/send_then_lock_delivery_test.dart`

## Why the decomposition is safe to send into downstream planning/execution

- The split follows real repo seams rather than turning the parity backlog into
  one giant mixed implementation bucket.
- Each session has a distinct closure bar, direct regression family, and named
  gate contract.
- The stable maintained closure docs for this area already exist and are reused
  rather than replaced.
- There are no unresolved external dependencies, missing ownership seams, or
  missing maintenance docs that require another decomposition pass before
  planning starts.
