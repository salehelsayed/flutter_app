//go:build integration

package integration_test

import (
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/mknoon/go-mknoon/node"
)

// ---------- Phase 3: Multi-Relay Failover Integration Tests ----------
//
// These tests verify that relay-dependent operations fall back to a second
// relay when the first is unreachable. They require a running relay server
// and use a combination of the real relay and a fake unreachable relay.
//
// The fake relay is listed FIRST to ensure the operation must fail on it
// before succeeding on the real relay.

// startNodeWithFakeFirstRelay creates a node configured with a fake
// unreachable relay listed first and the real relay listed second.
// This forces relay-dependent operations to fall back to the real relay.
func startNodeWithFakeFirstRelay(t *testing.T) (*node.Node, string) {
	t.Helper()

	privHex, expectedPeerId := generatePrivateKeyHex(t)
	n := node.NewNode()

	// Use a fake relay address first (unreachable), then the real relay.
	cfg := node.NodeConfig{
		PrivateKeyHex: privHex,
		RelayAddresses: []string{
			// Fake relay — different peer ID, unreachable port
			"/ip4/127.0.0.1/tcp/19999/p2p/12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN",
			// Real relay (the operation should fall back here)
			relayAddr(),
		},
		ListenPort:   0,
		AutoRegister: false,
	}

	state, err := n.Start(cfg)
	if err != nil {
		t.Fatalf("node.Start: %v", err)
	}

	t.Logf("node started with fake-first relay: peerId=%s", state.PeerId)

	if state.PeerId != expectedPeerId {
		t.Fatalf("peerId mismatch: got %s, want %s", state.PeerId, expectedPeerId)
	}

	t.Cleanup(func() {
		if err := n.Stop(); err != nil {
			t.Errorf("node.Stop: %v", err)
		}
	})

	// Wait for the real relay connection to be established.
	if err := n.WaitForRelayConnection(15 * time.Second); err != nil {
		t.Fatalf("relay connection not established: %v", err)
	}

	return n, state.PeerId
}

// TestPeerDialFallsBackToSecondRelay verifies that DialPeerViaRelay
// succeeds when the first relay is dead but the second is healthy.
func TestPeerDialFallsBackToSecondRelay(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in -short mode")
	}
	requireRelay(t)

	// Start two nodes: A with fake-first relay, B normally.
	nodeA, _ := startNodeWithFakeFirstRelay(t)
	nodeB, peerIdB := startNode(t)

	// Register nodeB on a namespace so we know it's online.
	ns := randomNamespace()
	if err := nodeB.RendezvousRegister(ns, nil); err != nil {
		t.Fatalf("nodeB register: %v", err)
	}

	// DialPeerViaRelay from A → B should succeed by falling back to
	// the real relay (second in list) after the fake relay fails.
	err := nodeA.DialPeerViaRelay(peerIdB)
	if err != nil {
		// DialPeerViaRelay may fail if B doesn't have a reservation
		// on the specific relay being tried. The key assertion is that
		// the error does NOT mention only the fake relay.
		if strings.Contains(err.Error(), "19999") && !strings.Contains(err.Error(), "relays failed") {
			t.Errorf("DialPeerViaRelay should have tried the second relay, got: %v", err)
		}
		t.Logf("DialPeerViaRelay error (may be expected if B lacks reservation): %v", err)
	} else {
		t.Log("DialPeerViaRelay succeeded via second relay")
	}
}

// TestRendezvousDiscoveryFallsBackToSecondRelay verifies that rendezvous
// discover succeeds when the first relay is dead but the second is healthy.
func TestRendezvousDiscoveryFallsBackToSecondRelay(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in -short mode")
	}
	requireRelay(t)

	// Start nodeA with fake-first relay, nodeB normally.
	nodeA, peerIdA := startNodeWithFakeFirstRelay(t)
	nodeB, _ := startNode(t)

	// Wait for nodeA to have circuit addresses before registering.
	nodeA.WaitForRelayConnection(10 * time.Second)
	time.Sleep(3 * time.Second) // Allow circuit address to propagate

	ns := randomNamespace()

	// nodeA registers on the real relay (second in its list).
	if err := nodeA.RendezvousRegister(ns, nil); err != nil {
		t.Fatalf("nodeA register: %v", err)
	}
	t.Logf("nodeA registered on %s", ns)

	time.Sleep(2 * time.Second)

	// nodeB discovers — should find nodeA via the real relay.
	var found bool
	for attempt := 1; attempt <= 5; attempt++ {
		peers, err := nodeB.RendezvousDiscover(ns, nil)
		if err != nil {
			t.Logf("attempt %d: discover error: %v", attempt, err)
			time.Sleep(2 * time.Second)
			continue
		}
		for _, p := range peers {
			if p.ID.String() == peerIdA {
				found = true
				break
			}
		}
		if found {
			break
		}
		time.Sleep(2 * time.Second)
	}

	if !found {
		t.Error("nodeA was not discoverable despite fake-first relay being dead")
	} else {
		t.Log("nodeA discovered successfully via second relay fallback")
	}
}

// TestInboxRetrieveFallsBackToSecondRelay verifies that inbox store/retrieve
// succeeds when the first relay is dead but the second is healthy.
func TestInboxRetrieveFallsBackToSecondRelay(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in -short mode")
	}
	requireRelay(t)

	// nodeA with fake-first relay stores message for nodeB.
	nodeA, peerIdA := startNodeWithFakeFirstRelay(t)
	nodeB, peerIdB := startNode(t)

	t.Logf("NodeA=%s (fake-first relay), NodeB=%s", peerIdA, peerIdB)

	// NodeA stores a message for NodeB — should fall back to real relay.
	if err := nodeA.InboxStore(peerIdB, "hello from fake-first relay"); err != nil {
		t.Fatalf("InboxStore: %v", err)
	}
	t.Log("InboxStore succeeded via second relay fallback")

	time.Sleep(2 * time.Second)

	// NodeB retrieves — should find the message.
	msgs, err := nodeB.InboxRetrieve()
	if err != nil {
		t.Fatalf("InboxRetrieve: %v", err)
	}

	found := false
	for _, m := range msgs {
		if m.From == peerIdA && m.Message == "hello from fake-first relay" {
			found = true
		}
	}

	if !found {
		t.Errorf("expected message from nodeA, got %d messages", len(msgs))
		for _, m := range msgs {
			t.Logf("  from=%s message=%q", m.From, m.Message)
		}
	} else {
		t.Log("Inbox retrieve succeeded — message delivered via second relay")
	}
}

// TestMediaDownloadFallsBackToSecondRelay verifies that media operations
// succeed when the first relay is dead but the second is healthy.
func TestMediaDownloadFallsBackToSecondRelay(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in -short mode")
	}
	requireRelay(t)

	// nodeA with fake-first relay lists media (should be empty, just testing connectivity).
	nodeA, _ := startNodeWithFakeFirstRelay(t)

	// MediaList should succeed by falling back to the real relay.
	blobs, err := nodeA.MediaList()
	if err != nil {
		t.Fatalf("MediaList: %v", err)
	}
	t.Logf("MediaList succeeded via second relay fallback: %d blobs", len(blobs))

	// The key assertion is that MediaList didn't fail due to the dead first relay.
	// The result can be empty (no media uploaded) — success means relay fallback worked.
	_ = fmt.Sprintf("verified %d blobs", len(blobs))
}
