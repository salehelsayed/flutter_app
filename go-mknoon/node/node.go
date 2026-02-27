package node

import (
	"context"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"strings"
	"sync"
	"time"

	"github.com/libp2p/go-libp2p"
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
	mu              sync.RWMutex
	host            host.Host
	ctx             context.Context
	cancel          context.CancelFunc
	peerId          string
	isStarted       bool
	relayAddresses  []string
	namespace       string
	eventCallback   EventCallback
	eventSub        event.Subscription
	connections     map[string]connectionInfo
	relayReady      chan struct{}
	relayReadyOnce  sync.Once
	startedAt       time.Time // for startup timing instrumentation
	lastConfig      *NodeConfig // saved for Restart()
}

type connectionInfo struct {
	PeerId    string `json:"peerId"`
	Address   string `json:"address"`
	Direction string `json:"direction"`
}

// NewNode creates a new Node instance without an event callback.
func NewNode() *Node {
	return &Node{
		connections: make(map[string]connectionInfo),
	}
}

// New creates a new Node instance with an event callback for Go → Flutter push events.
func New(cb EventCallback) *Node {
	return &Node{
		connections:   make(map[string]connectionInfo),
		eventCallback: cb,
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
	n.lastConfig = &cfgCopy

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
	if len(relayAddresses) == 0 {
		relayAddresses = []string{DefaultRelayAddress}
	}
	n.relayAddresses = relayAddresses

	// Parse relay multiaddrs into AddrInfo for AutoRelay.
	// Merge addresses for the same peer ID (e.g. WSS + QUIC for the same relay).
	relayInfoMap := make(map[peer.ID]*peer.AddrInfo)
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
	}
	relayInfos := make([]peer.AddrInfo, 0, len(relayInfoMap))
	for _, info := range relayInfoMap {
		relayInfos = append(relayInfos, *info)
	}

	// Build listen addresses
	listenAddrs := []string{
		"/ip4/0.0.0.0/udp/0/quic-v1",
		"/ip4/0.0.0.0/tcp/0/ws",
		"/ip4/0.0.0.0/tcp/0",
	}
	if cfg.ListenPort > 0 {
		listenAddrs = []string{
			fmt.Sprintf("/ip4/0.0.0.0/udp/%d/quic-v1", cfg.ListenPort),
			fmt.Sprintf("/ip4/0.0.0.0/tcp/%d/ws", cfg.ListenPort),
			fmt.Sprintf("/ip4/0.0.0.0/tcp/%d", cfg.ListenPort),
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
	}
	if len(relayInfos) > 0 {
		hostOpts = append(hostOpts,
			libp2p.EnableAutoRelayWithStaticRelays(relayInfos,
				autorelay.WithBootDelay(0),               // Static relays known; skip candidate wait
				autorelay.WithBackoff(30*time.Second),    // Retry in 30s, not 1 hour
				autorelay.WithMinInterval(5*time.Second), // Re-query peer source every 5s, not 30s
			),
		)
	}
	h, err := libp2p.New(hostOpts...)
	if err != nil {
		return nil, fmt.Errorf("create host: %w", err)
	}

	n.host = h
	n.peerId = h.ID().String()
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

	// Warm relay connections concurrently in background.
	// Each relayInfo may contain multiple addresses (e.g. WSS + QUIC) for
	// the same peer — host.Connect() tries all addresses internally.
	go func() {
		var wg sync.WaitGroup
		for _, info := range relayInfos {
			wg.Add(1)
			go func(ri peer.AddrInfo) {
				defer wg.Done()
				if err := n.warmRelayConnection(ri); err != nil {
					log.Printf("[NODE] relay dial FAILED (%s): %v", ri.ID.String()[:min(20, len(ri.ID.String()))], err)
				} else {
					n.relayReadyOnce.Do(func() { close(n.relayReady) })
				}
			}(info)
		}
		wg.Wait()

		// Auto-register on rendezvous after relay connection.
		// Wait for circuit address to appear before registering so that
		// the peer record includes the relay circuit address.
		if cfg.AutoRegister {
			n.waitForCircuitAddress(10 * time.Second)
			if err := n.RendezvousRegister(n.namespace, nil); err != nil {
				log.Printf("[NODE] auto-register failed: %v", err)
			}
		}
	}()

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
	n.host = nil
	n.eventSub = nil
	n.relayReadyOnce = sync.Once{} // reset so next Start() can use it
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
		for _, addr := range n.host.Addrs() {
			s := addr.String()
			if strings.Contains(s, "/p2p-circuit") {
				circuitAddrs = append(circuitAddrs, s)
			} else {
				listenAddrs = append(listenAddrs, s)
			}
		}
		for _, c := range n.connections {
			conns = append(conns, map[string]interface{}{
				"peerId":    c.PeerId,
				"address":   c.Address,
				"direction": c.Direction,
			})
		}
	}

	return map[string]interface{}{
		"ok":               true,
		"peerId":           n.peerId,
		"isStarted":        n.isStarted,
		"listenAddresses":  listenAddrs,
		"circuitAddresses": circuitAddrs,
		"connections":      conns,
	}
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
	ctx, cancel := context.WithTimeout(n.ctx, DialTimeout)
	defer cancel()

	if err := n.host.Connect(ctx, info); err != nil {
		return fmt.Errorf("dial relay: %w", err)
	}

	log.Printf("[NODE] Warmed relay connection: %s", info.ID.String()[:min(20, len(info.ID.String()))])
	return nil
}

