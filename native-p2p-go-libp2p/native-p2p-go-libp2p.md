# Native P2P Migration: WebView → go-libp2p via gomobile

## Overview

Replace the WebView-hosted js-libp2p runtime with a native go-libp2p library compiled via gomobile. This unlocks QUIC transport, native mDNS local discovery, DCUtR hole-punching, and future BLE transport — none of which are possible inside a browser sandbox.

The Flutter web build retains js-libp2p + WebRTC unchanged.

---

## Architecture: Before & After

```
BEFORE (current)                          AFTER (target)
┌──────────────────────┐                 ┌──────────────────────┐
│     Flutter UI        │                 │     Flutter UI        │
│  (unchanged either    │                 │  (unchanged)          │
│   way)                │                 │                       │
├──────────────────────┤                 ├──────────────────────┤
│  P2PServiceImpl       │                 │  P2PServiceImpl       │
│  (same interface)     │                 │  (same interface)     │
├──────────────────────┤                 ├──────────────────────┤
│  WebViewJsBridge      │                 │  GoBridgeClient       │
│  (JSON over postMsg)  │                 │  (JSON over platform  │
│                       │                 │   channels)           │
├──────────────────────┤                 ├──────────────────────┤
│  WebView              │                 │  Go native library    │
│  ├─ js-libp2p         │                 │  ├─ go-libp2p         │
│  │  ├─ WebSocket      │                 │  │  ├─ QUIC (primary) │
│  │  ├─ WebRTC         │                 │  │  ├─ WebSocket      │
│  │  └─ Circuit Relay  │                 │  │  ├─ Circuit Relay  │
│  ├─ @noble/post-      │                 │  │  ├─ DCUtR          │
│  │   quantum (ML-KEM) │                 │  │  └─ TCP            │
│  └─ bip39 + Ed25519   │                 │  ├─ circl (ML-KEM)   │
│     identity gen      │                 │  └─ bip39 + Ed25519   │
└──────────────────────┘                 │     identity gen      │
                                          └──────────────────────┘
                                          + bonsoir (Flutter mDNS)
```

### What Stays the Same

- `P2PService` interface — unchanged
- `IncomingMessageRouter` — unchanged
- `ChatMessageListener` / `ContactRequestListener` — unchanged
- All UI code (Screen + Wired pairs) — unchanged
- v1/v2 message envelope format — unchanged
- Database schema — unchanged
- Secure storage (SecureKeyStore) — unchanged
- DI chain pattern — unchanged

### What Changes

| Component        | Before                               | After                                        |
|------------------|--------------------------------------|----------------------------------------------|
| libp2p runtime   | WebView (js-libp2p)                  | Native (go-libp2p via gomobile)              |
| Bridge           | WebViewJsBridge (JS message passing) | GoBridgeClient (platform channels)           |
| Crypto           | JS (@noble/post-quantum + @noble/ciphers) | Go (circl ML-KEM-768 + stdlib AES-GCM) |
| Identity         | JS (bip39 + @libp2p/crypto)          | Go (tyler-smith/go-bip39 + go-libp2p/crypto) |
| Transports       | WebSocket + WebRTC                   | QUIC + WebSocket + Relay + DCUtR + TCP       |
| Local discovery  | None                                 | Native mDNS via bonsoir (Bonjour/NSD)        |
| Binary size      | ~0 (WebView is system-provided)      | +15–30 MB (Go runtime + libp2p)              |
| Platform code    | None                                 | GoBridge.swift + GoBridge.kt (thin wrappers) |

---

## Current Bridge Commands (JS → Go port required)

All bridge communication uses JSON `{ "cmd": "...", "payload": {...} }` → `{ "ok": true, ... }` pattern.

### Identity Commands

| Command | Dart caller | JS handler | Purpose |
|---------|-------------|------------|---------|
| `identity.generate` | `callJsIdentityGenerate()` | `handleIdentityGenerate()` | Generate BIP39 mnemonic → Ed25519 keypair → peerId |
| `identity.restore` | `callJsIdentityRestore()` | `handleIdentityRestore()` | Restore keypair from 12-word mnemonic |

