# Global Context: M2 QR Code Generation

This context is shared across all tasks in the M2 milestone. It defines the canonical data shapes, runtime boundaries, and verification gates that all implementations must follow.

---

## Baseline Inventory (from C4_MODEL.md + repo)

### Existing containers and boundaries (REAL runtime path)

1) **Flutter Application (Dart/Flutter)**
- Owns UI + use cases + repository layer.
- Crosses boundaries:
  - **Flutter ↔ WebView JS runtime** via JSON messages over a real WebView JavaScriptChannel.
  - **Flutter ↔ SQLite** via sqflite (or sqflite_common_ffi on desktop).

2) **JavaScript Runtime (WebView)**
- Executes the bundled core library from `assets/js/core_lib.js` (built from `core_lib_js/`).
- Receives JSON requests from Flutter and responds via the same channel.

3) **SQLite Database**
- Persists identity locally (M1): single-row identity record (id=1).

### Baseline components and file paths to REUSE (do not re-invent)

Flutter (M1):
- WebView bridge runtime: `lib/core/bridge/webview_js_bridge.dart`
- Bridge client helpers: `lib/core/bridge/js_bridge_client.dart`
- Identity entity: `lib/features/identity/domain/models/identity_model.dart`
- Identity repository interface + impl:
  - `lib/features/identity/domain/repositories/identity_repository.dart`
  - `lib/features/identity/domain/repositories/identity_repository_impl.dart`
- Flow logging utility: `lib/core/utils/flow_event_emitter.dart`
- DB helpers + migration:
  - `lib/core/database/helpers/identity_db_helpers.dart`
  - `lib/core/database/migrations/001_identity_table.dart`

JavaScript (M1):
- Bridge entry + handler routing:
  - `core_lib_js/src/bridge/entry.ts`
  - `core_lib_js/src/bridge/handlers.ts`
- Base64 utilities (browser-safe): `core_lib_js/src/utils/base64.ts`
- Flow logging utility: `core_lib_js/src/utils/flow_events.ts`
- Build/bundle pipeline:
  - `core_lib_js/build.mjs`
  - Output asset: `assets/js/core_lib.js`
  - WebView wrapper: `assets/js/bridge.html`

---

## Boundary Map (baseline + M2 impact)

### Boundary A — Flutter ↔ WebView JS (payload signing)

- Protocol: JSON request/response over the existing WebView JavaScriptChannel.
- Envelope shape (baseline):
  - Request includes **requestId** for correlation.
  - Response echoes the same **requestId**.
- Entry points:
  - Flutter sends via `JsBridgeClient` → `WebViewJsBridge`
  - JS receives via `core_lib_js/src/bridge/entry.ts` and routes via `handlers.ts`

**M2 touches this boundary by adding one command: `payload.sign`.**

Handshake requirement (verification):
- The milestone smoke test MUST prove the runtime bridge is real by successfully executing at least one JS command over the WebView path (not a mock).

### Boundary B — Flutter ↔ SQLite (load identity)

- Protocol: sqflite queries through the existing M1 repository/helpers.
- M2 reads identity via `IdentityRepository.loadIdentity()`.

Handshake requirement (verification):
- The milestone smoke test MUST prove real DB persistence by saving and reloading identity (no in-memory stub).

---

## Delta Plan (delta-only)

| Change Type | Component / File Path | Why Needed (MVP) | How Verified (Runnable) |
|---|---|---|---|
| REUSE | `lib/core/bridge/webview_js_bridge.dart` | Real Flutter↔JS runtime boundary | `flutter run -t lib/smoke_test_m2_qr_generation.dart` prints PASS |
| REUSE | `core_lib_js/build.mjs` → `assets/js/core_lib.js` | JS must run inside WebView | `cd core_lib_js && npm run build` then smoke test |
| MODIFY | `core_lib_js/src/bridge/handlers.ts` | Add `payload.sign` handler | Smoke test exercises `payload.sign` via WebView |
| ADD | `core_lib_js/src/types/qr_payload.ts` | Canonical QR payload types | `npx tsc -p tsconfig.json --noEmit` |
| ADD | `core_lib_js/src/signing/sign_payload.ts` | Real Ed25519 signing | Smoke test checks signature realness (non-constant, base64, changes with input) |
| MODIFY | `lib/core/bridge/js_bridge_client.dart` | Add `callJsSignPayload()` using baseline envelope | Smoke test uses real call + checks requestId correlation |
| ADD | `lib/features/qr_code/**` | QR payload model + use case + UI | Smoke test validates produced QR JSON + manual UI check |
| ADD (if missing) | `lib/core/constants/network_constants.dart` | Single source for rendezvous multiaddr | Smoke test validates `rv` equals constant |
| ADD | `lib/smoke_test_m2_qr_generation.dart` | Automated runnable gate | `flutter run -t lib/smoke_test_m2_qr_generation.dart ...` prints PASS |

---

## Milestone Overview

```
Milestone: M2 – QR Code Generation

Scope:
  - Allow user to display a QR code containing their identity contact information
  - QR payload includes: public key, namespace (peerID), rendezvous point, timestamp
  - Payload is signed with user's private key for authenticity verification
  - Provide an automated smoke test that exercises REAL runtime boundaries (WebView + SQLite)
```

