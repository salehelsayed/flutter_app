/**
 * P2P-related TypeScript interfaces
 */
import type { Libp2p } from 'libp2p';
import type { PeerId } from '@libp2p/interface';
import type { Multiaddr } from '@multiformats/multiaddr';
export interface NodeConfig {
    /** Private key in hex format (64 bytes / 128 hex chars for Ed25519) */
    privateKeyHex?: string;
    /** Path to credentials file containing private key */
    credentialsPath?: string;
    /** Listen addresses */
    listenAddresses?: string[];
    /** Bootstrap/relay addresses */
    bootstrapAddresses?: string[];
    /** WebRTC ICE servers */
    iceServers?: RTCIceServer[];
    /** Enable circuit relay transport */
    enableCircuitRelay?: boolean;
    /** Enable DCUtR (hole punching) */
    enableDcutr?: boolean;
}
export interface RTCIceServer {
    urls: string | string[];
    username?: string;
    credential?: string;
}
export interface RendezvousConfig {
    /** Rendezvous server addresses */
    serverAddresses: string[];
    /** Registration TTL in seconds */
    ttlSeconds?: number;
    /** Retry interval in ms on failure */
    retryMs?: number;
    /** Discovery poll interval in ms */
    pollMs?: number;
    /** Discovery timeout in ms */
    timeoutMs?: number;
}
export interface DiscoveredPeer {
    id: PeerId;
    addresses: Multiaddr[];
}
export interface ChatMessage {
    from: string;
    to: string;
    content: string;
    timestamp: number;
}
export interface InboxMessage {
    from: string;
    message: string;
    timestamp: number;
    metadata?: Record<string, unknown>;
}
export interface ConnectionState {
    peerId: string;
    multiaddrs: string[];
    direction: 'inbound' | 'outbound';
    status: 'connected' | 'disconnected';
    connectedAt?: number;
}
export interface NodeState {
    peerId: string | null;
    isStarted: boolean;
    listenAddresses: string[];
    circuitAddresses: string[];
    connections: ConnectionState[];
    registeredNamespaces: string[];
}
export type P2PEventType = 'node:started' | 'node:stopped' | 'peer:connected' | 'peer:disconnected' | 'message:received' | 'message:sent' | 'rendezvous:registered' | 'rendezvous:discovered' | 'inbox:received';
export interface P2PEvent {
    type: P2PEventType;
    timestamp: number;
    data: unknown;
}
export type BridgeCommand = 'node:start' | 'node:stop' | 'node:status' | 'rendezvous:register' | 'rendezvous:discover' | 'peer:dial' | 'peer:disconnect' | 'message:send' | 'inbox:check' | 'inbox:store';
export interface BridgeRequest {
    id: string;
    command: BridgeCommand;
    params: Record<string, unknown>;
}
export interface BridgeResponse {
    id: string;
    success: boolean;
    data?: unknown;
    error?: string;
}
export type MessageHandler = (message: ChatMessage) => void | Promise<void>;
export type EventHandler = (event: P2PEvent) => void | Promise<void>;
export interface MknoonNode extends Libp2p {
    mknoon: {
        config: NodeConfig;
        rendezvousConfig: RendezvousConfig | null;
        registrationAbort: AbortController | null;
        onMessage: MessageHandler | null;
        onEvent: EventHandler | null;
    };
}
//# sourceMappingURL=p2p.d.ts.map