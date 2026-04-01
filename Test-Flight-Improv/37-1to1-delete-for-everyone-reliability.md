# 37 - 1:1 Delete for Everyone Reliability

## 1. Title and Type

- Title: `1:1 Delete for Everyone Reliability`
- Issue type: `bug`
- Output doc path: `Test-Flight-Improv/37-1to1-delete-for-everyone-reliability.md`

## 2. Problem Statement

- The user is trying to retract a previously delivered 1:1 message for both sides and trust that the delete action is as reliable as a normal sent message, including when the app is backgrounded, the phone is locked, or the recipient is offline.
- The current product can create and send a delete-for-everyone tombstone, but the sender-facing row can disappear before the remote delete is fully finalized, and the current repo evidence does not prove a dedicated delete-specific pause/resume or lock-screen recovery path equivalent to the normal 1:1 send flow.
- This is a product problem because delete-for-everyone is a trust-sensitive action. If the sender sees the original content disappear locally, but the recipient can still retain or continue seeing the original content under lifecycle or ordering edge cases, the app overstates what the delete action actually accomplished.

## 3. Impact Analysis

- Who is affected:
  - Senders using delete-for-everyone in 1:1 conversations from Orbit or Feed.
  - Recipients who may receive the original message and the deletion event under offline catch-up or reordered delivery conditions.
- When the issue appears:
  - When the delete send fails or is only partially finalized.
  - When the sender backgrounds the app or locks the phone immediately after choosing delete-for-everyone.
  - When the recipient is offline and later drains inbox state.
  - When a delete event reaches the recipient before the original message row exists locally.
- Severity:
  - Moderate from a feature-surface perspective because the delete action exists and works in covered happy paths.
  - High trust cost in affected cases because users are relying on message retraction, not a cosmetic local hide.
- Frequency:
  - Lower than normal send frequency because it only affects users who choose delete-for-everyone.
  - The confusing cases are concentrated in network, offline, and lifecycle edges rather than every delete action.
- Visible confusion and dead-end cost supported by current code:
  - A failed delete-for-everyone is stored as a hidden failed tombstone, so the original row disappears from normal conversation queries even when the remote delete is not yet confirmed.
  - The conversation and feed delete entry points treat any returned updated tombstone as enough to refresh UI and return, while the visible failure snackbar only appears when no updated message is returned.

## 4. Current State

- Adjacent product context:
  - `Test-Flight-Improv/33-delete-message-for-me-everyone.md` described the original missing delete feature before the current delete-for-me and delete-for-everyone flow was implemented.

- Affected code areas:
  - 1:1 delete entry points:
    - `lib/features/conversation/presentation/screens/conversation_wired.dart`
    - `lib/features/feed/presentation/screens/feed_wired.dart`
  - Delete transport and tombstone contract:
    - `lib/features/conversation/application/delete_message_use_case.dart`
  - Generic 1:1 retry and lifecycle recovery:
    - `lib/core/lifecycle/handle_app_paused.dart`
    - `lib/core/lifecycle/handle_app_resumed.dart`
    - `lib/features/conversation/application/retry_failed_messages_use_case.dart`
    - `lib/features/conversation/application/retry_unacked_messages_use_case.dart`
  - Sender-visible filtering and DB queries:
    - `lib/core/database/helpers/messages_db_helpers.dart`
  - Recipient-side delete application:
    - `lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart`
    - `lib/features/conversation/application/message_deletion_listener.dart`
    - `lib/main.dart`

