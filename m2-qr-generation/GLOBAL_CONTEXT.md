# Global Context: M2 QR Code Generation

This context is shared across all tasks in the M2 milestone. It defines the canonical data shapes, contracts, and behaviors that all implementations must follow.

---

## Baseline Inventory (from C4_MODEL.md + repo)

| Container/Boundary | Exists in Repo? | Notes |
|--------------------|-----------------|-------|
| Flutter App | Yes | Main mobile application |
| WebView (core-lib JS) | Yes | JavaScript runtime for crypto operations |
| SQLite Database | Yes | Local persistence for identity data |
| IdentityModel | Yes | Domain model with peerId, publicKey, privateKey |
| IdentityRepository | Yes | Repository interface for identity operations |
| JsBridge | Yes | Message-based communication channel |

---

## Boundary Map (baseline + M2 impact)

### Boundary A: Flutter <-> WebView JS

| Direction | Message Type | M2 Impact |
|-----------|--------------|-----------|
| Flutter -> JS | `payload.sign` command | NEW: Sign QR payload data |
| JS -> Flutter | Sign response (ok/error) | NEW: Return signature or error |

### Boundary B: Flutter <-> SQLite

| Direction | Operation | M2 Impact |
|-----------|-----------|-----------|
| Flutter -> SQLite | loadIdentity() | EXISTING: Read identity for QR payload |
| SQLite -> Flutter | IdentityModel? | EXISTING: Return identity or null |

---

## Delta Plan (delta-only)

| Change Type | Component/File Path | Why Needed | How Verified |
|-------------|---------------------|------------|--------------|
| NEW | `lib/features/qr_code/domain/models/qr_payload_model.dart` | Data model for QR payload | Unit test: JSON serialization, canonicalization |
| NEW | `lib/core/bridge/js_bridge_client.dart` (add method) | Call JS for signing | Integration test: sign/verify round-trip |
| NEW | `lib/features/qr_code/application/build_qr_payload_use_case.dart` | Orchestrate QR generation flow | Unit test: happy path + error cases |
| NEW | `lib/features/qr_code/presentation/screens/qr_display_screen.dart` | Stateless QR display UI | Widget test: renders QR, shows error states |
| NEW | `lib/features/qr_code/presentation/screens/qr_display_wired.dart` | Wired screen with dependencies | Integration test: full flow |
| NEW | `core-lib-js/src/signing/sign_payload.ts` | Ed25519 signing function | Unit test: known test vectors |
| MODIFY | `core-lib-js/src/bridge/handlers.ts` | Add payload.sign handler | Integration test: bridge round-trip |
| NEW | `test/qr_smoke_test.dart` | Automated smoke test | CI: runs on every commit |

---

## Milestone Overview

```
Milestone: M2 - QR Code Generation

Scope:
  - Allow user to display a QR code containing their identity contact information
  - QR payload includes: public key, namespace (peerID), rendezvous point, timestamp
  - Payload is signed with user's private key for authenticity verification
  - Display QR in a chat-app style UI (centered QR with identity info)
  - Automated smoke test validates end-to-end flow (identity load -> sign -> QR render)

Tech Stack:
  - Flutter: UI widgets, business logic, repository layer, JS-bridge client, QR generation
  - core-lib JS: Ed25519 signing of payload
  - SQLite: Read identity data (public key, private key, peerID)

Dependencies from M1:
  - IdentityModel: Contains peerId, publicKey, privateKey
  - IdentityRepository: loadIdentity() returns IdentityModel?
  - JsBridge: Message-based communication with JS core-lib
```

---

## Canonical QR Payload JSON

This is the **single source of truth** for QR payload data shape. The QR code will contain this JSON string.

**(no placeholder/demo content)**

```json
{
  "pk": "base64-string",           // User's public key (from identity.publicKey)
  "ns": "string",                  // Namespace = peerID (from identity.peerId)
  "rv": "multiaddr-string",        // Rendezvous point address
  "ts": "ISO-8601-UTC",            // Timestamp when QR was generated
  "sig": "base64-string"           // Ed25519 signature of the payload (excluding sig field)
}
```

