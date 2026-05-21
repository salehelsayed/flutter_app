package node

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"strings"
	"testing"
	"time"

	mcrypto "github.com/mknoon/go-mknoon/crypto"
	"github.com/mknoon/go-mknoon/internal"
)

func waitForCollectedEventAfter(t *testing.T, collector *testEventCollector, baseline int, eventName string, timeout time.Duration) map[string]interface{} {
	t.Helper()

	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		events := collector.snapshot()
		for _, raw := range events[baseline:] {
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

	events := collector.snapshot()
	t.Fatalf("timed out waiting for event %q after baseline %d; events=%s", eventName, baseline, strings.Join(events[baseline:], "\n"))
	return nil
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
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

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

func TestGP022ReceivePathEmitsDecryptionFailedDiagnosticsForWrongLocalKey(t *testing.T) {
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
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

	groupId := "gp022-wrong-local-key"
	senderPeerId := nodeA.PeerId()
	config := &GroupConfig{
		Name:      "GP022 Wrong Local Key",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderPeerId, Role: GroupRoleAdmin, PublicKey: senderPubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: "receiverPubKey"},
		},
		CreatedBy: senderPeerId,
	}
	keyInfoA := &GroupKeyInfo{Key: actualGroupKey, KeyEpoch: 22}
	keyInfoB := &GroupKeyInfo{Key: wrongGroupKey, KeyEpoch: 22}

	if err := nodeA.JoinGroupTopic(groupId, config, keyInfoA); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, config, keyInfoB); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}
	connectLocalGroupNodes(t, nodeA, nodeB)
	waitForGroupTopicPeerCount(t, nodeB, groupId, 1, 3*time.Second)

	plaintextMarker := "gp022 wrong local key plaintext"
	envelopeJSON := buildTestEnvelope(
		t,
		groupId,
		senderPeerId,
		senderPrivB64,
		senderPubB64,
		actualGroupKey,
		keyInfoA.KeyEpoch,
		plaintextMarker,
	)

	baseline := len(nodeBCapture.snapshot())
	publishRawGroupEnvelope(t, nodeA, groupId, envelopeJSON)

	data := waitForCollectedEventAfter(t, nodeBCapture, baseline, "group:decryption_failed", 5*time.Second)
	for _, tc := range []struct {
		key  string
		want interface{}
	}{
		{"groupId", groupId},
		{"senderId", senderPeerId},
		{"keyEpoch", float64(keyInfoA.KeyEpoch)},
		{"localKeyEpoch", float64(keyInfoB.KeyEpoch)},
	} {
		if got := data[tc.key]; got != tc.want {
			t.Fatalf("%s = %#v, want %#v in event %#v", tc.key, got, tc.want, data)
		}
	}
	gotErr, _ := data["error"].(string)
	if !strings.Contains(gotErr, "aes-gcm decrypt") {
		t.Fatalf("error = %q, want aes-gcm decrypt diagnostic", gotErr)
	}
	decryptMs, ok := data["decryptMs"].(float64)
	if !ok {
		t.Fatalf("decryptMs = %#v (%T), want numeric field in event %#v", data["decryptMs"], data["decryptMs"], data)
	}
	if decryptMs < 0 {
		t.Fatalf("decryptMs = %v, want non-negative", decryptMs)
	}

	assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, `"event":"group_message:received"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, `"event":"group_reaction:received"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, plaintextMarker, 500*time.Millisecond)
}

