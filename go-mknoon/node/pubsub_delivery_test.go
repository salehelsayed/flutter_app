package node

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"regexp"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p"
	pubsub "github.com/libp2p/go-libp2p-pubsub"
	pb "github.com/libp2p/go-libp2p-pubsub/pb"
	libp2pcrypto "github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	relayclient "github.com/libp2p/go-libp2p/p2p/protocol/circuitv2/client"

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

func startNW002LocalCircuitRelay(t *testing.T) (host.Host, string) {
	t.Helper()
	privKey, _, err := libp2pcrypto.GenerateEd25519Key(rand.Reader)
	if err != nil {
		t.Fatalf("generate relay key: %v", err)
	}
	relayHost, err := libp2p.New(
		libp2p.Identity(privKey),
		libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"),
		libp2p.EnableRelayService(),
		libp2p.ForceReachabilityPublic(),
	)
	if err != nil {
		t.Fatalf("start local circuit relay: %v", err)
	}
	t.Cleanup(func() {
		if err := relayHost.Close(); err != nil {
			t.Fatalf("close local circuit relay: %v", err)
		}
	})
	if len(relayHost.Addrs()) == 0 {
		t.Fatal("local circuit relay has no listen addresses")
	}
	relayAddr := fmt.Sprintf("%s/p2p/%s", relayHost.Addrs()[0], relayHost.ID())
	return relayHost, relayAddr
}

func startNW002RelayNode(
	t *testing.T,
	relayAddr string,
	collector *testEventCollector,
) *Node {
	t.Helper()
	hexKey := generateTestKey(t)
	n := New(collector)
	_, err := n.Start(NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{relayAddr},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("Start with local circuit relay: %v", err)
	}
	t.Cleanup(func() { n.Stop() })
	if err := n.WaitForRelayConnection(5 * time.Second); err != nil {
		t.Fatalf("%s did not warm local relay: %v", n.PeerId(), err)
	}
	relayInfo, err := peer.AddrInfoFromString(relayAddr)
	if err != nil {
		t.Fatalf("parse local relay addr: %v", err)
	}
	reserveCtx, cancel := context.WithTimeout(n.ctx, 10*time.Second)
	defer cancel()
	if _, err := relayclient.Reserve(reserveCtx, n.Host(), *relayInfo); err != nil {
		t.Fatalf("%s could not reserve local circuit relay: %v", n.PeerId(), err)
	}
	return n
}

func cancelNW002GroupDiscovery(t *testing.T, n *Node, groupId string) {
	t.Helper()
	n.mu.Lock()
	cancel, ok := n.groupDiscoveryCtx[groupId]
	if ok {
		cancel()
		delete(n.groupDiscoveryCtx, groupId)
	}
	n.mu.Unlock()
}

func clearNW002DirectRouteState(t *testing.T, from *Node, target *Node) {
	t.Helper()
	fromID, err := peer.Decode(from.PeerId())
	if err != nil {
		t.Fatalf("decode sender peer ID: %v", err)
	}
	targetID, err := peer.Decode(target.PeerId())
	if err != nil {
		t.Fatalf("decode target peer ID: %v", err)
	}
	fromHost := from.Host()
	targetHost := target.Host()
	if fromHost == nil {
		t.Fatalf("%s host is nil", from.PeerId())
	}
	if targetHost == nil {
		t.Fatalf("%s host is nil", target.PeerId())
	}

	_ = fromHost.Network().ClosePeer(targetID)
	_ = targetHost.Network().ClosePeer(fromID)
	fromHost.Peerstore().ClearAddrs(targetID)
	targetHost.Peerstore().ClearAddrs(fromID)
}

func assertNW002NoDirectPeerstoreAddrs(t *testing.T, from *Node, target *Node) {
	t.Helper()
	pid, err := peer.Decode(target.PeerId())
	if err != nil {
		t.Fatalf("decode target peer ID: %v", err)
	}
	if got := collectDirectMultiaddrs(from.Host(), pid, nil); len(got) != 0 {
		t.Fatalf(
			"%s unexpectedly had %d direct peerstore addrs for %s before circuit dial: %v",
			from.PeerId(),
			len(got),
			target.PeerId(),
			multiaddrsToStrings(got),
		)
	}
}

func assertNW002LimitedCircuitConn(t *testing.T, from *Node, target *Node) {
	t.Helper()
	pid, err := peer.Decode(target.PeerId())
	if err != nil {
		t.Fatalf("decode target peer ID: %v", err)
	}
	conns := from.Host().Network().ConnsToPeer(pid)
	if len(conns) == 0 {
		t.Fatalf("%s has no connection to %s", from.PeerId(), target.PeerId())
	}
	for _, conn := range conns {
		if conn.Stat().Limited {
			return
		}
	}
	t.Fatalf("%s connection to %s was not marked limited/circuit-routed", from.PeerId(), target.PeerId())
}

func assertNW002ReceivedText(
	t *testing.T,
	events []map[string]interface{},
	text string,
	senderPeerId string,
) {
	t.Helper()
	for _, event := range events {
		if event["text"] == text && event["senderId"] == senderPeerId {
			return
		}
	}
	t.Fatalf("missing received text %q from %s in events: %+v", text, senderPeerId, events)
}

func waitForCollectedGroupDiscoveryPeerPrefix(
	t *testing.T,
	collector *testEventCollector,
	groupId string,
	step string,
	peerId string,
	timeout time.Duration,
) map[string]interface{} {
	t.Helper()
	wantPrefix := peerIDDiagnosticPrefix(peerId)
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		for _, event := range collector.collectEvents("group:discovery") {
			if event["groupId"] != groupId || event["step"] != step {
				continue
			}
			if event["peerIdPrefix"] == wantPrefix {
				if len(wantPrefix) > 12 {
					t.Fatalf("peerIdPrefix length = %d, want <= 12", len(wantPrefix))
				}
				return event
			}
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatalf(
		"timed out waiting for group discovery peer prefix %q step %q group %s; events=%v",
		wantPrefix,
		step,
		groupId,
		collector.snapshot(),
	)
	return nil
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

	return buildLP013GroupMessageEnvelopeWithExtra(
		t,
		harness,
		groupId,
		text,
		timestamp,
		buildGroupMessageExtra(messageId, nil),
	)
}

func buildLP013GroupMessageEnvelopeWithExtra(
	t *testing.T,
	harness lp013GroupHarness,
	groupId string,
	text string,
	timestamp string,
	extra map[string]interface{},
) string {
	t.Helper()

	payload := &internal.GroupMessagePayload{
		Text:      text,
		Timestamp: timestamp,
		Username:  "Alice",
		Extra:     extra,
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

func TestGO001PublishGroupMessageReportsZeroTopicPeers(t *testing.T) {
	privB64, pubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	n := NewNode()
	_, err = n.Start(NodeConfig{
		PrivateKeyHex:  generateTestKey(t),
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	groupID := "go001-zero-topic-peers"
	senderPeerID := n.PeerId()
	if err := n.JoinGroupTopic(groupID, &GroupConfig{
		Name:      "GO001 Zero Topic Peers",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderPeerID, Role: GroupRoleAdmin, PublicKey: pubB64},
		},
		CreatedBy: senderPeerID,
	}, &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}); err != nil {
		t.Fatalf("JoinGroupTopic: %v", err)
	}

	msgID, peerCount, err := n.PublishGroupMessage(
		groupID,
		privB64,
		senderPeerID,
		pubB64,
		"Alice",
		"GO-001 publish with no live topic peers",
		"go001-message-id",
		nil,
	)
	if err != nil {
		t.Fatalf("PublishGroupMessage should report zero live topic peers without failing: %v", err)
	}
	if msgID != "go001-message-id" {
		t.Fatalf("msgID = %q, want caller-provided id", msgID)
	}
	if peerCount != 0 {
		t.Fatalf("peerCount = %d, want 0 for a topic with no live peers", peerCount)
	}
}

func TestGP005PublishWithZeroTopicPeersStillSucceedsAndReportsZero(t *testing.T) {
	privB64, pubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	n := NewNode()
	_, err = n.Start(NodeConfig{
		PrivateKeyHex:  generateTestKey(t),
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	groupID := "gp005-zero-topic-peers"
	senderPeerID := n.PeerId()
	if err := n.JoinGroupTopic(groupID, &GroupConfig{
		Name:      "GP005 Zero Peers",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderPeerID, Role: GroupRoleAdmin, PublicKey: pubB64},
		},
		CreatedBy: senderPeerID,
	}, &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}); err != nil {
		t.Fatalf("JoinGroupTopic: %v", err)
	}

	msgID, peerCount, err := n.PublishGroupMessage(
		groupID,
		privB64,
		senderPeerID,
		pubB64,
		"Alice",
		"gp005 publish with zero live topic peers",
		"gp005-message-id",
		nil,
	)
	if err != nil {
		t.Fatalf("PublishGroupMessage should succeed when PubSub accepts a zero-peer publish: %v", err)
	}
	if msgID != "gp005-message-id" {
		t.Fatalf("msgID = %q, want caller-provided id", msgID)
	}
	if peerCount != 0 {
		t.Fatalf("peerCount = %d, want 0 for a topic with no live peers", peerCount)
	}
}

func TestGP007ZeroPeerPublishUsesBoundedSettleWait(t *testing.T) {
	privB64, pubB64 := generateEd25519KeyPair(t)
	_, remotePubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	capture := &testEventCollector{}
	n := startLocalNodeForMultiRelayTestWithCollector(t, capture)
	groupID := "gp007-zero-peer-bounded-publish"
	senderPeerID := n.PeerId()
	remotePeerID := generatePeerIDStr(t)
	if err := n.JoinGroupTopic(groupID, &GroupConfig{
		Name:      "GP007 Zero Peer Bounded Publish",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderPeerID, Role: GroupRoleAdmin, PublicKey: pubB64},
			{PeerId: remotePeerID, Role: GroupRoleWriter, PublicKey: remotePubB64},
		},
		CreatedBy: senderPeerID,
	}, &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}); err != nil {
		t.Fatalf("JoinGroupTopic: %v", err)
	}

	start := time.Now()
	msgID, peerCount, err := n.PublishGroupMessage(
		groupID,
		privB64,
		senderPeerID,
		pubB64,
		"Alice",
		"gp007 publish with bounded zero-peer preflight",
		"gp007-message-id",
		nil,
	)
	elapsed := time.Since(start)
	if err != nil {
		t.Fatalf("PublishGroupMessage should succeed with zero live peers: %v", err)
	}
	if msgID != "gp007-message-id" {
		t.Fatalf("msgID = %q, want caller-provided id", msgID)
	}
	if peerCount != 0 {
		t.Fatalf("peerCount = %d, want 0 for zero live topic peers", peerCount)
	}
	if elapsed > GroupPublishZeroPeerSettleWait+750*time.Millisecond {
		t.Fatalf("zero-peer publish elapsed %v, want bounded near %v", elapsed, GroupPublishZeroPeerSettleWait)
	}

	begin := waitForCollectedEventData(t, capture, "group:discovery", func(event map[string]interface{}) bool {
		return event["step"] == "publish_peer_refresh_begin"
	}, time.Second)
	assertGP007NumericEquals(t, begin, "topicPeers", 0)
	assertGP007NumericEquals(t, begin, "expectedPeers", 1)

	done := waitForCollectedEventData(t, capture, "group:discovery", func(event map[string]interface{}) bool {
		return event["step"] == "publish_peer_refresh_done"
	}, time.Second)
	assertGP007NumericEquals(t, done, "topicPeers", 0)
	assertGP007NumericEquals(t, done, "expectedPeers", 1)
	assertGP007NumericEquals(t, done, "settleWaitMs", int(GroupPublishZeroPeerSettleWait.Milliseconds()))
	if got := GroupPublishZeroPeerSettleWait; got >= GroupPublishPartialPeerSettleWait {
		t.Fatalf("zero-peer settle wait %v must stay below partial-peer wait %v", got, GroupPublishPartialPeerSettleWait)
	}
}

func assertGP007NumericEquals(t *testing.T, data map[string]interface{}, field string, want int) {
	t.Helper()

	got, ok := data[field].(float64)
	if !ok {
		t.Fatalf("%s = %v (%T), want numeric %d; event=%v", field, data[field], data[field], want, data)
	}
	if int(got) != want {
		t.Fatalf("%s = %v, want %d; event=%v", field, got, want, data)
	}
}

func TestGP015ConnectedHostPeerDoesNotCountAsLiveTopicPeer(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	_, hostOnlyPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeACapture := &testEventCollector{}
	nodeBCapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)
	nodeBID, err := peer.Decode(nodeB.PeerId())
	if err != nil {
		t.Fatalf("decode node B peer ID: %v", err)
	}

	groupID := "gp015-host-connected-not-topic-peer"
	config := &GroupConfig{
		Name:      "GP015 Host Connected",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: senderPubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: hostOnlyPubB64},
		},
		CreatedBy: nodeA.PeerId(),
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	if err := nodeA.JoinGroupTopic(groupID, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	connectLocalGroupNodes(t, nodeA, nodeB)
	if got := nodeA.Host().Network().Connectedness(nodeBID); got != network.Connected {
		t.Fatalf("nodeB host connectedness = %s, want connected", got)
	}
	if got := nodeA.countConnectedGroupMembers(groupID); got != 0 {
		t.Fatalf("connected host peer counted as live group topic peer before publish: got %d", got)
	}
	if live := nodeA.liveGroupTopicPeerSet(groupID); len(live) != 0 {
		t.Fatalf("expected no live topic peers before publish, got %v", live)
	}

	nodeBBaseline := len(nodeBCapture.snapshot())
	messageID := "gp015-host-connected-not-topic"
	msgID, peerCount, err := nodeA.PublishGroupMessage(
		groupID,
		senderPrivB64,
		nodeA.PeerId(),
		senderPubB64,
		"Alice",
		"GP015 host connection is not a topic peer",
		messageID,
		nil,
	)
	if err != nil {
		t.Fatalf("PublishGroupMessage: %v", err)
	}
	if msgID != messageID {
		t.Fatalf("msgID = %q, want %q", msgID, messageID)
	}
	if peerCount != 0 {
		t.Fatalf("peerCount = %d, want 0 because host connection is not topic.ListPeers", peerCount)
	}
	if got := nodeA.Host().Network().Connectedness(nodeBID); got != network.Connected {
		t.Fatalf("nodeB host connectedness after publish = %s, want connected", got)
	}
	if got := nodeA.countConnectedGroupMembers(groupID); got != 0 {
		t.Fatalf("connected host peer counted as live group topic peer after publish: got %d", got)
	}
	publishDebug := waitForCollectedEventData(t, nodeACapture, "group:publish_debug", func(event map[string]interface{}) bool {
		return event["messageId"] == messageID
	}, time.Second)
	if got, ok := publishDebug["topicPeers"].(float64); !ok || int(got) != 0 {
		t.Fatalf("publish_debug.topicPeers = %v, want 0; event=%v", publishDebug["topicPeers"], publishDebug)
	}
	assertNoCollectedEventContainingAfter(t, nodeBCapture, nodeBBaseline, messageID, 500*time.Millisecond)
}

func TestGO007MetricsDistinguishHostConnectionFromLiveTopicPeer(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	_, hostOnlyPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeACapture := &testEventCollector{}
	nodeBCapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)
	nodeBID, err := peer.Decode(nodeB.PeerId())
	if err != nil {
		t.Fatalf("decode node B peer ID: %v", err)
	}

	groupID := "go007-host-connected-not-topic-peer"
	config := &GroupConfig{
		Name:      "GO007 Host Connected",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: senderPubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: hostOnlyPubB64},
		},
		CreatedBy: nodeA.PeerId(),
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	if err := nodeA.JoinGroupTopic(groupID, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	connectLocalGroupNodes(t, nodeA, nodeB)
	if got := nodeA.Host().Network().Connectedness(nodeBID); got != network.Connected {
		t.Fatalf("nodeB host connectedness = %s, want connected", got)
	}
	if got := nodeA.countConnectedGroupMembers(groupID); got != 0 {
		t.Fatalf("host-connected peer counted as live topic peer before publish: got %d", got)
	}
	if live := nodeA.liveGroupTopicPeerSet(groupID); len(live) != 0 {
		t.Fatalf("expected no live topic peers before publish, got %v", live)
	}

	nodeBBaseline := len(nodeBCapture.snapshot())
	messageID := "go007-host-not-topic-metric"
	msgID, peerCount, err := nodeA.PublishGroupMessage(
		groupID,
		senderPrivB64,
		nodeA.PeerId(),
		senderPubB64,
		"Alice",
		"GO007 host connection is not a topic peer",
		messageID,
		nil,
	)
	if err != nil {
		t.Fatalf("PublishGroupMessage: %v", err)
	}
	if msgID != messageID {
		t.Fatalf("msgID = %q, want %q", msgID, messageID)
	}
	if peerCount != 0 {
		t.Fatalf("peerCount = %d, want 0 because host connection is not topic.ListPeers", peerCount)
	}
	if got := nodeA.Host().Network().Connectedness(nodeBID); got != network.Connected {
		t.Fatalf("nodeB host connectedness after publish = %s, want connected", got)
	}
	if got := nodeA.countConnectedGroupMembers(groupID); got != 0 {
		t.Fatalf("host-connected peer counted as live topic peer after publish: got %d", got)
	}

	refreshDone := waitForCollectedEventData(t, nodeACapture, "group:discovery", func(event map[string]interface{}) bool {
		return event["groupId"] == groupID && event["step"] == "publish_peer_refresh_done"
	}, time.Second)
	assertGO007NumericEquals(t, refreshDone, "topicPeers", 0)
	assertGO007NumericEquals(t, refreshDone, "expectedPeers", 1)
	assertGO007NumericEquals(t, refreshDone, "missingPeers", 1)
	assertGO007BoolEquals(t, refreshDone, "backingOff", false)

	publishDebug := waitForCollectedEventData(t, nodeACapture, "group:publish_debug", func(event map[string]interface{}) bool {
		return event["messageId"] == messageID
	}, time.Second)
	assertGO007NumericEquals(t, publishDebug, "topicPeers", 0)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, nodeBBaseline, messageID, 500*time.Millisecond)
}

func assertGO007NumericEquals(t *testing.T, data map[string]interface{}, field string, want int) {
	t.Helper()

	got, ok := data[field].(float64)
	if !ok {
		t.Fatalf("%s = %v (%T), want numeric %d; event=%v", field, data[field], data[field], want, data)
	}
	if int(got) != want {
		t.Fatalf("%s = %v, want %d; event=%v", field, got, want, data)
	}
}

func assertGO007BoolEquals(t *testing.T, data map[string]interface{}, field string, want bool) {
	t.Helper()

	got, ok := data[field].(bool)
	if !ok {
		t.Fatalf("%s = %v (%T), want bool %t; event=%v", field, data[field], data[field], want, data)
	}
	if got != want {
		t.Fatalf("%s = %v, want %t; event=%v", field, got, want, data)
	}
}

func TestGP006PublishWithPartialPeersRefreshesKnownMembersBeforeSend(t *testing.T) {
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

	for _, n := range []*Node{nodeA, nodeB, nodeC} {
		n.waitForCircuitAddressHook = func(timeout time.Duration) bool {
			return false
		}
		n.relayReady = make(chan struct{})
		close(n.relayReady)
	}

	groupID := "gp006-partial-peer-refresh"
	config := &GroupConfig{
		Name:      "GP006 Partial Peer Refresh",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: senderPubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: "peerBPubKey"},
			{PeerId: nodeC.PeerId(), Role: GroupRoleWriter, PublicKey: "peerCPubKey"},
		},
		CreatedBy: nodeA.PeerId(),
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	if err := nodeB.JoinGroupTopic(groupID, config, keyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}
	if err := nodeC.JoinGroupTopic(groupID, config, keyInfo); err != nil {
		t.Fatalf("nodeC JoinGroupTopic: %v", err)
	}

	nodeBID, err := peer.Decode(nodeB.PeerId())
	if err != nil {
		t.Fatalf("decode node B peer ID: %v", err)
	}
	nodeA.Host().Peerstore().AddAddrs(nodeBID, nodeB.Host().Addrs(), time.Hour)

	if err := nodeA.JoinGroupTopic(groupID, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	waitForGroupTopicPeerCount(t, nodeA, groupID, 1, 2*time.Second)

	nodeA.mu.RLock()
	topic := nodeA.groupTopics[groupID]
	initialPeers := 0
	if topic != nil {
		initialPeers = len(topic.ListPeers())
	}
	nodeA.mu.RUnlock()
	if initialPeers != 1 {
		t.Fatalf("initial topic peer count = %d, want exactly one live recipient before publish", initialPeers)
	}

	nodeCID, err := peer.Decode(nodeC.PeerId())
	if err != nil {
		t.Fatalf("decode node C peer ID: %v", err)
	}
	nodeA.Host().Peerstore().AddAddrs(nodeCID, nodeC.Host().Addrs(), time.Hour)

	senderBaseline := len(nodeACapture.snapshot())
	nodeBBaseline := len(nodeBCapture.snapshot())
	nodeCBaseline := len(nodeCCapture.snapshot())
	messageID := "gp006-partial-refresh-message"
	msgID, peerCount, err := nodeA.PublishGroupMessage(
		groupID,
		senderPrivB64,
		nodeA.PeerId(),
		senderPubB64,
		"Alice",
		"GP-006 partial peers refresh before send",
		messageID,
		nil,
	)
	if err != nil {
		t.Fatalf("PublishGroupMessage: %v", err)
	}
	if msgID != messageID {
		t.Fatalf("messageId = %q, want %q", msgID, messageID)
	}
	if peerCount < 2 {
		t.Fatalf("peerCount = %d, want refresh to promote missing known member", peerCount)
	}

	waitDiscoveryStepAfter := func(step string) map[string]interface{} {
		t.Helper()
		deadline := time.Now().Add(3 * time.Second)
		for time.Now().Before(deadline) {
			for _, raw := range nodeACapture.snapshot()[senderBaseline:] {
				var payload map[string]interface{}
				if err := json.Unmarshal([]byte(raw), &payload); err != nil {
					continue
				}
				if payload["event"] != "group:discovery" {
					continue
				}
				data, _ := payload["data"].(map[string]interface{})
				if data["groupId"] == groupID && data["step"] == step {
					return data
				}
			}
			time.Sleep(25 * time.Millisecond)
		}
		t.Fatalf("timed out waiting for group %s discovery step %s after publish; events=%v", groupID, step, nodeACapture.snapshot()[senderBaseline:])
		return nil
	}
	waitDiscoveryStepAndPeerAfter := func(step string, peerID string) map[string]interface{} {
		t.Helper()
		deadline := time.Now().Add(3 * time.Second)
		for time.Now().Before(deadline) {
			for _, raw := range nodeACapture.snapshot()[senderBaseline:] {
				var payload map[string]interface{}
				if err := json.Unmarshal([]byte(raw), &payload); err != nil {
					continue
				}
				if payload["event"] != "group:discovery" {
					continue
				}
				data, _ := payload["data"].(map[string]interface{})
				if data["groupId"] == groupID && data["step"] == step && data["peerId"] == peerID {
					return data
				}
			}
			time.Sleep(25 * time.Millisecond)
		}
		t.Fatalf("timed out waiting for group %s discovery step %s peer %s after publish; events=%v", groupID, step, peerID, nodeACapture.snapshot()[senderBaseline:])
		return nil
	}
	assertNumericAtLeast := func(data map[string]interface{}, field string, wantMin int) {
		t.Helper()
		got, ok := data[field].(float64)
		if !ok || int(got) < wantMin {
			t.Fatalf("%s = %v, want >= %d in event data %#v", field, data[field], wantMin, data)
		}
	}
	assertNumericEquals := func(data map[string]interface{}, field string, want int) {
		t.Helper()
		got, ok := data[field].(float64)
		if !ok || int(got) != want {
			t.Fatalf("%s = %v, want %d in event data %#v", field, data[field], want, data)
		}
	}

	beginData := waitDiscoveryStepAfter("publish_peer_refresh_begin")
	assertNumericEquals(beginData, "topicPeers", 1)
	assertNumericEquals(beginData, "expectedPeers", 2)
	nodeCShort := nodeC.PeerId()
	if len(nodeCShort) > 16 {
		nodeCShort = nodeCShort[:16]
	}
	successData := waitDiscoveryStepAndPeerAfter("known_member_dial_success", nodeCShort)
	if successData["path"] != "direct" {
		t.Fatalf("known_member_dial_success path = %v, want direct", successData["path"])
	}
	directData := waitDiscoveryStepAfter("direct_dial")
	assertNumericAtLeast(directData, "membersDialed", 1)
	assertNumericEquals(directData, "totalMembers", 2)
	doneData := waitDiscoveryStepAfter("publish_peer_refresh_done")
	assertNumericEquals(doneData, "expectedPeers", 2)
	assertNumericAtLeast(doneData, "topicPeers", 2)
	if promoted, ok := doneData["promoted"].(bool); !ok || !promoted {
		t.Fatalf("promoted = %v, want true in event data %#v", doneData["promoted"], doneData)
	}

	bEvent := waitForCollectedEventAfter(t, nodeBCapture, nodeBBaseline, "group_message:received", 5*time.Second)
	cEvent := waitForCollectedEventAfter(t, nodeCCapture, nodeCBaseline, "group_message:received", 5*time.Second)
	for label, event := range map[string]map[string]interface{}{
		"nodeB": bEvent,
		"nodeC": cEvent,
	} {
		if event["messageId"] != messageID {
			t.Fatalf("%s messageId = %v, want %s", label, event["messageId"], messageID)
		}
		if event["text"] != "GP-006 partial peers refresh before send" {
			t.Fatalf("%s text = %v", label, event["text"])
		}
	}
}

