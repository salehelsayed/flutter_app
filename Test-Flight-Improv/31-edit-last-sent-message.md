# 31 - Edit Last Sent Message

**New Feature**

---

## 1. Problem Statement

Once a user sends a message, there is no way to edit its text. If the user
makes a typo or wants to correct their message, they must send a new follow-up
message. There is no edit capability anywhere in the messaging flow.

**Current behavior:**

- User sends a message → message is persisted and sent via P2P.
- Message text is immutable after sending.
- No "Edit" option exists in the long-press interaction (currently only shows
  emoji reaction bar; Report 26 proposes adding Reply/Copy).
- No `action` field exists in `MessagePayload` to distinguish a new message
  from an edit.
- `handleIncomingChatMessage` rejects messages with duplicate IDs as
  `HandleChatMessageResult.duplicate` (handle_incoming_chat_message_use_case.dart:150–158).

**What is needed:**

- An "Edit" option in the long-press context menu (per Report 26) for **the
  user's last sent message only**.
- When the user taps "Edit", the compose area pre-fills with the message text
  for editing.
- On confirm, the updated text is saved locally and sent to the recipient via
  P2P so both sides see the updated message.
- The edited message should show an "(edited)" indicator.

**Constraint:** Only the **last sent message** in a conversation can be edited.
Not any arbitrary past message. This limits complexity and matches user
expectations from apps like Signal.

**Who is affected:** All users sending text messages in 1:1 conversations.

---

## 2. Impact Analysis

| Dimension | Assessment |
|-----------|-----------|
| Severity | Low — messages can be sent but not corrected; cosmetic/UX gap |
| Frequency | Every time a user notices a typo or error after sending |
| User consequence | Must send correction as a new message; no inline fix |
| Workaround | Send a follow-up message with corrected text |
| Platform scope | iOS and Android (Flutter) |

---

## 3. Current State

### 3.1 Message Model

| File | Key Lines |
|------|-----------|
| `lib/features/conversation/domain/models/conversation_message.dart` | Lines 7–48 |

**Fields relevant to edit:**
- `id` (String) — UUID v4, primary key (line 9)
- `text` (String) — message content (line 18)
- `isIncoming` (bool) — `false` for sent messages (line 28)
- `timestamp` (String) — creation time (line 21)
- `status` (String) — `'sending'`, `'sent'`, `'delivered'`, `'failed'` (line 25)
- `wireEnvelope` (String?) — serialized payload for retry, cleared after delivery (line 44)

**Missing fields:** No `editedAt`, `originalText`, or `isEdited` field exists.

**`copyWith()`** (lines 106–138): Supports creating modified copies of
messages. Can be used to update `text` while preserving other fields.

**`toMap()` / `fromMap()`** (lines 85–82): Serialization for DB. Would need
extension for new edit-related columns.

### 3.2 Database Schema

| File | Purpose | Key Lines |
|------|---------|-----------|
| `lib/core/database/migrations/002_messages_table.dart` | Messages table | Lines 6–16 |

- `text TEXT NOT NULL` — current constraint.
- `id TEXT PRIMARY KEY` — enables upsert via `ConflictAlgorithm.replace`.
- Extensions added via migrations 006, 009, 012, 014 (read_at, quoted_message_id,
  transport, wire_envelope) — establishes pattern for adding columns.

**No `edited_at` or related column exists.**

### 3.3 Message Persistence (Upsert)

| File | Key Lines |
|------|-----------|
| `lib/core/database/helpers/messages_db_helpers.dart` | Lines 6–35 |

- `dbInsertMessage()` uses `ConflictAlgorithm.replace` — same ID replaces
  existing row. This is already the infrastructure needed for edit persistence.
- Test confirms: inserting with same ID and different text replaces the row
  (messages_db_helpers_test.dart ~line 106–113).

### 3.4 Message Payload (Wire Format)

| File | Key Lines |
|------|-----------|
| `lib/features/conversation/domain/models/message_payload.dart` | Lines 15–32 |

- **Fields:** `id`, `text`, `senderPeerId`, `senderUsername`, `timestamp`,
  `quotedMessageId`, `media`.
