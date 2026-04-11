# C4 Model -- Level 2: Container Diagram

## Feature: MessageContextOverlay

**Scope:** Long-press interaction on LetterCard in ConversationScreen, showing a
glassmorphic overlay with reaction bar, selected message preview, and context
menu (Reply, Edit, Copy, Delete).

**Diagram type:** C4 Container (Level 2) -- shows the major runtime containers
and their communication flows, scoped to the MessageContextOverlay feature only.

---

## System Boundary: mknoon Flutter App

```
+==============================================================================+
|                          mknoon Flutter App                                  |
|                                                                              |
|  +-----------------------------------------------------------------------+   |
|  |                   1. PRESENTATION LAYER (Container)                   |   |
|  |                                                                       |   |
|  |  +---------------------+    +-------------------+                     |   |
|  |  | ConversationWired   |    | ConversationScreen |                    |   |
|  |  | (StatefulWidget)    |--->| (StatelessWidget)   |                   |   |
|  |  |                     |    |                     |                   |   |
|  |  | - _messages list    |    | - ListView.builder  |                   |   |
|  |  | - _reactions map    |    |   (reverse: true)   |                   |   |
|  |  | - stream subs       |    | - onLongPress per   |                   |   |
|  |  | - _onReaction       |    |   LetterCard        |                   |   |
|  |  |   Selected()        |    |                     |                   |   |
|  |  | - _onQuoteReply()   |    +----------+----------+                   |   |
|  |  | - _onEditMessage()  |               |                              |   |
|  |  | - _onDeleteMessage()|               | builds                       |   |
|  |  | - _onCopyMessage()  |               v                              |   |
|  |  +---------------------+    +-------------------+                     |   |
|  |                             | LetterCard         |                    |   |
|  |                             | (StatelessWidget)  |                    |   |
|  |                             |                    |                    |   |
|  |                             | - senderName       |                    |   |
|  |                             | - text, time       |                    |   |
|  |                             | - isIncoming       |                    |   |
|  |                             | - onLongPress -----+------+            |   |
|  |                             | - left/right accent|      |            |   |
|  |                             | - glassmorphic bg  |      |            |   |
|  |                             +--------------------+      |            |   |
|  |                                                         |            |   |
|  |                   showDialog(useSafeArea: false,         |            |   |
|  |                     barrierColor: transparent)           |            |   |
|  |                                                         v            |   |
|  |  +--------------------------------------------------------------+    |   |
|  |  | MessageContextOverlay (StatelessWidget)                      |    |   |
|  |  | Shown as full-screen dialog overlay                          |    |   |
|  |  |                                                              |    |   |
|  |  |  +------------------+  +--------------+  +----------------+  |    |   |
|  |  |  | ReactionBar      |  | Selected Msg |  | _ContextMenu   |  |    |   |
|  |  |  | (StatefulWidget) |  | Preview      |  |   Card         |  |    |   |
|  |  |  |                  |  | (FittedBox   |  |                |  |    |   |
|  |  |  | - 6 preset emoji |  |  scaled-down |  | - Reply        |  |    |   |
|  |  |  |   buttons        |  |  LetterCard  |  | - Edit (cond.) |  |    |   |
|  |  |  | - "+" full picker|  |  via Ignore  |  | - Copy (cond.) |  |    |   |
|  |  |  | - scale anim     |  |  Pointer)    |  | - Delete(cond.)|  |    |   |
|  |  |  |   0.8->1.0 200ms |  |              |  |                |  |    |   |
|  |  |  | - currentEmoji   |  +--------------+  +---+----+---+---+  |    |   |
|  |  |  |   highlight      |                        |    |   |      |    |   |
|  |  |  +--------+---------+                        |    |   |      |    |   |
|  |  |           |                                  |    |   |      |    |   |
|  |  |  Backdrop: BackdropFilter blur(18,18)        |    |   |      |    |   |
|  |  |  + semi-transparent scrim rgba(6,8,12,0.24)  |    |   |      |    |   |
|  |  |  Smart viewport clamping: safe-area aware     |    |   |      |    |   |
|  |  +------+---------+----------------------------+----+----+---+--+    |   |
|  |         |         |                            |    |   |    |       |   |
|  |         |         |                            |    |   |    |       |   |
|  |  +------v---------v----+                       |    |   |    |       |   |
|  |  | ComposeArea          |<---------------------+    |   |    |       |   |
|  |  | (StatefulWidget)     | Reply: enters quote mode  |   |    |       |   |
|  |  |                      | Edit: pre-fills text       |   |    |       |   |
|  |  | - text input         |                            |   |    |       |   |
|  |  | - quote preview bar  |                            |   |    |       |   |
|  |  | - edit mode banner   |                            |   |    |       |   |
|  |  +----------------------+                            |   |    |       |   |
|  +-----------------------------------------------------------------------+   |
|         | emoji selected       | reply tap        | copy | delete        |   |
|         v                      v                  v tap  v tap           |   |
|  +-----------------------------------------------------------------------+   |
|  |                   2. APPLICATION LAYER (Container)                    |   |
|  |                                                                       |   |
|  |  Use Cases (top-level functions):                                     |   |
|  |  +----------------------+  +-------------------------+                |   |
|  |  | sendReaction()       |  | sendChatMessage()       |               |   |
|  |  | - encrypt via Bridge |  | - with quotedMessageId  |               |   |
|  |  | - send via P2P       |  |   for Reply action      |               |   |
|  |  | - persist locally    |  | - encrypt via Bridge    |               |   |
|  |  +----------------------+  | - send via P2P          |               |   |
|  |  +----------------------+  +-------------------------+               |   |
|  |  | removeReaction()     |  +-------------------------+               |   |
|  |  | - send removal       |  | editChatMessage()       |               |   |
|  |  | - delete from DB     |  | - last sent msg only    |               |   |
|  |  +----------------------+  | - sends edit payload    |               |   |
|  |  +----------------------+  +-------------------------+               |   |
|  |  | loadReactions()      |  +-------------------------+               |   |
|  |  | - batch load by IDs  |  | deleteMessageForMe()    |               |   |
|  |  | - returns Map<id,    |  | - hard-delete from DB   |               |   |
|  |  |   List<Reaction>>    |  | - cleanup media files   |               |   |
|  |  +----------------------+  +-------------------------+               |   |
|  |                            +-------------------------+               |   |
|  |                            | deleteMessageForEveryone|               |   |
|  |                            | - soft-delete locally   |               |   |
|  |                            | - send deletion payload |               |   |
|  |                            |   via P2P to recipient  |               |   |
|  |                            +-------------------------+               |   |
|  |                                                                       |   |
|  |  Listeners (StreamController broadcast):                              |   |
|  |  +----------------------------+  +------------------------------+     |   |
|  |  | ReactionListener           |  | ChatMessageListener          |     |   |
|  |  | - subscribes to            |  | - subscribes to              |     |   |
|  |  |   reactionStream (from     |  |   chatStream (from           |     |   |
|  |  |   IncomingMessageRouter)   |  |   IncomingMessageRouter)     |     |   |
|  |  | - decrypts v2 envelopes    |  | - decrypts v2 envelopes     |     |   |
|  |  | - calls handleIncoming     |  | - calls handleIncoming      |     |   |
|  |  |   Reaction use case        |  |   ChatMessage use case       |     |   |
|  |  | - broadcasts via           |  | - broadcasts via             |     |   |
|  |  |   StreamController         |  |   StreamController           |     |   |
|  |  +----------------------------+  +------------------------------+     |   |
|  |  +------------------------------+                                     |   |
|  |  | MessageDeletionListener      |                                     |   |
|  |  | - subscribes to              |                                     |   |
|  |  |   deletionStream             |                                     |   |
|  |  | - soft-deletes messages      |                                     |   |
|  |  | - broadcasts change to UI    |                                     |   |
|  |  +------------------------------+                                     |   |
|  +-----------------------------------------------------------------------+   |
|         |                   |                        |                        |
|         v                   v                        v                        |
|  +-----------------------------------------------------------------------+   |
|  |                   3. DOMAIN LAYER (Container)                         |   |
|  |                                                                       |   |
|  |  Models:                                                              |   |
|  |  +---------------------------+  +---------------------------+         |   |
|  |  | ConversationMessage       |  | MessageReaction           |         |   |
|  |  | - id: String (UUID v4)    |  | - id: String (UUID v4)    |         |   |
|  |  | - contactPeerId           |  | - messageId (FK)          |         |   |
|  |  | - senderPeerId            |  | - emoji: String           |         |   |
|  |  | - text: String            |  | - senderPeerId            |         |   |
|  |  | - timestamp: ISO-8601     |  | - timestamp: ISO-8601     |         |   |
|  |  | - status: sending/sent/   |  | - createdAt: ISO-8601     |         |   |
|  |  |   delivered/failed        |  |                           |         |   |
|  |  | - isIncoming: bool        |  | UNIQUE(message_id,        |         |   |
|  |  | - editedAt: String?       |  |   sender_peer_id)         |         |   |
|  |  | - deletedAt: String?      |  |                           |         |   |
|  |  | - deletedByPeerId: String?|  | fromMap/toMap (DB)        |         |   |
|  |  | - quotedMessageId: String?|  | fromJson/toJson (wire)    |         |   |
|  |  | - media: List<Attachment> |  +---------------------------+         |   |
|  |  |                           |                                        |   |
|  |  | fromMap/toMap (DB)        |  +---------------------------+         |   |
|  |  | fromJson/toJson (wire)    |  | MessageDeletionPayload    |         |   |
|  |  +---------------------------+  | - id, originalMessageId   |         |   |
|  |                                 | - deletedByPeerId         |         |   |
|  |  Repository Interfaces:         | - timestamp               |         |   |
|  |  +---------------------------+  +---------------------------+         |   |
|  |  | MessageRepository         |  +---------------------------+         |   |
|  |  | - saveMessage()           |  | ReactionRepository        |         |   |
|  |  | - getMessage()            |  | - saveReaction() (upsert) |         |   |
|  |  | - getMessagesForContact() |  | - getReactionsForMessage()|         |   |
|  |  | - updateMessageStatus()   |  | - getReactionsForMessages |         |   |
|  |  | - deleteMessage()         |  |   () (batch)              |         |   |
|  |  | - markConversationAsRead()|  | - removeReaction()        |         |   |
|  |  +---------------------------+  | - deleteReactionsFor      |         |   |
|  |                                 |   Message()               |         |   |
|  |                                 +---------------------------+         |   |
|  +-----------------------------------------------------------------------+   |
|         |                   |                        |                        |
|         v                   v                        v                        |
|  +-----------------------------------------------------------------------+   |
|  |                   4. INFRASTRUCTURE LAYER (Container)                  |   |
|  |                                                                       |   |
|  |  +-----------------------------+  +-----------------------------+     |   |
|  |  | SQLCipher Database          |  | P2PService                  |     |   |
|  |  | (sqflite_sqlcipher)         |  | (libp2p networking)         |     |   |
|  |  |                             |  |                             |     |   |
|  |  | Tables:                     |  | - sendMessage(peerId, json) |     |   |
|  |  | - messages (v2+)            |  | - storeInInbox() fallback   |     |   |
|  |  | - message_reactions         |  | - messageStream for         |     |   |
|  |  |                             |  |   incoming messages         |     |   |
|  |  | Encrypted at rest:          |  |                             |     |   |
|  |  | - 256-bit random key        |  | Wire formats:               |     |   |
|  |  | - key in SecureKeyStore     |  | - v1: {type, version,       |     |   |
|  |  +-----------------------------+  |       payload}              |     |   |
|  |                                   | - v2: {version: "2",        |     |   |
|  |  +-----------------------------+  |       encrypted: {kem,      |     |   |
|  |  | Bridge (GoBridgeClient)     |  |       ciphertext, nonce}}   |     |   |
|  |  | (MethodChannel -> Go native)|  +-----------------------------+     |   |
|  |  |                             |                                      |   |
|  |  | Commands used:              |  +-----------------------------+     |   |
|  |  | - message.encrypt           |  | SecureKeyStore              |     |   |
|  |  | - message.decrypt           |  | (iOS Keychain / Android     |     |   |
|  |  | - payload.sign              |  |  EncryptedSharedPrefs)      |     |   |
|  |  |                             |  |                             |     |   |
|  |  | ML-KEM-768 + AES-256-GCM   |  | Stores:                     |     |   |
|  |  | post-quantum encryption     |  | - identity_private_key      |     |   |
|  |  +-----------------------------+  | - identity_ml_kem_secret_key|     |   |
|  |                                   | - db_encryption_key         |     |   |
|  |  +-----------------------------+  +-----------------------------+     |   |
|  |  | Flutter Clipboard           |                                      |   |
|  |  | Clipboard.setData()         |                                      |   |
|  |  | - Used by Copy action       |                                      |   |
|  |  +-----------------------------+                                      |   |
|  +-----------------------------------------------------------------------+   |
+==============================================================================+
```

