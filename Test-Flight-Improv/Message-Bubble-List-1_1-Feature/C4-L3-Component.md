# C4 Model -- Level 3: Component Diagram

## Feature: MessageContextOverlay

**Scope:** Long-press context menu on a LetterCard in the conversation screen. Shows glassmorphic overlay with reaction bar (6 presets + full emoji picker), context menu (Reply, Edit, Copy, Delete), and scaled-down preview of the selected message.

**System boundary:** `lib/features/conversation/` within the Flutter app. External systems are P2PService (libp2p transport) and Bridge/GoBridgeClient (Go native crypto).

---

## Container: Presentation

All widgets and state management for the overlay feature.

### MessageContextOverlay

- **Type:** StatelessWidget
- **File:** `lib/features/conversation/presentation/widgets/message_context_overlay.dart` (329 lines)
- **Purpose:** Full-screen overlay shown via `showDialog` on long-press of a LetterCard. Composites the backdrop, selected message preview, reaction bar, and context menu into a positioned Stack.

**Constructor parameters:**
```
anchorRect: Rect                          -- global bounds of the long-pressed card
selectedMessage: Widget?                  -- scaled-down clone of the LetterCard
currentEmoji: String?                     -- user's existing reaction (highlight in bar)
showEditAction: bool                      -- gate: only last sent, non-deleted, has text
showCopyAction: bool                      -- gate: non-deleted, has text
showDeleteAction: bool                    -- gate: non-deleted, non-system transport
onDismiss: VoidCallback                   -- pops the dialog
onReactionSelected: void Function(String) -- emoji selected from bar
onPlusTap: VoidCallback                   -- opens FullEmojiPicker bottom sheet
onReplyTap: VoidCallback                  -- sets compose area to quote-reply mode
onEditTap: VoidCallback?                  -- sets compose area to edit mode
onCopyTap: VoidCallback?                  -- copies message text to clipboard
onDeleteTap: VoidCallback?               -- triggers delete flow
```

**Static test keys:**
`overlayKey`, `backdropKey`, `reactionBarKey`, `selectedMessageKey`, `menuKey`, `replyActionKey`, `editActionKey`, `copyActionKey`, `deleteActionKey`

**Layout algorithm:**
1. Compute safe viewport bounds: 8px padding + system safe areas (top/bottom).
2. Place selected message preview at clamped anchor position (between reaction bar bottom and menu top).
3. Place reaction bar above preview (min 60px from top safe edge).
4. Place context menu below preview, height = actionCount * 58px.
5. Horizontal alignment: `Alignment(((anchorCenterX / screenWidth) * 2 - 1).clamp(-1, 1), -1)`.

**Visual layers (Stack order):**
1. Backdrop: `GestureDetector(onTap: onDismiss)` + `BackdropFilter(blur: 18, 18)` + `Container(color: RGBA(6,8,12,0.24))`
2. Selected message preview: `FittedBox(fit: scaleDown)` + `IgnorePointer` + `ClipRect`
3. ReactionBar (positioned above preview)
4. _ContextMenuCard (positioned below preview, max 220px wide)

**Internal widgets:**
- `_ContextMenuCard` -- glassmorphic container (`RGBA(18,20,28,0.95)`, blur 20, border `RGBA(255,255,255,0.10)`, radius 24) holding action rows separated by thin dividers.
- `_ContextMenuAction` -- InkWell row with icon + label. Delete action uses `Color(0xFFFF8A80)`.

---

### ReactionBar

- **Type:** StatefulWidget (uses `SingleTickerProviderStateMixin`)
- **File:** `lib/features/conversation/presentation/widgets/reaction_bar.dart` (153 lines)
- **Purpose:** Floating bar with 6 preset emoji buttons + "+" button for full picker.

**Constructor parameters:**
```
currentEmoji: String?                      -- highlights user's existing reaction
onReactionSelected: void Function(String)  -- callback when preset tapped
onPlusTap: VoidCallback                    -- opens full emoji picker
onDismiss: VoidCallback                    -- backdrop tap dismiss
anchorY: double?                           -- vertical anchor (standalone mode)
inline: bool                               -- true when embedded in overlay Stack
```

