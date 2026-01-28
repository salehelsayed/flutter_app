/**
 * QR Payload Type Definitions for M2 - QR Code Generation
 * 
 * These types define the structure of QR code payloads used for
 * identity sharing and P2P connection establishment.
 */

/**
 * Unsigned QR payload structure (before signing)
 * This represents the data that will be signed with the user's Ed25519 private key
 */
export interface UnsignedQRPayload {
  /**
   * User's Ed25519 public key (base64-encoded)
   * Example: "SGVsbG8gV29ybGQ..."
   */
  pk: string;

  /**
   * Namespace identifier (same as peerID)
   * Example: "12D3KooWA1b2C3d4E5f6..."
   */
  ns: string;

  /**
   * Rendezvous point multiaddr for P2P connection
   * Example: "/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g"
   */
  rv: string;

  /**
   * ISO-8601 UTC timestamp when QR was generated
   * Example: "2025-01-22T12:34:56.000Z"
   */
  ts: string;
}

/**
 * Signed QR payload structure (after signing)
 * This extends the unsigned payload with an Ed25519 signature
 */
export interface SignedQRPayload extends UnsignedQRPayload {
  /**
   * Ed25519 signature of the unsigned payload (base64-encoded)
   * The signature is computed over the canonical JSON serialization
   * of the unsigned payload fields
   * Example: "U2lnbmF0dXJl..."
   */
  sig: string;
}
