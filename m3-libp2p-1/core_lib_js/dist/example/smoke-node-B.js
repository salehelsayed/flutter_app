/**
 * smoke-node-B.ts
 *
 * Smoke test Node B - connects to Node A and exchanges messages.
 * Run smoke-node-A.ts first, then run this.
 *
 * Usage:
 *   npx tsx smoke-node-B.ts [credentials-path] [node-A-peer-id]
 *
 * Defaults:
 *   - Credentials: ../../../Creds_User_B.txt (PeerId: 12D3KooWCP1pBwwH1WoyqF6scuBny9T6JsdsEnDLQwVSpD6SJ8XR)
 *   - Target: 12D3KooWDto5miiRBpfUcZg1uozYNXUALGetBjtwmUEvuftMmRBc (Node A from Creds_User_A.txt)
 *
 * Environment variables:
 *   - TARGET_PEER_ID: Override the default target peer ID
 *
 * This smoke test validates:
 * - Node creation with credentials
 * - Relay connection and circuit address acquisition
 * - Rendezvous registration and peer discovery
 * - Chat protocol handler setup
 * - Connection event listeners
 * - Dialing a discovered peer
 * - Message sending and receiving with replies
 */
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
// Import directly from specific modules to avoid bridge/inbox dependency
import { createNode, getPeerId, getCircuitAddresses } from '../p2p/node.js';
import { startRegistration, discoverPeer, buildChatNamespace } from '../p2p/rendezvous.js';
import { setupListeners, dialPeer, addPeerToStore, getConnectedPeers } from '../p2p/listeners.js';
import { CHAT_PROTOCOL, setupChatHandler, setupConnectionListeners, sendMessage } from '../p2p/handlers.js';
// Configuration
const __dirname = dirname(fileURLToPath(import.meta.url));
// Default credentials path (same as node_B_receiver_rendezvous.js)
const DEFAULT_CREDS_PATH = new URL('../../../Creds_User_B.txt', import.meta.url);
// Default target peer ID - Node A's peer ID from Creds_User_A.txt
// PeerId: 12D3KooWDto5miiRBpfUcZg1uozYNXUALGetBjtwmUEvuftMmRBc
const DEFAULT_TARGET_PEER_ID = process.env.TARGET_PEER_ID ?? '12D3KooWDto5miiRBpfUcZg1uozYNXUALGetBjtwmUEvuftMmRBc';
const RELAY_ADDRESS = process.env.RELAY_ADDRESS ??
    '/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g';
const RENDEZVOUS_ADDRESSES = (process.env.RENDEZVOUS_ADDRESSES ?? RELAY_ADDRESS)
    .split(',')
    .map(s => s.trim())
    .filter(Boolean);
