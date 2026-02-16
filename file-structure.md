# File Structure

## Project Structure Overview

```
flutter_app/
├── assets/
│   ├── js/
│   │   ├── bridge.html                             # WebView HTML wrapper (routes inbox:* commands)
│   │   ├── core_lib.js                             # Bundled JS identity/signing (generated)
│   │   ├── core_lib.js.map                         # Source map for core_lib.js
│   │   ├── p2p_lib.js                              # Bundled JS P2P networking + inbox (generated)
│   │   └── test.html                               # Test HTML for bridge debugging
│   └── icons/
│       ├── nav_feed.svg                             # Feed tab icon
│       ├── nav_orbit.svg                            # Orbit/circle tab icon
│       └── nav_remember.svg                         # Remember tab icon
│
├── lib/
│   ├── main.dart                               # App entry point, SecureKeyStore + encrypted DB setup, secrets migration, DI (dbCountMessagesForContact wired to MessageRepositoryImpl)
│   ├── smoke_test_main.dart                    # Smoke test entry point
│   ├── smoke_test_restore.dart                 # Smoke test for identity restore
│   ├── smoke_test_messages.dart                # Smoke test for messages DB layer
│   │
│   ├── core/
│   │   ├── bridge/
│   │   │   ├── js_bridge_client.dart           # JsBridge interface + identity/signing/encryption helpers
│   │   │   ├── webview_js_bridge.dart          # WebView implementation + event handlers
│   │   │   └── p2p_bridge_client.dart          # P2P-specific bridge calls + inbox store/retrieve
│   │   │
│   │   ├── constants/
│   │   │   └── network_constants.dart          # Rendezvous address constant
│   │   │
│   │   ├── database/
│   │   │   ├── encrypted_db_opener.dart        # SQLCipher DB open + plaintext→encrypted migration
│   │   │   ├── migrations/
│   │   │   │   ├── 001_identity_table.dart     # Schema v1 (identity, contacts, contact_requests)
│   │   │   │   ├── 002_messages_table.dart     # Schema v2 (messages table + indexes)
│   │   │   │   ├── 003_mlkem_keys.dart         # Schema v3 (ML-KEM key columns on identity, contacts, contact_requests)
│   │   │   │   ├── 004_nullify_secret_columns.dart  # Schema v4 (nullable secret columns)
│   │   │   │   └── 005_secret_null_checks.dart      # Schema v5 (CHECK constraints + avatar_blob BLOB)
│   │   │   └── helpers/
│   │   │       ├── identity_db_helpers.dart     # Identity table CRUD
│   │   │       ├── contacts_db_helpers.dart     # Contacts table CRUD
│   │   │       ├── contact_requests_db_helpers.dart  # Contact requests table CRUD
│   │   │       └── messages_db_helpers.dart     # Messages table CRUD (insert, load, update status, count for contact)
│   │   │
│   │   ├── services/
│   │   │   ├── p2p_service.dart                # P2PService abstract interface (incl. inbox)
│   │   │   ├── p2p_service_impl.dart           # P2PServiceImpl with reactive streams + offline inbox
│   │   │   └── incoming_message_router.dart    # Routes P2P messages by type to typed streams
│   │   │
│   │   ├── theme/
│   │   │   ├── app_colors.dart                 # Color constants (dark theme)
│   │   │   ├── app_theme.dart                  # ThemeData configuration
│   │   │   └── glassmorphism.dart              # GlassmorphicContainer widget
│   │   │
│   │   ├── secure_storage/
│   │   │   ├── secure_key_store.dart           # SecureKeyStore abstract interface (read, write, delete, containsKey)
│   │   │   ├── flutter_secure_key_store.dart   # Production impl (iOS Keychain / Android EncryptedSharedPreferences)
│   │   │   └── migrate_secrets_to_secure_storage.dart  # One-time DB→secure storage migration with sentinel
│   │   │
│   │   └── utils/
│   │       ├── flow_event_emitter.dart         # Structured logging utility
│   │       ├── key_conversion.dart             # base64 ↔ hex key conversion
│   │       ├── ring_avatar_spec.dart           # Ring avatar constants + data models
│   │       ├── ring_avatar_generator.dart      # Deterministic avatar from peerId (DJB2 hash)
│   │       └── chat_console_logger.dart        # Chat message debug logging with shortened IDs
│   │
│   └── features/
│       ├── home/
│       │   └── presentation/
│       │       ├── screens/
│       │       │   ├── first_time_experience_screen.dart   # Pure UI (staggered animations)
│       │       │   └── first_time_experience_wired.dart    # Business logic + CR listener + avatar blob storage
│       │       └── widgets/
│       │           ├── profile_avatar_widget.dart           # Avatar display (Image.memory) + camera button
│       │           ├── editable_username_widget.dart        # Tap-to-edit username
│       │           ├── qr_code_section.dart                 # QR code with green glow
│       │           ├── scan_friend_card.dart                # Glassmorphic scan action card
│       │           ├── empty_circle_state.dart              # Pulsing dashed circles
│       │           ├── ring_avatar.dart                     # RingAvatar widget (peerId → avatar)
│       │           └── ring_avatar_painter.dart             # CustomPainter canvas renderer
│       │
│       ├── feed/
│       │   ├── domain/
│       │   │   ├── models/
│       │   │   │   └── feed_item.dart                       # FeedItem base + ConnectionFeedItem + MessageFeedItem
│       │   │   └── utils/
│       │   │       └── format_message_time.dart             # Message timestamp formatting + relative time ("2m ago")
│       │   ├── application/
│       │   │   └── load_feed_use_case.dart                  # Load initial feed from DB (contacts + latest messages)
│       │   └── presentation/
│       │       ├── screens/
│       │       │   ├── feed_screen.dart                     # Pure UI feed display
│       │       │   └── feed_wired.dart                      # Feed business logic + CR/chat listeners + orbit navigation
│       │       ├── widgets/
│       │       │   ├── feed_header.dart                     # Sticky header (username + avatar from memory bytes)
│       │       │   ├── feed_navigation_bar.dart             # Bottom glass nav bar (3 tabs)
│       │       │   ├── nav_bar_button.dart                  # Individual nav button widget
│       │       │   ├── connection_card.dart                 # Contact connection card (inline green badge)
│       │       │   ├── message_feed_card.dart               # Incoming message card with reply button
│       │       │   └── checkmark_burst_animation.dart       # Animated checkmark with rings (unused/orphaned)
│       │       └── navigation/
│       │           └── feed_route_transition.dart            # Slide-up route transition
│       │
│       ├── conversation/
│       │   ├── domain/
│       │   │   ├── models/
│       │   │   │   ├── conversation_message.dart            # ConversationMessage (id, text, status, isIncoming)
│       │   │   │   └── message_payload.dart                 # Wire-format envelope model (chat_message type)
│       │   │   └── repositories/
│       │   │       ├── message_repository.dart              # Abstract interface (save, load, update status, count for contact)
│       │   │       └── message_repository_impl.dart         # DB-backed implementation (incl. getMessageCountForContact)
│       │   ├── application/
│       │   │   ├── send_chat_message_use_case.dart          # Send message with 3x retry, inbox fallback + optimistic persist
│       │   │   ├── handle_incoming_chat_message_use_case.dart  # Parse, validate sender, detect name changes
│       │   │   ├── load_conversation_use_case.dart          # Load all messages for a contact
│       │   │   └── chat_message_listener.dart               # Background listener for chat_message stream
│       │   └── presentation/
│       │       ├── screens/
│       │       │   ├── conversation_screen.dart             # Pure UI: header, letter cards, compose area
│       │       │   └── conversation_wired.dart              # Business logic: load, send, listen, optimistic UI
│       │       ├── widgets/
│       │       │   ├── letter_card.dart                     # Full-width message card (left/right accent, queued/delivered status)
│       │       │   ├── compose_area.dart                    # Auto-growing text field + send button
│       │       │   ├── empty_conversation_state.dart        # Breathing glow avatar + connection info
│       │       │   ├── conversation_header.dart             # Frosted-glass header with back + contact info
│       │       │   ├── compact_origin_marker.dart           # Compact connection origin at conversation top
│       │       │   └── date_separator.dart                  # Date divider between letter cards
│       │       └── navigation/
│       │           └── conversation_route_transition.dart    # Slide-up route transition (420ms)
│       │
│       ├── orbit/
│       │   ├── domain/
│       │   │   └── models/
│       │   │       └── orbit_friend.dart                    # Composite model: contact + messageCount + lastActivity
│       │   ├── application/
│       │   │   └── load_orbit_data_use_case.dart            # Top-level function: loads contacts with message counts, sorted desc
│       │   └── presentation/
│       │       ├── screens/
│       │       │   ├── orbit_screen.dart                    # StatelessWidget: pure UI layout with 4-layer Stack
│       │       │   └── orbit_wired.dart                     # StatefulWidget: state, 3 animation controllers, streams, DI (8 deps)
│       │       ├── widgets/
│       │       │   ├── orbital_visualization.dart           # 320x320 Stack: rings + center + friend avatars + overflow badge
│       │       │   ├── orbital_ring_painter.dart            # CustomPainter: 2 dashed concentric circles (teal + purple)
│       │       │   ├── orbital_avatar.dart                  # Positioned avatar on ring with staggered scale-in animation
│       │       │   ├── overflow_badge.dart                  # "+N" circle badge on outer ring (1000ms delayed entrance)
│       │       │   ├── orbit_close_button.dart              # 36x36 glass circle X button with BackdropFilter
│       │       │   ├── orbit_header.dart                    # Right-aligned user avatar (44px)
│       │       │   ├── friends_list_header.dart             # "Friends" title + My QR / Scan pill buttons
│       │       │   ├── friend_row.dart                      # Glassmorphic tappable friend card + AnimatedFriendRow wrapper
│       │       │   ├── qr_action_cards.dart                 # Two side-by-side bottom QR cards (unused/created but removed from screen)
│       │       │   ├── orbit_search_trigger.dart            # Floating glass pill at bottom (search + close)
│       │       │   └── orbit_search_dock.dart               # Bottom-docked search input panel with native keyboard
│       │       └── navigation/
│       │           └── orbit_route_transition.dart           # Slide-up route (matches conversation pattern, 420ms)
│       │
│       ├── identity/
│       │   ├── domain/
│       │   │   ├── models/
│       │   │   │   └── identity_model.dart                 # IdentityModel (peerId, keys, mnemonic, avatarBlob, etc.)
│       │   │   └── repositories/
│       │   │       ├── identity_repository.dart            # Abstract interface
│       │   │       └── identity_repository_impl.dart       # DB-backed impl + SecureKeyStore for secrets
│       │   ├── application/
│       │   │   ├── startup_decision.dart                   # decideStartupRoute() use case (3-way)
│       │   │   ├── generate_identity_use_case.dart         # generateNewIdentity() use case
│       │   │   └── restore_identity_use_case.dart          # restoreIdentityFromMnemonic() use case
│       │   └── presentation/
│       │       ├── startup_router.dart                     # Routes to feed, home, or onboarding
│       │       ├── screens/
│       │       │   ├── identity_choice_screen.dart         # "I'm new" / "Load my key" UI
│       │       │   ├── identity_choice_wired.dart          # Choice screen business logic
│       │       │   ├── mnemonic_input_screen.dart          # Recovery phrase input UI
│       │       │   └── mnemonic_input_wired.dart           # Mnemonic input business logic
│       │       └── widgets/
│       │           ├── ambient_background.dart             # Animated glow background
│       │           ├── brand_header.dart                   # Logo/title header
│       │           └── choice_card.dart                    # Glassmorphic tappable card
│       │
│       ├── identity_onboard/
│       │   └── presentation/
│       │       └── welcome_screen.dart                     # Onboarding welcome screen
│       │
│       ├── qr_code/
│       │   ├── domain/
│       │   │   └── models/
│       │   │       └── qr_payload_model.dart               # QR payload Dart model
│       │   ├── application/
│       │   │   ├── build_qr_payload_use_case.dart          # Build signed QR payload
│       │   │   └── parse_qr_payload_use_case.dart          # Validate scanned QR (sig, expiry, self)
│       │   └── presentation/
│       │       ├── screens/
│       │       │   ├── qr_display_screen.dart              # Full-screen QR display + long-press copy (debug)
│       │       │   ├── qr_display_wired.dart               # QR display business logic
│       │       │   ├── qr_scanner_screen.dart              # Camera scanner UI (mobile_scanner)
│       │       │   └── qr_scanner_wired.dart               # Scanner logic: parse, add, send request
│       │       └── widgets/
│       │           └── scan_overlay.dart                    # Canvas overlay with corner markers
│       │
│       ├── contacts/
│       │   ├── domain/
│       │   │   ├── models/
│       │   │   │   └── contact_model.dart                  # ContactModel (from QR or P2P)
│       │   │   └── repositories/
│       │   │       ├── contact_repository.dart             # Abstract interface (6 methods)
│       │   │       └── contact_repository_impl.dart        # DB-backed implementation
│       │   └── application/
│       │       └── add_contact_use_case.dart                # Add contact with duplicate check
│       │
│       ├── contact_request/
│       │   ├── domain/
│       │   │   ├── models/
│       │   │   │   └── contact_request_model.dart          # ContactRequestModel + status enum
│       │   │   └── repositories/
│       │   │       ├── contact_request_repository.dart     # Abstract interface (6 methods)
│       │   │       └── contact_request_repository_impl.dart
│       │   ├── application/
│       │   │   ├── send_contact_request_use_case.dart      # Build, sign, discover, dial, send (3x retry)
│       │   │   ├── accept_contact_request_use_case.dart    # Convert request → contact
│       │   │   ├── decline_contact_request_use_case.dart   # Update status to declined
│       │   │   ├── handle_incoming_message_use_case.dart   # Parse, validate sig, store request
│       │   │   └── contact_request_listener.dart           # Background P2P message listener service
│       │   └── presentation/
│       │       └── widgets/
│       │           ├── contact_request_dialog.dart          # Accept/Decline modal with RingAvatar
│       │           └── pending_requests_badge.dart          # Circular count badge (99+ max)
│       │
│       └── p2p/
│           ├── domain/
│           │   └── models/
│           │       ├── node_state.dart                     # NodeState (isStarted, connections, addresses)
│           │       ├── connection_state.dart                # ConnectionState (peerId, direction, status)
│           │       ├── discovered_peer.dart                 # DiscoveredPeer (id, addresses)
│           │       ├── chat_message.dart                    # ChatMessage (from, to, content, isIncoming)
│           │       └── send_message_result.dart             # SendMessageResult enum
│           ├── application/
│           │   ├── start_node_use_case.dart                 # Start P2P node with identity
│           │   ├── stop_node_use_case.dart                  # Stop running node
│           │   ├── send_message_use_case.dart               # Send message to peer
│           │   └── discover_peer_use_case.dart              # Discover + dial peer via rendezvous
│           └── presentation/
│               └── widgets/
│                   └── connection_status_indicator.dart     # Online/Offline status badge
│
├── core_lib_js/
│   ├── package.json                                       # NPM config + dependencies
│   ├── package-lock.json                                  # Dependency lock file
│   ├── build.mjs                                          # esbuild config (core_lib.js)
│   ├── build.sh                                           # Shell build script (npm install + build)
│   ├── tsconfig.json                                      # TypeScript compiler options
│   ├── jest.config.cjs                                    # Jest test runner config (CommonJS for ESM package)
│   ├── test_identity.js                                   # Standalone Node.js identity test
│   ├── shims/
│   │   └── buffer-shim.js                                 # Node.js Buffer polyfill
│   └── src/
│       ├── types/
│       │   ├── identity.ts                                # IdentityJson interface (incl. mlKemPublicKey, mlKemSecretKey)
│       │   └── qr_payload.ts                              # UnsignedQRPayload, SignedQRPayload
│       ├── identity/
│       │   ├── generate.ts                                # generateIdentity() (Ed25519 + ML-KEM-768)
│       │   └── restore.ts                                 # restoreIdentityFromMnemonic() (Ed25519 + fresh ML-KEM-768)
│       ├── crypto/
│       │   ├── keygen_mlkem.ts                            # ML-KEM-768 keypair generation
│       │   ├── encrypt_message.ts                         # ML-KEM encapsulate + AES-256-GCM encrypt
│       │   └── decrypt_message.ts                         # ML-KEM decapsulate + AES-256-GCM decrypt
│       ├── signing/
│       │   └── sign_payload.ts                            # signPayload() using @noble/ed25519
│       ├── bridge/
│       │   ├── entry.ts                                   # WebView entry point (incl. mlkem.keygen, message.encrypt/decrypt)
│       │   └── handlers.ts                                # Command registry (identity.*, payload.sign)
│       ├── utils/
│       │   ├── flow_events.ts                             # JS-side flow event emitter
│       │   └── base64.ts                                  # Browser-compatible base64
│       └── __test__/
│           ├── identity.test.ts                           # Jest unit tests for identity gen/restore
│           └── crypto.test.ts                             # Jest unit tests for ML-KEM keygen, encrypt/decrypt
│
├── integration_test/
│   └── smoke_test.dart                                    # Integration smoke test
│
├── test/
│   ├── widget_test.dart                                   # Widget tests
│   ├── core/
│   │   ├── services/
│   │   │   └── incoming_message_router_test.dart           # IncomingMessageRouter unit tests
│   │   └── secure_storage/
│   │       ├── fake_secure_key_store.dart                  # In-memory test fake
│   │       └── migrate_secrets_to_secure_storage_test.dart # Migration unit tests
│   └── features/
│       ├── feed/
│       │   ├── application/
│       │   │   └── load_feed_use_case_test.dart            # Feed loading tests
│       │   ├── domain/
│       │   │   ├── models/
│       │   │   │   └── feed_item_test.dart                 # FeedItem model tests
│       │   │   └── utils/
│       │   │       └── format_message_time_test.dart       # Time formatting tests
│       │   └── presentation/
│       │       └── widgets/
│       │           └── message_feed_card_test.dart         # Message feed card widget tests
│       └── conversation/
│           ├── integration/
│           │   └── two_user_message_exchange_test.dart    # Integration: full send/receive flow
│           ├── application/
│           │   ├── send_chat_message_use_case_test.dart
│           │   ├── handle_incoming_chat_message_use_case_test.dart
│           │   └── load_conversation_use_case_test.dart
│           ├── domain/
│           │   ├── models/
│           │   │   ├── conversation_message_test.dart
│           │   │   └── message_payload_test.dart
│           │   └── repositories/
│           │       └── message_repository_impl_test.dart
│           └── presentation/
│               ├── screens/
│               │   ├── conversation_screen_test.dart
│               │   └── conversation_wired_test.dart
│               └── widgets/
│                   ├── empty_conversation_state_test.dart
│                   ├── compact_origin_marker_test.dart
│                   ├── conversation_header_test.dart
│                   ├── letter_card_test.dart
│                   ├── date_separator_test.dart
│                   └── compose_area_test.dart
│
├── android/
│   └── app/
│       └── src/
│           └── main/
│               └── res/
│                   └── xml/
│                       ├── backup_rules.xml               # Android <12 backup rules (exclude all)
│                       └── data_extraction_rules.xml      # Android 12+ extraction rules (exclude all)
│
├── pubspec.yaml                                           # Flutter dependencies (sqflite_sqlcipher, sqlcipher_flutter_libs, flutter_secure_storage)
├── C4_MODEL.md                                            # C4 architecture documentation
└── file-structure.md                                      # This file
```

