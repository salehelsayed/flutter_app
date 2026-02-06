# File Structure

## Project Structure Overview

```
flutter_app/
├── assets/
│   ├── js/
│   │   ├── bridge.html                             # WebView HTML wrapper
│   │   ├── core_lib.js                             # Bundled JS identity/signing (generated)
│   │   ├── core_lib.js.map                         # Source map for core_lib.js
│   │   ├── p2p_lib.js                              # Bundled JS P2P networking (generated)
│   │   └── test.html                               # Test HTML for bridge debugging
│   └── icons/
│       ├── nav_feed.svg                             # Feed tab icon
│       ├── nav_orbit.svg                            # Orbit/circle tab icon
│       └── nav_remember.svg                         # Remember tab icon
│
├── lib/
│   ├── main.dart                               # App entry point, DB setup, DI
│   ├── smoke_test_main.dart                    # Smoke test entry point
│   ├── smoke_test_restore.dart                 # Smoke test for identity restore
│   │
│   ├── core/
│   │   ├── bridge/
│   │   │   ├── js_bridge_client.dart           # JsBridge interface + identity/signing helpers
│   │   │   ├── webview_js_bridge.dart          # WebView implementation + event handlers
│   │   │   └── p2p_bridge_client.dart          # P2P-specific bridge calls
│   │   │
│   │   ├── constants/
│   │   │   └── network_constants.dart          # Rendezvous address constant
│   │   │
│   │   ├── database/
│   │   │   ├── migrations/
│   │   │   │   └── 001_identity_table.dart     # Schema migration (identity, contacts, contact_requests)
│   │   │   └── helpers/
│   │   │       ├── identity_db_helpers.dart     # Identity table CRUD
│   │   │       ├── contacts_db_helpers.dart     # Contacts table CRUD
│   │   │       └── contact_requests_db_helpers.dart  # Contact requests table CRUD
│   │   │
│   │   ├── services/
│   │   │   ├── p2p_service.dart                # P2PService abstract interface
│   │   │   └── p2p_service_impl.dart           # P2PServiceImpl with reactive streams
│   │   │
│   │   ├── theme/
│   │   │   ├── app_colors.dart                 # Color constants (dark theme)
│   │   │   ├── app_theme.dart                  # ThemeData configuration
│   │   │   └── glassmorphism.dart              # GlassmorphicContainer widget
│   │   │
│   │   └── utils/
│   │       ├── flow_event_emitter.dart         # Structured logging utility
│   │       ├── key_conversion.dart             # base64 ↔ hex key conversion
│   │       ├── ring_avatar_spec.dart           # Ring avatar constants + data models
│   │       └── ring_avatar_generator.dart      # Deterministic avatar from peerId (DJB2 hash)
│   │
│   └── features/
│       ├── home/
│       │   └── presentation/
│       │       ├── screens/
│       │       │   ├── first_time_experience_screen.dart   # Pure UI (staggered animations)
│       │       │   └── first_time_experience_wired.dart    # Business logic + CR listener
│       │       └── widgets/
│       │           ├── profile_avatar_widget.dart           # Avatar display + camera button
│       │           ├── editable_username_widget.dart        # Tap-to-edit username
│       │           ├── qr_code_section.dart                 # QR code with green glow
│       │           ├── scan_friend_card.dart                # Glassmorphic scan action card
│       │           ├── empty_circle_state.dart              # Pulsing dashed circles
│       │           ├── ring_avatar.dart                     # RingAvatar widget (peerId → avatar)
│       │           └── ring_avatar_painter.dart             # CustomPainter canvas renderer
│       │
│       ├── feed/
│       │   ├── domain/
│       │   │   └── models/
│       │   │       └── feed_item.dart                       # FeedItem base + ConnectionFeedItem
│       │   └── presentation/
│       │       ├── screens/
│       │       │   ├── feed_screen.dart                     # Pure UI feed display
│       │       │   └── feed_wired.dart                      # Feed business logic + CR listener
│       │       ├── widgets/
│       │       │   ├── feed_header.dart                     # Sticky header (username + avatar)
│       │       │   ├── feed_navigation_bar.dart             # Bottom glass nav bar (3 tabs)
│       │       │   ├── nav_bar_button.dart                  # Individual nav button widget
│       │       │   ├── connection_card.dart                 # Contact connection card
│       │       │   └── checkmark_burst_animation.dart       # Animated checkmark with rings
│       │       └── navigation/
│       │           └── feed_route_transition.dart            # Slide-up route transition
│       │
│       ├── identity/
│       │   ├── domain/
│       │   │   ├── models/
│       │   │   │   └── identity_model.dart                 # IdentityModel (peerId, keys, mnemonic, etc.)
│       │   │   └── repositories/
│       │   │       ├── identity_repository.dart            # Abstract interface
│       │   │       └── identity_repository_impl.dart       # DB-backed implementation
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
│       │       │   ├── qr_display_screen.dart              # Full-screen QR display
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
│           │       └── chat_message.dart                    # ChatMessage (from, to, content, isIncoming)
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
│   ├── jest.config.js                                     # Jest test runner config
│   ├── test_identity.js                                   # Standalone Node.js identity test
│   ├── shims/
│   │   └── buffer-shim.js                                 # Node.js Buffer polyfill
│   └── src/
│       ├── types/
│       │   ├── identity.ts                                # IdentityJson interface
│       │   └── qr_payload.ts                              # UnsignedQRPayload, SignedQRPayload
│       ├── identity/
│       │   ├── generate.ts                                # generateIdentity()
│       │   └── restore.ts                                 # restoreIdentityFromMnemonic()
│       ├── signing/
│       │   └── sign_payload.ts                            # signPayload() using @noble/ed25519
│       ├── bridge/
│       │   ├── entry.ts                                   # WebView entry point
│       │   └── handlers.ts                                # Command registry (identity.*, payload.sign)
│       ├── utils/
│       │   ├── flow_events.ts                             # JS-side flow event emitter
│       │   └── base64.ts                                  # Browser-compatible base64
│       └── __test__/
│           └── identity.test.ts                           # Jest unit tests for identity gen/restore
│
├── integration_test/
│   └── smoke_test.dart                                    # Integration smoke test
│
├── test/
│   └── widget_test.dart                                   # Widget tests
│
├── pubspec.yaml                                           # Flutter dependencies
├── C4_MODEL.md                                            # C4 architecture documentation
└── file-structure.md                                      # This file
```

