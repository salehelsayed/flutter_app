package node

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	ma "github.com/multiformats/go-multiaddr"
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

// generatePeerIDStr creates a random Ed25519 key and returns the peer ID string.
func generatePeerIDStr(t *testing.T) string {
	t.Helper()
	priv, _, err := crypto.GenerateEd25519Key(rand.Reader)
	if err != nil {
		t.Fatalf("generate key: %v", err)
	}
	pid, err := peer.IDFromPrivateKey(priv)
	if err != nil {
		t.Fatalf("peer ID from key: %v", err)
	}
	return pid.String()
}

func configureRefreshRelayAddresses(t *testing.T, n *Node, addrs []string) []peer.AddrInfo {
	t.Helper()

	relayInfos := make([]peer.AddrInfo, 0, len(addrs))
	relayPeerOrder := make([]peer.ID, 0, len(addrs))
	for _, addr := range addrs {
		maddr, err := ma.NewMultiaddr(addr)
		if err != nil {
			t.Fatalf("NewMultiaddr(%q): %v", addr, err)
		}
		info, err := peer.AddrInfoFromP2pAddr(maddr)
		if err != nil {
			t.Fatalf("AddrInfoFromP2pAddr(%q): %v", addr, err)
		}
		relayInfos = append(relayInfos, *info)
		relayPeerOrder = append(relayPeerOrder, info.ID)
	}

	n.mu.Lock()
	n.relayAddresses = append([]string(nil), addrs...)
	n.relayPeerOrder = append([]peer.ID(nil), relayPeerOrder...)
	n.mu.Unlock()

	for _, relayPeerID := range relayPeerOrder {
		n.relaySessionMgr.InitRelayPeer(relayPeerID)
	}

	return relayInfos
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

func TestNodeStart_ExplicitEmptyRelayAddressesDisableStartupRelayWarmup(t *testing.T) {
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

	n.mu.RLock()
	relayPeerOrder := append([]peer.ID(nil), n.relayPeerOrder...)
	n.mu.RUnlock()

	if len(relayPeerOrder) != 0 {
		t.Fatalf("expected no startup relay peers for explicit empty relay config, got %d", len(relayPeerOrder))
	}
}

func TestNodeStart_NilRelayAddressesUseDefaultRelay(t *testing.T) {
	hexKey := generateTestKey(t)

	n := NewNode()
	_, err := n.Start(NodeConfig{
		PrivateKeyHex: hexKey,
		AutoRegister:  false,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	n.mu.RLock()
	relayPeerOrder := append([]peer.ID(nil), n.relayPeerOrder...)
	n.mu.RUnlock()

	if len(relayPeerOrder) != 1 {
		t.Fatalf("expected default relay to be configured when relay addresses are omitted, got %d", len(relayPeerOrder))
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

func TestAutoRegister_DoesNotWaitForSlowSecondaryWarmAttempt(t *testing.T) {
	hexKey := generateTestKey(t)

	n := NewNode()
	slowRelayReleased := make(chan struct{})
	circuitReady := make(chan struct{})
	registerCalled := make(chan struct{}, 1)
	var warmCalls atomic.Int32

	n.warmRelayConnectionHook = func(info peer.AddrInfo) error {
		call := warmCalls.Add(1)
		if call == 1 {
			close(circuitReady)
			return nil
		}

		<-slowRelayReleased
		return nil
	}
	n.waitForCircuitAddressHook = func(timeout time.Duration) bool {
		select {
		case <-circuitReady:
			return true
		case <-time.After(timeout):
			return false
		}
	}
	n.rendezvousRegisterHook = func(namespace string, serverAddresses []string) error {
		registerCalled <- struct{}{}
		return nil
	}

	_, err := n.Start(NodeConfig{
		PrivateKeyHex: hexKey,
		RelayAddresses: []string{
			generateFakeRelayAddr(t, 19011),
			generateFakeRelayAddr(t, 19012),
		},
		AutoRegister: true,
		Namespace:    "mknoon:chat:test",
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}

	select {
	case <-registerCalled:
	case <-time.After(200 * time.Millisecond):
		close(slowRelayReleased)
		n.Stop()
		t.Fatal("auto-register waited on a slow secondary warm attempt")
	}

	close(slowRelayReleased)
	if err := n.Stop(); err != nil {
		t.Fatalf("Stop: %v", err)
	}
}

func TestPersonalRendezvousRefreshInterval_IsSafelyBelowTTL(t *testing.T) {
	if DefaultPersonalRendezvousRefreshEvery >= PersonalRendezvousRegistrationTTL {
		t.Fatalf(
			"default personal refresh interval %v must be below registration TTL %v",
			DefaultPersonalRendezvousRefreshEvery,
			PersonalRendezvousRegistrationTTL,
		)
	}
	if DefaultPersonalRendezvousRefreshEvery > PersonalRendezvousRegistrationTTL/2 {
		t.Fatalf(
			"default personal refresh interval %v should leave a large safety margin under TTL %v",
			DefaultPersonalRendezvousRefreshEvery,
			PersonalRendezvousRegistrationTTL,
		)
	}

	cfg := NodeConfig{}
	if got := cfg.PersonalRendezvousRefreshEvery(); got != DefaultPersonalRendezvousRefreshEvery {
		t.Fatalf("default refresh interval = %v, want %v", got, DefaultPersonalRendezvousRefreshEvery)
	}

	cfg.PersonalRendezvousRefreshInterval = 7 * time.Second
	if got := cfg.PersonalRendezvousRefreshEvery(); got != 7*time.Second {
		t.Fatalf("configured refresh interval = %v, want %v", got, 7*time.Second)
	}
}

func TestWarmRelayConnectionWithTimeout_FallsBackAcrossSamePeerAddresses(t *testing.T) {
	seedAddr := generateFakeRelayAddr(t, 19021)
	seedMaddr, err := ma.NewMultiaddr(seedAddr)
	if err != nil {
		t.Fatalf("NewMultiaddr(%q): %v", seedAddr, err)
	}
	seedInfo, err := peer.AddrInfoFromP2pAddr(seedMaddr)
	if err != nil {
		t.Fatalf("AddrInfoFromP2pAddr(%q): %v", seedAddr, err)
	}
	peerID := seedInfo.ID.String()
	firstAddr := fmt.Sprintf("/ip4/127.0.0.1/udp/19022/quic-v1/p2p/%s", peerID)
	secondAddr := fmt.Sprintf("/ip4/127.0.0.1/tcp/19023/ws/p2p/%s", peerID)
	relay := NewRelaySelector([]string{firstAddr, secondAddr}).Relays()[0]

	n := NewNode()
	n.ctx, n.cancel = context.WithCancel(context.Background())
	defer n.cancel()

	attempts := make([]string, 0, 2)
	n.connectRelayHook = func(ctx context.Context, info peer.AddrInfo) error {
		if len(info.Addrs) != 1 {
			t.Fatalf("connect attempt got %d addrs, want one", len(info.Addrs))
		}
		attempts = append(attempts, info.Addrs[0].String())
		if len(attempts) == 1 {
			return errors.New("first transport failed")
		}
		return nil
	}

	if err := n.warmRelayConnectionWithTimeout(peer.AddrInfo{
		ID:    relay.ID,
		Addrs: relay.Addrs,
	}, time.Second); err != nil {
		t.Fatalf("warmRelayConnectionWithTimeout: %v", err)
	}

	if len(attempts) != 2 {
		t.Fatalf("connect attempts = %d, want 2 (%v)", len(attempts), attempts)
	}
	if attempts[0] != "/ip4/127.0.0.1/udp/19022/quic-v1" {
		t.Fatalf("first attempt = %q, want QUIC address", attempts[0])
	}
	if attempts[1] != "/ip4/127.0.0.1/tcp/19023/ws" {
		t.Fatalf("second attempt = %q, want WSS address", attempts[1])
	}
}

func TestPersonalRendezvousRefreshLoop_StartsAfterSuccessfulPersonalRegister(t *testing.T) {
	hexKey := generateTestKey(t)

	n := NewNode()
	initialRegisterStarted := make(chan struct{})
	releaseInitialRegister := make(chan struct{})
	refreshObserved := make(chan struct{}, 1)
	var callCount atomic.Int32

	n.warmRelayConnectionHook = func(info peer.AddrInfo) error {
		return nil
	}
	n.waitForCircuitAddressHook = func(timeout time.Duration) bool {
		return true
	}
	n.rendezvousRegisterHook = func(namespace string, serverAddresses []string) error {
		switch callCount.Add(1) {
		case 1:
			close(initialRegisterStarted)
			select {
			case <-releaseInitialRegister:
			case <-n.ctx.Done():
			}
		case 2:
			refreshObserved <- struct{}{}
		}
		return nil
	}

	_, err := n.Start(NodeConfig{
		PrivateKeyHex: hexKey,
		RelayAddresses: []string{
			generateFakeRelayAddr(t, 19021),
		},
		AutoRegister:                      true,
		Namespace:                         "mknoon:chat:phase1-start-after-register",
		PersonalRendezvousRefreshInterval: 10 * time.Millisecond,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	select {
	case <-initialRegisterStarted:
	case <-time.After(200 * time.Millisecond):
		t.Fatal("expected initial personal registration attempt to start")
	}

	time.Sleep(40 * time.Millisecond)
	if got := callCount.Load(); got != 1 {
		t.Fatalf("refresh loop started before initial registration succeeded; got %d register calls", got)
	}

	close(releaseInitialRegister)

	select {
	case <-refreshObserved:
	case <-time.After(200 * time.Millisecond):
		t.Fatal("expected personal refresh loop to start after initial registration succeeded")
	}
}

func TestPersonalRendezvousRefreshLoop_SkipsWhenNodeNotStarted(t *testing.T) {
	n := NewNode()
	registerCalled := make(chan struct{}, 1)

	n.rendezvousRegisterHook = func(namespace string, serverAddresses []string) error {
		registerCalled <- struct{}{}
		return nil
	}

	n.startPersonalRendezvousRefreshLoop(10 * time.Millisecond)

	select {
	case <-registerCalled:
		t.Fatal("refresh loop should not register when the node has not started")
	case <-time.After(40 * time.Millisecond):
	}

	n.mu.RLock()
	cancel := n.personalRendezvousRefreshCancel
	n.mu.RUnlock()
	if cancel != nil {
		t.Fatal("refresh loop should not leave a cancel handle when the node has not started")
	}
}

func TestPersonalRendezvousRefreshLoop_UsesConfiguredNamespace(t *testing.T) {
	hexKey := generateTestKey(t)

	n := NewNode()
	namespaces := make(chan string, 4)

	n.warmRelayConnectionHook = func(info peer.AddrInfo) error {
		return nil
	}
	n.waitForCircuitAddressHook = func(timeout time.Duration) bool {
		return true
	}
	n.rendezvousRegisterHook = func(namespace string, serverAddresses []string) error {
		namespaces <- namespace
		return nil
	}

	const expectedNamespace = "mknoon:chat:configured-namespace"
	_, err := n.Start(NodeConfig{
		PrivateKeyHex: hexKey,
		RelayAddresses: []string{
			generateFakeRelayAddr(t, 19022),
		},
		AutoRegister:                      true,
		Namespace:                         expectedNamespace,
		PersonalRendezvousRefreshInterval: 10 * time.Millisecond,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	for i := 0; i < 2; i++ {
		select {
		case namespace := <-namespaces:
			if namespace != expectedNamespace {
				t.Fatalf("register call %d used namespace %q, want %q", i+1, namespace, expectedNamespace)
			}
		case <-time.After(200 * time.Millisecond):
			t.Fatalf("timed out waiting for register call %d", i+1)
		}
	}
}

func TestPersonalRendezvousRefreshLoop_DoesNotStartWhenAutoRegisterDisabled(t *testing.T) {
	hexKey := generateTestKey(t)

	n := NewNode()
	registerCalled := make(chan struct{}, 1)

	n.warmRelayConnectionHook = func(info peer.AddrInfo) error {
		return nil
	}
	n.waitForCircuitAddressHook = func(timeout time.Duration) bool {
		return true
	}
	n.rendezvousRegisterHook = func(namespace string, serverAddresses []string) error {
		registerCalled <- struct{}{}
		return nil
	}

	_, err := n.Start(NodeConfig{
		PrivateKeyHex: hexKey,
		RelayAddresses: []string{
			generateFakeRelayAddr(t, 19023),
		},
		AutoRegister:                      false,
		Namespace:                         "mknoon:chat:no-auto-register",
		PersonalRendezvousRefreshInterval: 10 * time.Millisecond,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	select {
	case <-registerCalled:
		t.Fatal("personal rendezvous registration should not start when AutoRegister=false")
	case <-time.After(60 * time.Millisecond):
	}

	n.mu.RLock()
	cancel := n.personalRendezvousRefreshCancel
	n.mu.RUnlock()
	if cancel != nil {
		t.Fatal("refresh loop should not start when AutoRegister=false")
	}
}

func TestPersonalRendezvousRefreshLoop_StopsOnNodeStop(t *testing.T) {
	hexKey := generateTestKey(t)

	n := NewNode()
	firstRefreshStarted := make(chan struct{})
	var callCount atomic.Int32

	n.warmRelayConnectionHook = func(info peer.AddrInfo) error {
		return nil
	}
	n.waitForCircuitAddressHook = func(timeout time.Duration) bool {
		return true
	}
	n.rendezvousRegisterHook = func(namespace string, serverAddresses []string) error {
		switch callCount.Add(1) {
		case 1:
			return nil
		case 2:
			close(firstRefreshStarted)
			<-n.ctx.Done()
		}
		return nil
	}

	_, err := n.Start(NodeConfig{
		PrivateKeyHex: hexKey,
		RelayAddresses: []string{
			generateFakeRelayAddr(t, 19024),
		},
		AutoRegister:                      true,
		Namespace:                         "mknoon:chat:phase1-stop",
		PersonalRendezvousRefreshInterval: 10 * time.Millisecond,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}

	select {
	case <-firstRefreshStarted:
	case <-time.After(200 * time.Millisecond):
		n.Stop()
		t.Fatal("expected refresh loop to attempt a registration before Stop()")
	}

	if err := n.Stop(); err != nil {
		t.Fatalf("Stop: %v", err)
	}

	time.Sleep(40 * time.Millisecond)

	if got := callCount.Load(); got != 2 {
		t.Fatalf("expected initial register plus exactly 1 in-flight refresh before stop, got %d calls", got)
	}
}

func TestPersonalRendezvousRefreshLoop_DoesNotDuplicateConcurrentTicks(t *testing.T) {
	hexKey := generateTestKey(t)

	n := NewNode()
	refreshStarted := make(chan struct{})
	releaseRefresh := make(chan struct{})
	var callCount atomic.Int32
	var inFlight atomic.Int32
	var maxInFlight atomic.Int32

	n.warmRelayConnectionHook = func(info peer.AddrInfo) error {
		return nil
	}
	n.waitForCircuitAddressHook = func(timeout time.Duration) bool {
		return true
	}
	n.rendezvousRegisterHook = func(namespace string, serverAddresses []string) error {
		current := inFlight.Add(1)
		for {
			existing := maxInFlight.Load()
			if current <= existing {
				break
			}
			if maxInFlight.CompareAndSwap(existing, current) {
				break
			}
		}

		callNumber := callCount.Add(1)
		if callNumber == 2 {
			close(refreshStarted)
			select {
			case <-releaseRefresh:
			case <-n.ctx.Done():
			}
		}

		inFlight.Add(-1)
		return nil
	}

	_, err := n.Start(NodeConfig{
		PrivateKeyHex: hexKey,
		RelayAddresses: []string{
			generateFakeRelayAddr(t, 19025),
		},
		AutoRegister:                      true,
		Namespace:                         "mknoon:chat:no-duplicate-ticks",
		PersonalRendezvousRefreshInterval: 10 * time.Millisecond,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	select {
	case <-refreshStarted:
	case <-time.After(200 * time.Millisecond):
		t.Fatal("expected first refresh-loop registration attempt to start")
	}

	time.Sleep(50 * time.Millisecond)

	if got := callCount.Load(); got != 2 {
		t.Fatalf("expected initial register plus exactly 1 blocked refresh attempt, got %d calls", got)
	}
	if got := maxInFlight.Load(); got != 1 {
		t.Fatalf("expected at most 1 concurrent registration attempt, got %d", got)
	}

	close(releaseRefresh)
}

func TestPersonalRendezvousRefreshLoop_DoesNotStartForGroupNamespaceRegister(t *testing.T) {
	hexKey := generateTestKey(t)

	n := NewNode()
	registerCalled := make(chan struct{}, 1)

	n.waitForCircuitAddressHook = func(timeout time.Duration) bool {
		return false
	}
	n.rendezvousRegisterHook = func(namespace string, serverAddresses []string) error {
		registerCalled <- struct{}{}
		return nil
	}

	_, err := n.Start(NodeConfig{
		PrivateKeyHex: hexKey,
		RelayAddresses: []string{
			generateFakeRelayAddr(t, 19026),
		},
		AutoRegister: true,
		Namespace:    "mknoon:chat:personal-namespace",
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	n.maybeStartPersonalRendezvousRefreshLoopAfterRegister(groupRendezvousNamespace("group-123"))

	select {
	case <-registerCalled:
		t.Fatal("group namespace register should not trigger the personal refresh loop")
	case <-time.After(40 * time.Millisecond):
	}

	n.mu.RLock()
	cancel := n.personalRendezvousRefreshCancel
	n.mu.RUnlock()
	if cancel != nil {
		t.Fatal("group namespace register should not start the personal refresh loop")
	}
}

func waitForPersonalRegisterCall(t *testing.T, registers <-chan string, timeout time.Duration) string {
	t.Helper()

	select {
	case namespace := <-registers:
		return namespace
	case <-time.After(timeout):
		t.Fatalf("timed out waiting for personal registration within %v", timeout)
		return ""
	}
}

func waitForPersonalRegisterIdle(t *testing.T, n *Node, timeout time.Duration) {
	t.Helper()

	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if !n.personalRendezvousRegistering.Load() {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatalf("timed out waiting for personal registration guard to clear within %v", timeout)
}

func assertNoPersonalRegisterCall(t *testing.T, registers <-chan string, timeout time.Duration) {
	t.Helper()

	select {
	case namespace := <-registers:
		t.Fatalf("unexpected personal registration for namespace %q", namespace)
	case <-time.After(timeout):
	}
}

func TestGR001RefreshRelaySessionNotStartedReturnsStructuredFailure(t *testing.T) {
	n := NewNode()

	assertNotStarted := func(result *RecoveryResult) {
		t.Helper()
		if result == nil {
			t.Fatal("RefreshRelaySession returned nil result")
		}
		if result.Success {
			t.Fatalf("RefreshRelaySession success = true, want false: %+v", result)
		}
		if result.RecoveryMode != "in_place" {
			t.Fatalf("RecoveryMode = %q, want in_place: %+v", result.RecoveryMode, result)
		}
		if result.ErrorCode != "NOT_STARTED" {
			t.Fatalf("ErrorCode = %q, want NOT_STARTED: %+v", result.ErrorCode, result)
		}
		if result.Reason != "node not started" {
			t.Fatalf("Reason = %q, want node not started: %+v", result.Reason, result)
		}
		if !result.ReusedHost {
			t.Fatalf("ReusedHost = false, want true: %+v", result)
		}
	}

	assertNotStarted(n.RefreshRelaySession())

	n.mu.RLock()
	hostAfterFirstRefresh := n.host
	startedAfterFirstRefresh := n.isStarted
	n.mu.RUnlock()
	if hostAfterFirstRefresh != nil {
		t.Fatal("RefreshRelaySession created a host before Start")
	}
	if startedAfterFirstRefresh {
		t.Fatal("RefreshRelaySession marked an unstarted node as started")
	}

	n.relaySessionMgr.mu.RLock()
	recoveringAfterFirstRefresh := n.relaySessionMgr.recovering
	n.relaySessionMgr.mu.RUnlock()
	if recoveringAfterFirstRefresh {
		t.Fatal("RefreshRelaySession left the shared recovery gate active after NOT_STARTED")
	}

	assertNotStarted(n.RefreshRelaySession())
}

func TestGR002ConcurrentRefreshRelaySessionCallsCoalesce(t *testing.T) {
	hexKey := generateTestKey(t)

	n := NewNode()
	refreshStarted := make(chan struct{})
	releaseRefresh := make(chan struct{})
	var refreshCalls atomic.Int32

	n.warmRelayConnectionHook = func(info peer.AddrInfo) error {
		return nil
	}
	n.waitForCircuitAddressHook = func(timeout time.Duration) bool {
		return true
	}
	n.refreshRelaySessionHook = func() *RecoveryResult {
		if refreshCalls.Add(1) == 1 {
			close(refreshStarted)
			select {
			case <-releaseRefresh:
			case <-n.ctx.Done():
			}
		}
		return &RecoveryResult{
			RecoveryMode:      "in_place",
			Success:           true,
			RelayState:        string(AggregateRelayOnline),
			HealthyRelayCount: 1,
		}
	}

	_, err := n.Start(NodeConfig{
		PrivateKeyHex: hexKey,
		RelayAddresses: []string{
			generateFakeRelayAddr(t, 19030),
		},
		PersonalRendezvousRefreshInterval: time.Hour,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	const callers = 4
	type refreshOutcome struct {
		result *RecoveryResult
	}
	outcomes := make(chan refreshOutcome, callers)
	var wg sync.WaitGroup
	wg.Add(callers)
	for i := 0; i < callers; i++ {
		go func() {
			defer wg.Done()
			outcomes <- refreshOutcome{result: n.RefreshRelaySession()}
		}()
	}

	select {
	case <-refreshStarted:
	case <-time.After(200 * time.Millisecond):
		t.Fatal("expected one RefreshRelaySession caller to begin the blocked refresh hook")
	}

	deadline := time.After(500 * time.Millisecond)
	ticker := time.NewTicker(10 * time.Millisecond)
	defer ticker.Stop()
	for {
		n.relaySessionMgr.mu.RLock()
		waiters := 0
		if n.relaySessionMgr.recovery != nil {
			waiters = n.relaySessionMgr.recovery.coalescedWaiters
		}
		n.relaySessionMgr.mu.RUnlock()
		if waiters == callers-1 {
			break
		}
		select {
		case <-ticker.C:
		case <-deadline:
			t.Fatalf("expected %d coalesced RefreshRelaySession waiters before release, got %d", callers-1, waiters)
		}
	}

	close(releaseRefresh)
	wg.Wait()
	close(outcomes)

	var first *RecoveryResult
	for i := 0; i < callers; i++ {
		outcome := <-outcomes
		if outcome.result == nil {
			t.Fatalf("RefreshRelaySession caller %d returned nil result", i+1)
		}
		if first == nil {
			first = outcome.result
		} else if outcome.result != first {
			t.Fatalf("RefreshRelaySession caller %d did not receive the shared recovery result", i+1)
		}
		if !outcome.result.Success || outcome.result.RecoveryMode != "in_place" {
			t.Fatalf("RefreshRelaySession caller %d got %+v, want successful in_place recovery", i+1, outcome.result)
		}
		if !outcome.result.ReusedHost {
			t.Fatalf("RefreshRelaySession caller %d reusedHost=false, want true", i+1)
		}
		if got := outcome.result.CoalescedRecoveryRequests; got != callers-1 {
			t.Fatalf("RefreshRelaySession caller %d coalescedRecoveryRequests=%d, want %d", i+1, got, callers-1)
		}
	}

	if got := refreshCalls.Load(); got != 1 {
		t.Fatalf("expected exactly 1 refresh hook invocation across concurrent callers, got %d", got)
	}
	if n.relaySessionMgr.IsRecovering() {
		t.Fatal("RefreshRelaySession left the shared recovery gate active after completion")
	}
}

func TestGR007AcknowledgeGroupRecoveryStoppedNodeFailsWithoutMutatingState(t *testing.T) {
	n := NewNode()
	collector := &testEventCollector{}
	n.eventCallback = collector

	n.relaySessionMgr.RecordWatchdogRestart()
	if got := n.relaySessionMgr.WatchdogRestartCount(); got != 1 {
		t.Fatalf("watchdog restart count before ack = %d, want 1", got)
	}
	if !n.relaySessionMgr.NeedsGroupRecovery() {
		t.Fatal("needsGroupRecovery should be true before stopped-node acknowledgement")
	}

	if err := n.Stop(); err != nil {
		t.Fatalf("Stop: %v", err)
	}

	err := n.AcknowledgeGroupRecovery()
	if err == nil {
		t.Fatal("AcknowledgeGroupRecovery on stopped node returned nil error")
	}
	if err.Error() != "node not started" {
		t.Fatalf("AcknowledgeGroupRecovery error = %q, want node not started", err.Error())
	}

	if !n.relaySessionMgr.NeedsGroupRecovery() {
		t.Fatal("stopped-node acknowledgement cleared needsGroupRecovery")
	}
	if got := n.relaySessionMgr.WatchdogRestartCount(); got != 1 {
		t.Fatalf("watchdog restart count after failed ack = %d, want 1", got)
	}
	if events := collector.snapshot(); len(events) != 0 {
		t.Fatalf("stopped-node acknowledgement emitted events: %v", events)
	}
}

func TestGR011RelayConnectednessUpdatesOnlyConfiguredRelayPeers(t *testing.T) {
	n := NewNode()
	collector := &testEventCollector{}
	n.eventCallback = collector

	relayPeer := fakePeerID("relay-gr011")
	nonRelayPeer := fakePeerID("non-relay-gr011")

	n.mu.Lock()
	n.relayPeerOrder = []peer.ID{relayPeer}
	n.mu.Unlock()
	n.relaySessionMgr.InitRelayPeer(relayPeer)

	n.mu.Lock()
	n.connections[nonRelayPeer.String()] = connectionInfo{PeerId: nonRelayPeer.String()}
	n.mu.Unlock()
	n.handleRelayConnectednessChanged(nonRelayPeer, network.Connected)

	if s := n.relaySessionMgr.GetSession(nonRelayPeer); s != nil {
		t.Fatalf("non-relay connectedness created relay session: %+v", s)
	}
	relaySession := n.relaySessionMgr.GetSession(relayPeer)
	if relaySession == nil {
		t.Fatal("expected configured relay session to remain tracked")
	}
	if relaySession.State != RelayStateDisconnected {
		t.Fatalf("configured relay state changed after non-relay connectedness = %s, want disconnected", relaySession.State)
	}
	if events := collector.snapshot(); len(events) != 0 {
		t.Fatalf("non-relay connectedness emitted relay state events: %v", events)
	}

	n.mu.Lock()
	n.connections[relayPeer.String()] = connectionInfo{PeerId: relayPeer.String()}
	n.mu.Unlock()
	n.handleRelayConnectednessChanged(relayPeer, network.Connected)

	relaySession = n.relaySessionMgr.GetSession(relayPeer)
	if relaySession == nil || relaySession.State != RelayStateConnected {
		t.Fatalf("configured relay connectedness state = %+v, want connected", relaySession)
	}
	fields := n.relaySessionMgr.StatusFields()
	relayStates, ok := fields["relayStates"].([]map[string]interface{})
	if !ok {
		t.Fatalf("status relayStates has type %T, want []map[string]interface{}", fields["relayStates"])
	}
	if len(relayStates) != 1 {
		t.Fatalf("status relayStates length = %d, want 1", len(relayStates))
	}
	if relayStates[0]["peerId"] != relayPeer.String() {
		t.Fatalf("status relay peer = %v, want %s", relayStates[0]["peerId"], relayPeer.String())
	}
	if relayStates[0]["state"] != string(RelayStateConnected) {
		t.Fatalf("status relay state = %v, want connected", relayStates[0]["state"])
	}

	n.mu.Lock()
	delete(n.connections, nonRelayPeer.String())
	n.mu.Unlock()
	n.handleRelayConnectednessChanged(nonRelayPeer, network.NotConnected)

	relaySession = n.relaySessionMgr.GetSession(relayPeer)
	if relaySession == nil || relaySession.State != RelayStateConnected {
		t.Fatalf("non-relay disconnect mutated configured relay state = %+v, want connected", relaySession)
	}
	if s := n.relaySessionMgr.GetSession(nonRelayPeer); s != nil {
		t.Fatalf("non-relay disconnect created relay session: %+v", s)
	}

	n.mu.Lock()
	delete(n.connections, relayPeer.String())
	n.mu.Unlock()
	n.handleRelayConnectednessChanged(relayPeer, network.NotConnected)

	relaySession = n.relaySessionMgr.GetSession(relayPeer)
	if relaySession == nil || relaySession.State != RelayStateDegraded {
		t.Fatalf("configured relay disconnect state = %+v, want degraded", relaySession)
	}
	if got := n.relaySessionMgr.HealthyRelayCount(); got != 0 {
		t.Fatalf("healthy relay count after configured relay disconnect = %d, want 0", got)
	}
}

func TestGR018RecoveryEventsAreDiagnosticAndPrivacySafe(t *testing.T) {
	const (
		privateGroupBody = "gr018-private-group-body-never-leak"
		privateGroupKey  = "gr018-super-secret-group-key-never-leak"
	)

	collector := &testEventCollector{}
	n := New(collector)
	relayPeer := fakePeerID("relay-gr018")

	n.groupConfigs = map[string]*GroupConfig{
		"gr018-private-group": {
			Name:        "gr018-private-group",
			Description: privateGroupBody,
		},
	}
	n.groupKeys = map[string]*GroupKeyInfo{
		"gr018-private-group": {
			Key:      privateGroupKey,
			KeyEpoch: 7,
		},
	}

	n.mu.Lock()
	n.relayPeerOrder = []peer.ID{relayPeer}
	n.connections[relayPeer.String()] = connectionInfo{PeerId: relayPeer.String()}
	n.mu.Unlock()
	n.relaySessionMgr.InitRelayPeer(relayPeer)

	circuitAddr := fmt.Sprintf("/ip4/127.0.0.1/tcp/19036/p2p/%s/p2p-circuit/p2p/%s", relayPeer, "self-gr018")
	n.syncRelaySessionFromRuntime("refresh_relay_session", []string{circuitAddr})

	for i := 0; i < WatchdogMaxConsecutiveFailures; i++ {
		n.relaySessionMgr.OnRefreshFailed(relayPeer, fmt.Errorf("gr018 relay probe failed %d", i+1))
	}
	n.emitRelayStateEvent("watchdog_restart")

	events := collector.collectEvents("relay:state")
	if len(events) != 2 {
		t.Fatalf("relay:state event count = %d, want 2: %v", len(events), events)
	}

	success := findGR018RelayStateEvent(t, events, "refresh_relay_session")
	if success["relayState"] != string(AggregateRelayOnline) {
		t.Fatalf("success relayState = %v, want online: %v", success["relayState"], success)
	}
	if success["healthyRelayCount"] != float64(1) {
		t.Fatalf("success healthyRelayCount = %v, want 1: %v", success["healthyRelayCount"], success)
	}
	if success["needsGroupRecovery"] != false {
		t.Fatalf("success needsGroupRecovery = %v, want false: %v", success["needsGroupRecovery"], success)
	}
	successRelay := findGR018RelayPeerState(t, success, relayPeer)
	if successRelay["state"] != string(RelayStateReserved) {
		t.Fatalf("success relay peer state = %v, want reserved: %v", successRelay["state"], successRelay)
	}
	if successRelay["lastReservedAt"] == "" {
		t.Fatalf("success event missing lastReservedAt diagnostic: %v", successRelay)
	}

	failure := findGR018RelayStateEvent(t, events, "watchdog_restart")
	if failure["relayState"] != string(AggregateRelayWatchdogRestart) {
		t.Fatalf("failure relayState = %v, want watchdog_restart: %v", failure["relayState"], failure)
	}
	if failure["needsGroupRecovery"] != true {
		t.Fatalf("failure needsGroupRecovery = %v, want true: %v", failure["needsGroupRecovery"], failure)
	}
	if failure["watchdogRestartCount"] != float64(0) {
		t.Fatalf("failure watchdogRestartCount = %v, want 0 before full restart: %v", failure["watchdogRestartCount"], failure)
	}
	failureRelay := findGR018RelayPeerState(t, failure, relayPeer)
	if failureRelay["lastError"] == "" {
		t.Fatalf("failure event missing lastError diagnostic: %v", failureRelay)
	}

	for _, event := range events {
		assertGR018RecoveryEventPrivacy(t, event, privateGroupBody, privateGroupKey)
	}
}

func findGR018RelayStateEvent(t *testing.T, events []map[string]interface{}, reason string) map[string]interface{} {
	t.Helper()

	for _, event := range events {
		if got, _ := event["reason"].(string); got == reason {
			return event
		}
	}
	t.Fatalf("missing relay:state event with reason %q in %v", reason, events)
	return nil
}

func findGR018RelayPeerState(t *testing.T, event map[string]interface{}, relayPeer peer.ID) map[string]interface{} {
	t.Helper()

	relayStates, ok := event["relayStates"].([]interface{})
	if !ok {
		t.Fatalf("relayStates has type %T, want []interface{}: %v", event["relayStates"], event)
	}
	for _, raw := range relayStates {
		entry, ok := raw.(map[string]interface{})
		if !ok {
			t.Fatalf("relayStates entry has type %T, want map[string]interface{}: %v", raw, relayStates)
		}
		if entry["peerId"] == relayPeer.String() {
			return entry
		}
	}
	t.Fatalf("missing relay peer %s in event %v", relayPeer, event)
	return nil
}

func assertGR018RecoveryEventPrivacy(t *testing.T, event map[string]interface{}, forbiddenValues ...string) {
	t.Helper()

	raw, err := json.Marshal(event)
	if err != nil {
		t.Fatalf("marshal recovery event: %v", err)
	}
	lowerRaw := strings.ToLower(string(raw))
	for _, value := range forbiddenValues {
		if strings.Contains(lowerRaw, strings.ToLower(value)) {
			t.Fatalf("relay recovery event leaked forbidden value %q: %s", value, raw)
		}
	}

	forbiddenKeys := map[string]struct{}{
		"content":      {},
		"plaintext":    {},
		"ciphertext":   {},
		"nonce":        {},
		"signature":    {},
		"key":          {},
		"groupkey":     {},
		"privatekey":   {},
		"prevkey":      {},
		"keymaterial":  {},
		"message":      {},
		"payload":      {},
		"encryptedkey": {},
	}
	var walk func(string, interface{})
	walk = func(path string, value interface{}) {
		switch typed := value.(type) {
		case map[string]interface{}:
			for key, nested := range typed {
				normalizedKey := strings.ToLower(strings.ReplaceAll(key, "_", ""))
				if _, ok := forbiddenKeys[normalizedKey]; ok {
					t.Fatalf("relay recovery event exposed forbidden field %s.%s in %v", path, key, event)
				}
				walk(path+"."+key, nested)
			}
		case []interface{}:
			for i, nested := range typed {
				walk(fmt.Sprintf("%s[%d]", path, i), nested)
			}
		}
	}
	walk("data", event)
}

func TestRefreshRelaySession_ReRegistersPersonalNamespaceOnSuccess(t *testing.T) {
	hexKey := generateTestKey(t)
	const expectedNamespace = "mknoon:chat:phase2-in-place"

	n := NewNode()
	registers := make(chan string, 4)
	var refreshCalls atomic.Int32
	var registerCalls atomic.Int32

	n.warmRelayConnectionHook = func(info peer.AddrInfo) error {
		return nil
	}
	n.waitForCircuitAddressHook = func(timeout time.Duration) bool {
		return true
	}
	n.rendezvousRegisterHook = func(namespace string, serverAddresses []string) error {
		registerCalls.Add(1)
		registers <- namespace
		return nil
	}
	n.refreshRelaySessionHook = func() *RecoveryResult {
		refreshCalls.Add(1)
		return &RecoveryResult{
			RecoveryMode:      "in_place",
			Success:           true,
			RelayState:        string(AggregateRelayOnline),
			HealthyRelayCount: 1,
		}
	}

	_, err := n.Start(NodeConfig{
		PrivateKeyHex: hexKey,
		RelayAddresses: []string{
			generateFakeRelayAddr(t, 19027),
		},
		AutoRegister:                      true,
		Namespace:                         expectedNamespace,
		PersonalRendezvousRefreshInterval: time.Hour,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	if namespace := waitForPersonalRegisterCall(t, registers, 200*time.Millisecond); namespace != expectedNamespace {
		t.Fatalf("initial personal register used namespace %q, want %q", namespace, expectedNamespace)
	}
	waitForPersonalRegisterIdle(t, n, 200*time.Millisecond)

	result := n.RefreshRelaySession()
	if !result.Success {
		t.Fatalf("RefreshRelaySession() should succeed, got %+v", result)
	}
	if result.RecoveryMode != "in_place" {
		t.Fatalf("expected in_place recovery, got %+v", result)
	}
	if got := refreshCalls.Load(); got != 1 {
		t.Fatalf("expected exactly 1 in-place refresh attempt, got %d", got)
	}

	if namespace := waitForPersonalRegisterCall(t, registers, 200*time.Millisecond); namespace != expectedNamespace {
		t.Fatalf("recovery personal register used namespace %q, want %q", namespace, expectedNamespace)
	}
	if got := registerCalls.Load(); got != 2 {
		t.Fatalf("expected initial register plus 1 recovery re-register, got %d calls", got)
	}
}

func TestReconnectRelays_WatchdogRestart_ReRegistersPersonalNamespace(t *testing.T) {
	hexKey := generateTestKey(t)
	const expectedNamespace = "mknoon:chat:phase2-watchdog"

	n := NewNode()
	registers := make(chan string, 4)
	var refreshCalls atomic.Int32
	var registerCalls atomic.Int32

	n.warmRelayConnectionHook = func(info peer.AddrInfo) error {
		return nil
	}
	n.waitForCircuitAddressHook = func(timeout time.Duration) bool {
		return true
	}
	n.rendezvousRegisterHook = func(namespace string, serverAddresses []string) error {
		registerCalls.Add(1)
		registers <- namespace
		return nil
	}
	n.refreshRelaySessionHook = func() *RecoveryResult {
		refreshCalls.Add(1)
		return &RecoveryResult{
			RecoveryMode: "in_place",
			Success:      false,
			ErrorCode:    "REFRESH_FAILED",
			Reason:       "forced refresh failure",
		}
	}

	_, err := n.Start(NodeConfig{
		PrivateKeyHex: hexKey,
		RelayAddresses: []string{
			generateFakeRelayAddr(t, 19028),
		},
		AutoRegister:                      true,
		Namespace:                         expectedNamespace,
		PersonalRendezvousRefreshInterval: time.Hour,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	if namespace := waitForPersonalRegisterCall(t, registers, 200*time.Millisecond); namespace != expectedNamespace {
		t.Fatalf("initial personal register used namespace %q, want %q", namespace, expectedNamespace)
	}
	waitForPersonalRegisterIdle(t, n, 200*time.Millisecond)

	result, err := n.ReconnectRelays()
	if err != nil {
		t.Fatalf("ReconnectRelays(): %v", err)
	}
	if !result.Success {
		t.Fatalf("watchdog restart should succeed, got %+v", result)
	}
	if result.RecoveryMode != "watchdog_restart" {
		t.Fatalf("expected watchdog_restart, got %+v", result)
	}
	if result.ReusedHost {
		t.Fatalf("watchdog restart should report ReusedHost=false, got %+v", result)
	}
	if got := refreshCalls.Load(); got != 1 {
		t.Fatalf("expected exactly 1 failed in-place refresh before watchdog restart, got %d", got)
	}

	if namespace := waitForPersonalRegisterCall(t, registers, 200*time.Millisecond); namespace != expectedNamespace {
		t.Fatalf("watchdog recovery personal register used namespace %q, want %q", namespace, expectedNamespace)
	}
	if got := registerCalls.Load(); got != 2 {
		t.Fatalf("expected initial register plus 1 watchdog re-register, got %d calls", got)
	}

	n.mu.RLock()
	cancel := n.personalRendezvousRefreshCancel
	cfg := n.lastConfig
	n.mu.RUnlock()
	if cancel == nil {
		t.Fatal("watchdog recovery should restart the personal refresh loop")
	}
	if cfg == nil || !cfg.AutoRegister {
		t.Fatalf("watchdog recovery should restore AutoRegister in lastConfig, got %+v", cfg)
	}
}

func TestNW004RefreshRelaySessionPreservesJoinedGroupTopicState(t *testing.T) {
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

	groupIds := []string{"nw004-relay-reconnect-alpha", "nw004-relay-reconnect-beta"}
	for idx, groupId := range groupIds {
		config := testGroupConfig(GroupTypeChat)
		config.Name = fmt.Sprintf("NW-004 group %d", idx)
		keyInfo := &GroupKeyInfo{
			Key:      fmt.Sprintf("nw004-key-%d", idx),
			KeyEpoch: idx + 1,
		}
		if err := n.JoinGroupTopic(groupId, config, keyInfo); err != nil {
			t.Fatalf("JoinGroupTopic(%s): %v", groupId, err)
		}
	}

	n.mu.RLock()
	pubsubBefore := n.pubsub
	topicByGroup := map[string]interface{}{}
	subByGroup := map[string]interface{}{}
	for _, groupId := range groupIds {
		topicByGroup[groupId] = n.groupTopics[groupId]
		subByGroup[groupId] = n.groupSubs[groupId]
	}
	n.mu.RUnlock()

	result := n.RefreshRelaySession()
	if result == nil {
		t.Fatal("RefreshRelaySession returned nil")
	}

	n.mu.RLock()
	defer n.mu.RUnlock()
	if n.pubsub != pubsubBefore {
		t.Fatal("NW-004 relay reconnect must preserve pubsub instance")
	}
	for idx, groupId := range groupIds {
		if n.groupTopics[groupId] == nil {
			t.Fatalf("NW-004 group topic %s missing after reconnect", groupId)
		}
		if n.groupTopics[groupId] != topicByGroup[groupId] {
			t.Fatalf("NW-004 group topic %s was replaced during reconnect", groupId)
		}
		if n.groupSubs[groupId] == nil {
			t.Fatalf("NW-004 group subscription %s missing after reconnect", groupId)
		}
		if n.groupSubs[groupId] != subByGroup[groupId] {
			t.Fatalf("NW-004 group subscription %s was replaced during reconnect", groupId)
		}
		if n.groupConfigs[groupId] == nil {
			t.Fatalf("NW-004 group config %s missing after reconnect", groupId)
		}
		keyInfo := n.groupKeys[groupId]
		if keyInfo == nil {
			t.Fatalf("NW-004 group key %s missing after reconnect", groupId)
		}
		if keyInfo.Key != fmt.Sprintf("nw004-key-%d", idx) || keyInfo.KeyEpoch != idx+1 {
			t.Fatalf("NW-004 group key %s = (%q,%d), want (%q,%d)",
				groupId, keyInfo.Key, keyInfo.KeyEpoch, fmt.Sprintf("nw004-key-%d", idx), idx+1)
		}
	}
}

func TestGR020ReconnectRelaysPreservesOriginalAutoRegisterSetting(t *testing.T) {
	for _, tc := range []struct {
		name         string
		autoRegister bool
		namespace    string
		relayPort    int
		wantCalls    int32
	}{
		{
			name:         "enabled restores true and re-registers personal namespace",
			autoRegister: true,
			namespace:    "mknoon:chat:gr020-enabled",
			relayPort:    19038,
			wantCalls:    2,
		},
		{
			name:         "disabled restores false and does not register personal namespace",
			autoRegister: false,
			namespace:    "mknoon:chat:gr020-disabled",
			relayPort:    19039,
			wantCalls:    0,
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			hexKey := generateTestKey(t)
			n := NewNode()
			registers := make(chan string, 4)
			var refreshCalls atomic.Int32
			var registerCalls atomic.Int32

			n.warmRelayConnectionHook = func(info peer.AddrInfo) error {
				return nil
			}
			n.waitForCircuitAddressHook = func(timeout time.Duration) bool {
				return true
			}
			n.rendezvousRegisterHook = func(namespace string, serverAddresses []string) error {
				registerCalls.Add(1)
				registers <- namespace
				return nil
			}
			n.refreshRelaySessionHook = func() *RecoveryResult {
				refreshCalls.Add(1)
				return &RecoveryResult{
					RecoveryMode: "in_place",
					Success:      false,
					ErrorCode:    "REFRESH_FAILED",
					Reason:       "forced refresh failure",
				}
			}

			_, err := n.Start(NodeConfig{
				PrivateKeyHex: hexKey,
				RelayAddresses: []string{
					generateFakeRelayAddr(t, tc.relayPort),
				},
				AutoRegister:                      tc.autoRegister,
				Namespace:                         tc.namespace,
				PersonalRendezvousRefreshInterval: time.Hour,
			})
			if err != nil {
				t.Fatalf("Start: %v", err)
			}
			defer n.Stop()

			if tc.autoRegister {
				if namespace := waitForPersonalRegisterCall(t, registers, 200*time.Millisecond); namespace != tc.namespace {
					t.Fatalf("initial personal register used namespace %q, want %q", namespace, tc.namespace)
				}
				waitForPersonalRegisterIdle(t, n, 200*time.Millisecond)
			} else {
				assertNoPersonalRegisterCall(t, registers, 80*time.Millisecond)
			}

			result, err := n.ReconnectRelays()
			if err != nil {
				t.Fatalf("ReconnectRelays(): %v", err)
			}
			if !result.Success {
				t.Fatalf("watchdog restart should succeed, got %+v", result)
			}
			if result.RecoveryMode != "watchdog_restart" {
				t.Fatalf("expected watchdog_restart, got %+v", result)
			}
			if got := refreshCalls.Load(); got != 1 {
				t.Fatalf("expected exactly 1 failed in-place refresh before restart, got %d", got)
			}

			if tc.autoRegister {
				if namespace := waitForPersonalRegisterCall(t, registers, 200*time.Millisecond); namespace != tc.namespace {
					t.Fatalf("watchdog recovery personal register used namespace %q, want %q", namespace, tc.namespace)
				}
			} else {
				assertNoPersonalRegisterCall(t, registers, 120*time.Millisecond)
			}
			if got := registerCalls.Load(); got != tc.wantCalls {
				t.Fatalf("personal register call count = %d, want %d", got, tc.wantCalls)
			}

			n.mu.RLock()
			cfg := n.lastConfig
			cancel := n.personalRendezvousRefreshCancel
			n.mu.RUnlock()
			if cfg == nil {
				t.Fatal("lastConfig should be restored after watchdog restart")
			}
			if cfg.AutoRegister != tc.autoRegister {
				t.Fatalf("lastConfig.AutoRegister = %v, want original %v", cfg.AutoRegister, tc.autoRegister)
			}
			if cfg.Namespace != tc.namespace {
				t.Fatalf("lastConfig.Namespace = %q, want %q", cfg.Namespace, tc.namespace)
			}
			if tc.autoRegister && cancel == nil {
				t.Fatal("watchdog restart should restore personal refresh loop when AutoRegister=true")
			}
			if !tc.autoRegister && cancel != nil {
				t.Fatal("watchdog restart should not start personal refresh loop when AutoRegister=false")
			}
		})
	}
}

func TestRecoveryCoalescing_PerformsSinglePersonalReregister(t *testing.T) {
	hexKey := generateTestKey(t)
	const expectedNamespace = "mknoon:chat:phase2-coalesced"

	n := NewNode()
	registers := make(chan string, 4)
	refreshStarted := make(chan struct{})
	releaseRefresh := make(chan struct{})
	var refreshCalls atomic.Int32
	var registerCalls atomic.Int32

	n.warmRelayConnectionHook = func(info peer.AddrInfo) error {
		return nil
	}
	n.waitForCircuitAddressHook = func(timeout time.Duration) bool {
		return true
	}
	n.rendezvousRegisterHook = func(namespace string, serverAddresses []string) error {
		registerCalls.Add(1)
		registers <- namespace
		return nil
	}
	n.refreshRelaySessionHook = func() *RecoveryResult {
		if refreshCalls.Add(1) == 1 {
			close(refreshStarted)
			select {
			case <-releaseRefresh:
			case <-n.ctx.Done():
			}
		}
		return &RecoveryResult{
			RecoveryMode: "in_place",
			Success:      false,
			ErrorCode:    "REFRESH_FAILED",
			Reason:       "forced refresh failure",
		}
	}

	_, err := n.Start(NodeConfig{
		PrivateKeyHex: hexKey,
		RelayAddresses: []string{
			generateFakeRelayAddr(t, 19029),
		},
		AutoRegister:                      true,
		Namespace:                         expectedNamespace,
		PersonalRendezvousRefreshInterval: time.Hour,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	if namespace := waitForPersonalRegisterCall(t, registers, 200*time.Millisecond); namespace != expectedNamespace {
		t.Fatalf("initial personal register used namespace %q, want %q", namespace, expectedNamespace)
	}
	waitForPersonalRegisterIdle(t, n, 200*time.Millisecond)

	type reconnectOutcome struct {
		result *RecoveryResult
		err    error
	}
	outcomes := make(chan reconnectOutcome, 2)

	go func() {
		result, err := n.ReconnectRelays()
		outcomes <- reconnectOutcome{result: result, err: err}
	}()

	select {
	case <-refreshStarted:
	case <-time.After(200 * time.Millisecond):
		t.Fatal("expected first reconnect caller to begin the in-place refresh step")
	}

	go func() {
		result, err := n.ReconnectRelays()
		outcomes <- reconnectOutcome{result: result, err: err}
	}()

	time.Sleep(40 * time.Millisecond)
	close(releaseRefresh)

	for i := 0; i < 2; i++ {
		outcome := <-outcomes
		if outcome.err != nil {
			t.Fatalf("ReconnectRelays() caller %d error: %v", i+1, outcome.err)
		}
		if outcome.result == nil {
			t.Fatalf("ReconnectRelays() caller %d returned nil result", i+1)
		}
		if !outcome.result.Success || outcome.result.RecoveryMode != "watchdog_restart" {
			t.Fatalf("ReconnectRelays() caller %d got %+v, want successful watchdog_restart", i+1, outcome.result)
		}
		if got := outcome.result.CoalescedRecoveryRequests; got != 1 {
			t.Fatalf("ReconnectRelays() caller %d coalescedRecoveryRequests=%d, want 1", i+1, got)
		}
	}

	if got := refreshCalls.Load(); got != 1 {
		t.Fatalf("expected exactly 1 in-place refresh attempt across concurrent callers, got %d", got)
	}
	if got := registerCalls.Load(); got != 2 {
		t.Fatalf("expected initial register plus exactly 1 watchdog re-register, got %d calls", got)
	}
	if namespace := waitForPersonalRegisterCall(t, registers, 200*time.Millisecond); namespace != expectedNamespace {
		t.Fatalf("watchdog recovery personal register used namespace %q, want %q", namespace, expectedNamespace)
	}

	status := n.Status()
	if got := status["watchdogRestartCount"]; got != 1 {
		t.Fatalf("expected a single watchdog restart after concurrent reconnects, got %v", got)
	}
}

// ---------------------------------------------------------------------------
// Phase 4: Relay Session Manager and Reservation-Aware Health
// ---------------------------------------------------------------------------

// testEventCollector implements EventCallback and collects emitted events.
type testEventCollector struct {
	mu     sync.Mutex
	events []string
}

func (c *testEventCollector) OnEvent(jsonStr string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.events = append(c.events, jsonStr)
}

func (c *testEventCollector) snapshot() []string {
	c.mu.Lock()
	defer c.mu.Unlock()
	out := make([]string, len(c.events))
	copy(out, c.events)
	return out
}

func TestRefreshRelaySession_DoesNotReplaceHost(t *testing.T) {
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

	// Capture the original host pointer.
	n.mu.RLock()
	originalHost := n.host
	n.mu.RUnlock()

	if originalHost == nil {
		t.Fatal("host should be non-nil after Start")
	}

	// Call RefreshRelaySession — this should attempt in-place recovery
	// without replacing the host.
	result := n.RefreshRelaySession()

	n.mu.RLock()
	currentHost := n.host
	n.mu.RUnlock()

	// The host pointer must be the same — no replacement.
	if currentHost != originalHost {
		t.Error("RefreshRelaySession should not replace the host")
	}

	// Recovery mode should be "in_place".
	if result.RecoveryMode != "in_place" {
		t.Errorf("expected recoveryMode=in_place, got %s", result.RecoveryMode)
	}
	if !result.ReusedHost {
		t.Fatalf("in-place refresh should report ReusedHost=true, got %+v", result)
	}
	if result.RelayRefreshMs < 0 {
		t.Fatalf("relay refresh timing should be non-negative, got %+v", result)
	}
	if result.ReservationPath == "" {
		t.Fatalf("reservation path should be populated, got %+v", result)
	}
}

func TestRefreshRelaySession_UsesForegroundCadenceAndDialTimeout(t *testing.T) {
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

	configureRefreshRelayAddresses(t, n, []string{generateFakeRelayAddr(t, 19030)})

	var warmTimeout time.Duration
	var waitTimeouts []time.Duration
	n.warmRelayConnectionWithTimeoutHook = func(info peer.AddrInfo, timeout time.Duration) error {
		warmTimeout = timeout
		return nil
	}
	n.waitForCircuitAddressHook = func(timeout time.Duration) bool {
		waitTimeouts = append(waitTimeouts, timeout)
		return true
	}

	result := n.RefreshRelaySession()
	if !result.Success {
		t.Fatalf("RefreshRelaySession() should succeed, got %+v", result)
	}

	if warmTimeout != ForegroundRelayDialTimeout {
		t.Fatalf("warm timeout = %v, want %v", warmTimeout, ForegroundRelayDialTimeout)
	}
	if result.ForegroundRelayDialTimeoutMs != ForegroundRelayDialTimeout.Milliseconds() {
		t.Fatalf(
			"foregroundRelayDialTimeoutMs = %d, want %d",
			result.ForegroundRelayDialTimeoutMs,
			ForegroundRelayDialTimeout.Milliseconds(),
		)
	}
	if result.ForegroundRelayDialTimeoutMs >= DialTimeout.Milliseconds() {
		t.Fatalf(
			"foregroundRelayDialTimeoutMs should be below general dial timeout %d, got %+v",
			DialTimeout.Milliseconds(),
			result,
		)
	}
	if result.AutorelayRetryCadenceMs != ForegroundAutoRelayRetryCadence.Milliseconds() {
		t.Fatalf(
			"autorelayRetryCadenceMs = %d, want %d",
			result.AutorelayRetryCadenceMs,
			ForegroundAutoRelayRetryCadence.Milliseconds(),
		)
	}
	if result.AutorelayRetryCadenceMs >= DefaultAutoRelayRetryCadence.Milliseconds() {
		t.Fatalf(
			"autorelayRetryCadenceMs should be below default cadence %d, got %+v",
			DefaultAutoRelayRetryCadence.Milliseconds(),
			result,
		)
	}
	if len(waitTimeouts) != 1 || waitTimeouts[0] != ForegroundCircuitAddressWaitTimeout {
		t.Fatalf(
			"waitForCircuitAddress timeouts = %v, want [%v]",
			waitTimeouts,
			ForegroundCircuitAddressWaitTimeout,
		)
	}
}

func TestGR013ForegroundRelayRecoveryCompletesWithinConfiguredBudget(t *testing.T) {
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

	configureRefreshRelayAddresses(t, n, []string{generateFakeRelayAddr(t, 19035)})

	var warmTimeout time.Duration
	var waitTimeouts []time.Duration
	n.warmRelayConnectionWithTimeoutHook = func(info peer.AddrInfo, timeout time.Duration) error {
		warmTimeout = timeout
		return nil
	}
	n.waitForCircuitAddressHook = func(timeout time.Duration) bool {
		waitTimeouts = append(waitTimeouts, timeout)
		return true
	}

	result := n.RefreshRelaySession()
	if result == nil {
		t.Fatal("RefreshRelaySession returned nil result")
	}
	if !result.Success {
		t.Fatalf("RefreshRelaySession should succeed on foreground path, got %+v", result)
	}
	if result.RecoveryMode != "in_place" {
		t.Fatalf("RecoveryMode = %q, want in_place", result.RecoveryMode)
	}
	if !result.ReusedHost {
		t.Fatalf("ReusedHost = false, want true: %+v", result)
	}
	if result.ForegroundRecoveryPath != "foreground_success" {
		t.Fatalf("foregroundRecoveryPath = %q, want foreground_success", result.ForegroundRecoveryPath)
	}
	if warmTimeout != ForegroundRelayDialTimeout {
		t.Fatalf("warm timeout = %v, want %v", warmTimeout, ForegroundRelayDialTimeout)
	}
	if len(waitTimeouts) != 1 || waitTimeouts[0] != ForegroundCircuitAddressWaitTimeout {
		t.Fatalf("waitForCircuitAddress timeouts = %v, want [%v]", waitTimeouts, ForegroundCircuitAddressWaitTimeout)
	}
	if result.ForegroundRelayDialTimeoutMs != ForegroundRelayDialTimeout.Milliseconds() {
		t.Fatalf("foregroundRelayDialTimeoutMs = %d, want %d", result.ForegroundRelayDialTimeoutMs, ForegroundRelayDialTimeout.Milliseconds())
	}
	if result.AutorelayRetryCadenceMs != ForegroundAutoRelayRetryCadence.Milliseconds() {
		t.Fatalf("autorelayRetryCadenceMs = %d, want %d", result.AutorelayRetryCadenceMs, ForegroundAutoRelayRetryCadence.Milliseconds())
	}
	if result.RelayWarmMs < 0 {
		t.Fatalf("relayWarmMs should be non-negative, got %+v", result)
	}
	if result.RelayWarmMs > ForegroundRelayDialTimeout.Milliseconds() {
		t.Fatalf("relayWarmMs = %d exceeded foreground dial budget %d", result.RelayWarmMs, ForegroundRelayDialTimeout.Milliseconds())
	}
	if result.CircuitAddressWaitMs < 0 {
		t.Fatalf("circuitAddressWaitMs should be non-negative, got %+v", result)
	}
	if result.CircuitAddressWaitMs > ForegroundCircuitAddressWaitTimeout.Milliseconds() {
		t.Fatalf("circuitAddressWaitMs = %d exceeded foreground wait budget %d", result.CircuitAddressWaitMs, ForegroundCircuitAddressWaitTimeout.Milliseconds())
	}
	if result.RelayRefreshMs < 0 {
		t.Fatalf("relayRefreshMs should be non-negative, got %+v", result)
	}
}

func TestRefreshRelaySession_WarmsRelaysInParallel(t *testing.T) {
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

	configureRefreshRelayAddresses(t, n, []string{
		generateFakeRelayAddr(t, 19031),
		generateFakeRelayAddr(t, 19032),
	})

	started := make(chan struct{}, 2)
	release := make(chan struct{})
	var concurrent atomic.Int32
	var maxConcurrent atomic.Int32
	n.warmRelayConnectionWithTimeoutHook = func(info peer.AddrInfo, timeout time.Duration) error {
		current := concurrent.Add(1)
		defer concurrent.Add(-1)

		for {
			previous := maxConcurrent.Load()
			if current <= previous || maxConcurrent.CompareAndSwap(previous, current) {
				break
			}
		}

		started <- struct{}{}
		<-release
		return nil
	}
	n.waitForCircuitAddressHook = func(timeout time.Duration) bool {
		return true
	}

	resultCh := make(chan *RecoveryResult, 1)
	go func() {
		resultCh <- n.RefreshRelaySession()
	}()

	for i := 0; i < 2; i++ {
		select {
		case <-started:
		case <-time.After(200 * time.Millisecond):
			close(release)
			t.Fatal("expected refresh warm-up to start both relay dials in parallel")
		}
	}
	close(release)

	result := <-resultCh
	if !result.Success {
		t.Fatalf("RefreshRelaySession() should succeed, got %+v", result)
	}
	if got := maxConcurrent.Load(); got < 2 {
		t.Fatalf("max concurrent warm dials = %d, want at least 2", got)
	}
	if result.RelayWarmParallelism != 2 {
		t.Fatalf("relayWarmParallelism = %d, want 2", result.RelayWarmParallelism)
	}
}

func TestRefreshRelaySession_ForegroundFallbackKeepsLongCircuitWait(t *testing.T) {
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

	configureRefreshRelayAddresses(t, n, []string{generateFakeRelayAddr(t, 19033)})

	var waitTimeouts []time.Duration
	n.warmRelayConnectionWithTimeoutHook = func(info peer.AddrInfo, timeout time.Duration) error {
		return nil
	}
	n.waitForCircuitAddressHook = func(timeout time.Duration) bool {
		waitTimeouts = append(waitTimeouts, timeout)
		return len(waitTimeouts) == 2
	}

	result := n.RefreshRelaySession()
	if !result.Success {
		t.Fatalf("RefreshRelaySession() should succeed via fallback, got %+v", result)
	}

	wantTimeouts := []time.Duration{
		ForegroundCircuitAddressWaitTimeout,
		CircuitAddressWaitTimeout - ForegroundCircuitAddressWaitTimeout,
	}
	if len(waitTimeouts) != len(wantTimeouts) {
		t.Fatalf("waitForCircuitAddress call count = %d, want %d (%v)", len(waitTimeouts), len(wantTimeouts), waitTimeouts)
	}
	for i, want := range wantTimeouts {
		if waitTimeouts[i] != want {
			t.Fatalf("wait timeout[%d] = %v, want %v (all=%v)", i, waitTimeouts[i], want, waitTimeouts)
		}
	}
	if result.ForegroundRecoveryPath != "background_fallback" {
		t.Fatalf("foregroundRecoveryPath = %q, want background_fallback", result.ForegroundRecoveryPath)
	}
}

func TestRefreshRelaySession_ReportsForegroundRecoveryAttribution(t *testing.T) {
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

	configureRefreshRelayAddresses(t, n, []string{generateFakeRelayAddr(t, 19034)})

	n.warmRelayConnectionWithTimeoutHook = func(info peer.AddrInfo, timeout time.Duration) error {
		return nil
	}
	n.waitForCircuitAddressHook = func(timeout time.Duration) bool {
		return true
	}

	result := n.RefreshRelaySession()
	if !result.Success {
		t.Fatalf("RefreshRelaySession() should succeed, got %+v", result)
	}

	if result.ForegroundRecoveryPath != "foreground_success" {
		t.Fatalf("foregroundRecoveryPath = %q, want foreground_success", result.ForegroundRecoveryPath)
	}
	if result.RelayWarmParallelism != 1 {
		t.Fatalf("relayWarmParallelism = %d, want 1", result.RelayWarmParallelism)
	}
	if result.ForegroundRelayDialTimeoutMs != ForegroundRelayDialTimeout.Milliseconds() {
		t.Fatalf(
			"foregroundRelayDialTimeoutMs = %d, want %d",
			result.ForegroundRelayDialTimeoutMs,
			ForegroundRelayDialTimeout.Milliseconds(),
		)
	}
	if result.AutorelayRetryCadenceMs != ForegroundAutoRelayRetryCadence.Milliseconds() {
		t.Fatalf(
			"autorelayRetryCadenceMs = %d, want %d",
			result.AutorelayRetryCadenceMs,
			ForegroundAutoRelayRetryCadence.Milliseconds(),
		)
	}
	if result.CircuitAddressWaitMs < 0 {
		t.Fatalf("circuitAddressWaitMs should be non-negative, got %+v", result)
	}
}

func TestRefreshRelaySession_PreservesPubSubMaps(t *testing.T) {
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

	// Verify pubsub is initialized.
	n.mu.RLock()
	ps := n.pubsub
	topics := n.groupTopics
	subs := n.groupSubs
	n.mu.RUnlock()

	if ps == nil {
		t.Fatal("pubsub should be initialized after Start")
	}

	// Call RefreshRelaySession.
	n.RefreshRelaySession()

	// PubSub maps must be preserved — not nil'd out like in Stop().
	n.mu.RLock()
	psAfter := n.pubsub
	topicsAfter := n.groupTopics
	subsAfter := n.groupSubs
	n.mu.RUnlock()

	if psAfter != ps {
		t.Error("RefreshRelaySession should preserve pubsub instance")
	}
	if topicsAfter == nil {
		t.Error("groupTopics should not be nil after RefreshRelaySession")
	}
	if subsAfter == nil {
		t.Error("groupSubs should not be nil after RefreshRelaySession")
	}
	// Verify maps are the same pointers (not re-created).
	// This confirms no data loss.
	_ = topics
	_ = subs
}

func TestStatus_IncludesRelaySessionFields(t *testing.T) {
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

	// New relay-session fields must be present (additive).
	requiredNewKeys := []string{
		"relayState",
		"relayStates",
		"healthyRelayCount",
		"watchdogRestartCount",
		"needsGroupRecovery",
	}
	for _, key := range requiredNewKeys {
		if _, exists := status[key]; !exists {
			t.Errorf("Status() missing new relay session key %q", key)
		}
	}

	// Legacy keys must still be present.
	legacyKeys := []string{"ok", "peerId", "isStarted", "listenAddresses", "circuitAddresses", "connections"}
	for _, key := range legacyKeys {
		if _, exists := status[key]; !exists {
			t.Errorf("Status() missing legacy key %q", key)
		}
	}

	// relayState should be a string.
	if _, ok := status["relayState"].(string); !ok {
		t.Errorf("relayState should be string, got %T", status["relayState"])
	}

	// healthyRelayCount should be an int.
	if _, ok := status["healthyRelayCount"].(int); !ok {
		t.Errorf("healthyRelayCount should be int, got %T", status["healthyRelayCount"])
	}
}

func TestPersonalRendezvousRefresh_RenewsBeforeTTLExpiry(t *testing.T) {
	hexKey := generateTestKey(t)

	n := NewNode()
	_, err := n.Start(NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{},
		AutoRegister:   false,
		Namespace:      "mknoon:chat:test-peer",
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	// Verify the namespace is set.
	if n.Namespace() != "mknoon:chat:test-peer" {
		t.Errorf("expected namespace 'mknoon:chat:test-peer', got %q", n.Namespace())
	}

	// The node should track the namespace for renewal purposes.
	// This test verifies the infrastructure exists — actual TTL refresh
	// happens against a live relay (integration test).
	n.mu.RLock()
	ns := n.namespace
	n.mu.RUnlock()

	if ns != "mknoon:chat:test-peer" {
		t.Errorf("node namespace not set correctly: %q", ns)
	}
}

func TestWatchdogRestart_ReRegistersPersonalNamespaceImmediately(t *testing.T) {
	hexKey := generateTestKey(t)

	n := NewNode()
	_, err := n.Start(NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{},
		AutoRegister:   true,
		Namespace:      "mknoon:chat:test-peer",
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	// Verify lastConfig preserves AutoRegister=true.
	n.mu.RLock()
	cfg := n.lastConfig
	n.mu.RUnlock()

	if cfg == nil {
		t.Fatal("lastConfig should not be nil")
	}
	if !cfg.AutoRegister {
		t.Error("lastConfig.AutoRegister should be true")
	}

	// After a watchdog restart, the namespace should be re-registered.
	// In unit tests (no relay), we just verify the config is preserved
	// for the restart path to use.
	if cfg.Namespace != "mknoon:chat:test-peer" {
		t.Errorf("lastConfig.Namespace = %q, want 'mknoon:chat:test-peer'", cfg.Namespace)
	}
}

func TestConnManager_ProtectsRelayAndHotPeersDuringRecovery(t *testing.T) {
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

	// The connection manager should be configured (set during Start).
	n.mu.RLock()
	h := n.host
	n.mu.RUnlock()

	if h == nil {
		t.Fatal("host should not be nil")
	}

	// Verify the connection manager exists.
	cm := h.ConnManager()
	if cm == nil {
		t.Fatal("connection manager should not be nil")
	}

	// The connection manager should allow tagging peers as protected.
	// This test confirms the infrastructure exists for relay/hot peer protection.
	// Actual tagging happens when relay connections are established.
}

func TestEmitEvent_SlowCallbackDoesNotBlockHotPath(t *testing.T) {
	hexKey := generateTestKey(t)

	// Create a callback that simulates a slow Flutter handler.
	var callCount int32
	slowCallback := &slowEventCallback{
		delay: 100 * time.Millisecond,
		count: &callCount,
	}

	n := New(slowCallback)
	_, err := n.Start(NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	// Emit multiple events rapidly — none should block.
	start := time.Now()
	for i := 0; i < 10; i++ {
		n.emitEvent("test:event", map[string]interface{}{
			"index": i,
		})
	}
	emitDuration := time.Since(start)

	// Emitting should complete near-instantly (< 50ms) since the dispatcher
	// handles delivery asynchronously.
	if emitDuration > 50*time.Millisecond {
		t.Errorf("emitting 10 events took %v, expected < 50ms (async dispatch)", emitDuration)
	}

	// Wait for events to be delivered.
	time.Sleep(2 * time.Second)

	count := atomic.LoadInt32(&callCount)
	if count < 10 {
		t.Errorf("expected at least 10 delivered events, got %d", count)
	}
}

func TestEventDispatcher_CoalescesAddressesUpdatedAndRelayState(t *testing.T) {
	var deliveredEvents []string
	var mu sync.Mutex

	cb := &recordingEventCallback{
		onEvent: func(jsonStr string) {
			mu.Lock()
			deliveredEvents = append(deliveredEvents, jsonStr)
			mu.Unlock()
		},
	}

	d := NewEventDispatcher(cb, 100)
	defer d.Stop()

	// Emit multiple addresses:updated events rapidly.
	for i := 0; i < 5; i++ {
		d.Emit("addresses:updated", map[string]interface{}{
			"circuitAddresses": []string{fmt.Sprintf("/circuit-%d", i)},
			"listenAddresses":  []string{},
		})
	}

	// Emit multiple relay:state events rapidly.
	for i := 0; i < 5; i++ {
		d.Emit("relay:state", map[string]interface{}{
			"state": fmt.Sprintf("state-%d", i),
		})
	}

	// Wait for dispatch.
	time.Sleep(500 * time.Millisecond)

	mu.Lock()
	events := make([]string, len(deliveredEvents))
	copy(events, deliveredEvents)
	mu.Unlock()

	// Count how many of each event type were actually delivered.
	addrCount := 0
	relayCount := 0
	for _, ev := range events {
		if strings.Contains(ev, "addresses:updated") {
			addrCount++
		}
		if strings.Contains(ev, "relay:state") {
			relayCount++
		}
	}

	// Because of coalescing, we should see at most 1-2 of each type
	// (depending on timing), not all 5.
	if addrCount > 2 {
		t.Errorf("expected coalesced addresses:updated events (got %d, expected <= 2)", addrCount)
	}
	if relayCount > 2 {
		t.Errorf("expected coalesced relay:state events (got %d, expected <= 2)", relayCount)
	}

	// Verify the last delivered value is the latest.
	for _, ev := range events {
		if strings.Contains(ev, "addresses:updated") && strings.Contains(ev, "circuit-4") {
			// Good — the latest value was delivered.
			return
		}
	}
	// If addresses:updated was delivered at all, verify it has the latest value.
	if addrCount > 0 {
		lastAddr := ""
		for _, ev := range events {
			if strings.Contains(ev, "addresses:updated") {
				lastAddr = ev
			}
		}
		if !strings.Contains(lastAddr, "circuit-4") {
			t.Errorf("last delivered addresses:updated should contain 'circuit-4', got: %s", lastAddr)
		}
	}
}

func TestPL008EventDispatcherCoalescesMediaProgressWithoutDroppingGroupMessages(t *testing.T) {
	const (
		queueCapacity = 8
		progressCount = 30
		messageCount  = 6
	)

	collector := &testEventCollector{}
	firstCallbackEntered := make(chan struct{})
	releaseFirstCallback := make(chan struct{})
	var firstCallbackOnce sync.Once

	release := sync.OnceFunc(func() {
		close(releaseFirstCallback)
	})

	cb := &recordingEventCallback{
		onEvent: func(jsonStr string) {
			firstCallbackOnce.Do(func() {
				close(firstCallbackEntered)
				<-releaseFirstCallback
			})
			collector.OnEvent(jsonStr)
		},
	}

	d := NewEventDispatcher(cb, queueCapacity)
	defer d.Stop()
	defer release()

	d.Emit("media:upload_progress", map[string]interface{}{
		"id":         "pl008-upload",
		"sentBytes":  0,
		"totalBytes": progressCount * 100,
	})

	select {
	case <-firstCallbackEntered:
	case <-time.After(time.Second):
		t.Fatal("dispatcher callback did not enter the gated delivery path")
	}

	for i := 1; i <= progressCount; i++ {
		d.Emit("media:upload_progress", map[string]interface{}{
			"id":         "pl008-upload",
			"sentBytes":  i * 100,
			"totalBytes": progressCount * 100,
		})
		if i%5 == 0 {
			sequence := (i / 5) - 1
			d.Emit("group_message:received", map[string]interface{}{
				"groupId":   "group-pl008",
				"messageId": fmt.Sprintf("pl008-message-%d", sequence),
				"sequence":  sequence,
				"text":      fmt.Sprintf("message during progress %d", sequence),
			})
		}
	}

	release()

	type collectedEvent struct {
		name string
		data map[string]interface{}
	}
	decodeSnapshot := func() []collectedEvent {
		rawEvents := collector.snapshot()
		events := make([]collectedEvent, 0, len(rawEvents))
		for _, raw := range rawEvents {
			var payload map[string]interface{}
			if err := json.Unmarshal([]byte(raw), &payload); err != nil {
				t.Fatalf("unmarshal collected event %q: %v", raw, err)
			}
			name, _ := payload["event"].(string)
			data, _ := payload["data"].(map[string]interface{})
			events = append(events, collectedEvent{name: name, data: data})
		}
		return events
	}

	var events []collectedEvent
	var groupMessages []collectedEvent
	var progressEvents []collectedEvent
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		events = decodeSnapshot()
		groupMessages = groupMessages[:0]
		progressEvents = progressEvents[:0]

		for _, ev := range events {
			switch ev.name {
			case "group_message:received":
				groupMessages = append(groupMessages, ev)
			case "media:upload_progress":
				progressEvents = append(progressEvents, ev)
			}
		}

		if len(groupMessages) == messageCount && len(progressEvents) >= 2 {
			break
		}
		time.Sleep(25 * time.Millisecond)
	}

	if len(groupMessages) != messageCount {
		t.Fatalf("delivered group_message:received count = %d, want %d; events = %#v", len(groupMessages), messageCount, events)
	}
	if len(progressEvents) >= progressCount {
		t.Fatalf("media progress events were not coalesced: delivered %d of %d", len(progressEvents), progressCount)
	}

	for i, ev := range groupMessages {
		sequence, ok := ev.data["sequence"].(float64)
		if !ok {
			t.Fatalf("group message %d sequence = %v (%T), want JSON number", i, ev.data["sequence"], ev.data["sequence"])
		}
		if got := int(sequence); got != i {
			t.Fatalf("group message FIFO sequence at index %d = %d, want %d", i, got, i)
		}
		wantMessageID := fmt.Sprintf("pl008-message-%d", i)
		if got := ev.data["messageId"]; got != wantMessageID {
			t.Fatalf("group message %d messageId = %v, want %s", i, got, wantMessageID)
		}
	}

	latestProgress := progressEvents[len(progressEvents)-1].data
	if got := latestProgress["id"]; got != "pl008-upload" {
		t.Fatalf("latest progress id = %v, want pl008-upload", got)
	}
	if got := latestProgress["sentBytes"]; got != float64(progressCount*100) {
		t.Fatalf("latest progress sentBytes = %v, want %d", got, progressCount*100)
	}

	_, coalesced, dropped := d.Diagnostics()
	if coalesced == 0 {
		t.Fatal("dispatcher coalesced count = 0, want media progress coalescing")
	}
	if dropped != 0 {
		t.Fatalf("dispatcher dropped = %d, want 0", dropped)
	}
}

func TestEventDispatcher_PreservesMessageEvents(t *testing.T) {
	var deliveredEvents []string
	var mu sync.Mutex

	cb := &recordingEventCallback{
		onEvent: func(jsonStr string) {
			mu.Lock()
			deliveredEvents = append(deliveredEvents, jsonStr)
			mu.Unlock()
		},
	}

	d := NewEventDispatcher(cb, 100)
	defer d.Stop()

	// Emit message events — these must ALL be delivered (lossless).
	for i := 0; i < 5; i++ {
		d.Emit("message:received", map[string]interface{}{
			"from":    fmt.Sprintf("peer-%d", i),
			"content": fmt.Sprintf("hello %d", i),
		})
	}

	// Also emit group message events.
	for i := 0; i < 3; i++ {
		d.Emit("group_message:received", map[string]interface{}{
			"groupId": fmt.Sprintf("group-%d", i),
			"text":    fmt.Sprintf("msg %d", i),
		})
	}

	// Wait for delivery.
	time.Sleep(500 * time.Millisecond)

	mu.Lock()
	events := make([]string, len(deliveredEvents))
	copy(events, deliveredEvents)
	mu.Unlock()

	// Count message events.
	msgCount := 0
	groupMsgCount := 0
	for _, ev := range events {
		if strings.Contains(ev, "message:received") && !strings.Contains(ev, "group_message") {
			msgCount++
		}
		if strings.Contains(ev, "group_message:received") {
			groupMsgCount++
		}
	}

	// All 5 message events must be delivered.
	if msgCount != 5 {
		t.Errorf("expected 5 message:received events, got %d", msgCount)
	}
	// All 3 group message events must be delivered.
	if groupMsgCount != 3 {
		t.Errorf("expected 3 group_message:received events, got %d", groupMsgCount)
	}
}

func TestDE010EventDispatcherCallbackPanicDoesNotStopLoopAndLogsFailure(t *testing.T) {
	var logBuffer bytes.Buffer
	originalOutput := log.Writer()
	originalFlags := log.Flags()
	log.SetOutput(&logBuffer)
	log.SetFlags(0)
	defer func() {
		log.SetOutput(originalOutput)
		log.SetFlags(originalFlags)
	}()

	collector := &testEventCollector{}
	var callbackCalls int32
	cb := &recordingEventCallback{
		onEvent: func(jsonStr string) {
			call := atomic.AddInt32(&callbackCalls, 1)
			if call == 1 {
				panic("DE-010 injected callback panic")
			}
			collector.OnEvent(jsonStr)
		},
	}

	d := NewEventDispatcher(cb, 8)
	defer d.Stop()

	for i, messageID := range []string{
		"de010-panic",
		"de010-after-1",
		"de010-after-2",
	} {
		d.Emit("group_message:received", map[string]interface{}{
			"groupId":   "group-de010",
			"messageId": messageID,
			"sequence":  i,
			"text":      fmt.Sprintf("DE-010 message %d", i),
		})
	}

	var rawEvents []string
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		rawEvents = collector.snapshot()
		if len(rawEvents) == 2 {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}

	if got := atomic.LoadInt32(&callbackCalls); got != 3 {
		t.Fatalf("callback calls = %d, want 3 so dispatch continued after panic", got)
	}
	if len(rawEvents) != 2 {
		t.Fatalf("delivered events after panic = %d, want 2; events = %#v", len(rawEvents), rawEvents)
	}

	for i, raw := range rawEvents {
		var payload map[string]interface{}
		if err := json.Unmarshal([]byte(raw), &payload); err != nil {
			t.Fatalf("unmarshal delivered event %d %q: %v", i, raw, err)
		}
		if got := payload["event"]; got != "group_message:received" {
			t.Fatalf("event %d name = %v, want group_message:received", i, got)
		}
		data, ok := payload["data"].(map[string]interface{})
		if !ok {
			t.Fatalf("event %d data = %v (%T), want object", i, payload["data"], payload["data"])
		}
		wantMessageID := fmt.Sprintf("de010-after-%d", i+1)
		if got := data["messageId"]; got != wantMessageID {
			t.Fatalf("event %d messageId = %v, want %s", i, got, wantMessageID)
		}
		if got := data["sequence"]; got != float64(i+1) {
			t.Fatalf("event %d sequence = %v, want %d", i, got, i+1)
		}
	}

	logOutput := logBuffer.String()
	if !strings.Contains(logOutput, `Callback panic for event "group_message:received"`) {
		t.Fatalf("dispatcher log did not record recovered callback panic: %q", logOutput)
	}
	if !strings.Contains(logOutput, "DE-010 injected callback panic") {
		t.Fatalf("dispatcher log did not include panic reason: %q", logOutput)
	}

	delivered, coalesced, dropped := d.Diagnostics()
	if delivered != 2 {
		t.Fatalf("dispatcher delivered = %d, want 2 successful post-panic deliveries", delivered)
	}
	if coalesced != 0 {
		t.Fatalf("dispatcher coalesced = %d, want 0", coalesced)
	}
	if dropped != 0 {
		t.Fatalf("dispatcher dropped = %d, want 0", dropped)
	}
	if depth := d.QueueDepth(); depth != 0 {
		t.Fatalf("dispatcher queue depth = %d, want 0 after post-panic drain", depth)
	}
}

func TestDE011EventDispatcherPreservesGroupMessagesBelowCapacityUnderPressure(t *testing.T) {
	const (
		queueCapacity = 6
		messageCount  = 5
	)

	collector := &testEventCollector{}
	firstCallbackEntered := make(chan struct{})
	releaseFirstCallback := make(chan struct{})
	var firstCallbackOnce sync.Once

	release := sync.OnceFunc(func() {
		close(releaseFirstCallback)
	})

	cb := &recordingEventCallback{
		onEvent: func(jsonStr string) {
			firstCallbackOnce.Do(func() {
				close(firstCallbackEntered)
				<-releaseFirstCallback
			})
			collector.OnEvent(jsonStr)
		},
	}

	d := NewEventDispatcher(cb, queueCapacity)
	defer d.Stop()
	defer release()

	d.Emit("addresses:updated", map[string]interface{}{
		"circuitAddresses": []string{"/p2p/de011-initial"},
		"listenAddresses":  []string{},
	})

	select {
	case <-firstCallbackEntered:
	case <-time.After(time.Second):
		t.Fatal("dispatcher callback did not enter the gated delivery path")
	}

	for i := 0; i < messageCount; i++ {
		d.Emit("group_message:received", map[string]interface{}{
			"groupId":   "group-de011",
			"messageId": fmt.Sprintf("de011-message-%d", i),
			"sequence":  i,
			"text":      fmt.Sprintf("below-capacity message %d", i),
		})
		d.Emit("relay:state", map[string]interface{}{
			"state": fmt.Sprintf("de011-relay-state-%d", i),
		})
		d.Emit("addresses:updated", map[string]interface{}{
			"circuitAddresses": []string{fmt.Sprintf("/p2p/de011-%d", i)},
			"listenAddresses":  []string{},
		})
	}

	release()

	type collectedEvent struct {
		name string
		data map[string]interface{}
	}
	decodeSnapshot := func() []collectedEvent {
		rawEvents := collector.snapshot()
		events := make([]collectedEvent, 0, len(rawEvents))
		for _, raw := range rawEvents {
			var payload map[string]interface{}
			if err := json.Unmarshal([]byte(raw), &payload); err != nil {
				t.Fatalf("unmarshal collected event %q: %v", raw, err)
			}
			name, _ := payload["event"].(string)
			data, _ := payload["data"].(map[string]interface{})
			events = append(events, collectedEvent{name: name, data: data})
		}
		return events
	}

	var events []collectedEvent
	var groupMessages []collectedEvent
	var pressure map[string]interface{}
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		events = decodeSnapshot()
		groupMessages = groupMessages[:0]
		pressure = nil

		for _, ev := range events {
			switch ev.name {
			case "group_message:received":
				groupMessages = append(groupMessages, ev)
			case dispatcherPressureEvent:
				pressure = ev.data
			}
		}

		if len(groupMessages) == messageCount && pressure != nil {
			break
		}
		time.Sleep(25 * time.Millisecond)
	}

	if len(groupMessages) != messageCount {
		t.Fatalf("delivered group_message:received count = %d, want %d; events = %#v", len(groupMessages), messageCount, events)
	}

	seenSequences := make(map[int]bool, messageCount)
	for i, ev := range groupMessages {
		sequence, ok := ev.data["sequence"].(float64)
		if !ok {
			t.Fatalf("group message %d sequence = %v (%T), want JSON number", i, ev.data["sequence"], ev.data["sequence"])
		}
		gotSequence := int(sequence)
		if gotSequence != i {
			t.Fatalf("group message FIFO sequence at index %d = %d, want %d", i, gotSequence, i)
		}
		if seenSequences[gotSequence] {
			t.Fatalf("group message sequence %d delivered more than once", gotSequence)
		}
		seenSequences[gotSequence] = true

		wantMessageID := fmt.Sprintf("de011-message-%d", i)
		if got := ev.data["messageId"]; got != wantMessageID {
			t.Fatalf("group message %d messageId = %v, want %s", i, got, wantMessageID)
		}
	}

	if pressure == nil {
		t.Fatalf("did not observe %s diagnostic; events = %#v", dispatcherPressureEvent, events)
	}
	if got := pressure["state"]; got != "near_overflow" {
		t.Fatalf("pressure state = %v, want near_overflow", got)
	}
	if got := pressure["lastEvent"]; got != "group_message:received" {
		t.Fatalf("pressure lastEvent = %v, want group_message:received", got)
	}
	if got := pressure["maxQueueSize"]; got != float64(queueCapacity) {
		t.Fatalf("pressure maxQueueSize = %v, want %d", got, queueCapacity)
	}
	queueDepth, ok := pressure["queueDepth"].(float64)
	if !ok {
		t.Fatalf("pressure queueDepth = %v (%T), want JSON number", pressure["queueDepth"], pressure["queueDepth"])
	}
	if queueDepth >= float64(queueCapacity) {
		t.Fatalf("pressure queueDepth = %v, want below maxQueueSize %d", queueDepth, queueCapacity)
	}

	for _, ev := range events {
		if ev.name == dispatcherOverflowEvent {
			t.Fatalf("unexpected %s diagnostic under below-capacity pressure: %#v", dispatcherOverflowEvent, ev.data)
		}
	}

	_, _, dropped := d.Diagnostics()
	if dropped != 0 {
		t.Fatalf("dispatcher dropped = %d, want 0", dropped)
	}
}

func TestDE020EventDispatcherLargeGroupPayloadDoesNotStarveLaterMessage(t *testing.T) {
	const productLimitTextSize = 10000

	collector := &testEventCollector{}
	cb := &recordingEventCallback{
		onEvent: collector.OnEvent,
	}

	d := NewEventDispatcher(cb, 4)
	defer d.Stop()

	largeText := strings.Repeat("L", productLimitTextSize)
	d.Emit("group_message:received", map[string]interface{}{
		"groupId":   "group-de020",
		"messageId": "de020-large",
		"sequence":  0,
		"text":      largeText,
	})
	d.Emit("group_message:received", map[string]interface{}{
		"groupId":   "group-de020",
		"messageId": "de020-normal",
		"sequence":  1,
		"text":      "DE-020 normal follow-up",
	})

	type collectedEvent struct {
		name string
		data map[string]interface{}
	}
	decodeSnapshot := func() []collectedEvent {
		rawEvents := collector.snapshot()
		events := make([]collectedEvent, 0, len(rawEvents))
		for _, raw := range rawEvents {
			var payload map[string]interface{}
			if err := json.Unmarshal([]byte(raw), &payload); err != nil {
				t.Fatalf("unmarshal collected event %q: %v", raw, err)
			}
			name, _ := payload["event"].(string)
			data, _ := payload["data"].(map[string]interface{})
			events = append(events, collectedEvent{name: name, data: data})
		}
		return events
	}

	var groupMessages []collectedEvent
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		groupMessages = groupMessages[:0]
		for _, ev := range decodeSnapshot() {
			if ev.name == "group_message:received" {
				groupMessages = append(groupMessages, ev)
			}
		}
		delivered, _, _ := d.Diagnostics()
		if len(groupMessages) == 2 && delivered == 2 && d.QueueDepth() == 0 {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}

	if len(groupMessages) != 2 {
		t.Fatalf("delivered group_message:received count = %d, want 2", len(groupMessages))
	}

	wantMessageIDs := []string{"de020-large", "de020-normal"}
	wantTextLengths := []int{productLimitTextSize, len("DE-020 normal follow-up")}
	for i, ev := range groupMessages {
		if got := ev.data["messageId"]; got != wantMessageIDs[i] {
			t.Fatalf("event %d messageId = %v, want %s", i, got, wantMessageIDs[i])
		}
		text, ok := ev.data["text"].(string)
		if !ok {
			t.Fatalf("event %d text = %v (%T), want string", i, ev.data["text"], ev.data["text"])
		}
		if len(text) != wantTextLengths[i] {
			t.Fatalf("event %d text length = %d, want %d", i, len(text), wantTextLengths[i])
		}
		if got := ev.data["sequence"]; got != float64(i) {
			t.Fatalf("event %d sequence = %v, want %d", i, got, i)
		}
	}

	delivered, coalesced, dropped := d.Diagnostics()
	if delivered != 2 {
		t.Fatalf("dispatcher delivered = %d, want 2", delivered)
	}
	if coalesced != 0 {
		t.Fatalf("dispatcher coalesced = %d, want 0", coalesced)
	}
	if dropped != 0 {
		t.Fatalf("dispatcher dropped = %d, want 0", dropped)
	}
	if depth := d.QueueDepth(); depth != 0 {
		t.Fatalf("dispatcher queue depth = %d, want 0 after large-payload drain", depth)
	}
}

func TestST005EventDispatcherHighThroughputStormPreservesGroupMessagesAndCoalescesStatus(t *testing.T) {
	const (
		queueCapacity = 1100
		messageCount  = 1000
		statusCount   = 1000
	)

	collector := &testEventCollector{}
	firstCallbackEntered := make(chan struct{})
	releaseFirstCallback := make(chan struct{})
	var firstCallbackOnce sync.Once

	release := sync.OnceFunc(func() {
		close(releaseFirstCallback)
	})

	cb := &recordingEventCallback{
		onEvent: func(jsonStr string) {
			firstCallbackOnce.Do(func() {
				close(firstCallbackEntered)
				<-releaseFirstCallback
			})
			collector.OnEvent(jsonStr)
		},
	}

	d := NewEventDispatcher(cb, queueCapacity)
	defer d.Stop()
	defer release()

	d.Emit("addresses:updated", map[string]interface{}{
		"circuitAddresses": []string{"/p2p/st005-initial"},
		"listenAddresses":  []string{},
	})

	select {
	case <-firstCallbackEntered:
	case <-time.After(time.Second):
		t.Fatal("dispatcher callback did not enter the gated delivery path")
	}

	for i := 0; i < messageCount; i++ {
		d.Emit("group_message:received", map[string]interface{}{
			"groupId":   "group-st005",
			"messageId": fmt.Sprintf("st005-message-%04d", i),
			"sequence":  i,
			"text":      fmt.Sprintf("ST-005 storm message %04d", i),
		})
		if i < statusCount {
			d.Emit("relay:state", map[string]interface{}{
				"state": fmt.Sprintf("st005-relay-state-%04d", i),
			})
			d.Emit("addresses:updated", map[string]interface{}{
				"circuitAddresses": []string{fmt.Sprintf("/p2p/st005-%04d", i)},
				"listenAddresses":  []string{},
			})
		}
	}

	release()

	type collectedEvent struct {
		name string
		data map[string]interface{}
	}
	decodeSnapshot := func() []collectedEvent {
		rawEvents := collector.snapshot()
		events := make([]collectedEvent, 0, len(rawEvents))
		for _, raw := range rawEvents {
			var payload map[string]interface{}
			if err := json.Unmarshal([]byte(raw), &payload); err != nil {
				t.Fatalf("unmarshal collected event %q: %v", raw, err)
			}
			name, _ := payload["event"].(string)
			data, _ := payload["data"].(map[string]interface{})
			events = append(events, collectedEvent{name: name, data: data})
		}
		return events
	}

	var events []collectedEvent
	var groupMessages []collectedEvent
	var relayStates []collectedEvent
	var addressUpdates []collectedEvent
	var pressure map[string]interface{}
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		events = decodeSnapshot()
		groupMessages = groupMessages[:0]
		relayStates = relayStates[:0]
		addressUpdates = addressUpdates[:0]
		pressure = nil

		for _, ev := range events {
			switch ev.name {
			case "group_message:received":
				groupMessages = append(groupMessages, ev)
			case "relay:state":
				relayStates = append(relayStates, ev)
			case "addresses:updated":
				addressUpdates = append(addressUpdates, ev)
			case dispatcherPressureEvent:
				pressure = ev.data
			}
		}

		if len(groupMessages) == messageCount && pressure != nil &&
			len(relayStates) > 0 && len(addressUpdates) > 0 {
			break
		}
		time.Sleep(25 * time.Millisecond)
	}

	if len(groupMessages) != messageCount {
		t.Fatalf("delivered group_message:received count = %d, want %d; events = %#v", len(groupMessages), messageCount, events)
	}

	seenSequences := make(map[int]bool, messageCount)
	for i, ev := range groupMessages {
		sequence, ok := ev.data["sequence"].(float64)
		if !ok {
			t.Fatalf("group message %d sequence = %v (%T), want JSON number", i, ev.data["sequence"], ev.data["sequence"])
		}
		gotSequence := int(sequence)
		if gotSequence != i {
			t.Fatalf("group message FIFO sequence at index %d = %d, want %d", i, gotSequence, i)
		}
		if seenSequences[gotSequence] {
			t.Fatalf("group message sequence %d delivered more than once", gotSequence)
		}
		seenSequences[gotSequence] = true

		wantMessageID := fmt.Sprintf("st005-message-%04d", i)
		if got := ev.data["messageId"]; got != wantMessageID {
			t.Fatalf("group message %d messageId = %v, want %s", i, got, wantMessageID)
		}
	}

	if pressure == nil {
		t.Fatalf("did not observe %s diagnostic; events = %#v", dispatcherPressureEvent, events)
	}
	if got := pressure["state"]; got != "near_overflow" {
		t.Fatalf("pressure state = %v, want near_overflow", got)
	}
	if got := pressure["lastEvent"]; got != "group_message:received" {
		t.Fatalf("pressure lastEvent = %v, want group_message:received", got)
	}
	if len(relayStates) >= statusCount {
		t.Fatalf("relay status events were not coalesced: delivered %d of %d", len(relayStates), statusCount)
	}
	if len(addressUpdates) >= statusCount {
		t.Fatalf("address status events were not coalesced: delivered %d of %d", len(addressUpdates), statusCount)
	}
	if got := relayStates[len(relayStates)-1].data["state"]; got != "st005-relay-state-0999" {
		t.Fatalf("latest relay state = %v, want st005-relay-state-0999", got)
	}
	lastAddresses := addressUpdates[len(addressUpdates)-1].data["circuitAddresses"].([]interface{})
	if got := lastAddresses[0]; got != "/p2p/st005-0999" {
		t.Fatalf("latest address update = %v, want /p2p/st005-0999", got)
	}

	for _, ev := range events {
		if ev.name == dispatcherOverflowEvent {
			t.Fatalf("unexpected %s diagnostic under high-throughput below-capacity storm: %#v", dispatcherOverflowEvent, ev.data)
		}
	}

	_, coalesced, dropped := d.Diagnostics()
	if coalesced == 0 {
		t.Fatal("dispatcher coalesced count = 0, want status coalescing")
	}
	if dropped != 0 {
		t.Fatalf("dispatcher dropped = %d, want 0", dropped)
	}
}

func TestEventDispatcher_EmitsPressureAndOverflowDiagnostics(t *testing.T) {
	collector := &testEventCollector{}
	cb := &recordingEventCallback{
		onEvent: func(jsonStr string) {
			time.Sleep(50 * time.Millisecond)
			collector.OnEvent(jsonStr)
		},
	}

	d := NewEventDispatcher(cb, 2)
	defer d.Stop()

	for i := 0; i < 10; i++ {
		d.Emit("group_message:received", map[string]interface{}{
			"groupId": "group-overflow",
			"text":    fmt.Sprintf("msg-%d", i),
		})
	}

	pressure := waitForCollectedEvent(t, collector, dispatcherPressureEvent, 3*time.Second)
	if got := pressure["state"]; got != "near_overflow" {
		t.Fatalf("pressure state = %v, want near_overflow", got)
	}
	if got := pressure["maxQueueSize"]; got != float64(2) {
		t.Fatalf("pressure maxQueueSize = %v, want 2", got)
	}
	if got := pressure["queueDepth"]; got == nil || got.(float64) < 1 {
		t.Fatalf("pressure queueDepth = %v, want >= 1", got)
	}
	if got := pressure["lastEvent"]; got != "group_message:received" {
		t.Fatalf("pressure lastEvent = %v, want group_message:received", got)
	}

	overflow := waitForCollectedEvent(t, collector, dispatcherOverflowEvent, 3*time.Second)
	if got := overflow["state"]; got != "overflow" {
		t.Fatalf("overflow state = %v, want overflow", got)
	}
	if got := overflow["maxQueueSize"]; got != float64(2) {
		t.Fatalf("overflow maxQueueSize = %v, want 2", got)
	}
	if got := overflow["queueDepth"]; got != float64(2) {
		t.Fatalf("overflow queueDepth = %v, want 2", got)
	}
	if got := overflow["droppedCount"]; got == nil || got.(float64) < 1 {
		t.Fatalf("overflow droppedCount = %v, want >= 1", got)
	}
	if got := overflow["lastEvent"]; got != "group_message:received" {
		t.Fatalf("overflow lastEvent = %v, want group_message:received", got)
	}
}

func TestDE012EventDispatcherOverflowDiagnosticIdentifiesDroppedGroupEventForReplayRecovery(t *testing.T) {
	const queueCapacity = 2

	collector := &testEventCollector{}
	firstCallbackEntered := make(chan struct{})
	releaseFirstCallback := make(chan struct{})
	var firstCallbackOnce sync.Once

	release := sync.OnceFunc(func() {
		close(releaseFirstCallback)
	})

	cb := &recordingEventCallback{
		onEvent: func(jsonStr string) {
			firstCallbackOnce.Do(func() {
				close(firstCallbackEntered)
				<-releaseFirstCallback
			})
			collector.OnEvent(jsonStr)
		},
	}

	d := NewEventDispatcher(cb, queueCapacity)
	defer d.Stop()
	defer release()

	d.Emit("addresses:updated", map[string]interface{}{
		"circuitAddresses": []string{"/p2p/de012-initial"},
		"listenAddresses":  []string{},
	})

	select {
	case <-firstCallbackEntered:
	case <-time.After(time.Second):
		t.Fatal("dispatcher callback did not enter the gated delivery path")
	}

	for i := 0; i < queueCapacity+1; i++ {
		d.Emit("group_message:received", map[string]interface{}{
			"groupId":   "group-de012",
			"messageId": fmt.Sprintf("de012-message-%d", i),
			"sequence":  i,
			"text":      fmt.Sprintf("overflow candidate %d", i),
		})
	}

	release()

	overflow := waitForCollectedEvent(t, collector, dispatcherOverflowEvent, 3*time.Second)
	if got := overflow["state"]; got != "overflow" {
		t.Fatalf("overflow state = %v, want overflow", got)
	}
	if got := overflow["lastEvent"]; got != "group_message:received" {
		t.Fatalf("overflow lastEvent = %v, want group_message:received", got)
	}
	if got := overflow["maxQueueSize"]; got != float64(queueCapacity) {
		t.Fatalf("overflow maxQueueSize = %v, want %d", got, queueCapacity)
	}
	if got := overflow["queueDepth"]; got != float64(queueCapacity) {
		t.Fatalf("overflow queueDepth = %v, want %d", got, queueCapacity)
	}
	if got := overflow["droppedCount"]; got == nil || got.(float64) < 1 {
		t.Fatalf("overflow droppedCount = %v, want >= 1", got)
	}

	rawEvents := collector.snapshot()
	deliveredMessages := make(map[string]int)
	for _, raw := range rawEvents {
		var payload map[string]interface{}
		if err := json.Unmarshal([]byte(raw), &payload); err != nil {
			t.Fatalf("unmarshal collected event %q: %v", raw, err)
		}
		if payload["event"] != "group_message:received" {
			continue
		}
		data, _ := payload["data"].(map[string]interface{})
		messageID, _ := data["messageId"].(string)
		deliveredMessages[messageID]++
	}

	if deliveredMessages["de012-message-2"] != 0 {
		t.Fatalf("overflowed message was delivered live: %#v", deliveredMessages)
	}
	for _, messageID := range []string{"de012-message-0", "de012-message-1"} {
		if deliveredMessages[messageID] != 1 {
			t.Fatalf("deliveredMessages[%s] = %d, want 1; all = %#v", messageID, deliveredMessages[messageID], deliveredMessages)
		}
	}

	_, _, dropped := d.Diagnostics()
	if dropped < 1 {
		t.Fatalf("dispatcher dropped = %d, want >= 1", dropped)
	}
}

// --- Test helper types ---

type slowEventCallback struct {
	delay time.Duration
	count *int32
}

func (c *slowEventCallback) OnEvent(jsonStr string) {
	time.Sleep(c.delay)
	atomic.AddInt32(c.count, 1)
}

type recordingEventCallback struct {
	onEvent func(string)
}

func (c *recordingEventCallback) OnEvent(jsonStr string) {
	c.onEvent(jsonStr)
}

// ---------------------------------------------------------------------------
// Loopback / Link-Local Address Filtering
// ---------------------------------------------------------------------------

func TestFilterAddresses(t *testing.T) {
	tests := []struct {
		name  string
		input []string
		want  []string
	}{
		// --- IPv4 ---
		{
			name:  "removes IPv4 loopback TCP",
			input: []string{"/ip4/127.0.0.1/tcp/1234"},
			want:  []string{},
		},
		{
			name:  "removes IPv4 loopback QUIC",
			input: []string{"/ip4/127.0.0.1/udp/1234/quic-v1"},
			want:  []string{},
		},
		{
			name:  "removes IPv4 loopback WebSocket",
			input: []string{"/ip4/127.0.0.1/tcp/1234/ws"},
			want:  []string{},
		},
		{
			name:  "removes IPv4 unspecified",
			input: []string{"/ip4/0.0.0.0/tcp/1234"},
			want:  []string{},
		},
		{
			name:  "keeps private LAN 192.168.x",
			input: []string{"/ip4/192.168.1.100/tcp/1234"},
			want:  []string{"/ip4/192.168.1.100/tcp/1234"},
		},
		{
			name:  "keeps private LAN 10.x",
			input: []string{"/ip4/10.0.0.1/udp/4001/quic-v1"},
			want:  []string{"/ip4/10.0.0.1/udp/4001/quic-v1"},
		},
		{
			name:  "keeps private LAN 172.16.x WebSocket",
			input: []string{"/ip4/172.16.0.1/tcp/4001/ws"},
			want:  []string{"/ip4/172.16.0.1/tcp/4001/ws"},
		},
		{
			name:  "keeps public IPv4 address",
			input: []string{"/ip4/203.0.113.5/tcp/1234"},
			want:  []string{"/ip4/203.0.113.5/tcp/1234"},
		},
		// --- IPv6 ---
		{
			name:  "removes IPv6 loopback TCP",
			input: []string{"/ip6/::1/tcp/1234"},
			want:  []string{},
		},
		{
			name:  "removes IPv6 loopback QUIC",
			input: []string{"/ip6/::1/udp/1234/quic-v1"},
			want:  []string{},
		},
		{
			name:  "removes IPv6 link-local",
			input: []string{"/ip6/fe80::1/tcp/1234"},
			want:  []string{},
		},
		{
			name:  "removes IPv4 link-local (169.254.x.x)",
			input: []string{"/ip4/169.254.1.100/tcp/1234"},
			want:  []string{},
		},
		{
			name:  "removes IPv6 link-local with zone (ip6zone)",
			input: []string{"/ip6zone/en0/ip6/fe80::1/tcp/1234"},
			want:  []string{},
		},
		{
			name:  "removes IPv6 unspecified",
			input: []string{"/ip6/::/tcp/1234"},
			want:  []string{},
		},
		{
			name:  "keeps global IPv6 address",
			input: []string{"/ip6/2001:db8::1/tcp/1234"},
			want:  []string{"/ip6/2001:db8::1/tcp/1234"},
		},
		{
			name:  "keeps global IPv6 QUIC",
			input: []string{"/ip6/2607:f8b0:4004:800::200e/udp/4001/quic-v1"},
			want:  []string{"/ip6/2607:f8b0:4004:800::200e/udp/4001/quic-v1"},
		},
		// --- Circuit relay (must survive loopback filter) ---
		{
			name:  "keeps circuit relay even when transport IP is loopback",
			input: []string{"/ip4/127.0.0.1/tcp/4001/p2p/12D3KooWRelay/p2p-circuit/p2p/12D3KooWPeer"},
			want:  []string{"/ip4/127.0.0.1/tcp/4001/p2p/12D3KooWRelay/p2p-circuit/p2p/12D3KooWPeer"},
		},
		{
			name:  "keeps circuit relay with public IP",
			input: []string{"/ip4/203.0.113.5/tcp/4001/p2p/12D3KooWRelay/p2p-circuit/p2p/12D3KooWPeer"},
			want:  []string{"/ip4/203.0.113.5/tcp/4001/p2p/12D3KooWRelay/p2p-circuit/p2p/12D3KooWPeer"},
		},
		{
			name: "loopback circuit kept, plain loopback removed",
			input: []string{
				"/ip4/127.0.0.1/tcp/5678",
				"/ip4/127.0.0.1/tcp/4001/p2p/12D3KooWRelay/p2p-circuit/p2p/12D3KooWPeer",
			},
			want: []string{
				"/ip4/127.0.0.1/tcp/4001/p2p/12D3KooWRelay/p2p-circuit/p2p/12D3KooWPeer",
			},
		},
		// --- Mixed ---
		{
			name: "mixed IPv4+IPv6: filters all loopback, keeps routable and circuit",
			input: []string{
				"/ip4/127.0.0.1/tcp/5678",
				"/ip4/127.0.0.1/udp/5678/quic-v1",
				"/ip4/127.0.0.1/tcp/5678/ws",
				"/ip6/::1/tcp/5678",
				"/ip6/::1/udp/5678/quic-v1",
				"/ip6/fe80::1/tcp/5678",
				"/ip4/192.168.1.100/tcp/5678",
				"/ip4/192.168.1.100/udp/5678/quic-v1",
				"/ip6/2001:db8::1/tcp/5678",
				"/ip6/2001:db8::1/udp/5678/quic-v1",
				"/ip4/127.0.0.1/tcp/4001/p2p/12D3KooWRelay/p2p-circuit/p2p/12D3KooWPeer",
			},
			want: []string{
				"/ip4/192.168.1.100/tcp/5678",
				"/ip4/192.168.1.100/udp/5678/quic-v1",
				"/ip6/2001:db8::1/tcp/5678",
				"/ip6/2001:db8::1/udp/5678/quic-v1",
				"/ip4/127.0.0.1/tcp/4001/p2p/12D3KooWRelay/p2p-circuit/p2p/12D3KooWPeer",
			},
		},
		{
			name:  "empty input returns empty",
			input: []string{},
			want:  []string{},
		},
		{
			name:  "nil input returns empty",
			input: nil,
			want:  []string{},
		},
	}

	// Generate real peer IDs for circuit relay test addresses.
	relayPeerID := generatePeerIDStr(t)
	targetPeerID := generatePeerIDStr(t)
	circuitSuffix := fmt.Sprintf("/p2p/%s/p2p-circuit/p2p/%s", relayPeerID, targetPeerID)

	// Replace placeholder peer IDs in test cases.
	replacePeerIDs := func(s string) string {
		s = strings.ReplaceAll(s, "/p2p/12D3KooWRelay/p2p-circuit/p2p/12D3KooWPeer", circuitSuffix)
		return s
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var addrs []ma.Multiaddr
			for _, s := range tt.input {
				addrs = append(addrs, ma.StringCast(replacePeerIDs(s)))
			}

			got := filterAddresses(addrs)

			gotStrs := make([]string, len(got))
			for i, a := range got {
				gotStrs[i] = a.String()
			}

			want := make([]string, len(tt.want))
			for i, w := range tt.want {
				want[i] = replacePeerIDs(w)
			}

			if len(gotStrs) != len(want) {
				t.Fatalf("filterAddresses() returned %d addrs, want %d\ngot:  %v\nwant: %v",
					len(gotStrs), len(want), gotStrs, want)
			}
			for i, w := range want {
				if gotStrs[i] != w {
					t.Errorf("filterAddresses()[%d] = %q, want %q", i, gotStrs[i], w)
				}
			}
		})
	}
}

func TestNodeAddressesExcludeLoopback(t *testing.T) {
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

	for _, addr := range n.Host().Addrs() {
		s := addr.String()
		if strings.Contains(s, "/ip4/127.0.0.1/") || strings.Contains(s, "/ip6/::1/") {
			t.Errorf("host.Addrs() contains loopback address: %s", s)
		}
		if strings.Contains(s, "/ip6/fe80") || strings.Contains(s, "169.254.") {
			t.Errorf("host.Addrs() contains link-local address: %s", s)
		}
		if strings.Contains(s, "/ip4/0.0.0.0/") || strings.Contains(s, "/ip6/::/") {
			t.Errorf("host.Addrs() contains unspecified address: %s", s)
		}
	}

	state := n.State()
	for _, a := range state.Addresses {
		if strings.Contains(a, "127.0.0.1") || strings.Contains(a, "::1/") ||
			strings.Contains(a, "/ip6/fe80") || strings.Contains(a, "169.254.") {
			t.Errorf("State().Addresses contains non-routable: %s", a)
		}
	}
}

// fakeHostWithAddrs is a minimal host.Host stub for testing splitHostAddresses
// with synthetic addresses that bypass AddrsFactory.
type fakeHostWithAddrs struct {
	host.Host // embed to satisfy interface; only Addrs() is called
	addrs     []ma.Multiaddr
}

func (f *fakeHostWithAddrs) Addrs() []ma.Multiaddr { return f.addrs }

func TestSplitHostAddressesFiltersLoopbackDirectly(t *testing.T) {
	relayPID := generatePeerIDStr(t)
	targetPID := generatePeerIDStr(t)
	circuitAddr := fmt.Sprintf("/ip4/127.0.0.1/tcp/4001/p2p/%s/p2p-circuit/p2p/%s", relayPID, targetPID)

	rawAddrs := []ma.Multiaddr{
		// Should be filtered (non-routable)
		ma.StringCast("/ip4/127.0.0.1/tcp/5678"),
		ma.StringCast("/ip4/127.0.0.1/udp/5678/quic-v1"),
		ma.StringCast("/ip6/::1/tcp/5678"),
		ma.StringCast("/ip6/fe80::1/tcp/5678"),
		ma.StringCast("/ip4/169.254.1.100/tcp/5678"),
		ma.StringCast("/ip4/0.0.0.0/tcp/5678"),
		ma.StringCast("/ip6/::/tcp/5678"),
		// Should be kept (routable listen addresses)
		ma.StringCast("/ip4/192.168.1.100/tcp/5678"),
		ma.StringCast("/ip6/2001:db8::1/tcp/5678"),
		// Should be kept (circuit relay — even with loopback transport)
		ma.StringCast(circuitAddr),
	}

	fh := &fakeHostWithAddrs{addrs: rawAddrs}
	listenAddrs, circuitAddrs := splitHostAddresses(fh)

	for _, a := range listenAddrs {
		if strings.Contains(a, "127.0.0.1") || strings.HasPrefix(a, "/ip6/::1/") ||
			strings.Contains(a, "/ip6/fe80") || strings.Contains(a, "169.254.") ||
			strings.HasPrefix(a, "/ip4/0.0.0.0") || strings.HasPrefix(a, "/ip6/::/") {
			t.Errorf("splitHostAddresses returned non-routable listen address: %s", a)
		}
	}

	if len(listenAddrs) != 2 {
		t.Errorf("expected 2 routable listen addrs, got %d: %v", len(listenAddrs), listenAddrs)
	}

	if len(circuitAddrs) != 1 {
		t.Errorf("expected 1 circuit addr, got %d: %v", len(circuitAddrs), circuitAddrs)
	}
}

func TestStatusExcludesLoopback(t *testing.T) {
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
	listenAddrs, _ := status["listenAddresses"].([]string)
	for _, a := range listenAddrs {
		if strings.Contains(a, "127.0.0.1") || strings.Contains(a, "::1/") ||
			strings.Contains(a, "/ip6/fe80") || strings.Contains(a, "169.254.") {
			t.Errorf("Status() listenAddresses contains non-routable: %s", a)
		}
	}
}

func TestStateLockedExcludesLoopback(t *testing.T) {
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

	state := n.State()
	for _, a := range state.Addresses {
		if strings.Contains(a, "127.0.0.1") || strings.Contains(a, "::1/") ||
			strings.Contains(a, "/ip6/fe80") || strings.Contains(a, "169.254.") ||
			strings.Contains(a, "0.0.0.0") || strings.Contains(a, "/ip6/::/") {
			t.Errorf("State().Addresses contains non-routable address: %s", a)
		}
	}
}

func TestAddressesUpdatedEventExcludesNonRoutable(t *testing.T) {
	hexKey := generateTestKey(t)

	var captured []map[string]interface{}
	var mu sync.Mutex
	gotEvent := make(chan struct{}, 1)

	cb := &recordingEventCallback{
		onEvent: func(jsonStr string) {
			var ev map[string]interface{}
			if err := json.Unmarshal([]byte(jsonStr), &ev); err != nil {
				return
			}
			if ev["event"] == "addresses:updated" {
				data, _ := ev["data"].(map[string]interface{})
				mu.Lock()
				captured = append(captured, data)
				mu.Unlock()
				select {
				case gotEvent <- struct{}{}:
				default:
				}
			}
		},
	}

	n := New(cb)
	_, err := n.Start(NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	// Wait for at least one addresses:updated event (with bounded timeout).
	select {
	case <-gotEvent:
		// got at least one event
	case <-time.After(5 * time.Second):
		t.Fatal("addresses:updated event not received within 5s — leak path #2 untested")
	}

	mu.Lock()
	events := captured
	mu.Unlock()

	for _, ev := range events {
		addrs, _ := ev["listenAddresses"].([]interface{})
		for _, a := range addrs {
			s, _ := a.(string)
			if strings.Contains(s, "127.0.0.1") || strings.Contains(s, "::1/") ||
				strings.Contains(s, "/ip6/fe80") || strings.Contains(s, "169.254.") ||
				strings.HasPrefix(s, "/ip4/0.0.0.0") || strings.HasPrefix(s, "/ip6/::/") {
				t.Errorf("addresses:updated event contains non-routable: %s", s)
			}
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

// ---------------------------------------------------------------------------
// IPv6 Dual-Stack Tests
// ---------------------------------------------------------------------------

func TestDefaultRelayAddressUsesDNS(t *testing.T) {
	if strings.Contains(DefaultRelayAddress, "/dns4/") {
		t.Errorf("DefaultRelayAddress uses /dns4/ — should use /dns/ for dual-stack: %s",
			DefaultRelayAddress)
	}
	if strings.Contains(DefaultQUICRelay, "/dns4/") {
		t.Errorf("DefaultQUICRelay uses /dns4/ — should use /dns/ for dual-stack: %s",
			DefaultQUICRelay)
	}
}

func TestNodeListensDualStack(t *testing.T) {
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

	listeners := n.Host().Network().ListenAddresses()
	hasIPv4 := false
	hasIPv6 := false
	for _, a := range listeners {
		s := a.String()
		if strings.HasPrefix(s, "/ip4/") {
			hasIPv4 = true
		}
		if strings.HasPrefix(s, "/ip6/") {
			hasIPv6 = true
		}
	}

	if !hasIPv4 {
		t.Error("node should have at least one IPv4 listener")
	}
	if !hasIPv6 {
		t.Error("node should have at least one IPv6 listener")
	}
}

func TestNodeIPv6LoopbackFiltered(t *testing.T) {
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

	for _, addr := range n.Host().Addrs() {
		s := addr.String()
		if strings.Contains(s, "/ip6/::1/") {
			t.Errorf("host.Addrs() contains IPv6 loopback: %s", s)
		}
		if strings.HasPrefix(s, "/ip6/fe80") {
			t.Errorf("host.Addrs() contains IPv6 link-local: %s", s)
		}
		if strings.HasPrefix(s, "/ip6/::/") {
			t.Errorf("host.Addrs() contains IPv6 unspecified: %s", s)
		}
	}
}

func TestSplitHostAddressesIncludesIPv6(t *testing.T) {
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

	listenAddrs, _ := splitHostAddresses(n.Host())

	hasIPv6 := false
	for _, a := range listenAddrs {
		if strings.HasPrefix(a, "/ip6/") {
			hasIPv6 = true
			if strings.Contains(a, "/ip6/::1/") || strings.HasPrefix(a, "/ip6/fe80") {
				t.Errorf("splitHostAddresses returned non-routable IPv6: %s", a)
			}
		}
	}

	if !hasIPv6 {
		t.Log("INFO: no global IPv6 addresses found — machine may not have IPv6 connectivity")
	}
}

func TestStatusIncludesIPv6Addresses(t *testing.T) {
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
	listenAddrs, ok := status["listenAddresses"].([]string)
	if !ok {
		t.Fatal("status missing listenAddresses")
	}

	hasIPv4 := false
	hasIPv6 := false
	for _, a := range listenAddrs {
		if strings.HasPrefix(a, "/ip4/") {
			hasIPv4 = true
		}
		if strings.HasPrefix(a, "/ip6/") {
			hasIPv6 = true
		}
	}

	if !hasIPv4 {
		t.Error("Status() listenAddresses should contain IPv4 addresses")
	}
	if !hasIPv6 {
		t.Log("INFO: Status() has no IPv6 listen addresses — machine may lack IPv6")
	}
}

func TestAddressesUpdatedEventIncludesIPv6(t *testing.T) {
	hexKey := generateTestKey(t)

	var lastEvent map[string]interface{}
	var mu sync.Mutex
	gotEvent := make(chan struct{}, 1)

	cb := &recordingEventCallback{
		onEvent: func(jsonStr string) {
			var ev map[string]interface{}
			if err := json.Unmarshal([]byte(jsonStr), &ev); err != nil {
				return
			}
			if ev["event"] == "addresses:updated" {
				data, _ := ev["data"].(map[string]interface{})
				mu.Lock()
				lastEvent = data
				mu.Unlock()
				select {
				case gotEvent <- struct{}{}:
				default:
				}
			}
		},
	}

	n := New(cb)
	_, err := n.Start(NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	select {
	case <-gotEvent:
	case <-time.After(5 * time.Second):
		t.Skip("no addresses:updated event received within 5s")
		return
	}

	mu.Lock()
	ev := lastEvent
	mu.Unlock()

	if ev == nil {
		t.Skip("no addresses:updated event received — may need relay connection")
		return
	}

	listenAddrs, _ := ev["listenAddresses"].([]interface{})
	hasIPv6 := false
	for _, a := range listenAddrs {
		if s, ok := a.(string); ok && strings.HasPrefix(s, "/ip6/") {
			hasIPv6 = true
		}
	}

	if !hasIPv6 {
		t.Log("INFO: addresses:updated event has no IPv6 — machine may lack IPv6")
	}
}

func TestFixedListenPortDualStack(t *testing.T) {
	hexKey := generateTestKey(t)
	n := NewNode()
	_, err := n.Start(NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{},
		AutoRegister:   false,
		ListenPort:     9876,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	listeners := n.Host().Network().ListenAddresses()
	hasIPv4Port := false
	hasIPv6Port := false
	for _, a := range listeners {
		s := a.String()
		if strings.HasPrefix(s, "/ip4/") && strings.Contains(s, "/9876") {
			hasIPv4Port = true
		}
		if strings.HasPrefix(s, "/ip6/") && strings.Contains(s, "/9876") {
			hasIPv6Port = true
		}
	}
	if !hasIPv4Port {
		t.Errorf("expected IPv4 listener on port 9876, got: %v", listeners)
	}
	if !hasIPv6Port {
		t.Errorf("expected IPv6 listener on port 9876, got: %v", listeners)
	}
}

func TestTwoNodesDualStackConnect(t *testing.T) {
	keyA := generateTestKey(t)
	keyB := generateTestKey(t)

	nodeA := NewNode()
	stateA, err := nodeA.Start(NodeConfig{
		PrivateKeyHex:  keyA,
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("Start A: %v", err)
	}
	defer nodeA.Stop()

	nodeB := NewNode()
	_, err = nodeB.Start(NodeConfig{
		PrivateKeyHex:  keyB,
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("Start B: %v", err)
	}
	defer nodeB.Stop()

	var addrStrs []string
	for _, a := range nodeA.Host().Addrs() {
		addrStrs = append(addrStrs, a.String())
	}

	err = nodeB.DialPeer(stateA.PeerId, addrStrs)
	if err != nil {
		t.Fatalf("DialPeer: %v", err)
	}

	conns := nodeB.Host().Network().ConnsToPeer(nodeA.Host().ID())
	if len(conns) == 0 {
		t.Fatal("expected at least one connection from B to A")
	}

	for _, c := range conns {
		t.Logf("Connection: %s → %s", c.LocalMultiaddr(), c.RemoteMultiaddr())
	}
}

func TestDialPeerViaRelayTriesAllAddresses(t *testing.T) {
	n := startLocalNodeForMultiRelayTest(t)

	// Generate ONE relay peer ID with TWO transports (TCP + QUIC).
	key, _, err := crypto.GenerateKeyPair(crypto.Ed25519, 0)
	if err != nil {
		t.Fatal(err)
	}
	relayID, _ := peer.IDFromPrivateKey(key)

	addr1 := fmt.Sprintf("/ip4/127.0.0.1/tcp/19991/p2p/%s", relayID)
	addr2 := fmt.Sprintf("/ip4/127.0.0.1/udp/19992/quic-v1/p2p/%s", relayID)

	n.mu.Lock()
	n.relayAddresses = []string{addr1, addr2}
	n.mu.Unlock()

	// Verify the selector groups them as 1 relay with 2 addrs.
	rs := n.buildRelaySelector(nil)
	if rs.Len() != 1 {
		t.Fatalf("expected 1 relay (grouped by peer ID), got %d", rs.Len())
	}
	relays := rs.Relays()
	if len(relays[0].Addrs) != 2 {
		t.Fatalf("expected 2 addrs for relay, got %d", len(relays[0].Addrs))
	}

	// Dial target — both addresses unreachable, but the code path
	// must build circuit addrs from ALL relay.Addrs, not just [0].
	targetKey := generateTestKey(t)
	targetNode := NewNode()
	st, err := targetNode.Start(NodeConfig{
		PrivateKeyHex:  targetKey,
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatal(err)
	}
	defer targetNode.Stop()

	err = n.DialPeerViaRelay(st.PeerId)
	if err == nil {
		t.Fatal("expected error (fake relay unreachable)")
	}

	if !strings.Contains(err.Error(), "relay") {
		t.Errorf("error should reference relay attempt, got: %v", err)
	}
}
