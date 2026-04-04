# Fix-2: Deferred Direct ACK — Move ACK After Flutter DB Confirmation

## Context

A 1:1 message ("اه كلمني 👍") was permanently lost on Apr 2, 2026. The sender (Saleh/iOS) saw double checkmarks, but the receiver (Ibra/Android) never got the message.

**Root cause**: In `go-mknoon/node/node.go:1147-1180`, the receiving Go node sends `{"ack":true}` to the sender **immediately after reading the message bytes** — before the message reaches Flutter, before decryption, before DB persistence. The sender treats this ACK as "delivered" and skips the inbox fallback. If anything fails between Go ACK and DB commit (app backgrounding, EventChannel disconnect, decryption failure), the message is permanently lost with no retry path.

**Goal**: Defer the ACK until Flutter confirms the message is persisted in the local DB. If Flutter can't confirm within a timeout, Go does NOT ACK — the sender's `readFrame` fails → `acknowledged=false` → sender falls back to inbox store-and-forward (the reliable path).

## Architecture Constraints

- **Go→Flutter** is one-way (`EventChannel`, fire-and-forget `OnEvent` callback)
- **Flutter→Go** is request/response (`MethodChannel`, supports round-trips)
- gomobile cannot do synchronous Go→Flutter→Go round-trips
- Sender stream deadlines: 3s interactive, 15s background — receiver must confirm within this budget

## Design

### Mechanism

```
SENDER                          RECEIVER GO                         RECEIVER FLUTTER
  │                                │                                     │
  │──writeFrame(message)──────────►│                                     │
  │                                │ generate confirmNonce               │
  │                                │ emit "message:received" + nonce     │
  │                                │ park goroutine on pendingConfirms   │
  │                                │ ─ ─ ─ ─ ─ ─ ─ ─ EventChannel ─ ─►│
  │                                │                                     │ parse, decrypt, persist to DB
  │                                │                                     │ callP2PConfirmDirect(nonce, ok)
  │                                │◄── ─ ─ MethodChannel ─ ─ ─ ─ ─ ─ ─│
  │                                │ unblock goroutine                   │
  │                                │ if ok: writeFrame(ack)              │
  │◄──readFrame(ack)───────────────│ if !ok: s.Reset() (no ack)          │
  │ acknowledged=true              │                                     │
  │ status='delivered' ✓           │                                     │

TIMEOUT PATH (app backgrounded, Flutter dead):
  │                                │                                     │
  │                                │ timeout (2s) fires                   ✗ (not running)
  │                                │ s.Reset() (no ack)                  │
  │ readFrame fails                │                                     │
  │ acknowledged=false             │                                     │
  │ → storeInInbox (safety net)    │                                     │
```

### Confirmation Semantics by Message Type

| Chat listener result | Confirm? | Rationale |
|---|---|---|
| `chatMessage` (DB persisted) | YES | Message safely stored |
| `duplicate` | YES | Already in DB — safe |
| `blockedSender` | YES | Intentional drop, don't retry |
| `unknownSender` | NO | Contact may be added later |
| `missingMlKemSecret` | NO | Key may load on retry |
| `decryptionFailed` | NO | Transient key issue possible |
| `editMissingOriginal` | NO | Original may arrive out of order |
| `notChatMessage` | YES | Not a chat msg — handled elsewhere |
| Non-chat types (contact_request, etc.) | YES | Confirm from `_handleEvent` |

### Feature Flag

`EnableDeferredDirectAck` in Go `FeatureFlags` — defaults to `true`. When disabled, falls back to the current immediate-ACK behavior. Allows quick rollback if issues arise.

---

## Implementation Steps

### Step 1: Go — Pending confirmation infrastructure

**File: `go-mknoon/node/node.go`**

Add to `Node` struct:
```go
pendingDirectConfirms map[string]chan bool // nonce → confirmation channel
pendingConfirmsMu     sync.Mutex
```

Initialize in `NewNode` / `Start`.

