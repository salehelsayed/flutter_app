# C4 Model - Mknoon Identity App

## Level 1: System Context

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              SYSTEM CONTEXT                                  │
└─────────────────────────────────────────────────────────────────────────────┘

                                 ┌─────────┐
                                 │  User   │
                                 │ (Person)│
                                 └────┬────┘
                                      │
                                      │ Uses app to create/restore
                                      │ cryptographic identity, share
                                      │ QR codes, discover peers,
                                      │ exchange contact requests,
                                      │ and send encrypted messages
                                      ▼
                        ┌─────────────────────────────┐
                        │                             │
                        │   Mknoon Identity App       │
                        │   [Software System]         │
                        │                             │
                        │   Allows users to generate  │
                        │   or restore a libp2p       │
                        │   identity, customize their │
                        │   profile, share QR codes,  │
                        │   connect via P2P, and      │
                        │   manage contacts           │
                        │                             │
                        └──────────────┬──────────────┘
                                       │
                                       │ libp2p (QUIC / WebSocket)
                                       │ via rendezvous relay
                                       ▼
                        ┌─────────────────────────────┐
                        │   Rendezvous / Relay Server │
                        │   [External System]         │
                        │                             │
                        │   mknoun.xyz:4001            │
                        │   Peer discovery, relay,    │
                        │   & offline message inbox   │
                        └─────────────────────────────┘

```

### Description

| Element | Type | Description |
|---------|------|-------------|
| User | Person | End user who wants to create or restore their cryptographic identity, connect with peers, manage contacts, and exchange encrypted messages |
| Mknoon Identity App | Software System | Mobile/desktop app for identity management, profile customization, peer discovery, contact requests, E2E encrypted conversations (ML-KEM-768 + AES-256-GCM), offline inbox, push notifications (Firebase Cloud Messaging), P2P messaging using Go-native libp2p and BIP39, and local WiFi discovery via mDNS. Data at rest encrypted via SQLCipher + OS-backed secure storage |
| Rendezvous / Relay Server | External System | libp2p rendezvous server for peer discovery, circuit relay for NAT traversal, and offline message inbox (`/mknoon/inbox/1.0.0`) for store-and-forward delivery |

### External Dependencies
- Rendezvous/Relay server at `mknoun.xyz:4001` (libp2p QUIC / WebSocket)
- Firebase Cloud Messaging (FCM) for push notifications

---

## Level 2: Container Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              CONTAINER DIAGRAM                               │
└─────────────────────────────────────────────────────────────────────────────┘

                                 ┌─────────┐
                                 │  User   │
                                 └────┬────┘
                                      │
                                      │ Interacts via UI
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Mknoon Identity App                                │
│  ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐ │
│                                                                             │
│  │  ┌───────────────────────────────────────────────────────────────┐   │  │
│     │                     Flutter Application                        │     │
│  │  │                     [Container: Dart/Flutter]                  │  │  │
│     │                                                                │     │
│  │  │  • UI screens and widgets (glassmorphic theme)                 │  │  │
│     │  • Business logic (use cases)                                  │     │
│  │  │  • Repository layer                                            │  │  │
│     │  • Bridge clients (identity + P2P)                             │     │
│  │  │  • QR code generation & scanning                               │  │  │
│     │  • Contact & contact request management                        │     │
│  │  │  • P2P service layer                                           │  │  │
│     │  • Ring avatar generation                                      │     │
│  │  │  • Image picker for avatars                                    │  │  │
│     │  • Local WiFi discovery (mDNS + WebSocket)                     │     │
│  │  └──────────────┬──────────────────┬──────────────┬──────────────┘│  │
│                    │                  │              │                   │
│  │                 │ MethodChannel/   │ SQL queries  │ Keychain/      │  │
│                    │ EventChannel     │              │ Keystore          │
│  │                 ▼                  ▼              ▼                │  │
│     ┌─────────────────────────┐ ┌─────────────────────┐ ┌────────────┐  │
│  │  │  Go Native Library      │ │  SQLCipher Database  │ │  Secure    ││  │
│     │  [Container: gomobile]  │ │  [Container:         │ │  Storage   │  │
│  │  │                         │ │  sqflite_sqlcipher]  │ │  [Container││  │
│     │  • BIP39 mnemonic gen   │ │                      │ │  flutter_  │  │
│  │  │  • Ed25519 keypair      │ │  • identity table    │ │  secure_   ││  │
│     │  • ML-KEM-768 keygen   │ │  • contacts table    │ │  storage]  │  │
│  │  │  • libp2p peer ID       │ │  • contact_requests  │ │            ││  │
│     │  • Payload sign/verify  │ │  • messages table    │ │ • private  │  │
│  │  │  • Message encrypt/     │ │  • avatar BLOB store │ │   _key     ││  │
│     │    decrypt              │ │  • 256-bit AES       │ │ • mnemonic │  │
│  │  │  • P2P node management  │ │    encrypted         │ │   12       ││  │
│     │  • Peer discovery &     │ │                      │ │ • ml_kem_  │  │
│  │  │    relay                │ │                      │ │   secret   ││  │
│     │  • Message send/receive │ │                      │ │ • db_enc   │  │
│  │  │  • Offline inbox store/ │ │                      │ │   _key     ││  │
│     │    retrieve             │ │                      │ │            │  │
│  │  └──────────────┬──────────┘ └──────────────────────┘ └────────────┘│  │
│                    │                                                      │
│  │                 │ libp2p (QUIC / WebSocket)                        │  │
│                    │                                                      │
│  └ ─ ─ ─ ─ ─ ─ ─ ─┼─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘  │
│                    │                                                      │
└────────────────────┼─────────────────────────────────────────────────────┘
                     │
                     │ libp2p (QUIC / WebSocket relay)
                     ▼
              ┌─────────────────────────────┐
              │   Rendezvous / Relay Server │
              │   mknoun.xyz:4001           │
              └─────────────────────────────┘
```

### Containers

| Container | Technology | Description |
|-----------|------------|-------------|
| Flutter Application | Dart/Flutter | Main application with UI, business logic, P2P service, local WiFi discovery (mDNS), and data access |
| Go Native Library | gomobile bind → .xcframework (iOS) + .aar (Android) | Executes crypto operations (BIP39, Ed25519, ML-KEM-768) and P2P networking (libp2p node, rendezvous, relay, inbox); communicates with Flutter via MethodChannel/EventChannel through platform wrappers (GoBridge.swift / GoBridge.kt) |
| SQLCipher Database | sqflite_sqlcipher | 256-bit AES encrypted SQLite database; persists identity, contacts, contact requests, messages, and avatar BLOBs locally |
| Secure Storage | flutter_secure_storage | OS-backed secret storage: iOS Keychain (device-bound, kSecAttrAccessibleWhenUnlockedThisDeviceOnly), Android EncryptedSharedPreferences; holds identity secrets and DB encryption key |
| Rendezvous / Relay Server | libp2p | External server for peer discovery, NAT traversal relay, and offline message inbox |
| Firebase Cloud Messaging | Firebase SDK | External push notification service; relay server sends FCM push when storing offline inbox messages |

### Communication

| From | To | Protocol | Description |
|------|-----|----------|-------------|
| Flutter App | Go Native Library | MethodChannel / EventChannel via platform wrappers | Request/response for identity, signing, crypto, and P2P operations; push events (message:received, peer:connected, peer:disconnected) delivered via EventChannel |
| Flutter App | SQLCipher DB | SQL via sqflite_sqlcipher | CRUD operations for identity, contacts, contact requests, messages, and avatar BLOBs (256-bit AES encrypted at rest) |
| Flutter App | Secure Storage | flutter_secure_storage API | Read/write identity secrets (private_key, mnemonic12, ml_kem_secret_key) and DB encryption key |
| Go Native Library | Rendezvous Server | libp2p (QUIC / WebSocket) | Peer discovery, relay circuits, messaging, and offline inbox protocol (`/mknoon/inbox/1.0.0`) |
| Flutter App | Firebase Cloud Messaging | HTTPS (FCM SDK) | Registers device token, receives push notifications for offline inbox messages |

---

