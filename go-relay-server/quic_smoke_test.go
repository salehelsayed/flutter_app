package main

import (
	"context"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/p2p/protocol/circuitv2/client"
	ma "github.com/multiformats/go-multiaddr"
)

const (
	// Must match the relay server's peer ID (derived from privateKeyRaw).
	expectedPeerID = "12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g"

	// Live relay addresses.
	quicRelayAddr = "/dns4/mknoun.xyz/udp/4002/quic-v1"
	wssRelayAddr  = "/dns4/mknoun.xyz/tcp/4001/wss"
	tcpRelayAddr  = "/ip4/13.60.15.36/tcp/4005"
)

// TestQUICSmokeIdentify dials the live relay server over QUIC and verifies
// that the libp2p identify handshake completes within 10 seconds.
//
// Run:  go test -run TestQUICSmokeIdentify -v -count=1
// Skip: set SKIP_LIVE_TESTS=1 to skip when no network is available.
func TestQUICSmokeIdentify(t *testing.T) {
	skipIfNoNetwork(t)

	relayMA := ma.StringCast(fmt.Sprintf("%s/p2p/%s", quicRelayAddr, expectedPeerID))

	// Create a minimal libp2p host with QUIC transport (enabled by default).
	h, err := libp2p.New(
		libp2p.NoListenAddrs,
		libp2p.EnableRelay(),
	)
	if err != nil {
		t.Fatalf("Failed to create libp2p host: %v", err)
	}
	defer h.Close()

	// Extract the peer.AddrInfo from the multiaddr.
	ai, err := peer.AddrInfoFromP2pAddr(relayMA)
	if err != nil {
		t.Fatalf("Failed to parse relay address: %v", err)
	}

	// Dial with a 10-second timeout.
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	t.Logf("Dialing relay via QUIC: %s", relayMA)
	start := time.Now()

	if err := h.Connect(ctx, *ai); err != nil {
		t.Fatalf("QUIC identify handshake failed: %v (elapsed: %s)", err, time.Since(start))
	}

	elapsed := time.Since(start)
	t.Logf("QUIC identify handshake completed in %s", elapsed)

	// Verify the remote peer ID matches expectations.
	conns := h.Network().ConnsToPeer(ai.ID)
	if len(conns) == 0 {
		t.Fatal("Connected but no active connections found")
	}

	for _, conn := range conns {
		t.Logf("  Connection: %s → %s (transport: %s)",
			conn.LocalMultiaddr(), conn.RemoteMultiaddr(),
			conn.RemoteMultiaddr().Protocols()[0].Name)
	}

	// Verify peer ID.
	if ai.ID.String() != expectedPeerID {
		t.Fatalf("Peer ID mismatch: got %s, want %s", ai.ID, expectedPeerID)
	}
	t.Logf("Peer ID verified: %s", ai.ID)
}

