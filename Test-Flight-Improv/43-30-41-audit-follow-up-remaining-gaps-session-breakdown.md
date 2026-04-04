# 43 - 30-41 Audit Follow-up Remaining Gaps Session Breakdown

## Decomposition artifact updated

- Artifact path:
  `Test-Flight-Improv/43-30-41-audit-follow-up-remaining-gaps-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/43-30-41-audit-follow-up-remaining-gaps.md`
- Decomposition date:
  `2026-04-02`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution
- Controller note:
  this artifact is now the controller ledger for the still-open `35`, `37`,
  `39`, `40`, and `41` remainder. Older report-specific breakdowns remain
  useful evidence, but they should not be treated as current closure truth
  until Session `7` refreshes them against the live repo state.
- Final acceptance rule:
  after all implementation sessions land, the rollout is not accepted until
  the repo has passed a whole-application regression sweep rather than only
  the touched direct suites and named gates. If unrelated suites are already
  red when that sweep runs, Session `7` must classify them explicitly as
  pre-existing blockers or fix/update them before claiming closure.

## Recommended plan count

- `7`
- The smallest safe split is:
  - four messaging-trust implementation sessions
  - two introducer follow-up implementation sessions
  - one closure-only cross-slice acceptance session

## Overall closure bar

Report `43` is closed only when the unresolved remainder from reports `35`,
`37`, `39`, `40`, and `41` is honestly closed at the same time without
reopening the already-landed work from `30`, `31`, `32`, `33`, `34`, `36`,
and `38`:

- Feed inline reply no longer resurrects pre-reply unread rows for the same
  1:1 thread.
- A canceled direct-message video upload becomes terminal for that same
  attempt across late upload completion, retry, resume, and recipient
  delivery.
- Delete-for-everyone keeps sender-visible pending or failed truth until the
  remote delete has actually converged, including pause/resume and ordering
  edge cases.
- The introducer gets truthful durable send history and a later durable
  completion surface when the introduced pair connects.
- Notification-opened chat and group routes no longer rely on silent fallback
  paths that can settle into an unchanged thread contradicting the
  notification.
