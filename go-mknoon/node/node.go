package node

import (
	"context"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"strings"
	"sync"
	"sync/atomic"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/google/uuid"
	"github.com/libp2p/go-libp2p"
	pubsub "github.com/libp2p/go-libp2p-pubsub"
	"github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/event"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/p2p/host/autorelay"
	"github.com/libp2p/go-libp2p/p2p/net/connmgr"
	relayclient "github.com/libp2p/go-libp2p/p2p/protocol/circuitv2/client"
	"github.com/libp2p/go-libp2p/p2p/protocol/holepunch"
	ma "github.com/multiformats/go-multiaddr"
)

// EventCallback is the interface for push events from Go → Flutter.
type EventCallback interface {
	OnEvent(jsonString string)
}

// Node wraps a go-libp2p host with mknoon protocol handlers.
type Node struct {
	mu              sync.RWMutex
	host            host.Host
	ctx             context.Context
	cancel          context.CancelFunc
	peerId          string
	isStarted       bool
	startInProgress bool
	relayAddresses  []string
	relayPeerOrder  []peer.ID
	featureFlags    *FeatureFlags
	namespace       string
	eventCallback   EventCallback
	eventSub        event.Subscription
	connections     map[string]connectionInfo
	// peerSession is the FDC-12 network.Notifiee that keeps connections[peer] on
	// the BEST live conn across a DCUtR relay->direct upgrade (and back). It is
	// registered in Start (after n.host is set) and removed in Stop. nil before
	// Start / after Stop.
	peerSession    *peerSessionNotifiee
	relayReady     chan struct{}
	relayReadyOnce *sync.Once
	startedAt      time.Time   // for startup timing instrumentation
	lastConfig     *NodeConfig // saved for Restart()
	// processStartEpochMs mirrors NodeConfig.ProcessStartEpochMs (the Dart
	// process-start wall-clock epoch). FDC-S1 observation-only: read by
	// sinceProcessStartMs() to stamp cold-start timing emits on Dart's clock.
	// Atomic (CV-50): a relay-warm goroutine spawned by a prior Start() can
	// outlive a Stop() and read this concurrently with the re-Start() write on a
	// reconnect/watchdog/StopStart cycle. 0 => caller predates FDC-S1.
	processStartEpochMs atomic.Int64

	// Phase 4: Relay session manager and event dispatcher.
	relaySessionMgr *RelaySessionManager
	eventDispatcher *EventDispatcher

	// PubSub / Group messaging
	pubsub               *pubsub.PubSub
	groupTopics          map[string]*pubsub.Topic
	groupSubs            map[string]*pubsub.Subscription
	groupConfigs         map[string]*GroupConfig
	groupKeys            map[string]*GroupKeyInfo
	groupSubCtx          map[string]context.CancelFunc
	groupDiscoveryCtx    map[string]context.CancelFunc // per-group rendezvous discovery loop cancellation
	groupDialBackoff     map[string]groupPeerDialState
	groupRecoverySem     chan struct{}
	groupDialSem         chan struct{}
	pubsubRejectDiagMu   sync.Mutex
	pubsubRejectDiagLast map[string]time.Time
	pubsubRejectDiagNow  func() time.Time

	// Test seams for startup timing behavior.
	warmRelayConnectionHook            func(peer.AddrInfo) error
	warmRelayConnectionWithTimeoutHook func(peer.AddrInfo, time.Duration) error
	reserveRelaySlotHook               func(context.Context, host.Host, peer.AddrInfo) (*relayclient.Reservation, error)
	connectRelayHook                   func(context.Context, peer.AddrInfo) error
	waitForCircuitAddressHook          func(time.Duration) bool
	rendezvousRegisterHook             func(string, []string) error
	rendezvousDiscoverHook             func(string, []string) ([]peer.AddrInfo, error)
	rendezvousUnregisterHook           func(string, []string) error
	rendezvousStreamOpenHook           func(context.Context, host.Host, peer.ID) (network.Stream, error)
	dialPeerViaRelayHook               func(string) error
	refreshRelaySessionHook            func() *RecoveryResult
	openChatStreamHook                 func(context.Context, host.Host, peer.ID) (network.Stream, error)
	recoverPeerForSendHook             func(context.Context, host.Host, peer.ID, string) error
	connectPeerForSendHook             func(context.Context, host.Host, peer.AddrInfo) error
	sendNowHook                        func() time.Time
	joinGroupTopicSubscribeHook        func(*pubsub.Topic) (*pubsub.Subscription, error)
	groupInboxRecoverHook              func(error) error
	newHost                            func(NodeConfig, []libp2p.Option) (host.Host, error)
	connectGroupPeerHook               func(peerId string, candidateAddrs []ma.Multiaddr, allowRelayFallback bool) (groupPeerConnectResult, error)
	// Local multi-node tests opt into loopback-only addresses without NAT port
	// mapping so same-process fixtures never depend on a host/VPN interface.
	hermeticLocalNetworkForTests bool

	// Personal rendezvous refresh state.
	personalRendezvousRefreshCancel context.CancelFunc
	personalRendezvousRefreshLoopID uint64
	personalRendezvousRegistering   atomic.Bool

	pendingConfirmsMu            sync.Mutex
	pendingDirectConfirms        map[string]chan directConfirmResult
	directConfirmTimeoutOverride time.Duration // test seam

	// NET-REL-02 Option A test seams (instrument-only).
	// holePunchTracerForTests injects a test-controlled holepunch.EventTracer;
	// nil in production (the real emitting tracer is installed instead).
	holePunchTracerForTests holepunch.EventTracer
	// forcePublicReachabilityForTests swaps ForceReachabilityPrivate() for
	// ForceReachabilityPublic() so PROTOCOL-feasibility tests can drive a real
	// loopback hole punch; false in production (private reachability untouched).
	forcePublicReachabilityForTests bool

	// FDC-11: bonsoir-fed libp2p LAN-direct dial. Wired in Start() once n.host is
	// set, nilled in Stop(). Holds the per-peer warm cooldown + dial. See
	// lan_dial.go / HandleLANPeerFound.
	lanDialHandler *lanDialHandler

	// FDC-15: inbound libp2p-LAN media (MediaLANProtocol) dedup set. A media id
	// is claimed atomically before its body is staged so a duplicate delivery (WS
	// leg already delivered, or a retransmit / concurrent stream) is rejected
	// without re-staging or re-emitting. Guarded by lanMediaSeenIdsMu — NOT n.mu —
	// because handleIncomingLANMedia runs on a fresh per-stream goroutine and must
	// not contend the node-wide lock across a multi-MB transfer. Lazily created on
	// first claim; reset to nil in Stop() so a recycled id after a restart is not
	// falsely suppressed. See media_lan.go.
	lanMediaSeenIdsMu sync.Mutex
	lanMediaSeenIds   map[string]bool
}

type connectionInfo struct {
	PeerId    string `json:"peerId"`
	Address   string `json:"address"`
	Direction string `json:"direction"`
	Limited   bool   `json:"limited,omitempty"`
	IsRelay   bool   `json:"isRelay,omitempty"`
}

// isCircuitAddr returns true if the multiaddr contains a /p2p-circuit component.
func isCircuitAddr(a ma.Multiaddr) bool {
	return strings.Contains(a.String(), "/p2p-circuit")
}

func classifyStreamTransport(s network.Stream) string {
	conn := s.Conn()
	if conn == nil {
		return "direct"
	}

	if local := conn.LocalMultiaddr(); local != nil && isCircuitAddr(local) {
		return "relay"
	}
	if remote := conn.RemoteMultiaddr(); remote != nil && isCircuitAddr(remote) {
		return "relay"
	}
	return "direct"
}

// extractIP returns the first IP address from a multiaddr, stripping any
// ip6zone prefix. Returns nil if the multiaddr does not start with an IP.
func extractIP(a ma.Multiaddr) net.IP {
	c, rest := ma.SplitFirst(a)
	if c == nil {
		return nil
	}
	// Strip ip6zone prefix: /ip6zone/<zone>/ip6/<addr>/...
	if c.Protocol().Code == ma.P_IP6ZONE {
		if rest == nil {
			return nil
		}
		c, _ = ma.SplitFirst(rest)
		if c == nil {
			return nil
		}
	}
	switch c.Protocol().Code {
	case ma.P_IP4, ma.P_IP6:
		return net.IP(c.RawValue())
	}
	return nil
}

// isNonRoutableAddr returns true if the multiaddr starts with a loopback,
// link-local, or unspecified IP address.
func isNonRoutableAddr(a ma.Multiaddr) bool {
	ip := extractIP(a)
	if ip == nil {
		return false
	}
	return ip.IsLoopback() || ip.IsLinkLocalUnicast() || ip.IsUnspecified()
}

// filterAddresses removes loopback, link-local, and unspecified addresses
// from the given multiaddr slice. Circuit relay addresses are always kept.
func filterAddresses(addrs []ma.Multiaddr) []ma.Multiaddr {
	filtered := make([]ma.Multiaddr, 0, len(addrs))
	for _, a := range addrs {
		if isCircuitAddr(a) {
			filtered = append(filtered, a)
			continue
		}
		if isNonRoutableAddr(a) {
			continue
		}
		filtered = append(filtered, a)
	}
	return filtered
}

// NewNode creates a new Node instance without an event callback.
func NewNode() *Node {
	return &Node{
		connections:           make(map[string]connectionInfo),
		relaySessionMgr:       NewRelaySessionManager(),
		relayReadyOnce:        &sync.Once{},
		groupDialBackoff:      make(map[string]groupPeerDialState),
		groupRecoverySem:      make(chan struct{}, GroupDiscoveryConcurrency),
		groupDialSem:          make(chan struct{}, GroupDiscoveryConcurrency),
		pubsubRejectDiagLast:  make(map[string]time.Time),
		pendingDirectConfirms: make(map[string]chan directConfirmResult),
		newHost:               defaultNewHost,
	}
}

// New creates a new Node instance with an event callback for Go → Flutter push events.
func New(cb EventCallback) *Node {
	return &Node{
		connections:           make(map[string]connectionInfo),
		eventCallback:         cb,
		relaySessionMgr:       NewRelaySessionManager(),
		relayReadyOnce:        &sync.Once{},
		groupDialBackoff:      make(map[string]groupPeerDialState),
		groupRecoverySem:      make(chan struct{}, GroupDiscoveryConcurrency),
		groupDialSem:          make(chan struct{}, GroupDiscoveryConcurrency),
		pubsubRejectDiagLast:  make(map[string]time.Time),
		pendingDirectConfirms: make(map[string]chan directConfirmResult),
		newHost:               defaultNewHost,
	}
}

func defaultNewHost(_ NodeConfig, opts []libp2p.Option) (host.Host, error) {
	return libp2p.New(opts...)
}

