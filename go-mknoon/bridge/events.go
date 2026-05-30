package bridge

// EventCallback is the interface that Flutter implements to receive
// push events from the Go layer (e.g., incoming messages, peer connects).
//
// gomobile will generate the platform-specific protocol/interface.
type EventCallback interface {
	// OnEvent receives a JSON string with the event data.
	// Format: { "event": "<name>", "data": { ... } }
	//
	// Events:
	//   "message:received"        — { from, to, content, timestamp, isIncoming, transport }
	//   "peer:connected"          — { peerId, address, direction }
	//   "peer:disconnected"       — { peerId }
	//   "addresses:updated"       — { listenAddresses, circuitAddresses }
	//   "relay:state"             — { relayState, healthyRelayCount, watchdogRestartCount, ... }
	//   "media:upload_progress"   — { id, sentBytes, totalBytes, toPeerId }
	//   "group_message:received"  — { groupId, senderId, transportPeerId, senderUsername, keyEpoch, text, timestamp }
	//   "holepunch:attempt"       — { step, attempt, rttMs?, remotePeerShort }
	//   "holepunch:success"       — { step, fromTransport, toTransport, elapsedMs, remotePeerShort }
	//   "holepunch:failure"       — { step, error, elapsedMs?, remotePeerShort }
	//   "transport:upgraded"      — { fromTransport, toTransport, elapsedMs, remotePeerShort }
	OnEvent(jsonString string)
}
