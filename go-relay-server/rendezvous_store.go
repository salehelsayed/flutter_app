package main

// RendezvousBackend abstracts the storage layer for rendezvous registrations.
// The in-memory map in RendezvousStore is the default dev/test backend.
// A shared backend (e.g. Redis) can replace it for multi-relay deployments.
type RendezvousBackend interface {
	// Register stores or refreshes a peer registration with TTL (seconds).
	Register(ns string, peerId string, signedPeerRecord []byte, ttlSeconds uint64)

	// Unregister removes a single peer from a namespace.
	Unregister(ns string, peerId string)

	// Discover returns up to limit non-expired registrations for a namespace,
	// excluding the requesting peer.
	Discover(ns string, requestingPeer string, limit uint64) []Registration

	// Cleanup removes expired entries. For shared backends this may be a no-op
	// if TTL is enforced natively.
	Cleanup()

	// Stats returns the number of active namespaces and total peer registrations.
	Stats() (namespaces int, totalPeers int)
}
