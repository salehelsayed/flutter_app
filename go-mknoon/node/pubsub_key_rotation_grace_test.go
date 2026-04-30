package node

import (
	"encoding/json"
	"strings"
	"testing"
	"time"

	mcrypto "github.com/mknoon/go-mknoon/crypto"
)

func hasCollectedEventName(events []string, eventName string) bool {
	for _, raw := range events {
		var ev map[string]interface{}
		if err := json.Unmarshal([]byte(raw), &ev); err != nil {
			continue
		}
		if got, _ := ev["event"].(string); got == eventName {
			return true
		}
	}
	return false
}

func TestGroupTopicValidator_AcceptsPreviousEpochDuringGrace(t *testing.T) {
	priv, pub := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	groupId := "group-prev-epoch-grace"
	config := &GroupConfig{
		Name:      "Grace Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: "peer-1", Role: GroupRoleAdmin, PublicKey: pub},
		},
		CreatedBy: "peer-1",
	}

	envelope := buildTestEnvelope(t, groupId, "peer-1", priv, pub, groupKey, 1, "old epoch")
	keyInfo := buildGroupKeyInfoWithGrace(
		"current-key-b64",
		2,
		groupKey,
		1,
		time.Now().Add(KeyRotationGracePeriod),
	)

	result := validateGroupEnvelope(envelope, groupId, config, keyInfo)
	if result != "accept" {
		t.Fatalf("expected accept during grace, got %s", result)
	}
}

func TestGroupTopicValidator_RejectsPreviousEpochAfterGraceExpires(t *testing.T) {
	priv, pub := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	groupId := "group-prev-epoch-expired"
	config := &GroupConfig{
		Name:      "Expired Grace Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: "peer-1", Role: GroupRoleAdmin, PublicKey: pub},
		},
		CreatedBy: "peer-1",
	}

	envelope := buildTestEnvelope(t, groupId, "peer-1", priv, pub, groupKey, 1, "old epoch")
	keyInfo := buildGroupKeyInfoWithGrace(
		"current-key-b64",
		2,
		groupKey,
		1,
		time.Now().Add(-time.Second),
	)

	result := validateGroupEnvelope(envelope, groupId, config, keyInfo)
	if result != "reject:bad_signature" {
		t.Fatalf("expected reject:bad_signature after grace expiry, got %s", result)
	}
}

func TestGroupTopicValidator_AcceptsCurrentEpochDuringGrace(t *testing.T) {
	priv, pub := generateEd25519KeyPair(t)
	currentKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate current key: %v", err)
	}
	prevKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate prev key: %v", err)
	}

	groupId := "group-current-epoch-grace"
	config := &GroupConfig{
		Name:      "Current Epoch Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: "peer-1", Role: GroupRoleAdmin, PublicKey: pub},
		},
		CreatedBy: "peer-1",
	}

	envelope := buildTestEnvelope(t, groupId, "peer-1", priv, pub, currentKey, 2, "current epoch")
	keyInfo := buildGroupKeyInfoWithGrace(
		currentKey,
		2,
		prevKey,
		1,
		time.Now().Add(KeyRotationGracePeriod),
	)

	result := validateGroupEnvelope(envelope, groupId, config, keyInfo)
	if result != "accept" {
		t.Fatalf("expected accept for current epoch during grace, got %s", result)
	}
}

func TestGroupTopicValidator_RejectsRemovedSenderPreviousEpochDuringGrace(t *testing.T) {
	_, adminPub := generateEd25519KeyPair(t)
	removedPriv, removedPub := generateEd25519KeyPair(t)
	currentKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate current key: %v", err)
	}
	prevKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate previous key: %v", err)
	}

	groupId := "group-removed-prev-epoch-grace"
	config := &GroupConfig{
		Name:      "Removed Previous Epoch Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: "peer-admin", Role: GroupRoleAdmin, PublicKey: adminPub},
		},
		CreatedBy: "peer-admin",
	}

	envelope := buildTestEnvelope(
		t,
		groupId,
		"peer-removed",
		removedPriv,
		removedPub,
		prevKey,
		1,
		"removed sender old epoch",
	)
	keyInfo := buildGroupKeyInfoWithGrace(
		currentKey,
		2,
		prevKey,
		1,
		time.Now().Add(KeyRotationGracePeriod),
	)

	result := validateGroupEnvelope(envelope, groupId, config, keyInfo)
	if result != "reject:non_member" {
		t.Fatalf("expected reject:non_member for removed sender during grace, got %s", result)
	}
}