// Start initializes the libp2p host and connects to the relay.
// Accepts a NodeConfig and returns the initial NodeState on success.
func (n *Node) Start(cfg NodeConfig) (state *NodeState, err error) {
	initialLockAt := time.Now()
	n.mu.Lock()
	if n.isStarted {
		n.mu.Unlock()
		return nil, fmt.Errorf("node already started")
	}
	if n.startInProgress {
		n.mu.Unlock()
		return nil, fmt.Errorf("node start in progress")
	}
	n.startInProgress = true
	hostFactory := n.newHost
	holePunchTracer := n.holePunchTracerForTests
	forcePublicReachability := n.forcePublicReachabilityForTests
	hermeticLocalNetwork := n.hermeticLocalNetworkForTests
	eventCallback := n.eventCallback
	n.mu.Unlock()
	lockHeld := time.Since(initialLockAt)

	if hostFactory == nil {
		hostFactory = defaultNewHost
	}

	var localHost host.Host
	var localCancel context.CancelFunc
	startCommitted := false
	rollbackStart := func() {
		if localHost != nil {
			_ = localHost.Close()
			localHost = nil
		}
		if localCancel != nil {
			localCancel()
			localCancel = nil
		}
		n.mu.Lock()
		n.startInProgress = false
		n.mu.Unlock()
	}
	defer func() {
		if r := recover(); r != nil {
			if startCommitted {
				panic(r)
			}
			rollbackStart()
			state = nil
			err = fmt.Errorf("node start panic: %v", r)
		}
	}()

	cfgCopy := cfg
	cfgCopy.PersonalRendezvousRefreshInterval = cfgCopy.PersonalRendezvousRefreshEvery()
	flags := cfg.EffectiveFlags()

	keyBytes, err := hex.DecodeString(cfg.PrivateKeyHex)
	if err != nil {
		rollbackStart()
		return nil, fmt.Errorf("invalid private key hex: %w", err)
	}
	privKey, err := crypto.UnmarshalEd25519PrivateKey(keyBytes)
	if err != nil {
		rollbackStart()
		return nil, fmt.Errorf("invalid Ed25519 key: %w", err)
	}

	localCtx, cancel := context.WithCancel(context.Background())
	localCancel = cancel

	cm, err := connmgr.NewConnManager(10, 100, connmgr.WithGracePeriod(time.Minute))
	if err != nil {
		rollbackStart()
		return nil, fmt.Errorf("connection manager: %w", err)
	}

	relayAddresses := cfg.RelayAddresses
	if relayAddresses == nil {
		relayAddresses = DefaultRelayAddresses()
	}
	relayAddresses = limitRelayAddresses(relayAddresses, flags)

	relayInfoMap := make(map[peer.ID]*peer.AddrInfo)
	relayPeerOrder := make([]peer.ID, 0, len(relayAddresses))
	seenRelayPeers := make(map[peer.ID]struct{})
	for _, addr := range relayAddresses {
		maddr, err := ma.NewMultiaddr(addr)
		if err != nil {
			log.Printf("[NODE] Skipping invalid relay address %s: %v", addr, err)
			continue
		}
		info, err := peer.AddrInfoFromP2pAddr(maddr)
		if err != nil {
			log.Printf("[NODE] Skipping unparseable relay address %s: %v", addr, err)
			continue
		}
		if existing, ok := relayInfoMap[info.ID]; ok {
			existing.Addrs = append(existing.Addrs, info.Addrs...)
		} else {
			relayInfoMap[info.ID] = info
		}
		if _, seen := seenRelayPeers[info.ID]; !seen {
			seenRelayPeers[info.ID] = struct{}{}
			relayPeerOrder = append(relayPeerOrder, info.ID)
		}
	}
	relayInfos := make([]peer.AddrInfo, 0, len(relayInfoMap))
	for _, info := range relayInfoMap {
		relayInfos = append(relayInfos, *info)
	}

	listenAddrs := []string{
		"/ip4/0.0.0.0/udp/0/quic-v1",
		"/ip4/0.0.0.0/tcp/0/ws",
		"/ip4/0.0.0.0/tcp/0",
		"/ip6/::/udp/0/quic-v1",
		"/ip6/::/tcp/0/ws",
		"/ip6/::/tcp/0",
	}
	if cfg.ListenPort > 0 {
		listenAddrs = []string{
			fmt.Sprintf("/ip4/0.0.0.0/udp/%d/quic-v1", cfg.ListenPort),
			fmt.Sprintf("/ip4/0.0.0.0/tcp/%d/ws", cfg.ListenPort),
			fmt.Sprintf("/ip4/0.0.0.0/tcp/%d", cfg.ListenPort),
			fmt.Sprintf("/ip6/::/udp/%d/quic-v1", cfg.ListenPort),
			fmt.Sprintf("/ip6/::/tcp/%d/ws", cfg.ListenPort),
			fmt.Sprintf("/ip6/::/tcp/%d", cfg.ListenPort),
		}
	}

	holeOpts := []holepunch.Option{}
	if holePunchTracer != nil {
		holeOpts = append(holeOpts, holepunch.WithTracer(holePunchTracer))
	} else {
		holeOpts = append(holeOpts, holepunch.WithTracer(newNodeHolePunchTracer(n)))
	}
	reachabilityOpt := libp2p.ForceReachabilityPrivate()
	if dcutrReachabilityMode(flags.EnableDcutrUpgrade, forcePublicReachability) == "public" {
		reachabilityOpt = libp2p.ForceReachabilityPublic()
	}
	advertisedAddrsFactory := filterAddresses
	if hermeticLocalNetwork {
		advertisedAddrsFactory = func(addrs []ma.Multiaddr) []ma.Multiaddr {
			loopback := make([]ma.Multiaddr, 0, len(addrs))
			for _, addr := range addrs {
				if ip := extractIP(addr); ip != nil && ip.IsLoopback() {
					loopback = append(loopback, addr)
				}
			}
			if len(loopback) == 0 {
				return filterAddresses(addrs)
			}
			return loopback
		}
	}

	hostOpts := []libp2p.Option{
		libp2p.Identity(privKey),
		libp2p.ListenAddrStrings(listenAddrs...),
		libp2p.ConnectionManager(cm),
		libp2p.EnableRelay(),
		libp2p.EnableHolePunching(holeOpts...),
	}
	if !hermeticLocalNetwork {
		hostOpts = append(hostOpts, libp2p.NATPortMap())
	}
	hostOpts = append(
		hostOpts,
		reachabilityOpt,
		libp2p.AddrsFactory(advertisedAddrsFactory),
	)
	if len(relayInfos) > 0 {
		hostOpts = append(hostOpts,
			libp2p.EnableAutoRelayWithStaticRelays(relayInfos,
				autorelay.WithBootDelay(0),
				autorelay.WithBackoff(ForegroundAutoRelayRetryCadence),
				autorelay.WithMinInterval(ForegroundAutoRelayRetryCadence),
			),
		)
	}
	libp2pStart := time.Now()
	h, err := hostFactory(cfgCopy, hostOpts)
	libp2pNewMs := time.Since(libp2pStart).Milliseconds()
	if err != nil {
		rollbackStart()
		return nil, fmt.Errorf("create host: %w", err)
	}
	localHost = h

	pubsubStart := time.Now()
	ps, err := pubsub.NewGossipSub(localCtx, h, pubsub.WithFloodPublish(true))
	if err != nil {
		rollbackStart()
		return nil, fmt.Errorf("init pubsub: %w", err)
	}
	pubsubInitMs := time.Since(pubsubStart).Milliseconds()

	peerSession := newPeerSessionNotifiee(n)
	h.Network().Notify(peerSession)
	lanDialHandler := newLANDialHandler(n)

	announceAddrs := h.Addrs()
	log.Printf("[NODE] Announcing %d addresses (loopback/link-local filtered out)", len(announceAddrs))
	for _, a := range announceAddrs {
		log.Printf("[NODE]   %s", a.String())
	}

	namespace := cfg.Namespace
	if namespace == "" {
		namespace = RendezvousPrefix + h.ID().String()
	}

	h.SetStreamHandler(ChatProtocol, n.handleIncomingMessage)
	h.SetStreamHandler(GroupValidationFeedbackProtocol, n.handleGroupValidationFeedback)
	if flags.EnableLibp2pLANMedia {
		h.SetStreamHandler(MediaLANProtocol, n.handleIncomingLANMedia)
	}

	var sub event.Subscription
	sub, err = h.EventBus().Subscribe([]interface{}{
		new(event.EvtPeerConnectednessChanged),
		new(event.EvtLocalAddressesUpdated),
	})
	if err != nil {
		log.Printf("[NODE] Failed to subscribe to events: %v", err)
	}

	relayReady := make(chan struct{})
	relayReadyOnce := &sync.Once{}
	var dispatcher *EventDispatcher
	if eventCallback != nil {
		dispatcher = NewEventDispatcher(eventCallback, 1024)
	}

	commitLockAt := time.Now()
	n.mu.Lock()
	n.lastConfig = &cfgCopy
	n.processStartEpochMs.Store(cfg.ProcessStartEpochMs)
	n.featureFlags = &flags
	n.ctx = localCtx
	n.cancel = cancel
	n.relayAddresses = relayAddresses
	n.relayPeerOrder = relayPeerOrder
	if n.relaySessionMgr != nil {
		for _, relayPeerID := range relayPeerOrder {
			n.relaySessionMgr.InitRelayPeer(relayPeerID)
		}
	}
	n.host = h
	n.peerId = h.ID().String()
	n.lanDialHandler = lanDialHandler
	n.peerSession = peerSession
	n.pubsub = ps
	n.groupTopics = make(map[string]*pubsub.Topic)
	n.groupSubs = make(map[string]*pubsub.Subscription)
	n.groupConfigs = make(map[string]*GroupConfig)
	n.groupKeys = make(map[string]*GroupKeyInfo)
	n.groupSubCtx = make(map[string]context.CancelFunc)
	n.groupDiscoveryCtx = make(map[string]context.CancelFunc)
	n.namespace = namespace
	n.eventSub = sub
	n.isStarted = true
	n.startedAt = time.Now()
	n.relayReady = relayReady
	n.relayReadyOnce = relayReadyOnce
	n.personalRendezvousRegistering.Store(false)
	if n.eventDispatcher != nil {
		n.eventDispatcher.Stop()
	}
	n.eventDispatcher = dispatcher
	n.startInProgress = false
	state = n.stateLocked()
	n.mu.Unlock()
	startCommitted = true
	lockHeld += time.Since(commitLockAt)

	localHost = nil
	localCancel = nil

	if sub != nil {
		go n.watchConnectionEvents(sub)
	}

	n.emitEvent("node:startup_timing", map[string]interface{}{
		"phase":               "host_ready",
		"libp2pNewMs":         libp2pNewMs,
		"pubsubInitMs":        pubsubInitMs,
		"sinceProcessStartMs": n.sinceProcessStartMs(),
	})
	n.emitReserveDispatchAnchor()

	relayWarmStart := time.Now()
	go func() {
		for _, info := range relayInfos {
			go func(ri peer.AddrInfo) {
				if err := n.warmRelayConnectionForStart(ri); err != nil {
					log.Printf("[NODE] relay dial FAILED (%s): %v", ri.ID.String()[:min(20, len(ri.ID.String()))], err)
				} else {
					relayReadyOnce.Do(func() { close(relayReady) })
				}
			}(info)
		}
	}()

	if len(relayInfos) > 0 {
		go func(ctx context.Context) {
			select {
			case <-relayReady:
				n.emitEvent("node:startup_timing", map[string]interface{}{
					"phase":               "relay_warm_done",
					"relayWarmMs":         time.Since(relayWarmStart).Milliseconds(),
					"relaysAttempted":     len(relayInfos),
					"sinceProcessStartMs": n.sinceProcessStartMs(),
				})
			case <-ctx.Done():
			}
		}(localCtx)
	}

	if cfg.AutoRegister {
		go n.autoRegisterPersonalNamespaceForStart()
	}

	n.emitEvent("node:startup_timing", map[string]interface{}{
		"phase":               "start_lock_window",
		"lockHoldMs":          lockHeld.Milliseconds(),
		"sinceProcessStartMs": n.sinceProcessStartMs(),
	})

	return state, nil
}

