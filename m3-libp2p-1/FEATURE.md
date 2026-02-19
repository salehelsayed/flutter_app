New Files to Create

  Core Layer - Bridge & Service

  lib/core/
  ├── bridge/
  │   └── p2p_bridge_client.dart          # Bridge helpers for P2P commands
  │                                        # callJsNodeStart(), callJsNodeStop(),
  │                                        # callJsRegisterRendezvous(), callJsDialPeer()
  │
  ├── services/
  │   ├── p2p_service.dart                 # Abstract interface for P2P operations
  │   └── p2p_service_impl.dart            # Implementation managing node lifecycle
  │                                        # Holds connection state, handles reconnection
  │
  └── constants/
      └── network_constants.dart           # (existing) - may need additional constants

  Domain Layer - P2P Feature

  lib/features/p2p/
  ├── domain/
  │   ├── models/
  │   │   ├── peer_model.dart              # PeerId, multiaddr, connection status
  │   │   ├── connection_state.dart        # Enum: disconnected, connecting, connected, registered
  │   │   └── p2p_message.dart             # Incoming/outgoing message structure
  │   │
  │   └── repositories/
  │       ├── peer_repository.dart         # Abstract: save/load known peers
  │       └── peer_repository_impl.dart    # SQLite implementation
  │
  ├── application/
  │   ├── start_node_use_case.dart         # Orchestrates: load identity → create node → register
  │   ├── stop_node_use_case.dart          # Graceful shutdown
  │   ├── register_rendezvous_use_case.dart # Register under namespace
  │   └── dial_peer_use_case.dart          # Connect to peer by ID
  │
  └── presentation/
      └── widgets/
          └── connection_status_indicator.dart  # Shows online/offline state

  JavaScript Runtime - libp2p Node

  core_lib_js/src/
  ├── p2p/
  │   ├── node.ts                          # createNode(identity): Libp2p
  │   │                                    # Configure transports, muxers, security
  │   │
  │   ├── rendezvous.ts                    # registerOnRendezvous(node, namespace)
  │   │                                    # discoverPeers(node, namespace)
  │   │
  │   ├── listeners.ts                     # setupListeners(node)
  │   │                                    # /p2p-circuit, TCP listeners
  │   │
  │   └── handlers.ts                      # Message handlers, connection events
  │
  ├── bridge/
  │   ├── entry.ts                         # (existing) - add new command routing
  │   └── handlers.ts                      # (existing) - add P2P command handlers:
  │                                        # 'node:start', 'node:stop',
  │                                        # 'rendezvous:register', 'peer:dial'
  │
  └── types/
      └── p2p.ts                           # P2P-related TypeScript interfaces

  Database Migration

  lib/core/database/
  └── migrations/
      └── 002_peers_table.dart             # CREATE TABLE peers (
                                           #   peer_id TEXT PRIMARY KEY,
                                           #   multiaddr TEXT,
                                           #   nickname TEXT,
                                           #   last_seen TEXT,
                                           #   created_at TEXT
                                           # )

  ---
  Files to Modify
  File: lib/main.dart
  Changes: Instantiate P2PServiceImpl, inject into app
  ────────────────────────────────────────
  File: lib/features/identity/presentation/startup_router.dart
  Changes: After routing, trigger startNodeUseCase()
  ────────────────────────────────────────
  File: lib/features/identity/presentation/screens/identity_choice_wired.dart
  Changes: After identity creation, call startNodeUseCase()
  ────────────────────────────────────────
  File: lib/features/home/presentation/screens/first_time_experience_wired.dart
  Changes: Add ConnectionStatusIndicator widget
  ────────────────────────────────────────
  File: core_lib_js/src/bridge/entry.ts
  Changes: Add routing for node:* and rendezvous:* commands
  ────────────────────────────────────────
  File: core_lib_js/package.json
  Changes: Add libp2p dependencies
  ---
  Data Flow

  ┌─────────────────────────────────────────────────────────────────────────────┐
  │                         STARTUP WITH P2P                                     │
  └─────────────────────────────────────────────────────────────────────────────┘

    main()
      │
      ├─► Initialize DB, Repository, Bridge (existing)
      │
      ├─► Initialize P2PServiceImpl
      │
      └─► StartupRouter
              │
              ├─► [hasIdentity]
              │       │
              │       ├─► Navigate to FirstTimeExperienceWired
              │       │
              │       └─► startNodeUseCase()
              │               │
              │               ├─► Load identity from repository
              │               ├─► callJsNodeStart(privateKey, peerId)
              │               │       │
              │               │       └─► [JS] createNode() + setupListeners()
              │               │
              │               └─► callJsRegisterRendezvous(namespace)
              │                       │
              │                       └─► [JS] registerOnRendezvous()
              │
              └─► [needsIdentity]
                      │
                      └─► IdentityChoiceWired
                              │
                              └─► onIdentityCreated callback
                                      │
                                      └─► startNodeUseCase()
                                              │
                                              └─► (same as above)

  ---
  JavaScript Dependencies (package.json additions)
 {
    "dependencies": {
      "libp2p": "^2.0.0",
      "@libp2p/websockets": "^9.0.0",
      "@libp2p/webrtc": "^5.0.0",
      "@libp2p/tcp": "^10.0.0",
      "@libp2p/circuit-relay-v2": "^3.0.0",
      "@libp2p/identify": "^3.0.0",
      "@libp2p/ping": "^2.0.0",
      "@libp2p/dcutr": "^2.0.0",
      "@libp2p/crypto": "^5.0.0",
      "@libp2p/peer-id": "^5.0.0",
      "@libp2p/peer-record": "^8.0.0",
      "@chainsafe/libp2p-noise": "^16.0.0",
      "@chainsafe/libp2p-yamux": "^7.0.0",
      "@canvas-js/libp2p-rendezvous": "^0.1.0",
      "@multiformats/multiaddr": "^12.0.0",
      "it-length-prefixed": "^9.0.0"
    }
  }

  ---
  Summary Table
  ┌───────────────┬──────────────────────────────────────────────┬────────────────────────────────────┐
  │     Layer     │                  New Files                   │              Purpose               │
  ├───────────────┼──────────────────────────────────────────────┼────────────────────────────────────┤
  │ JS Runtime    │ 4 files in core_lib_js/src/p2p/              │ libp2p node, rendezvous, listeners │
  ├───────────────┼──────────────────────────────────────────────┼────────────────────────────────────┤
  │ Core Bridge   │ p2p_bridge_client.dart                       │ Flutter ↔ JS P2P commands          │
  ├───────────────┼──────────────────────────────────────────────┼────────────────────────────────────┤
  │ Core Service  │ p2p_service.dart, p2p_service_impl.dart      │ Connection lifecycle management    │
  ├───────────────┼──────────────────────────────────────────────┼────────────────────────────────────┤
  │ Domain Models │ 3 files in features/p2p/domain/models/       │ Peer, connection state, message    │
  ├───────────────┼──────────────────────────────────────────────┼────────────────────────────────────┤
  │ Domain Repo   │ 2 files in features/p2p/domain/repositories/ │ Peer persistence                   │
  ├───────────────┼──────────────────────────────────────────────┼────────────────────────────────────┤
  │ Use Cases     │ 4 files in features/p2p/application/         │ Start, stop, register, dial        │
  ├───────────────┼──────────────────────────────────────────────┼────────────────────────────────────┤
  │ Presentation  │ connection_status_indicator.dart             │ UI for connection state            │
  ├───────────────┼──────────────────────────────────────────────┼────────────────────────────────────┤
  │ Migration     │ 002_peers_table.dart                         │ Peers database schema              │
  └───────────────┴──────────────────────────────────────────────┴────────────────────────────────────┘
  Total: ~15 new files + modifications to 6 existing files.