## Level 3: Component Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            COMPONENT DIAGRAM                                 │
└─────────────────────────────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────────────────┐
│                          FLUTTER APPLICATION                                 │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                        PRESENTATION LAYER                              │ │
│  │                                                                        │ │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │ │
│  │  │                    IDENTITY FEATURE                              │  │ │
│  │  │  ┌──────────────────┐  ┌──────────────────┐  ┌────────────────┐ │  │ │
│  │  │  │  StartupRouter   │  │IdentityChoice    │  │ MnemonicInput  │ │  │ │
│  │  │  │  [Widget]        │  │Screen [Widget]   │  │ Screen         │ │  │ │
│  │  │  │                  │  │                  │  │                │ │  │ │
│  │  │  │  Routes to home  │  │  "I'm new here"  │  │  TextField +   │ │  │ │
│  │  │  │  or onboarding   │  │  "Load my key"   │  │  "Restore"     │ │  │ │
│  │  │  └──────────────────┘  └──────────────────┘  └────────────────┘ │  │ │
│  │  └─────────────────────────────────────────────────────────────────┘  │ │
│  │                                                                        │ │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │ │
│  │  │                      HOME FEATURE                                │  │ │
│  │  │  ┌──────────────────────────────────────────────────────────┐   │  │ │
│  │  │  │         FirstTimeExperienceScreen [Widget]                │   │  │ │
│  │  │  │                                                           │   │  │ │
│  │  │  │  ┌────────────────┐  ┌────────────────┐  ┌────────────┐  │   │  │ │
│  │  │  │  │ProfileAvatar   │  │EditableUsername│  │QRCodeSection│  │   │  │ │
│  │  │  │  │Widget          │  │Widget          │  │            │  │   │  │ │
│  │  │  │  └────────────────┘  └────────────────┘  └────────────┘  │   │  │ │
│  │  │  │  ┌────────────────┐  ┌────────────────┐  ┌────────────┐  │   │  │ │
│  │  │  │  │ScanFriendCard  │  │EmptyCircleState│  │Connection  │  │   │  │ │
│  │  │  │  │                │  │(pulsing anim)  │  │StatusIndic.│  │   │  │ │
│  │  │  │  └────────────────┘  └────────────────┘  └────────────┘  │   │  │ │
│  │  │  │  ┌────────────────┐  ┌────────────────┐                  │   │  │ │
│  │  │  │  │RingAvatar      │  │RingAvatarPaint.│                  │   │  │ │
│  │  │  │  │(deterministic) │  │(canvas render) │                  │   │  │ │
│  │  │  │  └────────────────┘  └────────────────┘                  │   │  │ │
│  │  │  └──────────────────────────────────────────────────────────┘   │  │ │
│  │  └─────────────────────────────────────────────────────────────────┘  │ │
│  │                                                                        │ │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │ │
│  │  │                    QR CODE FEATURE                               │  │ │
│  │  │  ┌──────────────────┐  ┌──────────────────┐  ┌────────────────┐ │  │ │
│  │  │  │ QRDisplayScreen  │  │ QRScannerScreen  │  │ ScanOverlay    │ │  │ │
│  │  │  │ [Widget]         │  │ [Widget]         │  │ [Widget]       │ │  │ │
│  │  │  │                  │  │                  │  │                │ │  │ │
│  │  │  │  Show QR with    │  │  Camera-based    │  │  Corner markers│ │  │ │
│  │  │  │  signed payload  │  │  QR code scanner │  │  scan area     │ │  │ │
│  │  │  └──────────────────┘  └──────────────────┘  └────────────────┘ │  │ │
│  │  └─────────────────────────────────────────────────────────────────┘  │ │
│  │                                                                        │ │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │ │
│  │  │                CONTACT REQUEST FEATURE                           │  │ │
│  │  │  ┌──────────────────────┐  ┌──────────────────────────────────┐ │  │ │
│  │  │  │ContactRequestDialog  │  │PendingRequestsBadge              │ │  │ │
│  │  │  │[Widget]              │  │[Widget]                          │ │  │ │
│  │  │  │                      │  │                                  │ │  │ │
│  │  │  │ Accept/Decline modal │  │ Circular count badge (99+ max)  │ │  │ │
│  │  │  │ with RingAvatar      │  │                                  │ │  │ │
│  │  │  └──────────────────────┘  └──────────────────────────────────┘ │  │ │
│  │  └─────────────────────────────────────────────────────────────────┘  │ │
│  │                                                                        │ │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │ │
│  │  │                      FEED FEATURE                                │  │ │
│  │  │  ┌──────────────────────────────────────────────────────────┐   │  │ │
│  │  │  │              FeedScreen [Widget]                          │   │  │ │
│  │  │  │                                                           │   │  │ │
│  │  │  │  ┌────────────────┐  ┌────────────────┐  ┌────────────┐  │   │  │ │
│  │  │  │  │FeedHeader      │  │ConnectionCard  │  │MessageFeed │  │   │  │ │
│  │  │  │  │(username+avatar)│  │(inline badge)  │  │Card (reply)│  │   │  │ │
│  │  │  │  └────────────────┘  └────────────────┘  └────────────┘  │   │  │ │
│  │  │  │  ┌────────────────┐  ┌────────────────┐  ┌────────────┐  │   │  │ │
│  │  │  │  │FeedNavBar      │  │NavBarButton    │  │UnreadCount │  │   │  │ │
│  │  │  │  │(glass, 3 tabs) │  │(badge overlay) │  │Badge (count)│  │   │  │ │
│  │  │  │  └────────────────┘  └────────────────┘  └────────────┘  │   │  │ │
│  │  │  └──────────────────────────────────────────────────────────┘   │  │ │
│  │  └─────────────────────────────────────────────────────────────────┘  │ │
│  │                                                                        │ │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │ │
│  │  │                  CONVERSATION FEATURE                           │  │ │
│  │  │  ┌──────────────────────────────────────────────────────────┐   │  │ │
│  │  │  │         ConversationScreen [Widget]                       │   │  │ │
│  │  │  │                                                           │   │  │ │
│  │  │  │  ┌────────────────┐  ┌────────────────┐  ┌────────────┐  │   │  │ │
│  │  │  │  │Conversation    │  │LetterCard      │  │ComposeArea │  │   │  │ │
│  │  │  │  │Header (glass)  │  │(full-width msg)│  │(text+send) │  │   │  │ │
│  │  │  │  └────────────────┘  └────────────────┘  └────────────┘  │   │  │ │
│  │  │  │  ┌────────────────┐  ┌────────────────┐  ┌────────────┐  │   │  │ │
│  │  │  │  │EmptyConversatio│  │CompactOrigin   │  │DateSeparat.│  │   │  │ │
│  │  │  │  │nState (glow)   │  │Marker          │  │(day divide)│  │   │  │ │
│  │  │  │  └────────────────┘  └────────────────┘  └────────────┘  │   │  │ │
│  │  │  └──────────────────────────────────────────────────────────┘   │  │ │
│  │  └─────────────────────────────────────────────────────────────────┘  │ │
│  │                                                                        │ │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │ │
│  │  │                      ORBIT FEATURE                              │  │ │
│  │  │  ┌──────────────────────────────────────────────────────────┐   │  │ │
│  │  │  │              OrbitScreen [Widget]                         │   │  │ │
│  │  │  │                                                           │   │  │ │
│  │  │  │  ┌────────────────┐  ┌────────────────┐  ┌────────────┐  │   │  │ │
│  │  │  │  │OrbitalVisualiz.│  │OrbitalRing     │  │OrbitalAvat.│  │   │  │ │
│  │  │  │  │(320x320 stack) │  │Painter (dashed)│  │(scale-in)  │  │   │  │ │
│  │  │  │  └────────────────┘  └────────────────┘  └────────────┘  │   │  │ │
│  │  │  │  ┌────────────────┐  ┌────────────────┐  ┌────────────┐  │   │  │ │
│  │  │  │  │OverflowBadge   │  │OrbitHeader     │  │OrbitClose  │  │   │  │ │
│  │  │  │  │("+N" delayed)  │  │(right avatar)  │  │Button (X)  │  │   │  │ │
│  │  │  │  └────────────────┘  └────────────────┘  └────────────┘  │   │  │ │
│  │  │  │  ┌────────────────┐  ┌────────────────┐  ┌────────────┐  │   │  │ │
│  │  │  │  │FriendsListHead.│  │SwipeableFriend │  │OrbitSearch │  │   │  │ │
│  │  │  │  │(QR/Scan pills) │  │Row (swipe acts)│  │Trigger     │  │   │  │ │
│  │  │  │  └────────────────┘  └────────────────┘  └────────────┘  │   │  │ │
│  │  │  │  ┌────────────────┐  ┌────────────────┐  ┌────────────┐  │   │  │ │
│  │  │  │  │OrbitSearchDock │  │FriendsFilter   │  │QRAction    │  │   │  │ │
│  │  │  │  │(bottom search) │  │Toggle (All/Ar.)│  │Cards       │  │   │  │ │
│  │  │  │  └────────────────┘  └────────────────┘  └────────────┘  │   │  │ │
│  │  │  └──────────────────────────────────────────────────────────┘   │  │ │
│  │  └─────────────────────────────────────────────────────────────────┘  │ │
│  │                                                                        │ │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │ │
│  │  │                    SHARED WIDGETS                                │  │ │
│  │  │  ┌──────────────────┐  ┌──────────────────┐  ┌────────────────┐ │  │ │
│  │  │  │AmbientBackground │  │GlassmorphicCont. │  │ChoiceCard      │ │  │ │
│  │  │  │(animated glows)  │  │(frosted glass)   │  │(tap animation) │ │  │ │
│  │  │  └──────────────────┘  └──────────────────┘  └────────────────┘ │  │ │
│  │  └─────────────────────────────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                        APPLICATION LAYER                               │ │
│  │                                                                        │ │
│  │  ── Identity ──────────────────────────────────────────────────────── │ │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────┐ │ │
│  │  │ decideStartup    │  │ generateNew      │  │ restoreIdentity      │ │ │
│  │  │ Route()          │  │ Identity()       │  │ FromMnemonic()       │ │ │
│  │  │ [Use Case]       │  │ [Use Case]       │  │ [Use Case]           │ │ │
│  │  └──────────────────┘  └──────────────────┘  └──────────────────────┘ │ │
│  │                                                                        │ │
│  │  ── QR Code ───────────────────────────────────────────────────────── │ │
│  │  ┌──────────────────┐  ┌──────────────────┐                          │ │
│  │  │ buildQRPayload() │  │ parseQRPayload() │                          │ │
│  │  │ [Use Case]       │  │ [Use Case]       │                          │ │
│  │  └──────────────────┘  └──────────────────┘                          │ │
│  │                                                                        │ │
│  │  ── P2P ──────────────────────────────────────────────────────────── │ │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────┐ │ │
│  │  │ startP2PNode()   │  │ stopP2PNode()    │  │ sendP2PMessage()     │ │ │
│  │  │ [Use Case]       │  │ [Use Case]       │  │ [Use Case]           │ │ │
│  │  └──────────────────┘  └──────────────────┘  └──────────────────────┘ │ │
│  │  ┌──────────────────┐                                                 │ │
│  │  │ discoverP2PPeer()│  + dialP2PPeer()                                │ │
│  │  │ [Use Case]       │                                                 │ │
│  │  └──────────────────┘                                                 │ │
│  │                                                                        │ │
│  │  ── Contacts ──────────────────────────────────────────────────────── │ │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────┐ │ │
│  │  │ addContact()     │  │ archiveContact() │  │ unarchiveContact()   │ │ │
│  │  │ [Use Case]       │  │ [Use Case]       │  │ [Use Case]           │ │ │
│  │  └──────────────────┘  └──────────────────┘  └──────────────────────┘ │ │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────┐ │ │
│  │  │ blockContact()   │  │ unblockContact() │  │ deleteContactAnd     │ │ │
│  │  │ [Use Case]       │  │ [Use Case]       │  │ Messages() [UC]      │ │ │
│  │  └──────────────────┘  └──────────────────┘  └──────────────────────┘ │ │
│  │                                                                        │ │
│  │  ── Contact Requests ──────────────────────────────────────────────── │ │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────┐ │ │
│  │  │ sendContact      │  │ acceptContact    │  │ declineContact       │ │ │
│  │  │ Request()        │  │ Request()        │  │ Request()            │ │ │
│  │  │ [Use Case]       │  │ [Use Case]       │  │ [Use Case]           │ │ │
│  │  └──────────────────┘  └──────────────────┘  └──────────────────────┘ │ │
│  │  ┌──────────────────┐  ┌──────────────────────────────────────────┐   │ │
│  │  │ handleIncoming   │  │ ContactRequestListener                   │   │ │
│  │  │ Message()        │  │ [Service: monitors P2P message stream]   │   │ │
│  │  │ [Use Case]       │  │                                          │   │ │
│  │  └──────────────────┘  └──────────────────────────────────────────┘   │ │
│  │                                                                        │ │
│  │  ── Conversation ─────────────────────────────────────────────────── │ │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────┐ │ │
│  │  │ sendChat         │  │ handleIncoming   │  │ loadConversation()   │ │ │
│  │  │ Message()        │  │ ChatMessage()    │  │ [Use Case]           │ │ │
│  │  │ [Use Case]       │  │ [Use Case]       │  │                      │ │ │
│  │  └──────────────────┘  └──────────────────┘  └──────────────────────┘ │ │
│  │  ┌──────────────────────────────────────────┐                         │ │
│  │  │ ChatMessageListener                      │                         │ │
│  │  │ [Service: monitors chatMessageStream]    │                         │ │
│  │  └──────────────────────────────────────────┘                         │ │
│  │  ┌──────────────────────────────────────────┐                         │ │
│  │  │ markConversationRead()                   │                         │ │
│  │  │ [Use Case]                               │                         │ │
│  │  └──────────────────────────────────────────┘                         │ │
│  │  ┌──────────────────────────────────────────┐                         │ │
│  │  │ retryFailedMessages()                    │                         │ │
│  │  │ [Use Case]                               │                         │ │
│  │  └──────────────────────────────────────────┘                         │ │
│  │                                                                        │ │
│  │  ── Feed ─────────────────────────────────────────────────────────── │ │
│  │  ┌──────────────────┐                                                 │ │
│  │  │ loadFeed()       │  Loads contacts + latest messages + unread     │ │
│  │  │ [Use Case]       │  counts per contact                            │ │
│  │  └──────────────────┘                                                 │ │
│  │                                                                        │ │
│  │  ── Orbit ────────────────────────────────────────────────────────── │ │
│  │  ┌──────────────────┐                                                 │ │
│  │  │ loadOrbitData()  │  Loads contacts + message counts + unread       │ │
│  │  │ [Use Case]       │  counts, sorted by messageCount descending      │ │
│  │  └──────────────────┘                                                 │ │
│  │                                                                        │ │
│  │  ── Push Notifications ──────────────────────────────────────────── │ │
│  │  ┌──────────────────────────────────────────┐                         │ │
│  │  │ requestPushPermission()                  │                         │ │
│  │  │ [Use Case]                               │                         │ │
│  │  └──────────────────────────────────────────┘                         │ │
│  │  ┌──────────────────────────────────────────┐                         │ │
│  │  │ registerPushToken()                      │                         │ │
│  │  │ [Use Case]                               │                         │ │
│  │  └──────────────────────────────────────────┘                         │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                          DOMAIN LAYER                                  │ │
│  │                                                                        │ │
│  │  ── Models ────────────────────────────────────────────────────────── │ │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────┐ │ │
│  │  │  IdentityModel   │  │  ContactModel    │  │ ContactRequestModel  │ │ │
│  │  │  [Entity]        │  │  [Entity]        │  │ [Entity]             │ │ │
│  │  └──────────────────┘  └──────────────────┘  └──────────────────────┘ │ │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────┐ │ │
│  │  │  NodeState       │  │ DiscoveredPeer   │  │ ConnectionState      │ │ │
│  │  │  [P2P Model]     │  │ [P2P Model]      │  │ [P2P Model]          │ │ │
│  │  └──────────────────┘  └──────────────────┘  └──────────────────────┘ │ │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────┐ │ │
│  │  │  ChatMessage     │  │ QRPayloadModel   │  │ FeedItem (abstract)  │ │ │
│  │  │  [P2P Model]     │  │ [QR Model]       │  │ [Feed Model]         │ │ │
│  │  └──────────────────┘  └──────────────────┘  └──────────────────────┘ │ │
│  │  ┌──────────────────┐  ┌──────────────────┐                           │ │
│  │  │ ConnectionFeed   │  │ MessageFeedItem  │  Both extend FeedItem     │ │
│  │  │ Item [Feed Model]│  │ [Feed Model]     │                           │ │
│  │  └──────────────────┘  └──────────────────┘                           │ │
│  │  ┌──────────────────┐  ┌──────────────────┐                           │ │
│  │  │ Conversation     │  │ MessagePayload   │                           │ │
│  │  │ Message [Model]  │  │ [Wire Model]     │                           │ │
│  │  └──────────────────┘  └──────────────────┘                           │ │
│  │  ┌──────────────────┐                                                 │ │
│  │  │ OrbitFriend       │  Composite: ContactModel + messageCount        │ │
│  │  │ [Orbit Model]    │  + lastActivity + lastMessageTimestamp          │ │
│  │  │                  │  + unreadCount (default 0)                      │ │
│  │  └──────────────────┘                                                 │ │
│  │                                                                        │ │
│  │  ── Repositories ──────────────────────────────────────────────────── │ │
│  │  ┌──────────────────────┐  ┌──────────────────────────────────────┐   │ │
│  │  │  IdentityRepository  │  │  ContactRepository                   │   │ │
│  │  │  [Interface + Impl]  │  │  [Interface + Impl]                  │   │ │
│  │  └──────────────────────┘  └──────────────────────────────────────┘   │ │
│  │  ┌──────────────────────────────────────────┐                         │ │
│  │  │  ContactRequestRepository                │                         │ │
│  │  │  [Interface + Impl]                      │                         │ │
│  │  └──────────────────────────────────────────┘                         │ │
│  │  ┌──────────────────────────────────────────┐                         │ │
│  │  │  MessageRepository                       │                         │ │
│  │  │  [Interface + Impl]                      │                         │ │
│  │  └──────────────────────────────────────────┘                         │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                           CORE LAYER                                   │ │
│  │                                                                        │ │
│  │  ── Bridge ────────────────────────────────────────────────────────── │ │
│  │  ┌──────────────────────────┐  ┌──────────────────────────────────┐   │ │
│  │  │     GoBridgeClient       │  │     P2PBridgeClient              │   │ │
│  │  │     [Bridge Client]      │  │     [Bridge Client]              │   │ │
│  │  │  MethodChannel/EventChan │  │                                  │   │ │
│  │  └──────────────────────────┘  └──────────────────────────────────┘   │ │
│  │  ┌──────────────────────────┐                                         │ │
│  │  │  Bridge Helper Functions │  In bridge.dart: callIdentityGenerate,  │ │
│  │  │  [in bridge.dart +       │  callSignPayload, callVerifyPayload,    │ │
│  │  │   p2p_bridge_client.dart]│  callMlKemKeygen, callEncryptMessage,   │ │
│  │  │                          │  callDecryptMessage                     │ │
│  │  │                          │  In p2p_bridge_client.dart: callP2P*    │ │
│  │  └──────────────────────────┘                                         │ │
│  │                                                                        │ │
│  │  ── Services ──────────────────────────────────────────────────────── │ │
│  │  ┌──────────────────────────────────────────┐                         │ │
│  │  │   P2PService [Interface] → P2PServiceImpl│                         │ │
│  │  │   Reactive streams for state + messages  │                         │ │
│  │  │   + offline inbox store/retrieve         │                         │ │
│  │  │   + registerPushToken (FCM push)         │                         │ │
│  │  │   + performImmediateHealthCheck()        │                         │ │
│  │  │   + drainOfflineInbox()                  │                         │ │
│  │  │   + sendMessageWithReply() (ACK support) │                         │ │
│  │  │   + local WiFi discovery (mDNS/Bonsoir)  │                         │ │
│  │  └──────────────────────────────────────────┘                         │ │
│  │  ┌──────────────────────────────────────────┐                         │ │
│  │  │   IncomingMessageRouter                  │                         │ │
│  │  │   Routes P2P msgs → typed streams        │                         │ │
│  │  │   (contactRequest, chatMessage, unknown)  │                         │ │
│  │  └──────────────────────────────────────────┘                         │ │
│  │  ┌──────────────────────────────────────────┐                         │ │
│  │  │   PendingMessageRetrier                  │                         │ │
│  │  │   Subscribes to stateStream, retries     │                         │ │
│  │  │   failed messages on reconnect (5s deb.) │                         │ │
│  │  └──────────────────────────────────────────┘                         │ │
│  │                                                                        │ │
│  │  ── Database ──────────────────────────────────────────────────────── │ │
│  │  ┌──────────────────────────┐  ┌──────────────────────────────────┐   │ │
│  │  │  identity_db_helpers     │  │  contacts_db_helpers             │   │ │
│  │  └──────────────────────────┘  └──────────────────────────────────┘   │ │
│  │  ┌──────────────────────────┐  ┌──────────────────────────────────┐   │ │
│  │  │  contact_requests_db_    │  │  messages_db_helpers             │   │ │
│  │  │  helpers                 │  │                                  │   │ │
│  │  └──────────────────────────┘  └──────────────────────────────────┘   │ │
│  │  ┌──────────────────────────┐  ┌──────────────────────────────────┐   │ │
│  │  │  001_identity_table      │  │  002_messages_table migration    │   │ │
│  │  │  migration (3 tables)    │  │  (messages table + indexes)      │   │ │
│  │  └──────────────────────────┘  └──────────────────────────────────┘   │ │
│  │  ┌──────────────────────────┐                                         │ │
│  │  │  003_mlkem_keys          │  ML-KEM key columns on identity,       │ │
│  │  │  migration (v3)          │  contacts, contact_requests            │ │
│  │  └──────────────────────────┘                                         │ │
│  │  ┌──────────────────────────┐  ┌──────────────────────────────────┐   │ │
│  │  │  004_nullify_secret_     │  │  005_secret_null_checks          │   │ │
│  │  │  columns migration (v4)  │  │  migration (v5)                  │   │ │
│  │  │  Makes private_key,      │  │  CHECK constraints: private_key, │   │ │
│  │  │  mnemonic12 nullable     │  │  mnemonic12, ml_kem_secret_key   │   │ │
│  │  └──────────────────────────┘  │  must be NULL + avatar_blob BLOB │   │ │
│  │                                └──────────────────────────────────┘   │ │
│  │  ┌──────────────────────────┐                                         │ │
│  │  │  006_read_at_column      │  Adds read_at TEXT column to           │ │
│  │  │  migration (v6)          │  messages table for unread tracking    │ │
│  │  └──────────────────────────┘                                         │ │
│  │  ┌──────────────────────────┐  ┌──────────────────────────────────┐   │ │
│  │  │  007_archive_columns     │  │  008_block_columns               │   │ │
│  │  │  migration (v7)          │  │  migration (v8)                  │   │ │
│  │  │  Adds is_archived,       │  │  Adds is_blocked,               │   │ │
│  │  │  archived_at to contacts │  │  blocked_at to contacts         │   │ │
│  │  └──────────────────────────┘  └──────────────────────────────────┘   │ │
│  │  ┌──────────────────────────┐                                         │ │
│  │  │  encrypted_db_opener     │  Opens SQLCipher DB with key from      │ │
│  │  │                          │  secure storage; handles plaintext→    │ │
│  │  │                          │  encrypted migration                   │ │
│  │  └──────────────────────────┘                                         │ │
│  │                                                                        │ │
│  │  ── Secure Storage ───────────────────────────────────────────────── │ │
│  │  ┌──────────────────────────┐  ┌──────────────────────────────────┐   │ │
│  │  │  SecureKeyStore          │  │  FlutterSecureKeyStore           │   │ │
│  │  │  [Interface]             │  │  [Impl: flutter_secure_storage]  │   │ │
│  │  │  read/write/delete/      │  │  iOS Keychain (device-bound)    │   │ │
│  │  │  containsKey             │  │  Android EncryptedSharedPrefs    │   │ │
│  │  └──────────────────────────┘  └──────────────────────────────────┘   │ │
│  │  ┌──────────────────────────┐                                         │ │
│  │  │  migrate_secrets_to_     │  One-time DB→secure storage migration  │ │
│  │  │  secure_storage          │  with secrets_migrated sentinel        │ │
│  │  └──────────────────────────┘                                         │ │
│  │                                                                        │ │
│  │  ── Utils ─────────────────────────────────────────────────────────── │ │
│  │  ┌──────────────────────────┐  ┌──────────────────────────────────┐   │ │
│  │  │  RingAvatarGenerator     │  │  KeyConversion                   │   │ │
│  │  │  (deterministic avatars) │  │  (base64 ↔ hex)                  │   │ │
│  │  └──────────────────────────┘  └──────────────────────────────────┘   │ │
│  │  ┌──────────────────────────┐  ┌──────────────────────────────────┐   │ │
│  │  │  FlowEventEmitter        │  │  NetworkConstants                │   │ │
│  │  │  (logging utility)       │  │  (rendezvous address)            │   │ │
│  │  └──────────────────────────┘  └──────────────────────────────────┘   │ │
│  │                                                                        │ │
│  │  ── Theme ─────────────────────────────────────────────────────────── │ │
│  │  ┌──────────────────────────┐  ┌──────────────────────────────────┐   │ │
│  │  │  AppColors / AppTheme    │  │  GlassmorphicContainer           │   │ │
│  │  └──────────────────────────┘  └──────────────────────────────────┘   │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
└──────────────────┬─────────────────────────────────┬───────────────────────┘
                   │                                 │
                   ▼                                 ▼
