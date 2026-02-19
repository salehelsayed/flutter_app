/**
 * @fileoverview Message encryption using ML-KEM-768 + AES-256-GCM.
 *
 * Per-message encryption flow:
 * 1. ML-KEM-768 encapsulate with recipient's public key -> shared secret
 * 2. AES-256-GCM encrypt plaintext with shared secret + random nonce
 * 3. Return KEM ciphertext + AES ciphertext + nonce (all base64)
 *
 * Uses @noble/ciphers for AES-GCM (pure JS, no WebCrypto dependency)
 * because Flutter WebView loads from file:// which lacks crypto.subtle.
 */

import { ml_kem768 } from '@noble/post-quantum/ml-kem';
import { gcm } from '@noble/ciphers/aes';
import { randomBytes } from '@noble/ciphers/webcrypto';
import { base64ToUint8Array, uint8ArrayToBase64 } from '../utils/base64';
import { emitFlowEvent } from '../utils/flow_events';

/**
 * Encrypts a plaintext message for a recipient using ML-KEM-768 + AES-256-GCM.
 *
 * @param recipientMlKemPublicKeyBase64 - Base64-encoded ML-KEM-768 public key (1184 bytes)
 * @param plaintext - The message text to encrypt
 * @returns Object with base64-encoded kem ciphertext, aes ciphertext, and nonce
 */
export async function encryptMessage(
  recipientMlKemPublicKeyBase64: string,
  plaintext: string
): Promise<{ kem: string; ciphertext: string; nonce: string }> {
  emitFlowEvent({
    layer: 'JS',
    event: 'MLKEM_JS_ENCRYPT_START',
    details: { plaintextLength: plaintext.length },
  });

  try {
    // 1. Decode recipient's ML-KEM public key
    const recipientPublicKey = base64ToUint8Array(recipientMlKemPublicKeyBase64);

    // 2. KEM encapsulate -> { cipherText, sharedSecret }
    const { cipherText: kemCiphertext, sharedSecret } = ml_kem768.encapsulate(recipientPublicKey);

    // 3. Generate random 12-byte nonce for AES-GCM
    const nonce = randomBytes(12);

    // 4. Encrypt plaintext with AES-256-GCM using pure JS (@noble/ciphers)
    const plaintextBytes = new TextEncoder().encode(plaintext);
    const aes = gcm(sharedSecret, nonce);
    const aesCiphertext = aes.encrypt(plaintextBytes);

    emitFlowEvent({
      layer: 'JS',
      event: 'MLKEM_JS_ENCRYPT_SUCCESS',
      details: { kemLength: kemCiphertext.length, aesLength: aesCiphertext.length },
    });

    return {
      kem: uint8ArrayToBase64(kemCiphertext),
      ciphertext: uint8ArrayToBase64(aesCiphertext),
      nonce: uint8ArrayToBase64(nonce),
    };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);

    emitFlowEvent({
      layer: 'JS',
      event: 'MLKEM_JS_ENCRYPT_ERROR',
      details: { error: errorMessage },
    });

    throw new Error(`encryptMessage failed: ${errorMessage}`);
  }
}