---

## Feature → File Mapping

### Identity (M1)

| Component | File(s) | Description |
|-----------|---------|-------------|
| Identity model | `identity_model.dart` | Immutable data class (peerId, keys, mnemonic, username, avatarBlob, mlKemPublicKey?, mlKemSecretKey?) |
| Identity repository | `identity_repository.dart`, `identity_repository_impl.dart` | Load/save identity, SecureKeyStore for secrets |
| Generate identity | `generate_identity_use_case.dart` | JS bridge call + DB save |
| Restore identity | `restore_identity_use_case.dart` | Validate mnemonic + JS bridge + DB save |
| Startup routing | `startup_decision.dart`, `startup_router.dart` | Check identity + contacts → route to feed, home, or onboarding |
| Encrypted DB opener | `encrypted_db_opener.dart` | SQLCipher DB open + plaintext→encrypted migration |
| Secure key store | `secure_key_store.dart`, `flutter_secure_key_store.dart` | Abstract interface + production impl (iOS Keychain / Android EncryptedSharedPreferences) |
| Secrets migration | `migrate_secrets_to_secure_storage.dart` | One-time DB→secure storage migration with sentinel |
| DB migration | `001_identity_table.dart` | Creates identity, contacts, contact_requests tables |
| DB helpers | `identity_db_helpers.dart` | Identity table CRUD |
| Bridge | `js_bridge_client.dart`, `webview_js_bridge.dart` | Flutter ↔ JS communication (identity, signing, ML-KEM encryption/decryption) |

