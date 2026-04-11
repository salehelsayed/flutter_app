# C4 Model -- Level 4 (Code): MessageContextOverlay Feature

## 1. Overview

The MessageContextOverlay feature provides a long-press context interaction for conversation messages. When a user long-presses a LetterCard, a glassmorphic overlay appears with three vertically stacked components: a ReactionBar (6 preset emojis + full picker), a scaled-down preview of the selected message, and a context menu (Reply, Edit, Copy, Delete). The overlay uses a blurred backdrop and viewport-aware positioning to keep all components visible regardless of where the message sits on screen.

---

## 2. Class Diagrams

### 2.1 MessageContextOverlay Widget Tree

```mermaid
classDiagram
    class MessageContextOverlay {
        <<StatelessWidget>>
        +Rect anchorRect
        +Widget? selectedMessage
        +String? currentEmoji
        +bool showEditAction
        +bool showCopyAction
        +bool showDeleteAction
        +VoidCallback onDismiss
        +void Function(String) onReactionSelected
        +VoidCallback onPlusTap
        +VoidCallback onReplyTap
        +VoidCallback? onEditTap
        +VoidCallback? onCopyTap
        +VoidCallback? onDeleteTap
        +Widget build(BuildContext context)
        -double _clampToViewport(double value, double min, double max)
    }

    class _ContextMenuCard {
        <<StatelessWidget>>
        +bool showEditAction
        +bool showCopyAction
        +bool showDeleteAction
        +VoidCallback onReplyTap
        +VoidCallback? onEditTap
        +VoidCallback? onCopyTap
        +VoidCallback? onDeleteTap
        +Widget build(BuildContext context)
    }

    class _ContextMenuAction {
        <<StatelessWidget>>
        +IconData icon
        +String label
        +VoidCallback? onTap
        +Color color
        +Widget build(BuildContext context)
    }

    class ReactionBar {
        <<StatefulWidget>>
        +String? currentEmoji
        +void Function(String) onReactionSelected
        +VoidCallback onPlusTap
        +VoidCallback onDismiss
        +double? anchorY
        +bool inline
    }

    class _ReactionBarState {
        <<State~ReactionBar~>>
        -AnimationController _controller
        -Animation~double~ _scaleAnimation
        +void initState()
        +void dispose()
        +Widget build(BuildContext context)
        -Widget _emojiButton(String emoji)
        -Widget _plusButton()
    }

    MessageContextOverlay --> _ContextMenuCard : contains
    MessageContextOverlay --> ReactionBar : contains
    _ContextMenuCard --> _ContextMenuAction : contains 1..4
    ReactionBar --> _ReactionBarState : creates state
```

### 2.2 MessageReaction Model

```mermaid
classDiagram
    class MessageReaction {
        +String id
        +String messageId
        +String emoji
        +String senderPeerId
        +String timestamp
        +String createdAt
        +MessageReaction.fromMap(Map~String,dynamic~ map)$
        +Map~String,dynamic~ toMap()
        +MessageReaction.fromJson(Map~String,dynamic~ json)$
        +Map~String,dynamic~ toJson()
        +MessageReaction copyWith(...)
        +bool operator==(Object other)
        +int get hashCode
    }
```

### 2.3 Integration Classes

```mermaid
classDiagram
    class ConversationScreen {
        <<StatefulWidget>>
        +Map~String,List~MessageReaction~~ reactions
        +void Function(String, String)? onReactionSelected
        +ValueChanged~String~? onDeleteMessage
        +ValueChanged~String~? onEditMessage
        +ValueChanged~String~? onQuoteReply
        +bool allowEditAction
        +String? ownPeerId
    }

    class _ConversationScreenState {
        <<State~ConversationScreen~>>
        -void _showMessageContextOverlay(ConversationMessage, BuildContext, Widget)
        -bool _canEditMessage(ConversationMessage)
        -bool _canDeleteMessage(ConversationMessage)
        -String? _lastSentMessageId()
        -Future~void~ _copyMessageText(String)
        -void _showFullPicker(String)
        -void _handleReplyAction(String)
        -void _handleEditAction(String)
    }

    class ConversationWired {
        <<StatefulWidget>>
        -Map~String,List~MessageReaction~~ _reactions
        -Future~void~ _onReactionSelected(String messageId, String emoji)
    }

    class LetterCard {
        <<StatelessWidget>>
        +VoidCallback? onLongPress
        +List~MessageReaction~ reactions
        +String? ownPeerId
        +void Function(String)? onReactionTap
    }

    ConversationWired --> ConversationScreen : constructs
    ConversationScreen --> LetterCard : builds per message
    _ConversationScreenState --> MessageContextOverlay : shows via showDialog
    ConversationWired --> sendReaction : calls use case
    ConversationWired --> removeReaction : calls use case
```

