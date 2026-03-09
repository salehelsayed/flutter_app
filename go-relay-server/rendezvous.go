package main

import (
	"context"
	"fmt"
	"log"
	"time"

	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/core/record"
	"github.com/libp2p/go-msgio"
)

const (
	RendezvousProtocol = "/canvas/rendezvous/1.0.0"
	maxTTL             = 2 * 60 * 60 // 2 hours in seconds
	maxDiscoverLimit   = 64
	maxNamespaceLen    = 256
	cleanupInterval    = 60 * time.Second
)

// --- In-memory store ---

type peerRegistration struct {
	signedPeerRecord []byte
	expiresAt        time.Time
}

// RendezvousStore wraps a RendezvousBackend and manages cleanup lifecycle.
type RendezvousStore struct {
	backend       RendezvousBackend
	cancelCleanup context.CancelFunc
}

// NewRendezvousStore creates a store with an in-memory backend.
func NewRendezvousStore() *RendezvousStore {
	return &RendezvousStore{
		backend: newMemoryRendezvousBackend(),
	}
}

// NewRendezvousStoreWithBackend creates a store with a custom backend.
func NewRendezvousStoreWithBackend(backend RendezvousBackend) *RendezvousStore {
	return &RendezvousStore{
		backend: backend,
	}
}

func (s *RendezvousStore) StartCleanup(ctx context.Context) {
	cleanupCtx, cancel := context.WithCancel(ctx)
	s.cancelCleanup = cancel
	go func() {
		ticker := time.NewTicker(cleanupInterval)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				s.cleanupExpired()
			case <-cleanupCtx.Done():
				return
			}
		}
	}()
}

func (s *RendezvousStore) StopCleanup() {
	if s.cancelCleanup != nil {
		s.cancelCleanup()
	}
}

func (s *RendezvousStore) cleanupExpired() {
	s.backend.Cleanup()
}

func (s *RendezvousStore) Register(ns string, peerId string, signedPeerRecord []byte, ttl uint64) {
	s.backend.Register(ns, peerId, signedPeerRecord, ttl)
}

func (s *RendezvousStore) Unregister(ns string, peerId string) {
	s.backend.Unregister(ns, peerId)
}

func (s *RendezvousStore) Discover(ns string, requestingPeer string, limit uint64) []Registration {
	return s.backend.Discover(ns, requestingPeer, limit)
}

func (s *RendezvousStore) Stats() (namespaces, totalPeers int) {
	return s.backend.Stats()
}

// --- Stream handler ---

func HandleRendezvousStream(s network.Stream, store *RendezvousStore) {
	start := time.Now()
	activeStreams.WithLabelValues("rendezvous").Inc()
	streamResult := "ok"
	defer func() {
		activeStreams.WithLabelValues("rendezvous").Dec()
		streamDuration.WithLabelValues("rendezvous", streamResult).Observe(time.Since(start).Seconds())
		log.Printf("[RENDEZVOUS] stream handled in %s", time.Since(start))
	}()
	defer s.Close()

	remotePeer := s.Conn().RemotePeer()
	log.Printf("[RENDEZVOUS] Incoming stream from %s", shortPeerId(remotePeer))

	// Read varint-prefixed request
	reader := msgio.NewVarintReaderSize(s, 1<<20) // 1MB max
	msgBytes, err := reader.ReadMsg()
	if err != nil {
		streamResult = "error"
		streamErrorsCounter.WithLabelValues("rendezvous", "read").Inc()
		log.Printf("[RENDEZVOUS] Read error from %s: %v", shortPeerId(remotePeer), err)
		return
	}
	defer reader.ReleaseMsg(msgBytes)

	req, err := UnmarshalRzMessage(msgBytes)
	if err != nil {
		streamResult = "error"
		streamErrorsCounter.WithLabelValues("rendezvous", "decode").Inc()
		log.Printf("[RENDEZVOUS] Decode error: %v", err)
		return
	}

	log.Printf("[RENDEZVOUS] Request type=%d from %s", req.Type, shortPeerId(remotePeer))

	resp, err := handleRendezvousRequest(remotePeer, req, store)
	if err != nil {
		streamResult = "error"
		log.Printf("[RENDEZVOUS] Handler error: %v", err)
		return
	}

	if resp == nil {
		return // UNREGISTER has no response
	}

	// Write varint-prefixed response
	respBytes := resp.Marshal()
	writer := msgio.NewVarintWriter(s)
	if err := writer.WriteMsg(respBytes); err != nil {
		streamResult = "error"
		streamErrorsCounter.WithLabelValues("rendezvous", "write").Inc()
		log.Printf("[RENDEZVOUS] Write error: %v", err)
	} else {
		log.Printf("[RENDEZVOUS] Sent response type=%d", resp.Type)
	}
}

