/**
 * node_unified_B.js
 *
 * Unified P2P chat node for User B with JSON message exchange.
 * Registers on rendezvous, discovers peers, sends and receives JSON chat messages.
 *
 * Identity: hardcoded private key (same as node_B_receiver_rendezvous.js)
 * Peer ID: 12D3KooWCP1pBwwH1WoyqF6scuBny9T6JsdsEnDLQwVSpD6SJ8XR
 *
 * Usage:
 *   node node_unified_B.js [target-peer-id] [message]
 */

import { randomUUID } from 'crypto'
import { fileURLToPath } from 'url'
import { resolve } from 'path'
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
import { peerIdFromPrivateKey, peerIdFromString, peerIdFromPublicKey } from '@libp2p/peer-id'
import { multiaddr } from '@multiformats/multiaddr'
import { Message } from '@canvas-js/libp2p-rendezvous/protocol'
import { PeerRecord, RecordEnvelope } from '@libp2p/peer-record'
import * as lp from 'it-length-prefixed'
import { storeInInbox, retrieveFromInbox, ResponseStatus } from './inbox.js'

// ============================================================================
// Configuration
// ============================================================================

// Hardcoded private key (same as node_B_receiver_rendezvous.js)
const PRIVATE_KEY_HEX = 'db7084b44dc03b8b7503f6240e4b15873648db426a8012375fa4e50b36d7a383261486988596e81c376cebc826f4ed4c01ee47f2eb005dc601eb19623c2ebbb8'

const RELAY_ADDRESS = process.env.RELAY_ADDRESS ??
  '/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g'

const RELAY_PEER_ID = RELAY_ADDRESS.match(/\/p2p\/([^/]+)$/)?.[1] ?? null

const RENDEZVOUS_POINTS = (process.env.RENDEZVOUS_POINTS ?? RELAY_ADDRESS)
  .split(',').map(s => s.trim()).filter(Boolean)

const CHAT_PROTOCOL = '/mknoon/chat/1.0.0'
const RENDEZVOUS_PROTOCOL = '/canvas/rendezvous/1.0.0'

const REGISTER_TTL_S = 2 * 60 * 60
const REGISTER_RETRY_MS = 5000
const DISCOVER_POLL_MS = 2000
const DISCOVER_TIMEOUT_MS = 60000
const CHAT_TIMEOUT_MS = 10000
const RELAY_TIMEOUT_MS = 30000
const MAX_FRAME_LEN = 128 * 1024

const NODE_NAME = 'Node_B'
const log = (...args) => console.log(`[${NODE_NAME}]`, ...args)
const warn = (...args) => console.warn(`[${NODE_NAME}]`, ...args)

// ============================================================================
// JSON Message Helpers
// ============================================================================

export function createChatMessage(fromPeerId, toPeerId, body) {
  return {
    schema: 'mknoon.chat.v1',
    type: 'message',
    id: randomUUID(),
    from: fromPeerId,
    to: toPeerId,
    body,
    timestamp: new Date().toISOString()
  }
}

export function createAckMessage(fromPeerId, originalMsg) {
  return {
    schema: 'mknoon.chat.v1',
    type: 'ack',
    id: randomUUID(),
    replyTo: originalMsg.id,
    from: fromPeerId,
    to: originalMsg.from,
    body: `received: ${originalMsg.body}`,
    timestamp: new Date().toISOString()
  }
}

export function serializeMessage(msg) {
  return new TextEncoder().encode(JSON.stringify(msg))
}

export function deserializeMessage(bytes) {
  return JSON.parse(new TextDecoder().decode(bytes))
}

// ============================================================================
// Framing (4-byte big-endian length prefix)
// ============================================================================

export function encodeFrame(payloadBytes) {
  if (payloadBytes.length > MAX_FRAME_LEN) throw new Error(`Frame too large: ${payloadBytes.length}`)
  const out = new Uint8Array(4 + payloadBytes.length)
  const len = payloadBytes.length >>> 0
  out[0] = (len >>> 24) & 0xff
  out[1] = (len >>> 16) & 0xff
  out[2] = (len >>> 8) & 0xff
  out[3] = len & 0xff
  out.set(payloadBytes, 4)
  return out
}

