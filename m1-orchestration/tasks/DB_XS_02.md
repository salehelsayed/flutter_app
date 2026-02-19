# Task Prompt: DB_XS_02 - Load Identity Row

## Instructions for AI Agent

You are implementing a specific task for a Flutter/JS application. Follow the task specification exactly. Output complete, working code that can be directly used.

---

## Global Context

```
Milestone: M1 – Identity Initialization (First Run)

Database Schema:
  CREATE TABLE IF NOT EXISTS identity (
    id INTEGER PRIMARY KEY,          -- Always 1
    peer_id TEXT NOT NULL,
    public_key TEXT NOT NULL,
    private_key TEXT NOT NULL,
    mnemonic12 TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  );

Constraint: At most one active identity row with id = 1

Column names use snake_case in DB.
```

---

## Task Definition

```
[TASK DB_XS_02 – DB helper: load identity row]

Owner: DB / Flutter-DB layer

Goal:
  Provide a small helper to read the single identity row (id=1) from the DB.

What to implement:
  - Function signature:
      Future<Map<String, Object?>?> dbLoadIdentityRow(Database db)
  
  - Behavior:
      - Run: SELECT * FROM identity WHERE id = 1 LIMIT 1;
      - If a row exists → return a Map with keys:
          "id", "peer_id", "public_key", "private_key",
          "mnemonic12", "created_at", "updated_at"
      - If no row → return null
      - If the table does not exist → surface the error (do not swallow)

Inputs:
  - db: Database instance from sqflite
  - Precondition: identity table migration ideally already applied

Outputs:
  - On success with row: Map<String, Object?> representing the row
  - On success no row: null
  - On failure: DB error surfaced via exception
  - No write side-effects

Flow_events:
  - Before query:
      - layer: "DB"
      - event: "ID_DB_LOAD_IDENTITY_START"
      - details: { "id": 1 }
  - After query – row found:
      - layer: "DB"
      - event: "ID_DB_LOAD_IDENTITY_FOUND"
      - details: { "id": 1 }
  - After query – no row:
      - layer: "DB"
      - event: "ID_DB_LOAD_IDENTITY_NOT_FOUND"
      - details: { "id": 1 }
  - On DB error:
      - layer: "DB"
      - event: "ID_DB_LOAD_IDENTITY_ERROR"
      - details: { "id": 1, "error": "<error_message>" }

Constraints:
  - Use the exact column names from the schema (snake_case)
  - No knowledge of IdentityModel or JS, just raw DB row
  - Read-only operation

Deliverable:
  - Function ready to be called from the repository layer
```

---

## Output Requirements

1. **File:** `lib/core/database/helpers/identity_db_helpers.dart` (partial - this function only)

2. **Must include:**
   - The `dbLoadIdentityRow` function
   - Flow event emissions
   - Proper null handling
   - Error handling that emits event then rethrows

3. **Function signature:**
```dart
Future<Map<String, Object?>?> dbLoadIdentityRow(Database db) async {
  // implementation
}
```

4. **Expected return shape when row exists:**
```dart
{
  'id': 1,
  'peer_id': '12D3KooW...',
  'public_key': 'base64...',
  'private_key': 'base64...',
  'mnemonic12': 'word1 word2 ... word12',
  'created_at': '2025-01-01T00:00:00.000Z',
  'updated_at': '2025-01-01T00:00:00.000Z',
}
```

---

## Flow Event Helper

Assume this helper exists:

```dart
void emitFlowEvent({
  required String layer,
  required String event,
  required Map<String, dynamic> details,
}) {
  print('[FLOW] $layer | $event | $details');
}
```

---

## Required Import

```dart
import 'package:sqflite/sqflite.dart';
```

---

## Begin Implementation

Implement the complete function now. Output the full code for the `dbLoadIdentityRow` function.
