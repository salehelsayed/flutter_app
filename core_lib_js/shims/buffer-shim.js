/**
 * Buffer polyfill for browser environment.
 * This is injected by esbuild into the bundle.
 */

import { Buffer } from 'buffer';

// Make Buffer globally available
globalThis.Buffer = Buffer;
