# C4 Model -- Reactions Action (MessageContextOverlay)

**Scope:** The complete Reactions subsystem of the MessageContextOverlay feature.
When a user long-presses a non-deleted `LetterCard`, the overlay appears with a
`ReactionBar` showing 6 preset emojis + a "+" button for the full emoji picker.
Presentation widgets only emit callbacks; add/replace/toggle-off behavior lives
in `ConversationWired`. Tapping the same emoji again toggles it off (removes
the reaction). One reaction per user per message (UNIQUE constraint on
`message_id + sender_peer_id`).

---

## Level 1 -- System Context

### 1.1 PlantUML C4 Context Diagram

```plantuml
@startuml C4_Context_Reactions
!include https://raw.githubusercontent.com/plantuml-stdlib/C4-PlantUML/master/C4_Context.puml

LAYOUT_WITH_LEGEND()

title System Context Diagram -- Reactions (MessageContextOverlay)

Person(local_user, "Local User", "Long-presses a non-deleted LetterCard to open the overlay, taps an emoji to react, taps same emoji to toggle off.")
Person(remote_peer, "Remote Peer", "Receives encrypted reaction payloads via P2P. Their app persists and renders the reaction on the matching message.")

System(mknoon_app, "mknoon Flutter App", "Houses overlay UI, reaction state, optimistic updates in ConversationWired, ReactionListener, sendReaction/removeReaction use cases, and ReactionRepository.")

System_Ext(p2p_network, "P2P Network / libp2p", "Transports reaction wire messages (v2 encrypted envelope). The app calls sendMessage(); when that returns false it attempts storeInInbox().")
System_Ext(go_bridge, "Go Bridge / Native Layer", "Encrypts reaction payload using ML-KEM-768 + AES-256-GCM via MethodChannel command 'message.encrypt'. Decrypts incoming reactions via 'message.decrypt'.")
System_Ext(sqlcipher_db, "SQLCipher DB", "Encrypted local database. Stores 'message_reactions' table with UNIQUE(message_id, sender_peer_id) constraint.")
System_Ext(secure_storage, "SecureKeyStore / flutter_secure_storage", "Holds identity secrets. On iOS this is Keychain-backed; on Android it is EncryptedSharedPreferences-backed.")

Rel(local_user, mknoon_app, "Long-press non-deleted message -> tap emoji", "Touch gesture")
Rel(mknoon_app, local_user, "Shows overlay with ReactionBar, inline reaction chips on LetterCard", "Flutter UI")

Rel(mknoon_app, go_bridge, "Encrypt reaction payload (ML-KEM-768 + AES-256-GCM)", "MethodChannel: message.encrypt")
Rel(go_bridge, mknoon_app, "Returns {kem, ciphertext, nonce}", "MethodChannel response")
Rel(mknoon_app, go_bridge, "Decrypt incoming reaction", "MethodChannel: message.decrypt")

Rel(mknoon_app, p2p_network, "Send v2 encrypted reaction envelope; if sendMessage() returns false, attempt storeInInbox()", "P2PService")
Rel(p2p_network, remote_peer, "Delivers encrypted reaction when the chosen transport succeeds", "Runtime transport path")
Rel(remote_peer, p2p_network, "Sends reaction back", "libp2p stream")
Rel(p2p_network, mknoon_app, "Delivers incoming reaction messages", "P2PService.messageStream")

Rel(mknoon_app, sqlcipher_db, "INSERT OR REPLACE / DELETE reaction rows", "sqflite_sqlcipher")
Rel(mknoon_app, secure_storage, "Load own ML-KEM secret key via IdentityRepository.loadIdentity()", "SecureKeyStore")

@enduml
```

### 1.2 Actors

| Actor | Role | Interactions |
|---|---|---|
| **Local User** | Initiates reactions by long-pressing a non-deleted LetterCard then tapping an emoji on the ReactionBar. Taps same emoji to toggle off. Can also tap "+" for full emoji picker. | Gesture -> overlay -> emoji tap -> optimistic UI update -> encrypted P2P send |
| **Remote Peer** | Receives reaction payloads over P2P. Their local app decrypts, persists, and renders the reaction. Can also send reactions back. | Receives v2 encrypted envelope via libp2p |

### 1.3 External Systems

| System | Protocol | Purpose |
|---|---|---|
| **P2P Network / libp2p** | `P2PService.sendMessage(...)` plus optional `storeInInbox(...)` attempt | Transports `message_reaction` type envelopes between peers |
| **Go Bridge** | MethodChannel (`message.encrypt`, `message.decrypt`) | ML-KEM-768 key encapsulation + AES-256-GCM symmetric encryption/decryption |
| **SQLCipher DB** | sqflite_sqlcipher | Persists `message_reactions` table with UNIQUE constraint enforcement |
| **Secure Storage** | `SecureKeyStore` via `flutter_secure_storage` | Stores `identity_ml_kem_secret_key` used by `IdentityRepository.loadIdentity()` for decryption |

### 1.4 Trust Boundaries

1. **Device boundary**: Reaction rows are stored in SQLCipher and reaction transport uses the v2 encrypted envelope. v1 plaintext reaction envelopes are rejected on receive.
2. **P2P boundary**: The code performs two separate trust checks: `ReactionListener` rejects blocked `message.from` contacts, and `handleIncomingReaction()` only accepts decrypted `payload.senderPeerId` values that exist in contacts. The code does not bind `message.from`, top-level envelope `senderPeerId`, and decrypted `payload.senderPeerId` together.
3. **Crypto boundary**: The Go bridge performs crypto operations. Dart obtains the ML-KEM secret key through `IdentityRepository.loadIdentity()` and passes it into `callDecryptMessage(...)`.

---

## Level 2 -- Containers

### 2.1 Mermaid Container Diagram

