package node

import (
	"context"
	"encoding/json"
	"strings"
	"testing"
	"time"

	pubsub "github.com/libp2p/go-libp2p-pubsub"
	pb "github.com/libp2p/go-libp2p-pubsub/pb"
	"github.com/libp2p/go-libp2p/core/peer"

	mcrypto "github.com/mknoon/go-mknoon/crypto"
	"github.com/mknoon/go-mknoon/internal"
)

func startLocalNodeForMultiRelayTestWithCollector(t *testing.T, collector *testEventCollector) *Node {
	t.Helper()
	hexKey := generateTestKey(t)
	n := New(collector)
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

type lp013GroupHarness struct {
	nodeA        *Node
	nodeBCapture *testEventCollector
	nodeB        *Node
	privB64      string
	pubB64       string
	keyInfo      *GroupKeyInfo
}

func setupLP013TwoNodeGroup(t *testing.T, groupId string) lp013GroupHarness {
	t.Helper()

	privB64, pubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeA := startLocalNodeForMultiRelayTest(t)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

	config := &GroupConfig{
		Name:      "LP013 Duplicate PubSub Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: pubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: "peerBPubKey"},
		},
		CreatedBy: nodeA.PeerId(),
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	if err := nodeA.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}

	var nodeBAddrStrs []string
	for _, addr := range nodeB.Host().Addrs() {
		nodeBAddrStrs = append(nodeBAddrStrs, addr.String())
	}
	if err := nodeA.DialPeer(nodeB.PeerId(), nodeBAddrStrs); err != nil {
		t.Fatalf("DialPeer A->B: %v", err)
	}
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 2*time.Second)

	return lp013GroupHarness{
		nodeA:        nodeA,
		nodeBCapture: nodeBCapture,
		nodeB:        nodeB,
		privB64:      privB64,
		pubB64:       pubB64,
		keyInfo:      keyInfo,
	}
}

func buildLP013GroupMessageEnvelope(
	t *testing.T,
	harness lp013GroupHarness,
	groupId string,
	messageId string,
	text string,
	timestamp string,
) string {
	t.Helper()

	payload := &internal.GroupMessagePayload{
		Text:      text,
		Timestamp: timestamp,
		Username:  "Alice",
		Extra:     buildGroupMessageExtra(messageId, nil),
	}
	payloadJSON, err := internal.MarshalGroupPayload(payload)
	if err != nil {
		t.Fatalf("marshal LP013 payload: %v", err)
	}

	ctB64, nonceB64, err := mcrypto.EncryptGroupMessage(harness.keyInfo.Key, payloadJSON)
	if err != nil {
		t.Fatalf("encrypt LP013 payload: %v", err)
	}

	sigData := mcrypto.BuildGroupSignatureData(groupId, harness.keyInfo.KeyEpoch, ctB64)
	signature, err := mcrypto.SignPayload(harness.privB64, sigData)
	if err != nil {
		t.Fatalf("sign LP013 envelope: %v", err)
	}

	envelopeJSON, err := internal.MarshalGroupEnvelope(&internal.GroupEnvelope{
		Version:         "3",
		Type:            "group_message",
		GroupId:         groupId,
		SenderId:        harness.nodeA.PeerId(),
		SenderPublicKey: harness.pubB64,
		Signature:       signature,
		KeyEpoch:        harness.keyInfo.KeyEpoch,
		Encrypted: internal.GroupEncryptedPayload{
			Ciphertext: ctB64,
			Nonce:      nonceB64,
		},
	})
	if err != nil {
		t.Fatalf("marshal LP013 envelope: %v", err)
	}
	return envelopeJSON
}