func TestGO004DecryptionFailureDiagnosticContainsRepairMetadataOnly(t *testing.T) {
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
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

	groupId := "go004-wrong-local-key"
	senderPeerId := nodeA.PeerId()
	config := &GroupConfig{
		Name:      "GO004 Wrong Local Key",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderPeerId, Role: GroupRoleAdmin, PublicKey: senderPubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: "receiverPubKey"},
		},
		CreatedBy: senderPeerId,
	}
	keyInfoA := &GroupKeyInfo{Key: actualGroupKey, KeyEpoch: 4}
	keyInfoB := &GroupKeyInfo{Key: wrongGroupKey, KeyEpoch: 4}

	if err := nodeA.JoinGroupTopic(groupId, config, keyInfoA); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, config, keyInfoB); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}
	connectLocalGroupNodes(t, nodeA, nodeB)
	waitForGroupTopicPeerCount(t, nodeB, groupId, 1, 3*time.Second)

	plaintextMarker := "GO-004 plaintext must not leak"
	envelopeJSON := buildTestEnvelope(
		t,
		groupId,
		senderPeerId,
		senderPrivB64,
		senderPubB64,
		actualGroupKey,
		keyInfoA.KeyEpoch,
		plaintextMarker,
	)
	var env internal.GroupEnvelope
	if err := json.Unmarshal([]byte(envelopeJSON), &env); err != nil {
		t.Fatalf("unmarshal test envelope: %v", err)
	}

	baseline := len(nodeBCapture.snapshot())
	publishRawGroupEnvelope(t, nodeA, groupId, envelopeJSON)

	data := waitForCollectedEventAfter(t, nodeBCapture, baseline, "group:decryption_failed", 5*time.Second)
	for _, tc := range []struct {
		key  string
		want interface{}
	}{
		{"groupId", groupId},
		{"senderId", senderPeerId},
		{"keyEpoch", float64(keyInfoA.KeyEpoch)},
		{"localKeyEpoch", float64(keyInfoB.KeyEpoch)},
	} {
		if got := data[tc.key]; got != tc.want {
			t.Fatalf("%s = %#v, want %#v in event %#v", tc.key, got, tc.want, data)
		}
	}
	gotErr, _ := data["error"].(string)
	if !strings.Contains(gotErr, "aes-gcm decrypt") {
		t.Fatalf("error = %q, want aes-gcm decrypt diagnostic", gotErr)
	}
	decryptMs, ok := data["decryptMs"].(float64)
	if !ok {
		t.Fatalf("decryptMs = %#v (%T), want numeric field in event %#v", data["decryptMs"], data["decryptMs"], data)
	}
	if decryptMs < 0 {
		t.Fatalf("decryptMs = %v, want non-negative", decryptMs)
	}

	rawEvents := strings.Join(nodeBCapture.snapshot()[baseline:], "\n")
	for _, secret := range []string{
		plaintextMarker,
		actualGroupKey,
		wrongGroupKey,
		env.Encrypted.Ciphertext,
		env.Encrypted.Nonce,
		env.Signature,
		senderPrivB64,
	} {
		if secret != "" && strings.Contains(rawEvents, secret) {
			t.Fatalf("decryption diagnostic leaked sensitive value %q in events: %s", secret, rawEvents)
		}
	}

	assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, `"event":"group_message:received"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, `"event":"group_reaction:received"`, 500*time.Millisecond)
}

func TestGO008FailureDiagnosticsDoNotLeakSensitiveLogsOrEvents(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	actualGroupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}
	wrongGroupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate wrong group key: %v", err)
	}

	var logBuffer bytes.Buffer
	originalOutput := log.Writer()
	originalFlags := log.Flags()
	log.SetOutput(&logBuffer)
	log.SetFlags(0)
	defer func() {
		log.SetOutput(originalOutput)
		log.SetFlags(originalFlags)
	}()

	nodeA := startLocalNodeForMultiRelayTest(t)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

	groupId := "go008-log-privacy"
	senderPeerId := nodeA.PeerId()
	config := &GroupConfig{
		Name:      "GO008 Log Privacy",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderPeerId, Role: GroupRoleAdmin, PublicKey: senderPubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: "receiverPubKey"},
		},
		CreatedBy: senderPeerId,
	}
	keyInfoA := &GroupKeyInfo{Key: actualGroupKey, KeyEpoch: 8}
	keyInfoBWrong := &GroupKeyInfo{Key: wrongGroupKey, KeyEpoch: 8}
	if err := nodeA.JoinGroupTopic(groupId, config, keyInfoA); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, config, keyInfoBWrong); err != nil {
		t.Fatalf("nodeB JoinGroupTopic wrong key: %v", err)
	}
	connectLocalGroupNodes(t, nodeA, nodeB)
	waitForGroupTopicPeerCount(t, nodeB, groupId, 1, 3*time.Second)

	decryptPlaintext := "GO-008 decryption plaintext must not leak"
	decryptEnvelopeJSON := buildTestEnvelope(
		t,
		groupId,
		senderPeerId,
		senderPrivB64,
		senderPubB64,
		actualGroupKey,
		keyInfoA.KeyEpoch,
		decryptPlaintext,
	)
	var decryptEnv internal.GroupEnvelope
	if err := json.Unmarshal([]byte(decryptEnvelopeJSON), &decryptEnv); err != nil {
		t.Fatalf("unmarshal decrypt envelope: %v", err)
	}
	publishRawGroupEnvelope(t, nodeA, groupId, decryptEnvelopeJSON)
	waitForCollectedEvent(t, nodeBCapture, "group:decryption_failed", 5*time.Second)

	nodeB.UpdateGroupKey(groupId, keyInfoA)
	parsePlaintext := "GO-008 malformed plaintext must not leak"
	parseEnvelopeJSON := buildTestEnvelopeWithPlaintext(
		t,
		groupId,
		"group_message",
		senderPeerId,
		senderPrivB64,
		senderPubB64,
		actualGroupKey,
		keyInfoA.KeyEpoch,
		parsePlaintext,
	)
	var parseEnv internal.GroupEnvelope
	if err := json.Unmarshal([]byte(parseEnvelopeJSON), &parseEnv); err != nil {
		t.Fatalf("unmarshal parse envelope: %v", err)
	}
	log.Printf("[PUBSUB] Failed to parse payload in group %s: %v", groupId, fmt.Errorf("parse group payload: expected JSON object"))
	nodeB.emitGroupPayloadParseFailed(groupId, &parseEnv)
	waitForCollectedEvent(t, nodeBCapture, "group:payload_parse_failed", 5*time.Second)

	nodeB.logPubSubValidationReject(
		"bad_signature_or_epoch",
		groupId,
		nodeA.Host().ID(),
		&decryptEnv,
	)
	waitForCollectedEvent(t, nodeBCapture, "group:validation_rejected", 5*time.Second)

	rawEvents := strings.Join(nodeBCapture.snapshot(), "\n")
	rawLogs := logBuffer.String()
	for _, secret := range []string{
		decryptPlaintext,
		parsePlaintext,
		actualGroupKey,
		wrongGroupKey,
		decryptEnv.Encrypted.Ciphertext,
		decryptEnv.Encrypted.Nonce,
		decryptEnv.Signature,
		parseEnv.Encrypted.Ciphertext,
		parseEnv.Encrypted.Nonce,
		parseEnv.Signature,
		senderPrivB64,
	} {
		if secret == "" {
			continue
		}
		if strings.Contains(rawEvents, secret) {
			t.Fatalf("GO-008 failure diagnostic event leaked sensitive value %q in events: %s", secret, rawEvents)
		}
		if strings.Contains(rawLogs, secret) {
			t.Fatalf("GO-008 failure diagnostic log leaked sensitive value %q in logs: %s", secret, rawLogs)
		}
	}
	for _, eventName := range []string{
		`"event":"group:decryption_failed"`,
		`"event":"group:payload_parse_failed"`,
		`"event":"group:validation_rejected"`,
	} {
		if !strings.Contains(rawEvents, eventName) {
			t.Fatalf("expected %s in GO-008 diagnostic events: %s", eventName, rawEvents)
		}
	}
}

func TestGL013HandleGroupSubscriptionEmitsDecryptionFailedAfterKeyRemoval(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	_, receiverPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeA := startLocalNodeForMultiRelayTest(t)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

	groupId := "gl013-subscription-key-removed"
	senderPeerId := nodeA.PeerId()
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 13}
	config := &GroupConfig{
		Name:      "GL013 Subscription Key Removed",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderPeerId, Role: GroupRoleAdmin, PublicKey: senderPubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: receiverPubB64},
		},
		CreatedBy: senderPeerId,
	}

	if err := nodeA.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}

	connectLocalGroupNodes(t, nodeA, nodeB)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 3*time.Second)

	// Exercise the accepted-then-key-removed race path; normal missing-key
	// traffic is rejected by nodeB's validator before reaching this handler.
	if err := nodeB.pubsub.UnregisterTopicValidator(GroupTopicPrefix + groupId); err != nil {
		t.Fatalf("nodeB unregister validator before key removal publish: %v", err)
	}
	nodeB.UpdateGroupKey(groupId, nil)
	if got := nodeB.GetGroupKeyInfo(groupId); got != nil {
		t.Fatalf("nodeB GetGroupKeyInfo after nil update = %#v, want nil", got)
	}

	envelopeJSON := buildTestEnvelope(
		t,
		groupId,
		senderPeerId,
		senderPrivB64,
		senderPubB64,
		groupKey,
		keyInfo.KeyEpoch,
		"GL013 valid envelope after receiver key removal",
	)
	baseline := len(nodeBCapture.snapshot())
	publishRawGroupEnvelope(t, nodeA, groupId, envelopeJSON)

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
	gotErr, _ := data["error"].(string)
	if !strings.Contains(gotErr, "missing group key info") {
		t.Fatalf("error = %q, want missing group key info", gotErr)
	}
	if _, ok := data["decryptMs"]; !ok {
		t.Fatal("expected decryptMs field")
	}
	if got, ok := data["localKeyEpoch"]; ok && got != nil {
		t.Fatalf("localKeyEpoch = %v, want absent or null after key removal", got)
	}

	events := nodeBCapture.snapshot()
	for _, raw := range events[baseline:] {
		if strings.Contains(raw, `"event":"group_message:received"`) {
			t.Fatal("group_message:received should not be emitted after missing key")
		}
		if strings.Contains(raw, `"event":"group_reaction:received"`) {
			t.Fatal("group_reaction:received should not be emitted after missing key")
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
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

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

func TestGP023ReceivePathContinuesAfterMalformedPayload(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeA := startLocalNodeForMultiRelayTest(t)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

	groupId := "gp023-malformed-then-valid"
	senderPeerId := nodeA.PeerId()
	config := &GroupConfig{
		Name:      "GP023 Malformed Then Valid",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderPeerId, Role: GroupRoleAdmin, PublicKey: senderPubB64},
		},
		CreatedBy: senderPeerId,
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 23}

	if err := nodeA.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}
	connectLocalGroupNodes(t, nodeA, nodeB)
	waitForGroupTopicPeerCount(t, nodeB, groupId, 1, 3*time.Second)

	badPlaintext := "gp023 malformed non-json plaintext must not surface"
	badEnvelope := buildGroupEnvelopeWithPlaintext(
		t,
		groupId,
		senderPeerId,
		senderPrivB64,
		senderPubB64,
		groupKey,
		keyInfo.KeyEpoch,
		badPlaintext,
	)
	badBaseline := len(nodeBCapture.snapshot())
	publishRawGroupEnvelope(t, nodeA, groupId, badEnvelope)

	parseFailed := waitForCollectedEventAfter(t, nodeBCapture, badBaseline, "group:payload_parse_failed", 5*time.Second)
	for _, tc := range []struct {
		key  string
		want interface{}
	}{
		{"groupId", groupId},
		{"senderId", senderPeerId},
		{"envelopeType", "group_message"},
	} {
		if got := parseFailed[tc.key]; got != tc.want {
			t.Fatalf("%s = %#v, want %#v in parse-failed event %#v", tc.key, got, tc.want, parseFailed)
		}
	}
	assertNoCollectedEventContainingAfter(t, nodeBCapture, badBaseline, `"event":"group_message:received"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, badBaseline, badPlaintext, 500*time.Millisecond)

	messageID := "gp023-valid-after-malformed"
	validPayload := &internal.GroupMessagePayload{
		Text:      "GP-023 valid message after malformed payload",
		Timestamp: "2026-05-13T02:02:00Z",
		Username:  "Alice",
		Extra: map[string]interface{}{
			"messageId": messageID,
		},
	}
	validPlaintext, err := internal.MarshalGroupPayload(validPayload)
	if err != nil {
		t.Fatalf("marshal GP-023 valid payload: %v", err)
	}
	validEnvelope := buildGroupEnvelopeWithPlaintext(
		t,
		groupId,
		senderPeerId,
		senderPrivB64,
		senderPubB64,
		groupKey,
		keyInfo.KeyEpoch,
		validPlaintext,
	)
	validBaseline := len(nodeBCapture.snapshot())
	publishRawGroupEnvelope(t, nodeA, groupId, validEnvelope)

	received := waitForCollectedEventAfter(t, nodeBCapture, validBaseline, "group_message:received", 5*time.Second)
	for _, tc := range []struct {
		key  string
		want interface{}
	}{
		{"groupId", groupId},
		{"senderId", senderPeerId},
		{"senderUsername", "Alice"},
		{"keyEpoch", float64(keyInfo.KeyEpoch)},
		{"text", "GP-023 valid message after malformed payload"},
		{"timestamp", "2026-05-13T02:02:00Z"},
		{"messageId", messageID},
	} {
		if got := received[tc.key]; got != tc.want {
			t.Fatalf("%s = %#v, want %#v in received event %#v", tc.key, got, tc.want, received)
		}
	}
}