### QR Code (M2)

| Component | File(s) | Description |
|-----------|---------|-------------|
| QR payload model | `qr_payload_model.dart` | Dart model for QR JSON |
| Build QR | `build_qr_payload_use_case.dart` | Create signed QR payload |
| Parse QR | `parse_qr_payload_use_case.dart` | Validate scanned QR (sig, expiry, self-scan) |
| QR display | `qr_display_screen.dart`, `qr_display_wired.dart` | Show QR code UI + long-press copy (debug) |
| QR scanner | `qr_scanner_screen.dart`, `qr_scanner_wired.dart` | Camera scan + process |
| Scan overlay | `scan_overlay.dart` | Canvas overlay with corner markers |
| JS signing | `sign_payload.ts`, `handlers.ts` | `payload.sign` handler |
| JS types | `qr_payload.ts` | UnsignedQRPayload, SignedQRPayload |

### P2P Networking

| Component | File(s) | Description |
|-----------|---------|-------------|
| P2P service | `p2p_service.dart`, `p2p_service_impl.dart` | Reactive P2P interface + implementation with offline inbox |
| P2P bridge | `p2p_bridge_client.dart` | Low-level JS bridge calls for P2P + inbox store/retrieve |
| Message router | `incoming_message_router.dart` | Routes P2P messages by envelope type to typed streams |
| Node state | `node_state.dart` | P2P node state model |
| Connection state | `connection_state.dart` | Active connection model |
| Discovered peer | `discovered_peer.dart` | Peer discovery result model |
| Chat message | `chat_message.dart` | P2P message model |
| Send result | `send_message_result.dart` | SendMessageResult enum |
| Start node | `start_node_use_case.dart` | Start node with identity key |
| Stop node | `stop_node_use_case.dart` | Stop running node |
| Send message | `send_message_use_case.dart` | Send P2P message |
| Discover peer | `discover_peer_use_case.dart` | Discover + dial via rendezvous |
| Status indicator | `connection_status_indicator.dart` | Online/Offline UI badge |

