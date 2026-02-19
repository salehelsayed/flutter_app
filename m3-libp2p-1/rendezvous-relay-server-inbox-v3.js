/**
 * rendezvous-relay-server-inbox-v3.js
 *
 * LibP2P v3 compatible rendezvous + relay server with offline inbox support.
 *
 * Run:
 *   node rendezvous-relay-server-inbox-v3.js
 */

import { createLibp2p } from 'libp2p'
import { noise } from '@chainsafe/libp2p-noise'
import { yamux } from '@chainsafe/libp2p-yamux'
import { circuitRelayServer, circuitRelayTransport } from '@libp2p/circuit-relay-v2'
import { identify, identifyPush } from '@libp2p/identify'
import { ping } from '@libp2p/ping'
import { webSockets } from '@libp2p/websockets'
import { webRTC } from '@libp2p/webrtc'
import { tcp } from '@libp2p/tcp'
import { privateKeyFromRaw } from '@libp2p/crypto/keys'
import * as lp from 'it-length-prefixed'
import { Message } from '@canvas-js/libp2p-rendezvous/protocol'
import { PeerRecord, RecordEnvelope } from '@libp2p/peer-record'
import { peerIdFromPublicKey } from '@libp2p/peer-id'

// Import inbox module
import {
  createInbox,
  createInboxHandler,
  INBOX_PROTOCOL
} from './inbox.js'

// Optional wrtc (Node) support with safe fallback
let wrtc = null
try {
  wrtc = await import('wrtc')
  Object.assign(globalThis, wrtc)
  console.log('[WRTC] Successfully loaded wrtc package')
} catch (e) {
  console.warn('[WRTC] Failed to load wrtc:', e?.message ?? e)
}

/**
 * Helper to log events from a given RTCPeerConnection, for debugging ICE.
 */
function logWebRTCEvents(rtcConnection, context = '') {
  if (!rtcConnection) return

  const prefix = context ? `[${context}] ` : ''
  console.log(`${prefix}[WebRTC] Setting up event logging for RTCPeerConnection`)

  try {
    rtcConnection.addEventListener('icegatheringstatechange', () => {
      console.log(`${prefix}[ICE] gatheringState: ${rtcConnection.iceGatheringState}`)
    })

    rtcConnection.addEventListener('iceconnectionstatechange', () => {
      console.log(`${prefix}[ICE] connectionState: ${rtcConnection.iceConnectionState}`)
    })

    rtcConnection.addEventListener('signalingstatechange', () => {
      console.log(`${prefix}[WebRTC] signalingState: ${rtcConnection.signalingState}`)
    })
  } catch (err) {
    console.warn(`${prefix}[WebRTC] Error setting up event listeners:`, err?.message ?? err)
  }
}

// Embedded private key (same as original server)
const privateKeyRaw = Uint8Array.from([
  3, 98, 126, 31, 53, 38, 77, 83, 95, 52, 208,
  245, 12, 231, 179, 29, 77, 119, 64, 225, 28, 76,
  152, 60, 22, 170, 169, 92, 240, 114, 50, 34, 97,
  34, 166, 6, 69, 146, 135, 77, 74, 250, 62, 215,
  106, 6, 45, 2, 118, 162, 136, 195, 108, 174, 61,
  180, 216, 136, 89, 9, 101, 139, 157, 193
])

// Server identity / addressing
const SERVER_IP4 = '13.60.15.36'
const SERVER_IP = 'mknoun.xyz'

// Ports
const WS_LOCAL_PORT = 4000
const TCP_PORT = 4005
const WSS_NGINX_PORT = 4001

// Rendezvous protocol
const RENDEZVOUS_PROTOCOL = '/canvas/rendezvous/1.0.0'
const MAX_TTL = BigInt(2 * 60 * 60) // 2 hours
const MAX_DISCOVER_LIMIT = BigInt(64)

// In-memory registration store (for simplicity)
const registrations = new Map() // namespace -> Map<peerId, { signedPeerRecord, expiresAt }>

function log(...args) {
  console.log('[RENDEZVOUS]', ...args)
}

function clamp(val, max) {
  return val > max ? max : val
}

// Clean expired registrations
function cleanupExpired() {
  const now = Date.now()
  for (const [ns, peers] of registrations) {
    for (const [peerId, reg] of peers) {
      if (reg.expiresAt < now) {
        peers.delete(peerId)
        log(`expired registration: ${ns} / ${peerId}`)
      }
    }
    if (peers.size === 0) {
      registrations.delete(ns)
    }
  }
}

// Run cleanup periodically
setInterval(cleanupExpired, 60000)