- The maintenance docs stop overclaiming closure against current code and
  tests.

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/43-30-41-audit-follow-up-remaining-gaps.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/24-cancel-media-upload-session-breakdown.md`
- `Test-Flight-Improv/33-delete-message-for-me-everyone-session-breakdown.md`
- `Test-Flight-Improv/35-cancelled-video-upload-still-sends-session-breakdown.md`
- `Test-Flight-Improv/39-introducer-intro-follow-up-copy-and-completion-card-session-breakdown.md`
- `Test-Flight-Improv/40-feed-stack-card-keeps-earlier-notification-messages-after-inline-reply-session-breakdown.md`
- `Test-Flight-Improv/41-notification-open-missing-incoming-messages-session-breakdown.md`
- `Test-Flight-Improv/00-INDEX.md`

Current repo facts that governed the split:

- `lib/features/feed/presentation/screens/feed_wired.dart` still saves an
  optimistic inline-reply row, marks the conversation read on success, and
  then merges the outgoing message into the existing feed-owned thread instead
  of forcing a fresh post-read snapshot.
- `lib/features/feed/domain/models/feed_item.dart` still derives visible
  open-mode content from `thread.unreadMessages`, which uses existing
  `isUnread` flags.
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
  still treats accepted upload cancel as composer restore plus failed-row
  restoration.
- `lib/features/conversation/application/retry_failed_messages_use_case.dart`
  still retries failed media rows generically, which means a canceled attempt
  can still be picked back up later unless the row is made terminal in a
  stronger way.
- `lib/features/conversation/application/delete_message_use_case.dart` still
  writes a hidden sender-side tombstone before remote finalization and the
  current test suite proves hidden failed tombstones, not sender-visible
  pending or failed honesty.
- `test/features/conversation/integration/message_deletion_roundtrip_test.dart`
  covers online delete success, but no delete-specific lock/pause-resume
  regression was found alongside the proven normal send lock suites in
  `test/features/conversation/integration/send_then_lock_delivery_test.dart`.
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
  still inserts count-only introducer copy even though the introduced
  usernames are already available at send time.
- `test/features/introduction/presentation/widgets/intro_system_message_test.dart`
  already proves the rendering layer can handle name-aware copy, and
  `test/features/introduction/presentation/screens/sent_confirmation_test.dart`
  already proves username-aware send-time copy exists.
- `lib/features/feed/presentation/screens/feed_screen.dart` still exposes the
  persistent `IntroductionConnectionCard` only for the newly connected
  participants, not for the introducer.
- `lib/main.dart` and
  `lib/features/identity/presentation/startup_router.dart` now call the shared
  notification preparation path before route open.
- `lib/core/services/p2p_service_impl.dart` now has staged
  `retrieve_pending` plus `ack` replay support, but `_retrievePendingInboxPage`
  still contains a legacy destructive retrieve fallback path.
- `test/core/services/p2p_service_impl_test.dart` still explicitly proves that
  fallback is allowed today.
- `test/core/notifications/app_root_notification_open_test.dart` and
  `test/features/push/application/chat_and_group_push_open_flow_test.dart`
  prove prepare-before-route ordering, not the final truthful degraded outcome
  when staged retrieval or replay does not fully complete.

Source-of-truth conflicts that materially affected decomposition:

- `35` and `41` breakdown prose plus `19` and `00-INDEX.md` currently read as
  closed, but current code and tests still leave live remainder in those seams.
- The older `39` and `40` breakdowns are still good seam analyses, but Report
  `43` is now the controller for the unresolved remainder rather than those
  older docs.
- Report `33` remains the closure owner for the delete feature rollout, but
  Report `37` reopens only sender-honesty and lifecycle reliability, not the
  original affordance rollout.
- Report `24` remains the stable closure owner for the broader cancelable
  upload program, but Report `35` reopened one narrower 1:1 seam and the live
  code still does not fully satisfy the stronger terminal-cancel contract
  described by the audit.

## Evidence collector summary

- Feed unread truth is a feed-owned projection problem centered on
  `feed_wired.dart`, `feed_item.dart`, and `feed_wired_test.dart`.
- Cancel terminalization is a conversation upload and retry-ownership problem
  centered on `conversation_wired.dart`,
  `retry_failed_messages_use_case.dart`, and the direct conversation widget
  tests.
- Delete-for-everyone reliability is a reopened shared delete seam spanning
  sender-side tombstone state, recipient ordering, and lifecycle recovery.
- Introducer follow-up remains split across two distinct seams:
  conversation-history copy and a later durable completion projection.
- Notification-open trust is no longer a relay/Go prerequisite rollout; the
  remaining seam is a client-side staged-recovery plus app-root outcome
  hardening pass.

## Closure mapper

- Real closure target:
  make the remaining `35`, `37`, `39`, `40`, and `41` user-visible contracts
  truthful again without reopening the already-landed `30`, `31`, `32`, `33`,
  `34`, `36`, and `38` slices.
- Correctness and reliability work:
  unread projection truth, terminal cancel semantics, sender-visible delete
  honesty, delete ordering and lifecycle convergence, truthful durable intro
  history, durable introducer completion surfacing, and truthful
  notification-open recovery.
- Evidence-only or acceptance-only work:
  Session `7` is required because multiple older maintenance docs currently
  disagree with the live repo state, and because the user explicitly requires
  one whole-application green test pass before the rollout can be treated as
  finished.
- Explicit non-goals:
  no new 1:1 read-receipt product, no new mid-stream upload abort contract, no
  new delete undo or time-window product, no intro protocol redesign, no new
  introducer contact-creation rule, and no re-creation of the old three-phase
  relay/bridge rollout from Report `41`.

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Execution verdict | Closure docs touched | Blocker note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `1` | `Feed inline-reply unread projection fix and proof` | `implementation-ready` | `Test-Flight-Improv/43-30-41-audit-follow-up-remaining-gaps-session-1-plan.md` | none | `accepted` | `accepted` | `Test-Flight-Improv/43-30-41-audit-follow-up-remaining-gaps-session-breakdown.md` | fixed by forcing a post-read contact refresh after successful inline reply; stable `40`, `19`, and `00-INDEX.md` refresh stays deferred to Session `7` |
| `2` | `Terminal cancel semantics for direct-message media sends` | `implementation-ready` | `Test-Flight-Improv/43-30-41-audit-follow-up-remaining-gaps-session-2-plan.md` | none | `accepted` | `accepted` | `Test-Flight-Improv/43-30-41-audit-follow-up-remaining-gaps-session-breakdown.md` | accepted after direct suites plus `1to1` and `baseline`; the local baseline run required `FLUTTER_DEVICE_ID=macos` because the workspace had multiple connected Flutter targets |
| `3` | `Delete-for-everyone sender honesty and lifecycle convergence` | `implementation-ready` | `Test-Flight-Improv/43-30-41-audit-follow-up-remaining-gaps-session-3-plan.md` | none | `accepted` | `accepted` | `Test-Flight-Improv/43-30-41-audit-follow-up-remaining-gaps-session-breakdown.md` | accepted after direct suites plus `1to1`, `feed`, and `baseline`; the local baseline run required `FLUTTER_DEVICE_ID=macos` and still passed despite standard macOS link/open warnings |
| `4` | `Notification-open fallback hardening and truthful surfaced outcome` | `implementation-ready` | `Test-Flight-Improv/43-30-41-audit-follow-up-remaining-gaps-session-4-plan.md` | none | `pending` | `not run` | none | none |
| `5` | `Introducer durable history copy` | `implementation-ready` | `Test-Flight-Improv/43-30-41-audit-follow-up-remaining-gaps-session-5-plan.md` | none | `pending` | `not run` | none | none |
| `6` | `Introducer completion surface and follow-up projection` | `implementation-ready` | `Test-Flight-Improv/43-30-41-audit-follow-up-remaining-gaps-session-6-plan.md` | `5` | `prerequisite-blocked` | `not run` | none | wait for Session `5` acceptance |
| `7` | `Audit-43 cross-slice acceptance and closure refresh` | `closure-only` | `Test-Flight-Improv/43-30-41-audit-follow-up-remaining-gaps-session-7-plan.md` | `1`, `2`, `3`, `4`, `5`, `6` | `prerequisite-blocked` | `not run` | none | wait for Sessions `4` through `6` acceptance |

## Downstream execution path

- Sessions `1` through `7` should each next run through:
  1. `$implementation-plan-orchestrator`
  2. `$implementation-execution-qa-orchestrator`
  3. `$implementation-closure-audit-orchestrator`

## Ordered session breakdown

### Session 1

- Title:
  `Feed inline-reply unread projection fix and proof`
- Session id:
  `1`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/43-30-41-audit-follow-up-remaining-gaps-session-1-plan.md`