### Field Specifications

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| `pk` | string | Base64-encoded Ed25519 public key | `"SGVsbG8gV29ybGQ..."` |
| `ns` | string | Namespace identifier (same as peerID) | `"12D3KooWA1b2C3d4E5f6..."` |
| `rv` | string | Rendezvous multiaddr for P2P connection | `"/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g"` |
| `ts` | string | ISO-8601 UTC timestamp of generation | `"2025-01-22T12:34:56.000Z"` |
| `sig` | string | Base64-encoded Ed25519 signature | `"U2lnbmF0dXJl..."` |

---

## Signing rules (canonicalization is REQUIRED)

The signature is computed over the **unsigned payload** (all fields except `sig`):

```json
{
  "pk": "...",
  "ns": "...",
  "rv": "...",
  "ts": "..."
}
```

**Canonicalization Steps:**

1. Construct unsigned payload JSON object with fields: `pk`, `ns`, `rv`, `ts`
2. **REQUIRED**: Serialize to canonical JSON string:
   - Keys sorted alphabetically: `ns`, `pk`, `rv`, `ts`
   - No whitespace between elements
   - No trailing newlines
3. Sign the UTF-8 bytes of the canonical string with Ed25519 private key
4. Base64-encode the signature (standard base64, no URL-safe variant)
5. Add `sig` field to create final payload

**Example canonical string:**
```
{"ns":"12D3KooW...","pk":"SGVsbG8...","rv":"/dns4/mknoun.xyz/...","ts":"2025-01-22T12:34:56.000Z"}
```

---

## Constants (Flutter single source)

```dart
// lib/core/constants/network_constants.dart
// This is the SINGLE SOURCE OF TRUTH for the rendezvous address.
// Do NOT duplicate this value elsewhere.

const String RENDEZVOUS_ADDRESS = '/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g';
```

---

## JS Bridge Contract (M2 command)

All communication between Flutter and JS core-lib uses this message-based contract.

### Command: `payload.sign`

**Purpose:** Sign a payload using the user's Ed25519 private key.

**Request:**
```json
{
  "requestId": "uuid-string",
  "cmd": "payload.sign",
  "payload": {
    "dataToSign": "canonical-json-string",
    "privateKey": "base64-encoded-private-key"
  }
}
```

**Success Response:**
```json
{
  "requestId": "uuid-string",
  "ok": true,
  "signature": "base64-encoded-signature"
}
```

**Error Response:**
```json
{
  "requestId": "uuid-string",
  "ok": false,
  "errorCode": "SIGNING_ERROR",
  "errorMessage": "Description of what went wrong"
}
```

### Error Codes

| Code | Meaning | Used By |
|------|---------|---------|
| `SIGNING_ERROR` | Failed to sign data | `payload.sign` |
| `INVALID_PRIVATE_KEY` | Private key format invalid | `payload.sign` |
| `INTERNAL_ERROR` | Unexpected error | All commands |

---

## Flow Events (required instrumentation)

All tasks emit flow events for observability. Use this helper pattern.

**IMPORTANT: Do NOT log secrets (private keys, full signatures in production). Redact or omit sensitive fields.**

```dart
// Dart
void emitFlowEvent({
  required String layer,    // "FL" | "JS" | "DB"
  required String event,    // Event name
  required Map<String, dynamic> details,
}) {
  // WARNING: Ensure details does not contain privateKey or other secrets
  final payload = {
    'ts': DateTime.now().toUtc().toIso8601String(),
    'milestone': 'M2_QR_GENERATION',
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
  // WARNING: Ensure details does not contain privateKey or other secrets
  const payload = {
    ts: new Date().toISOString(),
    milestone: 'M2_QR_GENERATION',
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
  QR_FL_PAYLOAD_BUILD_START
  QR_JS_SIGN_PAYLOAD_SUCCESS
  QR_FL_SCREEN_DISPLAY_QR
```