### Contacts

| Component | File(s) | Description |
|-----------|---------|-------------|
| Contact model | `contact_model.dart` | Contact data (from QR scan or P2P, incl. mlKemPublicKey?) |
| Contact repository | `contact_repository.dart`, `contact_repository_impl.dart` | CRUD for contacts |
| Add contact | `add_contact_use_case.dart` | Add with duplicate check |
| DB helpers | `contacts_db_helpers.dart` | Contacts table CRUD |

### Contact Requests

| Component | File(s) | Description |
|-----------|---------|-------------|
| Request model | `contact_request_model.dart` | Request data + status enum (incl. mlKemPublicKey?) |
| Request repository | `contact_request_repository.dart`, `contact_request_repository_impl.dart` | CRUD for requests |
| Send request | `send_contact_request_use_case.dart` | Build, sign, discover, dial, send (3x retry) |
| Accept request | `accept_contact_request_use_case.dart` | Convert request → contact |
| Decline request | `decline_contact_request_use_case.dart` | Update status to declined |
| Handle incoming | `handle_incoming_message_use_case.dart` | Parse P2P message, validate, store |
| Listener service | `contact_request_listener.dart` | Background P2P message monitor |
| Request dialog | `contact_request_dialog.dart` | Accept/Decline modal UI |
| Requests badge | `pending_requests_badge.dart` | Count badge widget |
| DB helpers | `contact_requests_db_helpers.dart` | Contact requests table CRUD |