- Exact scope:
  - make the Feed 1:1 open-mode stack stop resurfacing earlier unread rows
    that the user already answered via inline reply
  - keep the existing collapse, session-reply, reopen-on-incoming, and
    expand-after-reply behavior that current tests already cover
  - add the exact escaped regression
    `A1 incoming -> B1 inline reply -> A2 incoming`
    plus the smallest adjacent longer-thread proof if the same seam owns it
- Why it is its own session:
  - this is one feed-owned unread-projection seam
  - it has one primary direct regression family and one main gate contract:
    `feed` plus companion `1to1`
- Likely code-entry files:
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/feed/domain/models/feed_item.dart`
  - `lib/features/feed/application/feed_projection.dart` only if the final fix
    needs snapshot-refresh parity rather than the current local merge
  - `lib/features/feed/application/load_contact_feed_snapshot_use_case.dart`
    only if the final fix changes snapshot ownership
- Likely direct tests/regressions:
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
  - `test/features/feed/application/feed_projection_test.dart` if snapshot
    ownership changes
  - `test/features/feed/integration/feed_card_flow_test.dart` only if the
    final plan needs one higher-layer visible proof
- Likely named gates:
  - `./scripts/run_test_gates.sh feed`
  - companion `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh baseline`
  - `./scripts/run_test_gates.sh transport` only if planning later proves the
    fix widened into bootstrap, reconnect, inbox-drain, or transport fallback
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/43-30-41-audit-follow-up-remaining-gaps-session-breakdown.md`
  - defer `40`, `19`, and `00-INDEX.md` refresh to Session `7`
- Dependency on earlier sessions:
  - none

## Session 1 closure outcome

- Closure classification:
  `accepted`
- What is now closed:
  - `lib/features/feed/presentation/screens/feed_wired.dart` now refreshes
    the contact snapshot after successful inline reply plus
    `markConversationRead(...)`, so the feed does not keep reusing stale
    pre-read unread flags when a later incoming message arrives
  - `test/features/feed/presentation/screens/feed_wired_test.dart` now pins
    the escaped sequence
    `A1 incoming -> B1 inline reply -> A2 incoming`
  - Session `1` now has direct and named-gate evidence that the fix stayed
    feed-owned and did not widen into a transport or broader 1:1 redesign
- Residual-only items:
  - stable closure refresh for `40`, `19`, and `00-INDEX.md` remains deferred
    to Session `7` so the multi-doc maintenance truth updates once the whole
    Audit `43` remainder is resolved
- Still-open items:
  - Sessions `4` through `7` remain open for this rollout
- Accepted differences:
  - no feed projection rewrite landed
  - no sender-visible read-receipt or unread-counter redesign landed
  - no `transport` gate widening was required
- Maintenance-time safety:
  - direct suite:
    `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
  - named gates:
    `./scripts/run_test_gates.sh feed`
    `./scripts/run_test_gates.sh 1to1`
    `./scripts/run_test_gates.sh baseline`
  - this session should reopen only on a real regression that causes Feed
    inline reply to resurface earlier answered unread rows or that proves the
    seam is broader than the feed-owned fix accepted here

### Session 2

- Title:
  `Terminal cancel semantics for direct-message media sends`
- Session id:
  `2`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/43-30-41-audit-follow-up-remaining-gaps-session-2-plan.md`
- Exact scope:
  - make accepted cancel terminal for that same direct-message media attempt
    rather than allowing it to collapse into a normal retryable failed-media
    row
  - keep later failed-message retry, resume recovery, and recipient delivery
    from picking that canceled attempt back up
  - add the missing proof across late upload completion, retry ownership, and
    resume-time recovery
- Why it is its own session:
  - this is a shared 1:1 upload and retry-ownership seam, not a feed unread
    seam and not a delete seam
  - it has a distinct direct regression family centered on
    `conversation_wired.dart` and failed-media retry ownership
- Likely code-entry files:
  - `lib/features/conversation/presentation/screens/conversation_wired.dart`
  - `lib/features/conversation/application/retry_failed_messages_use_case.dart`
  - `lib/features/conversation/application/retry_incomplete_uploads_use_case.dart`
    only if the final fix needs stronger resume-time skipping
  - `lib/core/services/pending_message_retrier.dart` only if the final state
    marker must be honored by shared retry orchestration
  - `lib/features/conversation/domain/repositories/media_attachment_repository.dart`
    and implementation only if a stronger terminal marker must be persisted
- Likely direct tests/regressions:
  - `test/features/conversation/presentation/screens/conversation_wired_test.dart`
  - `test/features/conversation/application/retry_failed_messages_media_reupload_test.dart`
  - `test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart`
    if resume ownership changes
  - `test/features/conversation/integration/media_attachment_flow_test.dart`
    only if the final plan needs explicit recipient non-delivery proof beyond
    the direct seam