**Preset emojis:** `kPresetEmojis = ['thumbs_up', 'heart', 'joy', 'open_mouth', 'cry', 'pray']`

**Animation:** `AnimationController(200ms)` + `Tween<double>(0.8 -> 1.0)` + `CurvedAnimation(Curves.easeOut)` applied via `ScaleTransition`.

**Selection highlight:** `isSelected` = `currentEmoji == emoji` -> background `RGBA(78,205,196,0.20)`.

**Toggle behavior:** Tapping the same emoji as `currentEmoji` triggers `onReactionSelected(emoji)`. ConversationWired interprets this as a toggle-off (remove reaction).

---

### LetterCard

- **Type:** StatelessWidget
- **File:** `lib/features/conversation/presentation/widgets/letter_card.dart` (521 lines)
- **Purpose:** Full-width glassmorphic letter card for conversation messages. Entry point for the overlay via `onLongPress`.

**Relevant parameters for overlay flow:**
```
onLongPress: VoidCallback?                 -- triggers _showMessageContextOverlay
reactions: List<MessageReaction>           -- inline reaction chips at card footer
ownPeerId: String?                         -- used to highlight own reaction chip
onReactionTap: void Function(String)?     -- inline chip tap (same toggle logic)
```

**Long-press wiring:** Top-level `GestureDetector(onLongPress: onLongPress)` wraps entire card.

**Inline reaction chips:** Footer `Wrap` widget groups reactions by emoji. Own reactions get teal border (`RGBA(78,205,196,0.30)`). Tapping a chip calls `onReactionTap(emoji)`.

---

### ConversationScreen

- **Type:** StatefulWidget
- **File:** `lib/features/conversation/presentation/screens/conversation_screen.dart` (850+ lines)
- **Purpose:** Pure UI screen. Bridges user gestures to callback props wired by ConversationWired.

**Key method -- `_showMessageContextOverlay(message, cardContext, selectedMessage)` (line 618-689):**
1. Gets `anchorRect` from `cardContext.findRenderObject().localToGlobal()`.
2. Resolves `ownReaction` from `widget.reactions[message.id]`.
3. Evaluates permission gates:
   - `_canEditMessage(message)`: `allowEditAction && !deleted && !incoming && senderPeerId == ownPeerId && text.isNotEmpty && _lastSentMessageId() == message.id`
   - `_canDeleteMessage(message)`: `onDeleteMessage != null && !deleted && transport != 'system'`
   - Copy: `!deleted && text.trim().isNotEmpty`
4. Calls `showDialog(useSafeArea: false, barrierColor: transparent)` with `MessageContextOverlay`.
5. Each callback: `Navigator.pop(dialogContext)` then dispatches to `widget.onReactionSelected / onQuoteReply / onEditMessage / onDeleteMessage`.

**Helper methods:**
- `_handleReplyAction(messageId)` -> `widget.onQuoteReply(messageId)` + `_requestComposerFocus()`
- `_handleEditAction(messageId)` -> `widget.onEditMessage(messageId)` + `_requestComposerFocus()`
- `_copyMessageText(text)` -> `Clipboard.setData()` + SnackBar confirmation

---

### ConversationWired

- **Type:** StatefulWidget
- **File:** `lib/features/conversation/presentation/screens/conversation_wired.dart` (3300+ lines)
- **Purpose:** Stateful orchestrator. Manages reactions state, dispatches to use cases, listens for remote updates.

**State:**
```
_reactions: Map<String, List<MessageReaction>>   -- messageId -> list of reactions
```

**Key method -- `_onReactionSelected(String messageId, String emoji)` (line 2758):**
1. Resolves own identity and checks `reactionRepo` + `bridge` availability.
2. Finds existing `ownReaction` for this message.
3. **Toggle off** (same emoji): optimistic `setState` removing own reaction -> `removeReaction()` use case.
4. **Add/replace**: optimistic `setState` with placeholder `MessageReaction(id: '')` -> `sendReaction()` use case -> on success, `setState` replacing placeholder with real reaction.

