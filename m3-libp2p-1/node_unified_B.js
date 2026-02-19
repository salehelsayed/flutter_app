/**
 * node_unified_B.js — Inbox Smoke Test (Receiver)
 *
 * Connects as User B, retrieves messages from inbox on the relay.
 * Run this AFTER Node A has stored a message.
 *
 * Usage:
 *   node node_unified_B.js              # Retrieve and consume messages
 *   node node_unified_B.js --peek       # Peek without consuming
 *
 * After retrieving, enters interactive mode for additional commands.
 */

import { readFile } from 'fs/promises'
import { createInterface } from 'node:readline'
import { createLibp2p } from 'libp2p'
import { noise } from '@chainsafe/libp2p-noise'
import { yamux } from '@chainsafe/libp2p-yamux'
import { circuitRelayTransport } from '@libp2p/circuit-relay-v2'
import { identify, identifyPush } from '@libp2p/identify'
import { ping } from '@libp2p/ping'
import { dcutr } from '@libp2p/dcutr'
import { webSockets } from '@libp2p/websockets'
import { webRTC } from '@libp2p/webrtc'
import { tcp } from '@libp2p/tcp'
import { privateKeyFromRaw } from '@libp2p/crypto/keys'
import { peerIdFromPrivateKey, peerIdFromString } from '@libp2p/peer-id'
import { multiaddr } from '@multiformats/multiaddr'
import { storeInInbox, retrieveFromInbox, ResponseStatus } from './core_lib_js/dist/inbox.js'

// ============================================================================
// Configuration
// ============================================================================

const CREDS_PATH = './Creds_User_B.txt'
const PEER_A_ID = '12D3KooWDto5miiRBpfUcZg1uozYNXUALGetBjtwmUEvuftMmRBc'

const RELAY_ADDRESS = '/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g'
const RELAY_PEER_ID = '12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g'

const RELAY_TIMEOUT_MS = 30000

// ============================================================================
// Helpers
// ============================================================================

const log = (...args) => console.log('[B]', ...args)
const warn = (...args) => console.warn('[B]', ...args)
const step = (n, msg) => console.log(`\n  [${n}] ${msg}`)

function extractPrivateKeyHex(contents) {
  const match = contents.match(/Private Key \(64 bytes, hex\):\s*([0-9a-fA-F]+)/)
  if (!match) throw new Error('Could not find private key in credentials file')
  return match[1].trim()
}

function getCircuitAddresses(node) {
  return node.getMultiaddrs().filter(ma => ma.toString().includes('/p2p-circuit'))
}

async function waitForCircuitAddresses(node, timeoutMs) {
  const existing = getCircuitAddresses(node)
  if (existing.length > 0) return existing

  return new Promise((resolve, reject) => {
    const onUpdate = () => {
      const addrs = getCircuitAddresses(node)
      if (addrs.length > 0) { cleanup(); resolve(addrs) }
    }
    const timer = setTimeout(() => { cleanup(); reject(new Error('Timeout waiting for circuit address')) }, timeoutMs)
    const cleanup = () => { clearTimeout(timer); node.removeEventListener('self:peer:update', onUpdate) }
    node.addEventListener('self:peer:update', onUpdate)
  })
}

// ============================================================================
// Main
// ============================================================================