```mermaid
graph TB
    subgraph "mknoon Flutter App"
        subgraph "Presentation Layer"
            MCO["MessageContextOverlay"]
            RB["ReactionBar"]
            FEP["showFullEmojiPicker()"]
            LC["LetterCard"]
            RD["ReactionDisplay (standalone)"]
            CS["ConversationScreen"]
            CW["ConversationWired"]
        end

        subgraph "Application Layer"
            SR["sendReaction()"]
            RR["removeReaction()"]
            LR["loadReactionsForConversation()"]
            RL["ReactionListener"]
            HIR["handleIncomingReaction()"]
        end

        subgraph "Domain Layer"
            MR["MessageReaction"]
            RC["ReactionChange"]
            RP["ReactionPayload"]
            RRepo["ReactionRepository"]
        end

        subgraph "Infrastructure Layer"
            RRI["ReactionRepositoryImpl"]
            DBH["reactions_db_helpers"]
            IMR["IncomingMessageRouter"]
        end
    end

    subgraph "External Systems"
        P2P["P2PService"]
        BR["Bridge / GoBridgeClient"]
        DB["SQLCipher DB"]
        SS["IdentityRepository.loadIdentity() / SecureKeyStore"]
    end

    MCO --> RB
    MCO -.-> FEP
    CS --> MCO
    CS --> LC
    CW --> CS
    CW --> SR
    CW --> RR
    CW --> LR
    CW --> RL

    RL --> HIR
    HIR --> RP
    SR --> RP
    RR --> RP

    SR --> BR
    RR --> BR
    HIR --> BR
    SR --> P2P
    RR --> P2P
    SR --> RRepo
    RR --> RRepo
    LR --> RRepo
    HIR --> RRepo

    RRepo -.-> RRI
    RRI --> DBH
    DBH --> DB

    RL --> IMR
    IMR --> P2P

    RL --> SS

    RL -.->|"ReactionChange stream"| CW
```

### 2.2 Container Details

#### Presentation Containers

| Container | Type | File | Responsibility |
|---|---|---|---|
| **MessageContextOverlay** | StatelessWidget | `presentation/widgets/message_context_overlay.dart` | Full-screen overlay: backdrop blur, positioned ReactionBar above anchor, selected message preview, context menu below. Forwards `currentEmoji` into `ReactionBar`; visible highlight exists only when that emoji is one of the 6 presets. |
| **ReactionBar** | StatefulWidget | `presentation/widgets/reaction_bar.dart` | 6 preset emojis + "+" button. Scale animation 0.8->1.0 (200ms, easeOut). Glassmorphic styling. `inline: true` mode is what the overlay uses. |
| **showFullEmojiPicker()** | Top-level function (internal `_FullEmojiPicker` StatefulWidget is private) | `presentation/widgets/full_emoji_picker.dart` | Modal bottom sheet with 7 categories (Smileys, People, Animals, Food, Travel, Objects, Symbols). GridView of emojis. Returns `Future<String?>` via `showModalBottomSheet<String>`. |
| **LetterCard** | StatelessWidget | `presentation/widgets/letter_card.dart` | Full-width glassmorphic card. Renders inline reaction chips in footer via `_buildReactionChipWidgets()`. Groups by emoji, shows count, own-reaction teal border. |
| **ReactionDisplay** | StatelessWidget | `presentation/widgets/reaction_display.dart` | Standalone reaction chip renderer. Groups reactions by emoji and highlights own reactions with teal border RGBA(78,205,196,0.30). It is currently not used by the active `ConversationScreen -> LetterCard` path. |
| **ConversationScreen** | StatefulWidget | `presentation/screens/conversation_screen.dart` | Screen-level overlay orchestration. `_showMessageContextOverlay()` resolves `ownReaction` from `widget.reactions[message.id]`, computes action availability, shows the dialog, and passes `message.id` back through callbacks. |
| **ConversationWired** | StatefulWidget | `presentation/screens/conversation_wired.dart` | State management. Owns `_reactions: Map<String, List<MessageReaction>>`. `_onReactionSelected()` implements optimistic update + toggle logic with no rollback on failure. `_loadReactions()` is only called after `_loadInitialPage()`. |

#### Application Containers

| Container | Type | File | Signature |
|---|---|---|---|
| **sendReaction()** | Top-level function | `application/send_reaction_use_case.dart` | `Future<(SendReactionResult, MessageReaction?)> sendReaction({p2pService, bridge, reactionRepo, targetPeerId, messageId, emoji, senderPeerId, recipientMlKemPublicKey})` |
| **removeReaction()** | Top-level function | `application/remove_reaction_use_case.dart` | `Future<RemoveReactionResult> removeReaction({p2pService, bridge, reactionRepo, targetPeerId, messageId, emoji, senderPeerId, recipientMlKemPublicKey})` |
| **loadReactionsForConversation()** | Top-level function | `application/load_reactions_use_case.dart` | `Future<Map<String, List<MessageReaction>>> loadReactionsForConversation({reactionRepo, messageIds})` |
| **ReactionListener** | Class with streams | `application/reaction_listener.dart` | Subscribes to `reactionStream` (from IncomingMessageRouter), checks whether `message.from` is blocked, resolves the local ML-KEM secret via `getOwnMlKemSecretKey()`, calls `handleIncomingReaction()`, and broadcasts `ReactionChange` on `incomingReactionChangeStream`. |
| **handleIncomingReaction()** | Top-level function | `application/handle_incoming_reaction_use_case.dart` | `Future<(HandleReactionResult, ReactionChange?)> handleIncomingReaction({message, reactionRepo, contactRepo, bridge, ownMlKemSecretKey})` |

#### Domain Containers

| Container | Type | File | Fields / Methods |
|---|---|---|---|
| **MessageReaction** | Model class | `domain/models/message_reaction.dart` | `id`, `messageId`, `emoji`, `senderPeerId`, `timestamp`, `createdAt`. Methods: `fromMap`/`toMap` (DB), `fromJson`/`toJson` (wire), `copyWith`. Equality by `id`. |
| **ReactionChange** | Algebraic type | `domain/models/reaction_change.dart` | `type` (upserted/removed), `messageId`, `senderPeerId`, `reaction?`. Named constructors: `ReactionChange.upsert(reaction)`, `ReactionChange.removed(messageId:, senderPeerId:)`. |
| **ReactionPayload** | Wire-format model | `domain/models/reaction_payload.dart` | `id`, `messageId`, `emoji`, `action`, `senderPeerId`, `timestamp`. Methods: `fromJson`, `toJson`, `toInnerJson`, `fromDecryptedJson`, `buildEncryptedEnvelope`, `parseEncryptedEnvelope`, `toMessageReaction`. The receive path treats exact `'remove'` specially; any other non-null action currently behaves like add. |
| **ReactionRepository** | Abstract interface | `domain/repositories/reaction_repository.dart` | `saveReaction`, `getReactionsForMessage`, `getReactionsForMessages`, `removeReaction`, `deleteReactionsForMessage`, `deleteReactionsForContact` |

