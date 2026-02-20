# mknoon

A Flutter mobile application with a Go native library (via gomobile) implementing cryptographic identity management, peer-to-peer networking (libp2p), end-to-end encrypted messaging (ML-KEM-768 + AES-256-GCM), contact exchange via QR codes, a conversation feed, orbit-based contact management, and push notifications.

---

## Features

- **Identity Management** -- Generate or restore a cryptographic identity from a 12-word BIP39 mnemonic. Ed25519 keypair, libp2p peer ID, and ML-KEM-768 post-quantum keys are all derived or generated at identity creation time. Secrets are stored in platform secure storage (iOS Keychain / Android EncryptedSharedPreferences).
- **P2P Networking** -- Fully native libp2p node (Go) with QUIC + WebSocket transports, circuit relay v2 for NAT traversal, and rendezvous-based peer discovery. Local WiFi delivery via mDNS + WebSocket for same-network peers.
- **QR Code Contact Exchange** -- Display a signed QR payload containing your public key, peer ID, rendezvous address, and ML-KEM public key. Scan another user's QR to send a verified contact request.
- **Contact Requests** -- Incoming contact requests are received over P2P, signature-verified, and stored locally. Users can accept (promoting to contact) or decline.
- **Conversations** -- Letter-card UI for one-to-one messaging. Messages are encrypted end-to-end when both parties have ML-KEM keys (v2 envelope), or sent as plaintext (v1 envelope) otherwise. Failed messages are automatically retried when connectivity returns.
- **Feed** -- Incoming message feed showing thread-grouped cards per contact, with unread badges and time-gap dividers. Serves as the primary home screen for returning users.
- **Orbit** -- Contact management screen with active/archived/blocked views, search, and swipe actions (archive, block, delete). Orbital visualization of your peer network.
- **Push Notifications** -- Firebase Cloud Messaging (FCM) integration. The relay server stores offline messages and sends push notifications. On resume, the app drains the offline inbox.
- **Data-at-Rest Encryption** -- SQLCipher-encrypted database with a random 256-bit key stored in platform secure storage. One-time migration moves legacy plaintext secrets out of the database.

---

## Application Flow

```
                              +---------------------+
                              |     APP LAUNCH      |
                              |     main.dart       |
                              +----------+----------+
                                         |
                    +--------------------+--------------------+
                    |                    |                    |
                    v                    v                    v
            +--------------+    +--------------+    +--------------+
            | SecureKeyStore|    | Open/Create  |    |   Create     |
            | (Keychain /   |    |  Encrypted   |    |  Go Bridge   |
            |  EncSharedPref|    |   Database   |    |  (gomobile)  |
            +--------------+    +------+-------+    +--------------+
                                       |
                                       v
                              +--------------------+
                              |  Run Migrations    |
                              |  (v1..v8)          |
                              +--------------------+
                                       |
                                       v
                              +--------------------+
                              | Migrate Secrets    |
                              | DB -> SecureStorage|
                              +--------------------+
                                       |
                                       v
                    +------------------+-------------------+
                    |  Create DI chain:                    |
                    |  Repos, Bridge, P2PService,          |
                    |  MessageRouter, Listeners, Retrier   |
                    +------------------+-------------------+
                                       |
                                       v
                              +--------------------+
                              |   StartupRouter    |
                              |  (Loading Screen)  |
                              +--------+-----------+
                                       |
                              +--------+----------+
                              | decideStartupRoute|
                              +--------+----------+
                                       |
              +------------------------+-------------------------+
              |                        |                         |
              v                        v                         v
  +-------------------+   +--------------------+   +--------------------+
  | hasIdentity       |   | hasIdentity        |   | needsIdentity      |
  | WithContacts      |   | NoContacts         |   |                    |
  |                   |   |                    |   | -> IdentityChoice  |
  | -> FeedWired      |   | -> FirstTimeExp.   |   |    (New / Restore) |
  +-------------------+   +--------------------+   +--------------------+
              |                        |                         |
              +------------------------+-------------------------+
                                       |
                              (background, post-navigation)
                                       |
                    +------------------+-------------------+
                    |                                      |
                    v                                      v
          +--------------------+              +------------------------+
          | Start P2P Node     |              | Register FCM Push      |
          | (Go libp2p)        |              | Token with Relay       |
          +--------------------+              +------------------------+
```

---

## Architecture