// Logger
function log(...args) {
    console.log('[Node-B]', ...args);
}
function warn(...args) {
    console.warn('[Node-B]', ...args);
}
// Parse command line arguments
function parseArgs() {
    const args = process.argv.slice(2);
    let credentialsPath;
    let targetPeerId;
    for (let i = 0; i < args.length; i++) {
        const arg = args[i];
        if (arg === '--creds' || arg === '-c') {
            credentialsPath = args[++i];
        }
        else if (arg === '--peer' || arg === '-p') {
            targetPeerId = args[++i];
        }
        else if (!arg.startsWith('-')) {
            if (!credentialsPath) {
                credentialsPath = arg;
            }
            else if (!targetPeerId) {
                targetPeerId = arg;
            }
        }
    }
    return { credentialsPath, targetPeerId };
}
// Validate that core exports are defined
function validateExports() {
    log('Validating exports...');
    const coreExports = {
        createNode,
        getPeerId,
        getCircuitAddresses,
        startRegistration,
        discoverPeer,
        buildChatNamespace,
        setupListeners,
        dialPeer,
        addPeerToStore,
        getConnectedPeers,
        CHAT_PROTOCOL,
        setupChatHandler,
        setupConnectionListeners,
        sendMessage
    };
    for (const [name, fn] of Object.entries(coreExports)) {
        if (fn === undefined)
            throw new Error(`Missing export: ${name}`);
    }
    log('All exports validated successfully!');
}
// Track test state
let messagesReceived = 0;
let messagesSent = 0;
let repliesReceived = 0;
let connectionsReceived = 0;
let discoverySucceeded = false;
let dialSucceeded = false;
// Sleep helper
function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}
// Main function
async function main() {
    const { credentialsPath: argCredentialsPath, targetPeerId: argTargetPeerId } = parseArgs();
    // Use provided path or default to Creds_User_B.txt
    const credentialsPath = argCredentialsPath ?? fileURLToPath(DEFAULT_CREDS_PATH);
    // Target peer ID can come from arg or env
    const targetPeerId = argTargetPeerId ?? DEFAULT_TARGET_PEER_ID;
    // Note: targetPeerId should now always have a value (from arg, env, or default)
    log(`Using credentials: ${credentialsPath}`);
    // Validate all exports work
    validateExports();
    // Create and start node
    log('Starting node...');
    const node = await createNode({
        credentialsPath: resolve(credentialsPath)
    });
    await node.start();
    const peerId = getPeerId(node);
    console.log('');
    console.log('='.repeat(60));
    console.log('NODE B STARTED');
    console.log('='.repeat(60));
    console.log(`PeerId: ${peerId}`);
    console.log(`Target (Node A): ${targetPeerId}`);
    console.log('='.repeat(60));
    console.log('');
    // Setup message handler
    const onMessage = (msg) => {
        messagesReceived++;
        console.log(`\n[RECEIVED] from ${msg.from.slice(0, 20)}...: ${msg.content}`);
    };
    setupChatHandler(node, onMessage);
    // Setup connection listeners
    const onConnect = (state) => {
        connectionsReceived++;
        log(`Peer connected: ${state.peerId.slice(0, 20)}...`);
    };
    const onDisconnect = (state) => {
        log(`Peer disconnected: ${state.peerId.slice(0, 20)}...`);
    };
    setupConnectionListeners(node, onConnect, onDisconnect);
    // Setup listeners and dial relay
    log('Connecting to relay...');
    const { circuitAddresses, relayPeerId } = await setupListeners(node, {
        relayAddresses: RENDEZVOUS_ADDRESSES
    });
    if (circuitAddresses.length === 0) {
        warn('No circuit addresses available - may not be reachable');
    }
    else {
        log(`Circuit addresses: ${circuitAddresses.length}`);
    }
    // Build namespace and register on rendezvous
    const myNamespace = buildChatNamespace(peerId);
    log(`My namespace: ${myNamespace}`);
    const rendezvousConfig = {
        serverAddresses: RENDEZVOUS_ADDRESSES,
        ttlSeconds: 2 * 60 * 60,
        retryMs: 5000,
        pollMs: 2000,
        timeoutMs: 60000
    };
    const registrationAbort = new AbortController();
    void startRegistration(node, rendezvousConfig, myNamespace, registrationAbort.signal);
    log('Registered on rendezvous');
    // Discover and connect to Node A
    const targetNamespace = buildChatNamespace(targetPeerId);
    log(`Target namespace: ${targetNamespace}`);
    log('Discovering Node A...');
    try {
        const discovered = await discoverPeer(node, rendezvousConfig, targetNamespace, targetPeerId);
        if (discovered) {
            discoverySucceeded = true;
            log('Discovered Node A addresses:');
            discovered.addresses.forEach(a => log(`  ${a.toString()}`));
            // Add to peerstore and dial
            log('Dialing Node A...');
            await addPeerToStore(node, targetPeerId, discovered.addresses);
            await dialPeer(node, targetPeerId, discovered.addresses);
            dialSucceeded = true;
            log('Connected to Node A!');
        }
        else {
            warn('Could not discover Node A - make sure smoke-node-A.ts is running');
        }
    }
    catch (err) {
        warn(`Discovery/dial failed: ${err?.message ?? err}`);
    }
    // If connected, send test messages
    if (dialSucceeded) {
        log('Sending test messages to Node A...');
        const testMessages = [
            'Hello from Node B! (smoke test 1/3)',
            'Second message from Node B (smoke test 2/3)',
            'Final message from Node B (smoke test 3/3)'
        ];
        for (const msg of testMessages) {
            try {
                const reply = await sendMessage(node, targetPeerId, msg);
                messagesSent++;
                repliesReceived++;
                log(`Sent: "${msg}"`);
                log(`Reply: "${reply}"`);
            }
            catch (err) {
                warn(`Failed to send message: ${err?.message ?? err}`);
            }
            // Small delay between messages
            await sleep(1000);
        }
    }
    // Print test results
    console.log('');
    console.log('='.repeat(60));
    console.log('SMOKE TEST RESULTS');
    console.log('='.repeat(60));
    console.log(`Discovery succeeded: ${discoverySucceeded ? 'YES' : 'NO'}`);
    console.log(`Dial succeeded: ${dialSucceeded ? 'YES' : 'NO'}`);
    console.log(`Messages sent: ${messagesSent}`);
    console.log(`Replies received: ${repliesReceived}`);
    console.log(`Messages received: ${messagesReceived}`);
    console.log(`Connections: ${connectionsReceived}`);
    console.log('');
    const testPassed = discoverySucceeded && dialSucceeded && messagesSent >= 3 && repliesReceived >= 3;
    if (testPassed) {
        console.log('SMOKE TEST PASSED!');
    }
    else {
        console.log('SMOKE TEST FAILED!');
    }
    console.log('='.repeat(60));
    console.log('');
    // Wait a bit to receive any additional messages
    log('Waiting 5 seconds for any additional messages...');
    await sleep(5000);
    // Cleanup
    registrationAbort.abort();
    await node.stop();
    process.exit(testPassed ? 0 : 1);
}
main().catch((err) => {
    console.error('Fatal error:', err);
    process.exit(1);
});
//# sourceMappingURL=smoke-node-B.js.map