#### Infrastructure Containers

| Container | Type | File | Details |
|---|---|---|---|
| **ReactionRepositoryImpl** | Concrete impl | `domain/repositories/reaction_repository_impl.dart` | Constructor-injected DB helper functions: `dbInsertReaction`, `dbLoadReactionsForMessage`, `dbLoadReactionsForMessages`, `dbDeleteReaction`, `dbDeleteReactionsForMessage`, `dbDeleteReactionsForContact`. Uses `emitFlowEvent()` in `saveReaction()` only (start/success/error); other operations are plain pass-through delegations. |
| **reactions_db_helpers** | Plain functions | `core/database/helpers/reactions_db_helpers.dart` | 6 functions taking `Database db` + args. Uses `ConflictAlgorithm.replace` for upsert. Parameterized queries throughout. |
| **IncomingMessageRouter** | Router class | `core/services/incoming_message_router.dart` | Parses JSON `type` field from P2P messages. Routes `message_reaction` type to `_reactionController` stream. |

---

## Level 3 -- Components

### 3.1 Component Diagram (Mermaid)

```mermaid
graph TD
    subgraph "ConversationWired (State Manager)"
        CW_state["_reactions: Map<String, List<MessageReaction>>"]
        CW_onReaction["_onReactionSelected(messageId, emoji)"]
        CW_startListen["_startListeningForReactions()"]
        CW_loadReact["_loadReactions(initialPageMessages)"]
        CW_onIncoming["_onIncomingReactionChange(change)"]
    end

    subgraph "Overlay Presentation"
        CS_show["ConversationScreen._showMessageContextOverlay()"]
        MCO_build["MessageContextOverlay.build()"]
        RB_build["ReactionBar.build()"]
        RB_anim["AnimationController(200ms) + ScaleTransition"]
        RB_emoji["_emojiButton(emoji) x6"]
        RB_plus["_plusButton()"]
        FEP_show["showFullEmojiPicker()"]
    end

    subgraph "Inline Presentation"
        LC_chips["LetterCard._buildReactionChipWidgets()"]
        RD_build["ReactionDisplay.build()"]
    end

    subgraph "Send Path"
        SR_check["1. Check p2pService.currentState.isStarted"]
        SR_payload["2. Build ReactionPayload(action: 'add')"]
        SR_encrypt["3. callEncryptMessage(bridge, recipientMlKemPublicKey, innerJson)"]
        SR_envelope["4. ReactionPayload.buildEncryptedEnvelope(kem, ciphertext, nonce)"]
        SR_send["5. p2pService.sendMessage || attempt storeInInbox (bool ignored)"]
        SR_persist["6. reactionRepo.saveReaction(reaction)"]
    end

    subgraph "Remove Path"
        RR_check["1. Check node started"]
        RR_payload["2. Build ReactionPayload(action: 'remove')"]
        RR_encrypt["3. callEncryptMessage(...)"]
        RR_envelope["4. buildEncryptedEnvelope(...)"]
        RR_send["5. sendMessage || attempt storeInInbox (bool ignored)"]
        RR_delete["6. reactionRepo.removeReaction(messageId, senderPeerId)"]
    end

    subgraph "Receive Path"
        IMR_route["IncomingMessageRouter._route()"]
        RL_onMsg["ReactionListener._onMessage()"]
        RL_block["Check blocked via contactRepo using message.from"]
        HIR_v2["parseEncryptedEnvelope()"]
        HIR_decrypt["callDecryptMessage(bridge, ownMlKemSecretKey, kem, ciphertext, nonce)"]
        HIR_parse["fromDecryptedJson(plaintext)"]
        HIR_validate["Validate payload.senderPeerId is a known contact"]
        HIR_action["action=='add' -> saveReaction | action=='remove' -> removeReaction"]
        RL_broadcast["Broadcast ReactionChange on incomingReactionChangeStream"]
    end

    subgraph "Database Layer"
        DB_insert["dbInsertReaction(db, row) -- REPLACE conflict"]
        DB_load["dbLoadReactionsForMessage(db, messageId)"]
        DB_load_batch["dbLoadReactionsForMessages(db, messageIds)"]
        DB_delete["dbDeleteReaction(db, messageId, senderPeerId)"]
        DB_delete_msg["dbDeleteReactionsForMessage(db, messageId)"]
        DB_delete_contact["dbDeleteReactionsForContact(db, contactPeerId)"]
    end

    CW_onReaction --> SR_check
    CW_onReaction --> RR_check
    CW_startListen --> RL_broadcast
    CW_loadReact --> DB_load_batch

    CS_show --> MCO_build
    MCO_build --> RB_build
    RB_build --> RB_anim
    RB_build --> RB_emoji
    RB_build --> RB_plus
    RB_plus --> FEP_show

    SR_check --> SR_payload --> SR_encrypt --> SR_envelope --> SR_send --> SR_persist
    RR_check --> RR_payload --> RR_encrypt --> RR_envelope --> RR_send --> RR_delete

    IMR_route --> RL_onMsg --> RL_block --> HIR_v2 --> HIR_decrypt --> HIR_parse --> HIR_validate --> HIR_action --> RL_broadcast
    RL_broadcast --> CW_onIncoming --> CW_state
```

### 3.2 ConversationWired._onReactionSelected Flow

```dart
// File: lib/features/conversation/presentation/screens/conversation_wired.dart
// Lines: 2758-2840
```

**Step-by-step:**

