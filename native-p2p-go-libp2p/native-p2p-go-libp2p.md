# Native P2P Migration: WebView js-libp2p to go-libp2p via gomobile

## 1. Why

The current architecture runs js-libp2p inside a Flutter WebView. This works but has fundamental limitations:

| Limitation | Root cause |
|------------|-----------|
| No mDNS local discovery | Browsers lack UDP multicast sockets |
| No QUIC transport | WebView only supports WebSocket and WebRTC |
| No BLE transport | No Bluetooth API in WebView |
| WebView startup overhead | ~2-3s cold start loading JS bundles |
| file:// lacks crypto.subtle | Forced to use pure-JS crypto (@noble/ciphers) instead of native AES-NI |
| iOS multicast entitlement | Apple requires special entitlement for raw UDP multicast |

Moving to go-libp2p compiled via gomobile eliminates all of these.

## 2. Architecture Overview

### Before

```
Flutter App
├── WebView (hidden)
│   ├── js-libp2p node
│   │   ├── WebSocket transport
│   │   └── WebRTC transport (via relay)
│   ├── @noble/post-quantum (ML-KEM-768)
│   ├── @noble/ciphers (AES-256-GCM)
│   ├── bip39 + @libp2p/crypto (identity)
│   └── rendezvous client
├── JsBridge (postMessage ↔ JSON)
├── P2PServiceImpl → bridge
├── Listeners (ChatMessage, ContactRequest)
└── UI (Wired + Screen)
```

### After (Mobile)

```
Flutter App
├── Go Library (.xcframework / .aar via gomobile)
│   ├── go-libp2p node
│   │   ├── QUIC transport (primary)
│   │   ├── WebSocket transport (fallback)
│   │   ├── Circuit Relay v2 (guaranteed fallback)
│   │   ├── DCUtR (relay → direct upgrade)
│   │   └── BLE transport (future, via Berty weshnet)
│   ├── circl (ML-KEM-768)
│   ├── crypto/aes (AES-256-GCM, hardware-accelerated)
│   ├── bip39 + ed25519 (identity)
│   └── rendezvous client
├── GoBridgeClient (MethodChannel + EventChannel)
├── Native mDNS (bonsoir → Bonjour/NSD)
├── P2PServiceImpl → GoBridgeClient (same interface)
├── Listeners (unchanged)
└── UI (unchanged)
```

### After (Web — unchanged)

```
Flutter Web
├── js-libp2p node (same as today)
│   ├── WebSocket transport
│   └── WebRTC transport
├── JsBridge (same postMessage protocol)
└── Everything else identical
```

## 3. Transport Stack

### Priority order (mobile)

| Priority | Transport | When used |
|----------|-----------|-----------|
| 1 | QUIC (UDP) | Default for all connections — fast, multiplexed, 0-RTT |
| 2 | WebSocket (TCP) | Fallback when UDP is blocked (corporate firewalls, some carriers) |
| 3 | Circuit Relay v2 | When both peers are behind NAT and direct connection fails |
| 4 | DCUtR | Upgrades relay connections to direct via coordinated hole-punch |
| 5 | BLE | Future — proximity messaging without any network |

### Cross-platform interop

Mobile (go-libp2p) and browser (js-libp2p) peers interoperate through the relay server:

```
Mobile A ──QUIC──► Relay Server ◄──WebSocket── Browser B
                      │
                Circuit Relay v2
                      │
              Mobile A ◄──────► Browser B
```

Both connect to the same relay with the same Peer ID. The relay bridges protocols transparently.

### Encryption layers (independent, transport-agnostic)

| Layer | Protocol | Purpose |
|-------|----------|---------|
| App-level | ML-KEM-768 + AES-256-GCM | E2E message encryption (v2 envelope) |
| libp2p session | Noise protocol | Stream authentication + encryption |
| Transport | TLS 1.3 (QUIC) / TLS (WSS) | Wire encryption |

All three layers work independently. Changing transport does not affect app encryption.

