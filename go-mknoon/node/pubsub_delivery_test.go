package node

import (
	"strings"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p/core/peer"

	mcrypto "github.com/mknoon/go-mknoon/crypto"
)

func startLocalNodeForMultiRelayTestWithCollector(t *testing.T, collector *testEventCollector) *Node {
	t.Helper()
	n := startLocalNodeForMultiRelayTest(t)
	n.eventCallback = collector
	return n
}

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

func TestPublishGroupMessage_RefreshesMissingKnownTopicPeersBeforePublish(t *testing.T) {
	privB64, pubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeA := startLocalNodeForMultiRelayTest(t)
	nodeB := startLocalNodeForMultiRelayTest(t)
	nodeC := startLocalNodeForMultiRelayTest(t)

	groupId := "test-publish-refreshes-missing-peer"
	senderPeerId := nodeA.PeerId()

	config := &GroupConfig{
		Name:      "Three Peer Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderPeerId, Role: GroupRoleAdmin, PublicKey: pubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: "peerBPubKey"},
			{PeerId: nodeC.PeerId(), Role: GroupRoleWriter, PublicKey: "peerCPubKey"},
		},
		CreatedBy: senderPeerId,
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	for _, n := range []*Node{nodeA, nodeB, nodeC} {
		if err := n.JoinGroupTopic(groupId, config, keyInfo); err != nil {
			t.Fatalf("%s JoinGroupTopic: %v", n.PeerId(), err)
		}
	}

	// Start from the asymmetric live state seen in production: A only has B
	// in its current topic peer set, while C is a known member but not yet live.
	bAddrs := nodeB.Host().Addrs()
	addrStrs := make([]string, len(bAddrs))
	for i, a := range bAddrs {
		addrStrs[i] = a.String()
	}
	if err := nodeA.DialPeer(nodeB.PeerId(), addrStrs); err != nil {
		t.Fatalf("DialPeer A->B: %v", err)
	}

	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 2*time.Second)

	nodeA.mu.RLock()
	initialPeers := len(nodeA.groupTopics[groupId].ListPeers())
	nodeA.mu.RUnlock()
	if initialPeers != 1 {
		t.Fatalf("expected exactly 1 live topic peer before publish refresh, got %d", initialPeers)
	}

	nodeCID, err := peer.Decode(nodeC.PeerId())
	if err != nil {
		t.Fatalf("decode node C peer ID: %v", err)
	}
	nodeA.Host().Peerstore().AddAddrs(nodeCID, nodeC.Host().Addrs(), time.Hour)

	msgID, peerCount, err := nodeA.PublishGroupMessage(
		groupId,
		privB64,
		senderPeerId,
		pubB64,
		"Alice",
		"refresh missing peer before publish",
		"",
		nil,
	)
	if err != nil {
		t.Fatalf("PublishGroupMessage failed: %v", err)
	}
	if msgID == "" {
		t.Fatal("expected non-empty messageId")
	}
	if peerCount < 2 {
		t.Fatalf("expected publish refresh to promote node C into the live topic set, got %d peers", peerCount)
	}

	waitForGroupTopicPeerCount(t, nodeA, groupId, 2, 2*time.Second)
}

func waitForGroupTopicPeerCount(t *testing.T, n *Node, groupId string, wantAtLeast int, timeout time.Duration) {
	t.Helper()

	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		n.mu.RLock()
		topic := n.groupTopics[groupId]
		n.mu.RUnlock()
		if topic != nil && len(topic.ListPeers()) >= wantAtLeast {
			return
		}
		time.Sleep(25 * time.Millisecond)
	}

	n.mu.RLock()
	topic := n.groupTopics[groupId]
	current := 0
	if topic != nil {
		current = len(topic.ListPeers())
	}
	n.mu.RUnlock()
	t.Fatalf(
		"timed out waiting for group %s topic peer count >= %d; got %d",
		groupId,
		wantAtLeast,
		current,
	)
}

func waitForCollectedEventContaining(t *testing.T, collector *testEventCollector, needle string, timeout time.Duration) {
	t.Helper()

	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		for _, raw := range collector.snapshot() {
			if strings.Contains(raw, needle) {
				return
			}
		}
		time.Sleep(25 * time.Millisecond)
	}

	t.Fatalf("timed out waiting for collected event containing %q", needle)
}

