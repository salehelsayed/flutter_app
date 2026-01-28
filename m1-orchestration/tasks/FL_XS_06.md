# Task Prompt: FL_XS_06 - generateNewIdentity() Use Case

## Instructions for AI Agent

You are implementing a specific task for a Flutter/JS application. Follow the task specification exactly. Output complete, working code that can be directly used.

---

## Global Context

```
Milestone: M1 – Identity Initialization (First Run)

JS Bridge Response for identity.generate:
  Success: { "ok": true, "identity": IdentityJson }
  Error: { "ok": false, "errorCode": "INTERNAL_ERROR", "errorMessage": "..." }

IdentityJson shape:
  { "peerId", "publicKey", "privateKey", "mnemonic12", "createdAt", "updatedAt" }
```

---

## Task Definition

```
[TASK FL_XS_06 – Use case: generateNewIdentity()]

Owner: Flutter

Goal:
  Implement a use-case function that:
    - Calls JS bridge "identity.generate"
    - Maps result to IdentityModel
    - Persists to IdentityRepository

What to implement:
  - enum GenerateIdentityResult { success, coreLibError, dbError }
  
  - Function:
      Future<GenerateIdentityResult> generateNewIdentity({
        required Future<Map<String, dynamic>> Function() callJsGenerate,
        required IdentityRepository repo,
      });
  
  - Behavior:
      1. Call callJsGenerate()
      2. If ok == false → return coreLibError
      3. If ok == true:
         - Build IdentityModel from response["identity"]
         - Try repo.saveIdentity(identity)
         - On DB success → return success
         - On DB error → return dbError

Inputs:
  - callJsGenerate: Injected bridge function (from FL_XS_08)
  - repo: IdentityRepository

Outputs:
  - GenerateIdentityResult enum value
  - Side-effect on success: DB row created/updated

Flow_events:
  - At start: layer: "FL", event: "ID_M1_GENERATE_START"
  - Before JS call: layer: "FL", event: "ID_M1_GENERATE_JS_CALL"
  - On JS ok=true: layer: "FL", event: "ID_M1_GENERATE_JS_OK", details: { "peerId": ... }
  - On JS ok=false: layer: "FL", event: "ID_M1_GENERATE_JS_ERROR", details: { "errorCode": ... }
  - On DB save success: layer: "FL", event: "ID_M1_DB_SAVE_SUCCESS", details: { "source": "generate" }
  - On DB save error: layer: "FL", event: "ID_M1_DB_SAVE_ERROR", details: { "source": "generate" }

Constraints:
  - callJsGenerate is injected (dependency injection pattern)
  - Do not import concrete bridge implementation

Deliverable:
  - File: lib/features/identity/application/generate_identity_use_case.dart
```

---

## Begin Implementation

Output the full code for `generate_identity_use_case.dart`.
