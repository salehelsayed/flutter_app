Change Summary

Files changed:

* m2-qr-generation/README.md
* m2-qr-generation/GLOBAL_CONTEXT.md
* m2-qr-generation/execution-order.md
* m2-qr-generation/file-structure.md
* m2-qr-generation/verification-checklist.md
* m2-qr-generation/tasks/JS_XS_01.md
* m2-qr-generation/tasks/JS_XS_02.md
* m2-qr-generation/tasks/JS_XS_03.md
* m2-qr-generation/tasks/FL_XS_01.md
* m2-qr-generation/tasks/FL_XS_02.md
* m2-qr-generation/tasks/FL_XS_03.md
* m2-qr-generation/tasks/FL_XS_04.md
* m2-qr-generation/tasks/FL_XS_05.md
* m2-qr-generation/tasks/QA_XS_01.md

Files added:

* (none)

--- a/m2-qr-generation/README.md
+++ b/m2-qr-generation/README.md
@@ -1,81 +1,109 @@
-# M2 QR Code Generation - Orchestration Package
------------------------------------------------

## -## Overview

## -This package contains everything needed to implement the M2 QR Code Generation milestone using AI coding agents. Each task is self-contained and can be executed independently.

## -## Prerequisites

-- Milestone 1 must be completed:

* * Identity generation and storage must be working
* * Flutter <-> JS bridge must be established
* * core-lib-js bundling pipeline must exist
*

## -## Package Contents

-```
-m2-qr-generation/
-├── README.md                      # This file
-├── GLOBAL_CONTEXT.md              # Shared context (included in every task)
-├── execution-order.md             # Sequence and parallelization guide
-├── verification-checklist.md      # How to verify each task
-├── file-structure.md              # Where to put generated code
-└── tasks/

* ├── JS_XS_01.md                # JS: QRPayloadJson type definition
* ├── JS_XS_02.md                # JS: signPayload() implementation
* ├── JS_XS_03.md                # JS: Bridge handler for payload.sign
* ├── FL_XS_01.md                # Flutter: QRPayloadModel
* ├── FL_XS_02.md                # Flutter: callJsSignPayload() bridge
* ├── FL_XS_03.md                # Flutter: buildQRPayload use case
* ├── FL_XS_04.md                # Flutter: QRDisplayScreen layout
* ├── FL_XS_05.md                # Flutter: Wire QRDisplayScreen
* └── QA_XS_01.md                # QA: Test script
  -```
*

## -## Feature Summary

-**User Story:**
-As a user, I want to display a QR code containing my identity information so that others can scan it to connect with me.
-------------------------------------------------------------------------------------------------------------------------

-**QR Payload Contents:**
-- Public key (pk)
-- Namespace/PeerID (ns)
-- Rendezvous point address (rv)
-- Timestamp (ts)
-- Signature (sig) - Ed25519 signature of payload
-------------------------------------------------

## -## How to Use

## -### Step 1: Follow `execution-order.md`

## -This provides the recommended sequence for task execution, including parallel tasks.

## -### Step 2: Execute tasks and place outputs

## -For each task:

-1. Open the task file (e.g., `tasks/JS_XS_01.md`)
-2. Copy the **entire contents**
-3. Paste to your AI coding agent
-4. Apply the generated code to the repo at the paths specified in `file-structure.md`
-5. Run the verification steps from `verification-checklist.md`
---------------------------------------------------------------

## -### Step 3: Verify milestone completion

## -Complete the QA test script in `tasks/QA_XS_01.md` to ensure everything works end-to-end.

## -## Dependencies

-**Flutter:**
-- qr_flutter package for QR code rendering
-------------------------------------------

-**JavaScript:**
-- @noble/ed25519 or @libp2p/crypto for signing
+# M2 QR Code Generation - Orchestration Package
+
+## Overview
+
+This package contains everything needed to implement the **M2 QR Code Generation** milestone using AI coding agents. Each task is self-contained and can be executed independently.
+
+**Milestone gate:** M2 is only DONE when the automated smoke test in `QA_XS_01` prints **PASS** using the **real runtime path** (Flutter ↔ WebView JS bridge ↔ core_lib_js bundle AND Flutter ↔ SQLite via the real `IdentityRepository`).
+
+## Prerequisites (from M1 - must be REAL, not simulated)
+
+- Identity data exists and is persisted locally:

* * `IdentityModel` with `peerId`, `publicKey`, `privateKey`
* * `IdentityRepository.loadIdentity()` reads from SQLite (not an in-memory stub)
*

+- Real Flutter ↔ JS runtime bridge (no fake bridge clients):

* * `lib/core/bridge/webview_js_bridge.dart` loads `assets/js/bridge.html`
* * `assets/js/bridge.html` loads `assets/js/core_lib.js`
* * Requests/responses are JSON over the WebView JavaScriptChannel (see `C4_MODEL.md`)
*

+- JS bundling pipeline exists and produces the runtime asset:

* * `core_lib_js/build.mjs` (esbuild)
* * `cd core_lib_js && npm install && npm run build`
* * Output: `assets/js/core_lib.js` (do not hand-edit)
*

+## Package Contents
+
+```
+m2-qr-generation/
+├── README.md                      # This file
+├── GLOBAL_CONTEXT.md              # Shared context (included in every task)
+├── execution-order.md             # Sequence and parallelization guide
+├── verification-checklist.md      # How to verify each task
+├── file-structure.md              # Where to put generated code
+└── tasks/

* ├── JS_XS_01.md                # JS: QRPayloadJson type definition
* ├── JS_XS_02.md                # JS: signPayload() implementation
* ├── JS_XS_03.md                # JS: Bridge handler for payload.sign (+ rebuild bundle)
* ├── FL_XS_01.md                # Flutter: QRPayloadModel
* ├── FL_XS_02.md                # Flutter: callJsSignPayload() bridge
* ├── FL_XS_03.md                # Flutter: buildQRPayload use case (+ rendezvous constant)
* ├── FL_XS_04.md                # Flutter: QRDisplayScreen layout (qr_flutter)
* ├── FL_XS_05.md                # Flutter: Wire QRDisplayScreen
* └── QA_XS_01.md                # QA: Automated smoke test (M2 gate) + optional manual steps
  +```
*

+## Feature Summary
+
+**User Story:**
+As a user, I want to display a QR code containing my identity information so that others can scan it to connect with me.
+
+**QR Payload Contents:**
+- `pk`: public key (base64; from M1 identity)
+- `ns`: namespace/peerID (from M1 identity)
+- `rv`: rendezvous multiaddr (constant)
+- `ts`: timestamp (UTC ISO-8601)
+- `sig`: Ed25519 signature of the canonical unsigned payload
+
+## How to Use
+
+### Step 1: Follow `execution-order.md`
+
+It includes:
+- baseline pre-flight checks (M1 bridge + JS bundle),
+- required build steps (`npm run build`),
+- and the automated smoke test command.
+
+### Step 2: Execute tasks and place outputs
+
+For each task:
+
+1. Open the task file (e.g., `tasks/JS_XS_01.md`)
+2. Copy the **entire contents**
+3. Paste to your AI coding agent
+4. Apply the generated code to the repo at the exact paths in `file-structure.md`
+5. Run the task's verification commands
+
+### Step 3: Run the milestone gate (automated smoke test)
+
+`QA_XS_01` provides the required command. It must:
+- run against a real emulator/device,
+- initialize the real WebView JS runtime,
+- read/write the real SQLite identity row,
+- and print `PASS` (otherwise treat as failing).
+
+## Dependencies
+
+**Flutter:**
+- `qr_flutter` (for QR rendering)
+
+**JavaScript:**
+- Reuse M1 crypto dependencies already present (per `C4_MODEL.md`), do NOT introduce new crypto libs unless the real smoke test proves it is required.

--- a/m2-qr-generation/GLOBAL_CONTEXT.md
+++ b/m2-qr-generation/GLOBAL_CONTEXT.md
@@ -1,216 +1,252 @@
-# Global Context: M2 QR Code Generation
----------------------------------------

## -This context is shared across all tasks in the M2 milestone. It defines the canonical data shapes, signing algorithms, and interface contracts that all implementations must follow.

---

*

## -## Milestone Overview

-```
-Milestone: M2 – QR Code Generation
-----------------------------------

-Scope:

* * Allow user to display a QR code containing their identity contact information
* * QR payload includes: public key, namespace (peerID), rendezvous point, timestamp
* * Payload is signed with user's private key for authenticity verification
    -```
*

---

*

## -## Canonical QR Payload JSON

## -The QR code MUST contain this JSON string:

-```json
-{

* "pk": "base64-string",           // User's public key
* "ns": "string",                  // Namespace = peerID
* "rv": "multiaddr-string",        // Rendezvous point address
* "ts": "ISO-8601-UTC",            // Timestamp when QR was generated
* "sig": "base64-string"           // Ed25519 signature of the payload
  -}
  -```
*

## -### Signing Rules

## -Signature is computed over the unsigned payload (all fields except sig):

-```json
-{

* "pk": "...",
* "ns": "...",
* "rv": "...",
* "ts": "..."
  -}
  -```
*

-Rules:
-1. Sort keys alphabetically
-2. Serialize to canonical JSON (no extra whitespace)
-3. Sign UTF-8 bytes of this JSON string with Ed25519 private key
-4. Base64-encode signature
-5. Add sig field to payload
----------------------------

---

*

## -## Constants

## -### Rendezvous Address

## -The rendezvous point is a fixed constant:

-`
-RENDEZVOUS_ADDRESS = "/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g"
-`
--

-This should be defined in:
-- Flutter: `lib/core/constants/network_constants.dart`
-- JS: (if needed) `core-lib-js/src/constants/network.ts`
---------------------------------------------------------

---

*

## -## JS Bridge Contract

## -### Command: `payload.sign`

## -Purpose: sign a canonical JSON string using the user's private key.

-Request:
-```json
-{

* "cmd": "payload.sign",
* "payload": {
* "dataToSign": "canonical-json-string",
* "privateKey": "base64-encoded-private-key"
* }
  -}
  -```
*

-Response:
-```json
-{

* "ok": true,
* "signature": "base64-encoded-signature"
  -}
  -```
*

-Error response:
-```json
-{

* "ok": false,
* "error": "error-message"
  -}
  -```
*

---

*

## -## QR Generation Flow

-1. Flutter loads identity from local SQLite DB:

* * peerId, publicKey, privateKey
*

-2. Flutter builds unsigned payload:

* * pk = publicKey
* * ns = peerId
* * rv = RENDEZVOUS_ADDRESS
* * ts = current UTC timestamp
*

## -3. Flutter serializes unsigned payload to canonical JSON string

-4. Flutter calls JS bridge:

* * cmd: payload.sign
* * dataToSign: canonical JSON string
* * privateKey: base64 private key
*

## -5. JS signs payload and returns signature

## -6. Flutter builds final payload with sig and renders QR code

---

*

## -## Flow Events

## -The following flow events should be emitted for debugging:

-### Flutter Events
-- QR_FL_PAYLOAD_BUILD_START
-- QR_FL_PAYLOAD_BUILD_SUCCESS
-- QR_FL_PAYLOAD_BUILD_ERROR
-- QR_FL_BRIDGE_SIGN_REQUEST
-- QR_FL_BRIDGE_SIGN_RESPONSE
-- QR_UI_DISPLAY_OPEN
-- QR_UI_DISPLAY_CLOSE
----------------------

-### JS Events
-- QR_JS_SIGN_PAYLOAD_START
-- QR_JS_SIGN_PAYLOAD_SUCCESS
-- QR_JS_SIGN_PAYLOAD_ERROR
---------------------------

---

*

## -## File Organization

## -### Flutter Files

-`
-lib/
-├── core/
-│   └── constants/
-│       └── network_constants.dart                 # RENDEZVOUS_ADDRESS
-├── features/
-│   └── qr_code/
-│       ├── domain/models/qr_payload_model.dart    # QRPayloadModel
-│       ├── application/build_qr_payload_use_case.dart # buildQRPayload use case
-│       └── presentation/screens/
-│           ├── qr_display_screen.dart             # QRDisplayScreen layout
-│           └── qr_display_wired.dart              # Wiring
-`
--

## -### JavaScript Files

-`
-core-lib-js/
-├── src/
-│   ├── types/qr_payload.ts                        # QR payload types
-│   ├── signing/sign_payload.ts                    # signPayload implementation
-│   └── bridge/handlers.ts                         # payload.sign handler
-`
+# Global Context: M2 QR Code Generation
+
+This context is shared across all tasks in the M2 milestone. It defines the canonical data shapes, runtime boundaries, and verification gates that all implementations must follow.
+
+---
+
+## Baseline Inventory (from C4_MODEL.md + repo)
+
+### Existing containers and boundaries (REAL runtime path)
+
+1) **Flutter Application (Dart/Flutter)**
+- Owns UI + use cases + repository layer.
+- Crosses boundaries:

* * **Flutter ↔ WebView JS runtime** via JSON messages over a real WebView JavaScriptChannel.
* * **Flutter ↔ SQLite** via sqflite (or sqflite_common_ffi on desktop).
*

+2) **JavaScript Runtime (WebView)**
+- Executes the bundled core library from `assets/js/core_lib.js` (built from `core_lib_js/`).
+- Receives JSON requests from Flutter and responds via the same channel.
+
+3) **SQLite Database**
+- Persists identity locally (M1): single-row identity record (id=1).
+
+### Baseline components and file paths to REUSE (do not re-invent)
+
+Flutter (M1):
+- WebView bridge runtime: `lib/core/bridge/webview_js_bridge.dart`
+- Bridge client helpers: `lib/core/bridge/js_bridge_client.dart`
+- Identity entity: `lib/features/identity/domain/models/identity_model.dart`
+- Identity repository interface + impl:

* * `lib/features/identity/domain/repositories/identity_repository.dart`
* * `lib/features/identity/domain/repositories/identity_repository_impl.dart`
    +- Flow logging utility: `lib/core/utils/flow_event_emitter.dart`
    +- DB helpers + migration:
* * `lib/core/database/helpers/identity_db_helpers.dart`
* * `lib/core/database/migrations/001_identity_table.dart`
*

+JavaScript (M1):
+- Bridge entry + handler routing:

* * `core_lib_js/src/bridge/entry.ts`
* * `core_lib_js/src/bridge/handlers.ts`
    +- Base64 utilities (browser-safe): `core_lib_js/src/utils/base64.ts`
    +- Flow logging utility: `core_lib_js/src/utils/flow_events.ts`
    +- Build/bundle pipeline:
* * `core_lib_js/build.mjs`
* * Output asset: `assets/js/core_lib.js`
* * WebView wrapper: `assets/js/bridge.html`
*

+---
+
+## Boundary Map (baseline + M2 impact)
+
+### Boundary A — Flutter ↔ WebView JS (payload signing)
+
+- Protocol: JSON request/response over the existing WebView JavaScriptChannel.
+- Envelope shape (baseline):

* * Request includes **requestId** for correlation.
* * Response echoes the same **requestId**.
    +- Entry points:
* * Flutter sends via `JsBridgeClient` → `WebViewJsBridge`
* * JS receives via `core_lib_js/src/bridge/entry.ts` and routes via `handlers.ts`
*

+**M2 touches this boundary by adding one command: `payload.sign`.**
+
+Handshake requirement (verification):
+- The milestone smoke test MUST prove the runtime bridge is real by successfully executing at least one JS command over the WebView path (not a mock).
+
+### Boundary B — Flutter ↔ SQLite (load identity)
+
+- Protocol: sqflite queries through the existing M1 repository/helpers.
+- M2 reads identity via `IdentityRepository.loadIdentity()`.
+
+Handshake requirement (verification):
+- The milestone smoke test MUST prove real DB persistence by saving and reloading identity (no in-memory stub).
+
+---
+
+## Delta Plan (delta-only)
+
+| Change Type | Component / File Path | Why Needed (MVP) | How Verified (Runnable) |
+|---|---|---|---|
+| REUSE | `lib/core/bridge/webview_js_bridge.dart` | Real Flutter↔JS runtime boundary | `flutter run -t lib/smoke_test_m2_qr_generation.dart` prints PASS |
+| REUSE | `core_lib_js/build.mjs` → `assets/js/core_lib.js` | JS must run inside WebView | `cd core_lib_js && npm run build` then smoke test |
+| MODIFY | `core_lib_js/src/bridge/handlers.ts` | Add `payload.sign` handler | Smoke test exercises `payload.sign` via WebView |
+| ADD | `core_lib_js/src/types/qr_payload.ts` | Canonical QR payload types | `npx tsc -p tsconfig.json --noEmit` |
+| ADD | `core_lib_js/src/signing/sign_payload.ts` | Real Ed25519 signing | Smoke test checks signature realness (non-constant, base64, changes with input) |
+| MODIFY | `lib/core/bridge/js_bridge_client.dart` | Add `callJsSignPayload()` using baseline envelope | Smoke test uses real call + checks requestId correlation |
+| ADD | `lib/features/qr_code/**` | QR payload model + use case + UI | Smoke test validates produced QR JSON + manual UI check |
+| ADD (if missing) | `lib/core/constants/network_constants.dart` | Single source for rendezvous multiaddr | Smoke test validates `rv` equals constant |
+| ADD | `lib/smoke_test_m2_qr_generation.dart` | Automated runnable gate | `flutter run -t lib/smoke_test_m2_qr_generation.dart ...` prints PASS |
+
+---
+
+## Milestone Overview
+
+```
+Milestone: M2 – QR Code Generation
+
+Scope:

* * Allow user to display a QR code containing their identity contact information
* * QR payload includes: public key, namespace (peerID), rendezvous point, timestamp
* * Payload is signed with user's private key for authenticity verification
* * Provide an automated smoke test that exercises REAL runtime boundaries (WebView + SQLite)
    +```
*

+---
+
+## Canonical QR Payload JSON
+
+The QR code MUST contain this JSON string (no placeholder/demo content).
+
+```json
+{

* "pk": "base64-string",           // User's public key (from identity.publicKey)
* "ns": "string",                  // Namespace = peerID (from identity.peerId)
* "rv": "multiaddr-string",        // Rendezvous point address (constant)
* "ts": "ISO-8601-UTC",            // Timestamp when QR was generated
* "sig": "base64-string"           // Ed25519 signature of the unsigned payload (excluding sig field)
  +}
  +```
*

+### Signing rules (canonicalization is REQUIRED)
+
+Signature is computed over the **unsigned payload** (all fields except `sig`):
+
+```json
+{

* "pk": "...",
* "ns": "...",
* "rv": "...",
* "ts": "..."
  +}
  +```
*

+Rules:
+1. Build the unsigned payload map with **exact keys**: `pk`, `ns`, `rv`, `ts`.
+2. Serialize to a **canonical JSON string**:

* * keys sorted alphabetically
* * no extra whitespace/newlines
    +3. Sign the UTF-8 bytes using the identity private key (M1).
    +4. Base64-encode the signature bytes.
    +5. Add `sig` and serialize the final payload to canonical JSON.
*

+---
+
+## Constants (Flutter single source)
+
+`RENDEZVOUS_ADDRESS` must be defined once in Flutter and reused by all M2 code:
+
+```dart
+// lib/core/constants/network_constants.dart
+const String RENDEZVOUS_ADDRESS =

* '/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g';
  +```
*

+---
+
+## JS Bridge Contract (M2 command)
+
+All M2 communication MUST follow the baseline envelope used by M1 (includes requestId).
+
+### Command: `payload.sign`
+
+Purpose: sign a canonical JSON string using the user's private key.
+
+Request:
+```json
+{

* "cmd": "payload.sign",
* "requestId": "string",
* "payload": {
* "dataToSign": "canonical-json-string",
* "privateKey": "base64-encoded-private-key"
* }
  +}
  +```
*

+Success response:
+```json
+{

* "ok": true,
* "requestId": "string",
* "signature": "base64-encoded-signature"
  +}
  +```
*

+Error response:
+```json
+{

* "ok": false,
* "requestId": "string",
* "errorCode": "SIGNING_ERROR|INVALID_PRIVATE_KEY|INTERNAL_ERROR",
* "errorMessage": "Description of what went wrong"
  +}
  +```
*

+---
+
+## Flow Events (required instrumentation)
+
+Flow events are used for debugging and tracing. They must not leak secrets.
+
+**Do NOT emit/log the full `privateKey` or `mnemonic12`.** If needed, emit only lengths or a short prefix.
+
+Flutter (emit via `lib/core/utils/flow_event_emitter.dart`):
+- `QR_FL_PAYLOAD_BUILD_START`
+- `QR_FL_PAYLOAD_BUILD_SUCCESS`
+- `QR_FL_PAYLOAD_BUILD_ERROR` (include `errorCode`)
+- `QR_FL_BRIDGE_SIGN_REQUEST` (include `requestId` if available; do not log privateKey)
+- `QR_FL_BRIDGE_SIGN_RESPONSE` (include `ok` + `errorCode` if any)
+
+JavaScript (emit via `core_lib_js/src/utils/flow_events.ts`):
+- `QR_JS_SIGN_PAYLOAD_START`
+- `QR_JS_SIGN_PAYLOAD_SUCCESS`
+- `QR_JS_SIGN_PAYLOAD_ERROR`
+
+UI (optional, emit when opening/closing the QR screen):
+- `QR_UI_DISPLAY_OPEN`
+- `QR_UI_DISPLAY_CLOSE`
+
+---
+
+## Realness / No-Stub Rules (apply to ALL tasks)
+
+M2 is invalid if any of these are true:
+- A fake/simulated JS bridge is used in the smoke test.
+- Any output contains obvious stub markers: `demo`, `placeholder`, `fake`, `stub`, `TODO`, `simulate`.
+- QR payload uses hard-coded keys/peerIds instead of values loaded from the real identity record.
+- JS bundle is not rebuilt after adding `payload.sign` (TS changes must reach `assets/js/core_lib.js`).
+
+---
+
+## File Organization (M2 additions only)
+
+`
+lib/
+├── core/
+│   └── constants/
+│       └── network_constants.dart                 # (M2) RENDEZVOUS_ADDRESS
+├── features/
+│   └── qr_code/
+│       ├── domain/models/qr_payload_model.dart    # (M2) FL_XS_01
+│       ├── application/build_qr_payload_use_case.dart # (M2) FL_XS_03
+│       └── presentation/screens/
+│           ├── qr_display_screen.dart             # (M2) FL_XS_04
+│           └── qr_display_wired.dart              # (M2) FL_XS_05
+└── smoke_test_m2_qr_generation.dart               # (M2) QA_XS_01 (automated gate) +
+core_lib_js/
+├── src/
+│   ├── types/qr_payload.ts                        # (M2) JS_XS_01
+│   ├── signing/sign_payload.ts                    # (M2) JS_XS_02
+│   └── bridge/handlers.ts                         # (M2) JS_XS_03 (modify)
+└── build.mjs                                      # (M1) bundle pipeline → assets/js/core_lib.js +
+assets/js/
+├── bridge.html                                    # (M1) WebView wrapper
+└── core_lib.js                                    # (generated) DO NOT EDIT
+`

--- a/m2-qr-generation/execution-order.md
+++ b/m2-qr-generation/execution-order.md
@@ -1,131 +1,178 @@
-# Execution Order
------------------

## -This document shows the recommended order for executing tasks, including which tasks can run in parallel.

## -## Dependency Graph

-```
-JS_XS_01 ──┐

* ```
        ├── JS_XS_02 ── JS_XS_03
  ```
* ```
        │
  ```

-FL_XS_01 ──┴── FL_XS_02 ── FL_XS_03 ── FL_XS_05

* ```
                                 │
  ```
* ```
                           FL_XS_04 (parallel)
  ```
*

-QA_XS_01 depends on all above
-```
----

## -## Execution Phases

## -### Phase 1: JavaScript Tasks (can run in parallel with Flutter domain)

-**Execute in order:**
-1. JS_XS_01 - QRPayloadJson Type Definition
-2. JS_XS_02 - signPayload() Implementation
-3. JS_XS_03 - Bridge Handler for payload.sign
----------------------------------------------

-**Rationale:**
-- JS_XS_01 provides types used by JS_XS_02 and JS_XS_03
-- JS_XS_02 provides signing function used by JS_XS_03
-- JS_XS_03 wires everything into the bridge
--------------------------------------------

## -### Phase 2: Flutter Domain Tasks (can run in parallel with JS tasks)

-**Execute:**
-1. FL_XS_01 - QRPayloadModel
-----------------------------

## -**Can run in parallel with Phase 1.**

## -### Phase 3: Flutter Bridge and Use Case (depends on JS + domain)

-**Execute in order:**
-1. FL_XS_02 - callJsSignPayload() Bridge Function
-2. FL_XS_03 - buildQRPayload Use Case
--------------------------------------

-**Dependencies:**
-- FL_XS_02 depends on JS bridge contract being defined (JS_XS_03)
-- FL_XS_03 depends on FL_XS_01 and FL_XS_02
--------------------------------------------

## -### Phase 4: UI Tasks

-**Execute:**
-1. FL_XS_04 - QRDisplayScreen Layout
-2. FL_XS_05 - Wire QRDisplayScreen
-----------------------------------

