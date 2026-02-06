/**
 * example/unified-node.ts
 *
 * Complete unified P2P node that combines sender and receiver functionality.
 * This node can:
 * - Register on rendezvous (so others can find it)
 * - Discover other peers (to send messages)
 * - Receive incoming messages
 * - Send outgoing messages
 * - Check inbox for offline messages
 * - Store messages in inbox when peer is offline
 */
import { createInterface } from 'node:readline';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { createNode, getPeerId, setupListeners, setupChatHandler, setupConnectionListeners, startRegistration, discoverPeer, dialPeer, addPeerToStore, sendMessage, buildChatNamespace, getConnectedPeers } from '../index.js';
import { storeInInbox, retrieveFromInbox, ResponseStatus } from '../inbox.js';
import { peerIdFromString } from '@libp2p/peer-id';
// Configuration
const __dirname = dirname(fileURLToPath(import.meta.url));
const RELAY_ADDRESS = process.env.RELAY_ADDRESS ??
    '/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g';
const RELAY_PEER_ID = RELAY_ADDRESS.match(/\/p2p\/([^/]+)$/)?.[1] ?? null;
const RENDEZVOUS_ADDRESSES = (process.env.RENDEZVOUS_ADDRESSES ?? RELAY_ADDRESS)
    .split(',')
    .map(s => s.trim())
    .filter(Boolean);