```
+---------------------------------------------------------------------------------+
|                                 FLUTTER APP                                     |
|                                                                                 |
|  +-------------------------------------------------------------------------+   |
|  |                         PRESENTATION LAYER                               |   |
|  |                                                                          |   |
|  |  StartupRouter  FeedWired   OrbitWired   ConversationWired               |   |
|  |  IdentityChoice FirstTimeExp QRScanner   QRDisplay                       |   |
|  |  MnemonicInput  ConnectionStatusIndicator PendingRequestsBadge           |   |
|  |                                                                          |   |
|  |  Pattern: pure Screen (StatelessWidget) + Wired (StatefulWidget)         |   |
|  +----+----------------------------+----------------------------+-----------+   |
|       |                            |                            |               |
|  +----v----------------------------v----------------------------v-----------+   |
|  |                       APPLICATION LAYER (Use Cases)                       |   |
|  |                                                                           |   |
|  |  Identity:     generateIdentity, restoreIdentity, decideStartupRoute     |   |
|  |  Contacts:     addContact, archiveContact, unarchiveContact,             |   |
|  |                blockContact, unblockContact, deleteContact               |   |
|  |  Requests:     sendContactRequest, handleIncomingMessage,                |   |
|  |                acceptContactRequest, declineContactRequest               |   |
|  |  Conversation: sendChatMessage, handleIncomingChatMessage,               |   |
|  |                loadConversation, markConversationRead, retryFailed       |   |
|  |  Feed:         loadFeed                                                  |   |
|  |  Orbit:        loadOrbitData                                             |   |
|  |  P2P:          startNode, stopNode, sendMessage, discoverPeer            |   |
|  |  QR Code:      buildQRPayload, parseQRPayload                           |   |
|  |  Push:         requestPushPermission, registerPushToken                  |   |
|  +----+----------------------------+----------------------------+-----------+   |
|       |                            |                            |               |
|  +----v----------------------------v----------------------------v-----------+   |
|  |                            DOMAIN LAYER                                   |   |
|  |                                                                           |   |
|  |  Models:   IdentityModel, ContactModel, ContactRequestModel,             |   |
|  |            ConversationMessage, MessagePayload, QRPayloadModel,          |   |
|  |            FeedItem (ConnectionFeedItem, ThreadFeedItem, MessageFeedItem),|   |
|  |            NodeState, ChatMessage, DiscoveredPeer, OrbitFriend            |   |
|  |                                                                           |   |
|  |  Repositories (interfaces):                                               |   |
|  |    IdentityRepository, ContactRepository, ContactRequestRepository,      |   |
|  |    MessageRepository                                                      |   |
|  +----+----------------------------+----------------------------+-----------+   |
|       |                            |                            |               |
|  +----v----------------------------v----------------------------v-----------+   |
|  |                       INFRASTRUCTURE LAYER                                |   |
|  |                                                                           |   |
|  |  +----------------------+     +-----------------------+                   |   |
|  |  |  Repository Impls    |     |    Bridge (abstract)   |                   |   |
|  |  |  (DB helper fns)     |     |       |                |                   |   |
|  |  +----------+-----------+     |  GoBridgeClient        |                   |   |
|  |             |                 |  (MethodChannel/       |                   |   |
|  |             v                 |   EventChannel)        |                   |   |
|  |  +----------+-----------+     +----------+------------+                   |   |
|  |  | SQLCipher Database   |                |                                |   |
|  |  | (sqflite_sqlcipher)  |                v                                |   |
|  |  +----------------------+     +----------+------------+                   |   |
|  |                               | Go Native Library     |                   |   |
|  |  +----------------------+     | (.xcframework / .aar)  |                   |   |
|  |  | SecureKeyStore       |     |                        |                   |   |
|  |  | (Keychain/EncShared) |     | - BIP39 mnemonic gen  |                   |   |
|  |  +----------------------+     | - Ed25519 keypair     |                   |   |
|  |                               | - ML-KEM-768 keygen   |                   |   |
|  |  +----------------------+     | - AES-256-GCM encrypt |                   |   |
|  |  | IncomingMessageRouter|     | - libp2p node         |                   |   |
|  |  |   |                  |     | - Rendezvous discovery|                   |   |
|  |  |   +-- ContactRequest |     | - Offline inbox       |                   |   |
|  |  |   |   Listener       |     | - FCM token register  |                   |   |
|  |  |   +-- ChatMessage    |     +-----------------------+                   |   |
|  |  |       Listener       |                                                 |   |
|  |  +----------------------+     +-----------------------+                   |   |
|  |                               | P2PServiceImpl        |                   |   |
|  |  +----------------------+     | (bridge + local P2P)  |                   |   |
|  |  | PendingMessageRetrier|     +-----------------------+                   |   |
|  |  +----------------------+                                                 |   |
|  |                               +-----------------------+                   |   |
|  |                               | LocalP2PService       |                   |   |
|  |                               | (mDNS + WebSocket)    |                   |   |
|  |                               +-----------------------+                   |   |
|  +-----------------------------------------------------------------------+   |
+---------------------------------------------------------------------------------+
```