┌──────────────────────────────────┐  ┌──────────────────────────────────────┐
│     GO NATIVE LIBRARY            │  │      SQLCIPHER DATABASE              │
│     [gomobile Container]         │  │    [sqflite_sqlcipher Container]     │
│                                  │  │                                      │
│  ┌────────────────────────────┐  │  │  ┌────────────────────────────────┐  │
│  │      Bridge Entry          │  │  │  │        identity table          │  │
│  │      [Command Dispatch]    │  │  │  │                                │  │
│  │                            │  │  │  │  id INTEGER PRIMARY KEY        │  │
│  │  HandleCommand(cmd, json)  │  │  │  │  peer_id TEXT NOT NULL         │  │
│  │  → JSON response           │  │  │  │  public_key TEXT NOT NULL      │  │
│  └──────────┬─────────────────┘  │  │  │  private_key TEXT              │  │
│             │                    │  │  │   CHECK(private_key IS NULL)  │  │
│  ┌──────────┴─────────────────┐  │  │  │  mnemonic12 TEXT              │  │
│  │    Commands                │  │  │  │   CHECK(mnemonic12 IS NULL)   │  │
│  │                            │  │  │  │  username TEXT NOT NULL        │  │
│  │  identity.generate         │  │  │  │  avatar_path TEXT              │  │
│  │  identity.restore          │  │  │  │  avatar_blob BLOB (v5)       │  │
│  │  payload.sign              │  │  │  │  created_at TEXT NOT NULL      │  │
│  │  payload.verify            │  │  │  │  updated_at TEXT NOT NULL      │  │
│  │  mlkem.keygen              │  │  │  │  ml_kem_public_key TEXT (v3)  │  │
│  │  message.encrypt           │  │  │  │  ml_kem_secret_key TEXT       │  │
│  │  message.decrypt           │  │  │  │   CHECK(..IS NULL) (v5)      │  │
│                                  │  │  │  Constraint: id = 1 always     │  │
│  ┌────────────────────────────┐  │  │  │  Secrets → Secure Storage      │  │
│  │    Identity Module         │  │  │  └────────────────────────────────┘  │
│  │    (identity/)             │  │  │                                      │
│  │                            │  │  │                                      │
│  │  GenerateIdentity()        │  │  │  ┌────────────────────────────────┐  │
│  │  RestoreFromMnemonic()     │  │  │  │        contacts table          │  │
│  └────────────────────────────┘  │  │  │                                │  │
│                                  │  │  │  peer_id TEXT PRIMARY KEY      │  │
│  ┌────────────────────────────┐  │  │  │  public_key TEXT NOT NULL      │  │
│  │    Signing Module          │  │  │  │  rendezvous TEXT NOT NULL      │  │
│  │                            │  │  │  │  username TEXT NOT NULL        │  │
│  │  SignPayload()             │  │  │  │  signature TEXT NOT NULL       │  │
│  │  VerifyPayload()           │  │  │  │  scanned_at TEXT NOT NULL      │  │
│  │                            │  │  │  │  avatar_path TEXT              │  │
│  │  Uses: crypto/ed25519      │  │  │  │  ml_kem_public_key TEXT (v3)  │  │
│  └────────────────────────────┘  │  │  │  is_archived INT NOT NULL (v7) │  │
│                                  │  │  │  archived_at TEXT (v7)         │  │
│                                  │  │  │  is_blocked INT NOT NULL (v8)  │  │
│                                  │  │  │  blocked_at TEXT (v8)          │  │
│                                  │  │  └────────────────────────────────┘  │
│                                  │  │                                      │
│  ┌────────────────────────────┐  │  │  ┌────────────────────────────────┐  │
│  │    Crypto Module           │  │  │  │    contact_requests table      │  │
│  │    (crypto/)               │  │  │  │                                │  │
│  │                            │  │  │  │  peer_id TEXT PRIMARY KEY      │  │
│  │  ML-KEM-768 keygen         │  │  │  │  public_key TEXT NOT NULL      │  │
│  │  EncryptMessage()          │  │  │  │  rendezvous TEXT NOT NULL      │  │
│  │  DecryptMessage()          │  │  │  │  username TEXT NOT NULL        │  │
│  │                            │  │  │  │  signature TEXT NOT NULL       │  │
│  │  Uses:                     │  │  │  │  received_at TEXT NOT NULL     │  │
│  │  • circl/kem/mlkem768      │  │  │  │  status TEXT NOT NULL          │  │
│  │  • crypto/aes (AES-GCM)   │  │  │  │  DEFAULT 'pending'            │  │
│  └────────────────────────────┘  │  │  │  ml_kem_public_key TEXT (v3)  │  │
│                                  │  │  └────────────────────────────────┘  │
│  ┌────────────────────────────┐  │  │                                      │
│  │    Node Module             │  │  │  ┌────────────────────────────────┐  │
│  │    (node/)                 │  │  │  │        messages table          │  │
│  │                            │  │  │  │        (v2 migration)          │  │
│  │  Node start/stop/status    │  │  │  │                                │  │
│  │  Rendezvous register       │  │  │  │  id TEXT PRIMARY KEY           │  │
│  │  Rendezvous discover       │  │  │  │                                │  │
│  │  Peer dial/disconnect      │  │  │  │  contact_peer_id TEXT NOT NULL │  │
│  │  Message send/receive      │  │  │  │  sender_peer_id TEXT NOT NULL  │  │
│  │  Offline inbox protocol    │  │  │  │  text TEXT NOT NULL            │  │
│  │                            │  │  │  │  timestamp TEXT NOT NULL       │  │
│  │  Uses:                     │  │  │  │  status TEXT DEFAULT 'sent'    │  │
│  │  • libp2p (Go)             │  │  │  │  is_incoming INTEGER NOT NULL  │  │
│  │  • Circuit relay v2        │  │  │  │  created_at TEXT NOT NULL      │  │
│  │  • Hole punching           │  │  │  │  read_at TEXT (v6)            │  │
│  │  • NAT port mapping        │  │  │  │  INDEX idx_messages_contact    │  │
│  └────────────────────────────┘  │  │  │  INDEX idx_messages_ts         │  │
│                                  │  │  └────────────────────────────────┘  │
│  ┌────────────────────────────┐  │  │                                      │
│  │    Platform Wrappers       │  │  └──────────────────────────────────────┘
│  │                            │  │
│  │  GoBridge.swift (iOS)      │  │
│  │  GoBridge.kt   (Android)  │  │
│  │  MethodChannel + EventChan │  │
│  └────────────────────────────┘  │
└──────────────────────────────────┘
```

### Flutter Application Components

| Component | Type | Responsibility |
|-----------|------|----------------|
| **Identity Feature** | | |
| StartupRouter | Widget | Decides routing based on identity existence |
| IdentityChoiceScreen | Widget | Onboarding UI with two options |
| MnemonicInputScreen | Widget | UI for entering recovery phrase |
| **Home Feature** | | |
| FirstTimeExperienceScreen | Widget | Main home screen with profile, QR, scan, and empty state |
| FirstTimeExperienceWired | Widget | Business logic: QR build, username edit, avatar (BLOB in DB), scan, contact request listening, P2P node start |
| ProfileAvatarWidget | Widget | Avatar display with camera button and image picker; uses Image.memory() from BLOB (no file on disk) |
| EditableUsernameWidget | Widget | Tap-to-edit username display |
| QRCodeSection | Widget | QR code display with green glow effect |
| ScanFriendCard | Widget | Glassmorphic card for QR scanning action |
| EmptyCircleState | Widget | Animated dashed circles for empty connections |
| RingAvatar | Widget | Deterministic ring avatar from peerId |
| RingAvatarPainter | CustomPainter | Canvas renderer for ring + glow avatar |
| ConnectionStatusIndicator | Widget | Online/Offline P2P status with connection count |
| **QR Code Feature** | | |
| QRDisplayScreen | Widget | Full-screen QR code display |
| QRScannerScreen | Widget | Camera-based QR code scanner (mobile_scanner) |
| QRScannerWired | Widget | Scanner business logic: parse, validate, add contact, send request |
| ScanOverlay | Widget | Canvas overlay with corner markers for scan area |
| **Contact Request Feature** | | |
| ContactRequestDialog | Widget | Accept/Decline modal with RingAvatar |
| PendingRequestsBadge | Widget | Circular count badge (shows 99+ max) |
| **Feed Feature** | | |
| FeedScreen | Widget | Main feed UI displaying connection and message cards |
| FeedWired | Widget | Feed orchestration: loads identity, builds initial feed, listens for contact requests and messages; orbit tab pushes OrbitWired via Navigator.push; P2P node start |
| FeedHeader | Widget | Sticky header with username and ring avatar |
| FeedNavigationBar | Widget | Bottom glassmorphic nav bar with 3 SVG tabs (feed, orbit, remember); orbit tab triggers Navigator.push instead of tab swap; shows total unread badge on feed tab |
| NavBarButton | Widget | Individual nav bar tab button (active/inactive states) with optional badge overlay |
| UnreadCountBadge | Widget | Circular count badge for unread messages (shows 99+ max) |
| ConnectionCard | Widget | Card displaying a contact connection with ring avatar and inline green checkmark badge |
| MessageFeedCard | Widget | Incoming message card with contact avatar, message preview, and reply button |
| ThreadCard | Widget | Thread card displaying grouped messages from a contact |
| MessageBubble | Widget | Single message bubble within a thread card |
| SessionDivider | Widget | Session divider between message groups in feed |
| TimeGapDivider | Widget | Time gap divider for significant time pauses between messages |
| CheckmarkBurstAnimation | Widget | Animated checkmark with expanding ring burst effect (unused/orphaned) |
| FeedRouteTransition | Route | Slide-up page transition for feed navigation |
| **Conversation Feature** | | |
| ConversationScreen | Widget | Pure UI: letter cards, empty state with breathing glow, compose area |
| ConversationWired | Widget | Business logic: load messages, optimistic send, listen for incoming, scroll management; marks conversation read on load + incoming messages |
| LetterCard | Widget | Full-width message card with left accent (received) / right accent (sent) and delivery status (sending/sent/delivered/queued/failed) |
| ComposeArea | Widget | Auto-growing text field with glassmorphic styling and animated send button |
| EmptyConversationState | Widget | Breathing glow avatar, "Connected!" label, connection date, writing prompt |
| ConversationHeader | Widget | Frosted-glass sticky header with back button, contact avatar + name, connection status |
| CompactOriginMarker | Widget | Compact connection origin marker at top of conversation (48px avatar) |
| DateSeparator | Widget | Date divider between letter cards spanning different days with gradient lines |
| BlockedBanner | Widget | Banner displayed when conversation contact is blocked, with "Unblock" button |
| ConversationRouteTransition | Route | Slide-up page transition (420ms easeOutCubic) |
| **Orbit Feature** | | |
| OrbitScreen | Widget | Pure UI: AmbientBackground, Scaffold, 4-layer Stack (scrollable content, close button, floating search trigger, search dock) |
| OrbitWired | Widget | Orbit business logic: 3 AnimationControllers (collapse 580ms, searchDock 560ms, searchTrigger 340ms), subscribes to chatMessageListener + contactRequestListener streams |
| OrbitalVisualization | Widget | 320x320 Stack with dashed ring painter, center RingAvatar, Ring 1 (top 5 friends, 62px, 38px avatars), Ring 2 (next 8, 108px, 30px avatars), overflow badge |
| OrbitalRingPainter | CustomPainter | Draws 2 dashed concentric circles (teal + purple) |
| OrbitalAvatar | Widget | Positioned avatar with staggered scale-in animation (globalIndex * 40ms) |
| OverflowBadge | Widget | "+N" badge with delayed entrance (1000ms) |
| OrbitCloseButton | Widget | 36x36 glass circle X button |
| OrbitHeader | Widget | Right-aligned 44px user RingAvatar |
| FriendsListHeader | Widget | "Friends" title + My QR / Scan pill buttons (hidden during search) |
| FriendRow | Widget | Glassmorphic card with contact avatar, name, message count, last activity, and unread badge |
| SwipeableFriendRow | Widget | FriendRow wrapper with slide-to-reveal swipe actions (Block/Delete/Archive or Unblock/Delete/Unarchive) |
| SwipeActionButtons | Widget | Block/Delete/Archive action buttons revealed on swipe |
| FriendsFilterToggle | Widget | Segmented toggle "All (N)" / "Archived (N)" for filtering friends list |
| ArchivedEmptyState | Widget | Empty state display for the archived contacts list |
| ConfirmationDialog | Widget | Confirmation dialog for destructive actions (block, delete) |
| QRActionCards | Widget | My QR / Scan QR action card buttons |
| OrbitSearchTrigger | Widget | Floating glass pill with search button + close button |
| OrbitSearchDock | Widget | Bottom-docked search TextField with native keyboard |
| **Push Notifications Feature** | | |
| requestPushPermission() | Use Case | Requests notification permission from user |
| registerPushToken() | Use Case | Registers FCM token with relay server via P2P inbox protocol |
| firebaseMessagingBackgroundHandler | Service | Firebase background message handler (@pragma entry-point) |
| **Shared Widgets** | | |
| AmbientBackground | Widget | Animated green/red glow background |
| GlassmorphicContainer | Widget | Frosted glass effect container |
| ChoiceCard | Widget | Tappable card with scale animation |
| IdentityLoadingCard | Widget | Loading card displayed during identity generation/restore |
| **Identity Use Cases** | | |
| decideStartupRoute() | Use Case | Checks identity + contact count → 3-way routing decision |
| generateNewIdentity() | Use Case | Orchestrates identity generation via Go bridge |
| restoreIdentityFromMnemonic() | Use Case | Orchestrates identity restoration via Go bridge |
| **QR Use Cases** | | |
| buildQRPayload() | Use Case | Creates signed QR payload |
| parseQRPayload() | Use Case | Validates scanned QR: JSON parse, field check, expiry, signature verify, self-scan |
| **P2P Use Cases** | | |
| startP2PNode() | Use Case | Loads identity, converts key, starts node |
| stopP2PNode() | Use Case | Stops running P2P node |
| sendP2PMessage() | Use Case | Sends message to peer via P2P |
| discoverP2PPeer() | Use Case | Discovers peer via rendezvous |
| dialP2PPeer() | Use Case | Establishes connection to peer |
| **Contact Use Cases** | | |
| addContact() | Use Case | Adds contact with duplicate check |
| archiveContact() | Use Case | Archives a contact |
| unarchiveContact() | Use Case | Unarchives a contact |
| blockContact() | Use Case | Blocks a contact |
| unblockContact() | Use Case | Unblocks a contact |
| deleteContactAndMessages() | Use Case | Deletes contact and all associated messages |
| **Contact Request Use Cases** | | |
| sendContactRequest() | Use Case | Builds signed payload, discovers peer, dials, sends request (3x retry) |
| acceptContactRequest() | Use Case | Converts request to contact, updates status |
| declineContactRequest() | Use Case | Updates request status to declined |
| handleIncomingMessage() | Use Case | Parses P2P message, validates signature, stores request |
| ContactRequestListener | Service | Monitors contactRequestStream, broadcasts new requests to UI |
| **Conversation Use Cases** | | |
| sendChatMessage() | Use Case | Builds MessagePayload, encrypts with ML-KEM-768 + AES-256-GCM if recipient has ML-KEM key (v2 envelope) or falls back to v1 plaintext, discovers peer, dials, sends with 3x retry, offline inbox fallback, persists optimistically |
| handleIncomingChatMessage() | Use Case | Detects v2 encrypted envelope (decrypts via ML-KEM decapsulate + AES-256-GCM) or v1 plaintext, validates sender is contact, detects name changes, persists |
| loadConversation() | Use Case | Loads all messages for a contact, ordered by timestamp ASC |
| ChatMessageListener | Service | Monitors chatMessageStream, resolves own ML-KEM secret key for decryption, rejects messages from blocked contacts, suppresses UI notification for archived contacts, broadcasts persisted ConversationMessages and contact updates to UI |
| markConversationRead() | Use Case | Marks all unread messages for a contact as read (sets read_at timestamp) |
| retryFailedMessages() | Use Case | Retries sending all failed outgoing messages; returns count of successfully retried |
| PendingMessageRetrier | Service | Subscribes to P2PService.stateStream, detects online transitions (5s debounce), auto-retries failed messages |
| **Feed Use Cases** | | |
| loadFeed() | Use Case | Loads initial feed from DB: contacts + latest messages per contact + unread counts |
| **Orbit Use Cases** | | |
| loadOrbitData() | Use Case | Loads all contacts with message counts + unread counts from MessageRepository, sorted by messageCount descending; returns List<OrbitFriend> |
| **Core Services** | | |
| IncomingMessageRouter | Service | Routes P2P messages by envelope type to contactRequestStream, chatMessageStream, unknownStream; stream subscription has onError/onDone handlers |
| **Stream Error Handling** | Convention | All `.listen()` calls across IncomingMessageRouter (1), ContactRequestListener (1), ChatMessageListener (1), FeedWired (3), ConversationWired (2), FirstTimeExperienceWired (1), OrbitWired (3) include `onError` and `onDone` callbacks for resilience |
| **Domain** | | |
| IdentityModel | Entity | Immutable data class for identity (peerId, keys, mnemonic, username, avatarBlob, mlKemPublicKey?, mlKemSecretKey?); secrets (privateKey, mnemonic12, mlKemSecretKey) stored in SecureKeyStore, DB columns always NULL |
| ContactModel | Entity | Contact from QR scan (peerId, publicKey, rendezvous, username, signature, scannedAt, mlKemPublicKey?, isArchived, archivedAt?, isBlocked, blockedAt?) |
| ContactRequestModel | Entity | Incoming request (peerId, publicKey, rendezvous, username, signature, status, mlKemPublicKey?) |
| NodeState | P2P Model | P2P node state (peerId, isStarted, listenAddresses, connections) |
| DiscoveredPeer | P2P Model | Discovered peer (id, addresses) |
| ConnectionState | P2P Model | Active connection (peerId, multiaddrs, direction, status) |
| ChatMessage | P2P Model | P2P message (from, to, content, timestamp, isIncoming) |
| SendMessageResult | P2P Model | P2P send result class (sent: bool, reply: String?, acknowledged: bool getter) |
| FeedItem | Abstract Entity | Base class for feed items (id, timestamp, type) |
| ConnectionFeedItem | Entity | Feed item for new connections (extends FeedItem) |
| ThreadFeedItem | Entity | Feed item representing a thread of messages grouped by contact and read session (extends FeedItem); contains List\<ThreadMessage\>, unreadCount, isUnreadCard |
| ThreadMessage | Data Class | Single message within a thread group (id, text, time, timestamp, isUnread) |
| MessageFeedItem | Entity | Feed item for incoming messages (extends FeedItem, contactPeerId, messageText, messageTime, unreadCount) |
| FeedItemType | Enum | Feed item types: connection, message, thread |
| ConversationMessage | Entity | Message in a conversation (id, contactPeerId, senderPeerId, text, status, isIncoming, readAt?) |
| MessagePayload | Wire Model | Chat message envelope: v1 plaintext `{ "type": "chat_message", "version": "1", "payload": {...} }` or v2 encrypted `{ "type": "chat_message", "version": "2", "senderPeerId": "...", "encrypted": { "kem", "ciphertext", "nonce" } }` |
| OrbitFriend | Composite Model | ContactModel + messageCount (int) + lastActivity (String) + lastMessageTimestamp (DateTime?) + unreadCount (int, default 0); used by Orbit feature for ranking friends by conversation activity |
| IdentityRepository | Interface + Impl | Abstracts identity persistence; IdentityRepositoryImpl takes SecureKeyStore, reads secrets from secure storage (falls back to DB for pre-migration), writes secrets only to secure storage |
| ContactRepository | Interface + Impl | Abstracts contact persistence (add, get, getAll, delete, exists, count, archiveContact, unarchiveContact, getActiveContacts, getArchivedContacts, blockContact, unblockContact) |
| ContactRequestRepository | Interface + Impl | Abstracts request persistence (add, get, getPending, updateStatus, delete, exists) |
| MessageRepository | Interface + Impl | Abstracts message persistence (save, getForContact, getLatest, updateStatus, exists, getMessageCountForContact, markConversationAsRead, getUnreadCountForContact, getTotalUnreadCount, getTotalUnreadCountExcludingArchived, deleteMessagesForContact, getFailedOutgoingMessages, getMessagesPage) |
| **Core** | | |
| GoBridgeClient | Bridge Client | Sends requests to Go native library via MethodChannel, receives push events via EventChannel; checkHealth() probes bridge liveness (node:status, 5s timeout); reinitialize() re-initializes Go bridge preserving callbacks; send() catches PlatformException and returns `{errorCode: 'PLATFORM_ERROR'}`; platform wrappers: GoBridge.swift (iOS) + GoBridge.kt (Android) |
| P2PBridgeClient | Bridge Client | P2P-specific bridge calls (start, stop, status, register, discover, dial, disconnect, send, inbox store/retrieve, inbox register token) |
| Bridge Helper Functions (in bridge.dart) | Bridge Helpers | Identity + signing + verification + ML-KEM encryption/decryption helper functions: callIdentityGenerate, callIdentityRestore, callSignPayload, callVerifyPayload, callMlKemKeygen, callEncryptMessage, callDecryptMessage |
| P2P Bridge Helper Functions (in p2p_bridge_client.dart) | Bridge Helpers | P2P-specific helper functions: callP2PNodeStart/Stop/Status, callP2PRendezvousRegister/Discover, callP2PPeerDial/Disconnect, callP2PMessageSend, callP2PInboxStore/Retrieve/RegisterToken; also exports defaultRendezvousAddress constant |
| P2PService / P2PServiceImpl | Service | Reactive P2P service with state and message streams, sendMessageWithReply() for ACK-based chat, offline inbox fallback + registerPushToken for FCM push notifications; public performImmediateHealthCheck() and drainOfflineInbox() wrappers for app-resume lifecycle; startNodeCore() / warmBackground() split for deferred startup; isLocalPeer() / sendLocalMessage() for WiFi-first delivery; local WiFi discovery via Bonsoir mDNS |
| IncomingMessageRouter | Service | Routes P2P messages by JSON envelope type to typed broadcast streams |
| LocalDiscoveryService | Interface | Abstract mDNS service discovery for local WiFi peers |
| BonsoirDiscoveryService | Impl | Bonsoir-based mDNS service discovery implementation |
| LocalP2PService | Service | Combines mDNS discovery + WebSocket for local WiFi peer communication |
| LocalWsServer | Service | Local WebSocket server for direct WiFi peer message exchange |
| RingAvatarGenerator | Utility | Deterministic avatar from peerId via DJB2 hash |
| KeyConversion | Utility | base64ToHex, hexToBase64, bytesToHex, hexToBytes |
| FlowEventEmitter | Utility | Structured logging across all layers |
| NetworkConstants | Constants | Rendezvous address constant |
| ChatConsoleLogger | Utility | Debug logging for chat messages with shortened peer IDs |
| formatRelativeTime() | Utility | Formats timestamps as relative "2m ago" strings for Orbit feature |
| StartupTiming | Utility | Singleton for debug timing marks during startup (mark, getAll) |
| StartupConfig | Config | Configuration class with deferredStartupMode flag |
| SecureKeyStore | Interface | Abstract secure key-value storage (read, write, delete, containsKey) |
| FlutterSecureKeyStore | Impl | iOS Keychain (kSecAttrAccessibleWhenUnlockedThisDeviceOnly, device-bound) / Android EncryptedSharedPreferences; stores identity_private_key, identity_mnemonic12, identity_ml_kem_secret_key, db_encryption_key |
| encrypted_db_opener | DB Setup | Opens SQLCipher-encrypted database with key from SecureKeyStore; handles plaintext-to-encrypted migration |
| migrate_secrets_to_secure_storage | Migration | One-time migration of secrets from DB columns to SecureKeyStore with secrets_migrated sentinel |
| Database Helpers | DB Access | Low-level SQL operations for all 4 tables (via sqflite_sqlcipher) |
| AppColors / AppTheme | Theme | Color constants and ThemeData for dark theme |
| GlassmorphicContainer | Theme | Frosted glass effect widget |

### Go Native Library Components

| Component | Responsibility |
|-----------|----------------|
| Bridge Entry (bridge/bridge.go) | Routes incoming requests to handlers via command dispatch; JSON request/response encoding |
| Identity Module (identity/) | `identity.generate` → BIP39 mnemonic + Ed25519 keypair + ML-KEM-768 keypair; `identity.restore` → derive from mnemonic + fresh ML-KEM-768 |
| Signing Module (bridge/bridge.go) | `payload.sign` → Ed25519 signing; `payload.verify` → Ed25519 signature verification |
| Crypto Module (crypto/) | `mlkem.keygen` → ML-KEM-768 keypair; `message.encrypt` → KEM encapsulate + AES-256-GCM; `message.decrypt` → KEM decapsulate + AES-256-GCM |
| Node Module (node/) | libp2p node lifecycle (start/stop/status), circuit relay v2, NAT port mapping, hole punching |
| Rendezvous Module (node/rendezvous.go) | Peer registration and discovery with signed peer records via protobuf protocol |
| Chat Protocol (node/node.go) | `/mknoon/chat/1.0.0` — bidirectional message exchange with ACK replies, 4-byte big-endian length-prefixed frames |
| Inbox Module (node/inbox.go) | `/mknoon/inbox/1.0.0` — offline message store/retrieve/register FCM token via relay server |
| Event System (node/node.go) | Push events to Flutter: `message:received`, `peer:connected`, `peer:disconnected` via callback interface |
| Platform Wrappers | GoBridge.swift (iOS) + GoBridge.kt (Android) — bridge MethodChannel/EventChannel to Go library |

---

## Level 4: Code Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              CODE DIAGRAM                                    │
└─────────────────────────────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────────────────┐
│                              FLUTTER CLASSES                                 │
├─────────────────────────────────────────────────────────────────────────────┤

  ── Bridge Layer ─────────────────────────────────────────────────────────

  ┌─────────────────────────────────────┐
  │         <<abstract>>                │
  │         Bridge                      │
  ├─────────────────────────────────────┤
  │ + send(message: String): String     │
  │ + initialize(): Future<void>        │
  │ + checkHealth(): Future<bool>       │
  │ + reinitialize(): Future<void>      │
  │ + dispose(): Future<void>           │
  │ + onMessageReceived: callback?      │
  │ + onPeerConnected: callback?        │
  │ + onPeerDisconnected: callback?     │
  └──────────────────┬──────────────────┘
                     │
                     │ implements
                     ▼
  ┌─────────────────────────────────────┐
  │         GoBridgeClient              │
  ├─────────────────────────────────────┤
  │ - _methodChannel: MethodChannel     │
  │ - _eventChannel: EventChannel       │
  │ - _initialized: bool                │
  │ - _cmdMap: Map<String, _CmdSpec>     │
  │   (cmd→MethodChannel method map)    │
  ├─────────────────────────────────────┤
  │ + initialize(): Future<void>        │
  │ + send(message: String): String     │
  │   (maps cmd strings to MethodChan   │
  │    method names, JSON encode/decode │
  │    via MethodChannel)               │
  │ + checkHealth(): Future<bool>       │
  │   (sends node:status, 5s timeout)   │
  │ + reinitialize(): Future<void>      │
  │   (re-initializes Go bridge,        │
  │    preserves callback references)   │
  │ + dispose(): Future<void>           │
  │ + onMessageReceived(callback)       │
  │ + onPeerConnected(callback)         │
  │ + onPeerDisconnected(callback)      │
  │ - _handleEvent(Map): void           │
  │   (routes EventChannel push events) │
  └─────────────────────────────────────┘


  ── Identity Domain ──────────────────────────────────────────────────────

  ┌─────────────────────────────────────┐
  │         IdentityModel               │
  ├─────────────────────────────────────┤
  │ + peerId: String                    │
  │ + publicKey: String                 │
  │ + privateKey: String?               │
  │ + mnemonic12: String?               │
  │ + username: String                  │
  │ + avatarBlob: Uint8List?            │
  │ + createdAt: String                 │
  │ + updatedAt: String                 │
  │ + mlKemPublicKey: String?           │
  │ + mlKemSecretKey: String?           │
  ├─────────────────────────────────────┤
  │ + fromJson(Map): IdentityModel      │
  │ + toJson(): Map                     │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │         <<abstract>>                │
  │         IdentityRepository          │
  ├─────────────────────────────────────┤
  │ + loadIdentity(): IdentityModel?    │
  │ + saveIdentity(IdentityModel): void │
  └──────────────────┬──────────────────┘
                     │ implements
                     ▼
  ┌─────────────────────────────────────┐
  │       IdentityRepositoryImpl        │
  ├─────────────────────────────────────┤
  │ - dbLoadIdentityRow: Function       │
  │ - dbUpsertIdentityRow: Function     │
  │ - secureKeyStore: SecureKeyStore    │
  ├─────────────────────────────────────┤
  │ + loadIdentity(): IdentityModel?    │
  │   (reads secrets from SecureKeyStore│
  │    falls back to DB for pre-migr.)  │
  │ + saveIdentity(IdentityModel): void │
  │   (writes secrets ONLY to secure    │
  │    storage, DB columns set to null) │
  └─────────────────────────────────────┘


  ── Contact Domain ───────────────────────────────────────────────────────

  ┌─────────────────────────────────────┐
  │         ContactModel                │
  ├─────────────────────────────────────┤
  │ + peerId: String                    │
  │ + publicKey: String                 │
  │ + rendezvous: String                │
  │ + username: String                  │
  │ + signature: String                 │
  │ + scannedAt: String                 │
  │ + avatarPath: String?               │
  │ + mlKemPublicKey: String?           │
  │ + isArchived: bool (default false)  │
  │ + archivedAt: String?               │
  │ + isBlocked: bool (default false)   │
  │ + blockedAt: String?                │
  ├─────────────────────────────────────┤
  │ + fromQRPayload(Map): ContactModel  │
  │ + fromMap(Map): ContactModel        │
  │ + toMap(): Map                      │
  │ + copyWith({clearArchivedAt,        │
  │     clearBlockedAt}): ContactModel  │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │         <<abstract>>                │
  │         ContactRepository           │
  ├─────────────────────────────────────┤
  │ + addContact(ContactModel): void    │
  │ + getContact(peerId): ContactModel? │
  │ + getAllContacts(): List<Contact>    │
  │ + deleteContact(peerId): void       │
  │ + contactExists(peerId): bool       │
  │ + getContactCount(): int            │
  │ + archiveContact(peerId): void      │
  │ + unarchiveContact(peerId): void    │
  │ + getActiveContacts(): List<Contact>│
  │ + getArchivedContacts(): List       │
  │ + blockContact(peerId): void        │
  │ + unblockContact(peerId): void      │
  └──────────────────┬──────────────────┘
                     │ implements
                     ▼
  ┌─────────────────────────────────────┐
  │       ContactRepositoryImpl         │
  ├─────────────────────────────────────┤
  │ - dbLoadAllContacts: Function       │
  │ - dbLoadContact: Function           │
  │ - dbUpsertContact: Function         │
  │ - dbDeleteContact: Function         │
  │ - dbGetContactCount: Function       │
  │ - dbContactExists: Function         │
  │ - dbArchiveContact: Function        │
  │ - dbUnarchiveContact: Function      │
  │ - dbLoadActiveContacts: Function    │
  │ - dbLoadArchivedContacts: Function  │
  │ - dbBlockContact: Function          │
  │ - dbUnblockContact: Function        │
  └─────────────────────────────────────┘


  ── Contact Request Domain ───────────────────────────────────────────────

  ┌─────────────────────────────────────┐
  │       ContactRequestModel           │
  ├─────────────────────────────────────┤
  │ + peerId: String                    │
  │ + publicKey: String                 │
  │ + rendezvous: String                │
  │ + username: String                  │
  │ + signature: String                 │
  │ + receivedAt: String                │
  │ + status: ContactRequestStatus      │
  │ + mlKemPublicKey: String?           │
  ├─────────────────────────────────────┤
  │ + fromP2PPayload(Map): Model        │
  │ + fromMap(Map): Model               │
  │ + toMap(): Map                      │
  │ + toContactModel(): ContactModel    │
  │ + copyWith(): Model                 │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │         <<abstract>>                │
  │       ContactRequestRepository      │
  ├─────────────────────────────────────┤
  │ + addRequest(Model): void           │
  │ + getRequest(peerId): Model?        │
  │ + getPendingRequests(): List<Model>  │
  │ + updateStatus(peerId, status): void│
  │ + deleteRequest(peerId): void       │
  │ + requestExists(peerId): bool       │
  └──────────────────┬──────────────────┘
                     │ implements
                     ▼
  ┌─────────────────────────────────────┐
  │   ContactRequestRepositoryImpl      │
  ├─────────────────────────────────────┤
  │ - dbLoadPendingRequests: Function   │
  │ - dbLoadRequest: Function           │
  │ - dbUpsertRequest: Function         │
  │ - dbUpdateRequestStatus: Function   │
  │ - dbDeleteRequest: Function         │
  │ - dbRequestExists: Function         │
  └─────────────────────────────────────┘


  ── P2P Domain ───────────────────────────────────────────────────────────

  ┌─────────────────────────────────────┐
  │         NodeState                   │
  ├─────────────────────────────────────┤
  │ + peerId: String?                   │
  │ + isStarted: bool                   │
  │ + listenAddresses: List<String>     │
  │ + circuitAddresses: List<String>    │
  │ + connections: List<ConnectionState>│
  │ + registeredNamespaces: List<String>│
  ├─────────────────────────────────────┤
  │ + fromJson(Map): NodeState          │
  │ + toJson(): Map                     │
  │ + copyWith(): NodeState             │
  │ + static stopped: NodeState         │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │         ConnectionState             │
  ├─────────────────────────────────────┤
  │ + peerId: String                    │
  │ + multiaddrs: List<String>          │
  │ + direction: String                 │
  │ + status: String                    │
  │ + connectedAt: String?              │
  ├─────────────────────────────────────┤
  │ + fromJson(Map): ConnectionState    │
  │ + toJson(): Map                     │
  │ + copyWith(): ConnectionState       │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │         DiscoveredPeer              │
  ├─────────────────────────────────────┤
  │ + id: String                        │
  │ + addresses: List<String>           │
  ├─────────────────────────────────────┤
  │ + fromJson(Map): DiscoveredPeer     │
  │ + toJson(): Map                     │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │         ChatMessage                 │
  ├─────────────────────────────────────┤
  │ + from: String                      │
  │ + to: String                        │
  │ + content: String                   │
  │ + timestamp: String                 │
  │ + isIncoming: bool                  │
  ├─────────────────────────────────────┤
  │ + fromJson(Map): ChatMessage        │
  │ + toJson(): Map                     │
  │ + copyWith(): ChatMessage           │
  └─────────────────────────────────────┘


  ── P2P Service ──────────────────────────────────────────────────────────

  ┌─────────────────────────────────────┐
  │         <<abstract>>                │
  │         P2PService                  │
  ├─────────────────────────────────────┤
  │ + currentState: NodeState           │
  │ + stateStream: Stream<NodeState>    │
  │ + messageStream: Stream<ChatMessage>│
  ├─────────────────────────────────────┤
  │ + startNode(privKey, peerId): bool  │
  │ + stopNode(): bool                  │
  │ + sendMessage(peerId, msg): bool    │
  │ + discoverPeer(peerId): Discovered? │
  │ + dialPeer(peerId, {addrs}): bool   │
  │ + storeInInbox(peerId, msg): bool  │
  │ + retrieveInbox(): List<Map>       │
  │ + registerPushToken(token, platform): bool │
  │ + sendMessageWithReply(peerId, msg): Map │
  │ + performImmediateHealthCheck(): void │
  │ + drainOfflineInbox(): void          │
  │ + startNodeCore(privKey, peerId)     │
  │ + warmBackground(): void             │
  │ + isLocalPeer(peerId): bool          │
  │ + sendLocalMessage(peerId, msg): bool│
  │ + dispose(): void                   │
  └──────────────────┬──────────────────┘
                     │ implements
                     ▼
  ┌─────────────────────────────────────┐
  │       P2PServiceImpl                │
  ├─────────────────────────────────────┤
  │ - _bridge: Bridge                   │
  │ - _localP2P: LocalP2PService?       │
  │ - _stateController: StreamController│
  │ - _messageController: StreamCtrl    │
  │ - _currentState: NodeState          │
  │ - _isStarting: bool                 │
  ├─────────────────────────────────────┤
  │ + startNode(privKey, peerId): bool  │
  │ + startNodeCore(privKey, peerId)    │
  │ + warmBackground(): void            │
  │ + stopNode(): bool                  │
  │ + sendMessage(peerId, msg): bool    │
  │ + sendMessageWithReply(peerId, msg) │
  │   (bidirectional chat with ACK)     │
  │ + discoverPeer(peerId): Discovered? │
  │ + dialPeer(peerId, {addrs}): bool   │
  │ + storeInInbox(peerId, msg): bool  │
  │ + retrieveInbox(): List<Map>       │
  │ + registerPushToken(token, plat.)   │
  │   (caches token/platform for        │
  │    recovery after relay reconnect)  │
  │ + performImmediateHealthCheck(): void │
  │   (public wrapper → _performHealthCheck) │
  │ + drainOfflineInbox(): void          │
  │   (public wrapper → _drainOfflineInbox)  │
  │ + isLocalPeer(peerId): bool         │
  │ + sendLocalMessage(peerId, msg)     │
  │ + dispose(): void                   │
  │ - _onMessageReceived(Map)           │
  │ - _onPeerConnected(Map)             │
  │ - _onPeerDisconnected(Map)          │
  │ - _performHealthCheck(): void      │
  │   (periodic 30s, detects degraded   │
  │    relay, auto-dials, re-registers) │
  │ - _drainOfflineInbox(): void       │
  └─────────────────────────────────────┘


  ── Contact Request Listener ─────────────────────────────────────────────

  ┌─────────────────────────────────────┐
  │     ContactRequestListener          │
  ├─────────────────────────────────────┤
  │ - p2pService: P2PService            │
  │ - requestRepo: ContactRequestRepo   │
  │ - contactRepo: ContactRepository    │
  │ - bridge: Bridge                    │
  │ - getOwnPeerId: () => String       │
  │ - _subscription: StreamSubscription │
  │ - _requestController: StreamCtrl    │
  ├─────────────────────────────────────┤
  │ + requestStream: Stream<Model>      │
  │ + start(): void                     │
  │ + stop(): void                      │
  │ + dispose(): void                   │
  │ - _onMessage(ChatMessage): void     │
  └─────────────────────────────────────┘


  ── First Time Experience ────────────────────────────────────────────────

  ┌─────────────────────────────────────┐
  │    FirstTimeExperienceWired         │
  ├─────────────────────────────────────┤
  │ + repository: IdentityRepository    │
  │ + contactRepository: ContactRepo    │
  │ + contactRequestRepository: CRRepo  │
  │ + contactRequestListener: Listener  │
  │ + bridge: Bridge                    │
  │ + p2pService: P2PService            │
  ├─────────────────────────────────────┤
  │ - _qrData: String?                  │
  │ - _username: String                 │
  │ - _avatarBlob: Uint8List?           │
  │ - _identity: IdentityModel?         │
  │ - _requestSubscription: StreamSub   │
  ├─────────────────────────────────────┤
  │ + _loadIdentityAndBuildQR()         │
  │ + _buildQRPayload()                 │
  │ + _onUsernameChanged(String)        │
  │ + _onCameraPressed()                │
  │ + _onScanPressed()                  │
  │ + _startListeningForContactRequests │
  │ + _onContactRequest(Model)          │
  │ + _acceptRequest(ctx, Model)        │
  │ + _declineRequest(ctx, Model)       │
  └─────────────────────────────────────┘


  ── Feed ───────────────────────────────────────────────────────────

  ┌─────────────────────────────────────┐
  │         <<enum>>                    │
  │         FeedItemType                │
  ├─────────────────────────────────────┤
  │ + connection                        │
  │ + message                           │
  │ + thread                            │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │         <<abstract>>                │
  │         FeedItem                    │
  ├─────────────────────────────────────┤
  │ + id: String                        │
  │ + timestamp: DateTime               │
  │ + type: FeedItemType                │
  └──────────────────┬──────────────────┘
                     │ extends
                     ▼
  ┌─────────────────────────────────────┐
  │       ConnectionFeedItem            │
  ├─────────────────────────────────────┤
  │ + contactPeerId: String             │
  │ + contactUsername: String            │
  │ + contactAvatarPath: String?        │
  ├─────────────────────────────────────┤
  │ + fromContact(ContactModel): Self   │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │       MessageFeedItem               │
  ├─────────────────────────────────────┤
  │ + contactPeerId: String             │
  │ + contactUsername: String            │
  │ + messageId: String                 │
  │ + messageText: String               │
  │ + messageTime: String               │
  │ + unreadCount: int                  │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │       ThreadFeedItem                │
  ├─────────────────────────────────────┤
  │ + contactPeerId: String             │
  │ + contactUsername: String            │
  │ + messages: List<ThreadMessage>     │
  │ + unreadCount: int                  │
  │ + isUnreadCard: bool                │
  ├─────────────────────────────────────┤
  │ + isMultiMessage: bool (getter)     │
  │ + latestMessage: ThreadMessage      │
  │ + additionalCount: int (getter)     │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │       ThreadMessage                 │
  ├─────────────────────────────────────┤
  │ + id: String                        │
  │ + text: String                      │
  │ + time: String                      │
  │ + timestamp: DateTime               │
  │ + isUnread: bool                    │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │    FeedWired                        │
  ├─────────────────────────────────────┤
  │ + repository: IdentityRepository    │
  │ + contactRepository: ContactRepo    │
  │ + contactRequestRepository: CRRepo  │
  │ + contactRequestListener: Listener  │
  │ + messageRepository: MessageRepo    │
  │ + bridge: Bridge                    │
  │ + p2pService: P2PService            │
  │ + initialContact: ContactModel      │
  ├─────────────────────────────────────┤
  │ - _identity: IdentityModel?         │
  │ - _feedItems: List<FeedItem>        │
  │ - _totalUnreadCount: int            │
  │ - _requestSubscription: StreamSub   │
  ├─────────────────────────────────────┤
  │ + _loadIdentity()                   │
  │ + _buildInitialFeed()               │
  │ + _startListeningForContactRequests │
  │ + _onContactRequest(Model)          │
  │ + _acceptRequest(ctx, Model)        │
  │ + _declineRequest(ctx, Model)       │
  │ + _onSwitchView('orbit')            │
  │     → Navigator.push(OrbitWired)    │
  └─────────────────────────────────────┘


  ── Orbit Domain ───────────────────────────────────────────────────────

  ┌─────────────────────────────────────┐
  │       OrbitFriend                   │
  ├─────────────────────────────────────┤
  │ + contact: ContactModel             │
  │ + messageCount: int                 │
  │ + lastActivity: String              │
  │ + lastMessageTimestamp: DateTime?   │
  │ + unreadCount: int (default 0)     │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │    OrbitWired                        │
  ├─────────────────────────────────────┤
  │ + contactRepository: ContactRepo    │
  │ + messageRepository: MessageRepo    │
  │ + chatMessageListener: Listener     │
  │ + contactRequestListener: Listener  │
  │ + identityRepository: IdentityRepo  │
  │ + p2pService: P2PService            │
  │ + bridge: Bridge                    │
  │ + contactRequestRepository: CRRepo  │
  ├─────────────────────────────────────┤
  │ - _orbitFriends: List<OrbitFriend>  │
  │ - _filteredFriends: List<OrbitFriend>│
  │ - _identity: IdentityModel?         │
  │ - _collapseController: AnimCtrl     │
  │   (580ms)                           │
  │ - _searchDockController: AnimCtrl   │
  │   (560ms)                           │
  │ - _searchTriggerController: AnimCtrl│
  │   (340ms)                           │
  │ - _isSearchActive: bool             │
  │ - _searchQuery: String              │
  ├─────────────────────────────────────┤
  │ + _loadOrbitData()                  │
  │ + _onSearch(String)                 │
  │ + _onFriendTap(OrbitFriend)         │
  │     → Navigator.push(ConvWired)     │
  │ + _onClose()                        │
  │     → Navigator.pop()              │
  └─────────────────────────────────────┘


  ── Conversation Domain ─────────────────────────────────────────────────

  ┌─────────────────────────────────────┐
  │       ConversationMessage           │
  ├─────────────────────────────────────┤
  │ + id: String (UUID)                 │
  │ + contactPeerId: String             │
  │ + senderPeerId: String              │
  │ + text: String                      │
  │ + timestamp: String                 │
  │ + status: String                    │
  │   ('sending'|'sent'|'delivered'|    │
  │    'queued'|'failed')              │
  │ + isIncoming: bool                  │
  │ + createdAt: String                 │
  │ + readAt: String?                   │
  ├─────────────────────────────────────┤
  │ + fromMap(Map): ConversationMessage │
  │ + toMap(): Map                      │
  │ + copyWith(): ConversationMessage   │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │       MessagePayload                │
  ├─────────────────────────────────────┤
  │ + id: String                        │
  │ + text: String                      │
  │ + senderPeerId: String              │
  │ + senderUsername: String             │
  │ + timestamp: String                 │
  ├─────────────────────────────────────┤
  │ + fromJson(String): MessagePayload? │
  │ + toJson(): String (v1 envelope)    │
  │ + toInnerJson(): String (payload)   │
  │ + toConversationMessage(): Model    │
  │ + buildEncryptedEnvelope(           │
  │ │   kem, ciphertext, nonce,         │
  │ │   senderPeerId): String (v2)      │
  │ + parseEncryptedEnvelope(           │
  │ │   json): Map? (v2 detection)      │
  │ + fromDecryptedJson(                │
  │ │   json): MessagePayload?          │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │         <<abstract>>                │
  │       MessageRepository             │
  ├─────────────────────────────────────┤
  │ + saveMessage(Model): void          │
  │ + getMessagesForContact(id): List   │
  │ + getLatestMessageForContact(): Msg?│
  │ + updateMessageStatus(id, s): void  │
  │ + messageExists(id): bool           │
  │ + getMessageCountForContact(        │
  │ │   contactPeerId): Future<int>     │
  │ + markConversationAsRead(           │
  │ │   contactPeerId): Future<int>     │
  │ + getUnreadCountForContact(         │
  │ │   contactPeerId): Future<int>     │
  │ + getTotalUnreadCount(): Future<int>│
  │ + getTotalUnreadCountExcluding     │
  │ │   Archived(): Future<int>        │
  │ + deleteMessagesForContact(        │
  │ │   peerId): Future<void>          │
  │ + getFailedOutgoingMessages():     │
  │ │   Future<List<ConversationMsg>>  │
  │ + getMessagesPage(contactPeerId,   │
  │ │   {limit, beforeTimestamp}):      │
  │ │   Future<List<ConversationMsg>>  │
  └──────────────────┬──────────────────┘
                     │ implements
                     ▼
  ┌─────────────────────────────────────┐
  │     MessageRepositoryImpl           │
  ├─────────────────────────────────────┤
  │ - dbInsertMessage: Function         │
  │ - dbLoadMessagesForContact: Function│
  │ - dbLoadLatestMessageForContact: Fn │
  │ - dbUpdateMessageStatus: Function   │
  │ - dbLoadMessage: Function           │
  │ - dbCountMessagesForContact: Fn     │
  │ - dbMarkConversationAsRead: Function│
  │ - dbCountUnreadForContact: Function │
  │ - dbCountTotalUnread: Function      │
  │ - dbCountTotalUnreadExcluding      │
  │     Archived: Function              │
  │ - dbDeleteMessagesForContact: Fn    │
  │ - dbLoadFailedOutgoingMessages: Fn  │
  │ - dbLoadMessagesPage: Function      │
  └─────────────────────────────────────┘


  ── Conversation Services ──────────────────────────────────────────────

  ┌─────────────────────────────────────┐
  │     ChatMessageListener             │
  ├─────────────────────────────────────┤
  │ - chatMessageStream: Stream         │
  │ - messageRepo: MessageRepository    │
  │ - contactRepo: ContactRepository    │
  │ - bridge: Bridge?                   │
  │ - getOwnMlKemSecretKey: Fn?        │
  │ - _subscription: StreamSubscription │
  │ - _messageController: StreamCtrl    │
  │ - _contactUpdatedController: Ctrl   │
  ├─────────────────────────────────────┤
  │ + incomingMessageStream: Stream     │
  │ + contactUpdatedStream: Stream      │
  │ + start(): void                     │
  │ + stop(): void                      │
  │ + dispose(): void                   │
  │ - _onMessage(ChatMessage): void     │
  └─────────────────────────────────────┘


  ── Incoming Message Router ────────────────────────────────────────────

  ┌─────────────────────────────────────┐
  │     IncomingMessageRouter           │
  ├─────────────────────────────────────┤
  │ - p2pService: P2PService            │
  │ - _subscription: StreamSubscription │
  │ - _contactRequestCtrl: StreamCtrl   │
  │ - _chatMessageCtrl: StreamCtrl      │
  │ - _unknownCtrl: StreamCtrl          │
  ├─────────────────────────────────────┤
  │ + contactRequestStream: Stream      │
  │ + chatMessageStream: Stream         │
  │ + unknownMessageStream: Stream      │
  │ + start(): void                     │
  │ + stop(): void                      │
  │ + dispose(): void                   │
  │ - _route(ChatMessage): void         │
  └─────────────────────────────────────┘


  ── Ring Avatar System ───────────────────────────────────────────────────

  ┌─────────────────────────────────────┐
  │     RingAvatarGenerator             │
  ├─────────────────────────────────────┤
  │ + generate(peerId, size): Data      │  (static)
  │ + djb2Hash(String): int             │  (static)
  │ - _shuffleColors(hash): List<Color> │
  │ - _generateRingParams(...)          │
  │ - _calculateRingRadii(...)          │
  │ - _generateGlow(hash, size)         │
  └─────────────────────────────────────┘

  ┌──────────────────┐  ┌──────────────────┐  ┌────────────────────┐
  │  RingAvatarData  │  │  RingData        │  │  GlowData          │
  │  rings: List     │  │  radius, stroke  │  │  color, outerR     │
  │  glow: GlowData  │  │  color, opacity  │  │  middleR, innerR   │
  │                  │  │  rotation, dash  │  │                    │
  └──────────────────┘  └──────────────────┘  └────────────────────┘


  ── Enums ────────────────────────────────────────────────────────────────

  ┌─────────────────────────────────────┐        ┌─────────────────────────┐
  │         <<enum>>                    │        │      <<enum>>           │
  │         StartupDecision             │        │  GenerateIdentityResult │
  ├─────────────────────────────────────┤        ├─────────────────────────┤
  │ + hasIdentityWithContacts           │        │ + success               │
  │ + hasIdentityNoContacts             │        │ + coreLibError          │
  │ + needsIdentity                     │        │ + dbError               │
  └─────────────────────────────────────┘        └─────────────────────────┘

  ┌─────────────────────────────────────┐        ┌─────────────────────────┐
  │         <<enum>>                    │        │      <<enum>>           │
  │       RestoreIdentityResult         │        │   BuildQRPayloadResult  │
  ├─────────────────────────────────────┤        ├─────────────────────────┤
  │ + success                           │        │ + success               │
  │ + invalidMnemonicFormat             │        │ + noIdentity            │
  │ + invalidMnemonicCore               │        │ + signingError          │
  │ + coreLibError                      │        └─────────────────────────┘
  │ + dbError                           │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐        ┌─────────────────────────┐
  │         <<enum>>                    │        │      <<enum>>           │
  │         ParseQRResult              │        │   AddContactResult      │
  ├─────────────────────────────────────┤        ├─────────────────────────┤
  │ + success                           │        │ + success               │
  │ + invalidJson                       │        │ + alreadyExists         │
  │ + missingFields                     │        │ + dbError               │
  │ + invalidSignature                  │        └─────────────────────────┘
  │ + expired                           │
  │ + selfScan                          │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐        ┌─────────────────────────┐
  │         <<enum>>                    │        │      <<enum>>           │
  │         StartNodeResult             │        │   StopNodeResult        │
  ├─────────────────────────────────────┤        ├─────────────────────────┤
  │ + success                           │        │ + success               │
  │ + noIdentity                        │        │ + notRunning            │
  │ + bridgeError                       │        │ + error                 │
  │ + connectionError                   │        └─────────────────────────┘
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐        ┌─────────────────────────┐
  │       SendMessageResult             │        │      <<enum>>           │
  │       [P2P Model / Class]           │        │  DiscoverPeerResult     │
  ├─────────────────────────────────────┤        ├─────────────────────────┤
  │ + sent: bool                        │        │ + success               │
  │ + reply: String?                    │        │ + nodeNotRunning        │
  │ + acknowledged: bool (getter)       │        │ + notFound              │
  │   (sent && reply != null/empty)     │        │ + error                 │
  └─────────────────────────────────────┘        └─────────────────────────┘

  ┌─────────────────────────────────────┐        ┌─────────────────────────┐
  │         <<enum>>                    │        │      <<enum>>           │
  │    SendContactRequestResult         │        │ AcceptContactReqResult  │
  ├─────────────────────────────────────┤        ├─────────────────────────┤
  │ + success                           │        │ + success               │
  │ + noIdentity                        │        │ + notFound              │
  │ + signingError                      │        │ + notPending            │
  │ + nodeNotRunning                    │        │ + addContactError       │
  │ + peerNotFound                      │        │ + updateStatusError     │
  │ + sendFailed                        │        └─────────────────────────┘
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐        ┌─────────────────────────┐
  │         <<enum>>                    │        │      <<enum>>           │
  │   DeclineContactRequestResult       │        │  HandleMessageResult    │
  ├─────────────────────────────────────┤        ├─────────────────────────┤
  │ + success                           │        │ + contactRequest        │
  │ + notFound                          │        │ + duplicateRequest      │
  │ + updateError                       │        │ + alreadyContact        │
  └─────────────────────────────────────┘        │ + regularMessage        │
                                                 │ + invalidMessage        │
  ┌─────────────────────────────────────┐        └─────────────────────────┘
  │         <<enum>>                    │
  │    ContactRequestStatus             │
  ├─────────────────────────────────────┤
  │ + pending                           │
  │ + accepted                          │
  │ + declined                          │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐        ┌─────────────────────────┐
  │         <<enum>>                    │        │      <<enum>>           │
  │    SendChatMessageResult            │        │ HandleChatMessageResult │
  ├─────────────────────────────────────┤        ├─────────────────────────┤
  │ + success                           │        │ + chatMessage           │
  │ + nodeNotRunning                    │        │ + notChatMessage        │
  │ + invalidMessage                    │        │ + unknownSender         │
  │ + peerNotFound                      │        │ + duplicate             │
  │ + dialFailed                        │        └─────────────────────────┘
  │ + sendFailed                        │
  └─────────────────────────────────────┘

└─────────────────────────────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────────────────┐
│                        GO BRIDGE WIRE FORMAT                                 │
├─────────────────────────────────────────────────────────────────────────────┤

  Bridge Request (MethodChannel → Go):
  ┌─────────────────────────────────────┐
  │  MethodChannel invocation           │
  ├─────────────────────────────────────┤
  │ + methodName: string                │
  │   (camelCase, e.g.                 │
  │    "generateIdentity",            │
  │    "startNode", "dialPeer")        │
  │ + argument: string? (JSON payload) │
  └─────────────────────────────────────┘

  Bridge Response (Go → MethodChannel):
  ┌─────────────────────────────────────┐
  │  JSON response string               │
  ├─────────────────────────────────────┤
  │ + ok: boolean                       │
  │ + identity?: IdentityJson           │
  │ + signature?: string                │
  │ + verified?: boolean                │
  │ + publicKey?: string                │
  │ + secretKey?: string                │
  │ + kem?: string                      │
  │ + ciphertext?: string               │
  │ + nonce?: string                    │
  │ + plaintext?: string                │
  │ + peerId?: string                   │
  │ + peers?: []                        │
  │ + messages?: []                     │
  │ + errorCode?: string                │
  │ + errorMessage?: string             │
  └─────────────────────────────────────┘

  Push Events (Go → EventChannel):
  ┌─────────────────────────────────────┐
  │  JSON event via EventChannel        │
  ├─────────────────────────────────────┤
  │ + event: string                     │
  │   ("message:received" |            │
  │    "peer:connected" |              │
  │    "peer:disconnected")            │
  │ + data: object                      │
  │   (message content or peer info)   │
  └─────────────────────────────────────┘

  Command Name Mapping (Dart cmd → MethodChannel method):
  ┌─────────────────────────────────────┐
  │  GoBridgeClient._cmdMap             │
  │  (cmd → _CmdSpec(methodName, bool)) │
  ├─────────────────────────────────────┤
  │  identity.generate → generateIdent. │
  │  identity.restore  → restoreIdent.  │
  │  payload.sign      → signPayload    │
  │  payload.verify    → verifyPayload  │
  │  mlkem.keygen      → mlKemKeygen    │
  │  message.encrypt   → encryptMessage │
  │  message.decrypt   → decryptMessage │
  │  node:start        → startNode      │
  │  node:stop         → stopNode       │
  │  node:status       → nodeStatus     │
  │  rendezvous:register → rendezvousR. │
  │  rendezvous:discover → rendezvousD. │
  │  peer:dial         → dialPeer       │
  │  peer:disconnect   → disconnectPeer │
  │  message:send      → sendMessage    │
  │  inbox:store       → inboxStore     │
  │  inbox:retrieve    → inboxRetrieve  │
  │  inbox:register_token → inboxReg.T. │
  └─────────────────────────────────────┘

└─────────────────────────────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────────────────┐
│                            FUNCTION SIGNATURES                               │
├─────────────────────────────────────────────────────────────────────────────┤

  FLUTTER USE CASES - IDENTITY:
  ─────────────────────────────
  decideStartupRoute(
    identityRepo: IdentityRepository,
    contactRepo: ContactRepository
  ): Future<StartupDecision>

  generateNewIdentity(
    callGenerate: () => Future<Map>,
    repo: IdentityRepository
  ): Future<GenerateIdentityResult>

  restoreIdentityFromMnemonic(
    input: String,
    callRestore: (String) => Future<Map>,
    repo: IdentityRepository
  ): Future<RestoreIdentityResult>


  FLUTTER USE CASES - QR CODE:
  ────────────────────────────
  buildQRPayload(
    repo: IdentityRepository,
    callSign: (String, String) => Future<Map>
  ): Future<(BuildQRPayloadResult, String?)>

  parseQRPayload(
    qrString: String,
    bridge: Bridge,
    ownPeerId: String,
    {maxAge: Duration = 24h}
  ): Future<(ParseQRResult, ContactModel?)>


  FLUTTER USE CASES - P2P:
  ────────────────────────
  startP2PNode(
    identityRepo: IdentityRepository,
    p2pService: P2PService
  ): Future<StartNodeResult>

  stopP2PNode(
    p2pService: P2PService
  ): Future<StopNodeResult>

  sendP2PMessage(
    p2pService: P2PService,
    peerId: String,
    message: String
  ): Future<SendMessageResult>

  discoverP2PPeer(
    p2pService: P2PService,
    peerId: String
  ): Future<(DiscoverPeerResult, DiscoveredPeer?)>

  dialP2PPeer(
    p2pService: P2PService,
    peerId: String,
    {addresses: List<String>?}
  ): Future<bool>


  FLUTTER USE CASES - CONVERSATION:
  ──────────────────────────────────
  sendChatMessage(
    p2pService: P2PService,
    messageRepo: MessageRepository,
    targetPeerId: String,
    text: String,
    senderPeerId: String,
    senderUsername: String,
    {messageId?: String, timestamp?: String,
     bridge?: Bridge,
     recipientMlKemPublicKey?: String}
  ): Future<(SendChatMessageResult, ConversationMessage?)>
  // If bridge + recipientMlKemPublicKey present → encrypt (v2 envelope)
  // Otherwise → plaintext (v1 envelope)
  // On send failure after 3x retry → storeInInbox() fallback

  handleIncomingChatMessage(
    message: ChatMessage,
    messageRepo: MessageRepository,
    contactRepo: ContactRepository,
    {bridge?: Bridge,
     ownMlKemSecretKey?: String}
  ): Future<(HandleChatMessageResult, ConversationMessage?, ContactModel?)>
  // Detects v2 encrypted envelope → decrypts via ML-KEM + AES-256-GCM
  // Falls back to v1 plaintext parsing

  loadConversation(
    messageRepo: MessageRepository,
    contactPeerId: String
  ): Future<List<ConversationMessage>>

  markConversationRead(
    messageRepo: MessageRepository,
    contactPeerId: String
  ): Future<int>

  retryFailedMessages(
    messageRepo: MessageRepository,
    identityRepo: IdentityRepository,
    contactRepo: ContactRepository,
    p2pService: P2PService,
    bridge: Bridge
  ): Future<int>   // Returns count of successfully retried messages


  FLUTTER USE CASES - FEED:
  ─────────────────────────
  loadFeed(
    contactRepo: ContactRepository,
    messageRepo: MessageRepository
  ): Future<List<FeedItem>>
  // Also queries unread counts per contact for MessageFeedItems


  FLUTTER USE CASES - ORBIT:
  ──────────────────────────
  loadOrbitData(
    contactRepo: ContactRepository,
    messageRepo: MessageRepository
  ): Future<List<OrbitFriend>>
  // Loads all contacts, queries message count + unread count per contact,
  // sorts by messageCount descending


  FLUTTER USE CASES - PUSH NOTIFICATIONS:
  ────────────────────────────────────────
  requestPushPermission(): Future<bool>

  registerPushToken(
    p2pService: P2PService
  ): Future<void>


  FLUTTER USE CASES - CONTACTS:
  ─────────────────────────────
  addContact(
    repository: ContactRepository,
    contact: ContactModel
  ): Future<AddContactResult>

  archiveContact(
    contactRepo: ContactRepository,
    peerId: String
  ): Future<void>

  unarchiveContact(
    contactRepo: ContactRepository,
    peerId: String
  ): Future<void>

  blockContact(
    contactRepo: ContactRepository,
    peerId: String
  ): Future<void>

  unblockContact(
    contactRepo: ContactRepository,
    peerId: String
  ): Future<void>

  deleteContactAndMessages(
    contactRepo: ContactRepository,
    messageRepo: MessageRepository,
    peerId: String
  ): Future<void>


  FLUTTER USE CASES - CONTACT REQUESTS:
  ─────────────────────────────────────
  sendContactRequest(
    p2pService: P2PService,
    identityRepo: IdentityRepository,
    bridge: Bridge,
    targetPeerId: String
  ): Future<SendContactRequestResult>

  acceptContactRequest(
    requestRepo: ContactRequestRepository,
    contactRepo: ContactRepository,
    peerId: String
  ): Future<AcceptContactRequestResult>

  declineContactRequest(
    requestRepo: ContactRequestRepository,
    peerId: String
  ): Future<DeclineContactRequestResult>

  handleIncomingMessage(
    message: ChatMessage,
    bridge: Bridge,
    requestRepo: ContactRequestRepository,
    contactRepo: ContactRepository,
    ownPeerId: String
  ): Future<(HandleMessageResult, ContactRequestModel?)>


  FLUTTER BRIDGE HELPERS - IDENTITY/CRYPTO:
  ─────────────────────────────────────────
  callIdentityGenerate(bridge: Bridge): Future<Map<String, dynamic>>
  callIdentityRestore(bridge: Bridge, mnemonic12: String): Future<Map<String, dynamic>>
  callSignPayload(bridge: Bridge, dataToSign: String, privateKey: String): Future<Map<String, dynamic>>
  callVerifyPayload(bridge: Bridge, dataToVerify: String, signature: String, publicKey: String): Future<Map<String, dynamic>>
  callMlKemKeygen(bridge: Bridge): Future<Map<String, dynamic>>
  callEncryptMessage({bridge, recipientMlKemPublicKey, plaintext, timeout?}): Future<Map<String, dynamic>>
  callDecryptMessage({bridge, ownMlKemSecretKey, kem, ciphertext, nonce, timeout?}): Future<Map<String, dynamic>>


  FLUTTER BRIDGE HELPERS - P2P:
  ─────────────────────────────
  callP2PNodeStart(bridge, privateKeyHex, {relayAddresses, autoRegister, namespace}): Future<Map>
  callP2PNodeStop(bridge): Future<Map>
  callP2PNodeStatus(bridge): Future<Map>
  callP2PRendezvousRegister(bridge, {namespace, serverAddresses}): Future<Map>
  callP2PRendezvousDiscover(bridge, {peerId, namespace, serverAddresses, timeoutMs}): Future<Map>
  callP2PPeerDial(bridge, peerId, {addresses, timeoutMs}): Future<Map>
  callP2PPeerDisconnect(bridge, peerId): Future<Map>
  callP2PMessageSend(bridge, peerId, message, {timeoutMs}): Future<Map>
  callP2PInboxStore(bridge, {toPeerId, message}): Future<Map>
  callP2PInboxRetrieve(bridge): Future<Map>
  callP2PInboxRegisterToken(bridge, {token, platform}): Future<Map>


  FLUTTER DB HELPERS - IDENTITY:
  ──────────────────────────────
  dbLoadIdentityRow(db: Database): Future<Map<String, Object?>?>
  dbUpsertIdentityRow(db: Database, row: Map<String, Object?>): Future<void>
  runIdentityTableMigration(db: Database): Future<void>   ← creates all 3 tables


  FLUTTER DB HELPERS - CONTACTS:
  ──────────────────────────────
  dbLoadAllContacts(db: Database): Future<List<Map>>
  dbLoadContact(db: Database, peerId: String): Future<Map?>
  dbUpsertContact(db: Database, row: Map): Future<void>
  dbDeleteContact(db: Database, peerId: String): Future<void>
  dbGetContactCount(db: Database): Future<int>
  dbContactExists(db: Database, peerId: String): Future<bool>
  dbArchiveContact(db: Database, peerId: String): Future<void>
  dbUnarchiveContact(db: Database, peerId: String): Future<void>
  dbLoadActiveContacts(db: Database): Future<List<Map>>
  dbLoadArchivedContacts(db: Database): Future<List<Map>>
  dbBlockContact(db: Database, peerId: String): Future<void>
  dbUnblockContact(db: Database, peerId: String): Future<void>


  FLUTTER DB HELPERS - CONTACT REQUESTS:
  ──────────────────────────────────────
  dbLoadPendingRequests(db: Database): Future<List<Map>>
  dbLoadRequest(db: Database, peerId: String): Future<Map?>
  dbUpsertRequest(db: Database, row: Map): Future<void>
  dbUpdateRequestStatus(db: Database, peerId: String, status: String): Future<void>
  dbDeleteRequest(db: Database, peerId: String): Future<void>
  dbRequestExists(db: Database, peerId: String): Future<bool>


  FLUTTER DB HELPERS - MESSAGES:
  ──────────────────────────────
  dbInsertMessage(db: Database, row: Map<String, Object?>): Future<void>
  dbLoadMessagesForContact(db: Database, contactPeerId: String): Future<List<Map>>
  dbLoadLatestMessageForContact(db: Database, contactPeerId: String): Future<Map?>
  dbUpdateMessageStatus(db: Database, id: String, status: String): Future<void>
  dbLoadMessage(db: Database, id: String): Future<Map?>
  dbGetMessageCount(db: Database): Future<int>
  dbCountMessagesForContact(db: Database, contactPeerId: String): Future<int>
  dbMarkConversationAsRead(db: Database, contactPeerId: String): Future<int>
  dbCountUnreadForContact(db: Database, contactPeerId: String): Future<int>
  dbCountTotalUnread(db: Database): Future<int>
  dbCountTotalUnreadExcludingArchived(db: Database): Future<int>
  dbDeleteMessagesForContact(db: Database, contactPeerId: String): Future<void>
  dbLoadFailedOutgoingMessages(db: Database): Future<List<Map>>
  dbLoadMessagesPage(db: Database, contactPeerId: String, {limit: int, beforeTimestamp: String?}): Future<List<Map>>
  runMessagesTableMigration(db: Database): Future<void>   ← creates messages table + indexes
  runReadAtColumnMigration(db: Database): Future<void>    ← adds read_at TEXT to messages (v6)
  runArchiveColumnsMigration(db: Database): Future<void>  ← adds is_archived, archived_at to contacts (v7)
  runBlockColumnsMigration(db: Database): Future<void>    ← adds is_blocked, blocked_at to contacts (v8)


  FLUTTER UTILS:
  ──────────────
  base64ToHex(String base64): String
  hexToBase64(String hex): String
  bytesToHex(Uint8List bytes): String
  hexToBytes(String hex): Uint8List
  RingAvatarGenerator.generate(String peerId, double size): RingAvatarData
  RingAvatarGenerator.djb2Hash(String input): int
  formatRelativeTime(DateTime timestamp): String   ← "2m ago", "3h ago", etc.


  FLUTTER DB HELPERS - ML-KEM KEYS:
  ─────────────────────────────────
  runMlKemKeysMigration(db: Database): Future<void>   ← adds ml_kem_* columns to identity, contacts, contact_requests


  FLUTTER DB HELPERS - DATA-AT-REST HARDENING:
  ─────────────────────────────────────────────
  runNullifySecretColumnsMigration(db: Database): Future<void>   ← v4: makes private_key, mnemonic12 nullable
  runSecretNullChecksMigration(db: Database): Future<void>       ← v5: CHECK constraints + avatar_blob BLOB


  FLUTTER SECURE STORAGE:
  ───────────────────────
  SecureKeyStore.read(key: String): Future<String?>
  SecureKeyStore.write(key: String, value: String): Future<void>
  SecureKeyStore.delete(key: String): Future<void>
  SecureKeyStore.containsKey(key: String): Future<bool>
  openEncryptedDatabase(path, version, secureKeyStore): Future<Database>
  migrateSecretsToSecureStorage(db, secureKeyStore): Future<void>


  GO BRIDGE FUNCTIONS (go-mknoon/bridge/bridge.go):
  ─────────────────────────────────────────────────
  HandleCommand(command string, payload string) string   // JSON dispatch to all handlers
  handleIdentityGenerate(payload) → {ok, identity}       // BIP39 + Ed25519 + ML-KEM-768
  handleIdentityRestore(payload) → {ok, identity}        // Derive from mnemonic + fresh ML-KEM
  handlePayloadSign(payload) → {ok, signature}           // Ed25519 sign
  handlePayloadVerify(payload) → {ok, verified}          // Ed25519 verify
  handleMlKemKeygen(payload) → {ok, publicKey, secretKey}
  handleMessageEncrypt(payload) → {ok, kem, ciphertext, nonce}
  handleMessageDecrypt(payload) → {ok, plaintext}
  handleNodeStart(payload) → {ok, peerId, ...}           // libp2p node + relay + auto-register
  handleNodeStop(payload) → {ok}
  handleNodeStatus(payload) → {ok, peerId, isStarted, connections, ...}
  handleRendezvousRegister(payload) → {ok}               // Signed peer record registration
  handleRendezvousDiscover(payload) → {ok, peers}
  handlePeerDial(payload) → {ok}
  handlePeerDisconnect(payload) → {ok}
  handleMessageSend(payload) → {ok, reply?}              // Frame-based with ACK
  handleInboxStore(payload) → {ok}
  handleInboxRetrieve(payload) → {ok, messages}
  handleInboxRegisterToken(payload) → {ok}               // FCM token registration

  GO NODE FUNCTIONS (go-mknoon/node/):
  ─────────────────────────────────────
  Node.Start(privateKeyHex, relayAddresses) error        // libp2p host + relay + NAT + hole punch
  Node.Stop() error
  Node.Status() NodeStatus
  Node.RegisterRendezvous(namespace, serverAddrs) error  // Protobuf signed peer records
  Node.DiscoverPeers(namespace, serverAddrs, timeout) []Peer
  Node.DialPeer(peerId, addresses, timeout) error
  Node.DisconnectPeer(peerId) error
  Node.SendMessage(peerId, message, timeout) (reply, error)  // /mknoon/chat/1.0.0
  Node.StoreInbox(toPeerId, message) error               // /mknoon/inbox/1.0.0
  Node.RetrieveInbox() []InboxMessage
  Node.RegisterInboxToken(token, platform) error          // FCM push registration
  Node.SetEventCallback(callback)                         // Push events to Flutter

└─────────────────────────────────────────────────────────────────────────────┘
```

