/**
 * inbox.ts
 *
 * Stub module for inbox functionality.
 * The full implementation will be added when the relay server supports inbox storage.
 */
import type { Libp2p } from 'libp2p';
import type { PeerId } from '@libp2p/interface';
export declare enum ResponseStatus {
    OK = "OK",
    ERROR = "ERROR",
    NO_MESSAGES = "NO_MESSAGES"
}
export interface InboxMessage {
    from: string;
    message: string;
    timestamp: number;
    metadata?: Record<string, unknown>;
}
export interface InboxResponse {
    status: ResponseStatus;
    messages: InboxMessage[];
    error?: string;
}
/**
 * Store a message in the recipient's inbox on the relay server
 * @stub Returns error - not yet implemented
 */
export declare function storeInInbox(_node: Libp2p, _relayPeerId: PeerId, _toPeerId: string, _message: string, _metadata?: Record<string, unknown>): Promise<InboxResponse>;
/**
 * Retrieve messages from this node's inbox on the relay server
 * @stub Returns empty - not yet implemented
 */
export declare function retrieveFromInbox(_node: Libp2p, _relayPeerId: PeerId, _options?: {
    limit?: number;
    peek?: boolean;
}): Promise<InboxResponse>;
//# sourceMappingURL=inbox.d.ts.map