/**
 * smoke-node-A.ts
 *
 * Smoke test Node A - waits for Node B to connect and receives messages.
 * Run this first, then run smoke-node-B.ts.
 *
 * Usage:
 *   npx tsx smoke-node-A.ts [credentials-path]
 *
 * Defaults:
 *   - Credentials: ../../../Creds_User_A.txt (PeerId: 12D3KooWDto5miiRBpfUcZg1uozYNXUALGetBjtwmUEvuftMmRBc)
 *
 * This smoke test validates:
 * - Node creation with credentials
 * - Relay connection and circuit address acquisition
 * - Rendezvous registration
 * - Chat protocol handler setup
 * - Connection event listeners
 * - Message sending and receiving
 */
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
// Import directly from specific modules to avoid bridge/inbox dependency
import { createNode, getPeerId, getCircuitAddresses } from '../p2p/node.js';
import { startRegistration, buildChatNamespace } from '../p2p/rendezvous.js';
import { setupListeners, getConnectedPeers } from '../p2p/listeners.js';
import { CHAT_PROTOCOL, setupChatHandler, setupConnectionListeners, sendMessage } from '../p2p/handlers.js';
// Configuration
const __dirname = dirname(fileURLToPath(import.meta.url));
// Default credentials path (same as node_A_sender_rendezvous.js)
// Uses Creds_User_A.txt which generates PeerId: 12D3KooWDto5miiRBpfUcZg1uozYNXUALGetBjtwmUEvuftMmRBc
const DEFAULT_CREDS_PATH = new URL('../../../Creds_User_A.txt', import.meta.url);
const RELAY_ADDRESS = process.env.RELAY_ADDRESS ??
    '/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g';
const RENDEZVOUS_ADDRESSES = (process.env.RENDEZVOUS_ADDRESSES ?? RELAY_ADDRESS)
    .split(',')
    .map(s => s.trim())
    .filter(Boolean);
// Logger
function log(...args) {
    console.log('[Node-A]', ...args);
}
function warn(...args) {
    console.warn('[Node-A]', ...args);
}
// Parse command line arguments
function parseArgs() {
    const args = process.argv.slice(2);
    let credentialsPath;
    for (let i = 0; i < args.length; i++) {
        const arg = args[i];
        if (arg === '--creds' || arg === '-c') {
            credentialsPath = args[++i];
        }
        else if (!arg.startsWith('-')) {
            if (!credentialsPath) {
                credentialsPath = arg;
            }
        }
    }
    return { credentialsPath };
}
// Validate that core exports are defined
function validateExports() {
    log('Validating exports...');
    const coreExports = {
        createNode,
        getPeerId,
        getCircuitAddresses,
        startRegistration,
        buildChatNamespace,
        setupListeners,
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
let connectionsReceived = 0;
let testPassed = false;
// Main function
async function main() {
    const { credentialsPath: argCredentialsPath } = parseArgs();
    // Use provided path or default to Creds_User_A.txt
    const credentialsPath = argCredentialsPath ?? fileURLToPath(DEFAULT_CREDS_PATH);
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
    console.log('NODE A STARTED');
    console.log('='.repeat(60));
    console.log(`PeerId: ${peerId}`);
    console.log('');
    console.log('Now run smoke-node-B.ts with this peer ID:');
    console.log(`  npx tsx smoke-node-B.ts <creds-B> ${peerId}`);
    console.log('='.repeat(60));
    console.log('');
    // Setup message handler
    const onMessage = (msg) => {
        messagesReceived++;
        console.log(`\n[RECEIVED] from ${msg.from.slice(0, 20)}...: ${msg.content}`);
        if (msg.content.includes('Hello from Node B')) {
            log('Smoke test message received from Node B!');
        }
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
    log(`Namespace: ${myNamespace}`);
    const rendezvousConfig = {
        serverAddresses: RENDEZVOUS_ADDRESSES,
        ttlSeconds: 2 * 60 * 60,
        retryMs: 5000
    };
    const registrationAbort = new AbortController();
    void startRegistration(node, rendezvousConfig, myNamespace, registrationAbort.signal);
    log('Registered on rendezvous');
    // Wait for messages from Node B
    log('Waiting for Node B to connect...');
    log('(Press Ctrl+C to exit)');
    // Check test status periodically
    const checkInterval = setInterval(() => {
        const peers = getConnectedPeers(node, relayPeerId ? [relayPeerId] : []);
        if (peers.length > 0) {
            log(`Connected peers: ${peers.length}`);
        }
        if (messagesReceived > 0 && !testPassed) {
            testPassed = true;
            console.log('');
            console.log('='.repeat(60));
            console.log('SMOKE TEST PASSED!');
            console.log(`Messages received: ${messagesReceived}`);
            console.log(`Connections received: ${connectionsReceived}`);
            console.log('='.repeat(60));
            console.log('');
            log('Waiting for more messages or Ctrl+C to exit...');
        }
    }, 5000);
    // Graceful shutdown
    const shutdown = async () => {
        clearInterval(checkInterval);
        registrationAbort.abort();
        console.log('');
        console.log('='.repeat(60));
        if (testPassed) {
            console.log('SMOKE TEST COMPLETED SUCCESSFULLY');
        }
        else {
            console.log('SMOKE TEST ENDED (no messages received)');
        }
        console.log(`Total messages received: ${messagesReceived}`);
        console.log(`Total connections: ${connectionsReceived}`);
        console.log('='.repeat(60));
        await node.stop();
        process.exit(testPassed ? 0 : 1);
    };
    process.on('SIGINT', shutdown);
    process.on('SIGTERM', shutdown);
}
main().catch((err) => {
    console.error('Fatal error:', err);
    process.exit(1);
});
//# sourceMappingURL=smoke-node-A.js.map