// ReconnectRelays performs a full node restart to recover circuit addresses.
//
// go-libp2p's AutoRelay (v0.38.2) does NOT reliably re-reserve circuit
// addresses after a relay disconnection. A full Stop() + Start() with
// the saved NodeConfig creates a fresh libp2p host + AutoRelay, which
// reliably obtains circuit addresses on startup.
func (n *Node) ReconnectRelays() error {
	n.mu.RLock()
	cfg := n.lastConfig
	started := n.isStarted
	n.mu.RUnlock()

	if !started {
		return fmt.Errorf("node not started")
	}
	if cfg == nil {
		return fmt.Errorf("no saved config — cannot restart")
	}

	log.Printf("[NODE] ReconnectRelays: performing full node restart")

	// Stop the current node (closes host, cancels context, clears state).
	if err := n.Stop(); err != nil {
		log.Printf("[NODE] ReconnectRelays: Stop() error (continuing): %v", err)
	}

	// Re-start with the saved config (creates fresh host + AutoRelay).
	// Disable auto-register since we don't need rendezvous re-registration
	// on recovery — just circuit address restoration.
	restartCfg := *cfg
	restartCfg.AutoRegister = false

	state, err := n.Start(restartCfg)
	if err != nil {
		return fmt.Errorf("restart Start() failed: %w", err)
	}

	// Restore original AutoRegister so future recoveries preserve it.
	// Start() saved restartCfg (with AutoRegister=false) into lastConfig;
	// we need the original value for rendezvous TTL re-registration.
	n.mu.Lock()
	n.lastConfig.AutoRegister = cfg.AutoRegister
	n.mu.Unlock()

	log.Printf("[NODE] ReconnectRelays: node restarted, peerId=%s, waiting for circuit addresses...",
		state.PeerId)

	// Wait for AutoRelay to obtain circuit addresses (same as first startup).
	if ok := n.waitForCircuitAddress(10 * time.Second); ok {
		log.Printf("[NODE] ReconnectRelays: circuit addresses obtained ✓")
	} else {
		log.Printf("[NODE] ReconnectRelays: WARNING — no circuit addresses after 10s")
	}

	return nil
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

	return h.Connect(ctx, ai)
}