- Likely named gates:
  - `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh baseline`
  - `./scripts/run_test_gates.sh transport` only if the final fix changes
    lifecycle or resume orchestration
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/43-30-41-audit-follow-up-remaining-gaps-session-breakdown.md`
  - defer `24`, `35`, `19`, and `00-INDEX.md` refresh to Session `7`
- Dependency on earlier sessions:
  - none

## Session 2 closure outcome

- Closure classification:
  `accepted`
- What is now closed:
  - `lib/features/conversation/presentation/screens/conversation_wired.dart`
    now rewrites accepted-cancel `upload_pending` attachment rows to
    `upload_cancelled` and rehydrates the restored failed row from storage, so
    the same attempt no longer settles back into the ordinary retryable
    failed-media surface
  - `lib/features/conversation/application/retry_failed_messages_use_case.dart`
    now treats `upload_cancelled` persisted attachments as a terminal skip
    reason, which keeps failed-message retry ownership and resume-time retry
    orchestration from resurrecting that cancelled attempt
  - `lib/features/conversation/presentation/screens/conversation_screen.dart`
    now keeps Retry/Delete failed-media affordances visible for genuinely
    retryable failed rows while hiding them for fully cancelled attempts
  - `test/features/conversation/presentation/screens/conversation_wired_test.dart`
    now proves both accepted-cancel regressions land as `upload_cancelled`
    without surfacing ordinary failed-media retry controls
  - `test/features/conversation/application/retry_failed_messages_media_reupload_test.dart`
    now proves cancelled persisted media rows are skipped without re-upload
    or resend
- Residual-only items:
  - stable closure refresh for `24`, `35`, `19`, and `00-INDEX.md` remains
    deferred to Session `7` so the maintenance truth update lands after the
    whole Audit `43` remainder is complete
- Still-open items:
  - Sessions `4` through `7` remain open for this rollout
- Accepted differences:
  - no repository interface widening was required
  - no `retryIncompleteUploads(...)` or `pending_message_retrier.dart`
    changes were required because the failed-message retry seam was fixed at
    the persisted attachment-state boundary
  - no `transport` gate widening was required
- Maintenance-time safety:
  - direct suites:
    `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart`
    `flutter test test/features/conversation/application/retry_failed_messages_media_reupload_test.dart`
  - named gates:
    `./scripts/run_test_gates.sh 1to1`
    `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`
  - this session should reopen only on a real regression that lets an
    accepted direct-message media cancel attempt re-upload, resend, or reappear
    as an ordinary retryable failed-media row

### Session 3

- Title:
  `Delete-for-everyone sender honesty and lifecycle convergence`
- Session id:
  `3`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/43-30-41-audit-follow-up-remaining-gaps-session-3-plan.md`
- Exact scope:
  - keep delete-for-everyone sender-visible state honest while the remote
    delete is still pending or failed
  - add delete-specific lifecycle and ordering reliability so pause/resume,
    lock/unlock, and recipient delete-before-original ordering converge to one
    truthful outcome
  - preserve the already-landed delete affordance program from Report `33`
    instead of reopening the whole feature
- Why it is its own session:
  - this is one reopened shared-delete reliability seam with a different
    direct test family from cancel, feed unread, and intro follow-up
  - the missing proof spans use-case, listener, presentation, and lifecycle
    coverage that should land together to leave a meaningful verified state
- Likely code-entry files:
  - `lib/features/conversation/application/delete_message_use_case.dart`
  - `lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart`
  - `lib/features/conversation/application/retry_failed_messages_use_case.dart`
    or `retry_unacked_messages_use_case.dart` if the final fix reuses shared
    retry ownership
  - `lib/features/conversation/presentation/screens/conversation_wired.dart`
  - `lib/features/feed/presentation/screens/feed_wired.dart` only if feed entry
    or feed-side delete-state parity needs change
  - `lib/core/lifecycle/handle_app_paused.dart` and
    `lib/core/lifecycle/handle_app_resumed.dart` only if the final fix needs
    dedicated delete recovery ordering
- Likely direct tests/regressions:
  - `test/features/conversation/application/delete_message_use_case_test.dart`
  - `test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart`
  - `test/features/conversation/integration/message_deletion_roundtrip_test.dart`
  - `test/features/conversation/presentation/screens/conversation_wired_test.dart`
  - `test/features/feed/presentation/screens/feed_wired_test.dart` if feed-side
    sender honesty changes
  - one delete-specific lock or pause-resume proof adjacent to
    `test/features/conversation/integration/send_then_lock_delivery_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh baseline`
  - `./scripts/run_test_gates.sh feed` if feed entry, preview, or feed-side
    delete-state parity changes
  - `./scripts/run_test_gates.sh transport` only if the final implementation
    widens into lifecycle or bootstrap-owned recovery wiring
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/43-30-41-audit-follow-up-remaining-gaps-session-breakdown.md`
  - defer `33`, `19`, and `00-INDEX.md` refresh to Session `7`
- Dependency on earlier sessions:
  - none

## Session 3 closure outcome

- Closure classification:
  `accepted`
- What is now closed:
  - `lib/features/conversation/application/delete_message_use_case.dart`
    now keeps outgoing delete-for-everyone tombstones visible while they are
    `sending`, `sent`, or `failed`, and hides them only once the current
    durable-send contract reaches `status == 'delivered'`
  - `lib/features/conversation/application/delete_message_tombstone_visibility.dart`
    now defines the shared sender-side hidden-at normalization for outgoing
    deleted tombstones so delete persistence and recovery converge on one
    final visibility rule
  - `lib/features/conversation/application/retry_failed_messages_use_case.dart`
    and `retry_unacked_messages_use_case.dart` now apply that same hide-on-
    delivered contract when stored delete wire envelopes succeed during retry
    and resume recovery
  - `test/features/conversation/application/delete_message_use_case_test.dart`,
    `retry_failed_messages_use_case_test.dart`, and
    `retry_unacked_messages_use_case_test.dart` now prove failed sender-visible
    delete truth and delivered finalization at the use-case boundary
  - `test/features/conversation/presentation/screens/conversation_wired_test.dart`
    and `test/features/feed/presentation/screens/feed_wired_test.dart` now
    prove Orbit and Feed keep the deleted placeholder visible while sender-side
    delete is still failed instead of falling back to the earlier visible row
  - `test/features/conversation/integration/send_then_lock_delivery_test.dart`
    now proves a failed delete stays visible through pause and becomes hidden
    only after resume-time retry delivers it
  - `test/features/conversation/integration/message_deletion_roundtrip_test.dart`
    remained green, so recipient tombstone convergence and delete-before-
    original ordering stayed intact while sender honesty changed
- Residual-only items:
  - stable closure refresh for `33`, `37`, `19`, and `00-INDEX.md` remains
    deferred to Session `7` so the maintenance truth update lands after the
    rest of Audit `43` is complete
- Still-open items:
  - Sessions `4` through `7` remain open for this rollout
- Accepted differences:
  - no message-query rewrite or visibility migration was required because the
    existing `hidden_at IS NULL` visibility contract stayed correct once the
    sender hide boundary moved to delivered finalization
  - no delete protocol redesign or recipient acknowledgement expansion landed
  - no `handle_app_paused.dart`, `handle_app_resumed.dart`, or `transport`
    gate widening was required because the shared retry success paths were
    normalized at the delete tombstone visibility boundary instead
- Maintenance-time safety:
  - direct suites:
    `flutter test test/features/conversation/application/delete_message_use_case_test.dart`
    `flutter test test/features/conversation/application/retry_failed_messages_use_case_test.dart`
    `flutter test test/features/conversation/application/retry_unacked_messages_use_case_test.dart`
    `flutter test test/features/conversation/integration/message_deletion_roundtrip_test.dart`
    `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart`
    `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
    `flutter test test/features/conversation/integration/send_then_lock_delivery_test.dart`
  - named gates:
    `./scripts/run_test_gates.sh 1to1`
    `./scripts/run_test_gates.sh feed`
    `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`
  - this session should reopen only on a real regression that hides a sender
    delete row before delivery finalization, leaves a delivered delete visible
    after resume, or breaks recipient tombstone convergence
  - the local baseline pass emitted standard macOS linker/deployment warnings
    and `Failed to foreground app; open returned 1`, but the gate still exited
    green and the integration assertions passed

