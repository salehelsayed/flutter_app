package node

import (
	"os"
	"time"
)

const (
	// DefaultRelayAddress is the relay server multiaddr (WSS).
	// Uses /dns/ (not /dns4/) to resolve both A and AAAA records for dual-stack.
	DefaultRelayAddress = "/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g"

	// DefaultQUICRelay is the relay server multiaddr (QUIC).
	// Uses /dns/ (not /dns4/) to resolve both A and AAAA records for dual-stack.
	DefaultQUICRelay = "/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g"

	// DefaultRendezvousNamespace prefix for chat discovery.
	RendezvousPrefix = "mknoon:chat:"

	// Protocol IDs matching the relay server.
	RendezvousProtocol              = "/canvas/rendezvous/1.0.0"
	InboxProtocol                   = "/mknoon/inbox/1.0.0"
	ChatProtocol                    = "/mknoon/chat/1.0.0"
	MediaProtocol                   = "/mknoon/media/1.0.0"
	GroupValidationFeedbackProtocol = "/mknoon/group-validation-feedback/1.0.0"
	// MediaLANProtocol (FDC-15) is the peer-to-peer LAN media byte stream — a
	// NEW protocol id, DISTINCT from the relay-CDN MediaProtocol above (which is
	// node→relay only). 1:1 media ciphertext rides this over a non-circuit
	// (direct) libp2p conn instead of the plaintext ws://+HTTP-PUT LAN leg.
	MediaLANProtocol = "/mknoon/media-lan/1.0.0"

	// Timeouts.
	DialTimeout                         = 15 * time.Second // Relay server connection
	PeerDialTimeout                     = 2 * time.Second  // Peer-to-peer dial
	RelayProbeTimeout                   = 5 * time.Second  // Relay probe via circuit
	SendTimeout                         = 15 * time.Second
	DiscoverTimeout                     = 10 * time.Second
	InboxTimeout                        = 15 * time.Second
	MediaTimeout                        = 5 * time.Minute  // large files need generous timeout
	MediaIdleTimeout                    = 10 * time.Second // stall = no bytes for this long
	CircuitAddressWaitTimeout           = 10 * time.Second
	DefaultAutoRelayRetryCadence        = 5 * time.Second
	ForegroundAutoRelayRetryCadence     = 1 * time.Second
	ForegroundRelayDialTimeout          = 3 * time.Second
	ForegroundRelayReserveTimeout       = 3 * time.Second
	ForegroundCircuitAddressWaitTimeout = 3 * time.Second

	// PubSub.
	GroupTopicPrefix = "/mknoon/group/"
	PubSubTimeout    = 30 * time.Second
	// KeyRotationGracePeriod is the DEFAULT key-rotation grace window. It now
	// constrains only which prior epoch a node will sign/publish under (the
	// receive path anchors to keys held in the ring, not the clock). Bumped from
	// 30s to 10m so a slow rollout still publishes acceptably under the prior
	// epoch. Override per-node via NodeConfig.KeyRotationGracePeriod.
	KeyRotationGracePeriod = 10 * time.Minute
	// RetainedEpochKeys bounds the held-keys ring: a node decrypts/verifies any
	// of the last K epochs it legitimately held. Past K, the oldest is evicted
	// (forward-secrecy bound).
	RetainedEpochKeys                 = 5
	GroupDiscoveryInterval            = 30 * time.Second // periodic rendezvous re-discovery for group peers
	GroupDiscoveryWarmInterval        = 3 * time.Second  // short foreground retry window while a group is only partially connected
	GroupDiscoveryWarmRetries         = 3                // bounded warm retries before falling back to slower background cadence
	MaxGroupDiscoveryBackoff          = 1 * time.Minute  // cap retry stalls; multi-minute fanout gaps are too slow for active chat
	GroupDiscoveryConcurrency         = 5                // max concurrent discovery goroutines
	GroupDiscoveryJitterFactor        = 4                // +/-25% interval jitter
	GroupRecoveryInitialJitter        = 3 * time.Second  // initial stagger for resume/watchdog bursts
	GroupPublishZeroPeerSettleWait    = 150 * time.Millisecond
	GroupPublishPartialPeerSettleWait = 500 * time.Millisecond
	GroupPublishPeerPoll              = 25 * time.Millisecond

	// Personal rendezvous registration.
	PersonalRendezvousRegistrationTTL     = 2 * time.Hour
	DefaultPersonalRendezvousRefreshEvery = PersonalRendezvousRegistrationTTL / 4

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
	StreamWriteDeadline  = 10 * time.Second
	StreamReadDeadline   = 10 * time.Second
	InboundReadDeadline  = 15 * time.Second // inbound reads may come from slow peers
	DirectConfirmTimeout = 2 * time.Second  // must stay within interactive direct-send budget

	// FDC-11 — bonsoir-fed libp2p LAN-direct dial.
	// LANDirectIdentifyBudget is the per-leg dial+identify budget for a same-WiFi
	// LAN-direct QUIC dial — FDC-S2 Option A: max(p95 rounded↑250ms, 750ms); the
	// measured p95 was 2ms so the 750ms floor governs. Fits interactiveLocalBudget
	// (1500ms) with margin.
	LANDirectIdentifyBudget = 750 * time.Millisecond
	// LANDialWarmCooldown debounces repeated bonsoir finds for the same peer so a
	// flapping/offline LAN peer cannot tight-loop the swarm into its 5s→5m dial
	// backoff (proposal §6.1, §10).
	LANDialWarmCooldown = 5 * time.Second

	// MaxLANMediaBytes (FDC-15) bounds a single libp2p-LAN media transfer so a
	// malicious framed header cannot drive an unbounded disk write before the
	// body is streamed. handleIncomingLANMedia rejects an offer whose header
	// `size` exceeds this BEFORE any io.CopyN runs. It matches the WS
	// LocalMediaServer.maxFileSize (5 GB) so any media that delivers over the
	// existing WS LAN leg also delivers over the libp2p-LAN lane. The transfer
	// streams to a temp file (never buffered in memory) and is additionally
	// bounded by MediaTimeout / MediaIdleTimeout.
	MaxLANMediaBytes int64 = 5 * 1024 * 1024 * 1024 // 5 GB, matches LocalMediaServer.maxFileSize

	// UpgradeAbandonTimeout (FDC-12 — opportunistic DCUtR relay->direct upgrade) is
	// the per-leg budget after which a DCUtR upgrade dial is abandoned back to the
	// relay leg (the user never waits on the punch; relay + inbox always backstop).
	// FDC-S2 Option A: max(p95 dial+identify rounded↑250ms, 750ms); the measured
	// direct-QUIC identify p95 was 2ms so the 750ms floor governs — the SAME single
	// source of truth as FDC-11's LANDirectIdentifyBudget (both derive from the one
	// FDC-S2 measurement). The production abandon-dial path is DEVICE-only and
	// gated by EnableDcutrUpgrade.
	UpgradeAbandonTimeout = 750 * time.Millisecond
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

// DefaultRelayAddresses returns the shipped default relay pool: the default
// relay peer reachable over BOTH WSS and QUIC transports. Both addresses point
// at the same relay peer, so the relay selector merges them into one relay with
// two transport addresses — transport redundancy that removes the single-
// transport SPOF without requiring a second relay host. Once ops provisions
// relay #2, its distinct WSS+QUIC addresses are appended here (or injected via
// NodeConfig.RelayAddresses) to extend the pool to multiple peers.
//
// WSS (DefaultRelayAddress) is listed FIRST so it remains the surviving address
// when EnableMultiRelayRouting is off — limitRelayAddresses truncates to the
// first address, order-preserving, with no sort.
func DefaultRelayAddresses() []string {
	return []string{DefaultRelayAddress, DefaultQUICRelay}
}

// NodeConfig holds the configuration for starting a Node.
type NodeConfig struct {
	PrivateKeyHex                     string        // Ed25519 private key as hex string
	RelayAddresses                    []string      // nil => defaults, explicit empty slice => disable startup relay warmup
	Namespace                         string        // e.g. "mknoon:chat:<peerId>"
	AutoRegister                      bool          // Auto-register on rendezvous after relay connect
	PersonalRendezvousRefreshInterval time.Duration // 0 → DefaultPersonalRendezvousRefreshEvery
	KeyRotationGracePeriod            time.Duration // 0 → KeyRotationGracePeriod default; sign/publish-under-prev-epoch window
	ListenPort                        int           // 0 for random
	FeatureFlags                      *FeatureFlags // Rollout flags; nil → all enabled
	// ProcessStartEpochMs is the Dart-side process-start wall-clock epoch
	// (DateTime.now().millisecondsSinceEpoch captured at the first line of
	// main()). FDC-S1 instrumentation-only: used solely to compute
	// sinceProcessStartMs on the node:startup_timing / relay:reservation_timing /
	// circuit_address:timing emits so cold-start milestones share one clock with
	// Dart. 0 => not provided (caller predates FDC-S1); never feeds timeout logic.
	ProcessStartEpochMs int64
}

// EffectiveFlags returns the feature flags from this config, falling back
// to DefaultFeatureFlags() when FeatureFlags is nil.
func (c *NodeConfig) EffectiveFlags() FeatureFlags {
	if c.FeatureFlags != nil {
		return *c.FeatureFlags
	}
	return DefaultFeatureFlags()
}

// PersonalRendezvousRefreshEvery returns the effective interval for periodic
// personal rendezvous re-registration.
func (c *NodeConfig) PersonalRendezvousRefreshEvery() time.Duration {
	if c != nil && c.PersonalRendezvousRefreshInterval > 0 {
		return c.PersonalRendezvousRefreshInterval
	}
	return DefaultPersonalRendezvousRefreshEvery
}

// EffectiveKeyRotationGracePeriod returns the effective key-rotation grace
// window, falling back to the KeyRotationGracePeriod default when unset (nil
// config or zero value). This now constrains only sign/publish-under-prev-epoch
// behaviour; the receive path accepts any epoch still held in the ring.
func (c *NodeConfig) EffectiveKeyRotationGracePeriod() time.Duration {
	if c != nil && c.KeyRotationGracePeriod > 0 {
		return c.KeyRotationGracePeriod
	}
	return KeyRotationGracePeriod
}

// NodeState represents the current state of the node.
type NodeState struct {
	PeerId      string   `json:"peerId"`
	IsStarted   bool     `json:"isStarted"`
	Addresses   []string `json:"addresses"`
	Connections int      `json:"connections"`
}
