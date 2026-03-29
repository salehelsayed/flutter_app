# 33 - Delete Message: "Delete for Me" and "Delete for Everyone"

**New Feature**

---

## 1. Problem Statement

Once a message is sent, the user has no way to delete it — either locally or
from the recipient's device. There is no "Delete" option in any message
interaction. Users cannot unsend a message or remove it from their conversation
view.

**Current behavior:**

- Long-press on a message only shows the emoji reaction bar (6 preset emojis +
  full picker). No context menu with actions like Delete exists.
- The only existing message deletion is at the **contact level** — deleting an
  entire contact deletes all their messages (delete_contact_use_case.dart).
  There is also a **failed-media message** delete for cleaning up upload
  failures (conversation_wired.dart:1369–1389).
- No mechanism exists to notify the recipient that a message has been deleted
  ("Delete for Everyone").
- No `message_deletion` payload type exists in the P2P protocol.
- No soft-delete or `is_deleted` column exists in the messages DB schema.

**What is needed (per the WhatsApp-style reference image):**

1. User long-presses any message → context menu appears (per Report 26) with a
   "Delete" option.
2. Tapping "Delete" shows a bottom sheet / dialog: **"Who would you like to
   delete this message for?"** with three buttons:
   - **"Delete for Me"** — removes the message from the user's local DB only.
   - **"Delete for Everyone"** — removes the message locally AND sends a
     deletion signal to the recipient via P2P, causing the recipient's app to
     remove the message as well.
   - **"Cancel"** — dismisses the dialog with no action.
3. After deletion, the message disappears from the conversation.

**Who is affected:** All users in 1:1 conversations.

---

## 2. Impact Analysis

| Dimension | Assessment |
|-----------|-----------|
| Severity | Moderate — no way to unsend or clean up messages |
| Frequency | Any time a user sends a message they want to retract |
| User consequence | Sent messages are permanent; no privacy control over shared content |
| Workaround | None — messages cannot be deleted once sent |
| Platform scope | iOS and Android (Flutter) |

| Delete Mode | Sender Effect | Recipient Effect |
|-------------|--------------|-----------------|
| Delete for Me | Message removed from sender's conversation | No change — recipient still sees the message |
| Delete for Everyone | Message removed from sender's conversation | Message removed from recipient's conversation |
| Cancel | No change | No change |

---

## 3. Current State

### 3.1 Message Model

| File | Key Lines |
|------|-----------|
| `lib/features/conversation/domain/models/conversation_message.dart` | Lines 7–48 |

- Fields: `id`, `contactPeerId`, `senderPeerId`, `text`, `timestamp`,
  `status` (`'sending'`/`'sent'`/`'delivered'`/`'failed'`), `isIncoming`,
  `createdAt`, `readAt`, `quotedMessageId`, `transport`, `wireEnvelope`,
  `media` (transient).
- **No `isDeleted`, `deletedAt`, or deletion-related field exists.**

### 3.2 Database Schema

| File | Key Lines |
|------|-----------|
| `lib/core/database/migrations/002_messages_table.dart` | Lines 6–16 |

- Columns: `id` (PK), `contact_peer_id`, `sender_peer_id`, `text` (NOT NULL),
  `timestamp`, `status`, `is_incoming`, `created_at`.
- Extended by migrations: `read_at` (006), `quoted_message_id` (009),
  `transport` (012), `wire_envelope` (014).
- **No `is_deleted` column exists.**

### 3.3 Existing Message Deletion Methods

| File | Method | Key Lines |
|------|--------|-----------|
| `lib/features/conversation/domain/repositories/message_repository.dart` | `deleteMessage(String id)` | Line 50 |
| `lib/features/conversation/domain/repositories/message_repository.dart` | `deleteMessagesForContact(String contactPeerId)` | Line 47 |
| `lib/core/database/helpers/messages_db_helpers.dart` | `dbDeleteMessage()` | Lines 498–524 |
| `lib/core/database/helpers/messages_db_helpers.dart` | `dbDeleteMessagesForContact()` | Lines 459–496 |

