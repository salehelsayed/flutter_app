## Dependencies

### Flutter Packages (pubspec.yaml)

| Package | Purpose |
|---------|---------|
| sqflite_sqlcipher | SQLCipher encrypted database access (replaces plain sqflite) |
| sqlcipher_flutter_libs | SQLCipher native libraries for iOS/Android |
| flutter_secure_storage | OS-backed secure key-value storage (iOS Keychain / Android EncryptedSharedPreferences) |
| qr_flutter | QR code generation widget |
| mobile_scanner | Camera-based QR code scanning |
| image_picker | Camera/gallery image selection |
| path_provider | App documents directory access |
| path | Cross-platform path manipulation |
| cupertino_icons | iOS-style icons |
| flutter_svg | SVG rendering |
| uuid | UUID v4 generation for message IDs |
| just_audio | Audio playback for voice messages |
| flutter_image_compress | Native image compression + EXIF stripping |
| crypto | SHA-256 hashing utilities |
| url_launcher | Opening URLs in external browser |
| video_compress | Video compression for media attachments |
| record | Audio recording via platform channels |
| firebase_core | Firebase initialization |
| firebase_messaging | Push notifications (FCM) |
| flutter_local_notifications | Local push notification display |
| bonsoir | mDNS service discovery for local WiFi P2P |

### Flutter Dev Packages

| Package | Purpose |
|---------|---------|
| sqflite_common_ffi | SQLite/SQLCipher FFI for desktop testing |
| flutter_test | Widget testing framework |
| integration_test | Integration testing framework |
| flutter_lints | Lint rules |

### Go Packages (go-mknoon/go.mod)

| Package | Purpose |
|---------|---------|
| github.com/libp2p/go-libp2p | Core libp2p host, relay, hole punching, NAT traversal |
| github.com/libp2p/go-libp2p-pubsub | GossipSub pubsub for group messaging topics |
| github.com/libp2p/go-msgio | Length-prefixed framed message I/O for chat protocol |
| github.com/tyler-smith/go-bip39 | BIP39 mnemonic phrase generation |
| github.com/cloudflare/circl | ML-KEM-768 (FIPS 203) post-quantum key encapsulation |
| github.com/google/uuid | UUID generation for message IDs |
| crypto/ed25519 (stdlib) | Ed25519 signing & verification |
| crypto/aes + crypto/cipher (stdlib) | AES-256-GCM symmetric encryption |
| golang.org/x/mobile/bind | gomobile framework binding (iOS .xcframework + Android .aar) |
| google.golang.org/protobuf | Protocol buffers (used by libp2p internals) |

---

## Startup Initialization Flow