### Conversation (UI-4)

| Component | File(s) | Description |
|-----------|---------|-------------|
| Message model | `conversation_message.dart` | ConversationMessage (id, text, status, isIncoming, timestamps) |
| Wire payload | `message_payload.dart` | MessagePayload envelope: v1 plaintext or v2 encrypted (ML-KEM-768 + AES-256-GCM) |
| Message repository | `message_repository.dart`, `message_repository_impl.dart` | Save, load, update status, count for contact |
| Send message | `send_chat_message_use_case.dart` | Build payload, encrypt with ML-KEM if available (v2) or plaintext (v1), discover + dial peer, 3x retry, offline inbox fallback, optimistic persist |
| Handle incoming | `handle_incoming_chat_message_use_case.dart` | Detect v2 encrypted envelope and decrypt, or parse v1 plaintext, validate sender, detect name changes, persist |
| Load conversation | `load_conversation_use_case.dart` | Load all messages for a contact by timestamp ASC |
| Chat listener | `chat_message_listener.dart` | Background listener on chatMessageStream, resolves ML-KEM secret key for decryption, broadcasts to UI |
| Conversation screen | `conversation_screen.dart` | Pure UI: header, letter cards, empty state, compose area |
| Conversation logic | `conversation_wired.dart` | Business logic: load messages, optimistic send, listen for incoming |
| Letter card | `letter_card.dart` | Full-width card with left accent (received) / right accent (sent), supports queued/delivered/failed status |
| Compose area | `compose_area.dart` | Auto-growing text field + animated send button |
| Empty state | `empty_conversation_state.dart` | Breathing glow avatar + "Connected!" + writing prompt |
| Header | `conversation_header.dart` | Frosted-glass header with back button + contact info |
| Origin marker | `compact_origin_marker.dart` | Compact connection origin at conversation top |
| Date separator | `date_separator.dart` | Date divider between letter cards on different days |
| Route transition | `conversation_route_transition.dart` | Slide-up transition (420ms easeOutCubic) |
| DB migration | `002_messages_table.dart` | Creates messages table with contact + timestamp indexes |
| DB migration | `003_mlkem_keys.dart` | Adds ml_kem_public_key, ml_kem_secret_key columns to identity; ml_kem_public_key to contacts and contact_requests |
| DB migration | `004_nullify_secret_columns.dart` | Schema v4: makes secret columns nullable for secure storage migration |
| DB migration | `005_secret_null_checks.dart` | Schema v5: CHECK constraints on secret columns + avatar_blob BLOB column |
| DB helpers | `messages_db_helpers.dart` | Messages table CRUD (insert, load, update status, count for contact) |

