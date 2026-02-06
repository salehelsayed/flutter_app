/**
 * p2p/utils.ts
 *
 * Common utility functions for P2P nodes.
 * No Node.js-specific imports - works in browser.
 */
import type { Libp2p } from 'libp2p';
/**
 * Get the node's peer ID as a string
 */
export declare function getPeerId(node: Libp2p): string;
/**
 * Get all multiaddrs the node is listening on
 */
export declare function getListenAddresses(node: Libp2p): string[];
/**
 * Get only circuit relay addresses
 */
export declare function getCircuitAddresses(node: Libp2p): string[];
/**
 * Check if node has circuit addresses available
 */
export declare function hasCircuitAddresses(node: Libp2p): boolean;
/**
 * Wait for circuit addresses to become available
 */
export declare function waitForCircuitAddresses(node: Libp2p, timeoutMs?: number, signal?: AbortSignal): Promise<string[]>;
//# sourceMappingURL=utils.d.ts.map