// Stop shuts down the libp2p host.
func (n *Node) Stop() error {
	n.mu.Lock()
	defer n.mu.Unlock()

	if n.startInProgress {
		return fmt.Errorf("node start in progress")
	}
	if !n.isStarted {
		return nil
	}

	if n.eventSub != nil {
		n.eventSub.Close()
	}

	// Cancel all group discovery loops (triggers rendezvous unregister).
	for gid, cancel := range n.groupDiscoveryCtx {
		cancel()
		delete(n.groupDiscoveryCtx, gid)
	}

	// Cancel all group subscription goroutines.
	for gid, cancel := range n.groupSubCtx {
		cancel()
		delete(n.groupSubCtx, gid)
	}
	for gid, sub := range n.groupSubs {
		sub.Cancel()
		delete(n.groupSubs, gid)
	}
	for gid, topic := range n.groupTopics {
		topic.Close()
		delete(n.groupTopics, gid)
	}
	n.groupConfigs = nil
	n.groupKeys = nil
	n.pubsub = nil

	n.stopPersonalRendezvousRefreshLoopLocked()

	if n.cancel != nil {
		n.cancel()
	}
	if n.host != nil {
		// FDC-12: deregister the session Notifiee before closing the host so no
		// re-point fires after Stop (host.Close() also tears down notifiees, but
		// StopNotify is explicit and mirrors FDC-11's clear-on-Stop discipline).
		if n.peerSession != nil {
			n.host.Network().StopNotify(n.peerSession)
		}
		if err := n.host.Close(); err != nil {
			return fmt.Errorf("host close: %w", err)
		}
	}

	n.isStarted = false
	n.connections = make(map[string]connectionInfo)
	n.relayPeerOrder = nil
	n.host = nil
	n.peerSession = nil
	n.eventSub = nil
	// FDC-11: tear down the LAN-dial handler so a Stop/Start cycle re-wires
	// cleanly with an empty cooldown (no leak, no double-wire).
	if n.lanDialHandler != nil {
		n.lanDialHandler.mu.Lock()
		n.lanDialHandler.cooldown = nil
		n.lanDialHandler.mu.Unlock()
		n.lanDialHandler = nil
	}
	// FDC-15: drop the inbound-media dedup set so a media id that delivered before
	// a Stop/Start can be received again after restart (mirror the lanDialHandler
	// reset above). A fresh host is built on the next Start, so the handler itself
	// needs no explicit removal.
	n.lanMediaSeenIdsMu.Lock()
	n.lanMediaSeenIds = nil
	n.lanMediaSeenIdsMu.Unlock()
	n.groupDialBackoff = make(map[string]groupPeerDialState)
	n.groupRecoverySem = make(chan struct{}, GroupDiscoveryConcurrency)
	n.groupDialSem = make(chan struct{}, GroupDiscoveryConcurrency)
	n.relayReadyOnce = &sync.Once{} // reset so next Start() can use it
	n.featureFlags = nil
	n.personalRendezvousRegistering.Store(false)

	// Phase 4: Stop event dispatcher and reset relay session state.
	if n.eventDispatcher != nil {
		n.eventDispatcher.Stop()
		n.eventDispatcher = nil
	}
	if n.relaySessionMgr != nil {
		n.relaySessionMgr.Reset()
	}

	return nil
}

// Status returns the current node state as a JSON-compatible map.
func (n *Node) Status() map[string]interface{} {
	n.mu.RLock()
	defer n.mu.RUnlock()

	listenAddrs := []string{}
	circuitAddrs := []string{}
	conns := []map[string]interface{}{}

	if n.host != nil && n.isStarted {
		listenAddrs, circuitAddrs = splitHostAddresses(n.host)
		for _, c := range n.connections {
			conns = append(conns, map[string]interface{}{
				"peerId":    c.PeerId,
				"address":   c.Address,
				"direction": c.Direction,
				"isRelay":   c.IsRelay,
			})
		}
	}

	featureFlags := DefaultFeatureFlags()
	if n.featureFlags != nil {
		featureFlags = *n.featureFlags
	}

	result := map[string]interface{}{
		"ok":               true,
		"peerId":           n.peerId,
		"isStarted":        n.isStarted,
		"listenAddresses":  listenAddrs,
		"circuitAddresses": circuitAddrs,
		"connections":      conns,
		"featureFlags":     featureFlagsStatusMap(featureFlags),
	}

	// Phase 4: Merge relay session fields additively.
	if n.relaySessionMgr != nil && featureFlags.EnableReservationAwareHealth {
		for k, v := range n.relaySessionMgr.StatusFields() {
			result[k] = v
		}
	}

	return result
}

// State returns the current node state as a typed NodeState.
func (n *Node) State() *NodeState {
	n.mu.RLock()
	defer n.mu.RUnlock()
	return n.stateLocked()
}

// stateLocked returns NodeState; caller must hold at least a read lock.
func (n *Node) stateLocked() *NodeState {
	addrs := []string{}
	if n.host != nil && n.isStarted {
		for _, addr := range n.host.Addrs() {
			addrs = append(addrs, addr.String())
		}
	}
	return &NodeState{
		PeerId:      n.peerId,
		IsStarted:   n.isStarted,
		Addresses:   addrs,
		Connections: len(n.connections),
	}
}

// WaitForRelayConnection blocks until at least one relay connection succeeds or the timeout expires.
func (n *Node) WaitForRelayConnection(timeout time.Duration) error {
	select {
	case <-n.relayReady:
		return nil
	case <-time.After(timeout):
		return fmt.Errorf("relay connection timeout after %v", timeout)
	case <-n.ctx.Done():
		return n.ctx.Err()
	}
}

// warmRelayConnection dials the relay server to warm the TCP/QUIC connection.
// AutoRelay handles circuit reservation and address management automatically;
// warming the connection lets AutoRelay's identify complete instantly when it
// runs tryNode(), avoiding a 20s identify timeout + 30s retry wait.
func (n *Node) warmRelayConnection(info peer.AddrInfo) error {
	return n.warmRelayConnectionWithTimeout(info, DialTimeout)
}

func (n *Node) warmRelayConnectionWithTimeout(info peer.AddrInfo, timeout time.Duration) error {
	if n.warmRelayConnectionWithTimeoutHook != nil {
		return n.warmRelayConnectionWithTimeoutHook(info, timeout)
	}
	if n.warmRelayConnectionHook != nil {
		return n.warmRelayConnectionHook(info)
	}

	start := time.Now()
	var lastErr error
	candidates := relayConnectCandidates(info)
	for i, candidate := range candidates {
		ctx, cancel := context.WithTimeout(n.ctx, timeout)
		ctx = network.WithDialPeerTimeout(ctx, timeout)
		err := n.connectRelay(ctx, candidate)
		cancel()
		if err == nil {
			n.emitEvent("relay:warm_timing", map[string]interface{}{
				"elapsedMs": time.Since(start).Milliseconds(),
				"outcome":   "success",
				"relayId":   info.ID.String()[:min(20, len(info.ID.String()))],
			})
			log.Printf("[NODE] Warmed relay connection: %s", info.ID.String()[:min(20, len(info.ID.String()))])
			return nil
		}
		lastErr = err
		if ctx.Err() == context.DeadlineExceeded {
			n.emitTimeoutFired("DialTimeout", timeout, start)
		}
		if len(candidates) > 1 {
			log.Printf(
				"[NODE] relay address dial FAILED (%s, addr %d/%d): %v",
				info.ID.String()[:min(20, len(info.ID.String()))],
				i+1,
				len(candidates),
				err,
			)
		}
	}

	n.emitEvent("relay:warm_timing", map[string]interface{}{
		"elapsedMs": time.Since(start).Milliseconds(),
		"outcome":   "failed",
		"relayId":   info.ID.String()[:min(20, len(info.ID.String()))],
	})
	return fmt.Errorf("dial relay: %w", lastErr)
}

func relayConnectCandidates(info peer.AddrInfo) []peer.AddrInfo {
	if len(info.Addrs) <= 1 {
		return []peer.AddrInfo{info}
	}

	candidates := make([]peer.AddrInfo, 0, len(info.Addrs))
	for _, addr := range info.Addrs {
		candidates = append(candidates, peer.AddrInfo{
			ID:    info.ID,
			Addrs: []ma.Multiaddr{addr},
		})
	}
	return candidates
}

func (n *Node) connectRelay(ctx context.Context, info peer.AddrInfo) error {
	if n.connectRelayHook != nil {
		return n.connectRelayHook(ctx, info)
	}
	return n.host.Connect(ctx, info)
}

func (n *Node) reserveRelaySlot(ctx context.Context, h host.Host, info peer.AddrInfo) (*relayclient.Reservation, error) {
	if n.reserveRelaySlotHook != nil {
		return n.reserveRelaySlotHook(ctx, h, info)
	}
	if h == nil {
		return nil, fmt.Errorf("node host not available")
	}
	return relayclient.Reserve(ctx, h, info)
}

func (n *Node) warmRelayConnectionForStart(info peer.AddrInfo) error {
	return n.warmRelayConnection(info)
}

// RefreshRelaySession attempts in-place relay recovery without replacing the host.
// It reconnects to relay peers and waits for AutoRelay to re-establish
// circuit reservations. PubSub subscriptions and peer connections are preserved.
//
// Returns a RecoveryResult describing what happened.
func (n *Node) RefreshRelaySession() *RecoveryResult {
	n.mu.RLock()
	mgr := n.relaySessionMgr
	n.mu.RUnlock()

	recovery, isNew := mgr.BeginRecovery()
	if !isNew {
		return waitForSharedRecoveryResult(recovery)
	}

	result := n.refreshRelaySessionOwned()
	mgr.CompleteRecovery(result, nil)
	return result
}

func waitForSharedRecoveryResult(recovery *recoveryPromise) *RecoveryResult {
	result, err := recovery.Wait()
	if result != nil {
		return result
	}
	if err != nil {
		return &RecoveryResult{
			RecoveryMode: "in_place",
			Success:      false,
			ErrorCode:    "RECOVERY_FAILED",
			Reason:       err.Error(),
			ReusedHost:   true,
		}
	}
	return &RecoveryResult{
		RecoveryMode: "in_place",
		Success:      false,
		ErrorCode:    "RECOVERY_NIL",
		Reason:       "coalesced recovery returned nil result",
		ReusedHost:   true,
	}
}

func waitForSharedRecoveryOutcome(recovery *recoveryPromise) (*RecoveryResult, error) {
	result, err := recovery.Wait()
	if result != nil || err != nil {
		return result, err
	}
	return &RecoveryResult{
		RecoveryMode: "in_place",
		Success:      false,
		ErrorCode:    "RECOVERY_NIL",
		Reason:       "coalesced recovery returned nil result",
		ReusedHost:   true,
	}, nil
}