### Orbit (UI-5)

| Component | File(s) | Description |
|-----------|---------|-------------|
| Orbit friend model | `orbit_friend.dart` | Composite model: contact + messageCount + lastActivity |
| Load orbit data | `load_orbit_data_use_case.dart` | Top-level function: loads contacts with message counts, sorted desc |
| Orbit screen | `orbit_screen.dart` | Pure UI: 4-layer Stack layout (header, visualization, friends list, search) |
| Orbit logic | `orbit_wired.dart` | State management: 3 animation controllers, streams, DI (8 deps) |
| Orbital visualization | `orbital_visualization.dart` | 320x320 Stack: rings + center avatar + friend avatars + overflow badge |
| Ring painter | `orbital_ring_painter.dart` | CustomPainter: 2 dashed concentric circles (teal + purple) |
| Orbital avatar | `orbital_avatar.dart` | Positioned avatar on ring with staggered scale-in animation |
| Overflow badge | `overflow_badge.dart` | "+N" circle badge on outer ring (1000ms delayed entrance) |
| Close button | `orbit_close_button.dart` | 36x36 glass circle X button with BackdropFilter |
| Orbit header | `orbit_header.dart` | Right-aligned user avatar (44px) |
| Friends list header | `friends_list_header.dart` | "Friends" title + My QR / Scan pill buttons |
| Friend row | `friend_row.dart` | Glassmorphic tappable friend card + AnimatedFriendRow wrapper |
| QR action cards | `qr_action_cards.dart` | Two side-by-side bottom QR cards (unused/created but removed from screen) |
| Search trigger | `orbit_search_trigger.dart` | Floating glass pill at bottom (search + close) |
| Search dock | `orbit_search_dock.dart` | Bottom-docked search input panel with native keyboard |
| Route transition | `orbit_route_transition.dart` | Slide-up route (matches conversation pattern, 420ms) |