The application initialization sequence is defined in `lib/main.dart`. Understanding this flow is critical for debugging startup issues and adding new initialization steps.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      STARTUP INITIALIZATION SEQUENCE                         │
└─────────────────────────────────────────────────────────────────────────────┘

  main()
    │
    ├─► WidgetsFlutterBinding.ensureInitialized()
    │       Ensures Flutter engine is ready before async operations
    │
    ├─► Firebase.initializeApp()
    │       Initializes Firebase SDK for push notifications
    │
    ├─► FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler)
    │       Registers background message handler (@pragma entry-point)
    │
    ├─► SecureKeyStore instantiation (FlutterSecureKeyStore)
    │       iOS Keychain (device-bound) / Android EncryptedSharedPreferences
    │
    ├─► openEncryptedDatabase('identity.db', version: 18, secureKeyStore)
    │       │
    │       ├─► Read/generate db_encryption_key from SecureKeyStore
    │       │       Random 256-bit key, stored as base64 in secure storage
    │       │
    │       ├─► Open SQLCipher DB with encryption key (sqflite_sqlcipher)
    │       │
    │       ├─► onCreate callback (first run only)
    │       │       │
    │       │       ├─► runIdentityTableMigration(db)
    │       │       │       Creates identity, contacts, contact_requests
    │       │       │
    │       │       ├─► runMessagesTableMigration(db)
    │       │       │       Creates messages table + indexes
    │       │       │
    │       │       ├─► runMlKemKeysMigration(db)
    │       │       │       Adds ml_kem_* columns to identity, contacts, contact_requests
    │       │       │
    │       │       ├─► runSecretNullChecksMigration(db)
    │       │       │       CHECK constraints + avatar_blob BLOB column (v5)
    │       │       │       (Fresh installs skip v4 — v5 already has nullable + CHECK)
    │       │       │
    │       │       ├─► runReadAtColumnMigration(db)
    │       │       │       Adds read_at TEXT column to messages (v6)
    │       │       │
    │       │       ├─► runArchiveColumnsMigration(db)
    │       │       │       Adds is_archived, archived_at to contacts (v7)
    │       │       │
    │       │       ├─► runBlockColumnsMigration(db)
    │       │       │       Adds is_blocked, blocked_at to contacts (v8)
    │       │       │
    │       │       ├─► runQuotedMessageIdMigration(db)
    │       │       │       Adds quoted_message_id TEXT to messages (v9)
    │       │       │
    │       │       ├─► runMediaAttachmentsMigration(db)
    │       │       │       Creates media_attachments table + indexes (v10)
    │       │       │
    │       │       ├─► runAvatarVersionMigration(db)
    │       │       │       Adds avatar_version INTEGER to identity and contacts (v11)
    │       │       │
    │       │       ├─► runTransportColumnMigration(db)
    │       │       │       Adds transport TEXT to messages (v12)
    │       │       │
    │       │       ├─► runWaveformColumnMigration(db)
    │       │       │       Adds waveform TEXT to media_attachments (v13)
    │       │       │
    │       │       ├─► runWireEnvelopeColumnMigration(db)
    │       │       │       Adds wire_envelope TEXT to messages (v14)
    │       │       │
    │       │       ├─► runMessageStatusCleanupMigration(db)
    │       │       │       Normalizes legacy 'queued' status to 'delivered' (v15)
    │       │       │
    │       │       ├─► runMessageReactionsMigration(db)
    │       │       │       Creates message_reactions table (v16)
    │       │       │
    │       │       ├─► runGroupsTablesMigration(db)
    │       │       │       Creates groups, group_members tables (v17)
    │       │       │
    │       │       └─► runGroupMessagesTablesMigration(db)
    │       │               Creates group_keys, group_messages tables (v18)
    │       │
    │       └─► onUpgrade callback (v1→v2→...→v17→v18)
    │               │
    │               ├─► runMessagesTableMigration(db)                (v1 → v2)
    │               │       Creates messages table for existing installs
    │               │
    │               ├─► runMlKemKeysMigration(db)                    (v2 → v3)
    │               │       Adds ML-KEM key columns for E2E encryption
    │               │
    │               ├─► runNullifySecretColumnsMigration(db)         (v3 → v4)
    │               │       Makes private_key, mnemonic12 nullable
    │               │
    │               ├─► runSecretNullChecksMigration(db)             (v4 → v5)
    │               │       CHECK constraints enforcing secret cols NULL
    │               │       + avatar_blob BLOB column
    │               │
    │               ├─► runReadAtColumnMigration(db)                (v5 → v6)
    │               │       Adds read_at TEXT column to messages table
    │               │
    │               ├─► runArchiveColumnsMigration(db)             (v6 → v7)
    │               │       Adds is_archived, archived_at to contacts
    │               │
    │               ├─► runBlockColumnsMigration(db)               (v7 → v8)
    │               │       Adds is_blocked, blocked_at to contacts
    │               │
    │               ├─► runQuotedMessageIdMigration(db)          (v8 → v9)
    │               │       Adds quoted_message_id TEXT to messages
    │               │
    │               ├─► runMediaAttachmentsMigration(db)         (v9 → v10)
    │               │       Creates media_attachments table + indexes
    │               │
    │               ├─► runAvatarVersionMigration(db)            (v10 → v11)
    │               │       Adds avatar_version INTEGER to identity and contacts
    │               │
    │               ├─► runTransportColumnMigration(db)        (v11 → v12)
    │               │       Adds transport TEXT to messages
    │               │
    │               ├─► runWaveformColumnMigration(db)         (v12 → v13)
    │               │       Adds waveform TEXT to media_attachments
    │               │
    │               ├─► runWireEnvelopeColumnMigration(db)     (v13 → v14)
    │               │       Adds wire_envelope TEXT to messages
    │               │
    │               ├─► runMessageStatusCleanupMigration(db)   (v14 → v15)
    │               │       Normalizes legacy 'queued' outgoing messages
    │               │
    │               ├─► runMessageReactionsMigration(db)       (v15 → v16)
    │               │       Creates message_reactions table
    │               │
    │               ├─► runGroupsTablesMigration(db)           (v16 → v17)
    │               │       Creates groups, group_members tables
    │               │
    │               └─► runGroupMessagesTablesMigration(db)    (v17 → v18)
    │                       Creates group_keys, group_messages tables
    │
    ├─► migrateSecretsToSecureStorage(db, secureKeyStore)
    │       One-time migration: reads secrets from DB, writes to SecureKeyStore
    │       Sets secrets_migrated sentinel in secure storage
    │       Nullifies DB secret columns after successful migration
    │
    ├─► Repository instantiation (8 repositories)
    │       │
    │       ├─► IdentityRepositoryImpl (dbLoad, dbUpsert, secureKeyStore)
    │       │
    │       ├─► ContactRepositoryImpl (12 db helper functions)
    │       │
    │       ├─► ContactRequestRepositoryImpl (6 db helper functions)
    │       │
    │       ├─► MessageRepositoryImpl (14 db helper functions)
    │       │
    │       ├─► MediaAttachmentRepositoryImpl (7 db helper functions)
    │       │
    │       ├─► ReactionRepositoryImpl (6 db helper functions)
    │       │
    │       ├─► GroupRepositoryImpl (18 db helper functions: groups + members + keys)
    │       │
    │       └─► GroupMessageRepositoryImpl (11 db helper functions)
    │
    ├─► MediaFileManager + ImageProcessor instantiation
    │       Media file path management + EXIF stripping + quality compression
    │
    ├─► AudioRecorderService instantiation (RecordAudioRecorderService)
    │       Audio recording via record package; amplitude stream + waveform extraction
    │
    ├─► GoBridgeClient instantiation + initialize()
    │       │
    │       └─► Sets up MethodChannel + EventChannel to Go native library
    │           via platform wrappers (GoBridge.swift / GoBridge.kt)
    │           Registers event handlers (messages, peer events, group messages)
    │
    ├─► LocalP2PService instantiation
    │       │
    │       ├─► BonsoirDiscoveryService (mDNS)
    │       │
    │       └─► LocalWsServer (WebSocket)
    │
    ├─► P2PServiceImpl instantiation
    │       │
    │       └─► Wraps GoBridgeClient + LocalP2PService with reactive streams
    │           stateStream (NodeState) + messageStream (ChatMessage)
    │
    ├─► IncomingMessageRouter instantiation + start()
    │       │
    │       └─► Subscribes to P2PService.messageStream
    │           Routes to typed streams by envelope type
    │           contactRequestStream, chatMessageStream, reactionStream,
    │           profileUpdateStream, groupInviteStream, groupKeyUpdateStream,
    │           unknownStream
    │
    ├─► NotificationService instantiation (FlutterNotificationService)
    │       Local notifications for incoming messages
    │
    ├─► ActiveConversationTracker instantiation (x2: 1:1 + group)
    │       Tracks foreground conversation to suppress notifications
    │
    ├─► ContactRequestListener instantiation + start()
    │       │
    │       └─► Subscribes to messageRouter.contactRequestStream
    │           Monitors for incoming contact requests
    │           Broadcasts to requestStream + contactKeyUpdatedStream for UI
    │
    ├─► ChatMessageListener instantiation + start()
    │       │
    │       └─► Subscribes to messageRouter.chatMessageStream
    │           Monitors for incoming chat messages
    │           Rejects messages from blocked contacts
    │           Suppresses UI notifications for archived contacts
    │           Broadcasts to incomingMessageStream + contactUpdatedStream
    │
    ├─► ReactionListener instantiation + start()
    │       │
    │       └─► Subscribes to messageRouter.reactionStream
    │           Persists incoming reactions to ReactionRepository
    │
    ├─► ProfileUpdateListener instantiation + start()
    │       │
    │       └─► Subscribes to messageRouter.profileUpdateStream
    │           Updates contact avatar/profile data
    │           Emits to contactUpdatedStream
    │
    ├─► GroupMessageListener instantiation + start(groupMessageStream)
    │       │
    │       └─► Subscribes to bridge.onGroupMessageReceived via StreamController
    │           Receives decrypted group messages from Go GossipSub handler
    │           Persists to GroupMessageRepository, triggers notifications
    │           Deduplicates messages by content hash
    │
    ├─► GroupInviteListener instantiation + start()
    │       │
    │       └─► Subscribes to messageRouter.groupInviteStream
    │           Processes incoming group invites (creates group + joins topic)
    │
    ├─► GroupKeyUpdateListener instantiation + start()
    │       │
    │       └─► Subscribes to messageRouter.groupKeyUpdateStream
    │           Processes group key rotations from admin
    │           Updates local key store + Go bridge key
    │
    ├─► PendingMessageRetrier instantiation + start()
    │       │
    │       └─► Subscribes to P2PService.stateStream
    │           Detects online transitions, 5s debounce
    │           Calls retryFailedMessages() on reconnect
    │
    ├─► KeyExchangeRetrier instantiation + start()
    │       │
    │       └─► Subscribes to P2PService.stateStream
    │           Detects online transitions, 5s debounce
    │           Calls retryIncompleteKeyExchanges() on reconnect
    │
    ├─► Stream forwarding (contactUpdatedStream cross-wiring):
    │       │
    │       ├─► profileUpdateListener.contactUpdatedStream → chatMessageListener.emitContactUpdate()
    │       │
    │       └─► contactRequestListener.contactKeyUpdatedStream → chatMessageListener.emitContactUpdate()
    │
    └─► runApp(MyApp) — StatefulWidget + WidgetsBindingObserver
            │
            ├─► Constructor params: all repositories, listeners, services, trackers, bridge, p2pService, isDesktop
            │
            ├─► handleAppResumed() lifecycle handler (app foreground):
            │       │   Calls handleAppResumed() top-level function:
            │       │
            │       ├─► bridge.checkHealth() (reinitialize if dead)
            │       │
            │       ├─► p2pService.performImmediateHealthCheck()
            │       │
            │       ├─► p2pService.drainOfflineInbox()
            │       │
            │       └─► retryIncompleteKeyExchanges()
            │
            ├─► _setupForegroundPushListener():
            │       │
            │       ├─► FirebaseMessaging.onMessage → drainOfflineInbox()
            │       │
            │       └─► FirebaseMessaging.onMessageOpenedApp → drainOfflineInbox()
            │
            ├─► _setupNotificationTapHandler():
            │       │
            │       └─► Routes notification taps to ConversationWired (1:1) or
            │           GroupConversationWired (group: prefix) via navigatorKey
            │
            ├─► dispose() orderly teardown:
            │       keyExchangeRetrier → pendingMessageRetrier →
            │       groupKeyUpdateListener → groupInviteListener →
            │       groupMessageListener → profileUpdateListener →
            │       reactionListener → chatMessageListener →
            │       contactRequestListener → messageRouter →
            │       p2pService → bridge → audioRecorderService →
            │       notificationService
            │
            └─► StartupRouter widget
                    │
                    ├─► initState() → _routeBasedOnIdentity()
                    │       │
                    │       └─► decideStartupRoute(repository)
                    │               Calls loadIdentity() to check DB
                    │
                    ├─► [hasIdentity] → Navigate to FirstTimeExperienceWired
                    │       │
                    │       └─► Subscribes to ContactRequestListener.requestStream
                    │
                    ├─► _registerPushToken() (after P2P node starts successfully)
                    │       │
                    │       ├─► requestPushPermission()
                    │       │
                    │       └─► registerPushToken(p2pService)
                    │               Registers FCM token with relay server
                    │
                    ├─► _doStartP2P() → after node:start completes:
                    │       │
                    │       ├─► rejoinGroupTopics() (re-subscribes active groups)
                    │       │
                    │       └─► drainGroupOfflineInbox() (retrieves queued group messages)
                    │
                    └─► [needsIdentity] → Navigate to IdentityChoiceWired