async function main() {
  const peekMode = process.argv.includes('--peek')

  console.log('='.repeat(60))
  console.log('  INBOX SMOKE TEST — Node B (Receiver)')
  console.log('='.repeat(60))

  // Step 1: Load identity
  step(1, 'Loading identity from ' + CREDS_PATH)
  const contents = await readFile(CREDS_PATH, 'utf8')
  const privateKeyHex = extractPrivateKeyHex(contents)
  const privateKeyBytes = Uint8Array.from(Buffer.from(privateKeyHex, 'hex'))
  const privateKey = privateKeyFromRaw(privateKeyBytes)
  const peerId = peerIdFromPrivateKey(privateKey)
  log(`Peer ID: ${peerId.toString()}`)

  // Step 2: Create node
  step(2, 'Creating libp2p node...')
  const node = await createLibp2p({
    privateKey,
    addresses: {
      listen: ['/p2p-circuit', '/ip4/0.0.0.0/tcp/0']
    },
    transports: [
      webSockets(),
      tcp(),
      webRTC({
        rtcConfiguration: {
          iceServers: [{
            urls: ['stun:mknoun.xyz:3478', 'turn:mknoun.xyz:3478?transport=udp', 'turn:mknoun.xyz:3478?transport=tcp'],
            username: 'testuser',
            credential: 'testpass'
          }]
        }
      }),
      circuitRelayTransport({ discoverRelays: 0 })
    ],
    connectionEncrypters: [noise()],
    streamMuxers: [yamux()],
    services: {
      identify: identify(),
      identifyPush: identifyPush(),
      ping: ping(),
      dcutr: dcutr()
    }
  })

  await node.start()
  log('Node started')

  // Step 3: Connect to relay
  step(3, 'Connecting to relay...')
  try {
    await node.dial(multiaddr(RELAY_ADDRESS), { signal: AbortSignal.timeout(20000) })
    log('Relay connected')
  } catch (err) {
    warn(`Relay connection failed: ${err?.message ?? err}`)
    process.exit(1)
  }

  // Step 4: Wait for circuit address
  step(4, 'Waiting for circuit address...')
  try {
    const circuitAddrs = await waitForCircuitAddresses(node, RELAY_TIMEOUT_MS)
    log(`Got ${circuitAddrs.length} circuit address(es)`)
  } catch (err) {
    warn(`No circuit addresses: ${err?.message ?? err}`)
  }

  // Step 5: Retrieve messages from inbox
  step(5, `Retrieving inbox messages${peekMode ? ' (peek — won\'t consume)' : ' (will consume)'}...`)
  try {
    const result = await retrieveFromInbox(node, peerIdFromString(RELAY_PEER_ID), { peek: peekMode })

    if (result.status === ResponseStatus.OK && result.messages.length > 0) {
      console.log(`\n  ✓ GOT ${result.messages.length} MESSAGE(S):`)
      console.log('  ' + '-'.repeat(50))
      for (const msg of result.messages) {
        const time = new Date(msg.timestamp).toLocaleString()
        const fromLabel = msg.from === PEER_A_ID ? 'User A' : msg.from.slice(0, 20) + '...'
        console.log(`  From:    ${fromLabel}`)
        console.log(`  Time:    ${time}`)
        console.log(`  Message: ${msg.message}`)
        if (msg.metadata && Object.keys(msg.metadata).length > 0) {
          console.log(`  Meta:    ${JSON.stringify(msg.metadata)}`)
        }
        console.log('  ' + '-'.repeat(50))
      }
      if (!peekMode) {
        console.log('  (Messages consumed — re-retrieve will be empty)')
      }
    } else if (result.status === ResponseStatus.NO_MESSAGES) {
      console.log('\n  — No messages in inbox')
      console.log('  Tip: Run node_unified_A.js first to store a message')
    } else {
      console.log(`\n  ✗ RETRIEVE FAILED: ${result.status} — ${result.error || 'unknown'}`)
    }
  } catch (err) {
    console.log(`\n  ✗ RETRIEVE ERROR: ${err?.message ?? err}`)
  }

  // Step 6: Verify inbox is empty after consume (unless peek)
  if (!peekMode) {
    step(6, 'Verifying inbox is now empty...')
    try {
      const verify = await retrieveFromInbox(node, peerIdFromString(RELAY_PEER_ID), { peek: true })
      if (verify.status === ResponseStatus.NO_MESSAGES || verify.messages.length === 0) {
        console.log('  ✓ Inbox is empty after retrieval — consume worked')
      } else {
        console.log(`  ⚠ Inbox still has ${verify.messages.length} message(s)`)
      }
    } catch (err) {
      warn(`Verify error: ${err?.message ?? err}`)
    }
  }

  // Interactive mode
  console.log('\n' + '-'.repeat(60))
  console.log('  Interactive mode — commands:')
  console.log('    inbox:check              Peek at inbox (no consume)')
  console.log('    inbox:retrieve           Retrieve and consume inbox')
  console.log('    inbox:store <message>    Store a message for A')
  console.log('    /exit                    Quit')
  console.log('-'.repeat(60) + '\n')

  const rl = createInterface({ input: process.stdin, output: process.stdout })
  let pending = Promise.resolve()

  rl.on('line', (line) => {
    const input = line.trim()
    if (!input) return

    pending = pending.then(async () => {
      if (input === '/exit' || input === '/quit') {
        rl.close()
        return
      }

      if (input === 'inbox:check') {
        try {
          const result = await retrieveFromInbox(node, peerIdFromString(RELAY_PEER_ID), { peek: true })
          log(`Status: ${result.status}, messages: ${result.messages.length}`)
          for (const msg of result.messages) {
            const time = new Date(msg.timestamp).toLocaleTimeString()
            log(`  [${time}] from ${msg.from.slice(0, 20)}...: ${msg.message}`)
          }
        } catch (err) {
          warn(`Check error: ${err?.message ?? err}`)
        }
        return
      }

      if (input === 'inbox:retrieve') {
        try {
          const result = await retrieveFromInbox(node, peerIdFromString(RELAY_PEER_ID))
          log(`Status: ${result.status}, messages: ${result.messages.length}`)
          for (const msg of result.messages) {
            const time = new Date(msg.timestamp).toLocaleTimeString()
            log(`  [${time}] from ${msg.from.slice(0, 20)}...: ${msg.message}`)
          }
        } catch (err) {
          warn(`Retrieve error: ${err?.message ?? err}`)
        }
        return
      }

      if (input.startsWith('inbox:store ')) {
        const msg = input.slice('inbox:store '.length)
        log(`Storing for A: "${msg}"`)
        try {
          const result = await storeInInbox(node, peerIdFromString(RELAY_PEER_ID), PEER_A_ID, msg)
          log(`Result: ${result.status}${result.error ? ' — ' + result.error : ''}`)
        } catch (err) {
          warn(`Store error: ${err?.message ?? err}`)
        }
        return
      }

      warn(`Unknown command: ${input}`)
      warn('Try: inbox:check, inbox:retrieve, inbox:store <msg>, /exit')
    }).catch(err => console.error('Error:', err))
  })

  const shutdown = async () => {
    rl.close()
    await pending
    await node.stop()
    process.exit(0)
  }

  process.on('SIGINT', shutdown)
  process.on('SIGTERM', shutdown)
  rl.on('close', shutdown)
}

main().catch(err => { console.error('Fatal:', err); process.exit(1) })
