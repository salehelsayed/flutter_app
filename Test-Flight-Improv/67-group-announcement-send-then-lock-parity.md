# 1. Title and Type

- Title: Group and Announcement Send-Then-Lock Parity
- Issue type: `feature-improvement`
- Output doc path: `Test-Flight-Improv/67-group-announcement-send-then-lock-parity.md`

# 2. Problem Statement

- Users already have a strong trust expectation in 1:1 chat: if they tap send
  and lock the phone immediately, the app should keep that message safe and
  finish delivery or recovery without asking them to rewrite or resend it.
- For group chats and announcements, users are trying to rely on the same
  expectation: tap send, lock quickly, and trust that the message will not be
  lost, duplicated, or behave differently depending on which in-app send
  surface they used.
- Current repo evidence shows meaningful sender-side durability for group and
  announcement text sends, but not one clear repo-wide parity contract matching
  the existing 1:1 expectation across immediate-lock, mixed live/offline
  recipients, and every current text-send surface.
- This is a product problem because "I sent it just before I locked my phone"
  should not feel trustworthy in 1:1 chat but noticeably less settled in group
  chat or announcements.

# 3. Impact Analysis

- Affects users sending group messages and announcement admins posting updates
  just before pocketing or locking the phone.
- Most visible during normal mobile behavior: send and immediately background,
  recipients split between live and offline membership, or send initiated from a
  lighter-weight surface instead of the full conversation screen.
- The current cost is mainly trust and consistency. The repo already treats
  direct chat as a stronger interruption-safe path, while the maintained group
  and announcement closure references intentionally stop short of claiming that
  same parity.
- The issue does not require an already-proven data-loss bug to matter. A core
  messaging action that feels safe in one conversation type but not clearly
  equivalent in the others creates confusion about what "sent" means when the
  user immediately leaves the app.

# 4. Current State

- 1:1 chat already has an explicit interrupted-send durability story. The send
  path persists `wireEnvelope` before risky transport work, keeps failed and
  unacked retry paths, and has direct send-then-lock regression coverage.
  Evidence: `lib/features/conversation/application/send_chat_message_use_case.dart`,
  `lib/features/conversation/application/retry_failed_messages_use_case.dart`,
  `lib/features/conversation/application/retry_unacked_messages_use_case.dart`,
  `test/features/conversation/integration/send_then_lock_delivery_test.dart`
- Group and announcement sends already persist durable sender-side state in the
  shared send use case. Outgoing rows are saved with `status='sending'`,
  `wireEnvelope`, `inboxStored`, and `inboxRetryPayload` before bridge publish
  work begins. Evidence:
  `lib/features/groups/application/send_group_message_use_case.dart`,
  `lib/core/database/migrations/041_group_message_reliability_columns.dart`
- The main group conversation screen already wraps text and voice send flows in
  a bridge background task, and the current widget proof covers announcement
  admin lock/unmount behavior with both live peers and zero peers. Evidence:
  `lib/features/groups/presentation/screens/group_conversation_wired.dart`,
  `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`
- Group pause/resume recovery already includes pause-time transition of
  in-flight outgoing rows, group inbox drain, stuck-send recovery, incomplete
  upload retry, failed-send retry, and failed inbox-store retry. Evidence:
  `lib/core/lifecycle/handle_app_paused.dart`,
  `lib/core/lifecycle/handle_app_resumed.dart`,
  `lib/core/services/pending_message_retrier.dart`,
  `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`,
  `lib/features/groups/application/retry_failed_group_messages_use_case.dart`,
  `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`
- The maintained closure references explicitly describe current group and
  announcement reliability as trustworthy sender-side behavior, not as identical
  to 1:1 per-recipient proof. Evidence:
  `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`,
  `Test-Flight-Improv/21-announcement-reliability-closure-reference.md`
- Some current group text-send surfaces are less directly proven for
  immediate-lock parity than the main conversation screen. `feed_wired.dart`
  routes inline group replies through `sendGroupMessage(...)`, but the existing
  feed tests for that seam prove optimistic UI and failure restore rather than
  lock/suspend behavior. Evidence:
  `lib/features/feed/presentation/screens/feed_wired.dart`,
  `test/features/feed/presentation/screens/feed_wired_test.dart`
- The current shared group send path can persist a successful `sent` outcome
  while `inboxStored` is still unresolved in some live-peer success branches,
  with retry state retained for later completion. That means sender durability
  exists, but the repo does not currently express one simple user-facing parity
  rule equivalent to the current 1:1 interruption-safe expectation. Evidence:
  `lib/features/groups/application/send_group_message_use_case.dart`
