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

    // 2. Extract the 32-byte seed if key is 64 bytes (seed + pubkey)
    const seed = privateKeyBytes.length === 64
      ? privateKeyBytes.slice(0, 32)
      : privateKeyBytes;

    // 3. Convert data to UTF-8 bytes
    const messageBytes = new TextEncoder().encode(dataToSign);

    // 4. Sign the message with Ed25519
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
    throw error;
  }
}
