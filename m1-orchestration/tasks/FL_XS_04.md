# Task Prompt: FL_XS_04 - IdentityRepositoryImpl.saveIdentity()

## Instructions for AI Agent
You are implementing a specific task for a Flutter application. Follow the task specification exactly.

---

## Global Context
```
Model field names (camelCase): peerId, publicKey, privateKey, mnemonic12, createdAt, updatedAt
DB column names (snake_case): peer_id, public_key, private_key, mnemonic12, created_at, updated_at
```

---

## Task Definition
```
[TASK FL_XS_04 – IdentityRepositoryImpl.saveIdentity()]

Goal: Implement saveIdentity() using dbUpsertIdentityRow().

What to implement:
  - Update IdentityRepositoryImpl to:
      - Accept dbUpsertIdentityRow in constructor
      - Implement saveIdentity():
          1. Map IdentityModel (camelCase) to DB row (snake_case)
          2. Call dbUpsertIdentityRow(row)

Mapping:
  identity.peerId → "peer_id"
  identity.publicKey → "public_key"
  identity.privateKey → "private_key"
  identity.mnemonic12 → "mnemonic12"
  identity.createdAt → "created_at"
  identity.updatedAt → "updated_at"

Flow_events:
  - Before: layer: "FL", event: "ID_REPO_SAVE_IDENTITY_CALL", details: { peerId }
  - Success: layer: "FL", event: "ID_REPO_SAVE_IDENTITY_SUCCESS"
  - Error: layer: "FL", event: "ID_REPO_SAVE_IDENTITY_ERROR"

Deliverable:
  - File: lib/features/identity/domain/repositories/identity_repository_impl.dart
  - Complete implementation with both methods
```

## Begin Implementation
Output the complete Dart file with both methods working.
