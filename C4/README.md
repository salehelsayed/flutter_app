# C4 Model - Mknoon Identity App

## Document Index

| File | Content | Lines |
|------|---------|-------|
| [README.md](README.md) | Level 1 (System Context) + Level 2 (Container Diagram) | ~150 |
| [components.md](components.md) | Level 3 (Component Diagram) | ~900 |
| [code.md](code.md) | Level 4 (Code Diagram) — classes, signatures, dependency graph | ~1680 |
| [file-structure.md](file-structure.md) | Project file tree with annotations | ~360 |
| [data-flows.md](data-flows.md) | Sequence diagrams for key flows | ~490 |
| [infrastructure.md](infrastructure.md) | Dependencies, startup init, networking & protocols | ~540 |

---

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
                                      │ send encrypted messages,
                                      │ and participate in group chats
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
                        │   connect via P2P, manage   │
                        │   contacts, and participate │
                        │   in encrypted group chats  │
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
| User | Person | End user who wants to create or restore their cryptographic identity, connect with peers, manage contacts, exchange encrypted messages, and participate in group chats |
| Mknoon Identity App | Software System | Mobile/desktop app for identity management, profile customization, peer discovery, contact requests, E2E encrypted 1:1 conversations (ML-KEM-768 + AES-256-GCM), encrypted group messaging (GossipSub pubsub + AES-256-GCM), offline inbox, push notifications (Firebase Cloud Messaging), P2P messaging using Go-native libp2p and BIP39, and local WiFi discovery via mDNS. Data at rest encrypted via SQLCipher + OS-backed secure storage |
| Rendezvous / Relay Server | External System | libp2p rendezvous server for peer discovery (including per-group rendezvous namespaces `/mknoon/group/<groupId>`), circuit relay for NAT traversal, and offline message inbox (`/mknoon/inbox/1.0.0`) for store-and-forward delivery of 1:1 messages and group invites |

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
│  │  │  • Group messaging (create, invite, send/receive)              │  │  │
│     │  • P2P service layer                                           │     │
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
│  │  │  • Message encrypt/     │ │  • media_attachments │ │   _key     ││  │
│     │    decrypt              │ │    table             │ │ • mnemonic │  │
│  │  │  • P2P node management  │ │  • groups table      │ │   12       ││  │
│     │  • Peer discovery &     │ │  • group_members     │ │ • ml_kem_  │  │
│  │  │    relay                │ │  • group_keys        │ │   secret   ││  │
│     │  • GossipSub pubsub    │ │  • group_messages    │ │ • db_enc   │  │
│  │  │    (group messaging)    │ │  • reactions table   │ │   _key     ││  │
│     │  • Message send/receive │ │  • avatar BLOB store │ │            │  │
│  │  │  • Offline inbox store/ │ │  • 256-bit AES       │ │            ││  │
│     │    retrieve             │ │    encrypted         │ │            │  │
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
| Flutter Application | Dart/Flutter | Main application with UI, business logic, P2P service, group messaging (create/invite/send/receive via GossipSub), local WiFi discovery (mDNS), and data access |
| Go Native Library | gomobile bind → .xcframework (iOS) + .aar (Android) | Executes crypto operations (BIP39, Ed25519, ML-KEM-768) and P2P networking (libp2p node, rendezvous, relay, inbox, GossipSub pubsub for group messaging); communicates with Flutter via MethodChannel/EventChannel through platform wrappers (GoBridge.swift / GoBridge.kt) |
| SQLCipher Database | sqflite_sqlcipher | 256-bit AES encrypted SQLite database (v18); persists identity, contacts, contact requests, messages, media attachments, reactions, groups, group members, group keys, group messages, and avatar BLOBs locally |
| Secure Storage | flutter_secure_storage | OS-backed secret storage: iOS Keychain (device-bound, kSecAttrAccessibleWhenUnlockedThisDeviceOnly), Android EncryptedSharedPreferences; holds identity secrets and DB encryption key |
| Rendezvous / Relay Server | libp2p | External server for peer discovery, NAT traversal relay, and offline message inbox |
| Firebase Cloud Messaging | Firebase SDK | External push notification service; relay server sends FCM push when storing offline inbox messages |

### Communication

| From | To | Protocol | Description |
|------|-----|----------|-------------|
| Flutter App | Go Native Library | MethodChannel / EventChannel via platform wrappers | Request/response for identity, signing, crypto, P2P, and group operations (group:create, group:join, group:publish, etc.); push events (message:received, peer:connected, peer:disconnected, group_message:received) delivered via EventChannel |
| Flutter App | SQLCipher DB | SQL via sqflite_sqlcipher | CRUD operations for identity, contacts, contact requests, messages, media attachments, reactions, groups, group members, group keys, group messages, and avatar BLOBs (256-bit AES encrypted at rest) |
| Flutter App | Secure Storage | flutter_secure_storage API | Read/write identity secrets (private_key, mnemonic12, ml_kem_secret_key) and DB encryption key |
| Go Native Library | Rendezvous Server | libp2p (QUIC / WebSocket) | Peer discovery (1:1 + per-group rendezvous namespaces), relay circuits, direct messaging, GossipSub pubsub (group messages), and offline inbox protocol (`/mknoon/inbox/1.0.0`) for 1:1 messages and group invites |
| Flutter App | Firebase Cloud Messaging | HTTPS (FCM SDK) | Registers device token, receives push notifications for offline inbox messages |

---