func (n *Node) refreshRelaySessionOwned() *RecoveryResult {
	refreshStart := time.Now()
	n.mu.RLock()
	h := n.host
	started := n.isStarted
	relayReady := n.relayReady
	relayReadyOnce := n.relayReadyOnce
	relayAddrs := n.relayAddresses
	relayPeerOrder := append([]peer.ID(nil), n.relayPeerOrder...)
	mgr := n.relaySessionMgr
	n.mu.RUnlock()

	if !started || h == nil {
		return &RecoveryResult{
			RecoveryMode: "in_place",
			Success:      false,
			ErrorCode:    "NOT_STARTED",
			Reason:       "node not started",
			ReusedHost:   true,
		}
	}

	// We own the shared recovery — perform in-place refresh.
	log.Printf("[NODE] RefreshRelaySession: attempting in-place relay recovery")

	var result *RecoveryResult
	if n.refreshRelaySessionHook != nil {
		result = n.refreshRelaySessionHook()
	} else {
		var refreshErr error
		var relayWarmMs int64
		var reserveRpcMs int64
		var circuitAddressWaitMs int64
		relayWarmParallelism := 0
		reservationPath := "poll_fallback"
		reservationWinnerPeer := ""
		foregroundRecoveryPath := "background_fallback"

		warmInfos, relayInfoMap := relayWarmPlan(relayAddrs, relayPeerOrder)
		warmSucceeded, lastWarmErr, successfulWarmInfos, relayWarmParallelism, relayWarmMs :=
			n.warmRelayInfos(warmInfos, relayInfoMap)
		reserveSucceeded, lastReserveErr, reserveRpcMs, reservationPath, reservationWinnerPeer :=
			n.reserveWarmedRelays(h, mgr, successfulWarmInfos, reservationPath, reservationWinnerPeer)

		// Give the faster foreground path a short chance to win first, then keep
		// the existing long wait budget as fallback safety behavior.
		waitStart := time.Now()
		if ok := n.waitForCircuitAddressOnHost(h, ForegroundCircuitAddressWaitTimeout); ok {
			log.Printf("[NODE] RefreshRelaySession: circuit addresses obtained ✓")
			foregroundRecoveryPath = "foreground_success"
			refreshErr = nil
		} else {
			remainingWait := CircuitAddressWaitTimeout - ForegroundCircuitAddressWaitTimeout
			if remainingWait < 0 {
				remainingWait = 0
			}
			if remainingWait > 0 && n.waitForCircuitAddressOnHost(h, remainingWait) {
				log.Printf("[NODE] RefreshRelaySession: circuit addresses obtained via fallback ✓")
				refreshErr = nil
			} else if reserveSucceeded {
				// 189 reservation-truth (Defect B): the explicit Reserve RPC
				// succeeded, so the relay holds a live slot and peers can
				// already dial <relay>/p2p-circuit/p2p/<us> (the dial path
				// builds that address deterministically without consulting
				// h.Addrs()). Only autorelay's relayFinder can ADVERTISE the
				// addr in v0.39.1 and it may never do so (Public reachability,
				// non-public relay addrs, or the field wedge) — failing here
				// forced a full restart that purged the reservation and
				// restarted the loop every 30s.
				log.Printf("[NODE] RefreshRelaySession: no advertised circuit address, accepting explicit reservation as circuit truth ✓")
				foregroundRecoveryPath = "reservation_truth"
				refreshErr = nil
			} else if !warmSucceeded && lastWarmErr != nil {
				refreshErr = lastWarmErr
			} else if lastReserveErr != nil && !reserveSucceeded {
				refreshErr = lastReserveErr
			} else {
				refreshErr = fmt.Errorf("no circuit addresses after %v wait", CircuitAddressWaitTimeout)
			}
		}
		circuitAddressWaitMs = time.Since(waitStart).Milliseconds()
		_, circuitAddrs := splitHostAddresses(h)
		for _, relayPeerID := range relayPeerOrder {
			if relayPeerHasCircuitAddress(relayPeerID, circuitAddrs) {
				reservationWinnerPeer = relayPeerID.String()
				break
			}
		}
		n.syncRelaySessionFromRuntime("refresh_relay_session", circuitAddrs)

		result = &RecoveryResult{
			RecoveryMode:                 "in_place",
			Success:                      refreshErr == nil,
			RelayState:                   string(mgr.AggregateState()),
			HealthyRelayCount:            mgr.HealthyRelayCount(),
			ReusedHost:                   true,
			RelayWarmMs:                  relayWarmMs,
			ReserveRpcMs:                 reserveRpcMs,
			RelayWarmParallelism:         relayWarmParallelism,
			ForegroundRecoveryPath:       foregroundRecoveryPath,
			ForegroundRelayDialTimeoutMs: ForegroundRelayDialTimeout.Milliseconds(),
			AutorelayRetryCadenceMs:      ForegroundAutoRelayRetryCadence.Milliseconds(),
			CircuitAddressWaitMs:         circuitAddressWaitMs,
			ReservationPath:              reservationPath,
			ReservationWinnerPeer:        reservationWinnerPeer,
		}
		if refreshErr != nil {
			result.ErrorCode = "REFRESH_FAILED"
			result.Reason = refreshErr.Error()
		}
	}

	if result != nil {
		result.RelayRefreshMs = time.Since(refreshStart).Milliseconds()
		if result.RecoveryMode == "in_place" {
			result.ReusedHost = true
			if result.ReservationPath == "" {
				result.ReservationPath = "poll_fallback"
			}
		}
	}
	result = n.finalizeRelayRecoveryResult(result, "relay refresh")
	if result.Success && result.RecoveryMode == "in_place" {
		n.closeRelayReadyIfCurrent(h, relayReady, relayReadyOnce)
	}
	return result
}

func relayWarmPlan(relayAddrs []string, relayPeerOrder []peer.ID) ([]peer.AddrInfo, map[peer.ID]*peer.AddrInfo) {
	if len(relayAddrs) == 0 {
		relayAddrs = DefaultRelayAddresses()
	}
	relayInfoMap := make(map[peer.ID]*peer.AddrInfo)
	for _, addr := range relayAddrs {
		maddr, err := ma.NewMultiaddr(addr)
		if err != nil {
			continue
		}
		info, err := peer.AddrInfoFromP2pAddr(maddr)
		if err != nil {
			continue
		}
		if existing, ok := relayInfoMap[info.ID]; ok {
			existing.Addrs = append(existing.Addrs, info.Addrs...)
		} else {
			relayInfoMap[info.ID] = info
		}
	}
	warmInfos := make([]peer.AddrInfo, 0, len(relayInfoMap))
	for _, relayPeerID := range relayPeerOrder {
		if info, ok := relayInfoMap[relayPeerID]; ok {
			warmInfos = append(warmInfos, *info)
		}
	}
	if len(warmInfos) == 0 {
		for _, info := range relayInfoMap {
			warmInfos = append(warmInfos, *info)
		}
	}
	return warmInfos, relayInfoMap
}

type relayWarmAttempt struct {
	peerID peer.ID
	err    error
}

func (n *Node) warmRelayInfos(
	warmInfos []peer.AddrInfo,
	relayInfoMap map[peer.ID]*peer.AddrInfo,
) (bool, error, []peer.AddrInfo, int, int64) {
	warmStart := time.Now()
	parallelism := len(warmInfos)
	attempts := make(chan relayWarmAttempt, max(1, parallelism))
	var warmWG sync.WaitGroup
	for _, info := range warmInfos {
		info := info
		warmWG.Add(1)
		go func() {
			defer warmWG.Done()
			attempts <- relayWarmAttempt{
				peerID: info.ID,
				err:    n.warmRelayConnectionWithTimeout(info, ForegroundRelayDialTimeout),
			}
		}()
	}
	warmWG.Wait()
	close(attempts)

	warmSucceeded := false
	var lastWarmErr error
	successfulWarmInfos := make([]peer.AddrInfo, 0, len(warmInfos))
	for attempt := range attempts {
		peerLabel := attempt.peerID.String()[:min(20, len(attempt.peerID.String()))]
		if attempt.err != nil {
			log.Printf("[NODE] RefreshRelaySession: warm %s failed: %v", peerLabel, attempt.err)
			lastWarmErr = attempt.err
			continue
		}
		warmSucceeded = true
		if info, ok := relayInfoMap[attempt.peerID]; ok {
			successfulWarmInfos = append(successfulWarmInfos, *info)
		}
		log.Printf("[NODE] RefreshRelaySession: warm %s success", peerLabel)
	}
	return warmSucceeded, lastWarmErr, successfulWarmInfos, parallelism, time.Since(warmStart).Milliseconds()
}

type reserveAttempt struct {
	peerID      peer.ID
	err         error
	reservation *relayclient.Reservation
}

func (n *Node) reserveWarmedRelays(
	h host.Host,
	mgr *RelaySessionManager,
	successfulWarmInfos []peer.AddrInfo,
	reservationPath string,
	reservationWinnerPeer string,
) (bool, error, int64, string, string) {
	if len(successfulWarmInfos) == 0 {
		return false, nil, 0, reservationPath, reservationWinnerPeer
	}
	reserveStart := time.Now()
	reserveAttempts := make(chan reserveAttempt, len(successfulWarmInfos))
	var reserveWG sync.WaitGroup
	for _, info := range successfulWarmInfos {
		info := info
		reserveWG.Add(1)
		go func() {
			defer reserveWG.Done()
			reserveCtx, cancel := context.WithTimeout(n.ctx, ForegroundRelayReserveTimeout)
			defer cancel()
			res, err := n.reserveRelaySlot(reserveCtx, h, info)
			reserveAttempts <- reserveAttempt{peerID: info.ID, err: err, reservation: res}
		}()
	}
	reserveWG.Wait()
	close(reserveAttempts)

	reserveSucceeded := false
	var lastReserveErr error
	reserveRpcMs := time.Since(reserveStart).Milliseconds()
	for attempt := range reserveAttempts {
		peerLabel := attempt.peerID.String()[:min(20, len(attempt.peerID.String()))]
		if attempt.err != nil {
			lastReserveErr = attempt.err
			log.Printf("[NODE] RefreshRelaySession: reserve %s failed: %v", peerLabel, attempt.err)
			if mgr != nil {
				mgr.OnRequestFailed(attempt.peerID, attempt.err)
			}
			n.emitRelayReservationTiming(reserveRpcMs, "failed", peerLabel, attempt.err)
			continue
		}
		reserveSucceeded = true
		reservationPath = "explicit_reserve"
		reservationWinnerPeer = attempt.peerID.String()
		if mgr != nil {
			var expiry time.Time
			if attempt.reservation != nil {
				expiry = attempt.reservation.Expiration
			}
			mgr.OnManualReservationOpened(attempt.peerID, expiry)
		}
		log.Printf("[NODE] RefreshRelaySession: reserve %s success", peerLabel)
		n.emitRelayReservationTiming(reserveRpcMs, "success", peerLabel, nil)
	}
	return reserveSucceeded, lastReserveErr, reserveRpcMs, reservationPath, reservationWinnerPeer
}

func (n *Node) emitRelayReservationTiming(elapsedMs int64, outcome string, relayID string, err error) {
	data := map[string]interface{}{
		"elapsedMs":           elapsedMs,
		"outcome":             outcome,
		"relayId":             relayID,
		"sinceProcessStartMs": n.sinceProcessStartMs(),
	}
	if err != nil {
		data["error"] = err.Error()
	}
	n.emitEvent("relay:reservation_timing", data)
}