**Listener integration:**
- Subscribes to `reactionListener.incomingReactionChangeStream` for remote reaction updates.
- On `ReactionChange.upserted`: upserts reaction into `_reactions` by `senderPeerId` (one reaction per user per message).
- On `ReactionChange.removed`: removes reaction from `_reactions` by `senderPeerId`.

**Callback wiring to ConversationScreen:**
```
onReactionSelected: _onReactionSelected
onQuoteReply: _handleReplyAction     -- sets compose area to quote-reply mode
onEditMessage: _handleEditAction     -- sets compose area to edit mode with text
onDeleteMessage: _handleDeleteAction -- shows delete-for-me / delete-for-everyone sheet
```

---

## Container: Application (Use Cases)

All use cases are top-level functions, not classes. Each uses `emitFlowEvent()` for structured logging.

### sendReaction()

- **File:** `lib/features/conversation/application/send_reaction_use_case.dart` (133 lines)
- **Signature:**
```dart
Future<(SendReactionResult, MessageReaction?)> sendReaction({
  required P2PService p2pService,
  required Bridge bridge,
  required ReactionRepository reactionRepo,
  required String targetPeerId,
  required String messageId,
  required String emoji,
  required String senderPeerId,
  required String recipientMlKemPublicKey,
})
```
- **Flow:**
  1. Check `p2pService.currentState.isStarted` -> `nodeNotRunning`
  2. Build `ReactionPayload(action: 'add')`
  3. Encrypt via `callEncryptMessage(bridge, recipientMlKemPublicKey, plaintext)` -> build v2 encrypted envelope
  4. Send: `p2pService.sendMessage()` direct, fallback `p2pService.storeInInbox()`
  5. Persist: `reactionRepo.saveReaction(reaction)`
  6. Return `(success, MessageReaction)`
- **Result enum:** `success`, `nodeNotRunning`, `encryptionRequired`, `encryptionFailed`, `sendFailed`

---

### removeReaction()

- **File:** `lib/features/conversation/application/remove_reaction_use_case.dart` (124 lines)
- **Signature:**
```dart
Future<RemoveReactionResult> removeReaction({
  required P2PService p2pService,
  required Bridge bridge,
  required ReactionRepository reactionRepo,
  required String targetPeerId,
  required String messageId,
  required String emoji,
  required String senderPeerId,
  required String recipientMlKemPublicKey,
})
```
- **Flow:** Same as sendReaction but `action: 'remove'` and calls `reactionRepo.removeReaction(messageId, senderPeerId)` instead of save.
- **Result enum:** `success`, `nodeNotRunning`, `encryptionRequired`, `encryptionFailed`, `sendFailed`

---

### editChatMessage()

- **File:** `lib/features/conversation/application/send_chat_message_use_case.dart` (line 537)
- **Signature:**
```dart
Future<(SendChatMessageResult, ConversationMessage?)> editChatMessage({
  required P2PService p2pService,
  required MessageRepository messageRepo,
  required ConversationMessage originalMessage,
  required String updatedText,
  required String senderUsername,
  Bridge? bridge,
  String? recipientMlKemPublicKey,
  MediaAttachmentRepository? mediaAttachmentRepo,
})
```
- **Flow:** Guards `originalMessage.isIncoming` -> `invalidMessage`. Delegates to `sendChatMessage()` with `action: MessagePayload.actionEdit` and `messageId: originalMessage.id`. The send path handles encrypt/send/persist including `editedAt` timestamp.

---

### deleteMessageForMe()

- **File:** `lib/features/conversation/application/delete_message_use_case.dart` (line 17)
- **Signature:**
```dart
Future<int> deleteMessageForMe({
  required ConversationMessage message,
  required MessageRepository messageRepo,
  ReactionRepository? reactionRepo,
  MediaAttachmentRepository? mediaAttachmentRepo,
  MediaFileManager? mediaFileManager,
})
```
- **Flow:** Cleans up artifacts (reactions, media attachments, local files) -> `messageRepo.deleteMessage(id)`. No P2P send. Returns deleted row count.

---

### deleteMessageForEveryone()

