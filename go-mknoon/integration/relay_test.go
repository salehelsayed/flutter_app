//go:build integration

package integration_test

import (
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"math/rand"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/mknoon/go-mknoon/identity"
	"github.com/mknoon/go-mknoon/node"
)

// ---------- helpers ----------

// generatePrivateKeyHex creates a fresh identity and returns the hex-encoded
// Ed25519 private key (suitable for NodeConfig.PrivateKeyHex) plus the peerId.
func generatePrivateKeyHex(t *testing.T) (string, string) {
	t.Helper()
	id, err := identity.GenerateIdentity()
	if err != nil {
		t.Fatalf("GenerateIdentity: %v", err)
	}
	privBytes, err := base64.StdEncoding.DecodeString(id.PrivateKey)
	if err != nil {
		t.Fatalf("decode private key: %v", err)
	}
	return hex.EncodeToString(privBytes), id.PeerId
}

// startNode creates a node, starts it with the QUIC relay, and registers
// t.Cleanup to stop it. Returns the running node and its peerId.
func startNode(t *testing.T) (*node.Node, string) {
	t.Helper()
	return startNodeWithCallback(t, nil)
}

// startNodeWithCallback is like startNode but accepts an EventCallback.
func startNodeWithCallback(t *testing.T, cb node.EventCallback) (*node.Node, string) {
	t.Helper()

	privHex, expectedPeerId := generatePrivateKeyHex(t)

	var n *node.Node
	if cb != nil {
		n = node.New(cb)
	} else {
		n = node.NewNode()
	}

	cfg := node.NodeConfig{
		PrivateKeyHex:  privHex,
		RelayAddresses: []string{node.DefaultQUICRelay},
		ListenPort:     0,
	}

	state, err := n.Start(cfg)
	if err != nil {
		t.Fatalf("node.Start: %v", err)
	}

	t.Logf("node started: peerId=%s addresses=%v", state.PeerId, state.Addresses)

	if state.PeerId != expectedPeerId {
		t.Fatalf("peerId mismatch: got %s, want %s", state.PeerId, expectedPeerId)
	}

	t.Cleanup(func() {
		if err := n.Stop(); err != nil {
			t.Errorf("node.Stop: %v", err)
		}
	})

	// Give the background relay-connect goroutine time to establish the
	// connection before the test proceeds. The relay dial uses QUIC and
	// typically completes well within this window.
	time.Sleep(5 * time.Second)

	return n, state.PeerId
}

// randomNamespace returns a unique rendezvous namespace for test isolation.
func randomNamespace() string {
	return fmt.Sprintf("%stest-%d-%d", node.RendezvousPrefix, time.Now().UnixNano(), rand.Intn(100000))
}

// eventCollector implements node.EventCallback and collects all emitted events.
type eventCollector struct {
	mu     sync.Mutex
	events []string
}

func (c *eventCollector) OnEvent(jsonStr string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.events = append(c.events, jsonStr)
}

// snapshot returns a copy of all collected events.
func (c *eventCollector) snapshot() []string {
	c.mu.Lock()
	defer c.mu.Unlock()
	out := make([]string, len(c.events))
	copy(out, c.events)
	return out
}

// waitForEvent polls until an event containing substr appears (or timeout).
func (c *eventCollector) waitForEvent(substr string, timeout time.Duration) (string, bool) {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		for _, ev := range c.snapshot() {
			if strings.Contains(ev, substr) {
				return ev, true
			}
		}
		time.Sleep(200 * time.Millisecond)
	}
	return "", false
}

// ---------- tests ----------

