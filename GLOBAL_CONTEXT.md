# Global Context: M2 QR Code Generation

This context is shared across all tasks in the M2 milestone. It defines the canonical data shapes, contracts, and behaviors that all implementations must follow.

---

## Milestone Overview

```
Milestone: M2 – QR Code Generation

Scope:
  - Allow user to display a QR code containing their identity contact information
  - QR payload includes: public key, namespace (peerID), rendezvous point, timestamp
  - Payload is signed with user's private key for authenticity verification
  - Display QR in a chat-app style UI (centered QR with identity info)

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

### Signing Process

The signature is computed over the **unsigned payload** (all fields except `sig`):

```json
{
  "pk": "...",
  "ns": "...",
  "rv": "...",
  "ts": "..."
}
```

1. Construct unsigned payload JSON object
2. Serialize to canonical JSON string (keys sorted alphabetically, no whitespace)
3. Sign the UTF-8 bytes with Ed25519 private key
4. Base64-encode the signature
5. Add `sig` field to create final payload

---

## Constants

```dart
// Flutter constants
const String RENDEZVOUS_ADDRESS = '/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g';
```

```typescript
// JS constants
const RENDEZVOUS_ADDRESS = '/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g';
```

---

## JS Bridge Contract

All communication between Flutter and JS core-lib uses this message-based contract.

### Command: `payload.sign`

**Purpose:** Sign a payload using the user's Ed25519 private key.

**Request:**
```json
{
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
  "ok": true,
  "signature": "base64-encoded-signature"
}
```

**Error Response:**
```json
{
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

## QR Generation Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    QR GENERATION FLOW                           │
└───────────────────────────────────┬─────────────────────────────┘
                                    │
                                    ▼
                      ┌─────────────────────────────┐
                      │  User taps "Show my QR"     │
                      └──────────────┬──────────────┘
                                     │
                                     ▼
                      ┌─────────────────────────────┐
                      │  Load identity from DB      │
                      │  (peerId, publicKey,        │
                      │   privateKey)               │
                      └──────────────┬──────────────┘
                                     │
                    ┌────────────────┴────────────────┐
                    │                                 │
               Identity Found                   No Identity
                    │                                 │
                    ▼                                 ▼
          ┌─────────────────────┐           ┌─────────────────┐
          │  Build unsigned     │           │  Show error:    │
          │  payload:           │           │  "No identity"  │
          │  {pk, ns, rv, ts}   │           └─────────────────┘
          └──────────┬──────────┘
                     │
                     ▼
          ┌─────────────────────┐
          │  Serialize to       │
          │  canonical JSON     │
          └──────────┬──────────┘
                     │
                     ▼
          ┌─────────────────────┐
          │  Call JS bridge     │
          │  payload.sign       │
          └──────────┬──────────┘
                     │
          ┌──────────┴──────────┐
          │                     │
      Sign OK              Sign Error
          │                     │
          ▼                     ▼
   ┌─────────────────┐   ┌─────────────────┐
   │  Add sig to     │   │  Show error     │
   │  payload        │   │  message        │
   └────────┬────────┘   └─────────────────┘
            │
            ▼
   ┌─────────────────┐
   │  Generate QR    │
   │  from JSON      │
   │  string         │
   └────────┬────────┘
            │
            ▼
   ┌─────────────────┐
   │  Display QR     │
   │  screen         │
   └─────────────────┘
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

## Layer Responsibilities

| Layer | Prefix | Responsibility |
|-------|--------|----------------|
| JS Core-Lib | `JS_XS_` | Ed25519 signing, bridge handlers |
| Flutter Domain | `FL_XS_01` | QRPayloadModel |
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

## File Organization

```
lib/
├── core/
│   ├── bridge/
│   │   └── js_bridge_client.dart        # Add callJsSignPayload (FL_XS_02)
│   └── constants/
│       └── network_constants.dart       # RENDEZVOUS_ADDRESS
├── features/
│   └── qr_code/
│       ├── domain/
│       │   └── models/
│       │       └── qr_payload_model.dart    # FL_XS_01
│       ├── application/
│       │   └── build_qr_payload_use_case.dart  # FL_XS_03
│       └── presentation/
│           └── screens/
│               ├── qr_display_screen.dart       # FL_XS_04
│               └── qr_display_wired.dart        # FL_XS_05
└── main.dart

core-lib-js/
├── src/
│   ├── types/
│   │   └── qr_payload.ts               # JS_XS_01
│   ├── signing/
│   │   └── sign_payload.ts             # JS_XS_02
│   └── bridge/
│       └── handlers.ts                 # Add payload.sign handler (JS_XS_03)
├── package.json
└── tsconfig.json
```

---

## UI Design Guidelines

The QR display screen should follow chat-app conventions:

```
┌─────────────────────────────────────┐
│  ←  My QR Code              [close] │
├─────────────────────────────────────┤
│                                     │
│         ┌─────────────────┐         │
│         │                 │         │
│         │    [QR CODE]    │         │
│         │                 │         │
│         │    256x256px    │         │
│         │                 │         │
│         └─────────────────┘         │
│                                     │
│     Scan to connect with me         │
│                                     │
│     ┌─────────────────────────┐     │
│     │  12D3KooW...abc123      │     │
│     │  (your peer ID)         │     │
│     └─────────────────────────┘     │
│                                     │
│         [ Share QR Code ]           │
│                                     │
└─────────────────────────────────────┘
```

Key UI elements:
- Back/close button in header
- Centered QR code (256x256 or larger)
- Helpful instruction text
- Truncated peerID display
- Optional share button