func TestGK029MalformedPayloadJSONEmitsPayloadParseFailedOnly(t *testing.T) {
	cases := []struct {
		name      string
		plaintext string
	}{
		{
			name:      "non-json",
			plaintext: "GK029 malformed non-json plaintext must not surface",
		},
		{
			name:      "wrong-schema-json",
			plaintext: `{"notText":"GK029 wrong-schema marker must not surface","timestamp":"2026-05-12T20:30:00Z"}`,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
			_, receiverPubB64 := generateEd25519KeyPair(t)
			groupKey, err := mcrypto.GenerateGroupKey()
			if err != nil {
				t.Fatalf("generate group key: %v", err)
			}

			nodeA := startLocalNodeForMultiRelayTest(t)
			nodeBCapture := &testEventCollector{}
			nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

			groupId := "gk029-payload-parse-" + tc.name
			senderPeerId := nodeA.PeerId()
			config := &GroupConfig{
				Name:      "GK029 Payload Parse",
				GroupType: GroupTypeChat,
				Members: []GroupMember{
					{PeerId: senderPeerId, Role: GroupRoleAdmin, PublicKey: senderPubB64},
					{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: receiverPubB64},
				},
				CreatedBy: senderPeerId,
			}
			keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 29}

			if err := nodeA.JoinGroupTopic(groupId, config, keyInfo); err != nil {
				t.Fatalf("nodeA JoinGroupTopic: %v", err)
			}
			if err := nodeB.JoinGroupTopic(groupId, config, keyInfo); err != nil {
				t.Fatalf("nodeB JoinGroupTopic: %v", err)
			}

			connectLocalGroupNodes(t, nodeA, nodeB)
			waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 3*time.Second)

			envelopeJSON := buildGroupEnvelopeWithPlaintext(
				t,
				groupId,
				senderPeerId,
				senderPrivB64,
				senderPubB64,
				groupKey,
				keyInfo.KeyEpoch,
				tc.plaintext,
			)

			baseline := len(nodeBCapture.snapshot())
			publishRawGroupEnvelope(t, nodeA, groupId, envelopeJSON)

			data := waitForCollectedEventAfter(t, nodeBCapture, baseline, "group:payload_parse_failed", 5*time.Second)
			if got := data["groupId"]; got != groupId {
				t.Fatalf("groupId = %v, want %q", got, groupId)
			}
			if got := data["senderId"]; got != senderPeerId {
				t.Fatalf("senderId = %v, want %q", got, senderPeerId)
			}
			if got := data["envelopeType"]; got != "group_message" {
				t.Fatalf("envelopeType = %v, want %q", got, "group_message")
			}

			assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, `"event":"group_message:received"`, 500*time.Millisecond)
			assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, `"event":"group_reaction:received"`, 500*time.Millisecond)
			assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, `"event":"group:decryption_failed"`, 500*time.Millisecond)
			assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, tc.plaintext, 500*time.Millisecond)
		})
	}
}

func TestGK025ValidGroupReactionDeliveryStillEmitsReaction(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	_, receiverPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeA := startLocalNodeForMultiRelayTest(t)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

	groupId := "gk025-valid-reaction-delivery"
	senderPeerId := nodeA.PeerId()
	config := &GroupConfig{
		Name:      "GK025 Valid Reaction Delivery",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderPeerId, Role: GroupRoleAdmin, PublicKey: senderPubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: receiverPubB64},
		},
		CreatedBy: senderPeerId,
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 25}

	if err := nodeA.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}

	connectLocalGroupNodes(t, nodeA, nodeB)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 3*time.Second)

	reactionBytes, err := json.Marshal(map[string]string{
		"id":           "gk025-valid-reaction",
		"messageId":    "gk025-target-message",
		"emoji":        "+1",
		"action":       "add",
		"senderPeerId": senderPeerId,
		"timestamp":    "2026-05-12T17:00:00Z",
	})
	if err != nil {
		t.Fatalf("marshal reaction payload: %v", err)
	}

	baseline := len(nodeBCapture.snapshot())
	if err := nodeA.PublishGroupReaction(groupId, senderPrivB64, senderPeerId, senderPubB64, string(reactionBytes)); err != nil {
		t.Fatalf("PublishGroupReaction: %v", err)
	}

	data := waitForCollectedEventAfter(t, nodeBCapture, baseline, "group_reaction:received", 5*time.Second)
	if got := data["groupId"]; got != groupId {
		t.Fatalf("groupId = %v, want %q", got, groupId)
	}
	if got := data["senderId"]; got != senderPeerId {
		t.Fatalf("senderId = %v, want %q", got, senderPeerId)
	}
	reactionJSON, _ := data["reaction"].(string)
	if !strings.Contains(reactionJSON, "gk025-valid-reaction") {
		t.Fatalf("reaction payload = %q, want GK025 valid reaction marker", reactionJSON)
	}
	assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, `"event":"group:payload_parse_failed"`, 500*time.Millisecond)
}

func TestGK033GroupReactionRejectsStaleEpochAndRevokedDeviceWithoutReceive(t *testing.T) {
	activePrivB64, activePubB64 := generateEd25519KeyPair(t)
	revokedPrivB64, revokedPubB64 := generateEd25519KeyPair(t)
	_, receiverPubB64 := generateEd25519KeyPair(t)
	currentGroupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate current group key: %v", err)
	}
	previousGroupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate previous group key: %v", err)
	}

	nodeA := startLocalNodeForMultiRelayTest(t)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)
	nodeC := startLocalNodeForMultiRelayTest(t)

	groupId := "gk033-reaction-validation"
	activeDevice := GroupMemberDevice{
		DeviceId:               nodeA.PeerId(),
		TransportPeerId:        nodeA.PeerId(),
		DeviceSigningPublicKey: activePubB64,
		KeyPackageId:           "kp-gk033-active",
		Status:                 "active",
	}
	revokedDevice := GroupMemberDevice{
		DeviceId:               nodeC.PeerId(),
		TransportPeerId:        nodeC.PeerId(),
		DeviceSigningPublicKey: revokedPubB64,
		KeyPackageId:           "kp-gk033-revoked",
		Status:                 "revoked",
		RevokedAt:              "2026-05-12T18:00:00Z",
	}
	config := &GroupConfig{
		Name:      "GK033 Reaction Validation",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{
				PeerId:    nodeA.PeerId(),
				Role:      GroupRoleWriter,
				PublicKey: activePubB64,
				Devices:   []GroupMemberDevice{activeDevice, revokedDevice},
			},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: receiverPubB64},
		},
		CreatedBy: nodeA.PeerId(),
	}
	joinKeyInfo := &GroupKeyInfo{Key: currentGroupKey, KeyEpoch: 2}
	if err := nodeA.JoinGroupTopic(groupId, config, joinKeyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, config, joinKeyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}
	if err := nodeC.JoinGroupTopic(groupId, config, joinKeyInfo); err != nil {
		t.Fatalf("nodeC JoinGroupTopic: %v", err)
	}

	connectLocalGroupNodes(t, nodeA, nodeB)
	connectLocalGroupNodes(t, nodeC, nodeB)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 3*time.Second)
	waitForGroupTopicPeerCount(t, nodeC, groupId, 1, 3*time.Second)

	currentReaction := `{"id":"gk033-current","messageId":"gk033-target","action":"add","emoji":"+1"}`
	currentBaseline := len(nodeBCapture.snapshot())
	if err := nodeA.PublishGroupReaction(groupId, activePrivB64, nodeA.PeerId(), activePubB64, currentReaction); err != nil {
		t.Fatalf("PublishGroupReaction current: %v", err)
	}
	currentData := waitForCollectedEventAfter(t, nodeBCapture, currentBaseline, "group_reaction:received", 5*time.Second)
	if got := currentData["senderId"]; got != nodeA.PeerId() {
		t.Fatalf("current reaction senderId = %v, want %q", got, nodeA.PeerId())
	}
	if reactionJSON, _ := currentData["reaction"].(string); !strings.Contains(reactionJSON, "gk033-current") {
		t.Fatalf("current reaction payload = %q, want GK033 current marker", reactionJSON)
	}

	nodeB.mu.Lock()
	nodeB.groupKeys[groupId] = buildGroupKeyInfoWithGrace(
		currentGroupKey,
		2,
		previousGroupKey,
		1,
		time.Now().Add(-time.Minute),
	)
	nodeB.mu.Unlock()

	staleReactionEnvelope := buildTestDeviceEnvelopeWithPlaintext(
		t,
		groupId,
		"group_reaction",
		nodeA.PeerId(),
		activeDevice.DeviceId,
		activeDevice.TransportPeerId,
		activePubB64,
		activeDevice.KeyPackageId,
		activePrivB64,
		activePubB64,
		previousGroupKey,
		1,
		`{"id":"gk033-stale","messageId":"gk033-target","action":"add","emoji":"+1"}`,
	)
	staleBaseline := len(nodeBCapture.snapshot())
	if err := nodeA.pubsub.UnregisterTopicValidator(GroupTopicPrefix + groupId); err != nil {
		t.Fatalf("nodeA unregister local validator before GK033 stale reaction publish: %v", err)
	}
	publishRawGroupEnvelope(t, nodeA, groupId, staleReactionEnvelope)
	waitForCollectedValidationReject(t, nodeBCapture, staleBaseline, "bad_signature_or_epoch", 1, 5*time.Second)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, staleBaseline, `"event":"group_reaction:received"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, staleBaseline, `"event":"group_message:received"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, staleBaseline, `"event":"group:decryption_failed"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, staleBaseline, "gk033-stale", 500*time.Millisecond)

	revokedReactionEnvelope := buildTestDeviceEnvelopeWithPlaintext(
		t,
		groupId,
		"group_reaction",
		nodeA.PeerId(),
		revokedDevice.DeviceId,
		revokedDevice.TransportPeerId,
		revokedPubB64,
		revokedDevice.KeyPackageId,
		revokedPrivB64,
		revokedPubB64,
		currentGroupKey,
		2,
		`{"id":"gk033-revoked","messageId":"gk033-target","action":"add","emoji":"+1"}`,
	)
	revokedBaseline := len(nodeBCapture.snapshot())
	if err := nodeC.pubsub.UnregisterTopicValidator(GroupTopicPrefix + groupId); err != nil {
		t.Fatalf("nodeC unregister local validator before GK033 revoked-device reaction publish: %v", err)
	}
	publishRawGroupEnvelope(t, nodeC, groupId, revokedReactionEnvelope)
	waitForCollectedValidationReject(t, nodeBCapture, revokedBaseline, "unbound_device", 2, 5*time.Second)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, revokedBaseline, `"event":"group_reaction:received"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, revokedBaseline, `"event":"group_message:received"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, revokedBaseline, `"event":"group:decryption_failed"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, revokedBaseline, "gk033-revoked", 500*time.Millisecond)
}

