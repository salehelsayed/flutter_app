# Network Transport libp2p — Transport Layer Reference

> **Scope:** Everything between `bridge.send()` and the wire, plus the Dart-Go interface boundary.
> **Includes:** Go protocols, wire formats, bridge commands, push events, blast radius, shared Go code paths, feature flags, Go test coverage, relay architecture, timeout taxonomy, relay state machine, Dart-Go interface boundary.
> **Excludes:** Dart message routing, listeners, repos, UI widgets (see `01`), routing decision logic (see `04`).

---

## 1. Go Protocols and Wire Formats

### Protocol Registry

| Protocol | ID | Direction | Purpose |
|---|---|---|---|
| **Chat** | `/mknoon/chat/1.0.0` | Bidirectional (stream handler registered) | 1:1 real-time message delivery |
| **Inbox** | `/mknoon/inbox/1.0.0` | Outbound to relay only | Store-and-forward offline delivery (1:1 + group) |
| **Rendezvous** | `/canvas/rendezvous/1.0.0` | Outbound to relay only | Peer discovery (personal + group namespaces) |
| **Media** | `/mknoon/media/1.0.0` | Outbound to relay only | File/avatar blob transfer via relay |
| **GossipSub** | `/mknoon/group/<groupId>` | Pubsub mesh (FloodPublish) | Real-time group message delivery |

Only ChatProtocol registers an inbound stream handler. Among the stream protocols, Inbox, Rendezvous, and Media open outbound streams to the relay server; GossipSub is peer pubsub, not a relay stream.

### Frame Protocol

Chat and Inbox share the same framing: **4-byte big-endian length prefix + JSON payload**. Max frame: 128 KB.

### ACK Protocol (1:1 Chat)

After receiving a message, the receiver writes an ACK frame: `{"ack":true}` (same 4-byte framing). No NACK exists — failure to ACK is indicated by stream close/reset.

**Deferred ACK flow** (when `EnableDeferredDirectAck` is true):
1. Go receives message, emits `message:received` with `confirmNonce`
2. Go waits up to `DirectConfirmTimeout` (2s) for Dart to call `message:confirm` with that nonce
3. If Dart confirms with `ok=true` → Go writes `{"ack":true}` frame
4. If timeout or `ok=false` → Go calls `stream.Reset()` (no ACK sent) — sender sees `acked=false`

### Wire Envelope Formats

**v1 — Plaintext 1:1**
```json
{ "type": "<message_type>", "version": "1", "payload": { ... } }
```
Note: `ParseEnvelopeVersion` also treats messages with no `version` field but a non-empty `type` field as v1 (legacy fallback).

