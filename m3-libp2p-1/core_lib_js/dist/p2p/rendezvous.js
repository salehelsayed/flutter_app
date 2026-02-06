/**
 * p2p/rendezvous.ts
 *
 * Rendezvous protocol for peer registration and discovery.
 * - registerOnRendezvous: Register this node so others can find it
 * - discoverPeers: Find other peers registered under a namespace
 */
import { multiaddr } from '@multiformats/multiaddr';
import { peerIdFromPublicKey } from '@libp2p/peer-id';
import { PeerRecord, RecordEnvelope } from '@libp2p/peer-record';
import { Message } from '@canvas-js/libp2p-rendezvous/protocol';
import * as lp from 'it-length-prefixed';
import { getCircuitAddresses } from './utils.js';
export const RENDEZVOUS_PROTOCOL = '/canvas/rendezvous/1.0.0';
// Default configuration
const DEFAULT_TTL_SECONDS = 2 * 60 * 60; // 2 hours
const DEFAULT_RETRY_MS = 5000;
const DEFAULT_POLL_MS = 2000;
const DEFAULT_TIMEOUT_MS = 60000;
/**
 * Sleep helper with abort signal support
 */
async function sleepWithSignal(ms, signal) {
    if (signal?.aborted)
        return;
    await new Promise(resolve => {
        const t = setTimeout(resolve, ms);
        if (signal) {
            signal.addEventListener('abort', () => {
                clearTimeout(t);
                resolve();
            }, { once: true });
        }
    });
}
/**
 * Register once on a rendezvous server
 */
export async function registerOnce(node, serverAddr, namespace, ttlSeconds = DEFAULT_TTL_SECONDS) {
    const circuitAddrs = getCircuitAddresses(node).map(a => multiaddr(a));
    if (circuitAddrs.length === 0) {
        throw new Error('No /p2p-circuit addresses available to register');
    }
    // Dial the rendezvous server
    const ma = typeof serverAddr === 'string' ? multiaddr(serverAddr) : serverAddr;
    const connection = await node.dial(ma, { signal: AbortSignal.timeout(20000) });
    // Open stream to rendezvous protocol
    const stream = await connection.newStream(RENDEZVOUS_PROTOCOL, {
        signal: AbortSignal.timeout(10000)
    });
    try {
        // Get private key from node components
        const privateKey = node.components?.components?.privateKey ||
            node.components?.privateKey;
        if (!privateKey) {
            throw new Error('Cannot access node privateKey for signing');
        }
        // Create signed peer record
        const record = new PeerRecord({ peerId: node.peerId, multiaddrs: circuitAddrs });
        const envelope = await RecordEnvelope.seal(record, privateKey);
        const signedPeerRecord = envelope.marshal();
        // Build REGISTER message
        const registerMsg = Message.encode({
            type: Message.MessageType.REGISTER,
            register: {
                ns: namespace,
                signedPeerRecord,
                ttl: BigInt(ttlSeconds)
            }
        });
        // Length-prefix encode
        const encoded = lp.encode.single(registerMsg);
        const msgBytes = encoded.subarray();
        // Set up response collection
        const responsePromise = new Promise((resolve, reject) => {
            const chunks = [];
            const timeout = setTimeout(() => {
                reject(new Error('Timeout waiting for register response'));
            }, 10000);
            const tryDecode = async () => {
                if (chunks.length === 0)
                    return;
                const totalLen = chunks.reduce((a, c) => a + c.length, 0);
                const allData = new Uint8Array(totalLen);
                let offset = 0;
                for (const c of chunks) {
                    allData.set(c, offset);
                    offset += c.length;
                }
                try {
                    async function* source() { yield allData; }
                    for await (const decoded of lp.decode(source())) {
                        clearTimeout(timeout);
                        resolve(decoded.subarray());
                        return;
                    }
                }
                catch {
                    // Not enough data yet
                }
            };
            // Handle different stream APIs
            if (typeof stream.onData === 'function') {
                const orig = stream.onData;
                stream.onData = (data) => {
                    orig?.call(stream, data);
                    chunks.push(data.subarray ? data.subarray() : new Uint8Array(data));
                    tryDecode();
                };
            }
            else {
                ;
                stream.addEventListener?.('data', (evt) => {
                    const data = evt.detail || evt.data || evt;
                    chunks.push(data.subarray ? data.subarray() : new Uint8Array(data));
                    tryDecode();
                });
            }
        });
        stream.send(msgBytes);
        // Wait for response
        const responseData = await responsePromise;
        const response = Message.decode(responseData);
        if (response.type !== Message.MessageType.REGISTER_RESPONSE) {
            throw new Error(`Unexpected response type: ${response.type}`);
        }
        if (response.registerResponse?.status !== Message.ResponseStatus.OK) {
            throw new Error(`Registration failed: ${response.registerResponse?.statusText ?? 'unknown error'}`);
        }
        return Number(response.registerResponse.ttl);
    }
    finally {
        try {
            await stream.close();
        }
        catch { }
    }
}
/**
 * Start continuous registration (re-registers before TTL expires)
 */
