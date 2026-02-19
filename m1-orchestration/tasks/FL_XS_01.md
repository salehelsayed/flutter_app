# Task Prompt: FL_XS_01 - IdentityModel with JSON Mapping

## Instructions for AI Agent
You are implementing a specific task for a Flutter application. Follow the task specification exactly.

---

## Global Context
```
Canonical IdentityJson (camelCase keys):
{
  "peerId": "string",
  "publicKey": "base64-string",
  "privateKey": "base64-string",
  "mnemonic12": "word1 ... word12",
  "createdAt": "ISO-8601-UTC",
  "updatedAt": "ISO-8601-UTC"
}
```

---

## Task Definition
```
[TASK FL_XS_01 – Dart IdentityModel with JSON mapping]

Goal: Create immutable Dart model matching IdentityJson.

What to implement:
  - class IdentityModel with final String fields:
      peerId, publicKey, privateKey, mnemonic12, createdAt, updatedAt
  - Constructor with required named parameters
  - factory IdentityModel.fromJson(Map<String, dynamic> json)
  - Map<String, dynamic> toJson()

Inputs:
  - For fromJson: Map with camelCase keys
  - For toJson: IdentityModel instance

Outputs:
  - Immutable model instance
  - JSON map with camelCase keys

Flow_events:
  - None (pure data class)

Constraints:
  - No DB logic
  - Keep immutable

Deliverable:
  - File: lib/features/identity/domain/models/identity_model.dart
```

## Begin Implementation
Output the complete Dart file.
