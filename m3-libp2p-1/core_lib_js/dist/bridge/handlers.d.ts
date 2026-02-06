/**
 * bridge/handlers.ts
 *
 * P2P command handlers for the bridge.
 * Each handler implements a specific bridge command.
 */
import type { MknoonNode, NodeState } from '../types/p2p.js';
/**
 * Handle node:start command
 * Creates and starts the P2P node
 */
export declare function handleNodeStart(params: Record<string, unknown>, setNode: (node: MknoonNode | null) => void): Promise<NodeState>;
/**
 * Handle node:stop command
 */
export declare function handleNodeStop(node: MknoonNode | null, setNode: (node: MknoonNode | null) => void): Promise<{
    stopped: boolean;
}>;
/**
 * Handle node:status command
 */
export declare function handleNodeStatus(node: MknoonNode | null): NodeState;
/**
 * Handle rendezvous:register command
 */
export declare function handleRendezvousRegister(node: MknoonNode | null, params: Record<string, unknown>): Promise<{
    registered: boolean;
    namespace: string;
}>;
/**
 * Handle rendezvous:discover command
 */
export declare function handleRendezvousDiscover(node: MknoonNode | null, params: Record<string, unknown>): Promise<{
    peers: Array<{
        id: string;
        addresses: string[];
    }>;
}>;
/**
 * Handle peer:dial command
 */
export declare function handlePeerDial(node: MknoonNode | null, params: Record<string, unknown>): Promise<{
    connected: boolean;
    peerId: string;
}>;
/**
 * Handle peer:disconnect command
 */
export declare function handlePeerDisconnect(node: MknoonNode | null, params: Record<string, unknown>): Promise<{
    disconnected: boolean;
    peerId: string;
}>;
/**
 * Handle message:send command
 */
export declare function handleMessageSend(node: MknoonNode | null, params: Record<string, unknown>): Promise<{
    sent: boolean;
    reply: string | null;
    storedInInbox: boolean;
}>;
/**
 * Handle inbox:check command
 */
export declare function handleInboxCheck(node: MknoonNode | null, params: Record<string, unknown>): Promise<{
    messages: Array<{
        from: string;
        message: string;
        timestamp: number;
    }>;
}>;
/**
 * Handle inbox:store command
 */
export declare function handleInboxStore(node: MknoonNode | null, params: Record<string, unknown>): Promise<{
    stored: boolean;
}>;
//# sourceMappingURL=handlers.d.ts.map