- `deleteMessage(id)` performs a **hard delete** (`DELETE FROM messages WHERE id = ?`).
- Flow events emitted: `MESSAGES_DB_DELETE_START`, `_SUCCESS`, `_ERROR`.
- These are local-only operations — no P2P notification is sent.
- Currently used by: `_onDeleteFailedMedia()` in conversation_wired.dart and
  `deleteContactAndMessages()` use case.

### 3.4 Failed Message Delete Pattern (Report 24)

| File | Key Lines |
|------|-----------|
| `lib/features/conversation/presentation/screens/conversation_wired.dart` | Lines 1369–1389 |

`_onDeleteFailedMedia(messageId)` cleanup cascade:
1. Query related media attachments.
2. Mark pending upload attachments as failed.
3. Delete local pending upload files via `mediaFileManager`.
4. Delete attachment DB records via `mediaAttachmentRepo.deleteAttachmentsForMessage()`.
5. Delete message from DB via `messageRepo.deleteMessage()`.
6. Remove from local UI state via `_removeLocalMessage()`.

This is the established pattern for message deletion with media cleanup.

### 3.5 P2P Message Protocol

| File | Purpose |
|------|---------|
| `lib/features/conversation/domain/models/message_payload.dart` | Chat message wire format |
| `lib/features/conversation/domain/models/reaction_payload.dart` | Reaction wire format (with `action` field) |
| `lib/core/services/incoming_message_router.dart` | Routes incoming P2P messages by `type` field |

**Message types currently routed:** `chat_message`, `message_reaction`,
`contact_request`, `profile_update`, `group_invite`, `introduction`, etc.

**No `message_deletion` type exists** in the router.

**Reaction payload pattern** (reaction_payload.dart): Has an `action` field
(`'add'` / `'remove'`) showing the established pattern for action-based P2P
messages. A deletion payload would follow this pattern with its own `type`
(e.g., `message_deletion`) containing the `messageId` to delete.

### 3.6 Incoming Message Handling

| File | Key Lines |
|------|-----------|
| `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart` | Lines 150–159 |

- Duplicate check: `messageRepo.messageExists(payload.id)` — rejects duplicates.
- Incoming handler does not process deletions — no mechanism to receive a
  "delete this message" signal from the sender.

### 3.7 Long-Press / Context Menu

| File | Key Lines |
|------|-----------|
| `lib/features/conversation/presentation/screens/conversation_screen.dart` | Lines 437–438, 549–580 |
| `lib/features/conversation/presentation/widgets/reaction_bar.dart` | Lines 1–155 |
| `lib/features/conversation/presentation/widgets/letter_card.dart` | Lines 30, 66–67 |
| `lib/features/feed/presentation/widgets/message_bubble.dart` | Lines 32, 64–65 |

- Long-press on `LetterCard` or `MessageBubble` fires `onLongPress` callback.
- Currently wired to `_showReactionBar()` which shows only the emoji reaction bar.
- Report 26 proposes adding Reply/Copy options. Report 31 proposes Edit. Delete
  would be an additional option in the same context menu.

### 3.8 Media Attachments

| File | Purpose |
|------|---------|
| `lib/features/conversation/domain/repositories/media_attachment_repository.dart` | Media CRUD |
| `lib/core/database/migrations/010_media_attachments.dart` | Schema: `message_id` FK |

- `deleteAttachmentsForMessage(messageId)` — bulk delete by message ID.
- Media files stored locally via `mediaFileManager`.
- When a message with media is deleted, both the DB attachment records and
  local files need cleanup (per the failed-media delete pattern).

### 3.9 Message Change Stream

| File | Key Lines |
|------|-----------|
| `lib/features/conversation/domain/repositories/message_repository_impl.dart` | `messageChanges` stream |

