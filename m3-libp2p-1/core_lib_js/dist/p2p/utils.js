/**
 * p2p/utils.ts
 *
 * Common utility functions for P2P nodes.
 * No Node.js-specific imports - works in browser.
 */
/**
 * Get the node's peer ID as a string
 */
export function getPeerId(node) {
    return node.peerId.toString();
}
/**
 * Get all multiaddrs the node is listening on
 */
export function getListenAddresses(node) {
    return node.getMultiaddrs().map(ma => ma.toString());
}
/**
 * Get only circuit relay addresses
 */
export function getCircuitAddresses(node) {
    return node.getMultiaddrs()
        .filter(ma => ma.toString().includes('/p2p-circuit'))
        .map(ma => ma.toString());
}
/**
 * Check if node has circuit addresses available
 */
export function hasCircuitAddresses(node) {
    return getCircuitAddresses(node).length > 0;
}
/**
 * Wait for circuit addresses to become available
 */
export async function waitForCircuitAddresses(node, timeoutMs = 30000, signal) {
    const existing = getCircuitAddresses(node);
    if (existing.length > 0) {
        return existing;
    }
    return new Promise((resolve, reject) => {
        const onUpdate = () => {
            const addrs = getCircuitAddresses(node);
            if (addrs.length > 0) {
                cleanup();
                resolve(addrs);
            }
        };
        const onAbort = () => {
            cleanup();
            reject(new Error('aborted'));
        };
        const timer = setTimeout(() => {
            cleanup();
            reject(new Error(`Timed out waiting for /p2p-circuit address after ${timeoutMs}ms`));
        }, timeoutMs);
        const cleanup = () => {
            clearTimeout(timer);
            node.removeEventListener('self:peer:update', onUpdate);
            signal?.removeEventListener('abort', onAbort);
        };
        node.addEventListener('self:peer:update', onUpdate);
        if (signal) {
            signal.addEventListener('abort', onAbort, { once: true });
        }
    });
}
//# sourceMappingURL=utils.js.map