---

## Feature → File Mapping

### Identity (M1)

| Component | File(s) | Description |
|-----------|---------|-------------|
| Identity model | `identity_model.dart` | Immutable data class (peerId, keys, mnemonic, username, avatarPath) |
| Identity repository | `identity_repository.dart`, `identity_repository_impl.dart` | Load/save identity |
| Generate identity | `generate_identity_use_case.dart` | JS bridge call + DB save |
| Restore identity | `restore_identity_use_case.dart` | Validate mnemonic + JS bridge + DB save |
| Startup routing | `startup_decision.dart`, `startup_router.dart` | Check identity + contacts → route to feed, home, or onboarding |
| DB migration | `001_identity_table.dart` | Creates all 3 tables |
| DB helpers | `identity_db_helpers.dart` | Identity table CRUD |
| Bridge | `js_bridge_client.dart`, `webview_js_bridge.dart` | Flutter ↔ JS communication |

### QR Code (M2)

| Component | File(s) | Description |
|-----------|---------|-------------|
| QR payload model | `qr_payload_model.dart` | Dart model for QR JSON |
| Build QR | `build_qr_payload_use_case.dart` | Create signed QR payload |
| Parse QR | `parse_qr_payload_use_case.dart` | Validate scanned QR (sig, expiry, self-scan) |
| QR display | `qr_display_screen.dart`, `qr_display_wired.dart` | Show QR code UI |
| QR scanner | `qr_scanner_screen.dart`, `qr_scanner_wired.dart` | Camera scan + process |
| Scan overlay | `scan_overlay.dart` | Canvas overlay with corner markers |
| JS signing | `sign_payload.ts`, `handlers.ts` | `payload.sign` handler |
| JS types | `qr_payload.ts` | UnsignedQRPayload, SignedQRPayload |

### P2P Networking

| Component | File(s) | Description |
|-----------|---------|-------------|
| P2P service | `p2p_service.dart`, `p2p_service_impl.dart` | Reactive P2P interface + implementation |
| P2P bridge | `p2p_bridge_client.dart` | Low-level JS bridge calls for P2P |
| Node state | `node_state.dart` | P2P node state model |
| Connection state | `connection_state.dart` | Active connection model |
| Discovered peer | `discovered_peer.dart` | Peer discovery result model |
| Chat message | `chat_message.dart` | P2P message model |
| Start node | `start_node_use_case.dart` | Start node with identity key |
| Stop node | `stop_node_use_case.dart` | Stop running node |
| Send message | `send_message_use_case.dart` | Send P2P message |
| Discover peer | `discover_peer_use_case.dart` | Discover + dial via rendezvous |
| Status indicator | `connection_status_indicator.dart` | Online/Offline UI badge |