### Session 4

- Title:
  `Notification-open fallback hardening and truthful surfaced outcome`
- Session id:
  `4`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/43-30-41-audit-follow-up-remaining-gaps-session-4-plan.md`
- Exact scope:
  - keep the already-landed staged inbox retrieval path as the production truth
    for notification-opened recovery rather than silently falling back to the
    older destructive retrieve path
  - make degraded staged recovery result in one truthful visible or
    diagnosable outcome instead of an apparently unchanged thread that
    contradicts the notification
  - add the direct regressions still missing for fallback, degraded replay, and
    real app-root open outcome
- Why it is its own session:
  - the relay and bridge prerequisite rollout from old Report `41` has already
    landed; the remaining seam is a bounded client-side service and app-root
    trust correction
  - it has a different direct regression family from the other sessions:
    `p2p_service_impl`, app-root notification open, and notification-open
    helper suites
- Likely code-entry files:
  - `lib/core/services/p2p_service_impl.dart`
  - `lib/main.dart`
  - `lib/features/identity/presentation/startup_router.dart` only if the final
    visible-outcome contract must stay aligned at startup
  - `lib/features/push/application/prepare_notification_open_use_case.dart`
    only if the result contract must become richer than the current `ok/error`
    shape
  - `lib/core/database/helpers/inbox_staging_db_helpers.dart` only if replay
    diagnostics need one more persisted reason field
- Likely direct tests/regressions:
  - `test/core/services/p2p_service_impl_test.dart`
  - `test/core/notifications/app_root_notification_open_test.dart`
  - `test/features/push/application/chat_and_group_push_open_flow_test.dart`
  - `test/features/push/application/prepare_notification_open_use_case_test.dart`
  - `test/integration/notification_deeplink_integration_test.dart` only if the
    final implementation needs one broader visible proof
- Likely named gates:
  - `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh baseline`
  - `./scripts/run_test_gates.sh transport`
  - direct notification suites for the touched app-root and helper seams
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/43-30-41-audit-follow-up-remaining-gaps-session-breakdown.md`
  - defer `41`, `19`, and `00-INDEX.md` refresh to Session `7`
- Dependency on earlier sessions:
  - none

### Session 5

- Title:
  `Introducer durable history copy`
- Session id:
  `5`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/43-30-41-audit-follow-up-remaining-gaps-session-5-plan.md`
- Exact scope:
  - replace the current count-only introducer system message with truthful
    name-aware durable copy using the usernames already present at send time
  - preserve bounded multi-name summary behavior without changing the existing
    transient sent-confirmation contract
  - keep the stored row as the current `transport = 'system'` conversation
    history shape
- Why it is its own session:
  - this is a bounded conversation-history copy seam that can land safely
    before any completion-card projection work
  - it has a narrower direct regression family than the later introducer
    completion surface
- Likely code-entry files:
  - `lib/features/conversation/presentation/screens/conversation_wired.dart`
  - `lib/features/introduction/application/insert_intro_system_message.dart`
  - `lib/features/introduction/presentation/widgets/intro_system_message.dart`
    only if the final copy helper needs a small rendering contract adjustment
- Likely direct tests/regressions:
  - `test/features/conversation/presentation/screens/conversation_overflow_intro_test.dart`
  - `test/features/introduction/presentation/widgets/intro_system_message_test.dart`
  - `test/features/introduction/presentation/screens/sent_confirmation_test.dart`
    only if the final summary helper is shared
- Likely named gates:
  - direct intro and conversation suites
  - `./scripts/run_test_gates.sh baseline`
  - `./scripts/run_test_gates.sh feed` only if feed rendering or feed-derived
    preview behavior changes
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/43-30-41-audit-follow-up-remaining-gaps-session-breakdown.md`
  - defer `39` and `00-INDEX.md` refresh to Sessions `6` and `7`