Add methods:
```go
func (n *Node) waitForDirectConfirm(nonce string, timeout time.Duration) bool
func (n *Node) ResolveDirectConfirm(nonce string, ok bool)
```

`waitForDirectConfirm`: creates a `chan bool` in the map, waits on it with timeout, cleans up.
`ResolveDirectConfirm`: sends `ok` on the channel if it exists, no-op otherwise. Called from the MethodChannel handler.

**File: `go-mknoon/node/config.go`**

Add constant:
```go
DirectConfirmTimeout = 2 * time.Second // must be < InteractiveSendTimeout (3s)
```

**File: `go-mknoon/node/feature_flags.go`**

Add flag:
```go
EnableDeferredDirectAck bool `json:"enableDeferredDirectAck"`
```

Default to `true` in `DefaultFeatureFlags()`.

### Step 2: Go — Modify handleIncomingMessage

**File: `go-mknoon/node/node.go` — `handleIncomingMessage` (line 1147)**

```go
func (n *Node) handleIncomingMessage(s network.Stream) {
    defer s.Close()
    remotePeer := s.Conn().RemotePeer().String()
    s.SetReadDeadline(time.Now().Add(InboundReadDeadline))

    msgBytes, err := readFrame(s)
    if err != nil {
        s.Reset()
        log.Printf("[NODE] Read error from %s: %v", remotePeer[:min(20, len(remotePeer))], err)
        return
    }

    // Feature-flagged deferred ACK
    flags := n.effectiveFlags()
    if flags.EnableDeferredDirectAck {
        nonce := generateNonce()  // UUID v4

        // Build event data WITH nonce
        msgData := map[string]interface{}{
            "from":         remotePeer,
            "to":           n.peerId,
            "content":      string(msgBytes),
            "timestamp":    time.Now().UTC().Format(time.RFC3339Nano),
            "isIncoming":   true,
            "transport":    classifyStreamTransport(s),
            "confirmNonce": nonce,
        }
        n.emitEvent("message:received", msgData)

        // Wait for Flutter to confirm DB persistence
        confirmed := n.waitForDirectConfirm(nonce, DirectConfirmTimeout)

        if confirmed {
            ack := []byte(`{"ack":true}`)
            _ = writeFrame(s, ack)
        } else {
            log.Printf("[NODE] Direct confirm timeout for %s — not ACKing", nonce[:8])
            s.Reset()
        }
    } else {
        // Legacy immediate ACK
        ack := []byte(`{"ack":true}`)
        _ = writeFrame(s, ack)

        msgData := map[string]interface{}{
            "from":       remotePeer,
            "to":         n.peerId,
            "content":    string(msgBytes),
            "timestamp":  time.Now().UTC().Format(time.RFC3339Nano),
            "isIncoming": true,
            "transport":  classifyStreamTransport(s),
        }
        n.emitEvent("message:received", msgData)
    }
}
```

### Step 3: Go — Bridge function for confirmation

**File: `go-mknoon/bridge/bridge.go`**

Add exported function:
```go
func ConfirmDirectMessage(paramsJSON string) (result string) {
    defer func() { if r := recover(); r != nil { result = errJSON("INTERNAL_ERROR", ...) } }()

    var params struct {
        Nonce string `json:"nonce"`
        Ok    bool   `json:"ok"`
    }
    if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
        return errJSON("INVALID_PARAMS", err.Error())
    }

    nodeMu.Lock()
    n := singletonNode
    nodeMu.Unlock()
    if n == nil {
        return errJSON("NODE_NOT_STARTED", "no node")
    }

    n.ResolveDirectConfirm(params.Nonce, params.Ok)
    return okJSON(map[string]interface{}{"ok": true})
}
```

### Step 4: Platform — iOS and Android method routing

**File: `ios/Runner/GoBridge.swift`**

Add case in `handleMethodCall`:
```swift
case "confirmDirectMessage":
    runOnBackground({ BridgeConfirmDirectMessage(args ?? "") }, result: result)
```

**File: `android/app/src/main/kotlin/com/mknoon/app/GoBridge.kt`**

