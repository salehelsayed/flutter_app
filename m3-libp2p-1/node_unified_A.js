/**
 * node_unified_A.js — Inbox Smoke Test (Sender)
 *
 * Connects as User A, stores a test message in User B's inbox on the relay.
 * Run this FIRST while User B is offline.
 *
 * Usage:
 *   node node_unified_A.js                          # Store default test message
 *   node node_unified_A.js "Custom message here"    # Store custom message
 *
 * After storing, enters interactive mode for additional commands.
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

const CREDS_PATH = './Creds_User_A.txt'
const PEER_B_ID = '12D3KooWCP1pBwwH1WoyqF6scuBny9T6JsdsEnDLQwVSpD6SJ8XR'

const RELAY_ADDRESS = '/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g'
const RELAY_PEER_ID = '12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g'

const RELAY_TIMEOUT_MS = 30000

// ============================================================================
// Helpers
// ============================================================================

const log = (...args) => console.log('[A]', ...args)
const warn = (...args) => console.warn('[A]', ...args)
const step = (n, msg) => console.log(`\n  [${ n}] ${msg}`)

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
  const customMessage = process.argv.slice(2).join(' ') || null

  console.log('='.repeat(60))
  console.log('  INBOX SMOKE TEST — Node A (Sender)')
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

  // Step 5: Check own inbox first
  step(5, 'Checking own inbox...')
  try {
    const inboxResult = await retrieveFromInbox(node, peerIdFromString(RELAY_PEER_ID), { peek: true })
    if (inboxResult.status === ResponseStatus.OK) {
      log(`Found ${inboxResult.messages.length} message(s) in own inbox`)
      for (const msg of inboxResult.messages) {
        const time = new Date(msg.timestamp).toLocaleTimeString()
        log(`  [${time}] from ${msg.from.slice(0, 20)}...: ${msg.message}`)
      }
    } else {
      log(`Inbox status: ${inboxResult.status}`)
    }
  } catch (err) {
    warn(`Inbox check failed: ${err?.message ?? err}`)
  }

  // Step 6: Store message in B's inbox
  const testMessage = customMessage || `Hello from A! Smoke test at ${new Date().toISOString()}`
  step(6, `Storing message in B's inbox...`)
  log(`To:      ${PEER_B_ID}`)
  log(`Message: ${testMessage}`)

  try {
    const storeResult = await storeInInbox(node, peerIdFromString(RELAY_PEER_ID), PEER_B_ID, testMessage)
    if (storeResult.status === ResponseStatus.OK) {
      console.log('\n  ✓ MESSAGE STORED SUCCESSFULLY')
    } else {
      console.log(`\n  ✗ STORE FAILED: ${storeResult.status} — ${storeResult.error || 'unknown'}`)
    }
  } catch (err) {
    console.log(`\n  ✗ STORE ERROR: ${err?.message ?? err}`)
  }

  // Interactive mode
  console.log('\n' + '-'.repeat(60))
  console.log('  Interactive mode — commands:')
  console.log('    inbox:store <message>    Store another message for B')
  console.log('    inbox:check              Check own inbox (peek)')
  console.log('    inbox:retrieve           Retrieve own inbox (consume)')
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

      if (input.startsWith('inbox:store ')) {
        const msg = input.slice('inbox:store '.length)
        log(`Storing: "${msg}"`)
        try {
          const result = await storeInInbox(node, peerIdFromString(RELAY_PEER_ID), PEER_B_ID, msg)
          log(`Result: ${result.status}${result.error ? ' — ' + result.error : ''}`)
        } catch (err) {
          warn(`Store error: ${err?.message ?? err}`)
        }
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

      // Default: store as message to B
      log(`Storing message for B: "${input}"`)
      try {
        const result = await storeInInbox(node, peerIdFromString(RELAY_PEER_ID), PEER_B_ID, input)
        log(`Result: ${result.status}${result.error ? ' — ' + result.error : ''}`)
      } catch (err) {
        warn(`Store error: ${err?.message ?? err}`)
      }
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
