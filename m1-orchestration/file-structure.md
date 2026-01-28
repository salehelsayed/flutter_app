# M1 File Structure

This document shows where to place each generated code file.

---

## Project Structure Overview

```
your_flutter_app/
├── lib/
│   ├── core/
│   │   ├── database/
│   │   │   ├── database_helper.dart          # DB connection singleton
│   │   │   ├── migrations/
│   │   │   │   └── 001_identity_table.dart   # DB_XS_01
│   │   │   └── helpers/
│   │   │       └── identity_db_helpers.dart  # DB_XS_02, DB_XS_03
│   │   ├── bridge/
│   │   │   └── js_bridge_client.dart         # FL_XS_08, FL_XS_09
│   │   └── utils/
│   │       └── flow_event_emitter.dart       # Shared flow event helper
│   │
│   ├── features/
│   │   └── identity/
│   │       ├── domain/
│   │       │   ├── models/
│   │       │   │   └── identity_model.dart   # FL_XS_01
│   │       │   └── repositories/
│   │       │       ├── identity_repository.dart      # FL_XS_02
│   │       │       └── identity_repository_impl.dart # FL_XS_03, FL_XS_04
│   │       │
│   │       ├── application/
│   │       │   ├── startup_decision.dart             # FL_XS_05
│   │       │   ├── generate_identity_use_case.dart   # FL_XS_06
│   │       │   └── restore_identity_use_case.dart    # FL_XS_07
│   │       │
│   │       └── presentation/
│   │           ├── screens/
│   │           │   ├── identity_choice_screen.dart   # FL_XS_10
│   │           │   ├── identity_choice_wired.dart    # FL_XS_11, FL_XS_12
│   │           │   ├── mnemonic_input_screen.dart    # FL_XS_13
│   │           │   └── mnemonic_input_wired.dart     # FL_XS_14
│   │           └── startup_router.dart               # FL_XS_15
│   │
│   └── main.dart                              # App entry point
│
├── core_lib_js/                               # JavaScript core library
│   ├── src/
│   │   ├── types/
│   │   │   └── identity.ts                   # JS_XS_01
│   │   ├── identity/
│   │   │   ├── generate.ts                   # JS_XS_02
│   │   │   └── restore.ts                    # JS_XS_03
│   │   ├── bridge/
│   │   │   └── handlers.ts                   # JS_XS_04
│   │   └── index.ts                          # Main export
│   ├── package.json
│   └── tsconfig.json
│
├── test/
│   └── ... (unit tests)
│
└── docs/
    └── qa/
        ├── QA_XS_01_new_identity.md          # QA_XS_01
        ├── QA_XS_02_restore.md               # QA_XS_02
        └── QA_XS_03_relaunch.md              # QA_XS_03
```

---

## Task to File Mapping

| Task | Output File(s) | Location |
|------|---------------|----------|
| DB_XS_01 | `001_identity_table.dart` | `lib/core/database/migrations/` |
| DB_XS_02 | `identity_db_helpers.dart` (partial) | `lib/core/database/helpers/` |
| DB_XS_03 | `identity_db_helpers.dart` (partial) | `lib/core/database/helpers/` |
| FL_XS_01 | `identity_model.dart` | `lib/features/identity/domain/models/` |
| FL_XS_02 | `identity_repository.dart` | `lib/features/identity/domain/repositories/` |
| FL_XS_03 | `identity_repository_impl.dart` (partial) | `lib/features/identity/domain/repositories/` |
| FL_XS_04 | `identity_repository_impl.dart` (partial) | `lib/features/identity/domain/repositories/` |
| FL_XS_05 | `startup_decision.dart` | `lib/features/identity/application/` |
| FL_XS_06 | `generate_identity_use_case.dart` | `lib/features/identity/application/` |
| FL_XS_07 | `restore_identity_use_case.dart` | `lib/features/identity/application/` |
| FL_XS_08 | `js_bridge_client.dart` (partial) | `lib/core/bridge/` |
| FL_XS_09 | `js_bridge_client.dart` (partial) | `lib/core/bridge/` |
| FL_XS_10 | `identity_choice_screen.dart` | `lib/features/identity/presentation/screens/` |
| FL_XS_11 | `identity_choice_wired.dart` (partial) | `lib/features/identity/presentation/screens/` |
| FL_XS_12 | `identity_choice_wired.dart` (partial) | `lib/features/identity/presentation/screens/` |
| FL_XS_13 | `mnemonic_input_screen.dart` | `lib/features/identity/presentation/screens/` |
| FL_XS_14 | `mnemonic_input_wired.dart` | `lib/features/identity/presentation/screens/` |
| FL_XS_15 | `startup_router.dart` | `lib/features/identity/presentation/` |
| JS_XS_01 | `identity.ts` | `core_lib_js/src/types/` |
| JS_XS_02 | `generate.ts` | `core_lib_js/src/identity/` |
| JS_XS_03 | `restore.ts` | `core_lib_js/src/identity/` |
| JS_XS_04 | `handlers.ts` | `core_lib_js/src/bridge/` |
| QA_XS_01 | `QA_XS_01_new_identity.md` | `docs/qa/` |
| QA_XS_02 | `QA_XS_02_restore.md` | `docs/qa/` |
| QA_XS_03 | `QA_XS_03_relaunch.md` | `docs/qa/` |

---

## File Contents Guide

### Files That Combine Multiple Tasks

Some files contain code from multiple tasks. Here's how to merge them:

#### `identity_db_helpers.dart`