Add case in `onMethodCall`:
```kotlin
"confirmDirectMessage" -> runOnBackground({ GoMknoon.confirmDirectMessage(args ?: "") }, result)
```

### Step 5: Dart — ChatMessage model

**File: `lib/features/p2p/domain/models/chat_message.dart`**

Add `confirmNonce` field:
```dart
class ChatMessage {
  final String from;
  final String to;
  final String content;
  final String timestamp;
  final bool isIncoming;
  final String? transport;
  final String? confirmNonce;  // NEW

  // Update constructor, fromJson, copyWith
}
```

In `fromJson`: `confirmNonce: json['confirmNonce']?.toString()`.
In `copyWith`: include `confirmNonce`.

### Step 6: Dart — Bridge client confirmation helper

**File: `lib/core/bridge/p2p_bridge_client.dart`**

Add function:
```dart
Future<void> callP2PConfirmDirectMessage({
  required Bridge bridge,
  required String nonce,
  required bool ok,
}) async {
  await bridge.send(jsonEncode({
    'cmd': 'message:confirm',
    'payload': jsonEncode({'nonce': nonce, 'ok': ok}),
  }));
}
```

**File: `lib/core/bridge/go_bridge_client.dart`**

Add to `_cmdMap`:
```dart
'message:confirm': _CmdSpec('confirmDirectMessage', true),
```

### Step 7: Dart — Confirm from GoBridgeClient for non-chat types

**File: `lib/core/bridge/go_bridge_client.dart` — `_handleEvent`**

After the existing `message:received` handling:
```dart
case 'message:received':
  if (onMessageReceived != null) {
    try {
      final chatMessage = ChatMessage.fromJson(eventData);
      onMessageReceived!(chatMessage);

      // For non-chat message types, confirm immediately.
      // Chat messages are confirmed by ChatMessageListener after DB persist.
      if (chatMessage.confirmNonce != null) {
        final isChatMessage = _peekMessageType(chatMessage.content) == 'chat_message';
        if (!isChatMessage) {
          _confirmDirectNonce(chatMessage.confirmNonce!, true);
        }
      }
    } catch (e) {
      debugPrint('[GoBridgeClient] Error parsing chat message: $e');
      // If we had a nonce, confirm with ok=false so Go doesn't ACK
      final nonce = eventData['confirmNonce']?.toString();
      if (nonce != null) {
        _confirmDirectNonce(nonce, false);
      }
    }
  }
```

Add helper methods:
```dart
static String? _peekMessageType(String content) {
  try {
    final json = jsonDecode(content) as Map<String, dynamic>;
    return json['type'] as String?;
  } catch (_) {
    return null;
  }
}

void _confirmDirectNonce(String nonce, bool ok) {
  // Fire-and-forget — don't block the event handler
  send(jsonEncode({
    'cmd': 'message:confirm',
    'payload': jsonEncode({'nonce': nonce, 'ok': ok}),
  })).catchError((_) {});
}
```

### Step 8: Dart — Confirm from ChatMessageListener after DB persist

**File: `lib/features/conversation/application/chat_message_listener.dart` — `processIncomingMessage`**

After `handleIncomingChatMessage` returns, confirm based on result:

```dart
// After the result switch/checks, before return:
if (bridge != null && message.confirmNonce != null) {
  final shouldConfirm = result == HandleChatMessageResult.chatMessage
      || result == HandleChatMessageResult.duplicate
      || result == HandleChatMessageResult.notChatMessage;

  callP2PConfirmDirectMessage(
    bridge: bridge!,
    nonce: message.confirmNonce!,
    ok: shouldConfirm,
  ).catchError((_) {});
}
```

This covers:
- `chatMessage`: DB persist succeeded → confirm
- `duplicate`: already in DB → confirm
- `notChatMessage`: parsed but wrong type → confirm (was handled by step 7)
- `unknownSender`, `missingMlKemSecret`, `decryptionFailed`, `editMissingOriginal`: DON'T confirm → Go times out → no ACK → sender falls back to inbox

---

## Files Modified (Summary)

