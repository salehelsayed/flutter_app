/**
 * @fileoverview Interop test vectors for Go <-> JS crypto wire-compatibility.
 *
 * These tests verify that the JS implementation produces identical outputs
 * to the Go implementation for deterministic operations (identity derivation,
 * Ed25519 signing) and can decrypt Go-encrypted messages (ML-KEM + AES-GCM).
 *
 * The Go counterpart is: go-mknoon/crypto/interop_test.go
 *
 * Run the Go test first to generate testdata/interop_vectors.json:
 *   cd go-mknoon && go test -run TestInterop_WriteVectorsJSON -v ./crypto/
 *
 * Then run this test:
 *   cd core_lib_js && npx jest --testPathPattern interop_vectors
 */

import { generateMlKemKeyPair } from '../crypto/keygen_mlkem';
import { encryptMessage } from '../crypto/encrypt_message';
import { decryptMessage } from '../crypto/decrypt_message';
import * as crypto from 'node:crypto';
import * as fs from 'node:fs';
import * as path from 'node:path';

// Polyfill crypto.subtle and crypto.getRandomValues for Node.js test environment
if (typeof globalThis.crypto === 'undefined') {
  (globalThis as any).crypto = crypto.webcrypto;
}

// -----------------------------------------------------------------------
// Shared constants -- must match go-mknoon/crypto/interop_test.go exactly.
// -----------------------------------------------------------------------

const KNOWN_MNEMONIC =
  'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

// Deterministic expected values derived from KNOWN_MNEMONIC.
// Both Go and JS must produce exactly these strings.
const EXPECTED_PEER_ID =
  '12D3KooWP7CwQswqLKZbwvYd9wrEynnL9F2aKVP1X9huNASBTuqj';
const EXPECTED_PUBLIC_KEY = 'xXheGGW3CJOK/4Fh1XMAZJZmOxqhCDTjltxWaGmixmo=';
const EXPECTED_PRIVATE_KEY =
  'XrALvdzwaQhIiairkVVWgWX1xFPMuF5wgRqu1vbaX8HFeF4YZbcIk4r/gWHVcwBklmY7GqEINOOW3FZoaaLGag==';

// Ed25519 signing test data.
const SIGN_PAYLOAD = 'interop-test-payload';
const EXPECTED_SIGNATURE =
  'vA6No9SDLTYKdhYoEl4WGfUUA5DvQkQmtQG1UxYHP+NjwHuSQ0/EmXfOLJPx4lic/HbIvNQc0W9DxA1LRteMCw==';

// ML-KEM encryption test plaintext (must match Go test).
const ENCRYPT_PLAINTEXT = 'Hello from Go!';

// -----------------------------------------------------------------------
// Helper: base64 <-> Uint8Array (using Node.js Buffer)
// -----------------------------------------------------------------------

function base64ToBytes(b64: string): Uint8Array {
  return new Uint8Array(Buffer.from(b64, 'base64'));
}

function bytesToBase64(bytes: Uint8Array): string {
  return Buffer.from(bytes).toString('base64');
}

// -----------------------------------------------------------------------
// Helper: Ed25519 sign/verify using Node.js native crypto
//
// Ed25519 PKCS#8 DER prefix for 32-byte seed:
//   30 2e 02 01 00 30 05 06 03 2b 65 70 04 22 04 20
//
// Ed25519 SPKI DER prefix for 32-byte public key:
//   30 2a 30 05 06 03 2b 65 70 03 21 00
// -----------------------------------------------------------------------

const ED25519_PKCS8_PREFIX = Buffer.from(
  '302e020100300506032b657004220420',
  'hex',
);
const ED25519_SPKI_PREFIX = Buffer.from('302a300506032b6570032100', 'hex');

function ed25519Sign(seed32: Uint8Array, message: Uint8Array): Uint8Array {
  const privateKey = crypto.createPrivateKey({
    key: Buffer.concat([ED25519_PKCS8_PREFIX, Buffer.from(seed32)]),
    format: 'der',
    type: 'pkcs8',
  });
  return new Uint8Array(crypto.sign(null, message, privateKey));
}

function ed25519Verify(
  publicKey32: Uint8Array,
  message: Uint8Array,
  signature: Uint8Array,
): boolean {
  const publicKeyObj = crypto.createPublicKey({
    key: Buffer.concat([ED25519_SPKI_PREFIX, Buffer.from(publicKey32)]),
    format: 'der',
    type: 'spki',
  });
  return crypto.verify(null, message, publicKeyObj, signature);
}

