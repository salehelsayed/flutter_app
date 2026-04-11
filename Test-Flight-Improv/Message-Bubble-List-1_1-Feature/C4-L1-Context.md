# C4 Model -- Level 1: System Context

## Feature: MessageContextOverlay

**Scope:** The glassmorphic overlay triggered by long-pressing a LetterCard or
MessageBubble in mknoon. Shows a reaction bar (6 preset emojis + full picker),
a scaled-down preview of the selected message, and a context menu with Reply,
Edit, Copy, and Delete actions.

---

## 1. Diagram (PlantUML C4 Notation)

```plantuml
@startuml C4_Context_MessageContextOverlay
!include https://raw.githubusercontent.com/plantuml-stdlib/C4-PlantUML/master/C4_Context.puml

LAYOUT_WITH_LEGEND()

title System Context Diagram -- MessageContextOverlay Feature

Person(user, "Local User", "The mknoon user who long-presses a message to react, reply, edit, copy, or delete.")
Person(remote_peer, "Remote Peer", "The contact on the other end of the conversation who receives reactions, edits, deletions, and reply messages.")

System(mknoon_app, "mknoon Flutter App", "Mobile application containing the conversation UI, overlay presentation, message state management, reaction state, and action dispatch logic.")

System_Ext(p2p_network, "P2P Network / libp2p", "Peer-to-peer transport layer. Direct connections, circuit relay, and inbox store-and-forward. No central server.")
System_Ext(go_bridge, "Go Bridge / Native Layer", "Go native library accessed via MethodChannel. Handles ML-KEM-768 encryption/decryption and Ed25519 payload signing for all outgoing actions.")
System_Ext(sqlcipher_db, "SQLite / SQLCipher", "Encrypted local database storing messages, reactions, media attachments, and deletion tombstones.")
System_Ext(secure_storage, "iOS Keychain / Secure Storage", "Platform secure storage holding identity secrets: private key, ML-KEM secret key, mnemonic.")

Rel(user, mknoon_app, "Long-presses a message", "Touch gesture")
Rel(mknoon_app, user, "Displays overlay: reaction bar, message preview, context menu", "Flutter UI")
Rel(user, mknoon_app, "Taps reaction emoji, Reply, Edit, Copy, or Delete", "Touch gesture")

Rel(mknoon_app, p2p_network, "Sends reaction, reply, edit, or delete message to peer", "libp2p / v2 encrypted envelope")
Rel(p2p_network, remote_peer, "Delivers message to remote peer", "Direct / Relay / Inbox")
Rel(remote_peer, p2p_network, "Sends acknowledgement or own messages back", "libp2p")
Rel(p2p_network, mknoon_app, "Delivers incoming messages and reactions", "libp2p stream")

Rel(mknoon_app, go_bridge, "Encrypts outgoing payload (ML-KEM-768 + AES-256-GCM), signs with Ed25519", "MethodChannel: message.encrypt, payload.sign")
Rel(go_bridge, mknoon_app, "Returns encrypted envelope / signature", "MethodChannel response")

Rel(mknoon_app, sqlcipher_db, "Reads message & reaction state; writes reaction, edit, or deletion result", "sqflite_sqlcipher")
Rel(mknoon_app, secure_storage, "Reads identity private key and ML-KEM secret key for encryption", "FlutterSecureStorage")

@enduml
```

---

## 2. Actors

### Local User (Person)

The mknoon user interacting with the conversation screen. Triggers the
overlay by long-pressing any LetterCard (Orbit 1:1 conversation) or
MessageBubble (Feed/Stack card). Once the overlay is visible, the user can:

| Action | Gesture | Result |
|--------|---------|--------|
| React with preset emoji | Tap one of 6 emojis | Reaction sent to peer, overlay dismissed |
| Open full emoji picker | Tap "+" button | Overlay dismissed, bottom-sheet picker shown |
| Reply | Tap "Reply" in context menu | Overlay dismissed, compose area enters quote mode |
| Edit | Tap "Edit" in context menu | Overlay dismissed, compose area enters edit mode (own recent messages only) |
| Copy | Tap "Copy" in context menu | Message text copied to system clipboard, overlay dismissed |
| Delete | Tap "Delete" in context menu | Deletion flow initiated (for-me or for-everyone), overlay dismissed |
| Dismiss | Tap blurred backdrop or system back gesture | Overlay dismissed, no action taken |

### Remote Peer (Person)

The contact on the other end of the 1:1 conversation. Does not interact with
the overlay directly. Receives the downstream effects of the user's actions:

| Incoming effect | Wire format |
|-----------------|-------------|
| Emoji reaction | v2 encrypted envelope with `type: "reaction"` payload |
| Reply message | v2 encrypted envelope with `quotedMessageId` in payload |
| Edited message | v2 encrypted envelope with `type: "message_edit"` payload |
| Delete-for-everyone | v2 encrypted envelope with `type: "message_deletion"` payload |
| Copy to clipboard | No wire effect -- purely local operation |

---

## 3. Systems

### mknoon Flutter App (Primary System -- inside boundary)

The Flutter mobile application. This is the system being designed. Relevant
subsystems involved in the MessageContextOverlay feature:

| Subsystem | Role in feature |
|-----------|----------------|
| `MessageContextOverlay` widget | Presents the full-screen glassmorphic overlay with backdrop blur, reaction bar, selected message preview, and context menu |
| `ReactionBar` widget | Renders the 6 preset emoji buttons + "+" picker trigger, embedded inside the overlay |
| `ConversationScreen` / `ConversationWired` | Hosts the overlay in Orbit 1:1 surface. `_showMessageContextOverlay()` opens the overlay as a dialog |
| `FeedScreen` / `FeedWired` | Hosts the overlay in Feed/Stack surface. `_showMessageContextOverlay()` opens the overlay as a dialog |
| `LetterCard` / `MessageBubble` | The message card widgets that detect the long-press gesture and provide the anchor rect for overlay positioning |
| Use cases (`send_reaction`, `delete_message`, `send_chat_message`, etc.) | Execute the business logic for each context menu action |
| Repositories (`reaction_repository`, `message_repository`) | Read/write message and reaction state from the encrypted database |

### P2P Network / libp2p (External System)

Peer-to-peer transport layer. All actions that produce a wire message (reaction,
reply, edit, delete-for-everyone) are sent through libp2p. Transport modes:

- **Direct connection** -- peers connected directly
- **Circuit relay** -- peers connected via a relay server
- **Inbox store-and-forward** -- message stored on relay for offline peer

The overlay does not interact with libp2p directly. Actions flow through use
cases, which call the bridge for encryption, then hand the encrypted envelope
to `p2pService.send()`.

### Go Bridge / Native Layer (External System)

The Go native library (`go-mknoon`) accessed via Flutter `MethodChannel`.
The overlay's outgoing actions require encryption before transmission:

| Bridge command | Purpose |
|----------------|---------|
| `message.encrypt` | ML-KEM-768 encapsulation + AES-256-GCM encryption of the action payload |
| `payload.sign` | Ed25519 signature of the encrypted envelope |
| `message.decrypt` | (Receive path) Decrypt incoming reactions/edits/deletions from peer |

The bridge is not called directly by the overlay widget. The call chain is:
overlay action callback --> use case --> bridge helper function --> MethodChannel --> Go native.

### SQLite / SQLCipher (External System)

Encrypted local database (SQLCipher via `sqflite_sqlcipher`). Relevant tables:

| Table | Overlay interaction |
|-------|---------------------|
| `messages` | Read: message text, sender, quoted ID for display. Write: edit updates, deletion tombstones |
| `reactions` | Read: current user reaction (to highlight in bar). Write: new/changed reactions |
| `media_attachments` | Read: determine if message is media-only (to hide Copy action) |

The database encryption key is stored in secure storage, not hardcoded.