- Dependency on earlier sessions:
  - none

### Session 6

- Title:
  `Introducer completion surface and follow-up projection`
- Session id:
  `6`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/43-30-41-audit-follow-up-remaining-gaps-session-6-plan.md`
- Exact scope:
  - give the introducer a durable user-facing completion surface when the
    introduced pair reaches mutual acceptance
  - reuse existing intro rows, listener signals, and current Flutter host
    surfaces rather than inventing a second intro protocol or notification-only
    state machine
  - preserve participant-side `IntroductionConnectionCard` behavior and the
    current intro notification routing semantics
- Why it is its own session:
  - this is a projection and presentation seam with a different direct test
    family from the sender-side copy bug
  - it depends on Session `5` if the durable introducer history is going to be
    truthful in the same final product state
- Likely code-entry files:
  - `lib/features/introduction/application/introduction_listener.dart`
  - `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`
    only if final projection state must be threaded there
  - `lib/features/feed/application/load_feed_use_case.dart`,
    `feed_store.dart`, or `feed_wired.dart` if Feed remains the chosen host
  - `lib/features/feed/presentation/screens/feed_screen.dart` if the final host
    is a feed card or feed section
  - `lib/features/orbit/presentation/screens/orbit_wired.dart` or
    `orbit_intros_wiring.dart` only if final planning proves Orbit is the
    right durable host
- Likely direct tests/regressions:
  - `test/features/introduction/application/introduction_listener_test.dart`
  - `test/features/feed/presentation/screens/feed_wired_test.dart` if Feed
    hosts the completion surface
  - `test/features/feed/presentation/widgets/introduction_connection_card_test.dart`
    if the existing card is reused or extended
  - `test/features/orbit/presentation/screens/orbit_wired_test.dart` or
    `orbit_intros_wiring_test.dart` only if Orbit becomes the durable host
  - `test/features/introduction/integration/intro_wiring_smoke_test.dart`,
    `introduction_smoke_test.dart`, or `introduction_multi_node_test.dart`
    only if the final plan needs one higher-layer follow-up proof
- Likely named gates:
  - direct intro, feed, and Orbit suites for the touched host surface
  - `./scripts/run_test_gates.sh baseline`
  - `./scripts/run_test_gates.sh feed` only if Feed remains the durable host
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/43-30-41-audit-follow-up-remaining-gaps-session-breakdown.md`
  - defer `39` and `00-INDEX.md` refresh to Session `7`
- Dependency on earlier sessions:
  - Session `5`

### Session 7

- Title:
  `Audit-43 cross-slice acceptance and closure refresh`
- Session id:
  `7`
- Session classification:
  `closure-only`
- Intended plan file:
  `Test-Flight-Improv/43-30-41-audit-follow-up-remaining-gaps-session-7-plan.md`
- Exact scope:
  - rerun the direct regressions added or changed by Sessions `1` through `6`
  - rerun the named gates and direct suites materially touched by those
    sessions
  - run the whole-application regression sweep for the Flutter app so closure
    does not depend only on change-local gates:
    all host-side tests under `test/`, all app-backed tests under
    `integration_test/`, and the frozen named gate commands needed to confirm
    the current scripted gate surface remains green
  - treat any red suite during that sweep as a real acceptance blocker until
    it is either fixed, intentionally updated because the new product contract
    changed, or documented as a proven pre-existing unrelated failure with
    exact evidence
  - refresh the stale maintenance docs so the folder no longer claims `35` and
    `41` are fully closed while the repo still disagrees, and so `39` and `40`
    no longer remain stranded as pending older breakdowns if this umbrella
    rollout closes them
  - stop and reopen the affected earlier session if acceptance exposes a real
    residual product gap instead of silently widening the closure session
- Why it is its own session:
  - this validates multiple earlier slices and multiple maintenance docs at
    once
  - leaving closure refresh to the individual implementation sessions would
    keep conflicting maintenance truth scattered across the folder
- Likely code-entry files:
  - `Test-Flight-Improv/43-30-41-audit-follow-up-remaining-gaps-session-breakdown.md`
  - `Test-Flight-Improv/00-INDEX.md`
  - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
  - `Test-Flight-Improv/24-cancel-media-upload-session-breakdown.md`
    conditionally
  - `Test-Flight-Improv/33-delete-message-for-me-everyone-session-breakdown.md`
    conditionally
  - `Test-Flight-Improv/35-cancelled-video-upload-still-sends-session-breakdown.md`
  - `Test-Flight-Improv/39-introducer-intro-follow-up-copy-and-completion-card-session-breakdown.md`
  - `Test-Flight-Improv/40-feed-stack-card-keeps-earlier-notification-messages-after-inline-reply-session-breakdown.md`
  - `Test-Flight-Improv/41-notification-open-missing-incoming-messages-session-breakdown.md`
- Likely direct tests/regressions:
  - the exact direct suites landed by Sessions `1` through `6`
  - `flutter test test`
  - the application `integration_test/` sweep on the supported local device
    path for this repo
  - `./scripts/run_test_gates.sh feed`
  - `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh baseline`
  - `./scripts/run_test_gates.sh transport` only if Sessions `3` or `4`
    materially changed lifecycle, inbox-drain, reconnect, or bootstrap wiring
  - direct intro, Orbit, and notification suites touched by Sessions `5` and
    `6`
