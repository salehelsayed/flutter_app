/**
 * p2p/handlers.ts
 *
 * Message handlers and connection event management:
 * - Chat protocol handler (incoming messages)
 * - Send message function
 * - Connection event listeners
 * - Inbox integration
 */
import { Libp2p } from 'libp2p';
import type { MknoonNode, ChatMessage, ConnectionState } from '../types/p2p.js';
export declare const CHAT_PROTOCOL = "/mknoon/chat/1.0.0";
/**
 * Encode a message with 4-byte big-endian length prefix
 */
export declare function encodeFrame(payload: Uint8Array): Uint8Array;
/**
 * Read one complete frame from a stream
 */
export declare function readOneFrame(stream: any): Promise<Uint8Array>;
/**
 * Write one frame to a stream
 */
export declare function writeOneFrame(stream: any, payload: Uint8Array): Promise<void>;
/**
 * Setup the chat protocol handler for incoming messages
 */
export declare function setupChatHandler(node: MknoonNode, onMessage?: (message: ChatMessage) => void | Promise<void>, logger?: {
    log: (...args: any[]) => void;
    warn: (...args: any[]) => void;
}): void;
/**
 * Send a chat message to a peer
 */
export declare function sendMessage(node: Libp2p, targetPeerId: string, message: string, timeoutMs?: number, logger?: {
    log: (...args: any[]) => void;
    warn: (...args: any[]) => void;
}): Promise<string>;
/**
 * Setup connection event listeners
 */
export declare function setupConnectionListeners(node: MknoonNode, onConnect?: (state: ConnectionState) => void, onDisconnect?: (state: ConnectionState) => void, logger?: {
    log: (...args: any[]) => void;
    warn: (...args: any[]) => void;
}): void;
/**
 * Remove the chat protocol handler
 */
export declare function removeChatHandler(node: Libp2p): Promise<void>;
//# sourceMappingURL=handlers.d.ts.map