```

### Initialization Files

| File | Responsibility |
|------|----------------|
| `lib/main.dart` | Entry point, Firebase init, SecureKeyStore + encrypted DB setup (v18), secret migration, repository (8x) + service + listener (7x) + retrier (2x) DI; MyApp is StatefulWidget + WidgetsBindingObserver with handleAppResumed() lifecycle, foreground push listeners, notification tap routing, and orderly dispose chain |
| `lib/core/secure_storage/secure_key_store.dart` | SecureKeyStore abstract interface |
| `lib/core/secure_storage/flutter_secure_key_store.dart` | FlutterSecureKeyStore production impl (iOS Keychain / Android EncryptedSharedPreferences) |
| `lib/core/database/encrypted_db_opener.dart` | Opens SQLCipher DB (v18) with key from secure storage; handles plaintext-to-encrypted migration |
| `lib/core/database/migrate_secrets_to_secure_storage.dart` | One-time DB-to-secure-storage secret migration with sentinel |
| `lib/core/database/migrations/001_identity_table.dart` | Schema v1 migration (3 tables) |
| `lib/core/database/migrations/002_messages_table.dart` | Schema v2 migration (messages table) |
| `lib/core/database/migrations/003_mlkem_keys.dart` | Schema v3 migration (ML-KEM key columns on identity, contacts, contact_requests) |
| `lib/core/database/migrations/004_nullify_secret_columns.dart` | Schema v4 migration (makes private_key, mnemonic12 nullable) |
| `lib/core/database/migrations/005_secret_null_checks.dart` | Schema v5 migration (CHECK constraints enforcing secret columns NULL + avatar_blob BLOB) |
| `lib/core/database/migrations/006_read_at_column.dart` | Schema v6 migration (read_at TEXT column on messages table) |
| `lib/core/database/migrations/007_archive_columns.dart` | Schema v7 migration (is_archived, archived_at on contacts table) |
| `lib/core/database/migrations/008_block_columns.dart` | Schema v8 migration (is_blocked, blocked_at on contacts table) |
| `lib/core/database/migrations/009_quoted_message_id.dart` | Schema v9 migration (quoted_message_id TEXT on messages table) |
| `lib/core/database/migrations/010_media_attachments.dart` | Schema v10 migration (media_attachments table + indexes) |
| `lib/core/database/migrations/011_avatar_version.dart` | Schema v11 migration (avatar_version INTEGER on identity and contacts) |
| `lib/core/database/migrations/012_transport_column.dart` | Schema v12 migration (transport TEXT on messages) |
| `lib/core/database/migrations/013_waveform_column.dart` | Schema v13 migration (waveform TEXT on media_attachments) |
| `lib/core/database/migrations/014_wire_envelope_column.dart` | Schema v14 migration (wire_envelope TEXT on messages) |
| `lib/core/database/migrations/015_message_status_cleanup.dart` | Schema v15 migration (normalizes legacy 'queued' outgoing status to 'delivered') |
| `lib/core/database/migrations/016_message_reactions.dart` | Schema v16 migration (message_reactions table for emoji reactions) |
| `lib/core/database/migrations/017_groups_tables.dart` | Schema v17 migration (groups, group_members tables) |
| `lib/core/database/migrations/018_group_messages_tables.dart` | Schema v18 migration (group_keys, group_messages tables) |
| `lib/core/services/incoming_message_router.dart` | P2P message routing by type (6 typed streams) |
| `lib/core/services/pending_message_retrier.dart` | Retries failed outgoing messages on P2P reconnect (5s debounce) |
| `lib/core/lifecycle/handle_app_resumed.dart` | App resume recovery: bridge health → P2P health → inbox drain → key exchange retry |
| `lib/core/bridge/go_bridge_client.dart` | Go native bridge initialization + event handlers (MethodChannel/EventChannel) |
| `lib/core/bridge/bridge_group_helpers.dart` | Group bridge helper functions (create, join, leave, publish, keygen, encrypt, decrypt, etc.) |
| `lib/core/services/p2p_service_impl.dart` | P2P service initialization |
| `lib/features/contact_request/application/contact_request_listener.dart` | Background contact request listener startup |
| `lib/features/conversation/application/chat_message_listener.dart` | Background chat message listener startup |
| `lib/features/conversation/application/reaction_listener.dart` | Background reaction listener startup |
| `lib/features/settings/application/profile_update_listener.dart` | Background profile update listener startup |
| `lib/features/groups/application/group_message_listener.dart` | Group message listener (GossipSub → DB persistence + notifications) |
| `lib/features/groups/application/group_invite_listener.dart` | Group invite listener (P2P invite → create group + join topic) |
| `lib/features/groups/application/group_key_update_listener.dart` | Group key update listener (key rotation from admin) |
| `lib/features/groups/application/rejoin_group_topics_use_case.dart` | Re-subscribes active groups on app restart |
| `lib/features/groups/application/drain_group_offline_inbox_use_case.dart` | Retrieves queued group messages from relay inbox |
| `lib/features/identity/presentation/startup_router.dart` | Route decision logic + push token registration + group topic rejoin |
| `lib/features/identity/application/startup_decision.dart` | Business logic for routing |
| `lib/features/push/application/background_message_handler.dart` | Firebase background message handler; logs with `note: 'inbox drain deferred to next app resume'` |
| `lib/features/push/request_push_permission.dart` | Push notification permission request |
| `lib/features/push/register_push_token.dart` | FCM token registration via P2P inbox protocol |

### Adding New Initialization Steps

To add a new initialization step:
1. Add async initialization code in `main()` before `runApp()`
2. Inject dependencies into `MyApp` constructor
3. Pass dependencies through `StartupRouter` to child widgets
4. For new migrations, create `019_*.dart` and update `openEncryptedDatabase` version (currently v18)
5. For new P2P event handlers, register on `GoBridgeClient` in `P2PServiceImpl`
6. For new secrets, add read/write methods to `SecureKeyStore` and update `FlutterSecureKeyStore`

---

## Networking & Integration Points

### Current State (P2P Active)

The application has **active P2P networking** via the Go native library. Identity and cryptographic operations happen locally, while peer discovery and messaging use the rendezvous/relay server. Group messaging uses GossipSub pubsub over libp2p with per-group topics. Local WiFi discovery (mDNS via Bonsoir) provides an additional direct connectivity path.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      CURRENT INTEGRATION ARCHITECTURE                        │
└─────────────────────────────────────────────────────────────────────────────┘

                         ┌─────────────────────────────────────┐
                         │        Mknoon Identity App          │
                         │                                     │
                         │   ┌─────────────────────────────┐   │
                         │   │      Local Operations       │   │
                         │   │                             │   │
                         │   │  • Identity generation      │   │
                         │   │  • Mnemonic restore         │   │
                         │   │  • ML-KEM-768 key mgmt     │   │
                         │   │  • E2E message encryption   │   │
                         │   │  • QR code creation         │   │
                         │   │  • QR code scanning         │   │
                         │   │  • Profile management       │   │
                         │   │  • SQLCipher persistence     │   │
                         │   │  • Contact management       │   │
                         │   │  • Message persistence      │   │
                         │   │  • Ring avatar generation   │   │
                         │   └─────────────────────────────┘   │
                         │                                     │
                         │   ┌─────────────────────────────┐   │
                         │   │      P2P Operations         │   │
                         │   │                             │   │
                         │   │  • Node start/stop          │   │
                         │   │  • Rendezvous registration  │   │
                         │   │  • Peer discovery           │   │
                         │   │  • Peer dialing             │   │
                         │   │  • Message send/receive     │   │
                         │   │  • Contact request exchange │   │
                         │   │  • Chat message exchange    │   │
                         │   │  • GossipSub group topics   │   │
                         │   │  • Group peer discovery     │   │
                         │   │  • Group message publish    │   │
                         │   │  • Offline inbox fallback   │   │
                         │   │  • Group inbox (relay)      │   │
                         │   │  • Inbox drain on startup   │   │
                         │   │  • Push token registration  │   │
                         │   │  • Local WiFi discovery     │   │
                         │   │    (mDNS + WebSocket)       │   │
                         │   └──────────────┬──────────────┘   │
                         │                  │                   │
                         └──────────────────┼───────────────────┘
                                            │
                                            │ libp2p (QUIC / WebSocket relay)
                                            ▼
                         ┌─────────────────────────────────────┐
                         │   Rendezvous / Relay Server         │
                         │   mknoun.xyz:4001                    │
                         │                                     │
                         │   • Peer discovery (namespace)      │
                         │   • Circuit relay (NAT traversal)   │
                         │   • Offline inbox (store/retrieve)  │
                         │   • Group inbox (store/retrieve)    │
                         └──────────────────┬──────────────────┘
                                            │
                                            │ libp2p relay
                                            ▼
                         ┌─────────────────────────────────────┐
                         │        Another Device               │
                         │   (Running Mknoon Identity App)     │
                         │                                     │
                         │   Also reachable via local WiFi     │
                         │   (mDNS + direct WebSocket)         │
                         └─────────────────────────────────────┘
```