---

## Canonical QR Payload JSON

The QR code MUST contain this JSON string (no placeholder/demo content).

```json
{
  "pk": "base64-string",           // User's public key (from identity.publicKey)
  "ns": "string",                  // Namespace = peerID (from identity.peerId)
  "rv": "multiaddr-string",        // Rendezvous point address (constant)
  "ts": "ISO-8601-UTC",            // Timestamp when QR was generated
  "sig": "base64-string"           // Ed25519 signature of the unsigned payload (excluding sig field)
}
```

### Signing rules (canonicalization is REQUIRED)

Signature is computed over the **unsigned payload** (all fields except `sig`):

```json
{
  "pk": "...",
  "ns": "...",
  "rv": "...",
  "ts": "..."
}
```

Rules:
1. Build the unsigned payload map with **exact keys**: `pk`, `ns`, `rv`, `ts`.
2. Serialize to a **canonical JSON string**:
   - keys sorted alphabetically
   - no extra whitespace/newlines
3. Sign the UTF-8 bytes using the identity private key (M1).
4. Base64-encode the signature bytes.
5. Add `sig` and serialize the final payload to canonical JSON.

---

## Constants (Flutter single source)

`RENDEZVOUS_ADDRESS` must be defined once in Flutter and reused by all M2 code:

```dart
// lib/core/constants/network_constants.dart
const String RENDEZVOUS_ADDRESS =
    '/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g';
```

---

## JS Bridge Contract (M2 command)

All M2 communication MUST follow the baseline envelope used by M1 (includes requestId).

### Command: `payload.sign`

Purpose: sign a canonical JSON string using the user's private key.

Request:
```json
{
  "cmd": "payload.sign",
  "requestId": "string",
  "payload": {
    "dataToSign": "canonical-json-string",
    "privateKey": "base64-encoded-private-key"
  }
}
```

Success response:
```json
{
  "ok": true,
  "requestId": "string",
  "signature": "base64-encoded-signature"
}
```

Error response:
```json
{
  "ok": false,
  "requestId": "string",
  "errorCode": "SIGNING_ERROR|INVALID_PRIVATE_KEY|INTERNAL_ERROR",
  "errorMessage": "Description of what went wrong"
}
```

---

## Flow Events (required instrumentation)

Flow events are used for debugging and tracing. They must not leak secrets.

**Do NOT emit/log the full `privateKey` or `mnemonic12`.** If needed, emit only lengths or a short prefix.

Flutter (emit via `lib/core/utils/flow_event_emitter.dart`):
- `QR_FL_PAYLOAD_BUILD_START`
- `QR_FL_PAYLOAD_BUILD_SUCCESS`
- `QR_FL_PAYLOAD_BUILD_ERROR` (include `errorCode`)
- `QR_FL_BRIDGE_SIGN_REQUEST` (include `requestId` if available; do not log privateKey)
- `QR_FL_BRIDGE_SIGN_RESPONSE` (include `ok` + `errorCode` if any)

JavaScript (emit via `core_lib_js/src/utils/flow_events.ts`):
- `QR_JS_SIGN_PAYLOAD_START`
- `QR_JS_SIGN_PAYLOAD_SUCCESS`
- `QR_JS_SIGN_PAYLOAD_ERROR`

UI (optional, emit when opening/closing the QR screen):
- `QR_UI_DISPLAY_OPEN`
- `QR_UI_DISPLAY_CLOSE`

---

## Realness / No-Stub Rules (apply to ALL tasks)

M2 is invalid if any of these are true:
- A fake/simulated JS bridge is used in the smoke test.
- Any output contains obvious stub markers: `demo`, `placeholder`, `fake`, `stub`, `TODO`, `simulate`.
- QR payload uses hard-coded keys/peerIds instead of values loaded from the real identity record.
- JS bundle is not rebuilt after adding `payload.sign` (TS changes must reach `assets/js/core_lib.js`).

---

## File Organization (M2 additions only)

```
lib/
├── core/
│   └── constants/
│       └── network_constants.dart                 # (M2) RENDEZVOUS_ADDRESS
├── features/
│   └── qr_code/
│       ├── domain/models/qr_payload_model.dart    # (M2) FL_XS_01
│       ├── application/build_qr_payload_use_case.dart # (M2) FL_XS_03
│       └── presentation/screens/
│           ├── qr_display_screen.dart             # (M2) FL_XS_04
│           └── qr_display_wired.dart              # (M2) FL_XS_05
└── smoke_test_m2_qr_generation.dart               # (M2) QA_XS_01 (automated gate)

core_lib_js/
├── src/
│   ├── types/qr_payload.ts                        # (M2) JS_XS_01
│   ├── signing/sign_payload.ts                    # (M2) JS_XS_02
│   └── bridge/handlers.ts                         # (M2) JS_XS_03 (modify)
└── build.mjs                                      # (M1) bundle pipeline → assets/js/core_lib.js

assets/js/
├── bridge.html                                    # (M1) WebView wrapper
└── core_lib.js                                    # (generated) DO NOT EDIT
```