func (n *Node) closeRelayReadyIfCurrent(expectedHost host.Host, expectedReady chan struct{}, expectedOnce *sync.Once) {
	if expectedHost == nil || expectedReady == nil || expectedOnce == nil {
		return
	}

	n.mu.RLock()
	defer n.mu.RUnlock()

	if !n.isStarted ||
		n.host != expectedHost ||
		n.relayReady != expectedReady ||
		n.relayReadyOnce != expectedOnce {
		return
	}

	expectedOnce.Do(func() { close(expectedReady) })
}

// ReconnectRelays attempts in-place relay recovery first, then falls back
// to a full host restart if in-place recovery fails.
//
// Phase 4: This method now uses singleflight coalescing via the relay
// session manager, so concurrent callers share one recovery attempt.
// The return value now includes structured recovery fields.
func (n *Node) ReconnectRelays() (*RecoveryResult, error) {
	n.mu.RLock()
	if n.startInProgress {
		n.mu.RUnlock()
		return nil, fmt.Errorf("node start in progress")
	}
	mgr := n.relaySessionMgr
	n.mu.RUnlock()

	recovery, isNew := mgr.BeginRecovery()
	if !isNew {
		return waitForSharedRecoveryOutcome(recovery)
	}

	result, err := n.reconnectRelaysOwned()
	mgr.CompleteRecovery(result, err)
	return result, err
}

func (n *Node) reconnectRelaysOwned() (*RecoveryResult, error) {
	restartStart := time.Now()
	n.mu.RLock()
	started := n.isStarted
	cfg := n.lastConfig
	n.mu.RUnlock()

	if !started {
		return nil, fmt.Errorf("node not started")
	}
	if cfg == nil {
		return nil, fmt.Errorf("no saved config — cannot restart")
	}

	flags := cfg.EffectiveFlags()

	if flags.EnableInPlaceRelayRecovery {
		result := n.refreshRelaySessionOwned()
		if result.Success {
			log.Printf("[NODE] ReconnectRelays: in-place recovery succeeded")
			return result, nil
		}

		log.Printf("[NODE] ReconnectRelays: in-place recovery failed (%s), performing full restart",
			result.Reason)
	} else {
		log.Printf("[NODE] ReconnectRelays: in-place recovery disabled by feature flag, performing full restart")
	}

	if err := n.Stop(); err != nil {
		log.Printf("[NODE] ReconnectRelays: Stop() error (continuing): %v", err)
	}

	restartCfg := *cfg
	restartCfg.AutoRegister = false

	state, err := n.Start(restartCfg)
	if err != nil {
		return &RecoveryResult{
			RecoveryMode: "watchdog_restart",
			Success:      false,
			ErrorCode:    "RESTART_FAILED",
			Reason:       err.Error(),
			ReusedHost:   false,
		}, fmt.Errorf("restart Start() failed: %w", err)
	}

	// Restore original AutoRegister.
	n.mu.Lock()
	n.lastConfig.AutoRegister = cfg.AutoRegister
	n.mu.Unlock()

	log.Printf("[NODE] ReconnectRelays: node restarted, peerId=%s, waiting for circuit addresses...",
		state.PeerId)

	waitStart := time.Now()
	circuitOk := n.waitForCircuitAddress(10 * time.Second)
	circuitAddressWaitMs := time.Since(waitStart).Milliseconds()

	n.mu.RLock()
	mgr := n.relaySessionMgr
	n.mu.RUnlock()

	if !circuitOk && mgr.HasReservation() {
		// 189 reservation-truth: consult the session manager, not only the
		// advertised address set (same seam as refreshRelaySessionOwned).
		log.Printf("[NODE] ReconnectRelays: no advertised circuit address after restart, but a relay reservation is live — accepting reservation truth ✓")
		circuitOk = true
	}
	if circuitOk {
		log.Printf("[NODE] ReconnectRelays: circuit addresses obtained ✓")
	} else {
		log.Printf("[NODE] ReconnectRelays: WARNING — no circuit addresses after 10s")
	}

	watchdogResult := &RecoveryResult{
		RecoveryMode:         "watchdog_restart",
		Success:              circuitOk,
		RelayState:           string(mgr.AggregateState()),
		HealthyRelayCount:    mgr.HealthyRelayCount(),
		ReusedHost:           false,
		RelayRefreshMs:       time.Since(restartStart).Milliseconds(),
		ReserveRpcMs:         0,
		CircuitAddressWaitMs: circuitAddressWaitMs,
		ReservationPath:      "poll_fallback",
	}
	if !circuitOk {
		watchdogResult.ErrorCode = "NO_CIRCUIT"
		watchdogResult.Reason = "no circuit addresses after watchdog restart"
	}

	return n.finalizeRelayRecoveryResult(watchdogResult, "watchdog restart"), nil
}

// DialPeerWithTimeout connects to a peer with an explicit timeout override.
// If timeoutMs <= 0, the default PeerDialTimeout is used.
func (n *Node) DialPeerWithTimeout(peerIdStr string, addresses []string, timeoutMs int) error {
	n.mu.RLock()
	h := n.host
	n.mu.RUnlock()

	if h == nil {
		return fmt.Errorf("node not started")
	}

	pid, err := peer.Decode(peerIdStr)
	if err != nil {
		return fmt.Errorf("invalid peer ID: %w", err)
	}

	var addrs []ma.Multiaddr
	for _, a := range addresses {
		maddr, err := ma.NewMultiaddr(a)
		if err != nil {
			log.Printf("[NODE] Skip invalid address %s: %v", a, err)
			continue
		}
		addrs = append(addrs, maddr)
	}

	timeout := PeerDialTimeout
	if timeoutMs > 0 {
		timeout = time.Duration(timeoutMs) * time.Millisecond
	}

	ai := peer.AddrInfo{ID: pid, Addrs: addrs}

	ctx, cancel := context.WithTimeout(n.ctx, timeout)
	defer cancel()
	ctx = network.WithDialPeerTimeout(ctx, timeout)
	ctx = network.WithAllowLimitedConn(ctx, "peer-dial")

	return h.Connect(ctx, ai)
}

// DialPeer connects to a peer, optionally with known addresses.
func (n *Node) DialPeer(peerIdStr string, addresses []string) error {
	n.mu.RLock()
	h := n.host
	n.mu.RUnlock()

	if h == nil {
		return fmt.Errorf("node not started")
	}

	pid, err := peer.Decode(peerIdStr)
	if err != nil {
		return fmt.Errorf("invalid peer ID: %w", err)
	}

	var addrs []ma.Multiaddr
	for _, a := range addresses {
		maddr, err := ma.NewMultiaddr(a)
		if err != nil {
			log.Printf("[NODE] Skip invalid address %s: %v", a, err)
			continue
		}
		addrs = append(addrs, maddr)
	}

	ai := peer.AddrInfo{ID: pid, Addrs: addrs}

	ctx, cancel := context.WithTimeout(n.ctx, PeerDialTimeout)
	defer cancel()
	ctx = network.WithDialPeerTimeout(ctx, PeerDialTimeout)
	ctx = network.WithAllowLimitedConn(ctx, "peer-dial")

	return h.Connect(ctx, ai)
}

// DialPeerViaRelay connects to a peer through the relay circuit address only.
// This is a fast probe (~100ms for NO_RESERVATION, ~500ms for connection) to
// determine if a peer is online without a full discover/dial cycle.
// Tries each configured relay in order until one succeeds.
func (n *Node) DialPeerViaRelay(peerIdStr string) error {
	if n.dialPeerViaRelayHook != nil {
		return n.dialPeerViaRelayHook(peerIdStr)
	}
	return n.dialPeerViaRelayWithTimeout(peerIdStr, RelayProbeTimeout)
}

func (n *Node) dialPeerViaRelayWithTimeout(peerIdStr string, timeout time.Duration) error {
	n.mu.RLock()
	h := n.host
	n.mu.RUnlock()

	if h == nil {
		return fmt.Errorf("node not started")
	}

	pid, err := peer.Decode(peerIdStr)
	if err != nil {
		return fmt.Errorf("invalid peer ID: %w", err)
	}

	rs := n.buildRelaySelector(nil)

	return rs.ForEach(func(relay RelayInfo) error {
		if len(relay.Addrs) == 0 {
			return fmt.Errorf("relay %s has no addresses", relay.ID)
		}

		circuitSuffix, err := ma.NewMultiaddr(
			fmt.Sprintf("/p2p/%s/p2p-circuit/p2p/%s", relay.ID.String(), peerIdStr),
		)
		if err != nil {
			return fmt.Errorf("build circuit suffix: %w", err)
		}

		// Build circuit addresses from ALL transport addresses for this relay.
		// This lets h.Connect try each transport (e.g. IPv4 + IPv6) before
		// falling over to the next relay peer.
		var circuitAddrs []ma.Multiaddr
		for _, transportAddr := range relay.Addrs {
			circuitAddrs = append(circuitAddrs, transportAddr.Encapsulate(circuitSuffix))
		}

		ai := peer.AddrInfo{
			ID:    pid,
			Addrs: circuitAddrs,
		}

		ctx, cancel := context.WithTimeout(n.ctx, timeout)
		defer cancel()
		ctx = network.WithDialPeerTimeout(ctx, timeout)
		ctx = network.WithAllowLimitedConn(ctx, "relay-probe")

		return h.Connect(ctx, ai)
	})
}

// dialPeerViaRelayForSend uses the caller's context for every relay/address
// candidate. The duration-based relay-probe wrapper above intentionally keeps
// its independent per-candidate behavior for non-message callers.
func (n *Node) dialPeerViaRelayForSend(
	ctx context.Context,
	h host.Host,
	pid peer.ID,
	peerIdStr string,
) error {
	rs := n.buildRelaySelector(nil)

	return rs.ForEach(func(relay RelayInfo) error {
		if err := ctx.Err(); err != nil {
			return err
		}
		if len(relay.Addrs) == 0 {
			return fmt.Errorf("relay %s has no addresses", relay.ID)
		}

		circuitSuffix, err := ma.NewMultiaddr(
			fmt.Sprintf("/p2p/%s/p2p-circuit/p2p/%s", relay.ID.String(), peerIdStr),
		)
		if err != nil {
			return fmt.Errorf("build circuit suffix: %w", err)
		}

		circuitAddrs := make([]ma.Multiaddr, 0, len(relay.Addrs))
		for _, transportAddr := range relay.Addrs {
			circuitAddrs = append(circuitAddrs, transportAddr.Encapsulate(circuitSuffix))
		}
		ai := peer.AddrInfo{ID: pid, Addrs: circuitAddrs}

		attemptCtx := network.WithAllowLimitedConn(ctx, "relay-probe")
		if deadline, ok := ctx.Deadline(); ok {
			remaining := time.Until(deadline)
			if remaining <= 0 {
				return context.DeadlineExceeded
			}
			attemptCtx = network.WithDialPeerTimeout(attemptCtx, remaining)
		}
		if n.connectPeerForSendHook != nil {
			return n.connectPeerForSendHook(attemptCtx, h, ai)
		}
		return h.Connect(attemptCtx, ai)
	})
}