function readU32BE(buf, offset = 0) {
  return (((buf[offset] << 24) >>> 0) + (buf[offset + 1] << 16) + (buf[offset + 2] << 8) + buf[offset + 3]) >>> 0
}

function toUint8(chunk) {
  if (chunk == null) return new Uint8Array()
  if (chunk instanceof Uint8Array) return chunk
  if (ArrayBuffer.isView(chunk)) return new Uint8Array(chunk.buffer, chunk.byteOffset, chunk.byteLength)
  if (chunk instanceof ArrayBuffer) return new Uint8Array(chunk)
  if (typeof chunk.subarray === 'function') return chunk.subarray()
  throw new Error(`Unsupported chunk type: ${typeof chunk}`)
}

function appendBuffers(a, b) {
  if (a.length === 0) return b
  if (b.length === 0) return a
  const out = new Uint8Array(a.length + b.length)
  out.set(a, 0)
  out.set(b, a.length)
  return out
}

// ============================================================================
// Utilities
// ============================================================================

const sleep = (ms) => new Promise(resolve => setTimeout(resolve, ms))

async function sleepWithSignal(ms, signal) {
  if (signal?.aborted) return
  await new Promise(resolve => {
    const t = setTimeout(resolve, ms)
    if (signal) signal.addEventListener('abort', () => { clearTimeout(t); resolve() }, { once: true })
  })
}

// ============================================================================
// Identity
// ============================================================================

export function loadIdentity() {
  const bytes = Uint8Array.from(Buffer.from(PRIVATE_KEY_HEX, 'hex'))
  const privateKey = privateKeyFromRaw(bytes)
  const peerId = peerIdFromPrivateKey(privateKey)
  return { privateKey, peerId }
}

// ============================================================================
// Node Creation
// ============================================================================

export async function createNode(privateKey, opts = {}) {
  const listenAddrs = opts.listenAddrs ?? ['/p2p-circuit', '/ip4/0.0.0.0/tcp/0']
  const useWebRTC = opts.useWebRTC !== false

  const transports = [webSockets(), tcp()]
  if (useWebRTC) {
    transports.push(webRTC({
      rtcConfiguration: {
        iceServers: [{
          urls: ['stun:mknoun.xyz:3478', 'turn:mknoun.xyz:3478?transport=udp', 'turn:mknoun.xyz:3478?transport=tcp'],
          username: 'testuser', credential: 'testpass'
        }]
      }
    }))
  }
  transports.push(circuitRelayTransport({ discoverRelays: 0 }))

  return await createLibp2p({
    privateKey,
    addresses: { listen: listenAddrs },
    transports,
    connectionEncrypters: [noise()],
    streamMuxers: [yamux()],
    services: {
      identify: identify(),
      identifyPush: identifyPush(),
      ping: ping(),
      dcutr: dcutr()
    }
  })
}

// ============================================================================
// Rendezvous Registration
// ============================================================================

export function getCircuitAddresses(node) {
  return node.getMultiaddrs().filter(ma => ma.toString().includes('/p2p-circuit'))
}