---

## Interaction Flows

### Flow 1: Long-Press Triggers Overlay

```
User                LetterCard          ConversationScreen       ConversationWired
 |                      |                       |                       |
 |--long-press--------->|                       |                       |
 |                      |--onLongPress--------->|                       |
 |                      |                       |                       |
 |                      |           _showMessageContextOverlay()        |
 |                      |           Capture anchorRect via RenderBox    |
 |                      |           Determine showEditAction,          |
 |                      |             showCopyAction, showDeleteAction  |
 |                      |                       |                       |
 |                      |           showDialog(                        |
 |                      |             useSafeArea: false,               |
 |                      |             barrierColor: transparent,        |
 |                      |             MessageContextOverlay(            |
 |                      |               anchorRect,                     |
 |                      |               selectedMessage: LetterCard,    |
 |                      |               currentEmoji,                   |
 |                      |               onReactionSelected,             |
 |                      |               onReplyTap,                     |
 |                      |               onEditTap,                      |
 |                      |               onCopyTap,                      |
 |                      |               onDeleteTap))                   |
 |                      |                       |                       |
 |<--- overlay visible (blur + reaction bar + preview + context menu)   |
```

### Flow 2: Reaction Selected

```
User            MessageContextOverlay    ConversationWired    sendReaction()    Bridge         P2PService    ReactionRepo
 |                      |                       |                  |              |                |              |
 |--tap emoji---------->|                       |                  |              |                |              |
 |                      |--Navigator.pop()----->|                  |              |                |              |
 |                      |  returns emoji        |                  |              |                |              |
 |                      |                       |--sendReaction()--|              |                |              |
 |                      |                       |                  |              |                |              |
 |                      |                       |                  |--encrypt---->|                |              |
 |                      |                       |                  |  (ML-KEM-768 |                |              |
 |                      |                       |                  |   + AES-256) |                |              |
 |                      |                       |                  |<--kem,cipher-|                |              |
 |                      |                       |                  |   nonce------|                |              |
 |                      |                       |                  |              |                |              |
 |                      |                       |                  |--sendMessage(v2 envelope)---->|              |
 |                      |                       |                  |  (fallback: storeInInbox)     |              |
 |                      |                       |                  |              |                |              |
 |                      |                       |                  |--saveReaction()---------------------------->|
 |                      |                       |                  |              |                |              |
 |                      |                       |<--success--------|              |                |              |
 |                      |                       |  + MessageReaction              |                |              |
 |                      |                       |                  |              |                |              |
 |                      |                       | update _reactions               |                |              |
 |                      |                       | map -> setState()               |                |              |
```