1. **Resolve identity**: `_identity` must be non-null. Check `reactionRepo` and `bridge` availability.
2. **Find existing ownReaction**: Filter `_reactions[messageId]` for entries where `senderPeerId == identity.peerId`.
3. **Toggle off** (same emoji as existing):
   - Optimistic `setState`: remove own reaction from `_reactions[messageId]` list.
   - Call `removeReaction()` use case (async, fire-and-forget from UI perspective).
   - Early return.
4. **Add/replace** (new emoji or no existing reaction):
   - Create optimistic `MessageReaction(id: '', ...)` placeholder.
   - Optimistic `setState`: insert or replace own reaction in list by `senderPeerId`.
   - Call `sendReaction()` use case.
   - On success: `setState` replacing placeholder (id='') with real `MessageReaction` from server response.

**Notes:**

- The toggle/add/remove logic above lives in `ConversationWired`, not in `ReactionBar`, `LetterCard`, or `ConversationScreen`.
- There is no UI rollback when `removeReaction()` fails.
- Add failures leave the optimistic placeholder or optimistic replacement in `_reactions` until some later reload or incoming change overwrites it.

```mermaid
stateDiagram-v2
    [*] --> CheckIdentity
    CheckIdentity --> FindExisting: identity != null
    CheckIdentity --> [*]: identity == null

    FindExisting --> ToggleOff: ownReaction.emoji == tappedEmoji
    FindExisting --> AddReplace: ownReaction == null OR ownReaction.emoji != tappedEmoji

    ToggleOff --> OptimisticRemove: setState remove from list
    OptimisticRemove --> CallRemoveUseCase: removeReaction()
    CallRemoveUseCase --> [*]

    AddReplace --> OptimisticAdd: setState with placeholder (id='')
    OptimisticAdd --> CallSendUseCase: sendReaction()
    CallSendUseCase --> ReplaceWithReal: success + reaction != null
    CallSendUseCase --> [*]: failure (placeholder remains)
    ReplaceWithReal --> [*]
```

### 3.3 ReactionListener Incoming Flow

```mermaid
sequenceDiagram
    participant P2P as P2PService.messageStream
    participant IMR as IncomingMessageRouter
    participant RL as ReactionListener
    participant CR as ContactRepository
    participant IDR as IdentityRepository
    participant HIR as handleIncomingReaction()
    participant BR as Bridge (Go)
    participant RRepo as ReactionRepository
    participant CW as ConversationWired

    P2P->>IMR: ChatMessage (raw)
    IMR->>IMR: jsonDecode, check type == 'message_reaction'
    IMR->>RL: ChatMessage via reactionStream

    RL->>CR: getContact(message.from)
    CR-->>RL: contact (check isBlocked)
    alt message.from is blocked
        RL->>RL: REJECT, emit REACTION_LISTENER_BLOCKED_REJECT
    else Sender is not blocked
        RL->>IDR: getOwnMlKemSecretKey()
        IDR-->>RL: ownMlKemSecretKey (via loadIdentity / secure storage)

        RL->>HIR: handleIncomingReaction(message, ownMlKemSecretKey)

        HIR->>HIR: parseEncryptedEnvelope(content)
        alt v2 envelope found
            HIR->>BR: callDecryptMessage(ownMlKemSecretKey, kem, ciphertext, nonce)
            BR-->>HIR: {ok: true, plaintext: innerJson}
            HIR->>HIR: fromDecryptedJson(plaintext) -> ReactionPayload
            HIR->>CR: getContact(payload.senderPeerId)
            CR-->>HIR: contact (validate known payload sender)
            alt action == 'add'
                HIR->>RRepo: saveReaction(payload.toMessageReaction())
                HIR-->>RL: (success, ReactionChange.upsert(reaction))
            else action == 'remove'
                HIR->>RRepo: removeReaction(messageId, senderPeerId)
                HIR-->>RL: (success, ReactionChange.removed(...))
            end
        else v1 or not a reaction
            HIR-->>RL: (notReaction, null)
        end

        RL->>RL: Broadcast ReactionChange on incomingReactionChangeStream

        CW->>CW: _reactionSubscription receives ReactionChange
        CW->>CW: Filter: only process if messageId exists in _messages
        CW->>CW: _onIncomingReactionChange(change)
        alt change.type == removed
            CW->>CW: removeWhere senderPeerId in list
        else change.type == upserted
            CW->>CW: find by senderPeerId, replace or append
        end
        CW->>CW: setState(_reactions = updated map)
    end
```

### 3.4 Component Constructor Params & Key Methods

#### MessageContextOverlay

```
Constructor:
  anchorRect: Rect           -- RenderBox position of the long-pressed LetterCard
  selectedMessage: Widget?   -- Cloned LetterCard rendered in overlay
  currentEmoji: String?      -- Existing own reaction emoji forwarded into ReactionBar
  showEditAction: bool
  showCopyAction: bool
  showDeleteAction: bool
  onDismiss: VoidCallback
  onReactionSelected: void Function(String emoji)
  onPlusTap: VoidCallback
  onReplyTap: VoidCallback
  onEditTap: VoidCallback?
  onCopyTap: VoidCallback?
  onDeleteTap: VoidCallback?

Key methods:
  build() -- Computes reactionBarTop, menuTop with viewport clamping.
             Stack: backdrop GestureDetector + selectedMessage + inline ReactionBar + ContextMenuCard
```

#### ReactionBar

```
Constructor:
  currentEmoji: String?              -- Emoji to highlight if it matches one of kPresetEmojis
  onReactionSelected: Function(emoji) -- Called when preset emoji tapped
  onPlusTap: VoidCallback            -- Opens full picker
  onDismiss: VoidCallback            -- Used only by standalone non-inline mode
  anchorY: double?                   -- Vertical position hint for standalone non-inline mode
  inline: bool = false               -- true when embedded in overlay (no dismiss wrapper)

Internal state:
  AnimationController _controller    -- 200ms duration
  Animation<double> _scaleAnimation  -- Tween(0.8, 1.0) + CurvedAnimation(easeOut)

Key methods:
  _emojiButton(emoji) -- 44x44 container, highlight color if selected
  _plusButton()       -- 44x44 container with add icon
```