func TestGroupTopicValidator_RejectsUnknownFutureEpochBeforeDelivery(t *testing.T) {
	priv, pub := generateEd25519KeyPair(t)
	currentKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate current key: %v", err)
	}
	futureKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate future key: %v", err)
	}

	groupId := "group-future-epoch-reject"
	config := &GroupConfig{
		Name:      "Future Epoch Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: "peer-1", Role: GroupRoleAdmin, PublicKey: pub},
		},
		CreatedBy: "peer-1",
	}

	envelope := buildTestEnvelope(
		t,
		groupId,
		"peer-1",
		priv,
		pub,
		futureKey,
		2,
		"future epoch message",
	)
	keyInfo := &GroupKeyInfo{Key: currentKey, KeyEpoch: 1}

	result := validateGroupEnvelope(envelope, groupId, config, keyInfo)
	if result != "reject:bad_signature" {
		t.Fatalf("expected reject:bad_signature for unknown future epoch, got %s", result)
	}
}

func TestUpdateGroupKey_PreservesPreviousKeyAndGraceDeadline(t *testing.T) {
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

	groupId := "group-update-preserve-prev"
	initialKey := &GroupKeyInfo{Key: "key-A", KeyEpoch: 1}
	if err := n.JoinGroupTopic(groupId, testGroupConfig(GroupTypeChat), initialKey); err != nil {
		t.Fatalf("JoinGroupTopic: %v", err)
	}

	before := time.Now()
	n.UpdateGroupKey(groupId, &GroupKeyInfo{Key: "key-B", KeyEpoch: 2})
	after := time.Now()

	got := n.GetGroupKeyInfo(groupId)
	if got == nil {
		t.Fatal("expected non-nil key info after update")
	}
	if got.Key != "key-B" || got.KeyEpoch != 2 {
		t.Fatalf("expected current key epoch 2/key-B, got epoch=%d key=%q", got.KeyEpoch, got.Key)
	}
	if got.PrevKey != "key-A" || got.PrevKeyEpoch != 1 {
		t.Fatalf("expected previous key epoch 1/key-A, got prevEpoch=%d prevKey=%q", got.PrevKeyEpoch, got.PrevKey)
	}
	minDeadline := before.Add(KeyRotationGracePeriod - time.Second)
	maxDeadline := after.Add(KeyRotationGracePeriod + time.Second)
	if got.GraceDeadline.Before(minDeadline) || got.GraceDeadline.After(maxDeadline) {
		t.Fatalf("grace deadline %v outside expected range [%v, %v]", got.GraceDeadline, minDeadline, maxDeadline)
	}
}

func TestJoinGroupTopic_InitialKeyHasNoGraceState(t *testing.T) {
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

	groupId := "group-initial-no-grace"
	initialKey := &GroupKeyInfo{Key: "key-A", KeyEpoch: 1}
	if err := n.JoinGroupTopic(groupId, testGroupConfig(GroupTypeChat), initialKey); err != nil {
		t.Fatalf("JoinGroupTopic: %v", err)
	}

	got := n.GetGroupKeyInfo(groupId)
	if got == nil {
		t.Fatal("expected non-nil key info after join")
	}
	if got.PrevKey != "" {
		t.Fatalf("expected empty PrevKey on initial join, got %q", got.PrevKey)
	}
	if got.PrevKeyEpoch != 0 {
		t.Fatalf("expected PrevKeyEpoch=0 on initial join, got %d", got.PrevKeyEpoch)
	}
	if !got.GraceDeadline.IsZero() {
		t.Fatalf("expected zero GraceDeadline on initial join, got %v", got.GraceDeadline)
	}
}

