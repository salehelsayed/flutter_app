/**
 * core_lib_js/src/index.ts
 *
 * Main entry point - exports all P2P functionality
 */
// Types
export * from './types/p2p.js';
// Node creation and management
export { createNode, loadIdentity, getPeerId, getListenAddresses, getCircuitAddresses, hasCircuitAddresses, waitForCircuitAddresses } from './p2p/node.js';
// Rendezvous protocol
export { RENDEZVOUS_PROTOCOL, registerOnce, startRegistration, discoverFromPoint, discoverPeer, discoverAllPeers, buildChatNamespace } from './p2p/rendezvous.js';
// Listeners and connections
export { extractPeerIdFromAddr, dialRelay, setupListeners, dialPeer, addPeerToStore, getConnectedPeers, disconnectPeer } from './p2p/listeners.js';
// Message handlers
export { CHAT_PROTOCOL, encodeFrame, readOneFrame, writeOneFrame, setupChatHandler, setupConnectionListeners, sendMessage, removeChatHandler } from './p2p/handlers.js';
// Bridge
export { setNode, getNode, isNodeRunning, handleCommand, createRequest, execute } from './bridge/entry.js';
// Re-export handlers for advanced usage
export * as bridgeHandlers from './bridge/handlers.js';
// Browser-specific node creation
export { createBrowserNode, loadIdentityFromHex } from './p2p/node-browser.js';
// Hex utilities (works in both Node.js and browser)
export { hexToBytes, bytesToHex } from './utils/hex.js';
// Common utilities (browser-compatible)
export * from './p2p/utils.js';
//# sourceMappingURL=index.js.map