func publishLP013RawGroupEnvelope(t *testing.T, n *Node, groupId string, envelopeJSON string) {
	t.Helper()

	n.mu.RLock()
	topic := n.groupTopics[groupId]
	n.mu.RUnlock()
	if topic == nil {
		t.Fatalf("group topic %q is not joined", groupId)
	}

	ctx, cancel := context.WithTimeout(n.ctx, PubSubTimeout)
	defer cancel()
	if err := topic.Publish(ctx, []byte(envelopeJSON)); err != nil {
		t.Fatalf("publish raw LP013 envelope: %v", err)
	}
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
	senderPeerId := n.PeerId()
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

func TestJoinGroupTopic_DuplicateJoinPreservesDelivery(t *testing.T) {
	privB64, pubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeA := startLocalNodeForMultiRelayTest(t)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

	groupId := "gl-002-duplicate-join-delivery"
	messageId := "gl-002-after-duplicate-join"
	config := &GroupConfig{
		Name:      "GL-002 Delivery Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: pubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: "peerBPubKey"},
		},
		CreatedBy: nodeA.PeerId(),
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	if err := nodeA.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}

	var nodeBAddrStrs []string
	for _, addr := range nodeB.Host().Addrs() {
		nodeBAddrStrs = append(nodeBAddrStrs, addr.String())
	}
	if err := nodeA.DialPeer(nodeB.PeerId(), nodeBAddrStrs); err != nil {
		t.Fatalf("DialPeer A->B: %v", err)
	}
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 2*time.Second)

	_, duplicatePubB64 := generateEd25519KeyPair(t)
	duplicateGroupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate duplicate group key: %v", err)
	}
	duplicateConfig := &GroupConfig{
		Name:      "GL-002 Rejected Delivery Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: duplicatePubB64},
		},
		CreatedBy: nodeA.PeerId(),
	}
	duplicateKeyInfo := &GroupKeyInfo{Key: duplicateGroupKey, KeyEpoch: 2}

	err = nodeA.JoinGroupTopic(groupId, duplicateConfig, duplicateKeyInfo)
	if err == nil {
		t.Fatal("expected error on duplicate join")
	}
	if !strings.Contains(err.Error(), "already joined") {
		t.Fatalf("expected 'already joined' error, got %q", err.Error())
	}

	msgId, peerCount, err := nodeA.PublishGroupMessage(
		groupId,
		privB64,
		nodeA.PeerId(),
		pubB64,
		"Alice",
		"delivery still works after duplicate join",
		messageId,
		nil,
	)
	if err != nil {
		t.Fatalf("PublishGroupMessage failed after duplicate join: %v", err)
	}
	if msgId != messageId {
		t.Fatalf("messageId = %q, want %q", msgId, messageId)
	}
	if peerCount < 1 {
		t.Fatalf("expected topicPeers >= 1 after duplicate join, got %d", peerCount)
	}

	events := waitForCollectedEventCount(t, nodeBCapture, "group_message:received", 1, 5*time.Second)
	event := events[0]
	if got, _ := event["messageId"].(string); got != messageId {
		t.Fatalf("messageId event = %q, want %q", got, messageId)
	}
	if got, _ := event["text"].(string); got != "delivery still works after duplicate join" {
		t.Fatalf("text event = %q, want delivery still works after duplicate join", got)
	}
	if got := int(event["keyEpoch"].(float64)); got != keyInfo.KeyEpoch {
		t.Fatalf("keyEpoch event = %d, want %d", got, keyInfo.KeyEpoch)
	}
}