-**Dependencies:**
-- FL_XS_04 is pure layout and can be done anytime after FL_XS_01
-- FL_XS_05 depends on FL_XS_03 and FL_XS_04
--------------------------------------------

## -### Phase 5: QA Verification

-**Execute:**
-1. QA_XS_01 - End-to-end testing
---------------------------------

-**Dependencies:**
-- QA_XS_01 requires all implementation tasks complete
------------------------------------------------------

## -## Parallelization Opportunities

## -These tasks can be done simultaneously by different agents:

-- Agent 1: JS_XS_01 → JS_XS_02 → JS_XS_03
-- Agent 2: FL_XS_01 (in parallel with JS tasks)
-- Agent 3: FL_XS_04 (layout) can start after FL_XS_01
------------------------------------------------------

-Then:
-- Agent 2: FL_XS_02 → FL_XS_03 (after JS_XS_03)
-- Agent 3: FL_XS_05 (after FL_XS_03 and FL_XS_04)
-- Agent 4: QA_XS_01 (after all complete)
-----------------------------------------

## -## Critical Path

## -The minimum sequence that must be completed in order:

-1. JS_XS_01 → JS_XS_02 → JS_XS_03
-2. FL_XS_01
-3. FL_XS_02 → FL_XS_03
-4. FL_XS_04 → FL_XS_05
-5. QA_XS_01
+# M2 Execution Order
+
+This document shows the recommended order for executing tasks, including which tasks can run in parallel.
+
+M2 is complete only when the automated smoke test (`QA_XS_01`) prints **PASS** using the real runtime path (WebView JS bridge + SQLite identity repo).
+
+---
+
+## Phase 0: Baseline Pre-flight (M1 must already be real)
+
+These are NOT M2 tasks, but M2 cannot be verified without them.
+
+- [ ] **JS bundle pipeline works:**

* * [ ] `cd core_lib_js && npm install`
* * [ ] `npm run build`
* * [ ] Output file exists: `assets/js/core_lib.js` (generated)
*

+- [ ] **WebView assets are wired in Flutter:**

* * [ ] `assets/js/bridge.html` exists
* * [ ] `assets/js/core_lib.js` exists (from build)
* * [ ] Both are declared in `pubspec.yaml` under `flutter: assets:`
*

+- [ ] **Real WebView bridge exists (no stubs):**

* * [ ] `lib/core/bridge/webview_js_bridge.dart` exists and is used by the app (see `C4_MODEL.md`)
*

+If any pre-flight item fails: fix M1 first. Do NOT add stubs in M2 to “make it pass”.
+
+---
+
+## Dependency Graph (M2 tasks)
+
+```
+PHASE 1: JS + Flutter Domain (Parallel)
+═══════════════════════════════════════════════════════════════════════════════
+

* JS Track                          Flutter Domain Track
* ────────                          ───────────────────
* ```
   │                                     │
  ```
* ```
   ▼                                     ▼
  ```
* ┌─────────┐                         ┌─────────┐
* │JS_XS_01 │                         │FL_XS_01 │
* │Types    │                         │Model    │
* └────┬────┘                         └─────────┘
* ```
    │
  ```
* ```
    ▼
  ```
* ┌─────────┐
* │JS_XS_02 │
* │Signing  │
* └────┬────┘
* ```
    │
  ```
* ```
    ▼
  ```
* ┌─────────┐   (after this: rebuild bundle)
* │JS_XS_03 │───────────────────────────────▶  `cd core_lib_js && npm run build`
* │Handler  │
* └─────────┘
*
*

+PHASE 2: Flutter Bridge + Use Case
+═══════════════════════════════════════════════════════════════════════════════
+

* Requires: JS_XS_03 (+ bundle rebuilt), FL_XS_01, M1 IdentityRepository
*
* ┌─────────┐
* │FL_XS_02 │  (callJsSignPayload)
* └────┬────┘
* ```
    │
  ```
* ```
    ▼
  ```
* ┌─────────┐
* │FL_XS_03 │  (buildQRPayload use case + RENDEZVOUS_ADDRESS constant)
* └─────────┘
*
*

+PHASE 3: UI Layer (can start layout earlier)
+═══════════════════════════════════════════════════════════════════════════════
+

* Layout (no deps)               Wiring (needs use case)
* ────────────────────────       ───────────────────────
* ┌─────────┐                        ┌─────────┐
* │FL_XS_04 │                        │FL_XS_05 │
* │Layout   │                        │Wiring   │
* └─────────┘                        └─────────┘
*
*

+PHASE 4: QA Gate (automated)
+═══════════════════════════════════════════════════════════════════════════════
+

* Requires: JS bundle rebuilt + FL/JS implementation complete
*
* ┌─────────┐
* │QA_XS_01 │  (Automated smoke test; MUST print PASS)
* └─────────┘
  +```
*

+---
+
+## Execution Checklist
+
+### Phase 1: JS + Flutter Domain (parallel)
+
+**JS (core_lib_js):**
+- [ ] `JS_XS_01` - QR payload TS types
+- [ ] `JS_XS_02` - signPayload() implementation
+- [ ] `JS_XS_03` - Bridge handler for `payload.sign`
+
+**IMPORTANT after JS_XS_03: rebuild the WebView JS bundle**
+- [ ] `cd core_lib_js && npm install`
+- [ ] `npm run build`
+- [ ] Confirm: `assets/js/core_lib.js` exists and contains `"payload.sign"`
+
+**Flutter domain:**
+- [ ] `FL_XS_01` - QRPayloadModel (canonical JSON)
+
+---
+
+### Phase 2: Flutter bridge + use case
+
+**Prerequisites:** JS bundle rebuilt; JS_XS_03; FL_XS_01; M1 IdentityRepository
+
+- [ ] `FL_XS_02` - `callJsSignPayload()` added to `lib/core/bridge/js_bridge_client.dart`
+- [ ] `FL_XS_03` - `buildQRPayload` use case (+ `RENDEZVOUS_ADDRESS` constant if missing)
+
+---
+
+### Phase 3: UI
+
+Layout can be developed in parallel with Phase 1/2, but wiring requires the use case.
+
+- [ ] `FL_XS_04` - QRDisplayScreen layout (`qr_flutter`)
+- [ ] `FL_XS_05` - Wire QRDisplayScreen to the real use case and dependencies
+
+---
+
+### Phase 4: QA gate (automated smoke test)
+
+**Prerequisites:** all implementation tasks complete; JS bundle rebuilt.
+
+- [ ] `QA_XS_01` - Add automated smoke test entrypoint and run it on a real device/emulator.
+
+**Gate command (example):**
+`bash
+flutter run -t lib/smoke_test_m2_qr_generation.dart -d <device-id>
+`
+
+PASS criteria:
+- App prints `PASS` in logs within a few seconds.
+- The test exercised:

* * WebView JS bridge (real, not mocked)
* * SQLite identity repository (real persistence)
* * M2 `payload.sign` command
* * M2 QR payload construction with realness checks

--- a/m2-qr-generation/file-structure.md
+++ b/m2-qr-generation/file-structure.md
@@ -1,242 +1,85 @@
-# File Structure
-----------------

## -This document specifies where each generated file should be placed in the repository.

## -## Project Structure Overview

-```
-your_flutter_app/
-├── core-lib-js/                          # JavaScript core library (from M1)
-│   └── src/
-│       ├── types/
-│       ├── signing/
-│       └── bridge/
-├── lib/
-│   ├── core/
-│   │   ├── bridge/                       # JS bridge code (from M1)
-│   │   └── constants/
-│   └── features/
-│       └── qr_code/                      # New QR feature folder
-│           ├── domain/
-│           ├── application/
-│           └── presentation/
-└── docs/

* └── qa/
  -```
*

## -## Task Output Locations

## -### JS_XS_01 - QRPayloadJson Type Definition

-Create:
-`
-core-lib-js/src/types/qr_payload.ts
-`
--

## -### JS_XS_02 - signPayload() Implementation

-Create:
-`
-core-lib-js/src/signing/sign_payload.ts
-`
--

## -### JS_XS_03 - Bridge Handler for payload.sign

-Modify:
-`
-core-lib-js/src/bridge/handlers.ts
-`
--

## -### FL_XS_01 - QRPayloadModel

-Create:
-`
-lib/features/qr_code/domain/models/qr_payload_model.dart
-`
--

## -### FL_XS_02 - callJsSignPayload() Bridge Function

-Modify:
-`
-lib/core/bridge/js_bridge_client.dart
-`
--

-Add function:
-```dart
-Future<Map<String, dynamic>> callJsSignPayload({

* required JsBridge bridge,
* required String dataToSign,
* required String privateKey,
  -})
  -```
*

## -### FL_XS_03 - buildQRPayload Use Case

-Create:
-`
-lib/features/qr_code/application/build_qr_payload_use_case.dart
-`
--

-Also create (if not exists):
-`
-lib/core/constants/network_constants.dart
-`
--

## -### FL_XS_04 - QRDisplayScreen Layout

-Create:
-`
-lib/features/qr_code/presentation/screens/qr_display_screen.dart
-`
--

-Update pubspec.yaml:
-```yaml
-dependencies:

* qr_flutter: ^4.1.0
  -```
*

## -### FL_XS_05 - Wire QRDisplayScreen

-Create:
-`
-lib/features/qr_code/presentation/screens/qr_display_wired.dart
-`
--

## -### QA_XS_01 - End-to-end Test Script

-Create:
-`
-docs/qa/QA_M2_XS_01_qr_generation.md
-`
--

## -## Additional Notes

## -### Barrel Exports (Optional)

## -If the project uses barrel exports, add:

-`
-lib/features/qr_code/domain/domain.dart
-lib/features/qr_code/application/application.dart
-lib/features/qr_code/presentation/presentation.dart
-`
--

## -And update feature exports accordingly.

## -### Import Conventions

-- Use relative imports within feature folders
-- Use package imports for core modules
-- Follow existing project import style
---------------------------------------

## -### JS Module Export

## -Ensure new JS modules are exported in the core-lib-js build:

-- Update core-lib-js/src/index.ts if needed
-- Ensure build.mjs includes new entry points
---------------------------------------------

## -### Signing Dependencies

## -JS signing implementation may require:

-```json
-{

* "@noble/ed25519": "^2.0.0",
* "buffer": "^6.0.3"
  -}
  -```
*

-But prefer existing dependencies from M1.
+# M2 File Structure
+
+This document shows where to place each generated code file for M2.
+
+M2 adds a new feature folder `lib/features/qr_code/` plus one automated smoke test entrypoint.
+
+---
+
+## Project Structure Overview (only what M2 touches)
+
+```
+your_flutter_app/
+├── assets/
+│   └── js/
+│       ├── bridge.html                      # From M1 (WebView wrapper)
+│       └── core_lib.js                      # Generated by `core_lib_js` build (DO NOT EDIT)
+│
+├── lib/
+│   ├── core/
+│   │   ├── bridge/
+│   │   │   ├── webview_js_bridge.dart       # From M1 (REAL runtime bridge)
+│   │   │   └── js_bridge_client.dart        # Modify in FL_XS_02
+│   │   ├── constants/
+│   │   │   └── network_constants.dart       # Create if missing (FL_XS_03)
+│   │   └── utils/
+│   │       └── flow_event_emitter.dart      # From M1 (reuse)
+│   │
+│   ├── features/
+│   │   ├── identity/                        # From M1 (reuse)
+│   │   └── qr_code/                         # NEW for M2
+│   │       ├── domain/models/qr_payload_model.dart             # FL_XS_01
+│   │       ├── application/build_qr_payload_use_case.dart      # FL_XS_03
+│   │       └── presentation/screens/
+│   │           ├── qr_display_screen.dart                      # FL_XS_04
+│   │           └── qr_display_wired.dart                       # FL_XS_05
+│   │
+│   └── smoke_test_m2_qr_generation.dart     # QA_XS_01 (automated gate)
+│
+├── core_lib_js/
+│   ├── src/
+│   │   ├── bridge/handlers.ts               # Modify in JS_XS_03
+│   │   ├── signing/sign_payload.ts          # JS_XS_02
+│   │   └── types/qr_payload.ts              # JS_XS_01
+│   └── build.mjs                            # From M1 (bundle pipeline)
+│
+└── docs/

* └── qa/
* ```
     └── QA_M2_XS_01_qr_generation.md     # Optional manual QA notes (QA_XS_01 may update)
  ```

+```
+
+---
+
+## Task → File Mapping
+
+| Task | Output File(s) | Notes |
+|------|---------------|------|
+| JS_XS_01 | `core_lib_js/src/types/qr_payload.ts` | new file |
+| JS_XS_02 | `core_lib_js/src/signing/sign_payload.ts` | new file |
+| JS_XS_03 | `core_lib_js/src/bridge/handlers.ts` | modify existing M1 handler map; then rebuild bundle to `assets/js/core_lib.js` |
+| FL_XS_01 | `lib/features/qr_code/domain/models/qr_payload_model.dart` | new file |
+| FL_XS_02 | `lib/core/bridge/js_bridge_client.dart` | add `callJsSignPayload()` following M1 patterns |
+| FL_XS_03 | `lib/features/qr_code/application/build_qr_payload_use_case.dart` | new file |
+| FL_XS_03 | `lib/core/constants/network_constants.dart` | create if missing; define `RENDEZVOUS_ADDRESS` |
+| FL_XS_04 | `lib/features/qr_code/presentation/screens/qr_display_screen.dart` | new file; requires `qr_flutter` dependency |
+| FL_XS_05 | `lib/features/qr_code/presentation/screens/qr_display_wired.dart` | new file |
+| QA_XS_01 | `lib/smoke_test_m2_qr_generation.dart` | automated gate (must print PASS) |
+| QA_XS_01 | `docs/qa/QA_M2_XS_01_qr_generation.md` | optional manual notes |
+
+---
+
+## Notes on generated assets (critical)
+
+- `assets/js/core_lib.js` is a **generated artifact** from `core_lib_js/`.
+- After completing `JS_XS_03`, you MUST run:

* ```bash
  ```
* cd core_lib_js
* npm install
* npm run build
* ```
  ```

+- Do NOT hand-edit `assets/js/core_lib.js`. Always change source under `core_lib_js/src/` and rebuild.

--- a/m2-qr-generation/verification-checklist.md
+++ b/m2-qr-generation/verification-checklist.md
@@ -1,239 +1,238 @@
-# Verification Checklist
-------------------------

## -This checklist provides verification steps for each task and milestone completion.

## -## Per-Task Verification

## -### JS_XS_01 - QRPayloadJson Type Definition

-- [ ] File `core-lib-js/src/types/qr_payload.ts` created
-- [ ] Exports `UnsignedQRPayload` and `SignedQRPayload` interfaces
-- [ ] Types match canonical payload structure
-- [ ] TypeScript compiles without errors
-----------------------------------------

-Verification command:
-`bash
-cd core-lib-js
-npm test  # or equivalent TypeScript build command
-`
--

## -### JS_XS_02 - signPayload() Implementation

-- [ ] File `core-lib-js/src/signing/sign_payload.ts` created
-- [ ] signPayload function exported and async
-- [ ] Uses Ed25519 signing correctly
-- [ ] Handles 32-byte and 64-byte private keys
-- [ ] Returns base64 signature string
-- [ ] Emits flow events for start/success/error
------------------------------------------------

-Verification:
-- [ ] Unit test with known key/message produces expected signature
-- [ ] Invalid key throws error
-------------------------------

## -### JS_XS_03 - Bridge Handler for payload.sign

-- [ ] Handler added to `core-lib-js/src/bridge/handlers.ts`
-- [ ] Accepts cmd "payload.sign"
-- [ ] Validates payload contains dataToSign and privateKey
-- [ ] Calls signPayload and returns signature
-- [ ] Error handling returns ok:false with error message
-- [ ] Flow events emitted for request/response
-----------------------------------------------

-Verification:
-- [ ] WebView bridge can call payload.sign successfully
-- [ ] Response format matches contract
---------------------------------------

## -### FL_XS_01 - QRPayloadModel

-- [ ] File `lib/features/qr_code/domain/models/qr_payload_model.dart` created
-- [ ] Model includes pk, ns, rv, ts, sig fields
-- [ ] fromJson/toJson work correctly
-- [ ] toJsonString produces canonical JSON (sorted keys, no whitespace)
-- [ ] buildUnsignedPayload static method works
-----------------------------------------------

-Verification:
-- [ ] Unit test: model round-trips JSON correctly
-- [ ] Canonical JSON output matches expected format
----------------------------------------------------

## -### FL_XS_02 - callJsSignPayload() Bridge Function

-- [ ] Function added to `lib/core/bridge/js_bridge_client.dart`
-- [ ] Sends correct cmd and payload to JS bridge
-- [ ] Handles ok:true response with signature
-- [ ] Handles ok:false response with error
-- [ ] Emits flow events for request/response
---------------------------------------------

-Verification:
-- [ ] Integration test: callJsSignPayload returns signature for valid input
-- [ ] Invalid input returns error
----------------------------------

## -### FL_XS_03 - buildQRPayload Use Case

-- [ ] File `lib/features/qr_code/application/build_qr_payload_use_case.dart` created
-- [ ] Enum BuildQRPayloadResult defined
-- [ ] buildQRPayload function implemented
-- [ ] Loads identity from repo
-- [ ] Returns noIdentity when identity missing
-- [ ] Builds unsigned payload with correct fields
-- [ ] Uses RENDEZVOUS_ADDRESS constant
-- [ ] Calls JS signing bridge
-- [ ] Returns canonical signed JSON string on success
-- [ ] Emits flow events for start/success/error
------------------------------------------------

-Verification:
-- [ ] Unit test: no identity returns correct result
-- [ ] Integration test: with identity produces valid signed payload
--------------------------------------------------------------------

## -### FL_XS_04 - QRDisplayScreen Layout

-- [ ] File `lib/features/qr_code/presentation/screens/qr_display_screen.dart` created
-- [ ] Screen renders QR code using qr_flutter
-- [ ] Displays peerId and instructions
-- [ ] Has close/back button
-- [ ] Share button present when callback provided
--------------------------------------------------

-Verification:
-- [ ] UI test: screen renders without errors
-- [ ] QR code scans correctly
------------------------------

## -### FL_XS_05 - Wire QRDisplayScreen

-- [ ] File `lib/features/qr_code/presentation/screens/qr_display_wired.dart` created
-- [ ] Loads identity and generates QR payload on init
-- [ ] Shows loading state while generating
-- [ ] Shows QRDisplayScreen on success
-- [ ] Shows error UI on failure
-- [ ] Retry mechanism works
----------------------------

-Verification:
-- [ ] Manual test: navigate to screen shows QR code
-- [ ] Error state shown when no identity
-----------------------------------------

## -### QA_XS_01 - End-to-end Test Script

-- [ ] File `docs/qa/QA_M2_XS_01_qr_generation.md` created
-- [ ] Script includes setup steps
-- [ ] Script tests full flow:

* * Identity exists
* * QR payload generated
* * Signature valid
* * QR displays correctly
*

## -## Milestone Completion Checklist

## -### Core Functionality

-- [ ] User can navigate to QR display screen
-- [ ] Screen loads without crashes
-- [ ] QR code renders visibly
-- [ ] QR payload contains correct identity data
-- [ ] Signature is generated via JS bridge
-- [ ] Timestamp is current UTC
-- [ ] Rendezvous address matches constant
------------------------------------------

## -### Integration

-- [ ] Flutter <-> JS bridge working for payload.sign
-- [ ] JS signing works in WebView environment
-- [ ] Identity loaded from local DB correctly
----------------------------------------------

## -### Manual QA

-Follow QA script in `docs/qa/QA_M2_XS_01_qr_generation.md`:
-- [ ] QR code scans successfully
-- [ ] Scanned data is valid JSON
-- [ ] Signature can be verified externally (optional)
-- [ ] Multiple generations produce different timestamps
--------------------------------------------------------

## -### Flow Event Logging

-- [ ] All expected flow events emitted in logs
-- [ ] No sensitive data (private keys) logged
----------------------------------------------

## -## Final Sign-off

-When all items above are checked, Milestone 2 is complete.
+# M2 Verification Checklist
+
+Use this checklist to verify each task output before moving to dependent tasks.
+
+M2 is complete only when the automated smoke test (`QA_XS_01`) prints **PASS** using the real runtime path (WebView JS bridge + SQLite identity repo).
+
+---
+
+## Phase 0: Baseline Pre-flight (M1 must already be real)
+
+- [ ] **Real WebView bridge exists (not simulated):**

* * [ ] `lib/core/bridge/webview_js_bridge.dart` is present and used by the app.
* * [ ] No “ProductionJsBridge” / “FakeJsBridge” / “Stub” bridge is used for runtime features.
*

+- [ ] **JS bundling produces the real runtime asset:**

* * [ ] `cd core_lib_js && npm install`
* * [ ] `npm run build`
* * [ ] `assets/js/core_lib.js` exists (generated) and is referenced by `assets/js/bridge.html`
*

+- [ ] **Flutter assets configured:**

* * [ ] `assets/js/bridge.html` and `assets/js/core_lib.js` are listed in `pubspec.yaml` assets.
*

+---
+
+## Task Verification
+
+### JS_XS_01 - QRPayloadJson Type Definition
+
+- [ ] File exists: `core_lib_js/src/types/qr_payload.ts`
+- [ ] `UnsignedQRPayload` exported with required fields: `pk`, `ns`, `rv`, `ts`
+- [ ] `SignedQRPayload` exported and extends `UnsignedQRPayload` with `sig`
+- [ ] No runtime code in the file (types only)
+- [ ] TypeScript typecheck passes:

* ```bash
  ```
* cd core_lib_js
* npm install
* npx tsc -p tsconfig.json --noEmit
* ```
  ```
*

+---
+
+### JS_XS_02 - signPayload() Implementation
+
+- [ ] File exists: `core_lib_js/src/signing/sign_payload.ts`
+- [ ] Function signature:

* * [ ] `export async function signPayload(dataToSign: string, privateKeyBase64: string): Promise<string>`
    +- [ ] Uses the **same private key representation as M1 identity** (do not guess; reuse the same parsing/unmarshal utilities already used in M1 core_lib_js)
    +- [ ] Signs UTF-8 bytes of the input string
    +- [ ] Returns **base64 signature** (non-empty; no placeholder)
    +- [ ] Emits flow events (M2):
* * [ ] `QR_JS_SIGN_PAYLOAD_START`
* * [ ] `QR_JS_SIGN_PAYLOAD_SUCCESS` or `QR_JS_SIGN_PAYLOAD_ERROR`
    +- [ ] TypeScript typecheck passes (see JS_XS_01)
*

+Realness checks (must be true in smoke test):
+- [ ] Signing the same message twice returns the same signature (Ed25519 deterministic)
+- [ ] Signing two different messages returns different signatures
+- [ ] Signature base64 decodes to a plausible byte length (non-trivial; not `"test"`)
+
+---
+
+### JS_XS_03 - Bridge Handler for payload.sign (+ bundle rebuild)
+
+- [ ] `payload.sign` handler registered in `core_lib_js/src/bridge/handlers.ts`
+- [ ] Handler expects payload fields:

* * [ ] `dataToSign` (string)
* * [ ] `privateKey` (string, base64)
    +- [ ] Handler follows the baseline envelope used by M1:
* * [ ] Request includes `requestId`
* * [ ] Response echoes the same `requestId`
    +- [ ] Success response shape:
* ```json
  ```
* { "ok": true, "requestId": "…", "signature": "base64…" }
* ```
  ```

+- [ ] Error response shape:

* ```json
  ```
* { "ok": false, "requestId": "…", "errorCode": "…", "errorMessage": "…" }
* ```
  ```

+- [ ] Bundle rebuilt and contains the new handler:

* ```bash
  ```
* cd core_lib_js
* npm install
* npm run build
* grep -n "payload.sign" -n ../assets/js/core_lib.js
* ```
  ```
*

+---
+
+### FL_XS_01 - QRPayloadModel
+
+- [ ] File exists: `lib/features/qr_code/domain/models/qr_payload_model.dart`
+- [ ] Immutable model with fields: `pk`, `ns`, `rv`, `ts`, `sig`
+- [ ] `fromJson` / `toJson` round-trip works
+- [ ] `toJsonString()` produces **canonical JSON**:

* * [ ] keys sorted alphabetically
* * [ ] no whitespace/newlines
    +- [ ] `buildUnsignedPayload()` produces only keys: `pk`, `ns`, `rv`, `ts`
    +- [ ] `flutter analyze` passes:
* ```bash
  ```
* flutter analyze
* ```
  ```
*

+---
+
+### FL_XS_02 - callJsSignPayload()
+
+- [ ] Added to: `lib/core/bridge/js_bridge_client.dart`
+- [ ] Follows existing M1 bridge send pattern (requestId correlation handled consistently)
+- [ ] Sends command `payload.sign` with payload fields `dataToSign` and `privateKey`
+- [ ] Does NOT implement any “fake” signing in Dart
+- [ ] Emits flow events:

* * [ ] `QR_FL_BRIDGE_SIGN_REQUEST`
* * [ ] `QR_FL_BRIDGE_SIGN_RESPONSE`
*