// Test: startup group recovery dials known members before waiting on a local
// circuit address, so live topic peers can form immediately.
func TestGroupPeerDiscoveryLoop_DialsKnownMembersBeforeCircuitAddressWait(t *testing.T) {
	privB64, pubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeA := startLocalNodeForMultiRelayTest(t)
	nodeB := startLocalNodeForMultiRelayTest(t)

	releaseCircuitWait := make(chan struct{})
	nodeA.waitForCircuitAddressHook = func(timeout time.Duration) bool {
		<-releaseCircuitWait
		return false
	}
	nodeA.relayReady = make(chan struct{})
	close(nodeA.relayReady)

	nodeBID, err := peer.Decode(nodeB.PeerId())
	if err != nil {
		t.Fatalf("decode node B peer ID: %v", err)
	}
	nodeA.Host().Peerstore().AddAddrs(nodeBID, nodeB.Host().Addrs(), time.Hour)

	groupId := "test-startup-known-member-dial"
	config := &GroupConfig{
		Name:      "Startup Live Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: pubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: "peerBPubKey"},
		},
		CreatedBy: nodeA.PeerId(),
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	if err := nodeB.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}
	if err := nodeA.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		close(releaseCircuitWait)
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	defer close(releaseCircuitWait)

	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 2*time.Second)

	msgID, peerCount, err := nodeA.PublishGroupMessage(
		groupId,
		privB64,
		nodeA.PeerId(),
		pubB64,
		"Alice",
		"live before circuit wait releases",
		"",
		nil,
	)
	if err != nil {
		t.Fatalf("PublishGroupMessage failed: %v", err)
	}
	if msgID == "" {
		t.Fatal("expected non-empty messageId")
	}
	if peerCount < 1 {
		t.Fatalf("expected live topic peers before circuit wait released, got %d", peerCount)
	}
}

// Test: known direct addresses can form live topic peers even before relayReady
// closes, so a slow relay warm-up on one foreground peer does not strand it
// outside the live topic set.
func TestGroupPeerDiscoveryLoop_DialsKnownMembersBeforeRelayReadyWhenDirectAddrsKnown(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeA := startLocalNodeForMultiRelayTest(t)
	nodeB := startLocalNodeForMultiRelayTest(t)
	nodeC := startLocalNodeForMultiRelayTest(t)

	groupId := "test-direct-only-before-relay-ready"
	config := &GroupConfig{
		Name:      "Foreground Direct Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: senderPubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: "peerBPubKey"},
			{PeerId: nodeC.PeerId(), Role: GroupRoleWriter, PublicKey: "peerCPubKey"},
		},
		CreatedBy: nodeA.PeerId(),
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	for _, pair := range []struct {
		from *Node
		to   *Node
	}{
		{from: nodeA, to: nodeB},
		{from: nodeA, to: nodeC},
		{from: nodeB, to: nodeA},
		{from: nodeB, to: nodeC},
		{from: nodeC, to: nodeA},
		{from: nodeC, to: nodeB},
	} {
		toID, err := peer.Decode(pair.to.PeerId())
		if err != nil {
			t.Fatalf("decode peer ID %s: %v", pair.to.PeerId(), err)
		}
		pair.from.Host().Peerstore().AddAddrs(toID, pair.to.Host().Addrs(), time.Hour)
	}

	for _, n := range []*Node{nodeA, nodeB, nodeC} {
		n.relayReady = make(chan struct{})
	}

	for _, n := range []*Node{nodeA, nodeB, nodeC} {
		if err := n.JoinGroupTopic(groupId, config, keyInfo); err != nil {
			t.Fatalf("%s JoinGroupTopic: %v", n.PeerId(), err)
		}
	}

	waitForGroupTopicPeerCount(t, nodeA, groupId, 2, 2*time.Second)

	msgID, peerCount, err := nodeA.PublishGroupMessage(
		groupId,
		senderPrivB64,
		nodeA.PeerId(),
		senderPubB64,
		"Alice",
		"direct peers should not wait for relayReady",
		"",
		nil,
	)
	if err != nil {
		t.Fatalf("PublishGroupMessage failed: %v", err)
	}
	if msgID == "" {
		t.Fatal("expected non-empty messageId")
	}
	if peerCount < 2 {
		t.Fatalf("expected topicPeers >= 2 before relayReady, got %d", peerCount)
	}
}