- `saveMessage()` and `deleteMessage()` emit to `_messageChangeController`.
- UI listens to this stream for reactive updates.
- Deleting via `deleteMessage()` would trigger UI refresh automatically.

### 3.10 Existing Tests

| File | Coverage |
|------|----------|
| `test/core/database/helpers/messages_db_helpers_*` | DB insert/query; delete helpers |
| `test/features/conversation/application/send_reaction_use_case_test.dart` | Reaction send pattern |

- No tests for single-message deletion UI.
- No tests for P2P deletion signals.
- DB `dbDeleteMessage()` is tested at the helper level.

---

## 4. Scope Clarification

| Area | Status | Notes |
|------|--------|-------|
| "Delete" option in long-press context menu | **In scope** | Available on all messages (sent and received) |
| "Delete for Me" — local-only deletion | **In scope** | Removes message from user's DB |
| "Delete for Everyone" — local + remote deletion | **In scope** | Sends P2P deletion signal to recipient |
| Confirmation dialog with 3 options | **In scope** | Delete for Me / Delete for Everyone / Cancel |
| "Delete for Everyone" only available on sent messages | **In scope** | User cannot delete others' messages remotely |
| Media cleanup on message deletion | **In scope** | Delete attachment records + local files |
| Incoming deletion handler (receiver side) | **In scope** | Processes P2P deletion signal |
| Deleted message placeholder ("This message was deleted") | **In scope** | Recipient sees placeholder instead of content |
| Works in Orbit 1:1 conversations (LetterCard) | **In scope** | Both surfaces |
| Works in Feed/Stack cards (MessageBubble) | **In scope** | Both surfaces |
| Delete in group conversations | **Out of scope** | 1:1 only for now |
| Time limit on "Delete for Everyone" | **Out of scope** | No time restriction requested |
| Batch/multi-select message deletion | **Out of scope** | Single message at a time |
| Undo delete | **Out of scope** | Hard delete is final |
| Quoted message reference update on delete | **In scope** | If a deleted message was quoted, the quote should show as unavailable |

---

## 5. Test Cases

### Group A: Context Menu — Delete Option Visibility

**TC-33-A01** — "Delete" option appears on long-press of a sent message
Given user-A is in a 1:1 conversation and long-presses on a message they sent,
when the context menu appears,
then a "Delete" option is visible among the menu items.

**TC-33-A02** — "Delete" option appears on long-press of a received message
Given user-A long-presses on a message received from user-B,
when the context menu appears,
then a "Delete" option is visible (for "Delete for Me" — local removal).

**TC-33-A03** — Tapping "Delete" shows the confirmation dialog
Given user-A long-presses a sent message and taps "Delete",
when the dialog appears,
then it shows the text "Who would you like to delete this message for?" with
three buttons: "Delete for Me", "Delete for Everyone", and "Cancel".