**Identity response format:**
```json
{
  "ok": true,
  "identity": {
    "peerId": "12D3KooW...",
    "publicKey": "<base64 Ed25519 pub 32B>",
    "privateKey": "<base64 Ed25519 priv 64B>",
    "mnemonic12": "word1 word2 ... word12",
    "createdAt": "2025-11-28T12:34:56.000Z",
    "updatedAt": "2025-11-28T12:34:56.000Z"
  }
}
```

**Identity derivation chain (must be identical in Go):**
1. BIP39 mnemonic (128 bits entropy → 12 words)
2. `mnemonicToSeed(mnemonic)` → 64-byte seed
3. Ed25519 keypair from `seed[0:32]`
4. libp2p peerId from public key

### Crypto Commands

| Command | Dart caller | Purpose |
|---------|-------------|---------|
| `payload.verify` | `callJsVerifyPayload()` | Verify Ed25519 signature |
| `payload.sign` | `callJsSignPayload()` | Sign data with Ed25519 |
| `mlkem.keygen` | `callJsMlKemKeygen()` | Generate ML-KEM-768 keypair |
| `message.encrypt` | `callJsEncryptMessage()` | ML-KEM-768 encapsulate + AES-256-GCM encrypt |
| `message.decrypt` | `callJsDecryptMessage()` | ML-KEM-768 decapsulate + AES-256-GCM decrypt |

**ML-KEM-768 key sizes:**
- Public key: 1184 bytes
- Secret key: 2400 bytes
- KEM ciphertext: 1088 bytes

**Encryption flow (must be identical in Go):**
1. `ml_kem768.encapsulate(recipientPublicKey)` → `{ kemCiphertext, sharedSecret }`
2. `AES-256-GCM(sharedSecret, randomNonce12B).encrypt(plaintext)` → `aesCiphertext`
3. Return `{ kem: base64, ciphertext: base64, nonce: base64 }`

**Decryption flow:**
1. `ml_kem768.decapsulate(kemCiphertext, ownSecretKey)` → `sharedSecret`
2. `AES-256-GCM(sharedSecret, nonce).decrypt(aesCiphertext)` → `plaintext`

### P2P Node Commands

| Command | Dart caller | Purpose |
|---------|-------------|---------|
| `node:start` | `callP2PNodeStart()` | Start libp2p node with private key, relay addresses, namespace |
| `node:stop` | `callP2PNodeStop()` | Stop node |
| `node:status` | `callP2PNodeStatus()` | Health check — returns peerId, isStarted, connections |

### Rendezvous Commands

| Command | Dart caller | Purpose |
|---------|-------------|---------|
| `rendezvous:register` | `callP2PRendezvousRegister()` | Register on `mknoon:chat:<peerId>` namespace |
| `rendezvous:discover` | `callP2PRendezvousDiscover()` | Discover peer by namespace → returns addresses |

### Peer Commands

| Command | Dart caller | Purpose |
|---------|-------------|---------|
| `peer:dial` | `callP2PPeerDial()` | Connect to peer via discovered addresses |
| `peer:disconnect` | `callP2PPeerDisconnect()` | Disconnect from peer |
| `message:send` | `callP2PMessageSend()` | Send message to connected peer |

### Inbox Commands

| Command | Dart caller | Purpose |
|---------|-------------|---------|
| `inbox:store` | `callP2PInboxStore()` | Store offline message on relay for peer |
| `inbox:retrieve` | `callP2PInboxRetrieve()` | Retrieve stored messages from relay |
| `inbox:register_token` | `callP2PInboxRegisterToken()` | Register FCM push token with relay |

### Push Events (JS → Dart, asynchronous)

| Event | Callback | Purpose |
|-------|----------|---------|
| `message:received` | `onMessageReceived(ChatMessage)` | Incoming P2P message |
| `peer:connected` | `onPeerConnected(ConnectionState)` | Peer connected |
| `peer:disconnected` | `onPeerDisconnected(ConnectionState)` | Peer disconnected |

---

## Transport Stack

### Mobile (go-libp2p)

```
Priority  Transport          When used
───────── ────────────────── ─────────────────────────────────────────
1         QUIC (UDP)         Primary — fast 0-RTT, built-in encryption
2         WebSocket (TCP)    Fallback for UDP-blocked networks
3         Circuit Relay v2   NAT traversal — guaranteed connectivity
4         DCUtR              Upgrades relay → direct (QUIC/TCP hole punch)
5         TCP                Server-to-server or local network
```

### Browser (js-libp2p, unchanged)

