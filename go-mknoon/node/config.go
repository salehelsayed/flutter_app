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
	MediaProtocol      = "/mknoon/media/1.0.0"

	// Timeouts.
	DialTimeout       = 15 * time.Second // Relay server connection
	PeerDialTimeout   = 2 * time.Second  // Peer-to-peer dial
	RelayProbeTimeout = 5 * time.Second  // Relay probe via circuit
	SendTimeout       = 15 * time.Second
	DiscoverTimeout   = 10 * time.Second
	InboxTimeout      = 15 * time.Second
	MediaTimeout      = 5 * time.Minute // large files need generous timeout

	// PubSub.
	GroupTopicPrefix           = "/mknoon/group/"
	PubSubTimeout              = 30 * time.Second
	GroupDiscoveryInterval     = 30 * time.Second // periodic rendezvous re-discovery for group peers
	MaxGroupDiscoveryBackoff   = 5 * time.Minute  // max backoff for group peer discovery
	GroupDiscoveryConcurrency  = 5                // max concurrent discovery goroutines
	GroupDiscoveryJitterFactor = 4                // +/-25% interval jitter
	GroupRecoveryInitialJitter = 3 * time.Second  // initial stagger for resume/watchdog bursts

	// Inbox framing.
	MaxFrameLen = 128 * 1024 // 128 KB, matches relay server

	// Interactive (foreground) timeouts — used when a user action is
	// waiting on the result (e.g. send-message, discover contact).
	InteractiveDialTimeout     = 4 * time.Second
	InteractiveSendTimeout     = 3 * time.Second
	InteractiveDiscoverTimeout = 2 * time.Second
	InteractiveInboxTimeout    = 3 * time.Second

	// Background discover can afford more patience (e.g. periodic
	// group peer re-discovery that runs on a 30 s ticker).
	BackgroundDiscoverTimeout = 10 * time.Second

	// Stream-level deadlines applied after NewStream succeeds.
	// These prevent hung connections from blocking goroutines forever.
	StreamWriteDeadline = 10 * time.Second
	StreamReadDeadline  = 10 * time.Second
	InboundReadDeadline = 15 * time.Second // inbound reads may come from slow peers
)

// TimeoutProfile bundles per-operation timeout durations for a given
// execution context (interactive foreground vs background sync).
type TimeoutProfile struct {
	Dial     time.Duration
	Send     time.Duration
	Discover time.Duration
	Inbox    time.Duration
}

// InteractiveTimeouts returns the timeout profile tuned for user-facing
// actions where responsiveness matters more than retry surface.
func InteractiveTimeouts() TimeoutProfile {
	return TimeoutProfile{
		Dial:     InteractiveDialTimeout,
		Send:     InteractiveSendTimeout,
		Discover: InteractiveDiscoverTimeout,
		Inbox:    InteractiveInboxTimeout,
	}
}

// BackgroundTimeouts returns the timeout profile for background work
// (periodic discovery, store-and-forward retrieval) where a generous
// timeout is acceptable.
func BackgroundTimeouts() TimeoutProfile {
	return TimeoutProfile{
		Dial:     DialTimeout,
		Send:     SendTimeout,
		Discover: BackgroundDiscoverTimeout,
		Inbox:    InboxTimeout,
	}
}

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
	PrivateKeyHex  string        // Ed25519 private key as hex string
	RelayAddresses []string      // Multiaddr strings for relay servers
	Namespace      string        // e.g. "mknoon:chat:<peerId>"
	AutoRegister   bool          // Auto-register on rendezvous after relay connect
	ListenPort     int           // 0 for random
	FeatureFlags   *FeatureFlags // Rollout flags; nil → all enabled
}

// EffectiveFlags returns the feature flags from this config, falling back
// to DefaultFeatureFlags() when FeatureFlags is nil.
func (c *NodeConfig) EffectiveFlags() FeatureFlags {
	if c.FeatureFlags != nil {
		return *c.FeatureFlags
	}
	return DefaultFeatureFlags()
}

// NodeState represents the current state of the node.
type NodeState struct {
	PeerId      string   `json:"peerId"`
	IsStarted   bool     `json:"isStarted"`
	Addresses   []string `json:"addresses"`
	Connections int      `json:"connections"`
}
