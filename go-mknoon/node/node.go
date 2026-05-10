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
	ma "github.com/multiformats/go-multiaddr"
)

// EventCallback is the interface for push events from Go → Flutter.
type EventCallback interface {
	OnEvent(jsonString string)
}

// Node wraps a go-libp2p host with mknoon protocol handlers.
type Node struct {
	mu             sync.RWMutex
	host           host.Host
	ctx            context.Context
	cancel         context.CancelFunc
	peerId         string
	isStarted      bool
	relayAddresses []string
	relayPeerOrder []peer.ID
	featureFlags   *FeatureFlags
	namespace      string
	eventCallback  EventCallback
	eventSub       event.Subscription
	connections    map[string]connectionInfo
	relayReady     chan struct{}
	relayReadyOnce sync.Once
	startedAt      time.Time   // for startup timing instrumentation
	lastConfig     *NodeConfig // saved for Restart()

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
	pubsubRejectDiagMu   sync.Mutex
	pubsubRejectDiagLast map[string]time.Time
	pubsubRejectDiagNow  func() time.Time

	// Test seams for startup timing behavior.
	warmRelayConnectionHook            func(peer.AddrInfo) error
	warmRelayConnectionWithTimeoutHook func(peer.AddrInfo, time.Duration) error
	waitForCircuitAddressHook          func(time.Duration) bool
	rendezvousRegisterHook             func(string, []string) error
	rendezvousDiscoverHook             func(string, []string) ([]peer.AddrInfo, error)
	refreshRelaySessionHook            func() *RecoveryResult
	openChatStreamHook                 func(context.Context, host.Host, peer.ID) (network.Stream, error)
	recoverPeerForSendHook             func(host.Host, peer.ID, string, time.Duration) error
	joinGroupTopicSubscribeHook        func(*pubsub.Topic) (*pubsub.Subscription, error)

	// Personal rendezvous refresh state.
	personalRendezvousRefreshCancel context.CancelFunc
	personalRendezvousRefreshLoopID uint64
	personalRendezvousRegistering   atomic.Bool

	pendingConfirmsMu            sync.Mutex
	pendingDirectConfirms        map[string]chan bool
	directConfirmTimeoutOverride time.Duration // test seam
}

type connectionInfo struct {
	PeerId    string `json:"peerId"`
	Address   string `json:"address"`
	Direction string `json:"direction"`
	Limited   bool   `json:"limited,omitempty"`
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
		groupDialBackoff:      make(map[string]groupPeerDialState),
		groupRecoverySem:      make(chan struct{}, GroupDiscoveryConcurrency),
		pubsubRejectDiagLast:  make(map[string]time.Time),
		pendingDirectConfirms: make(map[string]chan bool),
	}
}

// New creates a new Node instance with an event callback for Go → Flutter push events.
func New(cb EventCallback) *Node {
	return &Node{
		connections:           make(map[string]connectionInfo),
		eventCallback:         cb,
		relaySessionMgr:       NewRelaySessionManager(),
		groupDialBackoff:      make(map[string]groupPeerDialState),
		groupRecoverySem:      make(chan struct{}, GroupDiscoveryConcurrency),
		pubsubRejectDiagLast:  make(map[string]time.Time),
		pendingDirectConfirms: make(map[string]chan bool),
	}
}