func TestGL009LeaveGroupTopicUnregistersValidatorAndRejoinUsesLatestConfigKey(t *testing.T) {
	oldPrivB64, oldPubB64 := generateEd25519KeyPair(t)
	latestPrivB64, latestPubB64 := generateEd25519KeyPair(t)
	oldGroupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate old group key: %v", err)
	}
	latestGroupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate latest group key: %v", err)
	}

	nodeA := startLocalNodeForMultiRelayTest(t)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

	groupId := "gl009-leave-rejoin-validator-latest-key"
	oldKeyInfo := &GroupKeyInfo{Key: oldGroupKey, KeyEpoch: 1}
	latestKeyInfo := &GroupKeyInfo{Key: latestGroupKey, KeyEpoch: 2}
	oldConfig := &GroupConfig{
		Name:      "GL009 Old Config",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: oldPubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: "peerBPubKey"},
		},
		CreatedBy: nodeA.PeerId(),
	}
	latestConfig := &GroupConfig{
		Name:      "GL009 Latest Config",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: latestPubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: "peerBPubKey"},
		},
		CreatedBy: nodeA.PeerId(),
	}

	if err := nodeB.JoinGroupTopic(groupId, oldConfig, oldKeyInfo); err != nil {
		t.Fatalf("nodeB old JoinGroupTopic: %v", err)
	}
	if err := nodeB.LeaveGroupTopic(groupId); err != nil {
		t.Fatalf("nodeB LeaveGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, latestConfig, latestKeyInfo); err != nil {
		t.Fatalf("nodeB rejoin JoinGroupTopic after leave: %v", err)
	}

	if err := nodeA.JoinGroupTopic(groupId, latestConfig, latestKeyInfo); err != nil {
		t.Fatalf("nodeA latest JoinGroupTopic: %v", err)
	}
	connectLocalGroupNodes(t, nodeA, nodeB)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 3*time.Second)

	latestMarker := "gl009-latest-valid-marker"
	latestEnvelope := buildTestEnvelope(
		t,
		groupId,
		nodeA.PeerId(),
		latestPrivB64,
		latestPubB64,
		latestGroupKey,
		latestKeyInfo.KeyEpoch,
		latestMarker,
	)
	publishRawGroupEnvelope(t, nodeA, groupId, latestEnvelope)
	waitForCollectedEventContaining(t, nodeBCapture, latestMarker, 5*time.Second)

	rejectBaseline := len(nodeBCapture.snapshot())
	staleMarker := "gl009-stale-old-key-marker"
	staleEnvelope := buildTestEnvelope(
		t,
		groupId,
		nodeA.PeerId(),
		oldPrivB64,
		oldPubB64,
		oldGroupKey,
		oldKeyInfo.KeyEpoch,
		staleMarker,
	)
	// The publisher's own latest validator would reject this envelope before
	// fanout. Disable only nodeA's local validator so nodeB's post-rejoin
	// latest validator is the one under test for the raw stale publish.
	if err := nodeA.pubsub.UnregisterTopicValidator(GroupTopicPrefix + groupId); err != nil {
		t.Fatalf("nodeA unregister local validator before stale raw publish: %v", err)
	}
	publishRawGroupEnvelope(t, nodeA, groupId, staleEnvelope)
	waitForCollectedValidationReject(t, nodeBCapture, rejectBaseline, "bad_signature_or_epoch", oldKeyInfo.KeyEpoch, 5*time.Second)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaseline, staleMarker, 500*time.Millisecond)

	senderPID, err := peer.Decode(nodeA.PeerId())
	if err != nil {
		t.Fatalf("decode nodeA peer id: %v", err)
	}
	staleSignerLatestKeyEnvelope := buildTestEnvelope(
		t,
		groupId,
		nodeA.PeerId(),
		oldPrivB64,
		oldPubB64,
		latestGroupKey,
		latestKeyInfo.KeyEpoch,
		"gl009-latest-key-old-signer-marker",
	)
	validator := nodeB.groupTopicValidator(groupId)
	msg := &pubsub.Message{Message: &pb.Message{Data: []byte(staleSignerLatestKeyEnvelope)}}
	if result := validator(context.Background(), senderPID, msg); result != pubsub.ValidationReject {
		t.Fatalf("validator result = %v, want ValidationReject for latest-key envelope signed by old key", result)
	}
}