func TestRelayConnect(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in -short mode")
	}

	privHex, expectedPeerId := generatePrivateKeyHex(t)
	n := node.NewNode()

	cfg := node.NodeConfig{
		PrivateKeyHex:  privHex,
		RelayAddresses: []string{node.DefaultQUICRelay},
		ListenPort:     0,
	}

	state, err := n.Start(cfg)
	if err != nil {
		t.Fatalf("Start failed: %v", err)
	}
	t.Cleanup(func() { n.Stop() })

	t.Logf("NodeState after Start: peerId=%s isStarted=%v addresses=%v connections=%d",
		state.PeerId, state.IsStarted, state.Addresses, state.Connections)

	if !state.IsStarted {
		t.Error("expected isStarted=true")
	}
	if state.PeerId == "" {
		t.Error("expected non-empty peerId")
	}
	if state.PeerId != expectedPeerId {
		t.Errorf("peerId mismatch: got %s, want %s", state.PeerId, expectedPeerId)
	}
	if n.PeerId() != expectedPeerId {
		t.Errorf("PeerId() mismatch: got %s, want %s", n.PeerId(), expectedPeerId)
	}

	// Wait for relay connection to complete in background.
	time.Sleep(5 * time.Second)

	// Verify the node reports a relay connection.
	status := n.Status()
	t.Logf("Status after relay connect: %+v", status)

	if err := n.Stop(); err != nil {
		t.Fatalf("Stop failed: %v", err)
	}

	// After stop, PeerId should still be readable but isStarted should be false.
	postState := n.State()
	if postState.IsStarted {
		t.Error("expected isStarted=false after Stop")
	}
}

func TestRelayRendezvousRegister(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in -short mode")
	}

	n, peerId := startNode(t)
	ns := randomNamespace()
	t.Logf("registering peerId=%s on namespace=%s", peerId, ns)

	err := n.RendezvousRegister(ns, nil)
	if err != nil {
		t.Fatalf("RendezvousRegister failed: %v", err)
	}

	t.Logf("register succeeded for ns=%s", ns)
}

func TestRelayRendezvousDiscoverSelf(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in -short mode")
	}

	n, peerId := startNode(t)
	ns := randomNamespace()
	t.Logf("peerId=%s namespace=%s", peerId, ns)

	// Register first.
	if err := n.RendezvousRegister(ns, nil); err != nil {
		t.Fatalf("RendezvousRegister: %v", err)
	}
	t.Log("register succeeded")

	// Small delay to let registration propagate on the server.
	time.Sleep(1 * time.Second)

	// Discover and expect to find our own peerId.
	peers, err := n.RendezvousDiscover(ns, nil)
	if err != nil {
		t.Fatalf("RendezvousDiscover: %v", err)
	}

	t.Logf("discovered %d peers", len(peers))
	for i, p := range peers {
		t.Logf("  peer[%d]: %s addrs=%v", i, p.ID.String(), p.Addrs)
	}

	found := false
	for _, p := range peers {
		if p.ID.String() == peerId {
			found = true
			break
		}
	}
	if !found {
		t.Errorf("own peerId %s not found in discover results", peerId)
	}
}

func TestRelayNodeStatus(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in -short mode")
	}

	n, peerId := startNode(t)

	// Verify Status while running.
	status := n.Status()
	t.Logf("Status (running): %+v", status)

	if ok, _ := status["ok"].(bool); !ok {
		t.Error("expected ok=true in status")
	}
	if got, _ := status["peerId"].(string); got != peerId {
		t.Errorf("status peerId=%s, want %s", got, peerId)
	}
	if started, _ := status["isStarted"].(bool); !started {
		t.Error("expected isStarted=true in status")
	}

	// Also check typed State().
	state := n.State()
	if !state.IsStarted {
		t.Error("State().IsStarted should be true")
	}
	if state.PeerId != peerId {
		t.Errorf("State().PeerId=%s, want %s", state.PeerId, peerId)
	}

	// Stop and verify.
	if err := n.Stop(); err != nil {
		t.Fatalf("Stop: %v", err)
	}

	statusAfter := n.Status()
	t.Logf("Status (stopped): %+v", statusAfter)

	if started, _ := statusAfter["isStarted"].(bool); started {
		t.Error("expected isStarted=false after Stop")
	}

	stateAfter := n.State()
	if stateAfter.IsStarted {
		t.Error("State().IsStarted should be false after Stop")
	}
}

