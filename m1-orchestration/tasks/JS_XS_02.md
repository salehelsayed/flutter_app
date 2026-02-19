# Task Prompt: JS_XS_02 - generateIdentity() Implementation

## Instructions for AI Agent

You are implementing a specific task for a Flutter/JS application. Follow the task specification exactly. Output complete, working code that can be directly used.

---

## Global Context

```
Milestone: M1 – Identity Initialization (First Run)

IdentityJson structure (from JS_XS_01):
  {
    peerId: string,
    publicKey: string,      // base64
    privateKey: string,     // base64
    mnemonic12: string,     // 12 space-separated words
    createdAt: string,      // ISO-8601-UTC
    updatedAt: string       // ISO-8601-UTC
  }

Tech stack for crypto:
  - @libp2p/crypto or similar for Ed25519 keypair generation
  - @libp2p/peer-id for PeerId derivation
  - bip39 for mnemonic generation
```

---

## Task Definition

```
[TASK JS_XS_02 – Implement generateIdentity()]

Owner: JS

Goal:
  Implement generateIdentity() that returns a new IdentityJson.

What to implement:
  - Function signature:
      export async function generateIdentity(): Promise<IdentityJson>
  
  - Inside:
      1. Generate a 12-word BIP39 mnemonic
      2. Derive seed from mnemonic
      3. Generate Ed25519 keypair from seed
      4. Derive peerId from public key
      5. Encode keys as base64
      6. Set createdAt and updatedAt to current UTC time
      7. Return complete IdentityJson

Inputs:
  - None (generates everything fresh)

Outputs:
  - Promise<IdentityJson> with:
      - All fields non-empty
      - Keys properly base64-encoded
      - Timestamps in ISO-8601-UTC format
  - No persistence side-effects

Flow_events:
  - At function start:
      - layer: "JS"
      - event: "ID_JS_GENERATE_IDENTITY_START"
      - details: { }
  - On successful generation:
      - layer: "JS"
      - event: "ID_JS_GENERATE_IDENTITY_SUCCESS"
      - details: { "peerId": identity.peerId }
  - On error:
      - layer: "JS"
      - event: "ID_JS_GENERATE_IDENTITY_ERROR"
      - details: { "error": "<error_message>" }

Constraints:
  - No DB access here
  - Use IdentityJson type from JS_XS_01
  - Handle errors gracefully

Deliverable:
  - TypeScript implementation of generateIdentity()
```

---

## Output Requirements

1. **File:** `core_lib_js/src/identity/generate.ts`

2. **Must include:**
   - Async function `generateIdentity()`
   - All crypto operations (mnemonic, keypair, peerId)
   - Base64 encoding for keys
   - Flow event emissions
   - Error handling

3. **Implementation outline:**
```typescript
import * as bip39 from 'bip39';
// Import your libp2p crypto libraries
import { IdentityJson } from '../types/identity';
import { emitFlowEvent } from '../utils/flow_events';

export async function generateIdentity(): Promise<IdentityJson> {
  emitFlowEvent({
    layer: 'JS',
    event: 'ID_JS_GENERATE_IDENTITY_START',
    details: {},
  });

  try {
    // 1. Generate mnemonic (12 words = 128 bits entropy)
    const mnemonic = bip39.generateMnemonic(128);
    
    // 2. Derive seed from mnemonic
    const seed = await bip39.mnemonicToSeed(mnemonic);
    
    // 3. Generate Ed25519 keypair
    // Use first 32 bytes of seed for Ed25519
    const keyPair = await generateKeyPairFromSeed(seed.slice(0, 32));
    
    // 4. Derive peerId from public key
    const peerId = await derivePeerId(keyPair.publicKey);
    
    // 5. Encode as base64
    const publicKeyBase64 = Buffer.from(keyPair.publicKey).toString('base64');
    const privateKeyBase64 = Buffer.from(keyPair.privateKey).toString('base64');
    
    // 6. Set timestamps
    const now = new Date().toISOString();
    
    // 7. Build result
    const identity: IdentityJson = {
      peerId: peerId.toString(),
      publicKey: publicKeyBase64,
      privateKey: privateKeyBase64,
      mnemonic12: mnemonic,
      createdAt: now,
      updatedAt: now,
    };

    emitFlowEvent({
      layer: 'JS',
      event: 'ID_JS_GENERATE_IDENTITY_SUCCESS',
      details: { peerId: identity.peerId },
    });

    return identity;
  } catch (error) {
    emitFlowEvent({
      layer: 'JS',
      event: 'ID_JS_GENERATE_IDENTITY_ERROR',
      details: { error: String(error) },
    });
    throw error;
  }
}
```

4. **Crypto library options:**
   - Use `@libp2p/crypto` for keypair generation
   - Use `@libp2p/peer-id` for PeerId
   - Or use `@noble/ed25519` for pure Ed25519
   - Adapt based on your existing dependencies

---

## Flow Event Helper

Create or use existing:

```typescript
// core_lib_js/src/utils/flow_events.ts
export function emitFlowEvent({
  layer,
  event,
  details,
}: {
  layer: 'JS';
  event: string;
  details: Record<string, unknown>;
}) {
  const payload = {
    ts: new Date().toISOString(),
    milestone: 'M1_IDENTITY_INIT',
    layer,
    event,
    details,
  };
  console.log('[FLOW]', JSON.stringify(payload));
}
```

---

## Begin Implementation

Implement the complete function now. Output the full code for `generate.ts`. Include necessary imports and adapt crypto library usage to your project's dependencies.
