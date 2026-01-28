# Task Prompt: FL_XS_07 - restoreIdentityFromMnemonic() Use Case

## Instructions for AI Agent

You are implementing a specific task for a Flutter/JS application. Follow the task specification exactly. Output complete, working code that can be directly used.

---

## Global Context

```
Milestone: M1 – Identity Initialization (First Run)

JS Bridge Response for identity.restore:
  Success: { "ok": true, "identity": IdentityJson }
  Error: { "ok": false, "errorCode": "INVALID_MNEMONIC" | "INTERNAL_ERROR", "errorMessage": "..." }

Valid mnemonic: exactly 12 BIP39 words separated by spaces
```

---

## Task Definition

```
[TASK FL_XS_07 – Use case: restoreIdentityFromMnemonic()]

Owner: Flutter

Goal:
  Implement a use-case function to validate mnemonic, call JS, and save identity.

What to implement:
  - enum RestoreIdentityResult {
      success,
      invalidMnemonicFormat,  // word count != 12
      invalidMnemonicCore,    // JS returned INVALID_MNEMONIC
      coreLibError,           // JS returned other error
      dbError,                // DB save failed
    }
  
  - Function:
      Future<RestoreIdentityResult> restoreIdentityFromMnemonic({
        required String input,
        required Future<Map<String, dynamic>> Function(String) callJsRestore,
        required IdentityRepository repo,
      });
  
  - Behavior:
      1. Local validation: trim input, split by spaces, check count == 12
         - If count != 12 → return invalidMnemonicFormat
      2. Call callJsRestore(normalized_mnemonic)
      3. If ok == false:
         - If errorCode == "INVALID_MNEMONIC" → invalidMnemonicCore
         - Else → coreLibError
      4. If ok == true:
         - Build IdentityModel from response["identity"]
         - Try repo.saveIdentity(identity)
         - On success → return success
         - On error → return dbError

Inputs:
  - input: Raw mnemonic string from UI (may have extra spaces, wrong case)
  - callJsRestore: Injected bridge function (from FL_XS_09)
  - repo: IdentityRepository

Outputs:
  - RestoreIdentityResult enum value
  - Side-effect on success: DB row created/updated

Flow_events:
  - At start: layer: "FL", event: "ID_M1_RESTORE_START"
  - On validation fail: layer: "FL", event: "ID_RESTORE_VALIDATION_FAIL", details: { "wordCount": n }
  - Before JS call: layer: "FL", event: "ID_M1_RESTORE_JS_CALL"
  - On JS ok=true: layer: "FL", event: "ID_M1_RESTORE_JS_OK", details: { "peerId": ... }
  - On JS INVALID_MNEMONIC: layer: "FL", event: "ID_RESTORE_INVALID_MNEMONIC_CORE"
  - On JS other error: layer: "FL", event: "ID_RESTORE_CORELIB_ERROR"
  - On DB save success: layer: "FL", event: "ID_M1_DB_SAVE_SUCCESS", details: { "source": "restore" }
  - On DB save error: layer: "FL", event: "ID_M1_DB_SAVE_ERROR", details: { "source": "restore" }

Constraints:
  - Normalize mnemonic: trim, lowercase, collapse multiple spaces
  - callJsRestore is injected

Deliverable:
  - File: lib/features/identity/application/restore_identity_use_case.dart
```

---

## Begin Implementation

Output the full code for `restore_identity_use_case.dart`.
