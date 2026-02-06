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
                                      │ and exchange contact requests
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
                        │   Peer discovery & relay    │
                        └─────────────────────────────┘

```

### Description

| Element | Type | Description |
|---------|------|-------------|
| User | Person | End user who wants to create or restore their cryptographic identity, connect with peers, and manage contacts |
| Mknoon Identity App | Software System | Mobile/desktop app for identity management, profile customization, peer discovery, contact requests, and P2P messaging using libp2p and BIP39 |
| Rendezvous / Relay Server | External System | libp2p rendezvous server for peer discovery and circuit relay for NAT traversal |

### External Dependencies
- Rendezvous/Relay server at `mknoun.xyz:4001` (WebSocket over TLS)

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
│     └───────────────────────┬───────────────────┬───────────────────┘     │
│  │                          │                   │                      │  │
│                             │ JSON/WebView      │ SQL queries            │
│  │                          │ Channel           │                      │  │
│                             ▼                   ▼                        │
│  │  ┌─────────────────────────────┐   ┌─────────────────────────────┐ │  │
│     │   JavaScript Runtime        │   │      SQLite Database        │    │
│  │  │   [Container: WebView]      │   │      [Container: sqflite]   │ │  │
│     │                             │   │                             │    │
│  │  │  • BIP39 mnemonic gen       │   │  • identity table           │ │  │
│     │  • Ed25519 keypair          │   │  • contacts table           │    │
│  │  │  • libp2p peer ID           │   │  • contact_requests table   │ │  │
│     │  • Payload signing          │   │  • Avatar path storage      │    │
│  │  │  • P2P node management      │   │                             │ │  │
│     │  • Peer discovery & relay   │   │                             │    │
│  │  │  • Message send/receive     │   │                             │ │  │
│     └──────────────┬──────────────┘   └─────────────────────────────┘    │
│  │                 │                                                   │  │
│                    │ WebSocket/libp2p                                     │
│  │                 │                                                   │  │
│  └ ─ ─ ─ ─ ─ ─ ─ ─┼─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘  │
│                    │                                                      │
│  ┌─────────────────┴───────────────┐                                     │
│  │      File System                │                                     │
│  │  [Container: Documents]         │                                     │
│  │                                 │                                     │
│  │  • Avatar images                │                                     │
│  │  • Documents/avatars/           │                                     │
│  └─────────────────────────────────┘                                     │
└───────────────────────────┬──────────────────────────────────────────────┘
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
| SQLite Database | sqflite / sqflite_common_ffi | Persists identity, contacts, and contact requests locally |
| File System | path_provider | Stores avatar images in app documents directory |
| Rendezvous / Relay Server | libp2p | External server for peer discovery and NAT traversal relay |

### Communication

| From | To | Protocol | Description |
|------|-----|----------|-------------|
| Flutter App | JS Runtime | JSON via JavaScriptChannel | Request/response for identity, signing, and P2P operations |
| Flutter App | SQLite | SQL via sqflite | CRUD operations for identity, contacts, and contact requests |
| Flutter App | File System | dart:io | Read/write avatar images |
| JS Runtime | Rendezvous Server | WebSocket (libp2p) | Peer discovery, relay circuits, and messaging |

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
│  │  │  │  │FeedHeader      │  │ConnectionCard  │  │Checkmark   │  │   │  │ │
│  │  │  │  │(username+avatar)│  │(contact card)  │  │BurstAnim   │  │   │  │ │
│  │  │  │  └────────────────┘  └────────────────┘  └────────────┘  │   │  │ │
│  │  │  │  ┌────────────────┐  ┌────────────────┐                  │   │  │ │
│  │  │  │  │FeedNavBar      │  │NavBarButton    │                  │   │  │ │
│  │  │  │  │(glass, 3 tabs) │  │(active/inactive)│                  │   │  │ │
│  │  │  │  └────────────────┘  └────────────────┘                  │   │  │ │
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
│  │  ┌──────────────────┐                                                 │ │
│  │  │ ConnectionFeed   │  Extends FeedItem                               │ │
│  │  │ Item [Feed Model]│                                                 │ │
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
│  │  └──────────────────────────────────────────┘                         │ │
│  │                                                                        │ │
│  │  ── Database ──────────────────────────────────────────────────────── │ │
│  │  ┌──────────────────────────┐  ┌──────────────────────────────────┐   │ │
│  │  │  identity_db_helpers     │  │  contacts_db_helpers             │   │ │
│  │  └──────────────────────────┘  └──────────────────────────────────┘   │ │
│  │  ┌──────────────────────────┐  ┌──────────────────────────────────┐   │ │
│  │  │  contact_requests_db_    │  │  001_identity_table migration    │   │ │
│  │  │  helpers                 │  │  (creates all 3 tables)          │   │ │
│  │  └──────────────────────────┘  └──────────────────────────────────┘   │ │
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
│     JAVASCRIPT RUNTIME           │  │         SQLITE DATABASE              │
│     [WebView Container]          │  │         [sqflite Container]          │
│                                  │  │                                      │
│  ┌────────────────────────────┐  │  │  ┌────────────────────────────────┐  │
│  │      Bridge Entry          │  │  │  │        identity table          │  │
│  │      [Handler Router]      │  │  │  │                                │  │
│  │                            │  │  │  │  id INTEGER PRIMARY KEY        │  │
│  │  handleBridgeMessage()     │  │  │  │  peer_id TEXT NOT NULL         │  │
│  │  sendToFlutter(response)   │  │  │  │  public_key TEXT NOT NULL      │  │
│  └──────────┬─────────────────┘  │  │  │  private_key TEXT NOT NULL     │  │
│             │                    │  │  │  mnemonic12 TEXT NOT NULL      │  │
│  ┌──────────┴─────────────────┐  │  │  │  username TEXT NOT NULL        │  │
│  │    Handlers                │  │  │  │  avatar_path TEXT              │  │
│  │                            │  │  │  │  created_at TEXT NOT NULL      │  │
│  │  identity.generate         │  │  │  │  updated_at TEXT NOT NULL      │  │
│  │  identity.restore          │  │  │  │  Constraint: id = 1 always     │  │
│  │  payload.sign              │  │  │  └────────────────────────────────┘  │
│  └────────────────────────────┘  │  │                                      │
│                                  │  │  ┌────────────────────────────────┐  │
│  ┌────────────────────────────┐  │  │  │        contacts table          │  │
│  │    Identity Module         │  │  │  │                                │  │
│  │                            │  │  │  │  peer_id TEXT PRIMARY KEY      │  │
│  │  generateIdentity()        │  │  │  │  public_key TEXT NOT NULL      │  │
│  │  restoreFromMnemonic()     │  │  │  │  rendezvous TEXT NOT NULL      │  │
│  └────────────────────────────┘  │  │  │  username TEXT NOT NULL        │  │
│                                  │  │  │  signature TEXT NOT NULL       │  │
│  ┌────────────────────────────┐  │  │  │  scanned_at TEXT NOT NULL      │  │
│  │    Signing Module          │  │  │  │  avatar_path TEXT              │  │
│  │                            │  │  │  └────────────────────────────────┘  │
│  │  signPayload()             │  │  │                                      │
│  │                            │  │  │  ┌────────────────────────────────┐  │
│  │  Uses:                     │  │  │  │    contact_requests table      │  │
│  │  • @noble/ed25519          │  │  │  │                                │  │
│  └────────────────────────────┘  │  │  │  peer_id TEXT PRIMARY KEY      │  │
│                                  │  │  │  public_key TEXT NOT NULL      │  │
│  ┌────────────────────────────┐  │  │  │  rendezvous TEXT NOT NULL      │  │
│  │    P2P Module              │  │  │  │  username TEXT NOT NULL        │  │
│  │    (libp2p node)           │  │  │  │  signature TEXT NOT NULL       │  │
│  │                            │  │  │  │  received_at TEXT NOT NULL     │  │
│  │  Node start/stop           │  │  │  │  status TEXT NOT NULL          │  │
│  │  Rendezvous register       │  │  │  │  DEFAULT 'pending'            │  │
│  │  Rendezvous discover       │  │  │  └────────────────────────────────┘  │
│  │  Peer dial/disconnect      │  │  │                                      │
│  │  Message send/receive      │  │  └──────────────────────────────────────┘
│  │                            │  │
│  │  Uses:                     │  │
│  │  • @libp2p/* suite         │  │
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
| FirstTimeExperienceWired | Widget | Business logic: QR build, username edit, avatar, scan, contact request listening |
| ProfileAvatarWidget | Widget | Avatar display with camera button and image picker |
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
| FeedScreen | Widget | Main feed UI displaying connection cards |
| FeedWired | Widget | Feed orchestration: loads identity, builds initial feed, listens for contact requests |
| FeedHeader | Widget | Sticky header with username and ring avatar |
| FeedNavigationBar | Widget | Bottom glassmorphic nav bar with 3 SVG tabs (feed, orbit, remember) |
| NavBarButton | Widget | Individual nav bar tab button (active/inactive states) |
| ConnectionCard | Widget | Card displaying a contact connection with ring avatar |
| CheckmarkBurstAnimation | Widget | Animated checkmark with expanding ring burst effect |
| FeedRouteTransition | Route | Slide-up page transition for feed navigation |
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
| ContactRequestListener | Service | Monitors P2P message stream, broadcasts new requests to UI |
| **Domain** | | |
| IdentityModel | Entity | Immutable data class for identity (peerId, keys, mnemonic, username, avatarPath) |
| ContactModel | Entity | Contact from QR scan (peerId, publicKey, rendezvous, username, signature, scannedAt) |
| ContactRequestModel | Entity | Incoming request (peerId, publicKey, rendezvous, username, signature, status) |
| NodeState | P2P Model | P2P node state (peerId, isStarted, listenAddresses, connections) |
| DiscoveredPeer | P2P Model | Discovered peer (id, addresses) |
| ConnectionState | P2P Model | Active connection (peerId, multiaddrs, direction, status) |
| ChatMessage | P2P Model | P2P message (from, to, content, timestamp, isIncoming) |
| FeedItem | Abstract Entity | Base class for feed items (id, timestamp, type) |
| ConnectionFeedItem | Entity | Feed item for new connections (extends FeedItem) |
| FeedItemType | Enum | Feed item types: connection |
| IdentityRepository | Interface + Impl | Abstracts identity persistence |
| ContactRepository | Interface + Impl | Abstracts contact persistence (add, get, getAll, delete, exists, count) |
| ContactRequestRepository | Interface + Impl | Abstracts request persistence (add, get, getPending, updateStatus, delete, exists) |
| **Core** | | |
| WebViewJsBridge | Bridge Client | Sends requests to JS runtime, manages event handlers |
| P2PBridgeClient | Bridge Client | P2P-specific bridge calls (start, stop, status, register, discover, dial, disconnect, send) |
| JsBridgeClient | Bridge Helpers | Identity + signing bridge helper functions |
| P2PService / P2PServiceImpl | Service | Reactive P2P service with state and message streams |
| RingAvatarGenerator | Utility | Deterministic avatar from peerId via DJB2 hash |
| KeyConversion | Utility | base64ToHex, hexToBase64, bytesToHex, hexToBytes |
| FlowEventEmitter | Utility | Structured logging across all layers |
| NetworkConstants | Constants | Rendezvous address constant |
| Database Helpers | DB Access | Low-level SQL operations for all 3 tables |
| AppColors / AppTheme | Theme | Color constants and ThemeData for dark theme |
| GlassmorphicContainer | Theme | Frosted glass effect widget |

### JavaScript Runtime Components

| Component | Responsibility |
|-----------|----------------|
| Bridge Entry (entry.ts) | Routes incoming requests to handlers via command registry |
| Handlers (handlers.ts) | Command map: `identity.generate`, `identity.restore`, `payload.sign` |
| generateIdentity() | Creates new BIP39 mnemonic + Ed25519 keypair |
| restoreFromMnemonic() | Derives keypair from existing mnemonic |
| signPayload() | Signs data with Ed25519 private key using @noble/ed25519 |
| P2P Module | libp2p node management, rendezvous, relay, messaging |

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
  │ + privateKey: String                │
  │ + mnemonic12: String                │
  │ + username: String                  │
  │ + avatarPath: String?               │
  │ + createdAt: String                 │
  │ + updatedAt: String                 │
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
  ├─────────────────────────────────────┤
  │ + loadIdentity(): IdentityModel?    │
  │ + saveIdentity(IdentityModel): void │
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
  │ + dispose(): void                   │
  │ - _onMessageReceived(Map)           │
  │ - _onPeerConnected(Map)             │
  │ - _onPeerDisconnected(Map)          │
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
  │ - _avatarPath: String?              │
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
  │    FeedWired                        │
  ├─────────────────────────────────────┤
  │ + repository: IdentityRepository    │
  │ + contactRepository: ContactRepo    │
  │ + contactRequestRepository: CRRepo  │
  │ + contactRequestListener: Listener  │
  │ + bridge: JsBridge                  │
  │ + p2pService: P2PService            │
  │ + initialContact: ContactModel      │
  ├─────────────────────────────────────┤
  │ - _identity: IdentityModel?         │
  │ - _feedItems: List<FeedItem>        │
  │ - _requestSubscription: StreamSub   │
  ├─────────────────────────────────────┤
  │ + _loadIdentity()                   │
  │ + _buildInitialFeed()               │
  │ + _startListeningForContactRequests │
  │ + _onContactRequest(Model)          │
  │ + _acceptRequest(ctx, Model)        │
  │ + _declineRequest(ctx, Model)       │
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


  FLUTTER UTILS:
  ──────────────
  base64ToHex(String base64): String
  hexToBase64(String hex): String
  bytesToHex(Uint8List bytes): String
  hexToBytes(String hex): Uint8List
  RingAvatarGenerator.generate(String peerId, double size): RingAvatarData
  RingAvatarGenerator.djb2Hash(String input): int


  JAVASCRIPT FUNCTIONS:
  ─────────────────────
  generateIdentity(): Promise<IdentityJson>
  restoreIdentityFromMnemonic(mnemonic12: string): Promise<IdentityJson>
  signPayload(dataToSign: string, privateKey: string): Promise<string>
  handleBridgeMessage(message: {cmd, requestId, payload}): Promise<any>

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
       │              └──────► ConnectionFeedItem.fromContact()
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
                      │              ├──────► File.copy() to Documents/avatars/
                      │              │
                      │              └──────► IdentityRepository.saveIdentity()
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


  ContactRequestListener (background service)
       │
       └──────► P2PService.messageStream (subscribe)
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
       └──────► messageStream (broadcast incoming ChatMessages)

```

