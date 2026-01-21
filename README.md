# Flutter Identity App

A Flutter mobile application with a JavaScript/TypeScript core library that implements cryptographic identity management. The app allows users to create new identities or restore existing ones using BIP39 mnemonic phrases.

---

## Milestone-1: Identity Initialization

**Status:** Completed

Milestone-1 implements the complete identity onboarding flow, enabling users to either generate a new cryptographic identity or restore an existing one from a 12-word mnemonic phrase.

---

## Application Flow Mind-Map

```
                              ┌─────────────────────┐
                              │     APP LAUNCH      │
                              │     main.dart       │
                              └──────────┬──────────┘
                                         │
                    ┌────────────────────┼────────────────────┐
                    │                    │                    │
                    ▼                    ▼                    ▼
            ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
            │  Open/Create │    │     Run      │    │   Create     │
            │   Database   │    │  Migrations  │    │  JS Bridge   │
            └──────────────┘    └──────────────┘    └──────────────┘
                                         │
                                         ▼
                              ┌─────────────────────┐
                              │   StartupRouter     │
                              │  (Loading Screen)   │
                              └──────────┬──────────┘
                                         │
                              ┌──────────┴──────────┐
                              │ decideStartupRoute()│
                              │   Check Database    │
                              └──────────┬──────────┘
                                         │
                    ┌────────────────────┴────────────────────┐
                    │                                         │
                    ▼                                         ▼
        ┌───────────────────┐                     ┌───────────────────┐
        │  Identity EXISTS  │                     │  NO Identity      │
        │                   │                     │                   │
        │  Navigate to:     │                     │  Navigate to:     │
        │  MainAppScreen    │                     │  IdentityChoice   │
        └───────────────────┘                     └─────────┬─────────┘
                                                            │
                                          ┌─────────────────┴─────────────────┐
                                          │                                   │
                                          ▼                                   ▼
                              ┌─────────────────────┐           ┌─────────────────────┐
                              │   "I'm new here"    │           │   "Load my key"     │
                              │                     │           │                     │
                              │   GENERATE NEW      │           │   RESTORE FROM      │
                              │   IDENTITY          │           │   MNEMONIC          │
                              └──────────┬──────────┘           └──────────┬──────────┘
                                         │                                 │
                                         ▼                                 ▼
                              ┌─────────────────────┐           ┌─────────────────────┐
                              │ 1. JS generates     │           │ 1. Show input screen│
                              │    mnemonic         │           │ 2. User enters 12   │
                              │ 2. Derive keypair   │           │    words            │
                              │ 3. Create peer ID   │           │ 3. JS validates     │
                              │ 4. Save to DB       │           │ 4. Derive keypair   │
                              │ 5. → MainApp        │           │ 5. Save to DB       │
                              └─────────────────────┘           │ 6. → MainApp        │
                                                                └─────────────────────┘
```

---

