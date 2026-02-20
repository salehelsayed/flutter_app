package main

import (
	"context"
	"fmt"
	"log"
	"sync"
	"sync/atomic"
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

var activeRendezvousStreams atomic.Int64

// --- In-memory store ---

type peerRegistration struct {
	signedPeerRecord []byte
	expiresAt        time.Time
}

type RendezvousStore struct {
	mu            sync.RWMutex
	registrations map[string]map[string]*peerRegistration // namespace → peerId → registration
	cancelCleanup context.CancelFunc
}

func NewRendezvousStore() *RendezvousStore {
	return &RendezvousStore{
		registrations: make(map[string]map[string]*peerRegistration),
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
	s.mu.Lock()
	defer s.mu.Unlock()
	now := time.Now()
	for ns, peers := range s.registrations {
		for pid, reg := range peers {
			if reg.expiresAt.Before(now) {
				delete(peers, pid)
				log.Printf("[RENDEZVOUS] Expired registration: %s / %s", ns, pid[:20])
			}
		}
		if len(peers) == 0 {
			delete(s.registrations, ns)
		}
	}
}

func (s *RendezvousStore) Register(ns string, peerId string, signedPeerRecord []byte, ttl uint64) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.registrations[ns]; !ok {
		s.registrations[ns] = make(map[string]*peerRegistration)
	}
	s.registrations[ns][peerId] = &peerRegistration{
		signedPeerRecord: signedPeerRecord,
		expiresAt:        time.Now().Add(time.Duration(ttl) * time.Second),
	}
}

func (s *RendezvousStore) Unregister(ns string, peerId string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if peers, ok := s.registrations[ns]; ok {
		delete(peers, peerId)
		if len(peers) == 0 {
			delete(s.registrations, ns)
		}
	}
}

func (s *RendezvousStore) Discover(ns string, requestingPeer string, limit uint64) []Registration {
	s.mu.RLock()
	defer s.mu.RUnlock()

	var results []Registration
	peers, ok := s.registrations[ns]
	if !ok {
		return results
	}

	now := time.Now()
	var count uint64
	for pid, reg := range peers {
		if count >= limit {
			break
		}
		if reg.expiresAt.After(now) && pid != requestingPeer {
			results = append(results, Registration{
				Ns:               ns,
				SignedPeerRecord: reg.signedPeerRecord,
			})
			count++
		}
	}
	return results
}

func (s *RendezvousStore) Stats() (namespaces, totalPeers int) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	namespaces = len(s.registrations)
	for _, peers := range s.registrations {
		totalPeers += len(peers)
	}
	return
}

// --- Stream handler ---

func HandleRendezvousStream(s network.Stream, store *RendezvousStore) {
	start := time.Now()
	current := activeRendezvousStreams.Add(1)
	defer func() {
		activeRendezvousStreams.Add(-1)
		log.Printf("[RENDEZVOUS] stream handled in %s", time.Since(start))
	}()
	defer s.Close()

	remotePeer := s.Conn().RemotePeer()
	log.Printf("[RENDEZVOUS] Incoming stream from %s (active=%d)", shortPeerId(remotePeer), current)

	// Read varint-prefixed request
	reader := msgio.NewVarintReaderSize(s, 1<<20) // 1MB max
	msgBytes, err := reader.ReadMsg()
	if err != nil {
		log.Printf("[RENDEZVOUS] Read error from %s: %v", shortPeerId(remotePeer), err)
		return
	}
	defer reader.ReleaseMsg(msgBytes)

	req, err := UnmarshalRzMessage(msgBytes)
	if err != nil {
		log.Printf("[RENDEZVOUS] Decode error: %v", err)
		return
	}

	log.Printf("[RENDEZVOUS] Request type=%d from %s", req.Type, shortPeerId(remotePeer))

	resp, err := handleRendezvousRequest(remotePeer, req, store)
	if err != nil {
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