---

## File Structure

```
lib/
├── main.dart                                    # App entry point, DI setup
├── smoke_test_main.dart                         # Smoke test entry point
├── smoke_test_restore.dart                      # Smoke test for identity restore
├── core/
│   ├── bridge/
│   │   ├── js_bridge_client.dart               # JsBridge interface + identity/signing helpers
│   │   ├── webview_js_bridge.dart              # WebView implementation + event handlers
│   │   └── p2p_bridge_client.dart              # P2P-specific bridge calls
│   ├── constants/
│   │   └── network_constants.dart              # Rendezvous address
│   ├── database/
│   │   ├── migrations/
│   │   │   └── 001_identity_table.dart         # Schema migration (all 3 tables)
│   │   └── helpers/
│   │       ├── identity_db_helpers.dart        # Identity DB CRUD
│   │       ├── contacts_db_helpers.dart        # Contacts DB CRUD
│   │       └── contact_requests_db_helpers.dart # Contact Requests DB CRUD
│   ├── services/
│   │   ├── p2p_service.dart                    # P2PService abstract interface
│   │   └── p2p_service_impl.dart               # P2PServiceImpl with streams
│   ├── theme/
│   │   ├── app_colors.dart                     # Color constants (Custom1 dark)
│   │   ├── app_theme.dart                      # ThemeData configuration
│   │   └── glassmorphism.dart                  # GlassmorphicContainer widget
│   └── utils/
│       ├── flow_event_emitter.dart             # Logging utility
│       ├── key_conversion.dart                 # base64 ↔ hex conversion
│       ├── ring_avatar_spec.dart               # Ring avatar constants + data models
│       └── ring_avatar_generator.dart          # Deterministic avatar from peerId
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
│   │   │   └── models/
│   │   │       └── feed_item.dart              # FeedItem base + ConnectionFeedItem
│   │   └── presentation/
│   │       ├── screens/
│   │       │   ├── feed_screen.dart            # Pure UI feed display
│   │       │   └── feed_wired.dart             # Feed business logic + CR listener
│   │       ├── widgets/
│   │       │   ├── feed_header.dart            # Sticky header (username + avatar)
│   │       │   ├── feed_navigation_bar.dart    # Bottom glass nav bar (3 tabs)
│   │       │   ├── nav_bar_button.dart         # Individual nav button widget
│   │       │   ├── connection_card.dart        # Contact connection card
│   │       │   └── checkmark_burst_animation.dart  # Animated checkmark
│   │       └── navigation/
│   │           └── feed_route_transition.dart   # Slide-up route transition
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
│   ├── identity_onboard/
│   │   └── presentation/
│   │       └── welcome_screen.dart             # Onboarding welcome screen
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
├── jest.config.js                              # Jest test runner config
├── test_identity.js                            # Standalone Node.js identity test
├── shims/
│   └── buffer-shim.js                          # Node.js Buffer polyfill
└── src/
    ├── types/
    │   ├── identity.ts                         # IdentityJson interface
    │   └── qr_payload.ts                       # UnsignedQRPayload, SignedQRPayload
    ├── identity/
    │   ├── generate.ts                         # generateIdentity()
    │   └── restore.ts                          # restoreIdentityFromMnemonic()
    ├── signing/
    │   └── sign_payload.ts                     # signPayload() using @noble/ed25519
    ├── bridge/
    │   ├── entry.ts                            # WebView entry point
    │   └── handlers.ts                         # Command map: identity.generate/restore, payload.sign
    ├── utils/
    │   ├── flow_events.ts
    │   └── base64.ts                           # Browser-compatible base64
    └── __test__/
        └── identity.test.ts                    # Jest unit tests for identity gen/restore

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

### Avatar Upload Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    AVATAR UPLOAD - DATA FLOW                                 │
└─────────────────────────────────────────────────────────────────────────────┘

  User                FTE Wired           ImagePicker          File System          Database
   │                      │                   │                    │                   │
   │  Tap camera button   │                   │                    │                   │
   │─────────────────────>│                   │                    │                   │
   │                      │                   │                    │                   │
   │                      │  Show bottom      │                    │                   │
   │                      │  sheet picker     │                    │                   │
   │                      │                   │                    │                   │
   │  Select "Gallery"    │                   │                    │                   │
   │─────────────────────>│                   │                    │                   │
   │                      │                   │                    │                   │
   │                      │  pickImage()      │                    │                   │
   │                      │──────────────────>│                    │                   │
   │                      │                   │                    │                   │
   │  Select photo        │                   │                    │                   │
   │─────────────────────>│                   │                    │                   │
   │                      │                   │                    │                   │
   │                      │  XFile (temp)     │                    │                   │
   │                      │<──────────────────│                    │                   │
   │                      │                   │                    │                   │
   │                      │  Copy to Documents/avatars/            │                   │
   │                      │───────────────────────────────────────>│                   │
   │                      │                   │                    │                   │
   │                      │  Saved path       │                    │                   │
   │                      │<──────────────────────────────────────│                   │
   │                      │                   │                    │                   │
   │                      │  Update identity with avatarPath       │                   │
   │                      │  saveIdentity()                        │                   │
   │                      │───────────────────────────────────────────────────────────>│
   │                      │                   │                    │                   │
   │                      │  setState()       │                    │                   │
   │                      │                   │                    │                   │
   │  Display avatar      │                   │                    │                   │
   │<─────────────────────│                   │                    │                   │
   │                      │                   │                    │                   │
```

