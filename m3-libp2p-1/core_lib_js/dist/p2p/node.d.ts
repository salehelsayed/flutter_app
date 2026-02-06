/**
 * p2p/node.ts
 *
 * Creates and configures the libp2p node with all transports, muxers, and security.
 */
import type { PrivateKey, PeerId } from '@libp2p/interface';
import type { NodeConfig, MknoonNode } from '../types/p2p.js';
/**
 * Load identity from configuration
 */
export declare function loadIdentity(config: NodeConfig): Promise<{
    privateKey: PrivateKey;
    peerId: PeerId;
}>;
/**
 * Create a configured libp2p node
 */
export declare function createNode(config?: NodeConfig): Promise<MknoonNode>;
export { getPeerId, getListenAddresses, getCircuitAddresses, hasCircuitAddresses, waitForCircuitAddresses } from './utils.js';
export default createNode;
//# sourceMappingURL=node.d.ts.map