// Handle a single rendezvous request
async function handleRequest(peerId, req, peerStore) {
  if (req.type === Message.MessageType.REGISTER) {
    if (!req.register) {
      throw new Error('invalid REGISTER message')
    }

    const { ns, signedPeerRecord, ttl } = req.register
    if (ns.length >= 256) {
      throw new Error('namespace too long')
    }

    log(`REGISTER ns=${ns} ttl=${ttl} from ${peerId}`)

    const actualTTL = ttl === 0n ? MAX_TTL : clamp(ttl, MAX_TTL)

    // Verify the signed peer record
    try {
      const envelope = await RecordEnvelope.openAndCertify(signedPeerRecord, PeerRecord.DOMAIN)
      const recordPeerId = peerIdFromPublicKey(envelope.publicKey)
      if (recordPeerId.toString() !== peerId.toString()) {
        throw new Error('peer record does not match sender')
      }
    } catch (err) {
      log(`invalid peer record: ${err.message}`)
      return {
        type: Message.MessageType.REGISTER_RESPONSE,
        registerResponse: {
          status: Message.ResponseStatus.E_INVALID_SIGNED_PEER_RECORD,
          statusText: `invalid peer record: ${err.message}`,
          ttl: 0n
        }
      }
    }

    // Store the registration
    if (!registrations.has(ns)) {
      registrations.set(ns, new Map())
    }
    registrations.get(ns).set(peerId.toString(), {
      signedPeerRecord,
      expiresAt: Date.now() + Number(actualTTL) * 1000
    })

    return {
      type: Message.MessageType.REGISTER_RESPONSE,
      registerResponse: {
        status: Message.ResponseStatus.OK,
        statusText: 'OK',
        ttl: actualTTL
      }
    }
  }

  if (req.type === Message.MessageType.UNREGISTER) {
    if (!req.unregister) {
      throw new Error('invalid UNREGISTER message')
    }

    const { ns } = req.unregister
    log(`UNREGISTER ns=${ns} from ${peerId}`)

    const peers = registrations.get(ns)
    if (peers) {
      peers.delete(peerId.toString())
      if (peers.size === 0) {
        registrations.delete(ns)
      }
    }

    // UNREGISTER has no response
    return null
  }

  if (req.type === Message.MessageType.DISCOVER) {
    if (!req.discover) {
      throw new Error('invalid DISCOVER message')
    }

    const { ns, limit } = req.discover
    log(`DISCOVER ns=${ns} limit=${limit} from ${peerId}`)

    const actualLimit = limit === 0n ? MAX_DISCOVER_LIMIT : clamp(limit, MAX_DISCOVER_LIMIT)

    const regs = []
    const peers = registrations.get(ns)
    if (peers) {
      const now = Date.now()
      let count = 0n
      for (const [pid, reg] of peers) {
        if (count >= actualLimit) break
        if (reg.expiresAt > now && pid !== peerId.toString()) {
          regs.push({ ns, signedPeerRecord: reg.signedPeerRecord })
          count++
        }
      }
    }

    return {
      type: Message.MessageType.DISCOVER_RESPONSE,
      discoverResponse: {
        status: Message.ResponseStatus.OK,
        statusText: 'OK',
        registrations: regs,
        cookie: new Uint8Array()
      }
    }
  }

  throw new Error(`unknown message type: ${req.type}`)
}

// Handle incoming rendezvous stream (yamux stream interface)
async function handleRendezvousStream({ stream, connection }) {
  const remotePeer = connection.remotePeer
  log(`incoming stream from ${remotePeer}`)

  try {
    // Read incoming request - try stream.source first (works for incoming streams),
    // fall back to stream directly
    const source = stream.source || stream
    let requestData = null
    for await (const chunk of lp.decode(source)) {
      requestData = chunk.subarray()
      break // Only process first message
    }

    if (!requestData) {
      log('no request data received')
      return
    }

    const req = Message.decode(requestData)
    log(`received request type=${req.type}`)

    const response = await handleRequest(remotePeer, req, null)

    if (response) {
      // Encode and send response using stream.send() (yamux method)
      const responseBytes = Message.encode(response)
      const encoded = lp.encode.single(responseBytes)

      if (typeof stream.send === 'function') {
        stream.send(encoded.subarray())
        log(`sent response type=${response.type} via send()`)
      } else if (typeof stream.sink === 'function') {
        await stream.sink((async function* () {
          yield encoded.subarray()
        })())
        log(`sent response type=${response.type} via sink()`)
      } else {
        log('ERROR: no way to send data on stream')
      }
    }
  } catch (err) {
    log(`stream error: ${err.message}`)
  } finally {
    try {
      await stream.close()
    } catch {}
    log(`stream closed for ${remotePeer}`)
  }
}