---

## Dependencies

### Flutter Packages (pubspec.yaml)

| Package | Purpose |
|---------|---------|
| sqflite | SQLite database access |
| webview_flutter | JavaScript runtime container |
| qr_flutter | QR code generation widget |
| mobile_scanner | Camera-based QR code scanning |
| image_picker | Camera/gallery image selection |
| path_provider | App documents directory access |
| cupertino_icons | iOS-style icons |

### Flutter Dev Packages

| Package | Purpose |
|---------|---------|
| sqflite_common_ffi | SQLite FFI for desktop testing |
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
    ├─► Platform Check (Desktop: Linux/Windows/macOS)
    │       │
    │       └─► sqfliteFfiInit()
    │           databaseFactory = databaseFactoryFfi
    │           Desktop platforms require FFI for SQLite
    │
    ├─► openDatabase('identity.db', version: 1)
    │       │
    │       └─► onCreate callback (first run only)
    │               │
    │               └─► runIdentityTableMigration(db)
    │                       Creates identity, contacts, and
    │                       contact_requests tables
    │
    ├─► Repository instantiation (4 repositories)
    │       │
    │       ├─► IdentityRepositoryImpl (dbLoad, dbUpsert)
    │       │
    │       ├─► ContactRepositoryImpl (6 db helper functions)
    │       │
    │       └─► ContactRequestRepositoryImpl (6 db helper functions)
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
    ├─► ContactRequestListener instantiation + start()
    │       │
    │       └─► Subscribes to P2PService.messageStream
    │           Monitors for incoming contact requests
    │           Broadcasts to requestStream for UI
    │
    └─► runApp(MyApp)
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
                    └─► [needsIdentity] → Navigate to IdentityChoiceWired
