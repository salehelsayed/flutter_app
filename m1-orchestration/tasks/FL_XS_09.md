# Task Prompt: FL_XS_09 - callJsIdentityRestore() Bridge Client

## Instructions for AI Agent
You are implementing a specific task for a Flutter/JS application. Follow the task specification exactly.

---

## Global Context
```
JS Bridge Contract for identity.restore:
  Request: { "cmd": "identity.restore", "payload": { "mnemonic12": "word1 ... word12" } }
  Response: { "ok": true, "identity": IdentityJson }
        or: { "ok": false, "errorCode": "INVALID_MNEMONIC"|"INTERNAL_ERROR", "errorMessage": "..." }
```

---

## Task Definition
```
[TASK FL_XS_09 – Flutter JS bridge client: identity.restore]

Goal: Implement helper to call JS bridge "identity.restore".

What to implement:
  - Function: Future<Map<String, dynamic>> callJsIdentityRestore(JsBridge bridge, String mnemonic12)
  - Build request: { "cmd": "identity.restore", "payload": { "mnemonic12": mnemonic12 } }
  - Send via bridge, decode response, return Map as-is

Inputs:
  - bridge: JsBridge instance
  - mnemonic12: String with 12 words

Outputs:
  - Map with response (success or error)

Flow_events:
  - Before: layer: "FL", event: "ID_BRIDGE_IDENTITY_RESTORE_REQUEST"
  - After: layer: "FL", event: "ID_BRIDGE_IDENTITY_RESTORE_RESPONSE"

Deliverable:
  - Add to: lib/core/bridge/js_bridge_client.dart
```

## Begin Implementation
Output the complete function code.