// DisconnectPeer closes connections to a peer.
func (n *Node) DisconnectPeer(peerIdStr string) error {
	n.mu.RLock()
	h := n.host
	n.mu.RUnlock()

	if h == nil {
		return fmt.Errorf("node not started")
	}

	pid, err := peer.Decode(peerIdStr)
	if err != nil {
		return fmt.Errorf("invalid peer ID: %w", err)
	}

	return h.Network().ClosePeer(pid)
}

func (n *Node) openChatStream(ctx context.Context, h host.Host, pid peer.ID) (network.Stream, error) {
	if n.openChatStreamHook != nil {
		return n.openChatStreamHook(ctx, h, pid)
	}
	return h.NewStream(ctx, pid, ChatProtocol)
}

func isRetryableChatStreamOpenError(err error) bool {
	if err == nil {
		return false
	}
	if errors.Is(err, context.DeadlineExceeded) {
		return true
	}
	msg := strings.ToLower(err.Error())
	if strings.Contains(msg, "failed to open stream") {
		return true
	}
	// Reconnect regressions can surface as open-stream dial errors with no
	// known addresses after relay recovery.
	return strings.Contains(msg, "failed to dial") &&
		strings.Contains(msg, "no addresses")
}

func (n *Node) recoverPeerForSend(h host.Host, pid peer.ID, peerIdStr string, timeout time.Duration) error {
	if n.recoverPeerForSendHook != nil {
		ctx, cancel := context.WithTimeout(n.ctx, timeout)
		defer cancel()
		return n.recoverPeerForSendHook(ctx, h, pid, peerIdStr)
	}

	if err := h.Network().ClosePeer(pid); err != nil {
		log.Printf("[NODE] SendMessage: ClosePeer(%s) returned: %v", peerIdStr, err)
	}

	return n.dialPeerViaRelayWithTimeout(peerIdStr, timeout)
}

func (n *Node) recoverPeerForSendWithContext(
	ctx context.Context,
	h host.Host,
	pid peer.ID,
	peerIdStr string,
) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	if n.recoverPeerForSendHook != nil {
		return n.recoverPeerForSendHook(ctx, h, pid, peerIdStr)
	}

	if err := h.Network().ClosePeer(pid); err != nil {
		log.Printf("[NODE] SendMessage: ClosePeer(%s) returned: %v", peerIdStr, err)
	}

	return n.dialPeerViaRelayForSend(ctx, h, pid, peerIdStr)
}

func (n *Node) openChatStreamForSend(
	h host.Host,
	pid peer.ID,
	peerIdStr string,
	timeout time.Duration,
) (network.Stream, error) {
	openAttempt := func() (network.Stream, error) {
		ctx, cancel := context.WithTimeout(n.ctx, timeout)
		defer cancel()
		ctx = network.WithDialPeerTimeout(ctx, timeout)
		ctx = network.WithAllowLimitedConn(ctx, "chat-send")
		return n.openChatStream(ctx, h, pid)
	}

	s, err := openAttempt()
	if err == nil || !isRetryableChatStreamOpenError(err) {
		return s, err
	}

	log.Printf("[NODE] SendMessage: open stream to %s failed, attempting peer self-heal: %v", peerIdStr, err)

	if healErr := n.recoverPeerForSend(h, pid, peerIdStr, timeout); healErr != nil {
		log.Printf("[NODE] SendMessage: peer self-heal failed for %s: %v", peerIdStr, healErr)
		return nil, err
	}

	s, retryErr := openAttempt()
	if retryErr != nil {
		log.Printf("[NODE] SendMessage: open stream still failing after self-heal for %s: %v", peerIdStr, retryErr)
		return nil, retryErr
	}

	return s, nil
}

func (n *Node) openChatStreamForSendWithContext(
	ctx context.Context,
	h host.Host,
	pid peer.ID,
	peerIdStr string,
	dialTimeout time.Duration,
) (network.Stream, error) {
	openAttempt := func() (network.Stream, error) {
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		attemptCtx := network.WithDialPeerTimeout(ctx, dialTimeout)
		attemptCtx = network.WithAllowLimitedConn(attemptCtx, "chat-send")
		return n.openChatStream(attemptCtx, h, pid)
	}

	s, err := openAttempt()
	if err == nil || !isRetryableChatStreamOpenError(err) {
		return s, err
	}
	if ctxErr := ctx.Err(); ctxErr != nil {
		return nil, ctxErr
	}

	log.Printf("[NODE] SendMessage: open stream to %s failed, attempting peer self-heal: %v", peerIdStr, err)

	if healErr := n.recoverPeerForSendWithContext(ctx, h, pid, peerIdStr); healErr != nil {
		log.Printf("[NODE] SendMessage: peer self-heal failed for %s: %v", peerIdStr, healErr)
		return nil, err
	}

	s, retryErr := openAttempt()
	if retryErr != nil {
		log.Printf("[NODE] SendMessage: open stream still failing after self-heal for %s: %v", peerIdStr, retryErr)
		return nil, retryErr
	}

	return s, nil
}

// SendMessage sends a message directly to a peer via the chat protocol.
// Returns (reply, acked, error):
//   - acked=true: peer ACK'd the message
//   - acked=false, err=nil: message written to stream but no ACK received
//   - acked=false, err!=nil: stream/write error
func (n *Node) SendMessage(peerIdStr string, message string, timeoutMs int) (string, bool, error) {
	result, err := n.SendMessageWithTransport(peerIdStr, message, timeoutMs)
	if err != nil {
		return "", false, err
	}
	return result.Reply, result.Acked, nil
}

type SendMessageResult struct {
	Reply        string
	Acked        bool
	Transport    string
	StreamOpenMs int64
	WriteMs      int64
	AckWaitMs    int64
}

func isAffirmativeAckFrame(reply []byte) bool {
	var frame map[string]json.RawMessage
	if err := json.Unmarshal(reply, &frame); err != nil {
		return false
	}

	rawAck, ok := frame["ack"]
	if !ok {
		return false
	}

	var ack bool
	if err := json.Unmarshal(rawAck, &ack); err != nil {
		return false
	}
	return ack
}

type messageCommandDeadlines struct {
	command  time.Time
	prewrite time.Time
	reserved bool
}

func deadlinesForMessage(start time.Time, timeout time.Duration, message []byte) (messageCommandDeadlines, bool) {
	if timeout <= 0 {
		return messageCommandDeadlines{}, false
	}

	deadlines := messageCommandDeadlines{
		command:  start.Add(timeout),
		prewrite: start.Add(timeout),
	}
	if !requiresCommittedAckReserve(message) {
		return deadlines, true
	}
	if timeout <= CommittedAckReserve {
		return messageCommandDeadlines{}, false
	}
	deadlines.prewrite = deadlines.command.Add(-CommittedAckReserve)
	deadlines.reserved = true
	return deadlines, true
}

func ackDeadlineAfterWrite(commandDeadline, writeCompletedAt time.Time) time.Time {
	reserveDeadline := writeCompletedAt.Add(CommittedAckReserve)
	if commandDeadline.Before(reserveDeadline) {
		return commandDeadline
	}
	return reserveDeadline
}

func (n *Node) sendNow() time.Time {
	if n.sendNowHook != nil {
		return n.sendNowHook()
	}
	return time.Now()
}

func (n *Node) SendMessageWithTransport(peerIdStr string, message string, timeoutMs int) (SendMessageResult, error) {
	n.mu.RLock()
	h := n.host
	n.mu.RUnlock()

	if h == nil {
		return SendMessageResult{}, fmt.Errorf("node not started")
	}

	pid, err := peer.Decode(peerIdStr)
	if err != nil {
		return SendMessageResult{}, fmt.Errorf("invalid peer ID: %w", err)
	}

	timeout := SendTimeout
	if timeoutMs > 0 {
		timeout = time.Duration(timeoutMs) * time.Millisecond
	}
	messageBytes := []byte(message)
	deadlines, admitted := deadlinesForMessage(n.sendNow(), timeout, messageBytes)
	if !admitted {
		return SendMessageResult{}, fmt.Errorf(
			"message timeout %v leaves no pre-write interval before committed ACK reserve %v",
			timeout,
			CommittedAckReserve,
		)
	}

	commandCtx, cancelCommand := context.WithDeadline(n.ctx, deadlines.command)
	defer cancelCommand()
	prewriteCtx, cancelPrewrite := context.WithDeadline(commandCtx, deadlines.prewrite)
	defer cancelPrewrite()

	dialTimeout := timeout
	if deadlines.reserved {
		dialTimeout -= CommittedAckReserve
	}

	streamOpenStart := time.Now()
	s, err := n.openChatStreamForSendWithContext(prewriteCtx, h, pid, peerIdStr, dialTimeout)
	streamOpenMs := time.Since(streamOpenStart).Milliseconds()
	if err != nil {
		return SendMessageResult{StreamOpenMs: streamOpenMs}, fmt.Errorf("open stream: %w", err)
	}
	if err := prewriteCtx.Err(); err != nil || !n.sendNow().Before(deadlines.prewrite) {
		_ = s.Reset()
		if err == nil {
			err = context.DeadlineExceeded
		}
		return SendMessageResult{StreamOpenMs: streamOpenMs}, fmt.Errorf("open stream: %w", err)
	}

	transport := classifyStreamTransport(s)

	// Opening, recovery, and the complete frame write share the pre-write
	// deadline. Installing it is itself part of the bounded operation.
	if err := s.SetDeadline(deadlines.prewrite); err != nil {
		_ = s.Reset()
		return SendMessageResult{StreamOpenMs: streamOpenMs}, fmt.Errorf("set pre-write deadline: %w", err)
	}

	// Write message using 4-byte BE framing (same as inbox protocol)
	writeStart := time.Now()
	if err := writeFrame(s, messageBytes); err != nil {
		_ = s.Reset()
		return SendMessageResult{StreamOpenMs: streamOpenMs}, fmt.Errorf("write message: %w", err)
	}
	writeCompletedAt := n.sendNow()
	writeMs := time.Since(writeStart).Milliseconds()

	ackDeadline := deadlines.command
	if deadlines.reserved {
		ackDeadline = ackDeadlineAfterWrite(deadlines.command, writeCompletedAt)
	}
	writtenResult := SendMessageResult{
		Transport:    transport,
		StreamOpenMs: streamOpenMs,
		WriteMs:      writeMs,
	}
	if err := s.SetDeadline(ackDeadline); err != nil {
		_ = s.Reset()
		return writtenResult, nil
	}
	if err := s.CloseWrite(); err != nil {
		_ = s.Reset()
		return writtenResult, nil
	}

	// Read reply
	ackStart := time.Now()
	replyBytes, err := readFrame(s)
	ackWaitMs := time.Since(ackStart).Milliseconds()
	if err != nil {
		// Message was written but ACK read failed
		_ = s.Reset()
		writtenResult.AckWaitMs = ackWaitMs
		return writtenResult, nil
	}

	result := SendMessageResult{
		Reply:        string(replyBytes),
		Acked:        isAffirmativeAckFrame(replyBytes),
		Transport:    transport,
		StreamOpenMs: streamOpenMs,
		WriteMs:      writeMs,
		AckWaitMs:    ackWaitMs,
	}
	if err := s.Close(); err != nil {
		_ = s.Reset()
	}
	return result, nil
}

