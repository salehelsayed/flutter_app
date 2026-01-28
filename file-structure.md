# M2 File Structure

This document shows where to place each generated code file.

---

## Project Structure Overview

```
your_flutter_app/
├── lib/
│   ├── core/
│   │   ├── constants/
│   │   │   └── network_constants.dart        # Rendezvous address constant
│   │   ├── bridge/
│   │   │   └── js_bridge_client.dart         # Add FL_XS_02 (callJsSignPayload)
│   │   └── utils/
│   │       └── flow_event_emitter.dart       # Shared flow event helper (from M1)
│   │
│   ├── features/
│   │   ├── identity/                         # From M1
│   │   │   └── ...
│   │   │
│   │   └── qr_code/                          # NEW for M2
│   │       ├── domain/
│   │       │   └── models/
│   │       │       └── qr_payload_model.dart     # FL_XS_01
│   │       │
│   │       ├── application/
│   │       │   └── build_qr_payload_use_case.dart # FL_XS_03
│   │       │
│   │       └── presentation/
│   │           └── screens/
│   │               ├── qr_display_screen.dart     # FL_XS_04
│   │               └── qr_display_wired.dart      # FL_XS_05
│   │
│   └── main.dart                              # App entry point
│
├── core_lib_js/                               # JavaScript core library
│   ├── src/
│   │   ├── types/
│   │   │   ├── identity.ts                   # From M1
│   │   │   └── qr_payload.ts                 # JS_XS_01
│   │   ├── identity/                         # From M1
│   │   │   └── ...
│   │   ├── signing/
│   │   │   └── sign_payload.ts               # JS_XS_02
│   │   ├── bridge/
│   │   │   └── handlers.ts                   # Add JS_XS_03 (payload.sign handler)
│   │   └── index.ts                          # Main export
│   ├── package.json
│   └── tsconfig.json
│
├── test/
│   └── ... (unit tests)
│
└── docs/
    └── qa/
        ├── QA_XS_01_new_identity.md          # From M1
        ├── QA_XS_02_restore.md               # From M1
        ├── QA_XS_03_relaunch.md              # From M1
        └── QA_M2_XS_01_qr_generation.md      # QA_XS_01 (M2)
```

---

## Task to File Mapping

| Task | Output File(s) | Location |
|------|---------------|----------|
| JS_XS_01 | `qr_payload.ts` | `core_lib_js/src/types/` |
| JS_XS_02 | `sign_payload.ts` | `core_lib_js/src/signing/` |
| JS_XS_03 | `handlers.ts` (addition) | `core_lib_js/src/bridge/` |
| FL_XS_01 | `qr_payload_model.dart` | `lib/features/qr_code/domain/models/` |
| FL_XS_02 | `js_bridge_client.dart` (addition) | `lib/core/bridge/` |
| FL_XS_03 | `build_qr_payload_use_case.dart` | `lib/features/qr_code/application/` |
| FL_XS_04 | `qr_display_screen.dart` | `lib/features/qr_code/presentation/screens/` |
| FL_XS_05 | `qr_display_wired.dart` | `lib/features/qr_code/presentation/screens/` |
| QA_XS_01 | `QA_M2_XS_01_qr_generation.md` | `docs/qa/` |

---

## File Contents Guide

### Files That Add to Existing M1 Files

Some files add functions to existing files from M1. Here's how to merge them:

#### `js_bridge_client.dart` (Adding to M1 file)

```dart
// lib/core/bridge/js_bridge_client.dart

class JsBridgeClient {
  // ... existing M1 methods ...

  // From M1 FL_XS_08
  Future<Map<String, dynamic>> callJsIdentityGenerate() async {
    // ... existing implementation
  }

  // From M1 FL_XS_09
  Future<Map<String, dynamic>> callJsIdentityRestore(String mnemonic12) async {
    // ... existing implementation
  }

  // NEW: From M2 FL_XS_02
  Future<Map<String, dynamic>> callJsSignPayload({
    required String dataToSign,
    required String privateKey,
  }) async {
    // ... implementation from FL_XS_02
  }
}
```

#### `handlers.ts` (Adding to M1 file)

```typescript
// core_lib_js/src/bridge/handlers.ts

// ... existing M1 handlers ...

// From M1: identity.generate handler
handlers.set('identity.generate', async (payload) => {
  // ... existing implementation
});

// From M1: identity.restore handler
handlers.set('identity.restore', async (payload) => {
  // ... existing implementation
});

// NEW: From M2 JS_XS_03
handlers.set('payload.sign', async (payload) => {
  // ... implementation from JS_XS_03
});
```

---

## New Files (M2 Specific)

### `qr_payload.ts`