---

## 3. Static Test Keys

MessageContextOverlay defines `ValueKey` constants for widget testing:

| Key Constant | Value | Widget |
|---|---|---|
| `overlayKey` | `'message-context-overlay'` | Root Material widget |
| `backdropKey` | `'message-context-backdrop'` | Dismissible blur backdrop |
| `reactionBarKey` | `'message-context-reaction-bar'` | ReactionBar |
| `selectedMessageKey` | `'message-context-selected-message'` | Message preview |
| `menuKey` | `'message-context-menu'` | Context menu container |
| `replyActionKey` | `'message-context-reply-action'` | Reply menu item |
| `editActionKey` | `'message-context-edit-action'` | Edit menu item |
| `copyActionKey` | `'message-context-copy-action'` | Copy menu item |
| `deleteActionKey` | `'message-context-delete-action'` | Delete menu item |

---

## 4. Widget Tree Structure

### 4.1 MessageContextOverlay Build Layout

```
Material(color: transparent)
  Stack(children: [
    // Layer 1: Dismissible blurred backdrop
    Positioned.fill(
      GestureDetector(onTap: onDismiss, behavior: opaque,
        ClipRect(
          BackdropFilter(blur: 18x18,
            Container(color: RGBA(6,8,12, 0.24))))))

    // Layer 2: Selected message preview (conditional)
    if (selectedMessageTop != null && selectedMessage != null)
      Padding(top: selectedMessageTop,
        Align(alignment: anchorAlignment,
          SizedBox(width: selectedMessageWidth, height: selectedMessageHeight,
            KeyedSubtree(
              ClipRect(
                IgnorePointer(
                  FittedBox(fit: scaleDown, alignment: topCenter,
                    SizedBox(width: selectedMessageWidth,
                      selectedMessage))))))))

    // Layer 3: Reaction bar
    Padding(top: reactionBarTop,
      Align(alignment: anchorAlignment,
        ReactionBar(inline: true, ...)))

    // Layer 4: Context menu
    Padding(top: menuTop,
      Align(alignment: anchorAlignment,
        ConstrainedBox(maxWidth: 220,
          _ContextMenuCard(...))))
  ])
```

### 4.2 _ContextMenuCard Build Layout

```
ClipRRect(borderRadius: 24,
  BackdropFilter(blur: 20x20,
    Container(
      decoration: BoxDecoration(
        color: RGBA(18,20,28, 0.95),
        borderRadius: 24,
        border: RGBA(255,255,255, 0.10)),
      Column(mainAxisSize: min, children: [
        _ContextMenuAction(icon: reply_rounded, label: l10n.reply, onTap: onReplyTap),
        Divider(RGBA(255,255,255, 0.08)),  // between each item
        if (showEditAction)
          _ContextMenuAction(icon: edit_rounded, label: l10n.edit, onTap: onEditTap),
        if (showCopyAction)
          _ContextMenuAction(icon: copy_rounded, label: l10n.copy, onTap: onCopyTap),
        if (showDeleteAction)
          _ContextMenuAction(icon: delete_outline_rounded, label: l10n.delete,
            onTap: onDeleteTap, color: Color(0xFFFF8A80)),
      ]))))
```

### 4.3 _ContextMenuAction Build Layout

```
Material(color: transparent,
  InkWell(onTap: onTap,
    Padding(horizontal: 16, vertical: 14,
      Row(mainAxisSize: min, children: [
        Icon(icon, size: 18, color: color),
        SizedBox(width: 12),
        Flexible(Text(label, fontSize: 15, fontWeight: w500, color: color)),
      ]))))
```

### 4.4 ReactionBar Build Layout (inline mode)