### Class Relationships

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          DEPENDENCY GRAPH                                    │
└─────────────────────────────────────────────────────────────────────────────┘

  StartupRouter
       │
       ├──────► decideStartupRoute()
       │              │
       │              ├──────► IdentityRepository.loadIdentity()
       │              │
       │              └──────► ContactRepository.getContactCount()
       │
       ├──────► FeedWired (hasIdentityWithContacts)
       │              │
       │              ├──────► IdentityRepository.loadIdentity()
       │              │
       │              ├──────► ContactRequestListener.requestStream
       │              │
       │              ├──────► ConnectionFeedItem.fromContact()
       │              │
       │              └──────► _onSwitchView('orbit')
       │                             │
       │                             └──────► Navigator.push(OrbitWired)
       │                                            │
       │                                            ├──────► loadOrbitData()
       │                                            │              │
       │                                            │              ├──────► ContactRepository.getAllContacts()
       │                                            │              │
       │                                            │              └──────► MessageRepository.getMessageCountForContact()
       │                                            │
       │                                            ├──────► ChatMessageListener.incomingMessageStream
       │                                            │
       │                                            ├──────► ContactRequestListener.requestStream
       │                                            │
       │                                            └──────► _onFriendTap()
       │                                                           │
       │                                                           └──────► Navigator.push(ConversationWired)
       │
       ├──────► FirstTimeExperienceWired (hasIdentityNoContacts)
       │
       ├──────► IdentityChoiceWired (needsIdentity)
       │              │
       │              ├──────► generateNewIdentity()
       │              │              │
       │              │              ├──────► callIdentityGenerate()
       │              │              │              │
       │              │              │              └──────► GoBridgeClient.send()
       │              │              │                             │
       │              │              │                             └──────► [Go] HandleCommand()
       │              │              │                                            │
       │              │              │                                            └──────► GenerateIdentity()
       │              │              │
       │              │              └──────► IdentityRepository.saveIdentity()
       │              │                             │
       │              │                             └──────► dbUpsertIdentityRow()
       │              │
       │              └──────► MnemonicInputWired
       │                             │
       │                             └──────► restoreIdentityFromMnemonic()
       │                                            │
       │                                            ├──────► callIdentityRestore()
       │                                            │              │
       │                                            │              └──────► [Go] RestoreFromMnemonic()
       │                                            │
       │                                            └──────► IdentityRepository.saveIdentity()
       │
       └──────► FirstTimeExperienceWired (from needsIdentity after generation)
                      │
                      ├──────► buildQRPayload()
                      │              │
                      │              ├──────► IdentityRepository.loadIdentity()
                      │              │
                      │              └──────► callSignPayload()
                      │                             │
                      │                             └──────► [Go] SignPayload()
                      │
                      ├──────► _onUsernameChanged()
                      │              │
                      │              └──────► IdentityRepository.saveIdentity()
                      │
                      ├──────► _onCameraPressed()
                      │              │
                      │              ├──────► ImagePicker.pickImage()
                      │              │
                      │              ├──────► Read bytes as Uint8List (no file copy to disk)
                      │              │
                      │              └──────► IdentityRepository.saveIdentity(avatarBlob: bytes)
                      │                             (avatar BLOB stored in SQLCipher DB)
                      │
                      ├──────► _onScanPressed()
                      │              │
                      │              └──────► QRScannerWired
                      │                             │
                      │                             ├──────► parseQRPayload()
                      │                             │              │
                      │                             │              ├──────► [Go] VerifyPayload()
                      │                             │              │
                      │                             │              └──────► ContactModel.fromQRPayload()
                      │                             │
                      │                             ├──────► addContact()
                      │                             │              │
                      │                             │              └──────► ContactRepository.addContact()
                      │                             │
                      │                             └──────► sendContactRequest() (background)
                      │                                            │
                      │                                            ├──────► P2PService.discoverPeer()
                      │                                            │
                      │                                            ├──────► P2PService.dialPeer()
                      │                                            │
                      │                                            └──────► P2PService.sendMessage()
                      │
                      └──────► ContactRequestListener.requestStream
                                     │
                                     └──────► _onContactRequest()
                                                    │
                                                    ├──────► ContactRequestDialog (Accept/Decline)
                                                    │
                                                    ├──────► acceptContactRequest()
                                                    │              │
                                                    │              ├──────► ContactRequestRepo.getRequest()
                                                    │              │
                                                    │              ├──────► ContactModel.fromRequest()
                                                    │              │
                                                    │              ├──────► ContactRepository.addContact()
                                                    │              │
                                                    │              └──────► ContactRequestRepo.updateStatus()
                                                    │
                                                    └──────► declineContactRequest()
                                                                   │
                                                                   └──────► ContactRequestRepo.updateStatus()


  IncomingMessageRouter (background service)
       │
       └──────► P2PService.messageStream (subscribe)
                      │
                      ├──────► contactRequestStream (type = "contact_request")
                      │
                      ├──────► chatMessageStream (type = "chat_message")
                      │
                      └──────► unknownMessageStream (other types)


  ContactRequestListener (background service)
       │
       └──────► IncomingMessageRouter.contactRequestStream (subscribe)
                      │
                      └──────► handleIncomingMessage()
                                     │
                                     ├──────► JSON parse + validate
                                     │
                                     ├──────► [Go] VerifyPayload()
                                     │
                                     ├──────► ContactRepository.contactExists()
                                     │
                                     ├──────► ContactRequestRepo.requestExists()
                                     │
                                     └──────► ContactRequestRepo.addRequest()


  ChatMessageListener (background service)
       │
       ├──────► bridge: Bridge? (for ML-KEM decryption)
       │
       ├──────► getOwnMlKemSecretKey: () => Future<String?> (from identity repo)
       │
       └──────► IncomingMessageRouter.chatMessageStream (subscribe)
                      │
                      └──────► handleIncomingChatMessage(bridge, ownMlKemSecretKey)
                                     │
                                     ├──────► Detect v2 encrypted envelope
                                     │              │
                                     │              └──────► callDecryptMessage() (ML-KEM + AES-256-GCM)
                                     │
                                     ├──────► [else] Parse v1 plaintext MessagePayload
                                     │
                                     ├──────► ContactRepository.getContact() (validate sender)
                                     │
                                     ├──────► MessageRepository.messageExists() (duplicate check)
                                     │
                                     ├──────► ContactRepository.addContact() (if username changed)
                                     │
                                     └──────► MessageRepository.saveMessage()


  ConversationWired
       │
       ├──────► loadConversation()
       │              │
       │              └──────► MessageRepository.getMessagesForContact()
       │
       ├──────► _onSend(text) → sendChatMessage(bridge, recipientMlKemPublicKey)
       │              │
       │              ├──────► MessageRepository.saveMessage() (optimistic persist)
       │              │
       │              ├──────► [if ML-KEM key] callEncryptMessage() → v2 envelope
       │              │
       │              ├──────► [else] Build v1 plaintext envelope
       │              │
       │              ├──────► P2PService.discoverPeer()
       │              │
       │              ├──────► P2PService.dialPeer()
       │              │
       │              ├──────► P2PService.sendMessage() (3x retry)
       │              │
       │              └──────► P2PService.storeInInbox() (offline fallback)
       │
       ├──────► ChatMessageListener.incomingMessageStream (subscribe)
       │              │
       │              └──────► Filter by contactPeerId, update _messages
       │
       └──────► ChatMessageListener.contactUpdatedStream (subscribe)
                      │
                      └──────► Update _contact when username changes


  P2PServiceImpl
       │
       ├──────► P2PBridgeClient (all bridge calls)
       │              │
       │              └──────► GoBridgeClient.send()
       │                             │
       │                             └──────► [Go] Node Module (libp2p)
       │                                            │
       │                                            └──────► Rendezvous Server
       │
       ├──────► stateStream (broadcast NodeState changes)
       │
       ├──────► messageStream (broadcast incoming ChatMessages)
       │
       ├──────► _drainOfflineInbox() (on startNode, injects queued messages)
       │              │
       │              └──────► retrieveInbox()
       │                             │
       │                             └──────► callP2PInboxRetrieve()
       │
       └──────► storeInInbox() / retrieveInbox()
                      │
                      └──────► callP2PInboxStore() / callP2PInboxRetrieve()

