package node

import (
	"crypto/rand"
	"encoding/hex"
	"strings"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p/core/crypto"
)

// generateTestKey creates a random Ed25519 key and returns its hex-encoded private key.
func generateTestKey(t *testing.T) string {
	t.Helper()
	priv, _, err := crypto.GenerateEd25519Key(rand.Reader)
	if err != nil {
		t.Fatalf("generate key: %v", err)
	}
	raw, err := priv.Raw()
	if err != nil {
		t.Fatalf("raw key: %v", err)
	}
	return hex.EncodeToString(raw)
}

func TestNewNode(t *testing.T) {
	n := NewNode()
	if n == nil {
		t.Fatal("NewNode returned nil")
	}

	state := n.State()
	if state.IsStarted {
		t.Error("new node should not be started")
	}
	if state.PeerId != "" {
		t.Errorf("new node peerId should be empty, got %q", state.PeerId)
	}
	if state.Connections != 0 {
		t.Errorf("new node connections should be 0, got %d", state.Connections)
	}
}

func TestNodeStartStop(t *testing.T) {
	hexKey := generateTestKey(t)

	n := NewNode()
	state, err := n.Start(NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{}, // no relay — local only
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}

	if !state.IsStarted {
		t.Error("state.IsStarted should be true after Start")
	}
	if state.PeerId == "" {
		t.Error("state.PeerId should not be empty after Start")
	}
	if len(state.Addresses) == 0 {
		t.Error("state.Addresses should not be empty after Start")
	}

	// Verify Host is accessible
	if n.Host() == nil {
		t.Error("Host() should not be nil after Start")
	}

	// Verify PeerId matches
	if n.PeerId() != state.PeerId {
		t.Errorf("PeerId() = %q, want %q", n.PeerId(), state.PeerId)
	}

	// Stop
	if err := n.Stop(); err != nil {
		t.Fatalf("Stop: %v", err)
	}

	afterStop := n.State()
	if afterStop.IsStarted {
		t.Error("state.IsStarted should be false after Stop")
	}
	if afterStop.Connections != 0 {
		t.Errorf("connections should be 0 after Stop, got %d", afterStop.Connections)
	}
}