#### ReactionListener

```
Constructor:
  reactionStream: Stream<ChatMessage>           -- From IncomingMessageRouter
  reactionRepo: ReactionRepository
  contactRepo: ContactRepository
  bridge: Bridge
  getOwnMlKemSecretKey: Future<String?> Function()

Internal state:
  StreamSubscription<ChatMessage>? _subscription
  StreamController<MessageReaction> _reactionController      -- emits upserts only
  StreamController<ReactionChange> _reactionChangeController -- primary stream

Key methods:
  start()   -- Begin listening
  stop()    -- Cancel subscription
  dispose() -- Stop + close controllers
  _onMessage(ChatMessage) -- Check blocked message.from, resolve own key, decrypt, broadcast change
```

#### ReactionRepositoryImpl

```
Constructor (6 injected DB helper functions):
  dbInsertReaction: Future<void> Function(Map<String, Object?> row)
  dbLoadReactionsForMessage: Future<List<Map<String, Object?>>> Function(String)
  dbLoadReactionsForMessages: Future<List<Map<String, Object?>>> Function(List<String>)
  dbDeleteReaction: Future<int> Function(String messageId, String senderPeerId)
  dbDeleteReactionsForMessage: Future<int> Function(String messageId)
  dbDeleteReactionsForContact: Future<int> Function(String contactPeerId)
```

#### ConversationWired (Reaction State)

```
Internal state:
  Map<String, List<MessageReaction>> _reactions = {}
  StreamSubscription<ReactionChange>? _reactionSubscription

Key methods:
  _startListeningForReactions()          -- Subscribes to ReactionListener, filters by conversation
  _onIncomingReactionChange(change)      -- Upsert/remove in _reactions map by senderPeerId
  _loadReactions(messages)               -- Batch-load via loadReactionsForConversation() after _loadInitialPage() only
  _onReactionSelected(messageId, emoji)  -- Toggle logic with optimistic updates and no rollback
```

---

## Level 4 -- Code

### 4.1 ReactionBar Widget Tree

```mermaid
graph TD
    STA["ScaleTransition (scale: _scaleAnimation)"]
    CR["ClipRRect (borderRadius: 28)"]
    BF["BackdropFilter (blur: 24x24)"]
    CON["Container (RGBA(18,20,28,0.95), border RGBA(255,255,255,0.10), padding H:12 V:8)"]
    ROW["Row (mainAxisSize: min)"]
    E1["_emojiButton('thumbs up')"]
    E2["_emojiButton('red heart')"]
    E3["_emojiButton('face with tears of joy')"]
    E4["_emojiButton('face with open mouth')"]
    E5["_emojiButton('crying face')"]
    E6["_emojiButton('folded hands')"]
    PB["_plusButton()"]

    STA --> CR --> BF --> CON --> ROW
    ROW --> E1
    ROW --> E2
    ROW --> E3
    ROW --> E4
    ROW --> E5
    ROW --> E6
    ROW --> PB
```

**Preset emojis constant:**

```dart
const kPresetEmojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];
```

### 4.2 ReactionBar Animation

```dart
// AnimationController + ScaleTransition
_controller = AnimationController(
  duration: const Duration(milliseconds: 200),
  vsync: this,
);
_scaleAnimation = Tween<double>(
  begin: 0.8,
  end: 1.0,
).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
_controller.forward(); // Starts on initState
```

The animation is applied via `ScaleTransition(scale: _scaleAnimation, child: ...)` wrapping the entire ClipRRect bar. This creates a subtle pop-in effect when the overlay appears.

### 4.3 Emoji Button

```dart
Widget _emojiButton(String emoji) {
  final isSelected = widget.currentEmoji == emoji;
  return GestureDetector(
    onTap: () => widget.onReactionSelected(emoji),
    child: Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isSelected
            ? const Color.fromRGBO(78, 205, 196, 0.20)  // Teal highlight
            : Colors.transparent,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Text(emoji, style: const TextStyle(fontSize: 24)),
    ),
  );
}
```

### 4.4 Plus Button

```dart
Widget _plusButton() {
  return GestureDetector(
    onTap: widget.onPlusTap,
    child: Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color.fromRGBO(255, 255, 255, 0.06),
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Icon(
        Icons.add,
        size: 20,
        color: Color.fromRGBO(255, 255, 255, 0.5),
      ),
    ),
  );
}
```

### 4.5 FullEmojiPicker

Triggered by the "+" button tap. `ConversationScreen._showFullPicker(messageId)` calls:

```dart
void _showFullPicker(String messageId) async {
  final emoji = await showFullEmojiPicker(context);
  if (emoji != null) {
    widget.onReactionSelected?.call(messageId, emoji);
  }
}
```

`showFullEmojiPicker()` returns `Future<String?>` via `showModalBottomSheet<String>`. Categories: Smileys (48), People (32), Animals (32), Food (32), Travel (24), Objects (24), Symbols (32). 8-column GridView. Selection pops the sheet with the emoji string.

If the user chooses a non-preset emoji from the full picker, the next overlay still forwards that emoji as `currentEmoji`, but `ReactionBar` only renders the 6 preset buttons, so no quick-reaction button shows a selected fill for that case.

### 4.6 Inline Reaction Chips on LetterCard

```dart
// LetterCard._buildReactionChipWidgets()
List<Widget> _buildReactionChipWidgets() {
  final groups = <String, List<MessageReaction>>{};
  for (final r in reactions) {
    groups.putIfAbsent(r.emoji, () => []).add(r);
  }
  return groups.entries.map((entry) {
    final emoji = entry.key;
    final list = entry.value;
    final isOwn = ownPeerId != null &&
        list.any((r) => r.senderPeerId == ownPeerId);
    return GestureDetector(
      onTap: onReactionTap != null ? () => onReactionTap!(emoji) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color.fromRGBO(255, 255, 255, 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isOwn
                ? const Color.fromRGBO(78, 205, 196, 0.30) // Teal border
                : Colors.transparent,
          ),
        ),
        child: Text(
          list.length > 1 ? '$emoji ${list.length}' : emoji,
          style: const TextStyle(fontSize: 14),
        ),
      ),
    );
  }).toList();
}
```