### Flow 3: Reply Tapped

```
User            MessageContextOverlay    ConversationWired    ComposeArea       sendChatMessage()
 |                      |                       |                  |                   |
 |--tap "Reply"-------->|                       |                  |                   |
 |                      |--Navigator.pop()----->|                  |                   |
 |                      |  returns 'reply'      |                  |                   |
 |                      |                       |                  |                   |
 |                      |         _onQuoteReply(messageId)         |                   |
 |                      |         sets _activeQuoteMessageId       |                   |
 |                      |                       |--setState()----->|                   |
 |                      |                       |  quotedText      |                   |
 |                      |                       |  shown in bar    |                   |
 |                      |                       |                  |                   |
 |--type reply text---->|                       |                  |                   |
 |--tap send----------->|                       |--sendChatMessage(                   |
 |                      |                       |    quotedMessageId: id)------------->|
 |                      |                       |                  |  encrypt + send   |
 |                      |                       |                  |  persist locally   |
```

### Flow 4: Edit Tapped

```
User            MessageContextOverlay    ConversationWired    ComposeArea     editChatMessage()
 |                      |                       |                  |                |
 |--tap "Edit"--------->|                       |                  |                |
 |                      |--Navigator.pop()----->|                  |                |
 |                      |  returns 'edit'       |                  |                |
 |                      |                       |                  |                |
 |                      |         _onEditMessage(messageId)        |                |
 |                      |         sets _editingMessageId           |                |
 |                      |         pre-fills compose text           |                |
 |                      |                       |--setState()----->|                |
 |                      |                       |  edit mode       |                |
 |                      |                       |  + original text |                |
 |                      |                       |                  |                |
 |--edit text---------->|                       |                  |                |
 |--tap confirm-------->|                       |--editChatMessage()-------------->|
 |                      |                       |                  |  encrypt + send|
 |                      |                       |                  |  update locally|
 |                      |                       |                  |  (editedAt set)|
```