```
ScaleTransition(scale: _scaleAnimation,
  ClipRRect(borderRadius: 28,
    BackdropFilter(blur: 24x24,
      Container(
        padding: H12 V8,
        decoration: BoxDecoration(
          color: RGBA(18,20,28, 0.95),
          borderRadius: 28,
          border: RGBA(255,255,255, 0.10)),
        Row(mainAxisSize: min, children: [
          _emojiButton('thumbs_up'),  // 44x44, highlight if selected
          _emojiButton('heart'),
          _emojiButton('laugh'),
          _emojiButton('surprised'),
          _emojiButton('sad'),
          _emojiButton('pray'),
          _plusButton(),              // 44x44, opens full picker
        ])))))
```

---

## 5. ReactionBar Animation State Machine

```mermaid
stateDiagram-v2
    [*] --> Idle : widget created
    Idle --> Animating : initState() calls _controller.forward()
    Animating --> Visible : animation completes (200ms)
    Visible --> Disposed : dispose()
    Animating --> Disposed : dispose() before completion

    state Animating {
        [*] --> ScaleUp
        note right of ScaleUp
            Tween: 0.8 -> 1.0
            Curve: easeOut
            Duration: 200ms
        end note
    }
```

**Animation details:**
- `AnimationController`: duration 200ms, `SingleTickerProviderStateMixin` vsync
- `_scaleAnimation`: `Tween<double>(begin: 0.8, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut))`
- Applied via `ScaleTransition(scale: _scaleAnimation, child: ...)`
- `initState()` calls `_controller.forward()` immediately
- `dispose()` calls `_controller.dispose()`

---

## 6. Positioning Algorithm

MessageContextOverlay uses a viewport-aware positioning algorithm that vertically stacks three components (reaction bar, message preview, context menu) while keeping them all within safe bounds.

### 6.1 Constants

```
_reactionBarHeight = 60.0    // height of the reaction bar
_menuActionHeight  = 58.0    // height of each context menu action row
_verticalGap       = 12.0    // gap between stacked components
```

### 6.2 Derived Values

```
topPadding    = MediaQuery.viewPadding.top + 8
bottomPadding = MediaQuery.viewPadding.bottom + 8
screenSize    = MediaQuery.size

actionCount = 1 (Reply always)
            + (showEditAction ? 1 : 0)
            + (showCopyAction ? 1 : 0)
            + (showDeleteAction ? 1 : 0)

menuHeight = actionCount * _menuActionHeight

selectedMessageWidth  = anchorRect.width > 0 ? anchorRect.width : screenSize.width - 32
selectedMessageHeight = anchorRect.height > 0 ? anchorRect.height : 120.0
```

### 6.3 Horizontal Alignment

```
anchorAlignment = Alignment(
  x: clamp((anchorRect.center.dx / screenSize.width) * 2 - 1, -1.0, 1.0),
  y: -1   // always align to top edge of the Padding
)
```

All three components (reaction bar, message preview, context menu) use the same `anchorAlignment` with `Align`, meaning they are horizontally centered on the original message's horizontal center, mapped to `[-1, 1]` alignment space. The context menu is additionally constrained to `maxWidth: 220`.

### 6.4 Vertical Positioning (with selected message)

```
minSelectedMessageTop = topPadding + _reactionBarHeight + _verticalGap
maxSelectedMessageTop = screenSize.height - bottomPadding - menuHeight - _verticalGap - selectedMessageHeight

selectedMessageTop = clampToViewport(anchorRect.top, min: minSelectedMessageTop, max: maxSelectedMessageTop)

reactionBarTop = selectedMessageTop - _reactionBarHeight - _verticalGap
menuTop        = selectedMessageTop + selectedMessageHeight + _verticalGap
```

### 6.5 Vertical Positioning (without selected message)

```
reactionBarTop = clampToViewport(
  anchorRect.top - _reactionBarHeight - _verticalGap,
  min: topPadding,
  max: screenSize.height - _reactionBarHeight - bottomPadding
)

menuTop = clampToViewport(
  anchorRect.bottom + _verticalGap,
  min: reactionBarTop + _reactionBarHeight + _verticalGap,
  max: screenSize.height - menuHeight - bottomPadding
)
```

### 6.6 Clamping Function

```dart
double _clampToViewport(double value, {required double min, required double max}) {
  if (max < min) return min;        // safety: collapsed range returns min
  return value.clamp(min, max);
}
```

