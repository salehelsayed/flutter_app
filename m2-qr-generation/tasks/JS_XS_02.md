# Task Prompt: JS_XS_02 - signPayload() Implementation

## Instructions for AI Agent

You are implementing a specific task for a Flutter/JS application. Follow the task specification exactly. Output complete, working code that can be directly used.

---

## Global Context

```
Milestone: M2 – QR Code Generation

Signing Requirements:
  - Algorithm: Ed25519
  - Input: UTF-8 bytes of canonical JSON string
  - Output: Base64-encoded signature
  - Private key format: Base64-encoded Ed25519 private key (64 bytes)

Crypto Library Options:
  - @noble/ed25519 (recommended)
  - @libp2p/crypto
  - tweetnacl

Flow Events:
  - Events should be emitted for observability
  - Format: QR_{LAYER}_{ACTION}_{RESULT}
```

---

## Task Definition

```
[TASK JS_XS_02 – Implement signPayload()]

Owner: JS

Goal:
  Implement a function that signs data using Ed25519.

What to implement:
  - Function signature:
      export async function signPayload(
        dataToSign: string,
        privateKeyBase64: string
      ): Promise<string>
  
  - Inside:
      1. Emit flow event: start
      2. Decode private key from base64
      3. Convert dataToSign string to UTF-8 bytes
      4. Sign the bytes with Ed25519
      5. Encode signature as base64
      6. Emit flow event: success
      7. Return base64 signature

Inputs:
  - dataToSign: string - The canonical JSON string to sign
  - privateKeyBase64: string - Base64-encoded Ed25519 private key

Outputs:
  - Promise<string> - Base64-encoded signature
  - Throws on error (invalid key, signing failure)

Flow_events:
  - At function start:
      - layer: "JS"
      - event: "QR_JS_SIGN_PAYLOAD_START"
      - details: { "dataLength": dataToSign.length }
  - On success:
      - layer: "JS"
      - event: "QR_JS_SIGN_PAYLOAD_SUCCESS"
      - details: { "signatureLength": signature.length }
  - On error:
      - layer: "JS"
      - event: "QR_JS_SIGN_PAYLOAD_ERROR"
      - details: { "error": "<error_message>" }

Constraints:
  - Use Ed25519 algorithm only
  - Private key is 64 bytes (seed + public key combined) or 32 bytes (seed only)
  - Handle both key formats if possible
  - No persistence or side effects beyond flow events

Deliverable:
  - File: core_lib_js/src/signing/sign_payload.ts
```

---

## Output Requirements

1. **File:** `core_lib_js/src/signing/sign_payload.ts`

2. **Must include:**
   - Async function `signPayload()`
   - Proper base64 decode/encode
   - Ed25519 signing operation
   - Flow event emissions
   - Error handling with rethrow

3. **Implementation outline:**

```typescript
import * as ed from '@noble/ed25519';
import { emitFlowEvent } from '../utils/flow_events';

/**
 * Signs data using Ed25519 and returns base64-encoded signature.
 * 
 * @param dataToSign - The string data to sign (will be converted to UTF-8 bytes)
 * @param privateKeyBase64 - Base64-encoded Ed25519 private key
 * @returns Base64-encoded signature
 * @throws Error if signing fails
 */
export async function signPayload(
  dataToSign: string,
  privateKeyBase64: string
): Promise<string> {
  emitFlowEvent({
    layer: 'JS',
    event: 'QR_JS_SIGN_PAYLOAD_START',
    details: { dataLength: dataToSign.length },
  });

  try {
    // 1. Decode private key from base64
    const privateKeyBytes = Buffer.from(privateKeyBase64, 'base64');
    
    // 2. Extract the 32-byte seed/secret if key is 64 bytes
    // Ed25519 private keys can be 32 bytes (seed) or 64 bytes (seed + pubkey)
    const seed = privateKeyBytes.length === 64 
      ? privateKeyBytes.slice(0, 32) 
      : privateKeyBytes;
    
    // 3. Convert data to UTF-8 bytes
    const messageBytes = new TextEncoder().encode(dataToSign);
    
    // 4. Sign the message
    const signature = await ed.signAsync(messageBytes, seed);
    
    // 5. Encode signature as base64
    const signatureBase64 = Buffer.from(signature).toString('base64');
    
    emitFlowEvent({
      layer: 'JS',
      event: 'QR_JS_SIGN_PAYLOAD_SUCCESS',
      details: { signatureLength: signatureBase64.length },
    });

    return signatureBase64;
  } catch (error) {
    emitFlowEvent({
      layer: 'JS',
      event: 'QR_JS_SIGN_PAYLOAD_ERROR',
      details: { error: String(error) },
    });
    throw new Error(`signPayload failed: ${error instanceof Error ? error.message : String(error)}`);
  }
}
```

4. **Crypto library notes:**

If using `@noble/ed25519`:
```bash
npm install @noble/ed25519
```

If using `tweetnacl`:
```typescript
import nacl from 'tweetnacl';
const signature = nacl.sign.detached(messageBytes, privateKeyBytes);
```

---

## Flow Event Helper

Assume this helper exists (or create it):

```typescript
// core_lib_js/src/utils/flow_events.ts
export function emitFlowEvent({
  layer,
  event,
  details,
  milestone,
}: {
  layer: 'JS';
  event: string;
  details: Record<string, unknown>;
  milestone?: string;
}) {
  const payload = {
    ts: new Date().toISOString(),
    milestone: milestone ?? 'M1_IDENTITY_INIT',
    layer,
    event,
    details,
  };
  console.log('[FLOW]', JSON.stringify(payload));
}
```

---

## Test Case

```typescript
// Test with a known keypair
import { signPayload } from './sign_payload';

async function test() {
  // Generate a test keypair (in real usage, this comes from identity)
  const testPrivateKey = 'BASE64_ENCODED_PRIVATE_KEY_HERE';
  const testData = '{"ns":"12D3KooW...","pk":"...","rv":"/dns4/...","ts":"2025-01-22T00:00:00Z"}';
  
  const signature = await signPayload(testData, testPrivateKey);
  console.log('Signature:', signature);
  // Should output a base64 string ~88 characters long
}
```

---

## Begin Implementation

Implement the complete function now. Output the full code for `sign_payload.ts`. Choose the most appropriate crypto library for your project.