- **File:** `lib/features/conversation/application/delete_message_use_case.dart` (line 49)
- **Signature:**
```dart
Future<(SendChatMessageResult, ConversationMessage?)> deleteMessageForEveryone({
  required P2PService p2pService,
  required MessageRepository messageRepo,
  required ConversationMessage originalMessage,
  ReactionRepository? reactionRepo,
  MediaAttachmentRepository? mediaAttachmentRepo,
  MediaFileManager? mediaFileManager,
  Bridge? bridge,
  String? recipientMlKemPublicKey,
})
```
- **Flow:**
  1. Validate: must be outgoing, not deleted, status = `delivered`
  2. Build `MessageDeletionPayload`, encrypt if bridge available
  3. Persist pending tombstone (`status: 'sending'`, `deletedAt`, `deletedByPeerId`)
  4. Cleanup artifacts (reactions, media)
  5. Race: try local send -> try direct send -> try relay probe -> fallback inbox
  6. Update tombstone to final status (`delivered`/`sent`/`failed`)

---

### ReactionListener

- **Type:** Class (service, not widget)
- **File:** `lib/features/conversation/application/reaction_listener.dart` (139 lines)
- **Purpose:** Subscribes to incoming P2P reaction messages, invokes `handleIncomingReaction`, broadcasts changes to UI.

**Constructor dependencies:**
```dart
reactionStream: Stream<ChatMessage>              -- filtered from IncomingMessageRouter
reactionRepo: ReactionRepository
contactRepo: ContactRepository
bridge: Bridge
getOwnMlKemSecretKey: Future<String?> Function()
```

**Streams exposed:**
```dart
incomingReactionStream: Stream<MessageReaction>   -- add events only
incomingReactionChangeStream: Stream<ReactionChange>  -- add + remove events
```

**Processing pipeline:**
1. Filter blocked senders via `contactRepo.getContact(senderPeerId)`
2. Resolve ML-KEM secret key via `getOwnMlKemSecretKey()`
3. Decrypt + parse via `handleIncomingReaction()` use case
4. Broadcast `ReactionChange` (type: `upserted` or `removed`) on change stream

**Lifecycle:** `start()` subscribes, `stop()` cancels subscription, `dispose()` closes stream controllers.

---

## Container: Domain (Models)

### ConversationMessage

- **File:** `lib/features/conversation/domain/models/conversation_message.dart` (199 lines)
- **Table:** `messages`
- **Fields:**
```
id: String (UUID v4)
contactPeerId: String
senderPeerId: String
text: String
timestamp: String (ISO-8601)
status: String ('sending' | 'sent' | 'delivered' | 'failed' | 'queued')
isIncoming: bool
createdAt: String (ISO-8601)
editedAt: String? (ISO-8601, set on edit)
readAt: String?
quotedMessageId: String?
deletedAt: String? (ISO-8601, set on delete-for-everyone)
deletedByPeerId: String?
hiddenAt: String? (set on delete-for-me sender-side)
transport: String? ('wifi' | 'local' | 'direct' | 'relay' | 'inbox' | 'system')
wireEnvelope: String? (serialized JSON for retry, null once delivered)
media: List<MediaAttachment> (transient, not persisted in messages table)
```
- **Methods:** `fromMap(Map)`, `toMap()`, `copyWith(...)`, `isDeleted` getter, `isHidden` getter
- **Equality:** by `id`

---

### MessageReaction

- **File:** `lib/features/conversation/domain/models/message_reaction.dart` (114 lines)
- **Table:** `message_reactions` with UNIQUE(message_id, sender_peer_id)
- **Fields:**
```
id: String (UUID v4)
messageId: String (FK -> messages.id)
emoji: String (emoji codepoints)
senderPeerId: String
timestamp: String (ISO-8601, sender creation time)
createdAt: String (ISO-8601, local row creation time)
```
- **Methods:** `fromMap(Map)`, `toMap()`, `fromJson(Map)`, `toJson()`, `copyWith(...)`
- **Equality:** by `id`

---

## Container: Infrastructure (Repositories + External Services)

### ReactionRepositoryImpl