// TestWSSSmokeIdentify dials the relay over WSS for comparison.
// If QUIC fails but WSS succeeds, the issue is QUIC-specific.
func TestWSSSmokeIdentify(t *testing.T) {
	skipIfNoNetwork(t)

	relayMA := ma.StringCast(fmt.Sprintf("%s/p2p/%s", wssRelayAddr, expectedPeerID))

	h, err := libp2p.New(
		libp2p.NoListenAddrs,
		libp2p.EnableRelay(),
	)
	if err != nil {
		t.Fatalf("Failed to create libp2p host: %v", err)
	}
	defer h.Close()

	ai, err := peer.AddrInfoFromP2pAddr(relayMA)
	if err != nil {
		t.Fatalf("Failed to parse relay address: %v", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	t.Logf("Dialing relay via WSS: %s", relayMA)
	start := time.Now()

	if err := h.Connect(ctx, *ai); err != nil {
		t.Fatalf("WSS identify handshake failed: %v (elapsed: %s)", err, time.Since(start))
	}

	t.Logf("WSS identify handshake completed in %s", time.Since(start))
}

// TestTCPSmokeIdentify dials the relay over plain TCP for comparison.
func TestTCPSmokeIdentify(t *testing.T) {
	skipIfNoNetwork(t)

	relayMA := ma.StringCast(fmt.Sprintf("%s/p2p/%s", tcpRelayAddr, expectedPeerID))

	h, err := libp2p.New(
		libp2p.NoListenAddrs,
		libp2p.EnableRelay(),
	)
	if err != nil {
		t.Fatalf("Failed to create libp2p host: %v", err)
	}
	defer h.Close()

	ai, err := peer.AddrInfoFromP2pAddr(relayMA)
	if err != nil {
		t.Fatalf("Failed to parse relay address: %v", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	t.Logf("Dialing relay via TCP: %s", relayMA)
	start := time.Now()

	if err := h.Connect(ctx, *ai); err != nil {
		t.Fatalf("TCP identify handshake failed: %v (elapsed: %s)", err, time.Since(start))
	}

	t.Logf("TCP identify handshake completed in %s", time.Since(start))
}

// TestQUICSmokeRelayReservation dials via QUIC and makes a relay reservation.
// This is the full path a mobile client takes: connect → identify → reserve.
func TestQUICSmokeRelayReservation(t *testing.T) {
	skipIfNoNetwork(t)

	relayMA := ma.StringCast(fmt.Sprintf("%s/p2p/%s", quicRelayAddr, expectedPeerID))

	h, err := libp2p.New(
		libp2p.NoListenAddrs,
		libp2p.EnableRelay(),
	)
	if err != nil {
		t.Fatalf("Failed to create libp2p host: %v", err)
	}
	defer h.Close()

	ai, err := peer.AddrInfoFromP2pAddr(relayMA)
	if err != nil {
		t.Fatalf("Failed to parse relay address: %v", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	// Step 1: Connect (identify handshake).
	t.Log("Step 1: Connecting via QUIC...")
	start := time.Now()
	if err := h.Connect(ctx, *ai); err != nil {
		t.Fatalf("QUIC connect failed: %v (elapsed: %s)", err, time.Since(start))
	}
	t.Logf("  Connected in %s", time.Since(start))

	// Step 2: Request relay reservation.
	t.Log("Step 2: Requesting relay reservation...")
	resStart := time.Now()
	reservation, err := client.Reserve(ctx, h, *ai)
	if err != nil {
		t.Fatalf("Relay reservation failed: %v (elapsed: %s)", err, time.Since(resStart))
	}
	t.Logf("  Reservation obtained in %s", time.Since(resStart))
	t.Logf("  Reservation expiry: %s", reservation.Expiration)
	t.Logf("  Relay addrs: %v", reservation.Addrs)
}

// TestAllTransportsSmokeCompare dials the relay over all three transports
// and compares handshake times. Useful for diagnosing transport-specific issues.
func TestAllTransportsSmokeCompare(t *testing.T) {
	skipIfNoNetwork(t)

	transports := []struct {
		name string
		addr string
	}{
		{"TCP", tcpRelayAddr},
		{"WSS", wssRelayAddr},
		{"QUIC", quicRelayAddr},
	}

	results := make(map[string]string)

	for _, tr := range transports {
		t.Run(tr.name, func(t *testing.T) {
			relayMA := ma.StringCast(fmt.Sprintf("%s/p2p/%s", tr.addr, expectedPeerID))

			h, err := libp2p.New(
				libp2p.NoListenAddrs,
				libp2p.EnableRelay(),
			)
			if err != nil {
				t.Fatalf("Failed to create host: %v", err)
			}
			defer h.Close()

			ai, err := peer.AddrInfoFromP2pAddr(relayMA)
			if err != nil {
				t.Fatalf("Failed to parse address: %v", err)
			}

			ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
			defer cancel()

			start := time.Now()
			err = h.Connect(ctx, *ai)
			elapsed := time.Since(start)

			if err != nil {
				results[tr.name] = fmt.Sprintf("FAILED (%s): %v", elapsed, err)
				t.Errorf("%s failed: %v (elapsed: %s)", tr.name, err, elapsed)
			} else {
				results[tr.name] = fmt.Sprintf("OK (%s)", elapsed)
				t.Logf("%s handshake: %s", tr.name, elapsed)
			}
		})
	}

	t.Log("\n--- Transport Comparison ---")
	for name, result := range results {
		t.Logf("  %s: %s", name, result)
	}
}

func skipIfNoNetwork(t *testing.T) {
	t.Helper()
	if os.Getenv("SKIP_LIVE_TESTS") == "1" {
		t.Skip("Skipping live network test (SKIP_LIVE_TESTS=1)")
	}
}
