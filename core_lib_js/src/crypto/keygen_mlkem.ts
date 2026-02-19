/**
 * @fileoverview ML-KEM-768 key pair generation.
 *
 * Generates a post-quantum Key Encapsulation Mechanism (KEM) key pair
 * using ML-KEM-768 (FIPS 203, NIST security level 3).
 *
 * Key sizes:
 * - Public key: 1184 bytes
 * - Secret key: 2400 bytes
 */

import { ml_kem768 } from '@noble/post-quantum/ml-kem';
import { uint8ArrayToBase64 } from '../utils/base64';
import { emitFlowEvent } from '../utils/flow_events';

/**
 * Generates a new ML-KEM-768 key pair.
 *
 * @returns Object with base64-encoded publicKey and secretKey
 */
export function generateMlKemKeyPair(): { publicKey: string; secretKey: string } {
  emitFlowEvent({
    layer: 'JS',
    event: 'MLKEM_JS_KEYGEN_START',
    details: {},
  });

  try {
    const keyPair = ml_kem768.keygen();

    const publicKey = uint8ArrayToBase64(keyPair.publicKey);
    const secretKey = uint8ArrayToBase64(keyPair.secretKey);

    emitFlowEvent({
      layer: 'JS',
      event: 'MLKEM_JS_KEYGEN_SUCCESS',
      details: { publicKeyLength: publicKey.length },
    });

    return { publicKey, secretKey };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);

    emitFlowEvent({
      layer: 'JS',
      event: 'MLKEM_JS_KEYGEN_ERROR',
      details: { error: errorMessage },
    });

    throw new Error(`ML-KEM keygen failed: ${errorMessage}`);
  }
}