export async function startRegistration(node, config, namespace, signal, logger = console) {
    const ttlSeconds = config.ttlSeconds ?? DEFAULT_TTL_SECONDS;
    const retryMs = config.retryMs ?? DEFAULT_RETRY_MS;
    // Store config on node
    node.mknoon.rendezvousConfig = config;
    while (!signal.aborted) {
        for (const serverAddr of config.serverAddresses) {
            if (signal.aborted)
                break;
            try {
                const actualTtl = await registerOnce(node, serverAddr, namespace, ttlSeconds);
                logger.log(`[Rendezvous] Registered on ${serverAddr} (ttl=${actualTtl}s)`);
                // Emit event if handler exists
                if (node.mknoon.onEvent) {
                    node.mknoon.onEvent({
                        type: 'rendezvous:registered',
                        timestamp: Date.now(),
                        data: { namespace, serverAddr, ttl: actualTtl }
                    });
                }
                // Wait for 80% of TTL before re-registering
                const refreshMs = Math.max(30000, Math.floor(actualTtl * 1000 * 0.8));
                await sleepWithSignal(refreshMs, signal);
                break; // Successfully registered, exit inner loop to re-register
            }
            catch (err) {
                logger.warn(`[Rendezvous] Register failed on ${serverAddr}:`, err?.message ?? err);
            }
        }
        // If we didn't successfully register on any server, wait before retrying
        if (!signal.aborted) {
            await sleepWithSignal(retryMs, signal);
        }
    }
}
/**
 * Discover peers from a single rendezvous point
 */
export async function discoverFromPoint(node, serverAddr, namespace) {
    const ma = typeof serverAddr === 'string' ? multiaddr(serverAddr) : serverAddr;
    const connection = await node.dial(ma, { signal: AbortSignal.timeout(20000) });
    const stream = await connection.newStream(RENDEZVOUS_PROTOCOL, {
        signal: AbortSignal.timeout(10000)
    });
    try {
        // Build DISCOVER message
        const discoverMsg = Message.encode({
            type: Message.MessageType.DISCOVER,
            discover: {
                ns: namespace,
                limit: BigInt(100),
                cookie: new Uint8Array()
            }
        });
        const encoded = lp.encode.single(discoverMsg);
        const msgBytes = encoded.subarray();
        // Start reading before sending
        let responseData = null;
        const readPromise = (async () => {
            for await (const chunk of lp.decode(stream)) {
                responseData = chunk.subarray();
                break;
            }
        })();
        stream.send(msgBytes);
        // Wait for response with timeout
        await Promise.race([
            readPromise,
            new Promise((_, reject) => setTimeout(() => reject(new Error('Timeout waiting for discover response')), 10000))
        ]);
        if (!responseData) {
            throw new Error('No response received');
        }
        const response = Message.decode(responseData);
        if (response.type !== Message.MessageType.DISCOVER_RESPONSE) {
            throw new Error(`Unexpected response type: ${response.type}`);
        }
        if (response.discoverResponse?.status !== Message.ResponseStatus.OK) {
            throw new Error(`Discover failed: ${response.discoverResponse?.statusText ?? 'unknown error'}`);
        }
        // Parse registrations
        const peers = [];
        for (const reg of response.discoverResponse.registrations || []) {
            try {
                const envelope = await RecordEnvelope.openAndCertify(reg.signedPeerRecord, PeerRecord.DOMAIN);
                const peerRecord = PeerRecord.createFromProtobuf(envelope.payload);
                const peerId = peerIdFromPublicKey(envelope.publicKey);
                peers.push({
                    id: peerId,
                    addresses: peerRecord.multiaddrs
                });
            }
            catch (err) {
                console.warn(`[Rendezvous] Failed to parse registration: ${err?.message ?? err}`);
            }
        }
        return peers;
    }
    finally {
        try {
            await stream.close();
        }
        catch { }
    }
}
/**
 * Discover a specific peer by ID across all rendezvous points
 */
export async function discoverPeer(node, config, namespace, targetPeerId, logger = console) {
    const timeoutMs = config.timeoutMs ?? DEFAULT_TIMEOUT_MS;
    const pollMs = config.pollMs ?? DEFAULT_POLL_MS;
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
        // Query all rendezvous points in parallel
        const results = await Promise.allSettled(config.serverAddresses.map(addr => discoverFromPoint(node, addr, namespace)));
        const allPeers = results
            .filter((r) => r.status === 'fulfilled')
            .flatMap(r => r.value);
        // Look for target peer
        const match = allPeers.find(p => p.id.toString() === targetPeerId);
        if (match) {
            logger.log(`[Rendezvous] Discovered ${targetPeerId}`);
            return match;
        }
        await sleepWithSignal(pollMs);
    }
    logger.warn(`[Rendezvous] Timed out discovering ${targetPeerId}`);
    return null;
}
/**
 * Discover all peers registered under a namespace
 */
export async function discoverAllPeers(node, config, namespace) {
    const results = await Promise.allSettled(config.serverAddresses.map(addr => discoverFromPoint(node, addr, namespace)));
    // Deduplicate by peer ID
    const seen = new Set();
    const peers = [];
    for (const result of results) {
        if (result.status === 'fulfilled') {
            for (const peer of result.value) {
                const id = peer.id.toString();
                if (!seen.has(id)) {
                    seen.add(id);
                    peers.push(peer);
                }
            }
        }
    }
    return peers;
}
/**
 * Build namespace for a peer-to-peer chat
 */
export function buildChatNamespace(peerId) {
    return `mknoon:chat:${peerId}`;
}
//# sourceMappingURL=rendezvous.js.map