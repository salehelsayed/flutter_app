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

func TestGL013UpdateGroupKeyNilRemovesKeyAndDisablesSendAndValidator(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	n := startLocalNodeForMultiRelayTest(t)
	collector := &testEventCollector{}
	n.eventCallback = collector

	groupId := "gl013-key-removal-disables-send-validator"
	senderPeerId := n.PeerId()
	senderPID, err := peer.Decode(senderPeerId)
	if err != nil {
		t.Fatalf("decode sender peer id: %v", err)
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 13}
	config := &GroupConfig{
		Name:      "GL013 Key Removal",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderPeerId, Role: GroupRoleAdmin, PublicKey: senderPubB64},
		},
		CreatedBy: senderPeerId,
	}

	if err := n.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("JoinGroupTopic: %v", err)
	}
	if got := n.GetGroupKeyInfo(groupId); got == nil {
		t.Fatal("expected key info after join")
	}

	validEnvelope := buildTestEnvelope(
		t,
		groupId,
		senderPeerId,
		senderPrivB64,
		senderPubB64,
		groupKey,
		keyInfo.KeyEpoch,
		"GL013 valid envelope before local key removal",
	)

	n.UpdateGroupKey(groupId, nil)

	if got := n.GetGroupKeyInfo(groupId); got != nil {
		t.Fatalf("GetGroupKeyInfo after nil update = %#v, want nil", got)
	}

	msgID, peerCount, publishErr := n.PublishGroupMessage(
		groupId,
		senderPrivB64,
		senderPeerId,
		senderPubB64,
		"Admin",
		"GL013 publish after key removal",
		"",
		nil,
	)
	if publishErr == nil {
		t.Fatal("expected PublishGroupMessage after key removal to fail")
	}
	if !strings.Contains(publishErr.Error(), "group not joined") && !strings.Contains(publishErr.Error(), "missing key") {
		t.Fatalf("PublishGroupMessage error = %q, want group not joined or missing key", publishErr.Error())
	}
	if msgID != "" || peerCount != 0 {
		t.Fatalf("PublishGroupMessage returned msgID=%q peerCount=%d, want empty/0", msgID, peerCount)
	}

	reactionErr := n.PublishGroupReaction(
		groupId,
		senderPrivB64,
		senderPeerId,
		senderPubB64,
		`{"messageId":"gl013-message","emoji":"+1","action":"add"}`,
	)
	if reactionErr == nil {
		t.Fatal("expected PublishGroupReaction after key removal to fail")
	}
	if !strings.Contains(reactionErr.Error(), "group not joined") && !strings.Contains(reactionErr.Error(), "missing key") {
		t.Fatalf("PublishGroupReaction error = %q, want group not joined or missing key", reactionErr.Error())
	}

	validator := n.groupTopicValidator(groupId)
	msg := &pubsub.Message{Message: &pb.Message{Data: []byte(validEnvelope)}}
	baseline := len(collector.snapshot())
	if result := validator(context.Background(), senderPID, msg); result != pubsub.ValidationReject {
		t.Fatalf("validator after key removal = %v, want ValidationReject", result)
	}
	waitForCollectedValidationReject(t, collector, baseline, "missing_key", keyInfo.KeyEpoch, time.Second)
}