+Verified by smoke test (QA_XS_01):
+- [ ] Real request/response crosses WebView boundary
+- [ ] requestId matches in response
+
+---
+
+### FL_XS_03 - buildQRPayload use case (+ rendezvous constant)
+
+- [ ] Use case exists: `lib/features/qr_code/application/build_qr_payload_use_case.dart`
+- [ ] Defines:

* * [ ] `enum BuildQRPayloadResult { success, noIdentity, signingError }`
* * [ ] `Future<(BuildQRPayloadResult, String?)> buildQRPayload(...)`
    +- [ ] Loads identity from `IdentityRepository` (SQLite-backed)
    +- [ ] If no identity → returns `(noIdentity, null)`
    +- [ ] Uses constant `RENDEZVOUS_ADDRESS` from:
* * [ ] `lib/core/constants/network_constants.dart` (create if missing)
    +- [ ] Produces final QR JSON with all fields: `pk`, `ns`, `rv`, `ts`, `sig`
    +- [ ] Canonical JSON rules satisfied (see GLOBAL_CONTEXT.md)
*

+Verified by smoke test (QA_XS_01):
+- [ ] `pk/ns` match the persisted identity
+- [ ] `rv` equals constant
+- [ ] `ts` is a recent UTC ISO timestamp
+- [ ] signature changes when payload changes
+
+---
+
+### FL_XS_04 - QRDisplayScreen Layout
+
+- [ ] File exists: `lib/features/qr_code/presentation/screens/qr_display_screen.dart`
+- [ ] Uses `qr_flutter` (dependency added in `pubspec.yaml`)
+- [ ] Stateless / layout-only (no business logic)
+- [ ] Renders QR code for provided `qrData` string
+
+---
+
+### FL_XS_05 - Wire QRDisplayScreen
+
+- [ ] File exists: `lib/features/qr_code/presentation/screens/qr_display_wired.dart`
+- [ ] Uses the real `buildQRPayload` use case and real dependencies
+- [ ] Has loading/success/error states and retry
+- [ ] No placeholder QR data in success state
+
+---
+
+## QA_XS_01 - Automated Smoke Test (M2 gate)
+
+Smoke test MUST:
+- exercise WebView JS bridge with the real `assets/js/core_lib.js` runtime,
+- exercise SQLite persistence via the real IdentityRepository,
+- validate realness (no stub markers).
+
+- [ ] File exists: `lib/smoke_test_m2_qr_generation.dart`
+- [ ] Running it on a real device/emulator prints `PASS` and does not crash:

* ```bash
  ```
* flutter run -t lib/smoke_test_m2_qr_generation.dart -d <device-id>
* ```
  ```
*

+Realness checks that must be enforced by the smoke test:
+- [ ] Fail if any output contains: `demo|placeholder|fake|stub|TODO|simulate` (case-insensitive)
+- [ ] PeerId looks like a real libp2p PeerId (e.g., starts with `12D3KooW`)
+- [ ] Base64 fields decode successfully (pk/privateKey/sig)
+- [ ] `sig` is non-empty and differs when the unsigned payload differs
+- [ ] Identity is saved to SQLite and reloaded (same peerId)
+
+---
+
+## Final Sign-Off
+
+- [ ] All tasks verified individually
+- [ ] JS bundle rebuilt after JS_XS_03
+- [ ] Smoke test prints PASS using real runtime boundaries
+
+**M2 QR Code Generation: COMPLETE**

--- a/m2-qr-generation/tasks/JS_XS_01.md
+++ b/m2-qr-generation/tasks/JS_XS_01.md
@@ -1,25 +1,61 @@
-## JS_XS_01 - QRPayloadJson Type Definition
--------------------------------------------

-### Goal
-Define the TypeScript interfaces for QR payload structure.
-----------------------------------------------------------

-### Files to Create
-- `core-lib-js/src/types/qr_payload.ts`
----------------------------------------

-### Requirements
-- Export `UnsignedQRPayload` interface:

* * pk: string (public key)
* * ns: string (namespace/peerID)
* * rv: string (rendezvous address)
* * ts: string (timestamp)
*

-- Export `SignedQRPayload` interface extends UnsignedQRPayload:

* * sig: string (signature)
*

-### Verification
-- TypeScript compiles without errors
-- Types match canonical JSON structure
+# Task Prompt: JS_XS_01 - QRPayloadJson Type Definition
+
+## Instructions for AI Agent
+You are implementing a specific task for a Flutter/JS application. Follow the task specification exactly. Output complete, working code that can be directly used.
+
+---
+
+## Global Context
+`text
+Milestone: M2 – QR Code Generation +
+Baseline (M1) that MUST be reused (no re-inventing):
+- JS runs inside Flutter WebView from the bundled asset: assets/js/core_lib.js
+- assets/js/core_lib.js is built from core_lib_js/ via core_lib_js/build.mjs
+- Bridge protocol uses a requestId-correlated JSON envelope (see C4_MODEL.md) +
+M2 QR payload shape:
+- Unsigned QR payload keys: pk, ns, rv, ts
+- Signed QR payload keys:   pk, ns, rv, ts, sig
+`
+
+---
+
+## Task Definition
+```
+[TASK JS_XS_01 – QRPayloadJson Type Definition]
+
+Owner: JS
+
+Goal:

* Create canonical TypeScript interfaces for the unsigned/signed QR payload so
* signing + bridge handler code shares a single source of truth.
*

+Prerequisites:

* * core_lib_js/ exists from M1 and TypeScript compilation works (tsconfig.json present).
*

+What to implement:

* * Create file: core_lib_js/src/types/qr_payload.ts
* * Export exactly:
* ```
   - interface UnsignedQRPayload { pk: string; ns: string; rv: string; ts: string }
  ```
* ```
   - interface SignedQRPayload extends UnsignedQRPayload { sig: string }
  ```
* * No runtime code in this file.
*

+Inputs:

* * None (type-only).
*

+Outputs:

* * Exported interfaces for use by JS_XS_02 and JS_XS_03.
*

+Flow_events:

* * None.
*

+Constraints:

* * Do NOT add runtime imports (no Buffer, no crypto, no side effects).
* * Keep field names exactly: pk, ns, rv, ts, sig.
* * Do NOT add optional fields; all fields required.
*

+Deliverable:

* * `core_lib_js/src/types/qr_payload.ts`
    +```
*

+---
+
+## Output Requirements
+1) Output the COMPLETE contents of `core_lib_js/src/types/qr_payload.ts`.
+
+2) Verification (runnable):
+`bash
+cd core_lib_js
+npm install
+npx tsc -p tsconfig.json --noEmit
+`
+
+---
+
+## Begin Implementation
+Output the complete implementation now.
+
+------------------------------------------------------------

--- a/m2-qr-generation/tasks/JS_XS_02.md
+++ b/m2-qr-generation/tasks/JS_XS_02.md
@@ -1,34 +1,82 @@
-## JS_XS_02 - signPayload() Implementation
-------------------------------------------

-### Goal
-Implement Ed25519 signing of QR payload JSON strings.
------------------------------------------------------

-### Files to Create
-- `core-lib-js/src/signing/sign_payload.ts`
--------------------------------------------

-### Requirements
-- Export async function `signPayload(dataToSign: string, privateKey: string): Promise<string>`
-- Input `dataToSign` is canonical JSON string
-- Input `privateKey` is base64 encoded private key string
----------------------------------------------------------

-- Implementation must:

* 1. Base64 decode private key to bytes
* 2. Handle both 32-byte and 64-byte private keys:
* ```
  - 32-byte: treat as seed
  ```
* ```
  - 64-byte: treat as full keypair, use first 32 bytes as seed
  ```
* 3. Convert dataToSign to UTF-8 bytes
* 4. Sign using Ed25519
* 5. Return base64-encoded signature
*

-- Must emit flow events:

* * QR_JS_SIGN_PAYLOAD_START
* * QR_JS_SIGN_PAYLOAD_SUCCESS
* * QR_JS_SIGN_PAYLOAD_ERROR
*

-### Dependencies
-- Use existing crypto dependencies from M1
-- If needed, add @noble/ed25519
--------------------------------

-### Verification
-- Unit test with known key and message
-- Signature verifies correctly
+# Task Prompt: JS_XS_02 - signPayload() Implementation
+
+## Instructions for AI Agent
+You are implementing a specific task for a Flutter/JS application. Follow the task specification exactly. Output complete, working code that can be directly used.
+
+---
+
+## Global Context
+`text
+Milestone: M2 – QR Code Generation +
+Baseline (M1) that MUST be reused (no re-inventing):
+- JS runs inside Flutter WebView from assets/js/core_lib.js (built from core_lib_js/)
+- Browser-safe utilities already exist in core_lib_js/src/utils/ (base64 + flow events)
+- Identity privateKey format is whatever M1 stores in SQLite; this task MUST sign using that real format. +
+Canonical signing input:
+- dataToSign is a canonical JSON string (keys sorted, no whitespace) built on Flutter side.
+- privateKeyBase64 is the identity.privateKey string from M1. +
+Output:
+- base64 signature string (NO placeholders).
+`
+
+---
+
+## Task Definition
+```
+[TASK JS_XS_02 – signPayload() Implementation]
+
+Owner: JS
+
+Goal:

* Implement signPayload(dataToSign, privateKeyBase64) that produces a real Ed25519 signature
* compatible with the identity key material produced by M1.
*

+Prerequisites:

* * JS_XS_01 complete (qr_payload types exist).
* * M1 JS crypto deps already present in core_lib_js (per C4_MODEL.md).
* * Browser runtime compatibility: do NOT depend on Node-only APIs unless M1 already polyfills them.
*

+What to implement:

* * Create file: core_lib_js/src/signing/sign_payload.ts
* * Export:
* ```
   export async function signPayload(
  ```
* ```
     dataToSign: string,
  ```
* ```
     privateKeyBase64: string
  ```
* ```
   ): Promise<string>
  ```
*
* * Implementation requirements:
* ```
   1) Emit flow event: QR_JS_SIGN_PAYLOAD_START (include safe metadata only; never log the full private key).
  ```
* ```
   2) Decode privateKeyBase64 to bytes using the existing base64 utility from M1
  ```
* ```
      (use core_lib_js/src/utils/base64.ts; do not introduce ad-hoc base64 code).
  ```
* ```
   3) Convert dataToSign → UTF-8 bytes (TextEncoder).
  ```
* ```
   4) Sign using Ed25519 with the SAME key representation as M1 identity:
  ```
* ```
      - Prefer the same key unmarshal/sign path already used by M1 JS identity code.
  ```
* ```
      - Do NOT change how M1 keys are generated or stored.
  ```
* ```
   5) Base64-encode signature bytes using the existing base64 utility.
  ```
* ```
   6) Emit QR_JS_SIGN_PAYLOAD_SUCCESS on success.
  ```
* ```
   7) On error: emit QR_JS_SIGN_PAYLOAD_ERROR and throw an Error with a clear message.
  ```
*

+Inputs:

* * dataToSign: canonical JSON string
* * privateKeyBase64: base64 identity private key (M1)
*

+Outputs:

* * Returns: base64 signature string.
*

+Flow_events:

* * QR_JS_SIGN_PAYLOAD_START
* * QR_JS_SIGN_PAYLOAD_SUCCESS
* * QR_JS_SIGN_PAYLOAD_ERROR
*

+Constraints:

* * NO placeholder/demo/test signatures.
* * Do NOT log or emit the full private key (only lengths or hashes if needed).
* * Must run in the WebView (browser) runtime.
* * Must be deterministic (same message + same key → same signature).
*

+Deliverable:

* * `core_lib_js/src/signing/sign_payload.ts`
    +```
*

+---
+
+## Output Requirements
+1) Output the COMPLETE contents of `core_lib_js/src/signing/sign_payload.ts`.
+
+2) Verification (runnable):
+`bash
+cd core_lib_js
+npm install
+npx tsc -p tsconfig.json --noEmit
+`
+
+NOTE: end-to-end correctness is verified in QA_XS_01 via the real Flutter↔WebView runtime.
+
+---
+
+## Begin Implementation
+Output the complete implementation now.
+
+------------------------------------------------------------

--- a/m2-qr-generation/tasks/JS_XS_03.md
+++ b/m2-qr-generation/tasks/JS_XS_03.md
@@ -1,33 +1,92 @@
-## JS_XS_03 - Bridge Handler for payload.sign
----------------------------------------------

-### Goal
-Wire the signing function into the existing JS bridge.
-------------------------------------------------------

-### Files to Modify
-- `core-lib-js/src/bridge/handlers.ts`
---------------------------------------

-### Requirements
-- Add handler for command `payload.sign`
-- Handler should:

* 1. Validate payload contains:
* ```
  - dataToSign: string
  ```
* ```
  - privateKey: string
  ```