Rendered inside the LetterCard's footer area as a `Wrap(spacing: 6, runSpacing: 4, ...)`. This path does not instantiate `ReactionDisplay`; `LetterCard` renders the chips directly. Tapping an inline chip invokes `onReactionTap(emoji)`, and `ConversationScreen` then forwards that to `widget.onReactionSelected(message.id, emoji)` -- the same upstream toggle logic used by the overlay path.

### 4.7 Wire Format -- Reaction Payload

#### v1 Envelope (Rejected on receive -- encryption required)

```json
{
  "type": "message_reaction",
  "version": "1",
  "payload": {
    "id": "uuid-v4",
    "messageId": "target-message-uuid",
    "emoji": "👍",
    "action": "add",
    "senderPeerId": "12D3KooW...",
    "timestamp": "2026-04-09T12:00:00.000Z"
  }
}
```

#### v2 Encrypted Envelope (Active)

```json
{
  "type": "message_reaction",
  "version": "2",
  "senderPeerId": "12D3KooW...",
  "encrypted": {
    "kem": "<base64 ML-KEM-768 encapsulated key>",
    "ciphertext": "<base64 AES-256-GCM encrypted inner payload>",
    "nonce": "<base64 AES-256-GCM nonce>"
  }
}
```

#### Inner Payload (Encrypted as plaintext)

```json
{
  "id": "uuid-v4",
  "messageId": "target-message-uuid",
  "emoji": "👍",
  "action": "add",
  "senderPeerId": "12D3KooW...",
  "timestamp": "2026-04-09T12:00:00.000Z"
}
```

The `action` field is intended to be `"add"` or `"remove"`. For removals, the `emoji` field contains the emoji being removed (informational; the UNIQUE constraint on `message_id + sender_peer_id` means only one reaction per user per message exists). The current receive path treats exact `"remove"` specially; any other non-null action behaves like add.

The v2 envelope also carries a top-level `senderPeerId`, but the current receive path does not validate that field against `message.from` or the decrypted `payload.senderPeerId`.

### 4.8 Database Schema -- message_reactions

```sql
-- Migration 016: lib/core/database/migrations/016_message_reactions.dart

CREATE TABLE IF NOT EXISTS message_reactions (
  id TEXT PRIMARY KEY,
  message_id TEXT NOT NULL,
  emoji TEXT NOT NULL,
  sender_peer_id TEXT NOT NULL,
  timestamp TEXT NOT NULL,
  created_at TEXT NOT NULL,
  UNIQUE(message_id, sender_peer_id)
);

CREATE INDEX IF NOT EXISTS idx_message_reactions_message
  ON message_reactions(message_id);
```

**UNIQUE Constraint Enforcement Pattern:**

- `dbInsertReaction()` uses `ConflictAlgorithm.replace` -- inserting a new reaction for the same `(message_id, sender_peer_id)` pair silently replaces the existing row (including changing the emoji).
- `dbDeleteReaction()` deletes by `WHERE message_id = ? AND sender_peer_id = ?` -- removes at most one row due to UNIQUE.
- This enforces one-reaction-per-user-per-message at the database level. The application layer does not need to check for duplicates.

**Important schema note:** migration 016 does not declare a foreign key from `message_reactions.message_id` to `messages.id`, so orphan reaction rows are possible if code saves a reaction for a message row that is not present locally.

### 4.9 sendReaction() Use Case -- Full Flow

```dart
// File: lib/features/conversation/application/send_reaction_use_case.dart

Future<(SendReactionResult, MessageReaction?)> sendReaction({
  required P2PService p2pService,
  required Bridge bridge,
  required ReactionRepository reactionRepo,
  required String targetPeerId,
  required String messageId,
  required String emoji,
  required String senderPeerId,
  required String recipientMlKemPublicKey,
}) async {
  // 1. Check P2P node is running
  if (!p2pService.currentState.isStarted) return (nodeNotRunning, null);

  // 2. Build ReactionPayload(action: 'add')
  final payload = ReactionPayload(
    id: uuid.v4(), messageId: messageId, emoji: emoji,
    action: 'add', senderPeerId: senderPeerId,
    timestamp: DateTime.now().toUtc().toIso8601String(),
  );

  // 3. Encrypt via Go Bridge
  final innerJson = payload.toInnerJson();
  final encryptResult = await callEncryptMessage(
    bridge: bridge,
    recipientMlKemPublicKey: recipientMlKemPublicKey,
    plaintext: innerJson,
  );
  if (encryptResult['ok'] != true) return (encryptionFailed, null);

  // 4. Build v2 encrypted envelope
  final jsonString = ReactionPayload.buildEncryptedEnvelope(
    senderPeerId: senderPeerId,
    kem: encryptResult['kem'] as String,
    ciphertext: encryptResult['ciphertext'] as String,
    nonce: encryptResult['nonce'] as String,
  );

  // 5. Send -- try direct, then attempt inbox on false
  final sent = await p2pService.sendMessage(targetPeerId, jsonString);
  if (!sent) {
    await p2pService.storeInInbox(targetPeerId, jsonString);
  }

  // 6. Persist locally
  final reaction = payload.toMessageReaction();
  await reactionRepo.saveReaction(reaction);

  return (success, reaction);
}
```

**Notes:**

- The `bool` returned by `storeInInbox()` is currently ignored. If `sendMessage()` returns `false` and `storeInInbox()` also returns `false` without throwing, the use case still persists locally and returns `success`.
- Local repository failures are not converted into `SendReactionResult`; they can still throw because persistence happens after the guarded transport block.

### 4.10 Full Reaction Lifecycle -- Sequence Diagram

The UI path is optimistic. `ConversationWired` does not roll back local add/remove state if `sendReaction()` / `removeReaction()` fails.