// SendMessageWithTimeout sends a message with explicit timeout enforcement
// and stream deadline management. On error after NewStream succeeds, the
// stream is Reset() instead of Close() to signal the transport that the
// connection may be unhealthy.
func (n *Node) SendMessageWithTimeout(peerIdStr string, message string, timeoutMs int) (string, error) {
	n.mu.RLock()
	h := n.host
	n.mu.RUnlock()

	if h == nil {
		return "", fmt.Errorf("node not started")
	}

	pid, err := peer.Decode(peerIdStr)
	if err != nil {
		return "", fmt.Errorf("invalid peer ID: %w", err)
	}

	timeout := SendTimeout
	if timeoutMs > 0 {
		timeout = time.Duration(timeoutMs) * time.Millisecond
	}

	s, err := n.openChatStreamForSend(h, pid, peerIdStr, timeout)
	if err != nil {
		return "", fmt.Errorf("open stream: %w", err)
	}

	// Apply stream-level deadline so OS-level writes/reads don't hang.
	setStreamDeadline(s, timeout)

	// Write message using 4-byte BE framing.
	if err := writeFrame(s, []byte(message)); err != nil {
		s.Reset() // signal unhealthy transport
		return "", fmt.Errorf("write message: %w", err)
	}

	// Read reply.
	replyBytes, err := readFrame(s)
	if err != nil {
		s.Reset()
		return "", fmt.Errorf("read reply: %w", err)
	}

	s.Close()
	return string(replyBytes), nil
}

// setStreamDeadline applies a deadline to a stream for both reads and writes.
func setStreamDeadline(s network.Stream, d time.Duration) {
	s.SetDeadline(time.Now().Add(d))
}

func finishStream(s network.Stream, ok *bool) {
	if *ok {
		_ = s.Close()
		return
	}
	_ = s.Reset()
}

func messageEnvelopeType(msgBytes []byte) string {
	var envelope struct {
		Type string `json:"type"`
	}
	if err := json.Unmarshal(msgBytes, &envelope); err != nil {
		return ""
	}
	return envelope.Type
}

func requiresCommittedAckReserve(msgBytes []byte) bool {
	switch messageEnvelopeType(msgBytes) {
	case "chat_message", "message_reaction", "message_deletion", "contact_request":
		return true
	default:
		return false
	}
}

func (n *Node) shouldDeferDirectAck(msgBytes []byte) bool {
	// F7 + 171: defer the wire ack until Dart durably commits, for every
	// envelope type whose receiver-side handling is durable (chat_message +
	// reactions + deletions) OR must survive a cold-receiver listener-subscribe
	// race (contact_request). A freshly-installed receiver is still cold-starting
	// when the scanner's contact_request arrives, so its ContactRequestListener
	// may not be subscribed to the unbuffered broadcast yet; an immediate ack
	// masks that drop and the sender's success short-circuit skips the durable
	// relay inbox. Deferring the ack forces a cold receiver to time out -> the
	// sender falls back to the inbox -> the request is durably delivered + auto-
	// added on replay. Other types (introductions, …) are legitimately
	// fire-and-forget and ack immediately.
	if !requiresCommittedAckReserve(msgBytes) {
		return false
	}
	if !n.currentFeatureFlags().EnableDeferredDirectAck {
		return false
	}

	n.mu.RLock()
	defer n.mu.RUnlock()
	return n.isStarted && n.eventDispatcher != nil
}

func (n *Node) directConfirmTimeout() time.Duration {
	if n == nil {
		return DirectConfirmTimeout
	}
	if n.directConfirmTimeoutOverride > 0 {
		return n.directConfirmTimeoutOverride
	}
	return DirectConfirmTimeout
}

const directConfirmCallWakeReceiptMaxBytes = 512

type directConfirmResult struct {
	ok              bool
	callWakeReceipt string
}

func validDirectConfirmCallWakeReceipt(value string) bool {
	if value == "" || len(value) > directConfirmCallWakeReceiptMaxBytes || !utf8.ValidString(value) {
		return false
	}
	for _, r := range value {
		if unicode.IsControl(r) {
			return false
		}
	}
	return true
}

func directConfirmAckFrame(callWakeReceipt string) []byte {
	if !validDirectConfirmCallWakeReceipt(callWakeReceipt) {
		return []byte(`{"ack":true}`)
	}

	frame, err := json.Marshal(struct {
		Ack             bool   `json:"ack"`
		CallWakeReceipt string `json:"callWakeReceipt"`
	}{
		Ack:             true,
		CallWakeReceipt: callWakeReceipt,
	})
	if err != nil {
		return []byte(`{"ack":true}`)
	}
	return frame
}

func (n *Node) registerDirectConfirm(nonce string) chan directConfirmResult {
	ch := make(chan directConfirmResult, 1)
	n.pendingConfirmsMu.Lock()
	if n.pendingDirectConfirms == nil {
		n.pendingDirectConfirms = make(map[string]chan directConfirmResult)
	}
	n.pendingDirectConfirms[nonce] = ch
	n.pendingConfirmsMu.Unlock()
	return ch
}

func (n *Node) waitForRegisteredDirectConfirm(
	nonce string,
	ch chan directConfirmResult,
	timeout time.Duration,
) directConfirmResult {
	timer := time.NewTimer(timeout)
	defer timer.Stop()
	defer func() {
		n.pendingConfirmsMu.Lock()
		delete(n.pendingDirectConfirms, nonce)
		n.pendingConfirmsMu.Unlock()
	}()

	select {
	case result := <-ch:
		return result
	case <-timer.C:
		return directConfirmResult{}
	}
}

func (n *Node) waitForDirectConfirm(nonce string, timeout time.Duration) bool {
	ch := n.registerDirectConfirm(nonce)
	return n.waitForRegisteredDirectConfirm(nonce, ch, timeout).ok
}

// ResolveDirectConfirm preserves the legacy deferred-confirm API. A successful
// resolution writes the historical exact {"ack":true} frame.
func (n *Node) ResolveDirectConfirm(nonce string, ok bool) {
	n.ResolveDirectConfirmWithReceipt(nonce, ok, "")
}

// ResolveDirectConfirmWithReceipt optionally binds an opaque application
// receipt to the deferred ACK. Invalid receipts are safely omitted, preserving
// the legacy generic ACK for successful confirmations.
func (n *Node) ResolveDirectConfirmWithReceipt(nonce string, ok bool, callWakeReceipt string) {
	if nonce == "" {
		return
	}
	if !ok || !validDirectConfirmCallWakeReceipt(callWakeReceipt) {
		callWakeReceipt = ""
	}

	n.pendingConfirmsMu.Lock()
	ch, exists := n.pendingDirectConfirms[nonce]
	n.pendingConfirmsMu.Unlock()
	if !exists {
		return
	}

	select {
	case ch <- directConfirmResult{ok: ok, callWakeReceipt: callWakeReceipt}:
	default:
	}
}

// handleIncomingMessage handles incoming chat protocol streams.
// Applies an inbound read deadline to prevent slow/malicious peers
// from holding a goroutine open indefinitely.
func (n *Node) handleIncomingMessage(s network.Stream) {
	ok := false
	defer finishStream(s, &ok)

	remotePeer := s.Conn().RemotePeer().String()

	// Apply bounded read deadline on inbound streams.
	s.SetReadDeadline(time.Now().Add(InboundReadDeadline))

	msgBytes, err := readFrame(s)
	if err != nil {
		log.Printf("[NODE] Read error from %s: %v", remotePeer[:min(20, len(remotePeer))], err)
		return
	}

	toPeer := n.peerId
	timestamp := time.Now().UTC().Format(time.RFC3339Nano)
	msgData := map[string]interface{}{
		"from":       remotePeer,
		"to":         toPeer,
		"content":    string(msgBytes),
		"timestamp":  timestamp,
		"isIncoming": true,
		"transport":  classifyStreamTransport(s),
	}

	if n.shouldDeferDirectAck(msgBytes) {
		nonce := uuid.NewString()
		// WIRE CONTRACT (Go->Dart, doc 118 / plan 120 G5): the "confirmNonce"
		// key on this "message:received" event is consumed by Dart's
		// ChatMessage.fromJson (lib/features/p2p/domain/models/chat_message.dart)
		// to drive the deferred-ack->notify path. Renaming/dropping this key or
		// flipping EnableDeferredDirectAck's default silently breaks live-direct
		// notifications. Guarded by transport_label_test.go
		// TestHandleIncomingMessage_DirectAckContract_AttachesConfirmNonce.
		msgData["confirmNonce"] = nonce
		confirmCh := n.registerDirectConfirm(nonce)
		n.emitEvent("message:received", msgData)

		waitStart := time.Now()
		confirm := n.waitForRegisteredDirectConfirm(nonce, confirmCh, n.directConfirmTimeout())
		waitMs := time.Since(waitStart).Milliseconds()

		if !confirm.ok {
			n.emitTimeoutFired("DirectConfirmTimeout", n.directConfirmTimeout(), waitStart)
			n.emitEvent("message:direct_ack_timing", map[string]interface{}{
				"waitMs":  waitMs,
				"outcome": "timeout",
			})
			log.Printf("[NODE] Direct confirm timeout for %s — not ACKing", nonce[:min(8, len(nonce))])
			return
		}

		ackWriteStart := time.Now()
		ack := directConfirmAckFrame(confirm.callWakeReceipt)
		if err := writeFrame(s, ack); err != nil {
			log.Printf("[NODE] ACK write error for %s: %v", remotePeer[:min(20, len(remotePeer))], err)
			return
		}
		ackWriteMs := time.Since(ackWriteStart).Milliseconds()

		n.emitEvent("message:direct_ack_timing", map[string]interface{}{
			"waitMs":     waitMs,
			"ackWriteMs": ackWriteMs,
			"outcome":    "confirmed",
		})

		ok = true
		return
	}

	ack := []byte(`{"ack":true}`)
	if err := writeFrame(s, ack); err != nil {
		log.Printf("[NODE] ACK write error for %s: %v", remotePeer[:min(20, len(remotePeer))], err)
		return
	}

	n.emitEvent("message:received", msgData)
	ok = true
}

// waitForCircuitAddress polls until at least one /p2p-circuit address
// appears in the host's address set, or the timeout expires.
func (n *Node) waitForCircuitAddress(timeout time.Duration) bool {
	if n.waitForCircuitAddressHook != nil {
		return n.waitForCircuitAddressHook(timeout)
	}

	n.mu.RLock()
	h := n.host
	n.mu.RUnlock()
	return n.waitForCircuitAddressOnHost(h, timeout)
}

