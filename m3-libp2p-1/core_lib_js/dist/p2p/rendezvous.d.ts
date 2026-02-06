/**
 * p2p/rendezvous.ts
 *
 * Rendezvous protocol for peer registration and discovery.
 * - registerOnRendezvous: Register this node so others can find it
 * - discoverPeers: Find other peers registered under a namespace
 */
import { Libp2p } from 'libp2p';
import { Multiaddr } from '@multiformats/multiaddr';
import type { RendezvousConfig, DiscoveredPeer, MknoonNode } from '../types/p2p.js';
export declare const RENDEZVOUS_PROTOCOL = "/canvas/rendezvous/1.0.0";
/**
 * Register once on a rendezvous server
 */
export declare function registerOnce(node: Libp2p, serverAddr: string | Multiaddr, namespace: string, ttlSeconds?: number): Promise<number>;
/**
 * Start continuous registration (re-registers before TTL expires)
 */
export declare function startRegistration(node: MknoonNode, config: RendezvousConfig, namespace: string, signal: AbortSignal, logger?: {
    log: (...args: any[]) => void;
    warn: (...args: any[]) => void;
}): Promise<void>;
/**
 * Discover peers from a single rendezvous point
 */
export declare function discoverFromPoint(node: Libp2p, serverAddr: string | Multiaddr, namespace: string): Promise<DiscoveredPeer[]>;
/**
 * Discover a specific peer by ID across all rendezvous points
 */
export declare function discoverPeer(node: Libp2p, config: RendezvousConfig, namespace: string, targetPeerId: string, logger?: {
    log: (...args: any[]) => void;
    warn: (...args: any[]) => void;
}): Promise<DiscoveredPeer | null>;
/**
 * Discover all peers registered under a namespace
 */
export declare function discoverAllPeers(node: Libp2p, config: RendezvousConfig, namespace: string): Promise<DiscoveredPeer[]>;
/**
 * Build namespace for a peer-to-peer chat
 */
export declare function buildChatNamespace(peerId: string): string;
//# sourceMappingURL=rendezvous.d.ts.map