### Flow 5: Copy Tapped

```
User            MessageContextOverlay    ConversationScreen    Flutter Clipboard
 |                      |                       |                      |
 |--tap "Copy"--------->|                       |                      |
 |                      |--onCopyTap----------->|                      |
 |                      |                       |                      |
 |                      |           Clipboard.setData(                 |
 |                      |             ClipboardData(text: message.text))|
 |                      |                       |--------------------->|
 |                      |                       |                      |
 |                      |           SnackBar feedback shown             |
 |                      |           Navigator.pop()                    |
 |                      |                       |                      |
 |<--- overlay dismissed, text on clipboard     |                      |
```

### Flow 6: Delete Tapped

```
User            MessageContextOverlay    ConversationWired    AlertDialog    deleteMessage*()    P2PService
 |                      |                       |                  |               |                |
 |--tap "Delete"------->|                       |                  |               |                |
 |                      |--Navigator.pop()----->|                  |               |                |
 |                      |  returns 'delete'     |                  |               |                |
 |                      |                       |                  |               |                |
 |                      |         _onDeleteMessage(messageId)      |               |                |
 |                      |                       |--show dialog---->|               |                |
 |                      |                       |  "Delete for Me" |               |                |
 |                      |                       |  "Delete for     |               |                |
 |                      |                       |   Everyone"      |               |                |
 |                      |                       |  "Cancel"        |               |                |
 |                      |                       |                  |               |                |
 |--tap "For Me"------->|                       |<-'forMe'---------|               |                |
 |                      |                       |--deleteMessageForMe()----------->|                |
 |                      |                       |  hard-delete from DB             |                |
 |                      |                       |  cleanup media + reactions        |                |
 |                      |                       |                  |               |                |
 |       --- OR ---     |                       |                  |               |                |
 |                      |                       |                  |               |                |
 |--tap "For Everyone"->|                       |<-'forEveryone'---|               |                |
 |                      |                       |--deleteMessageForEveryone()----->|                |
 |                      |                       |  soft-delete locally (deletedAt) |                |
 |                      |                       |  send deletion payload via P2P----------send----->|
 |                      |                       |                  |               |                |
 |                      |                       | remove from _messages            |                |
 |                      |                       | setState() -> UI updated         |                |
```

