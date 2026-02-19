# Task Prompt: DB_XS_01 - Identity Table Migration

## Instructions for AI Agent

You are implementing a specific task for a Flutter/JS application. Follow the task specification exactly. Output complete, working code that can be directly used.

---

## Global Context

```
Milestone: M1 – Identity Initialization (First Run)

Tech Stack:
  - Flutter with SQLite (sqflite package)
  - Single active identity stored in local DB

Database Schema (Target):
  CREATE TABLE IF NOT EXISTS identity (
    id INTEGER PRIMARY KEY,
    peer_id TEXT NOT NULL,
    public_key TEXT NOT NULL,
    private_key TEXT NOT NULL,
    mnemonic12 TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  );

Constraint: At most one active identity row with id = 1
```

---

## Task Definition

```
[TASK DB_XS_01 – Identity table migration]

Owner: DB / Flutter-DB layer

Goal:
  Create a DB migration that creates the identity table exactly as defined above.

What to implement:
  - One migration file/function that runs the CREATE TABLE statement
  - Make the migration idempotent (CREATE TABLE IF NOT EXISTS)
  - Integrate with a migration runner pattern

Inputs:
  - A DB connection / Database instance from sqflite
  - Precondition: DB file exists or is created by the app

Outputs:
  - Side-effect: identity table exists with the schema above
  - Return: Future<void>
  - SQL errors surface as exceptions

Flow_events:
  - On migration start:
      - layer: "DB"
      - event: "ID_DB_IDENTITY_MIGRATION_START"
      - details: { "table": "identity" }
  - On migration success:
      - layer: "DB"
      - event: "ID_DB_IDENTITY_MIGRATION_SUCCESS"
      - details: { "table": "identity" }
  - On migration error (catch & rethrow after logging):
      - layer: "DB"
      - event: "ID_DB_IDENTITY_MIGRATION_ERROR"
      - details: { "table": "identity", "error": "<error_message>" }

Constraints:
  - Do not create any other tables
  - Use sqflite package conventions
  - Must be idempotent (safe to run multiple times)

Deliverable:
  - Complete Dart file: `001_identity_table.dart`
  - Ready to be plugged into a migration pipeline
```

---

## Output Requirements

1. **File:** `lib/core/database/migrations/001_identity_table.dart`

2. **Must include:**
   - A function or class to run the migration
   - Flow event emissions at start, success, and error
   - The exact SQL schema from the global context
   - Error handling that logs then rethrows

3. **Code style:**
   - Use async/await
   - Include doc comments
   - Follow Dart conventions

4. **Example usage pattern:**
```dart
// How this migration will be called:
final db = await openDatabase('app.db');
await runIdentityTableMigration(db);
```

---

## Flow Event Helper

Assume this helper exists (you can include a simple version):

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

## Begin Implementation

Implement the complete migration file now. Output the full code for `001_identity_table.dart`.