### Home / First-Time Experience

| Component | File(s) | Description |
|-----------|---------|-------------|
| Home screen | `first_time_experience_screen.dart` | Animated home UI |
| Home logic | `first_time_experience_wired.dart` | QR build, username edit, avatar blob storage, scan, CR listener |
| Profile avatar | `profile_avatar_widget.dart` | Avatar display (Image.memory) + camera button |
| Username edit | `editable_username_widget.dart` | Tap-to-edit username |
| QR section | `qr_code_section.dart` | QR code with glow |
| Scan card | `scan_friend_card.dart` | Glassmorphic scan action |
| Empty state | `empty_circle_state.dart` | Pulsing circles animation |
| Ring avatar | `ring_avatar.dart`, `ring_avatar_painter.dart` | Deterministic peerId avatar |

### Feed

| Component | File(s) | Description |
|-----------|---------|-------------|
| Feed item model | `feed_item.dart` | FeedItem base + ConnectionFeedItem + MessageFeedItem |
| Time formatting | `format_message_time.dart` | Message timestamp formatting + relative time ("2m ago") |
| Load feed | `load_feed_use_case.dart` | Load initial feed from DB (contacts + latest messages) |
| Feed screen | `feed_screen.dart` | Pure UI feed display (connection + message cards) |
| Feed logic | `feed_wired.dart` | Feed orchestration, identity load, CR/chat listeners, orbit navigation |
| Feed header | `feed_header.dart` | Sticky header with username + avatar from memory bytes |
| Navigation bar | `feed_navigation_bar.dart` | Bottom glass nav bar (3 tabs) |
| Nav button | `nav_bar_button.dart` | Individual tab button (active/inactive) |
| Connection card | `connection_card.dart` | Contact connection display card (inline green checkmark badge) |
| Message card | `message_feed_card.dart` | Incoming message card with reply button |
| Checkmark anim | `checkmark_burst_animation.dart` | Animated checkmark with expanding rings (unused/orphaned) |
| Route transition | `feed_route_transition.dart` | Slide-up page transition |