- Likely named gates:
  - the union of the gates actually touched by Sessions `1` through `6`
  - no gate-definition rewrite by default
- Matrix/closure docs to update when done:
  - required:
    - `Test-Flight-Improv/43-30-41-audit-follow-up-remaining-gaps-session-breakdown.md`
    - `Test-Flight-Improv/00-INDEX.md`
    - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
    - `Test-Flight-Improv/35-cancelled-video-upload-still-sends-session-breakdown.md`
    - `Test-Flight-Improv/39-introducer-intro-follow-up-copy-and-completion-card-session-breakdown.md`
    - `Test-Flight-Improv/40-feed-stack-card-keeps-earlier-notification-messages-after-inline-reply-session-breakdown.md`
    - `Test-Flight-Improv/41-notification-open-missing-incoming-messages-session-breakdown.md`
  - conditional:
    - `Test-Flight-Improv/24-cancel-media-upload-session-breakdown.md`
      if Session `2` changes the stable cancel-program wording
    - `Test-Flight-Improv/33-delete-message-for-me-everyone-session-breakdown.md`
      if Session `3` changes the accepted delete reliability wording
- Dependency on earlier sessions:
  - Sessions `1`, `2`, `3`, `4`, `5`, and `6`

## Reviewer pass

- Is the recommended session count sufficient, too coarse, or too fragmented:
  - sufficient; `7` is the minimum safe set that leaves each seam in a
    meaningful verified state
- Which proposed sessions should merge:
  - none
- Which proposed sessions must split:
  - none from current repo evidence
- What tests or named gates are missing from the decomposition:
  - Session `1` must add the exact `A1 -> B1 -> A2` Feed regression
  - Session `2` must add explicit cancel-across-retry or resume proof
  - Session `3` must add delete-specific lifecycle proof, not just reuse the
    normal send lock evidence by assumption
  - Session `4` must add degraded staged-recovery proof, not just preparation
    ordering proof
  - Sessions `5` and `6` must keep the current intro direct-suite ownership
    explicit because no frozen named gate owns that area
- Does each session end in a meaningful verified state:
  - yes; Sessions `1` through `6` each close one coherent user-visible seam,
    and Session `7` closes the audit-level maintenance truth only after the
    whole-app regression sweep is green or all remaining failures are proven
    pre-existing and explicitly classified
- Is the matrix-update responsibility assigned clearly:
  - yes; Session `7` owns the multi-doc closure refresh
- What is the minimum session set that is still safe:
  - `7`

## Arbiter outcome

- Structural blockers:
  - none
- Mergeable sessions:
  - none
- Required splits:
  - none
- Accepted differences:
  - older `41` relay and bridge prerequisite work stays accepted and is not
    recreated as new sessions
  - no new cancel `status = cancelled` model is assumed up front
  - no new intro protocol or introducer-contact product is assumed
  - no sender-visible read-receipt or unread-counter redesign is implied

## Why this is not fewer sessions

- Sessions `1`, `2`, `3`, and `4` each hit a different core seam:
  feed unread projection, media cancel and retry ownership, delete reliability,
  and staged inbox notification-open trust.
- Sessions `5` and `6` should not merge because sender-side durable intro copy
  is a bounded conversation-history fix, while the introducer completion
  surface is a different projection and host-surface decision.
- Session `7` is required because the folder currently has stale or conflicting
  maintenance prose across `00`, `19`, `24`, `33`, `35`, `39`, `40`, and `41`.
  Leaving closure refresh implicit would preserve contradictory maintenance
  truth even if the code landed.

## Why this is not more sessions

- Do not recreate old Report `41` as a new three-session relay or bridge
  rollout; those prerequisites are already landed and the remaining seam is
  narrower.
- Do not split Session `2` into separate UI cancel and retry-ownership
  sessions unless planning later proves a new persisted state model is
  unavoidable; current evidence still points to one coherent terminal-cancel
  seam.
- Do not split Session `3` into separate sender-state, recipient-ordering, and
  lifecycle sessions. Those all define the same truthful delete-for-everyone
  closure bar and should land together.
- Do not split Session `6` into separate projection and widget-only sessions
  unless planning later proves the chosen host surface requires a genuinely
  distinct data prerequisite beyond Session `5`.

## Regression and gate contract

- Use `Test-Flight-Improv/14-regression-test-strategy.md` as the policy
  reference and `Test-Flight-Improv/test-gate-definitions.md` as the execution
  source of truth.
- Add the exact escaped regression first in every implementation session before
  broadening code changes.
- Session `1` must run direct Feed suites plus `feed`, companion `1to1`, and
  `baseline`.
- Session `2` must run direct conversation cancel and retry suites plus
  `1to1` and `baseline`; `transport` only if lifecycle or resume orchestration
  changes.
- Session `3` must run direct delete use-case, listener, and lifecycle proof
  suites plus `1to1` and `baseline`; `feed` if feed-owned delete parity
  changes; `transport` only if lifecycle or startup-owned recovery changes.
- Session `4` must run direct staged-inbox and app-root notification suites
  plus `1to1`, `baseline`, and `transport`.
- Sessions `5` and `6` must run the exact direct intro, conversation, feed,
  and Orbit suites for the touched host surface plus `baseline`; no named gate
  expansion is justified by default.
- Session `7` reruns the union of the direct regressions and named gates
  touched by Sessions `1` through `6`.
