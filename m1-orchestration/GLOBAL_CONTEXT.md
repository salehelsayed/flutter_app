# Global Context: M1 Identity Initialization

This context is shared across all tasks in the M1 milestone. It defines the canonical data shapes, contracts, and behaviors that all implementations must follow.

---

## Milestone Overview

```
Milestone: M1 – Identity Initialization (First Run)

Scope:
  - On first app launch, if no identity in DB → show identity onboarding:
      - Button A: "I'm new here" → generate new identity
      - Button B: "Load my key"  → restore identity from 12-word mnemonic
  - In both paths, persist identity in local DB and show success message
  - On subsequent launches, if identity exists → go directly to main app

Tech Stack:
  - Flutter: UI widgets, business logic, repository layer, JS-bridge client
  - core-lib JS: Identity generation and restore, exposed via message-based bridge
  - SQLite: Local encrypted database storing exactly one active identity row
```

---

## Canonical Identity JSON

This is the **single source of truth** for identity data shape. All layers must use this exact structure when exchanging identity data.

```json
{
  "peerId": "string",              // libp2p peer ID (text form, e.g., "12D3KooW...")
  "publicKey": "base64-string",    // base64-encoded public key bytes
  "privateKey": "base64-string",   // base64-encoded private key bytes
  "mnemonic12": "word1 ... word12",// 12 BIP39 words separated by single spaces
  "createdAt": "ISO-8601-UTC",     // e.g., "2025-11-28T12:34:56.000Z"
  "updatedAt": "ISO-8601-UTC"      // e.g., "2025-11-28T12:34:56.000Z"
}
```

### Field Specifications

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| `peerId` | string | libp2p peer ID derived from public key | `"12D3KooWA1b2C3d4E5f6..."` |
| `publicKey` | string | Base64-encoded Ed25519 public key (32 bytes) | `"SGVsbG8gV29ybGQ..."` |
| `privateKey` | string | Base64-encoded Ed25519 private key (64 bytes) | `"U2VjcmV0S2V5..."` |
| `mnemonic12` | string | 12 BIP39 English words, space-separated | `"abandon ability able..."` |
| `createdAt` | string | ISO-8601 UTC timestamp of creation | `"2025-11-28T12:34:56.000Z"` |
| `updatedAt` | string | ISO-8601 UTC timestamp of last update | `"2025-11-28T12:34:56.000Z"` |

---

## Database Schema

```sql
CREATE TABLE IF NOT EXISTS identity (
  id INTEGER PRIMARY KEY,          -- Always 1 (single active identity)
  peer_id TEXT NOT NULL,           -- libp2p peer ID
  public_key TEXT NOT NULL,        -- base64-encoded
  private_key TEXT NOT NULL,       -- base64-encoded (sensitive!)
  mnemonic12 TEXT NOT NULL,        -- 12 words space-separated (sensitive!)
  created_at TEXT NOT NULL,        -- ISO-8601-UTC
  updated_at TEXT NOT NULL         -- ISO-8601-UTC
);
```

### Constraints
- There is **at most one** active identity row with `id = 1`
- The `private_key` and `mnemonic12` fields contain sensitive data

### Column Mapping (JSON ↔ DB)

| JSON Field | DB Column | Notes |
|------------|-----------|-------|
| `peerId` | `peer_id` | Direct mapping |
| `publicKey` | `public_key` | Direct mapping |
| `privateKey` | `private_key` | Direct mapping |
| `mnemonic12` | `mnemonic12` | Direct mapping |
| `createdAt` | `created_at` | Direct mapping |
| `updatedAt` | `updated_at` | Direct mapping |

---

## JS Bridge Contract

All communication between Flutter and JS core-lib uses this message-based contract.

### Command: `identity.generate`

**Purpose:** Generate a new identity with fresh keypair and mnemonic.

**Request:**
```json
{
  "cmd": "identity.generate",
  "payload": {}
}
```

**Success Response:**
```json
{
  "ok": true,
  "identity": {
    "peerId": "12D3KooW...",
    "publicKey": "base64...",
    "privateKey": "base64...",
    "mnemonic12": "word1 word2 ... word12",
    "createdAt": "2025-11-28T12:34:56.000Z",
    "updatedAt": "2025-11-28T12:34:56.000Z"
  }
}
```

**Error Response:**
```json
{
  "ok": false,
  "errorCode": "INTERNAL_ERROR",
  "errorMessage": "Description of what went wrong"
}
```

### Command: `identity.restore`

**Purpose:** Restore identity from existing 12-word mnemonic.

**Request:**
```json
{
  "cmd": "identity.restore",
  "payload": {
    "mnemonic12": "word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12"
  }
}
```

**Success Response:**
```json
{
  "ok": true,
  "identity": {
    "peerId": "12D3KooW...",
    "publicKey": "base64...",
    "privateKey": "base64...",
    "mnemonic12": "word1 word2 ... word12",
    "createdAt": "2025-11-28T12:34:56.000Z",
    "updatedAt": "2025-11-28T12:34:56.000Z"
  }
}
```

