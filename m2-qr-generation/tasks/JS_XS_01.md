# Task Prompt: JS_XS_01 - QRPayloadJson Type Definition

## Instructions for AI Agent

You are implementing a specific task for a Flutter/JS application. Follow the task specification exactly. Output complete, working code that can be directly used.

---

## Global Context

```
Milestone: M2 – QR Code Generation

QR Payload Structure:
  Unsigned (before signing):
    {
      "pk": "base64-string",      // public key
      "ns": "string",             // namespace (peerID)
      "rv": "multiaddr-string",   // rendezvous address
      "ts": "ISO-8601-UTC"        // timestamp
    }
  
  Signed (after signing):
    {
      "pk": "base64-string",
      "ns": "string",
      "rv": "multiaddr-string",
      "ts": "ISO-8601-UTC",
      "sig": "base64-string"      // Ed25519 signature
    }

Signing Process:
  1. Build unsigned payload object
  2. Serialize to canonical JSON (keys sorted alphabetically)
  3. Sign UTF-8 bytes with Ed25519 private key
  4. Base64-encode signature
  5. Add sig field to create signed payload
```

---

## Task Definition

```
[TASK JS_XS_01 – QRPayloadJson type definitions]

Owner: JS

Goal:
  Define TypeScript interfaces for QR payload data structures.

Prerequisites:
  - None (this is a foundational type definition task)

What to implement:
  - interface UnsignedQRPayload {
      pk: string;   // public key (base64)
      ns: string;   // namespace (peerID)
      rv: string;   // rendezvous address (multiaddr)
      ts: string;   // ISO-8601 UTC timestamp
    }

  - interface SignedQRPayload extends UnsignedQRPayload {
      sig: string;  // Ed25519 signature (base64)
    }

Inputs:
  - None (type definitions only)

Outputs:
  - TypeScript interfaces exported for use by other modules

Flow_events:
  - None (type definitions only)

Constraints:
  - Pure type definitions, no runtime code
  - All fields are required (no optional fields)
  - Use string type for all fields (encoding happens elsewhere)

Deliverable:
  - File: core_lib_js/src/types/qr_payload.ts
```

---

## Output Requirements

1. **File:** `core_lib_js/src/types/qr_payload.ts`

2. **Must include:**
   - `UnsignedQRPayload` interface with pk, ns, rv, ts
   - `SignedQRPayload` interface extending UnsignedQRPayload with sig
   - JSDoc comments explaining each field
   - Export statements for both interfaces

3. **Verification command:**
   ```bash
   npx tsc -p tsconfig.json --noEmit
   ```

4. **Example usage after implementation:**

```typescript
import { UnsignedQRPayload, SignedQRPayload } from './qr_payload';

// Creating an unsigned payload
const unsigned: UnsignedQRPayload = {
  pk: 'SGVsbG8gV29ybGQ=',
  ns: '12D3KooWAbcdef...',
  rv: '/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g',
  ts: '2025-01-22T12:00:00.000Z',
};

// Creating a signed payload
const signed: SignedQRPayload = {
  ...unsigned,
  sig: 'U2lnbmF0dXJlQmFzZTY0...',
};
```

---

## Begin Implementation

Output the complete TypeScript file with both interfaces and proper documentation.