```

---

## File Structure

```
lib/
├── main.dart                                    # App entry point, Firebase init, SecureKeyStore + encrypted DB setup (v8), secret migration, DI; MyApp = StatefulWidget + WidgetsBindingObserver (lifecycle, push listeners, orderly dispose)
├── smoke_test_main.dart                         # Smoke test entry point
├── smoke_test_restore.dart                      # Smoke test for identity restore
├── smoke_test_messages.dart                     # Smoke test for messages DB layer
├── core/
│   ├── bridge/
│   │   ├── bridge.dart                          # Bridge abstract interface (send, initialize, checkHealth, reinitialize, dispose, callbacks) + identity/crypto helper functions (callIdentityGenerate, callSignPayload, callVerifyPayload, callMlKemKeygen, callEncryptMessage, callDecryptMessage)
│   │   ├── go_bridge_client.dart               # GoBridgeClient: MethodChannel/EventChannel → Go native; _cmdMap maps cmd→MethodChannel method names
│   │   └── p2p_bridge_client.dart              # P2P-specific bridge calls (callP2PNodeStart/Stop/Status, rendezvous, peer, message, inbox) + defaultRendezvousAddress constant
│   ├── constants/
│   │   └── network_constants.dart              # Rendezvous address
│   ├── database/
│   │   ├── encrypted_db_opener.dart              # Opens SQLCipher DB with key from secure storage
│   │   ├── migrate_secrets_to_secure_storage.dart # One-time DB→secure storage migration
│   │   ├── migrations/
│   │   │   ├── 001_identity_table.dart         # Schema v1 (identity, contacts, contact_requests)
│   │   │   ├── 002_messages_table.dart         # Schema v2 (messages table + indexes)
│   │   │   ├── 003_mlkem_keys.dart             # Schema v3 (ML-KEM key columns on identity, contacts, contact_requests)
│   │   │   ├── 004_nullify_secret_columns.dart # Schema v4 (makes private_key, mnemonic12 nullable)
│   │   │   ├── 005_secret_null_checks.dart     # Schema v5 (CHECK constraints + avatar_blob BLOB)
│   │   │   ├── 006_read_at_column.dart         # Schema v6 (read_at TEXT on messages table)
│   │   │   ├── 007_archive_columns.dart        # Schema v7 (is_archived, archived_at on contacts)
│   │   │   └── 008_block_columns.dart          # Schema v8 (is_blocked, blocked_at on contacts)
│   │   └── helpers/
│   │       ├── identity_db_helpers.dart        # Identity DB CRUD
│   │       ├── contacts_db_helpers.dart        # Contacts DB CRUD
│   │       ├── contact_requests_db_helpers.dart # Contact Requests DB CRUD
│   │       └── messages_db_helpers.dart        # Messages DB CRUD
│   ├── secure_storage/
│   │   ├── secure_key_store.dart                 # SecureKeyStore abstract interface
│   │   └── flutter_secure_key_store.dart         # FlutterSecureKeyStore impl (iOS Keychain / Android EncryptedSharedPrefs)
│   ├── services/
│   │   ├── p2p_service.dart                    # P2PService abstract interface (incl. inbox, sendMessageWithReply, startNodeCore, warmBackground, isLocalPeer, sendLocalMessage)
│   │   ├── p2p_service_impl.dart               # P2PServiceImpl with streams, offline inbox drain, local WiFi discovery (mDNS/Bonsoir), periodic health check (30s)
│   │   ├── incoming_message_router.dart        # Routes P2P messages by type to streams
│   │   ├── pending_message_retrier.dart        # PendingMessageRetrier: subscribes to stateStream, retries failed messages on reconnect (5s debounce)
│   │   ├── chat_message_listener.dart          # Stub ChatMessageListener (core-level; real impl in features/conversation)
│   │   ├── contact_request_listener.dart       # Stub ContactRequestListener (core-level; real impl in features/contact_request)
│   │   └── chat_message.dart                   # ChatMessage type re-export
│   ├── theme/
│   │   ├── app_colors.dart                     # Color constants (Custom1 dark)
│   │   ├── app_theme.dart                      # ThemeData configuration
│   │   └── glassmorphism.dart                  # GlassmorphicContainer widget
│   ├── config/
│   │   └── startup_config.dart                 # StartupConfig class with deferredStartupMode flag
│   ├── local_discovery/
│   │   ├── local_discovery_service.dart        # LocalDiscoveryService abstract interface (mDNS)
│   │   ├── bonsoir_discovery_service.dart      # BonsoirDiscoveryService impl (Bonsoir mDNS)
│   │   ├── local_p2p_service.dart              # LocalP2PService: combines mDNS discovery + WebSocket
│   │   └── local_ws_server.dart                # LocalWsServer: local WebSocket server for WiFi peers
│   └── utils/
│       ├── flow_event_emitter.dart             # Logging utility
│       ├── key_conversion.dart                 # base64 ↔ hex conversion
│       ├── ring_avatar_spec.dart               # Ring avatar constants + data models
│       ├── ring_avatar_generator.dart          # Deterministic avatar from peerId
│       ├── chat_console_logger.dart           # Chat message debug logging + wire envelope logging
│       └── startup_timing.dart                # StartupTiming singleton for debug timing marks
│
├── features/
│   ├── home/
│   │   └── presentation/
│   │       ├── screens/
│   │       │   ├── first_time_experience_screen.dart   # Pure UI (animated)
│   │       │   └── first_time_experience_wired.dart    # Business logic + CR listener
│   │       └── widgets/
│   │           ├── profile_avatar_widget.dart          # Avatar + camera
│   │           ├── editable_username_widget.dart       # Tap-to-edit username
│   │           ├── qr_code_section.dart                # QR with glow
│   │           ├── scan_friend_card.dart               # Scan action card
│   │           ├── empty_circle_state.dart             # Pulsing circles
│   │           ├── ring_avatar.dart                    # RingAvatar widget
│   │           └── ring_avatar_painter.dart            # Canvas renderer
│   │
│   ├── feed/
│   │   ├── domain/
│   │   │   ├── models/
│   │   │   │   └── feed_item.dart              # FeedItem base + ConnectionFeedItem + MessageFeedItem + ThreadFeedItem + ThreadMessage
│   │   │   └── utils/
│   │   │       ├── format_message_time.dart    # Message timestamp formatting + formatRelativeTime()
│   │   │       ├── group_messages_into_threads.dart  # Groups incoming messages into ThreadFeedItems by contact and read session
│   │   │       └── has_significant_time_gap.dart     # Returns true if gap >= 2h or crosses AM/PM boundary
│   │   ├── application/
│   │   │   └── load_feed_use_case.dart         # Load initial feed from DB
│   │   └── presentation/
│   │       ├── screens/
│   │       │   ├── feed_screen.dart            # Pure UI feed display
│   │       │   └── feed_wired.dart             # Feed business logic + CR listener
│   │       ├── widgets/
│   │       │   ├── feed_header.dart            # Sticky header (username + avatar)
│   │       │   ├── feed_navigation_bar.dart    # Bottom glass nav bar (3 tabs)
│   │       │   ├── nav_bar_button.dart         # Individual nav button widget
│   │       │   ├── connection_card.dart        # Contact connection card
│   │       │   ├── message_feed_card.dart     # Incoming message card with reply
│   │       │   ├── message_bubble.dart        # Single message bubble within thread card
│   │       │   ├── thread_card.dart           # Thread card: grouped messages by contact
│   │       │   ├── session_divider.dart       # Session divider between message groups
│   │       │   ├── time_gap_divider.dart      # Time gap divider for significant pauses
│   │       │   ├── unread_count_badge.dart   # Circular unread count badge
│   │       │   └── checkmark_burst_animation.dart  # Animated checkmark
│   │       └── navigation/
│   │           └── feed_route_transition.dart   # Slide-up route transition
│   │
│   ├── conversation/
│   │   ├── domain/
│   │   │   ├── models/
│   │   │   │   ├── conversation_message.dart   # ConversationMessage model
│   │   │   │   └── message_payload.dart        # Wire-format envelope model
│   │   │   └── repositories/
│   │   │       ├── message_repository.dart     # Abstract interface
│   │   │       └── message_repository_impl.dart # DB-backed implementation
│   │   ├── application/
│   │   │   ├── send_chat_message_use_case.dart # Send: encrypt (v2) or plaintext (v1), 3x retry, inbox fallback
│   │   │   ├── handle_incoming_chat_message_use_case.dart  # Receive: decrypt v2 or parse v1
│   │   │   ├── load_conversation_use_case.dart # Load messages for contact
│   │   │   ├── mark_conversation_read_use_case.dart # Mark unread messages as read
│   │   │   ├── retry_failed_messages_use_case.dart  # Retry failed outgoing messages on reconnect
│   │   │   └── chat_message_listener.dart      # Background chat listener + ML-KEM decryption; rejects blocked contacts, suppresses UI for archived
│   │   └── presentation/
│   │       ├── screens/
│   │       │   ├── conversation_screen.dart    # Pure UI: letter cards, compose
│   │       │   └── conversation_wired.dart     # Business logic + optimistic UI
│   │       ├── widgets/
│   │       │   ├── letter_card.dart            # Full-width message card
│   │       │   ├── compose_area.dart           # Text field + send button
│   │       │   ├── empty_conversation_state.dart # Breathing glow empty state
│   │       │   ├── conversation_header.dart    # Frosted-glass header
│   │       │   ├── compact_origin_marker.dart  # Connection origin marker
│   │       │   ├── date_separator.dart         # Date divider
│   │       │   └── blocked_banner.dart         # Blocked contact banner with "Unblock" button
│   │       └── navigation/
│   │           └── conversation_route_transition.dart
│   │
│   ├── orbit/
│   │   ├── domain/
│   │   │   └── models/
│   │   │       └── orbit_friend.dart             # OrbitFriend composite model
│   │   ├── application/
│   │   │   └── load_orbit_data_use_case.dart     # Load contacts + message counts
│   │   └── presentation/
│   │       ├── screens/
│   │       │   ├── orbit_screen.dart             # Pure UI: orbital viz, friend list, search
│   │       │   └── orbit_wired.dart              # Business logic + 3 AnimationControllers
│   │       └── widgets/
│   │           ├── orbital_visualization.dart     # 320x320 Stack with ring painter + avatars
│   │           ├── orbital_ring_painter.dart      # CustomPainter: 2 dashed concentric circles
│   │           ├── orbital_avatar.dart            # Positioned avatar with staggered scale-in
│   │           ├── overflow_badge.dart            # "+N" badge with delayed entrance
│   │           ├── orbit_close_button.dart        # 36x36 glass circle X button
│   │           ├── orbit_header.dart              # Right-aligned 44px user RingAvatar
│   │           ├── friends_list_header.dart        # "Friends" title + QR/Scan pill buttons
│   │           ├── friend_row.dart                # Glassmorphic friend card
│   │           ├── swipeable_friend_row.dart      # Swipeable friend row with slide-to-reveal actions (Block/Delete/Archive)
│   │           ├── swipe_action_buttons.dart       # Block/Delete/Archive action buttons for swipe
│   │           ├── friends_filter_toggle.dart      # Segmented toggle "All (N)" / "Archived (N)"
│   │           ├── archived_empty_state.dart       # Empty state for archived contacts list
│   │           ├── confirmation_dialog.dart        # Confirmation dialog for destructive actions
│   │           ├── qr_action_cards.dart            # QR action cards (My QR / Scan QR)
│   │           ├── orbit_search_trigger.dart       # Floating glass pill search button
│   │           └── orbit_search_dock.dart          # Bottom-docked search TextField
│   │
│   ├── push/
│   │   ├── background_message_handler.dart         # @pragma('vm:entry-point') Firebase handler; defers inbox drain to next app resume
│   │   ├── request_push_permission.dart            # Requests notification permission
│   │   └── register_push_token.dart                # Registers FCM token via P2P inbox protocol
│   │
│   ├── identity/
│   │   ├── domain/
│   │   │   ├── models/
│   │   │   │   └── identity_model.dart         # IdentityModel class
│   │   │   └── repositories/
│   │   │       ├── identity_repository.dart    # Abstract interface
│   │   │       └── identity_repository_impl.dart
│   │   ├── application/
│   │   │   ├── startup_decision.dart           # decideStartupRoute() (3-way)
│   │   │   ├── generate_identity_use_case.dart
│   │   │   └── restore_identity_use_case.dart
│   │   └── presentation/
│   │       ├── startup_router.dart                     # Routes to feed, home, or onboarding
│   │       ├── screens/
│   │       │   ├── identity_choice_screen.dart
│   │       │   ├── identity_choice_wired.dart
│   │       │   ├── mnemonic_input_screen.dart
│   │       │   └── mnemonic_input_wired.dart
│   │       └── widgets/
│   │           ├── ambient_background.dart     # Animated glow background
│   │           ├── brand_header.dart           # Logo/title header
│   │           ├── choice_card.dart            # Glassmorphic tap card
│   │           └── identity_loading_card.dart  # Loading card during identity generation/restore
│   │
│   ├── qr_code/
│   │   ├── domain/
│   │   │   └── models/
│   │   │       └── qr_payload_model.dart
│   │   ├── application/
│   │   │   ├── build_qr_payload_use_case.dart  # Sign and build QR
│   │   │   └── parse_qr_payload_use_case.dart  # Validate scanned QR
│   │   └── presentation/
│   │       ├── screens/
│   │       │   ├── qr_display_screen.dart
│   │       │   ├── qr_display_wired.dart
│   │       │   ├── qr_scanner_screen.dart      # Camera scanner UI
│   │       │   └── qr_scanner_wired.dart       # Scanner business logic
│   │       └── widgets/
│   │           └── scan_overlay.dart            # Canvas scan overlay
│   │
│   ├── contacts/
│   │   ├── domain/
│   │   │   ├── models/
│   │   │   │   └── contact_model.dart          # ContactModel class
│   │   │   └── repositories/
│   │   │       ├── contact_repository.dart     # Abstract interface
│   │   │       └── contact_repository_impl.dart
│   │   └── application/
│   │       ├── add_contact_use_case.dart        # Add with duplicate check
│   │       ├── archive_contact_use_case.dart    # Archive contact
│   │       ├── unarchive_contact_use_case.dart  # Unarchive contact
│   │       ├── block_contact_use_case.dart      # Block contact
│   │       ├── unblock_contact_use_case.dart    # Unblock contact
│   │       └── delete_contact_use_case.dart     # Delete contact and messages
│   │
│   ├── contact_request/
│   │   ├── domain/
│   │   │   ├── models/
│   │   │   │   └── contact_request_model.dart  # ContactRequestModel + status enum
│   │   │   └── repositories/
│   │   │       ├── contact_request_repository.dart      # Abstract interface
│   │   │       └── contact_request_repository_impl.dart
│   │   ├── application/
│   │   │   ├── send_contact_request_use_case.dart       # Build, sign, discover, dial, send
│   │   │   ├── accept_contact_request_use_case.dart     # Request → contact
│   │   │   ├── decline_contact_request_use_case.dart    # Update status
│   │   │   ├── handle_incoming_message_use_case.dart    # Parse, validate, store
│   │   │   └── contact_request_listener.dart            # Background P2P listener
│   │   └── presentation/
│   │       └── widgets/
│   │           ├── contact_request_dialog.dart           # Accept/Decline modal
│   │           └── pending_requests_badge.dart           # Count badge
│   │
│   └── p2p/
│       ├── domain/
│       │   └── models/
│       │       ├── node_state.dart              # NodeState (isStarted, connections, etc.)
│       │       ├── connection_state.dart         # ConnectionState (peerId, direction)
│       │       ├── discovered_peer.dart          # DiscoveredPeer (id, addresses)
│       │       ├── chat_message.dart             # ChatMessage (from, to, content)
│       │       └── send_message_result.dart      # SendMessageResult class (sent, reply, acknowledged)
│       ├── application/
│       │   ├── start_node_use_case.dart          # Start node with identity
│       │   ├── stop_node_use_case.dart           # Stop running node
│       │   ├── send_message_use_case.dart        # Send P2P message
│       │   └── discover_peer_use_case.dart       # Discover + dial peer
│       └── presentation/
│           └── widgets/
│               └── connection_status_indicator.dart  # Online/Offline badge