// DialPeerViaRelay connects to a peer through the relay circuit address only.
// This is a fast probe (~100ms for NO_RESERVATION, ~500ms for connection) to
// determine if a peer is online without a full discover/dial cycle.
func (n *Node) DialPeerViaRelay(peerIdStr string) error {
	n.mu.RLock()
	h := n.host
	relayAddrs := n.relayAddresses
	n.mu.RUnlock()

	if h == nil {
		return fmt.Errorf("node not started")
	}

	pid, err := peer.Decode(peerIdStr)
	if err != nil {
		return fmt.Errorf("invalid peer ID: %w", err)
	}

	if len(relayAddrs) == 0 {
		return fmt.Errorf("no relay addresses configured")
	}

	// Parse the first relay address to get the relay peer info
	relayMaddr, err := ma.NewMultiaddr(relayAddrs[0])
	if err != nil {
		return fmt.Errorf("parse relay address: %w", err)
	}
	relayInfo, err := peer.AddrInfoFromP2pAddr(relayMaddr)
	if err != nil {
		return fmt.Errorf("parse relay addr info: %w", err)
	}

	// Construct circuit multiaddr: relayAddr + /p2p-circuit/p2p/<peerId>
	// Strip the /p2p/<relayPeerId> component from the relay address first
	relayTransport, _ := ma.SplitFunc(relayMaddr, func(c ma.Component) bool {
		return c.Protocol().Code == ma.P_P2P
	})
	circuitSuffix, err := ma.NewMultiaddr(
		fmt.Sprintf("/p2p/%s/p2p-circuit/p2p/%s", relayInfo.ID.String(), peerIdStr),
	)
	if err != nil {
		return fmt.Errorf("build circuit suffix: %w", err)
	}
	circuitAddr := relayTransport.Encapsulate(circuitSuffix)

	ai := peer.AddrInfo{
		ID:    pid,
		Addrs: []ma.Multiaddr{circuitAddr},
	}

	ctx, cancel := context.WithTimeout(n.ctx, RelayProbeTimeout)
	defer cancel()

	return h.Connect(ctx, ai)
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

// SendMessage sends a message directly to a peer via the chat protocol.
// Returns (reply, acked, error):
//   - acked=true: peer ACK'd the message
//   - acked=false, err=nil: message written to stream but no ACK received
//   - acked=false, err!=nil: stream/write error
func (n *Node) SendMessage(peerIdStr string, message string, timeoutMs int) (string, bool, error) {
	n.mu.RLock()
	h := n.host
	n.mu.RUnlock()

	if h == nil {
		return "", false, fmt.Errorf("node not started")
	}

	pid, err := peer.Decode(peerIdStr)
	if err != nil {
		return "", false, fmt.Errorf("invalid peer ID: %w", err)
	}

	timeout := SendTimeout
	if timeoutMs > 0 {
		timeout = time.Duration(timeoutMs) * time.Millisecond
	}

	ctx, cancel := context.WithTimeout(n.ctx, timeout)
	defer cancel()

	s, err := h.NewStream(ctx, pid, ChatProtocol)
	if err != nil {
		return "", false, fmt.Errorf("open stream: %w", err)
	}
	defer s.Close()

	// Apply deadline to stream read/write so stale connections fail fast.
	s.SetDeadline(time.Now().Add(timeout))

	// Write message using 4-byte BE framing (same as inbox protocol)
	if err := writeFrame(s, []byte(message)); err != nil {
		return "", false, fmt.Errorf("write message: %w", err)
	}

	// Read reply
	replyBytes, err := readFrame(s)
	if err != nil {
		// Message was written but ACK read failed
		return "", false, nil
	}

	return string(replyBytes), true, nil
}

// handleIncomingMessage handles incoming chat protocol streams.
func (n *Node) handleIncomingMessage(s network.Stream) {
	defer s.Close()

	remotePeer := s.Conn().RemotePeer().String()

	msgBytes, err := readFrame(s)
	if err != nil {
		log.Printf("[NODE] Read error from %s: %v", remotePeer[:min(20, len(remotePeer))], err)
		return
	}

	// Send ACK reply
	ack := []byte(`{"ack":true}`)
	_ = writeFrame(s, ack)

	// Build ChatMessage and emit to Flutter
	toPeer := n.peerId
	timestamp := time.Now().UTC().Format(time.RFC3339Nano)

	msgData := map[string]interface{}{
		"from":       remotePeer,
		"to":         toPeer,
		"content":    string(msgBytes),
		"timestamp":  timestamp,
		"isIncoming": true,
	}

	n.emitEvent("message:received", msgData)
}

// waitForCircuitAddress polls until at least one /p2p-circuit address
// appears in the host's address set, or the timeout expires.
func (n *Node) waitForCircuitAddress(timeout time.Duration) bool {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		n.mu.RLock()
		h := n.host
		n.mu.RUnlock()
		if h == nil {
			return false
		}
		for _, addr := range h.Addrs() {
			if strings.Contains(addr.String(), "/p2p-circuit") {
				return true
			}
		}
		time.Sleep(200 * time.Millisecond)
	}
	log.Printf("[NODE] Timed out waiting for circuit address after %v", timeout)
	return false
}

// watchConnectionEvents monitors peer connect/disconnect and address events.
func (n *Node) watchConnectionEvents() {
	for ev := range n.eventSub.Out() {
		switch e := ev.(type) {
		case event.EvtPeerConnectednessChanged:
			pid := e.Peer.String()
			if e.Connectedness == network.Connected {
				addr := ""
				conns := n.host.Network().ConnsToPeer(e.Peer)
				direction := "inbound"
				if len(conns) > 0 {
					addr = conns[0].RemoteMultiaddr().String()
					if conns[0].Stat().Direction == network.DirOutbound {
						direction = "outbound"
					}
				}

				n.mu.Lock()
				n.connections[pid] = connectionInfo{
					PeerId:    pid,
					Address:   addr,
					Direction: direction,
				}
				n.mu.Unlock()

				n.emitEvent("peer:connected", map[string]interface{}{
					"peerId":    pid,
					"address":   addr,
					"direction": direction,
				})
			} else if e.Connectedness == network.NotConnected {
				n.mu.Lock()
				delete(n.connections, pid)
				n.mu.Unlock()

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

			var listenAddrs, circuitAddrs []string
			for _, addr := range h.Addrs() {
				s := addr.String()
				if strings.Contains(s, "/p2p-circuit") {
					circuitAddrs = append(circuitAddrs, s)
				} else {
					listenAddrs = append(listenAddrs, s)
				}
			}

			sinceStartMs := time.Since(started).Milliseconds()

			n.emitEvent("addresses:updated", map[string]interface{}{
				"listenAddresses":  listenAddrs,
				"circuitAddresses": circuitAddrs,
				"sinceStartMs":     sinceStartMs,
			})
		}
	}
}

// emitEvent sends a push event to Flutter via the callback.
func (n *Node) emitEvent(eventName string, data map[string]interface{}) {
	if n.eventCallback == nil {
		return
	}

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