// Parse command line arguments
function parseArgs() {
    const args = process.argv.slice(2);
    let credentialsPath;
    let targetPeerId;
    let message;
    for (let i = 0; i < args.length; i++) {
        const arg = args[i];
        if (arg === '--creds' || arg === '-c') {
            credentialsPath = args[++i];
        }
        else if (arg === '--peer' || arg === '-p') {
            targetPeerId = args[++i];
        }
        else if (arg === '--message' || arg === '-m') {
            message = args.slice(i + 1).join(' ');
            break;
        }
        else if (!arg.startsWith('-')) {
            // First positional arg is credentials path
            if (!credentialsPath) {
                credentialsPath = arg;
            }
            else if (!targetPeerId) {
                targetPeerId = arg;
            }
        }
    }
    return { credentialsPath, targetPeerId, message };
}
// Logger
function log(...args) {
    console.log('[Node]', ...args);
}
function warn(...args) {
    console.warn('[Node]', ...args);
}
// Check inbox for offline messages
async function checkInbox(node) {
    if (!RELAY_PEER_ID) {
        log('No relay peer ID, skipping inbox check');
        return;
    }
    try {
        const response = await retrieveFromInbox(node, peerIdFromString(RELAY_PEER_ID));
        if (response.status === ResponseStatus.OK && response.messages?.length > 0) {
            log(`Received ${response.messages.length} offline message(s):`);
            for (const msg of response.messages) {
                const time = new Date(msg.timestamp).toLocaleTimeString();
                console.log(`  [${time}] from ${msg.from.slice(0, 20)}...: ${msg.message}`);
            }
        }
        else if (response.status === ResponseStatus.NO_MESSAGES) {
            log('No offline messages');
        }
    }
    catch (err) {
        warn(`Inbox check failed: ${err?.message ?? err}`);
    }
}
// Store message for offline delivery
async function storeOfflineMessage(node, toPeerId, message) {
    if (!RELAY_PEER_ID) {
        warn('No relay peer ID for inbox');
        return false;
    }
    try {
        const response = await storeInInbox(node, peerIdFromString(RELAY_PEER_ID), toPeerId, message);
        if (response.status === ResponseStatus.OK) {
            log('Message stored in inbox for offline delivery');
            return true;
        }
        warn(`Inbox store failed: ${response.error ?? 'unknown error'}`);
        return false;
    }
    catch (err) {
        warn(`Inbox store error: ${err?.message ?? err}`);
        return false;
    }
}
// Send message with offline fallback
async function sendMessageWithFallback(node, targetPeerId, message) {
    try {
        const reply = await sendMessage(node, targetPeerId, message);
        console.log(`[Reply] ${reply}`);
    }
    catch (err) {
        console.log('\n===== DIRECT SEND FAILED =====');
        warn(err?.message ?? err);
        // Try inbox fallback
        log('Attempting to store in inbox for offline delivery...');
        const stored = await storeOfflineMessage(node, targetPeerId, message);
        if (stored) {
            console.log('===== MESSAGE STORED IN INBOX =====\n');
        }
    }
}
// Main function
async function main() {
    const { credentialsPath, targetPeerId, message: oneShotMessage } = parseArgs();
    if (!credentialsPath) {
        console.log('Usage: npx ts-node unified-node.ts <credentials-path> [target-peer-id] [--message "msg"]');
        console.log('');
        console.log('Options:');
        console.log('  --creds, -c <path>    Path to credentials file');
        console.log('  --peer, -p <id>       Target peer ID to connect to');
        console.log('  --message, -m <msg>   One-shot message (exits after sending)');
        console.log('');
        console.log('Environment variables:');
        console.log('  RELAY_ADDRESS         Relay/rendezvous server address');
        console.log('  RENDEZVOUS_ADDRESSES  Comma-separated rendezvous addresses');
        process.exit(1);
    }
    // Create and start node
    log('Starting node...');
    const node = await createNode({
        credentialsPath: resolve(credentialsPath)
    });
    await node.start();
    const peerId = getPeerId(node);
    log(`PeerId: ${peerId}`);
    // Setup message handler
    const onMessage = (msg) => {
        console.log(`\n[${msg.from.slice(0, 20)}...] ${msg.content}`);
    };
    setupChatHandler(node, onMessage);
    // Track connected peers
    const connectedPeers = new Map();
    const onConnect = (state) => {
        connectedPeers.set(state.peerId, true);
    };
    const onDisconnect = (state) => {
        connectedPeers.delete(state.peerId);
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
    // Check inbox for offline messages
    await checkInbox(node);
    // Build namespace (use own peer ID so others can find us)
    const myNamespace = buildChatNamespace(peerId);
    log(`Namespace: ${myNamespace}`);
    // Register on rendezvous
    const rendezvousConfig = {
        serverAddresses: RENDEZVOUS_ADDRESSES,
        ttlSeconds: 2 * 60 * 60, // 2 hours
        retryMs: 5000
    };
    const registrationAbort = new AbortController();
    void startRegistration(node, rendezvousConfig, myNamespace, registrationAbort.signal);
    log('Registered on rendezvous');
    // If target peer specified, discover and connect
    if (targetPeerId) {
        log(`Target peer: ${targetPeerId}`);
        const targetNamespace = buildChatNamespace(targetPeerId);
        log('Discovering target peer...');
        try {
            const discovered = await discoverPeer(node, rendezvousConfig, targetNamespace, targetPeerId);
            if (discovered) {
                log('Discovered peer addresses:');
                discovered.addresses.forEach(a => log(`  ${a.toString()}`));
                await addPeerToStore(node, targetPeerId, discovered.addresses);
                await dialPeer(node, targetPeerId, discovered.addresses);
                log('Connected to target peer');
            }
            else {
                warn('Could not discover target peer');
            }
        }
        catch (err) {
            warn(`Discovery/dial failed: ${err?.message ?? err}`);
        }
    }
    // One-shot message mode
    if (oneShotMessage && targetPeerId) {
        await sendMessageWithFallback(node, targetPeerId, oneShotMessage);
        await node.stop();
        process.exit(0);
    }
    // Interactive mode
    const rl = createInterface({ input: process.stdin, output: process.stdout });
    console.log('');
    console.log('Commands:');
    console.log('  /send <peer-id> <message>  Send to specific peer');
    console.log('  /dial <peer-id>            Discover and connect to peer');
    console.log('  /peers                     List connected peers');
    console.log('  /inbox                     Check inbox');
    console.log('  /exit                      Quit');
    console.log('');
    console.log('Or just type a message to send to target peer (if connected)');
    console.log('');
    let pending = Promise.resolve();
    rl.on('line', (line) => {
        const input = line.trim();
        if (!input)
            return;
        pending = pending.then(async () => {
            // Parse commands
            if (input.startsWith('/')) {
                const [cmd, ...args] = input.slice(1).split(' ');
                switch (cmd) {
                    case 'exit':
                    case 'quit':
                        rl.close();
                        return;
                    case 'peers':
                        const peers = getConnectedPeers(node, relayPeerId ? [relayPeerId] : []);
                        if (peers.length === 0) {
                            log('No peers connected');
                        }
                        else {
                            log('Connected peers:');
                            peers.forEach(p => log(`  ${p}`));
                        }
                        return;
                    case 'inbox':
                        await checkInbox(node);
                        return;
                    case 'dial':
                        if (!args[0]) {
                            warn('Usage: /dial <peer-id>');
                            return;
                        }
                        const dialPeerId = args[0];
                        try {
                            const ns = buildChatNamespace(dialPeerId);
                            log(`Discovering ${dialPeerId}...`);
                            const disc = await discoverPeer(node, rendezvousConfig, ns, dialPeerId);
                            if (disc) {
                                await addPeerToStore(node, dialPeerId, disc.addresses);
                                await dialPeer(node, dialPeerId, disc.addresses);
                                log(`Connected to ${dialPeerId}`);
                            }
                            else {
                                warn('Could not discover peer');
                            }
                        }
                        catch (err) {
                            warn(`Dial failed: ${err?.message ?? err}`);
                        }
                        return;
                    case 'send':
                        if (args.length < 2) {
                            warn('Usage: /send <peer-id> <message>');
                            return;
                        }
                        const sendTo = args[0];
                        const sendMsg = args.slice(1).join(' ');
                        await sendMessageWithFallback(node, sendTo, sendMsg);
                        return;
                    default:
                        warn(`Unknown command: ${cmd}`);
                        return;
                }
            }
            // Send to target peer if connected
            if (targetPeerId) {
                await sendMessageWithFallback(node, targetPeerId, input);
            }
            else {
                warn('No target peer. Use /send <peer-id> <message> or /dial <peer-id>');
            }
        }).catch(err => {
            console.error('Error:', err);
        });
    });
    // Graceful shutdown
    const shutdown = async () => {
        registrationAbort.abort();
        rl.close();
        await pending;
        await node.stop();
        process.exit(0);
    };
    process.on('SIGINT', shutdown);
    process.on('SIGTERM', shutdown);
    rl.on('close', shutdown);
}
main().catch((err) => {
    console.error('Fatal error:', err);
    process.exit(1);
});
//# sourceMappingURL=unified-node.js.map