## Architecture Mind-Map

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                                    FLUTTER APP                                       │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│  ┌─────────────────────────────────────────────────────────────────────────────┐    │
│  │                         PRESENTATION LAYER                                   │    │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────────────┐  │    │
│  │  │ StartupRouter   │  │IdentityChoice   │  │ MnemonicInput              │  │    │
│  │  │                 │  │    Screen       │  │    Screen                  │  │    │
│  │  │ - Loading state │  │                 │  │                            │  │    │
│  │  │ - Route decision│  │ - "I'm new"     │  │ - Text input (12 words)    │  │    │
│  │  │ - Error handling│  │ - "Load key"    │  │ - Validation feedback      │  │    │
│  │  └────────┬────────┘  └────────┬────────┘  └─────────────┬──────────────┘  │    │
│  └───────────┼────────────────────┼─────────────────────────┼──────────────────┘    │
│              │                    │                         │                        │
│  ┌───────────┼────────────────────┼─────────────────────────┼──────────────────┐    │
│  │           ▼                    ▼                         ▼                   │    │
│  │                         APPLICATION LAYER (Use Cases)                        │    │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────────────┐  │    │
│  │  │decideStartup    │  │generateNew      │  │ restoreIdentityFrom         │  │    │
│  │  │    Route()      │  │  Identity()     │  │    Mnemonic()               │  │    │
│  │  │                 │  │                 │  │                             │  │    │
│  │  │ Check if        │  │ Call JS bridge  │  │ 1. Normalize input          │  │    │
│  │  │ identity exists │  │ Save to DB      │  │ 2. Validate word count      │  │    │
│  │  │ Return decision │  │ Return result   │  │ 3. Call JS bridge           │  │    │
│  │  └────────┬────────┘  └────────┬────────┘  │ 4. Save to DB               │  │    │
│  │           │                    │           └─────────────┬───────────────┘  │    │
│  └───────────┼────────────────────┼─────────────────────────┼──────────────────┘    │
│              │                    │                         │                        │
│  ┌───────────┼────────────────────┼─────────────────────────┼──────────────────┐    │
│  │           ▼                    ▼                         ▼                   │    │
│  │                           DOMAIN LAYER                                       │    │
│  │  ┌──────────────────────────────────────────────────────────────────────┐   │    │
│  │  │                      IdentityRepository (Interface)                   │   │    │
│  │  │                                                                       │   │    │
│  │  │  + loadIdentity(): Future<IdentityModel?>                            │   │    │
│  │  │  + saveIdentity(identity): Future<void>                              │   │    │
│  │  └──────────────────────────────────────────────────────────────────────┘   │    │
│  │                                    │                                         │    │
│  │  ┌──────────────────────────────────────────────────────────────────────┐   │    │
│  │  │                         IdentityModel                                 │   │    │
│  │  │                                                                       │   │    │
│  │  │  - peerId: String          (libp2p peer identifier)                  │   │    │
│  │  │  - publicKey: String       (Base64 Ed25519 public key)               │   │    │
│  │  │  - privateKey: String      (Base64 Ed25519 private key)              │   │    │
│  │  │  - mnemonic12: String      (12 BIP39 words)                          │   │    │
│  │  │  - createdAt: String       (ISO-8601 timestamp)                      │   │    │
│  │  │  - updatedAt: String       (ISO-8601 timestamp)                      │   │    │
│  │  └──────────────────────────────────────────────────────────────────────┘   │    │
│  └──────────────────────────────────────────────────────────────────────────────┘    │
│                                         │                                            │
│  ┌──────────────────────────────────────┼───────────────────────────────────────┐   │
│  │                                      ▼                                        │   │
│  │                        INFRASTRUCTURE LAYER                                   │   │
│  │  ┌────────────────────────────┐    ┌────────────────────────────────────┐    │   │
│  │  │  IdentityRepositoryImpl    │    │         JS Bridge Client           │    │   │
│  │  │                            │    │                                    │    │   │
│  │  │  - loadIdentity()          │    │  - callJsIdentityGenerate()        │    │   │
│  │  │  - saveIdentity()          │    │  - callJsIdentityRestore()         │    │   │
│  │  │  - DB row mapping          │    │  - JSON message passing            │    │   │
│  │  └─────────────┬──────────────┘    └──────────────┬─────────────────────┘    │   │
│  │                │                                   │                          │   │
│  │                ▼                                   ▼                          │   │
│  │  ┌────────────────────────────┐    ┌────────────────────────────────────┐    │   │
│  │  │    SQLite Database         │    │   TypeScript/JavaScript Core       │    │   │
│  │  │                            │    │                                    │    │   │
│  │  │  identity table:           │    │  - BIP39 mnemonic generation       │    │   │
│  │  │  - id (always 1)           │    │  - Ed25519 keypair derivation      │    │   │
│  │  │  - peer_id                 │    │  - libp2p peer ID creation         │    │   │
│  │  │  - public_key              │    │  - Mnemonic validation             │    │   │
│  │  │  - private_key             │    │                                    │    │   │
│  │  │  - mnemonic12              │    │                                    │    │   │
│  │  │  - created_at              │    │                                    │    │   │
│  │  │  - updated_at              │    │                                    │    │   │
│  │  └────────────────────────────┘    └────────────────────────────────────┘    │   │
│  └───────────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Project Structure Mind-Map

