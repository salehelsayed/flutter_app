package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"runtime"
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
	"github.com/prometheus/client_golang/prometheus/promhttp"
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
	serverDNS = "mknoun.xyz"
	serverIP4 = "13.60.15.36"
	wsPort    = 4000 // Local WS — nginx proxies WSS:4001 → WS:4000
	tcpPort   = 4005
	wssPort   = 4001 // Announced WSS port (via nginx)
	quicPort  = 4002 // New: direct QUIC for mobile clients
)

func main() {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Load private key (Ed25519, 64 bytes: seed + public)
	privKey, err := crypto.UnmarshalEd25519PrivateKey(privateKeyRaw)
	if err != nil {
		log.Fatalf("Failed to unmarshal private key: %v", err)
	}

	limitsCfg := loadServerLimitsFromEnv()

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
			relay.WithResources(relayResourcesFromServerLimits(limitsCfg)),
		),
		libp2p.ForceReachabilityPublic(),
	)
	if err != nil {
		log.Fatalf("Failed to create libp2p host: %v", err)
	}

	// Initialize subsystems
	fcmPath := os.Getenv("FIREBASE_SERVICE_ACCOUNT")
	if fcmPath == "" {
		fcmPath = "./firebase-service-account.json"
	}

	backendCfg := loadBackendConfigFromEnv()
	stores, err := newControlPlaneStores(ctx, backendCfg, limitsCfg, fcmPath)
	if err != nil {
		log.Fatalf("Failed to initialize control-plane stores: %v", err)
	}
	defer func() {
		if err := stores.Close(); err != nil {
			log.Printf("Failed to close control-plane stores: %v", err)
		}
	}()

	store := stores.Rendezvous
	store.StartCleanup(ctx)
	push := stores.Push
	inbox := stores.Inbox
	groupInbox := stores.GroupInbox
	media := NewMediaStore(mediaDataDir)
	media.StartCleanup(ctx)
	profile := NewProfileStore(profileDataDir)

	// Register protocol handlers
	h.SetStreamHandler(RendezvousProtocol, func(s network.Stream) {
		HandleRendezvousStream(s, store)
	})
	h.SetStreamHandler(InboxProtocol, func(s network.Stream) {
		HandleInboxStream(s, inbox, groupInbox)
	})
	h.SetStreamHandler(MediaProtocol, func(s network.Stream) {
		HandleMediaStream(s, media, profile)
	})

	// Start periodic group inbox prune (every 1 hour).
	go func() {
		ticker := time.NewTicker(1 * time.Hour)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				groupInbox.Prune()
			case <-ctx.Done():
				return
			}
		}
	}()

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
					connectionsActive.Inc()
					connectionsCounter.Inc()
					conns := len(h.Network().Peers())
					logPeerConnected(e.Peer, inbox, int64(conns))
				} else if e.Connectedness == network.NotConnected {
					connectionsActive.Dec()
					disconnectionsCounter.Inc()
					conns := len(h.Network().Peers())
					log.Printf("[NODE] Peer disconnected: %s (total=%d)", shortPeerId(e.Peer), conns)
				}
			}
		}
	}()

	// Start
	log.Println("Starting go-libp2p relay + rendezvous + inbox server...")
	log.Printf("Control-plane backend: %s", backendCfg.Kind)
	log.Printf(
		"Relay limits: reservations=%d connectionsPerPeer=%d inboxPerPeer=%d groupInboxPerGroup=%d",
		limitsCfg.MaxRelayReservations,
		limitsCfg.MaxConnectionsPerPeer,
		limitsCfg.MaxInboxMessagesPerPeer,
		limitsCfg.MaxGroupInboxMessages,
	)

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
	log.Printf("  Media:      %s", MediaProtocol)
	log.Printf("  Push:       %s", push.Status())
	log.Println()

	// Prometheus metrics endpoint on :2112
	go func() {
		mux := http.NewServeMux()
		mux.Handle("/metrics", promhttp.Handler())
		log.Println("[METRICS] Serving Prometheus metrics on :2112/metrics")
		if err := http.ListenAndServe(":2112", mux); err != nil {
			log.Printf("[METRICS] HTTP server error: %v", err)
		}
	}()

	// Periodic stats
	go logStatsPeriodically(ctx, h, inbox, groupInbox, store, media, profile)

	// Wait for shutdown signal
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	sig := <-sigCh

	log.Printf("Shutting down (%s)...", sig)
	sub.Close()
	store.StopCleanup()
	media.StopCleanup()
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

func logStatsPeriodically(ctx context.Context, h host.Host, inbox *InboxStore, groupInbox *GroupInboxStore, rz *RendezvousStore, media *MediaStore, profile *ProfileStore) {
	ticker := time.NewTicker(60 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ticker.C:
			conns := len(h.Network().Peers())
			rzNs, rzPeers := rz.Stats()
			inboxPeers, inboxMsgs := inbox.Stats()
			tokenCount := inbox.push.TokenCount()
			mediaBlobs, mediaDiskMB := media.Stats()
			pCount, pDiskMB := profile.Stats()
			groupInboxGroups, groupInboxMsgs := groupInbox.Stats()
			var mem runtime.MemStats
			runtime.ReadMemStats(&mem)

			// Update Prometheus gauges
			rendezvousNamespacesGauge.Set(float64(rzNs))
			rendezvousPeersGauge.Set(float64(rzPeers))
			inboxPeersPending.Set(float64(inboxPeers))
			inboxMessagesPending.Set(float64(inboxMsgs))
			inboxPushTokens.Set(float64(tokenCount))
			mediaBlobsPending.Set(float64(mediaBlobs))
			mediaDiskBytes.Set(float64(mediaDiskMB * 1024 * 1024))
			profileCountGauge.Set(float64(pCount))
			profileDiskBytes.Set(float64(pDiskMB * 1024 * 1024))
			groupInboxGroupsActiveGauge.Set(float64(groupInboxGroups))
			groupInboxMessagesStoredGauge.Set(float64(groupInboxMsgs))

			log.Printf("[STATS] conns=%d rz_ns=%d rz_peers=%d inbox_peers=%d inbox_msgs=%d push_tokens=%d media_blobs=%d media_disk_mb=%d profile_count=%d profile_disk_mb=%d group_inbox_groups=%d group_inbox_msgs=%d heap_mb=%d goroutines=%d",
				conns, rzNs, rzPeers, inboxPeers, inboxMsgs, tokenCount,
				mediaBlobs, mediaDiskMB,
				pCount, pDiskMB,
				groupInboxGroups, groupInboxMsgs,
				mem.HeapAlloc/1024/1024, runtime.NumGoroutine())
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