func TestGK025EnvelopeTypeTamperToReactionEmitsPayloadParseFailedWithoutFakeReaction(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	_, receiverPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeA := startLocalNodeForMultiRelayTest(t)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

	groupId := "gk025-envelope-type-tamper"
	senderPeerId := nodeA.PeerId()
	plaintextMarker := "GK025 message payload must not become a reaction"
	config := &GroupConfig{
		Name:      "GK025 Envelope Type Tamper",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderPeerId, Role: GroupRoleAdmin, PublicKey: senderPubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: receiverPubB64},
		},
		CreatedBy: senderPeerId,
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 25}

	if err := nodeA.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}

	connectLocalGroupNodes(t, nodeA, nodeB)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 3*time.Second)

	validMessageEnvelope := buildTestEnvelope(
		t,
		groupId,
		senderPeerId,
		senderPrivB64,
		senderPubB64,
		groupKey,
		keyInfo.KeyEpoch,
		plaintextMarker,
	)
	tamperedEnvelope := mutateGroupEnvelope(t, validMessageEnvelope, func(env *internal.GroupEnvelope) {
		env.Type = "group_reaction"
	})

	validEnv, err := internal.ParseGroupEnvelope(validMessageEnvelope)
	if err != nil {
		t.Fatalf("parse valid message envelope: %v", err)
	}
	tamperedEnv, err := internal.ParseGroupEnvelope(tamperedEnvelope)
	if err != nil {
		t.Fatalf("parse tampered envelope: %v", err)
	}
	if tamperedEnv.Type != "group_reaction" {
		t.Fatalf("tampered type = %q, want group_reaction", tamperedEnv.Type)
	}
	if tamperedEnv.Signature != validEnv.Signature {
		t.Fatal("tampered type envelope must not be re-signed")
	}
	if tamperedEnv.Encrypted.Ciphertext != validEnv.Encrypted.Ciphertext ||
		tamperedEnv.Encrypted.Nonce != validEnv.Encrypted.Nonce {
		t.Fatal("tampered type envelope must preserve encrypted message payload")
	}
	if result := validateGroupEnvelope(tamperedEnvelope, groupId, config, keyInfo); result != "accept" {
		t.Fatalf("validateGroupEnvelope result = %q, want accept to preserve validator semantics", result)
	}

	baseline := len(nodeBCapture.snapshot())
	publishRawGroupEnvelope(t, nodeA, groupId, tamperedEnvelope)

	data := waitForCollectedEventAfter(t, nodeBCapture, baseline, "group:payload_parse_failed", 5*time.Second)
	if got := data["groupId"]; got != groupId {
		t.Fatalf("groupId = %v, want %q", got, groupId)
	}
	if got := data["senderId"]; got != senderPeerId {
		t.Fatalf("senderId = %v, want %q", got, senderPeerId)
	}
	if got := data["envelopeType"]; got != "group_reaction" {
		t.Fatalf("envelopeType = %v, want %q", got, "group_reaction")
	}

	assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, `"event":"group_reaction:received"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, `"event":"group_message:received"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, `"event":"group:decryption_failed"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, plaintextMarker, 500*time.Millisecond)
}

func TestGK006TamperedCiphertextAfterSigningRejectedByValidatorAndEmitsNoMessage(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	_, receiverPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeA := startLocalNodeForMultiRelayTest(t)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

	groupId := "gk006-post-sign-ciphertext-tamper"
	senderPeerId := nodeA.PeerId()
	config := &GroupConfig{
		Name:      "GK006 Post-Sign Ciphertext Tamper",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderPeerId, Role: GroupRoleAdmin, PublicKey: senderPubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: receiverPubB64},
		},
		CreatedBy: senderPeerId,
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 6}

	if err := nodeA.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}

	connectLocalGroupNodes(t, nodeA, nodeB)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 3*time.Second)

	validEnvelope := buildTestEnvelope(
		t,
		groupId,
		senderPeerId,
		senderPrivB64,
		senderPubB64,
		groupKey,
		keyInfo.KeyEpoch,
		"hello over post-signing tampered ciphertext",
	)
	tamperedEnvelope := mutateGroupEnvelope(t, validEnvelope, func(env *internal.GroupEnvelope) {
		ciphertextBytes, err := base64.StdEncoding.DecodeString(env.Encrypted.Ciphertext)
		if err != nil {
			t.Fatalf("decode ciphertext: %v", err)
		}
		if len(ciphertextBytes) == 0 {
			t.Fatal("expected non-empty decoded ciphertext")
		}
		ciphertextBytes[0] ^= 0xFF
		env.Encrypted.Ciphertext = base64.StdEncoding.EncodeToString(ciphertextBytes)
	})

	if result := validateGroupEnvelope(tamperedEnvelope, groupId, config, keyInfo); result != "reject:bad_signature" {
		t.Fatalf("validateGroupEnvelope result = %q, want reject:bad_signature", result)
	}

	rejectBaseline := len(nodeBCapture.snapshot())
	// Node A's local validator rejects this post-signing mutation before
	// fanout; disable only node A so node B's validator remains under test.
	if err := nodeA.pubsub.UnregisterTopicValidator(GroupTopicPrefix + groupId); err != nil {
		t.Fatalf("nodeA unregister local validator before GK006 raw publish: %v", err)
	}
	publishRawGroupEnvelope(t, nodeA, groupId, tamperedEnvelope)
	waitForCollectedValidationReject(t, nodeBCapture, rejectBaseline, "bad_signature_or_epoch", keyInfo.KeyEpoch, 5*time.Second)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaseline, `"event":"group_message:received"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaseline, `"event":"group_reaction:received"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaseline, `"event":"group:decryption_failed"`, 500*time.Millisecond)
}

func TestGK008SignatureRejectsWrongPublicKeyAndEmitsNoMessage(t *testing.T) {
	_, memberBPubB64 := generateEd25519KeyPair(t)
	attackerPrivB64, attackerPubB64 := generateEd25519KeyPair(t)
	_, receiverPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeA := startLocalNodeForMultiRelayTest(t)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

	groupId := "gk008-signature-rejects-wrong-public-key"
	memberBPeerId := nodeA.PeerId()
	plaintextMarker := "GK008 plaintext marker must not surface"
	config := &GroupConfig{
		Name:      "GK008 Wrong Public Key Signature",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: memberBPeerId, Role: GroupRoleAdmin, PublicKey: memberBPubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: receiverPubB64},
		},
		CreatedBy: memberBPeerId,
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 8}

	if err := nodeA.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}

	connectLocalGroupNodes(t, nodeA, nodeB)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 3*time.Second)

	wrongKeyEnvelope := buildTestEnvelope(
		t,
		groupId,
		memberBPeerId,
		attackerPrivB64,
		memberBPubB64,
		groupKey,
		keyInfo.KeyEpoch,
		plaintextMarker,
	)
	env, err := internal.ParseGroupEnvelope(wrongKeyEnvelope)
	if err != nil {
		t.Fatalf("parse wrong-key envelope: %v", err)
	}
	if env.SenderId != memberBPeerId {
		t.Fatalf("senderId = %q, want %q", env.SenderId, memberBPeerId)
	}
	if env.SenderPublicKey != memberBPubB64 {
		t.Fatal("wrong-key envelope must claim member B public key")
	}
	if env.SenderDevicePublicKey != "" {
		t.Fatalf("senderDevicePublicKey = %q, want empty legacy member path", env.SenderDevicePublicKey)
	}

	signatureData := mcrypto.BuildGroupSignatureData(groupId, keyInfo.KeyEpoch, env.Encrypted.Ciphertext)
	validWithAttackerKey, err := mcrypto.VerifyPayload(attackerPubB64, signatureData, env.Signature)
	if err != nil {
		t.Fatalf("verify signature with attacker public key: %v", err)
	}
	if !validWithAttackerKey {
		t.Fatal("signature should verify with attacker public key X")
	}
	validWithMemberBKey, err := mcrypto.VerifyPayload(memberBPubB64, signatureData, env.Signature)
	if err != nil {
		t.Fatalf("verify signature with member B public key: %v", err)
	}
	if validWithMemberBKey {
		t.Fatal("signature should not verify with configured member B public key")
	}

	if result := validateGroupEnvelope(wrongKeyEnvelope, groupId, config, keyInfo); result != "reject:bad_signature" {
		t.Fatalf("validateGroupEnvelope result = %q, want reject:bad_signature", result)
	}

	rejectBaseline := len(nodeBCapture.snapshot())
	// Node A's local validator rejects the wrong-key signature before fanout;
	// disable only node A so node B's validator remains under test.
	if err := nodeA.pubsub.UnregisterTopicValidator(GroupTopicPrefix + groupId); err != nil {
		t.Fatalf("nodeA unregister local validator before GK008 raw publish: %v", err)
	}
	publishRawGroupEnvelope(t, nodeA, groupId, wrongKeyEnvelope)
	waitForCollectedValidationReject(t, nodeBCapture, rejectBaseline, "bad_signature_or_epoch", keyInfo.KeyEpoch, 5*time.Second)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaseline, `"event":"group_message:received"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaseline, `"event":"group_reaction:received"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaseline, `"event":"group:decryption_failed"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaseline, plaintextMarker, 500*time.Millisecond)
}

