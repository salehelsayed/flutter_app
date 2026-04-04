# 43 - 30-41 Audit Follow-up Remaining Gaps

## 1. Title and Type

- Title: `30-41 audit follow-up remaining gaps`
- Issue type: `feature-improvement`
- Output doc path: `Test-Flight-Improv/43-30-41-audit-follow-up-remaining-gaps.md`

## 2. Problem Statement

- The user is trying to confirm that the product work tracked by
  `Test-Flight-Improv/30-swipe-nav-feed-orbit.md` through
  `Test-Flight-Improv/41-notification-open-missing-incoming-messages.md`
  is actually complete in the live app.
- Current repo evidence shows that several reports in that range now appear to
  be implemented, but a smaller set of trust-sensitive user flows still remain
  incomplete or only partially closed.
- From the user's perspective, that means the audit cannot honestly be treated
  as fully done yet. Some high-value messaging behaviors still have gaps around:
  canceled video sends, delete-for-everyone reliability, introducer-side intro
  follow-up, Feed unread stack accuracy after inline reply, and
  notification-open message visibility guarantees.
- The product problem is therefore not "nothing was implemented." The problem is
  that the remaining unresolved gaps are concentrated in flows where users need
  the app to be accurate and trustworthy.

## 3. Impact Analysis

- Who is affected:
  - users replying from Feed cards
  - users canceling direct-message video uploads
  - users using delete-for-everyone in 1:1 chats
  - users acting as the introducer in friend introductions
  - users opening chats or groups from notifications
- When the issue appears:
  - after an inline Feed reply when later unread messages arrive from the same
    contact
  - after a sender cancels an in-flight video upload and later retries or
    lifecycle recovery occurs
  - when delete-for-everyone is pending, fails, reorders, or survives
    pause/resume
  - when the introducer expects durable name-aware history and durable
    completion follow-up after a successful intro
  - when notification-open recovery uses degraded inbox retrieval or later
    fallback handling
- Severity:
  - moderate to high overall, because the remaining gaps sit inside messaging
    trust, delivery trust, and durable social-history flows
- Frequency:
  - repo evidence does not support a single frequency for the whole cluster
  - the affected paths are concentrated in repeatable edge flows rather than a
    one-off internal-only state
- Visible user costs supported by the current code:
  - a canceled media send can still remain retryable
  - a delete-for-everyone action can look finished for the sender before remote
    finalization is known
  - Feed can resurface older unread messages that the user already replied to
  - introducers still lose specific durable history and durable completion
    follow-up
  - a notification-opened route can still settle without visibly surfacing the
    promised message in some degraded retrieval paths

## 4. Current State

- Adjacent audit context:
  - the current repo appears to have substantially landed the main product work
    for reports `30`, `31`, `32`, `33`, `34`, `36`, and `38`
  - this follow-up spec is only about the unresolved remainder discovered by
    the codebase review

- Affected code areas:
  - Feed unread/open-mode reply flow:
    - `lib/features/feed/presentation/screens/feed_wired.dart`
    - `lib/features/feed/domain/models/feed_item.dart`
    - `lib/features/conversation/domain/repositories/message_repository_impl.dart`
  - Direct conversation media cancel and retry:
    - `lib/features/conversation/presentation/screens/conversation_wired.dart`
    - `lib/features/conversation/application/retry_failed_messages_use_case.dart`
    - `lib/main.dart`
  - Delete-for-everyone reliability:
    - `lib/features/conversation/application/delete_message_use_case.dart`
    - `lib/features/conversation/application/retry_failed_messages_use_case.dart`
    - `lib/features/conversation/application/retry_unacked_messages_use_case.dart`
    - `lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart`
    - `lib/core/lifecycle/handle_app_paused.dart`
    - `lib/core/lifecycle/handle_app_resumed.dart`
  - Introducer-side intro history and follow-up:
    - `lib/features/conversation/presentation/screens/conversation_wired.dart`
    - `lib/features/introduction/application/insert_intro_system_message.dart`
    - `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`
    - `lib/features/feed/presentation/screens/feed_screen.dart`
  - Notification-open recovery:
    - `lib/main.dart`
    - `lib/features/identity/presentation/startup_router.dart`
    - `lib/features/push/application/prepare_notification_open_use_case.dart`
    - `lib/core/services/p2p_service_impl.dart`
    - `lib/core/database/helpers/inbox_staging_db_helpers.dart`