export async function waitForCircuitAddresses(node, timeoutMs) {
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

export async function registerOnce(node, namespace, rendezvousAddr) {
  const circuitAddrs = getCircuitAddresses(node)
  if (circuitAddrs.length === 0) throw new Error('No circuit addresses available')

  const connection = await node.dial(multiaddr(rendezvousAddr), { signal: AbortSignal.timeout(20000) })
  const stream = await connection.newStream(RENDEZVOUS_PROTOCOL, { signal: AbortSignal.timeout(10000) })

  try {
    const pk = node.components?.components?.privateKey || node.components?.privateKey
    if (!pk) throw new Error('Cannot access node privateKey')

    const record = new PeerRecord({ peerId: node.peerId, multiaddrs: circuitAddrs })
    const envelope = await RecordEnvelope.seal(record, pk)
    const signedPeerRecord = envelope.marshal()

    const registerMsg = Message.encode({
      type: Message.MessageType.REGISTER,
      register: { ns: namespace, signedPeerRecord, ttl: BigInt(REGISTER_TTL_S) }
    })

    const encoded = lp.encode.single(registerMsg)
    const msgBytes = encoded.subarray()

    const responsePromise = new Promise((resolve, reject) => {
      const chunks = []
      const timeout = setTimeout(() => reject(new Error('Timeout')), 10000)
      const tryDecode = async () => {
        if (chunks.length === 0) return
        const totalLen = chunks.reduce((a, c) => a + c.length, 0)
        const allData = new Uint8Array(totalLen)
        let offset = 0
        for (const c of chunks) { allData.set(c, offset); offset += c.length }
        try {
          async function* source() { yield allData }
          for await (const decoded of lp.decode(source())) { clearTimeout(timeout); resolve(decoded.subarray()); return }
        } catch {}
      }
      if (typeof stream.onData === 'function') {
        const orig = stream.onData
        stream.onData = (data) => { orig?.call(stream, data); chunks.push(toUint8(data)); tryDecode() }
      } else {
        stream.addEventListener?.('data', (evt) => {
          const data = evt.detail || evt.data || evt
          chunks.push(toUint8(data)); tryDecode()
        })
      }
    })

    stream.send(msgBytes)
    const responseData = await responsePromise
    const response = Message.decode(responseData)

    if (response.type !== Message.MessageType.REGISTER_RESPONSE) throw new Error(`Unexpected: ${response.type}`)
    if (response.registerResponse?.status !== Message.ResponseStatus.OK) throw new Error(response.registerResponse?.statusText ?? 'Registration failed')

    return Number(response.registerResponse.ttl)
  } finally {
    try { await stream.close() } catch {}
  }
}

export async function registerForever(node, namespace, rendezvousAddr, signal) {
  while (!signal.aborted) {
    try {
      const ttl = await registerOnce(node, namespace, rendezvousAddr)
      log(`Registered on rendezvous (ttl=${ttl}s)`)
      const refreshMs = Math.max(30000, Math.floor(ttl * 1000 * 0.8))
      await sleepWithSignal(refreshMs, signal)
    } catch (err) {
      warn(`Registration failed: ${err?.message ?? err}`)
      await sleepWithSignal(REGISTER_RETRY_MS, signal)
    }
  }
}

// ============================================================================
// Rendezvous Discovery
// ============================================================================

export async function discoverFromPoint(node, pointAddr, namespace) {
  let stream = null
  try {
    const connection = await node.dial(multiaddr(pointAddr), { signal: AbortSignal.timeout(20000) })
    stream = await connection.newStream(RENDEZVOUS_PROTOCOL, { signal: AbortSignal.timeout(10000) })

    const discoverMsg = Message.encode({
      type: Message.MessageType.DISCOVER,
      discover: { ns: namespace, limit: BigInt(100), cookie: new Uint8Array() }
    })
    const encoded = lp.encode.single(discoverMsg)
    const msgBytes = encoded.subarray()

    let responseData = null
    const readPromise = (async () => {
      for await (const chunk of lp.decode(stream)) { responseData = chunk.subarray(); break }
    })()

    stream.send(msgBytes)
    await Promise.race([
      readPromise,
      new Promise((_, reject) => setTimeout(() => reject(new Error('Timeout')), 10000))
    ])

    if (!responseData) throw new Error('No response')
    const response = Message.decode(responseData)
    if (response.type !== Message.MessageType.DISCOVER_RESPONSE) throw new Error(`Unexpected: ${response.type}`)
    if (response.discoverResponse?.status !== Message.ResponseStatus.OK) throw new Error(response.discoverResponse?.statusText ?? 'Discover failed')

    const peers = []
    for (const reg of response.discoverResponse.registrations || []) {
      try {
        const envelope = await RecordEnvelope.openAndCertify(reg.signedPeerRecord, PeerRecord.DOMAIN)
        const peerRecord = PeerRecord.createFromProtobuf(envelope.payload)
        const peerId = peerIdFromPublicKey(envelope.publicKey)
        peers.push({ id: peerId, addresses: peerRecord.multiaddrs })
      } catch {}
    }
    return peers
  } catch (err) {
    warn(`Discover from ${pointAddr} failed: ${err?.message ?? err}`)
    return []
  } finally {
    try { if (stream) await stream.close() } catch {}
  }
}

export async function discoverTarget(node, namespace, targetPeerId, rendezvousPoints, timeoutMs = DISCOVER_TIMEOUT_MS) {
  const points = rendezvousPoints ?? RENDEZVOUS_POINTS
  const deadline = Date.now() + timeoutMs
  while (Date.now() < deadline) {
    const results = await Promise.allSettled(
      points.map(addr => discoverFromPoint(node, addr, namespace))
    )
    const allPeers = results.filter(r => r.status === 'fulfilled').flatMap(r => r.value)
    const match = allPeers.find(p => p.id.toString() === targetPeerId)
    if (match) {
      const addrs = match.addresses.map(ma => {
        const s = ma.toString()
        return s.includes(`/p2p/${targetPeerId}`) ? ma : multiaddr(`${s}/p2p/${targetPeerId}`)
      })
      return { peer: match, multiaddrs: addrs }
    }
    await sleep(DISCOVER_POLL_MS)
  }
  return null
}

// ============================================================================
// JSON Chat Messaging
// ============================================================================

export function setupJsonChatHandler(node, onMessage) {
  node.handle(CHAT_PROTOCOL, async (incomingData) => {
    const stream = incomingData?.stream ?? incomingData
    const connection = incomingData?.connection
    const remotePeer = connection?.remotePeer?.toString?.() ?? 'unknown'

    try {
      let buffer = new Uint8Array(0)
      const source = stream.source || stream
      for await (const chunk of source) {
        buffer = appendBuffers(buffer, toUint8(chunk))
        if (buffer.length >= 4) {
          const len = readU32BE(buffer, 0)
          if (len > MAX_FRAME_LEN) { warn(`Frame too large: ${len}`); return }
          if (buffer.length >= 4 + len) {
            const payload = buffer.subarray(4, 4 + len)
            const msg = deserializeMessage(payload)
            log(`Message from ${remotePeer.slice(0, 20)}...: ${msg.body}`)
            if (onMessage) onMessage(msg)

            const ack = createAckMessage(node.peerId.toString(), msg)
            const framed = encodeFrame(serializeMessage(ack))
            stream.send(framed)
            break
          }
        }
      }
    } catch (err) {
      warn(`Chat handler error: ${err?.message ?? err}`)
    } finally {
      try { await stream.close() } catch {}
    }
  }, { runOnLimitedConnection: true })
}

export async function sendJsonMessage(node, targetPeerId, body) {
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), CHAT_TIMEOUT_MS)

  let stream = null
  try {
    stream = await node.dialProtocol(peerIdFromString(targetPeerId), CHAT_PROTOCOL, {
      signal: controller.signal,
      runOnLimitedConnection: true
    })

    const msg = createChatMessage(node.peerId.toString(), targetPeerId, body)
    const framed = encodeFrame(serializeMessage(msg))
    stream.send(framed)

    // Read ack
    let buffer = new Uint8Array(0)
    const source = stream.source || stream
    for await (const chunk of source) {
      buffer = appendBuffers(buffer, toUint8(chunk))
      if (buffer.length >= 4) {
        const len = readU32BE(buffer, 0)
        if (buffer.length >= 4 + len) {
          return { sent: msg, ack: deserializeMessage(buffer.subarray(4, 4 + len)) }
        }
      }
    }
    throw new Error('Stream ended before ack')
  } finally {
    clearTimeout(timer)
    try { if (stream?.close) await stream.close() } catch {}
  }
}

