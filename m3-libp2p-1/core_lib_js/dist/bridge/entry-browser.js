/**
 * bridge/entry-browser.ts
 *
 * Browser-specific entry point for WebView integration.
 * Uses browser-compatible node creation (no fs, tcp).
 */
import { createBrowserNode, getPeerId, getListenAddresses, getCircuitAddresses } from '../p2p/node-browser.js';
import { setupListeners, dialPeer, addPeerToStore, disconnectPeer } from '../p2p/listeners.js';
import { startRegistration, discoverPeer, discoverAllPeers, buildChatNamespace } from '../p2p/rendezvous.js';
import { setupChatHandler, setupConnectionListeners, sendMessage } from '../p2p/handlers.js';
// Global node instance
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
 * Send response to Flutter via channel
 */
function sendToFlutter(response) {
    const json = JSON.stringify(response);
    if (globalThis.FlutterChannel) {
        globalThis.FlutterChannel.postMessage(json);
    }
    else {
        console.log('[Bridge] Response:', json);
    }
}
/**
 * Handle a bridge request from Flutter
 */
export async function handleRequest(requestJson) {
    let request;
    try {
        request = JSON.parse(requestJson);
    }
    catch (err) {
        sendToFlutter({
            id: 'parse-error',
            success: false,
            error: `Failed to parse request: ${err?.message}`
        });
        return;
    }
    const { id, command, params } = request;
    try {
        let data;
        switch (command) {
            case 'node:start':
                data = await handleNodeStart(params);
                break;
            case 'node:stop':
                data = await handleNodeStop();
                break;
            case 'node:status':
                data = handleNodeStatus();
                break;
            case 'rendezvous:register':
                data = await handleRendezvousRegister(params);
                break;
            case 'rendezvous:discover':
                data = await handleRendezvousDiscover(params);
                break;
            case 'peer:dial':
                data = await handlePeerDial(params);
                break;
            case 'peer:disconnect':
                data = await handlePeerDisconnect(params);
                break;
            case 'message:send':
                data = await handleMessageSend(params);
                break;
            default:
                sendToFlutter({
                    id,
                    success: false,
                    error: `Unknown command: ${command}`
                });
                return;
        }
        sendToFlutter({ id, success: true, data });
    }
    catch (err) {
        sendToFlutter({
            id,
            success: false,
            error: err?.message ?? String(err)
        });
    }
}
// Command handlers
async function handleNodeStart(params) {
    if (!params.privateKeyHex) {
        throw new Error('privateKeyHex is required');
    }
    const node = await createBrowserNode({
        privateKeyHex: params.privateKeyHex,
        listenAddresses: params.listenAddresses,
        iceServers: params.iceServers
    });
    await node.start();
    // Setup listeners
    const relayAddresses = params.relayAddresses;
    const { circuitAddresses, relayPeerId } = await setupListeners(node, {
        relayAddresses,
        waitForCircuitMs: params.waitForCircuitMs
    });
    // Setup chat handler
    setupChatHandler(node, (msg) => {
        sendToFlutter({
            id: 'message:received',
            success: true,
            data: msg
        });
    });
    // Setup connection listeners
    setupConnectionListeners(node, (state) => sendToFlutter({ id: 'peer:connected', success: true, data: state }), (state) => sendToFlutter({ id: 'peer:disconnected', success: true, data: state }));
    node._relayPeerId = relayPeerId;
    // Auto-register on rendezvous if configured
    if (params.namespace || params.autoRegister !== false) {
        const namespace = params.namespace || buildChatNamespace(getPeerId(node));
        const rendezvousConfig = {
            serverAddresses: relayAddresses || [
                '/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g'
            ],
            ttlSeconds: params.ttlSeconds,
            retryMs: params.retryMs
        };
        const abort = new AbortController();
        node.mknoon.registrationAbort = abort;
        void startRegistration(node, rendezvousConfig, namespace, abort.signal);
    }
    globalNode = node;
    return {
        peerId: getPeerId(node),
        isStarted: true,
        listenAddresses: getListenAddresses(node),
        circuitAddresses,
        connections: [],
        registeredNamespaces: params.namespace ? [params.namespace] : []
    };
}
async function handleNodeStop() {
    if (!globalNode) {
        return { stopped: false };
    }
    if (globalNode.mknoon.registrationAbort) {
        globalNode.mknoon.registrationAbort.abort();
        globalNode.mknoon.registrationAbort = null;
    }
    await globalNode.stop();
    globalNode = null;
    return { stopped: true };
}
function handleNodeStatus() {
    if (!globalNode) {
        return {
            peerId: null,
            isStarted: false,
            listenAddresses: [],
            circuitAddresses: [],
            connections: [],
            registeredNamespaces: []
        };
    }
    const connections = globalNode.getConnections().map(conn => ({
        peerId: conn.remotePeer.toString(),
        multiaddrs: [conn.remoteAddr.toString()],
        direction: conn.direction,
        status: 'connected'
    }));
    return {
        peerId: getPeerId(globalNode),
        isStarted: globalNode.status === 'started',
        listenAddresses: getListenAddresses(globalNode),
        circuitAddresses: getCircuitAddresses(globalNode),
        connections,
        registeredNamespaces: globalNode.mknoon.rendezvousConfig
            ? [buildChatNamespace(getPeerId(globalNode))]
            : []
    };
}
async function handleRendezvousRegister(params) {
    if (!globalNode)
        throw new Error('Node not started');
    const namespace = params.namespace || buildChatNamespace(getPeerId(globalNode));
    const serverAddresses = params.serverAddresses || [
        '/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g'
    ];
    const rendezvousConfig = {
        serverAddresses,
        ttlSeconds: params.ttlSeconds,
        retryMs: params.retryMs
    };
    if (globalNode.mknoon.registrationAbort) {
        globalNode.mknoon.registrationAbort.abort();
    }
    const abort = new AbortController();
    globalNode.mknoon.registrationAbort = abort;
    void startRegistration(globalNode, rendezvousConfig, namespace, abort.signal);
    return { registered: true, namespace };
}
async function handleRendezvousDiscover(params) {
    if (!globalNode)
        throw new Error('Node not started');
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
        const peer = await discoverPeer(globalNode, config, namespace, targetPeerId);
        peers = peer ? [peer] : [];
    }
    else {
        peers = await discoverAllPeers(globalNode, config, namespace);
    }
    return {
        peers: peers.map(p => ({
            id: p.id.toString(),
            addresses: p.addresses.map(a => a.toString())
        }))
    };
}
async function handlePeerDial(params) {
    if (!globalNode)
        throw new Error('Node not started');
    const peerId = params.peerId;
    if (!peerId)
        throw new Error('peerId is required');
    let addresses = params.addresses;
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
        const discovered = await discoverPeer(globalNode, config, namespace, peerId);
        if (!discovered) {
            throw new Error(`Could not discover peer ${peerId}`);
        }
        addresses = discovered.addresses.map(a => a.toString());
    }
    await addPeerToStore(globalNode, peerId, addresses);
    await dialPeer(globalNode, peerId, addresses, params.timeoutMs);
    return { connected: true, peerId };
}
async function handlePeerDisconnect(params) {
    if (!globalNode)
        throw new Error('Node not started');
    const peerId = params.peerId;
    if (!peerId)
        throw new Error('peerId is required');
    await disconnectPeer(globalNode, peerId);
    return { disconnected: true, peerId };
}
async function handleMessageSend(params) {
    if (!globalNode)
        throw new Error('Node not started');
    const peerId = params.peerId;
    const message = params.message;
    if (!peerId)
        throw new Error('peerId is required');
    if (!message)
        throw new Error('message is required');
    const reply = await sendMessage(globalNode, peerId, message, params.timeoutMs);
    return { sent: true, reply, storedInInbox: false };
}
// Expose to global scope for WebView
;
globalThis.handleRequest = handleRequest;
globalThis.getNode = getNode;
globalThis.isNodeRunning = isNodeRunning;
//# sourceMappingURL=entry-browser.js.map