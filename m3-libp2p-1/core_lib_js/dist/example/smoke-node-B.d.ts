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
export {};
//# sourceMappingURL=smoke-node-B.d.ts.map