func TestGE018SeededEnvelopeTamperingLivePathNeverRendersPlaintext(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	_, receiverPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeA := startLocalNodeForMultiRelayTest(t)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

	groupId := "ge018-live-tamper"
	senderPeerId := nodeA.PeerId()
	plaintextMarker := "GE-018 tampered plaintext marker must not render"
	config := &GroupConfig{
		Name:      "GE-018 Live Tamper",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderPeerId, Role: GroupRoleAdmin, PublicKey: senderPubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: receiverPubB64},
		},
		CreatedBy: senderPeerId,
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 18}

	if err := nodeA.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}

	connectLocalGroupNodes(t, nodeA, nodeB)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 3*time.Second)

	validEnvelope := buildTestEnvelope(
		t,
		groupId,
		senderPeerId,
		senderPrivB64,
		senderPubB64,
		groupKey,
		keyInfo.KeyEpoch,
		plaintextMarker,
	)
	validBaseline := len(nodeBCapture.snapshot())
	publishRawGroupEnvelope(t, nodeA, groupId, validEnvelope)
	received := waitForCollectedEventAfter(t, nodeBCapture, validBaseline, "group_message:received", 5*time.Second)
	if got := received["text"]; got != plaintextMarker {
		t.Fatalf("valid control text = %#v, want %q in event %#v", got, plaintextMarker, received)
	}

	if err := nodeA.pubsub.UnregisterTopicValidator(GroupTopicPrefix + groupId); err != nil {
		t.Fatalf("nodeA unregister local validator before GE-018 raw publish: %v", err)
	}

	type liveMutation struct {
		name     string
		envelope string
		event    string
		reason   string
		keyEpoch int
	}
	mutations := []liveMutation{
		{
			name:     "version_tamper",
			envelope: setGroupEnvelopeJSONField(t, validEnvelope, "version", "2"),
			event:    "group:validation_rejected",
			reason:   "not_v3_envelope",
			keyEpoch: 0,
		},
		{
			name:     "group_id_mismatch",
			envelope: setGroupEnvelopeJSONField(t, validEnvelope, "groupId", "ge018-live-other"),
			event:    "group:validation_rejected",
			reason:   "group_mismatch",
			keyEpoch: keyInfo.KeyEpoch,
		},
		{
			name: "ciphertext_tamper",
			envelope: mutateGroupEnvelope(t, validEnvelope, func(env *internal.GroupEnvelope) {
				ciphertextBytes, err := base64.StdEncoding.DecodeString(env.Encrypted.Ciphertext)
				if err != nil {
					t.Fatalf("decode ciphertext: %v", err)
				}
				ciphertextBytes[0] ^= 0x11
				env.Encrypted.Ciphertext = base64.StdEncoding.EncodeToString(ciphertextBytes)
			}),
			event:    "group:validation_rejected",
			reason:   "bad_signature_or_epoch",
			keyEpoch: keyInfo.KeyEpoch,
		},
		{
			name: "nonce_tamper",
			envelope: mutateGroupEnvelope(t, validEnvelope, func(env *internal.GroupEnvelope) {
				nonceBytes, err := base64.StdEncoding.DecodeString(env.Encrypted.Nonce)
				if err != nil {
					t.Fatalf("decode nonce: %v", err)
				}
				nonceBytes[0] ^= 0x22
				env.Encrypted.Nonce = base64.StdEncoding.EncodeToString(nonceBytes)
			}),
			event:    "group:decryption_failed",
			keyEpoch: keyInfo.KeyEpoch,
		},
		{
			name: "type_tamper_to_reaction",
			envelope: mutateGroupEnvelope(t, validEnvelope, func(env *internal.GroupEnvelope) {
				env.Type = "group_reaction"
			}),
			event:    "group:payload_parse_failed",
			keyEpoch: keyInfo.KeyEpoch,
		},
	}

	for _, seed := range []int64{18018} {
		t.Run(fmt.Sprintf("seed_%d", seed), func(t *testing.T) {
			for _, tc := range mutations {
				t.Run(tc.name, func(t *testing.T) {
					baseline := len(nodeBCapture.snapshot())
					publishRawGroupEnvelope(t, nodeA, groupId, tc.envelope)
					switch tc.event {
					case "group:validation_rejected":
						waitForCollectedValidationReject(t, nodeBCapture, baseline, tc.reason, tc.keyEpoch, 5*time.Second)
					default:
						data := waitForCollectedEventAfter(t, nodeBCapture, baseline, tc.event, 5*time.Second)
						if got := data["groupId"]; got != groupId {
							t.Fatalf("%s groupId = %#v, want %q in event %#v", tc.name, got, groupId, data)
						}
					}
					assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, `"event":"group_message:received"`, 500*time.Millisecond)
					assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, `"event":"group_reaction:received"`, 500*time.Millisecond)
					assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, plaintextMarker, 500*time.Millisecond)
				})
			}
		})
	}
}

func TestGK012MissingSignatureRejectedByValidatorAndEmitsNoMessage(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	_, receiverPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeA := startLocalNodeForMultiRelayTest(t)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

	groupId := "gk012-missing-signature"
	senderPeerId := nodeA.PeerId()
	config := &GroupConfig{
		Name:      "GK012 Missing Signature",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderPeerId, Role: GroupRoleAdmin, PublicKey: senderPubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: receiverPubB64},
		},
		CreatedBy: senderPeerId,
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 12}

	if err := nodeA.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}

	connectLocalGroupNodes(t, nodeA, nodeB)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 3*time.Second)

	validEnvelope := buildTestEnvelope(
		t,
		groupId,
		senderPeerId,
		senderPrivB64,
		senderPubB64,
		groupKey,
		keyInfo.KeyEpoch,
		"missing signature must not emit",
	)
	missingSignatureEnvelope := deleteGroupEnvelopeJSONField(t, validEnvelope, "signature")

	env, err := internal.ParseGroupEnvelope(missingSignatureEnvelope)
	if err != nil {
		t.Fatalf("parse missing signature envelope: %v", err)
	}
	if env.Signature != "" {
		t.Fatalf("parsed Signature = %q, want empty", env.Signature)
	}
	if result := validateGroupEnvelope(missingSignatureEnvelope, groupId, config, keyInfo); result != "reject:bad_signature" {
		t.Fatalf("validateGroupEnvelope result = %q, want reject:bad_signature", result)
	}

	rejectBaseline := len(nodeBCapture.snapshot())
	// Node A's local validator rejects the missing signature before fanout;
	// disable only node A so node B's validator remains under test.
	if err := nodeA.pubsub.UnregisterTopicValidator(GroupTopicPrefix + groupId); err != nil {
		t.Fatalf("nodeA unregister local validator before GK012 raw publish: %v", err)
	}
	publishRawGroupEnvelope(t, nodeA, groupId, missingSignatureEnvelope)
	waitForCollectedValidationReject(t, nodeBCapture, rejectBaseline, "bad_signature_or_epoch", keyInfo.KeyEpoch, 5*time.Second)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaseline, `"event":"group_message:received"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaseline, `"event":"group_reaction:received"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaseline, `"event":"group:decryption_failed"`, 500*time.Millisecond)
}