// Start initializes the libp2p host and connects to the relay.
// Accepts a NodeConfig and returns the initial NodeState on success.
func (n *Node) Start(cfg NodeConfig) (*NodeState, error) {
	n.mu.Lock()
	defer n.mu.Unlock()

	if n.isStarted {
		return nil, fmt.Errorf("node already started")
	}

	// Save config for Restart().
	cfgCopy := cfg
	cfgCopy.PersonalRendezvousRefreshInterval = cfgCopy.PersonalRendezvousRefreshEvery()
	n.lastConfig = &cfgCopy
	flags := cfg.EffectiveFlags()
	n.featureFlags = &flags

	// Decode private key from hex
	keyBytes, err := hex.DecodeString(cfg.PrivateKeyHex)
	if err != nil {
		return nil, fmt.Errorf("invalid private key hex: %w", err)
	}

	privKey, err := crypto.UnmarshalEd25519PrivateKey(keyBytes)
	if err != nil {
		return nil, fmt.Errorf("invalid Ed25519 key: %w", err)
	}

	n.ctx, n.cancel = context.WithCancel(context.Background())

	// Connection manager
	cm, err := connmgr.NewConnManager(10, 100, connmgr.WithGracePeriod(time.Minute))
	if err != nil {
		return nil, fmt.Errorf("connection manager: %w", err)
	}

	// Parse relay addresses
	relayAddresses := cfg.RelayAddresses
	if relayAddresses == nil {
		relayAddresses = []string{DefaultRelayAddress}
	}
	relayAddresses = limitRelayAddresses(relayAddresses, flags)
	n.relayAddresses = relayAddresses

	// Parse relay multiaddrs into AddrInfo for AutoRelay.
	// Merge addresses for the same peer ID (e.g. WSS + QUIC for the same relay).
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
	n.relayPeerOrder = relayPeerOrder
	if n.relaySessionMgr != nil {
		for _, relayPeerID := range relayPeerOrder {
			n.relaySessionMgr.InitRelayPeer(relayPeerID)
		}
	}

	// Build listen addresses (dual-stack: IPv4 + IPv6)
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

	// Create the libp2p host with AutoRelay for circuit address management.
	// ForceReachabilityPrivate tells AutoRelay to always seek relay reservations,
	// which is correct for mobile devices that are always behind NAT.
	hostOpts := []libp2p.Option{
		libp2p.Identity(privKey),
		libp2p.ListenAddrStrings(listenAddrs...),
		libp2p.ConnectionManager(cm),
		libp2p.EnableRelay(),
		libp2p.EnableHolePunching(),
		libp2p.NATPortMap(),
		libp2p.ForceReachabilityPrivate(),
		libp2p.AddrsFactory(filterAddresses),
	}
	if len(relayInfos) > 0 {
		hostOpts = append(hostOpts,
			libp2p.EnableAutoRelayWithStaticRelays(relayInfos,
				autorelay.WithBootDelay(0), // Static relays known; skip candidate wait
				// Phase 3b experiment: lower the retry cadence from the
				// instrumentation baseline so foreground recovery gets an
				// earlier AutoRelay retry window after a warm dial.
				autorelay.WithBackoff(ForegroundAutoRelayRetryCadence),
				autorelay.WithMinInterval(ForegroundAutoRelayRetryCadence),
			),
		)
	}
	libp2pStart := time.Now()
	h, err := libp2p.New(hostOpts...)
	libp2pNewMs := time.Since(libp2pStart).Milliseconds()
	if err != nil {
		return nil, fmt.Errorf("create host: %w", err)
	}

	n.host = h
	n.peerId = h.ID().String()

	// Log announced addresses (post-filter).
	announceAddrs := h.Addrs()
	log.Printf("[NODE] Announcing %d addresses (loopback/link-local filtered out)", len(announceAddrs))
	for _, a := range announceAddrs {
		log.Printf("[NODE]   %s", a.String())
	}

	// Initialize PubSub (GossipSub) for group messaging.
	pubsubStart := time.Now()
	if err := n.initPubSub(); err != nil {
		h.Close()
		return nil, fmt.Errorf("init pubsub: %w", err)
	}
	pubsubInitMs := time.Since(pubsubStart).Milliseconds()

	n.namespace = cfg.Namespace
	if n.namespace == "" {
		n.namespace = RendezvousPrefix + n.peerId
	}

	// Register chat message handler
	h.SetStreamHandler(ChatProtocol, n.handleIncomingMessage)

	// Subscribe to connection and address events
	sub, err := h.EventBus().Subscribe([]interface{}{
		new(event.EvtPeerConnectednessChanged),
		new(event.EvtLocalAddressesUpdated),
	})
	if err != nil {
		log.Printf("[NODE] Failed to subscribe to events: %v", err)
	} else {
		n.eventSub = sub
		go n.watchConnectionEvents()
	}

	n.isStarted = true
	n.startedAt = time.Now()
	n.relayReady = make(chan struct{})
	n.personalRendezvousRegistering.Store(false)

	// Phase 4: Initialize event dispatcher for async delivery.
	if n.eventCallback != nil && n.eventDispatcher == nil {
		n.eventDispatcher = NewEventDispatcher(n.eventCallback, 1024)
	}

	n.emitEvent("node:startup_timing", map[string]interface{}{
		"phase":        "host_ready",
		"libp2pNewMs":  libp2pNewMs,
		"pubsubInitMs": pubsubInitMs,
	})

	// Warm relay connections concurrently in background.
	// Each relayInfo may contain multiple addresses (e.g. WSS + QUIC) for
	// the same peer — host.Connect() tries all addresses internally.
	relayWarmStart := time.Now()
	go func() {
		for _, info := range relayInfos {
			go func(ri peer.AddrInfo) {
				if err := n.warmRelayConnectionForStart(ri); err != nil {
					log.Printf("[NODE] relay dial FAILED (%s): %v", ri.ID.String()[:min(20, len(ri.ID.String()))], err)
				} else {
					n.relayReadyOnce.Do(func() { close(n.relayReady) })
				}
			}(info)
		}
	}()

	// Emit relay_warm_done when first relay connection succeeds.
	// Capture channel and context locally so a Stop/Start cycle doesn't
	// cause this goroutine to reference the next cycle's channel.
	if len(relayInfos) > 0 {
		relayReadyCh := n.relayReady
		ctx := n.ctx
		go func() {
			select {
			case <-relayReadyCh:
				n.emitEvent("node:startup_timing", map[string]interface{}{
					"phase":           "relay_warm_done",
					"relayWarmMs":     time.Since(relayWarmStart).Milliseconds(),
					"relaysAttempted": len(relayInfos),
				})
			case <-ctx.Done():
				// Node stopped before relay connected — no event
			}
		}()
	}

	// Auto-register as soon as the first relay path yields a discoverable
	// circuit address. Do not wait for slower warm attempts to settle.
	if cfg.AutoRegister {
		go n.autoRegisterPersonalNamespaceForStart()
	}

	return n.stateLocked(), nil
}

