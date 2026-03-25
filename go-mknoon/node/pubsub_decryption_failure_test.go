package node

import (
	"context"
	"encoding/json"
	"strings"
	"testing"
	"time"

	mcrypto "github.com/mknoon/go-mknoon/crypto"
	"github.com/mknoon/go-mknoon/internal"
)

func waitForCollectedEvent(t *testing.T, collector *testEventCollector, eventName string, timeout time.Duration) map[string]interface{} {
	t.Helper()

	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		for _, raw := range collector.snapshot() {
			var ev map[string]interface{}
			if err := json.Unmarshal([]byte(raw), &ev); err != nil {
				continue
			}
			if evName, _ := ev["event"].(string); evName == eventName {
				data, _ := ev["data"].(map[string]interface{})
				return data
			}
		}
		time.Sleep(25 * time.Millisecond)
	}

	t.Fatalf("timed out waiting for event %q", eventName)
	return nil
}

func buildGroupEnvelopeWithPlaintext(t *testing.T, groupId, senderId, privB64, pubB64, groupKey string, keyEpoch int, plaintext string) string {
	t.Helper()

	ctB64, nonceB64, err := mcrypto.EncryptGroupMessage(groupKey, plaintext)
	if err != nil {
		t.Fatalf("encrypt: %v", err)
	}

	sigData := mcrypto.BuildGroupSignatureData(groupId, keyEpoch, ctB64)
	signature, err := mcrypto.SignPayload(privB64, sigData)
	if err != nil {
		t.Fatalf("sign: %v", err)
	}

	envelope := &internal.GroupEnvelope{
		Version:         "3",
		Type:            "group_message",
		GroupId:         groupId,
		SenderId:        senderId,
		SenderPublicKey: pubB64,
		Signature:       signature,
		KeyEpoch:        keyEpoch,
		Encrypted: internal.GroupEncryptedPayload{
			Ciphertext: ctB64,
			Nonce:      nonceB64,
		},
	}

	envelopeJSON, err := internal.MarshalGroupEnvelope(envelope)
	if err != nil {
		t.Fatalf("marshal envelope: %v", err)
	}
	return envelopeJSON
}

func publishRawGroupEnvelope(t *testing.T, n *Node, groupId, envelopeJSON string) {
	t.Helper()

	topic := n.groupTopics[groupId]
	if topic == nil {
		t.Fatalf("missing topic for group %q", groupId)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := topic.Publish(ctx, []byte(envelopeJSON)); err != nil {
		t.Fatalf("topic publish: %v", err)
	}
}

func TestHandleGroupSubscription_EmitsDecryptionFailedEvent(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	actualGroupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}
	wrongGroupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate wrong group key: %v", err)
	}

	nodeA := startLocalNodeForMultiRelayTest(t)
	nodeB := startLocalNodeForMultiRelayTest(t)

	groupId := "group-decrypt-failure"
	senderPeerId := nodeA.PeerId()
	config := &GroupConfig{
		Name:      "Decrypt Failure Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderPeerId, Role: GroupRoleAdmin, PublicKey: senderPubB64},
		},
		CreatedBy: senderPeerId,
	}
	keyInfoA := &GroupKeyInfo{Key: actualGroupKey, KeyEpoch: 7}
	keyInfoB := &GroupKeyInfo{Key: wrongGroupKey, KeyEpoch: 7}

	if err := nodeA.JoinGroupTopic(groupId, config, keyInfoA); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, config, keyInfoB); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}

	nodeBCapture := &testEventCollector{}
	nodeB.eventCallback = nodeBCapture

	bAddrs := nodeB.Host().Addrs()
	addrStrs := make([]string, len(bAddrs))
	for i, a := range bAddrs {
		addrStrs[i] = a.String()
	}
	if err := nodeA.DialPeer(nodeB.PeerId(), addrStrs); err != nil {
		t.Fatalf("DialPeer A->B: %v", err)
	}

	time.Sleep(500 * time.Millisecond)

	envelopeJSON := buildTestEnvelope(
		t,
		groupId,
		senderPeerId,
		senderPrivB64,
		senderPubB64,
		actualGroupKey,
		keyInfoA.KeyEpoch,
		"hello over the wrong local key",
	)
	publishRawGroupEnvelope(t, nodeA, groupId, envelopeJSON)

	data := waitForCollectedEvent(t, nodeBCapture, "group:decryption_failed", 5*time.Second)

	if got := data["groupId"]; got != groupId {
		t.Fatalf("groupId = %v, want %q", got, groupId)
	}
	if got := data["senderId"]; got != senderPeerId {
		t.Fatalf("senderId = %v, want %q", got, senderPeerId)
	}
	if got := int(data["keyEpoch"].(float64)); got != keyInfoA.KeyEpoch {
		t.Fatalf("keyEpoch = %d, want %d", got, keyInfoA.KeyEpoch)
	}
	if got := int(data["localKeyEpoch"].(float64)); got != keyInfoB.KeyEpoch {
		t.Fatalf("localKeyEpoch = %d, want %d", got, keyInfoB.KeyEpoch)
	}
	if got := data["error"]; got == "" {
		t.Fatal("expected non-empty error field")
	}

	events := nodeBCapture.snapshot()
	for _, raw := range events {
		if strings.Contains(raw, `"event":"group_message:received"`) {
			t.Fatal("group_message:received should not be emitted after decryption failure")
		}
	}
}

func TestHandleGroupSubscription_EmitsPayloadParseFailedEvent(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeA := startLocalNodeForMultiRelayTest(t)
	nodeB := startLocalNodeForMultiRelayTest(t)

	groupId := "group-parse-failure"
	senderPeerId := nodeA.PeerId()
	config := &GroupConfig{
		Name:      "Parse Failure Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderPeerId, Role: GroupRoleAdmin, PublicKey: senderPubB64},
		},
		CreatedBy: senderPeerId,
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 11}

	if err := nodeA.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}

	nodeBCapture := &testEventCollector{}
	nodeB.eventCallback = nodeBCapture

	bAddrs := nodeB.Host().Addrs()
	addrStrs := make([]string, len(bAddrs))
	for i, a := range bAddrs {
		addrStrs[i] = a.String()
	}
	if err := nodeA.DialPeer(nodeB.PeerId(), addrStrs); err != nil {
		t.Fatalf("DialPeer A->B: %v", err)
	}

	time.Sleep(500 * time.Millisecond)

	envelopeJSON := buildGroupEnvelopeWithPlaintext(
		t,
		groupId,
		senderPeerId,
		senderPrivB64,
		senderPubB64,
		groupKey,
		keyInfo.KeyEpoch,
		"not-json",
	)
	publishRawGroupEnvelope(t, nodeA, groupId, envelopeJSON)

	data := waitForCollectedEvent(t, nodeBCapture, "group:payload_parse_failed", 5*time.Second)

	if got := data["groupId"]; got != groupId {
		t.Fatalf("groupId = %v, want %q", got, groupId)
	}
	if got := data["senderId"]; got != senderPeerId {
		t.Fatalf("senderId = %v, want %q", got, senderPeerId)
	}
	if got := data["envelopeType"]; got != "group_message" {
		t.Fatalf("envelopeType = %v, want %q", got, "group_message")
	}

	events := nodeBCapture.snapshot()
	for _, raw := range events {
		if strings.Contains(raw, `"event":"group_message:received"`) {
			t.Fatal("group_message:received should not be emitted after payload parse failure")
		}
	}
}