### Rendezvous Address

**Location:** `lib/core/constants/network_constants.dart`

```dart
const String RENDEZVOUS_ADDRESS =
    '/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g';
```

**Current Usage:**
- Embedded in QR payload via `buildQRPayload()` use case (field: `rv`)
- Used by P2P bridge client for rendezvous registration and discovery
- Used by `sendContactRequest()` for peer discovery

### QR Payload Structure

The QR code contains all information needed for P2P connection:

```json
{
  "ns": "mknoon-id-v1",           // Namespace/version
  "pk": "<base64-public-key>",    // Ed25519 public key
  "rv": "<multiaddr>",            // Rendezvous point (from constant)
  "ts": 1706745600000,            // Timestamp (ms since epoch)
  "un": "Username",               // Display name
  "sig": "<base64-signature>"     // Ed25519 signature of above fields
}
```

### P2P Contact Request Protocol

Contact requests support two wire formats:

**v1 (plaintext):**
```json
{
  "type": "contact_request",
  "version": "1",
  "payload": {
    "ns": "<peer_id>",
    "pk": "<base64-public-key>",
    "rv": "<rendezvous-multiaddr>",
    "ts": "<ISO8601-timestamp>",
    "un": "<username>",
    "mlkem": "<base64-ml-kem-768-public-key>",
    "sig": "<base64-signature>"
  }
}
```