// Stop shuts down the libp2p host.
func (n *Node) Stop() error {
	n.mu.Lock()
	defer n.mu.Unlock()

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
		if err := n.host.Close(); err != nil {
			return fmt.Errorf("host close: %w", err)
		}
	}

	n.isStarted = false
	n.connections = make(map[string]connectionInfo)
	n.relayPeerOrder = nil
	n.host = nil
	n.eventSub = nil
	n.groupDialBackoff = make(map[string]groupPeerDialState)
	n.groupRecoverySem = make(chan struct{}, GroupDiscoveryConcurrency)
	n.relayReadyOnce = sync.Once{} // reset so next Start() can use it
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
	ctx, cancel := context.WithTimeout(n.ctx, timeout)
	defer cancel()
	ctx = network.WithDialPeerTimeout(ctx, timeout)

	if err := n.host.Connect(ctx, info); err != nil {
		if ctx.Err() == context.DeadlineExceeded {
			n.emitTimeoutFired("DialTimeout", timeout, start)
		}
		n.emitEvent("relay:warm_timing", map[string]interface{}{
			"elapsedMs": time.Since(start).Milliseconds(),
			"outcome":   "failed",
			"relayId":   info.ID.String()[:min(20, len(info.ID.String()))],
		})
		return fmt.Errorf("dial relay: %w", err)
	}

	n.emitEvent("relay:warm_timing", map[string]interface{}{
		"elapsedMs": time.Since(start).Milliseconds(),
		"outcome":   "success",
		"relayId":   info.ID.String()[:min(20, len(info.ID.String()))],
	})
	log.Printf("[NODE] Warmed relay connection: %s", info.ID.String()[:min(20, len(info.ID.String()))])
	return nil
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
		var circuitAddressWaitMs int64
		relayWarmParallelism := 0
		reservationPath := "poll_fallback"
		reservationWinnerPeer := ""
		foregroundRecoveryPath := "background_fallback"

		// Build relay AddrInfos for warm connection.
		if len(relayAddrs) == 0 {
			relayAddrs = []string{DefaultRelayAddress}
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

		// Attempt to reconnect to each relay peer in parallel so one slow dial
		// does not serialize the whole foreground recovery attempt.
		warmStart := time.Now()
		relayWarmParallelism = len(warmInfos)
		type relayWarmAttempt struct {
			peerID peer.ID
			err    error
		}
		attempts := make(chan relayWarmAttempt, max(1, relayWarmParallelism))
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
		relayWarmMs = time.Since(warmStart).Milliseconds()

		warmSucceeded := false
		var lastWarmErr error
		for attempt := range attempts {
			peerLabel := attempt.peerID.String()[:min(20, len(attempt.peerID.String()))]
			if attempt.err != nil {
				log.Printf("[NODE] RefreshRelaySession: warm %s failed: %v", peerLabel, attempt.err)
				lastWarmErr = attempt.err
				continue
			}
			warmSucceeded = true
			log.Printf("[NODE] RefreshRelaySession: warm %s success", peerLabel)
		}

		// Give the faster foreground path a short chance to win first, then keep
		// the existing long wait budget as fallback safety behavior.
		waitStart := time.Now()
		if ok := n.waitForCircuitAddress(ForegroundCircuitAddressWaitTimeout); ok {
			log.Printf("[NODE] RefreshRelaySession: circuit addresses obtained ✓")
			foregroundRecoveryPath = "foreground_success"
			refreshErr = nil
		} else {
			remainingWait := CircuitAddressWaitTimeout - ForegroundCircuitAddressWaitTimeout
			if remainingWait < 0 {
				remainingWait = 0
			}
			if remainingWait > 0 && n.waitForCircuitAddress(remainingWait) {
				log.Printf("[NODE] RefreshRelaySession: circuit addresses obtained via fallback ✓")
				refreshErr = nil
			} else if !warmSucceeded && lastWarmErr != nil {
				refreshErr = lastWarmErr
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
			ReserveRpcMs:                 0,
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
	return result
}

// ReconnectRelays attempts in-place relay recovery first, then falls back
// to a full host restart if in-place recovery fails.
//
// Phase 4: This method now uses singleflight coalescing via the relay
// session manager, so concurrent callers share one recovery attempt.
// The return value now includes structured recovery fields.
func (n *Node) ReconnectRelays() (*RecoveryResult, error) {
	n.mu.RLock()
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
	if circuitOk {
		log.Printf("[NODE] ReconnectRelays: circuit addresses obtained ✓")
	} else {
		log.Printf("[NODE] ReconnectRelays: WARNING — no circuit addresses after 10s")
	}

	n.mu.RLock()
	mgr := n.relaySessionMgr
	n.mu.RUnlock()

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
		return n.recoverPeerForSendHook(h, pid, peerIdStr, timeout)
	}

	if err := h.Network().ClosePeer(pid); err != nil {
		log.Printf("[NODE] SendMessage: ClosePeer(%s) returned: %v", peerIdStr, err)
	}

	return n.dialPeerViaRelayWithTimeout(peerIdStr, timeout)
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

	streamOpenStart := time.Now()
	s, err := n.openChatStreamForSend(h, pid, peerIdStr, timeout)
	streamOpenMs := time.Since(streamOpenStart).Milliseconds()
	if err != nil {
		return SendMessageResult{StreamOpenMs: streamOpenMs}, fmt.Errorf("open stream: %w", err)
	}
	defer s.Close()

	transport := classifyStreamTransport(s)

	// Apply deadline to stream read/write so stale connections fail fast.
	s.SetDeadline(time.Now().Add(timeout))

	// Write message using 4-byte BE framing (same as inbox protocol)
	writeStart := time.Now()
	if err := writeFrame(s, []byte(message)); err != nil {
		return SendMessageResult{StreamOpenMs: streamOpenMs}, fmt.Errorf("write message: %w", err)
	}
	writeMs := time.Since(writeStart).Milliseconds()

	// Read reply
	ackStart := time.Now()
	replyBytes, err := readFrame(s)
	ackWaitMs := time.Since(ackStart).Milliseconds()
	if err != nil {
		// Message was written but ACK read failed
		return SendMessageResult{Transport: transport, StreamOpenMs: streamOpenMs, WriteMs: writeMs, AckWaitMs: ackWaitMs}, nil
	}

	return SendMessageResult{
		Reply:        string(replyBytes),
		Acked:        true,
		Transport:    transport,
		StreamOpenMs: streamOpenMs,
		WriteMs:      writeMs,
		AckWaitMs:    ackWaitMs,
	}, nil
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

func (n *Node) shouldDeferDirectAck(msgBytes []byte) bool {
	if messageEnvelopeType(msgBytes) != "chat_message" {
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

func (n *Node) registerDirectConfirm(nonce string) chan bool {
	ch := make(chan bool, 1)
	n.pendingConfirmsMu.Lock()
	if n.pendingDirectConfirms == nil {
		n.pendingDirectConfirms = make(map[string]chan bool)
	}
	n.pendingDirectConfirms[nonce] = ch
	n.pendingConfirmsMu.Unlock()
	return ch
}

func (n *Node) waitForRegisteredDirectConfirm(nonce string, ch chan bool, timeout time.Duration) bool {
	timer := time.NewTimer(timeout)
	defer timer.Stop()
	defer func() {
		n.pendingConfirmsMu.Lock()
		delete(n.pendingDirectConfirms, nonce)
		n.pendingConfirmsMu.Unlock()
	}()

	select {
	case ok := <-ch:
		return ok
	case <-timer.C:
		return false
	}
}

func (n *Node) waitForDirectConfirm(nonce string, timeout time.Duration) bool {
	ch := n.registerDirectConfirm(nonce)
	return n.waitForRegisteredDirectConfirm(nonce, ch, timeout)
}

func (n *Node) ResolveDirectConfirm(nonce string, ok bool) {
	if nonce == "" {
		return
	}

	n.pendingConfirmsMu.Lock()
	ch, exists := n.pendingDirectConfirms[nonce]
	n.pendingConfirmsMu.Unlock()
	if !exists {
		return
	}

	select {
	case ch <- ok:
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
		msgData["confirmNonce"] = nonce
		confirmCh := n.registerDirectConfirm(nonce)
		n.emitEvent("message:received", msgData)

		waitStart := time.Now()
		confirmed := n.waitForRegisteredDirectConfirm(nonce, confirmCh, n.directConfirmTimeout())
		waitMs := time.Since(waitStart).Milliseconds()

		if !confirmed {
			n.emitTimeoutFired("DirectConfirmTimeout", n.directConfirmTimeout(), waitStart)
			n.emitEvent("message:direct_ack_timing", map[string]interface{}{
				"waitMs":  waitMs,
				"outcome": "timeout",
			})
			log.Printf("[NODE] Direct confirm timeout for %s — not ACKing", nonce[:min(8, len(nonce))])
			return
		}

		ackWriteStart := time.Now()
		ack := []byte(`{"ack":true}`)
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

	start := time.Now()
	pollCount := 0
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		pollCount++
		n.mu.RLock()
		h := n.host
		n.mu.RUnlock()
		if h == nil {
			return false
		}
		for _, addr := range h.Addrs() {
			if strings.Contains(addr.String(), "/p2p-circuit") {
				n.emitEvent("circuit_address:timing", map[string]interface{}{
					"elapsedMs": time.Since(start).Milliseconds(),
					"outcome":   "found",
					"pollCount": pollCount,
				})
				return true
			}
		}
		time.Sleep(200 * time.Millisecond)
	}
	n.emitEvent("circuit_address:timing", map[string]interface{}{
		"elapsedMs": time.Since(start).Milliseconds(),
		"outcome":   "timeout",
		"pollCount": pollCount,
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
func (n *Node) watchConnectionEvents() {
	for ev := range n.eventSub.Out() {
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

				n.mu.Lock()
				n.connections[pid] = connectionInfo{
					PeerId:    pid,
					Address:   addr,
					Direction: direction,
					Limited:   limited,
				}
				n.mu.Unlock()

				n.emitEvent("peer:connected", map[string]interface{}{
					"peerId":    pid,
					"address":   addr,
					"direction": direction,
					"limited":   limited,
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
