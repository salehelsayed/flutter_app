package main

// InboxBackend abstracts the storage layer for 1:1 inbox messages.
type InboxBackend interface {
	// Store appends a message to a peer's inbox.
	Store(toPeerId string, entry inboxMessage)

	// Retrieve returns up to limit messages for a peer in FIFO order
	// and removes them from the store (destructive read).
	// Returns the messages and whether more messages remain (hasMore).
	Retrieve(peerId string, limit int) (messages []inboxMessage, hasMore bool)

	// Count returns the number of pending messages for a peer.
	Count(peerId string) int

	// Stats returns total peers with pending messages and total message count.
	Stats() (totalPeers int, totalMessages int)
}

// PushTokenBackend abstracts push token storage so tokens survive server restarts.
type PushTokenBackend interface {
	// RegisterToken stores or updates a push token for a peer.
	RegisterToken(peerId string, token string, platform string)

	// UnregisterToken removes the push token for a peer.
	UnregisterToken(peerId string)

	// LookupToken returns the token entry for a peer, or nil if not found.
	LookupToken(peerId string) *tokenEntry

	// TokenCount returns the number of registered tokens.
	TokenCount() int
}