```
Priority  Transport          When used
───────── ────────────────── ─────────────────────────────────────────
1         WebSocket          Primary browser transport
2         WebRTC             Browser-to-browser (via relay signaling)
3         Circuit Relay v2   NAT traversal
```

### Cross-Platform Interop

Mobile (QUIC) and browser (WebSocket) peers communicate through the relay server, which speaks both transports. The relay server (`go-relay-server/`) already supports QUIC + WebSocket + TCP.

---

## Encryption Layers (Independent, Transport-Agnostic)

```
Layer 1: App-level (ML-KEM-768 + AES-256-GCM)
  ↓ v2 encrypted envelope: { version: "2", encrypted: { kem, ciphertext, nonce } }
Layer 2: libp2p session (Noise protocol)
  ↓ authenticated encrypted stream
Layer 3: Transport TLS
  ↓ QUIC has TLS 1.3 built-in; WSS has TLS via nginx
Wire
```

All three layers are independent. Changing the transport (WebSocket → QUIC) does not affect app-level or session encryption.

---

## Go Library Structure (go-mknoon/)

```
go-mknoon/
├── go.mod
├── bridge/
│   ├── bridge.go           # gomobile-exported API (StartNode, StopNode, Send, etc.)
│   └── events.go           # EventCallback interface for push events
├── node/
│   ├── node.go             # go-libp2p host setup (QUIC + WS + TCP + Relay + DCUtR)
│   ├── config.go           # Transport config, relay addresses
│   └── rendezvous.go       # Rendezvous client (register, discover)
├── crypto/
│   ├── identity.go         # BIP39 mnemonic → Ed25519 keypair → peerId
│   ├── mlkem.go            # ML-KEM-768 keygen/encapsulate/decapsulate (via circl)
│   ├── encrypt.go          # ML-KEM + AES-256-GCM encrypt
│   ├── decrypt.go          # ML-KEM + AES-256-GCM decrypt
│   └── sign.go             # Ed25519 sign/verify
├── inbox/
│   ├── client.go           # Inbox protocol client (store, retrieve, register_token)
│   └── protocol.go         # 4-byte BE framing, JSON messages
└── messaging/
    ├── send.go             # Send message to peer (direct stream)
    └── receive.go          # Incoming message handler → EventCallback
```

### gomobile-Exported API (bridge/bridge.go)

```go
package bridge

// EventCallback receives async events from Go → Flutter
type EventCallback interface {
    OnEvent(jsonEvent string)  // { "event": "message:received", "data": {...} }
}

// Initialize must be called once at app startup
func Initialize(callback EventCallback) string

// Identity
func IdentityGenerate() string         // → { ok, identity }
func IdentityRestore(json string) string  // payload: { mnemonic12 }

// Crypto
func MlKemKeygen() string              // → { ok, publicKey, secretKey }
func EncryptMessage(json string) string // payload: { recipientPublicKey, plaintext }
func DecryptMessage(json string) string // payload: { secretKey, kem, ciphertext, nonce }
func SignPayload(json string) string    // payload: { privateKey, data }
func VerifyPayload(json string) string  // payload: { publicKey, data, signature }

// Node
func StartNode(json string) string     // payload: { privateKeyHex, relayAddresses, namespace }
func StopNode() string
func NodeStatus() string

// Rendezvous
func RendezvousRegister(json string) string
func RendezvousDiscover(json string) string

// Peer
func DialPeer(json string) string
func DisconnectPeer(json string) string
func SendMessage(json string) string

// Inbox
func InboxStore(json string) string
func InboxRetrieve() string
func InboxRegisterToken(json string) string
```

### Go Dependencies

```
github.com/libp2p/go-libp2p          # Core p2p (QUIC, WS, TCP, Relay, DCUtR, Noise)
github.com/cloudflare/circl           # ML-KEM-768 (FIPS 203)
github.com/tyler-smith/go-bip39       # BIP39 mnemonic generation/validation
github.com/libp2p/go-libp2p/core/crypto  # Ed25519 keypair + peerId derivation
```

### Compile with gomobile

```bash
# iOS — produces GoMknoon.xcframework
gomobile bind -target=ios -o GoMknoon.xcframework ./bridge/

# Android — produces gomknoon.aar
gomobile bind -target=android -o gomknoon.aar ./bridge/
```

