package node

import (
	"os"
	"time"
)

const (
	// DefaultRelayAddress is the relay server multiaddr (WSS).
	DefaultRelayAddress = "/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g"

	// DefaultQUICRelay is the relay server multiaddr (QUIC).
	DefaultQUICRelay = "/dns4/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g"

	// DefaultRendezvousNamespace prefix for chat discovery.
	RendezvousPrefix = "mknoon:chat:"

	// Protocol IDs matching the relay server.
	RendezvousProtocol = "/canvas/rendezvous/1.0.0"
	InboxProtocol      = "/mknoon/inbox/1.0.0"
	ChatProtocol       = "/mknoon/chat/1.0.0"

	// Timeouts.
	DialTimeout     = 30 * time.Second
	SendTimeout     = 15 * time.Second
	DiscoverTimeout = 10 * time.Second
	InboxTimeout    = 15 * time.Second

	// Inbox framing.
	MaxFrameLen = 128 * 1024 // 128 KB, matches relay server
)

// RelayAddress returns the QUIC relay multiaddr, overridable via
// MKNOON_RELAY_ADDR for testing against local or alternative relays.
func RelayAddress() string {
	if addr := os.Getenv("MKNOON_RELAY_ADDR"); addr != "" {
		return addr
	}
	return DefaultQUICRelay
}

// NodeConfig holds the configuration for starting a Node.
type NodeConfig struct {
	PrivateKeyHex  string   // Ed25519 private key as hex string
	RelayAddresses []string // Multiaddr strings for relay servers
	Namespace      string   // e.g. "mknoon:chat:<peerId>"
	AutoRegister   bool     // Auto-register on rendezvous after relay connect
	ListenPort     int      // 0 for random
}

// NodeState represents the current state of the node.
type NodeState struct {
	PeerId      string   `json:"peerId"`
	IsStarted   bool     `json:"isStarted"`
	Addresses   []string `json:"addresses"`
	Connections int      `json:"connections"`
}