// waitForCircuitAddressOnHost keeps an in-place recovery's bounded wait
// independent from later writers of Node.mu. The recovery owner already
// captured the host under the mutex; reacquiring the node-wide lock on every
// poll can otherwise turn a finite circuit-address wait into an unbounded one.
func (n *Node) waitForCircuitAddressOnHost(h host.Host, timeout time.Duration) bool {
	if n.waitForCircuitAddressHook != nil {
		return n.waitForCircuitAddressHook(timeout)
	}

	start := time.Now()
	pollCount := 0
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		pollCount++
		if h == nil {
			return false
		}
		for _, addr := range h.Addrs() {
			if strings.Contains(addr.String(), "/p2p-circuit") {
				n.emitEvent("circuit_address:timing", map[string]interface{}{
					"elapsedMs":           time.Since(start).Milliseconds(),
					"outcome":             "found",
					"pollCount":           pollCount,
					"sinceProcessStartMs": n.sinceProcessStartMs(), // FDC-S1 (b)
				})
				return true
			}
		}
		time.Sleep(200 * time.Millisecond)
	}
	n.emitEvent("circuit_address:timing", map[string]interface{}{
		"elapsedMs":           time.Since(start).Milliseconds(),
		"outcome":             "timeout",
		"pollCount":           pollCount,
		"sinceProcessStartMs": n.sinceProcessStartMs(), // FDC-S1 (b)
	})
	log.Printf("[NODE] Timed out waiting for circuit address after %v", timeout)
	return false
}

func (n *Node) waitForCircuitAddressForStart(timeout time.Duration) bool {
	return n.waitForCircuitAddress(timeout)
}

func (n *Node) rendezvousRegisterForStart(namespace string, serverAddresses []string) error {
	if n.rendezvousRegisterHook != nil {
		return n.rendezvousRegisterHook(namespace, serverAddresses)
	}
	return n.RendezvousRegister(namespace, serverAddresses)
}

// watchConnectionEvents monitors peer connect/disconnect and address events.
func (n *Node) watchConnectionEvents(sub event.Subscription) {
	if sub == nil {
		return
	}
	for ev := range sub.Out() {
		switch e := ev.(type) {
		case event.EvtPeerConnectednessChanged:
			pid := e.Peer.String()
			if e.Connectedness == network.Connected || e.Connectedness == network.Limited {
				addr := ""
				n.mu.RLock()
				h := n.host
				n.mu.RUnlock()
				if h == nil {
					continue
				}

				conns := h.Network().ConnsToPeer(e.Peer)
				direction := "inbound"
				limited := e.Connectedness == network.Limited
				if len(conns) > 0 {
					addr = conns[0].RemoteMultiaddr().String()
					if conns[0].Stat().Direction == network.DirOutbound {
						direction = "outbound"
					}
					if conns[0].Stat().Limited {
						limited = true
					}
				}
				isRelay := n.isRelayPeer(e.Peer)

				n.mu.Lock()
				n.connections[pid] = connectionInfo{
					PeerId:    pid,
					Address:   addr,
					Direction: direction,
					Limited:   limited,
					IsRelay:   isRelay,
				}
				n.mu.Unlock()

				n.emitEvent("peer:connected", map[string]interface{}{
					"peerId":    pid,
					"address":   addr,
					"direction": direction,
					"limited":   limited,
					"isRelay":   isRelay,
				})
				n.handleRelayConnectednessChanged(e.Peer, e.Connectedness)
			} else if e.Connectedness == network.NotConnected {
				n.mu.Lock()
				delete(n.connections, pid)
				n.mu.Unlock()
				n.handleRelayConnectednessChanged(e.Peer, e.Connectedness)

				n.emitEvent("peer:disconnected", map[string]interface{}{
					"peerId": pid,
				})
			}

		case event.EvtLocalAddressesUpdated:
			n.mu.RLock()
			h := n.host
			started := n.startedAt
			n.mu.RUnlock()
			if h == nil {
				continue
			}

			listenAddrs, circuitAddrs := splitHostAddresses(h)
			n.syncRelaySessionFromRuntime("addresses_updated", circuitAddrs)

			sinceStartMs := time.Since(started).Milliseconds()

			n.emitEvent("addresses:updated", map[string]interface{}{
				"listenAddresses":  listenAddrs,
				"circuitAddresses": circuitAddrs,
				"sinceStartMs":     sinceStartMs,
			})
		}
	}
}

func splitHostAddresses(h host.Host) (listenAddrs []string, circuitAddrs []string) {
	if h == nil {
		return nil, nil
	}
	for _, addr := range h.Addrs() {
		s := addr.String()
		if strings.Contains(s, "/p2p-circuit") {
			circuitAddrs = append(circuitAddrs, s)
			continue
		}
		// Belt-and-suspenders: skip loopback/link-local even if AddrsFactory missed them.
		if isNonRoutableAddr(addr) {
			continue
		}
		listenAddrs = append(listenAddrs, s)
	}
	// FDC-11 (Android): when the OS blocks local interface enumeration — Android
	// SELinux denies the Go runtime's netlink route socket (bug b/155595000) —
	// h.Addrs()/AddrsFactory report no routable LAN address, so listenAddrs is
	// empty and the bonsoir advert omits the libp2p port; a same-WiFi peer then
	// discovers this node but has no quic/tcp port to LAN-dial. The bound listen
	// sockets still know their PORT even when the host IP cannot be enumerated,
	// so fall back to them to recover it. These are unspecified (0.0.0.0 / ::)
	// addrs — deliberately NOT run through isNonRoutableAddr, since the dialing
	// peer supplies the IP from mDNS and only the port is mined from here (by the
	// Dart advert's _libp2pListenPort). No-op on platforms where h.Addrs() already
	// yields a routable LAN address (e.g. iOS), so this only heals the blocked case.
	if len(listenAddrs) == 0 {
		for _, addr := range h.Network().ListenAddresses() {
			s := addr.String()
			if strings.Contains(s, "/p2p-circuit") {
				continue
			}
			listenAddrs = append(listenAddrs, s)
		}
	}
	return listenAddrs, circuitAddrs
}

func (n *Node) isRelayPeer(pid peer.ID) bool {
	n.mu.RLock()
	defer n.mu.RUnlock()
	for _, relayPeerID := range n.relayPeerOrder {
		if relayPeerID == pid {
			return true
		}
	}
	return false
}

func (n *Node) emitRelayStateEvent(reason string) {
	if n.relaySessionMgr == nil || !n.reservationAwareHealthEnabled() {
		return
	}

	data := n.relaySessionMgr.StatusFields()
	if reason != "" {
		data["reason"] = reason
	}
	n.emitEvent("relay:state", data)
}

// AcknowledgeGroupRecovery clears the pending group recovery signal after
// Flutter successfully rejoins group topics.
func (n *Node) AcknowledgeGroupRecovery() error {
	n.mu.RLock()
	started := n.isStarted
	mgr := n.relaySessionMgr
	n.mu.RUnlock()

	if !started || mgr == nil {
		return fmt.Errorf("node not started")
	}

	mgr.AcknowledgeGroupRecovery()
	n.emitRelayStateEvent("group_recovery_acknowledged")
	return nil
}

func (n *Node) handleRelayConnectednessChanged(pid peer.ID, connectedness network.Connectedness) {
	if n.relaySessionMgr == nil || !n.isRelayPeer(pid) {
		return
	}

	reason := "connectedness_changed"
	switch connectedness {
	case network.Connected:
		reason = "relay_connected"
	case network.NotConnected:
		reason = "relay_disconnected"
	}

	_, circuitAddrs := splitHostAddresses(n.Host())
	n.syncRelaySessionFromRuntime(reason, circuitAddrs)
}

// emitEvent sends a push event to Flutter via the callback.
// emitTimeoutFired emits a timeout:fired event for instrumentation.
func (n *Node) emitTimeoutFired(name string, configured time.Duration, start time.Time) {
	n.emitEvent("timeout:fired", map[string]interface{}{
		"timeoutName":  name,
		"configuredMs": configured.Milliseconds(),
		"actualMs":     time.Since(start).Milliseconds(),
	})
}

// Phase 4: Uses the async event dispatcher when available, falling back
// to synchronous delivery for backward compatibility.
// sinceProcessStartMs returns the elapsed wall-clock ms from the Dart
// process-start epoch (NodeConfig.ProcessStartEpochMs) to now, anchoring Go
// cold-start timing emits to Dart's clock. Returns -1 when the epoch was not
// supplied (caller predates FDC-S1). FDC-S1 observation-only; never gates logic.
func (n *Node) sinceProcessStartMs() int64 {
	epoch := n.processStartEpochMs.Load()
	if epoch <= 0 {
		return -1
	}
	return time.Now().UnixMilli() - epoch
}

func (n *Node) emitEvent(eventName string, data map[string]interface{}) {
	if n.eventCallback == nil {
		return
	}

	// Use the async dispatcher if available (Phase 4).
	if n.eventDispatcher != nil {
		n.eventDispatcher.Emit(eventName, data)
		return
	}

	// Fallback: synchronous delivery (pre-Phase 4 behavior).
	payload := map[string]interface{}{
		"event": eventName,
		"data":  data,
	}

	jsonBytes, err := json.Marshal(payload)
	if err != nil {
		log.Printf("[NODE] Event marshal error: %v", err)
		return
	}

	n.eventCallback.OnEvent(string(jsonBytes))
}

// SetHolePunchTracerForTests injects a test-controlled holepunch.EventTracer.
// NET-REL-02 Option A: production leaves this nil and installs the real
// emitting tracer; tests inject their own collector before Start().
func (n *Node) SetHolePunchTracerForTests(t holepunch.EventTracer) {
	n.mu.Lock()
	n.holePunchTracerForTests = t
	n.mu.Unlock()
}

// SetForcePublicReachabilityForTests forces ForceReachabilityPublic() in place
// of the production ForceReachabilityPrivate(). NET-REL-02 Option A: used only
// by PROTOCOL-feasibility tests; false in production.
func (n *Node) SetForcePublicReachabilityForTests(v bool) {
	n.mu.Lock()
	n.forcePublicReachabilityForTests = v
	n.mu.Unlock()
}

// Host returns the underlying libp2p host (for protocol implementations).
func (n *Node) Host() host.Host {
	n.mu.RLock()
	defer n.mu.RUnlock()
	return n.host
}

// Context returns the node's context.
func (n *Node) Context() context.Context {
	return n.ctx
}

// PeerId returns the node's peer ID string.
func (n *Node) PeerId() string {
	n.mu.RLock()
	defer n.mu.RUnlock()
	return n.peerId
}

// Namespace returns the node's rendezvous namespace.
func (n *Node) Namespace() string {
	n.mu.RLock()
	defer n.mu.RUnlock()
	return n.namespace
}

// --- Frame I/O (4-byte BE length prefix, matching relay server) ---

func readFrame(r io.Reader) ([]byte, error) {
	var lenBuf [4]byte
	if _, err := io.ReadFull(r, lenBuf[:]); err != nil {
		return nil, fmt.Errorf("read length: %w", err)
	}
	length := binary.BigEndian.Uint32(lenBuf[:])
	if length > MaxFrameLen {
		return nil, fmt.Errorf("frame too large: %d", length)
	}
	data := make([]byte, length)
	if _, err := io.ReadFull(r, data); err != nil {
		return nil, fmt.Errorf("read payload: %w", err)
	}
	return data, nil
}

func writeFrame(w io.Writer, data []byte) error {
	if len(data) > MaxFrameLen {
		return fmt.Errorf("frame too large: %d", len(data))
	}
	var lenBuf [4]byte
	binary.BigEndian.PutUint32(lenBuf[:], uint32(len(data)))
	if _, err := w.Write(lenBuf[:]); err != nil {
		return fmt.Errorf("write length: %w", err)
	}
	if _, err := w.Write(data); err != nil {
		return fmt.Errorf("write payload: %w", err)
	}
	return nil
}
