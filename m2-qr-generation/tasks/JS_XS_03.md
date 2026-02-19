# Task Prompt: JS_XS_03 - Bridge Handler for payload.sign

## Instructions for AI Agent

You are implementing a specific task for a Flutter/JS application. Follow the task specification exactly. Output complete, working code that can be directly used.

---

## Global Context

```
Milestone: M2 – QR Code Generation

M2 adds ONE new command to the existing bridge infrastructure:
  - Command: "payload.sign"
  - Purpose: Sign canonical JSON payloads using Ed25519

Bridge Contract for payload.sign:
  Request:
    {
      "cmd": "payload.sign",
      "requestId": "uuid-string",
      "payload": {
        "dataToSign": "canonical-json-string",
        "privateKey": "base64-encoded-private-key"
      }
    }

  Success Response:
    {
      "ok": true,
      "requestId": "uuid-string",
      "signature": "base64-encoded-signature"
    }

  Error Response:
    {
      "ok": false,
      "requestId": "uuid-string",
      "errorCode": "SIGNING_ERROR" | "INVALID_PRIVATE_KEY" | "INTERNAL_ERROR",
      "errorMessage": "Description of what went wrong"
    }

Existing Bridge Infrastructure (from M1):
  - handlers Map that registers command handlers
  - Message dispatch system with requestId correlation
  - Response format conventions
```

---

## Task Definition

```
[TASK JS_XS_03 – Bridge handler for payload.sign command]

Owner: JS

Goal:
  Register a bridge handler for the payload.sign command.

What to implement:
  - Add handler for "payload.sign" command to existing handlers map
  - Handler extracts dataToSign and privateKey from payload
  - Handler validates payload fields before processing
  - Handler calls signPayload() function (from JS_XS_02)
  - Handler returns standardized response format with requestId correlation

Handler Registration:
  - Register handler in the existing handlers Map
  - Handler key: "payload.sign"
  - Handler signature: async (payload, requestId) => response

Payload Validation:
  - Validate dataToSign is present and is a string
  - Validate privateKey is present and is a string
  - Return error response if validation fails

RequestId Correlation:
  - Accept requestId from the bridge message
  - Include requestId in all response objects (success and error)
  - This enables Flutter to match responses to requests

Success Response Shape:
  {
    "ok": true,
    "requestId": "uuid-string",
    "signature": "base64-encoded-signature"
  }

Error Response Shape:
  {
    "ok": false,
    "requestId": "uuid-string",
    "errorCode": "ERROR_CODE",
    "errorMessage": "Human readable error description"
  }

Error Codes:
  - INVALID_PRIVATE_KEY: Private key format/decode error or missing
  - SIGNING_ERROR: Ed25519 signing operation failed
  - INTERNAL_ERROR: Any other unexpected error

Inputs:
  - payload.dataToSign: string - The data to sign
  - payload.privateKey: string - Base64-encoded private key
  - requestId: string - Correlation ID from Flutter

Outputs:
  - Success: { ok: true, requestId, signature: "base64..." }
  - Error: { ok: false, requestId, errorCode: "...", errorMessage: "..." }

Flow_events:
  - When handler receives message:
      - layer: "JS"
      - event: "QR_JS_BRIDGE_SIGN_RECEIVED"
      - details: { "dataLength": dataToSign.length, "requestId": requestId }
  - On success:
      - layer: "JS"
      - event: "QR_JS_BRIDGE_SIGN_SUCCESS"
      - details: { "requestId": requestId }
  - On error:
      - layer: "JS"
      - event: "QR_JS_BRIDGE_SIGN_ERROR"
      - details: { "errorCode": "...", "error": "...", "requestId": requestId }

Constraints:
  - Must follow existing M1 bridge handler patterns
  - Use consistent error codes
  - Do not modify existing handlers
  - This is an ADDITION to the handlers.ts file
  - Always include requestId in responses for correlation

Deliverable:
  - Addition to: core_lib_js/src/bridge/handlers.ts
```

---

## Output Requirements

1. **File:** `core_lib_js/src/bridge/handlers.ts` (addition to existing file)

2. **Must include:**
   - Handler registration for `payload.sign`
   - Parameter extraction and validation
   - RequestId correlation in all responses
   - Call to `signPayload()` function
   - Proper error code mapping
   - Flow event emissions

3. **Handler structure:**