* 2. Call signPayload(dataToSign, privateKey)
* 3. Return response:
* ````
  ```json
  ````
* ```
  {
  ```
* ```
    "ok": true,
  ```
* ```
    "signature": "base64..."
  ```
* ```
  }
  ```
* ````
  ```
  ````
*

-- Error response:

* ```json
  ```
* {
* "ok": false,
* "error": "error message"
* }
* ```
  ```
*

-- Must emit flow events:

* * QR_JS_BRIDGE_SIGN_REQUEST
* * QR_JS_BRIDGE_SIGN_RESPONSE
*

-### Verification
-- Test via Flutter bridge call
-- Ensure response matches contract
+# Task Prompt: JS_XS_03 - Bridge Handler for payload.sign
+
+## Instructions for AI Agent
+You are implementing a specific task for a Flutter/JS application. Follow the task specification exactly. Output complete, working code that can be directly used.
+
+---
+
+## Global Context
+`text
+Milestone: M2 – QR Code Generation +
+Baseline (M1) that MUST be reused:
+- Bridge entry routes requests to handlers map: core_lib_js/src/bridge/entry.ts + handlers.ts
+- Request/response envelope includes requestId (correlation).
+- The WebView runtime executes assets/js/core_lib.js (built from core_lib_js/ via build.mjs) +
+M2 adds ONE new command:
+- cmd: "payload.sign"
+- Purpose: sign canonical JSON string with identity private key +
+IMPORTANT:
+- This task must ensure the new handler is actually present in the WebView bundle by rebuilding.
+`
+
+---
+
+## Task Definition
+```
+[TASK JS_XS_03 – Bridge Handler for payload.sign]
+
+Owner: JS
+
+Goal:

* Register a real bridge handler for "payload.sign" and ensure it is included in the WebView runtime bundle.
*

+Prerequisites:

* * JS_XS_02 complete (signPayload exists).
* * M1 bridge routing exists (handlers map is used by entry.ts).
*

+What to implement:

* * Modify: core_lib_js/src/bridge/handlers.ts
* * Add handler registration for cmd "payload.sign".
* * Follow the SAME request/response envelope pattern used by M1 handlers
* ```
   (especially requestId correlation).
  ```
*
* * Handler behavior:
* 1. Validate payload fields:
* ```
    - payload.dataToSign is a non-empty string
  ```
* ```
    - payload.privateKey is a non-empty string (base64)
  ```
* 2. Call signPayload(dataToSign, privateKey)
* ```
    (signPayload emits QR_JS_SIGN_PAYLOAD_START/SUCCESS/ERROR)
  ```
* 3. Return success response:
* ```
    { ok: true, requestId, signature }
  ```
* 4. On error return error response:
* ```
    { ok: false, requestId, errorCode, errorMessage }
  ```
*

+Error codes:

* * INVALID_PRIVATE_KEY
* * SIGNING_ERROR
* * INTERNAL_ERROR
*

+Flow_events:

* * (from signPayload) QR_JS_SIGN_PAYLOAD_START / QR_JS_SIGN_PAYLOAD_SUCCESS / QR_JS_SIGN_PAYLOAD_ERROR
*

+Constraints:

* * MUST echo requestId back in all responses (success + error).
* * No placeholder signatures.
* * Do not log private key material.
*

+Deliverable:

* * Modification to `core_lib_js/src/bridge/handlers.ts`
* * (Build step) Rebuild bundle to update `assets/js/core_lib.js`
    +```
*

+---
+
+## Output Requirements
+1) Output the updated `core_lib_js/src/bridge/handlers.ts` (full file if small; otherwise provide an exact patch with clear anchors showing where to insert the handler).
+
+2) Verification (runnable):
+`bash
+cd core_lib_js
+npm install
+npx tsc -p tsconfig.json --noEmit
+npm run build +
+# Confirm the built bundle includes the new command string
+grep -n "payload.sign" -n ../assets/js/core_lib.js
+`
+
+---
+
+## Begin Implementation
+Output the complete implementation now.
+
+------------------------------------------------------------

--- a/m2-qr-generation/tasks/FL_XS_01.md
+++ b/m2-qr-generation/tasks/FL_XS_01.md
@@ -1,34 +1,81 @@
-## FL_XS_01 - QRPayloadModel
-----------------------------

-### Goal
-Create a Dart model class for QR payload data with canonical JSON serialization.
---------------------------------------------------------------------------------

-### Files to Create
-- `lib/features/qr_code/domain/models/qr_payload_model.dart`
-------------------------------------------------------------

-### Requirements
-- Create `QRPayloadModel` class with fields:

* * pk: String (public key)
* * ns: String (namespace/peerID)
* * rv: String (rendezvous address)
* * ts: String (timestamp)
* * sig: String (signature)
*

-- Implement:

* * `QRPayloadModel.fromJson(Map<String, dynamic>)`
* * `toJson(): Map<String, dynamic>`
* * `toJsonString(): String` - must output canonical JSON:
* * keys sorted alphabetically
* * no whitespace/newlines beyond JSON standard
*

-- Add helper method:

* * `static Map<String, dynamic> buildUnsignedPayload(...)` returning map without sig
*

-### Verification
-- Unit test canonical JSON output
-- Ensure sorted key order: ns, pk, rv, sig, ts
+# Task Prompt: FL_XS_01 - QRPayloadModel
+
+## Instructions for AI Agent
+You are implementing a specific task for a Flutter application. Follow the task specification exactly. Output complete, working Dart code that can be directly used.
+
+---
+
+## Global Context
+`text
+Milestone: M2 – QR Code Generation +
+Canonical QR payload keys:
+- Unsigned: pk, ns, rv, ts
+- Signed:   pk, ns, rv, ts, sig +
+Canonical JSON rule (required for signing):
+- Keys MUST be sorted alphabetically.
+- No extra whitespace/newlines. +
+Identity source (M1):
+- IdentityRepository.loadIdentity() returns IdentityModel with peerId/publicKey/privateKey.
+`
+
+---
+
+## Task Definition
+```
+[TASK FL_XS_01 – QRPayloadModel]
+
+Owner: Flutter
+
+Goal:

* Create an immutable QRPayloadModel that provides canonical JSON serialization used for signing and QR encoding.
*

+Prerequisites:

* * M1 identity domain exists (IdentityModel + IdentityRepository).
*

+What to implement:

* * Create file: lib/features/qr_code/domain/models/qr_payload_model.dart
* * Implement:
* ```
   class QRPayloadModel {
  ```
* ```
     final String pk;
  ```
* ```
     final String ns;
  ```
* ```
     final String rv;
  ```
* ```
     final String ts;
  ```
* ```
     final String sig;
  ```
*
* ```
     const QRPayloadModel({ ... });
  ```
*
* ```
     factory QRPayloadModel.fromJson(Map<String, dynamic> json);
  ```
* ```
     Map<String, dynamic> toJson();
  ```
* ```
     String toJsonString(); // canonical: sorted keys, jsonEncode on sorted map
  ```
*
* ```
     static Map<String, dynamic> buildUnsignedPayload({
  ```
* ```
       required String pk,
  ```
* ```
       required String ns,
  ```
* ```
       required String rv,
  ```
* ```
       required String ts,
  ```
* ```
     });
  ```
* ```
   }
  ```
*
* * Canonicalization requirement:
* ```
   - toJsonString() MUST output keys in alphabetical order.
  ```
* ```
   - Use a sorted map (e.g., SplayTreeMap<String, dynamic>) to guarantee ordering.
  ```
*

+Inputs:

* * JSON map / field values.
*

+Outputs:

* * Canonical JSON string for signing and QR generation.
*

+Flow_events:

* * None (model is pure).
*

+Constraints:

* * Immutable (all fields final).
* * Do NOT include any placeholder/demo defaults.
* * Field names MUST match exactly: pk, ns, rv, ts, sig.
*

+Deliverable:

* * `lib/features/qr_code/domain/models/qr_payload_model.dart`
    +```
*

+---
+
+## Output Requirements
+1) Output the COMPLETE contents of `lib/features/qr_code/domain/models/qr_payload_model.dart`.
+
+2) Verification (runnable):
+`bash
+flutter analyze
+`
+
+NOTE: canonical string correctness is validated again in QA_XS_01 smoke test.
+
+---
+
+## Begin Implementation
+Output the complete implementation now.
+
+------------------------------------------------------------

--- a/m2-qr-generation/tasks/FL_XS_02.md
+++ b/m2-qr-generation/tasks/FL_XS_02.md
@@ -1,27 +1,87 @@
-## FL_XS_02 - callJsSignPayload() Bridge Function
--------------------------------------------------

-### Goal
-Add a Flutter bridge function to call JS signing handler.
----------------------------------------------------------

-### Files to Modify
-- `lib/core/bridge/js_bridge_client.dart`
------------------------------------------

-### Requirements
-- Add function:

* ```dart
  ```
* Future<Map<String, dynamic>> callJsSignPayload({
* required JsBridge bridge,
* required String dataToSign,
* required String privateKey,
* })
* ```
  ```
*

-- Function should:

* 1. Send bridge message with cmd "payload.sign"
* 2. Include payload with dataToSign and privateKey
* 3. Parse response JSON
* 4. Return response map
* 5. Emit flow events:
* ```
  - QR_FL_BRIDGE_SIGN_REQUEST
  ```
* ```
  - QR_FL_BRIDGE_SIGN_RESPONSE
  ```
*

-### Verification
-- Integration test with JS bridge
-- Ensure signature returned
+# Task Prompt: FL_XS_02 - callJsSignPayload() Bridge Function
+
+## Instructions for AI Agent
+You are implementing a specific task for a Flutter application. Follow the task specification exactly. Output complete, working Dart code that can be directly used.
+
+---
+
+## Global Context
+```text
+Milestone: M2 – QR Code Generation
+
+Baseline (M1) bridge code to reuse:
+- lib/core/bridge/js_bridge_client.dart defines:

* * JsBridge abstraction
* * WebViewJsBridge implementation (in lib/core/bridge/webview_js_bridge.dart)
* * bridge helper functions callJsIdentityGenerate / callJsIdentityRestore
*

+Bridge envelope (baseline, per C4_MODEL.md):
+- Request contains cmd + requestId + payload
+- Response echoes requestId and includes ok + data or error
+
+M2 command to add:
+- cmd: "payload.sign"
+- payload: { dataToSign: string, privateKey: string }
+- response: { ok: true, requestId, signature } OR { ok:false, requestId, errorCode, errorMessage }
+` +
+--- +
+## Task Definition
+`
+[TASK FL_XS_02 – callJsSignPayload() Bridge Function]
+
+Owner: Flutter
+
+Goal:

* Add a real bridge client function for the "payload.sign" command, using the existing M1 requestId-correlated bridge.
* This must be a thin wrapper over the real runtime boundary (no fake signing in Dart).
*

+Prerequisites:

* * M1 JsBridge + WebViewJsBridge exist and are real.
* * lib/core/bridge/js_bridge_client.dart already contains callJsIdentityGenerate/callJsIdentityRestore.
* * JS_XS_03 is implemented and included in the WebView JS bundle (assets/js/core_lib.js rebuilt).
*

+What to implement:

* * Modify: lib/core/bridge/js_bridge_client.dart
* * Add a new bridge helper function (mirror the style of callJsIdentityGenerate):
* ```
   Future<Map<String, dynamic>> callJsSignPayload({
  ```
* ```
     required JsBridge bridge,
  ```
* ```
     required String dataToSign,
  ```
* ```
     required String privateKey,
  ```
* ```
   })
  ```
*
* * Implementation requirements:
* ```
   1) Emit flow event: QR_FL_BRIDGE_SIGN_REQUEST (do not log privateKey contents).
  ```
* ```
   2) Send bridge request cmd "payload.sign" with payload:
  ```
* ```
      { "dataToSign": dataToSign, "privateKey": privateKey }
  ```
* ```
      using the SAME internal send/requestId mechanism used by M1 calls.
  ```
* ```
   3) Decode the JSON response into Map<String, dynamic>.
  ```
* ```
   4) Emit flow event: QR_FL_BRIDGE_SIGN_RESPONSE (include ok + errorCode if any).
  ```
* ```
   5) Return the decoded response map to the caller (do not swallow errors silently).
  ```
*

+Inputs:

* * bridge: JsBridge (REAL WebViewJsBridge in production)
* * dataToSign: canonical JSON string
* * privateKey: base64 private key from identity
*

+Outputs:

* * Map response containing signature or error fields.
*

+Flow_events:

* * QR_FL_BRIDGE_SIGN_REQUEST
* * QR_FL_BRIDGE_SIGN_RESPONSE
*

+Constraints:

* * MUST use the real bridge runtime path (no mocks).
* * MUST NOT generate signatures in Dart (JS is source of truth).
* * Must preserve requestId correlation (reuse existing client infrastructure).
* * No placeholder/demo values.
*

+Deliverable:

* * Modification to `lib/core/bridge/js_bridge_client.dart`
    +```