| File | Change |
|---|---|
| `go-mknoon/node/node.go` | `pendingDirectConfirms` map, `waitForDirectConfirm`, `ResolveDirectConfirm`, modified `handleIncomingMessage` |
| `go-mknoon/node/config.go` | `DirectConfirmTimeout = 2s` |
| `go-mknoon/node/feature_flags.go` | `EnableDeferredDirectAck` flag |
| `go-mknoon/bridge/bridge.go` | `ConfirmDirectMessage()` exported function |
| `ios/Runner/GoBridge.swift` | `case "confirmDirectMessage"` |
| `android/.../GoBridge.kt` | `case "confirmDirectMessage"` |
| `lib/features/p2p/domain/models/chat_message.dart` | `confirmNonce` field |
| `lib/core/bridge/go_bridge_client.dart` | `_cmdMap` entry, `_confirmDirectNonce`, `_peekMessageType`, non-chat confirm in `_handleEvent` |
| `lib/core/bridge/p2p_bridge_client.dart` | `callP2PConfirmDirectMessage()` |
| `lib/features/conversation/application/chat_message_listener.dart` | Confirm call after `handleIncomingChatMessage` |

## Test Plan

### Go Unit Tests (new file: `go-mknoon/node/direct_confirm_test.go`)

1. **TestDirectConfirm_HappyPath**: Sender sends message → receiver waits → confirm arrives within timeout → ACK written → sender reads ACK → `Acked=true`
2. **TestDirectConfirm_Timeout**: Sender sends → receiver waits → no confirm → timeout → stream reset → sender reads error → `Acked=false`
3. **TestDirectConfirm_FalseConfirm**: Confirm arrives with `ok=false` → stream reset → `Acked=false`
4. **TestDirectConfirm_DuplicateNonce**: Second confirm for same nonce is no-op
5. **TestDirectConfirm_FeatureFlagDisabled**: With flag off, immediate ACK (legacy behavior)

### Dart Unit Tests

6. **ChatMessage.fromJson preserves confirmNonce**: Verify the nonce field survives serialization
7. **ChatMessageListener confirms on chatMessage result**: Mock bridge, verify `message:confirm` called with `ok=true`
8. **ChatMessageListener confirms on duplicate result**: Mock bridge, verify `message:confirm` called with `ok=true`
9. **ChatMessageListener does NOT confirm on decryptionFailed**: Mock bridge, verify `message:confirm` called with `ok=false`
10. **GoBridgeClient confirms non-chat types immediately**: Verify `_confirmDirectNonce` fires for `contact_request` type
11. **GoBridgeClient confirms with ok=false on parse error**: Verify nonce is not leaked

### Integration / Manual Test

12. Send a 1:1 message while recipient is active → double checkmark, message appears (happy path)
13. Send a 1:1 message, immediately background recipient app → sender should see single checkmark (ACK timeout), message stored in inbox, delivered on resume
14. Send a 1:1 message to a contact that has been deleted from recipient's DB → sender should NOT get double checkmark, inbox fallback

## Build Sequence

1. Go changes first (steps 1-3) → `cd go-mknoon && make all`
2. Platform changes (step 4) → `cd ../ios && pod install`
3. Dart changes (steps 5-8)
4. Run Dart tests → `flutter test`
5. Manual test on iOS simulator + Android emulator

## Risk Considerations

- **Timeout too short**: 2s should be plenty for DB write + MethodChannel round-trip (~200ms typical). If SQLite is slow under load, increase to 3s but keep below sender's interactive deadline (3s)
- **Goroutine leak**: `waitForDirectConfirm` uses `select` with timeout — goroutine always unblocks. Map entry cleaned up in `defer`.
- **MethodChannel ordering**: Flutter is single-threaded, so confirm calls are sequential. No risk of concurrent map access on the Dart side.
- **Feature flag rollback**: If deferred ACK causes issues, disable `EnableDeferredDirectAck` → immediate rollback to current behavior without code deploy (flag can be passed in `NodeConfig` from Dart).
