/**
 * p2p/handlers.ts
 *
 * Message handlers and connection event management:
 * - Chat protocol handler (incoming messages)
 * - Send message function
 * - Connection event listeners
 * - Inbox integration
 */
import { peerIdFromString } from '@libp2p/peer-id';
// Protocol identifiers
export const CHAT_PROTOCOL = '/mknoon/chat/1.0.0';
// Framing constants
const MAX_FRAME_LEN = 128 * 1024;
// Text encoding
const encoder = new TextEncoder();
const decoder = new TextDecoder();
/**
 * Convert various chunk types to Uint8Array
 */
function toUint8(chunk) {
    if (chunk == null)
        return new Uint8Array();
    if (chunk instanceof Uint8Array) {
        // Copy to ensure we have ArrayBuffer, not SharedArrayBuffer
        return new Uint8Array(chunk);
    }
    if (ArrayBuffer.isView(chunk)) {
        const view = chunk;
        const copy = new Uint8Array(view.byteLength);
        copy.set(new Uint8Array(view.buffer, view.byteOffset, view.byteLength));
        return copy;
    }
    if (chunk instanceof ArrayBuffer)
        return new Uint8Array(chunk);
    if (typeof chunk.subarray === 'function') {
        const sub = chunk.subarray();
        return new Uint8Array(sub);
    }
    if (typeof chunk.slice === 'function')
        return Uint8Array.from(chunk.slice());
    throw new Error(`Unsupported chunk type: ${typeof chunk}`);
}
/**
 * Append two Uint8Arrays
 */
function appendBuffers(a, b) {
    if (a.length === 0)
        return b;
    if (b.length === 0)
        return a;
    const out = new Uint8Array(a.length + b.length);
    out.set(a, 0);
    out.set(b, a.length);
    return out;
}
/**
 * Encode a message with 4-byte big-endian length prefix
 */
export function encodeFrame(payload) {
    if (payload.length > MAX_FRAME_LEN) {
        throw new Error(`Frame too large (${payload.length} bytes)`);
    }
    const out = new Uint8Array(4 + payload.length);
    const len = payload.length >>> 0;
    out[0] = (len >>> 24) & 0xff;
    out[1] = (len >>> 16) & 0xff;
    out[2] = (len >>> 8) & 0xff;
    out[3] = len & 0xff;
    out.set(payload, 4);
    return out;
}
/**
 * Read 4-byte big-endian length
 */
function readU32BE(buf, offset = 0) {
    return (((buf[offset] << 24) >>> 0) +
        (buf[offset + 1] << 16) +
        (buf[offset + 2] << 8) +
        buf[offset + 3]) >>> 0;
}
/**
 * Read one complete frame from a stream
 */
export async function readOneFrame(stream) {
    const source = stream?.source && typeof stream.source[Symbol.asyncIterator] === 'function'
        ? stream.source
        : stream && typeof stream[Symbol.asyncIterator] === 'function'
            ? stream
            : null;
    if (!source) {
        throw new Error('Stream is not async iterable');
    }
    let buffer = new Uint8Array(0);
    for await (const chunk of source) {
        buffer = appendBuffers(buffer, toUint8(chunk));
        if (buffer.length < 4)
            continue;
        const len = readU32BE(buffer, 0);
        if (len > MAX_FRAME_LEN) {
            throw new Error(`Incoming frame too large: ${len} bytes`);
        }
        const needed = 4 + len;
        if (buffer.length < needed)
            continue;
        return buffer.subarray(4, needed);
    }
    throw new Error('Stream ended before a full frame was received');
}
/**
 * Write one frame to a stream
 */
export async function writeOneFrame(stream, payload) {
    const framed = encodeFrame(payload);
    if (typeof stream?.sink === 'function') {
        await stream.sink((async function* () {
            yield framed;
        })());
        return;
    }
    if (typeof stream?.send === 'function') {
        const backpressure = stream.send(framed) === false;
        if (backpressure && typeof stream.onDrain === 'function') {
            await stream.onDrain();
        }
        return;
    }
    throw new Error('Stream is not writable');
}
/**
 * Close a stream safely
 */
async function closeStream(stream) {
    try {
        if (stream && typeof stream.close === 'function') {
            await stream.close();
        }
    }
    catch { }
}
/**
 * Setup the chat protocol handler for incoming messages
 */