```dart
// lib/core/database/helpers/identity_db_helpers.dart

// From DB_XS_02
Future<Map<String, Object?>?> dbLoadIdentityRow() async {
  // ... implementation from DB_XS_02
}

// From DB_XS_03
Future<void> dbUpsertIdentityRow(Map<String, Object?> row) async {
  // ... implementation from DB_XS_03
}
```

#### `identity_repository_impl.dart`

```dart
// lib/features/identity/domain/repositories/identity_repository_impl.dart

class IdentityRepositoryImpl implements IdentityRepository {
  final Future<Map<String, Object?>?> Function() _dbLoadIdentityRow;
  final Future<void> Function(Map<String, Object?>) _dbUpsertIdentityRow;

  IdentityRepositoryImpl({
    required Future<Map<String, Object?>?> Function() dbLoadIdentityRow,
    required Future<void> Function(Map<String, Object?>) dbUpsertIdentityRow,
  })  : _dbLoadIdentityRow = dbLoadIdentityRow,
        _dbUpsertIdentityRow = dbUpsertIdentityRow;

  // From FL_XS_03
  @override
  Future<IdentityModel?> loadIdentity() async {
    // ... implementation from FL_XS_03
  }

  // From FL_XS_04
  @override
  Future<void> saveIdentity(IdentityModel identity) async {
    // ... implementation from FL_XS_04
  }
}
```

#### `js_bridge_client.dart`

```dart
// lib/core/bridge/js_bridge_client.dart

class JsBridgeClient {
  // Bridge setup code...

  // From FL_XS_08
  Future<Map<String, dynamic>> callJsIdentityGenerate() async {
    // ... implementation from FL_XS_08
  }

  // From FL_XS_09
  Future<Map<String, dynamic>> callJsIdentityRestore(String mnemonic12) async {
    // ... implementation from FL_XS_09
  }
}
```

#### `identity_choice_wired.dart`

```dart
// lib/features/identity/presentation/screens/identity_choice_wired.dart

class IdentityChoiceWired extends StatefulWidget {
  // ... state management

  // From FL_XS_11
  Future<void> _handleNewHere() async {
    // ... implementation from FL_XS_11
  }

  // From FL_XS_12
  void _handleLoadMyKey() {
    // ... implementation from FL_XS_12
  }

  @override
  Widget build(BuildContext context) {
    return IdentityChoiceScreen(
      onNewHere: _handleNewHere,
      onLoadMyKey: _handleLoadMyKey,
    );
  }
}
```

---

## Import Structure

### Dart Import Order

```dart
// 1. Dart SDK
import 'dart:async';
import 'dart:convert';

// 2. Flutter SDK
import 'package:flutter/material.dart';

// 3. Third-party packages
import 'package:sqflite/sqflite.dart';

// 4. Project imports - core
import 'package:your_app/core/database/database_helper.dart';
import 'package:your_app/core/bridge/js_bridge_client.dart';
import 'package:your_app/core/utils/flow_event_emitter.dart';

// 5. Project imports - feature
import 'package:your_app/features/identity/domain/models/identity_model.dart';
import 'package:your_app/features/identity/domain/repositories/identity_repository.dart';
```

### JS/TS Import Order

```typescript
// 1. Node built-ins
import { Buffer } from 'buffer';

// 2. Third-party packages
import * as bip39 from 'bip39';
import { Ed25519Provider } from '...';

// 3. Project imports
import { IdentityJson } from '../types/identity';
import { emitFlowEvent } from '../utils/flow_events';
```

---

## Barrel Exports

Create index files for clean imports:

### `lib/features/identity/domain/models/index.dart`

```dart
export 'identity_model.dart';
```

### `lib/features/identity/domain/repositories/index.dart`

```dart
export 'identity_repository.dart';
export 'identity_repository_impl.dart';
```

### `lib/features/identity/application/index.dart`

```dart
export 'startup_decision.dart';
export 'generate_identity_use_case.dart';
export 'restore_identity_use_case.dart';
```

### `core_lib_js/src/index.ts`

```typescript
export * from './types/identity';
export * from './identity/generate';
export * from './identity/restore';
export * from './bridge/handlers';
```

---

## Shared Utilities

### Flow Event Emitter (Create Before Tasks)

```dart
// lib/core/utils/flow_event_emitter.dart

import 'dart:convert';

void emitFlowEvent({
  required String layer,
  required String event,
  required Map<String, dynamic> details,
}) {
  final payload = {
    'ts': DateTime.now().toUtc().toIso8601String(),
    'milestone': 'M1_IDENTITY_INIT',
    'layer': layer,
    'event': event,
    'details': details,
  };
  
  // In debug mode, print to console
  assert(() {
    print('[FLOW] ${jsonEncode(payload)}');
    return true;
  }());
  
  // In production, could send to analytics/logging service
}
```

```typescript
// core_lib_js/src/utils/flow_events.ts

export function emitFlowEvent({
  layer,
  event,
  details,
}: {
  layer: 'JS';
  event: string;
  details: Record<string, unknown>;
}) {
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

---

## Quick Setup Commands

```bash
# Create Flutter directory structure
mkdir -p lib/core/database/migrations
mkdir -p lib/core/database/helpers
mkdir -p lib/core/bridge
mkdir -p lib/core/utils
mkdir -p lib/features/identity/domain/models
mkdir -p lib/features/identity/domain/repositories
mkdir -p lib/features/identity/application
mkdir -p lib/features/identity/presentation/screens
mkdir -p docs/qa

# Create JS directory structure
mkdir -p core_lib_js/src/types
mkdir -p core_lib_js/src/identity
mkdir -p core_lib_js/src/bridge
mkdir -p core_lib_js/src/utils
```