## 4. Go Library Structure (go-mknoon/)

```
go-mknoon/
├── go.mod
├── bridge/
│   ├── bridge.go           # gomobile-exported API (all public functions)
│   └── events.go           # EventCallback interface for Go → Flutter events
├── node/
│   ├── node.go             # go-libp2p host setup (QUIC + WS + Relay + DCUtR)
│   ├── config.go           # Transport config, announce addrs, bootstrap peers
│   └── rendezvous.go       # Rendezvous client (register, discover)
├── crypto/
│   ├── mlkem.go            # ML-KEM-768 keygen, encapsulate, decapsulate (circl)
│   ├── envelope.go         # v1/v2 envelope encrypt/decrypt
│   └── aes_gcm.go          # AES-256-GCM encrypt/decrypt
├── identity/
│   ├── generate.go         # BIP39 mnemonic + Ed25519 keypair + PeerId
│   └── restore.go          # Restore from mnemonic
├── inbox/
│   └── client.go           # Inbox protocol client (store, retrieve)
└── ble/                    # Future
    ├── transport.go        # Wraps Berty weshnet BLE transport
    ├── driver_ios.go       # iOS CoreBluetooth callbacks
    └── driver_android.go   # Android BLE callbacks
```

### gomobile-exported API (bridge/bridge.go)

Every function takes and returns JSON strings (gomobile constraint — no complex types across FFI boundary).

```go
// --- Identity ---
func GenerateIdentity() string
// Returns: { "ok": true, "identity": { "peerId", "publicKey", "privateKey", "mnemonic12", "createdAt", "updatedAt" } }

func RestoreIdentity(mnemonic12JSON string) string
// Input:  { "mnemonic12": "word1 word2 ... word12" }
// Returns: same as GenerateIdentity

// --- Crypto ---
func MlKemKeygen() string
// Returns: { "ok": true, "publicKey": "<base64>", "secretKey": "<base64>" }

func EncryptMessage(paramsJSON string) string
// Input:  { "recipientPublicKey": "<base64>", "plaintext": "..." }
// Returns: { "ok": true, "kem": "<base64>", "ciphertext": "<base64>", "nonce": "<base64>" }

func DecryptMessage(paramsJSON string) string
// Input:  { "secretKey": "<base64>", "kem": "<base64>", "ciphertext": "<base64>", "nonce": "<base64>" }
// Returns: { "ok": true, "plaintext": "..." }

// --- P2P Node ---
func StartNode(configJSON string) string
// Input:  { "privateKey": "<base64>", "relayAddr": "/dns4/mknoun.xyz/...", "namespace": "mknoon" }
// Returns: { "ok": true, "peerId": "12D3KooW..." }

func StopNode() string

func SendMessage(paramsJSON string) string
// Input:  { "to": "<peerId>", "content": "<v1/v2 envelope JSON>" }
// Returns: { "ok": true, "method": "direct|relay|inbox" }

func ConnectPeer(multiaddr string) string
// For local discovery: connect to a peer by multiaddr

// --- Push ---
func RegisterPushToken(paramsJSON string) string
// Input:  { "token": "...", "platform": "ios|android" }

// --- Lifecycle ---
func HealthCheck() string
// Returns: { "connected": true, "relayConnected": true, "peers": 3 }

// --- Events (Go → Flutter) ---
type EventCallback interface {
    OnMessage(json string)          // incoming message
    OnPeerConnected(json string)    // peer came online
    OnPeerDisconnected(json string) // peer went offline
    OnNodeStarted(json string)      // node ready
    OnNodeError(json string)        // node error
    OnFlowEvent(json string)        // structured logging
}

func SetEventCallback(cb EventCallback)
```

### Wire format compatibility

The Go library MUST produce identical wire bytes as the JS library for:

| Format | Spec |
|--------|------|
| v1 envelope | `{ "type": "chat", "version": "1", "payload": { "id", "content", "timestamp" } }` |
| v2 envelope | `{ "version": "2", "encrypted": { "kem": "<b64>", "ciphertext": "<b64>", "nonce": "<b64>" } }` |
| ML-KEM-768 | FIPS 203 — public key 1184 bytes, secret key 2400 bytes, ciphertext 1088 bytes |
| BIP39 | 128-bit entropy → 12 English words, PBKDF2 seed derivation |
| Ed25519 | RFC 8032 — same seed → same keypair |
| PeerId | libp2p peer ID from Ed25519 public key (multihash + multicodec) |
| Rendezvous | `/canvas/rendezvous/1.0.0` — protobuf over varint-prefixed framing |
| Inbox | `/mknoon/inbox/1.0.0` — JSON over 4-byte BE length-prefixed framing |

### Go dependencies

| Dependency | Purpose |
|-----------|---------|
| `github.com/libp2p/go-libp2p` | P2P networking (QUIC, WS, Relay, DCUtR, Noise) |
| `github.com/cloudflare/circl` | ML-KEM-768 (FIPS 203) |
| `github.com/tyler-smith/go-bip39` | BIP39 mnemonic generation/validation |
| `golang.org/x/mobile/cmd/gomobile` | Cross-compile to .xcframework / .aar |
| `github.com/libp2p/go-msgio` | Varint-prefixed framing (rendezvous protocol) |

## 5. Flutter Integration

### GoBridgeClient (Dart)

Replaces `JsBridge` with platform channels to the Go library:

```dart
// lib/core/bridge/go_bridge_client.dart

class GoBridgeClient implements JsBridge {
  static const _channel = MethodChannel('com.mknoon/go-bridge');
  static const _eventChannel = EventChannel('com.mknoon/go-bridge-events');

  @override
  Future<String> send(String message) async {
    // Route to appropriate Go function based on cmd
    final request = jsonDecode(message);
    final cmd = request['cmd'] as String;

    switch (cmd) {
      case 'identity.generate':
        return await _channel.invokeMethod('GenerateIdentity', '{}');
      case 'identity.restore':
        return await _channel.invokeMethod('RestoreIdentity', jsonEncode(request['payload']));
      case 'mlkem.keygen':
        return await _channel.invokeMethod('MlKemKeygen', '{}');
      case 'message.encrypt':
        return await _channel.invokeMethod('EncryptMessage', jsonEncode(request['payload']));
      case 'message.decrypt':
        return await _channel.invokeMethod('DecryptMessage', jsonEncode(request['payload']));
      default:
        return jsonEncode({'ok': false, 'errorCode': 'UNKNOWN_COMMAND'});
    }
  }

  // P2P operations (not part of JsBridge interface — used by P2PServiceImpl directly)
  Future<String> startNode(String configJSON) => _channel.invokeMethod('StartNode', configJSON);
  Future<String> stopNode() => _channel.invokeMethod('StopNode', '{}');
  Future<String> sendMessage(String paramsJSON) => _channel.invokeMethod('SendMessage', paramsJSON);
  Future<String> connectPeer(String multiaddr) => _channel.invokeMethod('ConnectPeer', multiaddr);
  Future<String> registerPushToken(String paramsJSON) => _channel.invokeMethod('RegisterPushToken', paramsJSON);
  Future<String> healthCheck() => _channel.invokeMethod('HealthCheck', '{}');

  Stream<Map<String, dynamic>> get eventStream =>
    _eventChannel.receiveBroadcastStream().map((e) => jsonDecode(e as String));
}
```

### Platform wrappers

**iOS — `ios/Runner/GoBridge.swift`**:
```swift
import Flutter
import Gomknoon  // Generated .xcframework

class GoBridge: NSObject, FlutterPlugin, GomknoonEventCallbackProtocol {
    static func register(with registrar: FlutterPluginRegistrar) { ... }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "GenerateIdentity": result(GomknoonGenerateIdentity())
        case "RestoreIdentity": result(GomknoonRestoreIdentity(call.arguments as! String))
        case "StartNode": result(GomknoonStartNode(call.arguments as! String))
        // ... etc
        }
    }

    // EventCallback — Go calls these, we push to EventChannel
    func onMessage(_ json: String) { eventSink?(json) }
    func onPeerConnected(_ json: String) { eventSink?(json) }
    // ...
}
```