---

## Message Delivery Pipeline

```
Outgoing:                                       Incoming:

ConversationWired                               Go Node (libp2p stream)
  |                                                |
  v                                                v
sendChatMessage (use case)                      EventChannel push event
  |                                                |
  |-- encrypt if contact has ML-KEM key            v
  |   (v2 envelope with AES-256-GCM)           GoBridgeClient._handleEvent()
  |                                                |
  |-- else v1 plaintext envelope                   v
  |                                             P2PServiceImpl._handleMessageReceived()
  v                                                |
P2PService.sendMessage()                           v
  |                                             IncomingMessageRouter
  |-- try local WiFi first (mDNS)                 |
  |   if peer on same network                     +-- type: "contact_request"
  |                                                |   -> ContactRequestListener
  |-- else relay (Go libp2p)                       |
  |                                                +-- type: "chat_message"
  |-- on failure: store in offline inbox               -> ChatMessageListener
  |   + update status to 'failed'                         |
  |                                                       v
  v                                                handleIncomingChatMessage
PendingMessageRetrier                              (decrypt v2 or parse v1)
  (auto-retries when relay reconnects)                |
                                                      v
                                                   MessageRepository.insert()
```

---

## Project Structure

```
flutter_app/
|
+-- lib/                                 # Flutter Application Code
|   +-- main.dart                        # Entry point, DI chain, Firebase init
|   |
|   +-- core/                            # Shared Infrastructure
|   |   +-- bridge/
|   |   |   +-- bridge.dart              # Bridge abstract + identity/crypto helpers
|   |   |   +-- go_bridge_client.dart    # MethodChannel/EventChannel -> Go native
|   |   |   +-- p2p_bridge_client.dart   # P2P-specific bridge helpers (node, peer, inbox)
|   |   +-- config/
|   |   |   +-- startup_config.dart      # Deferred startup mode toggle
|   |   +-- constants/
|   |   |   +-- network_constants.dart   # Relay addresses, timeouts
|   |   +-- database/
|   |   |   +-- encrypted_db_opener.dart # SQLCipher open/create/migrate
|   |   |   +-- helpers/
|   |   |   |   +-- identity_db_helpers.dart
|   |   |   |   +-- contacts_db_helpers.dart
|   |   |   |   +-- contact_requests_db_helpers.dart
|   |   |   |   +-- messages_db_helpers.dart
|   |   |   +-- migrations/
|   |   |       +-- 001_identity_table.dart
|   |   |       +-- 002_messages_table.dart
|   |   |       +-- 003_mlkem_keys.dart
|   |   |       +-- 004_nullify_secret_columns.dart
|   |   |       +-- 005_secret_null_checks.dart
|   |   |       +-- 006_read_at_column.dart
|   |   |       +-- 007_archive_columns.dart
|   |   |       +-- 008_block_columns.dart
|   |   +-- local_discovery/
|   |   |   +-- local_discovery_service.dart   # mDNS discovery interface
|   |   |   +-- bonsoir_discovery_service.dart # Bonsoir mDNS implementation
|   |   |   +-- local_p2p_service.dart         # Composed mDNS + WebSocket facade
|   |   |   +-- local_ws_server.dart           # Direct WiFi WebSocket server
|   |   +-- secure_storage/
|   |   |   +-- secure_key_store.dart              # Abstract interface
|   |   |   +-- flutter_secure_key_store.dart      # Production (Keychain/EncSharedPref)
|   |   |   +-- migrate_secrets_to_secure_storage.dart
|   |   +-- services/
|   |   |   +-- p2p_service.dart               # Abstract P2P interface
|   |   |   +-- p2p_service_impl.dart          # Bridge-backed implementation
|   |   |   +-- incoming_message_router.dart   # Routes P2P messages by type
|   |   |   +-- pending_message_retrier.dart   # Auto-retry on reconnect
|   |   +-- theme/
|   |   |   +-- app_theme.dart                 # Dark theme definition
|   |   |   +-- app_colors.dart                # Color constants
|   |   |   +-- glassmorphism.dart             # Glass effect utilities
|   |   +-- utils/
|   |       +-- flow_event_emitter.dart        # Structured event logging
|   |       +-- startup_timing.dart            # Startup performance tracking
|   |       +-- ring_avatar_generator.dart     # Deterministic avatar generation
|   |       +-- ring_avatar_spec.dart          # Avatar specification
|   |       +-- key_conversion.dart            # Base64 <-> hex conversions
|   |       +-- chat_console_logger.dart       # Debug message logging
|   |
|   +-- features/
|       +-- identity/                    # Identity Feature
|       |   +-- domain/models/identity_model.dart
|       |   +-- domain/repositories/identity_repository.dart
|       |   +-- domain/repositories/identity_repository_impl.dart
|       |   +-- application/generate_identity_use_case.dart
|       |   +-- application/restore_identity_use_case.dart
|       |   +-- application/startup_decision.dart
|       |   +-- presentation/startup_router.dart
|       |   +-- presentation/screens/identity_choice_{screen,wired}.dart
|       |   +-- presentation/screens/mnemonic_input_{screen,wired}.dart
|       |   +-- presentation/widgets/  (ambient_background, brand_header, etc.)
|       |
|       +-- contacts/                    # Contacts Feature
|       |   +-- domain/models/contact_model.dart
|       |   +-- domain/repositories/contact_repository{,_impl}.dart
|       |   +-- application/ (add, archive, unarchive, block, unblock, delete)
|       |
|       +-- contact_request/             # Contact Request Feature
|       |   +-- domain/models/contact_request_model.dart
|       |   +-- domain/repositories/contact_request_repository{,_impl}.dart
|       |   +-- application/ (send, handle_incoming, accept, decline, listener)
|       |   +-- presentation/widgets/ (contact_request_dialog, pending_requests_badge)
|       |
|       +-- conversation/                # Conversation Feature
|       |   +-- domain/models/conversation_message.dart
|       |   +-- domain/models/message_payload.dart
|       |   +-- domain/repositories/message_repository{,_impl}.dart
|       |   +-- application/ (send, handle_incoming, load, mark_read, retry, listener)
|       |   +-- presentation/screens/conversation_{screen,wired}.dart
|       |   +-- presentation/widgets/ (letter_card, compose_area, conversation_header,
|       |   |                          empty_state, origin_marker, date_separator,
|       |   |                          blocked_banner)
|       |   +-- presentation/navigation/conversation_route_transition.dart
|       |
|       +-- feed/                        # Feed Feature
|       |   +-- domain/models/feed_item.dart
|       |   +-- domain/utils/ (format_message_time, group_messages_into_threads, etc.)
|       |   +-- application/load_feed_use_case.dart
|       |   +-- presentation/screens/feed_{screen,wired}.dart
|       |   +-- presentation/widgets/ (feed_header, feed_navigation_bar, thread_card,
|       |   |                          connection_card, message_feed_card, message_bubble,
|       |   |                          session_divider, time_gap_divider, nav_bar_button,
|       |   |                          unread_count_badge, checkmark_burst_animation)
|       |   +-- presentation/navigation/feed_route_transition.dart
|       |
|       +-- orbit/                       # Orbit Feature (Contact Management)
|       |   +-- domain/models/orbit_friend.dart
|       |   +-- application/load_orbit_data_use_case.dart
|       |   +-- presentation/screens/orbit_{screen,wired}.dart
|       |   +-- presentation/widgets/ (orbital_visualization, orbital_avatar,
|       |   |                          orbital_ring_painter, friend_row, swipeable_friend_row,
|       |   |                          swipe_action_buttons, friends_filter_toggle,
|       |   |                          friends_list_header, orbit_header, orbit_close_button,
|       |   |                          orbit_search_dock, orbit_search_trigger,
|       |   |                          overflow_badge, qr_action_cards, confirmation_dialog,
|       |   |                          archived_empty_state)
|       |   +-- presentation/navigation/orbit_route_transition.dart
|       |
|       +-- home/                        # Home / First-Time Experience
|       |   +-- presentation/screens/first_time_experience_{screen,wired}.dart
|       |   +-- presentation/widgets/ (editable_username, empty_circle_state,
|       |                              profile_avatar, qr_code_section, ring_avatar,
|       |                              ring_avatar_painter, scan_friend_card)
|       |
|       +-- p2p/                         # P2P Feature (Models + Use Cases)
|       |   +-- domain/models/ (chat_message, connection_state, discovered_peer,
|       |   |                   node_state, send_message_result)
|       |   +-- application/ (start_node, stop_node, send_message, discover_peer)
|       |   +-- presentation/widgets/connection_status_indicator.dart
|       |
|       +-- push/                        # Push Notifications Feature
|       |   +-- application/background_message_handler.dart
|       |   +-- application/register_push_token_use_case.dart
|       |   +-- application/request_push_permission_use_case.dart
|       |
|       +-- qr_code/                     # QR Code Feature
|           +-- domain/models/qr_payload_model.dart
|           +-- application/build_qr_payload_use_case.dart
|           +-- application/parse_qr_payload_use_case.dart
|           +-- presentation/screens/qr_display_{screen,wired}.dart
|           +-- presentation/screens/qr_scanner_{screen,wired}.dart
|           +-- presentation/widgets/scan_overlay.dart
|
+-- go-mknoon/                           # Go Native Library (gomobile)
|   +-- bridge/
|   |   +-- bridge.go                    # Exported API: identity, crypto, node, inbox
|   |   +-- bridge_test.go
|   |   +-- events.go                    # EventCallback interface for Go -> Flutter
|   +-- identity/
|   |   +-- identity.go                  # BIP39 mnemonic + Ed25519 keypair generation
|   |   +-- identity_test.go
|   +-- crypto/
|   |   +-- sign.go                      # Ed25519 signing
|   |   +-- mlkem.go                     # ML-KEM-768 key generation
|   |   +-- encrypt.go                   # ML-KEM encapsulate + AES-256-GCM encrypt
|   |   +-- decrypt.go                   # ML-KEM decapsulate + AES-256-GCM decrypt
|   |   +-- *_test.go
|   +-- node/
|   |   +-- node.go                      # libp2p host, stream handlers, peer mgmt
|   |   +-- config.go                    # Node configuration
|   |   +-- rendezvous.go               # Rendezvous register/discover
|   |   +-- inbox.go                     # Offline inbox store/retrieve via relay
|   |   +-- node_test.go
|   +-- internal/
|   |   +-- envelope.go                  # Message envelope utilities
|   +-- integration/
|   |   +-- relay_test.go               # Relay integration test
|   +-- stub/
|   |   +-- gosigar/sigar.go            # iOS build stub (no libproc.h)
|   +-- Makefile                         # gomobile bind targets (ios, android)
|   +-- go.mod, go.sum, tools.go
|
+-- test/                                # Unit Tests (Dart)
|   +-- core/bridge/                     # Bridge helper tests
|   +-- core/local_discovery/            # Local P2P tests + fakes
|   +-- core/secure_storage/             # Secrets migration tests + FakeSecureKeyStore
|   +-- core/services/                   # IncomingMessageRouter tests
|   +-- features/identity/               # Identity use case tests
|   +-- features/contacts/               # Contact model, repo, use case tests
|   +-- features/contact_request/        # Contact request use case tests
|   +-- features/conversation/           # Message use case, model, repo, widget tests
|   +-- features/feed/                   # Feed use case, model, widget tests
|   +-- features/orbit/                  # Orbit use case, widget tests
|   +-- features/qr_code/               # QR payload use case tests
|
+-- integration_test/
|   +-- smoke_test.dart                  # On-device smoke test
|
+-- ios/                                 # iOS native (GoBridge.swift platform wrapper)
+-- android/                             # Android native (GoBridge.kt platform wrapper)
```