**Error Responses:**
```json
// Invalid mnemonic (wrong words, wrong count, bad checksum)
{
  "ok": false,
  "errorCode": "INVALID_MNEMONIC",
  "errorMessage": "Mnemonic validation failed: invalid word count"
}

// Other errors
{
  "ok": false,
  "errorCode": "INTERNAL_ERROR",
  "errorMessage": "Description of what went wrong"
}
```

### Error Codes

| Code | Meaning | Used By |
|------|---------|---------|
| `INVALID_MNEMONIC` | Mnemonic failed validation | `identity.restore` |
| `INTERNAL_ERROR` | Unexpected error | Both commands |

---

## App Startup Behavior

```
┌─────────────────────────────────────────────────────────────────┐
│                        APP STARTUP                              │
└─────────────────────────────────┬───────────────────────────────┘
                                  │
                                  ▼
                    ┌─────────────────────────────┐
                    │  Load identity from DB      │
                    │  (SELECT WHERE id = 1)      │
                    └─────────────┬───────────────┘
                                  │
                    ┌─────────────┴─────────────┐
                    │                           │
               Row Found                   No Row Found
                    │                           │
                    ▼                           ▼
          ┌─────────────────┐       ┌─────────────────────┐
          │  Go to Main App │       │  Show Onboarding    │
          │  (identity      │       │  IdentityChoice     │
          │   cached)       │       │  Screen             │
          └─────────────────┘       └─────────────────────┘
```

---

## Flow Events

All tasks emit flow events for observability. Use this helper pattern:

```dart
// Dart
void emitFlowEvent({
  required String layer,    // "FL" | "JS" | "DB"
  required String event,    // Event name
  required Map<String, dynamic> details,
}) {
  final payload = {
    'ts': DateTime.now().toUtc().toIso8601String(),
    'milestone': 'M1_IDENTITY_INIT',
    'layer': layer,
    'event': event,
    'details': details,
  };
  // Log or send to telemetry
  print('[FLOW] ${jsonEncode(payload)}');
}
```

```javascript
// JavaScript
function emitFlowEvent({ layer, event, details }) {
  const payload = {
    ts: new Date().toISOString(),
    milestone: 'M1_IDENTITY_INIT',
    layer,
    event,
    details,
  };
  console.log('[FLOW]', JSON.stringify(payload));
}
```

### Event Naming Convention

```
{MILESTONE}_{LAYER}_{ENTITY}_{ACTION}_{RESULT}

Examples:
  ID_DB_IDENTITY_MIGRATION_START
  ID_FL_REPO_LOAD_IDENTITY_SUCCESS
  ID_JS_GENERATE_IDENTITY_ERROR
```

---

## Layer Responsibilities

| Layer | Prefix | Responsibility |
|-------|--------|----------------|
| Database | `DB_XS_` | Schema, migrations, raw CRUD operations |
| Flutter Domain | `FL_XS_01-04` | Models, repository interface & implementation |
| Flutter Use-Cases | `FL_XS_05-07` | Business logic orchestration |
| Flutter Bridge | `FL_XS_08-09` | JS communication helpers |
| Flutter UI | `FL_XS_10-15` | Screens, widgets, navigation |
| JS Core-Lib | `JS_XS_` | Identity generation, restoration, crypto |
| QA | `QA_XS_` | Test scripts and verification |

---

## Dependency Injection Pattern

All use-cases accept their dependencies as parameters for testability:

```dart
// Good: Dependencies injected
Future<Result> generateNewIdentity({
  required Future<Map<String, dynamic>> Function() callJsGenerate,
  required IdentityRepository repo,
}) { ... }

// Bad: Dependencies hardcoded
Future<Result> generateNewIdentity() {
  final response = await JsBridge.generate(); // Hardcoded!
  await IdentityRepositoryImpl().save(...);   // Hardcoded!
}
```

---

## File Organization

```
lib/
├── core/
│   ├── database/
│   │   ├── database_helper.dart
│   │   ├── migrations/
│   │   │   └── 001_identity_table.dart
│   │   └── helpers/
│   │       └── identity_db_helpers.dart
│   ├── bridge/
│   │   └── js_bridge.dart
│   └── flow_events/
│       └── flow_event_emitter.dart
├── features/
│   └── identity/
│       ├── domain/
│       │   ├── models/
│       │   │   └── identity_model.dart
│       │   └── repositories/
│       │       ├── identity_repository.dart
│       │       └── identity_repository_impl.dart
│       ├── application/
│       │   ├── startup_decision.dart
│       │   ├── generate_identity_use_case.dart
│       │   └── restore_identity_use_case.dart
│       └── presentation/
│           ├── screens/
│           │   ├── identity_choice_screen.dart
│           │   └── mnemonic_input_screen.dart
│           └── startup_router.dart
└── main.dart

core-lib-js/
├── src/
│   ├── types/
│   │   └── identity.ts
│   ├── identity/
│   │   ├── generate.ts
│   │   └── restore.ts
│   └── bridge/
│       └── handlers.ts
├── package.json
└── tsconfig.json
```
