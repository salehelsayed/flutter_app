/**
 * bridge/entry.ts
 *
 * Entry point for the P2P bridge - routes commands to appropriate handlers.
 * This module acts as a facade for the P2P functionality.
 */
import type { BridgeRequest, BridgeResponse, MknoonNode } from '../types/p2p.js';
import * as handlers from './handlers.js';
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
 * Route a command to the appropriate handler
 */
export declare function handleCommand(request: BridgeRequest): Promise<BridgeResponse>;
/**
 * Create a request object (convenience helper)
 */
export declare function createRequest(command: BridgeRequest['command'], params?: Record<string, unknown>): BridgeRequest;
/**
 * Shorthand for executing a command
 */
export declare function execute(command: BridgeRequest['command'], params?: Record<string, unknown>): Promise<BridgeResponse>;
export { handlers };
//# sourceMappingURL=entry.d.ts.map