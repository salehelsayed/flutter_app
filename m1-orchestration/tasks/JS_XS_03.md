# Task Prompt: JS_XS_03 - restoreIdentityFromMnemonic()

## Instructions for AI Agent
You are implementing a specific task for a TypeScript/JavaScript library. Follow the task specification exactly.

---

## Task Definition
```
[TASK JS_XS_03 – Implement restoreIdentityFromMnemonic()]

Goal: Restore identity from 12-word mnemonic deterministically.

What to implement:
  - async function restoreIdentityFromMnemonic(mnemonic12: string): Promise<IdentityJson>
  - Steps:
      1. Validate word count == 12 (throw INVALID_MNEMONIC if not)
      2. Validate BIP39 checksum (throw INVALID_MNEMONIC if invalid)
      3. Derive seed from mnemonic
      4. Derive keypair from seed (deterministic)
      5. Derive peerId from public key
      6. Return IdentityJson

Key Property: Same mnemonic → same keypair → same peerId (deterministic)

Flow_events:
  - Start: layer: "JS", event: "ID_JS_RESTORE_IDENTITY_START"
  - Invalid count: layer: "JS", event: "ID_JS_RESTORE_IDENTITY_INVALID_WORDCOUNT"
  - Invalid mnemonic: layer: "JS", event: "ID_JS_RESTORE_IDENTITY_INVALID_MNEMONIC"
  - Success: layer: "JS", event: "ID_JS_RESTORE_IDENTITY_SUCCESS"

Error Handling:
  - Throw error with property type="INVALID_MNEMONIC" for validation failures

Deliverable:
  - File: core_lib_js/src/identity/restore.ts
```

## Begin Implementation
Output the complete TypeScript file.
