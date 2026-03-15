package node

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
)

func TestSendMessage_RetriesChatStreamOpenAfterSelfHeal(t *testing.T) {
	nodeA := NewNode()
	_, err := nodeA.Start(NodeConfig{
		PrivateKeyHex:  generateTestKey(t),
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("nodeA Start: %v", err)
	}
	defer nodeA.Stop()

	nodeB := NewNode()
	stateB, err := nodeB.Start(NodeConfig{
		PrivateKeyHex:  generateTestKey(t),
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("nodeB Start: %v", err)
	}
	defer nodeB.Stop()

	var nodeBAddrStrs []string
	for _, addr := range nodeB.Host().Addrs() {
		nodeBAddrStrs = append(nodeBAddrStrs, addr.String())
	}

	if err := nodeA.DialPeer(stateB.PeerId, nodeBAddrStrs); err != nil {
		t.Fatalf("DialPeer: %v", err)
	}

	targetID, err := peer.Decode(stateB.PeerId)
	if err != nil {
		t.Fatalf("decode target peer: %v", err)
	}

	openCalls := 0
	recoverCalls := 0
	nodeA.openChatStreamHook = func(ctx context.Context, h host.Host, pid peer.ID) (network.Stream, error) {
		openCalls++
		if openCalls == 1 {
			return nil, fmt.Errorf("failed to open stream: %w", context.DeadlineExceeded)
		}
		return h.NewStream(ctx, pid, ChatProtocol)
	}
	nodeA.recoverPeerForSendHook = func(h host.Host, pid peer.ID, peerIdStr string, timeout time.Duration) error {
		recoverCalls++
		if pid != targetID {
			t.Fatalf("unexpected recover peer id: got %s want %s", pid, targetID)
		}
		if peerIdStr != stateB.PeerId {
			t.Fatalf("unexpected recover peer string: got %s want %s", peerIdStr, stateB.PeerId)
		}
		return nil
	}

	reply, acked, err := nodeA.SendMessage(stateB.PeerId, "phase4 self-heal retry", 1000)
	if err != nil {
		t.Fatalf("SendMessage: %v", err)
	}
	if !acked {
		t.Fatal("expected SendMessage to be acknowledged after self-heal retry")
	}
	if reply == "" {
		t.Fatal("expected non-empty reply after self-heal retry")
	}
	if openCalls != 2 {
		t.Fatalf("expected 2 open attempts, got %d", openCalls)
	}
	if recoverCalls != 1 {
		t.Fatalf("expected 1 self-heal attempt, got %d", recoverCalls)
	}

	if nodeA.Host().Network().Connectedness(targetID) != network.Connected {
		t.Fatalf("expected nodeA to remain connected to %s after retry", stateB.PeerId)
	}
}

func TestSendMessage_DoesNotSelfHealNonRetryableOpenErrors(t *testing.T) {
	nodeA := NewNode()
	_, err := nodeA.Start(NodeConfig{
		PrivateKeyHex:  generateTestKey(t),
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("nodeA Start: %v", err)
	}
	defer nodeA.Stop()

	nodeB := NewNode()
	stateB, err := nodeB.Start(NodeConfig{
		PrivateKeyHex:  generateTestKey(t),
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("nodeB Start: %v", err)
	}
	defer nodeB.Stop()

	var nodeBAddrStrs []string
	for _, addr := range nodeB.Host().Addrs() {
		nodeBAddrStrs = append(nodeBAddrStrs, addr.String())
	}

	if err := nodeA.DialPeer(stateB.PeerId, nodeBAddrStrs); err != nil {
		t.Fatalf("DialPeer: %v", err)
	}

	recoverCalls := 0
	nodeA.openChatStreamHook = func(ctx context.Context, h host.Host, pid peer.ID) (network.Stream, error) {
		return nil, fmt.Errorf("boom")
	}
	nodeA.recoverPeerForSendHook = func(h host.Host, pid peer.ID, peerIdStr string, timeout time.Duration) error {
		recoverCalls++
		return nil
	}

	_, _, err = nodeA.SendMessage(stateB.PeerId, "non-retryable", 1000)
	if err == nil {
		t.Fatal("expected SendMessage to fail on non-retryable stream-open error")
	}
	if recoverCalls != 0 {
		t.Fatalf("expected no self-heal attempt, got %d", recoverCalls)
	}
}

func TestSendMessage_OpensChatStreamsWithAllowLimitedConnAndDialTimeout(t *testing.T) {
	nodeA := NewNode()
	_, err := nodeA.Start(NodeConfig{
		PrivateKeyHex:  generateTestKey(t),
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("nodeA Start: %v", err)
	}
	defer nodeA.Stop()

	nodeB := NewNode()
	stateB, err := nodeB.Start(NodeConfig{
		PrivateKeyHex:  generateTestKey(t),
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("nodeB Start: %v", err)
	}
	defer nodeB.Stop()

	var nodeBAddrStrs []string
	for _, addr := range nodeB.Host().Addrs() {
		nodeBAddrStrs = append(nodeBAddrStrs, addr.String())
	}

	if err := nodeA.DialPeer(stateB.PeerId, nodeBAddrStrs); err != nil {
		t.Fatalf("DialPeer: %v", err)
	}

	var allowLimited bool
	var allowReason string
	var dialTimeout time.Duration
	nodeA.openChatStreamHook = func(ctx context.Context, h host.Host, pid peer.ID) (network.Stream, error) {
		allowLimited, allowReason = network.GetAllowLimitedConn(ctx)
		dialTimeout = network.GetDialPeerTimeout(ctx)
		return h.NewStream(ctx, pid, ChatProtocol)
	}

	reply, acked, err := nodeA.SendMessage(stateB.PeerId, "allow limited", 900)
	if err != nil {
		t.Fatalf("SendMessage: %v", err)
	}
	if !acked || reply == "" {
		t.Fatalf("expected acknowledged reply, got acked=%v reply=%q", acked, reply)
	}
	if !allowLimited {
		t.Fatal("expected SendMessage to allow relay-limited chat streams")
	}
	if allowReason != "chat-send" {
		t.Fatalf("unexpected allow-limited reason: %q", allowReason)
	}
	if dialTimeout != 900*time.Millisecond {
		t.Fatalf("expected dial timeout 900ms, got %v", dialTimeout)
	}
}

func TestSendMessageWithTimeout_OpensChatStreamsWithAllowLimitedConnAndDialTimeout(t *testing.T) {
	nodeA := NewNode()
	_, err := nodeA.Start(NodeConfig{
		PrivateKeyHex:  generateTestKey(t),
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("nodeA Start: %v", err)
	}
	defer nodeA.Stop()

	nodeB := NewNode()
	stateB, err := nodeB.Start(NodeConfig{
		PrivateKeyHex:  generateTestKey(t),
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("nodeB Start: %v", err)
	}
	defer nodeB.Stop()

	var nodeBAddrStrs []string
	for _, addr := range nodeB.Host().Addrs() {
		nodeBAddrStrs = append(nodeBAddrStrs, addr.String())
	}

	if err := nodeA.DialPeer(stateB.PeerId, nodeBAddrStrs); err != nil {
		t.Fatalf("DialPeer: %v", err)
	}

	var allowLimited bool
	var allowReason string
	var dialTimeout time.Duration
	nodeA.openChatStreamHook = func(ctx context.Context, h host.Host, pid peer.ID) (network.Stream, error) {
		allowLimited, allowReason = network.GetAllowLimitedConn(ctx)
		dialTimeout = network.GetDialPeerTimeout(ctx)
		return h.NewStream(ctx, pid, ChatProtocol)
	}

	reply, err := nodeA.SendMessageWithTimeout(stateB.PeerId, "allow limited timeout", 1100)
	if err != nil {
		t.Fatalf("SendMessageWithTimeout: %v", err)
	}
	if reply == "" {
		t.Fatal("expected non-empty reply from SendMessageWithTimeout")
	}
	if !allowLimited {
		t.Fatal("expected SendMessageWithTimeout to allow relay-limited chat streams")
	}
	if allowReason != "chat-send" {
		t.Fatalf("unexpected allow-limited reason: %q", allowReason)
	}
	if dialTimeout != 1100*time.Millisecond {
		t.Fatalf("expected dial timeout 1100ms, got %v", dialTimeout)
	}
}
