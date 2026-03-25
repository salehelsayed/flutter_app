package node

import (
	"testing"
	"time"

	mcrypto "github.com/mknoon/go-mknoon/crypto"
)

// --- PublishGroupMessage peer count tests ---

// TestPublishGroupMessage_ReturnsPeerCountZero_WhenNoPeers verifies that
// PublishGroupMessage returns topicPeerCount == 0 and no error when a single
// node publishes to a topic with no other peers subscribed.
func TestPublishGroupMessage_ReturnsPeerCountZero_WhenNoPeers(t *testing.T) {
	privB64, pubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	hexKey := generateTestKey(t)
	n := NewNode()
	_, err = n.Start(NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	groupId := "test-peer-count-zero"
	senderPeerId := "sender-zero"
	config := &GroupConfig{
		Name:      "Zero Peers Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderPeerId, Role: GroupRoleAdmin, PublicKey: pubB64},
		},
		CreatedBy: senderPeerId,
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	if err := n.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("JoinGroupTopic: %v", err)
	}

	msgId, peerCount, err := n.PublishGroupMessage(
		groupId,
		privB64,
		senderPeerId,
		pubB64,
		"Alice",
		"hello with no peers",
		"",
		nil,
	)
	if err != nil {
		t.Fatalf("PublishGroupMessage should succeed with 0 peers, got error: %v", err)
	}
	if msgId == "" {
		t.Fatal("expected non-empty messageId")
	}
	if peerCount != 0 {
		t.Errorf("expected peerCount == 0 (no other peers), got %d", peerCount)
	}
}

// TestPublishGroupMessage_ReturnsPeerCountPositive_WhenPeersConnected verifies
// that PublishGroupMessage returns topicPeerCount >= 1 when two nodes are both
// joined to the same topic and directly connected.
func TestPublishGroupMessage_ReturnsPeerCountPositive_WhenPeersConnected(t *testing.T) {
	privB64, pubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	// Start node A (the publisher).
	nodeA := startLocalNodeForMultiRelayTest(t)
	// Start node B (the subscriber peer).
	nodeB := startLocalNodeForMultiRelayTest(t)

	groupId := "test-peer-count-positive"
	senderPeerId := nodeA.PeerId()

	config := &GroupConfig{
		Name:      "Connected Peers Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderPeerId, Role: GroupRoleAdmin, PublicKey: pubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: "peerBPubKey"},
		},
		CreatedBy: senderPeerId,
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	// Both nodes join the same group topic.
	if err := nodeA.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}

	// Connect node A to node B directly using B's local addresses.
	bAddrs := nodeB.Host().Addrs()
	addrStrs := make([]string, len(bAddrs))
	for i, a := range bAddrs {
		addrStrs[i] = a.String()
	}
	if err := nodeA.DialPeer(nodeB.PeerId(), addrStrs); err != nil {
		t.Fatalf("DialPeer A->B: %v", err)
	}

	// Allow GossipSub mesh formation time.
	time.Sleep(500 * time.Millisecond)

	msgId, peerCount, err := nodeA.PublishGroupMessage(
		groupId,
		privB64,
		senderPeerId,
		pubB64,
		"Alice",
		"hello with peers",
		"",
		nil,
	)
	if err != nil {
		t.Fatalf("PublishGroupMessage failed: %v", err)
	}
	if msgId == "" {
		t.Fatal("expected non-empty messageId")
	}
	if peerCount < 1 {
		t.Errorf("expected peerCount >= 1 (node B is connected and subscribed), got %d", peerCount)
	}
}

// TestPublishGroupMessage_ReturnsErrorForUnjoinedGroup verifies that
// PublishGroupMessage returns an error (and 0 peer count) when the group
// has not been joined.
func TestPublishGroupMessage_ReturnsErrorForUnjoinedGroup(t *testing.T) {
	privB64, pubB64 := generateEd25519KeyPair(t)

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

	msgId, peerCount, err := n.PublishGroupMessage(
		"nonexistent-group",
		privB64,
		"some-peer",
		pubB64,
		"Alice",
		"hello",
		"",
		nil,
	)
	if err == nil {
		t.Fatal("expected error for unjoined group, got nil")
	}
	if msgId != "" {
		t.Errorf("expected empty messageId on error, got %q", msgId)
	}
	if peerCount != 0 {
		t.Errorf("expected peerCount == 0 on error, got %d", peerCount)
	}
}