async function main() {
  console.log('Starting LibP2P relay + rendezvous + inbox server (v3 compatible)...')

  // Create inbox instance
  const inbox = createInbox({
    maxMessagesPerPeer: 100,
    maxMessageAge: 7 * 24 * 60 * 60 * 1000, // 7 days
    onStore: (toPeerId, entry) => {
      console.log(`[INBOX] Stored message for ${toPeerId.slice(0, 20)}... from ${entry.from.slice(0, 20)}...`)
    },
    onRetrieve: (peerId, messages) => {
      console.log(`[INBOX] Retrieved ${messages.length} messages for ${peerId.slice(0, 20)}...`)
    }
  })

  // Create inbox protocol handler
  const handleInboxStream = createInboxHandler(inbox, console)

  // Test WebRTC STUN/TURN configuration on startup
  if (wrtc && globalThis.RTCPeerConnection) {
    try {
      console.log('[TEST] Testing WebRTC STUN/TURN config...')
      const pc = new globalThis.RTCPeerConnection({
        iceServers: [
          {
            urls: [
              `stun:${SERVER_IP}:3478`,
              `turn:${SERVER_IP}:3478?transport=udp`,
              `turn:${SERVER_IP}:3478?transport=tcp`
            ],
            username: 'testuser',
            credential: 'testpass'
          }
        ]
      })
      logWebRTCEvents(pc, 'TEST')
      pc.createDataChannel('test')
      const offer = await pc.createOffer()
      await pc.setLocalDescription(offer)
      await new Promise(r => setTimeout(r, 5000))
      pc.close()
      console.log('[TEST] WebRTC test complete.')
    } catch (e) {
      console.log('[TEST] WebRTC test failed:', e?.message ?? e)
    }
  } else {
    console.log('[TEST] Skipping WebRTC test - RTCPeerConnection not available')
  }

  const transports = [
    webSockets(),
    tcp()
  ]

  if (wrtc) {
    transports.push(
      webRTC({
        rtcConfiguration: {
          iceServers: [
            {
              urls: [
                `stun:${SERVER_IP}:3478`,
                `turn:${SERVER_IP}:3478?transport=udp`,
                `turn:${SERVER_IP}:3478?transport=tcp`
              ],
              username: 'testuser',
              credential: 'testpass'
            }
          ]
        },
        connectionObserver: (rtc) => logWebRTCEvents(rtc, 'RELAY')
      })
    )
  }

  transports.push(circuitRelayTransport({ discoverRelays: 1 }))

  const node = await createLibp2p({
    privateKey: privateKeyFromRaw(privateKeyRaw),

    addresses: {
      listen: [
        `/ip4/127.0.0.1/tcp/${WS_LOCAL_PORT}/ws`,
        `/ip4/0.0.0.0/tcp/${TCP_PORT}`
      ],
      announce: [
        `/dns4/${SERVER_IP}/tcp/${WSS_NGINX_PORT}/wss`,
        `/ip4/${SERVER_IP4}/tcp/${TCP_PORT}`
      ]
    },

    transports,

    connectionEncrypters: [noise()],
    streamMuxers: [yamux()],

    services: {
      identify: identify(),
      identifyPush: identifyPush(),
      ping: ping(),

      relay: circuitRelayServer({
        hop: { enabled: true },
        reservations: {
          maxReservations: Infinity
        }
      })
    }
  })

  // Register protocol handlers
  await node.handle(RENDEZVOUS_PROTOCOL, handleRendezvousStream)
  await node.handle(INBOX_PROTOCOL, handleInboxStream)

  // Log connections
  node.addEventListener('peer:connect', evt => {
    const peerId = evt.detail.toString()
    console.log(`[NODE] Peer connected: ${peerId}`)

    // Notify if peer has pending messages
    if (inbox.hasPending(peerId)) {
      console.log(`[INBOX] Peer ${peerId.slice(0, 20)}... has ${inbox.count(peerId)} pending messages`)
    }
  })

  node.addEventListener('peer:disconnect', evt => {
    console.log(`[NODE] Peer disconnected: ${evt.detail.toString()}`)
  })

  console.log('Starting LibP2P node...')
  await node.start()

  console.log('Node started:')
  console.log('Peer ID:', node.peerId.toString())
  console.log('Listening addresses:')
  node.getMultiaddrs().forEach(ma => console.log('  -', ma.toString()))

  console.log(`\nRelay circuit address:\n  /p2p/${node.peerId.toString()}/p2p-circuit\n`)

  console.log('Public WSS address for browsers (through Nginx):')
  console.log(`  /dns4/${SERVER_IP}/tcp/${WSS_NGINX_PORT}/wss/p2p/${node.peerId.toString()}\n`)

  console.log('Protocols:')
  console.log(`  Rendezvous: ${RENDEZVOUS_PROTOCOL}`)
  console.log(`  Inbox:      ${INBOX_PROTOCOL}\n`)

  // Log inbox stats periodically
  setInterval(() => {
    const stats = inbox.getStats()
    if (stats.totalMessages > 0) {
      console.log(`[INBOX] Stats: ${stats.totalPeers} peers, ${stats.totalMessages} messages`)
    }
  }, 60000)

  // Keep alive
  process.stdin.resume()
  console.log('Press Ctrl+C to exit')

  // Clean shutdown
  const shutdown = async (signal) => {
    try {
      console.log(`\nShutting down (${signal})...`)
      inbox.stop()
      await node.stop()
      console.log('Node stopped')
    } catch (err) {
      console.error('[NODE] Error during shutdown:', err)
    } finally {
      process.exit(0)
    }
  }

  process.on('SIGINT', () => void shutdown('SIGINT'))
  process.on('SIGTERM', () => void shutdown('SIGTERM'))
}

main().catch(err => {
  console.error('[FATAL] startup error:', err)
  process.exit(1)
})
