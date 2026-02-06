/**
 * bridge/entry.ts
 *
 * Entry point for the P2P bridge - routes commands to appropriate handlers.
 * This module acts as a facade for the P2P functionality.
 */
import * as handlers from './handlers.js';
// Global node instance (singleton pattern)
let globalNode = null;
/**
 * Set the global node instance
 */
export function setNode(node) {
    globalNode = node;
}
/**
 * Get the global node instance
 */
export function getNode() {
    return globalNode;
}
/**
 * Check if node is running
 */
export function isNodeRunning() {
    return globalNode !== null && globalNode.status === 'started';
}
/**
 * Route a command to the appropriate handler
 */
export async function handleCommand(request) {
    const { id, command, params } = request;
    try {
        let data;
        switch (command) {
            // Node lifecycle
            case 'node:start':
                data = await handlers.handleNodeStart(params, setNode);
                break;
            case 'node:stop':
                data = await handlers.handleNodeStop(globalNode, setNode);
                break;
            case 'node:status':
                data = handlers.handleNodeStatus(globalNode);
                break;
            // Rendezvous
            case 'rendezvous:register':
                data = await handlers.handleRendezvousRegister(globalNode, params);
                break;
            case 'rendezvous:discover':
                data = await handlers.handleRendezvousDiscover(globalNode, params);
                break;
            // Peer management
            case 'peer:dial':
                data = await handlers.handlePeerDial(globalNode, params);
                break;
            case 'peer:disconnect':
                data = await handlers.handlePeerDisconnect(globalNode, params);
                break;
            // Messaging
            case 'message:send':
                data = await handlers.handleMessageSend(globalNode, params);
                break;
            // Inbox
            case 'inbox:check':
                data = await handlers.handleInboxCheck(globalNode, params);
                break;
            case 'inbox:store':
                data = await handlers.handleInboxStore(globalNode, params);
                break;
            default:
                return {
                    id,
                    success: false,
                    error: `Unknown command: ${command}`
                };
        }
        return {
            id,
            success: true,
            data
        };
    }
    catch (err) {
        return {
            id,
            success: false,
            error: err?.message ?? String(err)
        };
    }
}
/**
 * Create a request object (convenience helper)
 */
export function createRequest(command, params = {}) {
    return {
        id: crypto.randomUUID(),
        command,
        params
    };
}
/**
 * Shorthand for executing a command
 */
export async function execute(command, params = {}) {
    return handleCommand(createRequest(command, params));
}
// Export handlers for direct access
export { handlers };
//# sourceMappingURL=entry.js.map