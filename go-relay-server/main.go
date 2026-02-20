package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/signal"
	"runtime"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/event"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/p2p/protocol/circuitv2/relay"
	ma "github.com/multiformats/go-multiaddr"
)

// Same private key as the JS server — produces the same Peer ID.
var privateKeyRaw = []byte{
	3, 98, 126, 31, 53, 38, 77, 83, 95, 52, 208,
	245, 12, 231, 179, 29, 77, 119, 64, 225, 28, 76,
	152, 60, 22, 170, 169, 92, 240, 114, 50, 34, 97,
	34, 166, 6, 69, 146, 135, 77, 74, 250, 62, 215,
	106, 6, 45, 2, 118, 162, 136, 195, 108, 174, 61,
	180, 216, 136, 89, 9, 101, 139, 157, 193,
}

const (
	serverDNS  = "mknoun.xyz"
	serverIP4  = "13.60.15.36"
	wsPort     = 4000 // Local WS — nginx proxies WSS:4001 → WS:4000
	tcpPort    = 4005
	wssPort    = 4001 // Announced WSS port (via nginx)
	quicPort   = 4002 // New: direct QUIC for mobile clients
)

var totalConnected atomic.Int64

func main() {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Load private key (Ed25519, 64 bytes: seed + public)
	privKey, err := crypto.UnmarshalEd25519PrivateKey(privateKeyRaw)
	if err != nil {
		log.Fatalf("Failed to unmarshal private key: %v", err)
	}

	// Announce addresses — what peers see from the outside
	announceAddrs := []ma.Multiaddr{
		ma.StringCast(fmt.Sprintf("/dns4/%s/tcp/%d/wss", serverDNS, wssPort)),
		ma.StringCast(fmt.Sprintf("/ip4/%s/tcp/%d", serverIP4, tcpPort)),
		ma.StringCast(fmt.Sprintf("/dns4/%s/udp/%d/quic-v1", serverDNS, quicPort)),
	}

	// Create the libp2p host
	h, err := libp2p.New(
		libp2p.Identity(privKey),
		libp2p.ListenAddrStrings(
			fmt.Sprintf("/ip4/0.0.0.0/tcp/%d/ws", wsPort),
			fmt.Sprintf("/ip4/0.0.0.0/tcp/%d", tcpPort),
			fmt.Sprintf("/ip4/0.0.0.0/udp/%d/quic-v1", quicPort),
		),
		libp2p.AddrsFactory(func([]ma.Multiaddr) []ma.Multiaddr {
			return announceAddrs
		}),
		libp2p.EnableRelayService(
			relay.WithInfiniteLimits(),
		),
		libp2p.ForceReachabilityPublic(),
	)
	if err != nil {
		log.Fatalf("Failed to create libp2p host: %v", err)
	}

	// Initialize subsystems
	store := NewRendezvousStore()
	store.StartCleanup(ctx)

	fcmPath := os.Getenv("FIREBASE_SERVICE_ACCOUNT")
	if fcmPath == "" {
		fcmPath = "./firebase-service-account.json"
	}
	push := NewPushService(ctx, fcmPath)
	inbox := NewInboxStore(push)

	// Register protocol handlers
	h.SetStreamHandler(RendezvousProtocol, func(s network.Stream) {
		HandleRendezvousStream(s, store)
	})
	h.SetStreamHandler(InboxProtocol, func(s network.Stream) {
		HandleInboxStream(s, inbox)
	})

	// Subscribe to connection events
	sub, err := h.EventBus().Subscribe([]interface{}{
		new(event.EvtPeerConnectednessChanged),
	})
	if err != nil {
		log.Fatalf("Failed to subscribe to events: %v", err)
	}
	go func() {
		for ev := range sub.Out() {
			switch e := ev.(type) {
			case event.EvtPeerConnectednessChanged:
				if e.Connectedness == network.Connected {
					current := totalConnected.Add(1)
					logPeerConnected(e.Peer, inbox, current)
				} else if e.Connectedness == network.NotConnected {
					current := totalConnected.Add(-1)
					log.Printf("[NODE] Peer disconnected: %s (total=%d)", shortPeerId(e.Peer), current)
				}
			}
		}
	}()

	// Start
	log.Println("Starting go-libp2p relay + rendezvous + inbox server...")

	log.Printf("Peer ID: %s", h.ID())
	log.Println("Listening addresses:")
	for _, addr := range h.Addrs() {
		log.Printf("  - %s", addr)
	}
	log.Println("Announced addresses:")
	for _, addr := range announceAddrs {
		log.Printf("  - %s/p2p/%s", addr, h.ID())
	}
	log.Printf("Relay circuit: /p2p/%s/p2p-circuit", h.ID())
	log.Println()
	log.Printf("Protocols:")
	log.Printf("  Rendezvous: %s", RendezvousProtocol)
	log.Printf("  Inbox:      %s", InboxProtocol)
	log.Printf("  Push:       %s", push.Status())
	log.Println()

	// Periodic stats
	go logStatsPeriodically(ctx, h, inbox, store)

	// Wait for shutdown signal
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	sig := <-sigCh

	log.Printf("Shutting down (%s)...", sig)
	sub.Close()
	store.StopCleanup()
	if err := h.Close(); err != nil {
		log.Printf("[NODE] Error during shutdown: %v", err)
	}
	log.Println("Node stopped.")
}

func logPeerConnected(p peer.ID, inbox *InboxStore, total int64) {
	short := shortPeerId(p)
	log.Printf("[NODE] Peer connected: %s (total=%d)", short, total)
	count := inbox.Count(p.String())
	if count > 0 {
		log.Printf("[INBOX] Peer %s has %d pending messages", short, count)
	}
}

func logStatsPeriodically(ctx context.Context, h host.Host, inbox *InboxStore, rz *RendezvousStore) {
	ticker := time.NewTicker(60 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ticker.C:
			conns := len(h.Network().Peers())
			rzNs, rzPeers := rz.Stats()
			inboxPeers, inboxMsgs := inbox.Stats()
			tokenCount := inbox.push.TokenCount()
			var mem runtime.MemStats
			runtime.ReadMemStats(&mem)
			log.Printf("[STATS] conns=%d rz_ns=%d rz_peers=%d inbox_peers=%d inbox_msgs=%d push_tokens=%d heap_mb=%d goroutines=%d active_rz_streams=%d active_inbox_streams=%d",
				conns, rzNs, rzPeers, inboxPeers, inboxMsgs, tokenCount,
				mem.HeapAlloc/1024/1024, runtime.NumGoroutine(),
				activeRendezvousStreams.Load(), activeInboxStreams.Load())
		case <-ctx.Done():
			return
		}
	}
}

func shortPeerId(p peer.ID) string {
	s := p.String()
	if len(s) > 20 {
		return s[:20] + "..."
	}
	return s
}
