# Task Prompt: JS_XS_01 - IdentityJson Type Definition

## Instructions for AI Agent

You are implementing a specific task for a Flutter/JS application. Follow the task specification exactly. Output complete, working code that can be directly used.

---

## Global Context

```
Milestone: M1 – Identity Initialization (First Run)

Canonical IdentityJson (shared contract):
  {
    "peerId": "string",              // libp2p peer ID (text form)
    "publicKey": "base64-string",    // base64-encoded public key bytes
    "privateKey": "base64-string",   // base64-encoded private key bytes
    "mnemonic12": "word1 ... word12",// 12 BIP39 words separated by single spaces
    "createdAt": "ISO-8601-UTC",     // e.g. "2025-11-28T12:34:56.000Z"
    "updatedAt": "ISO-8601-UTC"
  }

This type is used:
  - By generateIdentity() as return type
  - By restoreIdentityFromMnemonic() as return type
  - In bridge responses to Flutter
```

---

## Task Definition

```
[TASK JS_XS_01 – Define IdentityJson type]

Owner: JS

Goal:
  Create a TypeScript type definition that matches IdentityJson from the global context.

What to implement:
  - TypeScript interface:
      export interface IdentityJson {
        peerId: string;
        publicKey: string;
        privateKey: string;
        mnemonic12: string;
        createdAt: string;
        updatedAt: string;
      }
  
  - Optional: A validation function to check if an object conforms to IdentityJson

Inputs:
  - None at runtime; this is type-level only

Outputs:
  - Exported interface IdentityJson
  - Optional: isValidIdentityJson(obj) validator function
  - No runtime side-effects

Flow_events:
  - None (types only, no runtime behavior)

Constraints:
  - No libp2p or crypto logic here; just the type definition
  - Keep it simple and well-documented

Deliverable:
  - One TypeScript file exporting IdentityJson (and optional validator)
```

---

## Output Requirements

1. **File:** `core_lib_js/src/types/identity.ts`

2. **Must include:**
   - Exported `IdentityJson` interface
   - JSDoc comments for each field
   - Optional: Type guard function `isValidIdentityJson()`

3. **Interface definition:**
```typescript
/**
 * Canonical identity data structure shared between Flutter and JS.
 * This is the single source of truth for identity data shape.
 */
export interface IdentityJson {
  /** libp2p peer ID in text form (e.g., "12D3KooW...") */
  peerId: string;
  
  /** Base64-encoded Ed25519 public key (32 bytes) */
  publicKey: string;
  
  /** Base64-encoded Ed25519 private key (64 bytes) */
  privateKey: string;
  
  /** 12 BIP39 English words separated by single spaces */
  mnemonic12: string;
  
  /** ISO-8601 UTC timestamp of identity creation */
  createdAt: string;
  
  /** ISO-8601 UTC timestamp of last update */
  updatedAt: string;
}
```

4. **Optional validator:**
```typescript
/**
 * Type guard to validate an object conforms to IdentityJson.
 * Performs basic structural validation only.
 */
export function isValidIdentityJson(obj: unknown): obj is IdentityJson {
  if (typeof obj !== 'object' || obj === null) return false;
  
  const candidate = obj as Record<string, unknown>;
  
  return (
    typeof candidate.peerId === 'string' &&
    typeof candidate.publicKey === 'string' &&
    typeof candidate.privateKey === 'string' &&
    typeof candidate.mnemonic12 === 'string' &&
    typeof candidate.createdAt === 'string' &&
    typeof candidate.updatedAt === 'string'
  );
}
```

---

## Begin Implementation

Implement the complete type definition file now. Output the full code for `identity.ts`.
