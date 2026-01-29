# M2 QR Code Generation - Orchestration Package

## Overview

This package contains everything needed to implement the **M2 QR Code Generation** milestone using AI coding agents. Each task is self-contained and can be executed independently.

**Milestone gate:** M2 is only DONE when the automated smoke test in `QA_XS_01` prints **PASS** using the **real runtime path** (Flutter ↔ WebView JS bridge ↔ core_lib_js bundle AND Flutter ↔ SQLite via the real `IdentityRepository`).

## Prerequisites (from M1 - must be REAL, not simulated)

- Identity data exists and is persisted locally:
  - `IdentityModel` with `peerId`, `publicKey`, `privateKey`
  - `IdentityRepository.loadIdentity()` reads from SQLite (not an in-memory stub)

- Real Flutter ↔ JS runtime bridge (no fake bridge clients):
  - `lib/core/bridge/webview_js_bridge.dart` loads `assets/js/bridge.html`
  - `assets/js/bridge.html` loads `assets/js/core_lib.js`
  - Requests/responses are JSON over the WebView JavaScriptChannel (see `C4_MODEL.md`)

- JS bundling pipeline exists and produces the runtime asset:
  - `core_lib_js/build.mjs` (esbuild)
  - `cd core_lib_js && npm install && npm run build`
  - Output: `assets/js/core_lib.js` (do not hand-edit)

## Package Contents

```
m2-qr-generation/
├── README.md                      # This file
├── GLOBAL_CONTEXT.md              # Shared context (included in every task)
├── execution-order.md             # Sequence and parallelization guide
├── verification-checklist.md      # How to verify each task
├── file-structure.md              # Where to put generated code
└── tasks/
    ├── JS_XS_01.md                # JS: QRPayloadJson type definition
    ├── JS_XS_02.md                # JS: signPayload() implementation
    ├── JS_XS_03.md                # JS: Bridge handler for payload.sign (+ rebuild bundle)
    ├── FL_XS_01.md                # Flutter: QRPayloadModel
    ├── FL_XS_02.md                # Flutter: callJsSignPayload() bridge
    ├── FL_XS_03.md                # Flutter: buildQRPayload use case (+ rendezvous constant)
    ├── FL_XS_04.md                # Flutter: QRDisplayScreen layout (qr_flutter)
    ├── FL_XS_05.md                # Flutter: Wire QRDisplayScreen
    └── QA_XS_01.md                # QA: Automated smoke test (M2 gate) + optional manual steps
```

## Feature Summary

**User Story:**
As a user, I want to display a QR code containing my identity information so that others can scan it to connect with me.

**QR Payload Contents:**
- `pk`: public key (base64; from M1 identity)
- `ns`: namespace/peerID (from M1 identity)
- `rv`: rendezvous multiaddr (constant)
- `ts`: timestamp (UTC ISO-8601)
- `sig`: Ed25519 signature of the canonical unsigned payload

## How to Use

### Step 1: Follow `execution-order.md`

It includes:
- baseline pre-flight checks (M1 bridge + JS bundle),
- required build steps (`npm run build`),
- and the automated smoke test command.

### Step 2: Execute tasks and place outputs

For each task:

1. Open the task file (e.g., `tasks/JS_XS_01.md`)
2. Copy the **entire contents**
3. Paste to your AI coding agent
4. Apply the generated code to the repo at the exact paths in `file-structure.md`
5. Run the task's verification commands

### Step 3: Run the milestone gate (automated smoke test)

`QA_XS_01` provides the required command. It must:
- run against a real emulator/device,
- initialize the real WebView JS runtime,
- read/write the real SQLite identity row,
- and print `PASS` (otherwise treat as failing).

## Dependencies

**Flutter:**
- `qr_flutter` (for QR rendering)

**JavaScript:**
- Reuse M1 crypto dependencies already present (per `C4_MODEL.md`), do NOT introduce new crypto libs unless the real smoke test proves it is required.