- **No `action` field** — all messages are implicitly "new".
- **Wire format:** `{ "type": "chat_message", "version": "1", "payload": {...} }`.
- Supports both v1 (plaintext) and v2 (encrypted) envelopes.

**Pattern reference:** `ReactionPayload` has an `action` field (`'add'` /
`'remove'`) showing the established pattern for polymorphic message handling.

### 3.5 Send Message Use Case

| File | Key Lines |
|------|-----------|
| `lib/features/conversation/application/send_chat_message_use_case.dart` | Lines 58–73, 142–152 |

- `sendChatMessage()` accepts `messageId` parameter (line 67) — can be
  provided for retries, could also be provided for edits.
- Builds `MessagePayload` with fields from parameters (lines 142–152).
- Persists via `messageRepo.saveMessage()` (line 422) — upsert.
- Sends via P2P (race across transports).

### 3.6 Incoming Message Handling

| File | Key Lines |
|------|-----------|
| `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart` | Lines 150–159 |

- **Duplicate check** (line 151): `messageRepo.messageExists(payload.id)`.
- If `exists == true` → returns `HandleChatMessageResult.duplicate` and
  **discards the message** (line 158).
- **This is the blocker for edit:** an edit message with the same ID as the
  original would be rejected as a duplicate. The handler needs to distinguish
  "duplicate" from "edit update".

### 3.7 Last Message Identification

- `messageRepo.getLatestMessageForContact(contactPeerId)` (message_repository.dart:18)
  returns the most recent message in a conversation.
- Query: `ORDER BY timestamp DESC LIMIT 1` — gets the latest regardless of
  direction.
- For "last **sent** message": need `is_incoming = 0` filter added to query.
- In the conversation UI, messages are loaded chronologically (ASC) —
  `messages[messages.length - 1]` is the newest message.

### 3.8 Message Change Stream

| File | Key Lines |
|------|-----------|
| `lib/features/conversation/domain/repositories/message_repository_impl.dart` | Lines 95–124 |

- `saveMessage()` emits to `_messageChangeController` (broadcast stream).
- UI subscribes to this stream and updates reactively.
- Editing a message via `saveMessage()` with same ID would automatically
  update the UI.

### 3.9 Long-Press / Context Menu

- `LetterCard.onLongPress` (letter_card.dart:30, 67): GestureDetector fires
  callback.
- `MessageBubble.onLongPress` (message_bubble.dart:32, 64–65): Same pattern.
- Currently wired to `_showReactionBar()` (conversation_screen.dart:549–580):
  shows only emoji reaction bar.
- Report 26 proposes adding Reply/Copy to this interaction. Edit would be a
  third option in the same context menu.

---

## 4. Scope Clarification

| Area | Status | Notes |
|------|--------|-------|
| "Edit" option in long-press context menu | **In scope** | Only shown on the user's last sent message |
| Edit pre-fills compose area with original text | **In scope** | User modifies text in compose input |
| Updated text saved locally (upsert) | **In scope** | Same message ID, new text |
| Updated text sent to recipient via P2P | **In scope** | Recipient sees edited message |
| "(edited)" indicator on edited messages | **In scope** | Both sender and receiver see it |
| DB migration for `edited_at` column | **In scope** | Tracks when message was edited |
| `action` field in MessagePayload | **In scope** | Distinguishes "send" from "edit" |
| Incoming edit handler (receiver side) | **In scope** | Receiver updates local message on edit receipt |
| Edit works in Orbit 1:1 conversations | **In scope** | LetterCard surface |
| Edit works in Feed/Stack card messages | **In scope** | MessageBubble surface |
| Edit any past message (not just last) | **Out of scope** | Only last sent message |
| Edit media attachments | **Out of scope** | Text-only edit |
| Edit history / view original text | **Out of scope** | Not requested |
| Edit in group conversations | **Out of scope** | 1:1 only (unless group uses same message model) |
| Time limit on editing | **Out of scope** | No time restriction requested |
| Undo edit | **Out of scope** | Not requested |

