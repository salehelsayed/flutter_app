/**
 * @fileoverview Tests for ML-KEM-768 + AES-256-GCM crypto functions.
 */

import { generateMlKemKeyPair } from '../crypto/keygen_mlkem';
import { encryptMessage } from '../crypto/encrypt_message';
import { decryptMessage } from '../crypto/decrypt_message';
import { webcrypto } from 'node:crypto';

// Polyfill crypto.subtle and crypto.getRandomValues for Node.js test environment
if (typeof globalThis.crypto === 'undefined') {
  (globalThis as any).crypto = webcrypto;
}

describe('JS_CRYPTO_01 - generateMlKemKeyPair', () => {
  test('returns base64 strings of expected lengths', () => {
    const keyPair = generateMlKemKeyPair();

    expect(typeof keyPair.publicKey).toBe('string');
    expect(typeof keyPair.secretKey).toBe('string');

    // ML-KEM-768: publicKey = 1184 bytes -> ~1579 base64 chars
    const pubKeyBytes = Buffer.from(keyPair.publicKey, 'base64');
    expect(pubKeyBytes.length).toBe(1184);

    // ML-KEM-768: secretKey = 2400 bytes -> ~3200 base64 chars
    const secKeyBytes = Buffer.from(keyPair.secretKey, 'base64');
    expect(secKeyBytes.length).toBe(2400);
  });

  test('generates unique key pairs', () => {
    const kp1 = generateMlKemKeyPair();
    const kp2 = generateMlKemKeyPair();

    expect(kp1.publicKey).not.toBe(kp2.publicKey);
    expect(kp1.secretKey).not.toBe(kp2.secretKey);
  });
});

describe('JS_CRYPTO_02 - encrypt/decrypt round-trip', () => {
  test('encrypts and decrypts message correctly', async () => {
    const keyPair = generateMlKemKeyPair();
    const plaintext = 'Hello, post-quantum world!';

    const encrypted = await encryptMessage(keyPair.publicKey, plaintext);

    expect(typeof encrypted.kem).toBe('string');
    expect(typeof encrypted.ciphertext).toBe('string');
    expect(typeof encrypted.nonce).toBe('string');

    // KEM ciphertext should be 1088 bytes
    const kemBytes = Buffer.from(encrypted.kem, 'base64');
    expect(kemBytes.length).toBe(1088);

    // Nonce should be 12 bytes
    const nonceBytes = Buffer.from(encrypted.nonce, 'base64');
    expect(nonceBytes.length).toBe(12);

    const decrypted = await decryptMessage(
      keyPair.secretKey,
      encrypted.kem,
      encrypted.ciphertext,
      encrypted.nonce,
    );

    expect(decrypted).toBe(plaintext);
  });

  test('handles empty plaintext', async () => {
    const keyPair = generateMlKemKeyPair();
    const plaintext = '';

    const encrypted = await encryptMessage(keyPair.publicKey, plaintext);
    const decrypted = await decryptMessage(
      keyPair.secretKey,
      encrypted.kem,
      encrypted.ciphertext,
      encrypted.nonce,
    );

    expect(decrypted).toBe(plaintext);
  });

  test('handles unicode plaintext', async () => {
    const keyPair = generateMlKemKeyPair();
    const plaintext = 'مرحبا بالعالم 🌍 こんにちは';

    const encrypted = await encryptMessage(keyPair.publicKey, plaintext);
    const decrypted = await decryptMessage(
      keyPair.secretKey,
      encrypted.kem,
      encrypted.ciphertext,
      encrypted.nonce,
    );

    expect(decrypted).toBe(plaintext);
  });
});

describe('JS_CRYPTO_03 - decryption failures', () => {
  test('wrong secret key fails to decrypt', async () => {
    const senderKeys = generateMlKemKeyPair();
    const wrongKeys = generateMlKemKeyPair();
    const plaintext = 'Secret message';

    const encrypted = await encryptMessage(senderKeys.publicKey, plaintext);

    await expect(
      decryptMessage(
        wrongKeys.secretKey,
        encrypted.kem,
        encrypted.ciphertext,
        encrypted.nonce,
      ),
    ).rejects.toThrow();
  });

  test('tampered KEM ciphertext fails', async () => {
    const keyPair = generateMlKemKeyPair();
    const plaintext = 'Secret message';

    const encrypted = await encryptMessage(keyPair.publicKey, plaintext);

    // Tamper with KEM ciphertext
    const kemBytes = Buffer.from(encrypted.kem, 'base64');
    kemBytes[0] ^= 0xff;
    const tamperedKem = kemBytes.toString('base64');

    await expect(
      decryptMessage(
        keyPair.secretKey,
        tamperedKem,
        encrypted.ciphertext,
        encrypted.nonce,
      ),
    ).rejects.toThrow();
  });

  test('tampered AES ciphertext fails (GCM auth error)', async () => {
    const keyPair = generateMlKemKeyPair();
    const plaintext = 'Secret message';

    const encrypted = await encryptMessage(keyPair.publicKey, plaintext);

    // Tamper with AES ciphertext
    const aesBytes = Buffer.from(encrypted.ciphertext, 'base64');
    aesBytes[0] ^= 0xff;
    const tamperedCiphertext = aesBytes.toString('base64');

    await expect(
      decryptMessage(
        keyPair.secretKey,
        encrypted.kem,
        tamperedCiphertext,
        encrypted.nonce,
      ),
    ).rejects.toThrow();
  });
});