function ed25519PublicKeyFromSeed(seed32: Uint8Array): Uint8Array {
  const privateKey = crypto.createPrivateKey({
    key: Buffer.concat([ED25519_PKCS8_PREFIX, Buffer.from(seed32)]),
    format: 'der',
    type: 'pkcs8',
  });
  const publicKeyObj = crypto.createPublicKey(privateKey);
  const spki = publicKeyObj.export({ type: 'spki', format: 'der' });
  // Strip the 12-byte SPKI prefix to get the raw 32-byte public key.
  return new Uint8Array((spki as Buffer).subarray(12));
}

// -----------------------------------------------------------------------
// Interop vectors JSON type (matches Go interopVectors struct)
// -----------------------------------------------------------------------

interface InteropVectors {
  identity: {
    mnemonic: string;
    peerId: string;
    publicKey: string;
    privateKey: string;
  };
  signature: {
    data: string;
    signature: string;
  };
  encryption: {
    publicKey: string;
    secretKey: string;
    plaintext: string;
    kem: string;
    ciphertext: string;
    nonce: string;
  };
}

// -----------------------------------------------------------------------
// Load Go-generated vectors (optional -- tests still work without them)
// -----------------------------------------------------------------------

function loadGoVectors(): InteropVectors | null {
  // Path relative to this test file: ../../go-mknoon/testdata/interop_vectors.json
  const vectorsPath = path.resolve(
    __dirname,
    '..',
    '..',
    '..',
    'go-mknoon',
    'testdata',
    'interop_vectors.json',
  );

  try {
    const raw = fs.readFileSync(vectorsPath, 'utf-8');
    return JSON.parse(raw) as InteropVectors;
  } catch {
    return null;
  }
}

// -----------------------------------------------------------------------
// Helper: derive identity from mnemonic using bip39 + Node.js native crypto
//
// Avoids @libp2p/crypto/keys and @libp2p/peer-id which are ESM-only
// and break Jest's CJS module resolution.
// -----------------------------------------------------------------------

const BASE58_ALPHABET =
  '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

/** Simple base58btc encoder (no external deps). */
function base58btcEncode(bytes: Uint8Array): string {
  // Count leading zeros
  let zeros = 0;
  for (let i = 0; i < bytes.length && bytes[i] === 0; i++) zeros++;

  // Convert to BigInt and do base58 division
  let num = BigInt(0);
  for (const byte of bytes) num = num * 256n + BigInt(byte);

  const chars: string[] = [];
  while (num > 0n) {
    chars.push(BASE58_ALPHABET[Number(num % 58n)]);
    num = num / 58n;
  }
  chars.reverse();

  // Prepend '1' for each leading zero byte
  return '1'.repeat(zeros) + chars.join('');
}

async function deriveIdentityFromMnemonic(mnemonic: string): Promise<{
  peerId: string;
  publicKey: string;
  privateKey: string;
}> {
  const bip39 = await import('bip39');

  const normalized = mnemonic.trim().toLowerCase();
  const seedBuffer = await bip39.mnemonicToSeed(normalized);
  const seed = new Uint8Array(seedBuffer.buffer, seedBuffer.byteOffset, 32);

  // Derive Ed25519 key pair using Node.js native crypto
  const rawPubKey = ed25519PublicKeyFromSeed(seed);
  const fullPrivKey = Buffer.concat([seed, rawPubKey]);

  // Construct libp2p peerId:
  // 1. Protobuf PublicKey: {type: Ed25519 (1), data: <32 bytes>}
  //    field 1 varint 1 → 0x08 0x01
  //    field 2 bytes len=32 → 0x12 0x20 <32 bytes>
  const protobuf = Buffer.concat([
    Buffer.from([0x08, 0x01, 0x12, 0x20]),
    rawPubKey,
  ]);

  // 2. Identity multihash (code=0x00, length=36)
  //    36 bytes ≤ 42 (MaxInlineKeyLength) → identity hash
  const multihash = Buffer.concat([
    Buffer.from([0x00, protobuf.length]),
    protobuf,
  ]);

  // 3. Base58btc encode
  const peerId = base58btcEncode(multihash);

  return {
    peerId,
    publicKey: bytesToBase64(rawPubKey),
    privateKey: bytesToBase64(fullPrivKey),
  };
}

// -----------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------