- Existing group resume tests prove missed-message recovery for backgrounded
  readers, including announcement readers, but I did not find a matching exact-
  once rapid pause/resume sender regression for ordinary group text analogous to
  the direct-chat proof. Evidence:
  `test/features/groups/integration/group_resume_recovery_test.dart`,
  `test/features/conversation/integration/send_then_lock_delivery_test.dart`

# 5. Scope Clarification

- In scope:
  - user-visible parity for text sends in group chats and announcements when
    the sender locks or backgrounds immediately after tapping send
  - sender trust across the currently reachable in-app text send surfaces for
    groups and announcements
  - consistent behavior when recipients are a mix of live and offline members
  - exact-once/no-loss expectations from the sender perspective during
    pause/resume or reconnect around the send moment
- Explicit non-goals:
  - read receipts or per-recipient proof UI
  - total ordering across devices
  - broader media-upload or true background-upload guarantees
  - announcement auth redesign, scheduling, analytics, or notification product
    scope
  - unrelated backlog-retention, discovery, or membership-policy work
- Accepted ambiguities for the later implementation pass:
  - whether "same reliability as 1:1" stops at sender-side no-loss trust or
    later expands into stronger recipient-confirmation semantics
  - whether every auxiliary surface must be included in the first parity pass or
    whether some current flows can remain explicitly narrower
  - exact sender-visible status wording, as long as the resulting behavior is
    consistent and trustworthy after immediate lock/background

# 6. Test Cases

## Happy Path

- From the main group conversation screen, a member sends a text message and
  locks or backgrounds immediately; when they return, the message still appears
  exactly once in the sender thread and each eligible group member eventually
  receives exactly one copy.
- From the main announcement conversation screen, an admin sends a text
  announcement and locks or backgrounds immediately; readers eventually receive
  exactly one copy and the sender does not need to resend manually.
- If no other members are live when the sender immediately locks after a group
  or announcement text send, the sender still sees a stable saved result and
  offline recipients receive the message once during later recovery.
- If some members are live and some are offline when the sender immediately
  locks after a group or announcement text send, live members receive the
  message normally and offline members still recover exactly one copy later
  without the sender creating a duplicate.

## Edge Cases

- Rapid repeated pause/resume cycles around the same outgoing group text do not
  create duplicate local rows, duplicate remote deliveries, or conflicting
  sender-visible status.
- The same immediate-lock reliability expectation holds when the user sends from
  any still-supported in-app group or announcement text surface, not only the
  fully expanded main conversation screen.
- An interrupted send that remains incomplete after the first background event
  still resumes or retries from durable local state rather than disappearing or
  requiring the user to rewrite the text.
- Announcement readers remain read-only throughout this flow; stronger send
  reliability for announcement admins does not reopen non-admin write access.
- A backgrounded or offline member who later catches up through recovery sees a
  missed text once, without duplicate replay from both live delivery and backlog
  delivery.

## Regressions To Preserve

- Existing durable pre-persist behavior for outgoing group and announcement
  messages remains intact.
- Existing group pause/resume recovery and offline backlog drain continue to
  work for ordinary missed-message recovery.
- Existing announcement admin lock/unmount behavior already covered in widget
  tests keeps working.
- Existing 1:1 send-then-lock behavior remains unchanged while group and
  announcement parity work lands.
- Existing inline group-reply optimistic UI and failure-restore behavior in feed
  keeps working after this parity improvement.

## Existing Partial Coverage Today

- Announcement admin lock/unmount coverage exists in
  `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`
- Group reader catch-up and announcement reader catch-up coverage exist in
  `test/features/groups/integration/group_resume_recovery_test.dart`
- Inline group reply optimistic/failure behavior is covered in
  `test/features/feed/presentation/screens/feed_wired_test.dart`
- Stronger direct-chat interrupted-send proof exists in
  `test/features/conversation/integration/send_then_lock_delivery_test.dart`

## Current Coverage Gaps

- No matching exact-once rapid pause/resume sender proof for ordinary group text
- No direct lock/suspend parity proof for ordinary group text that mirrors the
  current announcement widget proof
- No direct lock/suspend proof for all current non-conversation group or
  announcement text send surfaces
- No direct proof covering the mixed live-member plus offline-member send-then-
  lock case from the sender perspective