func TestUpdateGroupKey_IgnoresSameEpochDifferentMaterial(t *testing.T) {
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

	groupId := "group-update-ignore-same-epoch"
	initialKey := &GroupKeyInfo{Key: "key-A", KeyEpoch: 1}
	if err := n.JoinGroupTopic(groupId, testGroupConfig(GroupTypeChat), initialKey); err != nil {
		t.Fatalf("JoinGroupTopic: %v", err)
	}
	n.UpdateGroupKey(groupId, &GroupKeyInfo{Key: "key-B", KeyEpoch: 2})
	before := n.GetGroupKeyInfo(groupId)
	if before == nil {
		t.Fatal("expected non-nil key info after current update")
	}

	n.UpdateGroupKey(groupId, &GroupKeyInfo{Key: "key-C", KeyEpoch: 2})

	got := n.GetGroupKeyInfo(groupId)
	if got == nil {
		t.Fatal("expected non-nil key info after same-epoch update")
	}
	if got.Key != "key-B" || got.KeyEpoch != 2 {
		t.Fatalf("expected current key epoch 2/key-B, got epoch=%d key=%q", got.KeyEpoch, got.Key)
	}
	if got.PrevKey != "key-A" || got.PrevKeyEpoch != 1 {
		t.Fatalf("expected previous key epoch 1/key-A, got prevEpoch=%d prevKey=%q", got.PrevKeyEpoch, got.PrevKey)
	}
	if !got.GraceDeadline.Equal(before.GraceDeadline) {
		t.Fatalf("same-epoch update changed grace deadline from %v to %v", before.GraceDeadline, got.GraceDeadline)
	}
}

func TestUpdateGroupKey_IgnoresOlderEpochAfterCurrent(t *testing.T) {
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

	groupId := "group-update-ignore-older-epoch"
	initialKey := &GroupKeyInfo{Key: "key-A", KeyEpoch: 1}
	if err := n.JoinGroupTopic(groupId, testGroupConfig(GroupTypeChat), initialKey); err != nil {
		t.Fatalf("JoinGroupTopic: %v", err)
	}
	n.UpdateGroupKey(groupId, &GroupKeyInfo{Key: "key-B", KeyEpoch: 2})
	before := n.GetGroupKeyInfo(groupId)
	if before == nil {
		t.Fatal("expected non-nil key info after current update")
	}

	n.UpdateGroupKey(groupId, &GroupKeyInfo{Key: "stale-key-A", KeyEpoch: 1})

	got := n.GetGroupKeyInfo(groupId)
	if got == nil {
		t.Fatal("expected non-nil key info after older update")
	}
	if got.Key != "key-B" || got.KeyEpoch != 2 {
		t.Fatalf("expected current key epoch 2/key-B, got epoch=%d key=%q", got.KeyEpoch, got.Key)
	}
	if got.PrevKey != "key-A" || got.PrevKeyEpoch != 1 {
		t.Fatalf("expected previous key epoch 1/key-A, got prevEpoch=%d prevKey=%q", got.PrevKeyEpoch, got.PrevKey)
	}
	if !got.GraceDeadline.Equal(before.GraceDeadline) {
		t.Fatalf("older update changed grace deadline from %v to %v", before.GraceDeadline, got.GraceDeadline)
	}
}

