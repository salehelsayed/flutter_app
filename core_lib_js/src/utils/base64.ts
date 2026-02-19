/**
 * @fileoverview Base64 <-> Uint8Array conversion utilities.
 *
 * Uses standard base64 encoding (not base64url). Compatible with:
 * - Go's encoding/base64.StdEncoding
 * - Node.js Buffer.toString('base64') / Buffer.from(str, 'base64')
 */

/**
 * Converts a Uint8Array to a standard base64-encoded string.
 */
export function uint8ArrayToBase64(bytes: Uint8Array): string {
  // In Node.js, Buffer.from() is the most efficient approach.
  // In a browser/WebView context, we'd use btoa or a polyfill.
  if (typeof Buffer !== 'undefined') {
    return Buffer.from(bytes).toString('base64');
  }
  // Browser fallback using btoa.
  let binary = '';
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}

/**
 * Converts a standard base64-encoded string to a Uint8Array.
 */
export function base64ToUint8Array(base64: string): Uint8Array {
  if (typeof Buffer !== 'undefined') {
    const buf = Buffer.from(base64, 'base64');
    return new Uint8Array(buf.buffer, buf.byteOffset, buf.byteLength);
  }
  // Browser fallback using atob.
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}