**Android — `android/.../GoBridge.kt`**: Same pattern with `MethodChannel` + `EventChannel`.

### DI chain changes

```
Before: ProductionJsBridge → main.dart → StartupRouter → IdentityChoiceWired
After:  GoBridgeClient     → main.dart → StartupRouter → IdentityChoiceWired
```

The `JsBridge` interface stays the same. Only `main.dart` changes which implementation it creates:

```dart
// main.dart — the only line that changes
final bridge = GoBridgeClient();  // was: ProductionJsBridge()
```

For feature branches with P2PService (UI-4+), `P2PServiceImpl` would take `GoBridgeClient` directly for P2P operations (startNode, sendMessage, etc.) in addition to the `JsBridge` interface for crypto/identity.

## 6. Local Discovery (mDNS via bonsoir)

### Why bonsoir instead of go-libp2p's built-in mDNS

go-libp2p's mDNS uses raw UDP multicast sockets. On iOS, this requires Apple's `com.apple.developer.networking.multicast` entitlement — a special entitlement that requires justification to Apple and may be rejected. The `bonsoir` Flutter package uses platform-native APIs (Bonjour on iOS, NSD on Android) which don't need this entitlement.

### Service advertisement

| Field | Value |
|-------|-------|
| Service type | `_mknoon._tcp` |
| Port | Go node's QUIC listening port |
| TXT record | `peerId=12D3KooW...` (full peer ID) |

### Flow

1. Go node starts → returns QUIC port
2. Flutter starts `bonsoir` advertising with peerId + port
3. `bonsoir` discovers peers on same WiFi
4. Flutter calls `bridge.connectPeer("/ip4/$ip/udp/$port/quic-v1")` for discovered peers
5. Direct QUIC connection established — no relay needed

### Platform config

**iOS (Info.plist)**:
```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Discover contacts on your local WiFi network for faster messaging</string>
<key>NSBonjourServices</key>
<array>
  <string>_mknoon._tcp</string>
</array>
```

**Android (AndroidManifest.xml)**:
```xml
<uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
```

## 7. Relay Server (go-relay-server/ — DONE)

The JS relay server has been rewritten in Go. Located at `go-relay-server/`.

### What changed

| Aspect | JS server | Go server |
|--------|-----------|-----------|
| Transports | WebSocket + TCP + WebRTC | **QUIC** + WebSocket + TCP |
| Runtime | Node.js | Native binary |
| Binary | ~0 (interpreted) | ~43 MB |
| Same Peer ID | Yes (hardcoded Ed25519 key) | Yes (same key bytes) |

### Ports

| Port | Protocol | Notes |
|------|----------|-------|
| 4000 | WebSocket (WS) | nginx proxies WSS:4001 → WS:4000 |
| 4001 | WSS (announced) | Via nginx TLS termination |
| 4002 | QUIC (new) | Direct UDP — primary for mobile clients |
| 4005 | TCP | Direct TCP connections |

### Files

| File | Description |
|------|-------------|
| `main.go` | Node setup with QUIC + WS + TCP, Circuit Relay v2, connection events |
| `rendezvous.go` | `/canvas/rendezvous/1.0.0` — register/unregister/discover with in-memory store |
| `inbox.go` | `/mknoon/inbox/1.0.0` — store/retrieve + FCM push notifications |
| `pb.go` | Manual protobuf marshal/unmarshal (no protoc dependency) |
| `proto/rendezvous.proto` | Reference proto definition |

### Deployment