func TestGL011UpdateGroupConfigReplacesMembershipDuringActiveSubscription(t *testing.T) {
	_, pubA := generateEd25519KeyPair(t)
	privC, pubC := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeA := startLocalNodeForMultiRelayTest(t)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)
	nodeC := startLocalNodeForMultiRelayTest(t)

	groupId := "gl011-active-subscription-config-update"
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	configWithC := &GroupConfig{
		Name:      "GL011 Active Subscription",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: pubA},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: "nodeBPubKey"},
			{PeerId: nodeC.PeerId(), Role: GroupRoleWriter, PublicKey: pubC},
		},
		CreatedBy: nodeA.PeerId(),
	}

	if err := nodeA.JoinGroupTopic(groupId, configWithC, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, configWithC, keyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}
	if err := nodeC.JoinGroupTopic(groupId, configWithC, keyInfo); err != nil {
		t.Fatalf("nodeC JoinGroupTopic: %v", err)
	}

	connectLocalGroupNodes(t, nodeC, nodeB)
	connectLocalGroupNodes(t, nodeA, nodeB)
	waitForGroupTopicPeerCount(t, nodeC, groupId, 1, 3*time.Second)
	waitForGroupTopicPeerCount(t, nodeB, groupId, 1, 3*time.Second)

	beforeMarker := "gl011-before-remove-member-c"
	msgID, peerCount, err := nodeC.PublishGroupMessage(
		groupId,
		privC,
		nodeC.PeerId(),
		pubC,
		"Member C",
		beforeMarker,
		"gl011-before-remove-message",
		nil,
	)
	if err != nil {
		t.Fatalf("nodeC PublishGroupMessage before removal: %v", err)
	}
	if msgID == "" || peerCount < 1 {
		t.Fatalf("before removal publish returned msgID=%q peerCount=%d, want non-empty/>=1", msgID, peerCount)
	}
	waitForCollectedEventContaining(t, nodeBCapture, beforeMarker, 5*time.Second)

	removedBaseline := len(nodeBCapture.snapshot())
	configWithoutC := &GroupConfig{
		Name:      "GL011 Active Subscription",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: pubA},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: "nodeBPubKey"},
		},
		CreatedBy: nodeA.PeerId(),
	}
	nodeB.UpdateGroupConfig(groupId, configWithoutC)

	removedMarker := "gl011-after-remove-member-c"
	msgID, peerCount, err = nodeC.PublishGroupMessage(
		groupId,
		privC,
		nodeC.PeerId(),
		pubC,
		"Member C",
		removedMarker,
		"gl011-after-remove-message",
		nil,
	)
	if err != nil {
		t.Fatalf("nodeC PublishGroupMessage after removal: %v", err)
	}
	if msgID == "" || peerCount < 1 {
		t.Fatalf("after removal publish returned msgID=%q peerCount=%d, want non-empty/>=1", msgID, peerCount)
	}
	waitForCollectedValidationReject(t, nodeBCapture, removedBaseline, "non_member", keyInfo.KeyEpoch, 5*time.Second)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, removedBaseline, removedMarker, 500*time.Millisecond)

	nodeB.UpdateGroupConfig(groupId, configWithC)

	afterMarker := "gl011-after-readd-member-c"
	msgID, peerCount, err = nodeC.PublishGroupMessage(
		groupId,
		privC,
		nodeC.PeerId(),
		pubC,
		"Member C",
		afterMarker,
		"gl011-after-readd-message",
		nil,
	)
	if err != nil {
		t.Fatalf("nodeC PublishGroupMessage after re-add: %v", err)
	}
	if msgID == "" || peerCount < 1 {
		t.Fatalf("after re-add publish returned msgID=%q peerCount=%d, want non-empty/>=1", msgID, peerCount)
	}
	waitForCollectedEventContaining(t, nodeBCapture, afterMarker, 5*time.Second)
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

func waitForCollectedEventCount(t *testing.T, collector *testEventCollector, eventName string, want int, timeout time.Duration) []map[string]interface{} {
	t.Helper()

	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		events := collector.collectEvents(eventName)
		if len(events) >= want {
			return events
		}
		time.Sleep(25 * time.Millisecond)
	}

	events := collector.collectEvents(eventName)
	t.Fatalf("timed out waiting for %d %q events; got %d", want, eventName, len(events))
	return nil
}

func waitForCollectedValidationReject(t *testing.T, collector *testEventCollector, baseline int, reason string, keyEpoch int, timeout time.Duration) {
	t.Helper()

	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		events := collector.snapshot()
		for _, raw := range events[baseline:] {
			var payload map[string]interface{}
			if err := json.Unmarshal([]byte(raw), &payload); err != nil {
				continue
			}
			if payload["event"] != "group:validation_rejected" {
				continue
			}
			data, _ := payload["data"].(map[string]interface{})
			gotEpoch, _ := data["keyEpoch"].(float64)
			if data["reason"] == reason && int(gotEpoch) == keyEpoch {
				return
			}
		}
		time.Sleep(25 * time.Millisecond)
	}

	events := collector.snapshot()
	t.Fatalf(
		"timed out waiting for validation reject reason=%q keyEpoch=%d after baseline %d; events=%s",
		reason,
		keyEpoch,
		baseline,
		strings.Join(events[baseline:], "\n"),
	)
}

func assertNoCollectedEventContainingAfter(t *testing.T, collector *testEventCollector, baseline int, needle string, timeout time.Duration) {
	t.Helper()

	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		events := collector.snapshot()
		for _, raw := range events[baseline:] {
			if strings.Contains(raw, needle) {
				t.Fatalf("collected unexpected event containing %q after baseline %d: %s", needle, baseline, raw)
			}
		}
		time.Sleep(25 * time.Millisecond)
	}
}