### iOS Keychain / Secure Storage (External System)

Platform-level secure storage (`FlutterSecureStorage` on iOS Keychain,
`EncryptedSharedPreferences` on Android). Stores three identity secrets used
during encryption of outgoing overlay actions:

| Key | Usage |
|-----|-------|
| `identity_private_key` | Ed25519 signing of outgoing envelopes |
| `identity_ml_kem_secret_key` | ML-KEM-768 decapsulation (receive path) |
| `db_encryption_key` | Unlocking the SQLCipher database on app start |

The overlay never reads from secure storage directly. Secrets are resolved
by `IdentityRepositoryImpl` and passed to bridge helper functions during
the send/encrypt flow.

---

## 4. Interaction Flows

### Flow A: Long-Press Trigger and Overlay Display

```
User --[long-press gesture]--> LetterCard / MessageBubble
  |
  +--> GestureDetector.onLongPress fires
  +--> _showMessageContextOverlay(message, cardContext)
  |      |
  |      +--> Computes anchorRect from cardContext RenderBox
  |      +--> Reads current reaction for this message from state
  |      +--> Determines which actions to show (Edit: own recent msg, Copy: has text, Delete: allowed)
  |      +--> showDialog() with barrierColor: transparent
  |             |
  |             +--> MessageContextOverlay widget
  |                    |
  |                    +--> BackdropFilter blur (sigma 18) over full screen
  |                    +--> Selected message preview (scaled-down, non-interactive)
  |                    +--> ReactionBar (6 emojis + "+" button)
  |                    +--> _ContextMenuCard (Reply, Edit?, Copy?, Delete?)
  |
  +--> User sees glassmorphic overlay
```

### Flow B: Reaction Selected

```
User --[tap emoji]--> ReactionBar.onReactionSelected(emoji)
  |
  +--> Overlay dismissed (Navigator.pop)
  +--> onReactionSelected callback in Wired layer
  |      |
  |      +--> sendReactionUseCase(messageId, emoji, contactPeerId)
  |             |
  |             +--> reactionRepository.saveReaction() --> SQLCipher
  |             +--> Bridge: message.encrypt(reactionPayload) --> Go native
  |             +--> p2pService.send(encryptedEnvelope) --> libp2p --> Remote Peer
```

### Flow C: Reply Action

```
User --[tap Reply]--> _ContextMenuCard.onReplyTap
  |
  +--> Overlay dismissed
  +--> onQuoteReply(messageId) in Wired layer
  |      |
  |      +--> Sets _activeQuoteMessageId state
  |      +--> Compose area shows quoted-message preview bar
  |
  +--> User types and sends reply
         |
         +--> sendChatMessageUseCase(text, quotedMessageId: messageId)
                |
                +--> messageRepository.saveMessage() --> SQLCipher
                +--> Bridge: message.encrypt(payload) --> Go native
                +--> p2pService.send(encryptedEnvelope) --> libp2p --> Remote Peer
```

### Flow D: Copy Action

```
User --[tap Copy]--> _ContextMenuCard.onCopyTap
  |
  +--> Overlay dismissed
  +--> Clipboard.setData(ClipboardData(text: message.text))
  |
  +--> (Purely local -- no wire message, no DB write, no bridge call)
```

### Flow E: Edit Action

```
User --[tap Edit]--> _ContextMenuCard.onEditTap
  |
  +--> Overlay dismissed
  +--> onEditMessage(messageId) in Wired layer
  |      |
  |      +--> Sets _editingMessageId state
  |      +--> Compose area pre-fills with original message text
  |
  +--> User modifies text and sends
         |
         +--> sendChatMessageUseCase(text, editedMessageId: messageId)
                |
                +--> messageRepository.updateMessage() --> SQLCipher
                +--> Bridge: message.encrypt(editPayload) --> Go native
                +--> p2pService.send(encryptedEnvelope) --> libp2p --> Remote Peer
```

### Flow F: Delete Action