- **File:** `lib/features/conversation/domain/repositories/reaction_repository_impl.dart` (96 lines)
- **Implements:** `ReactionRepository`
- **Injected DB helpers (constructor):**
```dart
dbInsertReaction: Future<void> Function(Map<String, Object?> row)
dbLoadReactionsForMessage: Future<List<Map>> Function(String messageId)
dbLoadReactionsForMessages: Future<List<Map>> Function(List<String> messageIds)
dbDeleteReaction: Future<int> Function(String messageId, String senderPeerId)
dbDeleteReactionsForMessage: Future<int> Function(String messageId)
dbDeleteReactionsForContact: Future<int> Function(String contactPeerId)
```
- **Interface methods:**
  - `saveReaction(MessageReaction)` -> upsert via `dbInsertReaction(reaction.toMap())`
  - `getReactionsForMessage(messageId)` -> `dbLoadReactionsForMessage` -> map to `MessageReaction.fromMap`
  - `getReactionsForMessages(messageIds)` -> batch load, group by messageId
  - `removeReaction(messageId, senderPeerId)` -> `dbDeleteReaction`
  - `deleteReactionsForMessage(messageId)` -> `dbDeleteReactionsForMessage`
  - `deleteReactionsForContact(contactPeerId)` -> `dbDeleteReactionsForContact`

---

### MessageRepositoryImpl

- **File:** `lib/features/conversation/domain/repositories/message_repository_impl.dart`
- **Implements:** `MessageRepository`, `ConversationThreadSummaryRepository`, `MessageRepositoryChangeSource`
- **Key interface methods used by overlay feature:**
  - `saveMessage(ConversationMessage)` -> upsert via `dbInsertMessage(message.toMap())`
  - `getMessage(String id)` -> `dbLoadMessage` -> `ConversationMessage.fromMap`
  - `deleteMessage(String id)` -> `dbDeleteMessage` (delete-for-me)
  - `getMessagesPage(contactPeerId, {limit, beforeTimestamp})` -> paginated query
  - `updateMessageStatus(id, status)` -> `dbUpdateMessageStatus`
- **Change stream:** `messageChanges: Stream<ConversationMessage>` for UI reactivity to background status changes.

---

### P2PService (External)

- **File:** `lib/core/services/p2p_service.dart`
- **Role:** Transport layer for all P2P wire messages.
- **Methods used by overlay feature:**
  - `sendMessage(peerId, jsonString)` -> direct stream send, returns bool
  - `sendMessageWithReply(peerId, jsonString, {timeoutMs})` -> send + wait for ACK
  - `storeInInbox(peerId, jsonString)` -> relay inbox fallback for offline peers
  - `discoverPeer(peerId, {timeoutMs})` -> rendezvous discover
  - `dialPeer(peerId, {addresses, timeoutMs})` -> libp2p dial
  - `probeRelay(peerId)` -> check relay reservation
  - `sendLocalMessage(peerId, jsonString, senderPeerId, {timeoutMs})` -> local WiFi send
  - `currentState.isStarted` -> node readiness check
  - `isLocalPeer(peerId)` -> local network peer check
  - `messageStream` -> incoming message stream (consumed by listeners)

---

### Bridge / GoBridgeClient (External)

- **File:** `lib/core/bridge/bridge.dart` (abstract), `lib/core/bridge/go_bridge_client.dart` (implementation)
- **Role:** MethodChannel to Go native library for cryptographic operations.
- **Helper functions used by overlay feature:**
  - `callEncryptMessage(bridge, recipientMlKemPublicKey, plaintext)` -> ML-KEM-768 encapsulate + AES-256-GCM encrypt -> `{ok, kem, ciphertext, nonce}`
  - `callDecryptMessage(bridge, ownMlKemSecretKey, kem, ciphertext, nonce)` -> decapsulate + decrypt -> `{ok, plaintext}`
- **Bridge commands invoked:** `message.encrypt`, `message.decrypt`

---

## Dependency Arrows

