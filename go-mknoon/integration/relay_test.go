//go:build integration

package integration_test

import (
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"math/rand"
	"net"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/mknoon/go-mknoon/identity"
	"github.com/mknoon/go-mknoon/node"
	ma "github.com/multiformats/go-multiaddr"
)

// ---------- helpers ----------

// requireRelay skips the test when SKIP_RELAY_TESTS is set or the relay
// is known to be unreachable.
func requireRelay(t *testing.T) {
	t.Helper()
	if os.Getenv("SKIP_RELAY_TESTS") != "" {
		t.Skip("SKIP_RELAY_TESTS set — skipping relay integration test")
	}

	// Probe the relay host to skip early if unreachable.
	addr := relayAddr()
	maddr, err := ma.NewMultiaddr(addr)
	if err != nil {
		t.Skipf("cannot parse relay multiaddr %q: %v", addr, err)
	}
	host, _ := maddr.ValueForProtocol(ma.P_DNS4)
	if host == "" {
		host, _ = maddr.ValueForProtocol(ma.P_IP4)
	}
	// Try TCP first (more reliable for reachability check).
	tcpPort, _ := maddr.ValueForProtocol(ma.P_TCP)
	if tcpPort != "" {
		conn, err := net.DialTimeout("tcp", net.JoinHostPort(host, tcpPort), 5*time.Second)
		if err != nil {
			t.Skipf("relay unreachable at %s:%s (tcp): %v", host, tcpPort, err)
		}
		conn.Close()
		return
	}
	// Fallback to UDP probe.
	udpPort, _ := maddr.ValueForProtocol(ma.P_UDP)
	if udpPort != "" {
		conn, err := net.DialTimeout("udp", net.JoinHostPort(host, udpPort), 5*time.Second)
		if err != nil {
			t.Skipf("relay unreachable at %s:%s (udp): %v", host, udpPort, err)
		}
		conn.Close()
	}
}

// relayAddr returns the relay multiaddr to use (env override or default).
func relayAddr() string {
	return node.RelayAddress()
}

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
		RelayAddresses: []string{relayAddr()},
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

	// Wait for the relay connection to be established (replaces blind sleep).
	if err := n.WaitForRelayConnection(15 * time.Second); err != nil {
		t.Fatalf("relay connection not established: %v", err)
	}

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
	requireRelay(t)

	privHex, expectedPeerId := generatePrivateKeyHex(t)
	n := node.NewNode()

	cfg := node.NodeConfig{
		PrivateKeyHex:  privHex,
		RelayAddresses: []string{relayAddr()},
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

	// Wait for relay connection to complete.
	if err := n.WaitForRelayConnection(15 * time.Second); err != nil {
		t.Fatalf("relay connection not established: %v", err)
	}

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
	requireRelay(t)

	n, peerId := startNode(t)
	ns := randomNamespace()
	t.Logf("registering peerId=%s on namespace=%s", peerId, ns)

	err := n.RendezvousRegister(ns, nil)
	if err != nil {
		t.Fatalf("RendezvousRegister failed: %v", err)
	}

	t.Logf("register succeeded for ns=%s", ns)
}

func TestRelayRendezvousDiscoverPeer(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in -short mode")
	}
	requireRelay(t)

	// Use two nodes: A registers, B discovers A.
	// (Many rendezvous servers filter the requester from results,
	// so self-discovery is unreliable.)
	nodeA, peerIdA := startNode(t)
	nodeB, _ := startNode(t)

	ns := randomNamespace()
	t.Logf("nodeA=%s namespace=%s", peerIdA, ns)

	// Node A registers on the namespace.
	if err := nodeA.RendezvousRegister(ns, nil); err != nil {
		t.Fatalf("RendezvousRegister: %v", err)
	}
	t.Log("nodeA register succeeded")

	// Node B discovers — retry up to 5 times with increasing delay
	// to handle propagation latency on the relay server.
	var found bool
	for attempt := 1; attempt <= 5; attempt++ {
		delay := time.Duration(attempt) * 2 * time.Second
		t.Logf("attempt %d: waiting %v for propagation...", attempt, delay)
		time.Sleep(delay)

		peers, err := nodeB.RendezvousDiscover(ns, nil)
		if err != nil {
			t.Logf("attempt %d: RendezvousDiscover error: %v", attempt, err)
			continue
		}

		t.Logf("attempt %d: discovered %d peers", attempt, len(peers))
		for i, p := range peers {
			t.Logf("  peer[%d]: %s addrs=%v", i, p.ID.String(), p.Addrs)
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
	}

	if !found {
		t.Errorf("nodeA peerId %s not found in discover results after 5 attempts", peerIdA)
	}
}

