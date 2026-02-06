/**
 * utils/hex.ts
 *
 * Native hex conversion utilities for browser environments.
 * Replaces Node.js Buffer.from(hex, 'hex') usage.
 */
/**
 * Convert hex string to Uint8Array
 */
export function hexToBytes(hex) {
    const cleanHex = hex.startsWith('0x') ? hex.slice(2) : hex;
    if (cleanHex.length % 2 !== 0) {
        throw new Error('Hex string must have even length');
    }
    if (!/^[0-9a-fA-F]*$/.test(cleanHex)) {
        throw new Error('Invalid hex string');
    }
    const bytes = new Uint8Array(cleanHex.length / 2);
    for (let i = 0; i < bytes.length; i++) {
        bytes[i] = parseInt(cleanHex.substr(i * 2, 2), 16);
    }
    return bytes;
}
/**
 * Convert Uint8Array to hex string
 */
export function bytesToHex(bytes) {
    return Array.from(bytes)
        .map(b => b.toString(16).padStart(2, '0'))
        .join('');
}
//# sourceMappingURL=hex.js.map