func TestGP008PublishPeerRefreshUsesLatestConfigAfterAddRemove(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeACapture := &testEventCollector{}
	nodeBCapture := &testEventCollector{}
	nodeCCapture := &testEventCollector{}
	nodeDCapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)
	nodeC := startLocalNodeForMultiRelayTestWithCollector(t, nodeCCapture)
	nodeD := startLocalNodeForMultiRelayTestWithCollector(t, nodeDCapture)

	for _, n := range []*Node{nodeA, nodeB, nodeC, nodeD} {
		n.waitForCircuitAddressHook = func(timeout time.Duration) bool {
			return false
		}
		n.relayReady = make(chan struct{})
		close(n.relayReady)
	}

	groupID := "gp008-latest-config-peer-refresh"
	oldConfig := &GroupConfig{
		Name:      "GP008 Old Config",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: senderPubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: "peerBPubKey"},
			{PeerId: nodeC.PeerId(), Role: GroupRoleWriter, PublicKey: "peerCPubKey"},
		},
		CreatedBy: nodeA.PeerId(),
	}
	currentConfig := &GroupConfig{
		Name:      "GP008 Current Config",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: senderPubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: "peerBPubKey"},
			{PeerId: nodeD.PeerId(), Role: GroupRoleWriter, PublicKey: "peerDPubKey"},
		},
		CreatedBy: nodeA.PeerId(),
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	if err := nodeB.JoinGroupTopic(groupID, currentConfig, keyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}
	if err := nodeC.JoinGroupTopic(groupID, oldConfig, keyInfo); err != nil {
		t.Fatalf("nodeC JoinGroupTopic: %v", err)
	}
	if err := nodeD.JoinGroupTopic(groupID, currentConfig, keyInfo); err != nil {
		t.Fatalf("nodeD JoinGroupTopic: %v", err)
	}

	nodeBID, err := peer.Decode(nodeB.PeerId())
	if err != nil {
		t.Fatalf("decode node B peer ID: %v", err)
	}
	nodeA.Host().Peerstore().AddAddrs(nodeBID, nodeB.Host().Addrs(), time.Hour)

	if err := nodeA.JoinGroupTopic(groupID, oldConfig, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	waitForGroupTopicPeerCount(t, nodeA, groupID, 1, 2*time.Second)

	nodeA.mu.RLock()
	topic := nodeA.groupTopics[groupID]
	initialPeers := 0
	if topic != nil {
		initialPeers = len(topic.ListPeers())
	}
	nodeA.mu.RUnlock()
	if initialPeers != 1 {
		t.Fatalf("initial topic peer count = %d, want exactly one live recipient before publish", initialPeers)
	}

	nodeCID, err := peer.Decode(nodeC.PeerId())
	if err != nil {
		t.Fatalf("decode node C peer ID: %v", err)
	}
	nodeDID, err := peer.Decode(nodeD.PeerId())
	if err != nil {
		t.Fatalf("decode node D peer ID: %v", err)
	}
	nodeA.Host().Peerstore().AddAddrs(nodeCID, nodeC.Host().Addrs(), time.Hour)
	nodeA.Host().Peerstore().AddAddrs(nodeDID, nodeD.Host().Addrs(), time.Hour)

	nodeA.UpdateGroupConfig(groupID, currentConfig)

	senderBaseline := len(nodeACapture.snapshot())
	nodeBBaseline := len(nodeBCapture.snapshot())
	nodeCBaseline := len(nodeCCapture.snapshot())
	nodeDBaseline := len(nodeDCapture.snapshot())
	messageID := "gp008-latest-config-message"
	msgID, peerCount, err := nodeA.PublishGroupMessage(
		groupID,
		senderPrivB64,
		nodeA.PeerId(),
		senderPubB64,
		"Alice",
		"GP-008 publish refresh uses latest config",
		messageID,
		nil,
	)
	if err != nil {
		t.Fatalf("PublishGroupMessage: %v", err)
	}
	if msgID != messageID {
		t.Fatalf("messageId = %q, want %q", msgID, messageID)
	}
	if peerCount < 2 {
		t.Fatalf("peerCount = %d, want refresh to promote newly added member", peerCount)
	}

	waitDiscoveryStepAfter := func(step string) map[string]interface{} {
		t.Helper()
		deadline := time.Now().Add(3 * time.Second)
		for time.Now().Before(deadline) {
			for _, raw := range nodeACapture.snapshot()[senderBaseline:] {
				var payload map[string]interface{}
				if err := json.Unmarshal([]byte(raw), &payload); err != nil {
					continue
				}
				if payload["event"] != "group:discovery" {
					continue
				}
				data, _ := payload["data"].(map[string]interface{})
				if data["groupId"] == groupID && data["step"] == step {
					return data
				}
			}
			time.Sleep(25 * time.Millisecond)
		}
		t.Fatalf("timed out waiting for group %s discovery step %s after publish; events=%v", groupID, step, nodeACapture.snapshot()[senderBaseline:])
		return nil
	}
	waitDiscoveryStepAndPeerAfter := func(step string, peerID string) map[string]interface{} {
		t.Helper()
		deadline := time.Now().Add(3 * time.Second)
		for time.Now().Before(deadline) {
			for _, raw := range nodeACapture.snapshot()[senderBaseline:] {
				var payload map[string]interface{}
				if err := json.Unmarshal([]byte(raw), &payload); err != nil {
					continue
				}
				if payload["event"] != "group:discovery" {
					continue
				}
				data, _ := payload["data"].(map[string]interface{})
				if data["groupId"] == groupID && data["step"] == step && data["peerId"] == peerID {
					return data
				}
			}
			time.Sleep(25 * time.Millisecond)
		}
		t.Fatalf("timed out waiting for group %s discovery step %s peer %s after publish; events=%v", groupID, step, peerID, nodeACapture.snapshot()[senderBaseline:])
		return nil
	}
	assertNumericAtLeast := func(data map[string]interface{}, field string, wantMin int) {
		t.Helper()
		got, ok := data[field].(float64)
		if !ok || int(got) < wantMin {
			t.Fatalf("%s = %v, want >= %d in event data %#v", field, data[field], wantMin, data)
		}
	}
	assertNumericEquals := func(data map[string]interface{}, field string, want int) {
		t.Helper()
		got, ok := data[field].(float64)
		if !ok || int(got) != want {
			t.Fatalf("%s = %v, want %d in event data %#v", field, data[field], want, data)
		}
	}
	waitDirectDialSummaryAfter := func() map[string]interface{} {
		t.Helper()
		deadline := time.Now().Add(3 * time.Second)
		for time.Now().Before(deadline) {
			for _, raw := range nodeACapture.snapshot()[senderBaseline:] {
				var payload map[string]interface{}
				if err := json.Unmarshal([]byte(raw), &payload); err != nil {
					continue
				}
				if payload["event"] != "group:discovery" {
					continue
				}
				data, _ := payload["data"].(map[string]interface{})
				if data["groupId"] != groupID || data["step"] != "direct_dial" {
					continue
				}
				membersDialed, dialedOK := data["membersDialed"].(float64)
				totalMembers, totalOK := data["totalMembers"].(float64)
				if dialedOK && totalOK && int(membersDialed) >= 1 && int(totalMembers) == 2 {
					return data
				}
			}
			time.Sleep(25 * time.Millisecond)
		}
		t.Fatalf("timed out waiting for current-config direct_dial summary after publish; events=%v", nodeACapture.snapshot()[senderBaseline:])
		return nil
	}
	shortPeerID := func(peerID string) string {
		if len(peerID) > 16 {
			return peerID[:16]
		}
		return peerID
	}
	nodeCShort := shortPeerID(nodeC.PeerId())
	nodeDShort := shortPeerID(nodeD.PeerId())
	if nodeCShort == nodeDShort {
		t.Fatalf("node C and D short peer IDs collided: %s", nodeCShort)
	}

	beginData := waitDiscoveryStepAfter("publish_peer_refresh_begin")
	assertNumericEquals(beginData, "topicPeers", 1)
	assertNumericEquals(beginData, "expectedPeers", 2)

	successData := waitDiscoveryStepAndPeerAfter("known_member_dial_success", nodeDShort)
	if successData["path"] != "direct" {
		t.Fatalf("known_member_dial_success path = %v, want direct", successData["path"])
	}
	directData := waitDirectDialSummaryAfter()
	assertNumericAtLeast(directData, "membersDialed", 1)
	assertNumericEquals(directData, "totalMembers", 2)
	doneData := waitDiscoveryStepAfter("publish_peer_refresh_done")
	assertNumericEquals(doneData, "expectedPeers", 2)
	assertNumericAtLeast(doneData, "topicPeers", 2)
	if promoted, ok := doneData["promoted"].(bool); !ok || !promoted {
		t.Fatalf("promoted = %v, want true in event data %#v", doneData["promoted"], doneData)
	}

	for _, forbiddenStep := range []string{
		"known_member_dial_success",
		"known_member_topic_missing",
		"known_member_dial_failed",
		"direct_dial_skipped_inflight",
		"direct_dial_skipped_cooldown",
	} {
		assertNoDiscoveryStepAndPeerAfter(t, nodeACapture, senderBaseline, groupID, forbiddenStep, nodeCShort, 300*time.Millisecond)
	}

	bEvent := waitForCollectedEventAfter(t, nodeBCapture, nodeBBaseline, "group_message:received", 5*time.Second)
	dEvent := waitForCollectedEventAfter(t, nodeDCapture, nodeDBaseline, "group_message:received", 5*time.Second)
	for label, event := range map[string]map[string]interface{}{
		"nodeB": bEvent,
		"nodeD": dEvent,
	} {
		if event["messageId"] != messageID {
			t.Fatalf("%s messageId = %v, want %s", label, event["messageId"], messageID)
		}
		if event["text"] != "GP-008 publish refresh uses latest config" {
			t.Fatalf("%s text = %v", label, event["text"])
		}
	}
	assertNoCollectedEventContainingAfter(t, nodeCCapture, nodeCBaseline, messageID, 500*time.Millisecond)
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

func TestNW001FullMeshDirectGroupDeliveryWithoutRelayFallback(t *testing.T) {
	alicePrivB64, alicePubB64 := generateEd25519KeyPair(t)
	bobPrivB64, bobPubB64 := generateEd25519KeyPair(t)
	charliePrivB64, charliePubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeACapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeB := startLocalNodeForMultiRelayTest(t)
	nodeC := startLocalNodeForMultiRelayTest(t)

	groupId := "nw001-full-mesh-direct-no-relay"
	config := &GroupConfig{
		Name:      "NW-001 Full Mesh Direct Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: alicePubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: bobPubB64},
			{PeerId: nodeC.PeerId(), Role: GroupRoleWriter, PublicKey: charliePubB64},
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
		if err := n.JoinGroupTopic(groupId, config, keyInfo); err != nil {
			t.Fatalf("%s JoinGroupTopic: %v", n.PeerId(), err)
		}
	}

	for _, n := range []*Node{nodeA, nodeB, nodeC} {
		waitForGroupTopicPeerCount(t, n, groupId, 2, 3*time.Second)
	}

	for _, tc := range []struct {
		name       string
		node       *Node
		privateKey string
		publicKey  string
		username   string
		messageId  string
		text       string
	}{
		{
			name:       "alice",
			node:       nodeA,
			privateKey: alicePrivB64,
			publicKey:  alicePubB64,
			username:   "Alice",
			messageId:  "nw001-go-alice",
			text:       "NW-001 direct full mesh from Alice",
		},
		{
			name:       "bob",
			node:       nodeB,
			privateKey: bobPrivB64,
			publicKey:  bobPubB64,
			username:   "Bob",
			messageId:  "nw001-go-bob",
			text:       "NW-001 direct full mesh from Bob",
		},
		{
			name:       "charlie",
			node:       nodeC,
			privateKey: charliePrivB64,
			publicKey:  charliePubB64,
			username:   "Charlie",
			messageId:  "nw001-go-charlie",
			text:       "NW-001 direct full mesh from Charlie",
		},
	} {
		msgID, peerCount, err := tc.node.PublishGroupMessage(
			groupId,
			tc.privateKey,
			tc.node.PeerId(),
			tc.publicKey,
			tc.username,
			tc.text,
			"",
			map[string]interface{}{"messageId": tc.messageId},
		)
		if err != nil {
			t.Fatalf("%s PublishGroupMessage failed: %v", tc.name, err)
		}
		if msgID == "" {
			t.Fatalf("%s PublishGroupMessage returned empty messageId", tc.name)
		}
		if peerCount < 2 {
			t.Fatalf("%s topicPeers=%d, want >=2 for NW-001 full mesh", tc.name, peerCount)
		}
	}
}

func TestNW002RelayOnlyOrCircuitRoutedPeerReceivesGroupMessages(t *testing.T) {
	alicePrivB64, alicePubB64 := generateEd25519KeyPair(t)
	bobPrivB64, bobPubB64 := generateEd25519KeyPair(t)
	_, charliePubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	_, relayAddr := startNW002LocalCircuitRelay(t)
	nodeACapture := &testEventCollector{}
	nodeBCapture := &testEventCollector{}
	nodeCCapture := &testEventCollector{}
	nodeA := startNW002RelayNode(t, relayAddr, nodeACapture)
	nodeB := startNW002RelayNode(t, relayAddr, nodeBCapture)
	nodeC := startNW002RelayNode(t, relayAddr, nodeCCapture)

	groupId := "nw002-relay-only-or-circuit-routed"
	config := &GroupConfig{
		Name:      "NW-002 Relay Only Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: alicePubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: bobPubB64},
			{PeerId: nodeC.PeerId(), Role: GroupRoleWriter, PublicKey: charliePubB64},
		},
		CreatedBy: nodeA.PeerId(),
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	for _, n := range []*Node{nodeA, nodeB, nodeC} {
		if err := n.JoinGroupTopic(groupId, config, keyInfo); err != nil {
			t.Fatalf("%s JoinGroupTopic: %v", n.PeerId(), err)
		}
		cancelNW002GroupDiscovery(t, n, groupId)
	}

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
		clearNW002DirectRouteState(t, pair.from, pair.to)
		assertNW002NoDirectPeerstoreAddrs(t, pair.from, pair.to)
		if err := pair.from.DialPeerViaRelay(pair.to.PeerId()); err != nil {
			t.Fatalf("%s circuit dial to %s: %v", pair.from.PeerId(), pair.to.PeerId(), err)
		}
		assertNW002LimitedCircuitConn(t, pair.from, pair.to)
	}

	for _, n := range []*Node{nodeA, nodeB, nodeC} {
		waitForGroupTopicPeerCount(t, n, groupId, 2, 10*time.Second)
	}

	aliceMsgID, alicePeerCount, err := nodeA.PublishGroupMessage(
		groupId,
		alicePrivB64,
		nodeA.PeerId(),
		alicePubB64,
		"Alice",
		"NW-002 Alice to relay-only Bob",
		"nw002-go-alice-to-relay-only-bob",
		nil,
	)
	if err != nil {
		t.Fatalf("Alice PublishGroupMessage failed: %v", err)
	}
	if aliceMsgID == "" {
		t.Fatal("Alice PublishGroupMessage returned empty messageId")
	}
	if alicePeerCount < 2 {
		t.Fatalf("Alice topicPeers=%d, want >=2 through circuit relay", alicePeerCount)
	}
	bobAfterAlice := waitForCollectedEventCount(t, nodeBCapture, "group_message:received", 1, 5*time.Second)
	charlieAfterAlice := waitForCollectedEventCount(t, nodeCCapture, "group_message:received", 1, 5*time.Second)
	assertNW002ReceivedText(t, bobAfterAlice, "NW-002 Alice to relay-only Bob", nodeA.PeerId())
	assertNW002ReceivedText(t, charlieAfterAlice, "NW-002 Alice to relay-only Bob", nodeA.PeerId())

	bobMsgID, bobPeerCount, err := nodeB.PublishGroupMessage(
		groupId,
		bobPrivB64,
		nodeB.PeerId(),
		bobPubB64,
		"Bob",
		"NW-002 Bob relay-only publish back",
		"nw002-go-bob-relay-publish-back",
		nil,
	)
	if err != nil {
		t.Fatalf("Bob PublishGroupMessage failed: %v", err)
	}
	if bobMsgID == "" {
		t.Fatal("Bob PublishGroupMessage returned empty messageId")
	}
	if bobPeerCount < 2 {
		t.Fatalf("Bob topicPeers=%d, want >=2 through circuit relay", bobPeerCount)
	}
	aliceAfterBob := waitForCollectedEventCount(t, nodeACapture, "group_message:received", 1, 5*time.Second)
	charlieAfterBob := waitForCollectedEventCount(t, nodeCCapture, "group_message:received", 2, 5*time.Second)
	assertNW002ReceivedText(t, aliceAfterBob, "NW-002 Bob relay-only publish back", nodeB.PeerId())
	assertNW002ReceivedText(t, charlieAfterBob, "NW-002 Bob relay-only publish back", nodeB.PeerId())
}

func TestNW003PartitionDuringRemoveReaddHealsToLatestTopicState(t *testing.T) {
	alicePrivB64, alicePubB64 := generateEd25519KeyPair(t)
	bobPrivB64, bobPubB64 := generateEd25519KeyPair(t)
	charliePrivB64, charliePubB64 := generateEd25519KeyPair(t)
	initialGroupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate initial group key: %v", err)
	}
	removedGroupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate removed group key: %v", err)
	}
	readdedGroupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate readded group key: %v", err)
	}

	nodeACapture := &testEventCollector{}
	nodeBCapture := &testEventCollector{}
	nodeCCapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)
	nodeC := startLocalNodeForMultiRelayTestWithCollector(t, nodeCCapture)

	groupId := "nw003-partition-remove-readd-heal"
	initialConfig := &GroupConfig{
		Name:      "NW-003 Partition Readd",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: alicePubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: bobPubB64},
			{PeerId: nodeC.PeerId(), Role: GroupRoleWriter, PublicKey: charliePubB64},
		},
		CreatedBy: nodeA.PeerId(),
	}
	initialKey := &GroupKeyInfo{Key: initialGroupKey, KeyEpoch: 1}
	for _, n := range []*Node{nodeA, nodeB, nodeC} {
		if err := n.JoinGroupTopic(groupId, initialConfig, initialKey); err != nil {
			t.Fatalf("%s initial JoinGroupTopic: %v", n.PeerId(), err)
		}
	}
	connectLocalGroupNodes(t, nodeA, nodeB)
	connectLocalGroupNodes(t, nodeA, nodeC)
	connectLocalGroupNodes(t, nodeB, nodeC)
	for _, n := range []*Node{nodeA, nodeB, nodeC} {
		waitForGroupTopicPeerCount(t, n, groupId, 2, 5*time.Second)
	}

	msgID, peerCount, err := nodeA.PublishGroupMessage(
		groupId,
		alicePrivB64,
		nodeA.PeerId(),
		alicePubB64,
		"Alice",
		"NW-003 baseline before partition",
		"nw003-go-baseline",
		nil,
	)
	if err != nil {
		t.Fatalf("Alice baseline PublishGroupMessage: %v", err)
	}
	if msgID == "" || peerCount < 2 {
		t.Fatalf("baseline publish returned msgID=%q peerCount=%d, want non-empty/>=2", msgID, peerCount)
	}
	assertNW002ReceivedText(
		t,
		waitForCollectedEventCount(t, nodeBCapture, "group_message:received", 1, 5*time.Second),
		"NW-003 baseline before partition",
		nodeA.PeerId(),
	)
	assertNW002ReceivedText(
		t,
		waitForCollectedEventCount(t, nodeCCapture, "group_message:received", 1, 5*time.Second),
		"NW-003 baseline before partition",
		nodeA.PeerId(),
	)

	clearNW002DirectRouteState(t, nodeA, nodeB)
	clearNW002DirectRouteState(t, nodeA, nodeC)

	removedConfig := &GroupConfig{
		Name:      "NW-003 Partition Readd",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: alicePubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: bobPubB64},
		},
		CreatedBy: nodeA.PeerId(),
	}
	removedKey := &GroupKeyInfo{Key: removedGroupKey, KeyEpoch: 2}
	for _, n := range []*Node{nodeA, nodeB, nodeC} {
		if updated, err := n.RefreshJoinedGroupStateIfNewer(groupId, removedConfig, removedKey); err != nil {
			t.Fatalf("%s removed RefreshJoinedGroupStateIfNewer: %v", n.PeerId(), err)
		} else if !updated {
			t.Fatalf("%s did not accept removed epoch refresh", n.PeerId())
		}
	}
	if msgID, peerCount, err = nodeC.PublishGroupMessage(
		groupId,
		charliePrivB64,
		nodeC.PeerId(),
		charliePubB64,
		"Charlie",
		"NW-003 Charlie removed-window publish should fail",
		"nw003-go-charlie-removed-window",
		nil,
	); err == nil {
		t.Fatalf("Charlie removed-window publish unexpectedly succeeded msgID=%q peerCount=%d", msgID, peerCount)
	}

	readdedConfig := &GroupConfig{
		Name:      "NW-003 Partition Readd",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: alicePubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: bobPubB64},
			{PeerId: nodeC.PeerId(), Role: GroupRoleWriter, PublicKey: charliePubB64},
		},
		CreatedBy: nodeA.PeerId(),
	}
	readdedKey := &GroupKeyInfo{Key: readdedGroupKey, KeyEpoch: 3}
	for _, n := range []*Node{nodeA, nodeB, nodeC} {
		if updated, err := n.RefreshJoinedGroupStateIfNewer(groupId, readdedConfig, readdedKey); err != nil {
			t.Fatalf("%s readded RefreshJoinedGroupStateIfNewer: %v", n.PeerId(), err)
		} else if !updated {
			t.Fatalf("%s did not accept readded epoch refresh", n.PeerId())
		}
	}
	connectLocalGroupNodes(t, nodeA, nodeB)
	connectLocalGroupNodes(t, nodeA, nodeC)
	connectLocalGroupNodes(t, nodeB, nodeC)
	for _, n := range []*Node{nodeA, nodeB, nodeC} {
		waitForGroupTopicPeerCount(t, n, groupId, 2, 10*time.Second)
	}

	_, peerCount, err = nodeA.PublishGroupMessage(
		groupId,
		alicePrivB64,
		nodeA.PeerId(),
		alicePubB64,
		"Alice",
		"NW-003 Alice current after heal",
		"nw003-go-alice-current",
		nil,
	)
	if err != nil || peerCount < 2 {
		t.Fatalf("Alice current publish err=%v peerCount=%d, want nil/>=2", err, peerCount)
	}
	_, peerCount, err = nodeB.PublishGroupMessage(
		groupId,
		bobPrivB64,
		nodeB.PeerId(),
		bobPubB64,
		"Bob",
		"NW-003 Bob current after heal",
		"nw003-go-bob-current",
		nil,
	)
	if err != nil || peerCount < 2 {
		t.Fatalf("Bob current publish err=%v peerCount=%d, want nil/>=2", err, peerCount)
	}
	_, peerCount, err = nodeC.PublishGroupMessage(
		groupId,
		charliePrivB64,
		nodeC.PeerId(),
		charliePubB64,
		"Charlie",
		"NW-003 Charlie current after heal",
		"nw003-go-charlie-current",
		nil,
	)
	if err != nil || peerCount < 2 {
		t.Fatalf("Charlie current publish err=%v peerCount=%d, want nil/>=2", err, peerCount)
	}

	assertNW002ReceivedText(
		t,
		waitForCollectedEventCount(t, nodeBCapture, "group_message:received", 3, 5*time.Second),
		"NW-003 Charlie current after heal",
		nodeC.PeerId(),
	)
	assertNW002ReceivedText(
		t,
		waitForCollectedEventCount(t, nodeCCapture, "group_message:received", 3, 5*time.Second),
		"NW-003 Bob current after heal",
		nodeB.PeerId(),
	)
	assertNW002ReceivedText(
		t,
		waitForCollectedEventCount(t, nodeACapture, "group_message:received", 2, 5*time.Second),
		"NW-003 Charlie current after heal",
		nodeC.PeerId(),
	)
}

