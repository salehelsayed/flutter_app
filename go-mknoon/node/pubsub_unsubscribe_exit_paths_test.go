package node

import (
	"encoding/base64"
	"strings"
	"testing"
	"time"

	mcrypto "github.com/mknoon/go-mknoon/crypto"
	"github.com/mknoon/go-mknoon/internal"
)

func TestLP003LeaveGroupTopicStopsLiveDeliveryAfterExit(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	exitedPrivB64, exitedPubB64 := generateEd25519KeyPair(t)
	_, remainingPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeA := startLocalNodeForMultiRelayTest(t)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)
	nodeCCapture := &testEventCollector{}
	nodeC := startLocalNodeForMultiRelayTestWithCollector(t, nodeCCapture)

	groupId := "lp003-leave-stops-live-delivery"
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	config := &GroupConfig{
		Name:      "LP003 Exit Proof",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: senderPubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: exitedPubB64},
			{PeerId: nodeC.PeerId(), Role: GroupRoleWriter, PublicKey: remainingPubB64},
		},
		CreatedBy: nodeA.PeerId(),
	}

	for _, n := range []*Node{nodeA, nodeB, nodeC} {
		if err := n.JoinGroupTopic(groupId, config, keyInfo); err != nil {
			t.Fatalf("%s JoinGroupTopic: %v", n.PeerId(), err)
		}
	}

	connectLocalGroupNodes(t, nodeA, nodeB)
	connectLocalGroupNodes(t, nodeA, nodeC)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 2, 3*time.Second)

	preExitMessageId := "lp003-pre-exit-normal"
	if msgID, peerCount, err := nodeA.PublishGroupMessage(
		groupId,
		senderPrivB64,
		nodeA.PeerId(),
		senderPubB64,
		"Alice",
		"LP003 pre-exit message",
		preExitMessageId,
		nil,
	); err != nil {
		t.Fatalf("pre-exit PublishGroupMessage: %v", err)
	} else if msgID != preExitMessageId || peerCount < 2 {
		t.Fatalf("pre-exit publish result msgID=%q peerCount=%d, want msgID=%q peerCount>=2", msgID, peerCount, preExitMessageId)
	}
	waitForCollectedEventContaining(t, nodeBCapture, preExitMessageId, 5*time.Second)
	waitForCollectedEventContaining(t, nodeCCapture, preExitMessageId, 5*time.Second)

	if err := nodeB.LeaveGroupTopic(groupId); err != nil {
		t.Fatalf("nodeB LeaveGroupTopic: %v", err)
	}
	assertLP003GroupPubSubStateRemoved(t, nodeB, groupId)

	time.Sleep(150 * time.Millisecond)
	nodeBExitedBaseline := len(nodeBCapture.snapshot())

	postExitMessageId := "lp003-post-exit-normal"
	if msgID, _, err := nodeA.PublishGroupMessage(
		groupId,
		senderPrivB64,
		nodeA.PeerId(),
		senderPubB64,
		"Alice",
		"LP003 post-exit normal message",
		postExitMessageId,
		nil,
	); err != nil {
		t.Fatalf("post-exit PublishGroupMessage: %v", err)
	} else if msgID != postExitMessageId {
		t.Fatalf("post-exit message ID = %q, want %q", msgID, postExitMessageId)
	}
	waitForCollectedEventCount(t, nodeCCapture, "group_message:received", 2, 5*time.Second)
	waitForCollectedEventContaining(t, nodeCCapture, postExitMessageId, 5*time.Second)

	reactionJSON := `{"messageId":"` + postExitMessageId + `","action":"add","emoji":"+1","sentinel":"lp003-post-exit-reaction"}`
	if err := nodeA.PublishGroupReaction(groupId, senderPrivB64, nodeA.PeerId(), senderPubB64, reactionJSON); err != nil {
		t.Fatalf("post-exit PublishGroupReaction: %v", err)
	}
	waitForCollectedEventCount(t, nodeCCapture, "group_reaction:received", 1, 5*time.Second)
	waitForCollectedEventContaining(t, nodeCCapture, "lp003-post-exit-reaction", 5*time.Second)

	parseFailureEnvelope := buildTestEnvelopeWithPlaintext(
		t,
		groupId,
		"group_message",
		nodeA.PeerId(),
		senderPrivB64,
		senderPubB64,
		groupKey,
		keyInfo.KeyEpoch,
		"not-json",
	)
	publishRawGroupEnvelope(t, nodeA, groupId, parseFailureEnvelope)
	waitForCollectedEventCount(t, nodeCCapture, "group:payload_parse_failed", 1, 5*time.Second)

	validEnvelope := buildTestEnvelope(
		t,
		groupId,
		nodeA.PeerId(),
		senderPrivB64,
		senderPubB64,
		groupKey,
		keyInfo.KeyEpoch,
		"LP003 decrypt failure seed",
	)
	decryptFailureEnvelope := mutateAndResignGroupEnvelope(t, validEnvelope, senderPrivB64, func(env *internal.GroupEnvelope) {
		ciphertextBytes, err := base64.StdEncoding.DecodeString(env.Encrypted.Ciphertext)
		if err != nil {
			t.Fatalf("decode ciphertext: %v", err)
		}
		ciphertextBytes[0] ^= 0xFF
		env.Encrypted.Ciphertext = base64.StdEncoding.EncodeToString(ciphertextBytes)
	})
	publishRawGroupEnvelope(t, nodeA, groupId, decryptFailureEnvelope)
	waitForCollectedEventCount(t, nodeCCapture, "group:decryption_failed", 1, 5*time.Second)

	assertLP003NoExitedGroupEventsAfter(t, nodeBCapture, nodeBExitedBaseline, 900*time.Millisecond)

	if _, _, err := nodeB.PublishGroupMessage(
		groupId,
		exitedPrivB64,
		nodeB.PeerId(),
		exitedPubB64,
		"Bob",
		"LP003 exited peer should not publish",
		"",
		nil,
	); err == nil || !strings.Contains(err.Error(), "group not joined") {
		t.Fatalf("exited PublishGroupMessage error = %v, want group not joined", err)
	}
	if err := nodeB.PublishGroupReaction(
		groupId,
		exitedPrivB64,
		nodeB.PeerId(),
		exitedPubB64,
		`{"messageId":"lp003-post-exit-normal","action":"add","emoji":"+1"}`,
	); err == nil || !strings.Contains(err.Error(), "group not joined") {
		t.Fatalf("exited PublishGroupReaction error = %v, want group not joined", err)
	}
}