- Session `7` also runs the whole-app Flutter regression sweep:
  `flutter test test` plus the repo’s supported `integration_test/` sweep on a
  concrete device target, because the user’s acceptance bar is broader than
  change-local regression proof.
- `./scripts/run_test_gates.sh completeness-check` is only required if
  execution edits the frozen gate definitions, which is not expected from the
  current decomposition.

## Matrix update contract

- Do not invent a new matrix doc for this work.
- `Test-Flight-Improv/43-30-41-audit-follow-up-remaining-gaps-session-breakdown.md`
  is the primary controller ledger for the rollout.
- Session `7` owns the final closure refresh after the implementation sessions
  land.
- Session `7` also owns the final whole-app green-test determination. Closure
  is not honest unless the broader app regression sweep is green or any
  remaining failures are explicitly proven to be unrelated pre-existing
  breakage.
- Required final maintenance updates:
  - `Test-Flight-Improv/00-INDEX.md`
  - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
  - `Test-Flight-Improv/35-cancelled-video-upload-still-sends-session-breakdown.md`
  - `Test-Flight-Improv/39-introducer-intro-follow-up-copy-and-completion-card-session-breakdown.md`
  - `Test-Flight-Improv/40-feed-stack-card-keeps-earlier-notification-messages-after-inline-reply-session-breakdown.md`
  - `Test-Flight-Improv/41-notification-open-missing-incoming-messages-session-breakdown.md`
- Conditional final maintenance updates:
  - `Test-Flight-Improv/24-cancel-media-upload-session-breakdown.md`
    if the accepted cancel contract wording changes
  - `Test-Flight-Improv/33-delete-message-for-me-everyone-session-breakdown.md`
    if the accepted delete reliability wording changes

## Structural blockers remaining

- none

## Accepted differences intentionally left unchanged

- Do not reopen reports `30`, `31`, `32`, `33`, `34`, `36`, or `38` as new
  implementation sessions.
- Do not promise mid-stream transport abort or a new `cancelled` status model
  unless planning later proves it is unavoidable.
- Do not widen delete scope into undo, time windows, batch delete, or other
  product redesign.
- Do not widen intro scope into new protocol, new contact-creation semantics
  for the introducer, or a new dedicated introducer-history browser.
- Do not widen notification-open scope back into relay-server or Go-bridge
  redesign; treat the old `41` Sessions `1` through `3` as landed
  prerequisites.
- Do not introduce sender-visible read receipts or broader unread-count product
  semantics.

## Exact docs/files used as evidence

- `Test-Flight-Improv/43-30-41-audit-follow-up-remaining-gaps.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/24-cancel-media-upload-session-breakdown.md`
- `Test-Flight-Improv/33-delete-message-for-me-everyone-session-breakdown.md`
- `Test-Flight-Improv/35-cancelled-video-upload-still-sends-session-breakdown.md`
- `Test-Flight-Improv/39-introducer-intro-follow-up-copy-and-completion-card-session-breakdown.md`
- `Test-Flight-Improv/40-feed-stack-card-keeps-earlier-notification-messages-after-inline-reply-session-breakdown.md`
- `Test-Flight-Improv/41-notification-open-missing-incoming-messages-session-breakdown.md`
- `Test-Flight-Improv/00-INDEX.md`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/feed/domain/models/feed_item.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/conversation/application/retry_failed_messages_use_case.dart`
- `lib/features/conversation/application/delete_message_use_case.dart`
- `lib/features/introduction/application/insert_intro_system_message.dart`
- `lib/features/feed/presentation/screens/feed_screen.dart`
- `lib/main.dart`
- `lib/features/identity/presentation/startup_router.dart`
- `lib/core/services/p2p_service_impl.dart`
- `lib/features/push/application/prepare_notification_open_use_case.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/features/feed/application/feed_projection_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/features/conversation/application/retry_failed_messages_media_reupload_test.dart`
- `test/features/conversation/application/delete_message_use_case_test.dart`
- `test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart`
- `test/features/conversation/integration/message_deletion_roundtrip_test.dart`
- `test/features/conversation/integration/send_then_lock_delivery_test.dart`
- `test/features/conversation/presentation/screens/conversation_overflow_intro_test.dart`
- `test/features/introduction/presentation/widgets/intro_system_message_test.dart`
- `test/features/introduction/presentation/screens/sent_confirmation_test.dart`
- `test/features/introduction/application/introduction_listener_test.dart`
- `test/features/feed/presentation/widgets/introduction_connection_card_test.dart`
- `test/core/services/p2p_service_impl_test.dart`
- `test/core/notifications/app_root_notification_open_test.dart`
- `test/features/push/application/chat_and_group_push_open_flow_test.dart`
- `test/features/push/application/prepare_notification_open_use_case_test.dart`
- `test/integration/notification_deeplink_integration_test.dart`

## Why the decomposition is safe to send into downstream planning/execution

- Every still-open product gap in Report `43` now maps to one concrete session
  with named code-entry files, direct tests, and gate expectations.
- The split is not relying on stale closure prose; current code and tests were
  used to narrow old `35` and `41` rollout assumptions down to the live
  remainder.
- Each implementation session can land independently without leaving a
  misleading half-state, and Session `7` owns the final acceptance and
  maintenance-truth refresh so the folder does not keep contradicting itself.
- The decomposition now matches the user’s acceptance bar: this rollout is not
  done on touched suites alone; it must finish with a whole-app regression
  sweep and a green-or-explicitly-classified final test state.
