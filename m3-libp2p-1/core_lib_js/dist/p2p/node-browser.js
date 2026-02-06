/**
 * p2p/node-browser.ts
 *
 * Browser-compatible libp2p node creation.
 * Uses WebRTC + WebSockets + Circuit Relay for connectivity.
 * No Node.js APIs (fs, tcp, Buffer) - works in WebView.
 */
import { createLibp2p } from 'libp2p';
import { noise } from '@chainsafe/libp2p-noise';
import { yamux } from '@chainsafe/libp2p-yamux';
import { webSockets } from '@libp2p/websockets';
import { webRTC } from '@libp2p/webrtc';
import { circuitRelayTransport } from '@libp2p/circuit-relay-v2';
import { identify, identifyPush } from '@libp2p/identify';
import { ping } from '@libp2p/ping';
import { dcutr } from '@libp2p/dcutr';
import { privateKeyFromRaw } from '@libp2p/crypto/keys';
import { peerIdFromPrivateKey } from '@libp2p/peer-id';
import { hexToBytes } from '../utils/hex.js';
// Default ICE servers for WebRTC
const DEFAULT_ICE_SERVERS = [
    {
        urls: [
            'stun:mknoun.xyz:3478',
            'turn:mknoun.xyz:3478?transport=udp',
            'turn:mknoun.xyz:3478?transport=tcp'
        ],
        username: 'testuser',
        credential: 'testpass'
    }
];
// Browser listen addresses (no TCP)
const BROWSER_LISTEN_ADDRESSES = [
    '/p2p-circuit',
    '/webrtc'
];
/**
 * Load identity from private key hex (browser version)
 * Uses native hex utilities instead of Node.js Buffer
 */
export function loadIdentityFromHex(privateKeyHex) {
    const privateKeyBytes = hexToBytes(privateKeyHex);
    const privateKey = privateKeyFromRaw(privateKeyBytes);
    const peerId = peerIdFromPrivateKey(privateKey);
    return { privateKey, peerId };
}
/**
 * Create a browser-compatible libp2p node
 */
export async function createBrowserNode(config = {}) {
    if (!config.privateKeyHex) {
        throw new Error('privateKeyHex is required for browser nodes');
    }
    const { privateKey } = loadIdentityFromHex(config.privateKeyHex);
    // Browser transports (no TCP)
    const transports = [
        webSockets(),
        webRTC({
            rtcConfiguration: {
                iceServers: config.iceServers || DEFAULT_ICE_SERVERS
            }
        }),
        circuitRelayTransport()
    ];
    // Create libp2p node
    const node = await createLibp2p({
        privateKey,
        addresses: {
            listen: config.listenAddresses || BROWSER_LISTEN_ADDRESSES
        },
        transports,
        connectionEncrypters: [noise()],
        streamMuxers: [yamux()],
        services: {
            identify: identify(),
            identifyPush: identifyPush(),
            ping: ping(),
            ...(config.enableDcutr !== false ? { dcutr: dcutr() } : {})
        }
    });
    // Attach mknoon state
    node.mknoon = {
        config,
        rendezvousConfig: null,
        registrationAbort: null,
        onMessage: null,
        onEvent: null
    };
    return node;
}
// Re-export utility functions from utils.ts (browser-compatible)
export { getPeerId, getListenAddresses, getCircuitAddresses, hasCircuitAddresses, waitForCircuitAddresses } from './utils.js';
//# sourceMappingURL=node-browser.js.map