**v2 — ML-KEM-768 + AES-256-GCM Encrypted 1:1**
```json
{ "type": "<message_type>", "version": "2", "id": "...", "senderPeerId": "...", "senderUsername": "...",
  "encrypted": { "kem": "...", "ciphertext": "...", "nonce": "..." } }
```
Note: `type` varies by message kind. Outer fields beyond `version` and `encrypted` vary by subtype — `id` and `senderUsername` are specific to `chat_message`; other subtypes (reactions, deletions, group invites) include different fields. Envelope constructed in Dart, not Go (Go's V2Envelope struct is receive-only: `Version` + `Encrypted` only).

**v2 — X25519 ECDH Encrypted (Contact Requests Only)**
```json
{ "type": "contact_request", "version": "2", "intent": "<request|accept|decline>", "msgId": "...", "ts": "...",
  "senderUsername": "..." (optional),
  "encrypted": { "ephemeralPublicKey": "...", "ciphertext": "...", "nonce": "..." } }
```
Flutter constructs this outer envelope; Go's X25519 helper authenticates `msgId + "|" + ts` as AAD.

**v3 — Group AES-256-GCM + Ed25519 Signed**
```json
{ "version": "3", "type": "group_message|group_reaction", "groupId": "...", "senderId": "...",
  "senderPublicKey": "...", "signature": "...", "keyEpoch": N,
  "encrypted": { "ciphertext": "...", "nonce": "..." } }
```
Signature covers: `groupId + "|" + keyEpoch + "|" + ciphertext`. Go handles v3 encryption/signing internally.

**v3 — Inner Plaintext (after decryption)**
```json
{ "text": "...", "timestamp": "...", "username": "..." (omitempty), "extra": {} (omitempty) }
```
Go struct: `GroupMessagePayload` in `internal/group_envelope.go`. This is the schema that `group_message:received` events carry after Go decrypts the v3 envelope.

### Relay Architecture

Single default relay peer at `mknoun.xyz`, exposed via WSS `:4001` and QUIC `:4002`. Dart sends `[WSS, QUIC]` order. When `node:start` receives no relay list, Go defaults to `DefaultRelayAddress` (WSS `:4001`). The separate `RelayAddress()` helper defaults to QUIC (`:4002`) and is overridable via `MKNOON_RELAY_ADDR`.

- **AutoRelay** with `ForceReachabilityPrivate` — always seeks circuit reservations (correct for mobile NAT)
- **Circuit address**: `/<relayAddr>/p2p/<relayPeerId>/p2p-circuit/p2p/<targetPeerId>`
- **RelaySessionManager**: 6-state machine (`disconnected -> connected -> reserving -> reserved <-> degraded, cooldown`)
- **Watchdog**: The `OnRefreshFailed` / 5-consecutive-failure threshold (`WatchdogMaxConsecutiveFailures`) exists in `RelaySessionManager` but is **only exercised in tests** — no production code calls `OnRefreshFailed`. In production, relay health is event-driven: libp2p `EvtPeerConnectednessChanged` / `EvtLocalAddressesUpdated` → `syncRelaySessionFromRuntime` → state transitions to `degraded` → `relay:state` event pushed to Dart. The actual watchdog restart path is: Dart calls `relay:reconnect` → `ReconnectRelays` tries in-place re-reservation → if that fails → full host Stop+Start → returns `RecoveryResult{recoveryMode: "watchdog_restart"}` → `CompleteRecovery` sets `needsGroupRecovery=true`
- **Recovery**: in-place re-reservation first, full host Stop+Start if in-place fails
- **RelaySelector**: multi-relay ordered failover

### GossipSub Setup

- `WithFloodPublish(true)` — sends to ALL connected peers, not just mesh subset (critical for small groups)
- Topic name: `/mknoon/group/<groupId>`
- Topic validator enforces: v3 envelope, groupId matches topic, member membership, write permission (announcement groups — messages only; reactions exempt), Ed25519 signature, key epoch
- `topic.Publish()` returning nil does NOT mean delivery — fire-and-forget
- Key rotation: current + previous key with 30s grace period

### Rendezvous Protocol

Custom protobuf-encoded (not standard libp2p rendezvous), varint-prefixed via `go-msgio`.

- **Personal namespace**: `mknoon:chat:<peerId>` — registered at startup, refreshed every 30 min
- **Group namespace**: `/mknoon/group/<groupId>` — matches GossipSub topic name
- Register TTL: 2h, includes signed peer record with current multiaddrs

### Group Peer Discovery Loop

Per-group goroutine:
1. Direct-only dial known members (no relay)
2. Wait for relay ready
3. First discovery cycle (relay fallback ok): dial known members + discover via rendezvous (NO registration)
4. Wait for circuit address (hardcoded 10s literal, not `BackgroundDiscoverTimeout`)
5. Initial jitter delay (up to 3s, `GroupRecoveryInitialJitter`) — staggers burst reconnects
6. Second discovery cycle: dial known members, register namespace, discover via rendezvous
7. Periodic loop at 30s, with up to 3 warm retries at 3s intervals when partially connected
8. Adaptive exponential backoff on failures, capped at 1 min

---

## 2. Bridge Commands (MethodChannel API Surface)

### Bootstrap

| Function | Go Function | Purpose |
|---|---|---|
| `Initialize` | `Initialize(cb)` | Wire event callback to singleton node. Must be called before `StartNode`. Called from native bridge init, not via MethodChannel. Safe to call multiple times. |

### Node Lifecycle

| Command | Go Function | Purpose |
|---|---|---|
| `node:start` | `StartNode(json)` | Build host, connect relay, start pubsub |
| `node:stop` | `StopNode()` | Tear down host and all goroutines |
| `node:status` | `NodeStatus()` | Query node state (peerId, addresses, relay, connections) |

### Relay

| Command | Go Function | Purpose |
|---|---|---|
| `relay:reconnect` | `RelayReconnect()` | In-place recovery, or full restart fallback. Returns: {ok, recoveryMode (`in_place`\|`watchdog_restart`), relayState, healthyRelayCount, [errorCode], [reason]} |
| `relay:probe` | `RelayProbe(json)` | Fast circuit dial probe (5s timeout) — online check |

### Peer Discovery & Connection

| Command | Go Function | Purpose |
|---|---|---|
| `rendezvous:register` | `RendezvousRegister(json)` | Register on namespace at relay server |
| `rendezvous:discover` | `RendezvousDiscover(json)` | Discover peers on namespace |
| `peer:dial` | `DialPeer(json)` | Connect to peer with known addresses |
| `peer:disconnect` | `DisconnectPeer(json)` | Close all connections to peer |

### 1:1 Messaging

| Command | Go Function | Purpose |
|---|---|---|
| `message:send` | `SendMessage(json)` | Open ChatProtocol stream, write frame, read ACK. On stream-open failure, recovers via `ClosePeer` + `DialPeerViaRelay` + single retry. Response includes `transport` field (`"direct"` or `"relay"`) indicating which path was used |
| `message:confirm` | `ConfirmDirectMessage(json)` | Release deferred ACK (Flutter confirms receipt) |

### Offline Inbox

| Command | Go Function | Purpose |
|---|---|---|
| `inbox:store` | `InboxStore(json)` | Store message at relay for offline peer |
| `inbox:retrieve` | `InboxRetrieveWithParams(json)` | Retrieve + delete pending messages |
| `inbox:retrieve_pending` | `InboxRetrievePendingWithParams(json)` | Retrieve without deleting |
| `inbox:ack` | `InboxAck(json)` | Delete specific entries by stable ID |
| `inbox:register_token` | `InboxRegisterToken(json)` | Register FCM push token at relay |

### Media

| Command | Go Function | Purpose |
|---|---|---|
| `media:upload` | `MediaUpload(json)` | Upload blob via MediaProtocol stream |
| `media:download` | `MediaDownload(json)` | Download blob |
| `media:delete` | `MediaDelete(json)` | Delete blob from relay |
| `media:list` | `MediaList(json)` | List blobs available to this peer |
| `profile:upload` | `ProfileUpload(json)` | Upload avatar |
| `profile:download` | `ProfileDownload(json)` | Download peer avatar |

### Blob Crypto

| Command | Go Function | Purpose |
|---|---|---|
| `blob:keygen` | `BlobKeygen(json)` | Random AES-256 key |
| `blob:encrypt` | `BlobEncrypt(json)` | AES-256-GCM encrypt file on disk |
| `blob:decrypt` | `BlobDecrypt(json)` | AES-256-GCM decrypt file on disk |

### Identity & Crypto

| Command | Go Function | Purpose |
|---|---|---|
| `identity.generate` | `GenerateIdentity()` | BIP39 + Ed25519 keypair |
| `identity.restore` | `RestoreIdentity(json)` | Restore from 12-word mnemonic |
| `mlkem.keygen` | `MlKemKeygen()` | ML-KEM-768 keypair |
| `message.encrypt` | `EncryptMessage(json)` | ML-KEM-768 + AES-256-GCM encrypt |
| `message.decrypt` | `DecryptMessage(json)` | ML-KEM-768 + AES-256-GCM decrypt |
| `payload.sign` | `SignPayload(json)` | Ed25519 sign |
| `payload.verify` | `VerifyPayload(json)` | Ed25519 verify |
| `contactrequest.encrypt` | `EncryptContactRequest(json)` | X25519 ECDH + HKDF-SHA256 + AES-256-GCM |
| `contactrequest.decrypt` | `DecryptContactRequest(json)` | Corresponding decrypt |

### Group (GossipSub)

| Command | Go Function | Purpose |
|---|---|---|
| `group:create` | `GroupCreate(json)` | Generate UUID+key, join topic, return config |
| `group:join` | `GroupJoinTopic(json)` | Join existing topic with config+key |
| `group:leave` | `GroupLeaveTopic(json)` | Leave topic, cancel discovery loop |
| `group:publish` | `GroupPublish(json)` | Encrypt+sign+publish message (v3 envelope) |
| `group:publishReaction` | `GroupPublishReaction(json)` | Publish reaction |
| `group:updateConfig` | `GroupUpdateConfig(json)` | Update in-memory group config |
| `group:generateNextKey` | `GroupGenerateNextKey(json)` | Generate next key/epoch without mutating state |
| `group:rotateKey` | `GroupRotateKey(json)` | Generate + store new group key (epoch++) |
| `group:updateKey` | `GroupUpdateKey(json)` | Store received key from admin |
| `group:acknowledgeRecovery` | `GroupAcknowledgeRecovery()` | Clear needsGroupRecovery flag |
| `group.keygen` | `GenerateGroupKey()` | Generate random AES-256 group key |
| `group.encrypt` | `GroupEncryptMessage(json)` | Encrypt plaintext with group key |
| `group.decrypt` | `GroupDecryptMessage(json)` | Decrypt ciphertext with group key |

### Group Inbox

| Command | Go Function | Purpose |
|---|---|---|
| `group:inboxStore` | `GroupInboxStore(json)` | Store group message for offline members |
| `group:inboxRetrieve` | `GroupInboxRetrieve(json)` | Retrieve by groupId + since timestamp |
| `group:inboxRetrieveCursor` | `GroupInboxRetrieveCursor(json)` | Cursor-based paginated retrieval |

### Background Tasks

| Command | Purpose |
|---|---|
| `bg:begin` | Background task start (iOS: `UIApplication.beginBackgroundTask`, Android: no-op) |
| `bg:end` | Background task end (iOS: `UIApplication.endBackgroundTask`, Android: no-op) |

---

## 3. Push Events (Go -> Dart)

Delivered via a two-stage pipeline:

1. **Go EventDispatcher** — async bounded queue, capacity **1024** items. Pressure event fires at 80% (819 items). Lossless events queued FIFO; coalesced events keep only latest.
2. **Native bridge buffer** — 256-item pre-sink buffer on iOS (`GoBridge.swift`) and Android (`GoBridge.kt`). Drop-oldest on overflow. Flushed to Dart when the `EventChannel` listener attaches.

Dart receives events through `EventChannel('com.mknoon/go_bridge_events')`. An event must pass both stages to reach Dart — overflow at either stage means data loss.

### Lossless Events (queued FIFO, but still subject to overflow drop)

| Event | Key Payload Fields |
|---|---|
| `message:received` | from, to, content, timestamp, isIncoming, transport, [confirmNonce] |
| `group_message:received` | groupId, senderId, senderUsername, keyEpoch, text, timestamp, [messageId, media, quotedMessageId] |
| `group_reaction:received` | groupId, senderId, reaction |
| `peer:connected` | peerId, address, direction, limited |
| `peer:disconnected` | peerId |

### Coalesced Events (only latest retained)

| Event | Key Payload Fields |
|---|---|
| `addresses:updated` | listenAddresses, circuitAddresses, sinceStartMs (int64 ms since node start) |
| `relay:state` | relayState, relayStates (array of {peerId, state, [lastReservedAt], [lastError]}), healthyRelayCount, watchdogRestartCount, needsGroupRecovery, [lastReservationAt], [reason] |
| `media:upload_progress` | id, sentBytes, totalBytes, toPeerId |
| `group:dispatcher_pressure` | state, queueDepth, maxQueueSize, droppedCount, deliveredCount, statusCount, coalescedCount, lastEvent |
| `group:dispatcher_overflow` | state, queueDepth, maxQueueSize, droppedCount, deliveredCount, statusCount, coalescedCount, lastEvent |

### Diagnostic Events (lossless — queued FIFO, subject to overflow drop)

| Event | Purpose |
|---|---|
| `group:discovery` | 22 step values: discover_result, discover_failed, dial_success, dial_failed, dial_skipped_cooldown, dial_skipped_inflight, dial_connected_but_topic_missing, direct_dial_skipped_inflight, direct_dial_skipped_cooldown, known_member_dial_success, known_member_dial_failed, known_member_topic_missing, known_member_pre_relay_direct_success, known_member_pre_relay_direct_failed, direct_dial, pre_relay_direct_dial, registered, register_failed, initial_jitter, backoff, publish_peer_refresh_begin, publish_peer_refresh_done |
| `group:publish_debug` | groupId, messageId, topicPeers |
| `group:decryption_failed` | Incoming message can't be decrypted |
| `group:payload_parse_failed` | Decrypted but JSON payload parse failed |

---

## 4. Blast Radius of Go Changes

### CRITICAL — Affects All Features

| Go Component | Key Files | What Breaks |
|---|---|---|
| **libp2p host setup** | `node/node.go` | Everything — nothing works without the host |
| **Relay / AutoRelay** | `node/relay_session.go`, `node/relay_selector.go` | Everything — relay is the fallback for all transport |
| **Event dispatcher** | `node/event_dispatcher.go` | Primary Go -> Dart push path after startup. If it breaks, most incoming transport events stop flowing; synchronous callback fallback still exists when the dispatcher is absent |

### HIGH — Affects All 1:1 Transport

| Go Component | Key Files | What Breaks |
|---|---|---|
| **ChatProtocol stream** | `node/node.go` | All 1:1 message delivery (any envelope riding ChatProtocol) |
| **Inbox protocol** | `node/inbox.go` | All offline fallback delivery + push token registration |
| **Peer dialing** | `node/node.go` (`DialPeerViaRelay`) | All 1:1 connections + group peer discovery |
| **Rendezvous** | `node/rendezvous.go` | Peer discovery for both personal and group namespaces |

### MEDIUM — Affects Group Transport Only

| Go Component | Key Files | What Breaks |
|---|---|---|
| **GossipSub** | `node/pubsub.go` | Group live delivery (messages + reactions) |
| **Group inbox** | `node/group_inbox.go` | Group offline delivery. Note: shares `InboxProtocol` (`/mknoon/inbox/1.0.0`) stream ID with 1:1 inbox — changes to the relay's inbox handler break both |
| **Topic validator** | `node/pubsub.go` (`groupTopicValidator`) | Group message authentication + write permissions |
| **Group peer discovery loop** | `node/pubsub.go` (`groupPeerDiscoveryLoop`) | Group member connectivity |
| **Group crypto** | `internal/group_envelope.go`, crypto package | v3 envelope encrypt/decrypt/sign/verify |

### LOW — Isolated

| Go Component | Key Files | What Breaks |
|---|---|---|
| **Media protocol** | `node/media.go` | File blob + profile/avatar transfer |
| **ML-KEM crypto** | crypto package | v2 envelope encrypt/decrypt only |
| **Contact request crypto** | crypto package | Contact request encrypt/decrypt only (X25519, separate path) |
| **Blob crypto** | crypto package | File-at-rest encryption only |

---

## 5. Shared Code Paths in Go

These are used by multiple protocols — changes have wide blast radius:

| Shared Path | Used By |
|---|---|
| `writeFrame` / `readFrame` (4-byte BE framing) | ChatProtocol + InboxProtocol + GroupInboxProtocol (full messages). MediaProtocol uses framing for control messages only — blob payloads use raw `io.Copy`/`io.CopyN` without framing |
| `openChatStreamForSend` | Every 1:1 message send |
| `DialPeerViaRelay` | 1:1 send recovery + group peer discovery |
| `RendezvousRegister` / `RendezvousDiscover` | Personal namespace + group namespace |
| `eventDispatcher.Emit()` | Primary async Go -> Dart event path when the dispatcher is installed (handles both lossless and coalesced internally). `emitEvent()` falls back to synchronous callback delivery if no dispatcher is present |
| `filterAddresses` | Host address selection (affects all protocols) |
| Relay warm connection logic | All relay-dependent protocols |

---

## 6. Feature Flags

All default to `true`. Passed from Dart via `featureFlags` in `node:start`.

| Flag | Effect |
|---|---|
| `EnableSharedRelayBackend` | Shared relay state (Redis-backed) |
| `EnableMultiRelayRouting` | Failover across multiple relays |
| `EnableReservationAwareHealth` | Reservation state as relay health source-of-truth |
| `EnableInPlaceRelayRecovery` | Try re-reservation before full host restart |
| `EnableResumeGroupRecovery` | Group topic rejoin after relay recovery |
| `EnableDeferredDirectAck` | Delay chat ACK until Flutter confirms handling |

### Dart-Side Environment Overrides

Flags and relay addresses can be overridden at compile time via `--dart-define`:

| Dart Env Variable | Default | Purpose |
|---|---|---|
| `MKNOON_RELAY_ADDRESSES` | (hardcoded WSS+QUIC) | CSV override for relay multiaddrs |
| `MKNOON_ENABLE_SHARED_RELAY_BACKEND` | `true` | |
| `MKNOON_ENABLE_MULTI_RELAY_ROUTING` | `true` | |
| `MKNOON_ENABLE_RESERVATION_AWARE_HEALTH` | `true` | |
| `MKNOON_ENABLE_IN_PLACE_RELAY_RECOVERY` | `true` | |
| `MKNOON_ENABLE_RESUME_GROUP_RECOVERY` | `true` | |
| `MKNOON_ENABLE_DEFERRED_DIRECT_ACK` | `true` | |

These are read in `p2p_bridge_client.dart` via `String.fromEnvironment` / `bool.fromEnvironment` and passed to Go at `node:start`.

---

## 7. Go Test Coverage

### Unit Tests

| Component | Test Files |
|---|---|
| Node | `node_test`, `config_test`, `feature_flags_runtime_test`, `stream_timeout_test`, `transport_label_test` |
| PubSub | `pubsub_test`, `pubsub_delivery_test`, `pubsub_decryption_failure_test`, `pubsub_key_rotation_grace_test` |
| Relay | `relay_session_test`, `multi_relay_test`, `autorelay_metrics_test` |
| Inbox | `group_inbox_test` |
| Rendezvous | `rendezvous_test` |
| Bridge | `bridge_test`, `bridge_generate_next_key_test` |
| Crypto | `interop_test`, `mlkem_test`, `sign_test`, `signature_test`, `group_test`, `x25519_test`, `file_crypto_test` |
| Identity | `identity_test` |
| Internal | `group_envelope_test` |
| Recovery | `send_message_recovery_test`, `group_security_harness_test` |

### Integration Tests (Go-level)

| Test | What It Covers |
|---|---|
| `relay_test` | Relay connectivity |
| `media_test` | Media upload/download via relay |
| `profile_test` | Profile upload/download via relay |
| `multi_relay_test` | Multi-relay failover |
| `watchdog_failover_test` | Watchdog recovery path |
| `ipv6_dual_stack_test` | IPv6 + IPv4 transport |
| `personal_discoverability_test` | Rendezvous personal namespace |
| `local_relay_harness_test` | Local relay test infrastructure |

### Test Peer CLI Tests (`cmd/testpeer/`)

| Test | What It Covers |
|---|---|
| `commands_test` | CLI command handling (identity generate/restore, unknown commands) |
| `envelope_test` | Go v1 envelope format matches Flutter `MessagePayload.toJson()` wire format |

---

## 8. Essential Go Files

| File | Purpose |
|---|---|
| `go-mknoon/bridge/bridge.go` | All exported functions callable from Dart |
| `go-mknoon/bridge/events.go` | EventCallback interface |
| `go-mknoon/node/node.go` | Host construction, ChatProtocol handler, send/receive, frame I/O |
| `go-mknoon/node/config.go` | Protocol IDs, relay addresses, timeouts, constants |
| `go-mknoon/node/pubsub.go` | GossipSub init, join/leave/publish, topic validator, discovery loop |
| `go-mknoon/node/rendezvous.go` | Custom protobuf rendezvous register/discover |
| `go-mknoon/node/inbox.go` | 1:1 offline inbox store/retrieve/ack |
| `go-mknoon/node/group_inbox.go` | Group store-and-forward inbox |
| `go-mknoon/node/relay_session.go` | Per-relay state machine, watchdog, recovery |
| `go-mknoon/node/relay_selector.go` | Multi-relay failover |
| `go-mknoon/node/event_dispatcher.go` | Async bounded event queue (lossless + coalesced) |
| `go-mknoon/node/media.go` | Media/profile upload/download via relay |
| `go-mknoon/node/feature_flags.go` | Rollout flags |
| `go-mknoon/node/feature_flags_runtime.go` | Runtime feature flag read helpers (flags are immutable after `node:start`) |
| `go-mknoon/node/group.go` | GroupConfig, GroupKeyInfo types, group management |
| `go-mknoon/node/autorelay_metrics.go` | Relay health metrics and reservation tracking |
| `go-mknoon/node/personal_rendezvous_refresh.go` | Auto-register + periodic namespace refresh |
| `go-mknoon/internal/envelope.go` | v1/v2 wire format types |
| `go-mknoon/internal/group_envelope.go` | v3 group wire format |

### Crypto Package

| File | Purpose |
|---|---|
| `go-mknoon/crypto/encrypt.go` | ML-KEM-768 + AES-256-GCM message encryption (v2 envelopes) |
| `go-mknoon/crypto/decrypt.go` | ML-KEM-768 + AES-256-GCM message decryption (v2 envelopes) |
| `go-mknoon/crypto/mlkem.go` | ML-KEM-768 keypair generation (cloudflare/circl, 2400-byte secret keys for JS wire compat) |
| `go-mknoon/crypto/sign.go` | Ed25519 signature generation and verification |
| `go-mknoon/crypto/x25519.go` | X25519 ECDH for contact requests + Ed25519-to-X25519 public key conversion |
| `go-mknoon/crypto/group.go` | Group symmetric key generation + AES-256-GCM encryption/decryption |
| `go-mknoon/crypto/file_crypto.go` | File-level AES-256-GCM encryption/decryption (blob at-rest) |

### Identity Package

| File | Purpose |
|---|---|
| `go-mknoon/identity/identity.go` | BIP39 mnemonic → deterministic Ed25519 keypair + libp2p peer ID derivation |

### Test Infrastructure

| File | Purpose |
|---|---|
| `go-mknoon/cmd/testpeer/main.go` | Headless CLI test peer for E2E transport testing (JSON stdin → stdout) |
| `go-mknoon/cmd/testpeer/commands.go` | Command handler implementations for testpeer CLI |
| `go-mknoon/cmd/testpeer/envelope.go` | Envelope serialization/deserialization for testpeer |
| `go-mknoon/cmd/testpeer/listener.go` | Event listener for testpeer async message events |
| `go-mknoon/node/testhooks_integration.go` | Integration test hooks (conditional build tag: `//go:build integration`) |

### Build & Stubs

| File | Purpose |
|---|---|
| `go-mknoon/tools.go` | Build tool dependency — blank import of `golang.org/x/mobile/bind` |
| `go-mknoon/stub/gosigar/sigar.go` | iOS stub for `gosigar` (libproc.h unavailable on iOS) |




## 9. Go Timeout & Constant Taxonomy

All defined in `go-mknoon/node/config.go`.

### Base Timeouts (background / default paths)

| Constant | Value | Used By |
|---|---|---|
| `PeerDialTimeout` | 2s | Peer-to-peer dial |
| `RelayProbeTimeout` | 5s | Circuit dial probe (`relay:probe`) |
| `DialTimeout` | 15s | Relay server connection |
| `SendTimeout` | 15s | Message send operation |
| `DiscoverTimeout` | 10s | Rendezvous discovery |
| `InboxTimeout` | 15s | Inbox store/retrieve |
| `MediaTimeout` | 5 min | Media upload/download (large files) |
| `PubSubTimeout` | 30s | General pubsub operation |

### Interactive (Foreground) Timeouts

Shorter limits intended for when user is waiting for a response. **Note: these constants are defined in `config.go` but NOT yet wired into production code paths** — only referenced in tests (`config_test.go`, `stream_timeout_test.go`). Production code currently uses the base timeouts above for all paths.

| Constant | Value |
|---|---|
| `InteractiveDialTimeout` | 4s |
| `InteractiveSendTimeout` | 3s |
| `InteractiveDiscoverTimeout` | 2s |
| `InteractiveInboxTimeout` | 3s |

### Background Timeouts

| Constant | Value |
|---|---|
| `BackgroundDiscoverTimeout` | 10s |

### Stream-Level Deadlines

| Constant | Value | Purpose |
|---|---|---|
| `StreamWriteDeadline` | 10s | Per-stream write deadline |
| `StreamReadDeadline` | 10s | Per-stream read deadline |
| `InboundReadDeadline` | 15s | Inbound stream read deadline |
| `DirectConfirmTimeout` | 2s | Deferred direct ACK confirm window |

### Publish Timing

| Constant | Value | Purpose |
|---|---|---|
| `GroupPublishZeroPeerSettleWait` | 150ms | Wait before publish when 0 peers on topic |
| `GroupPublishPartialPeerSettleWait` | 500ms | Wait before publish when partial peers connected |
| `GroupPublishPeerPoll` | 25ms | Poll interval while waiting for peers |

### Discovery Loop Tuning

| Constant | Value | Purpose |
|---|---|---|
| `GroupDiscoveryInterval` | 30s | Periodic discovery loop interval |
| `GroupDiscoveryWarmInterval` | 3s | Warm retry interval |
| `GroupDiscoveryWarmRetries` | 3 | Max warm retries before fallback to full interval |
| `GroupDiscoveryConcurrency` | 5 | Max concurrent discovery goroutines |
| `GroupDiscoveryJitterFactor` | 4 | ±25% jitter on interval |
| `GroupRecoveryInitialJitter` | 3s | Initial stagger for resume/watchdog burst reconnects |
| `MaxGroupDiscoveryBackoff` | 1 min | Exponential backoff cap on failures |

### Relay Session State Machine

**Per-relay states** (6):

```
disconnected → connected ──────→ reserved ↔ degraded
                    ↑                 ↓
                    └─── cooldown ←── reserving
```
Note: `reserving` is defined as a state constant but no production code transitions INTO it — `connected` transitions directly to `reserved` via `OnReservationOpened`. The `reserving → cooldown` path exists in `OnRequestFailed` but is only exercised in tests.

| State | Meaning |
|---|---|
| `disconnected` | Initial / no transport connection |
| `connected` | Transport connected, not yet reserved |
| `reserving` | Reservation request in flight |
| `reserved` | Active circuit reservation |
| `degraded` | Lost reservation, attempting recovery |
| `cooldown` | Reservation request failed, backing off |

**Aggregate relay states** (4):

| State | Meaning |
|---|---|
| `starting` | Initial state, no relay attempts yet |
| `online` | At least one relay has active reservation |
| `recovering` | All relays degraded, recovery in progress |
| `watchdog_restart` | Watchdog triggered full host restart |

---

## 10. Dart-Go Interface Boundary

> **Scope:** Transport-relevant details on the Dart side of the MethodChannel/EventChannel bridge.

### Platform Channels

| Channel | Type | Purpose |
|---|---|---|
| `com.mknoon/go_bridge` | MethodChannel | Request-response RPC calls |
| `com.mknoon/go_bridge_events` | EventChannel | Push events from Go |

### Dart-Level Timeouts

Where present, Dart bridge helpers apply their own `.timeout()` independently of Go's internal timeouts. Several P2P/control helpers intentionally rely only on Go-side timeouts:

| Category | Timeout | Commands |
|---|---|---|
| Identity | 30s | `identity.generate`, `identity.restore`, `mlkem.keygen` |
| Crypto | 10s | `message.encrypt/decrypt`, `payload.sign/verify`, `contactrequest.encrypt/decrypt` |
| Media/Blob | 5 min | `media:upload/download`, `profile:upload/download`, `blob:encrypt/decrypt` |
| Media metadata | 15s | `media:delete`, `media:list` |
| Groups | 10–30s | `group:create/join/leave` (30s), all others (10s). Note: `callGroupJoinWithConfig` is a Dart helper that sends `group:join` with extra payload, not a separate command |
| Blob keygen | 10s | `blob:keygen` |
| P2P operations | No Dart timeout | `node:start/stop/status`, `peer:dial`, `message:send`, `inbox:*` (Go timeouts apply) |

### Error Response Schema

All bridge responses follow a standard schema:

```json
{ "ok": true|false, "errorCode": "...", "errorMessage": "...", ...fields }
```

Dart timeout errors are standardized as `errorCode: "BRIDGE_TIMEOUT"`.

### Broadcast Streams (beyond callbacks)

Two additional Dart-side streams not covered by the `Bridge` callback properties:

| Stream | Source Events | Purpose |
|---|---|---|
| `mediaUploadProgressStream` | `media:upload_progress` | UI progress indicators for file uploads |
| `groupDiagnosticEventStream` | `group:decryption_failed`, `group:payload_parse_failed`, `group:dispatcher_pressure`, `group:dispatcher_overflow` | Group diagnostic monitoring |

### Key Dart Files

| File | Purpose |
|---|---|
| `lib/core/bridge/bridge.dart` | Abstract `Bridge` interface + identity/crypto/blob helper functions |
| `lib/core/bridge/go_bridge_client.dart` | `GoBridgeClient` — MethodChannel/EventChannel implementation, event dispatch |
| `lib/core/bridge/p2p_bridge_client.dart` | P2P helper functions — node, relay, peer, messaging, inbox, media, profile |
| `lib/core/bridge/bridge_group_helpers.dart` | Group helper functions — create, join, leave, publish, key rotation, group inbox |

### Native Bridge Wrappers

Three platform-specific wrappers route MethodChannel calls to Go and buffer events:

| File | Platform | Notes |
|---|---|---|
| `ios/Runner/GoBridge.swift` | iOS | Full bridge + `UIApplication.beginBackgroundTask` for `bg:begin/end` + 256-item event buffer |
| `android/.../GoBridge.kt` | Android | Full bridge + no-op `bg:begin/end` + 256-item event buffer |
| `macos/Runner/MainFlutterWindow.swift` | macOS | Full bridge but **missing `groupGenerateNextKey` handler** (falls to `FlutterMethodNotImplemented`) and no `bg:begin/end` handlers |

**Known macOS gap:** `group:generateNextKey` is handled on iOS (line 149) and Android (line 117) but the macOS `switch` jumps from `groupUpdateConfig` directly to `groupRotateKey`, skipping it.

### FLOW Telemetry

Most bridge helpers emit structured `emitFlowEvent()` telemetry. A repo-wide search over `lib/core/bridge/*` currently yields 110 distinct event names (e.g. `P2P_NODE_START_REQUEST`, `GROUP_FL_BRIDGE_PUBLISH_RESPONSE`), and emitted events are tagged with `layer: 'FL'`. Utility helpers such as `bg:begin` / `bg:end` do not participate, and some helpers emit only request-side telemetry.

---

## Recommended Approach for Tracking Changes

Use this file as a transport reference matrix only. For performance analysis, see `03-timing-and-performance.md`; for routing decisions, see `04-transport-routing-strategy.md`.
