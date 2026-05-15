package node

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
	"testing"

	"github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/peer"
	ma "github.com/multiformats/go-multiaddr"
)

// generateFakeRelayAddr generates a multiaddr string with a random peer ID
// pointing to a local port that nothing listens on. This guarantees the
// relay is unreachable and its peer ID never collides with the production relay.
func generateFakeRelayAddr(t *testing.T, port int) string {
	t.Helper()
	priv, _, err := crypto.GenerateEd25519Key(rand.Reader)
	if err != nil {
		t.Fatalf("generate fake relay key: %v", err)
	}
	pid, err := peer.IDFromPrivateKey(priv)
	if err != nil {
		t.Fatalf("peer ID from key: %v", err)
	}
	return fmt.Sprintf("/ip4/127.0.0.1/tcp/%d/p2p/%s", port, pid.String())
}

// ---------- RelaySelector unit tests ----------

func TestNewRelaySelector_GroupsByPeerID(t *testing.T) {
	// Two addresses for the same relay peer (WSS + QUIC).
	// Use the same peer ID string in both.
	pid := generateFakeRelayAddr(t, 4001)
	// Extract the peer ID from the generated address.
	maddr, _ := ma.NewMultiaddr(pid)
	info, _ := peer.AddrInfoFromP2pAddr(maddr)
	peerIdStr := info.ID.String()

	addrs := []string{
		fmt.Sprintf("/ip4/10.0.0.1/tcp/4001/p2p/%s", peerIdStr),
		fmt.Sprintf("/ip4/10.0.0.1/udp/4002/quic-v1/p2p/%s", peerIdStr),
	}

	rs := NewRelaySelector(addrs)
	if rs.Len() != 1 {
		t.Fatalf("expected 1 relay peer, got %d", rs.Len())
	}

	relays := rs.Relays()
	if len(relays[0].Addrs) != 2 {
		t.Errorf("expected 2 addresses merged for relay peer, got %d", len(relays[0].Addrs))
	}
}

func TestNewRelaySelector_TwoDistinctRelays(t *testing.T) {
	addr1 := generateFakeRelayAddr(t, 19001)
	addr2 := generateFakeRelayAddr(t, 19002)

	rs := NewRelaySelector([]string{addr1, addr2})
	if rs.Len() != 2 {
		t.Fatalf("expected 2 relay peers, got %d", rs.Len())
	}
}

func TestNewRelaySelector_SkipsInvalidAddresses(t *testing.T) {
	addr1 := generateFakeRelayAddr(t, 19001)
	addrs := []string{
		"not-a-multiaddr",
		addr1,
	}

	rs := NewRelaySelector(addrs)
	if rs.Len() != 1 {
		t.Fatalf("expected 1 relay after skipping invalid, got %d", rs.Len())
	}
}

