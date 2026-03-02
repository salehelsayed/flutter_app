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
	//   "message:received"        — { from, to, content, timestamp, isIncoming }
	//   "peer:connected"          — { peerId, address, direction }
	//   "peer:disconnected"       — { peerId }
	//   "addresses:updated"       — { listenAddresses, circuitAddresses }
	//   "group_message:received"  — { groupId, senderId, senderUsername, keyEpoch, text, timestamp }
	OnEvent(jsonString string)
}
