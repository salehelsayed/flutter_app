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

const version = "1.5.0"

func main() {
	// Handle subcommands
	if len(os.Args) > 1 {
		switch os.Args[1] {
		case "version", "--version", "-v":
			fmt.Println("relay-server v" + version)
			return
		case "generate-key":
			generateAndPrintKey()
			return
		}
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	serverCfg := loadServerConfigFromEnv()
	storageCfg := loadStorageConfigFromEnv()

	// Load private key (Ed25519, 64 bytes: seed + public)
	privKey, err := crypto.UnmarshalEd25519PrivateKey(serverCfg.PrivateKey)
	if err != nil {
		log.Fatalf("Failed to unmarshal private key: %v", err)
	}

	limitsCfg := loadServerLimitsFromEnv()

	// Announce addresses — what peers see from the outside
	announceAddrs := []ma.Multiaddr{
		ma.StringCast(fmt.Sprintf("/dns4/%s/tcp/%d/wss", serverCfg.ServerDNS, serverCfg.WSSPort)),
		ma.StringCast(fmt.Sprintf("/ip4/%s/tcp/%d", serverCfg.ServerIP4, serverCfg.TCPPort)),
		ma.StringCast(fmt.Sprintf("/dns4/%s/udp/%d/quic-v1", serverCfg.ServerDNS, serverCfg.QUICPort)),
	}

	// Create the libp2p host
	h, err := libp2p.New(
		libp2p.Identity(privKey),
		libp2p.ListenAddrStrings(
			fmt.Sprintf("/ip4/0.0.0.0/tcp/%d/ws", serverCfg.WSPort),
			fmt.Sprintf("/ip4/0.0.0.0/tcp/%d", serverCfg.TCPPort),
			fmt.Sprintf("/ip4/0.0.0.0/udp/%d/quic-v1", serverCfg.QUICPort),
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
	media := NewMediaStore(storageCfg.MediaDir)
	media.StartCleanup(ctx)
	profile := NewProfileStore(storageCfg.ProfileDir)
	biz = newBusinessMetrics()

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
					biz.RecordPeerSeen(e.Peer.String())
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
	log.Printf("Starting relay-server v%s", version)
	log.Printf("Control-plane backend: %s", backendCfg.Kind)
	keySource := "default"
	if serverCfg.IsCustomKey() {
		keySource = "custom"
	}
	log.Printf("Server config: dns=%s ip=%s ws=%d tcp=%d wss=%d quic=%d key=%s",
		serverCfg.ServerDNS, serverCfg.ServerIP4,
		serverCfg.WSPort, serverCfg.TCPPort, serverCfg.WSSPort, serverCfg.QUICPort,
		keySource)
	log.Printf(
		"Relay limits: reservations=%d connectionsPerPeer=%d inboxPerPeer=%d groupInboxPerGroup=%d",
		limitsCfg.MaxRelayReservations,
		limitsCfg.MaxConnectionsPerPeer,
		limitsCfg.MaxInboxMessagesPerPeer,
		limitsCfg.MaxGroupInboxMessages,
	)
	log.Printf(
		"Storage config: root=%s media=%s profiles=%s",
		storageCfg.RootDir,
		storageCfg.MediaDir,
		storageCfg.ProfileDir,
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
	go logStatsPeriodically(ctx, h, inbox, groupInbox, store, media, profile, push)

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

func logStatsPeriodically(ctx context.Context, h host.Host, inbox *InboxStore, groupInbox *GroupInboxStore, rz *RendezvousStore, media *MediaStore, profile *ProfileStore, push *PushService) {
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

			// Business metrics (aggregate only, privacy-safe)
			biz.CheckAndResetPeriods()
			dau := biz.dailyHLL.Estimate()
			wau := biz.weeklyHLL.Estimate()
			mau := biz.monthlyHLL.Estimate()
			dailyMsgs := biz.messagesDailyCount.Load()
			dailyMedia := biz.mediaUploadsDailyCount.Load()
			estimatedDAU.Set(float64(dau))
			estimatedWAU.Set(float64(wau))
			estimatedMAU.Set(float64(mau))
			messagesDailyGauge.Set(float64(dailyMsgs))
			mediaUploadsDailyGauge.Set(float64(dailyMedia))

			platformCounts := push.PlatformCounts()
			for _, p := range []string{"ios", "android"} {
				pushTokensByPlatform.WithLabelValues(p).Set(float64(platformCounts[p]))
			}

			log.Printf("[STATS] conns=%d rz_ns=%d rz_peers=%d inbox_peers=%d inbox_msgs=%d push_tokens=%d media_blobs=%d media_disk_mb=%d profile_count=%d profile_disk_mb=%d group_inbox_groups=%d group_inbox_msgs=%d dau=%d wau=%d mau=%d daily_msgs=%d daily_media=%d heap_mb=%d goroutines=%d",
				conns, rzNs, rzPeers, inboxPeers, inboxMsgs, tokenCount,
				mediaBlobs, mediaDiskMB,
				pCount, pDiskMB,
				groupInboxGroups, groupInboxMsgs,
				dau, wau, mau, dailyMsgs, dailyMedia,
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