*

+---
+
+## Output Requirements
+1) Output the updated `lib/core/bridge/js_bridge_client.dart`:

* * If the file is small, output the whole file.
* * If the file is large, output an exact patch showing ONLY the new function + any minimal supporting changes, with clear anchors.
*

+2) Verification (runnable):
+`bash
+flutter analyze
+`
+
+End-to-end verification is done by running QA_XS_01 smoke test (real WebView + SQLite).
+
+---
+
+## Begin Implementation
+Output the complete implementation now.
+
+------------------------------------------------------------

--- a/m2-qr-generation/tasks/FL_XS_03.md
+++ b/m2-qr-generation/tasks/FL_XS_03.md
@@ -1,46 +1,120 @@
-## FL_XS_03 - buildQRPayload Use Case
--------------------------------------

-### Goal
-Create use case to build signed QR payload from identity data.
---------------------------------------------------------------

-### Files to Create
-- `lib/features/qr_code/application/build_qr_payload_use_case.dart`
-- `lib/core/constants/network_constants.dart` (if not exists)
--------------------------------------------------------------

-### Requirements
-- Define enum:

* ```dart
  ```
* enum BuildQRPayloadResult { success, noIdentity, signingError }
* ```
  ```
*

-- Define function:

* ```dart
  ```
* Future<(BuildQRPayloadResult, String?)> buildQRPayload({
* required IdentityRepository repo,
* required Future<Map<String, dynamic>> Function({
* ```
   required String dataToSign,
  ```
* ```
   required String privateKey,
  ```
* }) callJsSign,
* })
* ```
  ```
*

-- Logic:

* 1. Load identity from repo.loadIdentity()
* 2. If null -> return (noIdentity, null)
* 3. Build unsigned payload map:
* ```
  - pk = identity.publicKey
  ```
* ```
  - ns = identity.peerId
  ```
* ```
  - rv = RENDEZVOUS_ADDRESS
  ```
* ```
  - ts = DateTime.now().toUtc().toIso8601String()
  ```
* 4. Serialize unsigned payload to canonical JSON string
* 5. Call callJsSign with dataToSign and identity.privateKey
* 6. If ok:false -> return (signingError, null)
* 7. Add sig to payload and serialize final canonical JSON
* 8. Return (success, jsonString)
*

-- Must emit flow events:

* * QR_FL_PAYLOAD_BUILD_START
* * QR_FL_PAYLOAD_BUILD_SUCCESS
* * QR_FL_PAYLOAD_BUILD_ERROR
*

-### Constants
-- RENDEZVOUS_ADDRESS in network_constants.dart
-----------------------------------------------

-### Verification
-- Unit test with mock identity and mock signing
-- Integration test with real JS bridge
+# Task Prompt: FL_XS_03 - buildQRPayload Use Case
+
+## Instructions for AI Agent
+You are implementing a specific task for a Flutter application. Follow the task specification exactly. Output complete, working Dart code that can be directly used.
+
+---
+
+## Global Context
+`text
+Milestone: M2 – QR Code Generation +
+Unsigned payload keys (signed over):
+- pk, ns, rv, ts +
+Signed payload keys (encoded in QR):
+- pk, ns, rv, ts, sig +
+Identity source (M1):
+- IdentityRepository.loadIdentity() -> IdentityModel { peerId, publicKey, privateKey } +
+Signing boundary (M2):
+- callJsSignPayload(bridge, dataToSign, privateKey) -> { ... ok:true, signature } or error +
+Rendezvous constant:
+- Use RENDEZVOUS_ADDRESS from lib/core/constants/network_constants.dart
+`
+
+---
+
+## Task Definition
+```
+[TASK FL_XS_03 – buildQRPayload Use Case]
+
+Owner: Flutter
+
+Goal:

* Implement the use case that:
* * loads the user's identity from SQLite (via the real IdentityRepository),
* * builds the canonical unsigned payload,
* * requests a signature over the real WebView JS bridge,
* * returns the final canonical signed JSON string to encode into the QR code.
*

+Prerequisites:

* * FL_XS_01 complete (QRPayloadModel exists)
* * FL_XS_02 complete (callJsSignPayload exists)
* * M1 IdentityRepository is real (SQLite-backed)
*

+What to implement:

* A) Constant (create if missing):
* ```
  - File: lib/core/constants/network_constants.dart
  ```
* ```
  - Define exactly:
  ```
* ```
      const String RENDEZVOUS_ADDRESS =
  ```
* ```
        '/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g';
  ```
* ```
  - Do NOT duplicate this constant elsewhere.
  ```
*
* B) Use case:
* ```
  - Create file: lib/features/qr_code/application/build_qr_payload_use_case.dart
  ```
* ```
  - Define:
  ```
* ```
      enum BuildQRPayloadResult { success, noIdentity, signingError }
  ```
*
* ```
      Future<(BuildQRPayloadResult, String?)> buildQRPayload({
  ```
* ```
        required IdentityRepository repo,
  ```
* ```
        required Future<Map<String, dynamic>> Function({
  ```
* ```
          required String dataToSign,
  ```
* ```
          required String privateKey,
  ```
* ```
        }) callJsSign,
  ```
* ```
      })
  ```
*
* C) Logic:
* ```
  1) Emit flow event: QR_FL_PAYLOAD_BUILD_START.
  ```
* ```
  2) Load identity via repo.loadIdentity().
  ```
* ```
  3) If identity is null:
  ```
* ```
       emit QR_FL_PAYLOAD_BUILD_ERROR (errorCode: NO_IDENTITY)
  ```
* ```
       return (noIdentity, null)
  ```
* ```
  4) Build unsigned payload:
  ```
* ```
       pk = identity.publicKey
  ```
* ```
       ns = identity.peerId
  ```
* ```
       rv = RENDEZVOUS_ADDRESS
  ```
* ```
       ts = DateTime.now().toUtc().toIso8601String()
  ```
* ```
  5) Serialize unsigned payload to canonical JSON (sorted keys; no whitespace).
  ```
* ```
  6) Call callJsSign(dataToSign, identity.privateKey).
  ```
* ```
     (callJsSignPayload emits QR_FL_BRIDGE_SIGN_REQUEST/RESPONSE; do not duplicate those here.)
  ```
* ```
  7) If response.ok != true OR response.signature missing:
  ```
* ```
       emit QR_FL_PAYLOAD_BUILD_ERROR (errorCode: response.errorCode ?? SIGNING_ERROR)
  ```
* ```
       return (signingError, null)
  ```
* ```
  8) Add sig field from response.signature and serialize final payload to canonical JSON.
  ```
* ```
  9) Emit QR_FL_PAYLOAD_BUILD_SUCCESS and return (success, finalJsonString).
  ```
*

+Inputs:

* * IdentityRepository (real)
* * callJsSign function (real bridge wrapper)
*

+Outputs:

* * Tuple: (BuildQRPayloadResult, qrJsonString?)
*

+Flow_events:

* * QR_FL_PAYLOAD_BUILD_START
* * QR_FL_PAYLOAD_BUILD_SUCCESS
* * QR_FL_PAYLOAD_BUILD_ERROR
* * (bridge emits) QR_FL_BRIDGE_SIGN_REQUEST / QR_FL_BRIDGE_SIGN_RESPONSE
*

+Constraints:

* * NO placeholder/demo outputs.
* * Must use RENDEZVOUS_ADDRESS constant (single source).
* * Must use canonical JSON for signing and for final QR string.
* * Must not log private key contents.
*

+Deliverables:

* * `lib/core/constants/network_constants.dart` (create if missing)
* * `lib/features/qr_code/application/build_qr_payload_use_case.dart`
    +```
*

+---
+
+## Output Requirements
+1) Output the COMPLETE contents of:

* * `lib/features/qr_code/application/build_qr_payload_use_case.dart`
* * AND `lib/core/constants/network_constants.dart` if you created/modified it
*

+2) Verification (runnable):
+`bash
+flutter analyze
+`
+
+End-to-end verification is QA_XS_01 smoke test.
+
+---
+
+## Begin Implementation
+Output the complete implementation now.
+
+------------------------------------------------------------

--- a/m2-qr-generation/tasks/FL_XS_04.md
+++ b/m2-qr-generation/tasks/FL_XS_04.md
@@ -1,33 +1,87 @@
-## FL_XS_04 - QRDisplayScreen Layout
-------------------------------------

-### Goal
-Create a Flutter UI screen to display QR code and identity information.
------------------------------------------------------------------------

-### Files to Create
-- `lib/features/qr_code/presentation/screens/qr_display_screen.dart`
---------------------------------------------------------------------

-### Requirements
-- Create `QRDisplayScreen` widget:

* * StatelessWidget
* * Takes parameters:
* * qrData: String (JSON string to encode)
* * peerId: String
* * onClose: VoidCallback
* * onShare: VoidCallback? (optional)
*

-- UI Layout:

* * AppBar with title "My QR Code" and close button
* * Centered QR code using qr_flutter `QrImageView`
* * Instruction text: "Scan to connect with me"
* * Display peerId (truncated if long)
* * Share button if onShare provided
*

-- Add dependency:

* * qr_flutter: ^4.1.0
*

-### Verification
-- Screen renders without errors
-- QR code scans correctly
+# Task Prompt: FL_XS_04 - QRDisplayScreen Layout
+
+## Instructions for AI Agent
+You are implementing a specific task for a Flutter application. Follow the task specification exactly. Output complete, working Dart code that can be directly used.
+
+---
+
+## Global Context
+`text
+Milestone: M2 – QR Code Generation +
+QRDisplayScreen is a pure UI widget:
+- It receives qrData (the final signed JSON string) and peerId for display.
+- It does NOT load identity, does NOT sign, does NOT call repositories. +
+QR rendering:
+- Use qr_flutter (QrImageView).
+`
+
+---
+
+## Task Definition
+```
+[TASK FL_XS_04 – QRDisplayScreen Layout]
+
+Owner: Flutter
+
+Goal:

* Build a pure layout screen that renders:
* * a centered QR code (for the qrData string),
* * a human-readable peerId,
* * close/back affordance,
* * optional Share button callback.
*

+Prerequisites:

* * None (layout-only), but project must allow adding dependencies.
*

+What to implement:

* * Add dependency if missing:
* ```
   pubspec.yaml → dependencies:
  ```
* ```
     qr_flutter: ^4.1.0
  ```
* Then run: flutter pub get
*
* * Create file:
* ```
   lib/features/qr_code/presentation/screens/qr_display_screen.dart
  ```
*
* * Widget API:
* ```
   class QRDisplayScreen extends StatelessWidget {
  ```
* ```
     final String qrData;
  ```
* ```
     final String peerId;
  ```
* ```
     final VoidCallback onClose;
  ```
* ```
     final VoidCallback? onShare;
  ```
* ```
   }
  ```
*
* * Layout requirements:
* ```
   - AppBar title: "My QR Code"
  ```
* ```
   - Close/back button triggers onClose
  ```
* ```
   - QrImageView renders qrData (min 256x256)
  ```
* ```
   - Instruction text: "Scan to connect with me"
  ```
* ```
   - Display peerId (truncate middle for long strings)
  ```
* ```
   - If onShare != null, show a Share button and call onShare
  ```
*

+Inputs:

* * qrData string
* * peerId string
*

+Outputs:

* * A reusable screen widget.
*

+Flow_events:

* * None (UI-only).
*

+Constraints:

* * StatelessWidget only (no business logic).
* * No placeholder QR data generation.
*

+Deliverables:

* * `pubspec.yaml` (dependency addition if needed)
* * `lib/features/qr_code/presentation/screens/qr_display_screen.dart`
    +```
*

+---
+
+## Output Requirements
+1) Output:

* * The COMPLETE Dart file: `lib/features/qr_code/presentation/screens/qr_display_screen.dart`
* * And, if you add/modify it, the exact `pubspec.yaml` dependency snippet to apply.
*

+2) Verification (runnable):
+`bash
+flutter pub get
+flutter analyze
+`
+
+---
+
+## Begin Implementation
+Output the complete implementation now.
+
+------------------------------------------------------------

--- a/m2-qr-generation/tasks/FL_XS_05.md
+++ b/m2-qr-generation/tasks/FL_XS_05.md
@@ -1,44 +1,97 @@
-## FL_XS_05 - Wire QRDisplayScreen
-----------------------------------

-### Goal
-Create a wired screen that loads identity and generates QR payload for display.
--------------------------------------------------------------------------------

-### Files to Create
-- `lib/features/qr_code/presentation/screens/qr_display_wired.dart`
--------------------------------------------------------------------

-### Requirements
-- Create `QRDisplayWired` StatefulWidget:

* * Takes dependencies:
* * IdentityRepository repo
* * JsBridgeClient bridgeClient
* * VoidCallback onClose
*

-- State management:

* * loading: bool
* * error: String?
* * qrData: String?
* * peerId: String?
*

-- On init:

* 1. Load identity via repo.loadIdentity()
* 2. If null -> show error "No identity found"
* 3. Call buildQRPayload use case
* 4. If success -> set qrData and peerId, show QRDisplayScreen
* 5. If error -> show error UI
*

-- UI states:

* * Loading spinner while generating
* * Error message with retry button
* * Success: QRDisplayScreen
*

## -- Retry should re-run generation

-- Must emit flow events:

* * QR_UI_DISPLAY_OPEN
* * QR_UI_DISPLAY_CLOSE
*

-### Verification
-- Manual test: navigate to screen shows QR
-- Error state when no identity
+# Task Prompt: FL_XS_05 - Wire QRDisplayScreen
+
+## Instructions for AI Agent
+You are implementing a specific task for a Flutter application. Follow the task specification exactly. Output complete, working Dart code that can be directly used.
+
+---
+
+## Global Context
+`text
+Milestone: M2 – QR Code Generation +
+This task wires the UI to the real use case:
+- buildQRPayload (FL_XS_03) loads identity from SQLite and calls the real WebView JS bridge via callJsSignPayload().
+- QRDisplayScreen (FL_XS_04) is layout-only.
+- QRDisplayWired manages loading/success/error states and passes the final qrData string to QRDisplayScreen. +
+Baseline (M1) wiring pattern:
+- Wired widgets typically receive real dependencies (repo + JsBridge) and pass closures into use cases.
+`
+
+---
+
+## Task Definition
+```
+[TASK FL_XS_05 – Wire QRDisplayScreen]
+
+Owner: Flutter
+
+Goal:

* Implement QRDisplayWired that:
* * runs buildQRPayload on init,
* * shows loading UI while building,
* * shows QRDisplayScreen on success,
* * shows an error UI (with retry) on failure/no identity.
*

+Prerequisites:

* * FL_XS_02 complete (callJsSignPayload exists in js_bridge_client.dart)
* * FL_XS_03 complete (buildQRPayload use case exists)
* * FL_XS_04 complete (QRDisplayScreen exists)
* * M1 IdentityRepository exists (real)
* * M1 JsBridge exists (real WebViewJsBridge in production)
*

+What to implement:

* * Create file:
* ```
   lib/features/qr_code/presentation/screens/qr_display_wired.dart
  ```
*
* * Widget API:
* ```
   class QRDisplayWired extends StatefulWidget {
  ```
* ```
     final IdentityRepository repo;
  ```
* ```
     final JsBridge bridge;
  ```
* ```
     final VoidCallback onClose;
  ```
* ```
   }
  ```
*
* * Behavior:
* ```
   - initState() triggers _buildPayload()
  ```
* ```
   - While loading: show spinner + brief text
  ```
* ```
   - On success:
  ```
* ```
       - render QRDisplayScreen(
  ```
* ```
           qrData: <finalJsonString>,
  ```
* ```
           peerId: <identity.peerId>,
  ```
* ```
           onClose: onClose
  ```
* ```
         )
  ```
* ```
   - On noIdentity:
  ```
* ```
       - show friendly message + close/back button
  ```
* ```
   - On signingError/other error:
  ```
* ```
       - show message + retry button + close/back button
  ```
* ```
   - Retry calls _buildPayload()
  ```
*
* * Wiring:
* ```
   - _buildPayload() calls buildQRPayload() with:
  ```
* ```
       repo: widget.repo
  ```
* ```
       callJsSign: ({dataToSign, privateKey}) =>
  ```
* ```
         callJsSignPayload(bridge: widget.bridge, dataToSign: dataToSign, privateKey: privateKey)
  ```
*

+Flow_events:

* * QR_UI_DISPLAY_OPEN
* * QR_UI_DISPLAY_CLOSE
*

+Constraints:

* * Must call the REAL buildQRPayload use case (no mock payload strings).
* * No placeholder/demo data.
* * Do not display the private key.
*

+Deliverable:

* * `lib/features/qr_code/presentation/screens/qr_display_wired.dart`
    +```
*

+---
+
+## Output Requirements
+1) Output the COMPLETE contents of `lib/features/qr_code/presentation/screens/qr_display_wired.dart`.
+
+2) Verification (runnable):
+`bash
+flutter analyze
+`
+
+Manual verification:
+- Use the app to navigate to QRDisplayWired and confirm QR renders.
+- Scan the QR and confirm it is valid JSON with pk/ns/rv/ts/sig.
+
+Automated verification is QA_XS_01 smoke test.
+
+---
+
+## Begin Implementation
+Output the complete implementation now.
+
+------------------------------------------------------------

--- a/m2-qr-generation/tasks/QA_XS_01.md
+++ b/m2-qr-generation/tasks/QA_XS_01.md
@@ -1,57 +1,158 @@
-## QA_XS_01 - End-to-end QR Generation Test Script
---------------------------------------------------

-### Goal
-Provide a manual QA script for verifying M2 QR code generation works end-to-end.
---------------------------------------------------------------------------------

-### Deliverable
-Create: `docs/qa/QA_M2_XS_01_qr_generation.md`
-----------------------------------------------

## -### Test Script Requirements

## -The QA script must cover:

-#### Setup
-1. Ensure Milestone 1 is complete and app builds
-2. Ensure identity has been generated (or generate one)
-3. Ensure JS bridge is working
-------------------------------

-#### Test Steps
-1. Launch app
-2. Navigate to QR code display screen
-3. Verify loading state shows briefly
-4. Verify QR code appears
-5. Verify peerId displayed matches identity
-6. Scan QR code with external scanner app
-7. Verify scanned content is valid JSON
-8. Verify JSON contains:

* * pk (base64)
* * ns (peerId)
* * rv (rendezvous address)
* * ts (recent UTC timestamp)
* * sig (base64 signature)
    -9. Generate QR code again (close and reopen)
    -10. Verify timestamp changes
    -11. Verify signature changes
*

-#### Error Cases
-1. Clear identity from DB and retry
-2. Verify error UI shows "No identity found"
-3. Verify retry option works after regenerating identity
---------------------------------------------------------

-### Verification
-- QA script is complete and actionable
-- Steps are clear and cover success + failure paths
+# Task Prompt: QA_XS_01 - Automated Smoke Test: QR Generation Flow (REAL runtime)
+
+## Instructions for AI Agent
+You are implementing the M2 verification gate. Follow the task specification exactly. Output complete, working code/docs that can be directly used.
+
+---
+
+## Global Context
+```text
+Milestone: M2 – QR Code Generation
+
+Hard requirement:
+- This smoke test MUST exercise the REAL runtime boundaries:

* * Flutter ↔ WebView JS bridge (assets/js/bridge.html + assets/js/core_lib.js)
* * Flutter ↔ SQLite via the real IdentityRepository (M1)
    +- NO simulated bridge clients. NO placeholder outputs.
*

+Baseline components to reuse:
+- WebView bridge: lib/core/bridge/webview_js_bridge.dart (WebViewJsBridge.initialize())
+- Bridge helpers: lib/core/bridge/js_bridge_client.dart (callJsIdentityGenerate/callJsIdentityRestore + M2 callJsSignPayload)
+- Identity repo: lib/features/identity/domain/repositories/identity_repository(_impl).dart
+- M1 use cases: lib/features/identity/application/generate_identity_use_case.dart + restore_identity_use_case.dart
+- M2 use case: lib/features/qr_code/application/build_qr_payload_use_case.dart
+` +
+--- +
+## Task Definition
+`
+[TASK QA_XS_01 – Automated Smoke Test: QR Generation Flow (REAL runtime)]
+
+Owner: QA
+
+Goal:

* Add an automated, runnable smoke test entrypoint that proves M2 works end-to-end using real runtime paths:
* 1. JS bridge is real and responsive inside WebView
* 2. Identity can be saved to and loaded from SQLite (real repo)
* 3. buildQRPayload produces a signed canonical JSON string
* 4. Signature is non-stub and depends on the signed input
*

+Prerequisites:

* * M1 complete and real (bridge + SQLite identity repo).
* * JS_XS_03 complete AND JS bundle rebuilt:
* ```
   cd core_lib_js && npm install && npm run build
  ```
* This must produce assets/js/core_lib.js containing "payload.sign".
*
* * Flutter assets configured (from M1): pubspec.yaml includes assets/js/bridge.html and assets/js/core_lib.js under flutter: assets:
    +What to implement:
* A) Automated smoke test entrypoint (NEW file):
* ```
  - Create: lib/smoke_test_m2_qr_generation.dart
  ```
* ```
  - This file must be runnable via:
  ```
* ```
      flutter run -t lib/smoke_test_m2_qr_generation.dart -d <device-id>
  ```
* ```
  - It must:
  ```
* ```
      - Ensure Flutter assets are configured in pubspec.yaml (assets/js/bridge.html + assets/js/core_lib.js)
  ```
* ```
      - Initialize WebViewJsBridge and load assets/js/bridge.html
  ```
* ```
      - Use the real IdentityRepository (SQLite-backed)
  ```
* ```
      - Ensure an identity exists:
  ```
* ```
          - If none exists, call M1 generateNewIdentity(...) which calls JS and persists to DB
  ```
* ```
          - If one exists, still exercise DB write path by calling repo.saveIdentity(existingIdentity)
  ```
* ```
      - Prove JS bridge is real by executing at least one M1 JS call
  ```
* ```
        (generate or restore) through the WebView bridge.
  ```
* ```
      - Call M2 buildQRPayload(...) using:
  ```
* ```
          repo: real repo
  ```
* ```
          callJsSign: closure calling callJsSignPayload(bridge: real bridge, ...)
  ```
* ```
      - Validate:
  ```
* ```
          - qrJsonString is valid JSON
  ```
* ```
          - keys present: pk, ns, rv, ts, sig
  ```
* ```
          - pk/ns match the persisted identity
  ```
* ```
          - rv equals RENDEZVOUS_ADDRESS constant
  ```
* ```
          - ts is UTC ISO-8601 and within a reasonable time window of "now"
  ```
* ```
          - sig is base64 and non-empty
  ```
* ```
          - sig changes when the unsigned payload changes (generate twice with different ts)
  ```
* ```
          - canonical JSON: re-encoding with sorted keys yields identical string
  ```
* ```
          - FAIL if any output contains: demo|placeholder|fake|stub|TODO|simulate (case-insensitive)
  ```
*
* ```
      - On success: print exactly "PASS" (and show PASS on screen).
  ```
* ```
      - On failure: print "FAIL: <reason>" and throw (so the run is visibly failing).
  ```
*
* ```
  Implementation guidance (must still match the repo code):
  ```
* ```
    - Use WebViewWidget/WebViewController per webview_flutter.
  ```
* ```
    - Call await bridge.initialize() before sending any messages.
  ```
* ```
    - Reuse existing M1 constructors/helpers for IdentityRepositoryImpl and bridge clients
  ```
* ```
      as they are used in the real app (do NOT create a fake repository or in-memory DB).
  ```
*
* B) Optional manual QA notes update (keep file if it already exists):
* ```
  - Update (or create if missing): docs/qa/QA_M2_XS_01_qr_generation.md
  ```
* ```
  - Include:
  ```
* ```
      - how to run the automated smoke test command
  ```
* ```
      - a short manual scan checklist (scan QR and confirm JSON fields)
  ```
*

+Inputs:

* * None.
*

+Outputs:

* * PASS/FAIL runtime logs
* * (Optional) updated manual QA doc
*

+Flow_events:

* * Smoke test should NOT require reading flow events, but it may print key checkpoints.
*

+Constraints:

* * MUST use real WebViewJsBridge (no simulated responses).
* * MUST use real SQLite IdentityRepository.
* * MUST NOT hardcode identity values or signature values.
* * MUST be runnable without editing the app's main.dart (separate entrypoint file).
*

+Deliverables:

* * `lib/smoke_test_m2_qr_generation.dart`
* * `docs/qa/QA_M2_XS_01_qr_generation.md` (optional update)
    +```
*

+---
+
+## Output Requirements
+1) Output the COMPLETE contents of `lib/smoke_test_m2_qr_generation.dart`.
+
+2) If you modify it, output the updated `docs/qa/QA_M2_XS_01_qr_generation.md` content.
+
+3) Verification (runnable):
+`bash
+cd core_lib_js
+npm install
+npm run build +
+flutter pub get
+flutter run -t lib/smoke_test_m2_qr_generation.dart -d <device-id>
+# Expect: PASS
+`
+
+---
+
+## Begin Implementation
+Output the complete implementation now.
+
+------------------------------------------------------------