export function setupChatHandler(node, onMessage, logger = console) {
    node.handle(CHAT_PROTOCOL, async (incomingData) => {
        const stream = incomingData?.stream ?? incomingData;
        const connection = incomingData?.connection;
        const remotePeer = connection?.remotePeer?.toString?.() ?? 'unknown';
        try {
            // Read the incoming message
            let buffer = new Uint8Array(0);
            const source = stream.source || stream;
            for await (const chunk of source) {
                buffer = appendBuffers(buffer, toUint8(chunk));
                if (buffer.length >= 4) {
                    const len = readU32BE(buffer, 0);
                    if (len > MAX_FRAME_LEN) {
                        logger.warn(`[Handlers] Frame too large: ${len} bytes`);
                        return;
                    }
                    if (buffer.length >= 4 + len) {
                        const payload = buffer.subarray(4, 4 + len);
                        const content = decoder.decode(payload);
                        logger.log(`[Handlers] Message from ${remotePeer}: ${content}`);
                        // Create message object
                        const message = {
                            from: remotePeer,
                            to: node.peerId.toString(),
                            content,
                            timestamp: Date.now()
                        };
                        // Call handler if provided
                        if (onMessage) {
                            await onMessage(message);
                        }
                        // Also call node's message handler if set
                        if (node.mknoon.onMessage) {
                            await node.mknoon.onMessage(message);
                        }
                        // Emit event
                        if (node.mknoon.onEvent) {
                            node.mknoon.onEvent({
                                type: 'message:received',
                                timestamp: Date.now(),
                                data: message
                            });
                        }
                        // Send acknowledgment reply
                        const reply = `received: ${content}`;
                        const replyBytes = encoder.encode(reply);
                        const framed = encodeFrame(replyBytes);
                        stream.send(framed);
                        break;
                    }
                }
            }
        }
        catch (err) {
            logger.warn(`[Handlers] Chat error from ${remotePeer}:`, err?.message ?? err);
        }
        finally {
            await closeStream(stream);
        }
    }, { runOnLimitedConnection: true });
}
/**
 * Send a chat message to a peer
 */
export async function sendMessage(node, targetPeerId, message, timeoutMs = 10000, logger = console) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    let stream = null;
    try {
        stream = await node.dialProtocol(peerIdFromString(targetPeerId), CHAT_PROTOCOL, {
            signal: controller.signal,
            runOnLimitedConnection: true
        });
        await writeOneFrame(stream, encoder.encode(message));
        const replyBytes = await readOneFrame(stream);
        const reply = decoder.decode(replyBytes);
        logger.log(`[Handlers] Sent to ${targetPeerId}, reply: ${reply}`);
        // Emit event if node has handler
        const mknoonNode = node;
        if (mknoonNode.mknoon?.onEvent) {
            mknoonNode.mknoon.onEvent({
                type: 'message:sent',
                timestamp: Date.now(),
                data: {
                    to: targetPeerId,
                    content: message,
                    reply
                }
            });
        }
        return reply;
    }
    finally {
        clearTimeout(timer);
        if (stream) {
            await closeStream(stream);
        }
    }
}
/**
 * Setup connection event listeners
 */
export function setupConnectionListeners(node, onConnect, onDisconnect, logger = console) {
    node.addEventListener('peer:connect', (evt) => {
        const peerId = evt.detail.toString();
        logger.log(`[Handlers] Connected: ${peerId}`);
        const connections = node.getConnections(evt.detail);
        const conn = connections[0];
        const state = {
            peerId,
            multiaddrs: conn ? [conn.remoteAddr.toString()] : [],
            direction: conn?.direction ?? 'inbound',
            status: 'connected',
            connectedAt: Date.now()
        };
        if (onConnect) {
            onConnect(state);
        }
        if (node.mknoon.onEvent) {
            node.mknoon.onEvent({
                type: 'peer:connected',
                timestamp: Date.now(),
                data: state
            });
        }
    });
    node.addEventListener('peer:disconnect', (evt) => {
        const peerId = evt.detail.toString();
        logger.log(`[Handlers] Disconnected: ${peerId}`);
        const state = {
            peerId,
            multiaddrs: [],
            direction: 'inbound',
            status: 'disconnected'
        };
        if (onDisconnect) {
            onDisconnect(state);
        }
        if (node.mknoon.onEvent) {
            node.mknoon.onEvent({
                type: 'peer:disconnected',
                timestamp: Date.now(),
                data: state
            });
        }
    });
}
/**
 * Remove the chat protocol handler
 */
export async function removeChatHandler(node) {
    await node.unhandle(CHAT_PROTOCOL);
}
//# sourceMappingURL=handlers.js.map