func TestHandleGroupSubscription_DecryptsPreviousEpochDuringGrace(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	oldGroupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate old group key: %v", err)
	}
	newGroupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate new group key: %v", err)
	}

	nodeA := startLocalNodeForMultiRelayTest(t)
	nodeB := startLocalNodeForMultiRelayTest(t)

	groupId := "group-decrypt-prev-grace"
	senderPeerId := nodeA.PeerId()
	config := &GroupConfig{
		Name:      "Decrypt During Grace Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderPeerId, Role: GroupRoleAdmin, PublicKey: senderPubB64},
		},
		CreatedBy: senderPeerId,
	}

	if err := nodeA.JoinGroupTopic(groupId, config, &GroupKeyInfo{Key: oldGroupKey, KeyEpoch: 1}); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, config, &GroupKeyInfo{Key: oldGroupKey, KeyEpoch: 1}); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}
	nodeB.UpdateGroupKey(groupId, &GroupKeyInfo{Key: newGroupKey, KeyEpoch: 2})

	nodeBCapture := &testEventCollector{}
	nodeB.eventCallback = nodeBCapture

	connectLocalGroupNodes(t, nodeA, nodeB)

	envelopeJSON := buildTestEnvelope(
		t,
		groupId,
		senderPeerId,
		senderPrivB64,
		senderPubB64,
		oldGroupKey,
		1,
		"old epoch still decrypts",
	)
	publishRawGroupEnvelope(t, nodeA, groupId, envelopeJSON)

	data := waitForCollectedEvent(t, nodeBCapture, "group_message:received", 5*time.Second)
	if got := data["groupId"]; got != groupId {
		t.Fatalf("groupId = %v, want %q", got, groupId)
	}
	if got := data["senderId"]; got != senderPeerId {
		t.Fatalf("senderId = %v, want %q", got, senderPeerId)
	}
	if got := data["text"]; got != "old epoch still decrypts" {
		t.Fatalf("text = %v, want %q", got, "old epoch still decrypts")
	}

	events := nodeBCapture.snapshot()
	if hasCollectedEventName(events, "group:decryption_failed") {
		t.Fatal("group:decryption_failed should not be emitted when previous epoch decrypts during grace")
	}
	for _, raw := range events {
		if strings.Contains(raw, `"event":"group_message:received"`) {
			return
		}
	}
	t.Fatal("expected group_message:received event during grace-period decrypt")
}

func TestHandleGroupSubscription_DropsPreviousEpochAfterGraceExpires(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	oldGroupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate old group key: %v", err)
	}
	newGroupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate new group key: %v", err)
	}

	nodeA := startLocalNodeForMultiRelayTest(t)
	nodeB := startLocalNodeForMultiRelayTest(t)

	groupId := "group-decrypt-prev-expired"
	senderPeerId := nodeA.PeerId()
	config := &GroupConfig{
		Name:      "Expired Grace Delivery Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderPeerId, Role: GroupRoleAdmin, PublicKey: senderPubB64},
		},
		CreatedBy: senderPeerId,
	}

	if err := nodeA.JoinGroupTopic(groupId, config, &GroupKeyInfo{Key: oldGroupKey, KeyEpoch: 1}); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, config, &GroupKeyInfo{Key: oldGroupKey, KeyEpoch: 1}); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}
	nodeB.UpdateGroupKey(groupId, &GroupKeyInfo{Key: newGroupKey, KeyEpoch: 2})
	nodeB.groupKeys[groupId].GraceDeadline = time.Now().Add(-time.Second)

	nodeBCapture := &testEventCollector{}
	nodeB.eventCallback = nodeBCapture

	connectLocalGroupNodes(t, nodeA, nodeB)

	envelopeJSON := buildTestEnvelope(
		t,
		groupId,
		senderPeerId,
		senderPrivB64,
		senderPubB64,
		oldGroupKey,
		1,
		"old epoch should now be stale",
	)
	publishRawGroupEnvelope(t, nodeA, groupId, envelopeJSON)

	time.Sleep(500 * time.Millisecond)

	events := nodeBCapture.snapshot()
	if hasCollectedEventName(events, "group_message:received") {
		t.Fatal("group_message:received should not be emitted after grace expiry")
	}
	if hasCollectedEventName(events, "group:decryption_failed") {
		t.Fatal("group:decryption_failed should not be emitted when stale old-epoch traffic is rejected by the validator")
	}
}
