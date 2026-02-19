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
	"github.com/libp2p/go-libp2p/p2p/net/connmgr"
	"github.com/libp2p/go-libp2p/p2p/protocol/circuitv2/client"
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

	// Create the libp2p host
	h, err := libp2p.New(
		libp2p.Identity(privKey),
		libp2p.ListenAddrStrings(listenAddrs...),
		libp2p.ConnectionManager(cm),
		libp2p.EnableRelay(),
		libp2p.EnableHolePunching(),
		libp2p.NATPortMap(),
	)
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

	// Subscribe to connection events
	sub, err := h.EventBus().Subscribe([]interface{}{
		new(event.EvtPeerConnectednessChanged),
	})
	if err != nil {
		log.Printf("[NODE] Failed to subscribe to events: %v", err)
	} else {
		n.eventSub = sub
		go n.watchConnectionEvents()
	}

	n.isStarted = true
	n.relayReady = make(chan struct{})

	// Connect to relay in background
	go func() {
		for _, addr := range relayAddresses {
			if err := n.connectToRelay(addr); err != nil {
				log.Printf("[NODE] Relay connect failed: %v", err)
			} else {
				n.relayReadyOnce.Do(func() { close(n.relayReady) })
			}
		}

		// Auto-register on rendezvous after relay connection
		if cfg.AutoRegister {
			if err := n.RendezvousRegister(n.namespace, nil); err != nil {
				log.Printf("[NODE] Auto-register failed: %v", err)
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

// connectToRelay dials the relay server and makes a reservation.
func (n *Node) connectToRelay(relayAddr string) error {
	maddr, err := ma.NewMultiaddr(relayAddr)
	if err != nil {
		return fmt.Errorf("parse relay address: %w", err)
	}

	addrInfo, err := peer.AddrInfoFromP2pAddr(maddr)
	if err != nil {
		return fmt.Errorf("parse relay addr info: %w", err)
	}

	ctx, cancel := context.WithTimeout(n.ctx, DialTimeout)
	defer cancel()

	if err := n.host.Connect(ctx, *addrInfo); err != nil {
		return fmt.Errorf("dial relay: %w", err)
	}

	// Request a relay reservation
	_, err = client.Reserve(ctx, n.host, *addrInfo)
	if err != nil {
		log.Printf("[NODE] Relay reservation failed (may not be needed): %v", err)
		// Not fatal — relay may auto-provide circuit
	}

	log.Printf("[NODE] Connected to relay: %s", addrInfo.ID.String()[:20])
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

	ctx, cancel := context.WithTimeout(n.ctx, DialTimeout)
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
func (n *Node) SendMessage(peerIdStr string, message string) (string, error) {
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

	ctx, cancel := context.WithTimeout(n.ctx, SendTimeout)
	defer cancel()

	s, err := h.NewStream(ctx, pid, ChatProtocol)
	if err != nil {
		return "", fmt.Errorf("open stream: %w", err)
	}
	defer s.Close()

	// Write message using 4-byte BE framing (same as inbox protocol)
	if err := writeFrame(s, []byte(message)); err != nil {
		return "", fmt.Errorf("write message: %w", err)
	}

	// Read reply
	replyBytes, err := readFrame(s)
	if err != nil {
		// No reply is OK — peer might not send one
		return "", nil
	}

	return string(replyBytes), nil
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

// watchConnectionEvents monitors peer connect/disconnect events.
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