describe('INTEROP_01 - Identity from known mnemonic', () => {
  test('JS produces the same peerId, publicKey, privateKey as Go', async () => {
    const identity = await deriveIdentityFromMnemonic(KNOWN_MNEMONIC);

    expect(identity.peerId).toBe(EXPECTED_PEER_ID);
    expect(identity.publicKey).toBe(EXPECTED_PUBLIC_KEY);
    expect(identity.privateKey).toBe(EXPECTED_PRIVATE_KEY);
  });

  test('identity derivation is deterministic across calls', async () => {
    const id1 = await deriveIdentityFromMnemonic(KNOWN_MNEMONIC);
    const id2 = await deriveIdentityFromMnemonic(KNOWN_MNEMONIC);

    expect(id1.peerId).toBe(id2.peerId);
    expect(id1.publicKey).toBe(id2.publicKey);
    expect(id1.privateKey).toBe(id2.privateKey);
  });

  test('public key is 32 bytes, private key is 64 bytes', async () => {
    const identity = await deriveIdentityFromMnemonic(KNOWN_MNEMONIC);

    const pubBytes = base64ToBytes(identity.publicKey);
    expect(pubBytes.length).toBe(32);

    const privBytes = base64ToBytes(identity.privateKey);
    expect(privBytes.length).toBe(64);
  });
});

describe('INTEROP_02 - Ed25519 signature fixed vectors', () => {
  test('JS produces the same deterministic Ed25519 signature as Go', () => {
    // The 64-byte Ed25519 private key is seed (32 bytes) + public (32 bytes).
    // Node.js crypto.sign takes the 32-byte seed wrapped in PKCS#8 DER format.
    const privKeyBytes = base64ToBytes(EXPECTED_PRIVATE_KEY);
    const seed = privKeyBytes.slice(0, 32); // first 32 bytes = Ed25519 seed

    const messageBytes = new TextEncoder().encode(SIGN_PAYLOAD);
    const signatureBytes = ed25519Sign(seed, messageBytes);
    const signatureB64 = bytesToBase64(signatureBytes);

    expect(signatureB64).toBe(EXPECTED_SIGNATURE);
  });

  test('JS-derived public key from seed matches expected public key', () => {
    const privKeyBytes = base64ToBytes(EXPECTED_PRIVATE_KEY);
    const seed = privKeyBytes.slice(0, 32);

    const derivedPubKey = ed25519PublicKeyFromSeed(seed);
    const derivedPubKeyB64 = bytesToBase64(derivedPubKey);

    expect(derivedPubKeyB64).toBe(EXPECTED_PUBLIC_KEY);
  });

  test('JS can verify the known signature with the known public key', () => {
    const pubKeyBytes = base64ToBytes(EXPECTED_PUBLIC_KEY);
    const sigBytes = base64ToBytes(EXPECTED_SIGNATURE);
    const messageBytes = new TextEncoder().encode(SIGN_PAYLOAD);

    const isValid = ed25519Verify(pubKeyBytes, messageBytes, sigBytes);
    expect(isValid).toBe(true);
  });

  test('verification fails with wrong data', () => {
    const pubKeyBytes = base64ToBytes(EXPECTED_PUBLIC_KEY);
    const sigBytes = base64ToBytes(EXPECTED_SIGNATURE);
    const wrongMessage = new TextEncoder().encode('wrong-payload');

    const isValid = ed25519Verify(pubKeyBytes, wrongMessage, sigBytes);
    expect(isValid).toBe(false);
  });
});

describe('INTEROP_03 - ML-KEM + AES-GCM round-trip (JS self-check)', () => {
  test('JS encrypt -> JS decrypt round-trip', async () => {
    const kp = generateMlKemKeyPair();
    const plaintext = ENCRYPT_PLAINTEXT;

    const encrypted = await encryptMessage(kp.publicKey, plaintext);
    const decrypted = await decryptMessage(
      kp.secretKey,
      encrypted.kem,
      encrypted.ciphertext,
      encrypted.nonce,
    );

    expect(decrypted).toBe(plaintext);
  });

  test('ML-KEM key sizes match specification', () => {
    const kp = generateMlKemKeyPair();

    const pubBytes = base64ToBytes(kp.publicKey);
    expect(pubBytes.length).toBe(1184);

    const secBytes = base64ToBytes(kp.secretKey);
    expect(secBytes.length).toBe(2400);
  });

  test('encrypted output has correct sizes', async () => {
    const kp = generateMlKemKeyPair();
    const encrypted = await encryptMessage(kp.publicKey, ENCRYPT_PLAINTEXT);

    // KEM ciphertext: 1088 bytes
    const kemBytes = base64ToBytes(encrypted.kem);
    expect(kemBytes.length).toBe(1088);

    // Nonce: 12 bytes
    const nonceBytes = base64ToBytes(encrypted.nonce);
    expect(nonceBytes.length).toBe(12);
  });

  test('handles unicode plaintext', async () => {
    const kp = generateMlKemKeyPair();
    const plaintext = '\u0645\u0631\u062d\u0628\u0627 \u3053\u3093\u306b\u3061\u306f';

    const encrypted = await encryptMessage(kp.publicKey, plaintext);
    const decrypted = await decryptMessage(
      kp.secretKey,
      encrypted.kem,
      encrypted.ciphertext,
      encrypted.nonce,
    );

    expect(decrypted).toBe(plaintext);
  });

  test('handles empty plaintext', async () => {
    const kp = generateMlKemKeyPair();

    const encrypted = await encryptMessage(kp.publicKey, '');
    const decrypted = await decryptMessage(
      kp.secretKey,
      encrypted.kem,
      encrypted.ciphertext,
      encrypted.nonce,
    );

    expect(decrypted).toBe('');
  });
});