```

### Initialization Files

| File | Responsibility |
|------|----------------|
| `lib/main.dart` | Entry point, DB setup, repository + service + listener DI |
| `lib/core/database/migrations/001_identity_table.dart` | Schema migration (3 tables) |
| `lib/core/bridge/webview_js_bridge.dart` | JS runtime initialization + event handlers |
| `lib/core/services/p2p_service_impl.dart` | P2P service initialization |
| `lib/features/contact_request/application/contact_request_listener.dart` | Background listener startup |
| `lib/features/identity/presentation/startup_router.dart` | Route decision logic |
| `lib/features/identity/application/startup_decision.dart` | Business logic for routing |

### Adding New Initialization Steps

To add a new initialization step:
1. Add async initialization code in `main()` before `runApp()`
2. Inject dependencies into `MyApp` constructor
3. Pass dependencies through `StartupRouter` to child widgets
4. For new migrations, create `002_*.dart` and update `openDatabase` version
5. For new P2P event handlers, register on `WebViewJsBridge` in `P2PServiceImpl`

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
                         │   │  • QR code creation         │   │
                         │   │  • QR code scanning         │   │
                         │   │  • Profile management       │   │
                         │   │  • SQLite persistence       │   │
                         │   │  • Contact management       │   │
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
    "sig": "<base64-signature>"
  }
}
```

### External Services

| Service | URL | Status | Purpose |
|---------|-----|--------|---------|
| Rendezvous/Relay Server | `mknoun.xyz:4001` | Active | P2P peer discovery and circuit relay |

### JS Bridge Command Registry

| Command | Handler | Description |
|---------|---------|-------------|
| `identity.generate` | Identity module | Generate new BIP39 mnemonic + Ed25519 keypair |
| `identity.restore` | Identity module | Restore keypair from existing mnemonic |
| `payload.sign` | Signing module | Sign data with Ed25519 private key |
| P2P commands | P2P module | Node management, peer discovery, messaging |