```
+---------------------+        +---------------------+
|   LetterCard        |        |   ReactionBar       |
|   [Presentation]    |        |   [Presentation]    |
+--------+------------+        +----------+----------+
         |                                |
         | onLongPress                    | onReactionSelected
         v                                | onPlusTap
+--------+--------------------------------+----------+
|              ConversationScreen                     |
|              [Presentation]                         |
|                                                     |
|  _showMessageContextOverlay() ------+               |
|  _canEditMessage()                  |               |
|  _canDeleteMessage()                |               |
|  _handleReplyAction()               |               |
|  _handleEditAction()                |               |
|  _copyMessageText()                 |               |
+-----+-------------------------------+---------------+
      |                                |
      | callbacks via                  | showDialog()
      | widget props                   v
      |                     +----------+----------+
      |                     | MessageContextOverlay|
      |                     | [Presentation]       |
      |                     +---------------------+
      |
      v
+-----+---------------------------------------------+
|              ConversationWired                      |
|              [Presentation / State]                 |
|                                                     |
|  _reactions: Map<String, List<MessageReaction>>     |
|  _onReactionSelected(messageId, emoji)              |
|  _handleReplyAction(messageId)                      |
|  _handleEditAction(messageId)                       |
|  _handleDeleteAction(messageId)                     |
+--+---------+---------+---------+-------------------+
   |         |         |         |
   |         |         |         | listens to
   |         |         |         v
   |         |         |  +------+-----------+
   |         |         |  | ReactionListener |
   |         |         |  | [Application]    |
   |         |         |  +------+-----------+
   |         |         |         |
   v         v         v         v
+--+--+  +--+--+  +---+---+  +--+--+
|send |  |remov|  |edit   |  |delet|
|React|  |eReac|  |ChatMsg|  |eMsgF|  deleteMessageForMe()
|ion()|  |tion()|  |()    |  |orEvr|
+--+--+  +--+--+  +--+---+  |yone()|
   |         |        |      +--+---+
   |         |        |         |
   +----+----+--------+---------+
        |              |
        v              v
+-------+------+  +---+----------------+
| ReactionRepo |  | MessageRepository  |
| [Infra]      |  | [Infra]            |
+---------+----+  +----+---------------+
          |             |
          v             v
     +---------+   +---------+
     | SQLite  |   | SQLite  |
     | (react  |   | (msgs   |
     |  table) |   |  table) |
     +---------+   +---------+

Use cases also depend on:
+-------------+         +-------------------+
| P2PService  | <------ | sendReaction()    |
| [External]  | <------ | removeReaction()  |
|             | <------ | editChatMessage() |
|             | <------ | deleteMsg*()      |
|             | ------> | ReactionListener  |
+------+------+         +-------------------+
       |
       v
+------+------+
| Bridge      | <------ sendReaction()
| (GoBridge   | <------ removeReaction()
|  Client)    | <------ editChatMessage()
| [External]  | <------ deleteMessageForEveryone()
|             | <------ ReactionListener
+-------------+
```

---

## Data Flow: Long-Press to Reaction Sent

```
1. User long-presses LetterCard
   -> LetterCard.onLongPress fires

2. ConversationScreen._showMessageContextOverlay()
   -> findRenderObject() -> anchorRect
   -> evaluate _canEditMessage, _canDeleteMessage, copy gate
   -> showDialog(MessageContextOverlay)

3. MessageContextOverlay renders:
   - Backdrop (blur + dimming)
   - Selected message preview (scaled clone)
   - ReactionBar (animated scale 0.8->1.0)
   - _ContextMenuCard (Reply, Edit?, Copy?, Delete?)

4. User taps emoji in ReactionBar
   -> onReactionSelected(emoji) callback
   -> Navigator.pop() (dismiss overlay)
   -> widget.onReactionSelected(messageId, emoji)

5. ConversationWired._onReactionSelected(messageId, emoji)
   -> Check if toggle-off (same emoji from same user)
   -> If toggle-off:
      a. Optimistic setState: remove own reaction from _reactions
      b. await removeReaction() use case
   -> If add/replace:
      a. Optimistic setState: add/replace in _reactions with placeholder
      b. await sendReaction() use case
      c. On success: setState replacing placeholder with real reaction

6. sendReaction() use case
   -> Check P2P node running
   -> Build ReactionPayload(action: 'add')
   -> callEncryptMessage(bridge, mlKemPublicKey, plaintext)
   -> p2pService.sendMessage() || p2pService.storeInInbox()
   -> reactionRepo.saveReaction(reaction)
   -> Return (success, MessageReaction)
```