func TestGK013MissingEncryptedFieldsRejectedByValidatorAndEmitsNoPayloadEvent(t *testing.T) {
	cases := []struct {
		name  string
		field string
	}{
		{name: "missing ciphertext", field: "ciphertext"},
		{name: "missing nonce", field: "nonce"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
			_, receiverPubB64 := generateEd25519KeyPair(t)
			groupKey, err := mcrypto.GenerateGroupKey()
			if err != nil {
				t.Fatalf("generate group key: %v", err)
			}

			nodeA := startLocalNodeForMultiRelayTest(t)
			nodeBCapture := &testEventCollector{}
			nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

			groupId := "gk013-missing-" + strings.ReplaceAll(tc.field, "_", "-")
			senderPeerId := nodeA.PeerId()
			plaintextMarker := "GK013 plaintext marker for " + tc.field + " must not surface"
			config := &GroupConfig{
				Name:      "GK013 Missing Encrypted Field",
				GroupType: GroupTypeChat,
				Members: []GroupMember{
					{PeerId: senderPeerId, Role: GroupRoleAdmin, PublicKey: senderPubB64},
					{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: receiverPubB64},
				},
				CreatedBy: senderPeerId,
			}
			keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 13}

			if err := nodeA.JoinGroupTopic(groupId, config, keyInfo); err != nil {
				t.Fatalf("nodeA JoinGroupTopic: %v", err)
			}
			if err := nodeB.JoinGroupTopic(groupId, config, keyInfo); err != nil {
				t.Fatalf("nodeB JoinGroupTopic: %v", err)
			}

			connectLocalGroupNodes(t, nodeA, nodeB)
			waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 3*time.Second)

			validEnvelope := buildTestEnvelope(
				t,
				groupId,
				senderPeerId,
				senderPrivB64,
				senderPubB64,
				groupKey,
				keyInfo.KeyEpoch,
				plaintextMarker,
			)
			malformedEnvelope := deleteNestedGroupEnvelopeJSONField(t, validEnvelope, "encrypted", tc.field)
			if result := validateGroupEnvelopeForTransportPeer(malformedEnvelope, groupId, config, keyInfo, senderPeerId); result != "reject:invalid_envelope" {
				t.Fatalf("validateGroupEnvelopeForTransportPeer result = %q, want reject:invalid_envelope", result)
			}

			rejectBaseline := len(nodeBCapture.snapshot())
			// Node A's local validator may reject the malformed envelope before
			// fanout; disable only node A so node B's validator remains under test.
			if err := nodeA.pubsub.UnregisterTopicValidator(GroupTopicPrefix + groupId); err != nil {
				t.Fatalf("nodeA unregister local validator before GK013 raw publish: %v", err)
			}
			publishRawGroupEnvelope(t, nodeA, groupId, malformedEnvelope)
			waitForCollectedValidationReject(t, nodeBCapture, rejectBaseline, "invalid_envelope", keyInfo.KeyEpoch, 5*time.Second)
			assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaseline, `"event":"group_message:received"`, 500*time.Millisecond)
			assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaseline, `"event":"group_reaction:received"`, 500*time.Millisecond)
			assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaseline, `"event":"group:decryption_failed"`, 500*time.Millisecond)
			assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaseline, plaintextMarker, 500*time.Millisecond)
		})
	}
}

func TestGK015GroupIDMismatchRejectedByValidatorAndEmitsNoPayloadEvent(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	_, receiverPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeA := startLocalNodeForMultiRelayTest(t)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

	topicGroupId := "gk015-topic-group"
	envelopeGroupId := "gk015-envelope-group"
	senderPeerId := nodeA.PeerId()
	plaintextMarker := "GK015 plaintext marker must not surface"
	config := &GroupConfig{
		Name:      "GK015 Group ID Mismatch",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderPeerId, Role: GroupRoleAdmin, PublicKey: senderPubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: receiverPubB64},
		},
		CreatedBy: senderPeerId,
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 15}

	if err := nodeA.JoinGroupTopic(topicGroupId, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(topicGroupId, config, keyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}

	connectLocalGroupNodes(t, nodeA, nodeB)
	waitForGroupTopicPeerCount(t, nodeA, topicGroupId, 1, 3*time.Second)

	mismatchedEnvelope := buildTestEnvelope(
		t,
		envelopeGroupId,
		senderPeerId,
		senderPrivB64,
		senderPubB64,
		groupKey,
		keyInfo.KeyEpoch,
		plaintextMarker,
	)
	if result := validateGroupEnvelopeForTransportPeer(
		mismatchedEnvelope,
		topicGroupId,
		config,
		keyInfo,
		senderPeerId,
	); result != "reject:group_mismatch" {
		t.Fatalf("validateGroupEnvelopeForTransportPeer result = %q, want reject:group_mismatch", result)
	}

	rejectBaseline := len(nodeBCapture.snapshot())
	if err := nodeA.pubsub.UnregisterTopicValidator(GroupTopicPrefix + topicGroupId); err != nil {
		t.Fatalf("nodeA unregister local validator before GK015 raw publish: %v", err)
	}
	publishRawGroupEnvelope(t, nodeA, topicGroupId, mismatchedEnvelope)
	waitForCollectedValidationReject(t, nodeBCapture, rejectBaseline, "group_mismatch", keyInfo.KeyEpoch, 5*time.Second)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaseline, `"event":"group_message:received"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaseline, `"event":"group_reaction:received"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaseline, `"event":"group:decryption_failed"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaseline, plaintextMarker, 500*time.Millisecond)
}

func TestGK026SenderIDTamperLiveRawPublishRejectsWithoutAttributionCorruption(t *testing.T) {
	memberBPrivB64, memberBPubB64 := generateEd25519KeyPair(t)
	_, memberCPubB64 := generateEd25519KeyPair(t)
	_, receiverPubB64 := generateEd25519KeyPair(t)
	if memberBPubB64 == memberCPubB64 {
		t.Fatal("test requires distinct member B and C signing keys")
	}
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeC := startLocalNodeForMultiRelayTest(t)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

	groupId := "gk026-senderid-tamper"
	memberBPeerId := generatePeerIDStr(t)
	memberCPeerId := nodeC.PeerId()
	receiverPeerId := nodeB.PeerId()
	plaintextMarker := "GK026 B signed plaintext must not surface as C"
	config := &GroupConfig{
		Name:      "GK026 SenderId Tamper",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: memberBPeerId, Role: GroupRoleAdmin, PublicKey: memberBPubB64},
			{PeerId: memberCPeerId, Role: GroupRoleWriter, PublicKey: memberCPubB64},
			{PeerId: receiverPeerId, Role: GroupRoleWriter, PublicKey: receiverPubB64},
		},
		CreatedBy: memberBPeerId,
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 26}

	if err := nodeC.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeC JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}

	connectLocalGroupNodes(t, nodeC, nodeB)
	waitForGroupTopicPeerCount(t, nodeC, groupId, 1, 3*time.Second)

	validEnvelope := buildTestEnvelope(
		t,
		groupId,
		memberBPeerId,
		memberBPrivB64,
		memberBPubB64,
		groupKey,
		keyInfo.KeyEpoch,
		plaintextMarker,
	)
	tamperedEnvelope := setGroupEnvelopeJSONField(t, validEnvelope, "senderId", memberCPeerId)

	_, tamperedEnv := assertGK026SenderIDOnlyMutationPreservesEnvelope(
		t,
		validEnvelope,
		tamperedEnvelope,
		memberBPeerId,
		memberCPeerId,
	)
	if tamperedEnv.SenderPublicKey != memberBPubB64 {
		t.Fatal("tampered envelope should still carry member B's original senderPublicKey field")
	}
	signatureData := mcrypto.BuildGroupSignatureData(groupId, keyInfo.KeyEpoch, tamperedEnv.Encrypted.Ciphertext)
	validWithBKey, err := mcrypto.VerifyPayload(memberBPubB64, signatureData, tamperedEnv.Signature)
	if err != nil {
		t.Fatalf("verify tampered envelope with member B key: %v", err)
	}
	if !validWithBKey {
		t.Fatal("tampered envelope signature should still verify with member B's signing key")
	}
	validWithCKey, err := mcrypto.VerifyPayload(memberCPubB64, signatureData, tamperedEnv.Signature)
	if err != nil {
		t.Fatalf("verify tampered envelope with member C key: %v", err)
	}
	if validWithCKey {
		t.Fatal("tampered envelope signature must not verify with member C's configured signing key")
	}
	if result := validateGroupEnvelopeForTransportPeer(
		tamperedEnvelope,
		groupId,
		config,
		keyInfo,
		memberCPeerId,
	); result != "reject:bad_signature" {
		t.Fatalf("tampered senderId result = %q, want reject:bad_signature under C's configured key", result)
	}

	rejectBaseline := len(nodeBCapture.snapshot())
	// Node C's local validator rejects the B-signed/C-claimed envelope before
	// fanout; disable only node C so node B's validator remains under test.
	if err := nodeC.pubsub.UnregisterTopicValidator(GroupTopicPrefix + groupId); err != nil {
		t.Fatalf("nodeC unregister local validator before GK026 raw publish: %v", err)
	}
	publishRawGroupEnvelope(t, nodeC, groupId, tamperedEnvelope)
	waitForCollectedValidationReject(t, nodeBCapture, rejectBaseline, "bad_signature_or_epoch", keyInfo.KeyEpoch, 5*time.Second)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaseline, `"event":"group_message:received"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaseline, `"event":"group_reaction:received"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaseline, `"event":"group:decryption_failed"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaseline, plaintextMarker, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaseline, `"senderId":"`+memberCPeerId+`"`, 500*time.Millisecond)
}