- Existing user-visible flow today:
  - Orbit and Feed only offer delete-for-everyone for the sender's own 1:1 messages whose current status is `delivered`.
    - Evidence:
      - `lib/features/conversation/presentation/screens/conversation_wired.dart` lines 1032-1112
      - `lib/features/feed/presentation/screens/feed_wired.dart` lines 340-418
  - The delete-for-everyone use case builds a `message_deletion` payload, writes a tombstone row with cleared content, `hiddenAt`, `status: 'sending'`, and a stored `wireEnvelope`, then attempts the same local/direct/relay/inbox ladder used by normal 1:1 sends.
    - Evidence:
      - `lib/features/conversation/application/delete_message_use_case.dart` lines 48-367
      - `lib/features/conversation/application/delete_message_use_case.dart` lines 477-560
  - On success, the tombstone can end as:
    - `delivered` with no `wireEnvelope`
    - `sent` with a retained `wireEnvelope` when transport succeeded but no ACK/inbox handoff completed yet
    - `failed` with a retained `wireEnvelope`
    - Evidence:
      - `lib/features/conversation/application/delete_message_use_case.dart` lines 321-367
      - `lib/features/conversation/application/delete_message_use_case.dart` lines 524-560
  - Conversation and feed message queries hide sender-side tombstones from normal visible lists because visible queries require `hidden_at IS NULL`.
    - Evidence:
      - `lib/core/database/helpers/messages_db_helpers.dart` lines 5, 44-129
      - `test/features/conversation/presentation/screens/conversation_wired_test.dart` lines 2406-2452
      - `test/features/feed/presentation/screens/feed_wired_test.dart` lines 4865-4888
  - A failed delete-for-everyone can therefore disappear from the sender's visible list while still remaining in the database as a hidden failed tombstone.
    - Evidence:
      - `test/features/conversation/application/delete_message_use_case_test.dart` lines 121-159
  - The conversation and feed delete entry points return early when an updated message is returned from the delete use case; the user-visible failure snackbar only appears when the use case returns no updated message.
    - Evidence:
      - `lib/features/conversation/presentation/screens/conversation_wired.dart` lines 1069-1095
      - `lib/features/feed/presentation/screens/feed_wired.dart` lines 381-409

- Important constraints and edge conditions already present in code:
  - The delete path is intentionally narrower than a general unsend:
    - delete-for-everyone is blocked for incoming messages, already-deleted messages, and non-`delivered` outgoing rows.
    - Evidence:
      - `lib/features/conversation/application/delete_message_use_case.dart` lines 88-112
      - `lib/features/conversation/presentation/screens/conversation_wired.dart` lines 1106-1112
      - `lib/features/feed/presentation/screens/feed_wired.dart` lines 412-418
  - The normal 1:1 send surfaces acquire a presentation-layer background task before send/upload, but the delete-for-everyone entry points do not show equivalent background-task acquisition before invoking the delete use case.
    - Evidence:
      - `lib/features/conversation/presentation/screens/conversation_wired.dart` lines 1313-1331
      - `lib/features/feed/presentation/screens/feed_wired.dart` lines 1528-1541
      - `lib/features/conversation/presentation/screens/conversation_wired.dart` lines 1032-1095
      - `lib/features/feed/presentation/screens/feed_wired.dart` lines 340-409
      - `test/features/conversation/application/send_chat_message_no_bg_task_test.dart` lines 231-257
  - The shared pause handler transitions any outgoing `sending` row to `failed`, and the shared resume handler runs the ordered 1:1 recovery chain `recoverStuckSendingMessages -> retryIncompleteUploads -> retryFailedMessages -> retryUnackedMessages`.
    - Evidence:
      - `lib/core/lifecycle/handle_app_paused.dart` lines 17-147
      - `lib/core/lifecycle/handle_app_resumed.dart` lines 308-406
  - The failed and unacked DB queries are status-based and do not exclude hidden tombstones, so sender-side delete tombstones participate in the same retry sweeps as ordinary 1:1 outgoing rows.
    - Evidence:
      - `lib/core/database/helpers/messages_db_helpers.dart` lines 544-621
      - `lib/core/database/helpers/messages_db_helpers.dart` lines 680-816
  - The generic failed-message retrier first tries inbox replay using the stored `wireEnvelope`, but if that does not complete it falls through to `sendChatMessage(...)` with the row's current text and attachments.
    - Evidence:
      - `lib/features/conversation/application/retry_failed_messages_use_case.dart` lines 173-223
      - `lib/features/conversation/application/retry_failed_messages_use_case.dart` lines 247-280
  - Recipient-side delete application is strict:
    - the app registers a dedicated `message_deletion` listener at startup
    - the delete is only applied if the target message row already exists locally
    - spoofed sender mismatches are rejected
    - missing target messages are ignored
    - Evidence:
      - `lib/main.dart` lines 934-946, 1129-1130
      - `lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart` lines 22-130
      - `test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart` lines 190-235