```mermaid
sequenceDiagram
    actor User as Local User
    participant CS as ConversationScreen
    participant MCO as MessageContextOverlay
    participant RB as ReactionBar
    participant CW as ConversationWired
    participant SR as sendReaction()
    participant RR as removeReaction()
    participant BR as Bridge (Go)
    participant P2P as P2PService
    participant DB as SQLCipher
    participant Net as P2P Network
    participant RP as Remote Peer App
    participant IMR as IncomingMessageRouter
    participant RL as ReactionListener
    participant CR as ContactRepository
    participant HIR as handleIncomingReaction()

    Note over User, CS: === SEND REACTION ===

    User->>CS: Long-press non-deleted LetterCard
    CS->>CS: _showMessageContextOverlay()
    CS->>CS: Resolve ownReaction from reactions[message.id]
    CS->>MCO: showDialog(overlay)
    MCO->>RB: ReactionBar(currentEmoji: ownReaction?.emoji)
    RB->>RB: AnimationController.forward() (0.8->1.0, 200ms)
    User->>RB: Tap emoji (e.g. "thumbs up")
    RB->>CS: onReactionSelected("thumbs up")
    CS->>CS: Navigator.pop(dialogContext)
    CS->>CW: onReactionSelected(messageId, "thumbs up")

    alt Toggle OFF (same emoji)
        CW->>CW: setState: remove own reaction from _reactions[messageId]
        CW->>RR: removeReaction(...)
        RR->>BR: callEncryptMessage(payload with action='remove')
        BR-->>RR: {kem, ciphertext, nonce}
        RR->>P2P: sendMessage(targetPeerId, v2 envelope)
        alt Peer online
            P2P-->>RR: sent=true
        else Peer offline
            RR->>P2P: storeInInbox(targetPeerId, v2 envelope)
        end
        RR->>DB: DELETE FROM message_reactions WHERE message_id=? AND sender_peer_id=?
    else Add/Replace
        CW->>CW: setState: add MessageReaction(id='') placeholder
        CW->>SR: sendReaction(...)
        SR->>SR: Build ReactionPayload(action='add')
        SR->>BR: callEncryptMessage(innerJson)
        BR-->>SR: {ok:true, kem, ciphertext, nonce}
        SR->>SR: buildEncryptedEnvelope(...)
        SR->>P2P: sendMessage(targetPeerId, v2 envelope)
        alt Peer online
            P2P-->>SR: sent=true
        else Peer offline
            SR->>P2P: storeInInbox(targetPeerId, v2 envelope)
        end
        SR->>DB: INSERT OR REPLACE INTO message_reactions
        SR-->>CW: (success, reaction)
        CW->>CW: setState: replace placeholder with real reaction
    end

    P2P->>Net: Deliver encrypted envelope

    Note over Net, RP: === RECEIVE REACTION (Remote Peer Side) ===

    Net->>RP: Encrypted reaction arrives
    RP->>IMR: ChatMessage via P2PService.messageStream
    IMR->>IMR: jsonDecode -> type='message_reaction'
    IMR->>RL: reactionStream.add(message)
    RL->>CR: getContact(message.from)
    CR-->>RL: contact / isBlocked
    RL->>HIR: handleIncomingReaction(message, ownMlKemSecretKey)
    HIR->>HIR: parseEncryptedEnvelope(content) -> v2 envelope
    HIR->>BR: callDecryptMessage(ownSecretKey, kem, ciphertext, nonce)
    BR-->>HIR: {ok:true, plaintext: innerJson}
    HIR->>HIR: fromDecryptedJson(plaintext) -> ReactionPayload
    HIR->>HIR: Validate payload sender is known contact

    alt action == 'add'
        HIR->>DB: INSERT OR REPLACE INTO message_reactions
        HIR-->>RL: (success, ReactionChange.upsert(reaction))
    else action == 'remove'
        HIR->>DB: DELETE WHERE message_id=? AND sender_peer_id=?
        HIR-->>RL: (success, ReactionChange.removed(...))
    end

    RL->>CW: incomingReactionChangeStream -> ReactionChange
    CW->>CW: _onIncomingReactionChange(change)
    CW->>CW: setState: upsert/remove in _reactions map
    CW->>CS: Rebuild with updated reactions
    CS->>CS: LetterCard renders updated inline chips
```

### 4.11 DI Wiring (main.dart)

The reaction components are wired through the standard DI chain:

```
main.dart:
  Database db = await openEncryptedDatabase(...)

  // DB helpers (closures capturing db)
  final insertReaction = (row) => dbInsertReaction(db, row);
  final loadReactionsForMessage = (id) => dbLoadReactionsForMessage(db, id);
  final loadReactionsForMessages = (ids) => dbLoadReactionsForMessages(db, ids);
  final deleteReaction = (mid, spid) => dbDeleteReaction(db, mid, spid);
  final deleteReactionsForMessage = (mid) => dbDeleteReactionsForMessage(db, mid);
  final deleteReactionsForContact = (cpid) => dbDeleteReactionsForContact(db, cpid);

  // Repository
  final reactionRepo = ReactionRepositoryImpl(
    dbInsertReaction: insertReaction,
    dbLoadReactionsForMessage: loadReactionsForMessage,
    dbLoadReactionsForMessages: loadReactionsForMessages,
    dbDeleteReaction: deleteReaction,
    dbDeleteReactionsForMessage: deleteReactionsForMessage,
    dbDeleteReactionsForContact: deleteReactionsForContact,
  );

  // Listener
  final reactionListener = ReactionListener(
    reactionStream: messageRouter.reactionStream,  // From IncomingMessageRouter
    reactionRepo: reactionRepo,
    contactRepo: contactRepo,
    bridge: bridge,
    getOwnMlKemSecretKey: () async {
      final identity = await repository.loadIdentity();
      return identity?.mlKemSecretKey;
    },
  );

  reactionListener.start();

  // Threaded to ConversationWired via constructor
  ConversationWired(
    ...
    reactionRepo: reactionRepo,
    reactionListener: reactionListener,
    bridge: bridge,
    ...
  )
```

### 4.12 Class Diagram