---

## DI Chain (main.dart)

Dependency injection is manual, wired in `main()`:

```
SecureKeyStore
  |
  +--> openEncryptedDatabase() --> Database
  |
  +--> migrateSecretsToSecureStorage()
  |
  +--> IdentityRepositoryImpl (dbHelpers + secureKeyStore)
  |
  +--> ContactRepositoryImpl (dbHelpers)
  +--> ContactRequestRepositoryImpl (dbHelpers)
  +--> MessageRepositoryImpl (dbHelpers)
  |
  +--> GoBridgeClient --> Bridge (abstract)
  |
  +--> BonsoirDiscoveryService + LocalWsServer --> LocalP2PService
  |
  +--> P2PServiceImpl (bridge + localP2PService)
  |
  +--> IncomingMessageRouter (p2pService)
  |
  +--> ContactRequestListener (router.contactRequestStream + repos + bridge)
  +--> ChatMessageListener (router.chatMessageStream + repos + bridge)
  +--> PendingMessageRetrier (p2pService + repos + bridge)
  |
  +--> MyApp --> StartupRouter --> Feature Screens
```

Everything is threaded through constructors. No service locator or code generation.

---

## Identity Data Model

```
+-------------------------------------------------------------+
|                      IdentityModel                            |
+-------------------------------------------------------------+
|                                                               |
|  peerId: String                                               |
|  +-- libp2p peer identifier                                   |
|  +-- Derived from Ed25519 public key                          |
|                                                               |
|  publicKey: String                                            |
|  +-- Base64-encoded Ed25519 public key                        |
|  +-- Used for identity verification + QR payload              |
|                                                               |
|  privateKey: String                                           |
|  +-- Base64-encoded Ed25519 private key                       |
|  +-- Stored in SecureKeyStore (NOT in database)               |
|  +-- Used for signing + P2P node authentication               |
|                                                               |
|  mnemonic12: String                                           |
|  +-- 12 BIP39 English words                                   |
|  +-- Stored in SecureKeyStore (NOT in database)               |
|  +-- Can regenerate Ed25519 identity                          |
|                                                               |
|  mlKemPublicKey: String?                                      |
|  +-- Base64-encoded ML-KEM-768 public key                     |
|  +-- Exchanged via QR payload + contact request               |
|                                                               |
|  mlKemSecretKey: String?                                      |
|  +-- Base64-encoded ML-KEM-768 secret key                     |
|  +-- Stored in SecureKeyStore (NOT in database)               |
|  +-- Used to decrypt incoming v2 messages                     |
|                                                               |
|  username: String (default "Username")                        |
|  +-- User-chosen display name                                 |
|                                                               |
|  avatarBlob: Uint8List?                                       |
|  +-- Optional profile image bytes                             |
|                                                               |
|  createdAt: String (ISO-8601)                                 |
|  updatedAt: String (ISO-8601)                                 |
|                                                               |
+-------------------------------------------------------------+
```