func TestRelayNodeStatus(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in -short mode")
	}
	requireRelay(t)

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
	requireRelay(t)

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
	relay := relayAddr()
	if err := nodeA.DialPeer(peerIdB, peerBAddrs); err != nil {
		// If direct dial fails, try relay circuit address.
		relayCircuitAddr := fmt.Sprintf("%s/p2p-circuit/p2p/%s", relay, peerIdB)
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

// ---------- Inbox integration tests ----------

func TestRelayInboxStoreRetrieve(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in -short mode")
	}
	requireRelay(t)

	nodeA, peerIdA := startNode(t)
	nodeB, peerIdB := startNode(t)

	t.Logf("NodeA=%s  NodeB=%s", peerIdA, peerIdB)

	// NodeA stores a message for NodeB in the relay inbox.
	if err := nodeA.InboxStore(peerIdB, "hello from A"); err != nil {
		t.Fatalf("InboxStore: %v", err)
	}
	t.Log("InboxStore succeeded")

	// Wait for the relay to persist the message.
	time.Sleep(2 * time.Second)

	// NodeB retrieves pending messages.
	msgs, err := nodeB.InboxRetrieve()
	if err != nil {
		t.Fatalf("InboxRetrieve: %v", err)
	}

	if len(msgs) == 0 {
		t.Fatal("expected at least 1 inbox message, got 0")
	}

	t.Logf("retrieved %d messages", len(msgs))
	found := false
	for _, m := range msgs {
		t.Logf("  from=%s message=%q ts=%d", m.From, m.Message, m.Timestamp)
		if m.From == peerIdA && m.Message == "hello from A" {
			found = true
		}
	}
	if !found {
		t.Error("expected message from NodeA with content 'hello from A'")
	}

	// Second retrieve should return no messages (cleared after first retrieve).
	msgs2, err := nodeB.InboxRetrieve()
	if err != nil {
		t.Fatalf("InboxRetrieve (second): %v", err)
	}
	if len(msgs2) != 0 {
		t.Errorf("expected 0 messages on second retrieve, got %d", len(msgs2))
	}
}

func TestRelayInboxRegisterToken(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in -short mode")
	}
	requireRelay(t)

	nodeA, _ := startNode(t)

	// Register a push token.
	if err := nodeA.InboxRegisterToken("fake-fcm-token-123", "ios"); err != nil {
		t.Fatalf("InboxRegisterToken: %v", err)
	}
	t.Log("first token registration succeeded")

	// Update with a different token — should also succeed.
	if err := nodeA.InboxRegisterToken("updated-token-456", "android"); err != nil {
		t.Fatalf("InboxRegisterToken (update): %v", err)
	}
	t.Log("token update succeeded")
}

func TestRelayInboxMultipleMessages(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in -short mode")
	}
	requireRelay(t)

	nodeA, peerIdA := startNode(t)
	nodeB, peerIdB := startNode(t)

	t.Logf("NodeA=%s  NodeB=%s", peerIdA, peerIdB)

	// NodeA stores 3 messages for NodeB.
	for i := 1; i <= 3; i++ {
		msg := fmt.Sprintf("message %d from A", i)
		if err := nodeA.InboxStore(peerIdB, msg); err != nil {
			t.Fatalf("InboxStore msg %d: %v", i, err)
		}
		t.Logf("stored message %d", i)
	}

	// Wait for relay to persist all messages.
	time.Sleep(2 * time.Second)

	// NodeB retrieves — expect all 3.
	msgs, err := nodeB.InboxRetrieve()
	if err != nil {
		t.Fatalf("InboxRetrieve: %v", err)
	}

	if len(msgs) != 3 {
		t.Fatalf("expected 3 messages, got %d", len(msgs))
	}

	for i, m := range msgs {
		expected := fmt.Sprintf("message %d from A", i+1)
		t.Logf("  msg[%d]: from=%s message=%q", i, m.From, m.Message)
		if m.Message != expected {
			t.Errorf("msg[%d]: got %q, want %q", i, m.Message, expected)
		}
		if m.From != peerIdA {
			t.Errorf("msg[%d]: from=%s, want %s", i, m.From, peerIdA)
		}
	}
}
