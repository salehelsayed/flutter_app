/**
 * p2p/listeners.ts
 *
 * Setup listeners for the libp2p node:
 * - /p2p-circuit relay listener
 * - TCP listener for direct connections
 * - Dial relay and establish circuit addresses
 */
import { Libp2p } from 'libp2p';
import { Multiaddr } from '@multiformats/multiaddr';
import type { MknoonNode } from '../types/p2p.js';
/**
 * Extract peer ID from a multiaddr string
 */
export declare function extractPeerIdFromAddr(addr: string): string | null;
/**
 * Dial a relay server to establish circuit relay connectivity
 */
export declare function dialRelay(node: Libp2p, relayAddr?: string | Multiaddr, logger?: {
    log: (...args: any[]) => void;
    warn: (...args: any[]) => void;
}): Promise<{
    connection: any;
    relayPeerId: string;
}>;
/**
 * Setup listeners and establish relay connection
 * Returns when circuit addresses are available
 */
export declare function setupListeners(node: MknoonNode, config?: {
    relayAddresses?: string[];
    waitForCircuitMs?: number;
}, logger?: {
    log: (...args: any[]) => void;
    warn: (...args: any[]) => void;
}): Promise<{
    circuitAddresses: string[];
    relayPeerId: string | null;
}>;
/**
 * Dial a peer using discovered addresses
 */
export declare function dialPeer(node: Libp2p, peerId: string, addresses: (string | Multiaddr)[], timeoutMs?: number, logger?: {
    log: (...args: any[]) => void;
    warn: (...args: any[]) => void;
}): Promise<any>;
/**
 * Add peer addresses to peerstore so dialProtocol works
 */
export declare function addPeerToStore(node: Libp2p, peerId: string, addresses: (string | Multiaddr)[]): Promise<void>;
/**
 * Get all connected peer IDs (excluding relay)
 */
export declare function getConnectedPeers(node: Libp2p, excludePeerIds?: string[]): string[];
/**
 * Disconnect from a peer
 */
export declare function disconnectPeer(node: Libp2p, peerId: string, logger?: {
    log: (...args: any[]) => void;
    warn: (...args: any[]) => void;
}): Promise<void>;
//# sourceMappingURL=listeners.d.ts.map