**v2 (E2E encrypted with X25519 ECDH + HKDF-SHA256 + AES-256-GCM):**
```json
{
  "type": "contact_request",
  "version": "2",
  "senderPeerId": "12D3...",
  "msgId": "uuid",
  "ts": 1234567890,
  "encrypted": {
    "ephemeralPublicKey": "base64...",
    "ciphertext": "base64...",
    "nonce": "base64..."
  }
}
```

### P2P Chat Message Protocol

Chat messages support two wire formats:

**v1 (plaintext, backward compatible):**
```json
{
  "type": "chat_message",
  "version": "1",
  "payload": {
    "id": "<uuid-v4>",
    "text": "<message-text>",
    "senderPeerId": "<sender-peer-id>",
    "senderUsername": "<display-name>",
    "timestamp": "<ISO8601-timestamp>"
  }
}
```

**v2 (E2E encrypted with ML-KEM-768 + AES-256-GCM):**
```json
{
  "type": "chat_message",
  "version": "2",
  "senderPeerId": "<sender-peer-id>",
  "encrypted": {
    "kem": "<base64-ml-kem-768-ciphertext-1088-bytes>",
    "ciphertext": "<base64-aes-256-gcm-encrypted-payload>",
    "nonce": "<base64-12-byte-random-nonce>"
  }
}
```