**TC-33-A04** — "Delete for Everyone" only shown for sent messages
Given user-A long-presses a **received** message and taps "Delete",
when the confirmation dialog appears,
then only "Delete for Me" and "Cancel" are shown — "Delete for Everyone" is
NOT available (user cannot delete others' messages remotely).

**TC-33-A05** — "Delete" option appears in Orbit 1:1 conversation (LetterCard)
Given user-A is in an Orbit 1:1 conversation,
when user-A long-presses any message,
then the "Delete" option is available in the context menu.

**TC-33-A06** — "Delete" option appears in Feed/Stack card (MessageBubble)
Given user-A has an open feed card with messages,
when user-A long-presses any message,
then the "Delete" option is available in the context menu.

### Group B: Delete for Me (Local Deletion)

**TC-33-B01** — "Delete for Me" removes the message from the sender's conversation
Given user-A long-presses a sent message "Hello Bob" and taps Delete → Delete for Me,
when the deletion completes,
then "Hello Bob" is no longer visible in user-A's conversation view.

**TC-33-B02** — "Delete for Me" on a received message removes it locally
Given user-A long-presses a received message from user-B and taps Delete → Delete for Me,
when the deletion completes,
then the message is no longer visible in user-A's conversation view.

**TC-33-B03** — "Delete for Me" does NOT affect the recipient's view
Given user-A sends "Hello Bob" and then deletes it via "Delete for Me",
when user-B checks their conversation,
then user-B still sees "Hello Bob" — no change on their side.

**TC-33-B04** — "Delete for Me" removes the message from the local database
Given user-A deletes a message via "Delete for Me",
when the messages table is queried for the deleted message ID,
then no row is returned (hard delete).

**TC-33-B05** — "Delete for Me" cleans up media attachments
Given user-A deletes a message that has an attached image via "Delete for Me",
when the deletion completes,
then the media attachment DB record is deleted AND the local image file is
removed from disk.

### Group C: Delete for Everyone (Remote Deletion)

**TC-33-C01** — "Delete for Everyone" removes the message from sender's conversation
Given user-A sends "Secret message" and taps Delete → Delete for Everyone,
when the deletion completes,
then "Secret message" is no longer visible in user-A's conversation.

**TC-33-C02** — "Delete for Everyone" removes the message from recipient's conversation
Given user-A sends "Secret message" to user-B and deletes it via "Delete for Everyone",
when user-B's app receives the deletion signal,
then "Secret message" is removed from user-B's conversation and replaced
with a placeholder (e.g., "This message was deleted").

**TC-33-C03** — Deletion signal is sent via P2P to the recipient
Given user-A deletes a message via "Delete for Everyone",
when the deletion is processed,
then a P2P message is sent to user-B containing the message ID to delete,
identifiable as a deletion signal (not a regular chat message).

**TC-33-C04** — "Delete for Everyone" works when recipient is offline
Given user-B is offline when user-A deletes a message via "Delete for Everyone",
when user-B comes online later,
then the deletion signal is delivered (via inbox fallback) and the message is
removed from user-B's conversation.

**TC-33-C05** — "Delete for Everyone" deletes media on recipient's side
Given user-A sends an image to user-B and then deletes it via "Delete for Everyone",
when user-B receives the deletion signal,
then the image message is removed from user-B's conversation, the media
attachment record is deleted, and the downloaded image file is removed from
user-B's device.

**TC-33-C06** — Recipient sees "This message was deleted" placeholder
Given user-A deletes a text message via "Delete for Everyone",
when user-B's conversation updates,
then in place of the original message, user-B sees a placeholder indicating the
message was deleted (e.g., italicized "This message was deleted" or similar).

### Group D: Cancel

**TC-33-D01** — "Cancel" dismisses the dialog with no action
Given user-A taps Delete and the confirmation dialog is showing,
when user-A taps "Cancel",
then the dialog closes and the message remains unchanged in the conversation.

**TC-33-D02** — Tapping outside the dialog dismisses it (no action)
Given the delete confirmation dialog is showing,
when user-A taps outside the dialog (on the dimmed background),
then the dialog closes with no deletion performed.

### Group E: Quoted Message Handling

**TC-33-E01** — Deleting a message that is quoted by another message
Given user-A sent "Original message", user-B replied quoting it, and user-A
deletes "Original message" via "Delete for Me",
when user-A views the conversation,
then user-B's reply shows the quote bar as unavailable/empty (not the deleted
text).

**TC-33-E02** — "Delete for Everyone" on a quoted message updates recipient's quotes
Given user-A sent "Original message", user-B quoted it in a reply, and user-A
deletes "Original message" via "Delete for Everyone",
when user-B's conversation updates,
then user-B's reply shows the quote as unavailable (the referenced message no
longer exists).

### Group F: Edge Cases

**TC-33-F01** — Delete a "failed" status message
Given user-A has a message with status "failed" (send failed),
when user-A long-presses → Delete → Delete for Me,
then the failed message is removed locally. "Delete for Everyone" is NOT
available (message was never delivered).

