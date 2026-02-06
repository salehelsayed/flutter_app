/**
 * p2p/listeners.ts
 *
 * Setup listeners for the libp2p node:
 * - /p2p-circuit relay listener
 * - TCP listener for direct connections
 * - Dial relay and establish circuit addresses
 */
import { multiaddr } from '@multiformats/multiaddr';
import { peerIdFromString } from '@libp2p/peer-id';
import { waitForCircuitAddresses } from './utils.js';
// Default relay address
const DEFAULT_RELAY_ADDRESS = '/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g';
/**
 * Extract peer ID from a multiaddr string
 */
export function extractPeerIdFromAddr(addr) {
    const match = addr.match(/\/p2p\/([^/]+)$/);
    return match ? match[1] : null;
}
/**
 * Dial a relay server to establish circuit relay connectivity
 */
export async function dialRelay(node, relayAddr = DEFAULT_RELAY_ADDRESS, logger = console) {
    const ma = typeof relayAddr === 'string' ? multiaddr(relayAddr) : relayAddr;
    const relayPeerId = extractPeerIdFromAddr(ma.toString());
    if (!relayPeerId) {
        throw new Error(`Could not extract peer ID from relay address: ${ma.toString()}`);
    }
    try {
        const connection = await node.dial(ma, { signal: AbortSignal.timeout(20000) });
        logger.log(`[Listeners] Relay connected: ${connection.remotePeer.toString()}`);
        // Try to protect the connection from being pruned
        const cm = node.connectionManager;
        if (typeof cm?.protect === 'function') {
            try {
                cm.protect(connection.remotePeer, 'mknoon-relay');
            }
            catch { }
        }
        return { connection, relayPeerId };
    }
    catch (err) {
        logger.warn(`[Listeners] Relay dial failed:`, err?.message ?? err);
        throw err;
    }
}
/**
 * Setup listeners and establish relay connection
 * Returns when circuit addresses are available
 */
export async function setupListeners(node, config = {}, logger = console) {
    const relayAddresses = config.relayAddresses || [DEFAULT_RELAY_ADDRESS];
    const waitForCircuitMs = config.waitForCircuitMs ?? 30000;
    let relayPeerId = null;
    // Try to dial relay addresses in order
    for (const relayAddr of relayAddresses) {
        try {
            const result = await dialRelay(node, relayAddr, logger);
            relayPeerId = result.relayPeerId;
            break;
        }
        catch (err) {
            logger.warn(`[Listeners] Failed to dial relay ${relayAddr}:`, err?.message ?? err);
        }
    }
    if (!relayPeerId) {
        logger.warn('[Listeners] Could not connect to any relay server');
    }
    // Wait for circuit addresses to become available
    let circuitAddresses = [];
    try {
        circuitAddresses = await waitForCircuitAddresses(node, waitForCircuitMs);
        logger.log('[Listeners] Circuit addresses available:');
        for (const addr of circuitAddresses) {
            logger.log(`  ${addr}`);
        }
    }
    catch (err) {
        logger.warn('[Listeners] Failed to get circuit addresses:', err?.message ?? err);
        // Continue anyway - may still work for outbound connections
    }
    return { circuitAddresses, relayPeerId };
}
/**
 * Dial a peer using discovered addresses
 */
export async function dialPeer(node, peerId, addresses, timeoutMs = 30000, logger = console) {
    // Check for existing connection
    const existing = node.getConnections().find(c => c.remotePeer.toString() === peerId);
    if (existing) {
        logger.log(`[Listeners] Already connected to ${peerId}`);
        return existing;
    }
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    let lastErr = null;
    try {
        for (const addr of addresses) {
            try {
                const ma = typeof addr === 'string' ? multiaddr(addr) : addr;
                // Ensure address includes peer ID
                let dialAddr = ma;
                if (!ma.toString().includes(`/p2p/${peerId}`)) {
                    dialAddr = multiaddr(`${ma.toString().replace(/\/$/, '')}/p2p/${peerId}`);
                }
                await node.dial(dialAddr, { signal: controller.signal });
                const conn = node.getConnections().find(c => c.remotePeer.toString() === peerId);
                if (conn) {
                    logger.log(`[Listeners] Connected to ${peerId} via ${dialAddr.toString()}`);
                    return conn;
                }
            }
            catch (err) {
                lastErr = err;
                logger.warn(`[Listeners] Dial failed via ${addr}:`, err?.message ?? err);
            }
        }
    }
    finally {
        clearTimeout(timer);
    }
    throw new Error(`Could not dial ${peerId}: ${lastErr?.message ?? 'no addresses worked'}`);
}
/**
 * Add peer addresses to peerstore so dialProtocol works
 */
export async function addPeerToStore(node, peerId, addresses) {
    const multiaddrs = addresses.map(a => typeof a === 'string' ? multiaddr(a) : a);
    // Ensure each address includes the peer ID
    const normalizedAddrs = multiaddrs.map(ma => {
        const s = ma.toString();
        if (s.includes(`/p2p/${peerId}`)) {
            return ma;
        }
        return multiaddr(`${s.replace(/\/$/, '')}/p2p/${peerId}`);
    });
    await node.peerStore.merge(peerIdFromString(peerId), { multiaddrs: normalizedAddrs });
}
/**
 * Get all connected peer IDs (excluding relay)
 */
export function getConnectedPeers(node, excludePeerIds = []) {
    const excludeSet = new Set(excludePeerIds);
    return node.getConnections()
        .map(c => c.remotePeer.toString())
        .filter(id => !excludeSet.has(id))
        .filter((id, idx, arr) => arr.indexOf(id) === idx); // dedupe
}
/**
 * Disconnect from a peer
 */
export async function disconnectPeer(node, peerId, logger = console) {
    const connections = node.getConnections().filter(c => c.remotePeer.toString() === peerId);
    for (const conn of connections) {
        try {
            await conn.close();
        }
        catch (err) {
            logger.warn(`[Listeners] Error closing connection:`, err?.message ?? err);
        }
    }
    if (connections.length > 0) {
        logger.log(`[Listeners] Disconnected from ${peerId}`);
    }
}
//# sourceMappingURL=listeners.js.map