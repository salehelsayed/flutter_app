/**
 * core_lib_js/src/index.ts
 *
 * Main entry point - exports all P2P functionality
 */
export * from './types/p2p.js';
export { createNode, loadIdentity, getPeerId, getListenAddresses, getCircuitAddresses, hasCircuitAddresses, waitForCircuitAddresses } from './p2p/node.js';
export { RENDEZVOUS_PROTOCOL, registerOnce, startRegistration, discoverFromPoint, discoverPeer, discoverAllPeers, buildChatNamespace } from './p2p/rendezvous.js';
export { extractPeerIdFromAddr, dialRelay, setupListeners, dialPeer, addPeerToStore, getConnectedPeers, disconnectPeer } from './p2p/listeners.js';
export { CHAT_PROTOCOL, encodeFrame, readOneFrame, writeOneFrame, setupChatHandler, setupConnectionListeners, sendMessage, removeChatHandler } from './p2p/handlers.js';
export { setNode, getNode, isNodeRunning, handleCommand, createRequest, execute } from './bridge/entry.js';
export * as bridgeHandlers from './bridge/handlers.js';
export { createBrowserNode, loadIdentityFromHex } from './p2p/node-browser.js';
export { hexToBytes, bytesToHex } from './utils/hex.js';
export * from './p2p/utils.js';
//# sourceMappingURL=index.d.ts.map