func assertLP003GroupPubSubStateRemoved(t *testing.T, n *Node, groupId string) {
	t.Helper()

	n.mu.RLock()
	_, hasTopic := n.groupTopics[groupId]
	_, hasSub := n.groupSubs[groupId]
	_, hasSubCtx := n.groupSubCtx[groupId]
	_, hasDiscoveryCtx := n.groupDiscoveryCtx[groupId]
	_, hasConfig := n.groupConfigs[groupId]
	_, hasKey := n.groupKeys[groupId]
	n.mu.RUnlock()

	if hasTopic || hasSub || hasSubCtx || hasDiscoveryCtx || hasConfig || hasKey {
		t.Fatalf(
			"leave should remove all pubsub state, got topic=%t sub=%t subCtx=%t discoveryCtx=%t config=%t key=%t",
			hasTopic,
			hasSub,
			hasSubCtx,
			hasDiscoveryCtx,
			hasConfig,
			hasKey,
		)
	}
}

func assertLP003NoExitedGroupEventsAfter(t *testing.T, collector *testEventCollector, baseline int, timeout time.Duration) {
	t.Helper()

	disallowed := []string{
		`"event":"group_message:received"`,
		`"event":"group_reaction:received"`,
		`"event":"group:payload_parse_failed"`,
		`"event":"group:decryption_failed"`,
	}
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		events := collector.snapshot()
		for _, raw := range events[baseline:] {
			for _, marker := range disallowed {
				if strings.Contains(raw, marker) {
					t.Fatalf("exited peer received disallowed post-exit event %s after baseline %d: %s", marker, baseline, raw)
				}
			}
		}
		time.Sleep(25 * time.Millisecond)
	}
}