- Existing user-visible flow today:
  - Feed inline reply still sets a local `SessionReply`, marks the conversation
    read, and then merges the outgoing message into the existing in-memory
    thread instead of forcing a fresh post-read thread snapshot. Open-mode card
    rendering still depends on `thread.unreadMessages`, which is derived from
    existing `isUnread` flags on the thread messages.
    Evidence:
    `lib/features/feed/presentation/screens/feed_wired.dart`,
    `lib/features/feed/domain/models/feed_item.dart`,
    `test/features/feed/presentation/screens/feed_wired_test.dart`,
    `test/features/feed/application/feed_projection_test.dart`
  - Video upload cancel now suppresses the immediate in-flight send path before
    the final message send, but the canceled optimistic row is restored as a
    generic failed-media row with retry/delete affordances. Shared failed-send
    recovery still knows how to re-upload and resend failed media rows on later
    retry/resume.
    Evidence:
    `lib/features/conversation/presentation/screens/conversation_wired.dart`,
    `lib/features/conversation/application/retry_failed_messages_use_case.dart`,
    `test/features/conversation/presentation/screens/conversation_wired_test.dart`,
    `test/features/conversation/application/retry_failed_messages_media_reupload_test.dart`
  - Delete-for-everyone already builds and sends a `message_deletion` tombstone
    and the recipient-side delete listener can apply it when the target message
    exists locally. The sender-side row is hidden immediately through
    `hidden_at`, including on failure, and shared pause/resume retry handling is
    reused rather than a delete-specific user-visible contract.
    Evidence:
    `lib/features/conversation/application/delete_message_use_case.dart`,
    `lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart`,
    `test/features/conversation/integration/message_deletion_roundtrip_test.dart`,
    `test/features/conversation/application/delete_message_use_case_test.dart`
  - Introducer-side send history still stores count-only copy
    (`You introduced N people to ...`) while the actual introduced usernames are
    only shown on the transient sent-confirmation screen. Later durable
    completion surfacing still exists for the newly connected participants, not
    for the introducer.
    Evidence:
    `lib/features/conversation/presentation/screens/conversation_wired.dart`,
    `lib/features/introduction/application/insert_intro_system_message.dart`,
    `lib/features/introduction/presentation/screens/sent_confirmation_screen.dart`,
    `lib/features/feed/presentation/screens/feed_screen.dart`
  - Notification-open routing now prepares before route open for local and
    remote paths, and durable inbox staging plus reject metadata are present.
    But the inbox service still has fallback paths that can drop into the older
    destructive retrieve behavior, and some failure paths still collapse into
    "no surfaced message" rather than an explicit trustworthy outcome.
    Evidence:
    `lib/main.dart`,
    `lib/features/identity/presentation/startup_router.dart`,
    `lib/core/services/p2p_service_impl.dart`,
    `test/features/push/application/chat_and_group_push_open_flow_test.dart`,
    `test/core/services/p2p_service_impl_test.dart`

- Important constraints and edge conditions already present in code/tests:
  - reports `30`, `31`, `32`, `33`, `34`, `36`, and `38` already have real code
    and targeted regression coverage, so this spec should not reopen them as
    missing
  - intro participant-side completion is already visible through
    `IntroductionConnectionCard`; the remaining gap is introducer-side durability
  - durable inbox staging already stores reject reason metadata, so the
    notification-open problem is now narrower than the original "no preparation"
    failure mode
  - delete-for-everyone is intentionally limited to delivered outgoing 1:1
    messages; that eligibility rule is existing behavior, not part of the gap
  - direct message cancel, delete, and notification-open behaviors already have
    partial regression coverage, but not enough to close the remaining
    user-visible contract

## 5. Scope Clarification

- In scope:
  - unresolved user-visible gaps remaining after the `30` to `41` code audit
  - Feed inline-reply unread-stack truthfulness
  - cancel meaning a final stop for direct-message video sends
  - sender-visible honesty and lifecycle reliability for delete-for-everyone
  - introducer-side durable intro send copy and durable completion follow-up
  - trustworthy notification-open message visibility in degraded inbox-recovery
    paths
- Non-goals:
  - reopening reports from `30` to `41` that already appear implemented in the
    current repo
  - choosing the final code ownership seam for any of these gaps
  - redesigning unrelated navigation, feed, orbit, or introduction UI beyond
    what is required to satisfy the unresolved user-visible contracts
  - turning this follow-up into rollout sessions or an implementation plan
- Accepted ambiguities:
  - the exact final copy for sender-visible pending/failed delete states
  - the exact final copy or host surface for introducer-side completion, as long
    as it is durable and user-facing
  - whether notification-open degraded paths surface a dedicated error state, a
    deferred loading state, or another truthful user-visible outcome, as long as
    the app does not silently imply there were no new messages
  - whether canceled upload history remains invisible or appears as a clearly
    terminal canceled state, as long as it is not retryable or later deliverable

## 6. Test Cases

### Happy Path

- `TC-43-HP-01` Given user-B receives `message-a-1` on Feed and replies inline
  with `message-b-1`, when user-A later sends `message-a-2`, then the reopened
  Feed stack card shows only the incoming messages that are new since the latest
  local reply rather than resurfacing `message-a-1`.
- `TC-43-HP-02` Given a sender starts uploading a direct-message video and taps
  `Cancel`, when the send flow settles, then that attempt is treated as canceled
  rather than as a normal failed message and it does not later resend or reach
  the recipient.