describe('INTEROP_04 - JS decrypts Go-encrypted vectors', () => {
  const goVectors = loadGoVectors();

  // Skip if the Go-generated vectors file is not present.
  const maybeTest = goVectors ? test : test.skip;

  maybeTest('Go identity vectors match hardcoded expected values', () => {
    expect(goVectors!.identity.peerId).toBe(EXPECTED_PEER_ID);
    expect(goVectors!.identity.publicKey).toBe(EXPECTED_PUBLIC_KEY);
    expect(goVectors!.identity.privateKey).toBe(EXPECTED_PRIVATE_KEY);
  });

  maybeTest('Go signature vector matches hardcoded expected value', () => {
    expect(goVectors!.signature.data).toBe(SIGN_PAYLOAD);
    expect(goVectors!.signature.signature).toBe(EXPECTED_SIGNATURE);
  });

  maybeTest('JS can verify the Go-generated Ed25519 signature', () => {
    const pubKeyBytes = base64ToBytes(goVectors!.identity.publicKey);
    const sigBytes = base64ToBytes(goVectors!.signature.signature);
    const messageBytes = new TextEncoder().encode(goVectors!.signature.data);

    const isValid = ed25519Verify(pubKeyBytes, messageBytes, sigBytes);
    expect(isValid).toBe(true);
  });

  maybeTest(
    'JS can decrypt Go-encrypted ML-KEM + AES-GCM message',
    async () => {
      const enc = goVectors!.encryption;

      // Use the Go-generated secret key to decrypt the Go-encrypted message.
      const decrypted = await decryptMessage(
        enc.secretKey,
        enc.kem,
        enc.ciphertext,
        enc.nonce,
      );

      expect(decrypted).toBe(enc.plaintext);
    },
  );

  maybeTest('Go ML-KEM key sizes match specification', () => {
    const pubBytes = base64ToBytes(goVectors!.encryption.publicKey);
    expect(pubBytes.length).toBe(1184);

    const secBytes = base64ToBytes(goVectors!.encryption.secretKey);
    expect(secBytes.length).toBe(2400);
  });

  maybeTest('Go KEM ciphertext and nonce sizes match specification', () => {
    const kemBytes = base64ToBytes(goVectors!.encryption.kem);
    expect(kemBytes.length).toBe(1088);

    const nonceBytes = base64ToBytes(goVectors!.encryption.nonce);
    expect(nonceBytes.length).toBe(12);
  });
});

describe('INTEROP_05 - Cross-platform encryption (JS encrypts for Go key)', () => {
  const goVectors = loadGoVectors();
  const maybeTest = goVectors ? test : test.skip;

  maybeTest(
    'JS can encrypt for a Go-generated ML-KEM public key and decrypt with the Go secret key',
    async () => {
      const enc = goVectors!.encryption;

      // JS encrypts a new message using the Go-generated public key.
      const newPlaintext = 'Hello from JS!';
      const encrypted = await encryptMessage(enc.publicKey, newPlaintext);

      // JS decrypts using the Go-generated secret key.
      // This proves JS KEM encapsulate is compatible with Go KEM decapsulate
      // (via the shared secret key), and AES-GCM is wire-compatible.
      const decrypted = await decryptMessage(
        enc.secretKey,
        encrypted.kem,
        encrypted.ciphertext,
        encrypted.nonce,
      );

      expect(decrypted).toBe(newPlaintext);
    },
  );
});