func TestGL014UpdateGroupKeyIgnoresOlderEpochAndKeepsCurrentEpochDelivery(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	_, receiverPubB64 := generateEd25519KeyPair(t)
	epoch2Key, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate epoch 2 group key: %v", err)
	}
	epoch3Key, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate epoch 3 group key: %v", err)
	}
	staleEpoch2Key, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate stale epoch 2 group key: %v", err)
	}

	nodeACapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

	groupId := "gl014-stale-older-epoch-keeps-current-delivery"
	senderPeerId := nodeA.PeerId()
	config := &GroupConfig{
		Name:      "GL014 Stale Epoch Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderPeerId, Role: GroupRoleAdmin, PublicKey: senderPubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: receiverPubB64},
		},
		CreatedBy: senderPeerId,
	}
	epoch2Info := &GroupKeyInfo{Key: epoch2Key, KeyEpoch: 2}
	epoch3Info := &GroupKeyInfo{Key: epoch3Key, KeyEpoch: 3}

	if err := nodeA.JoinGroupTopic(groupId, config, epoch2Info); err != nil {
		t.Fatalf("nodeA JoinGroupTopic epoch 2: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, config, epoch2Info); err != nil {
		t.Fatalf("nodeB JoinGroupTopic epoch 2: %v", err)
	}
	nodeA.UpdateGroupKey(groupId, epoch3Info)
	nodeB.UpdateGroupKey(groupId, epoch3Info)

	assertGL014Epoch3WithPrevEpoch2 := func(label string, got *GroupKeyInfo) {
		t.Helper()
		if got == nil {
			t.Fatalf("%s GetGroupKeyInfo = nil, want epoch 3 info", label)
		}
		if got.Key != epoch3Key || got.KeyEpoch != 3 {
			t.Fatalf("%s current key/epoch = %q/%d, want epoch 3 key/3", label, got.Key, got.KeyEpoch)
		}
		if got.PrevKey != epoch2Key || got.PrevKeyEpoch != 2 {
			t.Fatalf("%s previous key/epoch = %q/%d, want original epoch 2 key/2", label, got.PrevKey, got.PrevKeyEpoch)
		}
		if got.GraceDeadline.IsZero() {
			t.Fatalf("%s GraceDeadline is zero, want previous-key grace window", label)
		}
	}
	assertGL014Unchanged := func(label string, got, before *GroupKeyInfo) {
		t.Helper()
		if got == nil {
			t.Fatalf("%s GetGroupKeyInfo = nil, want preserved epoch 3 info", label)
		}
		if got.Key != before.Key || got.KeyEpoch != before.KeyEpoch {
			t.Fatalf("%s current key/epoch changed from %q/%d to %q/%d", label, before.Key, before.KeyEpoch, got.Key, got.KeyEpoch)
		}
		if got.PrevKey != before.PrevKey || got.PrevKeyEpoch != before.PrevKeyEpoch {
			t.Fatalf("%s previous key/epoch changed from %q/%d to %q/%d", label, before.PrevKey, before.PrevKeyEpoch, got.PrevKey, got.PrevKeyEpoch)
		}
		if !got.GraceDeadline.Equal(before.GraceDeadline) {
			t.Fatalf("%s grace deadline changed from %v to %v", label, before.GraceDeadline, got.GraceDeadline)
		}
	}

	beforeA := nodeA.GetGroupKeyInfo(groupId)
	beforeB := nodeB.GetGroupKeyInfo(groupId)
	assertGL014Epoch3WithPrevEpoch2("nodeA before stale update", beforeA)
	assertGL014Epoch3WithPrevEpoch2("nodeB before stale update", beforeB)

	staleInfo := &GroupKeyInfo{Key: staleEpoch2Key, KeyEpoch: 2}
	nodeA.UpdateGroupKey(groupId, staleInfo)
	nodeB.UpdateGroupKey(groupId, staleInfo)

	afterStaleA := nodeA.GetGroupKeyInfo(groupId)
	afterStaleB := nodeB.GetGroupKeyInfo(groupId)
	assertGL014Unchanged("nodeA after stale update", afterStaleA, beforeA)
	assertGL014Unchanged("nodeB after stale update", afterStaleB, beforeB)

	connectLocalGroupNodes(t, nodeA, nodeB)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 3*time.Second)

	baselineB := len(nodeBCapture.snapshot())
	messageId := "gl014-epoch3-message"
	text := "GL014 epoch 3 delivery after stale epoch 2 update"
	msgID, peerCount, publishErr := nodeA.PublishGroupMessage(
		groupId,
		senderPrivB64,
		senderPeerId,
		senderPubB64,
		"Alice",
		text,
		messageId,
		nil,
	)
	if publishErr != nil {
		t.Fatalf("PublishGroupMessage after stale update: %v", publishErr)
	}
	if msgID != messageId {
		t.Fatalf("PublishGroupMessage message id = %q, want %q", msgID, messageId)
	}
	if peerCount < 1 {
		t.Fatalf("PublishGroupMessage peer count = %d, want >= 1", peerCount)
	}

	received := waitForCollectedEvent(t, nodeBCapture, "group_message:received", 5*time.Second)
	if got, _ := received["groupId"].(string); got != groupId {
		t.Fatalf("received groupId = %q, want %q", got, groupId)
	}
	if got, _ := received["senderId"].(string); got != senderPeerId {
		t.Fatalf("received senderId = %q, want %q", got, senderPeerId)
	}
	if got, _ := received["messageId"].(string); got != messageId {
		t.Fatalf("received messageId = %q, want %q", got, messageId)
	}
	if got, _ := received["text"].(string); got != text {
		t.Fatalf("received text = %q, want %q", got, text)
	}
	if got, ok := received["keyEpoch"].(float64); !ok || int(got) != 3 {
		t.Fatalf("received keyEpoch = %v, want 3", received["keyEpoch"])
	}

	if hasCollectedEventName(nodeBCapture.snapshot()[baselineB:], "group:decryption_failed") {
		t.Fatal("group:decryption_failed should not be emitted for epoch 3 delivery after stale epoch 2 update")
	}
	assertGL014Unchanged("nodeB after epoch 3 delivery", nodeB.GetGroupKeyInfo(groupId), beforeB)
}