---

## Flutter Integration

### GoBridgeClient (Dart)

`lib/core/bridge/go_bridge_client.dart` — implements `JsBridge` abstract interface:

```dart
class GoBridgeClient extends JsBridge {
  static const _channel = MethodChannel('com.mknoon/go_bridge');
  static const _eventChannel = EventChannel('com.mknoon/go_bridge_events');

  // Callbacks (same as WebViewJsBridge)
  void Function(ChatMessage)? onMessageReceived;
  void Function(ConnectionState)? onPeerConnected;
  void Function(ConnectionState)? onPeerDisconnected;

  Future<void> initialize() async {
    // Listen for push events from Go via EventChannel
    _eventChannel.receiveBroadcastStream().listen(_handleEvent);
    await _channel.invokeMethod('initialize');
  }

  @override
  Future<String> send(String message) async {
    // Route to specific Go method based on cmd
    final request = jsonDecode(message);
    final cmd = request['cmd'];
    final payload = jsonEncode(request['payload'] ?? {});

    final result = await _channel.invokeMethod(cmd, payload);
    return result as String;
  }
}
```

### Platform Wrappers

**iOS** — `ios/Runner/GoBridge.swift`:
- Import `GoMknoon` framework
- Register `FlutterMethodChannel("com.mknoon/go_bridge")`
- Route method calls to `GoMknoon.Bridge*()` functions
- Implement `EventCallback` protocol → send events to `FlutterEventChannel`

**Android** — `android/app/src/main/kotlin/.../GoBridge.kt`:
- Import `gomknoon.aar`
- Register `MethodChannel("com.mknoon/go_bridge")`
- Route method calls to `Bridge.*()` functions
- Implement `EventCallback` interface → send events to `EventChannel`

### DI Chain Changes

```
main.dart:
  // BEFORE:
  final bridge = WebViewJsBridge();
  await bridge.initialize();

  // AFTER:
  final bridge = GoBridgeClient();
  await bridge.initialize();

  // Everything else identical — bridge is typed as JsBridge
```

The `JsBridge` abstract interface is the seam. `P2PServiceImpl` takes `WebViewJsBridge` directly — it needs to be updated to take `JsBridge` (the abstract type) instead. Then swapping implementations is a one-line change in `main.dart`.

---

## Local Discovery (mDNS via bonsoir)

### Why not go-libp2p's built-in mDNS?

go-libp2p's mDNS uses raw UDP multicast sockets. On iOS, this requires Apple's `com.apple.developer.networking.multicast` entitlement — a special request that Apple rarely approves for App Store apps.

Instead, use Flutter's `bonsoir` package which wraps:
- **iOS**: Bonjour APIs (no special entitlement needed)
- **Android**: NSD (Network Service Discovery)

### Service Definition

- **Service type**: `_mknoon._tcp`
- **TXT record**: `peerId=12D3KooW...` (full peerId fits in 255-byte TXT limit)
- **Port**: Go node's QUIC listen port

### Flow

1. Go node starts → reports QUIC listen port to Flutter
2. Flutter starts bonsoir advertising: `_mknoon._tcp` on that port with `peerId` TXT
3. Peer discovered → Flutter calls `bridge.dialPeer(peerId, addresses: [localMultiaddr])`
4. Direct QUIC connection on LAN — no relay needed

### Platform Config

**iOS** — `ios/Runner/Info.plist`:
```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Discover contacts on your local WiFi network for faster messaging</string>
<key>NSBonjourServices</key>
<array>
  <string>_mknoon._tcp</string>
</array>
```

**Android** — `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
```

---

## Relay Server (go-relay-server/) — DONE

Already rewritten in Go and committed. Located at `go-relay-server/` in this repo.

| File | Description |
|------|-------------|
| `main.go` | libp2p node: QUIC (4002) + WS (4000) + TCP (4005) + Relay |
| `rendezvous.go` | `/canvas/rendezvous/1.0.0` — protobuf over varint-prefixed framing |
| `inbox.go` | `/mknoon/inbox/1.0.0` — JSON over 4-byte BE framing + FCM push |
| `pb.go` | Manual protobuf encode/decode (no protoc dependency) |

Same Ed25519 private key as the JS server → same Peer ID → seamless migration.

---

## BLE Transport (Future — Phase 5)

### Berty's weshnet BLE Transport

