/**
 * bridge/handlers.ts
 *
 * P2P command handlers for the bridge.
 * Each handler implements a specific bridge command.
 */
import { peerIdFromString } from '@libp2p/peer-id';
import { createNode, getPeerId, getListenAddresses, getCircuitAddresses } from '../p2p/node.js';
import { setupListeners, dialPeer, addPeerToStore, disconnectPeer } from '../p2p/listeners.js';
import { startRegistration, discoverPeer, discoverAllPeers, buildChatNamespace } from '../p2p/rendezvous.js';
import { setupChatHandler, setupConnectionListeners, sendMessage } from '../p2p/handlers.js';
// Import inbox helpers
import { storeInInbox, retrieveFromInbox, ResponseStatus } from '../inbox.js';
/**
 * Handle node:start command
 * Creates and starts the P2P node
 */
export async function handleNodeStart(params, setNode) {
    const config = {
        privateKeyHex: params.privateKeyHex,
        credentialsPath: params.credentialsPath,
        listenAddresses: params.listenAddresses,
        bootstrapAddresses: params.bootstrapAddresses,
        iceServers: params.iceServers,
        enableCircuitRelay: params.enableCircuitRelay,
        enableDcutr: params.enableDcutr
    };
    // Create and start node
    const node = await createNode(config);
    await node.start();
    // Setup listeners (dial relay, get circuit addresses)
    const relayAddresses = params.relayAddresses;
    const { circuitAddresses, relayPeerId } = await setupListeners(node, {
        relayAddresses,
        waitForCircuitMs: params.waitForCircuitMs
    });
    // Setup chat protocol handler
    setupChatHandler(node, undefined);
    // Setup connection event listeners
    setupConnectionListeners(node);
    node._relayPeerId = relayPeerId;
    // Auto-register on rendezvous if namespace provided
    if (params.namespace || params.autoRegister !== false) {
        const namespace = params.namespace || buildChatNamespace(getPeerId(node));
        const rendezvousConfig = {
            serverAddresses: relayAddresses || [
                '/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g'
            ],
            ttlSeconds: params.ttlSeconds,
            retryMs: params.retryMs
        };
        // Start registration in background
        const abort = new AbortController();
        node.mknoon.registrationAbort = abort;
        void startRegistration(node, rendezvousConfig, namespace, abort.signal);
    }
    // Check inbox for offline messages
    if (relayPeerId && params.checkInbox !== false) {
        try {
            const response = await retrieveFromInbox(node, peerIdFromString(relayPeerId));
            if (response.status === ResponseStatus.OK && response.messages?.length > 0) {
                console.log(`[Bridge] Retrieved ${response.messages.length} offline message(s)`);
                // Trigger message handlers for each
                for (const msg of response.messages) {
                    if (node.mknoon.onMessage) {
                        await node.mknoon.onMessage({
                            from: msg.from,
                            to: getPeerId(node),
                            content: msg.message,
                            timestamp: msg.timestamp
                        });
                    }
                }
            }
        }
        catch (err) {
            console.warn('[Bridge] Inbox check failed:', err?.message ?? err);
        }
    }
    // Store node globally
    setNode(node);
    return {
        peerId: getPeerId(node),
        isStarted: true,
        listenAddresses: getListenAddresses(node),
        circuitAddresses,
        connections: [],
        registeredNamespaces: params.namespace ? [params.namespace] : []
    };
}
/**
 * Handle node:stop command
 */
export async function handleNodeStop(node, setNode) {
    if (!node) {
        return { stopped: false };
    }
    // Stop registration
    if (node.mknoon.registrationAbort) {
        node.mknoon.registrationAbort.abort();
        node.mknoon.registrationAbort = null;
    }
    await node.stop();
    setNode(null);
    return { stopped: true };
}
/**
 * Handle node:status command
 */
export function handleNodeStatus(node) {
    if (!node) {
        return {
            peerId: null,
            isStarted: false,
            listenAddresses: [],
            circuitAddresses: [],
            connections: [],
            registeredNamespaces: []
        };
    }
    const connections = node.getConnections().map(conn => ({
        peerId: conn.remotePeer.toString(),
        multiaddrs: [conn.remoteAddr.toString()],
        direction: conn.direction,
        status: 'connected'
    }));
    return {
        peerId: getPeerId(node),
        isStarted: node.status === 'started',
        listenAddresses: getListenAddresses(node),
        circuitAddresses: getCircuitAddresses(node),
        connections,
        registeredNamespaces: node.mknoon.rendezvousConfig
            ? [buildChatNamespace(getPeerId(node))]
            : []
    };
}
/**
 * Handle rendezvous:register command
 */
export async function handleRendezvousRegister(node, params) {
    if (!node) {
        throw new Error('Node not started');
    }
    const namespace = params.namespace || buildChatNamespace(getPeerId(node));
    const serverAddresses = params.serverAddresses || [
        '/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g'
    ];
    const rendezvousConfig = {
        serverAddresses,
        ttlSeconds: params.ttlSeconds,
        retryMs: params.retryMs
    };
    // Cancel existing registration if any
    if (node.mknoon.registrationAbort) {
        node.mknoon.registrationAbort.abort();
    }
    // Start new registration
    const abort = new AbortController();
    node.mknoon.registrationAbort = abort;
    void startRegistration(node, rendezvousConfig, namespace, abort.signal);
    return { registered: true, namespace };
}
/**
 * Handle rendezvous:discover command
 */