### 6.7 Visual Stack (top to bottom)

```
+-------------------------------------+
| safe area top + 8px                  |
|                                      |
| +-------------------------------+    |
| |  ReactionBar (60px)           |    |
| +-------------------------------+    |
|          12px gap                    |
| +-------------------------------+    |
| | Selected Message Preview      |    |
| | (anchorRect dimensions)       |    |
| +-------------------------------+    |
|          12px gap                    |
| +-------------------------------+    |
| | Context Menu (max 220px wide) |    |
| |   Reply        (58px)        |    |
| |   Edit         (58px)        |    |
| |   Copy         (58px)        |    |
| |   Delete       (58px)        |    |
| +-------------------------------+    |
|                                      |
| safe area bottom + 8px              |
+-------------------------------------+
```

---

## 7. Sequence Diagrams

### 7.1 Overlay Trigger (Long Press)

```mermaid
sequenceDiagram
    participant User
    participant LetterCard
    participant ConversationScreenState as _ConversationScreenState
    participant ShowDialog as showDialog()
    participant MCO as MessageContextOverlay

    User->>LetterCard: onLongPress
    LetterCard->>ConversationScreenState: _showMessageContextOverlay(message, cardContext, selectedMessage)
    ConversationScreenState->>ConversationScreenState: cardContext.findRenderObject() as RenderBox
    ConversationScreenState->>ConversationScreenState: localToGlobal(Offset.zero) -> topLeft
    ConversationScreenState->>ConversationScreenState: anchorRect = topLeft & renderObject.size
    ConversationScreenState->>ConversationScreenState: lookup ownReaction from widget.reactions[message.id]
    ConversationScreenState->>ConversationScreenState: _canEditMessage(message)
    ConversationScreenState->>ConversationScreenState: _canDeleteMessage(message)
    ConversationScreenState->>ShowDialog: showDialog(useSafeArea: false, barrierColor: transparent)
    ShowDialog->>MCO: build MessageContextOverlay(anchorRect, selectedMessage, callbacks...)
    MCO->>User: render blurred overlay with reaction bar + preview + menu
```

### 7.2 Reaction Flow (Preset Emoji)

```mermaid
sequenceDiagram
    participant User
    participant RB as ReactionBar
    participant MCO as MessageContextOverlay
    participant Nav as Navigator
    participant CW as ConversationWired
    participant SR as sendReaction()
    participant Bridge
    participant P2P as P2PService
    participant Repo as ReactionRepository

    User->>RB: tap emoji (e.g. thumbs_up)
    RB->>MCO: onReactionSelected(emoji)
    MCO->>Nav: pop() (dismiss overlay)
    MCO->>CW: widget.onReactionSelected(messageId, emoji)
    CW->>CW: _onReactionSelected(messageId, emoji)

    alt Same emoji as existing own reaction
        CW->>CW: setState: remove own reaction (toggle off)
        CW->>SR: removeReaction(...)
    else New or different emoji
        CW->>CW: setState: add/replace optimistic MessageReaction
        CW->>SR: sendReaction(p2pService, bridge, reactionRepo, ...)
        SR->>SR: emitFlowEvent(REACTION_SEND_START)
        SR->>SR: Check p2pService.currentState.isStarted
        SR->>SR: Build ReactionPayload(id, messageId, emoji, action: 'add', ...)
        SR->>Bridge: callEncryptMessage(recipientMlKemPublicKey, plaintext)
        Bridge-->>SR: {ok: true, kem, ciphertext, nonce}
        SR->>SR: buildEncryptedEnvelope(senderPeerId, kem, ciphertext, nonce)
        SR->>P2P: sendMessage(targetPeerId, jsonString)
        alt Direct send fails
            SR->>P2P: storeInInbox(targetPeerId, jsonString)
        end
        SR->>Repo: saveReaction(reaction)
        SR-->>CW: (SendReactionResult.success, reaction)
        CW->>CW: setState: replace optimistic with real reaction
    end
```

### 7.3 Full Emoji Picker Flow (Plus Button)