go-mknoon/
├── Makefile                                    # Build targets: `make all` (iOS + Android), `make ios`, `make android`
├── go.mod / go.sum                             # Go module dependencies
├── bridge/
│   └── bridge.go                               # HandleCommand() dispatch → identity, crypto, node, inbox handlers
├── identity/
│   ├── generate.go                             # BIP39 mnemonic + Ed25519 keypair + ML-KEM-768 keygen
│   └── restore.go                              # Restore Ed25519 from mnemonic + fresh ML-KEM-768
├── crypto/
│   ├── mlkem.go                                # ML-KEM-768 keygen (circl/kem/mlkem768)
│   ├── encrypt.go                              # ML-KEM encapsulate + AES-256-GCM encrypt
│   └── decrypt.go                              # ML-KEM decapsulate + AES-256-GCM decrypt
├── node/
│   ├── node.go                                 # libp2p host lifecycle, chat protocol (/mknoon/chat/1.0.0), event broadcasting
│   ├── rendezvous.go                           # Rendezvous register/discover with protobuf signed peer records
│   └── inbox.go                                # Offline inbox protocol (/mknoon/inbox/1.0.0): store/retrieve/register FCM token
├── stub/
│   └── gosigar/                                # iOS stub for gosigar (libproc.h not available)
└── testdata/
    └── interop_vectors.json                    # Cross-platform test vectors for crypto interop

