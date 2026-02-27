package node

import (
	"crypto/rand"
	"encoding/hex"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p/core/crypto"
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

func TestWaitForCircuitAddress_NoRelay(t *testing.T) {
	hexKey := generateTestKey(t)

	n := NewNode()
	_, err := n.Start(NodeConfig{
		PrivateKeyHex: hexKey,
		// Use an unreachable relay (RFC 5737 TEST-NET) so no circuit address appears.
		RelayAddresses: []string{
			"/ip4/192.0.2.99/tcp/4001/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g",
		},
		AutoRegister: false,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	// With an unreachable relay, waitForCircuitAddress should time out and return false.
	start := time.Now()
	got := n.waitForCircuitAddress(2 * time.Second)
	elapsed := time.Since(start)

	if got {
		t.Error("waitForCircuitAddress should return false with unreachable relay")
	}
	if elapsed < 2*time.Second {
		t.Errorf("expected to wait at least 2s, waited %v", elapsed)
	}
}

func TestConcurrentRelayConnect(t *testing.T) {
	hexKey := generateTestKey(t)

	// Use two unreachable addresses (RFC 5737 TEST-NET).
	// With concurrent dialing both should fail in parallel, not sequentially.
	n := NewNode()
	start := time.Now()
	_, err := n.Start(NodeConfig{
		PrivateKeyHex: hexKey,
		RelayAddresses: []string{
			"/ip4/192.0.2.1/tcp/4001/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g",
			"/ip4/192.0.2.2/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g",
		},
		AutoRegister: false,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	// WaitForRelayConnection should time out since both addresses are unreachable.
	relayErr := n.WaitForRelayConnection(5 * time.Second)
	elapsed := time.Since(start)

	if relayErr == nil {
		t.Error("expected relay connection to fail with unreachable addresses")
	}

	// Concurrent dial: total time should be less than 2 * DialTimeout (60s).
	// With a 5s wait timeout, we mainly verify it doesn't hang for 60s+.
	if elapsed > 40*time.Second {
		t.Errorf("expected concurrent relay connect, but took %v (sequential would be ~60s)", elapsed)
	}
	t.Logf("concurrent relay connect completed in %v", elapsed)
}

func TestReconnectRelaysPreservesAutoRegister(t *testing.T) {
	hexKey := generateTestKey(t)

	n := NewNode()
	_, err := n.Start(NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{},
		AutoRegister:   true,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	// Verify AutoRegister was saved
	n.mu.RLock()
	if !n.lastConfig.AutoRegister {
		t.Fatal("lastConfig.AutoRegister should be true after Start")
	}
	n.mu.RUnlock()

	// ReconnectRelays temporarily sets AutoRegister=false for the restart,
	// but must restore the original value so future recoveries preserve it.
	if err := n.ReconnectRelays(); err != nil {
		t.Fatalf("ReconnectRelays: %v", err)
	}

	n.mu.RLock()
	autoReg := n.lastConfig.AutoRegister
	n.mu.RUnlock()

	if !autoReg {
		t.Error("lastConfig.AutoRegister should be true after ReconnectRelays, got false")
	}
}

func TestReconnectRelaysPreservesAutoRegisterMultipleCycles(t *testing.T) {
	hexKey := generateTestKey(t)

	n := NewNode()
	_, err := n.Start(NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{},
		AutoRegister:   true,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	for cycle := 1; cycle <= 3; cycle++ {
		if err := n.ReconnectRelays(); err != nil {
			t.Fatalf("ReconnectRelays cycle %d: %v", cycle, err)
		}

		n.mu.RLock()
		autoReg := n.lastConfig.AutoRegister
		n.mu.RUnlock()

		if !autoReg {
			t.Errorf("cycle %d: lastConfig.AutoRegister should be true, got false", cycle)
		}
	}
}

func TestRelayReadyChannelNotClosedOnFailure(t *testing.T) {
	hexKey := generateTestKey(t)

	n := NewNode()
	_, err := n.Start(NodeConfig{
		PrivateKeyHex: hexKey,
		RelayAddresses: []string{
			"/ip4/192.0.2.1/tcp/4001/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g",
		},
		AutoRegister: false,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	// relayReady should NOT be closed since the relay is unreachable.
	select {
	case <-n.relayReady:
		t.Error("relayReady channel should not be closed when relay is unreachable")
	case <-time.After(2 * time.Second):
		// Expected: channel is still open after 2s.
	}
}

func TestWarmRelayConnectionConnectOnly(t *testing.T) {
	hexKey := generateTestKey(t)

	// Use an unreachable relay address (RFC 5737 TEST-NET) so the node
	// doesn't connect to the real relay in the background.
	n := NewNode()
	_, err := n.Start(NodeConfig{
		PrivateKeyHex: hexKey,
		RelayAddresses: []string{
			"/ip4/192.0.2.99/tcp/4001/p2p/12D3KooWDnwLFvCp4cNBKYJqsBCBFmxnR4VWbBqbfxdCbRhJgkp9",
		},
		AutoRegister: false,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	// Generate a random peer ID that's NOT connected, so host.Connect()
	// will actually try to dial the unreachable address and fail.
	randomKey := generateTestKey(t)
	keyBytes, _ := hex.DecodeString(randomKey)
	priv, _ := crypto.UnmarshalEd25519PrivateKey(keyBytes)
	randomPeerID, _ := peer.IDFromPrivateKey(priv)

	// warmRelayConnection with a valid AddrInfo but unreachable address
	// should return an error (dial failure) without panicking.
	unreachableAddr, _ := ma.NewMultiaddr("/ip4/192.0.2.1/tcp/4001")
	info := peer.AddrInfo{
		ID:    randomPeerID,
		Addrs: []ma.Multiaddr{unreachableAddr},
	}

	err = n.warmRelayConnection(info)
	if err == nil {
		t.Error("expected error for unreachable relay, got nil")
	}
	t.Logf("warmRelayConnection error (expected): %v", err)

	// warmRelayConnection with no addresses should fail.
	emptyInfo := peer.AddrInfo{
		ID:    randomPeerID,
		Addrs: nil,
	}
	err = n.warmRelayConnection(emptyInfo)
	if err == nil {
		t.Error("expected error for empty AddrInfo, got nil")
	}
	t.Logf("warmRelayConnection empty error (expected): %v", err)
}