---

## Database Schema (version 8)

| Table | Key Columns | Notes |
|-------|-------------|-------|
| `identity` | id=1, peer_id, public_key, private_key(NULL), mnemonic12(NULL), ml_kem_public_key, ml_kem_secret_key(NULL), username, avatar_blob, created_at, updated_at | Secrets enforced NULL by CHECK constraints (stored in SecureKeyStore) |
| `contacts` | peer_id (PK), public_key, rendezvous, username, signature, scanned_at, avatar_path, ml_kem_public_key, is_archived, archived_at, is_blocked, blocked_at | Added via QR scan or accepted contact request |
| `contact_requests` | peer_id (PK), public_key, rendezvous, username, signature, received_at, status, ml_kem_public_key | status: pending / accepted / declined |
| `messages` | id (UUID PK), contact_peer_id, sender_peer_id, text, timestamp, status, is_incoming, created_at, read_at | status: sending / sent / delivered / failed |

---

## Wire Message Formats

**v1 -- Plaintext envelope** (used when recipient has no ML-KEM key):
```json
{
  "type": "chat_message",
  "version": "1",
  "payload": {
    "id": "uuid",
    "text": "Hello!",
    "senderPeerId": "12D3Koo...",
    "senderUsername": "Alice",
    "timestamp": "2025-01-15T12:00:00Z"
  }
}
```

