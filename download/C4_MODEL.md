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
                                      │ cryptographic identity
                                      ▼
                        ┌─────────────────────────────┐
                        │                             │
                        │   Mknoon Identity App       │
                        │   [Software System]         │
                        │                             │
                        │   Allows users to generate  │
                        │   or restore a libp2p       │
                        │   identity using BIP39      │
                        │   mnemonic phrases          │
                        │                             │
                        └─────────────────────────────┘

```

### Description

| Element | Type | Description |
|---------|------|-------------|
| User | Person | End user who wants to create or restore their cryptographic identity |
| Mknoon Identity App | Software System | Mobile/desktop app for identity management using libp2p and BIP39 |

### External Dependencies
- None (fully local, offline-capable)

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
│  ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐ │
│                                                                             │
│  │  ┌───────────────────────────────────────────────────────────────┐    │  │
│     │                     Flutter Application                        │      │
│  │  │                     [Container: Dart/Flutter]                  │   │  │
│     │                                                                │      │
│  │  │  • UI screens and widgets                                      │   │  │
│     │  • Business logic (use cases)                                  │      │
│  │  │  • Repository layer                                            │   │  │
│     │  • Bridge client                                               │      │
│  │  └───────────────────────┬───────────────────┬───────────────────┘   │  │
│                             │                   │                         │
│  │                          │ JSON/WebView      │ SQL queries           │  │
│                             │ Channel           │                         │
│  │                          ▼                   ▼                       │  │
│     ┌─────────────────────────────┐   ┌─────────────────────────────┐     │
│  │  │   JavaScript Runtime        │   │      SQLite Database        │  │  │
│     │   [Container: WebView]      │   │      [Container: sqflite]   │     │
│  │  │                             │   │                             │  │  │
│     │  • BIP39 mnemonic gen       │   │  • identity table           │     │
│  │  │  • Ed25519 keypair          │   │  • Single row (id=1)        │  │  │
│     │  • libp2p peer ID           │   │  • Encrypted storage        │     │
│  │  │  • @libp2p/crypto           │   │                             │  │  │
│     └─────────────────────────────┘   └─────────────────────────────┘     │
│  │                                                                      │  │
│  └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Containers

| Container | Technology | Description |
|-----------|------------|-------------|
| Flutter Application | Dart/Flutter | Main application with UI, business logic, and data access |
| JavaScript Runtime | WebView + esbuild bundle | Executes crypto operations using libp2p libraries |
| SQLite Database | sqflite / sqflite_common_ffi | Persists identity data locally |

### Communication

| From | To | Protocol | Description |
|------|-----|----------|-------------|
| Flutter App | JS Runtime | JSON via JavaScriptChannel | Request/response for identity operations |
| Flutter App | SQLite | SQL via sqflite | CRUD operations for identity persistence |

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
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────┐ │ │
│  │  │  StartupRouter   │  │IdentityChoice    │  │ MnemonicInput        │ │ │
│  │  │  [Widget]        │  │Screen [Widget]   │  │ Screen [Widget]      │ │ │
│  │  │                  │  │                  │  │                      │ │ │
│  │  │  Routes to main  │  │  "I'm new here"  │  │  TextField +         │ │ │
│  │  │  or onboarding   │  │  "Load my key"   │  │  "Restore" button    │ │ │
│  │  └────────┬─────────┘  └────────┬─────────┘  └──────────┬───────────┘ │ │
│  └───────────┼─────────────────────┼────────────────────────┼────────────┘ │
│              │                     │                        │              │
│              ▼                     ▼                        ▼              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                        APPLICATION LAYER                               │ │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────┐ │ │
│  │  │ decideStartup    │  │ generateNew      │  │ restoreIdentity      │ │ │
│  │  │ Route()          │  │ Identity()       │  │ FromMnemonic()       │ │ │
│  │  │ [Use Case]       │  │ [Use Case]       │  │ [Use Case]           │ │ │
│  │  └────────┬─────────┘  └────────┬─────────┘  └──────────┬───────────┘ │ │
│  └───────────┼─────────────────────┼────────────────────────┼────────────┘ │
│              │                     │                        │              │
│              ▼                     ▼                        ▼              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                          DOMAIN LAYER                                  │ │
│  │  ┌──────────────────┐  ┌──────────────────────────────────────────┐   │ │
│  │  │  IdentityModel   │  │        IdentityRepository                │   │ │
│  │  │  [Entity]        │  │        [Interface + Impl]                │   │ │
│  │  │                  │  │                                          │   │ │
│  │  │  peerId          │  │  loadIdentity(): IdentityModel?          │   │ │
│  │  │  publicKey       │  │  saveIdentity(IdentityModel): void       │   │ │
│  │  │  privateKey      │  │                                          │   │ │
│  │  │  mnemonic12      │  │  Maps DB rows ↔ IdentityModel            │   │ │
│  │  │  createdAt       │  │                                          │   │ │
│  │  │  updatedAt       │  │                                          │   │ │
│  │  └──────────────────┘  └────────────────┬─────────────────────────┘   │ │
│  └─────────────────────────────────────────┼─────────────────────────────┘ │
│                                            │                               │
│              ┌─────────────────────────────┼─────────────────────┐         │
│              │                             │                     │         │
│              ▼                             ▼                     ▼         │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                           CORE LAYER                                   │ │
│  │  ┌──────────────────────────┐  ┌──────────────────────────────────┐   │ │
│  │  │     WebViewJsBridge      │  │      Database Helpers            │   │ │
│  │  │     [Bridge Client]      │  │      [DB Access]                 │   │ │
│  │  │                          │  │                                  │   │ │
│  │  │  initialize()            │  │  dbLoadIdentityRow()             │   │ │
│  │  │  send(request): response │  │  dbUpsertIdentityRow()           │   │ │
│  │  │                          │  │  runIdentityTableMigration()     │   │ │
│  │  │  Uses JavaScriptChannel  │  │                                  │   │ │
│  │  └────────────┬─────────────┘  └────────────────┬─────────────────┘   │ │
│  └───────────────┼─────────────────────────────────┼─────────────────────┘ │
└──────────────────┼─────────────────────────────────┼───────────────────────┘
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
│  │  handleRequest(json)       │  │  │  │  peer_id TEXT NOT NULL         │  │
│  │  sendToFlutter(response)   │  │  │  │  public_key TEXT NOT NULL      │  │
│  └──────────┬─────────────────┘  │  │  │  private_key TEXT NOT NULL     │  │
│             │                    │  │  │  mnemonic12 TEXT NOT NULL      │  │
│             ▼                    │  │  │  created_at TEXT NOT NULL      │  │
│  ┌────────────────────────────┐  │  │  │  updated_at TEXT NOT NULL      │  │
│  │    Identity Module         │  │  │  │                                │  │
│  │                            │  │  │  │  Constraint: id = 1 always     │  │
│  │  generateIdentity()        │  │  │  └────────────────────────────────┘  │
│  │  restoreFromMnemonic()     │  │  │                                      │
│  │                            │  │  └──────────────────────────────────────┘
│  │  Uses:                     │  │
│  │  • bip39 (mnemonic)        │  │
│  │  • @libp2p/crypto (keys)   │  │
│  │  • @libp2p/peer-id         │  │
│  └────────────────────────────┘  │
└──────────────────────────────────┘
```