func TestGA001CurrentMemberPublishesPrivateChatMessageExactlyOnce(t *testing.T) {
	groupId := "ga001-current-member-private-chat"
	harness := setupLP013TwoNodeGroup(t, groupId)
	messageId := "ga001-current-member-message"
	text := "GA-001 current member private chat delivery"

	baseline := len(harness.nodeBCapture.snapshot())
	msgID, peerCount, err := harness.nodeA.PublishGroupMessage(
		groupId,
		harness.privB64,
		harness.nodeA.PeerId(),
		harness.pubB64,
		"Alice",
		text,
		messageId,
		nil,
	)
	if err != nil {
		t.Fatalf("PublishGroupMessage: %v", err)
	}
	if msgID != messageId {
		t.Fatalf("messageId = %q, want %q", msgID, messageId)
	}
	if peerCount < 1 {
		t.Fatalf("expected topicPeers >= 1, got %d", peerCount)
	}

	event := waitForCollectedEventAfter(t, harness.nodeBCapture, baseline, "group_message:received", 5*time.Second)
	for _, tc := range []struct {
		key  string
		want interface{}
	}{
		{key: "groupId", want: groupId},
		{key: "senderId", want: harness.nodeA.PeerId()},
		{key: "senderUsername", want: "Alice"},
		{key: "messageId", want: messageId},
		{key: "text", want: text},
		{key: "keyEpoch", want: float64(harness.keyInfo.KeyEpoch)},
	} {
		if got := event[tc.key]; got != tc.want {
			t.Fatalf("%s = %v, want %v", tc.key, got, tc.want)
		}
	}

	time.Sleep(500 * time.Millisecond)
	receivedCount := 0
	for _, raw := range harness.nodeBCapture.snapshot()[baseline:] {
		var payload map[string]interface{}
		if err := json.Unmarshal([]byte(raw), &payload); err != nil {
			continue
		}
		if payload["event"] != "group_message:received" {
			continue
		}
		data, _ := payload["data"].(map[string]interface{})
		if data["messageId"] == messageId {
			receivedCount++
		}
	}
	if receivedCount != 1 {
		t.Fatalf("group_message:received count for %q = %d, want exactly 1", messageId, receivedCount)
	}
}

func TestGA003RemovedMemberCannotPublishWithOldConfigKey(t *testing.T) {
	_, pubA := generateEd25519KeyPair(t)
	_, pubB := generateEd25519KeyPair(t)
	privC, pubC := generateEd25519KeyPair(t)
	epoch1Key, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate epoch 1 group key: %v", err)
	}
	epoch2Key, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate epoch 2 group key: %v", err)
	}

	nodeACapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)
	nodeC := startLocalNodeForMultiRelayTest(t)

	groupId := "ga003-removed-member-old-config-key"
	epoch1Info := &GroupKeyInfo{Key: epoch1Key, KeyEpoch: 1}
	configWithC := &GroupConfig{
		Name:      "GA003 Initial Private Chat",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: pubA},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: pubB},
			{PeerId: nodeC.PeerId(), Role: GroupRoleWriter, PublicKey: pubC},
		},
		CreatedBy: nodeA.PeerId(),
	}
	configWithoutC := &GroupConfig{
		Name:      "GA003 Current Private Chat",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: pubA},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: pubB},
		},
		CreatedBy: nodeA.PeerId(),
	}

	for _, join := range []struct {
		label string
		node  *Node
	}{
		{label: "nodeA", node: nodeA},
		{label: "nodeB", node: nodeB},
		{label: "nodeC", node: nodeC},
	} {
		if err := join.node.JoinGroupTopic(groupId, configWithC, epoch1Info); err != nil {
			t.Fatalf("%s JoinGroupTopic: %v", join.label, err)
		}
	}

	connectLocalGroupNodes(t, nodeC, nodeA)
	connectLocalGroupNodes(t, nodeC, nodeB)
	connectLocalGroupNodes(t, nodeA, nodeB)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 2, 3*time.Second)
	waitForGroupTopicPeerCount(t, nodeB, groupId, 2, 3*time.Second)
	waitForGroupTopicPeerCount(t, nodeC, groupId, 2, 3*time.Second)

	nodeA.UpdateGroupConfig(groupId, configWithoutC)
	nodeB.UpdateGroupConfig(groupId, configWithoutC)
	nodeA.UpdateGroupKey(groupId, &GroupKeyInfo{Key: epoch2Key, KeyEpoch: 2})
	nodeB.UpdateGroupKey(groupId, &GroupKeyInfo{Key: epoch2Key, KeyEpoch: 2})

	nodeC.mu.RLock()
	staleConfig := nodeC.groupConfigs[groupId]
	staleKeyInfo := nodeC.groupKeys[groupId]
	_, charlieStillJoined := nodeC.groupTopics[groupId]
	nodeC.mu.RUnlock()
	if !charlieStillJoined || findMember(staleConfig, nodeC.PeerId()) == nil {
		t.Fatal("nodeC must remain locally joined with stale membership state")
	}
	if staleKeyInfo == nil || staleKeyInfo.KeyEpoch != epoch1Info.KeyEpoch {
		t.Fatalf("nodeC stale key epoch = %#v, want epoch %d", staleKeyInfo, epoch1Info.KeyEpoch)
	}

	plaintextMarker := "ga003-charlie-old-config-key"
	oldEnvelope := buildTestEnvelopeWithPlaintext(
		t,
		groupId,
		"group_message",
		nodeC.PeerId(),
		privC,
		pubC,
		epoch1Key,
		epoch1Info.KeyEpoch,
		`{"text":"`+plaintextMarker+`","timestamp":"2026-05-12T19:45:45Z"}`,
	)
	nodeA.mu.RLock()
	currentKeyInfo := nodeA.groupKeys[groupId]
	nodeA.mu.RUnlock()
	if result := validateGroupEnvelopeForTransportPeer(oldEnvelope, groupId, configWithoutC, currentKeyInfo, nodeC.PeerId()); result != "reject:non_member" {
		t.Fatalf("pure validator = %s, want reject:non_member", result)
	}

	baselineA := len(nodeACapture.snapshot())
	baselineB := len(nodeBCapture.snapshot())
	msgID, peerCount, err := nodeC.PublishGroupMessage(
		groupId,
		privC,
		nodeC.PeerId(),
		pubC,
		"Charlie",
		plaintextMarker,
		"ga003-charlie-stale-message",
		nil,
	)
	if err != nil {
		t.Fatalf("nodeC stale PublishGroupMessage: %v", err)
	}
	if msgID == "" || peerCount < 2 {
		t.Fatalf("stale publish returned msgID=%q peerCount=%d, want non-empty/>=2", msgID, peerCount)
	}

	allowedRejectReasons := []string{"non_member", "bad_signature_or_epoch"}
	waitForCollectedValidationRejectAny(t, nodeACapture, baselineA, allowedRejectReasons, epoch1Info.KeyEpoch, 5*time.Second)
	waitForCollectedValidationRejectAny(t, nodeBCapture, baselineB, allowedRejectReasons, epoch1Info.KeyEpoch, 5*time.Second)
	for _, check := range []struct {
		label     string
		collector *testEventCollector
		baseline  int
	}{
		{label: "node A", collector: nodeACapture, baseline: baselineA},
		{label: "node B", collector: nodeBCapture, baseline: baselineB},
	} {
		for _, forbidden := range []string{
			`"event":"group_message:received"`,
			`"event":"group_reaction:received"`,
			`"event":"group:decryption_failed"`,
			`"event":"group:payload_parse_failed"`,
			plaintextMarker,
		} {
			t.Run(check.label+"/"+forbidden, func(t *testing.T) {
				assertNoCollectedEventContainingAfter(t, check.collector, check.baseline, forbidden, 500*time.Millisecond)
			})
		}
	}
}

func TestGA005RoleUpdateTakesEffectWithoutTopicRejoin(t *testing.T) {
	_, pubA := generateEd25519KeyPair(t)
	privB, pubB := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeACapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeB := startLocalNodeForMultiRelayTest(t)

	groupId := "ga005-role-update-without-topic-rejoin"
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	configBWriter := &GroupConfig{
		Name:      "GA005 Announcement Writer",
		GroupType: GroupTypeAnnouncement,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: pubA},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: pubB},
		},
		CreatedBy: nodeA.PeerId(),
	}
	configBAdmin := &GroupConfig{
		Name:      "GA005 Announcement Admin",
		GroupType: GroupTypeAnnouncement,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: pubA},
			{PeerId: nodeB.PeerId(), Role: GroupRoleAdmin, PublicKey: pubB},
		},
		CreatedBy: nodeA.PeerId(),
	}

	if err := nodeA.JoinGroupTopic(groupId, configBWriter, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, configBWriter, keyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}
	connectLocalGroupNodes(t, nodeB, nodeA)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 3*time.Second)
	waitForGroupTopicPeerCount(t, nodeB, groupId, 1, 3*time.Second)

	nodeA.mu.RLock()
	nodeATopicBefore := nodeA.groupTopics[groupId]
	nodeA.mu.RUnlock()
	nodeB.mu.RLock()
	nodeBTopicBefore := nodeB.groupTopics[groupId]
	nodeB.mu.RUnlock()
	if nodeATopicBefore == nil || nodeBTopicBefore == nil {
		t.Fatal("both nodes must be joined before GA-005 role updates")
	}

	writerMarker := "ga005-writer-before-promotion"
	writerEnvelope := buildTestEnvelopeWithPlaintext(
		t,
		groupId,
		"group_message",
		nodeB.PeerId(),
		privB,
		pubB,
		groupKey,
		keyInfo.KeyEpoch,
		`{"text":"`+writerMarker+`","timestamp":"2026-05-12T19:57:15Z"}`,
	)
	if result := validateGroupEnvelopeForTransportPeer(writerEnvelope, groupId, configBWriter, keyInfo, nodeB.PeerId()); result != "reject:unauthorized" {
		t.Fatalf("writer pure validation before promotion = %s, want reject:unauthorized", result)
	}
	if result := validateGroupEnvelopeForTransportPeer(writerEnvelope, groupId, configBAdmin, keyInfo, nodeB.PeerId()); result != "accept" {
		t.Fatalf("writer pure validation after promotion = %s, want accept", result)
	}
	if _, _, err := nodeB.PublishGroupMessage(
		groupId,
		privB,
		nodeB.PeerId(),
		pubB,
		"Bob",
		writerMarker,
		"ga005-writer-before-promotion-message",
		nil,
	); err == nil || !strings.Contains(err.Error(), "not allowed to write") {
		t.Fatalf("writer PublishGroupMessage before promotion error = %v, want not allowed to write", err)
	}

	nodeA.UpdateGroupConfig(groupId, configBAdmin)
	nodeB.UpdateGroupConfig(groupId, configBAdmin)
	nodeA.mu.RLock()
	nodeATopicAfterPromotion := nodeA.groupTopics[groupId]
	nodeA.mu.RUnlock()
	nodeB.mu.RLock()
	nodeBTopicAfterPromotion := nodeB.groupTopics[groupId]
	nodeB.mu.RUnlock()
	if nodeATopicAfterPromotion != nodeATopicBefore || nodeBTopicAfterPromotion != nodeBTopicBefore {
		t.Fatal("UpdateGroupConfig promotion must not replace or drop the joined topic")
	}

	adminMarker := "ga005-admin-after-promotion"
	adminBaseline := len(nodeACapture.snapshot())
	msgID, peerCount, err := nodeB.PublishGroupMessage(
		groupId,
		privB,
		nodeB.PeerId(),
		pubB,
		"Bob",
		adminMarker,
		"ga005-admin-after-promotion-message",
		nil,
	)
	if err != nil {
		t.Fatalf("admin PublishGroupMessage after promotion: %v", err)
	}
	if msgID != "ga005-admin-after-promotion-message" || peerCount < 1 {
		t.Fatalf("admin publish returned msgID=%q peerCount=%d, want provided id/>=1", msgID, peerCount)
	}
	received := waitForCollectedEventAfter(t, nodeACapture, adminBaseline, "group_message:received", 5*time.Second)
	for _, tc := range []struct {
		key  string
		want interface{}
	}{
		{key: "groupId", want: groupId},
		{key: "senderId", want: nodeB.PeerId()},
		{key: "senderUsername", want: "Bob"},
		{key: "messageId", want: "ga005-admin-after-promotion-message"},
		{key: "text", want: adminMarker},
		{key: "keyEpoch", want: float64(keyInfo.KeyEpoch)},
	} {
		if got := received[tc.key]; got != tc.want {
			t.Fatalf("%s = %v, want %v", tc.key, got, tc.want)
		}
	}
	assertNoCollectedEventContainingAfter(t, nodeACapture, adminBaseline, `"event":"group:validation_rejected"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeACapture, adminBaseline, `"event":"group:decryption_failed"`, 500*time.Millisecond)

	nodeA.UpdateGroupConfig(groupId, configBWriter)
	nodeA.mu.RLock()
	nodeATopicAfterDemotion := nodeA.groupTopics[groupId]
	nodeA.mu.RUnlock()
	nodeB.mu.RLock()
	nodeBTopicBeforeLocalDemotion := nodeB.groupTopics[groupId]
	nodeB.mu.RUnlock()
	if nodeATopicAfterDemotion != nodeATopicBefore || nodeBTopicBeforeLocalDemotion != nodeBTopicBefore {
		t.Fatal("receiver-side UpdateGroupConfig demotion must not replace or drop the joined topic")
	}

	demotedMarker := "ga005-writer-after-demotion"
	demotedEnvelope := buildTestEnvelopeWithPlaintext(
		t,
		groupId,
		"group_message",
		nodeB.PeerId(),
		privB,
		pubB,
		groupKey,
		keyInfo.KeyEpoch,
		`{"text":"`+demotedMarker+`","timestamp":"2026-05-12T19:57:16Z"}`,
	)
	if result := validateGroupEnvelopeForTransportPeer(demotedEnvelope, groupId, configBWriter, keyInfo, nodeB.PeerId()); result != "reject:unauthorized" {
		t.Fatalf("writer pure validation after demotion = %s, want reject:unauthorized", result)
	}

	demotedBaseline := len(nodeACapture.snapshot())
	msgID, peerCount, err = nodeB.PublishGroupMessage(
		groupId,
		privB,
		nodeB.PeerId(),
		pubB,
		"Bob",
		demotedMarker,
		"ga005-writer-after-demotion-stale-local-message",
		nil,
	)
	if err != nil {
		t.Fatalf("stale local admin PublishGroupMessage after receiver demotion: %v", err)
	}
	if msgID != "ga005-writer-after-demotion-stale-local-message" || peerCount < 1 {
		t.Fatalf("stale local admin publish returned msgID=%q peerCount=%d, want provided id/>=1", msgID, peerCount)
	}
	waitForCollectedValidationReject(t, nodeACapture, demotedBaseline, "unauthorized_writer", keyInfo.KeyEpoch, 5*time.Second)
	for _, forbidden := range []string{
		`"event":"group_message:received"`,
		`"event":"group_reaction:received"`,
		`"event":"group:decryption_failed"`,
		`"event":"group:payload_parse_failed"`,
		demotedMarker,
	} {
		t.Run("demoted writer rejected/"+forbidden, func(t *testing.T) {
			assertNoCollectedEventContainingAfter(t, nodeACapture, demotedBaseline, forbidden, 500*time.Millisecond)
		})
	}

	nodeB.UpdateGroupConfig(groupId, configBWriter)
	nodeB.mu.RLock()
	nodeBTopicAfterLocalDemotion := nodeB.groupTopics[groupId]
	nodeB.mu.RUnlock()
	if nodeBTopicAfterLocalDemotion != nodeBTopicBefore {
		t.Fatal("local UpdateGroupConfig demotion must not replace or drop the joined topic")
	}
	if _, _, err := nodeB.PublishGroupMessage(
		groupId,
		privB,
		nodeB.PeerId(),
		pubB,
		"Bob",
		demotedMarker,
		"ga005-writer-after-demotion-local-message",
		nil,
	); err == nil || !strings.Contains(err.Error(), "not allowed to write") {
		t.Fatalf("writer PublishGroupMessage after demotion error = %v, want not allowed to write", err)
	}
}

func TestGA007LegacySingleDeviceMemberAcceptsDefaultDeviceBinding(t *testing.T) {
	_, pubA := generateEd25519KeyPair(t)
	privB, pubB := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeACapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeB := startLocalNodeForMultiRelayTest(t)

	groupId := "ga007-legacy-single-device-default-binding"
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	config := &GroupConfig{
		Name:      "GA007 Legacy Private Chat",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: pubA},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: pubB},
		},
		CreatedBy: nodeA.PeerId(),
	}

	if err := nodeA.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}
	connectLocalGroupNodes(t, nodeB, nodeA)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 3*time.Second)
	waitForGroupTopicPeerCount(t, nodeB, groupId, 1, 3*time.Second)

	cases := []struct {
		name     string
		marker   string
		envelope func() string
	}{
		{
			name:   "omitted binding fields",
			marker: "ga007-omitted-default-binding",
			envelope: func() string {
				return buildTestEnvelopeWithPlaintext(
					t,
					groupId,
					"group_message",
					nodeB.PeerId(),
					privB,
					pubB,
					groupKey,
					keyInfo.KeyEpoch,
					`{"text":"ga007-omitted-default-binding","timestamp":"2026-05-12T20:06:00Z"}`,
				)
			},
		},
		{
			name:   "explicit peer default binding",
			marker: "ga007-explicit-peer-default-binding",
			envelope: func() string {
				envelopeJSON := buildTestEnvelopeWithPlaintext(
					t,
					groupId,
					"group_message",
					nodeB.PeerId(),
					privB,
					pubB,
					groupKey,
					keyInfo.KeyEpoch,
					`{"text":"ga007-explicit-peer-default-binding","timestamp":"2026-05-12T20:06:01Z"}`,
				)
				envelopeJSON = setGroupEnvelopeJSONField(t, envelopeJSON, "senderDeviceId", nodeB.PeerId())
				envelopeJSON = setGroupEnvelopeJSONField(t, envelopeJSON, "senderTransportPeerId", nodeB.PeerId())
				return setGroupEnvelopeJSONField(t, envelopeJSON, "senderDevicePublicKey", pubB)
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			envelopeJSON := tc.envelope()
			if result := validateGroupEnvelopeForTransportPeer(envelopeJSON, groupId, config, keyInfo, nodeB.PeerId()); result != "accept" {
				t.Fatalf("pure validator = %s, want accept", result)
			}

			baseline := len(nodeACapture.snapshot())
			publishRawGroupEnvelope(t, nodeB, groupId, envelopeJSON)
			event := waitForCollectedEventAfter(t, nodeACapture, baseline, "group_message:received", 5*time.Second)
			for _, check := range []struct {
				key  string
				want interface{}
			}{
				{key: "groupId", want: groupId},
				{key: "senderId", want: nodeB.PeerId()},
				{key: "text", want: tc.marker},
				{key: "keyEpoch", want: float64(keyInfo.KeyEpoch)},
			} {
				if got := event[check.key]; got != check.want {
					t.Fatalf("%s = %v, want %v", check.key, got, check.want)
				}
			}
			assertNoCollectedEventContainingAfter(t, nodeACapture, baseline, `"event":"group:validation_rejected"`, 500*time.Millisecond)
			assertNoCollectedEventContainingAfter(t, nodeACapture, baseline, `"event":"group:decryption_failed"`, 500*time.Millisecond)
			assertNoCollectedEventContainingAfter(t, nodeACapture, baseline, `"event":"group:payload_parse_failed"`, 500*time.Millisecond)
		})
	}
}

func TestGA008LegacySingleDeviceMemberRejectsWrongSenderDeviceID(t *testing.T) {
	_, pubA := generateEd25519KeyPair(t)
	privB, pubB := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeACapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeB := startLocalNodeForMultiRelayTest(t)

	groupId := "ga008-legacy-single-device-wrong-device"
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	config := &GroupConfig{
		Name:      "GA008 Legacy Private Chat",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: pubA},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: pubB},
		},
		CreatedBy: nodeA.PeerId(),
	}

	if err := nodeA.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}
	connectLocalGroupNodes(t, nodeB, nodeA)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 3*time.Second)
	waitForGroupTopicPeerCount(t, nodeB, groupId, 1, 3*time.Second)

	plaintextMarker := "ga008-wrong-legacy-device"
	envelopeJSON := buildTestEnvelopeWithPlaintext(
		t,
		groupId,
		"group_message",
		nodeB.PeerId(),
		privB,
		pubB,
		groupKey,
		keyInfo.KeyEpoch,
		`{"text":"`+plaintextMarker+`","timestamp":"2026-05-12T20:10:00Z"}`,
	)
	envelopeJSON = setGroupEnvelopeJSONField(t, envelopeJSON, "senderDeviceId", "ga008-not-"+nodeB.PeerId())

	if result := validateGroupEnvelopeForTransportPeer(envelopeJSON, groupId, config, keyInfo, nodeB.PeerId()); result != "reject:unbound_device" {
		t.Fatalf("pure validator = %s, want reject:unbound_device", result)
	}

	if err := nodeB.pubsub.UnregisterTopicValidator(GroupTopicPrefix + groupId); err != nil {
		t.Fatalf("nodeB unregister local validator before GA008 raw publish: %v", err)
	}

	baseline := len(nodeACapture.snapshot())
	publishRawGroupEnvelope(t, nodeB, groupId, envelopeJSON)
	waitForCollectedValidationReject(t, nodeACapture, baseline, "unbound_device", keyInfo.KeyEpoch, 5*time.Second)
	for _, forbidden := range []string{
		`"event":"group_message:received"`,
		`"event":"group_reaction:received"`,
		`"event":"group:decryption_failed"`,
		`"event":"group:payload_parse_failed"`,
		plaintextMarker,
	} {
		t.Run("wrong legacy device rejected/"+forbidden, func(t *testing.T) {
			assertNoCollectedEventContainingAfter(t, nodeACapture, baseline, forbidden, 500*time.Millisecond)
		})
	}
}

func TestGA009LegacySingleDeviceMemberRejectsWrongSenderDevicePublicKey(t *testing.T) {
	_, pubA := generateEd25519KeyPair(t)
	privB, pubB := generateEd25519KeyPair(t)
	_, wrongPub := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeACapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeB := startLocalNodeForMultiRelayTest(t)

	groupId := "ga009-legacy-single-device-wrong-device-public-key"
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	config := &GroupConfig{
		Name:      "GA009 Legacy Private Chat",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: pubA},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: pubB},
		},
		CreatedBy: nodeA.PeerId(),
	}

	if err := nodeA.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}
	connectLocalGroupNodes(t, nodeB, nodeA)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 3*time.Second)
	waitForGroupTopicPeerCount(t, nodeB, groupId, 1, 3*time.Second)

	plaintextMarker := "ga009-wrong-device-public-key"
	envelopeJSON := buildTestEnvelopeWithPlaintext(
		t,
		groupId,
		"group_message",
		nodeB.PeerId(),
		privB,
		pubB,
		groupKey,
		keyInfo.KeyEpoch,
		`{"text":"`+plaintextMarker+`","timestamp":"2026-05-12T20:14:00Z"}`,
	)
	envelopeJSON = setGroupEnvelopeJSONField(t, envelopeJSON, "senderDevicePublicKey", wrongPub)

	if result := validateGroupEnvelopeForTransportPeer(envelopeJSON, groupId, config, keyInfo, nodeB.PeerId()); result != "reject:unbound_device" {
		t.Fatalf("pure validator = %s, want reject:unbound_device", result)
	}

	if err := nodeB.pubsub.UnregisterTopicValidator(GroupTopicPrefix + groupId); err != nil {
		t.Fatalf("nodeB unregister local validator before GA009 raw publish: %v", err)
	}

	baseline := len(nodeACapture.snapshot())
	publishRawGroupEnvelope(t, nodeB, groupId, envelopeJSON)
	waitForCollectedValidationReject(t, nodeACapture, baseline, "unbound_device", keyInfo.KeyEpoch, 5*time.Second)
	for _, forbidden := range []string{
		`"event":"group_message:received"`,
		`"event":"group_reaction:received"`,
		`"event":"group:decryption_failed"`,
		`"event":"group:payload_parse_failed"`,
		plaintextMarker,
	} {
		t.Run("wrong legacy device public key rejected/"+forbidden, func(t *testing.T) {
			assertNoCollectedEventContainingAfter(t, nodeACapture, baseline, forbidden, 500*time.Millisecond)
		})
	}
}

func TestGA010MultiDeviceActiveDeviceCanPublish(t *testing.T) {
	_, pubA := generateEd25519KeyPair(t)
	devicePriv, devicePub := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeACapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeP := startLocalNodeForMultiRelayTest(t)

	groupId := "ga010-multi-device-active-device"
	memberBID := "ga010-member-b"
	deviceID := "ga010-device-s"
	keyPackageID := "ga010-kp-s"
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	config := &GroupConfig{
		Name:      "GA010 Multi Device Private Chat",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: pubA},
			{
				PeerId:    memberBID,
				Role:      GroupRoleWriter,
				PublicKey: "ga010-member-b-public-key",
				Devices: []GroupMemberDevice{
					{
						DeviceId:               deviceID,
						TransportPeerId:        nodeP.PeerId(),
						DeviceSigningPublicKey: devicePub,
						KeyPackageId:           keyPackageID,
						Status:                 "active",
					},
				},
			},
		},
		CreatedBy: nodeA.PeerId(),
	}

	if err := nodeA.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeP.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeP JoinGroupTopic: %v", err)
	}
	connectLocalGroupNodes(t, nodeP, nodeA)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 3*time.Second)
	waitForGroupTopicPeerCount(t, nodeP, groupId, 1, 3*time.Second)

	plaintextMarker := "ga010-active-device-message"
	envelopeJSON := buildTestDeviceEnvelopeWithPlaintext(
		t,
		groupId,
		"group_message",
		memberBID,
		deviceID,
		nodeP.PeerId(),
		devicePub,
		keyPackageID,
		devicePriv,
		devicePub,
		groupKey,
		keyInfo.KeyEpoch,
		`{"text":"`+plaintextMarker+`","timestamp":"2026-05-12T20:18:00Z"}`,
	)
	if result := validateGroupEnvelopeForTransportPeer(envelopeJSON, groupId, config, keyInfo, nodeP.PeerId()); result != "accept" {
		t.Fatalf("pure validator = %s, want accept", result)
	}

	baseline := len(nodeACapture.snapshot())
	publishRawGroupEnvelope(t, nodeP, groupId, envelopeJSON)
	event := waitForCollectedEventAfter(t, nodeACapture, baseline, "group_message:received", 5*time.Second)
	for _, check := range []struct {
		key  string
		want interface{}
	}{
		{key: "groupId", want: groupId},
		{key: "senderId", want: memberBID},
		{key: "senderDeviceId", want: deviceID},
		{key: "transportPeerId", want: nodeP.PeerId()},
		{key: "text", want: plaintextMarker},
		{key: "keyEpoch", want: float64(keyInfo.KeyEpoch)},
	} {
		if got := event[check.key]; got != check.want {
			t.Fatalf("%s = %v, want %v", check.key, got, check.want)
		}
	}
	assertNoCollectedEventContainingAfter(t, nodeACapture, baseline, `"event":"group:validation_rejected"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeACapture, baseline, `"event":"group:decryption_failed"`, 500*time.Millisecond)
}