func TestGK027DeviceAndTransportBindingTamperLiveRawPublishRejectsWithoutPayload(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	_, receiverPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeA := startLocalNodeForMultiRelayTest(t)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

	groupId := "gk027-device-transport-binding-tamper"
	senderMemberId := "member-gk027-live"
	receiverPeerId := nodeB.PeerId()
	plaintextMarker := "GK027 active device-bound plaintext must not surface"
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 27}
	activeDevice := GroupMemberDevice{
		DeviceId:               "gk027-live-active-device",
		TransportPeerId:        nodeA.PeerId(),
		DeviceSigningPublicKey: senderPubB64,
		KeyPackageId:           "gk027-live-active-key-package",
		Status:                 "active",
	}
	revokedDevice := GroupMemberDevice{
		DeviceId:               "gk027-live-revoked-device",
		TransportPeerId:        generatePeerIDStr(t),
		DeviceSigningPublicKey: senderPubB64,
		KeyPackageId:           "gk027-live-revoked-key-package",
		Status:                 "revoked",
		RevokedAt:              "2026-05-12T18:00:00Z",
	}
	config := &GroupConfig{
		Name:      "GK027 Live Binding Tamper",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{
				PeerId:  senderMemberId,
				Role:    GroupRoleAdmin,
				Devices: []GroupMemberDevice{activeDevice, revokedDevice},
			},
			{PeerId: receiverPeerId, Role: GroupRoleWriter, PublicKey: receiverPubB64},
		},
		CreatedBy: senderMemberId,
	}

	if err := nodeA.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}

	connectLocalGroupNodes(t, nodeA, nodeB)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 3*time.Second)

	validEnvelope := buildTestDeviceEnvelope(
		t,
		groupId,
		senderMemberId,
		activeDevice.DeviceId,
		activeDevice.TransportPeerId,
		activeDevice.DeviceSigningPublicKey,
		activeDevice.KeyPackageId,
		senderPrivB64,
		senderPubB64,
		groupKey,
		keyInfo.KeyEpoch,
		plaintextMarker,
	)
	if result := validateGroupEnvelopeForTransportPeer(validEnvelope, groupId, config, keyInfo, nodeA.PeerId()); result != "accept" {
		t.Fatalf("valid device-bound envelope result = %q, want accept", result)
	}

	deviceTamperedEnvelope := setGroupEnvelopeJSONField(t, validEnvelope, "senderDeviceId", revokedDevice.DeviceId)
	_, deviceTamperedEnv := assertGK027BindingOnlyMutationPreservesEnvelope(
		t,
		validEnvelope,
		deviceTamperedEnvelope,
		"senderDeviceId",
		revokedDevice.DeviceId,
	)
	if result := validateGroupEnvelopeForTransportPeer(deviceTamperedEnvelope, groupId, config, keyInfo, nodeA.PeerId()); result != "reject:unbound_device" {
		t.Fatalf("senderDeviceId tamper result = %q, want reject:unbound_device", result)
	}

	transportTamperedEnvelope := setGroupEnvelopeJSONField(t, validEnvelope, "senderTransportPeerId", revokedDevice.TransportPeerId)
	_, transportTamperedEnv := assertGK027BindingOnlyMutationPreservesEnvelope(
		t,
		validEnvelope,
		transportTamperedEnvelope,
		"senderTransportPeerId",
		revokedDevice.TransportPeerId,
	)
	if result := validateGroupEnvelopeForTransportPeer(transportTamperedEnvelope, groupId, config, keyInfo, nodeA.PeerId()); result != "reject:peer_mismatch" {
		t.Fatalf("senderTransportPeerId tamper result = %q, want reject:peer_mismatch", result)
	}

	if err := nodeA.pubsub.UnregisterTopicValidator(GroupTopicPrefix + groupId); err != nil {
		t.Fatalf("nodeA unregister local validator before GK027 raw publishes: %v", err)
	}

	rejectBaseline := len(nodeBCapture.snapshot())
	publishRawGroupEnvelope(t, nodeA, groupId, deviceTamperedEnvelope)
	waitForCollectedValidationReject(t, nodeBCapture, rejectBaseline, "unbound_device", keyInfo.KeyEpoch, 5*time.Second)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaseline, `"event":"group_message:received"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaseline, `"event":"group_reaction:received"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaseline, `"event":"group:decryption_failed"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaseline, plaintextMarker, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaseline, `"senderDeviceId":"`+deviceTamperedEnv.SenderDeviceId+`"`, 500*time.Millisecond)

	rejectBaseline = len(nodeBCapture.snapshot())
	publishRawGroupEnvelope(t, nodeA, groupId, transportTamperedEnvelope)
	waitForCollectedValidationReject(t, nodeBCapture, rejectBaseline, "peer_mismatch", keyInfo.KeyEpoch, 5*time.Second)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaseline, `"event":"group_message:received"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaseline, `"event":"group_reaction:received"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaseline, `"event":"group:decryption_failed"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaseline, plaintextMarker, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaseline, `"senderTransportPeerId":"`+transportTamperedEnv.SenderTransportPeerId+`"`, 500*time.Millisecond)
}

func TestGK028SenderPublicKeyTamperLiveRawPublishRejectsWithoutPayload(t *testing.T) {
	memberPrivB64, memberPubB64 := generateEd25519KeyPair(t)
	attackerPrivB64, attackerPubB64 := generateEd25519KeyPair(t)
	_, receiverPubB64 := generateEd25519KeyPair(t)
	if memberPubB64 == attackerPubB64 {
		t.Fatal("test requires distinct configured and attacker keys")
	}
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeA := startLocalNodeForMultiRelayTest(t)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

	groupId := "gk028-sender-public-key-tamper"
	senderPeerId := nodeA.PeerId()
	receiverPeerId := nodeB.PeerId()
	plaintextMarker := "GK028 attacker-key signed plaintext must not surface"
	config := &GroupConfig{
		Name:      "GK028 SenderPublicKey Tamper",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderPeerId, Role: GroupRoleAdmin, PublicKey: memberPubB64},
			{PeerId: receiverPeerId, Role: GroupRoleWriter, PublicKey: receiverPubB64},
		},
		CreatedBy: senderPeerId,
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 28}

	if err := nodeA.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}

	connectLocalGroupNodes(t, nodeA, nodeB)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 3*time.Second)

	validEnvelope := buildTestEnvelope(
		t,
		groupId,
		senderPeerId,
		memberPrivB64,
		memberPubB64,
		groupKey,
		keyInfo.KeyEpoch,
		"GK028 configured-key signed plaintext",
	)
	if result := validateGroupEnvelopeForTransportPeer(validEnvelope, groupId, config, keyInfo, senderPeerId); result != "accept" {
		t.Fatalf("valid configured-key envelope result = %q, want accept", result)
	}

	tamperedEnvelope := buildTestEnvelope(
		t,
		groupId,
		senderPeerId,
		attackerPrivB64,
		attackerPubB64,
		groupKey,
		keyInfo.KeyEpoch,
		plaintextMarker,
	)
	tamperedEnv, err := internal.ParseGroupEnvelope(tamperedEnvelope)
	if err != nil {
		t.Fatalf("parse tampered envelope: %v", err)
	}
	if tamperedEnv.SenderPublicKey != attackerPubB64 {
		t.Fatalf("tampered senderPublicKey = %q, want attacker key", tamperedEnv.SenderPublicKey)
	}
	signatureData := mcrypto.BuildGroupSignatureData(groupId, keyInfo.KeyEpoch, tamperedEnv.Encrypted.Ciphertext)
	validWithAttackerKey, err := mcrypto.VerifyPayload(attackerPubB64, signatureData, tamperedEnv.Signature)
	if err != nil {
		t.Fatalf("verify tampered envelope with attacker key: %v", err)
	}
	if !validWithAttackerKey {
		t.Fatal("tampered envelope signature should verify with the claimed attacker senderPublicKey")
	}
	validWithConfiguredKey, err := mcrypto.VerifyPayload(memberPubB64, signatureData, tamperedEnv.Signature)
	if err != nil {
		t.Fatalf("verify tampered envelope with configured member key: %v", err)
	}
	if validWithConfiguredKey {
		t.Fatal("tampered envelope signature unexpectedly verifies with the configured member key")
	}
	if result := validateGroupEnvelopeForTransportPeer(
		tamperedEnvelope,
		groupId,
		config,
		keyInfo,
		senderPeerId,
	); result != "reject:bad_signature" {
		t.Fatalf("tampered senderPublicKey result = %q, want reject:bad_signature under configured member key", result)
	}

	rejectBaseline := len(nodeBCapture.snapshot())
	if err := nodeA.pubsub.UnregisterTopicValidator(GroupTopicPrefix + groupId); err != nil {
		t.Fatalf("nodeA unregister local validator before GK028 raw publish: %v", err)
	}
	publishRawGroupEnvelope(t, nodeA, groupId, tamperedEnvelope)
	waitForCollectedValidationReject(t, nodeBCapture, rejectBaseline, "bad_signature_or_epoch", keyInfo.KeyEpoch, 5*time.Second)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaseline, `"event":"group_message:received"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaseline, `"event":"group_reaction:received"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaseline, `"event":"group:decryption_failed"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaseline, `"event":"group:payload_parse_failed"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaseline, plaintextMarker, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, rejectBaseline, `"senderPublicKey":"`+attackerPubB64+`"`, 500*time.Millisecond)
}