```typescript
import { signPayload } from '../signing/sign_payload';
import { emitFlowEvent } from '../utils/flow_events';

// Add this handler to the existing handlers map

handlers.set('payload.sign', async (payload: {
  dataToSign?: string;
  privateKey?: string;
}, requestId?: string) => {
  emitFlowEvent({
    layer: 'JS',
    event: 'QR_JS_BRIDGE_SIGN_RECEIVED',
    details: { dataLength: payload.dataToSign?.length ?? 0, requestId },
  });

  try {
    // Validate required fields
    if (!payload.dataToSign || typeof payload.dataToSign !== 'string') {
      return {
        ok: false,
        requestId,
        errorCode: 'SIGNING_ERROR',
        errorMessage: 'Missing or invalid dataToSign',
      };
    }
    if (!payload.privateKey || typeof payload.privateKey !== 'string') {
      return {
        ok: false,
        requestId,
        errorCode: 'INVALID_PRIVATE_KEY',
        errorMessage: 'Missing or invalid privateKey',
      };
    }

    // Call signing function
    const signature = await signPayload(payload.dataToSign, payload.privateKey);

    emitFlowEvent({
      layer: 'JS',
      event: 'QR_JS_BRIDGE_SIGN_SUCCESS',
      details: { requestId },
    });

    return {
      ok: true,
      requestId,
      signature,
    };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);

    // Map error to appropriate error code
    let errorCode = 'INTERNAL_ERROR';
    if (errorMessage.includes('private key') || errorMessage.includes('key')) {
      errorCode = 'INVALID_PRIVATE_KEY';
    } else if (errorMessage.includes('sign')) {
      errorCode = 'SIGNING_ERROR';
    }

    emitFlowEvent({
      layer: 'JS',
      event: 'QR_JS_BRIDGE_SIGN_ERROR',
      details: { errorCode, error: errorMessage, requestId },
    });

    return {
      ok: false,
      requestId,
      errorCode,
      errorMessage,
    };
  }
});
```

---

## Integration with Existing M1 Handlers

The handlers.ts file should now have:

```typescript
// core_lib_js/src/bridge/handlers.ts

import { generateIdentity } from '../identity/generate';
import { restoreIdentityFromMnemonic } from '../identity/restore';
import { signPayload } from '../signing/sign_payload';
import { emitFlowEvent } from '../utils/flow_events';

// Handler registry
const handlers = new Map<string, (payload: any, requestId?: string) => Promise<any>>();

// ============================================
// M1 HANDLERS (existing)
// ============================================

handlers.set('identity.generate', async (payload, requestId) => {
  // ... existing M1 implementation
});

handlers.set('identity.restore', async (payload, requestId) => {
  // ... existing M1 implementation
});

// ============================================
// M2 HANDLERS (new)
// ============================================

handlers.set('payload.sign', async (payload, requestId) => {
  // ... new implementation from this task
});

// ============================================
// DISPATCHER (existing)
// ============================================

export async function handleBridgeMessage(message: {
  cmd: string;
  requestId?: string;
  payload: any;
}): Promise<any> {
  const handler = handlers.get(message.cmd);
  if (!handler) {
    return {
      ok: false,
      requestId: message.requestId,
      errorCode: 'UNKNOWN_COMMAND',
      errorMessage: `Unknown command: ${message.cmd}`,
    };
  }
  return handler(message.payload, message.requestId);
}

export { handlers };
```

---

## Test Case

```typescript
// Test the handler
import { handleBridgeMessage } from './handlers';

async function testSignHandler() {
  const request = {
    cmd: 'payload.sign',
    requestId: 'test-request-123',
    payload: {
      dataToSign: '{"ns":"test","pk":"test","rv":"test","ts":"2025-01-22T00:00:00Z"}',
      privateKey: 'BASE64_PRIVATE_KEY_HERE',
    },
  };

  const response = await handleBridgeMessage(request);

  // Verify requestId correlation
  console.log('RequestId matches:', response.requestId === request.requestId);

  if (response.ok) {
    console.log('Success! Signature:', response.signature);
  } else {
    console.log('Error:', response.errorCode, response.errorMessage);
  }
}
```

---

## Error Code Reference

| Error Code | When to Use |
|------------|-------------|
| `INVALID_PRIVATE_KEY` | Private key missing, wrong format, or decode error |
| `SIGNING_ERROR` | Ed25519 signing operation failed |
| `INTERNAL_ERROR` | Any other unexpected error |

---

## Verification Steps

After implementation, verify the handler is correctly registered:

1. **Bundle rebuild:**
   ```bash
   cd core_lib_js && npm run build
   ```

2. **Grep verification:**
   ```bash
   grep -n "payload.sign" core_lib_js/src/bridge/handlers.ts
   grep -n "payload.sign" core_lib_js/dist/bundle.js
   ```

   Expected output should show the handler registration in both source and built files.

---

## Begin Implementation

Output the code that should be ADDED to the existing handlers.ts file. Show clearly where it integrates with M1 handlers.