---

## Container Communication Summary

| From | To | Protocol / Mechanism | Data |
|------|----|---------------------|------|
| ConversationScreen | MessageContextOverlay | `showDialog()` (Flutter Navigator) | anchorRect, selectedMessage widget, callbacks |
| MessageContextOverlay | ConversationWired | Callback functions via Navigator.pop() result | Action enum ('reply', 'edit', 'copy', 'delete') + messageId |
| ConversationWired | sendReaction() | Direct function call | p2pService, bridge, reactionRepo, targetPeerId, emoji |
| ConversationWired | sendChatMessage() | Direct function call | p2pService, messageRepo, text, quotedMessageId |
| ConversationWired | editChatMessage() | Direct function call | p2pService, messageRepo, originalMessage, newText |
| ConversationWired | deleteMessageForMe() | Direct function call | message, messageRepo, reactionRepo |
| ConversationWired | deleteMessageForEveryone() | Direct function call | p2pService, messageRepo, originalMessage, bridge |
| sendReaction() | Bridge | `callEncryptMessage()` via MethodChannel | recipientMlKemPublicKey, plaintext |
| sendReaction() | P2PService | `sendMessage()` / `storeInInbox()` | targetPeerId, v2 encrypted JSON envelope |
| sendReaction() | ReactionRepository | `saveReaction()` | MessageReaction model |
| deleteMessageForEveryone() | P2PService | `sendMessage()` / `storeInInbox()` | targetPeerId, deletion payload (v2 encrypted) |
| ReactionListener | P2PService.messageStream | Stream subscription (filtered) | Incoming ChatMessage with type "reaction" |
| ReactionListener | ReactionRepository | `saveReaction()` / `removeReaction()` | Persisted MessageReaction |
| ReactionListener | ConversationWired | StreamController broadcast | MessageReaction / ReactionChange |
| ChatMessageListener | P2PService.messageStream | Stream subscription (filtered) | Incoming ChatMessage with type "chat" |
| MessageDeletionListener | P2PService.messageStream | Stream subscription (filtered) | Incoming deletion payload |
| ConversationScreen | Flutter Clipboard | `Clipboard.setData()` | ClipboardData(text: message.text) |
| MessageRepository | SQLCipher Database | sqflite_sqlcipher API | SQL on `messages` table |
| ReactionRepository | SQLCipher Database | sqflite_sqlcipher API | SQL on `message_reactions` table |
| Bridge | Go native library | MethodChannel / EventChannel | `message.encrypt`, `message.decrypt`, `payload.sign` |
| SecureKeyStore | OS Keychain / EncryptedSharedPrefs | Platform channel | ML-KEM secret key for decryption |

---

## Container Descriptions

### 1. Presentation Layer