func TestRelaySelector_ForEach_SucceedsOnFirstRelay(t *testing.T) {
	addr1 := generateFakeRelayAddr(t, 19001)
	addr2 := generateFakeRelayAddr(t, 19002)

	rs := NewRelaySelector([]string{addr1, addr2})
	calls := 0
	err := rs.ForEach(func(relay RelayInfo) error {
		calls++
		return nil // first relay succeeds
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if calls != 1 {
		t.Errorf("expected 1 call (stop at first success), got %d", calls)
	}
}

func TestRelaySelector_ForEach_FallsBackToSecondRelay(t *testing.T) {
	addr1 := generateFakeRelayAddr(t, 19001)
	addr2 := generateFakeRelayAddr(t, 19002)

	rs := NewRelaySelector([]string{addr1, addr2})
	calls := 0
	err := rs.ForEach(func(relay RelayInfo) error {
		calls++
		if calls == 1 {
			return fmt.Errorf("first relay down")
		}
		return nil // second relay succeeds
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if calls != 2 {
		t.Errorf("expected 2 calls (fall through to second), got %d", calls)
	}
}

func TestRelaySelector_ForEach_FallsBackAcrossAddressesForSameRelay(t *testing.T) {
	seedAddr := generateFakeRelayAddr(t, 19024)
	maddr, err := ma.NewMultiaddr(seedAddr)
	if err != nil {
		t.Fatalf("NewMultiaddr(%q): %v", seedAddr, err)
	}
	info, err := peer.AddrInfoFromP2pAddr(maddr)
	if err != nil {
		t.Fatalf("AddrInfoFromP2pAddr(%q): %v", seedAddr, err)
	}
	peerID := info.ID.String()
	addrs := []string{
		fmt.Sprintf("/ip4/127.0.0.1/udp/19025/quic-v1/p2p/%s", peerID),
		fmt.Sprintf("/ip4/127.0.0.1/tcp/19026/ws/p2p/%s", peerID),
	}

	rs := NewRelaySelector(addrs)
	if rs.Len() != 1 {
		t.Fatalf("Len() = %d, want one grouped relay peer", rs.Len())
	}

	attempts := make([]string, 0, 2)
	err = rs.ForEach(func(relay RelayInfo) error {
		if len(relay.Addrs) != 1 {
			t.Fatalf("relay attempt got %d addrs, want one", len(relay.Addrs))
		}
		attempts = append(attempts, relay.Addrs[0].String())
		if len(attempts) == 1 {
			return errors.New("first transport failed")
		}
		return nil
	})
	if err != nil {
		t.Fatalf("ForEach: %v", err)
	}
	if len(attempts) != 2 {
		t.Fatalf("attempts = %d, want 2 (%v)", len(attempts), attempts)
	}
	if attempts[0] != "/ip4/127.0.0.1/udp/19025/quic-v1" {
		t.Fatalf("first attempt = %q, want QUIC address", attempts[0])
	}
	if attempts[1] != "/ip4/127.0.0.1/tcp/19026/ws" {
		t.Fatalf("second attempt = %q, want WSS address", attempts[1])
	}
}

func TestRelaySelector_ForEach_AllFail(t *testing.T) {
	addr1 := generateFakeRelayAddr(t, 19001)
	addr2 := generateFakeRelayAddr(t, 19002)

	rs := NewRelaySelector([]string{addr1, addr2})
	err := rs.ForEach(func(relay RelayInfo) error {
		return fmt.Errorf("relay down")
	})
	if err == nil {
		t.Fatal("expected error when all relays fail")
	}
	if !strings.Contains(err.Error(), "all 2 relays failed") {
		t.Errorf("error should mention all relays failed: %v", err)
	}
}

func TestRelaySelector_FanOut_AttemptsAllRelaysAndSucceedsIfAnyRelaySucceeds(t *testing.T) {
	addr1 := generateFakeRelayAddr(t, 19001)
	addr2 := generateFakeRelayAddr(t, 19002)
	addr3 := generateFakeRelayAddr(t, 19003)

	rs := NewRelaySelector([]string{addr1, addr2, addr3})
	calls := 0
	err := rs.FanOut(func(relay RelayInfo) error {
		calls++
		if calls == 2 {
			return nil
		}
		return fmt.Errorf("relay down")
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if calls != 3 {
		t.Errorf("expected 3 calls (fan out across all relays), got %d", calls)
	}
}

func TestRelaySelector_FanOut_AllFail(t *testing.T) {
	addr1 := generateFakeRelayAddr(t, 19001)
	addr2 := generateFakeRelayAddr(t, 19002)

	rs := NewRelaySelector([]string{addr1, addr2})
	err := rs.FanOut(func(relay RelayInfo) error {
		return fmt.Errorf("relay down")
	})
	if err == nil {
		t.Fatal("expected error when all relays fail")
	}
	if !strings.Contains(err.Error(), "all 2 relays failed") {
		t.Errorf("error should mention all relays failed: %v", err)
	}
}

func TestRelaySelector_ForEach_EmptyList(t *testing.T) {
	rs := NewRelaySelector(nil)
	err := rs.ForEach(func(relay RelayInfo) error {
		return nil
	})
	if err == nil {
		t.Fatal("expected error with empty relay list")
	}
	if !strings.Contains(err.Error(), "no relays configured") {
		t.Errorf("expected 'no relays configured' error, got: %v", err)
	}
}

func TestForEachWithResult_ReturnsFirstSuccess(t *testing.T) {
	addr1 := generateFakeRelayAddr(t, 19001)
	addr2 := generateFakeRelayAddr(t, 19002)

	rs := NewRelaySelector([]string{addr1, addr2})
	calls := 0
	result, err := ForEachWithResult(rs, func(relay RelayInfo) (string, error) {
		calls++
		if calls == 1 {
			return "", fmt.Errorf("relay 1 down")
		}
		return "from relay 2", nil
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result != "from relay 2" {
		t.Errorf("expected 'from relay 2', got %q", result)
	}
	if calls != 2 {
		t.Errorf("expected 2 calls, got %d", calls)
	}
}

// ---------- Node multi-relay operation tests ----------
//
// These tests start local nodes (no real relay) and verify that
// relay-dependent operations try multiple relays via the RelaySelector.
// The key assertion: when the first relay peer fails, the operation
// tries the second relay peer instead of returning the first error.

// startLocalNodeForMultiRelayTest creates a started node without any relay.
func startLocalNodeForMultiRelayTest(t *testing.T) *Node {
	t.Helper()
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
	t.Cleanup(func() { n.Stop() })
	return n
}

// setFakeRelays configures two fake relay addresses on a node using
// random peer IDs that won't match any running relay server.
func setFakeRelays(t *testing.T, n *Node) {
	t.Helper()
	addr1 := generateFakeRelayAddr(t, 19991)
	addr2 := generateFakeRelayAddr(t, 19992)
	n.mu.Lock()
	n.relayAddresses = []string{addr1, addr2}
	n.mu.Unlock()
}

func TestDialPeerViaRelay_TriesSecondRelayWhenFirstFails(t *testing.T) {
	n := startLocalNodeForMultiRelayTest(t)
	setFakeRelays(t, n)

	// Create a valid target peer ID to dial.
	targetKey := generateTestKey(t)
	targetNode := NewNode()
	st, err := targetNode.Start(NodeConfig{
		PrivateKeyHex:  targetKey,
		RelayAddresses: []string{},
	})
	if err != nil {
		t.Fatalf("target Start: %v", err)
	}
	defer targetNode.Stop()

	// DialPeerViaRelay should try both relay addresses.
	err = n.DialPeerViaRelay(st.PeerId)
	if err == nil {
		t.Fatal("expected error (both fake relays unreachable)")
	}

	// The error should indicate that multiple relays were tried.
	// The error must indicate multi-relay failover was attempted.
	// Our relay selector wraps failures as "all N relays failed".
	if !strings.Contains(err.Error(), "relays failed") {
		t.Errorf("error should indicate multi-relay attempt, got: %v", err)
	}
}

func TestRendezvousRegister_TriesSecondRelayWhenFirstFails(t *testing.T) {
	n := startLocalNodeForMultiRelayTest(t)

	// Two fake relay addresses — neither is a real rendezvous server.
	addr1 := generateFakeRelayAddr(t, 19991)
	addr2 := generateFakeRelayAddr(t, 19992)

	err := n.RendezvousRegister("test-ns", []string{addr1, addr2})
	if err == nil {
		t.Fatal("expected error (both fake relays unreachable)")
	}

	// Should mention all relays were tried.
	// The error must indicate multi-relay failover was attempted.
	// Our relay selector wraps failures as "all N relays failed".
	if !strings.Contains(err.Error(), "relays failed") {
		t.Errorf("error should indicate multi-relay attempt, got: %v", err)
	}
}

func TestRendezvousDiscover_TriesSecondRelayWhenFirstFails(t *testing.T) {
	n := startLocalNodeForMultiRelayTest(t)

	addr1 := generateFakeRelayAddr(t, 19991)
	addr2 := generateFakeRelayAddr(t, 19992)

	_, err := n.RendezvousDiscover("test-ns", []string{addr1, addr2})
	if err == nil {
		t.Fatal("expected error (both fake relays unreachable)")
	}

	// The error must indicate multi-relay failover was attempted.
	// Our relay selector wraps failures as "all N relays failed".
	if !strings.Contains(err.Error(), "relays failed") {
		t.Errorf("error should indicate multi-relay attempt, got: %v", err)
	}
}

func TestInboxStore_TriesSecondRelayWhenFirstFails(t *testing.T) {
	n := startLocalNodeForMultiRelayTest(t)
	setFakeRelays(t, n)

	err := n.InboxStore("12D3KooWFakePeer", "test message", 0)
	if err == nil {
		t.Fatal("expected error (both fake relays unreachable)")
	}

	// The error must indicate multi-relay failover was attempted.
	// Our relay selector wraps failures as "all N relays failed".
	if !strings.Contains(err.Error(), "relays failed") {
		t.Errorf("error should indicate multi-relay attempt, got: %v", err)
	}
}

func TestGroupInboxRetrieve_TriesSecondRelayWhenFirstFails(t *testing.T) {
	n := startLocalNodeForMultiRelayTest(t)
	setFakeRelays(t, n)

	_, err := n.GroupInboxRetrieve("group-123", 0)
	if err == nil {
		t.Fatal("expected error (both fake relays unreachable)")
	}

	// The error must indicate multi-relay failover was attempted.
	// Our relay selector wraps failures as "all N relays failed".
	if !strings.Contains(err.Error(), "relays failed") {
		t.Errorf("error should indicate multi-relay attempt, got: %v", err)
	}
}

func TestGroupInboxRetrieveWithCursor_TriesSecondRelayWhenFirstFails(t *testing.T) {
	n := startLocalNodeForMultiRelayTest(t)
	setFakeRelays(t, n)

	_, _, err := n.GroupInboxRetrieveWithCursor("group-123", "opaque-cursor", 25)
	if err == nil {
		t.Fatal("expected error (both fake relays unreachable)")
	}

	if !strings.Contains(err.Error(), "relays failed") {
		t.Errorf("error should indicate multi-relay attempt, got: %v", err)
	}
}

func TestMediaUpload_TriesSecondRelayWhenFirstFails(t *testing.T) {
	n := startLocalNodeForMultiRelayTest(t)
	setFakeRelays(t, n)

	// MediaUpload should try both relays before failing.
	// The relay connection will fail before file access.
	err := n.MediaUpload("test-id", "12D3KooWFakePeer", "image/jpeg", "/nonexistent/file.jpg", nil)
	if err == nil {
		t.Fatal("expected error (both fake relays unreachable)")
	}

	// The error must indicate multi-relay failover was attempted.
	// Our relay selector wraps failures as "all N relays failed".
	if !strings.Contains(err.Error(), "relays failed") {
		t.Errorf("error should indicate multi-relay attempt, got: %v", err)
	}
}

func TestProfileDownload_TriesSecondRelayWhenFirstFails(t *testing.T) {
	n := startLocalNodeForMultiRelayTest(t)
	setFakeRelays(t, n)

	_, _, err := n.ProfileDownload("12D3KooWFakePeer", "/tmp/test-profile.jpg")
	if err == nil {
		t.Fatal("expected error (both fake relays unreachable)")
	}

	// The error must indicate multi-relay failover was attempted.
	// Our relay selector wraps failures as "all N relays failed".
	if !strings.Contains(err.Error(), "relays failed") {
		t.Errorf("error should indicate multi-relay attempt, got: %v", err)
	}
}

// ---------- buildRelaySelector tests ----------

func TestBuildRelaySelector_UsesServerAddresses(t *testing.T) {
	n := startLocalNodeForMultiRelayTest(t)

	explicit := []string{
		generateFakeRelayAddr(t, 4001),
	}
	rs := n.buildRelaySelector(explicit)
	if rs.Len() != 1 {
		t.Errorf("expected 1 relay from explicit addresses, got %d", rs.Len())
	}
}

func TestBuildRelaySelector_FallsBackToNodeRelays(t *testing.T) {
	n := startLocalNodeForMultiRelayTest(t)
	setFakeRelays(t, n)

	rs := n.buildRelaySelector(nil)
	if rs.Len() != 2 {
		t.Errorf("expected 2 relays from node config, got %d", rs.Len())
	}
}

func TestBuildRelaySelector_FallsBackToDefault(t *testing.T) {
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

	// Node has no relay addresses, selector should fall back to default.
	rs := n.buildRelaySelector(nil)
	if rs.Len() != 1 {
		t.Errorf("expected 1 relay from default, got %d", rs.Len())
	}

	relays := rs.Relays()
	// Check the default relay peer ID matches the DefaultRelayAddress.
	defaultMaddr, _ := ma.NewMultiaddr(DefaultRelayAddress)
	defaultInfo, _ := peer.AddrInfoFromP2pAddr(defaultMaddr)
	if relays[0].ID != defaultInfo.ID {
		t.Errorf("default relay ID mismatch: got %s, want %s", relays[0].ID, defaultInfo.ID)
	}
}

// ---------- Backward compatibility ----------

// TestDialPeerViaRelay_SingleRelayStillWorks verifies backward compatibility:
// a single relay address still works (no regression from multi-relay logic).
func TestDialPeerViaRelay_SingleRelayStillWorks(t *testing.T) {
	n := startLocalNodeForMultiRelayTest(t)

	// Configure a single fake relay address.
	addr1 := generateFakeRelayAddr(t, 19991)
	n.mu.Lock()
	n.relayAddresses = []string{addr1}
	n.mu.Unlock()

	targetKey := generateTestKey(t)
	targetNode := NewNode()
	st, err := targetNode.Start(NodeConfig{
		PrivateKeyHex:  targetKey,
		RelayAddresses: []string{},
	})
	if err != nil {
		t.Fatalf("target Start: %v", err)
	}
	defer targetNode.Stop()

	// Should fail (relay unreachable), but should not panic or behave differently
	// from the pre-multi-relay code.
	err = n.DialPeerViaRelay(st.PeerId)
	if err == nil {
		t.Fatal("expected error (fake relay unreachable)")
	}
}

// suppress unused import warnings
var _ = hex.EncodeToString
var _ = rand.Reader