func TestPublishGroupMessage_DuplicateProvidedMessageIdRemainsVisibleAfterDecrypt(t *testing.T) {
	privB64, pubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeA := startLocalNodeForMultiRelayTest(t)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

	groupId := "test-duplicate-message-id-pubsub"
	duplicateMessageId := "msg-duplicate-pubsub-001"
	config := &GroupConfig{
		Name:      "Duplicate Message ID Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: pubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: "peerBPubKey"},
		},
		CreatedBy: nodeA.PeerId(),
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	if err := nodeA.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}

	var nodeBAddrStrs []string
	for _, addr := range nodeB.Host().Addrs() {
		nodeBAddrStrs = append(nodeBAddrStrs, addr.String())
	}
	if err := nodeA.DialPeer(nodeB.PeerId(), nodeBAddrStrs); err != nil {
		t.Fatalf("DialPeer A->B: %v", err)
	}
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 2*time.Second)

	for i := 0; i < 2; i++ {
		msgID, peerCount, err := nodeA.PublishGroupMessage(
			groupId,
			privB64,
			nodeA.PeerId(),
			pubB64,
			"Alice",
			"duplicate pubsub body",
			duplicateMessageId,
			nil,
		)
		if err != nil {
			t.Fatalf("PublishGroupMessage %d failed: %v", i+1, err)
		}
		if msgID != duplicateMessageId {
			t.Fatalf("PublishGroupMessage %d messageId = %q, want %q", i+1, msgID, duplicateMessageId)
		}
		if peerCount < 1 {
			t.Fatalf("PublishGroupMessage %d topicPeers = %d, want >= 1", i+1, peerCount)
		}
		time.Sleep(10 * time.Millisecond)
	}

	events := waitForCollectedEventCount(t, nodeBCapture, "group_message:received", 2, 5*time.Second)
	for i, event := range events[:2] {
		if got, _ := event["messageId"].(string); got != duplicateMessageId {
			t.Fatalf("event %d messageId = %q, want %q", i+1, got, duplicateMessageId)
		}
		if got, _ := event["text"].(string); got != "duplicate pubsub body" {
			t.Fatalf("event %d text = %q, want duplicate pubsub body", i+1, got)
		}
		if got := int(event["keyEpoch"].(float64)); got != keyInfo.KeyEpoch {
			t.Fatalf("event %d keyEpoch = %d, want %d", i+1, got, keyInfo.KeyEpoch)
		}
	}
}

func TestLP013DefaultPubSubMessageIdUsesSourceAndSeqnoNotPayloadHash(t *testing.T) {
	topic := "lp013-default-msg-id"
	from := []byte("lp013-source-peer")
	seqOne := []byte("seq-1")
	seqTwo := []byte("seq-2")

	msgID := func(data, seqno []byte) string {
		return pubsub.DefaultMsgIdFn(&pb.Message{
			From:  from,
			Data:  data,
			Seqno: seqno,
			Topic: &topic,
		})
	}

	first := msgID([]byte("payload-a"), seqOne)
	conflictingPayload := msgID([]byte("payload-b"), seqOne)
	samePayloadDistinctSeq := msgID([]byte("payload-a"), seqTwo)

	if first != string(from)+string(seqOne) {
		t.Fatalf("default PubSub message ID = %q, want from+seqno %q", first, string(from)+string(seqOne))
	}
	if conflictingPayload != first {
		t.Fatalf("same from+seqno with conflicting payload should collide: got %q want %q", conflictingPayload, first)
	}
	if samePayloadDistinctSeq == first {
		t.Fatalf("same payload with distinct seqno should not collide: both IDs were %q", first)
	}
	if strings.Contains(first, "payload-a") || strings.Contains(conflictingPayload, "payload-b") {
		t.Fatalf("default PubSub message ID unexpectedly included payload bytes: %q / %q", first, conflictingPayload)
	}
}

