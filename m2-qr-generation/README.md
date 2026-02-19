# M2 QR Code Generation - Orchestration Package

## Milestone Gate

This milestone is complete when the automated smoke test prints **PASS** using the real runtime path (not mocked).

## Overview

This package contains everything needed to implement the **M2 QR Code Generation** milestone using AI coding agents. Each task is self-contained and can be executed independently.

## Prerequisites

- **M1 Must Be REAL** (not simulated):
  - `IdentityModel` with `peerId`, `publicKey`, `privateKey`
  - `IdentityRepository` with `loadIdentity()` method
  - WebView bridge for Flutter ↔ JS communication
  - JS bundling pipeline configured and working
  - SQLite database with identity table

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
    ├── JS_XS_03.md                # JS: Bridge handler for payload.sign + rebuild bundle
    ├── FL_XS_01.md                # Flutter: QRPayloadModel
    ├── FL_XS_02.md                # Flutter: callJsSignPayload() bridge
    ├── FL_XS_03.md                # Flutter: buildQRPayload use case + rendezvous constant
    ├── FL_XS_04.md                # Flutter: QRDisplayScreen layout (qr_flutter)
    ├── FL_XS_05.md                # Flutter: Wire QRDisplayScreen
    └── QA_XS_01.md                # QA: QR generation test script
```

## Feature Summary

**User Story:**
As a user, I want to display a QR code containing my identity information so that others can scan it to connect with me.

**QR Payload Contents:**
- `pk`: My public key (base64)
- `ns`: My namespace/peerID
- `rv`: Rendezvous server address
- `ts`: Timestamp of generation
- `sig`: Ed25519 signature for authenticity

## How to Use

### Step 1: Understand the Execution Order

Open `execution-order.md` to see which tasks can run in parallel and which have dependencies.

### Step 2: Execute Tasks

For each task:

1. Open the task file (e.g., `tasks/JS_XS_01.md`)
2. Copy the **entire contents**
3. Paste to your AI coding agent
4. Collect the generated code
5. Place the code in the correct location (see `file-structure.md`)
6. Mark complete on `verification-checklist.md`

### Step 3: Run the Milestone Gate (Automated Smoke Test)

After all tasks are complete, run the automated smoke test to verify the milestone gate passes with real runtime data.

### Step 4: Integrate

Once all tasks in a phase are complete, run integration verification before moving to the next phase.

## Task Prompt Structure

Each task file contains:

```
┌─────────────────────────────────────────────────────────────────┐
│  SYSTEM INSTRUCTIONS                                            │
│  (Tells the agent how to behave)                                │
├─────────────────────────────────────────────────────────────────┤
│  GLOBAL CONTEXT                                                 │
│  (Shared data contracts, schemas, etc.)                         │
├─────────────────────────────────────────────────────────────────┤
│  TASK DEFINITION                                                │
│  (Specific task with inputs/outputs/flow events)                │
├─────────────────────────────────────────────────────────────────┤
│  OUTPUT REQUIREMENTS                                            │
│  (What files to produce, format, etc.)                          │
└─────────────────────────────────────────────────────────────────┘
```

## Quick Start

1. Start with Phase 1 tasks (can run in parallel):
   - `JS_XS_01.md` → `JS_XS_02.md` → `JS_XS_03.md`
   - `FL_XS_01.md`

2. Continue with Phase 2 (Bridge Layer):
   - `FL_XS_02.md` (needs JS_XS_03)

3. Continue with Phase 3 (Use Case):
   - `FL_XS_03.md` (needs FL_XS_01, FL_XS_02)

4. Continue with Phase 4 (UI Layer):
   - `FL_XS_04.md` (no dependencies - pure layout)
   - `FL_XS_05.md` (needs FL_XS_03, FL_XS_04)

5. Run QA verification:
   - `QA_XS_01.md`

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│  USER TAP "Show QR"                                             │
└───────────────────────────────────┬─────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────┐
│  FL_XS_05: QRDisplayWired                                       │
│  - Calls buildQRPayload use case                                │
│  - Handles loading/error states                                 │
│  - Passes QR string to display widget                           │
└───────────────────────────────────┬─────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────┐
│  FL_XS_03: buildQRPayloadUseCase                                │
│  - Loads identity from repository                               │
│  - Builds unsigned payload                                      │
│  - Calls JS bridge for signing                                  │
│  - Returns signed JSON string                                   │
└───────────────────────────────────┬─────────────────────────────┘
                                    │
                    ┌───────────────┴───────────────┐
                    │                               │
                    ▼                               ▼
┌───────────────────────────┐       ┌───────────────────────────┐
│  M1: IdentityRepository   │       │  FL_XS_02: callJsSign     │
│  - loadIdentity()         │       │  - Sends to JS bridge     │
│  - Returns IdentityModel  │       │  - Returns signature      │
└───────────────────────────┘       └───────────────┬───────────┘
                                                    │
                                                    ▼
                                    ┌───────────────────────────┐
                                    │  JS_XS_03: Bridge Handler │
                                    │  - Receives payload.sign  │
                                    │  - Calls signPayload()    │
                                    └───────────────┬───────────┘
                                                    │
                                                    ▼
                                    ┌───────────────────────────┐
                                    │  JS_XS_02: signPayload()  │
                                    │  - Ed25519 signing        │
                                    │  - Returns base64 sig     │
                                    └───────────────────────────┘
```

## Tips

- **Always include the full prompt** - Each task file is self-contained
- **Don't skip tasks** - Even if they seem simple, the flow events are important
- **Verify before proceeding** - Check outputs match expected signatures
- **Keep outputs organized** - Use the file structure in `file-structure.md`
- **Test with M1 data** - Ensure identity exists before testing QR generation

## Dependencies

**Flutter:**
- `qr_flutter` - For QR code generation/display
- Reuse M1 crypto deps (existing: `sqflite`, M1 packages)

**JavaScript:**
- `@noble/ed25519` or `@libp2p/crypto` - For Ed25519 signing
- Reuse M1 crypto deps (existing: M1 packages)

Add to pubspec.yaml:
```yaml
dependencies:
  qr_flutter: ^4.1.0
```
