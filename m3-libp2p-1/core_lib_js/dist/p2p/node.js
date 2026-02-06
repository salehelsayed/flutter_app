/**
 * p2p/node.ts
 *
 * Creates and configures the libp2p node with all transports, muxers, and security.
 */
import { createLibp2p } from 'libp2p';
import { noise } from '@chainsafe/libp2p-noise';
import { yamux } from '@chainsafe/libp2p-yamux';
import { webSockets } from '@libp2p/websockets';
import { webRTC } from '@libp2p/webrtc';
import { tcp } from '@libp2p/tcp';
import { circuitRelayTransport } from '@libp2p/circuit-relay-v2';
import { identify, identifyPush } from '@libp2p/identify';
import { ping } from '@libp2p/ping';
import { dcutr } from '@libp2p/dcutr';
import { privateKeyFromRaw } from '@libp2p/crypto/keys';
import { peerIdFromPrivateKey } from '@libp2p/peer-id';
import { readFile } from 'fs/promises';
// Default configuration
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
const DEFAULT_LISTEN_ADDRESSES = [
    '/p2p-circuit', // Virtual relay listener
    '/ip4/0.0.0.0/tcp/0' // Real TCP port for DCUtR
];
/**
 * Extract private key hex from credentials file content
 */
function extractPrivateKeyHex(contents) {
    const match = contents.match(/Private Key \(64 bytes, hex\):\s*([0-9a-fA-F]+)/);
    if (!match) {
        throw new Error('Could not find "Private Key (64 bytes, hex): ..." in credentials file');
    }
    return match[1].trim();
}
/**
 * Load identity from configuration
 */
export async function loadIdentity(config) {
    let privateKeyHex;
    if (config.privateKeyHex) {
        privateKeyHex = config.privateKeyHex;
    }
    else if (config.credentialsPath) {
        const contents = await readFile(config.credentialsPath, 'utf8');
        privateKeyHex = extractPrivateKeyHex(contents);
    }
    else {
        throw new Error('Either privateKeyHex or credentialsPath must be provided');
    }
    const privateKeyBytes = Uint8Array.from(Buffer.from(privateKeyHex, 'hex'));
    const privateKey = privateKeyFromRaw(privateKeyBytes);
    const peerId = peerIdFromPrivateKey(privateKey);
    return { privateKey, peerId };
}
/**
 * Create a configured libp2p node
 */
export async function createNode(config = {}) {
    const { privateKey, peerId } = await loadIdentity(config);
    // Build transports array
    const transports = [
        webSockets(),
        tcp(),
        webRTC({
            rtcConfiguration: {
                iceServers: config.iceServers || DEFAULT_ICE_SERVERS
            }
        })
    ];
    // Add circuit relay transport if enabled (default: true)
    if (config.enableCircuitRelay !== false) {
        transports.push(circuitRelayTransport());
    }
    // Create the libp2p node
    const node = await createLibp2p({
        privateKey,
        addresses: {
            listen: config.listenAddresses || DEFAULT_LISTEN_ADDRESSES
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
    // Attach mknoon-specific state
    node.mknoon = {
        config,
        rendezvousConfig: null,
        registrationAbort: null,
        onMessage: null,
        onEvent: null
    };
    return node;
}
// Re-export utility functions
export { getPeerId, getListenAddresses, getCircuitAddresses, hasCircuitAddresses, waitForCircuitAddresses } from './utils.js';
export default createNode;
//# sourceMappingURL=node.js.map