```mermaid
sequenceDiagram
    participant User
    participant RB as ReactionBar
    participant MCO as MessageContextOverlay
    participant Nav as Navigator
    participant CSS as _ConversationScreenState
    participant Picker as showFullEmojiPicker()
    participant CW as ConversationWired

    User->>RB: tap "+" button
    RB->>MCO: onPlusTap()
    MCO->>Nav: pop() (dismiss overlay)
    MCO->>CSS: _showFullPicker(messageId)
    CSS->>Picker: showFullEmojiPicker(context)
    Picker-->>CSS: emoji (String?) or null if dismissed
    alt emoji != null
        CSS->>CW: widget.onReactionSelected(messageId, emoji)
        Note over CW: same flow as 7.2 from this point
    end
```

### 7.4 Reply Flow

```mermaid
sequenceDiagram
    participant User
    participant MCO as MessageContextOverlay
    participant Nav as Navigator
    participant CSS as _ConversationScreenState
    participant CW as ConversationWired
    participant ComposeArea

    User->>MCO: tap Reply action
    MCO->>Nav: pop() (dismiss overlay)
    MCO->>CSS: _handleReplyAction(messageId)
    CSS->>CW: widget.onQuoteReply(messageId)
    CSS->>CSS: _requestComposerFocus()
    CW->>CW: setState: set quotedMessageId
    CW->>ComposeArea: activeQuoteText populated, focus requested
    User->>ComposeArea: types reply text + sends
    ComposeArea->>CW: onSend(text) with quotedMessageId
    CW->>CW: sendChatMessage(text, quotedMessageId: messageId)
```

### 7.5 Edit Flow

```mermaid
sequenceDiagram
    participant User
    participant MCO as MessageContextOverlay
    participant Nav as Navigator
    participant CSS as _ConversationScreenState
    participant CW as ConversationWired
    participant ComposeArea

    User->>MCO: tap Edit action
    MCO->>Nav: pop() (dismiss overlay)
    MCO->>CSS: _handleEditAction(messageId)
    CSS->>CW: widget.onEditMessage(messageId)
    CSS->>CSS: _requestComposerFocus()
    CW->>CW: setState: enter edit mode, pre-fill compose area
    CW->>ComposeArea: isEditingMessage=true, initialText=message.text
    User->>ComposeArea: modifies text + submits
    ComposeArea->>CW: onSend(newText)
    CW->>CW: editChatMessage(messageId, newText)
```

### 7.6 Copy Flow

```mermaid
sequenceDiagram
    participant User
    participant MCO as MessageContextOverlay
    participant Nav as Navigator
    participant CSS as _ConversationScreenState
    participant Clipboard

    User->>MCO: tap Copy action
    MCO->>Nav: pop() (dismiss overlay)
    MCO->>CSS: _copyMessageText(message.text)
    CSS->>Clipboard: Clipboard.setData(ClipboardData(text: message.text))
    CSS->>CSS: ScaffoldMessenger.showSnackBar("Copied")
```

### 7.7 Delete Flow

```mermaid
sequenceDiagram
    participant User
    participant MCO as MessageContextOverlay
    participant Nav as Navigator
    participant CSS as _ConversationScreenState
    participant CW as ConversationWired

    User->>MCO: tap Delete action
    MCO->>Nav: pop() (dismiss overlay)
    MCO->>CSS: addPostFrameCallback
    CSS->>CW: widget.onDeleteMessage(messageId)
    CW->>CW: show confirmation dialog / execute delete
```

---

## 8. Permission Guard Logic

### 8.1 canOpenContextOverlay

Defined inline in `_ConversationScreenState._buildDisplayItems`:

```dart
final canOpenContextOverlay = !message.isDeleted;
```

A deleted message cannot be long-pressed to open the overlay.

### 8.2 _canEditMessage(ConversationMessage message)

```
RETURN false IF:
  - widget.allowEditAction == false
  - widget.onEditMessage == null
  - message.isDeleted == true
  - widget.ownPeerId == null
  - message.isIncoming == true
  - message.senderPeerId != widget.ownPeerId
  - message.text.trim().isEmpty
  - _lastSentMessageId() != message.id    // only the most recent own message
RETURN true OTHERWISE
```

`_lastSentMessageId()` scans `widget.messages` from newest to oldest, skipping deleted messages, and returns the `id` of the first non-deleted outgoing message where `senderPeerId == ownPeerId`.

### 8.3 _canDeleteMessage(ConversationMessage message)

```
RETURN false IF:
  - widget.onDeleteMessage == null
  - message.isDeleted == true
  - message.transport == 'system'
RETURN true OTHERWISE
```