### Flutter Application Components

| Component | Type | Responsibility |
|-----------|------|----------------|
| StartupRouter | Widget | Decides routing based on identity existence |
| IdentityChoiceScreen | Widget | Onboarding UI with two options |
| MnemonicInputScreen | Widget | UI for entering recovery phrase |
| decideStartupRoute() | Use Case | Checks if identity exists |
| generateNewIdentity() | Use Case | Orchestrates identity generation |
| restoreIdentityFromMnemonic() | Use Case | Orchestrates identity restoration |
| IdentityModel | Entity | Immutable data class for identity |
| IdentityRepository | Interface + Impl | Abstracts identity persistence |
| WebViewJsBridge | Bridge Client | Sends requests to JS runtime |
| Database Helpers | DB Access | Low-level SQL operations |

### JavaScript Runtime Components

| Component | Responsibility |
|-----------|----------------|
| Bridge Entry (entry.ts) | Routes incoming requests to handlers |
| generateIdentity() | Creates new BIP39 mnemonic + Ed25519 keypair |
| restoreFromMnemonic() | Derives keypair from existing mnemonic |

---

## Level 4: Code Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              CODE DIAGRAM                                    │
└─────────────────────────────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────────────────┐
│                              FLUTTER CLASSES                                 │
├─────────────────────────────────────────────────────────────────────────────┤

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
  ├─────────────────────────────────────┤
  │ + initialize(): Future<void>        │
  │ + send(message: String): String     │
  │ - _onMessage(JavaScriptMessage)     │
  └─────────────────────────────────────┘


  ┌─────────────────────────────────────┐
  │         IdentityModel               │
  ├─────────────────────────────────────┤
  │ + peerId: String                    │
  │ + publicKey: String                 │
  │ + privateKey: String                │
  │ + mnemonic12: String                │
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
                     │
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


  ┌─────────────────────────────────────┐        ┌─────────────────────────┐
  │         <<enum>>                    │        │      <<enum>>           │
  │         StartupDecision             │        │  GenerateIdentityResult │
  ├─────────────────────────────────────┤        ├─────────────────────────┤
  │ + hasIdentity                       │        │ + success               │
  │ + needsIdentity                     │        │ + coreLibError          │
  └─────────────────────────────────────┘        │ + dbError               │
                                                 └─────────────────────────┘

  ┌─────────────────────────────────────┐
  │         <<enum>>                    │
  │       RestoreIdentityResult         │
  ├─────────────────────────────────────┤
  │ + success                           │
  │ + invalidMnemonicFormat             │
  │ + invalidMnemonicCore               │
  │ + coreLibError                      │
  │ + dbError                           │
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
  │ + errorCode?: string                │
  │ + errorMessage?: string             │
  └─────────────────────────────────────┘