### Core Utilities

| Component | File(s) | Description |
|-----------|---------|-------------|
| Ring avatar gen | `ring_avatar_generator.dart`, `ring_avatar_spec.dart` | DJB2 hash → deterministic rings |
| Key conversion | `key_conversion.dart` | base64 ↔ hex utilities |
| Flow events | `flow_event_emitter.dart` | Structured logging (DB/FL/JS layers) |
| Chat logger | `chat_console_logger.dart` | Debug logging for chat messages with shortened peer IDs |
| Network constants | `network_constants.dart` | Rendezvous multiaddr |
| Theme | `app_colors.dart`, `app_theme.dart`, `glassmorphism.dart` | Dark theme + glass effects |

### Relay Server (Infrastructure)

| Component | File(s) | Description |
|-----------|---------|-------------|
| Relay server v4 | `rendezvous-relay-server-inbox-v4.js` | libp2p relay + rendezvous + offline inbox (/mknoon/inbox/1.0.0 protocol) |

---

## Database Tables

| Table | Primary Key | Migration | Description |
|-------|-------------|-----------|-------------|
| `identity` | `id` (always 1) | v1 (`001`), v3 (`003`: ml_kem_public_key, ml_kem_secret_key), v4 (`004`: nullable secret columns), v5 (`005`: CHECK constraints + avatar_blob) | Single-row identity storage, secrets in secure storage (DB columns always NULL via CHECK), avatar as BLOB |
| `contacts` | `peer_id` | v1 (`001`), v3 (`003`: ml_kem_public_key) | Contacts added via QR scanning |
| `contact_requests` | `peer_id` | v1 (`001`), v3 (`003`: ml_kem_public_key) | Incoming P2P contact requests |
| `messages` | `id` (UUID) | v2 (`002`) | Conversation messages (indexes on contact_peer_id, timestamp) |

Database version: **5** (set in `main.dart` `openDatabase` call). Migrations v4 (`004_nullify_secret_columns.dart`: makes secret columns nullable) and v5 (`005_secret_null_checks.dart`: CHECK constraints ensuring secret columns stay NULL + avatar_blob BLOB column).

---

## Notes on Generated Assets

The files `assets/js/core_lib.js` and `assets/js/p2p_lib.js` are generated by bundling the TypeScript sources in `core_lib_js/`. After modifying any `.ts` file in `core_lib_js/src/`, you **must** rebuild:

```bash
cd core_lib_js
npm run build
```

This outputs the bundled `core_lib.js` to `assets/js/`. Without this step, changes to TypeScript code will not be available at runtime.