```
flutter_app/
│
├── lib/                                 # Flutter Application Code
│   ├── main.dart                        # Entry point, DB init, routing
│   │
│   ├── core/                            # Shared Infrastructure
│   │   ├── bridge/
│   │   │   └── js_bridge_client.dart    # JS communication layer
│   │   ├── database/
│   │   │   ├── helpers/
│   │   │   │   └── identity_db_helpers.dart  # DB CRUD operations
│   │   │   └── migrations/
│   │   │       └── 001_identity_table.dart   # Schema creation
│   │   └── utils/
│   │       └── flow_event_emitter.dart       # Event tracking
│   │
│   └── features/
│       └── identity/                    # Identity Feature Module
│           ├── domain/                  # Business Logic
│           │   ├── models/
│           │   │   └── identity_model.dart   # Data structure
│           │   └── repositories/
│           │       ├── identity_repository.dart      # Interface
│           │       └── identity_repository_impl.dart # Implementation
│           │
│           ├── application/             # Use Cases
│           │   ├── generate_identity_use_case.dart   # New identity
│           │   ├── restore_identity_use_case.dart    # From mnemonic
│           │   └── startup_decision.dart             # Route logic
│           │
│           └── presentation/            # UI Layer
│               ├── startup_router.dart              # Initial routing
│               └── screens/
│                   ├── identity_choice_screen.dart  # Choice UI
│                   ├── identity_choice_wired.dart   # Choice + Logic
│                   ├── mnemonic_input_screen.dart   # Input UI
│                   └── mnemonic_input_wired.dart    # Input + Logic
│
├── core_lib_js/                         # TypeScript/JavaScript Core
│   └── src/
│       ├── types/
│       │   └── identity.ts              # IdentityJson type
│       ├── identity/
│       │   ├── generate.ts              # New identity generation
│       │   └── restore.ts               # Mnemonic restoration
│       ├── bridge/
│       │   └── handlers.ts              # Bridge message handlers
│       └── utils/
│           └── flow_events.ts           # Event definitions
│
├── Milestone-1/                         # Phase Documentation
│   ├── M1-Phase-1/                      # DB & JS Setup
│   ├── M1-Phase-2/                      # Repository Implementation
│   ├── M1-Phase-3/                      # Startup Decision Logic
│   ├── M1-Phase-4/                      # UI Screens
│   ├── M1-Phase-5/                      # Startup Routing
│   └── M1-Phase-6/                      # QA & Verification
│
└── Platform Directories
    ├── android/                         # Android native code
    ├── ios/                             # iOS native code
    ├── macos/                           # macOS native code
    ├── linux/                           # Linux native code
    ├── windows/                         # Windows native code
    └── web/                             # Web support
```

---

## Milestone-1 Phases

### Phase 1: Database & JavaScript Core Setup
**Tasks:** DB_XS_01, DB_XS_02, DB_XS_03, JS_XS_01-04, FL_XS_01-02

Foundation layer establishing:
- SQLite `identity` table schema
- TypeScript `IdentityJson` type definition
- JavaScript identity generation and restoration functions
- Dart `IdentityModel` with JSON serialization
- Database helper functions (load/upsert)

### Phase 2: Flutter Repository Implementation
**Tasks:** FL_XS_03, FL_XS_04

Data persistence layer:
- `IdentityRepositoryImpl` with `loadIdentity()` and `saveIdentity()`
- Database row mapping (snake_case ↔ camelCase)
- Error handling and flow events

### Phase 3: Startup Decision Logic
**Tasks:** FL_XS_05, FL_XS_06, FL_XS_07, FL_XS_08, FL_XS_09

App lifecycle management:
- `StartupDecision` enum: `hasIdentity` | `needsIdentity`
- `decideStartupRoute()` function checking database
- Flow events for startup decision tracking

### Phase 4: UI Screens & Wiring
**Tasks:** FL_XS_10, FL_XS_11, FL_XS_12, FL_XS_13, FL_XS_14

User interface:
- `IdentityChoiceScreen`: Two-button layout (New / Restore)
- `MnemonicInputScreen`: 12-word text input with validation
- Wired versions connecting UI to business logic

### Phase 5: Startup Routing
**Tasks:** FL_XS_15

Navigation orchestration:
- `StartupRouter` stateful widget with loading state
- Conditional routing based on identity presence
- Error handling with retry capability

### Phase 6: QA & Verification
**Tasks:** QA_XS_01, QA_XS_02, QA_XS_03

Acceptance testing:
- New identity creation flow verification
- Mnemonic restoration flow verification
- App relaunch behavior verification

---

## Identity Data Model