func TestGL015UpdateGroupKeyIgnoresSameEpochDifferentMaterialAndKeepsEpoch3Delivery(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	_, receiverPubB64 := generateEd25519KeyPair(t)
	epoch2Key, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate epoch 2 group key: %v", err)
	}
	epoch3K1, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate epoch 3 K1 group key: %v", err)
	}
	epoch3K2, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate epoch 3 K2 group key: %v", err)
	}
	if epoch3K1 == epoch3K2 {
		t.Fatal("generated epoch 3 K1 and K2 are identical; test requires different material")
	}

	nodeACapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

	groupId := "gl015-same-epoch-different-material-keeps-current-delivery"
	senderPeerId := nodeA.PeerId()
	config := &GroupConfig{
		Name:      "GL015 Same Epoch Conflict Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderPeerId, Role: GroupRoleAdmin, PublicKey: senderPubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: receiverPubB64},
		},
		CreatedBy: senderPeerId,
	}
	epoch2Info := &GroupKeyInfo{Key: epoch2Key, KeyEpoch: 2}
	epoch3K1Info := &GroupKeyInfo{Key: epoch3K1, KeyEpoch: 3}

	if err := nodeA.JoinGroupTopic(groupId, config, epoch2Info); err != nil {
		t.Fatalf("nodeA JoinGroupTopic epoch 2: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, config, epoch2Info); err != nil {
		t.Fatalf("nodeB JoinGroupTopic epoch 2: %v", err)
	}
	nodeA.UpdateGroupKey(groupId, epoch3K1Info)
	nodeB.UpdateGroupKey(groupId, epoch3K1Info)

	assertGL015Epoch3K1WithPrevEpoch2 := func(label string, got *GroupKeyInfo) {
		t.Helper()
		if got == nil {
			t.Fatalf("%s GetGroupKeyInfo = nil, want epoch 3 K1 info", label)
		}
		if got.Key != epoch3K1 || got.KeyEpoch != 3 {
			t.Fatalf("%s current key/epoch = %q/%d, want epoch 3 K1/3", label, got.Key, got.KeyEpoch)
		}
		if got.PrevKey != epoch2Key || got.PrevKeyEpoch != 2 {
			t.Fatalf("%s previous key/epoch = %q/%d, want original epoch 2 key/2", label, got.PrevKey, got.PrevKeyEpoch)
		}
		if got.GraceDeadline.IsZero() {
			t.Fatalf("%s GraceDeadline is zero, want previous-key grace window", label)
		}
	}
	assertGL015Unchanged := func(label string, got, before *GroupKeyInfo) {
		t.Helper()
		if got == nil {
			t.Fatalf("%s GetGroupKeyInfo = nil, want preserved epoch 3 K1 info", label)
		}
		if got.Key != before.Key || got.KeyEpoch != before.KeyEpoch {
			t.Fatalf("%s current key/epoch changed from %q/%d to %q/%d", label, before.Key, before.KeyEpoch, got.Key, got.KeyEpoch)
		}
		if got.PrevKey != before.PrevKey || got.PrevKeyEpoch != before.PrevKeyEpoch {
			t.Fatalf("%s previous key/epoch changed from %q/%d to %q/%d", label, before.PrevKey, before.PrevKeyEpoch, got.PrevKey, got.PrevKeyEpoch)
		}
		if !got.GraceDeadline.Equal(before.GraceDeadline) {
			t.Fatalf("%s grace deadline changed from %v to %v", label, before.GraceDeadline, got.GraceDeadline)
		}
	}

	beforeA := nodeA.GetGroupKeyInfo(groupId)
	beforeB := nodeB.GetGroupKeyInfo(groupId)
	assertGL015Epoch3K1WithPrevEpoch2("nodeA before same-epoch conflict", beforeA)
	assertGL015Epoch3K1WithPrevEpoch2("nodeB before same-epoch conflict", beforeB)

	conflictingEpoch3Info := &GroupKeyInfo{Key: epoch3K2, KeyEpoch: 3}
	nodeA.UpdateGroupKey(groupId, conflictingEpoch3Info)
	nodeB.UpdateGroupKey(groupId, conflictingEpoch3Info)

	afterConflictA := nodeA.GetGroupKeyInfo(groupId)
	afterConflictB := nodeB.GetGroupKeyInfo(groupId)
	assertGL015Unchanged("nodeA after same-epoch conflict", afterConflictA, beforeA)
	assertGL015Unchanged("nodeB after same-epoch conflict", afterConflictB, beforeB)

	connectLocalGroupNodes(t, nodeA, nodeB)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 3*time.Second)

	baselineB := len(nodeBCapture.snapshot())
	messageId := "gl015-epoch3-message"
	text := "GL015 epoch 3 delivery after same-epoch K2 update"
	msgID, peerCount, publishErr := nodeA.PublishGroupMessage(
		groupId,
		senderPrivB64,
		senderPeerId,
		senderPubB64,
		"Alice",
		text,
		messageId,
		nil,
	)
	if publishErr != nil {
		t.Fatalf("PublishGroupMessage after same-epoch conflict: %v", publishErr)
	}
	if msgID != messageId {
		t.Fatalf("PublishGroupMessage message id = %q, want %q", msgID, messageId)
	}
	if peerCount < 1 {
		t.Fatalf("PublishGroupMessage peer count = %d, want >= 1", peerCount)
	}

	received := waitForCollectedEvent(t, nodeBCapture, "group_message:received", 5*time.Second)
	if got, _ := received["groupId"].(string); got != groupId {
		t.Fatalf("received groupId = %q, want %q", got, groupId)
	}
	if got, _ := received["senderId"].(string); got != senderPeerId {
		t.Fatalf("received senderId = %q, want %q", got, senderPeerId)
	}
	if got, _ := received["messageId"].(string); got != messageId {
		t.Fatalf("received messageId = %q, want %q", got, messageId)
	}
	if got, _ := received["text"].(string); got != text {
		t.Fatalf("received text = %q, want %q", got, text)
	}
	if got, ok := received["keyEpoch"].(float64); !ok || int(got) != 3 {
		t.Fatalf("received keyEpoch = %v, want 3", received["keyEpoch"])
	}

	if hasCollectedEventName(nodeBCapture.snapshot()[baselineB:], "group:decryption_failed") {
		t.Fatal("group:decryption_failed should not be emitted for epoch 3 delivery after same-epoch K2 update")
	}
	assertGL015Unchanged("nodeB after epoch 3 delivery", nodeB.GetGroupKeyInfo(groupId), beforeB)
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