Per-message encryption flow:
1. Sender: `ml_kem768.encapsulate(recipientPublicKey)` -> `{kemCiphertext, sharedSecret}`
2. Sender: `AES-256-GCM(plaintext, sharedSecret, nonce)` -> `aesCiphertext`
3. Receiver: `ml_kem768.decapsulate(kemCiphertext, ownSecretKey)` -> `sharedSecret`
4. Receiver: `AES-256-GCM-decrypt(aesCiphertext, sharedSecret, nonce)` -> `plaintext`

Each message gets a fresh KEM encapsulation for forward secrecy. Falls back to v1 when contact has no ML-KEM public key.

### P2P Group Message Protocol (GossipSub)

Group messages use GossipSub pubsub over libp2p. Each group has a dedicated topic (`/mknoon/group/<groupId>`). Messages are encrypted with a shared symmetric group key (AES-256-GCM) and signed with the sender's Ed25519 private key. The Go layer handles encryption, signing, validation, and decryption transparently.

**v3 (group encrypted + signed):**
```json
{
  "version": "3",
  "type": "group_message",
  "groupId": "<group-uuid>",
  "senderId": "<sender-peer-id>",
  "senderPublicKey": "<base64-ed25519-public-key>",
  "signature": "<base64-ed25519-signature>",
  "keyEpoch": 0,
  "encrypted": {
    "ciphertext": "<base64-aes-256-gcm-encrypted-payload>",
    "nonce": "<base64-12-byte-random-nonce>"
  }
}
```