export async function handleRendezvousDiscover(node, params) {
    if (!node) {
        throw new Error('Node not started');
    }
    const targetPeerId = params.peerId;
    const namespace = params.namespace || (targetPeerId ? buildChatNamespace(targetPeerId) : undefined);
    if (!namespace) {
        throw new Error('Either namespace or peerId must be provided');
    }
    const serverAddresses = params.serverAddresses || [
        '/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g'
    ];
    const config = {
        serverAddresses,
        timeoutMs: params.timeoutMs,
        pollMs: params.pollMs
    };
    let peers;
    if (targetPeerId) {
        const peer = await discoverPeer(node, config, namespace, targetPeerId);
        peers = peer ? [peer] : [];
    }
    else {
        peers = await discoverAllPeers(node, config, namespace);
    }
    return {
        peers: peers.map(p => ({
            id: p.id.toString(),
            addresses: p.addresses.map(a => a.toString())
        }))
    };
}
/**
 * Handle peer:dial command
 */
export async function handlePeerDial(node, params) {
    if (!node) {
        throw new Error('Node not started');
    }
    const peerId = params.peerId;
    if (!peerId) {
        throw new Error('peerId is required');
    }
    let addresses = params.addresses;
    // If no addresses provided, try to discover via rendezvous
    if (!addresses || addresses.length === 0) {
        const namespace = params.namespace || buildChatNamespace(peerId);
        const serverAddresses = params.serverAddresses || [
            '/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g'
        ];
        const config = {
            serverAddresses,
            timeoutMs: params.timeoutMs,
            pollMs: params.pollMs
        };
        const discovered = await discoverPeer(node, config, namespace, peerId);
        if (!discovered) {
            throw new Error(`Could not discover peer ${peerId}`);
        }
        addresses = discovered.addresses.map(a => a.toString());
    }
    // Add to peerstore
    await addPeerToStore(node, peerId, addresses);
    // Dial the peer
    await dialPeer(node, peerId, addresses, params.timeoutMs);
    return { connected: true, peerId };
}
/**
 * Handle peer:disconnect command
 */
export async function handlePeerDisconnect(node, params) {
    if (!node) {
        throw new Error('Node not started');
    }
    const peerId = params.peerId;
    if (!peerId) {
        throw new Error('peerId is required');
    }
    await disconnectPeer(node, peerId);
    return { disconnected: true, peerId };
}
/**
 * Handle message:send command
 */
export async function handleMessageSend(node, params) {
    if (!node) {
        throw new Error('Node not started');
    }
    const peerId = params.peerId;
    const message = params.message;
    if (!peerId) {
        throw new Error('peerId is required');
    }
    if (!message) {
        throw new Error('message is required');
    }
    try {
        const reply = await sendMessage(node, peerId, message, params.timeoutMs);
        return { sent: true, reply, storedInInbox: false };
    }
    catch (err) {
        console.warn('[Bridge] Direct send failed:', err?.message ?? err);
        // Try to store in inbox for offline delivery
        const relayPeerId = node._relayPeerId;
        if (relayPeerId && params.fallbackToInbox !== false) {
            try {
                const response = await storeInInbox(node, peerIdFromString(relayPeerId), peerId, message);
                if (response.status === ResponseStatus.OK) {
                    console.log('[Bridge] Message stored in inbox for offline delivery');
                    return { sent: false, reply: null, storedInInbox: true };
                }
            }
            catch (inboxErr) {
                console.warn('[Bridge] Inbox store failed:', inboxErr?.message ?? inboxErr);
            }
        }
        throw err;
    }
}
/**
 * Handle inbox:check command
 */
export async function handleInboxCheck(node, params) {
    if (!node) {
        throw new Error('Node not started');
    }
    const relayPeerId = params.relayPeerId || node._relayPeerId;
    if (!relayPeerId) {
        throw new Error('No relay peer ID available');
    }
    const response = await retrieveFromInbox(node, peerIdFromString(relayPeerId), {
        limit: params.limit,
        peek: params.peek
    });
    if (response.status === ResponseStatus.OK) {
        return { messages: response.messages || [] };
    }
    else if (response.status === ResponseStatus.NO_MESSAGES) {
        return { messages: [] };
    }
    else {
        throw new Error(response.error || 'Failed to retrieve messages');
    }
}
/**
 * Handle inbox:store command
 */
export async function handleInboxStore(node, params) {
    if (!node) {
        throw new Error('Node not started');
    }
    const toPeerId = params.toPeerId;
    const message = params.message;
    if (!toPeerId) {
        throw new Error('toPeerId is required');
    }
    if (!message) {
        throw new Error('message is required');
    }
    const relayPeerId = params.relayPeerId || node._relayPeerId;
    if (!relayPeerId) {
        throw new Error('No relay peer ID available');
    }
    const response = await storeInInbox(node, peerIdFromString(relayPeerId), toPeerId, message, params.metadata);
    if (response.status === ResponseStatus.OK) {
        return { stored: true };
    }
    else {
        throw new Error(response.error || 'Failed to store message');
    }
}
//# sourceMappingURL=handlers.js.map