// ============================================================================
// Inbox Integration
// ============================================================================

async function checkInbox(node) {
  if (!RELAY_PEER_ID) { log('No relay peer ID, skipping inbox'); return }
  try {
    const response = await retrieveFromInbox(node, peerIdFromString(RELAY_PEER_ID))
    if (response.status === ResponseStatus.OK && response.messages?.length > 0) {
      log(`Received ${response.messages.length} offline message(s):`)
      for (const msg of response.messages) {
        const time = new Date(msg.timestamp).toLocaleTimeString()
        console.log(`  [${time}] from ${msg.from.slice(0, 20)}...: ${msg.message}`)
      }
    } else if (response.status === ResponseStatus.NO_MESSAGES) {
      log('No offline messages')
    }
  } catch (err) {
    warn(`Inbox check failed: ${err?.message ?? err}`)
  }
}

async function storeOfflineMessage(node, toPeerId, message) {
  if (!RELAY_PEER_ID) return false
  try {
    const response = await storeInInbox(node, peerIdFromString(RELAY_PEER_ID), toPeerId, message)
    if (response.status === ResponseStatus.OK) { log('Message stored in inbox'); return true }
  } catch (err) { warn(`Inbox store failed: ${err?.message ?? err}`) }
  return false
}

async function sendWithFallback(node, targetPeerId, body) {
  try {
    const { sent, ack } = await sendJsonMessage(node, targetPeerId, body)
    log(`Ack: ${ack.body}`)
  } catch (err) {
    warn(`Direct send failed: ${err?.message ?? err}`)
    log('Attempting inbox fallback...')
    const stored = await storeOfflineMessage(node, targetPeerId, body)
    if (stored) log('Message stored in inbox for offline delivery')
  }
}

