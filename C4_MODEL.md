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
                                       │ WebSocket (libp2p)
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
| Mknoon Identity App | Software System | Mobile/desktop app for identity management, profile customization, peer discovery, contact requests, E2E encrypted conversations (ML-KEM-768 + AES-256-GCM), offline inbox, push notifications (Firebase Cloud Messaging), and P2P messaging using libp2p and BIP39. Data at rest encrypted via SQLCipher + OS-backed secure storage |
| Rendezvous / Relay Server | External System | libp2p rendezvous server for peer discovery, circuit relay for NAT traversal, and offline message inbox (`/mknoon/inbox/1.0.0`) for store-and-forward delivery |

### External Dependencies
- Rendezvous/Relay server at `mknoun.xyz:4001` (WebSocket over TLS)
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
│     └──────────────┬──────────────────┬──────────────┬──────────────┘     │
│  │                 │                  │              │                 │  │
│                    │ JSON/WebView     │ SQL queries  │ Keychain/        │
│  │                 │ Channel          │              │ Keystore        │  │
│                    ▼                  ▼              ▼                   │
│  │  ┌─────────────────────────┐ ┌─────────────────────┐ ┌────────────┐│  │
│     │  JavaScript Runtime     │ │  SQLCipher Database  │ │  Secure    │   │
│  │  │  [Container: WebView]   │ │  [Container:         │ │  Storage   ││  │
│     │                         │ │  sqflite_sqlcipher]  │ │  [Container│   │
│  │  │  • BIP39 mnemonic gen   │ │                      │ │  flutter_  ││  │
│     │  • Ed25519 keypair      │ │  • identity table    │ │  secure_   │   │
│  │  │  • ML-KEM-768 keygen   │ │  • contacts table    │ │  storage]  ││  │
│     │  • libp2p peer ID       │ │  • contact_requests  │ │            │   │
│  │  │  • Payload signing      │ │  • messages table    │ │ • private  ││  │
│     │  • Message encrypt/     │ │  • avatar BLOB store │ │   _key     │   │
│  │  │    decrypt              │ │  • 256-bit AES       │ │ • mnemonic ││  │
│     │  • P2P node management  │ │    encrypted         │ │   12       │   │
│  │  │  • Peer discovery &     │ │                      │ │ • ml_kem_  ││  │
│     │    relay                │ │                      │ │   secret   │   │
│  │  │  • Message send/receive │ │                      │ │ • db_enc   ││  │
│     │  • Offline inbox store/ │ │                      │ │   _key     │   │
│  │  │    retrieve             │ │                      │ │            ││  │
│     └──────────────┬──────────┘ └──────────────────────┘ └────────────┘   │
│  │                 │                                                   │  │
│                    │ WebSocket/libp2p                                     │
│  │                 │                                                   │  │
│  └ ─ ─ ─ ─ ─ ─ ─ ─┼─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘  │
│                    │                                                      │
└────────────────────┼─────────────────────────────────────────────────────┘
                     │
                     │ WebSocket (libp2p relay)
                     ▼
              ┌─────────────────────────────┐
              │   Rendezvous / Relay Server │
              │   mknoun.xyz:4001           │
              └─────────────────────────────┘