---

## Data Flow: Incoming Remote Reaction

```
1. P2P message arrives on p2pService.messageStream
   -> IncomingMessageRouter routes to reactionStream

2. ReactionListener._onMessage(ChatMessage)
   -> Check blocked sender via contactRepo
   -> Resolve ownMlKemSecretKey
   -> handleIncomingReaction(): decrypt v2 envelope, parse payload
   -> If success: broadcast ReactionChange on incomingReactionChangeStream

3. ConversationWired subscription
   -> On ReactionChange.upserted: upsert into _reactions by senderPeerId
   -> On ReactionChange.removed: remove from _reactions by senderPeerId
   -> setState() -> ConversationScreen rebuilds -> LetterCard shows updated chips
```

---

## Data Flow: Context Menu Actions

### Reply
```
User taps Reply -> Navigator.pop() -> ConversationScreen._handleReplyAction(messageId)
-> widget.onQuoteReply(messageId) -> ConversationWired sets compose area to quote-reply mode
-> _requestComposerFocus()
```

### Edit
```
User taps Edit -> Navigator.pop() -> ConversationScreen._handleEditAction(messageId)
-> widget.onEditMessage(messageId) -> ConversationWired sets compose area to edit mode with message text
-> _requestComposerFocus()
-> On submit: editChatMessage() use case -> sendChatMessage(action: 'edit', messageId) -> encrypt -> send -> persist editedAt
```

### Copy
```
User taps Copy -> Navigator.pop() -> _copyMessageText(text)
-> Clipboard.setData(ClipboardData(text: text)) -> SnackBar confirmation
```

### Delete
```
User taps Delete -> Navigator.pop() -> addPostFrameCallback
-> widget.onDeleteMessage(messageId) -> ConversationWired._handleDeleteAction
-> Shows bottom sheet: "Delete for me" / "Delete for everyone" (if eligible)
-> deleteMessageForMe(): messageRepo.deleteMessage(id), no P2P send
-> deleteMessageForEveryone(): encrypt deletion payload -> race (local/direct/relay/inbox) -> persist tombstone
```

---

## Permission Matrix

| Action | Condition |
|--------|-----------|
| Reply | Always shown |
| Edit | `allowEditAction && onEditMessage != null && !deleted && !incoming && senderPeerId == ownPeerId && text.isNotEmpty && messageId == lastSentMessageId` |
| Copy | `!deleted && text.trim().isNotEmpty` |
| Delete | `onDeleteMessage != null && !deleted && transport != 'system'` |

---

## Key Design Decisions

1. **showDialog with transparent barrier** -- The overlay uses `showDialog(useSafeArea: false, barrierColor: Colors.transparent)` to get route-level lifecycle management (back button, pop) while rendering its own custom backdrop with blur.

2. **Optimistic reactions** -- ConversationWired updates `_reactions` state before the network round-trip completes. On success, the placeholder reaction (with `id: ''`) is swapped for the real persisted one. Failure silently leaves the optimistic update in place until next refresh.

3. **One reaction per user per message** -- The UNIQUE(message_id, sender_peer_id) constraint ensures upsert semantics. The UI groups by emoji and shows count. ConversationWired upserts by `senderPeerId` index.

4. **v2 encrypted-only reactions** -- Both `sendReaction()` and `removeReaction()` require `recipientMlKemPublicKey`. Reactions are never sent as v1 plaintext.

5. **Inline mode for ReactionBar** -- When `inline: true`, ReactionBar renders just the bar content (no backdrop/positioning wrapper). MessageContextOverlay handles all positioning via its Stack layout.

6. **Selected message preview is IgnorePointer** -- The scaled-down card clone is wrapped in `IgnorePointer` so taps pass through to the backdrop dismiss handler.