```typescript
// core_lib_js/src/types/qr_payload.ts

/**
 * Unsigned QR payload (before signing)
 */
export interface UnsignedQRPayload {
  pk: string;   // public key (base64)
  ns: string;   // namespace (peerID)
  rv: string;   // rendezvous address
  ts: string;   // ISO-8601 timestamp
}

/**
 * Signed QR payload (after signing)
 */
export interface SignedQRPayload extends UnsignedQRPayload {
  sig: string;  // signature (base64)
}
```

### `sign_payload.ts`

```typescript
// core_lib_js/src/signing/sign_payload.ts

import { emitFlowEvent } from '../utils/flow_events';

export async function signPayload(
  dataToSign: string,
  privateKeyBase64: string
): Promise<string> {
  // ... implementation from JS_XS_02
}
```

### `qr_payload_model.dart`

```dart
// lib/features/qr_code/domain/models/qr_payload_model.dart

class QRPayloadModel {
  final String pk;
  final String ns;
  final String rv;
  final String ts;
  final String sig;

  // ... implementation from FL_XS_01
}
```

### `build_qr_payload_use_case.dart`

```dart
// lib/features/qr_code/application/build_qr_payload_use_case.dart

enum BuildQRPayloadResult {
  success,
  noIdentity,
  signingError,
}

Future<(BuildQRPayloadResult, String?)> buildQRPayload({
  required IdentityRepository repo,
  required Future<Map<String, dynamic>> Function(String, String) callJsSign,
}) async {
  // ... implementation from FL_XS_03
}
```

### `qr_display_screen.dart`

```dart
// lib/features/qr_code/presentation/screens/qr_display_screen.dart

class QRDisplayScreen extends StatelessWidget {
  final String qrData;
  final String peerId;
  final VoidCallback? onShare;
  final VoidCallback onClose;

  // ... implementation from FL_XS_04
}
```

### `qr_display_wired.dart`

```dart
// lib/features/qr_code/presentation/screens/qr_display_wired.dart

class QRDisplayWired extends StatefulWidget {
  // ... implementation from FL_XS_05
}
```

---

## Constants File

Create this file for shared constants:

```dart
// lib/core/constants/network_constants.dart

/// Rendezvous point for P2P connections
const String RENDEZVOUS_ADDRESS = 
    '/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g';
```

---

## Import Structure

### Dart Import Order for M2 Files

```dart
// 1. Dart SDK
import 'dart:convert';

// 2. Flutter SDK
import 'package:flutter/material.dart';

// 3. Third-party packages
import 'package:qr_flutter/qr_flutter.dart';

// 4. Project imports - core
import 'package:your_app/core/constants/network_constants.dart';
import 'package:your_app/core/bridge/js_bridge_client.dart';
import 'package:your_app/core/utils/flow_event_emitter.dart';

// 5. Project imports - M1 feature (identity)
import 'package:your_app/features/identity/domain/repositories/identity_repository.dart';

// 6. Project imports - M2 feature (qr_code)
import 'package:your_app/features/qr_code/domain/models/qr_payload_model.dart';
```

### JS/TS Import Order for M2 Files

```typescript
// 1. Node built-ins
import { Buffer } from 'buffer';

// 2. Third-party packages
import * as ed from '@noble/ed25519';

// 3. Project imports - types
import { UnsignedQRPayload, SignedQRPayload } from '../types/qr_payload';

// 4. Project imports - utils
import { emitFlowEvent } from '../utils/flow_events';
```

---

## Barrel Exports

Create/update index files for clean imports:

### `lib/features/qr_code/domain/models/index.dart`

```dart
export 'qr_payload_model.dart';
```

### `lib/features/qr_code/application/index.dart`

```dart
export 'build_qr_payload_use_case.dart';
```

### `lib/features/qr_code/presentation/screens/index.dart`

```dart
export 'qr_display_screen.dart';
export 'qr_display_wired.dart';
```

### `core_lib_js/src/index.ts` (add to existing)

```typescript
// Existing M1 exports
export * from './types/identity';
export * from './identity/generate';
export * from './identity/restore';
export * from './bridge/handlers';

// NEW M2 exports
export * from './types/qr_payload';
export * from './signing/sign_payload';
```

---

## Quick Setup Commands

```bash
# Create Flutter directory structure for M2
mkdir -p lib/core/constants
mkdir -p lib/features/qr_code/domain/models
mkdir -p lib/features/qr_code/application
mkdir -p lib/features/qr_code/presentation/screens

# Create JS directory structure for M2
mkdir -p core_lib_js/src/signing

# Add qr_flutter package
flutter pub add qr_flutter
```

---

## Package Dependencies

### pubspec.yaml additions

```yaml
dependencies:
  # ... existing dependencies ...
  qr_flutter: ^4.1.0  # For QR code generation
```

### package.json additions (if not already present)

```json
{
  "dependencies": {
    "@noble/ed25519": "^2.0.0"
  }
}
```
