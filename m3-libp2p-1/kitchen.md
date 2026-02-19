 Directory Structure

  core_lib_js/
  ├── package.json                    # Dependencies and scripts
  ├── tsconfig.json                   # TypeScript configuration
  └── src/
      ├── index.ts                    # Main exports
      ├── types/
      │   └── p2p.ts                  # TypeScript interfaces
      ├── p2p/
      │   ├── node.ts                 # createNode(), loadIdentity(), waitForCircuitAddresses()
      │   ├── rendezvous.ts           # registerOnce(), startRegistration(), discoverPeer()
      │   ├── listeners.ts            # setupListeners(), dialPeer(), dialRelay()
      │   └── handlers.ts             # setupChatHandler(), sendMessage(), encodeFrame()
      ├── bridge/
      │   ├── entry.ts                # handleCommand(), execute() - command routing
      │   └── handlers.ts             # Individual command handlers (node:start, message:send, etc.)
      └── example/
          └── unified-node.ts         # Complete working example

  Also Created

  node_unified.js - A ready-to-run JavaScript file (no TypeScript compilation needed) that combines all
  functionality from node_A and node_B.

  Usage

  TypeScript (after building):
  cd core_lib_js
  npm install
  npm run build
  npx tsx src/example/unified-node.ts ./Creds_User_A.txt

  JavaScript (immediate use):
  node node_unified.js ./Creds_User_A.txt                      # Wait for connections
  node node_unified.js ./Creds_User_A.txt 12D3KooW...          # Connect to peer
  node node_unified.js ./Creds_User_A.txt 12D3KooW... "Hello!" # One-shot message

  Key Features
  ┌──────────────────────────┬────────────────────────────────────────────────────┐
  │         Feature          │                   Implementation                   │
  ├──────────────────────────┼────────────────────────────────────────────────────┤
  │ Register on rendezvous   │ startRegistration() runs in background             │
  ├──────────────────────────┼────────────────────────────────────────────────────┤
  │ Discover peers           │ discoverPeer() queries all rendezvous points       │
  ├──────────────────────────┼────────────────────────────────────────────────────┤
  │ Handle incoming messages │ setupChatHandler() with callback                   │
  ├──────────────────────────┼────────────────────────────────────────────────────┤
  │ Send messages            │ sendMessage() with timeout                         │
  ├──────────────────────────┼────────────────────────────────────────────────────┤
  │ Inbox check on startup   │ Automatic in handleNodeStart()                     │
  ├──────────────────────────┼────────────────────────────────────────────────────┤
  │ Offline fallback         │ sendWithFallback() stores in inbox if direct fails │
  └──────────────────────────┴────────────────────────────────────────────────────┘