**v2 -- Encrypted envelope** (ML-KEM-768 + AES-256-GCM):
```json
{
  "type": "chat_message",
  "version": "2",
  "senderPeerId": "12D3Koo...",
  "encrypted": {
    "kem": "<base64 KEM ciphertext>",
    "ciphertext": "<base64 AES-256-GCM ciphertext>",
    "nonce": "<base64 96-bit nonce>"
  }
}
```

**Contact request envelope:**
```json
{
  "type": "contact_request",
  "version": "1",
  "payload": {
    "pk": "<base64 public key>",
    "ns": "<peer ID>",
    "rv": "<rendezvous multiaddr>",
    "un": "Alice",
    "ts": "2025-01-15T12:00:00Z",
    "sig": "<base64 Ed25519 signature>",
    "mlkem": "<base64 ML-KEM public key>"
  }
}
```

---

## User Flows

### New Identity Creation

```
User                    App                     Go Native                SecureKeyStore
  |                      |                         |                        |
  |   Opens app          |                         |                        |
  |-------------------->|                         |                        |
  |                      |   Check identity in DB  |                        |
  |                      |   (none found)          |                        |
  |   Show choice screen |                         |                        |
  |<--------------------|                         |                        |
  |                      |                         |                        |
  |   Tap "I'm new here" |                         |                        |
  |-------------------->|                         |                        |
  |                      |   identity.generate     |                        |
  |                      |----------------------->|                        |
  |                      |   {peerId, publicKey,   |                        |
  |                      |    privateKey, mnemonic} |                        |
  |                      |<-----------------------|                        |
  |                      |                         |                        |
  |                      |   mlkem.keygen          |                        |
  |                      |----------------------->|                        |
  |                      |   {publicKey, secretKey}|                        |
  |                      |<-----------------------|                        |
  |                      |                         |                        |
  |                      |   Save secrets          |                        |
  |                      |---------------------------------------------->|
  |                      |   Save public fields to DB                      |
  |                      |                         |                        |
  |   Navigate to FTE    |                         |                        |
  |<--------------------|                         |                        |
  |                      |   (background) Start P2P node                   |
  |                      |   (background) Register FCM push token          |
```