```

### Containers

| Container | Technology | Description |
|-----------|------------|-------------|
| Flutter Application | Dart/Flutter | Main application with UI, business logic, P2P service, and data access |
| JavaScript Runtime | WebView + esbuild bundle | Executes crypto operations and P2P networking using libp2p libraries |
| SQLCipher Database | sqflite_sqlcipher | 256-bit AES encrypted SQLite database; persists identity, contacts, contact requests, messages, and avatar BLOBs locally |
| Secure Storage | flutter_secure_storage | OS-backed secret storage: iOS Keychain (device-bound, kSecAttrAccessibleWhenUnlockedThisDeviceOnly), Android EncryptedSharedPreferences; holds identity secrets and DB encryption key |
| Rendezvous / Relay Server | libp2p | External server for peer discovery, NAT traversal relay, and offline message inbox |
| Firebase Cloud Messaging | Firebase SDK | External push notification service; relay server sends FCM push when storing offline inbox messages |

### Communication

| From | To | Protocol | Description |
|------|-----|----------|-------------|
| Flutter App | JS Runtime | JSON via JavaScriptChannel | Request/response for identity, signing, and P2P operations |
| Flutter App | SQLCipher DB | SQL via sqflite_sqlcipher | CRUD operations for identity, contacts, contact requests, messages, and avatar BLOBs (256-bit AES encrypted at rest) |
| Flutter App | Secure Storage | flutter_secure_storage API | Read/write identity secrets (private_key, mnemonic12, ml_kem_secret_key) and DB encryption key |
| JS Runtime | Rendezvous Server | WebSocket (libp2p) | Peer discovery, relay circuits, messaging, and offline inbox protocol (`/mknoon/inbox/1.0.0`) |
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
│  │  │  │  │FriendsListHead.│  │FriendRow +     │  │OrbitSearch │  │   │  │ │
│  │  │  │  │(QR/Scan pills) │  │AnimatedFriend  │  │Trigger     │  │   │  │ │
│  │  │  │  └────────────────┘  └────────────────┘  └────────────┘  │   │  │ │
│  │  │  │  ┌────────────────┐                                      │   │  │ │
│  │  │  │  │OrbitSearchDock │                                      │   │  │ │
│  │  │  │  │(bottom search) │                                      │   │  │ │
│  │  │  │  └────────────────┘                                      │   │  │ │
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
│  │  ┌──────────────────┐                                                 │ │
│  │  │ addContact()     │  Adds contact from QR scan                      │ │
│  │  │ [Use Case]       │                                                 │ │
│  │  └──────────────────┘                                                 │ │
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
│  │  │     WebViewJsBridge      │  │     P2PBridgeClient              │   │ │
│  │  │     [Bridge Client]      │  │     [Bridge Client]              │   │ │
│  │  └──────────────────────────┘  └──────────────────────────────────┘   │ │
│  │  ┌──────────────────────────┐                                         │ │
│  │  │   JsBridgeClient         │  Identity + signing bridge helpers      │ │
│  │  │   [Bridge Helpers]       │                                         │ │
│  │  └──────────────────────────┘                                         │ │
│  │                                                                        │ │
│  │  ── Services ──────────────────────────────────────────────────────── │ │
│  │  ┌──────────────────────────────────────────┐                         │ │
│  │  │   P2PService [Interface] → P2PServiceImpl│                         │ │
│  │  │   Reactive streams for state + messages  │                         │ │
│  │  │   + offline inbox store/retrieve         │                         │ │
│  │  │   + registerInboxToken (FCM push)        │                         │ │
│  │  │   + performImmediateHealthCheck()        │                         │ │
│  │  │   + drainOfflineInbox()                  │                         │ │
│  │  └──────────────────────────────────────────┘                         │ │
│  │  ┌──────────────────────────────────────────┐                         │ │
│  │  │   IncomingMessageRouter                  │                         │ │
│  │  │   Routes P2P msgs → typed streams        │                         │ │
│  │  │   (contactRequest, chatMessage, unknown)  │                         │ │
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
│     JAVASCRIPT RUNTIME           │  │      SQLCIPHER DATABASE              │
│     [WebView Container]          │  │    [sqflite_sqlcipher Container]     │
│                                  │  │                                      │
│  ┌────────────────────────────┐  │  │  ┌────────────────────────────────┐  │
│  │      Bridge Entry          │  │  │  │        identity table          │  │
│  │      [Handler Router]      │  │  │  │                                │  │
│  │                            │  │  │  │  id INTEGER PRIMARY KEY        │  │
│  │  handleBridgeMessage()     │  │  │  │  peer_id TEXT NOT NULL         │  │
│  │  sendToFlutter(response)   │  │  │  │  public_key TEXT NOT NULL      │  │
│  └──────────┬─────────────────┘  │  │  │  private_key TEXT              │  │
│             │                    │  │  │   CHECK(private_key IS NULL)  │  │
│  ┌──────────┴─────────────────┐  │  │  │  mnemonic12 TEXT              │  │
│  │    Handlers                │  │  │  │   CHECK(mnemonic12 IS NULL)   │  │
│  │                            │  │  │  │  username TEXT NOT NULL        │  │
│  │  identity.generate         │  │  │  │  avatar_path TEXT              │  │
│  │  identity.restore          │  │  │  │  avatar_blob BLOB (v5)       │  │
│  │  payload.sign              │  │  │  │  created_at TEXT NOT NULL      │  │
│  │  mlkem.keygen              │  │  │  │  updated_at TEXT NOT NULL      │  │
│  │  message.encrypt           │  │  │  │  ml_kem_public_key TEXT (v3)  │  │
│  │  message.decrypt           │  │  │  │  ml_kem_secret_key TEXT       │  │
│                                  │  │  │   CHECK(..IS NULL) (v5)      │  │
│  ┌────────────────────────────┐  │  │  │  Constraint: id = 1 always     │  │
│  │    Identity Module         │  │  │  │  Secrets → Secure Storage      │  │
│  │                            │  │  │  └────────────────────────────────┘  │
│  │  generateIdentity()        │  │  │                                      │
│  │  restoreFromMnemonic()     │  │  │                                      │
│  └────────────────────────────┘  │  │  ┌────────────────────────────────┐  │
│                                  │  │  │        contacts table          │  │
│                                  │  │  │                                │  │
│  ┌────────────────────────────┐  │  │  │  peer_id TEXT PRIMARY KEY      │  │
│  │    Signing Module          │  │  │  │  public_key TEXT NOT NULL      │  │
│  │                            │  │  │  │  rendezvous TEXT NOT NULL      │  │
│  │  signPayload()             │  │  │  │  username TEXT NOT NULL        │  │
│  │                            │  │  │  │  signature TEXT NOT NULL       │  │
│  │  Uses:                     │  │  │  │  scanned_at TEXT NOT NULL      │  │
│  │  • @noble/ed25519          │  │  │  │  avatar_path TEXT              │  │
│  └────────────────────────────┘  │  │  │  ml_kem_public_key TEXT (v3)  │  │
│                                  │  │  └────────────────────────────────┘  │
│  ┌────────────────────────────┐  │  │                                      │
│  │    Crypto Module           │  │  │  ┌────────────────────────────────┐  │
│  │                            │  │  │  │    contact_requests table      │  │
│  │  ML-KEM-768 keygen         │  │  │  │                                │  │
│  │  encryptMessage()          │  │  │  │  peer_id TEXT PRIMARY KEY      │  │
│  │  decryptMessage()          │  │  │  │  public_key TEXT NOT NULL      │  │
│  │                            │  │  │  │  rendezvous TEXT NOT NULL      │  │
│  │  Uses:                     │  │  │  │  username TEXT NOT NULL        │  │
│  │  • @noble/post-quantum    │  │  │  │  signature TEXT NOT NULL       │  │
│  │  • crypto.subtle (AES)    │  │  │  │  received_at TEXT NOT NULL     │  │
│  └────────────────────────────┘  │  │  │  status TEXT NOT NULL          │  │
│                                  │  │  │  DEFAULT 'pending'            │  │
│  ┌────────────────────────────┐  │  │  │  ml_kem_public_key TEXT (v3)  │  │
│  │    P2P Module              │  │  │  └────────────────────────────────┘  │
│  │    (libp2p node)           │  │  │                                      │
│  │                            │  │  │  ┌────────────────────────────────┐  │
│  │  Node start/stop           │  │  │  │        messages table          │  │
│  │  Rendezvous register       │  │  │  │        (v2 migration)          │  │
│  │  Rendezvous discover       │  │  │  │                                │  │
│  │  Peer dial/disconnect      │  │  │  │  id TEXT PRIMARY KEY           │  │
│  │  Message send/receive      │  │  │  │                                │  │
│  │                            │  │  │  │  contact_peer_id TEXT NOT NULL │  │
│  │  Uses:                     │  │  │  │  sender_peer_id TEXT NOT NULL  │  │
│  │  • @libp2p/* suite         │  │  │  │  text TEXT NOT NULL            │  │
│  └────────────────────────────┘  │  │  │  timestamp TEXT NOT NULL       │  │
│                                  │  │  │  status TEXT DEFAULT 'sent'    │  │
│                                  │  │  │  is_incoming INTEGER NOT NULL  │  │
│                                  │  │  │  created_at TEXT NOT NULL      │  │
│                                  │  │  │  read_at TEXT (v6)            │  │
│                                  │  │  │  INDEX idx_messages_contact    │  │
│                                  │  │  │  INDEX idx_messages_ts         │  │
│                                  │  │  └────────────────────────────────┘  │
│                                  │  │                                      │
│                                  │  └──────────────────────────────────────┘
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
| FirstTimeExperienceWired | Widget | Business logic: QR build, username edit, avatar (BLOB in DB), scan, contact request listening |
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
| FeedWired | Widget | Feed orchestration: loads identity, builds initial feed, listens for contact requests and messages; orbit tab pushes OrbitWired via Navigator.push |
| FeedHeader | Widget | Sticky header with username and ring avatar |
| FeedNavigationBar | Widget | Bottom glassmorphic nav bar with 3 SVG tabs (feed, orbit, remember); orbit tab triggers Navigator.push instead of tab swap; shows total unread badge on feed tab |
| NavBarButton | Widget | Individual nav bar tab button (active/inactive states) with optional badge overlay |
| UnreadCountBadge | Widget | Circular count badge for unread messages (shows 99+ max) |
| ConnectionCard | Widget | Card displaying a contact connection with ring avatar and inline green checkmark badge |
| MessageFeedCard | Widget | Incoming message card with contact avatar, message preview, and reply button |
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
| AnimatedFriendRow | Widget | FriendRow wrapper with staggered slide-up animation (index * 20ms) |
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
| **Identity Use Cases** | | |
| decideStartupRoute() | Use Case | Checks identity + contact count → 3-way routing decision |
| generateNewIdentity() | Use Case | Orchestrates identity generation via JS bridge |
| restoreIdentityFromMnemonic() | Use Case | Orchestrates identity restoration via JS bridge |
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
| ChatMessageListener | Service | Monitors chatMessageStream, resolves own ML-KEM secret key for decryption, broadcasts persisted ConversationMessages and contact updates to UI |
| markConversationRead() | Use Case | Marks all unread messages for a contact as read (sets read_at timestamp) |
| **Feed Use Cases** | | |
| loadFeed() | Use Case | Loads initial feed from DB: contacts + latest messages per contact + unread counts |
| **Orbit Use Cases** | | |
| loadOrbitData() | Use Case | Loads all contacts with message counts + unread counts from MessageRepository, sorted by messageCount descending; returns List<OrbitFriend> |
| **Core Services** | | |
| IncomingMessageRouter | Service | Routes P2P messages by envelope type to contactRequestStream, chatMessageStream, unknownStream; stream subscription has onError/onDone handlers |
| **Stream Error Handling** | Convention | All `.listen()` calls across IncomingMessageRouter (1), ContactRequestListener (1), ChatMessageListener (1), FeedWired (3), ConversationWired (2), FirstTimeExperienceWired (1), OrbitWired (3) include `onError` and `onDone` callbacks for resilience |
| **Domain** | | |
| IdentityModel | Entity | Immutable data class for identity (peerId, keys, mnemonic, username, avatarBlob, mlKemPublicKey?, mlKemSecretKey?); secrets (privateKey, mnemonic12, mlKemSecretKey) stored in SecureKeyStore, DB columns always NULL |
| ContactModel | Entity | Contact from QR scan (peerId, publicKey, rendezvous, username, signature, scannedAt, mlKemPublicKey?) |
| ContactRequestModel | Entity | Incoming request (peerId, publicKey, rendezvous, username, signature, status, mlKemPublicKey?) |
| NodeState | P2P Model | P2P node state (peerId, isStarted, listenAddresses, connections) |
| DiscoveredPeer | P2P Model | Discovered peer (id, addresses) |
| ConnectionState | P2P Model | Active connection (peerId, multiaddrs, direction, status) |
| ChatMessage | P2P Model | P2P message (from, to, content, timestamp, isIncoming) |
| FeedItem | Abstract Entity | Base class for feed items (id, timestamp, type) |
| ConnectionFeedItem | Entity | Feed item for new connections (extends FeedItem) |
| MessageFeedItem | Entity | Feed item for incoming messages (extends FeedItem, contactPeerId, messageText, messageTime, unreadCount) |
| FeedItemType | Enum | Feed item types: connection, message |
| ConversationMessage | Entity | Message in a conversation (id, contactPeerId, senderPeerId, text, status, isIncoming, readAt?) |
| MessagePayload | Wire Model | Chat message envelope: v1 plaintext `{ "type": "chat_message", "version": "1", "payload": {...} }` or v2 encrypted `{ "type": "chat_message", "version": "2", "senderPeerId": "...", "encrypted": { "kem", "ciphertext", "nonce" } }` |
| OrbitFriend | Composite Model | ContactModel + messageCount (int) + lastActivity (String) + lastMessageTimestamp (DateTime?) + unreadCount (int, default 0); used by Orbit feature for ranking friends by conversation activity |
| IdentityRepository | Interface + Impl | Abstracts identity persistence; IdentityRepositoryImpl takes SecureKeyStore, reads secrets from secure storage (falls back to DB for pre-migration), writes secrets only to secure storage |
| ContactRepository | Interface + Impl | Abstracts contact persistence (add, get, getAll, delete, exists, count) |
| ContactRequestRepository | Interface + Impl | Abstracts request persistence (add, get, getPending, updateStatus, delete, exists) |
| MessageRepository | Interface + Impl | Abstracts message persistence (save, getForContact, getLatest, updateStatus, exists, getMessageCountForContact, markConversationAsRead, getUnreadCountForContact, getTotalUnreadCount) |
| **Core** | | |
| WebViewJsBridge | Bridge Client | Sends requests to JS runtime, manages event handlers; checkHealth() probes bridge liveness (node:status, 5s timeout); reinitialize() tears down and recreates WebView preserving callbacks; send() catches PlatformException and returns `{errorCode: 'BRIDGE_DEAD'}` |
| P2PBridgeClient | Bridge Client | P2P-specific bridge calls (start, stop, status, register, discover, dial, disconnect, send, inbox store/retrieve, inbox register token) |
| JsBridgeClient | Bridge Helpers | Identity + signing + ML-KEM encryption/decryption bridge helper functions |
| P2PService / P2PServiceImpl | Service | Reactive P2P service with state and message streams, with offline inbox fallback + registerInboxToken for FCM push notifications; public performImmediateHealthCheck() and drainOfflineInbox() wrappers for app-resume lifecycle |
| IncomingMessageRouter | Service | Routes P2P messages by JSON envelope type to typed broadcast streams |
| RingAvatarGenerator | Utility | Deterministic avatar from peerId via DJB2 hash |
| KeyConversion | Utility | base64ToHex, hexToBase64, bytesToHex, hexToBytes |
| FlowEventEmitter | Utility | Structured logging across all layers |
| NetworkConstants | Constants | Rendezvous address constant |
| ChatConsoleLogger | Utility | Debug logging for chat messages with shortened peer IDs |
| formatRelativeTime() | Utility | Formats timestamps as relative "2m ago" strings for Orbit feature |
| SecureKeyStore | Interface | Abstract secure key-value storage (read, write, delete, containsKey) |
| FlutterSecureKeyStore | Impl | iOS Keychain (kSecAttrAccessibleWhenUnlockedThisDeviceOnly, device-bound) / Android EncryptedSharedPreferences; stores identity_private_key, identity_mnemonic12, identity_ml_kem_secret_key, db_encryption_key |
| encrypted_db_opener | DB Setup | Opens SQLCipher-encrypted database with key from SecureKeyStore; handles plaintext-to-encrypted migration |
| migrate_secrets_to_secure_storage | Migration | One-time migration of secrets from DB columns to SecureKeyStore with secrets_migrated sentinel |
| Database Helpers | DB Access | Low-level SQL operations for all 4 tables (via sqflite_sqlcipher) |
| AppColors / AppTheme | Theme | Color constants and ThemeData for dark theme |
| GlassmorphicContainer | Theme | Frosted glass effect widget |

### JavaScript Runtime Components

| Component | Responsibility |
|-----------|----------------|
| Bridge Entry (entry.ts) | Routes incoming requests to handlers via command registry; log sanitization prevents secret payloads in fallback console output |
| Handlers (handlers.ts) | Command map: `identity.generate`, `identity.restore`, `payload.sign`, `inbox:store`, `inbox:retrieve`, `inbox:check` |
| generateIdentity() | Creates new BIP39 mnemonic + Ed25519 keypair + ML-KEM-768 keypair |
| restoreFromMnemonic() | Derives Ed25519 keypair from existing mnemonic + generates fresh ML-KEM-768 keypair |
| signPayload() | Signs data with Ed25519 private key using @noble/ed25519 |
| Crypto Module (crypto/) | ML-KEM-768 keygen, message encrypt (KEM encapsulate + AES-256-GCM), message decrypt (KEM decapsulate + AES-256-GCM) using @noble/post-quantum |
| Bridge Commands | `mlkem.keygen` → ML-KEM keypair, `message.encrypt` → {kem, ciphertext, nonce}, `message.decrypt` → {plaintext} |
| P2P Module | libp2p node management, rendezvous, relay, messaging |
| Inbox Module | Offline message store/retrieve/register token via relay server inbox protocol (`/mknoon/inbox/1.0.0`) |

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
  │         JsBridge                    │
  ├─────────────────────────────────────┤
  │ + send(message: String): String     │
  └──────────────────┬──────────────────┘
                     │
                     │ extends
                     ▼
  ┌─────────────────────────────────────┐
  │         WebViewJsBridge             │
  ├─────────────────────────────────────┤
  │ - _controller: WebViewController?   │
  │ - _initialized: bool                │
  │ - _requestId: int                   │
  │ - _pendingRequests: Map<Completer>  │
  │ - _eventHandlers: Map<String, Fn>  │
  ├─────────────────────────────────────┤
  │ + initialize(): Future<void>        │
  │ + send(message: String): String     │
  │   (catches PlatformException →      │
  │    marks bridge dead, returns       │
  │    {errorCode: 'BRIDGE_DEAD'})      │
  │ + checkHealth(): Future<bool>       │
  │   (sends node:status, 5s timeout)   │
  │ + reinitialize(): Future<void>      │
  │   (tears down + recreates WebView,  │
  │    preserves callback references)   │
  │ + onMessageReceived(callback)       │
  │ + onPeerConnected(callback)         │
  │ + onPeerDisconnected(callback)      │
  │ - _onMessage(JavaScriptMessage)     │
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
  ├─────────────────────────────────────┤
  │ + fromQRPayload(Map): ContactModel  │
  │ + fromMap(Map): ContactModel        │
  │ + toMap(): Map                      │
  │ + copyWith(): ContactModel          │
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
  │ + registerInboxToken(token, platform): bool │
  │ + performImmediateHealthCheck(): void │
  │ + drainOfflineInbox(): void          │
  │ + dispose(): void                   │
  └──────────────────┬──────────────────┘
                     │ implements
                     ▼
  ┌─────────────────────────────────────┐
  │       P2PServiceImpl                │
  ├─────────────────────────────────────┤
  │ - _bridge: WebViewJsBridge          │
  │ - _stateController: StreamController│
  │ - _messageController: StreamCtrl    │
  │ - _currentState: NodeState          │
  ├─────────────────────────────────────┤
  │ + startNode(privKey, peerId): bool  │
  │ + stopNode(): bool                  │
  │ + sendMessage(peerId, msg): bool    │
  │ + discoverPeer(peerId): Discovered? │
  │ + dialPeer(peerId, {addrs}): bool   │
  │ + storeInInbox(peerId, msg): bool  │
  │ + retrieveInbox(): List<Map>       │
  │ + registerInboxToken(token, platform): bool │
  │ + performImmediateHealthCheck(): void │
  │   (public wrapper → _performHealthCheck) │
  │ + drainOfflineInbox(): void          │
  │   (public wrapper → _drainOfflineInbox)  │
  │ + dispose(): void                   │
  │ - _onMessageReceived(Map)           │
  │ - _onPeerConnected(Map)             │
  │ - _onPeerDisconnected(Map)          │
  │ - _performHealthCheck(): void      │
  │ - _drainOfflineInbox(): void       │
  └─────────────────────────────────────┘


  ── Contact Request Listener ─────────────────────────────────────────────

  ┌─────────────────────────────────────┐
  │     ContactRequestListener          │
  ├─────────────────────────────────────┤
  │ - p2pService: P2PService            │
  │ - requestRepo: ContactRequestRepo   │
  │ - contactRepo: ContactRepository    │
  │ - bridge: JsBridge                  │
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
  │ + bridge: JsBridge                  │
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
  │    FeedWired                        │
  ├─────────────────────────────────────┤
  │ + repository: IdentityRepository    │
  │ + contactRepository: ContactRepo    │
  │ + contactRequestRepository: CRRepo  │
  │ + contactRequestListener: Listener  │
  │ + messageRepository: MessageRepo    │
  │ + bridge: JsBridge                  │
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
  │ + bridge: JsBridge                  │
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
  └─────────────────────────────────────┘


  ── Conversation Services ──────────────────────────────────────────────

  ┌─────────────────────────────────────┐
  │     ChatMessageListener             │
  ├─────────────────────────────────────┤
  │ - chatMessageStream: Stream         │
  │ - messageRepo: MessageRepository    │
  │ - contactRepo: ContactRepository    │
  │ - bridge: JsBridge?                 │
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
  │         <<enum>>                    │        │      <<enum>>           │
  │         SendMessageResult           │        │  DiscoverPeerResult     │
  ├─────────────────────────────────────┤        ├─────────────────────────┤
  │ + success                           │        │ + success               │
  │ + nodeNotRunning                    │        │ + nodeNotRunning        │
  │ + peerNotFound                      │        │ + notFound              │
  │ + error                             │        │ + error                 │
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
│                           TYPESCRIPT INTERFACES                              │
├─────────────────────────────────────────────────────────────────────────────┤

  ┌─────────────────────────────────────┐
  │         <<interface>>               │
  │         IdentityJson                │
  ├─────────────────────────────────────┤
  │ + peerId: string                    │
  │ + publicKey: string                 │
  │ + privateKey: string                │
  │ + mnemonic12: string                │
  │ + createdAt: string                 │
  │ + updatedAt: string                 │
  │ + mlKemPublicKey?: string           │
  │ + mlKemSecretKey?: string           │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │         <<interface>>               │
  │         UnsignedQRPayload           │
  ├─────────────────────────────────────┤
  │ + pk: string                        │
  │ + ns: string                        │
  │ + rv: string                        │
  │ + ts: string                        │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │         <<interface>>               │
  │     SignedQRPayload extends         │
  │         UnsignedQRPayload           │
  ├─────────────────────────────────────┤
  │ + sig: string                       │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │         <<interface>>               │
  │         BridgeRequest               │
  ├─────────────────────────────────────┤
  │ + cmd: string                       │
  │ + payload: object                   │
  │ + requestId: string                 │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │         <<interface>>               │
  │         BridgeResponse              │
  ├─────────────────────────────────────┤
  │ + ok: boolean                       │
  │ + requestId: string                 │
  │ + identity?: IdentityJson           │
  │ + signature?: string                │
  │ + errorCode?: string                │
  │ + errorMessage?: string             │
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
    callJsGenerate: () => Future<Map>,
    repo: IdentityRepository
  ): Future<GenerateIdentityResult>

  restoreIdentityFromMnemonic(
    input: String,
    callJsRestore: (String) => Future<Map>,
    repo: IdentityRepository
  ): Future<RestoreIdentityResult>


  FLUTTER USE CASES - QR CODE:
  ────────────────────────────
  buildQRPayload(
    repo: IdentityRepository,
    callJsSign: (String, String) => Future<Map>
  ): Future<(BuildQRPayloadResult, String?)>

  parseQRPayload(
    qrString: String,
    bridge: JsBridge,
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
     bridge?: JsBridge,
     recipientMlKemPublicKey?: String}
  ): Future<(SendChatMessageResult, ConversationMessage?)>
  // If bridge + recipientMlKemPublicKey present → encrypt (v2 envelope)
  // Otherwise → plaintext (v1 envelope)
  // On send failure after 3x retry → storeInInbox() fallback

  handleIncomingChatMessage(
    message: ChatMessage,
    messageRepo: MessageRepository,
    contactRepo: ContactRepository,
    {bridge?: JsBridge,
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


  FLUTTER USE CASES - CONTACT REQUESTS:
  ─────────────────────────────────────
  sendContactRequest(
    p2pService: P2PService,
    identityRepo: IdentityRepository,
    bridge: JsBridge,
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
    bridge: JsBridge,
    requestRepo: ContactRequestRepository,
    contactRepo: ContactRepository,
    ownPeerId: String
  ): Future<(HandleMessageResult, ContactRequestModel?)>


  FLUTTER BRIDGE CLIENTS - IDENTITY:
  ──────────────────────────────────
  callJsIdentityGenerate(bridge: JsBridge): Future<Map<String, dynamic>>
  callJsIdentityRestore(bridge: JsBridge, mnemonic12: String): Future<Map<String, dynamic>>
  callJsSignPayload(bridge: JsBridge, dataToSign: String, privateKey: String): Future<Map<String, dynamic>>
  callJsMlKemKeygen(bridge: JsBridge): Future<Map<String, dynamic>>
  callJsEncryptMessage({bridge, recipientMlKemPublicKey, plaintext, timeout?}): Future<Map<String, dynamic>>
  callJsDecryptMessage({bridge, ownMlKemSecretKey, kem, ciphertext, nonce, timeout?}): Future<Map<String, dynamic>>


  FLUTTER BRIDGE CLIENTS - P2P:
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
  runMessagesTableMigration(db: Database): Future<void>   ← creates messages table + indexes
  runReadAtColumnMigration(db: Database): Future<void>    ← adds read_at TEXT to messages (v6)


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


  JAVASCRIPT FUNCTIONS:
  ─────────────────────
  generateIdentity(): Promise<IdentityJson>           // now includes mlKemPublicKey, mlKemSecretKey
  restoreIdentityFromMnemonic(mnemonic12: string): Promise<IdentityJson>  // fresh ML-KEM keypair (not from mnemonic)
  signPayload(dataToSign: string, privateKey: string): Promise<string>
  generateMlKemKeyPair(): Promise<{publicKey, secretKey}>
  encryptMessage(recipientMlKemPublicKey, plaintext): Promise<{kem, ciphertext, nonce}>
  decryptMessage(ownMlKemSecretKey, kem, ciphertext, nonce): Promise<{plaintext}>
  handleBridgeMessage(message: {cmd, requestId, payload}): Promise<any>
  storeInInbox(node, relayPeerId, toPeerId, message, metadata): Promise<InboxResponse>
  retrieveFromInbox(node, relayPeerId, options): Promise<InboxResponse>
  registerInboxToken(node, relayPeerId, {token, platform}): Promise<InboxResponse>

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
       │              │              ├──────► callJsIdentityGenerate()
       │              │              │              │
       │              │              │              └──────► WebViewJsBridge.send()
       │              │              │                             │
       │              │              │                             └──────► [JS] handleBridgeMessage()
       │              │              │                                            │
       │              │              │                                            └──────► generateIdentity()
       │              │              │
       │              │              └──────► IdentityRepository.saveIdentity()
       │              │                             │
       │              │                             └──────► dbUpsertIdentityRow()
       │              │
       │              └──────► MnemonicInputWired
       │                             │
       │                             └──────► restoreIdentityFromMnemonic()
       │                                            │
       │                                            ├──────► callJsIdentityRestore()
       │                                            │              │
       │                                            │              └──────► [JS] restoreFromMnemonic()
       │                                            │
       │                                            └──────► IdentityRepository.saveIdentity()
       │
       └──────► FirstTimeExperienceWired (from needsIdentity after generation)
                      │
                      ├──────► buildQRPayload()
                      │              │
                      │              ├──────► IdentityRepository.loadIdentity()
                      │              │
                      │              └──────► callJsSignPayload()
                      │                             │
                      │                             └──────► [JS] signPayload()
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
                      │                             │              ├──────► [JS] signPayload() (verify)
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
                                     ├──────► [JS] signPayload() (verify signature)
                                     │
                                     ├──────► ContactRepository.contactExists()
                                     │
                                     ├──────► ContactRequestRepo.requestExists()
                                     │
                                     └──────► ContactRequestRepo.addRequest()


  ChatMessageListener (background service)
       │
       ├──────► bridge: JsBridge? (for ML-KEM decryption)
       │
       ├──────► getOwnMlKemSecretKey: () => Future<String?> (from identity repo)
       │
       └──────► IncomingMessageRouter.chatMessageStream (subscribe)
                      │
                      └──────► handleIncomingChatMessage(bridge, ownMlKemSecretKey)
                                     │
                                     ├──────► Detect v2 encrypted envelope
                                     │              │
                                     │              └──────► callJsDecryptMessage() (ML-KEM + AES-256-GCM)
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
       │              ├──────► [if ML-KEM key] callJsEncryptMessage() → v2 envelope
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
       │              └──────► WebViewJsBridge.send()
       │                             │
       │                             └──────► [JS] P2P Module (libp2p)
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
├── main.dart                                    # App entry point, Firebase init, SecureKeyStore + encrypted DB setup (v6), secret migration, DI; MyApp = StatefulWidget + WidgetsBindingObserver (lifecycle, push listeners, orderly dispose)
├── smoke_test_main.dart                         # Smoke test entry point
├── smoke_test_restore.dart                      # Smoke test for identity restore
├── smoke_test_messages.dart                     # Smoke test for messages DB layer
├── core/
│   ├── bridge/
│   │   ├── js_bridge_client.dart               # JsBridge interface + identity/signing/encryption helpers
│   │   ├── webview_js_bridge.dart              # WebView implementation + event handlers
│   │   └── p2p_bridge_client.dart              # P2P-specific bridge calls + inbox store/retrieve
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
│   │   │   └── 006_read_at_column.dart         # Schema v6 (read_at TEXT on messages table)
│   │   └── helpers/
│   │       ├── identity_db_helpers.dart        # Identity DB CRUD
│   │       ├── contacts_db_helpers.dart        # Contacts DB CRUD
│   │       ├── contact_requests_db_helpers.dart # Contact Requests DB CRUD
│   │       └── messages_db_helpers.dart        # Messages DB CRUD
│   ├── secure_storage/
│   │   ├── secure_key_store.dart                 # SecureKeyStore abstract interface
│   │   └── flutter_secure_key_store.dart         # FlutterSecureKeyStore impl (iOS Keychain / Android EncryptedSharedPrefs)
│   ├── services/
│   │   ├── p2p_service.dart                    # P2PService abstract interface (incl. inbox)
│   │   ├── p2p_service_impl.dart               # P2PServiceImpl with streams + offline inbox drain
│   │   └── incoming_message_router.dart        # Routes P2P messages by type to streams
│   ├── theme/
│   │   ├── app_colors.dart                     # Color constants (Custom1 dark)
│   │   ├── app_theme.dart                      # ThemeData configuration
│   │   └── glassmorphism.dart                  # GlassmorphicContainer widget
│   └── utils/
│       ├── flow_event_emitter.dart             # Logging utility
│       ├── key_conversion.dart                 # base64 ↔ hex conversion
│       ├── ring_avatar_spec.dart               # Ring avatar constants + data models
│       ├── ring_avatar_generator.dart          # Deterministic avatar from peerId
│       └── chat_console_logger.dart           # Chat message debug logging + wire envelope logging
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
│   │   │   │   └── feed_item.dart              # FeedItem base + ConnectionFeedItem + MessageFeedItem
│   │   │   └── utils/
│   │   │       └── format_message_time.dart    # Message timestamp formatting + formatRelativeTime()
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
│   │   │   └── chat_message_listener.dart      # Background chat listener + ML-KEM decryption
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
│   │       │   └── date_separator.dart         # Date divider
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
│   │           ├── animated_friend_row.dart        # Staggered slide-up wrapper (index * 20ms)
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
│   │           └── choice_card.dart            # Glassmorphic tap card
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
│   │       └── add_contact_use_case.dart        # Add with duplicate check
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
│       │       └── chat_message.dart             # ChatMessage (from, to, content)
│       ├── application/
│       │   ├── start_node_use_case.dart          # Start node with identity
│       │   ├── stop_node_use_case.dart           # Stop running node
│       │   ├── send_message_use_case.dart        # Send P2P message
│       │   └── discover_peer_use_case.dart       # Discover + dial peer
│       └── presentation/
│           └── widgets/
│               └── connection_status_indicator.dart  # Online/Offline badge

core_lib_js/
├── package.json                                # NPM config + dependencies
├── package-lock.json                           # Dependency lock file
├── build.mjs                                   # esbuild config
├── build.sh                                    # Shell build script
├── tsconfig.json                               # TypeScript compiler options
├── jest.config.cjs                             # Jest test runner config (CommonJS for ESM package)
├── test_identity.js                            # Standalone Node.js identity test
├── shims/
│   └── buffer-shim.js                          # Node.js Buffer polyfill
└── src/
    ├── types/
    │   ├── identity.ts                         # IdentityJson interface (incl. mlKemPublicKey, mlKemSecretKey)
    │   └── qr_payload.ts                       # UnsignedQRPayload, SignedQRPayload
    ├── identity/
    │   ├── generate.ts                         # generateIdentity() (Ed25519 + ML-KEM-768)
    │   └── restore.ts                          # restoreIdentityFromMnemonic() (Ed25519 + fresh ML-KEM-768)
    ├── crypto/
    │   ├── keygen_mlkem.ts                     # ML-KEM-768 keypair generation
    │   ├── encrypt_message.ts                  # ML-KEM encapsulate + AES-256-GCM encrypt
    │   └── decrypt_message.ts                  # ML-KEM decapsulate + AES-256-GCM decrypt
    ├── signing/
    │   └── sign_payload.ts                     # signPayload() using @noble/ed25519
    ├── bridge/
    │   ├── entry.ts                            # WebView entry point (incl. mlkem.keygen, message.encrypt/decrypt); log sanitization
    │   └── handlers.ts                         # Command map: identity.*, payload.sign
    ├── utils/
    │   ├── flow_events.ts                      # JS-side flow event emitter
    │   └── base64.ts                           # Browser-compatible base64
    └── __test__/
        ├── identity.test.ts                    # Jest unit tests for identity gen/restore
        └── crypto.test.ts                      # Jest unit tests for ML-KEM keygen, encrypt/decrypt

assets/
├── js/
│   ├── bridge.html                             # WebView HTML wrapper
│   ├── core_lib.js                             # Bundled JS identity/signing (generated)
│   ├── core_lib.js.map                         # Source map for debugging
│   ├── p2p_lib.js                              # Bundled JS P2P networking (generated)
│   └── test.html                               # Test HTML for bridge debugging
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

  User                Flutter UI           Use Case            Bridge              JS Runtime           Database
   │                      │                   │                   │                    │                   │
   │  Tap "I'm new"       │                   │                   │                    │                   │
   │─────────────────────>│                   │                   │                    │                   │
   │                      │                   │                   │                    │                   │
   │                      │  generateNew      │                   │                    │                   │
   │                      │  Identity()       │                   │                    │                   │
   │                      │──────────────────>│                   │                    │                   │
   │                      │                   │                   │                    │                   │
   │                      │                   │  callJsGenerate() │                    │                   │
   │                      │                   │──────────────────>│                    │                   │
   │                      │                   │                   │                    │                   │
   │                      │                   │                   │  JSON request      │                   │
   │                      │                   │                   │  {cmd, payload}    │                   │
   │                      │                   │                   │───────────────────>│                   │
   │                      │                   │                   │                    │                   │
   │                      │                   │                   │                    │  bip39.generate() │
   │                      │                   │                   │                    │  ed25519.keypair()│
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

  User                FTE Wired            Use Case            Bridge              JS Runtime           Database
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
   │                      │                   │  callJsSign()     │                    │                   │
   │                      │                   │──────────────────>│                    │                   │
   │                      │                   │                   │                    │                   │
   │                      │                   │                   │  Sign payload      │                   │
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
   │                 │                │                │                 │  Sign via JS    │
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

  User          Conv Wired      sendChatMsg UC   JS Bridge     MessageRepo     P2PService
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
   │                 │                │  callJsEncrypt│              │                │
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

  P2PService     Msg Router     Chat Listener    handleMsg UC    JS Bridge    Conv Wired     User
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
   │                │                │                │  callJsDecrypt            │           │
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
| webview_flutter | JavaScript runtime container |
| qr_flutter | QR code generation widget |
| mobile_scanner | Camera-based QR code scanning |
| image_picker | Camera/gallery image selection |
| path_provider | App documents directory access |
| cupertino_icons | iOS-style icons |
| firebase_core | Firebase initialization |
| firebase_messaging | Push notifications (FCM) |

### Flutter Dev Packages

| Package | Purpose |
|---------|---------|
| sqflite_common_ffi | SQLite/SQLCipher FFI for desktop testing |
| flutter_test | Widget testing framework |
| integration_test | Integration testing framework |
| flutter_lints | Lint rules |

### JavaScript Packages (package.json)

| Package | Purpose |
|---------|---------|
| bip39 | Mnemonic phrase generation |
| @libp2p/crypto | Ed25519 key generation |
| @libp2p/peer-id | libp2p peer ID derivation |
| @noble/ed25519 | Ed25519 signing & verification |
| @noble/post-quantum | ML-KEM-768 (FIPS 203) key encapsulation for E2E message encryption |
| esbuild | JavaScript bundling |
| @libp2p/* suite | P2P networking (node, relay, rendezvous, messaging) |

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
    ├─► openEncryptedDatabase('identity.db', version: 6, secureKeyStore)
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
    │       │       └─► runReadAtColumnMigration(db)
    │       │               Adds read_at TEXT column to messages (v6)
    │       │
    │       └─► onUpgrade callback (v1→v2→v3→v4→v5→v6)
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
    │               └─► runReadAtColumnMigration(db)                (v5 → v6)
    │                       Adds read_at TEXT column to messages table
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
    │       ├─► ContactRepositoryImpl (6 db helper functions)
    │       │
    │       ├─► ContactRequestRepositoryImpl (6 db helper functions)
    │       │
    │       └─► MessageRepositoryImpl (9 db helper functions)
    │
    ├─► WebViewJsBridge instantiation + initialize()
    │       │
    │       └─► Loads bridge.html + core_lib.js into hidden WebView
    │           Sets up JavaScriptChannel for Flutter ↔ JS communication
    │           Registers event handlers (messages, peer events)
    │
    ├─► P2PServiceImpl instantiation
    │       │
    │       └─► Wraps WebViewJsBridge with reactive streams
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
    │           Broadcasts to incomingMessageStream + contactUpdatedStream
    │
    └─► runApp(MyApp) — StatefulWidget + WidgetsBindingObserver
            │
            ├─► Constructor params: messageRouter, isDesktop, + all existing deps
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
            │       chatMessageListener → contactRequestListener →
            │       messageRouter → p2pService → bridge
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
| `lib/main.dart` | Entry point, Firebase init, SecureKeyStore + encrypted DB setup (v6), secret migration, repository + service + listener DI; MyApp is StatefulWidget + WidgetsBindingObserver with app-resume lifecycle (bridge health check → reinitialize if dead → P2P health check → drain inbox), foreground push listeners (Firebase onMessage/onMessageOpenedApp → inbox drain), and orderly dispose chain (chatMessageListener → contactRequestListener → messageRouter → p2pService → bridge) |
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
| `lib/core/services/incoming_message_router.dart` | P2P message routing by type |
| `lib/core/bridge/webview_js_bridge.dart` | JS runtime initialization + event handlers |
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
4. For new migrations, create `007_*.dart` and update `openEncryptedDatabase` version (currently v6)
5. For new P2P event handlers, register on `WebViewJsBridge` in `P2PServiceImpl`
6. For new secrets, add read/write methods to `SecureKeyStore` and update `FlutterSecureKeyStore`

---

## Networking & Integration Points

### Current State (P2P Active)

The application has **active P2P networking** via the JavaScript runtime. Identity and cryptographic operations happen locally, while peer discovery and messaging use the rendezvous/relay server.

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
                         │   └──────────────┬──────────────┘   │
                         │                  │                   │
                         └──────────────────┼───────────────────┘
                                            │
                                            │ WebSocket (libp2p relay)
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
                                            │ WebSocket relay
                                            ▼
                         ┌─────────────────────────────────────┐
                         │        Another Device               │
                         │   (Running Mknoon Identity App)     │
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

### JS Bridge Command Registry

| Command | Handler | Description |
|---------|---------|-------------|
| `identity.generate` | Identity module | Generate new BIP39 mnemonic + Ed25519 keypair + ML-KEM-768 keypair |
| `identity.restore` | Identity module | Restore Ed25519 keypair from mnemonic + generate fresh ML-KEM-768 keypair |
| `payload.sign` | Signing module | Sign data with Ed25519 private key |
| `mlkem.keygen` | Crypto module | Generate ML-KEM-768 keypair (publicKey + secretKey) |
| `message.encrypt` | Crypto module | Encrypt message: ML-KEM-768 encapsulate + AES-256-GCM -> {kem, ciphertext, nonce} |
| `message.decrypt` | Crypto module | Decrypt message: ML-KEM-768 decapsulate + AES-256-GCM -> {plaintext} |
| `inbox:register_token` | Inbox module | Register FCM device token for push notifications |
| P2P commands | P2P module | Node management, peer discovery, messaging |