func TestLP013DuplicateWireEnvelopeWithDistinctPubSubSeqnosPreservesApplicationMessageId(t *testing.T) {
	groupId := "test-lp013-duplicate-wire-envelope"
	messageId := "lp013-wire-dup"
	harness := setupLP013TwoNodeGroup(t, groupId)
	envelopeJSON := buildLP013GroupMessageEnvelope(
		t,
		harness,
		groupId,
		messageId,
		"lp013 duplicate wire body",
		"2026-04-30T22:45:00.000Z",
	)

	publishLP013RawGroupEnvelope(t, harness.nodeA, groupId, envelopeJSON)
	publishLP013RawGroupEnvelope(t, harness.nodeA, groupId, envelopeJSON)

	events := waitForCollectedEventCount(t, harness.nodeBCapture, "group_message:received", 1, 5*time.Second)
	deadline := time.Now().Add(750 * time.Millisecond)
	for time.Now().Before(deadline) {
		events = harness.nodeBCapture.collectEvents("group_message:received")
		if len(events) >= 2 {
			break
		}
		time.Sleep(25 * time.Millisecond)
	}
	if len(events) < 1 || len(events) > 2 {
		t.Fatalf("same wire envelope published twice produced %d events, want explicit one-or-two event outcome", len(events))
	}

	for i, event := range events {
		if got, _ := event["messageId"].(string); got != messageId {
			t.Fatalf("event %d messageId = %q, want %q", i+1, got, messageId)
		}
		if got, _ := event["text"].(string); got != "lp013 duplicate wire body" {
			t.Fatalf("event %d text = %q, want lp013 duplicate wire body", i+1, got)
		}
		if got := int(event["keyEpoch"].(float64)); got != harness.keyInfo.KeyEpoch {
			t.Fatalf("event %d keyEpoch = %d, want %d", i+1, got, harness.keyInfo.KeyEpoch)
		}
	}
	t.Logf("same encrypted wire envelope published twice produced %d app event(s); PubSub suppressed before app when count is one", len(events))
}

func TestLP013ConflictingApplicationDuplicatePubSubPayloadsPreserveFirstWriterInputsForDartDedupe(t *testing.T) {
	groupId := "test-lp013-conflicting-app-duplicate"
	messageId := "lp013-conflicting-dup"
	harness := setupLP013TwoNodeGroup(t, groupId)

	firstEnvelopeJSON := buildLP013GroupMessageEnvelope(
		t,
		harness,
		groupId,
		messageId,
		"trusted first content",
		"2026-04-30T22:46:00.000Z",
	)
	secondEnvelopeJSON := buildLP013GroupMessageEnvelope(
		t,
		harness,
		groupId,
		messageId,
		"conflicting duplicate content",
		"2026-04-30T22:47:00.000Z",
	)

	publishLP013RawGroupEnvelope(t, harness.nodeA, groupId, firstEnvelopeJSON)
	publishLP013RawGroupEnvelope(t, harness.nodeA, groupId, secondEnvelopeJSON)

	events := waitForCollectedEventCount(t, harness.nodeBCapture, "group_message:received", 2, 5*time.Second)
	seenText := map[string]bool{}
	seenTimestamp := map[string]bool{}
	for i, event := range events[:2] {
		if got, _ := event["messageId"].(string); got != messageId {
			t.Fatalf("event %d messageId = %q, want %q", i+1, got, messageId)
		}
		if got := int(event["keyEpoch"].(float64)); got != harness.keyInfo.KeyEpoch {
			t.Fatalf("event %d keyEpoch = %d, want %d", i+1, got, harness.keyInfo.KeyEpoch)
		}
		text, _ := event["text"].(string)
		timestamp, _ := event["timestamp"].(string)
		seenText[text] = true
		seenTimestamp[timestamp] = true
	}

	if !seenText["trusted first content"] || !seenText["conflicting duplicate content"] {
		t.Fatalf("conflicting duplicate payloads did not both reach the app layer: texts=%v", seenText)
	}
	if !seenTimestamp["2026-04-30T22:46:00.000Z"] || !seenTimestamp["2026-04-30T22:47:00.000Z"] {
		t.Fatalf("conflicting duplicate payload timestamps were not preserved into app events: timestamps=%v", seenTimestamp)
	}
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

	// Full-package runs can take a few extra warm cycles before the late
	// peer address is retried. Keep the assertion on the eventual state, not
	// the exact retry wall-clock.
	waitForGroupTopicPeerCount(t, nodeA, groupId, 2, 10*time.Second)

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

	waitForGroupTopicPeerCount(t, nodeA, groupId, 2, 10*time.Second)

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
