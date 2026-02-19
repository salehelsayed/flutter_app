# Task Prompt: DB_XS_03 - Upsert Identity Row

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
[TASK DB_XS_03 – DB helper: upsert identity row]

Owner: DB / Flutter-DB layer

Goal:
  Provide a helper to insert or update the active identity row at id=1.

What to implement:
  - Function signature:
      Future<void> dbUpsertIdentityRow(Database db, Map<String, Object?> row)
  
  - Behavior:
      - The input Map is expected to contain keys:
          "peer_id", "public_key", "private_key",
          "mnemonic12", "created_at", "updated_at"
      - Implement INSERT OR REPLACE (or equivalent)
      - Always write id=1
      - On error (e.g., DB locked) → throw/propagate exception

Inputs:
  - db: Database instance from sqflite
  - row: Map<String, Object?> with the columns above (no "id"; id is always 1)
  - Precondition: identity table exists

Outputs:
  - Side-effect: writes/overwrites row with id=1 in identity table
  - Return: Future<void>
  - DB errors surface as exceptions

Flow_events:
  - Before upsert:
      - layer: "DB"
      - event: "ID_DB_UPSERT_IDENTITY_START"
      - details: { "id": 1 }
  - On success:
      - layer: "DB"
      - event: "ID_DB_UPSERT_IDENTITY_SUCCESS"
      - details: { "id": 1 }
  - On error:
      - layer: "DB"
      - event: "ID_DB_UPSERT_IDENTITY_ERROR"
      - details: { "id": 1, "error": "<error_message>" }

Constraints:
  - Do not perform validation of the values (that belongs to higher layers)
  - Only one row with id=1 is allowed; this helper always targets id=1
  - Use INSERT OR REPLACE or equivalent upsert pattern

Deliverable:
  - Function ready to be called by the IdentityRepository implementation
```

---

## Output Requirements

1. **File:** `lib/core/database/helpers/identity_db_helpers.dart` (partial - this function only)

2. **Must include:**
   - The `dbUpsertIdentityRow` function
   - Flow event emissions
   - Hardcoded id=1
   - Error handling that emits event then rethrows

3. **Function signature:**
```dart
Future<void> dbUpsertIdentityRow(Database db, Map<String, Object?> row) async {
  // implementation
}
```

4. **Expected input shape:**
```dart
{
  'peer_id': '12D3KooW...',
  'public_key': 'base64...',
  'private_key': 'base64...',
  'mnemonic12': 'word1 word2 ... word12',
  'created_at': '2025-01-01T00:00:00.000Z',
  'updated_at': '2025-01-01T00:00:00.000Z',
}
```

Note: The function should add `'id': 1` when inserting.

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

## SQL Pattern

Use INSERT OR REPLACE pattern:

```sql
INSERT OR REPLACE INTO identity (id, peer_id, public_key, private_key, mnemonic12, created_at, updated_at)
VALUES (1, ?, ?, ?, ?, ?, ?)
```

Or use sqflite's `insert` with `conflictAlgorithm: ConflictAlgorithm.replace`.

---

## Begin Implementation

Implement the complete function now. Output the full code for the `dbUpsertIdentityRow` function.