**TC-33-F02** — Delete a "sending" status message
Given user-A has a message with status "sending" (still in transit),
when user-A long-presses → Delete,
then appropriate behavior occurs (either block deletion until sent, or allow
local delete with note that recipient may still receive it).

**TC-33-F03** — Delete the only message in a conversation
Given user-A has a conversation with user-B containing exactly 1 message,
when user-A deletes that message via "Delete for Me",
then the conversation view shows empty state, and the feed card updates to
reflect no messages.

**TC-33-F04** — Delete a message with both text and media
Given user-A sent a message with text "Check this out" and an attached photo,
when user-A deletes it via "Delete for Everyone",
then both the text and media are deleted on both devices. The recipient sees
the "deleted" placeholder.

**TC-33-F05** — Receiving a deletion signal for a message that doesn't exist locally
Given user-B receives a "Delete for Everyone" signal for message ID "xyz",
but user-B's app does not have a message with ID "xyz" (already deleted or
never received),
when the deletion signal is processed,
then no error occurs — the signal is silently ignored.

**TC-33-F06** — Receiving a deletion signal from someone who didn't send the message
Given user-C sends a deletion signal for a message that user-A sent to user-B
(spoofed deletion),
when user-B processes the signal,
then the deletion is rejected — only the original sender can delete their own
messages via "Delete for Everyone".

**TC-33-F07** — App restart after "Delete for Everyone" while offline
Given user-A deletes a message via "Delete for Everyone" while offline,
then the deletion is saved locally (message removed from user-A's DB), and
the deletion P2P signal is queued for delivery when connectivity returns.

### Group G: UI Behavior

**TC-33-G01** — Message disappears smoothly from conversation after deletion
Given user-A deletes a message,
when the deletion completes,
then the message row is removed from the conversation list and remaining
messages reflow without visual glitch.

**TC-33-G02** — Deletion dialog matches the app's design language
Given the deletion confirmation dialog is showing,
when the user inspects it visually,
then it matches the glassmorphic/dark design language of the app with three
clearly labeled buttons (as in the WhatsApp reference: rounded dark buttons
with colored text).

**TC-33-G03** — Feed card updates after message deletion
Given user-A has a feed card showing the latest message "Hello Bob",
when user-A deletes "Hello Bob" via "Delete for Me",
then the feed card updates to show the next-most-recent message (or empty state
if no messages remain).

### Group H: Regression

**TC-33-H01** — Emoji reactions still work from long-press
Given user-A long-presses a message,
when the context menu appears with the emoji bar and options (Reply, Copy,
Delete, etc.),
then selecting an emoji still sends a reaction correctly.

**TC-33-H02** — Reply and Copy still work from context menu
Given user-A long-presses a message,
when the context menu appears,
then Reply and Copy (per Report 26) still function correctly.

**TC-33-H03** — Contact-level delete still works
Given user-A deletes an entire contact via the Orbit contact menu,
when the deletion processes,
then all messages for that contact are deleted (existing behavior unchanged).

**TC-33-H04** — Failed media delete still works
Given user-A has a failed media upload message,
when user-A taps the delete option on the failed message,
then the cleanup cascade works as before (media files, attachment records,
message record all deleted).

**TC-33-H05** — Message sending is not affected
Given user-A types and sends a new message,
when the message is sent,
then it is delivered normally with no interference from the deletion feature.

### Group I: Backward Compatibility

**TC-33-I01** — Old app version receives deletion signal
Given user-B is running an older app version that does not support "Delete for
Everyone",
when user-A sends a deletion signal,
then user-B's app either: (a) ignores the unknown message type silently, or
(b) logs it as unrecognized — but does **not crash**.

**TC-33-I02** — Old app version sender, new app version receiver
Given user-A is running an older version (no delete feature),
when user-B (new version) opens a conversation,
then all messages display normally with no delete-related UI issues.