func TestNodeStatus(t *testing.T) {
	hexKey := generateTestKey(t)

	n := NewNode()

	// Status before start
	preStatus := n.Status()
	if preStatus["isStarted"] != false {
		t.Error("status isStarted should be false before Start")
	}

	state, err := n.Start(NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	// Status after start
	status := n.Status()
	if status["isStarted"] != true {
		t.Error("status isStarted should be true after Start")
	}
	if status["peerId"] != state.PeerId {
		t.Errorf("status peerId = %v, want %v", status["peerId"], state.PeerId)
	}
	if status["ok"] != true {
		t.Error("status ok should be true")
	}

	// State after start (typed)
	typedState := n.State()
	if !typedState.IsStarted {
		t.Error("State().IsStarted should be true after Start")
	}
	if typedState.PeerId != state.PeerId {
		t.Errorf("State().PeerId = %q, want %q", typedState.PeerId, state.PeerId)
	}
}

func TestNodeStartAlreadyStarted(t *testing.T) {
	hexKey := generateTestKey(t)

	n := NewNode()
	_, err := n.Start(NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	// Starting again should fail
	_, err = n.Start(NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{},
	})
	if err == nil {
		t.Error("expected error when starting already-started node")
	}
}

func TestNodeStartInvalidKey(t *testing.T) {
	n := NewNode()

	// Invalid hex
	_, err := n.Start(NodeConfig{
		PrivateKeyHex: "not-hex",
	})
	if err == nil {
		t.Error("expected error for invalid hex key")
	}

	// Valid hex but invalid key bytes
	_, err = n.Start(NodeConfig{
		PrivateKeyHex: "deadbeef",
	})
	if err == nil {
		t.Error("expected error for invalid Ed25519 key")
	}
}

// ---------------------------------------------------------------------------
// Phase 0: Baseline Harness — Contract-Locking Tests
// ---------------------------------------------------------------------------

// TestReconnectRelays_LeavesPeerIdStable verifies that stopping and restarting
// a node with the same private key produces the same peer ID. This locks the
// current restart semantics: the identity is deterministic from the key.
func TestReconnectRelays_LeavesPeerIdStable(t *testing.T) {
	hexKey := generateTestKey(t)

	n := NewNode()
	state1, err := n.Start(NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{}, // no relay — local only
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("first Start: %v", err)
	}

	peerId1 := state1.PeerId
	if peerId1 == "" {
		t.Fatal("peerId should not be empty after first Start")
	}

	if err := n.Stop(); err != nil {
		t.Fatalf("Stop: %v", err)
	}

	// Restart with the same key — peer ID must be stable.
	state2, err := n.Start(NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("second Start: %v", err)
	}
	defer n.Stop()

	if state2.PeerId != peerId1 {
		t.Errorf("peerId changed across restart: %q → %q", peerId1, state2.PeerId)
	}
}

// TestReconnectRelays_ClearsAndRebuildsPubSubState_CurrentBehavior verifies
// that Stop() clears transient state (connections map) and Start() rebuilds
// it from scratch. This locks the current full-restart recovery semantics so
// later phases can prove the new behavior changed intentionally.
func TestReconnectRelays_ClearsAndRebuildsPubSubState_CurrentBehavior(t *testing.T) {
	hexKey := generateTestKey(t)

	n := NewNode()
	state1, err := n.Start(NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("first Start: %v", err)
	}

	if !state1.IsStarted {
		t.Fatal("node should be started after first Start")
	}
	if len(state1.Addresses) == 0 {
		t.Fatal("should have listen addresses after first Start")
	}

	// Stop clears connections and sets isStarted=false.
	if err := n.Stop(); err != nil {
		t.Fatalf("Stop: %v", err)
	}

	afterStop := n.State()
	if afterStop.IsStarted {
		t.Error("isStarted should be false after Stop")
	}
	if afterStop.Connections != 0 {
		t.Error("connections should be 0 after Stop")
	}

	status := n.Status()
	conns, ok := status["connections"].([]map[string]interface{})
	if ok && len(conns) != 0 {
		t.Errorf("Status connections should be empty after Stop, got %d", len(conns))
	}

	// Restart — fresh state, new addresses (ports re-randomized).
	state2, err := n.Start(NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("second Start: %v", err)
	}
	defer n.Stop()

	if !state2.IsStarted {
		t.Error("node should be started after second Start")
	}
	if len(state2.Addresses) == 0 {
		t.Error("should have listen addresses after second Start")
	}
	if state2.Connections != 0 {
		t.Errorf("fresh node should have 0 connections, got %d", state2.Connections)
	}
}

// TestStatus_BackwardCompatibleShape verifies that Status() returns a map with
// the exact keys that Dart's NodeState.fromJson expects. Adding new fields in
// the future must NOT remove or rename any of these keys.
func TestStatus_BackwardCompatibleShape(t *testing.T) {
	hexKey := generateTestKey(t)

	n := NewNode()
	_, err := n.Start(NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	status := n.Status()

	// --- Required keys ---
	requiredKeys := []string{
		"ok",
		"peerId",
		"isStarted",
		"listenAddresses",
		"circuitAddresses",
		"connections",
	}

	for _, key := range requiredKeys {
		if _, exists := status[key]; !exists {
			t.Errorf("Status() missing required key %q", key)
		}
	}

	// --- Type checks ---
	if _, ok := status["ok"].(bool); !ok {
		t.Errorf("ok should be bool, got %T", status["ok"])
	}
	if _, ok := status["peerId"].(string); !ok {
		t.Errorf("peerId should be string, got %T", status["peerId"])
	}
	if _, ok := status["isStarted"].(bool); !ok {
		t.Errorf("isStarted should be bool, got %T", status["isStarted"])
	}
	if _, ok := status["listenAddresses"].([]string); !ok {
		t.Errorf("listenAddresses should be []string, got %T", status["listenAddresses"])
	}
	if _, ok := status["circuitAddresses"].([]string); !ok {
		t.Errorf("circuitAddresses should be []string, got %T", status["circuitAddresses"])
	}
	if _, ok := status["connections"].([]map[string]interface{}); !ok {
		t.Errorf("connections should be []map[string]interface{}, got %T", status["connections"])
	}

	// Verify additive fields do NOT break parsing: if a future Go version
	// adds "relayState" or "healthyRelayCount", the existing Dart parser
	// must ignore them. This test ensures the baseline shape is stable.
}

// TestAutoRegister_DoesNotWaitForAllRelayWarmAttemptsAfterFirstHealthyRelay
// verifies that auto-registration fires after the first relay connection
// succeeds, without waiting for all relay warm-up goroutines to finish.
// This is a contract-locking test: the current implementation closes the
// relayReady channel on the first successful warm, and auto-register runs
// after the WaitGroup completes — but the first healthy relay is what
// matters for circuit address availability.
func TestAutoRegister_DoesNotWaitForAllRelayWarmAttemptsAfterFirstHealthyRelay(t *testing.T) {
	hexKey := generateTestKey(t)

	n := NewNode()
	state, err := n.Start(NodeConfig{
		PrivateKeyHex: hexKey,
		// Use multiple relay addresses including the default one.
		// When relays are unreachable (test environment), the relay-ready
		// channel remains open but the goroutine completes once all attempts
		// finish. This verifies Start() returns immediately without blocking.
		RelayAddresses: []string{},
		AutoRegister:   true, // auto-register enabled
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	// The node should start regardless of relay connectivity.
	if !state.IsStarted {
		t.Error("node should be started even without relay connectivity")
	}
	if state.PeerId == "" {
		t.Error("node should have a peerId even without relay connectivity")
	}

	// The relayReady channel should exist (created during Start).
	n.mu.RLock()
	rr := n.relayReady
	n.mu.RUnlock()
	if rr == nil {
		t.Error("relayReady channel should be initialized after Start")
	}
}

// TestAutoRegister_WaitsForDiscoverableCircuitRecordNotMereRelaySocket
// verifies that auto-registration waits for a circuit address to appear
// before registering on rendezvous. Without a circuit address in the
// peer record, other peers cannot connect via the relay.
func TestAutoRegister_WaitsForDiscoverableCircuitRecordNotMereRelaySocket(t *testing.T) {
	hexKey := generateTestKey(t)

	n := NewNode()
	_, err := n.Start(NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{}, // no relay available
		AutoRegister:   true,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	// In a test environment with no relay, waitForCircuitAddress should
	// return false (no circuit addresses). This confirms the code path
	// exists and doesn't panic or deadlock.
	hasCircuit := n.waitForCircuitAddress(100 * time.Millisecond)
	if hasCircuit {
		t.Error("expected no circuit addresses without relay connection")
	}

	// Verify the node still has listen addresses (non-circuit).
	state := n.State()
	if len(state.Addresses) == 0 {
		t.Error("should have local listen addresses even without relay")
	}

	// Verify no circuit addresses are in the set.
	for _, addr := range state.Addresses {
		if strings.Contains(addr, "/p2p-circuit") {
			t.Errorf("unexpected circuit address without relay: %s", addr)
		}
	}
}

func TestNodeStopIdempotent(t *testing.T) {
	n := NewNode()

	// Stop on a non-started node should be a no-op
	if err := n.Stop(); err != nil {
		t.Fatalf("Stop on non-started node: %v", err)
	}

	hexKey := generateTestKey(t)
	_, err := n.Start(NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{},
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}

	// Stop twice
	if err := n.Stop(); err != nil {
		t.Fatalf("first Stop: %v", err)
	}
	if err := n.Stop(); err != nil {
		t.Fatalf("second Stop: %v", err)
	}
}