- `TC-43-HP-03` Given a sender uses delete-for-everyone on a delivered 1:1
  message, when the delete is still pending or fails, then the sender sees a
  truthful user-visible state rather than the original message silently
  disappearing as if the remote delete had already finished.
- `TC-43-HP-04` Given user-A introduces user-C to user-B from the conversation
  with user-B, when the send completes, then the durable system message in that
  conversation names the introduced person or people rather than collapsing to a
  count-only summary.
- `TC-43-HP-05` Given the same introduction later reaches mutual acceptance,
  when user-A revisits the app after the transient notification is gone, then
  user-A still has a persistent user-facing completion surface showing that the
  introduced pair connected.
- `TC-43-HP-06` Given a user taps a chat or group notification, when the route
  opens, then the relevant conversation or group visibly contains the incoming
  message or messages that caused the notification during that same open flow.

### Edge Cases

- `TC-43-EC-01` Given a longer Feed card back-and-forth
  (`A1 -> B1 -> A2 -> B2 -> A3`), when the card reopens after `A3`, then only
  the post-`B2` incoming unread messages remain in the open-mode stack.
- `TC-43-EC-02` Given a sender cancels a video upload and then backgrounds,
  resumes, or restarts the app, when shared recovery runs later, then the
  canceled attempt does not reappear as retryable and does not resend.
- `TC-43-EC-03` Given delete-for-everyone survives pause/resume or lock/unlock
  while still pending, when the app recovers, then the sender and recipient
  eventually converge on one truthful outcome without the sender losing visible
  context prematurely.
- `TC-43-EC-04` Given a delete event reaches the recipient before the original
  message row is locally available, when later ordering catches up, then the
  final visible recipient state still resolves correctly instead of permanently
  ignoring the delete.
- `TC-43-EC-05` Given multiple users were introduced in one send, when user-A
  revisits the durable conversation history later, then the visible summary
  stays truthful about who was introduced even if truncation is needed.
- `TC-43-EC-06` Given a notification-open path falls onto a degraded or
  fallback inbox-recovery path, when retrieval or replay does not fully
  complete, then the user still gets a truthful visible outcome rather than an
  apparently unchanged thread that silently contradicts the notification.
- `TC-43-EC-07` Given staged inbox replay rejects or defers a recovered message
  because of unknown sender, duplicate handling, missing ML-KEM secret, or
  another local validation failure, when support or QA inspects the client
  record later, then the exact reason remains recoverable from client-side
  diagnostics.

### Regressions To Preserve

- `TC-43-RG-01` Preservation: The already-landed swipe navigation, edit,
  delete-for-me, live Orbit intro delete, selected-message overlay, and
  mutual-accept participant flows from reports `30`, `31`, `33`, `34`, `36`,
  and `38` continue to behave as they do today.
- `TC-43-RG-02` Bug regression: After an inline reply from Feed, earlier unread
  incoming messages that were already answered must not reappear in the next
  notification-led open-mode stack for that contact.
- `TC-43-RG-03` Bug regression: A canceled direct-message video upload must not
  later resend because of manual retry, background resume, or failed-message
  recovery.
- `TC-43-RG-04` Bug regression: Delete-for-everyone must not leave the sender
  with a product state that looks finalized while the remote delete is still
  pending or failed.
- `TC-43-RG-05` Bug regression: Tapping a notification for a chat or group must
  not settle into an opened thread that still shows none of the pending incoming
  messages promised by that notification.
- `TC-43-RG-06` Preservation: Participant-side introduction completion still
  creates the new contact and still allows the existing
  `IntroductionConnectionCard` experience for the newly connected users.

### Existing Coverage And Gaps

- Existing partial coverage:
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
  - `test/features/feed/application/feed_projection_test.dart`
  - `test/features/conversation/presentation/screens/conversation_wired_test.dart`
  - `test/features/conversation/application/delete_message_use_case_test.dart`
  - `test/features/conversation/integration/message_deletion_roundtrip_test.dart`
  - `test/features/conversation/application/retry_failed_messages_media_reupload_test.dart`
  - `test/features/push/application/chat_and_group_push_open_flow_test.dart`
  - `test/core/services/p2p_service_impl_test.dart`
  - `test/features/introduction/presentation/screens/sent_confirmation_test.dart`
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
- Current coverage gaps:
  - no direct end-to-end regression was found for the full Feed sequence
    `incoming -> inline reply -> later incoming -> older unread excluded`
  - no direct regression was found proving canceled direct-message video sends
    remain non-retryable and non-deliverable across resume/retry flows
  - no delete-for-everyone lock/pause-resume integration regression was found
    matching the normal send lifecycle depth
  - no automated test was found for introducer-side durable name-aware history
    or introducer-side persistent completion surfacing
  - no app-root end-to-end notification-open regression was found proving the
    opened thread visibly contains the notified message after real route open in
    all relevant local/remote entry paths