---

## 5. Test Cases

### Group A: Edit Menu Visibility

**TC-31-A01** — "Edit" option appears on long-press of user's last sent message
Given user-A is in a 1:1 conversation with user-B and user-A's last sent
message is "Hello Bob",
when user-A long-presses on "Hello Bob",
then the context menu includes an "Edit" option alongside Reply and Copy.

**TC-31-A02** — "Edit" option does NOT appear on a received message
Given user-A long-presses on a message received from user-B,
when the context menu appears,
then the "Edit" option is not shown (Reply and Copy still appear per Report 26).

**TC-31-A03** — "Edit" option does NOT appear on a non-last sent message
Given user-A sent 3 messages: "msg1", "msg2", "msg3" (msg3 is the latest),
when user-A long-presses on "msg1" or "msg2",
then the "Edit" option is not shown (only the last sent message is editable).

**TC-31-A04** — "Edit" option appears on last sent message even if last overall message is received
Given user-A sent "Hello" and then user-B replied "Hi back",
when user-A long-presses on "Hello" (the last sent message by user-A, even
though "Hi back" is the newest message overall),
then the "Edit" option appears because "Hello" is user-A's last sent message.

**TC-31-A05** — "Edit" option does NOT appear on a media-only message (no text)
Given user-A's last sent message is an image with no text caption,
when user-A long-presses on the image message,
then the "Edit" option is not shown (there is no text to edit).

**TC-31-A06** — "Edit" option appears on a message with both text and media
Given user-A's last sent message has text "Check this out" and an attached image,
when user-A long-presses on the message,
then the "Edit" option is shown (the text portion is editable).

### Group B: Edit Flow (Sender Side)

**TC-31-B01** — Tapping "Edit" pre-fills the compose area with the message text
Given user-A long-presses their last sent message "Hello Bob" and taps "Edit",
when the context menu dismisses,
then the compose input field is pre-filled with "Hello Bob", the cursor is at
the end, and the keyboard opens.

**TC-31-B02** — User can modify the text and send the edit
Given the compose area is pre-filled with "Hello Bob" in edit mode,
when user-A changes the text to "Hello Bob!" and taps send,
then the message in the conversation updates to show "Hello Bob!" with an
"(edited)" indicator.

**TC-31-B03** — Canceling the edit clears the compose area
Given the compose area is in edit mode with pre-filled text,
when user-A taps a cancel/dismiss control (e.g., X button on the edit bar),
then the compose area returns to normal (empty) mode, and the original message
is unchanged.

**TC-31-B04** — Sending an edit with identical text (no actual change)
Given the compose area is in edit mode with "Hello Bob",
when user-A taps send without changing the text,
then no edit is sent (or the edit is a no-op), and no "(edited)" indicator
is added.

**TC-31-B05** — Edit preserves the message's original timestamp and position
Given user-A edits their last sent message from "Hello" to "Hello!",
when the edit is saved,
then the message remains in its original position in the conversation (same
timestamp), not moved to the bottom as a new message.

**TC-31-B06** — Edit preserves existing reactions on the message
Given user-A's last sent message has a thumbs-up reaction from user-B,
when user-A edits the message text,
then the thumbs-up reaction is still displayed on the edited message.

### Group C: Edit Flow (Receiver Side)

**TC-31-C01** — Receiver sees the updated message text
Given user-A edits a message from "Hello" to "Hello!",
when user-B receives the edit update,
then user-B's conversation shows "Hello!" instead of "Hello" for that message.

**TC-31-C02** — Receiver sees "(edited)" indicator on the updated message
Given user-B receives an edit update for a message,
when the message updates in the conversation,
then user-B sees an "(edited)" label or indicator on the message.

**TC-31-C03** — Receiver's message position is unchanged after edit
Given user-B has a conversation with 10 messages and the 8th message is edited,
when the edit arrives,
then message #8 updates in place — it does not jump to the bottom of the
conversation.