### Contacts

| Component | File(s) | Description |
|-----------|---------|-------------|
| Contact model | `contact_model.dart` | Contact data (from QR scan or P2P) |
| Contact repository | `contact_repository.dart`, `contact_repository_impl.dart` | CRUD for contacts |
| Add contact | `add_contact_use_case.dart` | Add with duplicate check |
| DB helpers | `contacts_db_helpers.dart` | Contacts table CRUD |

### Contact Requests

| Component | File(s) | Description |
|-----------|---------|-------------|
| Request model | `contact_request_model.dart` | Request data + status enum |
| Request repository | `contact_request_repository.dart`, `contact_request_repository_impl.dart` | CRUD for requests |
| Send request | `send_contact_request_use_case.dart` | Build, sign, discover, dial, send (3x retry) |
| Accept request | `accept_contact_request_use_case.dart` | Convert request → contact |
| Decline request | `decline_contact_request_use_case.dart` | Update status to declined |
| Handle incoming | `handle_incoming_message_use_case.dart` | Parse P2P message, validate, store |
| Listener service | `contact_request_listener.dart` | Background P2P message monitor |
| Request dialog | `contact_request_dialog.dart` | Accept/Decline modal UI |
| Requests badge | `pending_requests_badge.dart` | Count badge widget |
| DB helpers | `contact_requests_db_helpers.dart` | Contact requests table CRUD |

### Home / First-Time Experience

| Component | File(s) | Description |
|-----------|---------|-------------|
| Home screen | `first_time_experience_screen.dart` | Animated home UI |
| Home logic | `first_time_experience_wired.dart` | QR build, username edit, avatar, scan, CR listener |
| Profile avatar | `profile_avatar_widget.dart` | Avatar + camera button |
| Username edit | `editable_username_widget.dart` | Tap-to-edit username |
| QR section | `qr_code_section.dart` | QR code with glow |
| Scan card | `scan_friend_card.dart` | Glassmorphic scan action |
| Empty state | `empty_circle_state.dart` | Pulsing circles animation |
| Ring avatar | `ring_avatar.dart`, `ring_avatar_painter.dart` | Deterministic peerId avatar |

### Feed

| Component | File(s) | Description |
|-----------|---------|-------------|
| Feed item model | `feed_item.dart` | FeedItem base class + ConnectionFeedItem |
| Feed screen | `feed_screen.dart` | Pure UI feed display |
| Feed logic | `feed_wired.dart` | Feed orchestration, identity load, CR listener |
| Feed header | `feed_header.dart` | Sticky header with username + avatar |
| Navigation bar | `feed_navigation_bar.dart` | Bottom glass nav bar (3 tabs) |
| Nav button | `nav_bar_button.dart` | Individual tab button (active/inactive) |
| Connection card | `connection_card.dart` | Contact connection display card |
| Checkmark anim | `checkmark_burst_animation.dart` | Animated checkmark with expanding rings |
| Route transition | `feed_route_transition.dart` | Slide-up page transition |

### Core Utilities

| Component | File(s) | Description |
|-----------|---------|-------------|
| Ring avatar gen | `ring_avatar_generator.dart`, `ring_avatar_spec.dart` | DJB2 hash → deterministic rings |
| Key conversion | `key_conversion.dart` | base64 ↔ hex utilities |
| Flow events | `flow_event_emitter.dart` | Structured logging (DB/FL/JS layers) |
| Network constants | `network_constants.dart` | Rendezvous multiaddr |
| Theme | `app_colors.dart`, `app_theme.dart`, `glassmorphism.dart` | Dark theme + glass effects |

---

## Database Tables

| Table | Primary Key | Description |
|-------|-------------|-------------|
| `identity` | `id` (always 1) | Single-row identity storage |
| `contacts` | `peer_id` | Contacts added via QR scanning |
| `contact_requests` | `peer_id` | Incoming P2P contact requests |

All tables are created in `001_identity_table.dart` migration.

---

## Notes on Generated Assets

The files `assets/js/core_lib.js` and `assets/js/p2p_lib.js` are generated by bundling the TypeScript sources in `core_lib_js/`. After modifying any `.ts` file in `core_lib_js/src/`, you **must** rebuild:

```bash
cd core_lib_js
npm run build
```

This outputs the bundled `core_lib.js` to `assets/js/`. Without this step, changes to TypeScript code will not be available at runtime.
