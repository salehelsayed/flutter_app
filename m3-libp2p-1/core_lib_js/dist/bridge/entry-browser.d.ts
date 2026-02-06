/**
 * bridge/entry-browser.ts
 *
 * Browser-specific entry point for WebView integration.
 * Uses browser-compatible node creation (no fs, tcp).
 */
import type { MknoonNode } from '../types/p2p.js';
/**
 * Set the global node instance
 */
export declare function setNode(node: MknoonNode | null): void;
/**
 * Get the global node instance
 */
export declare function getNode(): MknoonNode | null;
/**
 * Check if node is running
 */
export declare function isNodeRunning(): boolean;
/**
 * Handle a bridge request from Flutter
 */
export declare function handleRequest(requestJson: string): Promise<void>;
//# sourceMappingURL=entry-browser.d.ts.map