```mermaid
classDiagram
    class MessageReaction {
        +String id
        +String messageId
        +String emoji
        +String senderPeerId
        +String timestamp
        +String createdAt
        +fromMap(Map) MessageReaction
        +toMap() Map
        +fromJson(Map) MessageReaction
        +toJson() Map
        +copyWith(...) MessageReaction
    }

    class ReactionChange {
        +ReactionChangeType type
        +String messageId
        +String senderPeerId
        +MessageReaction? reaction
        +upsert(MessageReaction) ReactionChange
        +removed(messageId, senderPeerId) ReactionChange
    }

    class ReactionPayload {
        +String id
        +String messageId
        +String emoji
        +String action
        +String senderPeerId
        +String timestamp
        +fromJson(String) ReactionPayload?
        +toJson() String
        +toInnerJson() String
        +fromDecryptedJson(String) ReactionPayload?
        +buildEncryptedEnvelope(...)$ String
        +parseEncryptedEnvelope(String)$ Map?
        +toMessageReaction() MessageReaction
    }

    class ReactionRepository {
        <<interface>>
        +saveReaction(MessageReaction) Future~void~
        +getReactionsForMessage(String) Future~List~
        +getReactionsForMessages(List) Future~Map~
        +removeReaction(String, String) Future~int~
        +deleteReactionsForMessage(String) Future~int~
        +deleteReactionsForContact(String) Future~int~
    }

    class ReactionRepositoryImpl {
        +dbInsertReaction: Function
        +dbLoadReactionsForMessage: Function
        +dbLoadReactionsForMessages: Function
        +dbDeleteReaction: Function
        +dbDeleteReactionsForMessage: Function
        +dbDeleteReactionsForContact: Function
    }

    class ReactionListener {
        +reactionStream: Stream
        +reactionRepo: ReactionRepository
        +contactRepo: ContactRepository
        +bridge: Bridge
        +getOwnMlKemSecretKey: Function
        +incomingReactionStream: Stream~MessageReaction~
        +incomingReactionChangeStream: Stream~ReactionChange~
        +start() void
        +stop() void
        +dispose() void
    }

    class ReactionBar {
        +currentEmoji: String?
        +onReactionSelected: Function
        +onPlusTap: VoidCallback
        +onDismiss: VoidCallback
        +anchorY: double?
        +inline: bool
    }

    class ReactionDisplay {
        +reactions: List~MessageReaction~
        +ownPeerId: String
        +onReactionTap: Function?
        +padding: EdgeInsetsGeometry
    }

    class SendReactionResult {
        <<enumeration>>
        success
        nodeNotRunning
        encryptionRequired
        encryptionFailed
        sendFailed
    }

    class RemoveReactionResult {
        <<enumeration>>
        success
        nodeNotRunning
        encryptionRequired
        encryptionFailed
        sendFailed
    }

    class HandleReactionResult {
        <<enumeration>>
        success
        notReaction
        unknownSender
        decryptionFailed
    }

    class ReactionChangeType {
        <<enumeration>>
        upserted
        removed
    }

    ReactionRepository <|.. ReactionRepositoryImpl
    ReactionRepositoryImpl --> MessageReaction : reads/writes
    ReactionListener --> ReactionRepository
    ReactionListener --> ReactionChange : broadcasts
    ReactionChange --> MessageReaction : contains?
    ReactionChange --> ReactionChangeType
    ReactionPayload --> MessageReaction : toMessageReaction()
    ReactionDisplay --> MessageReaction : renders
```

---

## File Index

| Layer | File | Purpose |
|---|---|---|
| DB Migration | `lib/core/database/migrations/016_message_reactions.dart` | CREATE TABLE + index |
| DB Helpers | `lib/core/database/helpers/reactions_db_helpers.dart` | 6 plain functions (insert, load, delete) |
| Domain Model | `lib/features/conversation/domain/models/message_reaction.dart` | MessageReaction (fromMap/toMap/fromJson/toJson) |
| Domain Model | `lib/features/conversation/domain/models/reaction_change.dart` | ReactionChange (upserted/removed) |
| Domain Model | `lib/features/conversation/domain/models/reaction_payload.dart` | ReactionPayload (wire format, v1/v2 envelope) |
| Domain Repo | `lib/features/conversation/domain/repositories/reaction_repository.dart` | ReactionRepository interface |
| Domain Repo | `lib/features/conversation/domain/repositories/reaction_repository_impl.dart` | ReactionRepositoryImpl (6 injected helpers) |
| Application | `lib/features/conversation/application/send_reaction_use_case.dart` | sendReaction() |
| Application | `lib/features/conversation/application/remove_reaction_use_case.dart` | removeReaction() |
| Application | `lib/features/conversation/application/load_reactions_use_case.dart` | loadReactionsForConversation() |
| Application | `lib/features/conversation/application/reaction_listener.dart` | ReactionListener |
| Application | `lib/features/conversation/application/handle_incoming_reaction_use_case.dart` | handleIncomingReaction() |
| Presentation | `lib/features/conversation/presentation/widgets/reaction_bar.dart` | ReactionBar (6 emojis + plus) |
| Presentation | `lib/features/conversation/presentation/widgets/reaction_display.dart` | Standalone reaction chip widget; not wired into the active `LetterCard` path |
| Presentation | `lib/features/conversation/presentation/widgets/full_emoji_picker.dart` | FullEmojiPicker (modal bottom sheet) |
| Presentation | `lib/features/conversation/presentation/widgets/letter_card.dart` | LetterCard (inline chips via _buildReactionChipWidgets) |
| Presentation | `lib/features/conversation/presentation/widgets/message_context_overlay.dart` | MessageContextOverlay (hosts ReactionBar) |
| Presentation | `lib/features/conversation/presentation/screens/conversation_screen.dart` | ConversationScreen (_showMessageContextOverlay, action gating, messageId callback handoff) |
| Presentation | `lib/features/conversation/presentation/screens/conversation_wired.dart` | ConversationWired (_onReactionSelected, _reactions state, initial-page-only reaction preload) |
| Router | `lib/core/services/incoming_message_router.dart` | IncomingMessageRouter (routes 'message_reaction' type) |
