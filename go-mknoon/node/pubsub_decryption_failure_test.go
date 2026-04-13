package node

import (
	"encoding/base64"
	"strings"
	"testing"
	"time"

	mcrypto "github.com/mknoon/go-mknoon/crypto"
	"github.com/mknoon/go-mknoon/internal"
)

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

	connectLocalGroupNodes(t, nodeA, nodeB)

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

	connectLocalGroupNodes(t, nodeA, nodeB)

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

func TestHandleGroupSubscription_EmitsDecryptionFailedEventForTamperedNonce(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeA := startLocalNodeForMultiRelayTest(t)
	nodeB := startLocalNodeForMultiRelayTest(t)

	groupId := "group-decrypt-failure-bad-nonce"
	senderPeerId := nodeA.PeerId()
	config := &GroupConfig{
		Name:      "Bad Nonce Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderPeerId, Role: GroupRoleAdmin, PublicKey: senderPubB64},
		},
		CreatedBy: senderPeerId,
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 9}

	if err := nodeA.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}

	nodeBCapture := &testEventCollector{}
	nodeB.eventCallback = nodeBCapture

	connectLocalGroupNodes(t, nodeA, nodeB)

	validEnvelope := buildTestEnvelope(
		t,
		groupId,
		senderPeerId,
		senderPrivB64,
		senderPubB64,
		groupKey,
		keyInfo.KeyEpoch,
		"hello over a tampered nonce",
	)
	tamperedEnvelope := mutateGroupEnvelope(t, validEnvelope, func(env *internal.GroupEnvelope) {
		env.Encrypted.Nonce = "tampered-nonce"
	})
	publishRawGroupEnvelope(t, nodeA, groupId, tamperedEnvelope)

	data := waitForCollectedEvent(t, nodeBCapture, "group:decryption_failed", 5*time.Second)

	if got := data["groupId"]; got != groupId {
		t.Fatalf("groupId = %v, want %q", got, groupId)
	}
	if got := data["senderId"]; got != senderPeerId {
		t.Fatalf("senderId = %v, want %q", got, senderPeerId)
	}
	if got := int(data["keyEpoch"].(float64)); got != keyInfo.KeyEpoch {
		t.Fatalf("keyEpoch = %d, want %d", got, keyInfo.KeyEpoch)
	}
	if got := int(data["localKeyEpoch"].(float64)); got != keyInfo.KeyEpoch {
		t.Fatalf("localKeyEpoch = %d, want %d", got, keyInfo.KeyEpoch)
	}
	if got := data["error"]; got == "" {
		t.Fatal("expected non-empty error field")
	}

	events := nodeBCapture.snapshot()
	for _, raw := range events {
		if strings.Contains(raw, `"event":"group_message:received"`) {
			t.Fatal("group_message:received should not be emitted after tampered nonce decryption failure")
		}
	}
}

func TestHandleGroupSubscription_EmitsDecryptionFailedEventForTamperedCiphertext(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeA := startLocalNodeForMultiRelayTest(t)
	nodeB := startLocalNodeForMultiRelayTest(t)

	groupId := "group-decrypt-failure-bad-ciphertext"
	senderPeerId := nodeA.PeerId()
	config := &GroupConfig{
		Name:      "Bad Ciphertext Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderPeerId, Role: GroupRoleAdmin, PublicKey: senderPubB64},
		},
		CreatedBy: senderPeerId,
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 10}

	if err := nodeA.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}

	nodeBCapture := &testEventCollector{}
	nodeB.eventCallback = nodeBCapture

	connectLocalGroupNodes(t, nodeA, nodeB)

	validEnvelope := buildTestEnvelope(
		t,
		groupId,
		senderPeerId,
		senderPrivB64,
		senderPubB64,
		groupKey,
		keyInfo.KeyEpoch,
		"hello over tampered ciphertext",
	)
	tamperedEnvelope := mutateAndResignGroupEnvelope(t, validEnvelope, senderPrivB64, func(env *internal.GroupEnvelope) {
		ciphertextBytes, err := base64.StdEncoding.DecodeString(env.Encrypted.Ciphertext)
		if err != nil {
			t.Fatalf("decode ciphertext: %v", err)
		}
		ciphertextBytes[0] ^= 0xFF
		env.Encrypted.Ciphertext = base64.StdEncoding.EncodeToString(ciphertextBytes)
	})
	publishRawGroupEnvelope(t, nodeA, groupId, tamperedEnvelope)

	data := waitForCollectedEvent(t, nodeBCapture, "group:decryption_failed", 5*time.Second)

	if got := data["groupId"]; got != groupId {
		t.Fatalf("groupId = %v, want %q", got, groupId)
	}
	if got := data["senderId"]; got != senderPeerId {
		t.Fatalf("senderId = %v, want %q", got, senderPeerId)
	}
	if got := int(data["keyEpoch"].(float64)); got != keyInfo.KeyEpoch {
		t.Fatalf("keyEpoch = %d, want %d", got, keyInfo.KeyEpoch)
	}
	if got := int(data["localKeyEpoch"].(float64)); got != keyInfo.KeyEpoch {
		t.Fatalf("localKeyEpoch = %d, want %d", got, keyInfo.KeyEpoch)
	}
	if got := data["error"]; got == "" {
		t.Fatal("expected non-empty error field")
	}

	events := nodeBCapture.snapshot()
	for _, raw := range events {
		if strings.Contains(raw, `"event":"group_message:received"`) {
			t.Fatal("group_message:received should not be emitted after tampered ciphertext decryption failure")
		}
	}
}
