/**
 * smoke-test-all.ts
 *
 * Combined smoke test that:
 * 1. Tests hex utilities
 * 2. Tests identity loading with hex (browser-compatible)
 * 3. Runs two nodes and verifies communication
 *
 * Usage:
 *   npx tsx src/example/smoke-test-all.ts
 */
import { fileURLToPath } from 'node:url';
import { readFile } from 'node:fs/promises';
// Import utilities
import { hexToBytes, bytesToHex } from '../utils/hex.js';
import { loadIdentityFromHex } from '../p2p/node-browser.js';
// Import p2p modules (avoiding bridge/handlers due to inbox dependency)
import { createNode, getPeerId } from '../p2p/node.js';
import { startRegistration, discoverPeer, buildChatNamespace } from '../p2p/rendezvous.js';
import { setupListeners, dialPeer, addPeerToStore } from '../p2p/listeners.js';
import { setupChatHandler, setupConnectionListeners, sendMessage } from '../p2p/handlers.js';
// Paths to credential files
const CREDS_A_PATH = new URL('../../../Creds_User_A.txt', import.meta.url);
const CREDS_B_PATH = new URL('../../../Creds_User_B.txt', import.meta.url);
const RELAY_ADDRESS = '/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g';
// Test results tracker
const results = [];
function log(prefix, ...args) {
    console.log(`[${prefix}]`, ...args);
}
function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}
// Extract private key hex from credentials file
function extractPrivateKeyHex(contents) {
    const match = contents.match(/Private Key \(64 bytes, hex\):\s*([0-9a-fA-F]+)/);
    if (!match) {
        throw new Error('Could not find private key in credentials file');
    }
    return match[1].trim();
}
// Test 1: Hex Utilities
async function testHexUtilities() {
    log('Test', '1. Testing hex utilities...');
    try {
        // Test hexToBytes
        const hex = '913fea6a43a3cbfd12216d4b2fad5dc3b17d618db05f2a866aa2a2d5ee26e7fd';
        const bytes = hexToBytes(hex);
        if (bytes.length !== 32) {
            throw new Error(`Expected 32 bytes, got ${bytes.length}`);
        }
        // Test bytesToHex (roundtrip)
        const roundtrip = bytesToHex(bytes);
        if (roundtrip !== hex) {
            throw new Error(`Roundtrip failed: ${roundtrip} !== ${hex}`);
        }
        // Test with 0x prefix
        const bytesWithPrefix = hexToBytes('0x' + hex);
        if (bytesToHex(bytesWithPrefix) !== hex) {
            throw new Error('Failed with 0x prefix');
        }
        // Test error cases
        try {
            hexToBytes('abc'); // odd length
            throw new Error('Should have thrown for odd length');
        }
        catch (e) {
            if (!e.message.includes('even length'))
                throw e;
        }
        try {
            hexToBytes('gggg'); // invalid hex
            throw new Error('Should have thrown for invalid hex');
        }
        catch (e) {
            if (!e.message.includes('Invalid hex'))
                throw e;
        }
        results.push({ test: 'Hex Utilities', passed: true });
        log('Test', '1. Hex utilities: PASSED');
    }
    catch (err) {
        results.push({ test: 'Hex Utilities', passed: false, error: err.message });
        log('Test', '1. Hex utilities: FAILED -', err.message);
    }
}
// Test 2: Identity Loading with Hex
async function testIdentityLoading() {
    log('Test', '2. Testing identity loading from hex...');
    try {
        const credsA = await readFile(fileURLToPath(CREDS_A_PATH), 'utf8');
        const privateKeyHex = extractPrivateKeyHex(credsA);
        const { privateKey, peerId } = loadIdentityFromHex(privateKeyHex);
        // Verify peer ID matches expected
        const expectedPeerId = '12D3KooWDto5miiRBpfUcZg1uozYNXUALGetBjtwmUEvuftMmRBc';
        if (peerId.toString() !== expectedPeerId) {
            throw new Error(`PeerId mismatch: ${peerId.toString()} !== ${expectedPeerId}`);
        }
        if (!privateKey) {
            throw new Error('Private key is null');
        }
        results.push({ test: 'Identity Loading', passed: true });
        log('Test', '2. Identity loading: PASSED');
        log('Test', `   PeerId: ${peerId.toString()}`);
    }
    catch (err) {
        results.push({ test: 'Identity Loading', passed: false, error: err.message });
        log('Test', '2. Identity loading: FAILED -', err.message);
    }
}
// Test 3: Two-node communication
async function testTwoNodeCommunication() {
    log('Test', '3. Testing two-node communication...');
    let nodeA = null;
    let nodeB = null;
    let abortA = null;
    let abortB = null;
    try {
        // Load credentials
        const credsAPath = fileURLToPath(CREDS_A_PATH);
        const credsBPath = fileURLToPath(CREDS_B_PATH);
        // Create Node A
        log('NodeA', 'Creating node...');
        nodeA = await createNode({ credentialsPath: credsAPath });
        await nodeA.start();
        const peerIdA = getPeerId(nodeA);
        log('NodeA', `Started: ${peerIdA}`);
        // Setup Node A message handler
        let nodeAReceivedMessage = false;
        setupChatHandler(nodeA, (msg) => {
            log('NodeA', `Received: "${msg.content}" from ${msg.from.slice(0, 20)}...`);
            nodeAReceivedMessage = true;
        });
        setupConnectionListeners(nodeA);
        // Connect Node A to relay
        log('NodeA', 'Connecting to relay...');
        const { circuitAddresses: circuitA, relayPeerId } = await setupListeners(nodeA, {
            relayAddresses: [RELAY_ADDRESS]
        });
        log('NodeA', `Circuit addresses: ${circuitA.length}`);
        // Register Node A on rendezvous
        const namespaceA = buildChatNamespace(peerIdA);
        const configA = {
            serverAddresses: [RELAY_ADDRESS],
            ttlSeconds: 300,
            retryMs: 5000
        };
        abortA = new AbortController();
        void startRegistration(nodeA, configA, namespaceA, abortA.signal);
        log('NodeA', `Registered on namespace: ${namespaceA}`);
        // Wait for registration to propagate
        await sleep(3000);
        // Create Node B
        log('NodeB', 'Creating node...');
        nodeB = await createNode({ credentialsPath: credsBPath });
        await nodeB.start();
        const peerIdB = getPeerId(nodeB);
        log('NodeB', `Started: ${peerIdB}`);
        // Setup Node B
        setupChatHandler(nodeB);
        setupConnectionListeners(nodeB);
        // Connect Node B to relay
        log('NodeB', 'Connecting to relay...');
        const { circuitAddresses: circuitB } = await setupListeners(nodeB, {
            relayAddresses: [RELAY_ADDRESS]
        });
        log('NodeB', `Circuit addresses: ${circuitB.length}`);
        // Register Node B
        const namespaceB = buildChatNamespace(peerIdB);
        abortB = new AbortController();
        void startRegistration(nodeB, configA, namespaceB, abortB.signal);
        log('NodeB', `Registered on namespace: ${namespaceB}`);
        // Discover Node A from Node B
        log('NodeB', 'Discovering Node A...');
        const discoveryConfig = {
            serverAddresses: [RELAY_ADDRESS],
            timeoutMs: 30000,
            pollMs: 2000
        };
        const discovered = await discoverPeer(nodeB, discoveryConfig, namespaceA, peerIdA);
        if (!discovered) {
            throw new Error('Could not discover Node A');
        }
        log('NodeB', `Discovered Node A with ${discovered.addresses.length} addresses`);
        // Dial Node A
        log('NodeB', 'Dialing Node A...');
        await addPeerToStore(nodeB, peerIdA, discovered.addresses);
        await dialPeer(nodeB, peerIdA, discovered.addresses);
        log('NodeB', 'Connected to Node A!');
        // Send message from B to A
        log('NodeB', 'Sending message to Node A...');
        const reply = await sendMessage(nodeB, peerIdA, 'Hello from Node B! (smoke test)');
        log('NodeB', `Reply: "${reply}"`);
        // Wait for message processing
        await sleep(2000);
        // Verify results
        const nodeBConnected = nodeB.getConnections().some(c => c.remotePeer.toString() === peerIdA);
        const replyReceived = reply.includes('received');
        if (!nodeBConnected) {
            throw new Error('Node B not connected to Node A');
        }
        if (!replyReceived) {
            throw new Error('Did not receive proper reply');
        }
        if (!nodeAReceivedMessage) {
            throw new Error('Node A did not receive message');
        }
        results.push({ test: 'Two-Node Communication', passed: true });
        log('Test', '3. Two-node communication: PASSED');
    }
    catch (err) {
        results.push({ test: 'Two-Node Communication', passed: false, error: err.message });
        log('Test', '3. Two-node communication: FAILED -', err.message);
    }
    finally {
        // Cleanup
        if (abortA)
            abortA.abort();
        if (abortB)
            abortB.abort();
        try {
            if (nodeB)
                await nodeB.stop();
        }
        catch { }
        try {
            if (nodeA)
                await nodeA.stop();
        }
        catch { }
    }
}
// Main
async function main() {
    console.log('');
    console.log('='.repeat(60));
    console.log('SMOKE TEST - core_lib_js');
    console.log('='.repeat(60));
    console.log('');
    // Run tests
    await testHexUtilities();
    await testIdentityLoading();
    await testTwoNodeCommunication();
    // Print summary
    console.log('');
    console.log('='.repeat(60));
    console.log('RESULTS SUMMARY');
    console.log('='.repeat(60));
    const passed = results.filter(r => r.passed).length;
    const total = results.length;
    for (const r of results) {
        const status = r.passed ? 'PASS' : 'FAIL';
        console.log(`  [${status}] ${r.test}${r.error ? ` - ${r.error}` : ''}`);
    }
    console.log('');
    console.log(`Total: ${passed}/${total} tests passed`);
    console.log('='.repeat(60));
    console.log('');
    process.exit(passed === total ? 0 : 1);
}
main().catch((err) => {
    console.error('Fatal error:', err);
    process.exit(1);
});
//# sourceMappingURL=smoke-test-all.js.map