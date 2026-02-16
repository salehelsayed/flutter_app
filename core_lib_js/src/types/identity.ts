/**
 * @fileoverview Canonical identity type definition for M1 Identity Initialization.
 *
 * This file defines the IdentityJson interface which serves as the single source
 * of truth for identity data shape across Flutter and JS layers. All identity
 * data exchanged between layers must conform to this structure.
 *
 * @module types/identity
 */

/**
 * Canonical identity data structure shared between Flutter and JS.
 * This is the single source of truth for identity data shape.
 *
 * Used by:
 * - generateIdentity() as return type
 * - restoreIdentityFromMnemonic() as return type
 * - Bridge responses to Flutter
 */
export interface IdentityJson {
  /**
   * libp2p peer ID in text form.
   * Derived from the public key using libp2p's peer-id library.
   * @example "12D3KooWA1b2C3d4E5f6..."
   */
  peerId: string;

  /**
   * Base64-encoded Ed25519 public key (32 bytes when decoded).
   * Used for identity verification and peer-to-peer authentication.
   * @example "SGVsbG8gV29ybGQ..."
   */
  publicKey: string;

  /**
   * Base64-encoded Ed25519 private key (64 bytes when decoded).
   * SENSITIVE: Must be stored securely and never transmitted.
   * @example "U2VjcmV0S2V5..."
   */
  privateKey: string;

  /**
   * 12 BIP39 English words separated by single spaces.
   * Used for identity backup and restoration.
   * SENSITIVE: Must be stored securely and protected.
   * @example "abandon ability able about above absent absorb abstract absurd abuse access accident"
   */
  mnemonic12: string;

  /**
   * Base64-encoded ML-KEM-768 public key (1184 bytes when decoded).
   * Used for post-quantum message encryption key exchange.
   * Optional for backward compatibility with older identities.
   */
  mlKemPublicKey?: string;

  /**
   * Base64-encoded ML-KEM-768 secret key (2400 bytes when decoded).
   * SENSITIVE: Used for decrypting incoming messages.
   * Optional for backward compatibility with older identities.
   */
  mlKemSecretKey?: string;

  /**
   * ISO-8601 UTC timestamp of identity creation.
   * Set once when the identity is first generated or restored.
   * @example "2025-11-28T12:34:56.000Z"
   */
  createdAt: string;

  /**
   * ISO-8601 UTC timestamp of last update.
   * Updated whenever the identity record is modified.
   * @example "2025-11-28T12:34:56.000Z"
   */
  updatedAt: string;
}

/**
 * Type guard to validate an object conforms to IdentityJson.
 * Performs basic structural validation only - does not validate:
 * - Base64 encoding correctness
 * - Mnemonic word validity
 * - Timestamp format
 * - Key sizes
 *
 * @param obj - The object to validate
 * @returns True if the object has all required IdentityJson fields as strings
 *
 * @example
 * ```typescript
 * const data = JSON.parse(response);
 * if (isValidIdentityJson(data)) {
 *   // TypeScript knows data is IdentityJson here
 *   console.log(data.peerId);
 * }
 * ```
 */
export function isValidIdentityJson(obj: unknown): obj is IdentityJson {
  if (typeof obj !== 'object' || obj === null) {
    return false;
  }

  const candidate = obj as Record<string, unknown>;

  return (
    typeof candidate.peerId === 'string' &&
    candidate.peerId.length > 0 &&
    typeof candidate.publicKey === 'string' &&
    candidate.publicKey.length > 0 &&
    typeof candidate.privateKey === 'string' &&
    candidate.privateKey.length > 0 &&
    typeof candidate.mnemonic12 === 'string' &&
    candidate.mnemonic12.length > 0 &&
    typeof candidate.createdAt === 'string' &&
    candidate.createdAt.length > 0 &&
    typeof candidate.updatedAt === 'string' &&
    candidate.updatedAt.length > 0
  );
}

/**
 * List of all required fields in IdentityJson.
 * Useful for validation error messages.
 */
export const IDENTITY_JSON_FIELDS = [
  'peerId',
  'publicKey',
  'privateKey',
  'mnemonic12',
  'mlKemPublicKey',
  'mlKemSecretKey',
  'createdAt',
  'updatedAt',
] as const;

/**
 * Type representing the keys of IdentityJson.
 */
export type IdentityJsonKey = (typeof IDENTITY_JSON_FIELDS)[number];