| Component | Type | Responsibility |
|-----------|------|---------------|
| **ConversationWired** | StatefulWidget | Orchestrates all conversation state: `_messages` list, `_reactions` map (messageId -> List\<MessageReaction\>), stream subscriptions to ReactionListener / ChatMessageListener / MessageDeletionListener. Handles callback results from the overlay (reaction selected, reply, edit, copy, delete). |
| **ConversationScreen** | StatelessWidget (pure) | Builds the message list via `ListView.builder(reverse: true)`. Attaches `onLongPress` to each LetterCard. Contains `_showMessageContextOverlay()` which captures the RenderBox anchor rect and calls `showDialog()`. Determines conditional actions: showEditAction (only user's last sent message), showCopyAction (message has text), showDeleteAction (always true). |
| **LetterCard** | StatelessWidget | Full-width glassmorphic message card. Left accent edge for incoming, right accent for sent. Exposes `onLongPress` callback. Displays text, time, sender name, quoted text, media grid, reactions, edited/deleted indicators. |
| **MessageContextOverlay** | StatelessWidget | Full-screen overlay rendered as a dialog. Composes three vertical zones: (1) ReactionBar positioned above the message, (2) scaled-down LetterCard preview via FittedBox + IgnorePointer, (3) \_ContextMenuCard below with Reply/Edit/Copy/Delete. Backdrop is `BackdropFilter(blur: 18, 18)` over `rgba(6, 8, 12, 0.24)` scrim. Smart viewport positioning clamps all elements within safe area bounds. |
| **ReactionBar** | StatefulWidget | Glassmorphic bar with 6 preset emojis + "+" button. Scale animation 0.8 to 1.0 over 200ms (easeOut). Highlights `currentEmoji` if user already reacted. "+" opens FullEmojiPicker modal sheet. |
| **ComposeArea** | StatefulWidget | Text input that supports two overlay-triggered modes: quote-reply mode (shows quoted text preview bar with dismiss button) and edit mode (pre-fills original text, shows edit banner). |

### 2. Application Layer

| Component | Type | Responsibility |
|-----------|------|---------------|
| **sendReaction()** | Top-level function | Checks P2P node running, builds ReactionPayload, encrypts via Bridge (ML-KEM-768 + AES-256-GCM), sends v2 envelope via P2PService (direct or inbox fallback), persists to ReactionRepository. Returns (result, MessageReaction?). |
| **removeReaction()** | Top-level function | Sends removal payload via P2P, deletes from ReactionRepository. |
| **loadReactions()** | Top-level function | Batch loads reactions for visible message IDs from ReactionRepository. Returns Map\<String, List\<MessageReaction\>\>. |
| **sendChatMessage()** | Top-level function | Sends a chat message with optional `quotedMessageId` for the Reply action. Encrypts if contact has ML-KEM key. Persists locally. |
| **editChatMessage()** | Top-level function | Sends edit payload for the user's last sent message. Updates `editedAt` locally and notifies recipient via P2P. |
| **deleteMessageForMe()** | Top-level function | Hard-deletes message from local DB. Cleans up associated reactions (via ReactionRepository) and media files. |
| **deleteMessageForEveryone()** | Top-level function | Soft-deletes locally (sets `deletedAt`, `deletedByPeerId`). Sends MessageDeletionPayload via P2P (v2 encrypted) so recipient also removes the message. |
| **ReactionListener** | Class (stream-based) | Subscribes to typed reaction stream from IncomingMessageRouter. Decrypts v2 envelopes, calls handleIncomingReaction, broadcasts persisted MessageReaction and ReactionChange events to UI via StreamController. |
| **ChatMessageListener** | Class (stream-based) | Same pattern as ReactionListener for chat messages. Broadcasts incoming ConversationMessage to UI. |
| **MessageDeletionListener** | Class (stream-based) | Subscribes to deletion stream. Soft-deletes messages locally when remote deletion notice arrives. Broadcasts change to UI. |

### 3. Domain Layer

| Component | Type | Responsibility |
|-----------|------|---------------|
| **ConversationMessage** | Model | Represents a single message. Fields: id, contactPeerId, senderPeerId, text, timestamp, status, isIncoming, editedAt, deletedAt, deletedByPeerId, quotedMessageId, media. Uses `fromMap`/`toMap` for DB, `fromJson`/`toJson` for wire. |
| **MessageReaction** | Model | Represents an emoji reaction. Fields: id, messageId, emoji, senderPeerId, timestamp, createdAt. UNIQUE constraint on (message_id, sender_peer_id). Uses `fromMap`/`toMap` for DB, `fromJson`/`toJson` for wire. |
| **MessageDeletionPayload** | Model | Wire-format payload for delete-for-everyone. Fields: id, originalMessageId, deletedByPeerId, timestamp. |
| **ReactionPayload** | Model | Wire-format payload for reactions. Builds v2 encrypted envelope. |
| **MessageRepository** | Interface | CRUD for messages: saveMessage, getMessage, getMessagesForContact, updateMessageStatus, deleteMessage, markConversationAsRead. |
| **ReactionRepository** | Interface | CRUD for reactions: saveReaction (upsert), getReactionsForMessage, getReactionsForMessages (batch), removeReaction, deleteReactionsForMessage. |

### 4. Infrastructure Layer

| Component | Type | Responsibility |
|-----------|------|---------------|
| **SQLCipher Database** | Encrypted SQLite (sqflite_sqlcipher) | Stores `messages` table (schema v2+) and `message_reactions` table. Encrypted at rest with 256-bit random key stored in SecureKeyStore. |
| **P2PService** | libp2p networking | Sends wire messages to peers. `sendMessage(peerId, json)` for direct delivery, `storeInInbox(peerId, json)` for store-and-forward when peer is offline. Provides `messageStream` for incoming messages consumed by listeners. |
| **Bridge (GoBridgeClient)** | MethodChannel to Go native | Executes cryptographic operations: `message.encrypt` (ML-KEM-768 encapsulation + AES-256-GCM), `message.decrypt`, `payload.sign`. Called by use cases for all v2 encrypted payloads. |
| **SecureKeyStore** | Platform secure storage | iOS Keychain / Android EncryptedSharedPreferences. Stores `identity_ml_kem_secret_key` needed by ReactionListener and ChatMessageListener for decrypting incoming v2 messages. Also stores DB encryption key. |
| **Flutter Clipboard** | Platform service | `Clipboard.setData(ClipboardData(text: ...))` used exclusively by the Copy action. Copies message text content to system clipboard. |

---

## PlantUML C4 Container Diagram

```plantuml
@startuml C4_MessageContextOverlay
!include https://raw.githubusercontent.com/plantuml-stdlib/C4-PlantUML/master/C4_Container.puml

LAYOUT_WITH_LEGEND()

title C4 Container Diagram - MessageContextOverlay Feature

System_Boundary(app, "mknoon Flutter App") {

    Container_Boundary(presentation, "Presentation Layer") {
        Container(wired, "ConversationWired", "StatefulWidget", "Orchestrates state: _messages, _reactions map, stream subscriptions. Routes overlay action results to use cases.")
        Container(screen, "ConversationScreen", "StatelessWidget", "Builds message list (ListView.builder reverse). Attaches onLongPress to each LetterCard. Shows overlay via showDialog().")
        Container(letterCard, "LetterCard", "StatelessWidget", "Glassmorphic message card. Left accent=incoming, right=sent. Exposes onLongPress callback.")
        Container(overlay, "MessageContextOverlay", "StatelessWidget", "Full-screen overlay: ReactionBar + message preview + context menu. BackdropFilter blur(18). Viewport-clamped positioning.")
        Container(reactionBar, "ReactionBar", "StatefulWidget", "6 preset emojis + '+' picker. Scale anim 0.8->1.0/200ms. Highlights current reaction.")
        Container(compose, "ComposeArea", "StatefulWidget", "Text input with quote-reply mode and edit mode triggered by overlay actions.")
    }

    Container_Boundary(application, "Application Layer") {
        Container(sendReaction, "sendReaction()", "Use Case", "Encrypt via Bridge, send v2 envelope via P2P, persist to ReactionRepo.")
        Container(removeReaction, "removeReaction()", "Use Case", "Send removal via P2P, delete from ReactionRepo.")
        Container(loadReactions, "loadReactions()", "Use Case", "Batch load reactions for visible message IDs.")
        Container(sendChat, "sendChatMessage()", "Use Case", "Send chat with optional quotedMessageId for Reply.")
        Container(editChat, "editChatMessage()", "Use Case", "Edit last sent message text, notify recipient.")
        Container(deleteForMe, "deleteMessageForMe()", "Use Case", "Hard-delete from local DB, cleanup artifacts.")
        Container(deleteForAll, "deleteMessageForEveryone()", "Use Case", "Soft-delete locally + send deletion payload via P2P.")
        Container(reactionListener, "ReactionListener", "Listener", "Stream sub on reactionStream, decrypt, persist, broadcast.")
        Container(chatListener, "ChatMessageListener", "Listener", "Stream sub on chatStream, decrypt, persist, broadcast.")
        Container(deletionListener, "MessageDeletionListener", "Listener", "Stream sub on deletionStream, soft-delete, broadcast.")
    }

    Container_Boundary(domain, "Domain Layer") {
        Container(msgModel, "ConversationMessage", "Model", "id, text, senderPeerId, isIncoming, status, editedAt, deletedAt, quotedMessageId, media")
        Container(rxnModel, "MessageReaction", "Model", "id, messageId, emoji, senderPeerId. UNIQUE(message_id, sender_peer_id)")
        Container(msgRepo, "MessageRepository", "Interface", "CRUD: save, get, update status, delete, mark read")
        Container(rxnRepo, "ReactionRepository", "Interface", "CRUD: save(upsert), get batch, remove, delete for message")
    }

    Container_Boundary(infra, "Infrastructure Layer") {
        ContainerDb(db, "SQLCipher Database", "sqflite_sqlcipher", "Encrypted SQLite. messages + message_reactions tables.")
        Container(p2p, "P2PService", "libp2p", "sendMessage / storeInInbox. messageStream for incoming. v1/v2 wire format.")
        Container(bridge, "Bridge (GoBridgeClient)", "MethodChannel->Go", "message.encrypt, message.decrypt, payload.sign. ML-KEM-768 + AES-256-GCM.")
        Container(keyStore, "SecureKeyStore", "Platform Secure Storage", "iOS Keychain / Android EncryptedSharedPrefs. ML-KEM secret key, DB key.")
        Container(clipboard, "Flutter Clipboard", "Platform Service", "Clipboard.setData() for Copy action.")
    }
}

Rel(wired, screen, "builds, passes callbacks")
Rel(screen, letterCard, "builds per message, attaches onLongPress")
Rel(letterCard, screen, "onLongPress fires")
Rel(screen, overlay, "showDialog(useSafeArea:false)")
Rel(overlay, reactionBar, "contains, positions above message")
Rel(overlay, wired, "Navigator.pop() returns action + data")
Rel(wired, compose, "sets quote-reply or edit mode")

Rel(wired, sendReaction, "emoji selected")
Rel(wired, sendChat, "reply with quotedMessageId")
Rel(wired, editChat, "edit action on last sent msg")
Rel(wired, deleteForMe, "delete for me action")
Rel(wired, deleteForAll, "delete for everyone action")
Rel(wired, loadReactions, "batch load on scroll")

Rel(sendReaction, bridge, "callEncryptMessage()")
Rel(sendReaction, p2p, "sendMessage() / storeInInbox()")
Rel(sendReaction, rxnRepo, "saveReaction()")
Rel(editChat, bridge, "callEncryptMessage()")
Rel(editChat, p2p, "sendMessage()")
Rel(deleteForAll, p2p, "sendMessage() deletion payload")
Rel(deleteForMe, msgRepo, "deleteMessage()")

Rel(reactionListener, p2p, "subscribes to messageStream", "Stream<ChatMessage>")
Rel(reactionListener, rxnRepo, "saveReaction()")
Rel(reactionListener, wired, "broadcasts MessageReaction", "StreamController")
Rel(chatListener, p2p, "subscribes to messageStream", "Stream<ChatMessage>")
Rel(chatListener, wired, "broadcasts ConversationMessage", "StreamController")
Rel(deletionListener, p2p, "subscribes to messageStream")
Rel(deletionListener, wired, "broadcasts deletion change")

Rel(msgRepo, db, "SQL queries on messages table")
Rel(rxnRepo, db, "SQL queries on message_reactions table")
Rel(bridge, keyStore, "reads ML-KEM secret key for decrypt")
Rel(screen, clipboard, "Clipboard.setData() on Copy tap")

@enduml
```

---

## Key Design Decisions

1. **Overlay as dialog, not Navigator push.** `showDialog(useSafeArea: false, barrierColor: transparent)` preserves the conversation behind the blur. The overlay is a single `Material` + `Stack` compositing reaction bar, message preview, and context menu with independent viewport-clamped positioning.

2. **Smart viewport clamping.** `MessageContextOverlay._clampToViewport()` ensures reaction bar, selected message preview, and context menu never clip outside safe area boundaries, regardless of whether the long-pressed message is near the top or bottom edge.

3. **Conditional context menu actions.** Edit is shown only for the user's last sent message. Copy is shown only when message has text content. Delete is shown for all messages. Reply is always shown.

4. **Encryption is mandatory for reactions and deletions.** `sendReaction()` enforces v2 encryption (ML-KEM-768 + AES-256-GCM). If the contact lacks an ML-KEM public key, the reaction cannot be sent (`encryptionRequired` result). Same applies to delete-for-everyone payloads.

5. **Fire-and-forget with inbox fallback.** P2PService.sendMessage attempts direct delivery; on failure, `storeInInbox()` queues for store-and-forward delivery when the peer comes online.

6. **Listeners decouple incoming from outgoing.** ReactionListener, ChatMessageListener, and MessageDeletionListener each subscribe to their typed stream from IncomingMessageRouter, decrypt v2 envelopes, persist to repositories, and broadcast to UI via StreamController. ConversationWired subscribes to these broadcast streams.
