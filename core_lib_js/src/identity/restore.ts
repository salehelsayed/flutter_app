/**
 * @fileoverview Identity restoration implementation for M1 Identity Initialization.
 *
 * This module provides the restoreIdentityFromMnemonic() function which restores
 * an identity from an existing BIP39 mnemonic, deterministically regenerating
 * the Ed25519 keypair and libp2p peer ID.
 *
 * @module identity/restore
 */

import * as bip39 from 'bip39';
import { generateKeyPairFromSeed } from '@libp2p/crypto/keys';
import { peerIdFromPrivateKey } from '@libp2p/peer-id';
import { IdentityJson } from '../types/identity';
import { emitFlowEvent } from '../utils/flow_events';
import { uint8ArrayToBase64 } from '../utils/base64';
import { generateMlKemKeyPair } from '../crypto/keygen_mlkem';

/**
 * Custom error class for identity restoration errors.
 */
export class IdentityError extends Error {
  type: string;

  constructor(message: string, type: string) {
    super(message);
    this.type = type;
    this.name = 'IdentityError';
  }
}

/**
 * Restores an identity from a 12-word BIP39 mnemonic phrase.
 *
 * This function deterministically generates the same keypair and peerId
 * from the same mnemonic every time.
 *
 * @param mnemonic12 - A 12-word BIP39 mnemonic phrase
 * @returns Promise<IdentityJson> - The restored identity
 * @throws IdentityError with type="INVALID_MNEMONIC" for validation failures
 *
 * @example
 * ```typescript
 * const identity = await restoreIdentityFromMnemonic("word1 word2 ... word12");
 * console.log(identity.peerId); // "12D3KooW..."
 * ```
 */
export async function restoreIdentityFromMnemonic(mnemonic12: string): Promise<IdentityJson> {
  emitFlowEvent({
    layer: 'JS',
    event: 'ID_JS_RESTORE_IDENTITY_START',
    details: { mnemonicLength: mnemonic12.length },
  });

  try {
    // Normalize and split the mnemonic
    const normalizedMnemonic = mnemonic12.trim().toLowerCase();
    const words = normalizedMnemonic.split(/\s+/);

    // Step 1: Validate word count == 12
    if (words.length !== 12) {
      emitFlowEvent({
        layer: 'JS',
        event: 'ID_JS_RESTORE_IDENTITY_INVALID_WORDCOUNT',
        details: { expected: 12, actual: words.length },
      });
      throw new IdentityError(
        `Invalid mnemonic: expected 12 words, got ${words.length}`,
        'INVALID_MNEMONIC'
      );
    }

    // Step 2: Validate BIP39 checksum
    const isValid = bip39.validateMnemonic(normalizedMnemonic);
    if (!isValid) {
      emitFlowEvent({
        layer: 'JS',
        event: 'ID_JS_RESTORE_IDENTITY_INVALID_MNEMONIC',
        details: { reason: 'Invalid BIP39 checksum or words' },
      });
      throw new IdentityError(
        'Invalid mnemonic: BIP39 checksum validation failed',
        'INVALID_MNEMONIC'
      );
    }

    // Step 3: Derive seed from mnemonic (returns 64-byte seed)
    const seedBuffer = await bip39.mnemonicToSeed(normalizedMnemonic);
    // Convert to Uint8Array for compatibility
    const seed = new Uint8Array(seedBuffer.buffer, seedBuffer.byteOffset, seedBuffer.byteLength);

    // Step 4: Generate Ed25519 keypair from seed (use first 32 bytes)
    const keyPair = await generateKeyPairFromSeed('Ed25519', seed.slice(0, 32));

    // Step 5: Derive libp2p peer ID from private key
    const peerId = peerIdFromPrivateKey(keyPair);

    // Get raw key bytes for base64 encoding
    const publicKeyBytes = keyPair.publicKey.raw;
    const privateKeyBytes = keyPair.raw;

    // Step 6: Encode keys as base64 (browser-compatible)
    const publicKeyBase64 = uint8ArrayToBase64(publicKeyBytes);
    const privateKeyBase64 = uint8ArrayToBase64(privateKeyBytes);

    // Step 7: Set timestamps (same for both on restoration)
    const now = new Date().toISOString();

    // Step 8: Generate ML-KEM-768 keypair (random, not derived from mnemonic)
    const mlKemKeys = generateMlKemKeyPair();

    // Step 9: Build the complete identity object
    const identity: IdentityJson = {
      peerId: peerId.toString(),
      publicKey: publicKeyBase64,
      privateKey: privateKeyBase64,
      mnemonic12: normalizedMnemonic,
      mlKemPublicKey: mlKemKeys.publicKey,
      mlKemSecretKey: mlKemKeys.secretKey,
      createdAt: now,
      updatedAt: now,
    };

    emitFlowEvent({
      layer: 'JS',
      event: 'ID_JS_RESTORE_IDENTITY_SUCCESS',
      details: { peerId: identity.peerId },
    });

    return identity;
  } catch (error) {
    // Re-throw IdentityError as-is
    if (error instanceof IdentityError) {
      throw error;
    }

    const errorMessage = error instanceof Error ? error.message : String(error);

    emitFlowEvent({
      layer: 'JS',
      event: 'ID_JS_RESTORE_IDENTITY_ERROR',
      details: { error: errorMessage },
    });

    throw error;
  }
}