### 8.4 Copy Availability

```dart
final hasCopyAction = !message.isDeleted && message.text.trim().isNotEmpty;
```

---

## 9. Glassmorphic Styling Constants

All overlay components share a consistent glassmorphic design language:

| Component | Background | Blur | Border Radius | Border |
|---|---|---|---|---|
| Backdrop | `RGBA(6, 8, 12, 0.24)` | `18 x 18` | -- | -- |
| ReactionBar | `RGBA(18, 20, 28, 0.95)` | `24 x 24` | `28` | `RGBA(255, 255, 255, 0.10)` |
| ContextMenuCard | `RGBA(18, 20, 28, 0.95)` | `20 x 20` | `24` | `RGBA(255, 255, 255, 0.10)` |
| Menu Dividers | `RGBA(255, 255, 255, 0.08)` | -- | -- | -- |
| Menu Action Text | `RGBA(255, 255, 255, 0.78)` | -- | -- | -- |
| Delete Action Text | `Color(0xFFFF8A80)` | -- | -- | -- |
| Selected Emoji Highlight | `RGBA(78, 205, 196, 0.20)` | -- | `22` | -- |
| Plus Button Background | `RGBA(255, 255, 255, 0.06)` | -- | `22` | -- |

---

## 10. File Inventory

| File | Lines | Role |
|---|---|---|
| `lib/features/conversation/presentation/widgets/message_context_overlay.dart` | 329 | MessageContextOverlay, _ContextMenuCard, _ContextMenuAction |
| `lib/features/conversation/presentation/widgets/reaction_bar.dart` | 153 | ReactionBar (StatefulWidget with scale animation) |
| `lib/features/conversation/presentation/widgets/letter_card.dart` | 520 | LetterCard with `onLongPress` callback |
| `lib/features/conversation/presentation/screens/conversation_screen.dart` | ~790 | Trigger flow: _showMessageContextOverlay, permission guards, clipboard, full picker |
| `lib/features/conversation/presentation/screens/conversation_wired.dart` | ~3300 | _onReactionSelected (optimistic update + use case call) |
| `lib/features/conversation/domain/models/message_reaction.dart` | 115 | MessageReaction model (fromMap/toMap, fromJson/toJson, copyWith) |
| `lib/features/conversation/application/send_reaction_use_case.dart` | 133 | sendReaction top-level function (encrypt + P2P send + persist) |
| `lib/features/conversation/presentation/widgets/full_emoji_picker.dart` | ~70 | showFullEmojiPicker (modal bottom sheet) |

---

## 11. Key Design Decisions

1. **StatelessWidget overlay.** MessageContextOverlay is a StatelessWidget -- all animation lives in ReactionBar's internal state. This keeps the overlay itself purely declarative and easy to test.

2. **Viewport-aware positioning.** The algorithm clamps all three stacked components within safe bounds, with the selected message preview as the anchor point. When the message preview position is computed, reaction bar and menu positions are derived relative to it, guaranteeing no component is clipped by notches or home indicators.

3. **Horizontal alignment via Alignment mapping.** Instead of absolute `Positioned(left: ...)`, the overlay maps the anchor's horizontal center to a `-1..1` alignment value, then uses `Align(alignment: anchorAlignment)` for all components. This naturally handles different screen widths and message positions.

4. **IgnorePointer on message preview.** The selected message widget is wrapped in `IgnorePointer` and `ClipRect` to prevent interaction -- it is purely a visual reference while the user interacts with the reaction bar and menu.

5. **Optimistic reaction updates.** `ConversationWired._onReactionSelected` calls `setState` to add/replace the reaction immediately, then fires the `sendReaction` use case asynchronously. On success, the optimistic reaction is replaced with the server-confirmed one. On toggle-off, the reaction is removed before calling `removeReaction`.

6. **Post-frame delete callback.** The delete action uses `WidgetsBinding.instance.addPostFrameCallback` to defer the `onDeleteMessage` call until after the dialog navigator pop has completed, avoiding framework conflicts.

7. **Localized menu labels.** All context menu action labels use `AppLocalizations` (`conversation_context_reply`, `conversation_context_edit`, `conversation_context_copy`, `conversation_context_delete`), not hardcoded English strings.