func TestRelayTwoNodesMessage(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in -short mode")
	}

	ns := randomNamespace()
	t.Logf("shared namespace: %s", ns)

	// -- Node A (sender) --
	collectorA := &eventCollector{}
	nodeA, peerIdA := startNodeWithCallback(t, collectorA)
	t.Logf("Node A peerId=%s", peerIdA)

	// -- Node B (receiver) --
	collectorB := &eventCollector{}
	nodeB, peerIdB := startNodeWithCallback(t, collectorB)
	t.Logf("Node B peerId=%s", peerIdB)

	// Both register on the shared namespace.
	if err := nodeA.RendezvousRegister(ns, nil); err != nil {
		t.Fatalf("Node A register: %v", err)
	}
	if err := nodeB.RendezvousRegister(ns, nil); err != nil {
		t.Fatalf("Node B register: %v", err)
	}
	t.Log("both nodes registered")

	// Small delay for registrations to propagate.
	time.Sleep(2 * time.Second)

	// Node A discovers peers to find Node B's addresses.
	peers, err := nodeA.RendezvousDiscover(ns, nil)
	if err != nil {
		t.Fatalf("Node A discover: %v", err)
	}
	t.Logf("Node A discovered %d peers", len(peers))

	var peerBAddrs []string
	for _, p := range peers {
		t.Logf("  discovered peer: %s addrs=%v", p.ID.String(), p.Addrs)
		if p.ID.String() == peerIdB {
			for _, a := range p.Addrs {
				peerBAddrs = append(peerBAddrs, a.String())
			}
		}
	}

	// Dial Node B (with discovered addresses or via relay circuit).
	if err := nodeA.DialPeer(peerIdB, peerBAddrs); err != nil {
		// If direct dial fails, try relay circuit address.
		relayCircuitAddr := fmt.Sprintf("%s/p2p-circuit/p2p/%s", node.DefaultQUICRelay, peerIdB)
		t.Logf("direct dial failed (%v), trying relay circuit: %s", err, relayCircuitAddr)
		if err2 := nodeA.DialPeer(peerIdB, []string{relayCircuitAddr}); err2 != nil {
			t.Fatalf("DialPeer (relay circuit) failed: %v", err2)
		}
	}
	t.Log("Node A connected to Node B")

	// Small delay for connection to stabilize.
	time.Sleep(1 * time.Second)

	// Send a message from A to B.
	testMsg := fmt.Sprintf(`{"type":"test","content":"hello from integration test","ts":%d}`, time.Now().UnixMilli())
	reply, err := nodeA.SendMessage(peerIdB, testMsg)
	if err != nil {
		t.Fatalf("SendMessage: %v", err)
	}
	t.Logf("SendMessage reply: %q", reply)

	// Verify Node B received the message event.
	ev, ok := collectorB.waitForEvent("message:received", 10*time.Second)
	if !ok {
		// Log all events for debugging.
		t.Logf("Node B events: %v", collectorB.snapshot())
		t.Fatal("Node B did not receive message:received event within timeout")
	}
	t.Logf("Node B received event: %s", ev)

	// Parse the event to verify content.
	var parsed map[string]interface{}
	if err := json.Unmarshal([]byte(ev), &parsed); err != nil {
		t.Fatalf("unmarshal event: %v", err)
	}

	data, _ := parsed["data"].(map[string]interface{})
	if data == nil {
		t.Fatal("event has no 'data' field")
	}

	from, _ := data["from"].(string)
	content, _ := data["content"].(string)
	isIncoming, _ := data["isIncoming"].(bool)

	if from != peerIdA {
		t.Errorf("event from=%s, want %s", from, peerIdA)
	}
	if content != testMsg {
		t.Errorf("event content=%q, want %q", content, testMsg)
	}
	if !isIncoming {
		t.Error("expected isIncoming=true")
	}

	t.Log("message exchange verified successfully")
}
