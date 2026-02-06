/**
 * p2p/node-browser.ts
 *
 * Browser-compatible libp2p node creation.
 * Uses WebRTC + WebSockets + Circuit Relay for connectivity.
 * No Node.js APIs (fs, tcp, Buffer) - works in WebView.
 */
import type { PrivateKey, PeerId } from '@libp2p/interface';
import type { NodeConfig, MknoonNode } from '../types/p2p.js';
/**
 * Load identity from private key hex (browser version)
 * Uses native hex utilities instead of Node.js Buffer
 */
export declare function loadIdentityFromHex(privateKeyHex: string): {
    privateKey: PrivateKey;
    peerId: PeerId;
};
/**
 * Create a browser-compatible libp2p node
 */
export declare function createBrowserNode(config?: NodeConfig): Promise<MknoonNode>;
export { getPeerId, getListenAddresses, getCircuitAddresses, hasCircuitAddresses, waitForCircuitAddresses } from './utils.js';
//# sourceMappingURL=node-browser.d.ts.map