└─────────────────────────────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────────────────┐
│                            FUNCTION SIGNATURES                               │
├─────────────────────────────────────────────────────────────────────────────┤

  FLUTTER USE CASES:
  ──────────────────
  decideStartupRoute(repo: IdentityRepository): Future<StartupDecision>

  generateNewIdentity(
    callJsGenerate: () => Future<Map>,
    repo: IdentityRepository
  ): Future<GenerateIdentityResult>

  restoreIdentityFromMnemonic(
    input: String,
    callJsRestore: (String) => Future<Map>,
    repo: IdentityRepository
  ): Future<RestoreIdentityResult>


  FLUTTER BRIDGE CLIENTS:
  ───────────────────────
  callJsIdentityGenerate(bridge: JsBridge): Future<Map<String, dynamic>>
  callJsIdentityRestore(bridge: JsBridge, mnemonic12: String): Future<Map<String, dynamic>>


  FLUTTER DB HELPERS:
  ───────────────────
  dbLoadIdentityRow(db: Database): Future<Map<String, Object?>?>
  dbUpsertIdentityRow(db: Database, row: Map<String, Object?>): Future<void>
  runIdentityTableMigration(db: Database): Future<void>


  JAVASCRIPT FUNCTIONS:
  ─────────────────────
  generateIdentity(): Promise<IdentityJson>
  restoreIdentityFromMnemonic(mnemonic12: string): Promise<IdentityJson>
  handleRequest(requestJson: string): Promise<void>
  sendToFlutter(response: object): void

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
       │              └──────► IdentityRepository.loadIdentity()
       │
       ├──────► IdentityChoiceWired
       │              │
       │              ├──────► generateNewIdentity()
       │              │              │
       │              │              ├──────► callJsIdentityGenerate()
       │              │              │              │
       │              │              │              └──────► WebViewJsBridge.send()
       │              │              │                             │
       │              │              │                             └──────► [JS] handleRequest()
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
       └──────► MainAppScreen

```

---

## File Structure

```
lib/
├── main.dart                                    # App entry point
├── core/
│   ├── bridge/
│   │   ├── js_bridge_client.dart               # JsBridge interface + helpers
│   │   └── webview_js_bridge.dart              # WebView implementation
│   ├── database/
│   │   ├── migrations/
│   │   │   └── 001_identity_table.dart         # Schema migration
│   │   └── helpers/
│   │       └── identity_db_helpers.dart        # DB CRUD functions
│   └── utils/
│       └── flow_event_emitter.dart             # Logging utility
│
├── features/
│   └── identity/
│       ├── domain/
│       │   ├── models/
│       │   │   └── identity_model.dart         # IdentityModel class
│       │   └── repositories/
│       │       ├── identity_repository.dart    # Abstract interface
│       │       └── identity_repository_impl.dart
│       ├── application/
│       │   ├── startup_decision.dart           # decideStartupRoute()
│       │   ├── generate_identity_use_case.dart
│       │   └── restore_identity_use_case.dart
│       └── presentation/
│           ├── startup_router.dart
│           └── screens/
│               ├── identity_choice_screen.dart
│               ├── identity_choice_wired.dart
│               ├── mnemonic_input_screen.dart
│               └── mnemonic_input_wired.dart

core_lib_js/
├── package.json
├── build.mjs                                   # esbuild config
├── tsconfig.json
├── shims/
│   └── buffer-shim.js                          # Node.js Buffer polyfill
└── src/
    ├── types/
    │   └── identity.ts                         # IdentityJson interface
    ├── identity/
    │   ├── generate.ts                         # generateIdentity()
    │   └── restore.ts                          # restoreIdentityFromMnemonic()
    ├── bridge/
    │   ├── entry.ts                            # WebView entry point
    │   └── handlers.ts                         # Command handlers
    └── utils/
        ├── flow_events.ts
        └── base64.ts                           # Browser-compatible base64

assets/
└── js/
    ├── bridge.html                             # WebView HTML wrapper
    └── core_lib.js                             # Bundled JS (generated)
```

---

## Data Flow Sequence

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
   │  Navigate to Main    │                   │                   │                    │                   │
   │<─────────────────────│                   │                   │                    │                   │
   │                      │                   │                   │                    │                   │
```
