# Task Prompt: FL_XS_08 - callJsIdentityGenerate() Bridge Client

## Instructions for AI Agent
You are implementing a specific task for a Flutter/JS application. Follow the task specification exactly.

---

## Global Context
```
JS Bridge Contract for identity.generate:
  Request: { "cmd": "identity.generate", "payload": {} }
  Response: { "ok": true, "identity": IdentityJson }
        or: { "ok": false, "errorCode": "INTERNAL_ERROR", "errorMessage": "..." }
```

---

## Task Definition
```
[TASK FL_XS_08 – Flutter JS bridge client: identity.generate]

Goal: Implement helper to call JS bridge "identity.generate".

What to implement:
  - Function: Future<Map<String, dynamic>> callJsIdentityGenerate(JsBridge bridge)
  - Build request: { "cmd": "identity.generate", "payload": {} }
  - Send via bridge, decode response, return Map as-is

Inputs:
  - bridge: JsBridge instance

Outputs:
  - Map with { "ok": bool, "identity": {...} } or { "ok": false, "errorCode": "...", ... }

Flow_events:
  - Before: layer: "FL", event: "ID_BRIDGE_IDENTITY_GENERATE_REQUEST"
  - After: layer: "FL", event: "ID_BRIDGE_IDENTITY_GENERATE_RESPONSE"

Deliverable:
  - File: lib/core/bridge/js_bridge_client.dart (this function)
```

## Begin Implementation
Output the complete function code.