```
┌─────────────────────────────────────────────────────────────┐
│                      IdentityModel                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  peerId: String                                             │
│  ├── libp2p peer identifier                                 │
│  └── Derived from public key                                │
│                                                             │
│  publicKey: String                                          │
│  ├── Base64-encoded Ed25519 public key                      │
│  └── Used for identity verification                         │
│                                                             │
│  privateKey: String                                         │
│  ├── Base64-encoded Ed25519 private key                     │
│  └── Used for signing (stored securely)                     │
│                                                             │
│  mnemonic12: String                                         │
│  ├── 12 BIP39 English words                                 │
│  └── Can regenerate entire identity                         │
│                                                             │
│  createdAt: String                                          │
│  └── ISO-8601 UTC timestamp                                 │
│                                                             │
│  updatedAt: String                                          │
│  └── ISO-8601 UTC timestamp                                 │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## User Flows

### New Identity Creation

```
User                    App                     JS Core                 Database
  │                      │                         │                        │
  │   Opens app          │                         │                        │
  │─────────────────────>│                         │                        │
  │                      │                         │                        │
  │                      │   Check for identity    │                        │
  │                      │────────────────────────────────────────────────> │
  │                      │                         │                        │
  │                      │   No identity found     │                        │
  │                      │<────────────────────────────────────────────────│
  │                      │                         │                        │
  │   Show choice screen │                         │                        │
  │<─────────────────────│                         │                        │
  │                      │                         │                        │
  │   Tap "I'm new here" │                         │                        │
  │─────────────────────>│                         │                        │
  │                      │                         │                        │
  │                      │   Generate identity     │                        │
  │                      │────────────────────────>│                        │
  │                      │                         │                        │
  │                      │   Return identity data  │                        │
  │                      │<────────────────────────│                        │
  │                      │                         │                        │
  │                      │   Save identity         │                        │
  │                      │────────────────────────────────────────────────> │
  │                      │                         │                        │
  │   Navigate to main   │                         │                        │
  │<─────────────────────│                         │                        │
  │                      │                         │                        │
```

### Identity Restoration

```
User                    App                     JS Core                 Database
  │                      │                         │                        │
  │   Opens app          │                         │                        │
  │─────────────────────>│                         │                        │
  │                      │                         │                        │
  │   Show choice screen │                         │                        │
  │<─────────────────────│                         │                        │
  │                      │                         │                        │
  │   Tap "Load my key"  │                         │                        │
  │─────────────────────>│                         │                        │
  │                      │                         │                        │
  │   Show mnemonic input│                         │                        │
  │<─────────────────────│                         │                        │
  │                      │                         │                        │
  │   Enter 12 words     │                         │                        │
  │   Tap "Restore"      │                         │                        │
  │─────────────────────>│                         │                        │
  │                      │                         │                        │
  │                      │   Validate & restore    │                        │
  │                      │────────────────────────>│                        │
  │                      │                         │                        │
  │                      │   Return identity data  │                        │
  │                      │<────────────────────────│                        │
  │                      │                         │                        │
  │                      │   Save identity         │                        │
  │                      │────────────────────────────────────────────────> │
  │                      │                         │                        │
  │   Navigate to main   │                         │                        │
  │<─────────────────────│                         │                        │
  │                      │                         │                        │
```

---

## Error Handling

```
┌─────────────────────────────────────────────────────────────┐
│                     Error Categories                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  GENERATION ERRORS                                          │
│  ├── coreLibError    → JS bridge communication failed       │
│  └── dbError         → Database save operation failed       │
│                                                             │
│  RESTORATION ERRORS                                         │
│  ├── invalidMnemonicFormat  → Word count ≠ 12              │
│  ├── invalidMnemonicCore    → BIP39 checksum invalid       │
│  ├── coreLibError           → JS bridge failed             │
│  └── dbError                → Database save failed         │
│                                                             │
│  STARTUP ERRORS                                             │
│  └── Database read failure  → Show retry screen            │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Flow Events

The application emits structured events for monitoring and debugging:

| Layer | Event Examples |
|-------|----------------|
| **Database** | `ID_DB_LOAD_IDENTITY_START`, `ID_DB_UPSERT_IDENTITY_SUCCESS` |
| **JS Core** | `ID_JS_GENERATE_IDENTITY_SUCCESS`, `ID_JS_RESTORE_IDENTITY_INVALID_MNEMONIC` |
| **Use Cases** | `ID_M1_GENERATE_START`, `ID_M1_RESTORE_JS_OK` |
| **Presentation** | `ID_STARTUP_ROUTE_MAIN`, `ID_BTN_GENERATE_CLICK` |

---

## Getting Started

### Prerequisites
- Flutter SDK (3.x or later)
- Dart SDK
- Xcode (for iOS/macOS)
- Android Studio (for Android)

### Running the App

```bash
# Get dependencies
flutter pub get

# Run on connected device or simulator
flutter run

# Run on specific platform
flutter run -d ios
flutter run -d android
flutter run -d macos
```

### Running Tests

```bash
# Run all tests
flutter test

# Run specific test file
flutter test test/widget_test.dart
```

---

## Technical Stack

- **Framework:** Flutter 3.x
- **Language:** Dart (Flutter), TypeScript (Core Library)
- **Database:** SQLite (via sqflite)
- **Cryptography:**
  - BIP39 (mnemonic generation)
  - Ed25519 (keypair generation)
  - libp2p (peer ID derivation)
- **Architecture:** Clean Architecture with Repository Pattern
- **State Management:** StatefulWidget with Use Cases

---

## License

This project is proprietary software.