func handleRendezvousRequest(remotePeer peer.ID, req *RzMessage, store *RendezvousStore) (*RzMessage, error) {
	switch req.Type {
	case MessageType_REGISTER:
		return handleRegister(remotePeer, req.Register, store)
	case MessageType_UNREGISTER:
		return handleUnregister(remotePeer, req.Unregister, store)
	case MessageType_DISCOVER:
		return handleDiscover(remotePeer, req.Discover, store)
	default:
		return nil, fmt.Errorf("unknown message type: %d", req.Type)
	}
}

func handleRegister(remotePeer peer.ID, reg *Register, store *RendezvousStore) (*RzMessage, error) {
	if reg == nil {
		return nil, fmt.Errorf("nil register message")
	}

	if len(reg.Ns) >= maxNamespaceLen {
		return nil, fmt.Errorf("namespace too long")
	}

	log.Printf("[RENDEZVOUS] REGISTER ns=%s ttl=%d from %s", reg.Ns, reg.TTL, shortPeerId(remotePeer))

	ttl := reg.TTL
	if ttl == 0 {
		ttl = maxTTL
	}
	if ttl > maxTTL {
		ttl = maxTTL
	}

	// Validate signed peer record
	_, err := record.UnmarshalEnvelope(reg.SignedPeerRecord)
	if err != nil {
		log.Printf("[RENDEZVOUS] Invalid peer record: %v", err)
		return &RzMessage{
			Type: MessageType_REGISTER_RESPONSE,
			RegisterResponse: &RegisterResponse{
				Status:     ResponseStatus_E_INVALID_SIGNED_PEER_RECORD,
				StatusText: fmt.Sprintf("invalid peer record: %v", err),
				TTL:        0,
			},
		}, nil
	}

	store.Register(reg.Ns, remotePeer.String(), reg.SignedPeerRecord, ttl)
	rendezvousRegisteredCounter.Inc()

	return &RzMessage{
		Type: MessageType_REGISTER_RESPONSE,
		RegisterResponse: &RegisterResponse{
			Status:     ResponseStatus_OK,
			StatusText: "OK",
			TTL:        ttl,
		},
	}, nil
}

func handleUnregister(remotePeer peer.ID, unreg *Unregister, store *RendezvousStore) (*RzMessage, error) {
	if unreg == nil {
		return nil, fmt.Errorf("nil unregister message")
	}

	log.Printf("[RENDEZVOUS] UNREGISTER ns=%s from %s", unreg.Ns, shortPeerId(remotePeer))
	store.Unregister(unreg.Ns, remotePeer.String())

	return nil, nil // No response for unregister
}

func handleDiscover(remotePeer peer.ID, disc *Discover, store *RendezvousStore) (*RzMessage, error) {
	if disc == nil {
		return nil, fmt.Errorf("nil discover message")
	}

	limit := disc.Limit
	if limit == 0 {
		limit = maxDiscoverLimit
	}
	if limit > maxDiscoverLimit {
		limit = maxDiscoverLimit
	}

	log.Printf("[RENDEZVOUS] DISCOVER ns=%s limit=%d from %s", disc.Ns, limit, shortPeerId(remotePeer))

	regs := store.Discover(disc.Ns, remotePeer.String(), limit)
	rendezvousDiscoveredCounter.Inc()

	return &RzMessage{
		Type: MessageType_DISCOVER_RESPONSE,
		DiscoverResponse: &DiscoverResponse{
			Status:        ResponseStatus_OK,
			StatusText:    "OK",
			Registrations: regs,
			Cookie:        []byte{},
		},
	}, nil
}