### QR Code Contact Exchange

```
Alice (scanner)          Alice's App               Bob's App              Bob (displayer)
  |                         |                         |                      |
  |                         |                         |   Show QR code       |
  |                         |                         |<--------------------|
  |   Scan Bob's QR         |                         |                      |
  |----------------------->|                         |                      |
  |                         |   Verify QR signature   |                      |
  |                         |   (Ed25519)             |                      |
  |                         |                         |                      |
  |                         |   Save Bob as contact   |                      |
  |                         |                         |                      |
  |                         |   Send contact_request  |                      |
  |                         |   via P2P to Bob        |                      |
  |                         |----------------------->|                      |
  |                         |                         |   Show request dialog|
  |                         |                         |-------------------->|
  |                         |                         |                      |
  |                         |                         |   User accepts       |
  |                         |                         |<--------------------|
  |                         |                         |   Save Alice as      |
  |                         |                         |   contact            |
```

### Sending an Encrypted Message

```
Alice's App                   Go Bridge                  Bob's App
  |                              |                          |
  |  sendChatMessage()           |                          |
  |  Bob has ML-KEM key?  YES   |                          |
  |                              |                          |
  |  message.encrypt             |                          |
  |  (Bob's ML-KEM pubkey,      |                          |
  |   plaintext JSON)            |                          |
  |---------------------------->|                          |
  |  {kem, ciphertext, nonce}   |                          |
  |<----------------------------|                          |
  |                              |                          |
  |  Build v2 envelope           |                          |
  |  message:send                |                          |
  |---------------------------->|                          |
  |                              | libp2p stream to Bob     |
  |                              |------------------------->|
  |                              |                          |
  |                              |                          | message.decrypt
  |                              |                          | (own ML-KEM secretKey)
  |                              |                          | -> plaintext JSON
  |                              |                          | -> save to messages DB
```

---

## Error Handling

```
+-------------------------------------------------------------+
|                     Error Categories                          |
+-------------------------------------------------------------+
|                                                               |
|  IDENTITY ERRORS                                              |
|  +-- coreLibError         Go bridge communication failed     |
|  +-- dbError              Database save operation failed     |
|  +-- invalidMnemonicFormat  Word count != 12                 |
|  +-- invalidMnemonicCore    BIP39 checksum invalid           |
|  +-- BRIDGE_TIMEOUT         Bridge call timed out            |
|                                                               |
|  P2P / NETWORKING ERRORS                                      |
|  +-- NODE_START_ERROR      Node failed to start              |
|  +-- DIAL_ERROR            Could not connect to peer         |
|  +-- SEND_ERROR            Message send failed               |
|  +-- RENDEZVOUS_ERROR      Discovery failed                  |
|  +-- INBOX_ERROR           Offline inbox operation failed    |
|  +-- NOT_INITIALIZED       Bridge not initialized            |
|                                                               |
|  CRYPTO ERRORS                                                |
|  +-- INVALID_INPUT         Missing or malformed parameters   |
|  +-- INTERNAL_ERROR        ML-KEM or AES operation failed    |
|                                                               |
|  DATABASE ERRORS                                              |
|  +-- Migration failure     Schema upgrade failed             |
|  +-- Encryption error      SQLCipher key derivation          |
|                                                               |
|  PUSH NOTIFICATION ERRORS                                     |
|  +-- Permission denied     User declined push permission     |
|  +-- Token registration    FCM token registration failed     |
|                                                               |
|  STARTUP ERRORS                                               |
|  +-- Database read failure Show retry screen                 |
|  +-- Bridge init failure   Show retry screen                 |
|                                                               |
+-------------------------------------------------------------+
```

---