Berty built a production BLE transport for go-libp2p:
- iOS: CoreBluetooth (GATT server/client), background BLE advertising
- Android: Android BLE APIs, Nearby Connections API
- L2CAP channels for higher throughput
- Stream multiplexing over BLE's tiny MTU (~20–512 bytes)
- libp2p Noise protocol handshake over BLE

### How It Fits

BLE is just another transport — go-libp2p treats it like QUIC or WebSocket:

```
go-libp2p node
├── QUIC transport        ← internet, same WiFi
├── WebSocket transport   ← UDP-blocked networks
├── Circuit Relay v2      ← NAT fallback
├── DCUtR                 ← relay → direct upgrade
└── BLE transport         ← no WiFi, no internet, proximity only
```

Messages flow through the same pipeline regardless of transport.

### Discovery Complement

| Method          | Range             | Requires     |
|-----------------|-------------------|--------------|
| mDNS (bonsoir)  | Same WiFi network | WiFi on      |
| BLE advertising | ~10–30 meters     | Bluetooth on |

Both on → both discover → go-libp2p picks best transport.

### Additional gomobile API for BLE

```go
func StartBLE() string    // Start BLE advertising + scanning
func StopBLE() string     // Stop BLE

// EventCallback additions:
OnBLEPeerFound(json string)
OnBLEStateChanged(json string)  // Bluetooth on/off
```

### Platform Permissions for BLE

**iOS** — `Info.plist`:
```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Connect with nearby contacts via Bluetooth</string>
<key>UIBackgroundModes</key>
<array>
  <string>bluetooth-central</string>
  <string>bluetooth-peripheral</string>
</array>
```

**Android** — `AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
```

---

## Migration Phases

### Phase 1: Go Library (go-mknoon/)

1. Create `go-mknoon/` Go module
2. Implement go-libp2p node with QUIC + WebSocket + Relay + DCUtR
3. Port identity generation: BIP39 → Ed25519 → peerId (must produce same keys from same mnemonic)
4. Port ML-KEM-768 + AES-256-GCM encryption/decryption (must produce interoperable ciphertext)
5. Port rendezvous client (register/discover on relay)
6. Port inbox client (store/retrieve/register_token)
7. Port message send/receive (direct stream protocol)
8. Define gomobile-exported API (`bridge/bridge.go`)
9. Compile with gomobile: `.xcframework` (iOS) + `.aar` (Android)
10. **Verify**: Go node can talk to existing JS relay at mknoun.xyz:4001

### Phase 2: Flutter Integration

1. Create `GoBridgeClient` (Dart) with `MethodChannel` + `EventChannel`
2. Create `GoBridge.swift` (iOS) + `GoBridge.kt` (Android) platform wrappers
3. Update `P2PServiceImpl` to accept `JsBridge` (abstract) instead of `WebViewJsBridge` (concrete)
4. Swap `WebViewJsBridge` → `GoBridgeClient` in `main.dart`
5. **Verify**: existing tests pass with new bridge (same P2PService interface)

### Phase 3: Local Discovery

1. Add `bonsoir` dependency to `pubspec.yaml`
2. Create `LocalDiscoveryService` using Bonjour/NSD
3. Wire into startup: after go-libp2p starts → get QUIC port → start advertising
4. On peer discovered → `bridge.dialPeer(peerId, addresses: [localMultiaddr])`
5. iOS `Info.plist`: NSLocalNetworkUsageDescription + NSBonjourServices
6. **Verify**: two devices on same WiFi discover and message directly

### Phase 4: Relay Server Deploy

1. Deploy `go-relay-server` on EC2 alongside (or replacing) JS relay
2. Open UDP port 4002 in AWS Security Group for QUIC
3. **Verify**: mobile (QUIC) ↔ browser (WebSocket) messaging works through relay

### Phase 5: BLE (Future)

1. Integrate Berty's weshnet BLE transport into `go-mknoon/`
2. Add BLE as additional transport in go-libp2p config
3. Add `StartBLE()` / `StopBLE()` to gomobile bridge
4. Add Bluetooth permission requests in Flutter
5. **Verify**: messaging works with WiFi off, Bluetooth on

### Phase 6: Remove WebView (Mobile Only)

