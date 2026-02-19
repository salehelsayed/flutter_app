/**
 * rendezvous-relay-server-inbox-v4.js
 *
 * LibP2P v4 relay server with inline inbox implementation.
 * No external inbox.js dependency — everything self-contained.
 *
 * Run:
 *   node rendezvous-relay-server-inbox-v4.js
 */

import admin from 'firebase-admin'
import { readFileSync } from 'fs'
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

// ============================================================================
// Server Identity & Configuration
// ============================================================================

// Embedded private key (same as original server)
const privateKeyRaw = Uint8Array.from([
  3, 98, 126, 31, 53, 38, 77, 83, 95, 52, 208,
  245, 12, 231, 179, 29, 77, 119, 64, 225, 28, 76,
  152, 60, 22, 170, 169, 92, 240, 114, 50, 34, 97,
  34, 166, 6, 69, 146, 135, 77, 74, 250, 62, 215,
  106, 6, 45, 2, 118, 162, 136, 195, 108, 174, 61,
  180, 216, 136, 89, 9, 101, 139, 157, 193
])

const SERVER_IP4 = '13.60.15.36'
const SERVER_IP = 'mknoun.xyz'

// Ports
const WS_LOCAL_PORT = 4000
const TCP_PORT = 4005
const WSS_NGINX_PORT = 4001

// ============================================================================
// Rendezvous Protocol
// ============================================================================

const RENDEZVOUS_PROTOCOL = '/canvas/rendezvous/1.0.0'
const MAX_TTL = BigInt(2 * 60 * 60) // 2 hours
const MAX_DISCOVER_LIMIT = BigInt(64)

// In-memory registration store
const registrations = new Map() // namespace -> Map<peerId, { signedPeerRecord, expiresAt }>

function log(...args) {
  console.log('[RENDEZVOUS]', ...args)
}

function clamp(val, max) {
  return val > max ? max : val
}

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

setInterval(cleanupExpired, 60000)

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

