package node

import (
	"context"
	"encoding/json"
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

func mutateGroupEnvelope(t *testing.T, envelopeJSON string, mutate func(*internal.GroupEnvelope)) string {
	t.Helper()

	envelope, err := internal.ParseGroupEnvelope(envelopeJSON)
	if err != nil {
		t.Fatalf("parse envelope: %v", err)
	}

	mutate(envelope)

	mutated, err := internal.MarshalGroupEnvelope(envelope)
	if err != nil {
		t.Fatalf("marshal mutated envelope: %v", err)
	}
	return mutated
}

func mutateAndResignGroupEnvelope(t *testing.T, envelopeJSON string, signerPrivB64 string, mutate func(*internal.GroupEnvelope)) string {
	t.Helper()

	envelope, err := internal.ParseGroupEnvelope(envelopeJSON)
	if err != nil {
		t.Fatalf("parse envelope: %v", err)
	}

	mutate(envelope)

	sigData := mcrypto.BuildGroupSignatureData(
		envelope.GroupId,
		envelope.KeyEpoch,
		envelope.Encrypted.Ciphertext,
	)
	signature, err := mcrypto.SignPayload(signerPrivB64, sigData)
	if err != nil {
		t.Fatalf("sign mutated envelope: %v", err)
	}
	envelope.Signature = signature

	mutated, err := internal.MarshalGroupEnvelope(envelope)
	if err != nil {
		t.Fatalf("marshal mutated envelope: %v", err)
	}
	return mutated
}

func buildGroupKeyInfoWithGrace(currentKey string, currentEpoch int, prevKey string, prevEpoch int, graceDeadline time.Time) *GroupKeyInfo {
	return &GroupKeyInfo{
		Key:           currentKey,
		KeyEpoch:      currentEpoch,
		PrevKey:       prevKey,
		PrevKeyEpoch:  prevEpoch,
		GraceDeadline: graceDeadline,
	}
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

func connectLocalGroupNodes(t *testing.T, dialer, target *Node) {
	t.Helper()

	targetAddrs := target.Host().Addrs()
	addrStrs := make([]string, len(targetAddrs))
	for i, addr := range targetAddrs {
		addrStrs[i] = addr.String()
	}
	if err := dialer.DialPeer(target.PeerId(), addrStrs); err != nil {
		t.Fatalf("DialPeer %s->%s: %v", dialer.PeerId(), target.PeerId(), err)
	}

	time.Sleep(500 * time.Millisecond)
}

func TestMutateGroupEnvelope_RewritesEncryptedFieldsWithoutChangingRoutingMetadata(t *testing.T) {
	privB64, pubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	original := buildTestEnvelope(
		t,
		"group-mutate-envelope",
		"peer-sender",
		privB64,
		pubB64,
		groupKey,
		3,
		"original payload",
	)
	mutated := mutateGroupEnvelope(t, original, func(env *internal.GroupEnvelope) {
		env.Encrypted.Ciphertext = "tampered-ciphertext"
		env.Encrypted.Nonce = "tampered-nonce"
	})

	originalEnv, err := internal.ParseGroupEnvelope(original)
	if err != nil {
		t.Fatalf("parse original envelope: %v", err)
	}
	mutatedEnv, err := internal.ParseGroupEnvelope(mutated)
	if err != nil {
		t.Fatalf("parse mutated envelope: %v", err)
	}

	if mutatedEnv.GroupId != originalEnv.GroupId {
		t.Fatalf("groupId = %q, want %q", mutatedEnv.GroupId, originalEnv.GroupId)
	}
	if mutatedEnv.SenderId != originalEnv.SenderId {
		t.Fatalf("senderId = %q, want %q", mutatedEnv.SenderId, originalEnv.SenderId)
	}
	if mutatedEnv.KeyEpoch != originalEnv.KeyEpoch {
		t.Fatalf("keyEpoch = %d, want %d", mutatedEnv.KeyEpoch, originalEnv.KeyEpoch)
	}
	if mutatedEnv.Encrypted.Ciphertext != "tampered-ciphertext" {
		t.Fatalf("ciphertext = %q, want tampered-ciphertext", mutatedEnv.Encrypted.Ciphertext)
	}
	if mutatedEnv.Encrypted.Nonce != "tampered-nonce" {
		t.Fatalf("nonce = %q, want tampered-nonce", mutatedEnv.Encrypted.Nonce)
	}
}
