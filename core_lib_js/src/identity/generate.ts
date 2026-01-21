/**
 * @fileoverview Identity generation implementation for M1 Identity Initialization.
 *
 * This module provides the generateIdentity() function which creates a new
 * identity with a fresh BIP39 mnemonic, Ed25519 keypair, and libp2p peer ID.
 *
 * @module identity/generate
 */

import * as bip39 from 'bip39';
import { generateKeyPairFromSeed } from '@libp2p/crypto/keys';
import { peerIdFromPrivateKey } from '@libp2p/peer-id';
import { IdentityJson } from '../types/identity';
import { emitFlowEvent } from '../utils/flow_events';

/**
 * Generates a new identity with fresh cryptographic credentials.
 *
 * This function performs the following steps:
 * 1. Generate a 12-word BIP39 mnemonic (128 bits entropy)
 * 2. Derive seed from mnemonic
 * 3. Generate Ed25519 keypair from seed (first 32 bytes)
 * 4. Derive libp2p peer ID from public key
 * 5. Base64 encode the keys
 * 6. Set creation timestamps
 *
 * @returns Promise resolving to a complete IdentityJson object
 * @throws Error if any cryptographic operation fails
 *
 * @example
 * ```typescript
 * const identity = await generateIdentity();
 * console.log(identity.peerId); // "12D3KooW..."
 * console.log(identity.mnemonic12); // "word1 word2 ... word12"
 * ```
 */
export async function generateIdentity(): Promise<IdentityJson> {
  emitFlowEvent({
    layer: 'JS',
    event: 'ID_JS_GENERATE_IDENTITY_START',
    details: {},
  });

  try {
    // 1. Generate 12-word BIP39 mnemonic (128 bits entropy = 12 words)
    const mnemonic = bip39.generateMnemonic(128);

    // 2. Derive seed from mnemonic (returns 64-byte seed)
    const seedBuffer = await bip39.mnemonicToSeed(mnemonic);
    // Convert to Uint8Array for compatibility
    const seed = new Uint8Array(seedBuffer.buffer, seedBuffer.byteOffset, seedBuffer.byteLength);

    // 3. Generate Ed25519 keypair from seed (use first 32 bytes)
    const keyPair = await generateKeyPairFromSeed('Ed25519', seed.slice(0, 32));

    // 4. Derive libp2p peer ID from private key
    const peerId = peerIdFromPrivateKey(keyPair);

    // Get raw key bytes for base64 encoding
    const publicKeyBytes = keyPair.publicKey.raw;
    const privateKeyBytes = keyPair.raw;

    // 5. Encode keys as base64
    const publicKeyBase64 = Buffer.from(publicKeyBytes).toString('base64');
    const privateKeyBase64 = Buffer.from(privateKeyBytes).toString('base64');

    // 6. Set timestamps (same for both on creation)
    const now = new Date().toISOString();

    // 7. Build the complete identity object
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
    const errorMessage = error instanceof Error ? error.message : String(error);

    emitFlowEvent({
      layer: 'JS',
      event: 'ID_JS_GENERATE_IDENTITY_ERROR',
      details: { error: errorMessage },
    });

    throw error;
  }
}