1. Confirm all mobile functionality works via Go bridge
2. Remove `WebViewJsBridge`, `bridge.html`, JS bundles from mobile build
3. Keep JS bundles for Flutter web build only
4. **Verify**: app size reduced, startup faster

---

## File Impact Summary

### New Files

| File | Description |
|------|-------------|
| `go-mknoon/` (entire Go module) | go-libp2p node, crypto, gomobile bridge |
| `lib/core/bridge/go_bridge_client.dart` | Dart platform channel client |
| `ios/Runner/GoBridge.swift` | iOS platform channel → Go calls |
| `android/.../GoBridge.kt` | Android platform channel → Go calls |
| `lib/core/local_discovery/local_discovery_service.dart` | Native mDNS via bonsoir |

### Modified Files

| File | Change |
|------|--------|
| `lib/main.dart` | Swap WebView init → Go bridge init |
| `lib/core/services/p2p_service_impl.dart` | Accept `JsBridge` (abstract) instead of `WebViewJsBridge` (concrete) |
| `pubspec.yaml` | Add `bonsoir` dependency |
| `ios/Runner/Info.plist` | Local network + Bonjour service declarations |
| `android/app/src/main/AndroidManifest.xml` | Multicast permission |

### Removed Files (Phase 6)

| File | Description |
|------|-------------|
| `assets/js/bridge.html` | No longer needed on mobile |
| `assets/js/core_lib.js` | Replaced by Go crypto |
| `assets/js/p2p_lib.js` | Replaced by go-libp2p |
| `lib/core/bridge/webview_js_bridge.dart` | Replaced by Go bridge |

---

## Testing Strategy

### Phase 1 Tests (Go Library)

**Unit tests** (Go `_test.go` files):
- `crypto/identity_test.go` — Generate identity, verify peerId format; restore from known mnemonic → must produce exact same peerId as JS
- `crypto/mlkem_test.go` — Keygen, encrypt/decrypt round-trip; encrypt in Go → decrypt in JS (cross-platform interop vectors)
- `crypto/encrypt_test.go` — Full envelope encrypt/decrypt; verify base64 encoding matches JS format
- `crypto/sign_test.go` — Sign/verify round-trip; verify signature from JS can be verified in Go
- `node/rendezvous_test.go` — Register/discover with mock store
- `inbox/client_test.go` — Store/retrieve with mock server

**Integration tests** (Go, against real relay):
- `integration/relay_interop_test.go` — Go node connects to `mknoun.xyz:4001`, registers, discovers, sends message
- `integration/crypto_interop_test.go` — Go encrypts → known JS test vectors decrypt correctly (and vice versa)

### Phase 2 Tests (Flutter Integration)

**Dart unit tests**:
- `test/core/bridge/go_bridge_client_test.dart` — Mock MethodChannel, verify cmd routing
- Update all existing tests that use `FakeP2PService` — should pass unchanged (interface didn't change)

**Smoke tests** (on device):
- Start app → identity generates via Go → node starts → connects to relay
- Send message to known peer → message arrives
- Receive message from known peer → appears in conversation

### Phase 3 Tests (Local Discovery)

**Dart unit tests**:
- `test/core/local_discovery/local_discovery_service_test.dart` — Mock bonsoir, verify peer map updates

**Manual device tests**:
- Two devices on same WiFi → mDNS discovers peer → direct message without relay

### Phase 4 Tests (Relay Server)

**Go tests** (already partially covered by `go-relay-server/`):
- Rendezvous register/discover round-trip
- Inbox store/retrieve round-trip
- Cross-transport: QUIC client ↔ WebSocket client via relay

**Smoke test**:
- Deploy Go relay alongside JS relay
- Mobile app connects via QUIC → registers → browser app connects via WSS → discovers → message flows

### Cross-Platform Interop Test Vectors

Critical: Go and JS must produce identical outputs for identical inputs.

| Test | Input | Expected |
|------|-------|----------|
| Identity from mnemonic | Known 12 words | Exact peerId match |
| ML-KEM encrypt→decrypt | Go encrypts, JS decrypts | Plaintext matches |
| ML-KEM encrypt→decrypt | JS encrypts, Go decrypts | Plaintext matches |
| Ed25519 sign→verify | Go signs, JS verifies | Valid |
| Ed25519 sign→verify | JS signs, Go verifies | Valid |
| v2 envelope | Go builds envelope | JS parses correctly |