ios/
├── Runner/GoBridge.swift                       # iOS platform wrapper: MethodChannel + EventChannel → GoMknoon framework
└── Podfile                                     # CocoaPods config (includes GoMknoon.xcframework)

android/
└── app/src/main/kotlin/.../GoBridge.kt         # Android platform wrapper: MethodChannel + EventChannel → GoMknoon AAR

assets/
└── icons/
    ├── nav_feed.svg                             # Feed tab icon
    ├── nav_orbit.svg                            # Orbit/circle tab icon
    └── nav_remember.svg                         # Remember tab icon
```

---

## Data Flow Sequences

### Generate Identity Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    GENERATE IDENTITY - DATA FLOW                             │
└─────────────────────────────────────────────────────────────────────────────┘

  User                Flutter UI           Use Case          GoBridgeClient       Go Native Lib        Database
   │                      │                   │                   │                    │                   │
   │  Tap "I'm new"       │                   │                   │                    │                   │
   │─────────────────────>│                   │                   │                    │                   │
   │                      │                   │                   │                    │                   │
   │                      │  generateNew      │                   │                    │                   │
   │                      │  Identity()       │                   │                    │                   │
   │                      │──────────────────>│                   │                    │                   │
   │                      │                   │                   │                    │                   │
   │                      │                   │  callGenerate()   │                    │                   │
   │                      │                   │──────────────────>│                    │                   │
   │                      │                   │                   │                    │                   │
   │                      │                   │                   │  MethodChannel     │                   │
   │                      │                   │                   │  generateIdentity  │                   │
   │                      │                   │                   │───────────────────>│                   │
   │                      │                   │                   │                    │                   │
   │                      │                   │                   │                    │  bip39.generate() │
   │                      │                   │                   │                    │  ed25519.keypair()│
   │                      │                   │                   │                    │  mlkem768.keygen()│
   │                      │                   │                   │                    │  peerId.derive()  │
   │                      │                   │                   │                    │                   │
   │                      │                   │                   │  JSON response     │                   │
   │                      │                   │                   │  {ok, identity}    │                   │
   │                      │                   │                   │<───────────────────│                   │
   │                      │                   │                   │                    │                   │
   │                      │                   │  Map<identity>    │                    │                   │
   │                      │                   │<──────────────────│                    │                   │
   │                      │                   │                   │                    │                   │
   │                      │                   │  repo.save        │                    │                   │
   │                      │                   │  Identity()       │                    │                   │
   │                      │                   │─────────────────────────────────────────────────────────────>│
   │                      │                   │                   │                    │                   │
   │                      │                   │                   │                    │    INSERT OR      │
   │                      │                   │                   │                    │    REPLACE        │
   │                      │                   │                   │                    │    id=1           │
   │                      │                   │                   │                    │                   │
   │                      │  Result.success   │                   │                    │                   │
   │                      │<──────────────────│                   │                    │                   │
   │                      │                   │                   │                    │                   │
   │  Navigate to Home    │                   │                   │                    │                   │
   │<─────────────────────│                   │                   │                    │                   │
   │                      │                   │                   │                    │                   │
```

### QR Code Generation Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    QR CODE GENERATION - DATA FLOW                            │
└─────────────────────────────────────────────────────────────────────────────┘

  User                FTE Wired            Use Case          GoBridgeClient       Go Native Lib        Database
   │                      │                   │                   │                    │                   │
   │  Screen loads        │                   │                   │                    │                   │
   │─────────────────────>│                   │                   │                    │                   │
   │                      │                   │                   │                    │                   │
   │                      │  loadIdentity()   │                   │                    │                   │
   │                      │─────────────────────────────────────────────────────────────────────────────────>│
   │                      │                   │                   │                    │                   │
   │                      │  IdentityModel    │                   │                    │                   │
   │                      │<─────────────────────────────────────────────────────────────────────────────────│
   │                      │                   │                   │                    │                   │
   │                      │  buildQRPayload() │                   │                    │                   │
   │                      │──────────────────>│                   │                    │                   │
   │                      │                   │                   │                    │                   │
   │                      │                   │  Build unsigned   │                    │                   │
   │                      │                   │  payload JSON     │                    │                   │
   │                      │                   │  {ns,pk,rv,ts,un} │                    │                   │
   │                      │                   │                   │                    │                   │
   │                      │                   │  callSignPayload()│                    │                   │
   │                      │                   │──────────────────>│                    │                   │
   │                      │                   │                   │                    │                   │
   │                      │                   │                   │  MethodChannel     │                   │
   │                      │                   │                   │  signPayload       │                   │
   │                      │                   │                   │───────────────────>│                   │
   │                      │                   │                   │                    │                   │
   │                      │                   │                   │                    │  ed25519.sign()   │
   │                      │                   │                   │                    │                   │
   │                      │                   │                   │  {ok, signature}   │                   │
   │                      │                   │                   │<───────────────────│                   │
   │                      │                   │                   │                    │                   │
   │                      │                   │  Add sig to JSON  │                    │                   │
   │                      │                   │  Return final     │                    │                   │
   │                      │                   │                   │                    │                   │
   │                      │  QR JSON string   │                   │                    │                   │
   │                      │<──────────────────│                   │                    │                   │
   │                      │                   │                   │                    │                   │
   │  Display QR code     │                   │                   │                    │                   │
   │<─────────────────────│                   │                   │                    │                   │
   │                      │                   │                   │                    │                   │
```

### QR Scan → Add Contact → Send Request Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│              QR SCAN + CONTACT REQUEST - DATA FLOW                           │
└─────────────────────────────────────────────────────────────────────────────┘

  User          Scanner Wired     parseQR UC      addContact UC    sendRequest UC     P2PService
   │                 │                │                │                 │                 │
   │  Scan QR code   │                │                │                 │                 │
   │────────────────>│                │                │                 │                 │
   │                 │                │                │                 │                 │
   │                 │  parseQR       │                │                 │                 │
   │                 │  Payload()     │                │                 │                 │
   │                 │───────────────>│                │                 │                 │
   │                 │                │                │                 │                 │
   │                 │                │  Validate JSON │                 │                 │
   │                 │                │  Check fields  │                 │                 │
   │                 │                │  Check expiry  │                 │                 │
   │                 │                │  Verify sig    │                 │                 │
   │                 │                │  Check self    │                 │                 │
   │                 │                │                │                 │                 │
   │                 │  (success,     │                │                 │                 │
   │                 │   ContactModel)│                │                 │                 │
   │                 │<───────────────│                │                 │                 │
   │                 │                │                │                 │                 │
   │                 │  addContact()  │                │                 │                 │
   │                 │───────────────────────────────>│                 │                 │
   │                 │                │                │                 │                 │
   │                 │  success       │                │                 │                 │
   │                 │<───────────────────────────────│                 │                 │
   │                 │                │                │                 │                 │
   │  Show success   │                │                │                 │                 │
   │<────────────────│                │                │                 │                 │
   │                 │                │                │                 │                 │
   │                 │  sendContactRequest() (background)               │                 │
   │                 │─────────────────────────────────────────────────>│                 │
   │                 │                │                │                 │                 │
   │                 │                │                │                 │  Build payload  │
   │                 │                │                │                 │  Sign via Go    │
   │                 │                │                │                 │  Discover peer  │
   │                 │                │                │                 │───────────────>│
   │                 │                │                │                 │  (3x retry)    │
   │                 │                │                │                 │                 │
   │                 │                │                │                 │  Dial peer      │
   │                 │                │                │                 │───────────────>│
   │                 │                │                │                 │                 │
   │                 │                │                │                 │  Send message   │
   │                 │                │                │                 │───────────────>│
   │                 │                │                │                 │                 │
```

### Incoming Contact Request Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│              INCOMING CONTACT REQUEST - DATA FLOW                            │
└─────────────────────────────────────────────────────────────────────────────┘

  P2PService      CR Listener       handleMsg UC     CR Repository      FTE Wired        User
   │                   │                │                 │                 │                │
   │  messageStream    │                │                 │                 │                │
   │  (ChatMessage)    │                │                 │                 │                │
   │──────────────────>│                │                 │                 │                │
   │                   │                │                 │                 │                │
   │                   │  handleIncoming│                 │                 │                │
   │                   │  Message()     │                 │                 │                │
   │                   │───────────────>│                 │                 │                │
   │                   │                │                 │                 │                │
   │                   │                │  Parse JSON     │                 │                │
   │                   │                │  Check type =   │                 │                │
   │                   │                │  contact_request│                 │                │
   │                   │                │  Validate fields│                 │                │
   │                   │                │  Verify sig     │                 │                │
   │                   │                │  Check not self │                 │                │
   │                   │                │  Check not dup  │                 │                │
   │                   │                │                 │                 │                │
   │                   │                │  Store request  │                 │                │
   │                   │                │────────────────>│                 │                │
   │                   │                │                 │                 │                │
   │                   │  (contactReq,  │                 │                 │                │
   │                   │   Model)       │                 │                 │                │
   │                   │<───────────────│                 │                 │                │
   │                   │                │                 │                 │                │
   │                   │  requestStream │                 │                 │                │
   │                   │  .add(model)   │                 │                 │                │
   │                   │───────────────────────────────────────────────────>│                │
   │                   │                │                 │                 │                │
   │                   │                │                 │                 │  Show dialog   │
   │                   │                │                 │                 │  (Accept/      │
   │                   │                │                 │                 │   Decline)     │
   │                   │                │                 │                 │───────────────>│
   │                   │                │                 │                 │                │
   │                   │                │                 │                 │  User taps     │
   │                   │                │                 │                 │  Accept        │
   │                   │                │                 │                 │<───────────────│
   │                   │                │                 │                 │                │
   │                   │                │                 │  acceptCR()     │                │
   │                   │                │                 │<────────────────│                │
   │                   │                │                 │                 │                │
   │                   │                │                 │  → Contact      │                │
   │                   │                │                 │  → status=      │                │
   │                   │                │                 │    accepted     │                │
   │                   │                │                 │                 │                │