## Flow Events

The application emits structured events via `emitFlowEvent()` at every layer for monitoring and debugging:

| Layer | Event Examples |
|-------|----------------|
| **Database** | `ID_DB_LOAD_IDENTITY_START`, `ID_DB_UPSERT_IDENTITY_SUCCESS` |
| **Go Bridge** | `GO_BRIDGE_INIT_SUCCESS`, `GO_BRIDGE_SEND`, `GO_BRIDGE_PLATFORM_ERROR` |
| **P2P Service** | `P2P_SERVICE_START_NODE_BEGIN`, `P2P_SERVICE_SEND_MESSAGE_SUCCESS` |
| **Message Router** | `MESSAGE_ROUTER_START`, `MESSAGE_ROUTER_UNKNOWN_TYPE` |
| **Listeners** | `CR_LISTENER_INCOMING`, `CHAT_LISTENER_MESSAGE_SAVED` |
| **Use Cases** | `ID_M1_GENERATE_START`, `SEND_CHAT_MESSAGE_ENCRYPTED` |
| **Presentation** | `ID_STARTUP_ROUTE_FEED`, `APP_LIFECYCLE_RESUME_COMPLETE` |
| **Push** | `PUSH_FOREGROUND_MESSAGE_RECEIVED`, `PUSH_REGISTER_TOKEN_ERROR` |

---

## Getting Started

### Prerequisites

- Flutter SDK (3.x, Dart SDK ^3.9.0)
- Go (1.22+)
- gomobile: `go install golang.org/x/mobile/cmd/gomobile@latest && gomobile init`
- Xcode (for iOS builds)
- Android Studio + NDK (for Android builds)
- CocoaPods (for iOS dependency management)

### Building the Go Native Library

The Go library must be built before running the Flutter app. `flutter run` alone does NOT rebuild Go code.

```bash
# Build for both iOS and Android
cd go-mknoon
PATH="$PATH:$(go env GOPATH)/bin" make all
cd ../ios && pod install
```

This produces:
- `ios/Runner/GoMknoon.xcframework` (iOS)
- `android/app/libs/GoMknoon.aar` (Android)

### Running the App

```bash
# Install Flutter dependencies
flutter pub get

# Run on connected device or simulator (Go library must be built first)
flutter run

# Run on specific platform
flutter run -d ios
flutter run -d android
```

### Running Tests

```bash
# Dart unit tests (no device required)
flutter test

# Go unit tests
cd go-mknoon && go test ./...

# On-device integration smoke test
flutter test integration_test/smoke_test.dart
```

### Known Build Notes

- Android build requires Go < 1.25 or a patched `wlynxg/anet` (known gomobile issue).
- gomobile symbols use the Go package prefix (`Bridge*`), not the framework name (`GoMknoon*`).
- The `go-mknoon/stub/gosigar/` stub is required because iOS cannot use `libproc.h`.
- Always run `make all` + `pod install` after modifying Go code.

---

## Technical Stack

- **Framework:** Flutter 3.x (Dart ^3.9.0)
- **Language:** Dart (Flutter), Go (native library via gomobile)
- **Database:** SQLCipher (via sqflite_sqlcipher) -- encrypted SQLite with 256-bit key
- **Secure Storage:** flutter_secure_storage (iOS Keychain / Android EncryptedSharedPreferences)
- **Cryptography:**
  - BIP39 (mnemonic generation)
  - Ed25519 (keypair derivation, signing, verification)
  - ML-KEM-768 / FIPS 203 (post-quantum key encapsulation)
  - AES-256-GCM (symmetric message encryption)
- **Networking:**
  - libp2p (QUIC + WebSocket transport, circuit relay v2, rendezvous discovery)
  - Bonsoir / mDNS (local WiFi peer discovery)
  - WebSocket (local WiFi direct messaging)
- **Push Notifications:** Firebase Cloud Messaging (FCM)
- **QR Code:** qr_flutter (display), mobile_scanner (camera scanning)
- **Architecture:** Clean Architecture with Repository Pattern (DB helpers -> Repos -> Use Cases -> Wired/Screen UI)
- **State Management:** StatefulWidget with constructor-injected use cases (no service locator, no code generation)
- **Platform Bridge:** MethodChannel / EventChannel -> Go .xcframework (iOS) / .aar (Android)
- **UI Pattern:** Screen (StatelessWidget) + Wired (StatefulWidget) pairs per feature
- **Logging:** `emitFlowEvent()` structured events at every layer

---

## License

This project is proprietary software.