func TestGA011MultiDeviceMissingSenderDeviceIDRejects(t *testing.T) {
	_, pubA := generateEd25519KeyPair(t)
	devicePriv, devicePub := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeACapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeP := startLocalNodeForMultiRelayTest(t)

	groupId := "ga011-missing-sender-device-id"
	memberBID := "ga011-member-b"
	deviceID := "ga011-device-s"
	keyPackageID := "ga011-kp-s"
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	config := &GroupConfig{
		Name:      "GA011 Missing Device ID Private Chat",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: pubA},
			{
				PeerId:    memberBID,
				Role:      GroupRoleWriter,
				PublicKey: "ga011-member-b-public-key",
				Devices: []GroupMemberDevice{
					{
						DeviceId:               deviceID,
						TransportPeerId:        nodeP.PeerId(),
						DeviceSigningPublicKey: devicePub,
						KeyPackageId:           keyPackageID,
						Status:                 "active",
					},
				},
			},
		},
		CreatedBy: nodeA.PeerId(),
	}

	if err := nodeA.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeP.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeP JoinGroupTopic: %v", err)
	}
	connectLocalGroupNodes(t, nodeP, nodeA)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 3*time.Second)
	waitForGroupTopicPeerCount(t, nodeP, groupId, 1, 3*time.Second)

	plaintextMarker := "ga011-missing-sender-device-id-message"
	validEnvelopeJSON := buildTestDeviceEnvelopeWithPlaintext(
		t,
		groupId,
		"group_message",
		memberBID,
		deviceID,
		nodeP.PeerId(),
		devicePub,
		keyPackageID,
		devicePriv,
		devicePub,
		groupKey,
		keyInfo.KeyEpoch,
		`{"text":"`+plaintextMarker+`","timestamp":"2026-05-12T20:22:00Z"}`,
	)
	missingDeviceEnvelopeJSON := deleteGroupEnvelopeJSONField(t, validEnvelopeJSON, "senderDeviceId")
	validEnv, err := internal.ParseGroupEnvelope(validEnvelopeJSON)
	if err != nil {
		t.Fatalf("parse valid envelope: %v", err)
	}
	missingEnv, err := internal.ParseGroupEnvelope(missingDeviceEnvelopeJSON)
	if err != nil {
		t.Fatalf("parse missing device envelope: %v", err)
	}
	if missingEnv.SenderDeviceId != "" {
		t.Fatalf("senderDeviceId = %q, want omitted/empty", missingEnv.SenderDeviceId)
	}
	for _, check := range []struct {
		name string
		got  interface{}
		want interface{}
	}{
		{name: "senderId", got: missingEnv.SenderId, want: validEnv.SenderId},
		{name: "senderTransportPeerId", got: missingEnv.SenderTransportPeerId, want: validEnv.SenderTransportPeerId},
		{name: "senderDevicePublicKey", got: missingEnv.SenderDevicePublicKey, want: validEnv.SenderDevicePublicKey},
		{name: "senderKeyPackageId", got: missingEnv.SenderKeyPackageId, want: validEnv.SenderKeyPackageId},
		{name: "groupId", got: missingEnv.GroupId, want: validEnv.GroupId},
		{name: "type", got: missingEnv.Type, want: validEnv.Type},
		{name: "keyEpoch", got: missingEnv.KeyEpoch, want: validEnv.KeyEpoch},
		{name: "signature", got: missingEnv.Signature, want: validEnv.Signature},
		{name: "encrypted", got: missingEnv.Encrypted, want: validEnv.Encrypted},
	} {
		if check.got != check.want {
			t.Fatalf("%s = %#v, want %#v", check.name, check.got, check.want)
		}
	}

	if result := validateGroupEnvelopeForTransportPeer(missingDeviceEnvelopeJSON, groupId, config, keyInfo, nodeP.PeerId()); result != "reject:unbound_device" {
		t.Fatalf("pure validator = %s, want reject:unbound_device", result)
	}
	if err := nodeP.pubsub.UnregisterTopicValidator(GroupTopicPrefix + groupId); err != nil {
		t.Fatalf("nodeP unregister local validator before GA011 raw publish: %v", err)
	}

	baseline := len(nodeACapture.snapshot())
	publishRawGroupEnvelope(t, nodeP, groupId, missingDeviceEnvelopeJSON)
	waitForCollectedValidationReject(t, nodeACapture, baseline, "unbound_device", keyInfo.KeyEpoch, 5*time.Second)
	for _, forbidden := range []string{
		`"event":"group_message:received"`,
		`"event":"group_reaction:received"`,
		`"event":"group:decryption_failed"`,
		`"event":"group:payload_parse_failed"`,
		plaintextMarker,
	} {
		t.Run("missing sender device id rejected/"+forbidden, func(t *testing.T) {
			assertNoCollectedEventContainingAfter(t, nodeACapture, baseline, forbidden, 500*time.Millisecond)
		})
	}
}

func TestGA012MultiDeviceMissingSenderTransportPeerIDRejects(t *testing.T) {
	_, pubA := generateEd25519KeyPair(t)
	devicePriv, devicePub := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeACapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeP := startLocalNodeForMultiRelayTest(t)

	groupId := "ga012-missing-sender-transport-peer-id"
	memberBID := "ga012-member-b"
	deviceID := "ga012-device-s"
	keyPackageID := "ga012-kp-s"
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	config := &GroupConfig{
		Name:      "GA012 Missing Transport Peer Private Chat",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: pubA},
			{
				PeerId:    memberBID,
				Role:      GroupRoleWriter,
				PublicKey: "ga012-member-b-public-key",
				Devices: []GroupMemberDevice{
					{
						DeviceId:               deviceID,
						TransportPeerId:        nodeP.PeerId(),
						DeviceSigningPublicKey: devicePub,
						KeyPackageId:           keyPackageID,
						Status:                 "active",
					},
				},
			},
		},
		CreatedBy: nodeA.PeerId(),
	}

	if err := nodeA.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeP.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeP JoinGroupTopic: %v", err)
	}
	connectLocalGroupNodes(t, nodeP, nodeA)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 3*time.Second)
	waitForGroupTopicPeerCount(t, nodeP, groupId, 1, 3*time.Second)

	plaintextMarker := "ga012-missing-sender-transport-peer-id-message"
	validEnvelopeJSON := buildTestDeviceEnvelopeWithPlaintext(
		t,
		groupId,
		"group_message",
		memberBID,
		deviceID,
		nodeP.PeerId(),
		devicePub,
		keyPackageID,
		devicePriv,
		devicePub,
		groupKey,
		keyInfo.KeyEpoch,
		`{"text":"`+plaintextMarker+`","timestamp":"2026-05-12T20:26:00Z"}`,
	)
	missingTransportEnvelopeJSON := deleteGroupEnvelopeJSONField(t, validEnvelopeJSON, "senderTransportPeerId")
	validEnv, err := internal.ParseGroupEnvelope(validEnvelopeJSON)
	if err != nil {
		t.Fatalf("parse valid envelope: %v", err)
	}
	missingEnv, err := internal.ParseGroupEnvelope(missingTransportEnvelopeJSON)
	if err != nil {
		t.Fatalf("parse missing transport envelope: %v", err)
	}
	if missingEnv.SenderTransportPeerId != "" {
		t.Fatalf("senderTransportPeerId = %q, want omitted/empty", missingEnv.SenderTransportPeerId)
	}
	for _, check := range []struct {
		name string
		got  interface{}
		want interface{}
	}{
		{name: "senderId", got: missingEnv.SenderId, want: validEnv.SenderId},
		{name: "senderDeviceId", got: missingEnv.SenderDeviceId, want: validEnv.SenderDeviceId},
		{name: "senderDevicePublicKey", got: missingEnv.SenderDevicePublicKey, want: validEnv.SenderDevicePublicKey},
		{name: "senderKeyPackageId", got: missingEnv.SenderKeyPackageId, want: validEnv.SenderKeyPackageId},
		{name: "groupId", got: missingEnv.GroupId, want: validEnv.GroupId},
		{name: "type", got: missingEnv.Type, want: validEnv.Type},
		{name: "keyEpoch", got: missingEnv.KeyEpoch, want: validEnv.KeyEpoch},
		{name: "signature", got: missingEnv.Signature, want: validEnv.Signature},
		{name: "encrypted", got: missingEnv.Encrypted, want: validEnv.Encrypted},
	} {
		if check.got != check.want {
			t.Fatalf("%s = %#v, want %#v", check.name, check.got, check.want)
		}
	}

	if result := validateGroupEnvelopeForTransportPeer(missingTransportEnvelopeJSON, groupId, config, keyInfo, nodeP.PeerId()); result != "reject:peer_mismatch" {
		t.Fatalf("pure validator = %s, want reject:peer_mismatch", result)
	}
	if err := nodeP.pubsub.UnregisterTopicValidator(GroupTopicPrefix + groupId); err != nil {
		t.Fatalf("nodeP unregister local validator before GA012 raw publish: %v", err)
	}

	baseline := len(nodeACapture.snapshot())
	publishRawGroupEnvelope(t, nodeP, groupId, missingTransportEnvelopeJSON)
	waitForCollectedValidationReject(t, nodeACapture, baseline, "peer_mismatch", keyInfo.KeyEpoch, 5*time.Second)
	for _, forbidden := range []string{
		`"event":"group_message:received"`,
		`"event":"group_reaction:received"`,
		`"event":"group:decryption_failed"`,
		`"event":"group:payload_parse_failed"`,
		plaintextMarker,
	} {
		t.Run("missing sender transport peer id rejected/"+forbidden, func(t *testing.T) {
			assertNoCollectedEventContainingAfter(t, nodeACapture, baseline, forbidden, 500*time.Millisecond)
		})
	}
}

func TestGA013RevokedDeviceCannotPublish(t *testing.T) {
	_, pubA := generateEd25519KeyPair(t)
	revokedPriv, revokedPub := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeACapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeP := startLocalNodeForMultiRelayTest(t)

	groupId := "ga013-revoked-device"
	memberBID := "ga013-member-b"
	deviceID := "ga013-device-s"
	keyPackageID := "ga013-kp-s"
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	config := &GroupConfig{
		Name:      "GA013 Revoked Device Private Chat",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: pubA},
			{
				PeerId:    memberBID,
				Role:      GroupRoleWriter,
				PublicKey: "ga013-member-b-public-key",
				Devices: []GroupMemberDevice{
					{
						DeviceId:               deviceID,
						TransportPeerId:        nodeP.PeerId(),
						DeviceSigningPublicKey: revokedPub,
						KeyPackageId:           keyPackageID,
						Status:                 "revoked",
						RevokedAt:              "2026-05-12T20:30:00Z",
					},
				},
			},
		},
		CreatedBy: nodeA.PeerId(),
	}

	if err := nodeA.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeP.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeP JoinGroupTopic: %v", err)
	}
	connectLocalGroupNodes(t, nodeP, nodeA)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 3*time.Second)
	waitForGroupTopicPeerCount(t, nodeP, groupId, 1, 3*time.Second)

	plaintextMarker := "ga013-revoked-device-message"
	envelopeJSON := buildTestDeviceEnvelopeWithPlaintext(
		t,
		groupId,
		"group_message",
		memberBID,
		deviceID,
		nodeP.PeerId(),
		revokedPub,
		keyPackageID,
		revokedPriv,
		revokedPub,
		groupKey,
		keyInfo.KeyEpoch,
		`{"text":"`+plaintextMarker+`","timestamp":"2026-05-12T20:30:01Z"}`,
	)
	if result := validateGroupEnvelopeForTransportPeer(envelopeJSON, groupId, config, keyInfo, nodeP.PeerId()); result != "reject:unbound_device" {
		t.Fatalf("pure validator = %s, want reject:unbound_device", result)
	}
	if err := nodeP.pubsub.UnregisterTopicValidator(GroupTopicPrefix + groupId); err != nil {
		t.Fatalf("nodeP unregister local validator before GA013 raw publish: %v", err)
	}

	baseline := len(nodeACapture.snapshot())
	publishRawGroupEnvelope(t, nodeP, groupId, envelopeJSON)
	waitForCollectedValidationReject(t, nodeACapture, baseline, "unbound_device", keyInfo.KeyEpoch, 5*time.Second)
	for _, forbidden := range []string{
		`"event":"group_message:received"`,
		`"event":"group_reaction:received"`,
		`"event":"group:decryption_failed"`,
		`"event":"group:payload_parse_failed"`,
		plaintextMarker,
	} {
		t.Run("revoked device rejected/"+forbidden, func(t *testing.T) {
			assertNoCollectedEventContainingAfter(t, nodeACapture, baseline, forbidden, 500*time.Millisecond)
		})
	}
}

func TestGA014InactiveDeviceCannotPublish(t *testing.T) {
	_, pubA := generateEd25519KeyPair(t)
	inactivePriv, inactivePub := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeACapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeP := startLocalNodeForMultiRelayTest(t)

	groupId := "ga014-inactive-device"
	memberBID := "ga014-member-b"
	deviceID := "ga014-device-s"
	keyPackageID := "ga014-kp-s"
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	config := &GroupConfig{
		Name:      "GA014 Inactive Device Private Chat",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: pubA},
			{
				PeerId:    memberBID,
				Role:      GroupRoleWriter,
				PublicKey: "ga014-member-b-public-key",
				Devices: []GroupMemberDevice{
					{
						DeviceId:               deviceID,
						TransportPeerId:        nodeP.PeerId(),
						DeviceSigningPublicKey: inactivePub,
						KeyPackageId:           keyPackageID,
						Status:                 "inactive",
					},
				},
			},
		},
		CreatedBy: nodeA.PeerId(),
	}

	if err := nodeA.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeP.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeP JoinGroupTopic: %v", err)
	}
	connectLocalGroupNodes(t, nodeP, nodeA)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 3*time.Second)
	waitForGroupTopicPeerCount(t, nodeP, groupId, 1, 3*time.Second)

	plaintextMarker := "ga014-inactive-device-message"
	envelopeJSON := buildTestDeviceEnvelopeWithPlaintext(
		t,
		groupId,
		"group_message",
		memberBID,
		deviceID,
		nodeP.PeerId(),
		inactivePub,
		keyPackageID,
		inactivePriv,
		inactivePub,
		groupKey,
		keyInfo.KeyEpoch,
		`{"text":"`+plaintextMarker+`","timestamp":"2026-05-12T20:34:01Z"}`,
	)
	if result := validateGroupEnvelopeForTransportPeer(envelopeJSON, groupId, config, keyInfo, nodeP.PeerId()); result != "reject:unbound_device" {
		t.Fatalf("pure validator = %s, want reject:unbound_device", result)
	}
	if err := nodeP.pubsub.UnregisterTopicValidator(GroupTopicPrefix + groupId); err != nil {
		t.Fatalf("nodeP unregister local validator before GA014 raw publish: %v", err)
	}

	baseline := len(nodeACapture.snapshot())
	publishRawGroupEnvelope(t, nodeP, groupId, envelopeJSON)
	waitForCollectedValidationReject(t, nodeACapture, baseline, "unbound_device", keyInfo.KeyEpoch, 5*time.Second)
	for _, forbidden := range []string{
		`"event":"group_message:received"`,
		`"event":"group_reaction:received"`,
		`"event":"group:decryption_failed"`,
		`"event":"group:payload_parse_failed"`,
		plaintextMarker,
	} {
		t.Run("inactive device rejected/"+forbidden, func(t *testing.T) {
			assertNoCollectedEventContainingAfter(t, nodeACapture, baseline, forbidden, 500*time.Millisecond)
		})
	}
}

func TestGA015KeyPackageIDMismatchRejects(t *testing.T) {
	_, pubA := generateEd25519KeyPair(t)
	devicePriv, devicePub := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeACapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeP := startLocalNodeForMultiRelayTest(t)

	groupId := "ga015-key-package-mismatch"
	memberBID := "ga015-member-b"
	deviceID := "ga015-device-s"
	activeKeyPackageID := "ga015-kp-active"
	claimedKeyPackageID := "ga015-kp-stale"
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	config := &GroupConfig{
		Name:      "GA015 Key Package Mismatch Private Chat",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: pubA},
			{
				PeerId:    memberBID,
				Role:      GroupRoleWriter,
				PublicKey: "ga015-member-b-public-key",
				Devices: []GroupMemberDevice{
					{
						DeviceId:               deviceID,
						TransportPeerId:        nodeP.PeerId(),
						DeviceSigningPublicKey: devicePub,
						KeyPackageId:           activeKeyPackageID,
						Status:                 "active",
					},
				},
			},
		},
		CreatedBy: nodeA.PeerId(),
	}

	if err := nodeA.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeP.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeP JoinGroupTopic: %v", err)
	}
	connectLocalGroupNodes(t, nodeP, nodeA)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 3*time.Second)
	waitForGroupTopicPeerCount(t, nodeP, groupId, 1, 3*time.Second)

	plaintextMarker := "ga015-key-package-mismatch-message"
	envelopeJSON := buildTestDeviceEnvelopeWithPlaintext(
		t,
		groupId,
		"group_message",
		memberBID,
		deviceID,
		nodeP.PeerId(),
		devicePub,
		claimedKeyPackageID,
		devicePriv,
		devicePub,
		groupKey,
		keyInfo.KeyEpoch,
		`{"text":"`+plaintextMarker+`","timestamp":"2026-05-12T20:38:01Z"}`,
	)
	env, err := internal.ParseGroupEnvelope(envelopeJSON)
	if err != nil {
		t.Fatalf("parse envelope: %v", err)
	}
	if env.SenderKeyPackageId != claimedKeyPackageID {
		t.Fatalf("senderKeyPackageId = %q, want %q", env.SenderKeyPackageId, claimedKeyPackageID)
	}
	if env.SenderKeyPackageId == activeKeyPackageID {
		t.Fatalf("test setup did not create key package mismatch")
	}
	if result := validateGroupEnvelopeForTransportPeer(envelopeJSON, groupId, config, keyInfo, nodeP.PeerId()); result != "reject:unbound_device" {
		t.Fatalf("pure validator = %s, want reject:unbound_device", result)
	}
	if err := nodeP.pubsub.UnregisterTopicValidator(GroupTopicPrefix + groupId); err != nil {
		t.Fatalf("nodeP unregister local validator before GA015 raw publish: %v", err)
	}

	baseline := len(nodeACapture.snapshot())
	publishRawGroupEnvelope(t, nodeP, groupId, envelopeJSON)
	waitForCollectedValidationReject(t, nodeACapture, baseline, "unbound_device", keyInfo.KeyEpoch, 5*time.Second)
	for _, forbidden := range []string{
		`"event":"group_message:received"`,
		`"event":"group_reaction:received"`,
		`"event":"group:decryption_failed"`,
		`"event":"group:payload_parse_failed"`,
		plaintextMarker,
	} {
		t.Run("key package mismatch rejected/"+forbidden, func(t *testing.T) {
			assertNoCollectedEventContainingAfter(t, nodeACapture, baseline, forbidden, 500*time.Millisecond)
		})
	}
}