**TC-31-C04** — Receiver who hasn't received the original message yet
Given user-B is offline when user-A sends "Hello", then user-A edits it to
"Hello!" before user-B comes online,
when user-B comes online and receives messages,
then user-B sees "Hello!" with "(edited)" indicator (not the original "Hello").

### Group D: Last Message Determination

**TC-31-D01** — "Last sent message" is determined by timestamp, not display order
Given user-A sent messages at 14:00, 14:05, and 14:10,
when user-A long-presses each message,
then only the 14:10 message shows the "Edit" option.

**TC-31-D02** — New message sent after edit updates the editable message
Given user-A edited their last message, then sends a new message "Goodbye",
when user-A long-presses the previously edited message,
then "Edit" does NOT appear (the newly sent "Goodbye" is now the last sent
message). "Edit" only appears on "Goodbye".

**TC-31-D03** — Failed message is still the last sent message
Given user-A's last sent message has status "failed" (send failed),
when user-A long-presses on it,
then "Edit" appears (failed messages are still editable since they are the
user's last sent message).

### Group E: P2P and Persistence

**TC-31-E01** — Edit is sent via P2P to the recipient
Given user-A edits a message,
when the edit is processed,
then a P2P message is sent to user-B containing the updated text and the same
message ID, distinguishable as an edit (not a new message).

**TC-31-E02** — Edit is persisted locally with same ID (upsert)
Given user-A edits message ID "abc-123" from "Hello" to "Hello!",
when the edit is saved,
then the `messages` table still has exactly one row with ID "abc-123" and
text "Hello!" (not two rows).

**TC-31-E03** — Edited message has `edited_at` timestamp set
Given user-A edits a message,
when the edit is saved locally,
then the message row has an `edited_at` value with the edit timestamp.

**TC-31-E04** — Edit works offline (local save, P2P queued)
Given user-A is offline,
when user-A edits their last sent message,
then the edit is saved locally immediately (text updates in UI), and the P2P
edit message is queued/stored in inbox for delivery when connectivity returns.

### Group F: Edge Cases

**TC-31-F01** — Edit a message in Orbit 1:1 conversation (LetterCard)
Given user-A is in an Orbit 1:1 conversation,
when user-A long-presses and edits their last sent message,
then the edit flow works the same as in the feed conversation context.

**TC-31-F02** — Edit a message in a Feed/Stack card (MessageBubble)
Given user-A has an open feed card with messages,
when user-A long-presses and edits their last sent message,
then the edit flow works the same as in the Orbit conversation context.

**TC-31-F03** — Edit a message that was a quote-reply
Given user-A's last sent message quotes user-B's message,
when user-A edits the text of their quote-reply,
then the quote reference is preserved (the reply-to link remains intact), and
only the response text is modified.

**TC-31-F04** — Concurrent edits (user-A edits while user-B reacts)
Given user-A edits message "Hello" to "Hello!" at the same moment user-B
sends a reaction on the original "Hello",
when both updates are processed,
then the final state shows the edited text "Hello!" with user-B's reaction
intact (no data loss from either operation).

**TC-31-F05** — Backward compatibility with older app versions
Given user-B is running an older version of the app that does not support edits,
when user-A sends an edit,
then user-B's app either: (a) ignores the edit (message stays as original), or
(b) treats it as a duplicate and discards it — but does **not crash**.

### Group G: Regression

**TC-31-G01** — Sending a new message still works normally
Given user-A is in a conversation,
when user-A types and sends a new message (not editing),
then the message is sent as before with no edit-related fields or indicators.

**TC-31-G02** — Reply/Copy from context menu still work
Given user-A long-presses on a message,
when the context menu appears with Reply, Copy, and (conditionally) Edit,
then Reply and Copy still function correctly per Report 26.

**TC-31-G03** — Emoji reactions still work from long-press
Given user-A long-presses on a message,
when the emoji reaction bar appears above the message,
then reactions still work correctly (selecting an emoji sends a reaction).

**TC-31-G04** — Duplicate message detection still works for non-edit messages
Given user-B receives a genuine duplicate of a message they already have,
when `handleIncomingChatMessage` processes it,
then the duplicate is still correctly rejected (not treated as an edit).