async function handleRendezvousStream({ stream, connection }) {
  const remotePeer = connection.remotePeer
  log(`incoming stream from ${remotePeer}`)

  try {
    const source = stream.source || stream
    let requestData = null
    for await (const chunk of lp.decode(source)) {
      requestData = chunk.subarray()
      break
    }

    if (!requestData) {
      log('no request data received')
      return
    }

    const req = Message.decode(requestData)
    log(`received request type=${req.type}`)

    const response = await handleRequest(remotePeer, req, null)

    if (response) {
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

// ============================================================================
// Push Notifications (FCM)
// ============================================================================

const FIREBASE_SERVICE_ACCOUNT_PATH = process.env.FIREBASE_SERVICE_ACCOUNT || './firebase-service-account.json'
let firebaseInitialized = false

try {
  const serviceAccount = JSON.parse(readFileSync(FIREBASE_SERVICE_ACCOUNT_PATH, 'utf8'))
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  })
  firebaseInitialized = true
  console.log('[PUSH] Firebase Admin SDK initialized')
} catch (err) {
  console.warn('[PUSH] Firebase not initialized — push notifications disabled:', err.message)
}

// Device token store: Map<peerId, { token, platform, updatedAt }>
const tokenStore = new Map()

function registerToken(peerId, token, platform) {
  tokenStore.set(peerId, { token, platform, updatedAt: Date.now() })
  console.log(`[PUSH] Token registered for ${peerId.slice(0, 20)}... (${platform})`)
}

function unregisterToken(peerId) {
  tokenStore.delete(peerId)
  console.log(`[PUSH] Token unregistered for ${peerId.slice(0, 20)}...`)
}

async function sendPushNotification(toPeerId, fromPeerId) {
  if (!firebaseInitialized) return

  const entry = tokenStore.get(toPeerId)
  if (!entry) return

  const message = {
    token: entry.token,
    data: {
      type: 'new_message',
      from: fromPeerId,
    },
    android: {
      priority: 'high',
    },
    apns: {
      headers: {
        'apns-priority': '10',
        'apns-push-type': 'alert',
      },
      payload: {
        aps: {
          'content-available': 1,
          alert: {
            title: 'New Message',
            body: 'You have a new message',
          },
        },
      },
    },
  }

  try {
    await admin.messaging().send(message)
    console.log(`[PUSH] Notification sent to ${toPeerId.slice(0, 20)}...`)
  } catch (err) {
    console.error(`[PUSH] Failed to send to ${toPeerId.slice(0, 20)}...:`, err.message)
    if (err.code === 'messaging/invalid-registration-token' ||
        err.code === 'messaging/registration-token-not-registered') {
      tokenStore.delete(toPeerId)
      console.log(`[PUSH] Removed invalid token for ${toPeerId.slice(0, 20)}...`)
    }
  }
}

// ============================================================================
// Inline Inbox Implementation
// ============================================================================

const INBOX_PROTOCOL = '/mknoon/inbox/1.0.0'

// In-memory store: Map<peerId, Array<{ from, message, timestamp, metadata }>>
const inboxStore = new Map()
const MAX_MESSAGES_PER_PEER = 100
const MAX_MESSAGE_AGE_MS = 7 * 24 * 60 * 60 * 1000 // 7 days

const MAX_FRAME_LEN = 128 * 1024
const textEncoder = new TextEncoder()
const textDecoder = new TextDecoder()

/**
 * Encode a payload with 4-byte big-endian length prefix
 */
function encodeFrame(payload) {
  if (payload.length > MAX_FRAME_LEN) throw new Error(`Frame too large: ${payload.length}`)
  const out = new Uint8Array(4 + payload.length)
  const len = payload.length >>> 0
  out[0] = (len >>> 24) & 0xff
  out[1] = (len >>> 16) & 0xff
  out[2] = (len >>> 8) & 0xff
  out[3] = len & 0xff
  out.set(payload, 4)
  return out
}

/**
 * Read 4-byte big-endian uint32
 */
function readU32BE(buf, offset = 0) {
  return (((buf[offset] << 24) >>> 0) + (buf[offset + 1] << 16) + (buf[offset + 2] << 8) + buf[offset + 3]) >>> 0
}

/**
 * Append two Uint8Arrays
 */
function appendBuffers(a, b) {
  if (a.length === 0) return b
  if (b.length === 0) return a
  const out = new Uint8Array(a.length + b.length)
  out.set(a, 0)
  out.set(b, a.length)
  return out
}

/**
 * Convert chunk to Uint8Array
 */
function toUint8(chunk) {
  if (chunk == null) return new Uint8Array()
  if (chunk instanceof Uint8Array) return chunk
  if (ArrayBuffer.isView(chunk)) return new Uint8Array(chunk.buffer, chunk.byteOffset, chunk.byteLength)
  if (chunk instanceof ArrayBuffer) return new Uint8Array(chunk)
  if (typeof chunk.subarray === 'function') return chunk.subarray()
  throw new Error(`Unsupported chunk type: ${typeof chunk}`)
}

/**
 * Read one complete frame from a stream (4-byte BE length prefix + payload)
 */
async function readOneFrame(stream) {
  const source = stream?.source && typeof stream.source[Symbol.asyncIterator] === 'function'
    ? stream.source
    : stream && typeof stream[Symbol.asyncIterator] === 'function'
      ? stream
      : null

  if (!source) throw new Error('Stream is not async iterable')

  let buffer = new Uint8Array(0)

  for await (const chunk of source) {
    buffer = appendBuffers(buffer, toUint8(chunk))

    if (buffer.length < 4) continue

    const len = readU32BE(buffer, 0)
    if (len > MAX_FRAME_LEN) throw new Error(`Frame too large: ${len}`)

    const needed = 4 + len
    if (buffer.length < needed) continue

    return buffer.subarray(4, needed)
  }

  throw new Error('Stream ended before a full frame was received')
}

/**
 * Write one frame to a stream
 */
async function writeOneFrame(stream, payload) {
  const framed = encodeFrame(payload)

  if (typeof stream?.sink === 'function') {
    await stream.sink((async function* () { yield framed })())
    return
  }

  if (typeof stream?.send === 'function') {
    stream.send(framed)
    return
  }

  throw new Error('Stream is not writable')
}

/**
 * Prune expired messages from a peer's inbox
 */
function pruneExpired(messages) {
  const cutoff = Date.now() - MAX_MESSAGE_AGE_MS
  return messages.filter(m => m.timestamp > cutoff)
}

/**
 * Store a message in a peer's inbox
 */
function storeMessage(toPeerId, entry) {
  let messages = inboxStore.get(toPeerId) || []

  // Prune expired messages
  messages = pruneExpired(messages)

  // Cap at max
  if (messages.length >= MAX_MESSAGES_PER_PEER) {
    messages = messages.slice(messages.length - MAX_MESSAGES_PER_PEER + 1)
  }

  messages.push(entry)
  inboxStore.set(toPeerId, messages)

  console.log(`[INBOX] Stored message for ${toPeerId.slice(0, 20)}... from ${entry.from.slice(0, 20)}... (total: ${messages.length})`)

  // Fire push notification (non-blocking)
  sendPushNotification(toPeerId, entry.from).catch(() => {})
}

/**
 * Retrieve messages from a peer's inbox
 */
function retrieveMessages(peerId, { limit = 50 } = {}) {
  let messages = inboxStore.get(peerId) || []

  // Prune expired
  messages = pruneExpired(messages)
  inboxStore.set(peerId, messages)

  const result = messages.slice(0, limit)

  if (result.length > 0) {
    // Delete retrieved messages from memory
    const remaining = messages.slice(limit)
    if (remaining.length > 0) {
      inboxStore.set(peerId, remaining)
    } else {
      inboxStore.delete(peerId)
    }
    console.log(`[INBOX] Retrieved ${result.length} message(s) for ${peerId.slice(0, 20)}... — deleted from memory (${remaining.length} remaining)`)
  } else {
    console.log(`[INBOX] No messages for ${peerId.slice(0, 20)}...`)
  }

  return result
}

/**
 * Check if a peer has pending messages
 */
function hasPending(peerId) {
  const messages = inboxStore.get(peerId)
  return messages != null && messages.length > 0
}

/**
 * Count pending messages for a peer
 */
function count(peerId) {
  const messages = inboxStore.get(peerId)
  return messages ? messages.length : 0
}

/**
 * Get overall inbox stats
 */
function getStats() {
  let totalMessages = 0
  for (const messages of inboxStore.values()) {
    totalMessages += messages.length
  }
  return {
    totalPeers: inboxStore.size,
    totalMessages
  }
}

/**
 * Handle an incoming inbox protocol stream
 */
async function handleInboxStream({ stream, connection }) {
  const remotePeer = connection.remotePeer.toString()
  console.log(`[INBOX] Incoming stream from ${remotePeer.slice(0, 20)}...`)

  try {
    const requestBytes = await readOneFrame(stream)
    const request = JSON.parse(textDecoder.decode(requestBytes))

    let response

    if (request.action === 'store') {
      // Validate required fields
      if (!request.to || !request.message) {
        response = { status: 'ERROR', error: 'Missing required fields: to, message' }
      } else {
        storeMessage(request.to, {
          from: request.from || remotePeer,
          message: request.message,
          timestamp: Date.now(),
          metadata: request.metadata || {}
        })
        response = { status: 'OK' }
      }
    } else if (request.action === 'register_token') {
      if (!request.token || !request.platform) {
        response = { status: 'ERROR', error: 'Missing required fields: token, platform' }
      } else {
        registerToken(remotePeer, request.token, request.platform)
        response = { status: 'OK' }
      }
    } else if (request.action === 'unregister_token') {
      unregisterToken(remotePeer)
      response = { status: 'OK' }
    } else if (request.action === 'retrieve') {
      const messages = retrieveMessages(remotePeer, {
        limit: request.limit || 50
      })
      response = {
        status: messages.length > 0 ? 'OK' : 'NO_MESSAGES',
        messages
      }
    } else {
      response = { status: 'ERROR', error: `Unknown action: ${request.action}` }
    }

    await writeOneFrame(stream, textEncoder.encode(JSON.stringify(response)))
  } catch (err) {
    console.error(`[INBOX] Stream error from ${remotePeer.slice(0, 20)}...:`, err?.message ?? err)
  } finally {
    try { await stream.close() } catch {}
    console.log(`[INBOX] Stream closed for ${remotePeer.slice(0, 20)}...`)
  }
}

// ============================================================================
// Main
// ============================================================================

async function main() {
  console.log('Starting LibP2P relay + rendezvous + inbox server (v4 — inline inbox)...')

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
    if (hasPending(peerId)) {
      console.log(`[INBOX] Peer ${peerId.slice(0, 20)}... has ${count(peerId)} pending messages`)
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
  console.log(`  Inbox:      ${INBOX_PROTOCOL}`)
  console.log(`  Push:       ${firebaseInitialized ? 'enabled' : 'disabled (no service account)'}\n`)

  // Log inbox stats periodically
  setInterval(() => {
    const stats = getStats()
    if (stats.totalMessages > 0 || tokenStore.size > 0) {
      console.log(`[INBOX] Stats: ${stats.totalPeers} peers, ${stats.totalMessages} messages | [PUSH] ${tokenStore.size} registered tokens`)
    }
  }, 60000)

  // Keep alive
  process.stdin.resume()
  console.log('Press Ctrl+C to exit')

  // Clean shutdown
  const shutdown = async (signal) => {
    try {
      console.log(`\nShutting down (${signal})...`)
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