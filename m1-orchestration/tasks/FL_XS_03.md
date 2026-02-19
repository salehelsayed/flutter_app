# Task Prompt: FL_XS_03 - IdentityRepositoryImpl.loadIdentity()

## Instructions for AI Agent
You are implementing a specific task for a Flutter application. Follow the task specification exactly.

---

## Global Context
```
DB column names (snake_case): peer_id, public_key, private_key, mnemonic12, created_at, updated_at
Model field names (camelCase): peerId, publicKey, privateKey, mnemonic12, createdAt, updatedAt
```

---

## Task Definition
```
[TASK FL_XS_03 – IdentityRepositoryImpl.loadIdentity()]

Goal: Implement loadIdentity() using dbLoadIdentityRow().

What to implement:
  - class IdentityRepositoryImpl implements IdentityRepository
  - Constructor accepting dbLoadIdentityRow function
  - loadIdentity():
      1. Call dbLoadIdentityRow()
      2. If null → return null
      3. Map DB row (snake_case) to IdentityModel (camelCase)

Mapping:
  row["peer_id"] → peerId
  row["public_key"] → publicKey
  row["private_key"] → privateKey
  row["mnemonic12"] → mnemonic12
  row["created_at"] → createdAt
  row["updated_at"] → updatedAt

Flow_events:
  - Before: layer: "FL", event: "ID_REPO_LOAD_IDENTITY_CALL"
  - Found: layer: "FL", event: "ID_REPO_LOAD_IDENTITY_FOUND"
  - Not found: layer: "FL", event: "ID_REPO_LOAD_IDENTITY_NOT_FOUND"

Deliverable:
  - File: lib/features/identity/domain/repositories/identity_repository_impl.dart
  - Note: saveIdentity() will be stub/unimplemented (done in FL_XS_04)
```

## Begin Implementation
Output the complete Dart file with loadIdentity() working.