Inner payload (after decryption):
```json
{
  "text": "<message-text>",
  "timestamp": "<RFC3339Nano-timestamp>",
  "username": "<sender-display-name>",
  "extra": { "media": [...] }
}
```

Group message flow:
1. Sender: `AES-256-GCM(payloadJSON, groupKey, nonce)` -> `ciphertext`
2. Sender: `Ed25519.sign(privateKey, groupId || keyEpoch || ciphertext)` -> `signature`
3. GossipSub publishes to topic (flood publish to ALL connected peers)
4. Topic validator on each peer: verifies sender is member, checks signature, checks write permission
5. Receiver: `AES-256-GCM-decrypt(ciphertext, groupKey, nonce)` -> `payloadJSON`
6. Go emits `group_message:received` event to Flutter via EventChannel

Group peer discovery uses two strategies:
- Primary: direct relay dialing of known group members by peer ID (from group config)
- Secondary: rendezvous register/discover on namespace `/mknoon/group/<groupId>` (30s interval)

Group types and write permissions:
- `chat`: any member can write
- `qa`: any member can write
- `announcement`: only admin-role members can write

### External Services

| Service | URL | Status | Purpose |
|---------|-----|--------|---------|
| Rendezvous/Relay Server | `mknoun.xyz:4001` | Active | P2P peer discovery and circuit relay |
| Firebase Cloud Messaging | Google FCM | Active | Push notifications for offline inbox messages |

### Go Bridge Command Registry

The Dart `GoBridgeClient._cmdMap` maps command strings (used by Dart callers) to MethodChannel method names (camelCase, invoked via platform wrappers GoBridge.swift / GoBridge.kt). Identity and crypto commands use dot-notation (`identity.generate`), P2P commands use colon-notation (`node:start`). The platform wrappers then dispatch to the Go library's `HandleCommand()`.