```bash
GOOS=linux GOARCH=amd64 go build -o relay-server .
scp relay-server ec2-user@13.60.15.36:~/
# Run with systemd (see deployment docs)
# Open UDP 4002 in AWS Security Group for QUIC
```

## 8. BLE Transport (Future — Phase 5)

### Berty's weshnet

Berty built a production BLE transport for go-libp2p:
- iOS: CoreBluetooth (GATT server/client), background BLE advertising
- Android: Android BLE APIs, Nearby Connections as bonus transport
- L2CAP channels for higher throughput than GATT characteristics
- Stream multiplexing over BLE's tiny MTU (~20-512 bytes)
- Noise protocol handshake over BLE

### How it fits

BLE is just another go-libp2p transport:

```
go-libp2p node
├── QUIC transport         ← internet, same WiFi
├── WebSocket transport    ← UDP-blocked networks
├── Circuit Relay v2       ← NAT fallback
├── DCUtR                  ← relay → direct upgrade
└── BLE transport          ← no WiFi, no internet, proximity only
```

### Discovery comparison

| Method | Range | Requires |
|--------|-------|----------|
| Rendezvous (relay) | Global | Internet |
| mDNS (bonsoir) | Same WiFi | WiFi on |
| BLE advertising | ~10-30 meters | Bluetooth on |

All three feed discovered peers into go-libp2p. They complement each other.

### Platform permissions

**iOS (Info.plist)**:
```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Connect with nearby contacts via Bluetooth</string>
<key>UIBackgroundModes</key>
<array>
  <string>bluetooth-central</string>
  <string>bluetooth-peripheral</string>
</array>
```

**Android (AndroidManifest.xml)**:
```xml
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
```

## 9. Migration Phases

### Phase 1: Go Library (go-mknoon/)

1. Create `go-mknoon/` Go module
2. Implement go-libp2p node with QUIC + WebSocket + Relay + DCUtR
3. Port identity generation (BIP39 + Ed25519 + PeerId) from `core_lib_js/src/identity/`
4. Port ML-KEM-768 keygen/encrypt/decrypt from `core_lib_js/src/crypto/`
5. Port rendezvous client from `core_lib_js/src/p2p/`
6. Port inbox client
7. Define gomobile-exported API (`bridge/bridge.go`)
8. Write Go unit tests for crypto wire-format compatibility
9. Compile with gomobile: `.xcframework` (iOS) + `.aar` (Android)
10. **Verify**: Go-generated identity matches JS-generated identity for same mnemonic

### Phase 2: Flutter Integration

1. Create `GoBridgeClient` (Dart) with MethodChannel + EventChannel
2. Create `GoBridge.swift` (iOS) platform wrapper
3. Create `GoBridge.kt` (Android) platform wrapper
4. Swap `ProductionJsBridge()` → `GoBridgeClient()` in `main.dart`
5. **Verify**: existing tests pass with new bridge (same `JsBridge` interface)

### Phase 3: Local Discovery

1. Add `bonsoir` dependency to `pubspec.yaml`
2. Create `LocalDiscoveryService` using Bonjour/NSD APIs
3. Wire into startup: after Go node starts → get QUIC port → start advertising
4. On peer discovered → `bridge.connectPeer(multiaddr)`
5. Add iOS `Info.plist` entries (NSLocalNetworkUsageDescription + NSBonjourServices)
6. **Verify**: two devices on same WiFi discover and message directly

### Phase 4: Relay Server Update (DONE)

Go relay server written in `go-relay-server/` with QUIC support.

1. ~~Rewrite relay server in Go~~ Done
2. Deploy Go relay alongside JS relay (both produce same Peer ID)
3. Open UDP 4002 in AWS Security Group
4. **Verify**: mobile (QUIC) + browser (WebSocket) messaging works through relay

### Phase 5: BLE (Future)

