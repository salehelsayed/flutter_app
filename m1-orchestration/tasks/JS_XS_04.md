# Task Prompt: JS_XS_04 - Bridge Handlers

## Instructions for AI Agent
You are implementing a specific task for a TypeScript/JavaScript library. Follow the task specification exactly.

---

## Global Context
```
Bridge Response Contract:
  Success: { "ok": true, "identity": IdentityJson }
  Error: { "ok": false, "errorCode": "INVALID_MNEMONIC"|"INTERNAL_ERROR", "errorMessage": "..." }
```

---

## Task Definition
```
[TASK JS_XS_04 – JS bridge handlers]

Goal: Register handlers for identity.generate and identity.restore commands.

What to implement:
  - Handler "identity.generate":
      - Call generateIdentity()
      - On success: { ok: true, identity }
      - On error: { ok: false, errorCode: "INTERNAL_ERROR", errorMessage }

  - Handler "identity.restore":
      - Get mnemonic12 from payload
      - Call restoreIdentityFromMnemonic(mnemonic12)
      - On success: { ok: true, identity }
      - On INVALID_MNEMONIC: { ok: false, errorCode: "INVALID_MNEMONIC", errorMessage }
      - On other error: { ok: false, errorCode: "INTERNAL_ERROR", errorMessage }

Flow_events:
  - On receive: ID_JS_BRIDGE_IDENTITY_*_RECEIVED
  - On success: ID_JS_BRIDGE_IDENTITY_*_SUCCESS
  - On error: ID_JS_BRIDGE_IDENTITY_*_ERROR

Deliverable:
  - File: core_lib_js/src/bridge/handlers.ts
```

## Handler Pattern
```typescript
// Assume this registration function exists:
function registerHandler(cmd: string, handler: (payload: any) => Promise<any>): void;
```

## Begin Implementation
Output the complete TypeScript file.