| Command (Dart) | MethodChannel Method | Handler | Description |
|---------|---------|---------|-------------|
| `identity.generate` | `generateIdentity` | Identity module | Generate new BIP39 mnemonic + Ed25519 keypair + ML-KEM-768 keypair |
| `identity.restore` | `restoreIdentity` | Identity module | Restore Ed25519 keypair from mnemonic + generate fresh ML-KEM-768 keypair |
| `payload.sign` | `signPayload` | Signing module | Sign data with Ed25519 private key |
| `payload.verify` | `verifyPayload` | Signing module | Verify Ed25519 signature against public key |
| `mlkem.keygen` | `mlKemKeygen` | Crypto module | Generate ML-KEM-768 keypair (publicKey + secretKey) |
| `message.encrypt` | `encryptMessage` | Crypto module | Encrypt message: ML-KEM-768 encapsulate + AES-256-GCM -> {kem, ciphertext, nonce} |
| `message.decrypt` | `decryptMessage` | Crypto module | Decrypt message: ML-KEM-768 decapsulate + AES-256-GCM -> {plaintext} |
| `contactrequest.encrypt` | `encryptContactRequest` | Crypto module | Encrypt contact request: X25519 ECDH + HKDF-SHA256 + AES-256-GCM |
| `contactrequest.decrypt` | `decryptContactRequest` | Crypto module | Decrypt contact request: X25519 ECDH + HKDF-SHA256 + AES-256-GCM |
| `node:start` | `startNode` | Node module | Start libp2p node with relay, auto-register |
| `node:stop` | `stopNode` | Node module | Stop libp2p node |
| `node:status` | `nodeStatus` | Node module | Get node status (peerId, connections, isStarted) |
| `rendezvous:register` | `rendezvousRegister` | Rendezvous module | Register peer with signed peer record |
| `rendezvous:discover` | `rendezvousDiscover` | Rendezvous module | Discover peers by namespace |
| `relay:reconnect` | `relayReconnect` | Node module | Reconnect to relay server |
| `relay:probe` | `relayProbe` | Node module | Probe relay server connectivity |
| `peer:dial` | `dialPeer` | Node module | Dial peer by ID and optional addresses |
| `peer:disconnect` | `disconnectPeer` | Node module | Disconnect from peer |
| `message:send` | `sendMessage` | Node module | Send message via /mknoon/chat/1.0.0 (frame-based with ACK) |
| `inbox:store` | `inboxStore` | Inbox module | Store message in offline inbox on relay |
| `inbox:retrieve` | `inboxRetrieve` | Inbox module | Retrieve messages from offline inbox |
| `inbox:register_token` | `inboxRegisterToken` | Inbox module | Register FCM device token for push notifications |
| `media:upload` | `mediaUpload` | Media module | Upload media to relay via /mknoon/media/1.0.0 |
| `media:download` | `mediaDownload` | Media module | Download media from relay via /mknoon/media/1.0.0 |
| `media:delete` | `mediaDelete` | Media module | Delete media from relay via /mknoon/media/1.0.0 |
| `media:list` | `mediaList` | Media module | List media on relay via /mknoon/media/1.0.0 |
| `profile:upload` | `profileUpload` | Media module | Upload profile picture to relay |
| `profile:download` | `profileDownload` | Media module | Download profile picture from relay |
| `group:create` | `groupCreate` | PubSub module | Create group: generate ID, join GossipSub topic, register validator |
| `group:join` | `groupJoinTopic` | PubSub module | Join existing group topic with config + key (used by invitees and rejoin on restart) |
| `group:leave` | `groupLeaveTopic` | PubSub module | Leave group topic: cancel subscription, discovery, unregister validator |
| `group:publish` | `groupPublish` | PubSub module | Encrypt + sign + publish v3 envelope to group GossipSub topic |
| `group:updateConfig` | `groupUpdateConfig` | PubSub module | Update stored group config (member list, name, type) |
| `group:rotateKey` | `groupRotateKey` | PubSub module | Generate new group key, increment epoch |
| `group:updateKey` | `groupUpdateKey` | PubSub module | Update stored group key (non-admin receiving key rotation) |
| `group:inboxStore` | `groupInboxStore` | PubSub module | Store group message in relay inbox (offline delivery) |
| `group:inboxRetrieve` | `groupInboxRetrieve` | PubSub module | Retrieve group messages from relay inbox |
| `group.keygen` | `generateGroupKey` | Crypto module | Generate AES-256 symmetric group key |
| `group.encrypt` | `groupEncryptMessage` | Crypto module | Encrypt plaintext with group key (AES-256-GCM) |
| `group.decrypt` | `groupDecryptMessage` | Crypto module | Decrypt ciphertext with group key (AES-256-GCM) |