```
User --[tap Delete]--> _ContextMenuCard.onDeleteTap
  |
  +--> Overlay dismissed
  +--> onDeleteMessage(messageId) in Wired layer
  |      |
  |      +--> Shows confirmation dialog (delete-for-me vs delete-for-everyone)
  |      |
  |      +--> [Delete for me]
  |      |      +--> messageRepository.softDelete(messageId) --> SQLCipher
  |      |      +--> (No wire message)
  |      |
  |      +--> [Delete for everyone]
  |             +--> deleteMessageUseCase(messageId, forEveryone: true)
  |                    |
  |                    +--> messageRepository.softDelete(messageId) --> SQLCipher
  |                    +--> Bridge: message.encrypt(deletionPayload) --> Go native
  |                    +--> p2pService.send(encryptedEnvelope) --> libp2p --> Remote Peer
```

### Flow G: Dismiss (No Action)

```
User --[tap backdrop / back gesture]--> GestureDetector.onTap / Navigator.pop
  |
  +--> Overlay dismissed
  +--> (No side effects)
```

---

## 5. System Boundary Summary

```
+------------------------------------------------------------------+
|                    mknoon Flutter App                             |
|                                                                  |
|  +--------------------+    +--------------------+                |
|  | ConversationScreen |    |    FeedScreen       |               |
|  |  (Orbit 1:1)       |    |  (Feed/Stack)       |               |
|  +--------+-----------+    +--------+------------+               |
|           |                         |                            |
|           +------+------------------+                            |
|                  |                                                |
|                  v                                                |
|     +---------------------------+                                |
|     | MessageContextOverlay     |                                |
|     |  - BackdropFilter blur    |                                |
|     |  - ReactionBar (6+picker) |                                |
|     |  - Selected message view  |                                |
|     |  - Context menu card      |                                |
|     |    (Reply/Edit/Copy/Del)  |                                |
|     +---------------------------+                                |
|         |        |        |        |                             |
|    Reaction   Reply    Edit     Delete      Copy                 |
|         |        |        |        |          |                  |
|         v        v        v        v          v                  |
|     +----------+   +----------+   +----------+  Clipboard       |
|     | Use Cases|   | Use Cases|   | Use Cases|  (local only)    |
|     +----+-----+   +----+-----+   +----+-----+                  |
|          |              |              |                          |
+------------------------------------------------------------------+
           |              |              |
           v              v              v
   +---------------+ +-------------+ +------------------+
   | Go Bridge     | | SQLCipher   | | Secure Storage   |
   | (Encrypt/Sign)| | (Messages,  | | (Private key,    |
   +-------+-------+ | Reactions)  | | ML-KEM secret)   |
           |          +------+------+ +------------------+
           v                 |
   +---------------+         |
   | P2P Network   |<--------+  (DB key from secure storage)
   | (libp2p)      |
   +-------+-------+
           |
           v
   +---------------+
   | Remote Peer   |
   +---------------+
```

---

## 6. Key Constraints

| Constraint | Detail |
|------------|--------|
| No central server | All message actions (reactions, replies, edits, deletions) travel peer-to-peer via libp2p |
| End-to-end encryption | Every outgoing wire payload is encrypted with ML-KEM-768 + AES-256-GCM before transmission |
| Copy is local-only | Copying message text to clipboard produces no wire traffic and no database writes |
| Edit restricted to own messages | The Edit action only appears for the user's own recently-sent messages |
| Delete has two modes | Delete-for-me is local (DB-only); delete-for-everyone sends a tombstone to the peer |
| Overlay is a dialog | Presented via `showDialog()` with transparent barrier -- the overlay widget itself renders the backdrop blur |
| Two host surfaces | The same `MessageContextOverlay` widget is reused in both `ConversationScreen` (1:1) and `FeedScreen` (Feed/Stack) |
| Anchor-based positioning | The overlay positions the reaction bar, message preview, and context menu relative to the long-pressed card's screen coordinates, clamped to viewport bounds |