1. Add `berty.tech/weshnet` dependency to `go-mknoon/go.mod`
2. Create BLE transport wrapper in `go-mknoon/ble/`
3. Add BLE as transport in go-libp2p node config
4. Add `StartBLE()` / `StopBLE()` to gomobile bridge
5. Add `GoBridgeClient.startBLE()` / `stopBLE()` in Dart
6. Add Bluetooth permission requests in Flutter
7. Add BLE toggle in app settings UI
8. **Verify**: messaging works with WiFi off, Bluetooth on

### Phase 6: Remove WebView

1. Confirm all mobile functionality works via Go bridge
2. Remove `ProductionJsBridge`, JS bundles from mobile build
3. Keep JS bundles for Flutter web build only
4. **Verify**: app size reduced, startup faster

## 10. What Stays the Same

- `JsBridge` interface — unchanged (GoBridgeClient implements it)
- `P2PService` interface — unchanged
- `IncomingMessageRouter` — unchanged
- `ChatMessageListener` — unchanged
- `ContactRequestListener` — unchanged
- All UI code (Wired + Screen) — unchanged
- v1/v2 envelope format — unchanged
- Database schema — unchanged
- Secure storage — unchanged
- DI chain pattern — unchanged
- `emitFlowEvent()` structured logging — unchanged

## 11. What Changes

| Component | Before | After |
|-----------|--------|-------|
| libp2p runtime | WebView (js-libp2p) | Native (go-libp2p via gomobile) |
| Bridge | JsBridge (JS postMessage) | GoBridgeClient (platform channels) |
| Crypto | JS (@noble/post-quantum, @noble/ciphers) | Go (circl + crypto/aes) |
| Identity | JS (bip39 + @libp2p/crypto) | Go (go-bip39 + ed25519) |
| Transports | WebSocket + WebRTC | QUIC + WebSocket + Relay + DCUtR |
| Local discovery | None | Native mDNS via bonsoir |
| Binary size | ~0 (WebView is system) | +15-30 MB (Go runtime + libp2p) |
| Platform code | None | GoBridge.swift + GoBridge.kt |

## 12. File Impact Summary

### New files

| File | Description |
|------|-------------|
| `go-mknoon/` (entire module) | Go library: node, crypto, identity, bridge |
| `lib/core/bridge/go_bridge_client.dart` | Dart platform channel client |
| `ios/Runner/GoBridge.swift` | iOS platform wrapper |
| `android/.../GoBridge.kt` | Android platform wrapper |
| `lib/core/local_discovery/local_discovery_service.dart` | Native mDNS via bonsoir |

### Modified files

| File | Change |
|------|--------|
| `lib/main.dart` | `ProductionJsBridge()` → `GoBridgeClient()` |
| `pubspec.yaml` | Add `bonsoir` dependency |
| `ios/Runner/Info.plist` | Local network + Bonjour service entries |
| `android/.../AndroidManifest.xml` | Multicast permission |
| `ios/Podfile` | Link Go `.xcframework` |
| `android/app/build.gradle` | Link Go `.aar` |

### Removed files (Phase 6)

| File | Description |
|------|-------------|
| `assets/js/bridge.html` | No longer needed on mobile |
| `assets/js/core_lib.js` | Replaced by Go crypto |
| `assets/js/p2p_lib.js` | Replaced by go-libp2p |
| `ProductionJsBridge` class in main.dart | Replaced by GoBridgeClient |

## 13. Security

### Threat model for local connections

| Threat | Mitigation |
|--------|-----------|
| Spoofed `from` peerId | v2 ML-KEM encryption: attacker can't produce valid ciphertext without sender's key |
| Unknown sender | `handleIncomingChatMessage` rejects senders not in contacts list |
| Eavesdropping on local WiFi | v2 envelope is AES-256-GCM encrypted; Noise protocol on libp2p stream |
| BLE sniffing | Same v2 encryption applies; Noise handshake over BLE |
| WS flood/DoS (local) | Rate-limit connections per IP; max concurrent connections |

### Key insight

The v2 encrypted envelope + contact list check means that even over an unencrypted local transport, messages are safe. The encryption is at the application layer, not the transport layer.