```

### Send Chat Message Flow (with E2E Encryption + Offline Inbox)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│              SEND CHAT MESSAGE - DATA FLOW (v2 encrypted / v1 fallback)      │
└─────────────────────────────────────────────────────────────────────────────┘

  User          Conv Wired      sendChatMsg UC   GoBridge      MessageRepo     P2PService
   │                 │                │              │              │                │
   │  Type + Send    │                │              │              │                │
   │────────────────>│                │              │              │                │
   │                 │                │              │              │                │
   │  Optimistic UI  │  Build         │              │              │                │
   │  (status:       │  MessagePayload│              │              │                │
   │   sending)      │  {id,text,     │              │              │                │
   │<────────────────│  sender,ts}    │              │              │                │
   │                 │                │              │              │                │
   │                 │  sendChat      │              │              │                │
   │                 │  Message()     │              │              │                │
   │                 │───────────────>│              │              │                │
   │                 │                │              │              │                │
   │                 │                │  saveMessage()│              │                │
   │                 │                │  (status:sent)│              │                │
   │                 │                │──────────────────────────────>│                │
   │                 │                │              │              │                │
   │                 │                │  [if contact has ML-KEM key]  │                │
   │                 │                │  callEncrypt │              │                │
   │                 │                │  Message()   │              │                │
   │                 │                │─────────────>│              │                │
   │                 │                │              │  ML-KEM-768  │                │
   │                 │                │              │  encapsulate │                │
   │                 │                │              │  + AES-256-  │                │
   │                 │                │              │  GCM encrypt │                │
   │                 │                │  {kem,cipher │              │                │
   │                 │                │   text,nonce}│              │                │
   │                 │                │<─────────────│              │                │
   │                 │                │              │              │                │
   │                 │                │  Build v2 envelope            │                │
   │                 │                │  (encrypted)  │              │                │
   │                 │                │              │              │                │
   │                 │                │  [else: no ML-KEM key]       │                │
   │                 │                │  Build v1 envelope            │                │
   │                 │                │  (plaintext)  │              │                │
   │                 │                │              │              │                │
   │                 │                │  discoverPeer()               │                │
   │                 │                │──────────────────────────────────────────────>│
   │                 │                │  (3x retry)  │              │                │
   │                 │                │              │              │                │
   │                 │                │  dialPeer()  │              │                │
   │                 │                │──────────────────────────────────────────────>│
   │                 │                │              │              │                │
   │                 │                │  sendMessage()│              │                │
   │                 │                │  (JSON envelope)             │                │
   │                 │                │──────────────────────────────────────────────>│
   │                 │                │              │              │                │
   │                 │                │  [if send succeeds]          │                │
   │                 │                │  updateStatus()              │                │
   │                 │                │  (delivered) │              │                │
   │                 │                │──────────────────────────────>│                │
   │                 │                │              │              │                │
   │                 │                │  [if send fails after 3x retry]               │
   │                 │                │  storeInInbox()              │                │
   │                 │                │──────────────────────────────────────────────>│
   │                 │                │              │              │                │
   │                 │                │  [if inbox store succeeds]   │                │
   │                 │                │  updateStatus()              │                │
   │                 │                │  (delivered) │              │                │
   │                 │                │──────────────────────────────>│                │
   │                 │                │              │              │                │
   │                 │  Result +      │              │              │                │
   │                 │  status update │              │              │                │
   │                 │<───────────────│              │              │                │
   │                 │                │              │              │                │
   │  Update tick    │                │              │              │                │
   │  (delivered)    │                │              │              │                │
   │<────────────────│                │              │              │                │
   │                 │                │              │              │                │
```

### Incoming Chat Message Flow (with E2E Decryption)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│              INCOMING CHAT MESSAGE - DATA FLOW (v2 decrypt / v1 parse)        │
└─────────────────────────────────────────────────────────────────────────────┘

  P2PService     Msg Router     Chat Listener    handleMsg UC    GoBridge     Conv Wired     User
   │                │                │                │              │            │           │
   │  messageStream │                │                │              │            │           │
   │  (ChatMessage) │                │                │              │            │           │
   │───────────────>│                │                │              │            │           │
   │                │                │                │              │            │           │
   │                │  _route():     │                │              │            │           │
   │                │  type=chat_msg │                │              │            │           │
   │                │  chatMessage   │                │              │            │           │
   │                │  Stream.add()  │                │              │            │           │
   │                │───────────────>│                │              │            │           │
   │                │                │                │              │            │           │
   │                │                │  Resolve own   │              │            │           │
   │                │                │  ML-KEM secret │              │            │           │
   │                │                │  key from repo │              │            │           │
   │                │                │                │              │            │           │
   │                │                │  handleIncoming│              │            │           │
   │                │                │  ChatMessage() │              │            │           │
   │                │                │───────────────>│              │            │           │
   │                │                │                │              │            │           │
   │                │                │                │  Detect v2?  │            │           │
   │                │                │                │  parseEncrypt│            │           │
   │                │                │                │  edEnvelope()│            │           │
   │                │                │                │              │            │           │
   │                │                │                │  [if v2 encrypted]        │           │
   │                │                │                │  callDecrypt              │           │
   │                │                │                │  Message()   │            │           │
   │                │                │                │─────────────>│            │           │
   │                │                │                │              │ ML-KEM-768 │           │
   │                │                │                │              │ decapsulate│           │
   │                │                │                │              │ + AES-256- │           │
   │                │                │                │              │ GCM decrypt│           │
   │                │                │                │  {plaintext} │            │           │
   │                │                │                │<─────────────│            │           │
   │                │                │                │              │            │           │
   │                │                │                │  fromDecrypt │            │           │
   │                │                │                │  edJson()    │            │           │
   │                │                │                │              │            │           │
   │                │                │                │  [else: v1 plaintext]     │           │
   │                │                │                │  fromJson()  │            │           │
   │                │                │                │              │            │           │
   │                │                │                │  Validate    │            │           │
   │                │                │                │  sender is   │            │           │
   │                │                │                │  contact     │            │           │
   │                │                │                │  Check dup   │            │           │
   │                │                │                │  Detect name │            │           │
   │                │                │                │  change      │            │           │
   │                │                │                │  Save message│            │           │
   │                │                │                │              │            │           │
   │                │                │  (chatMessage, │              │            │           │
   │                │                │   Model)       │              │            │           │
   │                │                │<───────────────│              │            │           │
   │                │                │                │              │            │           │
   │                │                │  incoming      │              │            │           │
   │                │                │  MessageStream │              │            │           │
   │                │                │  .add(msg)     │              │            │           │
   │                │                │──────────────────────────────────────────>│           │
   │                │                │                │              │            │           │
   │                │                │                │              │            │  New       │
   │                │                │                │              │            │  letter    │
   │                │                │                │              │            │  card      │
   │                │                │                │              │            │──────────>│
   │                │                │                │              │            │           │
```

### Avatar Upload Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    AVATAR UPLOAD - DATA FLOW                                 │
│              (No file written to disk — avatar stored as BLOB in DB)         │
└─────────────────────────────────────────────────────────────────────────────┘

  User                FTE Wired           ImagePicker          SQLCipher Database
   │                      │                   │                       │
   │  Tap camera button   │                   │                       │
   │─────────────────────>│                   │                       │
   │                      │                   │                       │
   │                      │  Show bottom      │                       │
   │                      │  sheet picker     │                       │
   │                      │                   │                       │
   │  Select "Gallery"    │                   │                       │
   │─────────────────────>│                   │                       │
   │                      │                   │                       │
   │                      │  pickImage()      │                       │
   │                      │──────────────────>│                       │
   │                      │                   │                       │
   │  Select photo        │                   │                       │
   │─────────────────────>│                   │                       │
   │                      │                   │                       │
   │                      │  XFile (temp)     │                       │
   │                      │<──────────────────│                       │
   │                      │                   │                       │
   │                      │  Read bytes       │                       │
   │                      │  (Uint8List)      │                       │
   │                      │                   │                       │
   │                      │  Update identity with avatarBlob          │
   │                      │  saveIdentity()                           │
   │                      │  (BLOB stored in encrypted DB)            │
   │                      │──────────────────────────────────────────>│
   │                      │                   │                       │
   │                      │  setState()       │                       │
   │                      │  Image.memory()   │                       │
   │                      │                   │                       │
   │  Display avatar      │                   │                       │
   │<─────────────────────│                   │                       │
   │                      │                   │                       │
```

### Orbit Navigation Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│              ORBIT NAVIGATION - DATA FLOW                                    │
└─────────────────────────────────────────────────────────────────────────────┘

  User          FeedWired       OrbitWired       loadOrbitData UC   MessageRepo     ContactRepo
   │                │                │                │                │               │
   │  Tap "Orbit"   │                │                │                │               │
   │  in nav bar    │                │                │                │               │
   │───────────────>│                │                │                │               │
   │                │                │                │                │               │
   │                │  Navigator     │                │                │               │
   │                │  .push(        │                │                │               │
   │                │  OrbitWired)   │                │                │               │
   │                │───────────────>│                │                │               │
   │                │                │                │                │               │
   │                │                │  loadOrbit     │                │               │
   │                │                │  Data()        │                │               │
   │                │                │───────────────>│                │               │
   │                │                │                │                │               │
   │                │                │                │  getAllContacts()               │
   │                │                │                │───────────────────────────────>│
   │                │                │                │                │               │
   │                │                │                │  List<Contact> │               │
   │                │                │                │<───────────────────────────────│
   │                │                │                │                │               │
   │                │                │                │  For each contact:             │
   │                │                │                │  getMessageCount               │
   │                │                │                │  ForContact()  │               │
   │                │                │                │───────────────>│               │
   │                │                │                │                │               │
   │                │                │                │  count (int)   │               │
   │                │                │                │<───────────────│               │
   │                │                │                │                │               │
   │                │                │                │  Sort by count │               │
   │                │                │                │  desc, build   │               │
   │                │                │                │  OrbitFriends  │               │
   │                │                │                │                │               │
   │                │                │  List<OrbitFriend>              │               │
   │                │                │<───────────────│                │               │
   │                │                │                │                │               │
   │  Show orbital  │                │  Render:       │                │               │
   │  visualization │                │  Ring 1 (top 5)│                │               │
   │  + friend list │                │  Ring 2 (next 8)               │               │
   │<────────────────────────────────│  Friend list   │                │               │
   │                │                │                │                │               │
   │                │                │                │                │               │
   │  Tap friend    │                │                │                │               │
   │───────────────────────────────>│                │                │               │
   │                │                │                │                │               │
   │                │                │  Navigator     │                │               │
   │                │                │  .push(        │                │               │
   │                │                │  ConvWired)    │                │               │
   │                │                │───────────────>│                │               │
   │                │                │                │                │               │
   │                │                │                │                │               │
   │  Type search   │                │                │                │               │
   │  query         │                │                │                │               │
   │───────────────────────────────>│                │                │               │
   │                │                │                │                │               │
   │                │                │  Filter        │                │               │
   │                │                │  _orbitFriends │                │               │
   │                │                │  by username   │                │               │
   │                │                │  match         │                │               │
   │                │                │                │                │               │
   │  Filtered list │                │                │                │               │
   │<────────────────────────────────│                │                │               │
   │                │                │                │                │               │
   │                │                │                │                │               │
   │  Tap X button  │                │                │                │               │
   │───────────────────────────────>│                │                │               │
   │                │                │                │                │               │
   │                │                │  Navigator     │                │               │
   │                │                │  .pop()        │                │               │
   │                │  <─────────────│                │                │               │
   │                │                │                │                │               │
   │  Back to Feed  │                │                │                │               │
   │<───────────────│                │                │                │               │
   │                │                │                │                │               │
```

---

## Dependencies

### Flutter Packages (pubspec.yaml)

| Package | Purpose |
|---------|---------|
| sqflite_sqlcipher | SQLCipher encrypted database access (replaces plain sqflite) |
| flutter_secure_storage | OS-backed secure key-value storage (iOS Keychain / Android EncryptedSharedPreferences) |
| qr_flutter | QR code generation widget |
| mobile_scanner | Camera-based QR code scanning |
| image_picker | Camera/gallery image selection |
| path_provider | App documents directory access |
| cupertino_icons | iOS-style icons |
| firebase_core | Firebase initialization |
| firebase_messaging | Push notifications (FCM) |
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
| github.com/tyler-smith/go-bip39 | BIP39 mnemonic phrase generation |
| github.com/cloudflare/circl | ML-KEM-768 (FIPS 203) post-quantum key encapsulation |
| crypto/ed25519 (stdlib) | Ed25519 signing & verification |
| crypto/aes + crypto/cipher (stdlib) | AES-256-GCM symmetric encryption |
| golang.org/x/mobile/bind | gomobile framework binding (iOS .xcframework + Android .aar) |

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
    ├─► openEncryptedDatabase('identity.db', version: 8, secureKeyStore)
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
    │       │       ├─► runNullifySecretColumnsMigration(db)
    │       │       │       Makes private_key, mnemonic12 nullable (v4)
    │       │       │
    │       │       ├─► runSecretNullChecksMigration(db)
    │       │       │       CHECK constraints + avatar_blob BLOB column (v5)
    │       │       │
    │       │       ├─► runReadAtColumnMigration(db)
    │       │       │       Adds read_at TEXT column to messages (v6)
    │       │       │
    │       │       ├─► runArchiveColumnsMigration(db)
    │       │       │       Adds is_archived, archived_at to contacts (v7)
    │       │       │
    │       │       └─► runBlockColumnsMigration(db)
    │       │               Adds is_blocked, blocked_at to contacts (v8)
    │       │
    │       └─► onUpgrade callback (v1→v2→v3→v4→v5→v6→v7→v8)
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
    │               └─► runBlockColumnsMigration(db)               (v7 → v8)
    │                       Adds is_blocked, blocked_at to contacts
    │
    ├─► migrateSecretsToSecureStorage(db, secureKeyStore)
    │       One-time migration: reads secrets from DB, writes to SecureKeyStore
    │       Sets secrets_migrated sentinel in secure storage
    │       Nullifies DB secret columns after successful migration
    │
    ├─► Repository instantiation (4 repositories)
    │       │
    │       ├─► IdentityRepositoryImpl (dbLoad, dbUpsert, secureKeyStore)
    │       │
    │       ├─► ContactRepositoryImpl (12 db helper functions)
    │       │
    │       ├─► ContactRequestRepositoryImpl (6 db helper functions)
    │       │
    │       └─► MessageRepositoryImpl (13 db helper functions)
    │
    ├─► GoBridgeClient instantiation + initialize()
    │       │
    │       └─► Sets up MethodChannel + EventChannel to Go native library
    │           via platform wrappers (GoBridge.swift / GoBridge.kt)
    │           Registers event handlers (messages, peer events)
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
    │           contactRequestStream, chatMessageStream, unknownStream
    │
    ├─► ContactRequestListener instantiation + start()
    │       │
    │       └─► Subscribes to messageRouter.contactRequestStream
    │           Monitors for incoming contact requests
    │           Broadcasts to requestStream for UI
    │
    ├─► ChatMessageListener instantiation + start()
    │       │
    │       └─► Subscribes to messageRouter.chatMessageStream
    │           Monitors for incoming chat messages
    │           Rejects messages from blocked contacts
    │           Suppresses UI notifications for archived contacts
    │           Broadcasts to incomingMessageStream + contactUpdatedStream
    │
    ├─► PendingMessageRetrier instantiation + start()
    │       │
    │       └─► Subscribes to P2PService.stateStream
    │           Detects online transitions, 5s debounce
    │           Calls retryFailedMessages() on reconnect
    │
    └─► runApp(MyApp) — StatefulWidget + WidgetsBindingObserver
            │
            ├─► Constructor params: messageRouter, pendingMessageRetrier, isDesktop, + all existing deps
            │
            ├─► _onResumed() lifecycle handler (app foreground):
            │       │
            │       ├─► bridge.checkHealth()
            │       │
            │       ├─► [dead] bridge.reinitialize()
            │       │
            │       ├─► p2pService.performImmediateHealthCheck()
            │       │
            │       └─► p2pService.drainOfflineInbox()
            │
            ├─► _setupForegroundPushListener():
            │       │
            │       ├─► FirebaseMessaging.onMessage → drainOfflineInbox()
            │       │
            │       └─► FirebaseMessaging.onMessageOpenedApp → drainOfflineInbox()
            │
            ├─► dispose() orderly teardown:
            │       pendingMessageRetrier → chatMessageListener →
            │       contactRequestListener → messageRouter →
            │       p2pService → bridge
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
                    └─► [needsIdentity] → Navigate to IdentityChoiceWired
```

### Initialization Files

| File | Responsibility |
|------|----------------|
| `lib/main.dart` | Entry point, Firebase init, SecureKeyStore + encrypted DB setup (v8), secret migration, repository + service + listener + PendingMessageRetrier DI; MyApp is StatefulWidget + WidgetsBindingObserver with app-resume lifecycle (bridge health check → reinitialize if dead → P2P health check → drain inbox), foreground push listeners (Firebase onMessage/onMessageOpenedApp → inbox drain), and orderly dispose chain (pendingMessageRetrier → chatMessageListener → contactRequestListener → messageRouter → p2pService → bridge) |
| `lib/core/secure_storage/secure_key_store.dart` | SecureKeyStore abstract interface |
| `lib/core/secure_storage/flutter_secure_key_store.dart` | FlutterSecureKeyStore production impl (iOS Keychain / Android EncryptedSharedPreferences) |
| `lib/core/database/encrypted_db_opener.dart` | Opens SQLCipher DB with key from secure storage; handles plaintext-to-encrypted migration |
| `lib/core/database/migrate_secrets_to_secure_storage.dart` | One-time DB-to-secure-storage secret migration with sentinel |
| `lib/core/database/migrations/001_identity_table.dart` | Schema v1 migration (3 tables) |
| `lib/core/database/migrations/002_messages_table.dart` | Schema v2 migration (messages table) |
| `lib/core/database/migrations/003_mlkem_keys.dart` | Schema v3 migration (ML-KEM key columns on identity, contacts, contact_requests) |
| `lib/core/database/migrations/004_nullify_secret_columns.dart` | Schema v4 migration (makes private_key, mnemonic12 nullable) |
| `lib/core/database/migrations/005_secret_null_checks.dart` | Schema v5 migration (CHECK constraints enforcing secret columns NULL + avatar_blob BLOB) |
| `lib/core/database/migrations/006_read_at_column.dart` | Schema v6 migration (read_at TEXT column on messages table) |
| `lib/core/database/migrations/007_archive_columns.dart` | Schema v7 migration (is_archived, archived_at on contacts table) |
| `lib/core/database/migrations/008_block_columns.dart` | Schema v8 migration (is_blocked, blocked_at on contacts table) |
| `lib/core/services/incoming_message_router.dart` | P2P message routing by type |
| `lib/core/services/pending_message_retrier.dart` | Retries failed outgoing messages on P2P reconnect (5s debounce) |
| `lib/core/bridge/go_bridge_client.dart` | Go native bridge initialization + event handlers (MethodChannel/EventChannel) |
| `lib/core/services/p2p_service_impl.dart` | P2P service initialization |
| `lib/features/contact_request/application/contact_request_listener.dart` | Background contact request listener startup |
| `lib/features/conversation/application/chat_message_listener.dart` | Background chat message listener startup |
| `lib/features/identity/presentation/startup_router.dart` | Route decision logic + push token registration |
| `lib/features/identity/application/startup_decision.dart` | Business logic for routing |
| `lib/features/push/background_message_handler.dart` | Firebase background message handler; logs with `note: 'inbox drain deferred to next app resume'` |
| `lib/features/push/request_push_permission.dart` | Push notification permission request |
| `lib/features/push/register_push_token.dart` | FCM token registration via P2P inbox protocol |

### Adding New Initialization Steps

To add a new initialization step:
1. Add async initialization code in `main()` before `runApp()`
2. Inject dependencies into `MyApp` constructor
3. Pass dependencies through `StartupRouter` to child widgets
4. For new migrations, create `009_*.dart` and update `openEncryptedDatabase` version (currently v8)
5. For new P2P event handlers, register on `GoBridgeClient` in `P2PServiceImpl`
6. For new secrets, add read/write methods to `SecureKeyStore` and update `FlutterSecureKeyStore`

---

## Networking & Integration Points

### Current State (P2P Active)

The application has **active P2P networking** via the Go native library. Identity and cryptographic operations happen locally, while peer discovery and messaging use the rendezvous/relay server. Local WiFi discovery (mDNS via Bonsoir) provides an additional direct connectivity path.

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
                         │   │  • Offline inbox fallback   │   │
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

Contact requests are sent as structured P2P messages:

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
| `node:start` | `startNode` | Node module | Start libp2p node with relay, auto-register |
| `node:stop` | `stopNode` | Node module | Stop libp2p node |
| `node:status` | `nodeStatus` | Node module | Get node status (peerId, connections, isStarted) |
| `rendezvous:register` | `rendezvousRegister` | Rendezvous module | Register peer with signed peer record |
| `rendezvous:discover` | `rendezvousDiscover` | Rendezvous module | Discover peers by namespace |
| `peer:dial` | `dialPeer` | Node module | Dial peer by ID and optional addresses |
| `peer:disconnect` | `disconnectPeer` | Node module | Disconnect from peer |
| `message:send` | `sendMessage` | Node module | Send message via /mknoon/chat/1.0.0 (frame-based with ACK) |
| `inbox:store` | `inboxStore` | Inbox module | Store message in offline inbox on relay |
| `inbox:retrieve` | `inboxRetrieve` | Inbox module | Retrieve messages from offline inbox |
| `inbox:register_token` | `inboxRegisterToken` | Inbox module | Register FCM device token for push notifications |