func TestGA016DevicePublicKeyMismatchRejects(t *testing.T) {
	_, pubA := generateEd25519KeyPair(t)
	_, activePub := generateEd25519KeyPair(t)
	attackerPriv, attackerPub := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeACapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeP := startLocalNodeForMultiRelayTest(t)

	groupId := "ga016-device-public-key-mismatch"
	memberBID := "ga016-member-b"
	deviceID := "ga016-device-s"
	keyPackageID := "ga016-kp-s"
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	config := &GroupConfig{
		Name:      "GA016 Device Public Key Mismatch Private Chat",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: pubA},
			{
				PeerId:    memberBID,
				Role:      GroupRoleWriter,
				PublicKey: "ga016-member-b-public-key",
				Devices: []GroupMemberDevice{
					{
						DeviceId:               deviceID,
						TransportPeerId:        nodeP.PeerId(),
						DeviceSigningPublicKey: activePub,
						KeyPackageId:           keyPackageID,
						Status:                 "active",
					},
				},
			},
		},
		CreatedBy: nodeA.PeerId(),
	}

	if err := nodeA.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeP.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeP JoinGroupTopic: %v", err)
	}
	connectLocalGroupNodes(t, nodeP, nodeA)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 3*time.Second)
	waitForGroupTopicPeerCount(t, nodeP, groupId, 1, 3*time.Second)

	plaintextMarker := "ga016-device-public-key-mismatch-message"
	envelopeJSON := buildTestDeviceEnvelopeWithPlaintext(
		t,
		groupId,
		"group_message",
		memberBID,
		deviceID,
		nodeP.PeerId(),
		attackerPub,
		keyPackageID,
		attackerPriv,
		attackerPub,
		groupKey,
		keyInfo.KeyEpoch,
		`{"text":"`+plaintextMarker+`","timestamp":"2026-05-12T20:42:01Z"}`,
	)
	env, err := internal.ParseGroupEnvelope(envelopeJSON)
	if err != nil {
		t.Fatalf("parse envelope: %v", err)
	}
	if env.SenderDevicePublicKey != attackerPub {
		t.Fatalf("senderDevicePublicKey = %q, want attacker public key", env.SenderDevicePublicKey)
	}
	if env.SenderDevicePublicKey == activePub {
		t.Fatalf("test setup did not create device public key mismatch")
	}
	signatureData := mcrypto.BuildGroupSignatureData(groupId, keyInfo.KeyEpoch, env.Encrypted.Ciphertext)
	validWithAttackerKey, err := mcrypto.VerifyPayload(attackerPub, signatureData, env.Signature)
	if err != nil {
		t.Fatalf("verify with attacker key: %v", err)
	}
	if !validWithAttackerKey {
		t.Fatalf("signature should verify with claimed attacker device key")
	}
	validWithActiveKey, err := mcrypto.VerifyPayload(activePub, signatureData, env.Signature)
	if err != nil {
		t.Fatalf("verify with active key: %v", err)
	}
	if validWithActiveKey {
		t.Fatalf("signature unexpectedly verifies with configured active device key")
	}
	if result := validateGroupEnvelopeForTransportPeer(envelopeJSON, groupId, config, keyInfo, nodeP.PeerId()); result != "reject:unbound_device" {
		t.Fatalf("pure validator = %s, want reject:unbound_device", result)
	}
	if err := nodeP.pubsub.UnregisterTopicValidator(GroupTopicPrefix + groupId); err != nil {
		t.Fatalf("nodeP unregister local validator before GA016 raw publish: %v", err)
	}

	baseline := len(nodeACapture.snapshot())
	publishRawGroupEnvelope(t, nodeP, groupId, envelopeJSON)
	waitForCollectedValidationReject(t, nodeACapture, baseline, "unbound_device", keyInfo.KeyEpoch, 5*time.Second)
	for _, forbidden := range []string{
		`"event":"group_message:received"`,
		`"event":"group_reaction:received"`,
		`"event":"group:decryption_failed"`,
		`"event":"group:payload_parse_failed"`,
		plaintextMarker,
	} {
		t.Run("device public key mismatch rejected/"+forbidden, func(t *testing.T) {
			assertNoCollectedEventContainingAfter(t, nodeACapture, baseline, forbidden, 500*time.Millisecond)
		})
	}
}

func TestGA017SiblingDeviceMessageIsNotSkippedAsSelf(t *testing.T) {
	deviceS1Priv, deviceS1Pub := generateEd25519KeyPair(t)
	deviceS2Priv, deviceS2Pub := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeS1Capture := &testEventCollector{}
	nodeS1 := startLocalNodeForMultiRelayTestWithCollector(t, nodeS1Capture)
	nodeS2 := startLocalNodeForMultiRelayTest(t)

	groupId := "ga017-sibling-device-self-skip"
	logicalMemberID := nodeS1.PeerId()
	deviceS1ID := "ga017-device-s1"
	deviceS2ID := "ga017-device-s2"
	deviceS1KeyPackageID := "ga017-kp-s1"
	deviceS2KeyPackageID := "ga017-kp-s2"
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	config := &GroupConfig{
		Name:      "GA017 Sibling Device Private Chat",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{
				PeerId:    logicalMemberID,
				Role:      GroupRoleWriter,
				PublicKey: deviceS1Pub,
				Devices: []GroupMemberDevice{
					{
						DeviceId:               deviceS1ID,
						TransportPeerId:        nodeS1.PeerId(),
						DeviceSigningPublicKey: deviceS1Pub,
						KeyPackageId:           deviceS1KeyPackageID,
						Status:                 "active",
					},
					{
						DeviceId:               deviceS2ID,
						TransportPeerId:        nodeS2.PeerId(),
						DeviceSigningPublicKey: deviceS2Pub,
						KeyPackageId:           deviceS2KeyPackageID,
						Status:                 "active",
					},
				},
			},
		},
		CreatedBy: logicalMemberID,
	}

	if err := nodeS1.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeS1 JoinGroupTopic: %v", err)
	}
	if err := nodeS2.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeS2 JoinGroupTopic: %v", err)
	}
	connectLocalGroupNodes(t, nodeS2, nodeS1)
	waitForGroupTopicPeerCount(t, nodeS1, groupId, 1, 3*time.Second)
	waitForGroupTopicPeerCount(t, nodeS2, groupId, 1, 3*time.Second)

	plaintextMarker := "ga017-sibling-device-message"
	envelopeJSON := buildTestDeviceEnvelopeWithPlaintext(
		t,
		groupId,
		"group_message",
		logicalMemberID,
		deviceS2ID,
		nodeS2.PeerId(),
		deviceS2Pub,
		deviceS2KeyPackageID,
		deviceS2Priv,
		deviceS2Pub,
		groupKey,
		keyInfo.KeyEpoch,
		`{"text":"`+plaintextMarker+`","timestamp":"2026-05-12T20:47:01Z"}`,
	)
	env, err := internal.ParseGroupEnvelope(envelopeJSON)
	if err != nil {
		t.Fatalf("parse envelope: %v", err)
	}
	if env.SenderId != nodeS1.PeerId() {
		t.Fatalf("test setup requires logical sender to equal local peer id, got sender=%q local=%q", env.SenderId, nodeS1.PeerId())
	}
	if env.SenderTransportPeerId == nodeS1.PeerId() {
		t.Fatalf("test setup requires sibling transport, got local transport %q", env.SenderTransportPeerId)
	}
	if groupEnvelopeOriginatesFromLocalTransport(env, nodeS1.PeerId()) {
		t.Fatalf("sibling device envelope should not be classified as local transport echo")
	}
	if result := validateGroupEnvelopeForTransportPeer(envelopeJSON, groupId, config, keyInfo, nodeS2.PeerId()); result != "accept" {
		t.Fatalf("pure validator = %s, want accept", result)
	}
	localEchoJSON := buildTestDeviceEnvelopeWithPlaintext(
		t,
		groupId,
		"group_message",
		logicalMemberID,
		deviceS1ID,
		nodeS1.PeerId(),
		deviceS1Pub,
		deviceS1KeyPackageID,
		deviceS1Priv,
		deviceS1Pub,
		groupKey,
		keyInfo.KeyEpoch,
		`{"text":"ga017-local-echo","timestamp":"2026-05-12T20:47:02Z"}`,
	)
	localEchoEnv, err := internal.ParseGroupEnvelope(localEchoJSON)
	if err != nil {
		t.Fatalf("parse local echo envelope: %v", err)
	}
	if !groupEnvelopeOriginatesFromLocalTransport(localEchoEnv, nodeS1.PeerId()) {
		t.Fatalf("same-transport envelope should still be classified as local transport echo")
	}

	baseline := len(nodeS1Capture.snapshot())
	publishRawGroupEnvelope(t, nodeS2, groupId, envelopeJSON)
	event := waitForCollectedEventAfter(t, nodeS1Capture, baseline, "group_message:received", 5*time.Second)
	for _, tc := range []struct {
		key  string
		want interface{}
	}{
		{"groupId", groupId},
		{"senderId", logicalMemberID},
		{"senderDeviceId", deviceS2ID},
		{"transportPeerId", nodeS2.PeerId()},
		{"text", plaintextMarker},
		{"keyEpoch", float64(keyInfo.KeyEpoch)},
	} {
		if got := event[tc.key]; got != tc.want {
			t.Fatalf("%s = %#v, want %#v in event %#v", tc.key, got, tc.want, event)
		}
	}
	assertNoCollectedEventContainingAfter(t, nodeS1Capture, baseline, `"event":"group:validation_rejected"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeS1Capture, baseline, `"event":"group:decryption_failed"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeS1Capture, baseline, `"event":"group:payload_parse_failed"`, 500*time.Millisecond)
}

func TestGA018SameTransportSelfEchoIsSkippedOnce(t *testing.T) {
	selfPriv, selfPub := generateEd25519KeyPair(t)
	relayPriv, relayPub := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeACapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeB := startLocalNodeForMultiRelayTest(t)

	groupId := "ga018-same-transport-self-echo"
	messageId := "ga018-local-message-id"
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	config := &GroupConfig{
		Name:      "GA018 Same Transport Self Echo",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: selfPub},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: relayPub},
		},
		CreatedBy: nodeA.PeerId(),
	}

	if err := nodeA.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}
	connectLocalGroupNodes(t, nodeB, nodeA)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 3*time.Second)
	waitForGroupTopicPeerCount(t, nodeB, groupId, 1, 3*time.Second)

	senderBaseline := len(nodeACapture.snapshot())
	msgID, peerCount, err := nodeA.PublishGroupMessage(
		groupId,
		selfPriv,
		nodeA.PeerId(),
		selfPub,
		"Alice",
		"GA-018 local sender row",
		messageId,
		nil,
	)
	if err != nil {
		t.Fatalf("PublishGroupMessage: %v", err)
	}
	if msgID != messageId {
		t.Fatalf("messageId = %q, want %q", msgID, messageId)
	}
	if peerCount < 1 {
		t.Fatalf("topic peer count = %d, want at least one peer", peerCount)
	}
	publishDebug := waitForCollectedEventAfter(t, nodeACapture, senderBaseline, "group:publish_debug", 5*time.Second)
	if got := publishDebug["messageId"]; got != messageId {
		t.Fatalf("publish_debug messageId = %#v, want %q", got, messageId)
	}
	assertNoCollectedEventContainingAfter(t, nodeACapture, senderBaseline, `"event":"group_message:received"`, 500*time.Millisecond)

	if err := nodeA.pubsub.UnregisterTopicValidator(GroupTopicPrefix + groupId); err != nil {
		t.Fatalf("nodeA unregister validator before GA018 raw echo: %v", err)
	}
	if err := nodeB.pubsub.UnregisterTopicValidator(GroupTopicPrefix + groupId); err != nil {
		t.Fatalf("nodeB unregister validator before GA018 raw echo: %v", err)
	}

	controlPayload, err := internal.MarshalGroupPayload(&internal.GroupMessagePayload{
		Text:      "GA-018 control remote delivery",
		Timestamp: "2026-05-14T00:09:00Z",
		Username:  "Bob",
		Extra:     buildGroupMessageExtra("ga018-control-message", nil),
	})
	if err != nil {
		t.Fatalf("marshal GA018 control payload: %v", err)
	}
	controlEnvelopeJSON := buildTestDeviceEnvelopeWithPlaintext(
		t,
		groupId,
		"group_message",
		nodeB.PeerId(),
		nodeB.PeerId(),
		nodeB.PeerId(),
		relayPub,
		"",
		relayPriv,
		relayPub,
		groupKey,
		keyInfo.KeyEpoch,
		controlPayload,
	)
	controlBaseline := len(nodeACapture.snapshot())
	publishRawGroupEnvelope(t, nodeB, groupId, controlEnvelopeJSON)
	controlEvent := waitForCollectedEventAfter(t, nodeACapture, controlBaseline, "group_message:received", 5*time.Second)
	if got := controlEvent["text"]; got != "GA-018 control remote delivery" {
		t.Fatalf("control text = %#v, want remote delivery", got)
	}

	selfEchoPayload, err := internal.MarshalGroupPayload(&internal.GroupMessagePayload{
		Text:      "GA-018 duplicate self echo",
		Timestamp: "2026-05-14T00:09:01Z",
		Username:  "Alice",
		Extra:     buildGroupMessageExtra(messageId, nil),
	})
	if err != nil {
		t.Fatalf("marshal GA018 self echo payload: %v", err)
	}
	selfEchoEnvelopeJSON := buildTestDeviceEnvelopeWithPlaintext(
		t,
		groupId,
		"group_message",
		nodeA.PeerId(),
		nodeA.PeerId(),
		nodeA.PeerId(),
		selfPub,
		"",
		selfPriv,
		selfPub,
		groupKey,
		keyInfo.KeyEpoch,
		selfEchoPayload,
	)
	selfEchoEnv, err := internal.ParseGroupEnvelope(selfEchoEnvelopeJSON)
	if err != nil {
		t.Fatalf("parse self echo envelope: %v", err)
	}
	if !groupEnvelopeOriginatesFromLocalTransport(selfEchoEnv, nodeA.PeerId()) {
		t.Fatalf("same-transport self echo should be classified as local transport")
	}
	if result := validateGroupEnvelopeForTransportPeer(selfEchoEnvelopeJSON, groupId, config, keyInfo, nodeA.PeerId()); result != "accept" {
		t.Fatalf("pure self echo validator = %s, want accept for local transport", result)
	}

	selfEchoBaseline := len(nodeACapture.snapshot())
	publishRawGroupEnvelope(t, nodeB, groupId, selfEchoEnvelopeJSON)
	for _, forbidden := range []string{
		`"event":"group_message:received"`,
		messageId,
		"GA-018 duplicate self echo",
		`"event":"group:decryption_failed"`,
		`"event":"group:payload_parse_failed"`,
		`"event":"group:validation_rejected"`,
	} {
		t.Run("same transport self echo skipped/"+forbidden, func(t *testing.T) {
			assertNoCollectedEventContainingAfter(t, nodeACapture, selfEchoBaseline, forbidden, 500*time.Millisecond)
		})
	}
}

func TestGP021MessageReceiveEmitsIdentityTransportAndMessageFields(t *testing.T) {
	_, receiverPub := generateEd25519KeyPair(t)
	senderDevicePriv, senderDevicePub := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeACapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeB := startLocalNodeForMultiRelayTest(t)

	groupId := "gp021-receive-event-fields"
	senderDeviceId := "gp021-device-b"
	senderKeyPackageId := "gp021-kp-b"
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 7}
	config := &GroupConfig{
		Name:      "GP021 Receive Fields",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{
				PeerId:    nodeA.PeerId(),
				Role:      GroupRoleAdmin,
				PublicKey: receiverPub,
				Devices: []GroupMemberDevice{
					{
						DeviceId:               "gp021-device-a",
						TransportPeerId:        nodeA.PeerId(),
						DeviceSigningPublicKey: receiverPub,
						KeyPackageId:           "gp021-kp-a",
						Status:                 "active",
					},
				},
			},
			{
				PeerId:    nodeB.PeerId(),
				Role:      GroupRoleWriter,
				PublicKey: senderDevicePub,
				Devices: []GroupMemberDevice{
					{
						DeviceId:               senderDeviceId,
						TransportPeerId:        nodeB.PeerId(),
						DeviceSigningPublicKey: senderDevicePub,
						KeyPackageId:           senderKeyPackageId,
						Status:                 "active",
					},
				},
			},
		},
		CreatedBy: nodeA.PeerId(),
	}

	if err := nodeA.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}
	connectLocalGroupNodes(t, nodeB, nodeA)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 3*time.Second)

	messageID := "gp021-message-id"
	payload := &internal.GroupMessagePayload{
		Text:      "GP-021 receive event field proof",
		Timestamp: "2026-05-13T01:40:00Z",
		Username:  "Bob Device",
		Extra: map[string]interface{}{
			"messageId": messageID,
		},
	}
	payloadJSON, err := internal.MarshalGroupPayload(payload)
	if err != nil {
		t.Fatalf("marshal GP-021 payload: %v", err)
	}
	envelopeJSON := buildTestDeviceEnvelopeWithPlaintext(
		t,
		groupId,
		"group_message",
		nodeB.PeerId(),
		senderDeviceId,
		nodeB.PeerId(),
		senderDevicePub,
		senderKeyPackageId,
		senderDevicePriv,
		senderDevicePub,
		groupKey,
		keyInfo.KeyEpoch,
		payloadJSON,
	)
	if result := validateGroupEnvelopeForTransportPeer(envelopeJSON, groupId, config, keyInfo, nodeB.PeerId()); result != "accept" {
		t.Fatalf("pure validator = %s, want accept", result)
	}

	baseline := len(nodeACapture.snapshot())
	publishRawGroupEnvelope(t, nodeB, groupId, envelopeJSON)
	event := waitForCollectedEventAfter(t, nodeACapture, baseline, "group_message:received", 5*time.Second)
	for _, tc := range []struct {
		key  string
		want interface{}
	}{
		{"groupId", groupId},
		{"senderId", nodeB.PeerId()},
		{"senderDeviceId", senderDeviceId},
		{"transportPeerId", nodeB.PeerId()},
		{"senderUsername", "Bob Device"},
		{"keyEpoch", float64(keyInfo.KeyEpoch)},
		{"text", "GP-021 receive event field proof"},
		{"timestamp", "2026-05-13T01:40:00Z"},
		{"messageId", messageID},
	} {
		if got := event[tc.key]; got != tc.want {
			t.Fatalf("%s = %#v, want %#v in event %#v", tc.key, got, tc.want, event)
		}
	}
	assertNoCollectedEventContainingAfter(t, nodeACapture, baseline, `"event":"group:validation_rejected"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeACapture, baseline, `"event":"group:decryption_failed"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeACapture, baseline, `"event":"group:payload_parse_failed"`, 500*time.Millisecond)
}

func TestGA019PublicKeyReuseAcrossMemberIDsRejectsPolicy(t *testing.T) {
	_, pubA := generateEd25519KeyPair(t)
	_, uniqueBPub := generateEd25519KeyPair(t)
	sharedPriv, sharedPub := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeACapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeC := startLocalNodeForMultiRelayTest(t)
	nodeReject := startLocalNodeForMultiRelayTest(t)

	groupId := "ga019-public-key-reuse-policy"
	memberBID := "ga019-member-b"
	memberCID := "ga019-member-c"
	deviceBID := "ga019-device-b"
	deviceCID := "ga019-device-c"
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	cSharedConfig := &GroupConfig{
		Name:      "GA019 Public Key Reuse Private Chat",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: pubA},
			{
				PeerId:    memberBID,
				Role:      GroupRoleWriter,
				PublicKey: uniqueBPub,
				Devices: []GroupMemberDevice{
					{
						DeviceId:               deviceBID,
						TransportPeerId:        "ga019-transport-b",
						DeviceSigningPublicKey: uniqueBPub,
						KeyPackageId:           "ga019-kp-b",
						Status:                 "active",
					},
				},
			},
			{
				PeerId:    memberCID,
				Role:      GroupRoleWriter,
				PublicKey: sharedPub,
				Devices: []GroupMemberDevice{
					{
						DeviceId:               deviceCID,
						TransportPeerId:        nodeC.PeerId(),
						DeviceSigningPublicKey: sharedPub,
						KeyPackageId:           "ga019-kp-c",
						Status:                 "active",
					},
				},
			},
		},
		CreatedBy: nodeA.PeerId(),
	}
	ambiguousConfig := cloneGroupConfig(cSharedConfig)
	ambiguousConfig.Members[1].Devices[0].DeviceSigningPublicKey = sharedPub
	ambiguousConfig.Members[1].PublicKey = sharedPub

	if err := validateGroupConfigSigningKeyUniqueness(cSharedConfig); err != nil {
		t.Fatalf("safe setup should not have duplicate signing keys: %v", err)
	}
	if err := validateGroupConfigSigningKeyUniqueness(ambiguousConfig); err == nil {
		t.Fatalf("ambiguous config should reject duplicate active device signing key")
	}
	rejectGroupId := groupId + "-join-reject"
	if err := nodeReject.JoinGroupTopic(rejectGroupId, ambiguousConfig, keyInfo); err == nil || !strings.Contains(err.Error(), "ambiguous signing key") {
		t.Fatalf("ambiguous JoinGroupTopic error = %v, want ambiguous signing key", err)
	}
	nodeReject.mu.RLock()
	_, topicStored := nodeReject.groupTopics[rejectGroupId]
	_, configStored := nodeReject.groupConfigs[rejectGroupId]
	nodeReject.mu.RUnlock()
	if topicStored || configStored {
		t.Fatalf("ambiguous JoinGroupTopic stored topic=%v config=%v", topicStored, configStored)
	}

	if err := nodeA.JoinGroupTopic(groupId, cSharedConfig, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeC.JoinGroupTopic(groupId, cSharedConfig, keyInfo); err != nil {
		t.Fatalf("nodeC JoinGroupTopic: %v", err)
	}
	connectLocalGroupNodes(t, nodeC, nodeA)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 3*time.Second)
	waitForGroupTopicPeerCount(t, nodeC, groupId, 1, 3*time.Second)

	plaintextMarker := "ga019-duplicate-signing-key-impersonation"
	envelopeJSON := buildTestDeviceEnvelopeWithPlaintext(
		t,
		groupId,
		"group_message",
		memberCID,
		deviceCID,
		nodeC.PeerId(),
		sharedPub,
		"ga019-kp-c",
		sharedPriv,
		sharedPub,
		groupKey,
		keyInfo.KeyEpoch,
		`{"text":"`+plaintextMarker+`","timestamp":"2026-05-12T20:49:01Z"}`,
	)
	if result := validateGroupEnvelopeForTransportPeer(envelopeJSON, groupId, cSharedConfig, keyInfo, nodeC.PeerId()); result != "accept" {
		t.Fatalf("safe config pure validator = %s, want accept", result)
	}
	if result := validateGroupEnvelopeForTransportPeer(envelopeJSON, groupId, ambiguousConfig, keyInfo, nodeC.PeerId()); result != "reject:ambiguous_signing_key" {
		t.Fatalf("ambiguous config pure validator = %s, want reject:ambiguous_signing_key", result)
	}

	nodeA.UpdateGroupConfig(groupId, ambiguousConfig)
	baseline := len(nodeACapture.snapshot())
	publishRawGroupEnvelope(t, nodeC, groupId, envelopeJSON)
	waitForCollectedValidationReject(t, nodeACapture, baseline, "ambiguous_signing_key", keyInfo.KeyEpoch, 5*time.Second)
	for _, forbidden := range []string{
		`"event":"group_message:received"`,
		`"event":"group_reaction:received"`,
		`"event":"group:decryption_failed"`,
		`"event":"group:payload_parse_failed"`,
		plaintextMarker,
	} {
		t.Run("duplicate signing key rejected/"+forbidden, func(t *testing.T) {
			assertNoCollectedEventContainingAfter(t, nodeACapture, baseline, forbidden, 500*time.Millisecond)
		})
	}
	if _, _, err := nodeA.PublishGroupMessage(
		groupId,
		sharedPriv,
		memberCID,
		sharedPub,
		"Charlie",
		"GA019 local publish blocked",
		"ga019-local-publish-blocked",
		map[string]interface{}{
			"senderDeviceId":        deviceCID,
			"senderTransportPeerId": nodeC.PeerId(),
			"senderDevicePublicKey": sharedPub,
			"senderKeyPackageId":    "ga019-kp-c",
		},
	); err == nil || !strings.Contains(err.Error(), "ambiguous signing key") {
		t.Fatalf("ambiguous local PublishGroupMessage error = %v, want ambiguous signing key", err)
	}
}