// Test: a missing third peer does not get stranded behind the warm dial
// cooldown once one recipient is already connected. The discovery loop should
// keep retrying the missing known member until topicPeers == 2 before publish.
func TestGroupPeerDiscoveryLoop_RetriesMissingThirdPeerDuringWarmWindow(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeA := startLocalNodeForMultiRelayTest(t)
	nodeBCapture := &testEventCollector{}
	nodeCCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)
	nodeC := startLocalNodeForMultiRelayTestWithCollector(t, nodeCCapture)

	nodeA.waitForCircuitAddressHook = func(timeout time.Duration) bool {
		return false
	}
	nodeA.relayReady = make(chan struct{})
	close(nodeA.relayReady)

	groupId := "test-warm-retry-missing-third-peer"
	config := &GroupConfig{
		Name:      "Three Peer Warm Retry Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: senderPubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: "peerBPubKey"},
			{PeerId: nodeC.PeerId(), Role: GroupRoleWriter, PublicKey: "peerCPubKey"},
		},
		CreatedBy: nodeA.PeerId(),
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	if err := nodeB.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}
	if err := nodeC.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeC JoinGroupTopic: %v", err)
	}

	nodeBID, err := peer.Decode(nodeB.PeerId())
	if err != nil {
		t.Fatalf("decode node B peer ID: %v", err)
	}
	nodeA.Host().Peerstore().AddAddrs(nodeBID, nodeB.Host().Addrs(), time.Hour)

	if err := nodeA.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}

	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 2*time.Second)

	go func() {
		time.Sleep(time.Second)
		nodeCID, err := peer.Decode(nodeC.PeerId())
		if err != nil {
			return
		}
		nodeA.Host().Peerstore().AddAddrs(nodeCID, nodeC.Host().Addrs(), time.Hour)
	}()

	waitForGroupTopicPeerCount(t, nodeA, groupId, 2, 6*time.Second)

	msgID, peerCount, err := nodeA.PublishGroupMessage(
		groupId,
		senderPrivB64,
		nodeA.PeerId(),
		senderPubB64,
		"Alice",
		"late third peer should still receive live",
		"",
		nil,
	)
	if err != nil {
		t.Fatalf("PublishGroupMessage failed: %v", err)
	}
	if msgID == "" {
		t.Fatal("expected non-empty messageId")
	}
	if peerCount < 2 {
		t.Fatalf("expected topicPeers >= 2 after warm retry catch-up, got %d", peerCount)
	}

	waitForCollectedEvent(t, nodeBCapture, "group_message:received", 5*time.Second)
	waitForCollectedEvent(t, nodeCCapture, "group_message:received", 5*time.Second)
}

// Test: when the initial recovery cycle connects only one live peer, the first
// retry should stay on the warm interval rather than falling back to the slower
// background cadence before the missing member's direct addresses appear.
func TestGroupPeerDiscoveryLoop_UsesWarmRetryImmediatelyAfterPartialInitialRecovery(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeACapture := &testEventCollector{}
	nodeBCapture := &testEventCollector{}
	nodeCCapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)
	nodeC := startLocalNodeForMultiRelayTestWithCollector(t, nodeCCapture)

	nodeA.waitForCircuitAddressHook = func(timeout time.Duration) bool {
		return false
	}
	nodeA.relayReady = make(chan struct{})
	close(nodeA.relayReady)

	groupId := "test-initial-partial-recovery-warm-retry"
	config := &GroupConfig{
		Name:      "Immediate Warm Retry Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: senderPubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: "peerBPubKey"},
			{PeerId: nodeC.PeerId(), Role: GroupRoleWriter, PublicKey: "peerCPubKey"},
		},
		CreatedBy: nodeA.PeerId(),
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	if err := nodeB.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}
	if err := nodeC.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeC JoinGroupTopic: %v", err)
	}

	nodeBID, err := peer.Decode(nodeB.PeerId())
	if err != nil {
		t.Fatalf("decode node B peer ID: %v", err)
	}
	nodeA.Host().Peerstore().AddAddrs(nodeBID, nodeB.Host().Addrs(), time.Hour)

	if err := nodeA.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}

	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 2*time.Second)
	waitForCollectedEventContaining(t, nodeACapture, `"step":"registered"`, 5*time.Second)

	nodeCID, err := peer.Decode(nodeC.PeerId())
	if err != nil {
		t.Fatalf("decode node C peer ID: %v", err)
	}
	nodeA.Host().Peerstore().AddAddrs(nodeCID, nodeC.Host().Addrs(), time.Hour)

	waitForGroupTopicPeerCount(t, nodeA, groupId, 2, 6*time.Second)

	msgID, peerCount, err := nodeA.PublishGroupMessage(
		groupId,
		senderPrivB64,
		nodeA.PeerId(),
		senderPubB64,
		"Alice",
		"partial initial recovery should warm retry quickly",
		"",
		nil,
	)
	if err != nil {
		t.Fatalf("PublishGroupMessage failed: %v", err)
	}
	if msgID == "" {
		t.Fatal("expected non-empty messageId")
	}
	if peerCount < 2 {
		t.Fatalf("expected topicPeers >= 2 after immediate warm retry, got %d", peerCount)
	}

	waitForCollectedEvent(t, nodeBCapture, "group_message:received", 5*time.Second)
	waitForCollectedEvent(t, nodeCCapture, "group_message:received", 5*time.Second)
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