- Existing test coverage that describes today's behavior:
  - Covered today:
    - online delete-for-everyone hides the sender row and tombstones the recipient:
      - `test/features/conversation/integration/message_deletion_roundtrip_test.dart` lines 41-70
    - offline inbox ordering leaves the recipient with a tombstoned final row:
      - `test/features/conversation/integration/message_deletion_roundtrip_test.dart` lines 73-105
    - failed delete-for-everyone persists as a hidden failed tombstone:
      - `test/features/conversation/application/delete_message_use_case_test.dart` lines 121-159
    - Orbit and Feed UI refresh hidden tombstones out of visible surfaces:
      - `test/features/conversation/presentation/screens/conversation_wired_test.dart` lines 2406-2452
      - `test/features/feed/presentation/screens/feed_wired_test.dart` lines 4865-4888
    - normal 1:1 send has dedicated send-then-lock coverage and pause/resume recovery coverage:
      - `test/features/conversation/integration/send_then_lock_delivery_test.dart` lines 1033-1315
  - Gaps visible from the current suite inventory:
    - no delete-for-everyone pause/resume or lock-screen integration test was found alongside the proven normal send lock tests
    - no delete-specific test was found for sender-visible behavior when the delete row is hidden locally but remote deletion is still pending or failed
    - no delete-specific test was found for the case where delete envelope replay fails and the generic failed-message retry falls through to the normal send path

## 5. Scope Clarification

- In scope:
  - User-visible reliability expectations for delete-for-everyone in 1:1 conversations.
  - Both sender-facing entry surfaces:
    - Orbit conversation
    - Feed inline conversation cards
  - Sender-visible outcome honesty when the delete action is still pending, partially finalized, or failed.
  - Recipient-visible final state after online delivery, offline catch-up, and lifecycle recovery.
  - Acceptance criteria for lock, pause, resume, and offline ordering cases.

- Non-goals:
  - Delete-for-me local deletion behavior.
  - Group-message deletion behavior.
  - A time-window policy for delete-for-everyone eligibility.
  - Architecture choices, queue design, retry design, or transport design.
  - Session decomposition, rollout steps, or implementation planning.

- Accepted ambiguities to keep open for later implementation work:
  - Exact sender copy or status wording when a delete is pending versus failed.
  - Exact recipient placeholder wording and styling for deleted rows.
  - Exact user-facing handling for legacy or unsupported recipients beyond the current evidence that unknown or missing delete targets can be ignored locally.

## 6. Test Cases

### Happy Path

- When a user deletes their own delivered 1:1 message for everyone while both users are online, the sender no longer sees the original content and the recipient sees a deleted placeholder for the same message instead of the original text or media.
- When a user deletes their own delivered 1:1 message for everyone while the recipient is offline, the sender eventually sees an honest finalized state, and after the recipient resumes and drains offline inbox state, the recipient sees the deleted placeholder rather than the original content.
- When a user deletes their own delivered 1:1 message for everyone from Feed, the contact card refreshes to the correct next latest visible state without leaving the deleted message preview behind.
- Existing direct coverage today:
  - `test/features/conversation/integration/message_deletion_roundtrip_test.dart`
  - `test/features/feed/presentation/screens/feed_wired_test.dart`

### Edge Cases

- When a user chooses delete-for-everyone and immediately locks the phone or backgrounds the app, the app eventually resolves that message to one honest state: remote deletion completed, or an explicit sender-visible pending or failure state. The original content must not silently disappear for the sender while remaining visible to the recipient.
- When a delete-for-everyone transport attempt fails, the sender must not be left with a UI that looks complete if the remote delete has not actually been finalized yet.
- When the recipient receives the original message and the deletion event under delayed or reordered offline catch-up, the recipient's final visible row must resolve to the deleted placeholder rather than retaining the original content.
- When the recipient receives a delete for a message that is missing locally, the app must remain stable and the resulting sender-facing product state must not overstate that the recipient definitely lost the original content.
- When a delete-for-everyone action survives multiple pause/resume cycles, it must not duplicate, resurrect the original content, or leave sender and recipient in contradictory visible states.
- Current gap:
  - No delete-for-everyone pause/resume or lock-screen integration test was found that matches the normal send lock coverage in `test/features/conversation/integration/send_then_lock_delivery_test.dart`.

### Regressions To Preserve

- Delete-for-everyone remains unavailable for incoming messages, already-deleted rows, and outgoing rows that are not yet `delivered`.
- Authorized recipient-side deletes continue to apply only when the original message sender matches the delete payload sender.
- Existing online delete-for-everyone success and offline inbox ordering continue to produce a deleted recipient placeholder rather than a hard-missing or duplicated row.
- Sender-side visible lists continue to avoid showing deleted outgoing content once a delete-for-everyone action has actually finalized.
- Existing direct coverage today:
  - `test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart`
  - `test/features/conversation/integration/message_deletion_roundtrip_test.dart`
  - `test/features/conversation/presentation/screens/conversation_wired_test.dart`