func TestGA020DuplicateDeviceIDsWithinMemberUseDeterministicBinding(t *testing.T) {
	_, pubA := generateEd25519KeyPair(t)
	shadowPriv, shadowPub := generateEd25519KeyPair(t)
	selectedPriv, selectedPub := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeACapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeShadow := startLocalNodeForMultiRelayTest(t)
	nodeSelected := startLocalNodeForMultiRelayTest(t)

	groupId := "ga020-duplicate-device-id-policy"
	memberBID := "ga020-member-b"
	duplicateDeviceID := "ga020-device-duplicate"
	selectedKeyPackageID := "ga020-kp-selected"
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	config := &GroupConfig{
		Name:      "GA020 Duplicate Device ID Private Chat",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: pubA},
			{
				PeerId:    memberBID,
				Role:      GroupRoleWriter,
				PublicKey: selectedPub,
				Devices: []GroupMemberDevice{
					{
						DeviceId:               duplicateDeviceID,
						TransportPeerId:        nodeShadow.PeerId(),
						DeviceSigningPublicKey: shadowPub,
						Status:                 "active",
					},
					{
						DeviceId:               duplicateDeviceID,
						TransportPeerId:        nodeSelected.PeerId(),
						DeviceSigningPublicKey: selectedPub,
						KeyPackageId:           selectedKeyPackageID,
						Status:                 "active",
					},
				},
			},
		},
		CreatedBy: nodeA.PeerId(),
	}

	if err := nodeA.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeShadow.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeShadow JoinGroupTopic: %v", err)
	}
	if err := nodeSelected.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeSelected JoinGroupTopic: %v", err)
	}
	connectLocalGroupNodes(t, nodeShadow, nodeA)
	connectLocalGroupNodes(t, nodeSelected, nodeA)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 2, 3*time.Second)
	waitForGroupTopicPeerCount(t, nodeSelected, groupId, 1, 3*time.Second)

	nodeA.mu.RLock()
	storedConfig := cloneGroupConfig(nodeA.groupConfigs[groupId])
	nodeA.mu.RUnlock()
	storedMember := findMember(storedConfig, memberBID)
	if storedMember == nil {
		t.Fatalf("stored config missing member %s", memberBID)
	}
	if len(storedMember.Devices) != 1 {
		t.Fatalf("stored duplicate device count = %d, want 1: %#v", len(storedMember.Devices), storedMember.Devices)
	}
	storedDevice := storedMember.Devices[0]
	if storedDevice.DeviceId != duplicateDeviceID ||
		storedDevice.TransportPeerId != nodeSelected.PeerId() ||
		storedDevice.DeviceSigningPublicKey != selectedPub ||
		storedDevice.KeyPackageId != selectedKeyPackageID {
		t.Fatalf("stored selected device = %#v, want selected transport/key package", storedDevice)
	}

	selectedMarker := "ga020-selected-duplicate-device-message"
	selectedEnvelope := buildTestDeviceEnvelopeWithPlaintext(
		t,
		groupId,
		"group_message",
		memberBID,
		duplicateDeviceID,
		nodeSelected.PeerId(),
		selectedPub,
		selectedKeyPackageID,
		selectedPriv,
		selectedPub,
		groupKey,
		keyInfo.KeyEpoch,
		`{"text":"`+selectedMarker+`","timestamp":"2026-05-12T20:50:01Z"}`,
	)
	if result := validateGroupEnvelopeForTransportPeer(selectedEnvelope, groupId, storedConfig, keyInfo, nodeSelected.PeerId()); result != "accept" {
		t.Fatalf("selected duplicate pure validator = %s, want accept", result)
	}

	baselineSelected := len(nodeACapture.snapshot())
	publishRawGroupEnvelope(t, nodeSelected, groupId, selectedEnvelope)
	event := waitForCollectedEventAfter(t, nodeACapture, baselineSelected, "group_message:received", 5*time.Second)
	if event["senderDeviceId"] != duplicateDeviceID || event["transportPeerId"] != nodeSelected.PeerId() || event["text"] != selectedMarker {
		t.Fatalf("selected duplicate event = %#v", event)
	}
	assertNoCollectedEventContainingAfter(t, nodeACapture, baselineSelected, `"event":"group:validation_rejected"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeACapture, baselineSelected, `"event":"group:decryption_failed"`, 500*time.Millisecond)

	shadowMarker := "ga020-shadow-duplicate-device-message"
	shadowEnvelope := buildTestDeviceEnvelopeWithPlaintext(
		t,
		groupId,
		"group_message",
		memberBID,
		duplicateDeviceID,
		nodeShadow.PeerId(),
		shadowPub,
		"",
		shadowPriv,
		shadowPub,
		groupKey,
		keyInfo.KeyEpoch,
		`{"text":"`+shadowMarker+`","timestamp":"2026-05-12T20:50:02Z"}`,
	)
	if result := validateGroupEnvelopeForTransportPeer(shadowEnvelope, groupId, storedConfig, keyInfo, nodeShadow.PeerId()); result != "reject:unbound_device" {
		t.Fatalf("shadow duplicate pure validator = %s, want reject:unbound_device", result)
	}
	if err := nodeShadow.pubsub.UnregisterTopicValidator(GroupTopicPrefix + groupId); err != nil {
		t.Fatalf("nodeShadow unregister local validator before GA020 raw publish: %v", err)
	}

	baselineShadow := len(nodeACapture.snapshot())
	publishRawGroupEnvelope(t, nodeShadow, groupId, shadowEnvelope)
	waitForCollectedValidationReject(t, nodeACapture, baselineShadow, "unbound_device", keyInfo.KeyEpoch, 5*time.Second)
	for _, forbidden := range []string{
		`"event":"group_message:received"`,
		`"event":"group_reaction:received"`,
		`"event":"group:decryption_failed"`,
		`"event":"group:payload_parse_failed"`,
		shadowMarker,
	} {
		t.Run("shadow duplicate device rejected/"+forbidden, func(t *testing.T) {
			assertNoCollectedEventContainingAfter(t, nodeACapture, baselineShadow, forbidden, 500*time.Millisecond)
		})
	}
}

func TestGA021DuplicateTransportPeerAcrossMembersRejectsPolicy(t *testing.T) {
	_, pubA := generateEd25519KeyPair(t)
	_, uniqueBPub := generateEd25519KeyPair(t)
	privC, pubC := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeACapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeSharedTransport := startLocalNodeForMultiRelayTest(t)
	nodeReject := startLocalNodeForMultiRelayTest(t)

	groupId := "ga021-duplicate-transport-peer-policy"
	memberBID := "ga021-member-b"
	memberCID := "ga021-member-c"
	deviceBID := "ga021-device-b"
	deviceCID := "ga021-device-c"
	sharedTransportPeerID := nodeSharedTransport.PeerId()
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	cSharedConfig := &GroupConfig{
		Name:      "GA021 Duplicate Transport Peer Private Chat",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: pubA},
			{
				PeerId:    memberBID,
				Role:      GroupRoleWriter,
				PublicKey: uniqueBPub,
				Devices: []GroupMemberDevice{
					{
						DeviceId:               deviceBID,
						TransportPeerId:        "ga021-transport-b",
						DeviceSigningPublicKey: uniqueBPub,
						KeyPackageId:           "ga021-kp-b",
						Status:                 "active",
					},
				},
			},
			{
				PeerId:    memberCID,
				Role:      GroupRoleWriter,
				PublicKey: pubC,
				Devices: []GroupMemberDevice{
					{
						DeviceId:               deviceCID,
						TransportPeerId:        sharedTransportPeerID,
						DeviceSigningPublicKey: pubC,
						KeyPackageId:           "ga021-kp-c",
						Status:                 "active",
					},
				},
			},
		},
		CreatedBy: nodeA.PeerId(),
	}
	ambiguousConfig := cloneGroupConfig(cSharedConfig)
	ambiguousConfig.Members[1].Devices[0].TransportPeerId = sharedTransportPeerID

	if err := validateGroupConfigTransportPeerUniqueness(cSharedConfig); err != nil {
		t.Fatalf("safe setup should not have duplicate transport peers: %v", err)
	}
	if err := validateGroupConfigTransportPeerUniqueness(ambiguousConfig); err == nil {
		t.Fatalf("ambiguous config should reject duplicate active transport peer")
	}
	if reason, err := validateGroupConfigIdentityUniqueness(ambiguousConfig); err == nil || reason != "ambiguous_transport_peer" {
		t.Fatalf("ambiguous identity validation reason=%q err=%v, want ambiguous_transport_peer", reason, err)
	}

	rejectGroupId := groupId + "-join-reject"
	if err := nodeReject.JoinGroupTopic(rejectGroupId, ambiguousConfig, keyInfo); err == nil || !strings.Contains(err.Error(), "ambiguous transport peer") {
		t.Fatalf("ambiguous JoinGroupTopic error = %v, want ambiguous transport peer", err)
	}
	nodeReject.mu.RLock()
	_, topicStored := nodeReject.groupTopics[rejectGroupId]
	_, configStored := nodeReject.groupConfigs[rejectGroupId]
	nodeReject.mu.RUnlock()
	if topicStored || configStored {
		t.Fatalf("ambiguous JoinGroupTopic stored topic=%v config=%v", topicStored, configStored)
	}

	if err := nodeA.JoinGroupTopic(groupId, cSharedConfig, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeSharedTransport.JoinGroupTopic(groupId, cSharedConfig, keyInfo); err != nil {
		t.Fatalf("nodeSharedTransport JoinGroupTopic: %v", err)
	}
	connectLocalGroupNodes(t, nodeSharedTransport, nodeA)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 3*time.Second)
	waitForGroupTopicPeerCount(t, nodeSharedTransport, groupId, 1, 3*time.Second)

	plaintextMarker := "ga021-duplicate-transport-peer-impersonation"
	envelopeJSON := buildTestDeviceEnvelopeWithPlaintext(
		t,
		groupId,
		"group_message",
		memberCID,
		deviceCID,
		sharedTransportPeerID,
		pubC,
		"ga021-kp-c",
		privC,
		pubC,
		groupKey,
		keyInfo.KeyEpoch,
		`{"text":"`+plaintextMarker+`","timestamp":"2026-05-12T20:51:01Z"}`,
	)
	if result := validateGroupEnvelopeForTransportPeer(envelopeJSON, groupId, cSharedConfig, keyInfo, sharedTransportPeerID); result != "accept" {
		t.Fatalf("safe config pure validator = %s, want accept", result)
	}
	if result := validateGroupEnvelopeForTransportPeer(envelopeJSON, groupId, ambiguousConfig, keyInfo, sharedTransportPeerID); result != "reject:ambiguous_transport_peer" {
		t.Fatalf("ambiguous config pure validator = %s, want reject:ambiguous_transport_peer", result)
	}

	nodeA.UpdateGroupConfig(groupId, ambiguousConfig)
	baseline := len(nodeACapture.snapshot())
	publishRawGroupEnvelope(t, nodeSharedTransport, groupId, envelopeJSON)
	waitForCollectedValidationReject(t, nodeACapture, baseline, "ambiguous_transport_peer", keyInfo.KeyEpoch, 5*time.Second)
	for _, forbidden := range []string{
		`"event":"group_message:received"`,
		`"event":"group_reaction:received"`,
		`"event":"group:decryption_failed"`,
		`"event":"group:payload_parse_failed"`,
		plaintextMarker,
	} {
		t.Run("duplicate transport peer rejected/"+forbidden, func(t *testing.T) {
			assertNoCollectedEventContainingAfter(t, nodeACapture, baseline, forbidden, 500*time.Millisecond)
		})
	}
	if _, _, err := nodeA.PublishGroupMessage(
		groupId,
		privC,
		memberCID,
		pubC,
		"Charlie",
		"GA021 local publish blocked",
		"ga021-local-publish-blocked",
		map[string]interface{}{
			"senderDeviceId":        deviceCID,
			"senderTransportPeerId": sharedTransportPeerID,
			"senderDevicePublicKey": pubC,
			"senderKeyPackageId":    "ga021-kp-c",
		},
	); err == nil || !strings.Contains(err.Error(), "ambiguous transport peer") {
		t.Fatalf("ambiguous local PublishGroupMessage error = %v, want ambiguous transport peer", err)
	}
}

func TestGK030PublishGroupMessagePreservesExtraFieldsInReceivedEvent(t *testing.T) {
	groupId := "gk030-extra-field-delivery"
	harness := setupLP013TwoNodeGroup(t, groupId)
	messageId := "gk030-msg-1"
	opts := map[string]interface{}{
		"quotedMessageId": "gk030-parent",
		"media": []map[string]interface{}{
			{"id": "media-1", "mime": "image/png"},
		},
		"attachments": []map[string]interface{}{
			{"id": "att-1", "name": "agenda.pdf"},
		},
		"deliveryId":      "delivery-gk030",
		"clientMessageId": "client-gk030",
		"unknownRenderHint": map[string]interface{}{
			"slot": "inline",
		},
		"groupId":        "spoofed-group",
		"senderId":       "spoofed-sender",
		"senderUsername": "Mallory",
		"keyEpoch":       999,
		"text":           "spoofed text",
		"timestamp":      "1999-01-01T00:00:00Z",
		"deliveryMs":     -1,
	}

	baseline := len(harness.nodeBCapture.snapshot())
	msgID, peerCount, err := harness.nodeA.PublishGroupMessage(
		groupId,
		harness.privB64,
		harness.nodeA.PeerId(),
		harness.pubB64,
		"Alice",
		"GK-030 full extra field delivery",
		messageId,
		opts,
	)
	if err != nil {
		t.Fatalf("PublishGroupMessage: %v", err)
	}
	if msgID != messageId {
		t.Fatalf("messageId = %q, want %q", msgID, messageId)
	}
	if peerCount < 1 {
		t.Fatalf("expected topicPeers >= 1, got %d", peerCount)
	}
	if _, ok := opts["publishedAtNano"]; ok {
		t.Fatal("PublishGroupMessage should not mutate opts with publishedAtNano")
	}

	event := waitForCollectedEventAfter(t, harness.nodeBCapture, baseline, "group_message:received", 5*time.Second)
	for _, tc := range []struct {
		key  string
		want interface{}
	}{
		{key: "messageId", want: messageId},
		{key: "quotedMessageId", want: "gk030-parent"},
		{key: "deliveryId", want: "delivery-gk030"},
		{key: "clientMessageId", want: "client-gk030"},
		{key: "groupId", want: groupId},
		{key: "senderId", want: harness.nodeA.PeerId()},
		{key: "senderUsername", want: "Alice"},
		{key: "keyEpoch", want: float64(harness.keyInfo.KeyEpoch)},
		{key: "text", want: "GK-030 full extra field delivery"},
	} {
		if got := event[tc.key]; got != tc.want {
			t.Fatalf("%s = %v, want %v", tc.key, got, tc.want)
		}
	}
	if publishedAtNano, ok := event["publishedAtNano"].(string); !ok || publishedAtNano == "" {
		t.Fatalf("publishedAtNano = %#v, want non-empty string", event["publishedAtNano"])
	}
	if media, ok := event["media"].([]interface{}); !ok || len(media) != 1 {
		t.Fatalf("media = %#v, want one item", event["media"])
	}
	if attachments, ok := event["attachments"].([]interface{}); !ok || len(attachments) != 1 {
		t.Fatalf("attachments = %#v, want one item", event["attachments"])
	}
	if hint, ok := event["unknownRenderHint"].(map[string]interface{}); !ok || hint["slot"] != "inline" {
		t.Fatalf("unknownRenderHint = %#v, want preserved map", event["unknownRenderHint"])
	}
	if got, ok := event["deliveryMs"].(float64); !ok || got < 0 {
		t.Fatalf("deliveryMs = %#v, want receive-path metric", event["deliveryMs"])
	}
}

func TestGK031PublishGroupMessageExplicitMessageIDWinsOverOptsMessageID(t *testing.T) {
	groupId := "gk031-explicit-message-id-delivery"
	harness := setupLP013TwoNodeGroup(t, groupId)
	explicitMessageId := "gk031-explicit-message"
	opts := map[string]interface{}{
		"messageId":       "gk031-spoofed-opts-message",
		"quotedMessageId": "gk031-parent",
		"clientMessageId": "gk031-client",
	}

	receiverBaseline := len(harness.nodeBCapture.snapshot())
	msgID, peerCount, err := harness.nodeA.PublishGroupMessage(
		groupId,
		harness.privB64,
		harness.nodeA.PeerId(),
		harness.pubB64,
		"Alice",
		"GK-031 explicit message id delivery",
		explicitMessageId,
		opts,
	)
	if err != nil {
		t.Fatalf("PublishGroupMessage: %v", err)
	}
	if msgID != explicitMessageId {
		t.Fatalf("PublishGroupMessage messageId = %q, want %q", msgID, explicitMessageId)
	}
	if peerCount < 1 {
		t.Fatalf("expected topicPeers >= 1, got %d", peerCount)
	}
	if got := opts["messageId"]; got != "gk031-spoofed-opts-message" {
		t.Fatalf("opts messageId mutated to %v", got)
	}

	event := waitForCollectedEventAfter(t, harness.nodeBCapture, receiverBaseline, "group_message:received", 5*time.Second)
	for _, tc := range []struct {
		key  string
		want interface{}
	}{
		{key: "messageId", want: explicitMessageId},
		{key: "quotedMessageId", want: "gk031-parent"},
		{key: "clientMessageId", want: "gk031-client"},
		{key: "groupId", want: groupId},
		{key: "senderId", want: harness.nodeA.PeerId()},
		{key: "senderUsername", want: "Alice"},
		{key: "text", want: "GK-031 explicit message id delivery"},
	} {
		if got := event[tc.key]; got != tc.want {
			t.Fatalf("%s = %v, want %v", tc.key, got, tc.want)
		}
	}
}

func TestGK032PublishedAtNanoInvalidValuesStillEmitMessageWithoutDeliveryMs(t *testing.T) {
	groupId := "gk032-published-at-nano-parse-safe"
	harness := setupLP013TwoNodeGroup(t, groupId)

	cases := []struct {
		name        string
		messageId   string
		extra       map[string]interface{}
		wantPresent bool
		wantValue   interface{}
	}{
		{
			name:      "missing",
			messageId: "gk032-missing-published-at",
			extra: map[string]interface{}{
				"messageId": "gk032-missing-published-at",
			},
		},
		{
			name:      "malformed",
			messageId: "gk032-malformed-published-at",
			extra: map[string]interface{}{
				"messageId":       "gk032-malformed-published-at",
				"publishedAtNano": "not-a-nanosecond",
			},
			wantPresent: true,
			wantValue:   "not-a-nanosecond",
		},
		{
			name:      "huge overflow",
			messageId: "gk032-huge-published-at",
			extra: map[string]interface{}{
				"messageId":       "gk032-huge-published-at",
				"publishedAtNano": "999999999999999999999999999999999999",
			},
			wantPresent: true,
			wantValue:   "999999999999999999999999999999999999",
		},
		{
			name:      "non-string",
			messageId: "gk032-non-string-published-at",
			extra: map[string]interface{}{
				"messageId":       "gk032-non-string-published-at",
				"publishedAtNano": float64(12345),
			},
			wantPresent: true,
			wantValue:   float64(12345),
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			baseline := len(harness.nodeBCapture.snapshot())
			envelopeJSON := buildLP013GroupMessageEnvelopeWithExtra(
				t,
				harness,
				groupId,
				"GK-032 "+tc.name,
				time.Now().UTC().Format(time.RFC3339Nano),
				tc.extra,
			)
			publishLP013RawGroupEnvelope(t, harness.nodeA, groupId, envelopeJSON)

			event := waitForCollectedEventAfter(t, harness.nodeBCapture, baseline, "group_message:received", 5*time.Second)
			if got := event["messageId"]; got != tc.messageId {
				t.Fatalf("messageId = %v, want %v", got, tc.messageId)
			}
			if got := event["text"]; got != "GK-032 "+tc.name {
				t.Fatalf("text = %v, want %v", got, "GK-032 "+tc.name)
			}
			if _, ok := event["deliveryMs"]; ok {
				t.Fatalf("deliveryMs = %#v, want omitted for invalid publishedAtNano", event["deliveryMs"])
			}
			got, ok := event["publishedAtNano"]
			if ok != tc.wantPresent {
				t.Fatalf("publishedAtNano present = %t, want %t; value=%#v", ok, tc.wantPresent, got)
			}
			if tc.wantPresent && got != tc.wantValue {
				t.Fatalf("publishedAtNano = %#v, want %#v", got, tc.wantValue)
			}
		})
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

func TestBB007FullConfigJoinDeliversLiveMessageAtJoinedEpoch(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	_, receiverPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeA := startLocalNodeForMultiRelayTest(t)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

	groupId := "bb007-full-config-live-delivery"
	messageId := "bb007-live-message-at-epoch-7"
	config := &GroupConfig{
		Name:        "BB-007 Full Config Delivery Group",
		GroupType:   GroupTypeChat,
		Description: "Full-config join payload live decrypt proof",
		Members: []GroupMember{
			{
				PeerId:         nodeA.PeerId(),
				Username:       "BB-007 Admin",
				Role:           GroupRoleAdmin,
				PublicKey:      senderPubB64,
				MlKemPublicKey: "bb007-admin-mlkem",
			},
			{
				PeerId:         nodeB.PeerId(),
				Username:       "BB-007 Receiver",
				Role:           GroupRoleWriter,
				PublicKey:      receiverPubB64,
				MlKemPublicKey: "bb007-receiver-mlkem",
			},
		},
		CreatedBy: nodeA.PeerId(),
		CreatedAt: "2026-05-10T20:00:00Z",
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 7}

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

	baselineEvents := len(nodeBCapture.snapshot())
	msgId, peerCount, err := nodeA.PublishGroupMessage(
		groupId,
		senderPrivB64,
		nodeA.PeerId(),
		senderPubB64,
		"BB-007 Admin",
		"BB-007 live message at joined epoch",
		messageId,
		nil,
	)
	if err != nil {
		t.Fatalf("PublishGroupMessage failed: %v", err)
	}
	if msgId != messageId {
		t.Fatalf("messageId = %q, want %q", msgId, messageId)
	}
	if peerCount < 1 {
		t.Fatalf("topicPeers = %d, want >= 1", peerCount)
	}

	events := waitForCollectedEventCount(t, nodeBCapture, "group_message:received", 1, 5*time.Second)
	event := events[0]
	if got, _ := event["messageId"].(string); got != messageId {
		t.Fatalf("event messageId = %q, want %q", got, messageId)
	}
	if got, _ := event["text"].(string); got != "BB-007 live message at joined epoch" {
		t.Fatalf("event text = %q, want BB-007 live message at joined epoch", got)
	}
	if got, _ := event["senderId"].(string); got != nodeA.PeerId() {
		t.Fatalf("event senderId = %q, want %q", got, nodeA.PeerId())
	}
	if got := int(event["keyEpoch"].(float64)); got != keyInfo.KeyEpoch {
		t.Fatalf("event keyEpoch = %d, want %d", got, keyInfo.KeyEpoch)
	}
	assertNoCollectedEventContainingAfter(t, nodeBCapture, baselineEvents, `"event":"group:decryption_failed"`, 200*time.Millisecond)
}

func TestGL009LeaveGroupTopicUnregistersValidatorAndRejoinUsesLatestConfigKey(t *testing.T) {
	testGL009LeaveGroupTopicUnregistersValidatorAndRejoinUsesLatestConfigKey(t)
}

func TestRA014GL009LeaveGroupTopicUnregistersValidatorAndRejoinUsesLatestConfigKey(t *testing.T) {
	testGL009LeaveGroupTopicUnregistersValidatorAndRejoinUsesLatestConfigKey(t)
}

func testGL009LeaveGroupTopicUnregistersValidatorAndRejoinUsesLatestConfigKey(t *testing.T) {
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

func TestGM034StableMemberDeliverySurvivesUnrelatedConfigUpdateOrders(t *testing.T) {
	type orderCase struct {
		name                string
		updateBeforePublish bool
	}

	for _, tc := range []orderCase{
		{name: "message_then_config", updateBeforePublish: false},
		{name: "config_then_message", updateBeforePublish: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			privA, pubA := generateEd25519KeyPair(t)
			_, pubB := generateEd25519KeyPair(t)
			_, pubC := generateEd25519KeyPair(t)
			groupKey, err := mcrypto.GenerateGroupKey()
			if err != nil {
				t.Fatalf("generate group key: %v", err)
			}

			nodeA := startLocalNodeForMultiRelayTest(t)
			nodeBCapture := &testEventCollector{}
			nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)
			nodeC := startLocalNodeForMultiRelayTest(t)

			groupId := fmt.Sprintf("gm034-%s", tc.name)
			keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
			configWithC := &GroupConfig{
				Name:      "GM034 Stable Delivery",
				GroupType: GroupTypeChat,
				Members: []GroupMember{
					{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: pubA},
					{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: pubB},
					{PeerId: nodeC.PeerId(), Role: GroupRoleWriter, PublicKey: pubC},
				},
				CreatedBy: nodeA.PeerId(),
			}
			configWithoutC := &GroupConfig{
				Name:      "GM034 Stable Delivery",
				GroupType: GroupTypeChat,
				Members: []GroupMember{
					{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: pubA},
					{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: pubB},
				},
				CreatedBy: nodeA.PeerId(),
			}

			for label, n := range map[string]*Node{
				"nodeA": nodeA,
				"nodeB": nodeB,
				"nodeC": nodeC,
			} {
				if err := n.JoinGroupTopic(groupId, configWithC, keyInfo); err != nil {
					t.Fatalf("%s JoinGroupTopic: %v", label, err)
				}
			}

			connectLocalGroupNodes(t, nodeA, nodeB)
			connectLocalGroupNodes(t, nodeA, nodeC)
			connectLocalGroupNodes(t, nodeB, nodeC)
			waitForGroupTopicPeerCount(t, nodeA, groupId, 2, 3*time.Second)
			waitForGroupTopicPeerCount(t, nodeB, groupId, 2, 3*time.Second)

			assertNodeBConfigMembers := func(want map[string]bool) {
				t.Helper()

				nodeB.mu.RLock()
				stored := cloneGroupConfig(nodeB.groupConfigs[groupId])
				nodeB.mu.RUnlock()
				if stored == nil {
					t.Fatalf("nodeB missing stored config for %s", groupId)
				}

				got := make(map[string]bool, len(stored.Members))
				for _, member := range stored.Members {
					got[member.PeerId] = true
				}
				if len(got) != len(want) {
					t.Fatalf("nodeB config members = %v, want %v", got, want)
				}
				for peerID := range want {
					if !got[peerID] {
						t.Fatalf("nodeB config members = %v, missing %s", got, peerID)
					}
				}
			}

			waitForMessageAfter := func(baseline int, messageId, text string) map[string]interface{} {
				t.Helper()

				deadline := time.Now().Add(5 * time.Second)
				for time.Now().Before(deadline) {
					var match map[string]interface{}
					matchCount := 0
					for _, raw := range nodeBCapture.snapshot()[baseline:] {
						var payload map[string]interface{}
						if err := json.Unmarshal([]byte(raw), &payload); err != nil {
							continue
						}
						if payload["event"] != "group_message:received" {
							continue
						}
						data, _ := payload["data"].(map[string]interface{})
						if data["messageId"] == messageId && data["text"] == text {
							match = data
							matchCount++
						}
					}
					if matchCount == 1 {
						return match
					}
					if matchCount > 1 {
						t.Fatalf("nodeB received duplicate GM-034 messageId=%s text=%q", messageId, text)
					}
					time.Sleep(25 * time.Millisecond)
				}

				t.Fatalf("timed out waiting for nodeB GM-034 messageId=%s text=%q; events=%s", messageId, text, strings.Join(nodeBCapture.snapshot()[baseline:], "\n"))
				return nil
			}

			assertNoValidationRejectAfter := func(baseline int) {
				t.Helper()

				deadline := time.Now().Add(300 * time.Millisecond)
				for time.Now().Before(deadline) {
					for _, raw := range nodeBCapture.snapshot()[baseline:] {
						var payload map[string]interface{}
						if err := json.Unmarshal([]byte(raw), &payload); err != nil {
							continue
						}
						if payload["event"] == "group:validation_rejected" {
							t.Fatalf("nodeB rejected GM-034 stable Alice delivery after %s: %s", tc.name, raw)
						}
					}
					time.Sleep(25 * time.Millisecond)
				}
			}

			baseline := len(nodeBCapture.snapshot())
			if tc.updateBeforePublish {
				nodeB.UpdateGroupConfig(groupId, configWithoutC)
				assertNodeBConfigMembers(map[string]bool{
					nodeA.PeerId(): true,
					nodeB.PeerId(): true,
				})
			}

			marker := fmt.Sprintf("gm034-%s-alice-valid", tc.name)
			messageId := fmt.Sprintf("gm034-%s-message", tc.name)
			msgID, peerCount, err := nodeA.PublishGroupMessage(
				groupId,
				privA,
				nodeA.PeerId(),
				pubA,
				"Alice",
				marker,
				messageId,
				nil,
			)
			if err != nil {
				t.Fatalf("nodeA PublishGroupMessage %s: %v", tc.name, err)
			}
			if msgID != messageId || peerCount < 1 {
				t.Fatalf("publish %s returned msgID=%q peerCount=%d, want %q/>=1", tc.name, msgID, peerCount, messageId)
			}

			received := waitForMessageAfter(baseline, messageId, marker)
			if got, _ := received["senderId"].(string); got != nodeA.PeerId() {
				t.Fatalf("%s senderId = %q, want %q", tc.name, got, nodeA.PeerId())
			}
			if got := int(received["keyEpoch"].(float64)); got != keyInfo.KeyEpoch {
				t.Fatalf("%s keyEpoch = %d, want %d", tc.name, got, keyInfo.KeyEpoch)
			}

			if !tc.updateBeforePublish {
				nodeB.UpdateGroupConfig(groupId, configWithoutC)
				assertNodeBConfigMembers(map[string]bool{
					nodeA.PeerId(): true,
					nodeB.PeerId(): true,
				})
			}
			assertNoValidationRejectAfter(baseline)
		})
	}
}

func TestGM017RemovedMemberWithStaleSubscriptionRejectedByRemainingValidators(t *testing.T) {
	privA, pubA := generateEd25519KeyPair(t)
	privB, pubB := generateEd25519KeyPair(t)
	privC, pubC := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeACapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)
	nodeC := startLocalNodeForMultiRelayTest(t)

	groupId := "gm017-stale-subscription-validator-backstop"
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	configWithC := &GroupConfig{
		Name:      "GM017 Stale Subscription",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: pubA},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: pubB},
			{PeerId: nodeC.PeerId(), Role: GroupRoleWriter, PublicKey: pubC},
		},
		CreatedBy: nodeA.PeerId(),
	}

	for label, n := range map[string]*Node{
		"nodeA": nodeA,
		"nodeB": nodeB,
		"nodeC": nodeC,
	} {
		if err := n.JoinGroupTopic(groupId, configWithC, keyInfo); err != nil {
			t.Fatalf("%s JoinGroupTopic: %v", label, err)
		}
	}

	connectLocalGroupNodes(t, nodeC, nodeA)
	connectLocalGroupNodes(t, nodeC, nodeB)
	connectLocalGroupNodes(t, nodeA, nodeB)
	waitForGroupTopicPeerCount(t, nodeC, groupId, 2, 3*time.Second)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 2, 3*time.Second)
	waitForGroupTopicPeerCount(t, nodeB, groupId, 2, 3*time.Second)

	beforeMarker := "gm017-charlie-before-removal"
	msgID, peerCount, err := nodeC.PublishGroupMessage(
		groupId,
		privC,
		nodeC.PeerId(),
		pubC,
		"Charlie",
		beforeMarker,
		"gm017-charlie-before-removal-message",
		nil,
	)
	if err != nil {
		t.Fatalf("nodeC PublishGroupMessage before removal: %v", err)
	}
	if msgID == "" || peerCount < 2 {
		t.Fatalf("before removal publish returned msgID=%q peerCount=%d, want non-empty/>=2", msgID, peerCount)
	}
	waitForCollectedEventContaining(t, nodeACapture, beforeMarker, 5*time.Second)
	waitForCollectedEventContaining(t, nodeBCapture, beforeMarker, 5*time.Second)

	configWithoutC := &GroupConfig{
		Name:      "GM017 Stale Subscription",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: pubA},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: pubB},
		},
		CreatedBy: nodeA.PeerId(),
	}
	nodeA.UpdateGroupConfig(groupId, configWithoutC)
	nodeB.UpdateGroupConfig(groupId, configWithoutC)

	nodeC.mu.RLock()
	staleConfig := nodeC.groupConfigs[groupId]
	_, charlieTopicStillJoined := nodeC.groupTopics[groupId]
	nodeC.mu.RUnlock()
	if !charlieTopicStillJoined || findMember(staleConfig, nodeC.PeerId()) == nil {
		t.Fatal("nodeC must remain joined locally with stale membership state for GM-017")
	}

	rejectBaselineA := len(nodeACapture.snapshot())
	rejectBaselineB := len(nodeBCapture.snapshot())
	staleMarker := "gm017-charlie-stale-after-removal"
	msgID, peerCount, err = nodeC.PublishGroupMessage(
		groupId,
		privC,
		nodeC.PeerId(),
		pubC,
		"Charlie",
		staleMarker,
		"gm017-charlie-stale-after-removal-message",
		nil,
	)
	if err != nil {
		t.Fatalf("nodeC stale PublishGroupMessage after removal: %v", err)
	}
	if msgID == "" || peerCount < 2 {
		t.Fatalf("stale publish returned msgID=%q peerCount=%d, want non-empty/>=2", msgID, peerCount)
	}

	allowedRejectReasons := []string{"non_member", "bad_signature_or_epoch"}
	waitForCollectedValidationRejectAny(t, nodeACapture, rejectBaselineA, allowedRejectReasons, keyInfo.KeyEpoch, 5*time.Second)
	waitForCollectedValidationRejectAny(t, nodeBCapture, rejectBaselineB, allowedRejectReasons, keyInfo.KeyEpoch, 5*time.Second)
	assertNoCollectedEventContainingAfter(t, nodeACapture, rejectBaselineA, staleMarker, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaselineB, staleMarker, 500*time.Millisecond)

	healthyMarker := "gm017-alice-bob-healthy-after-reject"
	msgID, peerCount, err = nodeA.PublishGroupMessage(
		groupId,
		privA,
		nodeA.PeerId(),
		pubA,
		"Alice",
		healthyMarker,
		"gm017-alice-healthy-after-reject-message",
		nil,
	)
	if err != nil {
		t.Fatalf("nodeA PublishGroupMessage after stale rejection: %v", err)
	}
	if msgID == "" || peerCount < 1 {
		t.Fatalf("healthy publish returned msgID=%q peerCount=%d, want non-empty/>=1", msgID, peerCount)
	}
	waitForCollectedEventContaining(t, nodeBCapture, healthyMarker, 5*time.Second)

	healthyReplyMarker := "gm017-bob-alice-healthy-after-reject"
	msgID, peerCount, err = nodeB.PublishGroupMessage(
		groupId,
		privB,
		nodeB.PeerId(),
		pubB,
		"Bob",
		healthyReplyMarker,
		"gm017-bob-healthy-after-reject-message",
		nil,
	)
	if err != nil {
		t.Fatalf("nodeB PublishGroupMessage after stale rejection: %v", err)
	}
	if msgID == "" || peerCount < 1 {
		t.Fatalf("healthy reply returned msgID=%q peerCount=%d, want non-empty/>=1", msgID, peerCount)
	}
	waitForCollectedEventContaining(t, nodeACapture, healthyReplyMarker, 5*time.Second)
}

func TestGO003StaleSenderValidationFeedbackReturnsToPublisher(t *testing.T) {
	_, pubA := generateEd25519KeyPair(t)
	_, pubB := generateEd25519KeyPair(t)
	privC, pubC := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeACapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeB := startLocalNodeForMultiRelayTest(t)
	nodeCCapture := &testEventCollector{}
	nodeC := startLocalNodeForMultiRelayTestWithCollector(t, nodeCCapture)

	groupId := "go003-stale-sender-feedback"
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	configWithC := &GroupConfig{
		Name:      "GO003 Stale Sender Feedback",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: pubA},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: pubB},
			{PeerId: nodeC.PeerId(), Role: GroupRoleWriter, PublicKey: pubC},
		},
		CreatedBy: nodeA.PeerId(),
	}

	for label, n := range map[string]*Node{
		"nodeA": nodeA,
		"nodeB": nodeB,
		"nodeC": nodeC,
	} {
		if err := n.JoinGroupTopic(groupId, configWithC, keyInfo); err != nil {
			t.Fatalf("%s JoinGroupTopic: %v", label, err)
		}
	}

	connectLocalGroupNodes(t, nodeC, nodeA)
	connectLocalGroupNodes(t, nodeC, nodeB)
	connectLocalGroupNodes(t, nodeA, nodeB)
	waitForGroupTopicPeerCount(t, nodeC, groupId, 2, 3*time.Second)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 2, 3*time.Second)

	configWithoutC := &GroupConfig{
		Name:      "GO003 Stale Sender Feedback",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: pubA},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: pubB},
		},
		CreatedBy: nodeA.PeerId(),
	}
	nodeA.UpdateGroupConfig(groupId, configWithoutC)
	nodeB.UpdateGroupConfig(groupId, configWithoutC)

	rejectBaselineA := len(nodeACapture.snapshot())
	feedbackBaselineC := len(nodeCCapture.snapshot())
	messageId := "go003-charlie-stale-after-removal-message"
	staleMarker := "go003-charlie-stale-after-removal"
	msgID, peerCount, err := nodeC.PublishGroupMessage(
		groupId,
		privC,
		nodeC.PeerId(),
		pubC,
		"Charlie",
		staleMarker,
		messageId,
		nil,
	)
	if err != nil {
		t.Fatalf("nodeC stale PublishGroupMessage: %v", err)
	}
	if msgID != messageId || peerCount < 2 {
		t.Fatalf("stale publish returned msgID=%q peerCount=%d, want %q/>=2", msgID, peerCount, messageId)
	}

	reason := waitForCollectedValidationRejectAny(
		t,
		nodeACapture,
		rejectBaselineA,
		[]string{"non_member", "bad_signature_or_epoch"},
		keyInfo.KeyEpoch,
		5*time.Second,
	)
	feedback := waitForCollectedEventAfter(
		t,
		nodeCCapture,
		feedbackBaselineC,
		"group:publish_validation_rejected",
		5*time.Second,
	)
	if got, _ := feedback["groupId"].(string); got != groupId {
		t.Fatalf("validation feedback groupId = %q, want %q", got, groupId)
	}
	if got, _ := feedback["messageId"].(string); got != messageId {
		t.Fatalf("validation feedback messageId = %q, want %q", got, messageId)
	}
	if got, _ := feedback["reason"].(string); got != reason {
		t.Fatalf("validation feedback reason = %q, want recipient reject reason %q", got, reason)
	}
	if got, _ := feedback["envelopeType"].(string); got != "group_message" {
		t.Fatalf("validation feedback envelopeType = %q, want group_message", got)
	}
	if got := int(feedback["keyEpoch"].(float64)); got != keyInfo.KeyEpoch {
		t.Fatalf("validation feedback keyEpoch = %d, want %d", got, keyInfo.KeyEpoch)
	}

	assertNoCollectedEventContainingAfter(t, nodeACapture, rejectBaselineA, staleMarker, 500*time.Millisecond)
}

func TestGM018RemainingMembersDeliverySurvivesRemovedMemberStalePressure(t *testing.T) {
	privA, pubA := generateEd25519KeyPair(t)
	_, pubB := generateEd25519KeyPair(t)
	privC, pubC := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeACapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)
	nodeC := startLocalNodeForMultiRelayTest(t)

	groupId := "gm018-remaining-delivery-stale-pressure"
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	configWithC := &GroupConfig{
		Name:      "GM018 Remaining Delivery",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: pubA},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: pubB},
			{PeerId: nodeC.PeerId(), Role: GroupRoleWriter, PublicKey: pubC},
		},
		CreatedBy: nodeA.PeerId(),
	}

	for label, n := range map[string]*Node{
		"nodeA": nodeA,
		"nodeB": nodeB,
		"nodeC": nodeC,
	} {
		if err := n.JoinGroupTopic(groupId, configWithC, keyInfo); err != nil {
			t.Fatalf("%s JoinGroupTopic: %v", label, err)
		}
	}

	connectLocalGroupNodes(t, nodeC, nodeA)
	connectLocalGroupNodes(t, nodeC, nodeB)
	connectLocalGroupNodes(t, nodeA, nodeB)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 2, 3*time.Second)
	waitForGroupTopicPeerCount(t, nodeB, groupId, 2, 3*time.Second)
	waitForGroupTopicPeerCount(t, nodeC, groupId, 2, 3*time.Second)

	configWithoutC := &GroupConfig{
		Name:      "GM018 Remaining Delivery",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: pubA},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: pubB},
		},
		CreatedBy: nodeA.PeerId(),
	}
	nodeA.UpdateGroupConfig(groupId, configWithoutC)
	nodeB.UpdateGroupConfig(groupId, configWithoutC)

	nodeC.mu.RLock()
	staleConfig := nodeC.groupConfigs[groupId]
	_, charlieTopicStillJoined := nodeC.groupTopics[groupId]
	nodeC.mu.RUnlock()
	if !charlieTopicStillJoined || findMember(staleConfig, nodeC.PeerId()) == nil {
		t.Fatal("nodeC must remain joined locally with stale membership state for GM-018")
	}

	allowedRejectReasons := []string{"non_member", "bad_signature_or_epoch"}
	staleMarker := "gm018-charlie-stale-online"
	rejectBaselineA := len(nodeACapture.snapshot())
	rejectBaselineB := len(nodeBCapture.snapshot())
	msgID, peerCount, err := nodeC.PublishGroupMessage(
		groupId,
		privC,
		nodeC.PeerId(),
		pubC,
		"Charlie",
		staleMarker,
		"gm018-charlie-stale-online-message",
		nil,
	)
	if err != nil {
		t.Fatalf("nodeC stale PublishGroupMessage: %v", err)
	}
	if msgID == "" || peerCount < 2 {
		t.Fatalf("stale publish returned msgID=%q peerCount=%d, want non-empty/>=2", msgID, peerCount)
	}
	waitForCollectedValidationRejectAny(t, nodeACapture, rejectBaselineA, allowedRejectReasons, keyInfo.KeyEpoch, 5*time.Second)
	waitForCollectedValidationRejectAny(t, nodeBCapture, rejectBaselineB, allowedRejectReasons, keyInfo.KeyEpoch, 5*time.Second)
	assertNoCollectedEventContainingAfter(t, nodeACapture, rejectBaselineA, staleMarker, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaselineB, staleMarker, 500*time.Millisecond)

	for i := 1; i <= 3; i++ {
		healthyMarker := fmt.Sprintf("gm018-alice-bob-live-%d", i)
		msgID, peerCount, err = nodeA.PublishGroupMessage(
			groupId,
			privA,
			nodeA.PeerId(),
			pubA,
			"Alice",
			healthyMarker,
			fmt.Sprintf("gm018-alice-bob-live-message-%d", i),
			nil,
		)
		if err != nil {
			t.Fatalf("nodeA PublishGroupMessage live %d: %v", i, err)
		}
		if msgID == "" || peerCount < 1 {
			t.Fatalf("healthy publish live %d returned msgID=%q peerCount=%d, want non-empty/>=1", i, msgID, peerCount)
		}
		waitForCollectedEventContaining(t, nodeBCapture, healthyMarker, 5*time.Second)
	}

	if err := nodeC.LeaveGroupTopic(groupId); err != nil {
		t.Fatalf("nodeC LeaveGroupTopic: %v", err)
	}

	for i := 1; i <= 2; i++ {
		offlineMarker := fmt.Sprintf("gm018-alice-bob-after-charlie-offline-%d", i)
		msgID, peerCount, err := nodeA.PublishGroupMessage(
			groupId,
			privA,
			nodeA.PeerId(),
			pubA,
			"Alice",
			offlineMarker,
			fmt.Sprintf("gm018-alice-bob-offline-message-%d", i),
			nil,
		)
		if err != nil {
			t.Fatalf("nodeA PublishGroupMessage after stale offline %d: %v", i, err)
		}
		if msgID == "" || peerCount < 1 {
			t.Fatalf("healthy publish offline %d returned msgID=%q peerCount=%d, want non-empty/>=1", i, msgID, peerCount)
		}
		waitForCollectedEventContaining(t, nodeBCapture, offlineMarker, 5*time.Second)
	}
}

func TestPublishGroupMessage_RefreshesMissingKnownTopicPeersBeforePublish(t *testing.T) {
	privB64, pubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeACapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
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

func waitForCollectedEventData(
	t *testing.T,
	collector *testEventCollector,
	eventName string,
	matches func(map[string]interface{}) bool,
	timeout time.Duration,
) map[string]interface{} {
	t.Helper()

	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		for _, event := range collector.collectEvents(eventName) {
			if matches == nil || matches(event) {
				return event
			}
		}
		time.Sleep(25 * time.Millisecond)
	}

	t.Fatalf("timed out waiting for %q event matching predicate; events=%v", eventName, collector.snapshot())
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

func waitForCollectedValidationRejectAny(t *testing.T, collector *testEventCollector, baseline int, reasons []string, keyEpoch int, timeout time.Duration) string {
	t.Helper()

	allowedReasons := make(map[string]struct{}, len(reasons))
	for _, reason := range reasons {
		allowedReasons[reason] = struct{}{}
	}

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
			reason, _ := data["reason"].(string)
			gotEpoch, _ := data["keyEpoch"].(float64)
			if _, ok := allowedReasons[reason]; ok && int(gotEpoch) == keyEpoch {
				return reason
			}
		}
		time.Sleep(25 * time.Millisecond)
	}

	events := collector.snapshot()
	t.Fatalf(
		"timed out waiting for validation reject reasons=%s keyEpoch=%d after baseline %d; events=%s",
		strings.Join(reasons, ","),
		keyEpoch,
		baseline,
		strings.Join(events[baseline:], "\n"),
	)
	return ""
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

func assertNoDiscoveryStepAndPeerAfter(t *testing.T, collector *testEventCollector, baseline int, groupID, step, peerID string, timeout time.Duration) {
	t.Helper()

	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		for _, raw := range collector.snapshot()[baseline:] {
			var payload map[string]interface{}
			if err := json.Unmarshal([]byte(raw), &payload); err != nil {
				continue
			}
			if payload["event"] != "group:discovery" {
				continue
			}
			data, _ := payload["data"].(map[string]interface{})
			if data["groupId"] == groupID && data["step"] == step && data["peerId"] == peerID {
				t.Fatalf("unexpected group %s discovery step %s peer %s after publish: %s", groupID, step, peerID, raw)
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

func TestGP003PublishUsesCallerProvidedMessageIDInPayloadAndReceivedEvent(t *testing.T) {
	privB64, pubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeACapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

	groupID := "gp003-provided-message-id"
	providedMessageID := "gp003-client-provided-message-id"
	config := &GroupConfig{
		Name:      "GP003 Provided Message ID Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: pubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: "peerBPubKey"},
		},
		CreatedBy: nodeA.PeerId(),
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	if err := nodeA.JoinGroupTopic(groupID, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupID, config, keyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}
	connectLocalGroupNodes(t, nodeA, nodeB)
	waitForGroupTopicPeerCount(t, nodeA, groupID, 1, 3*time.Second)

	senderBaseline := len(nodeACapture.snapshot())
	receiverBaseline := len(nodeBCapture.snapshot())
	msgID, peerCount, err := nodeA.PublishGroupMessage(
		groupID,
		privB64,
		nodeA.PeerId(),
		pubB64,
		"Alice",
		"gp003 provided message body",
		providedMessageID,
		nil,
	)
	if err != nil {
		t.Fatalf("PublishGroupMessage: %v", err)
	}
	if msgID != providedMessageID {
		t.Fatalf("PublishGroupMessage returned messageId = %q, want %q", msgID, providedMessageID)
	}
	if peerCount < 1 {
		t.Fatalf("PublishGroupMessage peerCount = %d, want >= 1", peerCount)
	}

	publishDebug := waitForCollectedEventAfter(t, nodeACapture, senderBaseline, "group:publish_debug", 5*time.Second)
	if got, _ := publishDebug["messageId"].(string); got != providedMessageID {
		t.Fatalf("publish_debug messageId = %q, want %q", got, providedMessageID)
	}

	received := waitForCollectedEventAfter(t, nodeBCapture, receiverBaseline, "group_message:received", 5*time.Second)
	for _, tc := range []struct {
		key  string
		want interface{}
	}{
		{key: "groupId", want: groupID},
		{key: "senderId", want: nodeA.PeerId()},
		{key: "senderUsername", want: "Alice"},
		{key: "messageId", want: providedMessageID},
		{key: "text", want: "gp003 provided message body"},
		{key: "keyEpoch", want: float64(keyInfo.KeyEpoch)},
	} {
		if got := received[tc.key]; got != tc.want {
			t.Fatalf("%s = %v, want %v", tc.key, got, tc.want)
		}
	}
}

func TestGP004PublishGeneratesUUIDWhenMessageIDEmpty(t *testing.T) {
	privB64, pubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeACapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

	groupID := "gp004-generated-message-id"
	config := &GroupConfig{
		Name:      "GP004 Generated Message ID Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: pubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: "peerBPubKey"},
		},
		CreatedBy: nodeA.PeerId(),
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	if err := nodeA.JoinGroupTopic(groupID, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupID, config, keyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}
	connectLocalGroupNodes(t, nodeA, nodeB)
	waitForGroupTopicPeerCount(t, nodeA, groupID, 1, 3*time.Second)

	senderBaseline := len(nodeACapture.snapshot())
	receiverBaseline := len(nodeBCapture.snapshot())
	msgID, peerCount, err := nodeA.PublishGroupMessage(
		groupID,
		privB64,
		nodeA.PeerId(),
		pubB64,
		"Alice",
		"gp004 generated message body",
		"",
		nil,
	)
	if err != nil {
		t.Fatalf("PublishGroupMessage: %v", err)
	}
	uuidV4Pattern := regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`)
	if !uuidV4Pattern.MatchString(msgID) {
		t.Fatalf("generated messageId = %q, want UUID v4", msgID)
	}
	if peerCount < 1 {
		t.Fatalf("PublishGroupMessage peerCount = %d, want >= 1", peerCount)
	}

	publishDebug := waitForCollectedEventAfter(t, nodeACapture, senderBaseline, "group:publish_debug", 5*time.Second)
	if got, _ := publishDebug["messageId"].(string); got != msgID {
		t.Fatalf("publish_debug messageId = %q, want generated id %q", got, msgID)
	}

	received := waitForCollectedEventAfter(t, nodeBCapture, receiverBaseline, "group_message:received", 5*time.Second)
	for _, tc := range []struct {
		key  string
		want interface{}
	}{
		{key: "groupId", want: groupID},
		{key: "senderId", want: nodeA.PeerId()},
		{key: "senderUsername", want: "Alice"},
		{key: "messageId", want: msgID},
		{key: "text", want: "gp004 generated message body"},
		{key: "keyEpoch", want: float64(keyInfo.KeyEpoch)},
	} {
		if got := received[tc.key]; got != tc.want {
			t.Fatalf("%s = %v, want %v", tc.key, got, tc.want)
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

	nodeACapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
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
	routeDiagnostic := waitForCollectedGroupDiscoveryPeerPrefix(
		t,
		nodeACapture,
		groupId,
		"known_member_dial_success",
		nodeB.PeerId(),
		2*time.Second,
	)
	if routeDiagnostic["path"] != "direct" {
		t.Fatalf("route diagnostic path = %v, want direct", routeDiagnostic["path"])
	}

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

func TestGP009GroupDiscoveryRegistersAndDiscoversAfterRelayReady(t *testing.T) {
	_, senderPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeACapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeB := startLocalNodeForMultiRelayTest(t)

	groupId := "test-gp009-relay-ready-register-discover"
	namespace := groupRendezvousNamespace(groupId)
	nodeA.relayReady = make(chan struct{})
	nodeA.waitForCircuitAddressHook = func(timeout time.Duration) bool { return true }

	sequenceCh := make(chan string, 16)
	recordSequence := func(step string) {
		select {
		case sequenceCh <- step:
		default:
		}
	}
	var relayDialCalls atomic.Int32
	var registerCalls atomic.Int32
	var discoverCalls atomic.Int32
	nodeA.dialPeerViaRelayHook = func(peerIdStr string) error {
		relayDialCalls.Add(1)
		recordSequence("relay_dial:" + peerIdStr)
		if peerIdStr != nodeB.PeerId() {
			return fmt.Errorf("unexpected relay dial target %s", peerIdStr)
		}

		var nodeBAddrs []string
		for _, addr := range nodeB.Host().Addrs() {
			nodeBAddrs = append(nodeBAddrs, addr.String())
		}
		return nodeA.DialPeerWithTimeout(peerIdStr, nodeBAddrs, 1000)
	}
	nodeA.rendezvousRegisterHook = func(namespace string, serverAddresses []string) error {
		registerCalls.Add(1)
		recordSequence("register:" + namespace)
		return nil
	}
	nodeA.rendezvousDiscoverHook = func(namespace string, serverAddresses []string) ([]peer.AddrInfo, error) {
		discoverCalls.Add(1)
		recordSequence("discover:" + namespace)
		return nil, nil
	}

	config := &GroupConfig{
		Name:      "GP009 Relay Ready Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: senderPubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: "peerBPubKey"},
		},
		CreatedBy: nodeA.PeerId(),
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	if err := nodeB.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}
	if err := nodeA.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}

	preRelay := waitForCollectedEventData(t, nodeACapture, "group:discovery", func(data map[string]interface{}) bool {
		return data["groupId"] == groupId && data["step"] == "pre_relay_direct_dial"
	}, 2*time.Second)
	if preRelay["membersDialed"] != float64(0) {
		t.Fatalf("pre-relay direct dial membersDialed=%v, want 0 without seeded direct addrs", preRelay["membersDialed"])
	}
	if preRelay["noDirectAddr"] != float64(1) {
		t.Fatalf("pre-relay direct dial noDirectAddr=%v, want 1", preRelay["noDirectAddr"])
	}
	if got := relayDialCalls.Load(); got != 0 {
		t.Fatalf("relay-assisted dial ran before relayReady closed: %d calls", got)
	}
	if got := registerCalls.Load(); got != 0 {
		t.Fatalf("rendezvous register ran before relayReady closed: %d calls", got)
	}
	if got := discoverCalls.Load(); got != 0 {
		t.Fatalf("rendezvous discover ran before relayReady closed: %d calls", got)
	}
	if got := len(sequenceCh); got != 0 {
		t.Fatalf("post-relay sequence started before relayReady closed: buffered=%d", got)
	}

	close(nodeA.relayReady)

	nodeBShort := nodeB.PeerId()
	if len(nodeBShort) > 16 {
		nodeBShort = nodeBShort[:16]
	}
	waitForCollectedEventData(t, nodeACapture, "group:discovery", func(data map[string]interface{}) bool {
		return data["groupId"] == groupId &&
			data["step"] == "known_member_dial_success" &&
			data["peerId"] == nodeBShort &&
			data["path"] == "relay"
	}, 5*time.Second)
	waitForCollectedEventData(t, nodeACapture, "group:discovery", func(data map[string]interface{}) bool {
		return data["groupId"] == groupId && data["step"] == "registered"
	}, 8*time.Second)
	waitForCollectedEventData(t, nodeACapture, "group:discovery", func(data map[string]interface{}) bool {
		return data["groupId"] == groupId && data["step"] == "discover_result"
	}, 8*time.Second)

	sequence := make([]string, 0, 8)
	registered := false
	deadline := time.After(8 * time.Second)
	for {
		select {
		case step := <-sequenceCh:
			sequence = append(sequence, step)
			if step == "register:"+namespace {
				registered = true
			}
			if registered && step == "discover:"+namespace {
				return
			}
		case <-deadline:
			t.Fatalf("timed out waiting for register then discover after relayReady; sequence=%v", sequence)
		}
	}
}