---

## Realness / No-Stub Rules

To ensure production-quality code from the start:

1. **No mock signatures**: All signing must use real Ed25519 operations
2. **No hardcoded test data in production code**: Test fixtures belong in test files only
3. **No TODO comments that bypass functionality**: If a feature is needed, implement it
4. **No stub implementations**: Every function must be fully implemented
5. **Real error handling**: Catch specific errors, provide meaningful messages
6. **Real data flow**: Data must flow through the actual architecture (DB -> Flutter -> JS -> Flutter)

**Verification**: The automated smoke test will fail if any stubs are detected.

---

## File Organization (M2 additions only)

```
lib/
├── core/
│   ├── bridge/
│   │   └── js_bridge_client.dart        # [FL_XS_02] Add callJsSignPayload method
│   └── constants/
│       └── network_constants.dart       # [FL_XS_01] RENDEZVOUS_ADDRESS constant
├── features/
│   └── qr_code/
│       ├── domain/
│       │   └── models/
│       │       └── qr_payload_model.dart    # [FL_XS_01] QRPayloadModel class
│       ├── application/
│       │   └── build_qr_payload_use_case.dart  # [FL_XS_03] BuildQRPayloadUseCase
│       └── presentation/
│           └── screens/
│               ├── qr_display_screen.dart       # [FL_XS_04] Stateless QR display
│               └── qr_display_wired.dart        # [FL_XS_05] Wired screen
└── main.dart

core-lib-js/
├── src/
│   ├── types/
│   │   └── qr_payload.ts               # [JS_XS_01] TypeScript types
│   ├── signing/
│   │   └── sign_payload.ts             # [JS_XS_02] signPayload function
│   └── bridge/
│       └── handlers.ts                 # [JS_XS_03] Add payload.sign handler
├── package.json
└── tsconfig.json

test/
└── qr_smoke_test.dart                  # [QA_XS_01] Automated smoke test
```

---

## Layer Responsibilities

| Layer | Prefix | Responsibility |
|-------|--------|----------------|
| JS Core-Lib | `JS_XS_` | Ed25519 signing, bridge handlers |
| Flutter Domain | `FL_XS_01` | QRPayloadModel, constants |
| Flutter Bridge | `FL_XS_02` | JS communication for signing |
| Flutter Use-Cases | `FL_XS_03` | Business logic orchestration |
| Flutter UI | `FL_XS_04-05` | QR display screen, wiring |
| QA | `QA_XS_` | Test scripts and verification |

---

## Dependency Injection Pattern

All use-cases accept their dependencies as parameters for testability:

```dart
// Good: Dependencies injected
Future<BuildQRPayloadResult> buildQRPayload({
  required IdentityRepository repo,
  required Future<Map<String, dynamic>> Function(String, String) callJsSign,
}) { ... }

// Bad: Dependencies hardcoded
Future<BuildQRPayloadResult> buildQRPayload() {
  final identity = await IdentityRepositoryImpl().loadIdentity(); // Hardcoded!
}
```

---

## UI Design Guidelines

The QR display screen should follow chat-app conventions:

```
+-----------------------------------------+
|  <-  My QR Code                 [close] |
+-----------------------------------------+
|                                         |
|         +---------------------+         |
|         |                     |         |
|         |      [QR CODE]      |         |
|         |                     |         |
|         |      256x256px      |         |
|         |                     |         |
|         +---------------------+         |
|                                         |
|       Scan to connect with me           |
|                                         |
|       +-------------------------+       |
|       |  12D3KooW...abc123      |       |
|       |  (your peer ID)         |       |
|       +-------------------------+       |
|                                         |
|           [ Share QR Code ]             |
|                                         |
+-----------------------------------------+
```

Key UI elements:
- Back/close button in header
- Centered QR code (256x256 or larger)
- Helpful instruction text
- Truncated peerID display
- Optional share button