func TestGK007NonceByteTamperFailsDecryptAndEmitsNoMessage(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	_, receiverPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeA := startLocalNodeForMultiRelayTest(t)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

	groupId := "gk007-nonce-byte-tamper"
	senderPeerId := nodeA.PeerId()
	plaintextMarker := "GK007 plaintext marker must not surface"
	config := &GroupConfig{
		Name:      "GK007 Nonce Byte Tamper",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderPeerId, Role: GroupRoleAdmin, PublicKey: senderPubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: receiverPubB64},
		},
		CreatedBy: senderPeerId,
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 7}

	if err := nodeA.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}

	connectLocalGroupNodes(t, nodeA, nodeB)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 3*time.Second)

	validEnvelope := buildTestEnvelope(
		t,
		groupId,
		senderPeerId,
		senderPrivB64,
		senderPubB64,
		groupKey,
		keyInfo.KeyEpoch,
		plaintextMarker,
	)
	tamperedEnvelope := mutateGroupEnvelope(t, validEnvelope, func(env *internal.GroupEnvelope) {
		nonceBytes, err := base64.StdEncoding.DecodeString(env.Encrypted.Nonce)
		if err != nil {
			t.Fatalf("decode nonce: %v", err)
		}
		if len(nonceBytes) != 12 {
			t.Fatalf("decoded nonce length = %d, want 12", len(nonceBytes))
		}
		nonceBytes[0] ^= 0xFF
		env.Encrypted.Nonce = base64.StdEncoding.EncodeToString(nonceBytes)
	})

	validEnv, err := internal.ParseGroupEnvelope(validEnvelope)
	if err != nil {
		t.Fatalf("parse valid envelope: %v", err)
	}
	tamperedEnv, err := internal.ParseGroupEnvelope(tamperedEnvelope)
	if err != nil {
		t.Fatalf("parse tampered envelope: %v", err)
	}
	if tamperedEnv.Signature != validEnv.Signature {
		t.Fatal("tampered nonce envelope must not be re-signed")
	}
	if tamperedEnv.Encrypted.Ciphertext != validEnv.Encrypted.Ciphertext {
		t.Fatal("tampered nonce envelope changed ciphertext")
	}
	if tamperedEnv.Encrypted.Nonce == validEnv.Encrypted.Nonce {
		t.Fatal("tampered nonce envelope did not change nonce")
	}

	if result := validateGroupEnvelope(tamperedEnvelope, groupId, config, keyInfo); result != "accept" {
		t.Fatalf("validateGroupEnvelope result = %q, want accept", result)
	}

	baseline := len(nodeBCapture.snapshot())
	publishRawGroupEnvelope(t, nodeA, groupId, tamperedEnvelope)

	data := waitForCollectedEventAfter(t, nodeBCapture, baseline, "group:decryption_failed", 5*time.Second)

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
	gotErr, _ := data["error"].(string)
	if !strings.Contains(gotErr, "aes-gcm decrypt") {
		t.Fatalf("error = %q, want aes-gcm decrypt", gotErr)
	}

	assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, `"event":"group_message:received"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, `"event":"group_reaction:received"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, plaintextMarker, 500*time.Millisecond)
}

func TestHandleGroupSubscription_EmitsDecryptionFailedEventForTamperedNonce(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeA := startLocalNodeForMultiRelayTest(t)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

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
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

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

func TestSV005TamperedCiphertextOrNonceDoesNotPoisonLaterValidDelivery(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeA := startLocalNodeForMultiRelayTest(t)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

	groupId := "sv005-tamper-stream-recovery"
	senderPeerId := nodeA.PeerId()
	config := &GroupConfig{
		Name:      "SV-005 Tamper Stream Recovery",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderPeerId, Role: GroupRoleAdmin, PublicKey: senderPubB64},
		},
		CreatedBy: senderPeerId,
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 12}

	if err := nodeA.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}

	connectLocalGroupNodes(t, nodeA, nodeB)

	nonceEnvelope := buildTestEnvelope(
		t,
		groupId,
		senderPeerId,
		senderPrivB64,
		senderPubB64,
		groupKey,
		keyInfo.KeyEpoch,
		"SV-005 tampered nonce should not deliver",
	)
	tamperedNonceEnvelope := mutateGroupEnvelope(t, nonceEnvelope, func(env *internal.GroupEnvelope) {
		nonceBytes, err := base64.StdEncoding.DecodeString(env.Encrypted.Nonce)
		if err != nil {
			t.Fatalf("decode nonce: %v", err)
		}
		nonceBytes[0] ^= 0xFF
		env.Encrypted.Nonce = base64.StdEncoding.EncodeToString(nonceBytes)
	})
	publishRawGroupEnvelope(t, nodeA, groupId, tamperedNonceEnvelope)
	decryptFailures := waitForCollectedEventCount(t, nodeBCapture, "group:decryption_failed", 1, 5*time.Second)
	if got := decryptFailures[0]["groupId"]; got != groupId {
		t.Fatalf("nonce failure groupId = %v, want %q", got, groupId)
	}
	if got := int(decryptFailures[0]["keyEpoch"].(float64)); got != keyInfo.KeyEpoch {
		t.Fatalf("nonce failure keyEpoch = %d, want %d", got, keyInfo.KeyEpoch)
	}

	ciphertextEnvelope := buildTestEnvelope(
		t,
		groupId,
		senderPeerId,
		senderPrivB64,
		senderPubB64,
		groupKey,
		keyInfo.KeyEpoch,
		"SV-005 tampered ciphertext should not deliver",
	)
	tamperedCiphertextEnvelope := mutateAndResignGroupEnvelope(t, ciphertextEnvelope, senderPrivB64, func(env *internal.GroupEnvelope) {
		ciphertextBytes, err := base64.StdEncoding.DecodeString(env.Encrypted.Ciphertext)
		if err != nil {
			t.Fatalf("decode ciphertext: %v", err)
		}
		ciphertextBytes[0] ^= 0xFF
		env.Encrypted.Ciphertext = base64.StdEncoding.EncodeToString(ciphertextBytes)
	})
	publishRawGroupEnvelope(t, nodeA, groupId, tamperedCiphertextEnvelope)
	decryptFailures = waitForCollectedEventCount(t, nodeBCapture, "group:decryption_failed", 2, 5*time.Second)
	if got := decryptFailures[1]["groupId"]; got != groupId {
		t.Fatalf("ciphertext failure groupId = %v, want %q", got, groupId)
	}
	if got := int(decryptFailures[1]["keyEpoch"].(float64)); got != keyInfo.KeyEpoch {
		t.Fatalf("ciphertext failure keyEpoch = %d, want %d", got, keyInfo.KeyEpoch)
	}

	if received := nodeBCapture.collectEvents("group_message:received"); len(received) != 0 {
		t.Fatalf("group_message:received before valid follow-up = %d, want 0: %#v", len(received), received)
	}

	validText := "SV-005 valid delivery after tampered envelopes"
	validEnvelope := buildTestEnvelope(
		t,
		groupId,
		senderPeerId,
		senderPrivB64,
		senderPubB64,
		groupKey,
		keyInfo.KeyEpoch,
		validText,
	)
	publishRawGroupEnvelope(t, nodeA, groupId, validEnvelope)

	received := waitForCollectedEventCount(t, nodeBCapture, "group_message:received", 1, 5*time.Second)
	if got := received[0]["text"]; got != validText {
		t.Fatalf("valid follow-up text = %v, want %q", got, validText)
	}
	if got := received[0]["senderId"]; got != senderPeerId {
		t.Fatalf("valid follow-up senderId = %v, want %q", got, senderPeerId)
	}
	if got := int(received[0]["keyEpoch"].(float64)); got != keyInfo.KeyEpoch {
		t.Fatalf("valid follow-up keyEpoch = %d, want %d", got, keyInfo.KeyEpoch)
	}
}
