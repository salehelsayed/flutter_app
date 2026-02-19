/**
 * @fileoverview Message decryption using ML-KEM-768 + AES-256-GCM.
 *
 * Per-message decryption flow:
 * 1. ML-KEM-768 decapsulate with own secret key -> shared secret
 * 2. AES-256-GCM decrypt with shared secret + nonce
 * 3. Return plaintext string
 *
 * Uses @noble/ciphers for AES-GCM (pure JS, no WebCrypto dependency)
 * because Flutter WebView loads from file:// which lacks crypto.subtle.
 */

import { ml_kem768 } from '@noble/post-quantum/ml-kem';
import { gcm } from '@noble/ciphers/aes';
import { base64ToUint8Array } from '../utils/base64';
import { emitFlowEvent } from '../utils/flow_events';

/**
 * Decrypts a message using ML-KEM-768 + AES-256-GCM.
 *
 * @param ownMlKemSecretKeyBase64 - Base64-encoded ML-KEM-768 secret key (2400 bytes)
 * @param kemCiphertextBase64 - Base64-encoded KEM ciphertext (1088 bytes)
 * @param aesCiphertextBase64 - Base64-encoded AES-GCM ciphertext
 * @param nonceBase64 - Base64-encoded 12-byte nonce
 * @returns The decrypted plaintext string
 */
export async function decryptMessage(
  ownMlKemSecretKeyBase64: string,
  kemCiphertextBase64: string,
  aesCiphertextBase64: string,
  nonceBase64: string
): Promise<string> {
  emitFlowEvent({
    layer: 'JS',
    event: 'MLKEM_JS_DECRYPT_START',
    details: {},
  });

  try {
    // 1. Decode all inputs from base64
    const ownSecretKey = base64ToUint8Array(ownMlKemSecretKeyBase64);
    const kemCiphertext = base64ToUint8Array(kemCiphertextBase64);
    const aesCiphertext = base64ToUint8Array(aesCiphertextBase64);
    const nonce = base64ToUint8Array(nonceBase64);

    // 2. KEM decapsulate -> sharedSecret
    const sharedSecret = ml_kem768.decapsulate(kemCiphertext, ownSecretKey);

    // 3. Decrypt AES ciphertext with pure JS (@noble/ciphers)
    const aes = gcm(sharedSecret, nonce);
    const plaintextBytes = aes.decrypt(aesCiphertext);

    const plaintext = new TextDecoder().decode(plaintextBytes);

    emitFlowEvent({
      layer: 'JS',
      event: 'MLKEM_JS_DECRYPT_SUCCESS',
      details: { plaintextLength: plaintext.length },
    });

    return plaintext;
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);

    emitFlowEvent({
      layer: 'JS',
      event: 'MLKEM_JS_DECRYPT_ERROR',
      details: { error: errorMessage },
    });

    throw new Error(`decryptMessage failed: ${errorMessage}`);
  }
}