func TestGR014GroupDiscoveryResumesAfterRelayReadyClosesLate(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeACapture := &testEventCollector{}
	nodeBCapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

	nodeA.relayReady = make(chan struct{})
	nodeA.waitForCircuitAddressHook = func(timeout time.Duration) bool { return true }

	var relayDialCalls atomic.Int32
	var registerCalls atomic.Int32
	var discoverCalls atomic.Int32
	nodeA.dialPeerViaRelayHook = func(peerIdStr string) error {
		relayDialCalls.Add(1)
		if peerIdStr != nodeB.PeerId() {
			return fmt.Errorf("unexpected relay dial target %s", peerIdStr)
		}

		var nodeBAddrs []string
		for _, addr := range nodeB.Host().Addrs() {
			nodeBAddrs = append(nodeBAddrs, addr.String())
		}
		return nodeA.DialPeerWithTimeout(peerIdStr, nodeBAddrs, 1000)
	}
	nodeA.rendezvousRegisterHook = func(namespace string, serverAddresses []string) error {
		registerCalls.Add(1)
		return nil
	}
	nodeA.rendezvousDiscoverHook = func(namespace string, serverAddresses []string) ([]peer.AddrInfo, error) {
		discoverCalls.Add(1)
		return nil, nil
	}

	groupId := "test-gr014-late-relay-ready"
	config := &GroupConfig{
		Name:      "GR014 Late Relay Ready Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: senderPubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: "peerBPubKey"},
		},
		CreatedBy: nodeA.PeerId(),
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	if err := nodeB.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}
	if err := nodeA.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}

	time.Sleep(150 * time.Millisecond)
	if got := relayDialCalls.Load(); got != 0 {
		t.Fatalf("relay-assisted discovery dial ran before relayReady closed: %d calls", got)
	}
	if got := registerCalls.Load(); got != 0 {
		t.Fatalf("rendezvous registration ran before relayReady closed: %d calls", got)
	}
	if got := discoverCalls.Load(); got != 0 {
		t.Fatalf("rendezvous discovery ran before relayReady closed: %d calls", got)
	}

	nodeA.relayReadyOnce.Do(func() { close(nodeA.relayReady) })

	nodeBShort := nodeB.PeerId()
	if len(nodeBShort) > 16 {
		nodeBShort = nodeBShort[:16]
	}
	dialSuccess := waitForCollectedEventData(t, nodeACapture, "group:discovery", func(data map[string]interface{}) bool {
		return data["groupId"] == groupId &&
			data["step"] == "known_member_dial_success" &&
			data["peerId"] == nodeBShort &&
			data["path"] == "relay"
	}, 5*time.Second)
	if dialSuccess["attemptedDirect"] != false {
		t.Fatalf("GR-014 relay-ready recovery should not use preseeded direct addrs, got attemptedDirect=%v", dialSuccess["attemptedDirect"])
	}
	if got := relayDialCalls.Load(); got == 0 {
		t.Fatal("relay-assisted discovery dial did not run after relayReady closed")
	}
	if got := discoverCalls.Load(); got == 0 {
		t.Fatal("rendezvous discovery did not resume after relayReady closed")
	}

	messageID := "gr014-late-relay-ready-message"
	msgID, peerCount, err := nodeA.PublishGroupMessage(
		groupId,
		senderPrivB64,
		nodeA.PeerId(),
		senderPubB64,
		"Alice",
		"late relay readiness should restore live group delivery",
		messageID,
		nil,
	)
	if err != nil {
		t.Fatalf("PublishGroupMessage after late relayReady: %v", err)
	}
	if msgID != messageID {
		t.Fatalf("PublishGroupMessage msgID=%q, want %q", msgID, messageID)
	}
	if peerCount < 1 {
		t.Fatalf("expected at least one live topic peer after late relayReady, got %d", peerCount)
	}

	received := waitForCollectedEventData(t, nodeBCapture, "group_message:received", func(data map[string]interface{}) bool {
		return data["messageId"] == messageID
	}, 5*time.Second)
	if got := received["text"]; got != "late relay readiness should restore live group delivery" {
		t.Fatalf("received text = %v, want GR-014 payload", got)
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

func TestGP016DialCooldownBacksOffThenClearsOnRecoveredDelivery(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeACapture := &testEventCollector{}
	nodeBCapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)
	nodeA.relayReady = make(chan struct{})
	nodeB.relayReady = make(chan struct{})

	groupId := "test-gp016-dial-cooldown-recovers"
	config := &GroupConfig{
		Name:      "GP016 Cooldown Recovery Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: senderPubB64},
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

	nodeBShort := nodeB.PeerId()
	if len(nodeBShort) > 16 {
		nodeBShort = nodeBShort[:16]
	}

	waitDiscoveryAfter := func(baseline int, step string) map[string]interface{} {
		t.Helper()

		deadline := time.Now().Add(5 * time.Second)
		for time.Now().Before(deadline) {
			events := nodeACapture.snapshot()
			for _, raw := range events[baseline:] {
				var payload map[string]interface{}
				if err := json.Unmarshal([]byte(raw), &payload); err != nil {
					continue
				}
				if payload["event"] != "group:discovery" {
					continue
				}
				data, _ := payload["data"].(map[string]interface{})
				if data["groupId"] == groupId && data["step"] == step && data["peerId"] == nodeBShort {
					return data
				}
			}
			time.Sleep(25 * time.Millisecond)
		}

		events := nodeACapture.snapshot()
		t.Fatalf(
			"timed out waiting for GP-016 discovery step %q after baseline %d; events=%s",
			step,
			baseline,
			strings.Join(events[baseline:], "\n"),
		)
		return nil
	}

	requireBackoffState := func(label string) groupPeerDialState {
		t.Helper()

		nodeA.mu.RLock()
		state, ok := nodeA.groupDialBackoff[nodeB.PeerId()]
		nodeA.mu.RUnlock()
		if !ok {
			t.Fatalf("%s: expected cooldown state for node B", label)
		}
		if state.inFlight {
			t.Fatalf("%s: cooldown state still in flight: %#v", label, state)
		}
		return state
	}

	expireBackoff := func() {
		t.Helper()

		nodeA.mu.Lock()
		state := nodeA.groupDialBackoff[nodeB.PeerId()]
		state.nextAllowed = time.Now().Add(-time.Millisecond)
		state.inFlight = false
		nodeA.groupDialBackoff[nodeB.PeerId()] = state
		nodeA.mu.Unlock()
	}

	baseline := len(nodeACapture.snapshot())
	nodeA.dialKnownGroupMembers(groupId, false)
	waitDiscoveryAfter(baseline, "known_member_dial_failed")
	firstFailure := requireBackoffState("first failure")
	if firstFailure.failureCount != 1 {
		t.Fatalf("first failure count = %d, want 1", firstFailure.failureCount)
	}
	if firstCooldown := groupPeerDialBackoff(firstFailure.failureCount); firstCooldown <= 0 {
		t.Fatalf("first cooldown = %v, want positive", firstCooldown)
	}

	baseline = len(nodeACapture.snapshot())
	nodeA.dialKnownGroupMembers(groupId, false)
	skipData := waitDiscoveryAfter(baseline, "direct_dial_skipped_cooldown")
	if retryIn, _ := skipData["retryIn"].(string); retryIn == "" {
		t.Fatalf("cooldown skip event missing retryIn: %#v", skipData)
	}
	skippedFailure := requireBackoffState("cooldown skip")
	if skippedFailure.failureCount != firstFailure.failureCount {
		t.Fatalf("cooldown skip failure count = %d, want unchanged %d", skippedFailure.failureCount, firstFailure.failureCount)
	}

	expireBackoff()
	baseline = len(nodeACapture.snapshot())
	nodeA.dialKnownGroupMembers(groupId, false)
	waitDiscoveryAfter(baseline, "known_member_dial_failed")
	secondFailure := requireBackoffState("second failure")
	if secondFailure.failureCount != 2 {
		t.Fatalf("second failure count = %d, want 2", secondFailure.failureCount)
	}

	expireBackoff()
	baseline = len(nodeACapture.snapshot())
	nodeA.dialKnownGroupMembers(groupId, false)
	waitDiscoveryAfter(baseline, "known_member_dial_failed")
	thirdFailure := requireBackoffState("third failure")
	if thirdFailure.failureCount != 3 {
		t.Fatalf("third failure count = %d, want 3", thirdFailure.failureCount)
	}
	if got, previous := groupPeerDialBackoff(thirdFailure.failureCount), groupPeerDialBackoff(secondFailure.failureCount); got <= previous {
		t.Fatalf("third cooldown = %v, want greater than second cooldown %v", got, previous)
	}

	nodeBID, err := peer.Decode(nodeB.PeerId())
	if err != nil {
		t.Fatalf("decode node B peer ID: %v", err)
	}
	nodeA.Host().Peerstore().AddAddrs(nodeBID, nodeB.Host().Addrs(), time.Hour)

	expireBackoff()
	baseline = len(nodeACapture.snapshot())
	nodeA.dialKnownGroupMembers(groupId, false)
	successData := waitDiscoveryAfter(baseline, "known_member_dial_success")
	if path, _ := successData["path"].(string); path != "direct" {
		t.Fatalf("recovery path = %v, want direct in event data %#v", successData["path"], successData)
	}
	if directAddrs, _ := successData["directAddrCount"].(float64); directAddrs <= 0 {
		t.Fatalf("recovery directAddrCount = %v, want positive in event data %#v", successData["directAddrCount"], successData)
	}
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 2*time.Second)

	nodeA.mu.RLock()
	_, stillBackedOff := nodeA.groupDialBackoff[nodeB.PeerId()]
	nodeA.mu.RUnlock()
	if stillBackedOff {
		t.Fatal("successful recovery should clear node B cooldown state")
	}

	messageID := "gp016-cooldown-recovery"
	_, peerCount, err := nodeA.PublishGroupMessage(
		groupId,
		senderPrivB64,
		nodeA.PeerId(),
		senderPubB64,
		"Alice",
		"cooldown should not permanently starve delivery",
		messageID,
		nil,
	)
	if err != nil {
		t.Fatalf("PublishGroupMessage after cooldown recovery failed: %v", err)
	}
	if peerCount < 1 {
		t.Fatalf("PublishGroupMessage peerCount = %d, want at least one live topic peer", peerCount)
	}

	received := waitForCollectedEventData(t, nodeBCapture, "group_message:received", func(data map[string]interface{}) bool {
		return data["messageId"] == messageID
	}, 5*time.Second)
	if got := received["text"]; got != "cooldown should not permanently starve delivery" {
		t.Fatalf("received text = %v, want GP-016 message", got)
	}
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

func TestGP001PublishGroupMessageFailsClearlyWhenGroupNotJoined(t *testing.T) {
	privB64, pubB64 := generateEd25519KeyPair(t)
	groupID := "gp001-not-joined"

	n := NewNode()
	_, err := n.Start(NodeConfig{
		PrivateKeyHex:  generateTestKey(t),
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	msgID, peerCount, err := n.PublishGroupMessage(
		groupID,
		privB64,
		n.PeerId(),
		pubB64,
		"Alice",
		"hello",
		"gp001-client-message-id",
		nil,
	)
	if err == nil {
		t.Fatal("expected group not joined error, got nil")
	}
	if !strings.Contains(err.Error(), "group not joined: "+groupID) {
		t.Fatalf("expected clear group not joined error for %q, got %v", groupID, err)
	}
	if msgID != "" {
		t.Fatalf("expected empty message ID on unjoined publish, got %q", msgID)
	}
	if peerCount != 0 {
		t.Fatalf("expected peerCount 0 on unjoined publish, got %d", peerCount)
	}

	n.mu.RLock()
	_, topicOK := n.groupTopics[groupID]
	_, configOK := n.groupConfigs[groupID]
	_, keyOK := n.groupKeys[groupID]
	_, subOK := n.groupSubs[groupID]
	n.mu.RUnlock()
	if topicOK || configOK || keyOK || subOK {
		t.Fatalf(
			"unjoined publish should not create group state: topic=%t config=%t key=%t sub=%t",
			topicOK,
			configOK,
			keyOK,
			subOK,
		)
	}
}

func TestGP002PublishBlocksUnauthorizedWriterBeforeEncryptSignAndPublish(t *testing.T) {
	_, pubB64 := generateEd25519KeyPair(t)

	collector := &testEventCollector{}
	n := startLocalNodeForMultiRelayTestWithCollector(t, collector)

	writerConfig := &GroupConfig{
		Name:      "GP002 Announcement Writer",
		GroupType: GroupTypeAnnouncement,
		Members: []GroupMember{
			{PeerId: n.PeerId(), Role: GroupRoleWriter, PublicKey: pubB64},
		},
		CreatedBy: "gp002-admin",
	}
	adminConfig := &GroupConfig{
		Name:      "GP002 Announcement Admin",
		GroupType: GroupTypeAnnouncement,
		Members: []GroupMember{
			{PeerId: n.PeerId(), Role: GroupRoleAdmin, PublicKey: pubB64},
		},
		CreatedBy: "gp002-admin",
	}

	invalidKeyGroupID := "gp002-invalid-key-sentinel"
	if err := n.JoinGroupTopic(
		invalidKeyGroupID,
		writerConfig,
		&GroupKeyInfo{Key: "not-base64-group-key", KeyEpoch: 1},
	); err != nil {
		t.Fatalf("JoinGroupTopic invalid-key sentinel group: %v", err)
	}

	baseline := len(collector.snapshot())
	msgID, peerCount, err := n.PublishGroupMessage(
		invalidKeyGroupID,
		"not-base64-private-key",
		n.PeerId(),
		pubB64,
		"Writer",
		"gp002 should not encrypt",
		"gp002-invalid-key-message",
		nil,
	)
	if err == nil {
		t.Fatal("expected unauthorized writer error before encryption, got nil")
	}
	if !strings.Contains(err.Error(), "not allowed to write") {
		t.Fatalf("expected not allowed to write error, got %v", err)
	}
	if strings.Contains(err.Error(), "encrypt group message") || strings.Contains(err.Error(), "sign group message") {
		t.Fatalf("unauthorized publish reached encrypt/sign path: %v", err)
	}
	if msgID != "" || peerCount != 0 {
		t.Fatalf("unauthorized publish returned msgID=%q peerCount=%d, want empty/0", msgID, peerCount)
	}
	assertNoCollectedEventContainingAfter(t, collector, baseline, `"event":"group:publish_debug"`, 300*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, collector, baseline, "gp002-invalid-key-message", 300*time.Millisecond)

	n.UpdateGroupConfig(invalidKeyGroupID, adminConfig)
	if _, _, encryptErr := n.PublishGroupMessage(
		invalidKeyGroupID,
		"not-base64-private-key",
		n.PeerId(),
		pubB64,
		"Admin",
		"gp002 authorized invalid key control",
		"gp002-authorized-encrypt-control",
		nil,
	); encryptErr == nil || !strings.Contains(encryptErr.Error(), "encrypt group message") {
		t.Fatalf("authorized invalid-key control error = %v, want encrypt group message", encryptErr)
	}

	validKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("GenerateGroupKey: %v", err)
	}
	invalidSignGroupID := "gp002-invalid-sign-sentinel"
	if err := n.JoinGroupTopic(
		invalidSignGroupID,
		writerConfig,
		&GroupKeyInfo{Key: validKey, KeyEpoch: 1},
	); err != nil {
		t.Fatalf("JoinGroupTopic invalid-sign sentinel group: %v", err)
	}

	baseline = len(collector.snapshot())
	msgID, peerCount, err = n.PublishGroupMessage(
		invalidSignGroupID,
		"not-base64-private-key",
		n.PeerId(),
		pubB64,
		"Writer",
		"gp002 should not sign",
		"gp002-invalid-sign-message",
		nil,
	)
	if err == nil {
		t.Fatal("expected unauthorized writer error before signing, got nil")
	}
	if !strings.Contains(err.Error(), "not allowed to write") {
		t.Fatalf("expected not allowed to write error, got %v", err)
	}
	if strings.Contains(err.Error(), "encrypt group message") || strings.Contains(err.Error(), "sign group message") {
		t.Fatalf("unauthorized publish reached encrypt/sign path: %v", err)
	}
	if msgID != "" || peerCount != 0 {
		t.Fatalf("unauthorized publish returned msgID=%q peerCount=%d, want empty/0", msgID, peerCount)
	}
	assertNoCollectedEventContainingAfter(t, collector, baseline, `"event":"group:publish_debug"`, 300*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, collector, baseline, "gp002-invalid-sign-message", 300*time.Millisecond)

	n.UpdateGroupConfig(invalidSignGroupID, adminConfig)
	if _, _, signErr := n.PublishGroupMessage(
		invalidSignGroupID,
		"not-base64-private-key",
		n.PeerId(),
		pubB64,
		"Admin",
		"gp002 authorized invalid signer control",
		"gp002-authorized-sign-control",
		nil,
	); signErr == nil || !strings.Contains(signErr.Error(), "sign group message") {
		t.Fatalf("authorized invalid-signer control error = %v, want sign group message", signErr)
	}
}