// ============================================================================
// Main
// ============================================================================

async function main() {
  const args = process.argv.slice(2)
  const targetPeerId = args[0] || null
  const oneShotMessage = args.length > 1 ? args.slice(1).join(' ') : null

  log('Loading identity (hardcoded)...')
  const { privateKey, peerId } = loadIdentity()
  log(`PeerId: ${peerId.toString()}`)

  log('Creating node...')
  const node = await createNode(privateKey)

  // Setup JSON chat handler
  setupJsonChatHandler(node, (msg) => {
    // Messages are already logged by the handler
  })

  // Connection tracking
  const connectedPeers = new Set()
  node.addEventListener('peer:connect', (evt) => { connectedPeers.add(evt.detail.toString()); log(`Connected: ${evt.detail}`) })
  node.addEventListener('peer:disconnect', (evt) => { connectedPeers.delete(evt.detail.toString()); log(`Disconnected: ${evt.detail}`) })

  await node.start()
  log('Node started')

  // Dial relay
  log('Connecting to relay...')
  try {
    await node.dial(multiaddr(RELAY_ADDRESS), { signal: AbortSignal.timeout(20000) })
    log('Relay connected')
  } catch (err) { warn(`Relay connection failed: ${err?.message ?? err}`) }

  // Wait for circuit addresses
  try {
    const circuitAddrs = await waitForCircuitAddresses(node, RELAY_TIMEOUT_MS)
    log('Circuit addresses:')
    circuitAddrs.forEach(a => log(`  ${a.toString()}`))
  } catch (err) { warn(`No circuit addresses: ${err?.message ?? err}`) }

  // Check inbox
  await checkInbox(node)

  // Register on rendezvous
  const myNamespace = `mknoon:chat:${peerId.toString()}`
  log(`Namespace: ${myNamespace}`)
  const registrationAbort = new AbortController()
  void registerForever(node, myNamespace, RENDEZVOUS_POINTS[0], registrationAbort.signal)

  // Discover and connect to target peer
  if (targetPeerId) {
    log(`Target peer: ${targetPeerId}`)
    const targetNamespace = `mknoon:chat:${targetPeerId}`
    log('Discovering target peer...')
    const result = await discoverTarget(node, targetNamespace, targetPeerId)
    if (result) {
      log('Discovered addresses:')
      result.multiaddrs.forEach(a => log(`  ${a.toString()}`))
      await node.peerStore.merge(peerIdFromString(targetPeerId), { multiaddrs: result.multiaddrs })
      for (const ma of result.multiaddrs) {
        try { await node.dial(ma, { signal: AbortSignal.timeout(30000) }); log('Connected to target'); break }
        catch (err) { warn(`Dial failed: ${err?.message ?? err}`) }
      }
    } else { warn('Could not discover target peer') }
  }

  // One-shot message mode
  if (oneShotMessage && targetPeerId) {
    await sendWithFallback(node, targetPeerId, oneShotMessage)
    await node.stop()
    process.exit(0)
  }

  // Interactive mode
  const rl = createInterface({ input: process.stdin, output: process.stdout })
  console.log('\nCommands:')
  console.log('  /send <peer-id> <message>  Send JSON message to peer')
  console.log('  /dial <peer-id>            Discover and connect to peer')
  console.log('  /peers                     List connected peers')
  console.log('  /inbox                     Check inbox')
  console.log('  /exit                      Quit\n')
  if (targetPeerId) console.log(`Type a message to send to ${targetPeerId.slice(0, 20)}...\n`)
  else console.log('Use /send <peer-id> <message> or /dial <peer-id> to connect\n')

  let pending = Promise.resolve()

  rl.on('line', (line) => {
    const input = line.trim()
    if (!input) return

    pending = pending.then(async () => {
      if (input.startsWith('/')) {
        const [cmd, ...cmdArgs] = input.slice(1).split(' ')
        switch (cmd) {
          case 'exit': case 'quit': rl.close(); return
          case 'peers': {
            const peers = [...connectedPeers].filter(p => p !== RELAY_PEER_ID)
            if (peers.length === 0) log('No peers connected')
            else { log('Connected peers:'); peers.forEach(p => log(`  ${p}`)) }
            return
          }
          case 'inbox': await checkInbox(node); return
          case 'dial': {
            if (!cmdArgs[0]) { warn('Usage: /dial <peer-id>'); return }
            const dialId = cmdArgs[0]
            log(`Discovering ${dialId}...`)
            const disc = await discoverTarget(node, `mknoon:chat:${dialId}`, dialId)
            if (disc) {
              await node.peerStore.merge(peerIdFromString(dialId), { multiaddrs: disc.multiaddrs })
              for (const ma of disc.multiaddrs) {
                try { await node.dial(ma, { signal: AbortSignal.timeout(30000) }); log(`Connected to ${dialId}`); break }
                catch (err) { warn(`Dial failed: ${err?.message ?? err}`) }
              }
            } else { warn('Could not discover peer') }
            return
          }
          case 'send': {
            if (cmdArgs.length < 2) { warn('Usage: /send <peer-id> <message>'); return }
            await sendWithFallback(node, cmdArgs[0], cmdArgs.slice(1).join(' '))
            return
          }
          default: warn(`Unknown command: ${cmd}`); return
        }
      }
      if (targetPeerId) await sendWithFallback(node, targetPeerId, input)
      else warn('No target peer. Use /send <peer-id> <message> or /dial <peer-id>')
    }).catch(err => console.error('Error:', err))
  })

  const shutdown = async () => {
    registrationAbort.abort()
    rl.close()
    await pending
    await node.stop()
    process.exit(0)
  }
  process.on('SIGINT', shutdown)
  process.on('SIGTERM', shutdown)
  rl.on('close', shutdown)
}

// Auto-run only when executed directly
const __filename = fileURLToPath(import.meta.url)
if (process.argv[1] && resolve(process.argv[1]) === resolve(__filename)) {
  main().catch(err => { console.error('Fatal:', err); process.exit(1) })
}
