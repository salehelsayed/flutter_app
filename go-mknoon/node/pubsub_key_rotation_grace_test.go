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

func TestGK017GroupTopicValidatorRejectsPreviousEpochAfterGraceDeadline(t *testing.T) {
	priv, pub := generateEd25519KeyPair(t)
	prevKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate previous group key: %v", err)
	}
	currentKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate current group key: %v", err)
	}

	groupId := "gk017-prev-epoch-expired-validator"
	senderId := "peer-gk017-validator"
	config := &GroupConfig{
		Name:      "GK017 Expired Previous Epoch",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderId, Role: GroupRoleAdmin, PublicKey: pub},
		},
		CreatedBy: senderId,
	}
	envelope := buildTestEnvelope(t, groupId, senderId, priv, pub, prevKey, 1, "stale epoch after grace")

	now := time.Now()
	liveGrace := buildGroupKeyInfoWithGrace(
		currentKey,
		2,
		prevKey,
		1,
		now.Add(KeyRotationGracePeriod),
	)
	if result := validateGroupEnvelope(envelope, groupId, config, liveGrace); result != "accept" {
		t.Fatalf("expected previous epoch accept during live grace control, got %s", result)
	}

	expiredGrace := buildGroupKeyInfoWithGrace(
		currentKey,
		2,
		prevKey,
		1,
		now.Add(-time.Second),
	)
	if result := validateGroupEnvelope(envelope, groupId, config, expiredGrace); result != "reject:bad_signature" {
		t.Fatalf("expected reject:bad_signature after grace deadline, got %s", result)
	}

	withoutPrevKey := buildGroupKeyInfoWithGrace(
		currentKey,
		2,
		"",
		1,
		now.Add(KeyRotationGracePeriod),
	)
	if result := validateGroupEnvelope(envelope, groupId, config, withoutPrevKey); result != "reject:bad_signature" {
		t.Fatalf("expected reject:bad_signature without previous key material, got %s", result)
	}

	withoutDeadline := buildGroupKeyInfoWithGrace(
		currentKey,
		2,
		prevKey,
		1,
		time.Time{},
	)
	if result := validateGroupEnvelope(envelope, groupId, config, withoutDeadline); result != "reject:bad_signature" {
		t.Fatalf("expected reject:bad_signature without grace deadline, got %s", result)
	}
}

func TestGK017DecryptGroupEnvelopePayloadRejectsPreviousEpochAfterGraceDeadline(t *testing.T) {
	priv, pub := generateEd25519KeyPair(t)
	prevKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate previous group key: %v", err)
	}
	currentKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate current group key: %v", err)
	}

	groupId := "gk017-prev-epoch-expired-decrypt"
	text := "stale decrypt after grace"
	envelopeJSON := buildTestEnvelope(t, groupId, "peer-gk017-decrypt", priv, pub, prevKey, 1, text)
	env, err := internal.ParseGroupEnvelope(envelopeJSON)
	if err != nil {
		t.Fatalf("parse envelope: %v", err)
	}

	now := time.Now()
	liveGrace := buildGroupKeyInfoWithGrace(
		currentKey,
		2,
		prevKey,
		1,
		now.Add(KeyRotationGracePeriod),
	)
	plaintext, err := decryptGroupEnvelopePayload(env, liveGrace, now)
	if err != nil {
		t.Fatalf("expected previous epoch decrypt during live grace control: %v", err)
	}
	if !strings.Contains(plaintext, text) {
		t.Fatalf("live grace plaintext %q does not contain %q", plaintext, text)
	}

	expiredGrace := buildGroupKeyInfoWithGrace(
		currentKey,
		2,
		prevKey,
		1,
		now.Add(-time.Second),
	)
	plaintext, err = decryptGroupEnvelopePayload(env, expiredGrace, now)
	if err == nil {
		t.Fatalf("expected decrypt after grace deadline to fail, got plaintext %q", plaintext)
	}
	if !strings.Contains(err.Error(), "no group key available for epoch 1") {
		t.Fatalf("decrypt error = %q, want no group key available for epoch 1", err.Error())
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

func TestGK018GroupTopicValidatorAcceptsCurrentEpochAfterGraceDeadline(t *testing.T) {
	priv, pub := generateEd25519KeyPair(t)
	prevKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate previous group key: %v", err)
	}
	currentKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate current group key: %v", err)
	}
	if currentKey == prevKey {
		t.Fatal("generated current and previous group keys are identical; test requires distinct material")
	}

	groupId := "gk018-current-epoch-expired-validator"
	senderId := "peer-gk018-validator"
	config := &GroupConfig{
		Name:      "GK018 Current Epoch Expired Grace",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderId, Role: GroupRoleAdmin, PublicKey: pub},
		},
		CreatedBy: senderId,
	}

	envelope := buildTestEnvelope(t, groupId, senderId, priv, pub, currentKey, 2, "current epoch after grace")
	expiredGrace := buildGroupKeyInfoWithGrace(
		currentKey,
		2,
		prevKey,
		1,
		time.Now().Add(-time.Second),
	)

	if result := validateGroupEnvelope(envelope, groupId, config, expiredGrace); result != "accept" {
		t.Fatalf("expected current epoch accept after expired previous-key grace, got %s", result)
	}
}

func TestGK018DecryptGroupEnvelopePayloadAcceptsCurrentEpochAfterGraceDeadline(t *testing.T) {
	priv, pub := generateEd25519KeyPair(t)
	prevKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate previous group key: %v", err)
	}
	currentKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate current group key: %v", err)
	}
	if currentKey == prevKey {
		t.Fatal("generated current and previous group keys are identical; test requires distinct material")
	}

	groupId := "gk018-current-epoch-expired-decrypt"
	text := "current decrypt after grace"
	envelopeJSON := buildTestEnvelope(t, groupId, "peer-gk018-decrypt", priv, pub, currentKey, 2, text)
	env, err := internal.ParseGroupEnvelope(envelopeJSON)
	if err != nil {
		t.Fatalf("parse envelope: %v", err)
	}

	now := time.Now()
	expiredGrace := buildGroupKeyInfoWithGrace(
		currentKey,
		2,
		prevKey,
		1,
		now.Add(-time.Second),
	)
	plaintext, err := decryptGroupEnvelopePayload(env, expiredGrace, now)
	if err != nil {
		t.Fatalf("expected current epoch decrypt after expired previous-key grace: %v", err)
	}
	if !strings.Contains(plaintext, text) {
		t.Fatalf("plaintext %q does not contain %q", plaintext, text)
	}
}

func TestGK019GroupTopicValidatorAcceptsOnlyEpoch0GraceAndCurrentEpoch2ForDirectJump(t *testing.T) {
	priv, pub := generateEd25519KeyPair(t)
	epoch0Key, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate epoch 0 key: %v", err)
	}
	epoch1Key, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate epoch 1 key: %v", err)
	}
	epoch2Key, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate epoch 2 key: %v", err)
	}

	groupId := "gk019-direct-jump-validator"
	senderId := "peer-gk019-validator"
	config := &GroupConfig{
		Name:      "GK019 Direct Jump Validator",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderId, Role: GroupRoleAdmin, PublicKey: pub},
		},
		CreatedBy: senderId,
	}
	envelopes := map[int]string{
		0: buildTestEnvelope(t, groupId, senderId, priv, pub, epoch0Key, 0, "epoch 0 grace after direct jump"),
		1: buildTestEnvelope(t, groupId, senderId, priv, pub, epoch1Key, 1, "epoch 1 unsupported skipped key"),
		2: buildTestEnvelope(t, groupId, senderId, priv, pub, epoch2Key, 2, "epoch 2 current after direct jump"),
	}

	liveKeyInfo := gk019DirectJumpKeyInfo(t, groupId, epoch0Key, epoch1Key, epoch2Key)
	expiredKeyInfo := *liveKeyInfo
	expiredKeyInfo.GraceDeadline = time.Now().Add(-time.Second)

	cases := []struct {
		name    string
		keyInfo *GroupKeyInfo
		epoch   int
		want    string
	}{
		{name: "live epoch 0 previous grace", keyInfo: liveKeyInfo, epoch: 0, want: "accept"},
		{name: "live epoch 1 skipped unsupported", keyInfo: liveKeyInfo, epoch: 1, want: "reject:bad_signature"},
		{name: "live epoch 2 current", keyInfo: liveKeyInfo, epoch: 2, want: "accept"},
		{name: "expired epoch 0 previous grace", keyInfo: &expiredKeyInfo, epoch: 0, want: "reject:bad_signature"},
		{name: "expired epoch 1 skipped unsupported", keyInfo: &expiredKeyInfo, epoch: 1, want: "reject:bad_signature"},
		{name: "expired epoch 2 current", keyInfo: &expiredKeyInfo, epoch: 2, want: "accept"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if result := validateGroupEnvelope(envelopes[tc.epoch], groupId, config, tc.keyInfo); result != tc.want {
				t.Fatalf("validator result = %s, want %s", result, tc.want)
			}
		})
	}
}

func TestGK019DecryptGroupEnvelopePayloadAcceptsOnlyEpoch0GraceAndCurrentEpoch2ForDirectJump(t *testing.T) {
	priv, pub := generateEd25519KeyPair(t)
	epoch0Key, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate epoch 0 key: %v", err)
	}
	epoch1Key, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate epoch 1 key: %v", err)
	}
	epoch2Key, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate epoch 2 key: %v", err)
	}

	groupId := "gk019-direct-jump-decrypt"
	senderId := "peer-gk019-decrypt"
	textByEpoch := map[int]string{
		0: "epoch 0 decrypts under direct jump grace",
		1: "epoch 1 remains unsupported after direct jump",
		2: "epoch 2 decrypts as current after direct jump",
	}
	envelopes := map[int]*internal.GroupEnvelope{}
	for epoch, key := range map[int]string{0: epoch0Key, 1: epoch1Key, 2: epoch2Key} {
		envelopeJSON := buildTestEnvelope(t, groupId, senderId, priv, pub, key, epoch, textByEpoch[epoch])
		env, err := internal.ParseGroupEnvelope(envelopeJSON)
		if err != nil {
			t.Fatalf("parse epoch %d envelope: %v", epoch, err)
		}
		envelopes[epoch] = env
	}

	now := time.Now()
	liveKeyInfo := gk019DirectJumpKeyInfo(t, groupId, epoch0Key, epoch1Key, epoch2Key)
	expiredKeyInfo := *liveKeyInfo
	expiredKeyInfo.GraceDeadline = now.Add(-time.Second)

	successCases := []struct {
		name    string
		keyInfo *GroupKeyInfo
		epoch   int
	}{
		{name: "live epoch 0 previous grace", keyInfo: liveKeyInfo, epoch: 0},
		{name: "live epoch 2 current", keyInfo: liveKeyInfo, epoch: 2},
		{name: "expired epoch 2 current", keyInfo: &expiredKeyInfo, epoch: 2},
	}
	for _, tc := range successCases {
		t.Run(tc.name, func(t *testing.T) {
			plaintext, err := decryptGroupEnvelopePayload(envelopes[tc.epoch], tc.keyInfo, now)
			if err != nil {
				t.Fatalf("decrypt epoch %d: %v", tc.epoch, err)
			}
			if !strings.Contains(plaintext, textByEpoch[tc.epoch]) {
				t.Fatalf("plaintext %q does not contain %q", plaintext, textByEpoch[tc.epoch])
			}
		})
	}

	errorCases := []struct {
		name       string
		keyInfo    *GroupKeyInfo
		epoch      int
		wantErrSub string
	}{
		{name: "live epoch 1 skipped unsupported", keyInfo: liveKeyInfo, epoch: 1, wantErrSub: "no group key available for epoch 1"},
		{name: "expired epoch 0 previous grace", keyInfo: &expiredKeyInfo, epoch: 0, wantErrSub: "no group key available for epoch 0"},
		{name: "expired epoch 1 skipped unsupported", keyInfo: &expiredKeyInfo, epoch: 1, wantErrSub: "no group key available for epoch 1"},
	}
	for _, tc := range errorCases {
		t.Run(tc.name, func(t *testing.T) {
			plaintext, err := decryptGroupEnvelopePayload(envelopes[tc.epoch], tc.keyInfo, now)
			if err == nil {
				t.Fatalf("expected decrypt epoch %d to fail, got plaintext %q", tc.epoch, plaintext)
			}
			if !strings.Contains(err.Error(), tc.wantErrSub) {
				t.Fatalf("decrypt error = %q, want substring %q", err.Error(), tc.wantErrSub)
			}
		})
	}
}

func TestGK020GroupTopicValidatorAcceptsOnlyEpoch1GraceAndCurrentEpoch2AfterSequentialRotations(t *testing.T) {
	priv, pub := generateEd25519KeyPair(t)
	epoch0Key, epoch1Key, epoch2Key := gk020GenerateDistinctEpochKeys(t)

	groupId := "gk020-sequential-rotations-validator"
	senderId := "peer-gk020-validator"
	config := &GroupConfig{
		Name:      "GK020 Sequential Rotations Validator",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderId, Role: GroupRoleAdmin, PublicKey: pub},
		},
		CreatedBy: senderId,
	}
	envelopes := map[int]string{
		0: buildTestEnvelope(t, groupId, senderId, priv, pub, epoch0Key, 0, "epoch 0 too old after sequential rotations"),
		1: buildTestEnvelope(t, groupId, senderId, priv, pub, epoch1Key, 1, "epoch 1 grace after sequential rotations"),
		2: buildTestEnvelope(t, groupId, senderId, priv, pub, epoch2Key, 2, "epoch 2 current after sequential rotations"),
	}

	liveKeyInfo := gk020SequentialRotationKeyInfo(t, groupId, epoch0Key, epoch1Key, epoch2Key)
	expiredKeyInfo := *liveKeyInfo
	expiredKeyInfo.GraceDeadline = time.Now().Add(-time.Second)

	cases := []struct {
		name    string
		keyInfo *GroupKeyInfo
		epoch   int
		want    string
	}{
		{name: "live epoch 0 too old", keyInfo: liveKeyInfo, epoch: 0, want: "reject:bad_signature"},
		{name: "live epoch 1 previous grace", keyInfo: liveKeyInfo, epoch: 1, want: "accept"},
		{name: "live epoch 2 current", keyInfo: liveKeyInfo, epoch: 2, want: "accept"},
		{name: "expired epoch 0 too old", keyInfo: &expiredKeyInfo, epoch: 0, want: "reject:bad_signature"},
		{name: "expired epoch 1 previous grace", keyInfo: &expiredKeyInfo, epoch: 1, want: "reject:bad_signature"},
		{name: "expired epoch 2 current", keyInfo: &expiredKeyInfo, epoch: 2, want: "accept"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if result := validateGroupEnvelope(envelopes[tc.epoch], groupId, config, tc.keyInfo); result != tc.want {
				t.Fatalf("validator result = %s, want %s", result, tc.want)
			}
		})
	}
}

func TestGK020DecryptGroupEnvelopePayloadAcceptsOnlyEpoch1GraceAndCurrentEpoch2AfterSequentialRotations(t *testing.T) {
	priv, pub := generateEd25519KeyPair(t)
	epoch0Key, epoch1Key, epoch2Key := gk020GenerateDistinctEpochKeys(t)

	groupId := "gk020-sequential-rotations-decrypt"
	senderId := "peer-gk020-decrypt"
	textByEpoch := map[int]string{
		0: "epoch 0 remains too old after sequential rotations",
		1: "epoch 1 decrypts under sequential rotation grace",
		2: "epoch 2 decrypts as current after sequential rotations",
	}
	envelopes := map[int]*internal.GroupEnvelope{}
	for epoch, key := range map[int]string{0: epoch0Key, 1: epoch1Key, 2: epoch2Key} {
		envelopeJSON := buildTestEnvelope(t, groupId, senderId, priv, pub, key, epoch, textByEpoch[epoch])
		env, err := internal.ParseGroupEnvelope(envelopeJSON)
		if err != nil {
			t.Fatalf("parse epoch %d envelope: %v", epoch, err)
		}
		envelopes[epoch] = env
	}

	now := time.Now()
	liveKeyInfo := gk020SequentialRotationKeyInfo(t, groupId, epoch0Key, epoch1Key, epoch2Key)
	expiredKeyInfo := *liveKeyInfo
	expiredKeyInfo.GraceDeadline = now.Add(-time.Second)

	successCases := []struct {
		name    string
		keyInfo *GroupKeyInfo
		epoch   int
	}{
		{name: "live epoch 1 previous grace", keyInfo: liveKeyInfo, epoch: 1},
		{name: "live epoch 2 current", keyInfo: liveKeyInfo, epoch: 2},
		{name: "expired epoch 2 current", keyInfo: &expiredKeyInfo, epoch: 2},
	}
	for _, tc := range successCases {
		t.Run(tc.name, func(t *testing.T) {
			plaintext, err := decryptGroupEnvelopePayload(envelopes[tc.epoch], tc.keyInfo, now)
			if err != nil {
				t.Fatalf("decrypt epoch %d: %v", tc.epoch, err)
			}
			if !strings.Contains(plaintext, textByEpoch[tc.epoch]) {
				t.Fatalf("plaintext %q does not contain %q", plaintext, textByEpoch[tc.epoch])
			}
		})
	}

	errorCases := []struct {
		name       string
		keyInfo    *GroupKeyInfo
		epoch      int
		wantErrSub string
	}{
		{name: "live epoch 0 too old", keyInfo: liveKeyInfo, epoch: 0, wantErrSub: "no group key available for epoch 0"},
		{name: "expired epoch 0 too old", keyInfo: &expiredKeyInfo, epoch: 0, wantErrSub: "no group key available for epoch 0"},
		{name: "expired epoch 1 previous grace", keyInfo: &expiredKeyInfo, epoch: 1, wantErrSub: "no group key available for epoch 1"},
	}
	for _, tc := range errorCases {
		t.Run(tc.name, func(t *testing.T) {
			plaintext, err := decryptGroupEnvelopePayload(envelopes[tc.epoch], tc.keyInfo, now)
			if err == nil {
				t.Fatalf("expected decrypt epoch %d to fail, got plaintext %q", tc.epoch, plaintext)
			}
			if !strings.Contains(err.Error(), tc.wantErrSub) {
				t.Fatalf("decrypt error = %q, want substring %q", err.Error(), tc.wantErrSub)
			}
		})
	}
}

func TestGK016GroupTopicValidatorAcceptsEpoch0PreviousKeyDuringFirstRotationGrace(t *testing.T) {
	priv, pub := generateEd25519KeyPair(t)
	epoch0Key, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate epoch 0 key: %v", err)
	}
	epoch1Key, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate epoch 1 key: %v", err)
	}

	groupId := "gk016-first-rotation-validator"
	senderId := "peer-gk016"
	config := &GroupConfig{
		Name:      "GK016 First Rotation",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderId, Role: GroupRoleAdmin, PublicKey: pub},
		},
		CreatedBy: senderId,
	}
	envelope := buildTestEnvelope(t, groupId, senderId, priv, pub, epoch0Key, 0, "epoch 0 in flight")

	liveGrace := buildGroupKeyInfoWithGrace(
		epoch1Key,
		1,
		epoch0Key,
		0,
		time.Now().Add(KeyRotationGracePeriod),
	)
	if result := validateGroupEnvelope(envelope, groupId, config, liveGrace); result != "accept" {
		t.Fatalf("expected epoch 0 accept during first rotation grace, got %s", result)
	}

	cases := []struct {
		name    string
		keyInfo *GroupKeyInfo
	}{
		{
			name: "missing previous key material",
			keyInfo: buildGroupKeyInfoWithGrace(
				epoch1Key,
				1,
				"",
				0,
				time.Now().Add(KeyRotationGracePeriod),
			),
		},
		{
			name: "zero grace deadline",
			keyInfo: buildGroupKeyInfoWithGrace(
				epoch1Key,
				1,
				epoch0Key,
				0,
				time.Time{},
			),
		},
		{
			name: "expired grace deadline",
			keyInfo: buildGroupKeyInfoWithGrace(
				epoch1Key,
				1,
				epoch0Key,
				0,
				time.Now().Add(-time.Second),
			),
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if result := validateGroupEnvelope(envelope, groupId, config, tc.keyInfo); result != "reject:bad_signature" {
				t.Fatalf("expected epoch 0 reject without explicit live grace, got %s", result)
			}
		})
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

func TestGK019UpdateGroupKeyJumpFromEpoch0To2PreservesOnlyEpoch0AsPrevious(t *testing.T) {
	epoch0Key, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate epoch 0 key: %v", err)
	}
	epoch1Key, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate epoch 1 key: %v", err)
	}
	epoch2Key, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate epoch 2 key: %v", err)
	}

	gk019DirectJumpKeyInfo(t, "gk019-update-direct-jump-state", epoch0Key, epoch1Key, epoch2Key)
}

func TestGK020UpdateGroupKeySequentialRotationsKeepsOnlyEpoch1AsPrevious(t *testing.T) {
	epoch0Key, epoch1Key, epoch2Key := gk020GenerateDistinctEpochKeys(t)

	gk020SequentialRotationKeyInfo(t, "gk020-update-sequential-rotation-state", epoch0Key, epoch1Key, epoch2Key)
}

func gk019DirectJumpKeyInfo(t *testing.T, groupId, epoch0Key, epoch1Key, epoch2Key string) *GroupKeyInfo {
	t.Helper()

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

	if err := n.JoinGroupTopic(groupId, testGroupConfig(GroupTypeChat), &GroupKeyInfo{Key: epoch0Key, KeyEpoch: 0}); err != nil {
		t.Fatalf("JoinGroupTopic: %v", err)
	}

	before := time.Now()
	n.UpdateGroupKey(groupId, &GroupKeyInfo{Key: epoch2Key, KeyEpoch: 2})
	after := time.Now()

	got := n.GetGroupKeyInfo(groupId)
	assertGK019DirectJumpKeyInfo(t, got, epoch0Key, epoch1Key, epoch2Key, before, after)
	return got
}

func assertGK019DirectJumpKeyInfo(t *testing.T, got *GroupKeyInfo, epoch0Key, epoch1Key, epoch2Key string, before, after time.Time) {
	t.Helper()

	if got == nil {
		t.Fatal("expected non-nil key info after direct 0->2 update")
	}
	if got.Key != epoch2Key || got.KeyEpoch != 2 {
		t.Fatalf("expected current epoch 2 key, got epoch=%d key=%q", got.KeyEpoch, got.Key)
	}
	if got.PrevKey != epoch0Key || got.PrevKeyEpoch != 0 {
		t.Fatalf("expected previous epoch 0 key, got prevEpoch=%d prevKey=%q", got.PrevKeyEpoch, got.PrevKey)
	}
	if got.Key == epoch1Key || got.PrevKey == epoch1Key || got.KeyEpoch == 1 || got.PrevKeyEpoch == 1 {
		t.Fatalf("epoch 1 must not be stored after direct 0->2 update: current epoch=%d key=%q prevEpoch=%d prevKey=%q", got.KeyEpoch, got.Key, got.PrevKeyEpoch, got.PrevKey)
	}
	minDeadline := before.Add(KeyRotationGracePeriod - time.Second)
	maxDeadline := after.Add(KeyRotationGracePeriod + time.Second)
	if got.GraceDeadline.IsZero() {
		t.Fatal("expected live grace deadline after direct 0->2 update")
	}
	if got.GraceDeadline.Before(minDeadline) || got.GraceDeadline.After(maxDeadline) {
		t.Fatalf("grace deadline %v outside expected range [%v, %v]", got.GraceDeadline, minDeadline, maxDeadline)
	}
	if !time.Now().Before(got.GraceDeadline) {
		t.Fatalf("grace deadline %v is not live", got.GraceDeadline)
	}
}

func gk020GenerateDistinctEpochKeys(t *testing.T) (string, string, string) {
	t.Helper()

	epoch0Key, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate epoch 0 key: %v", err)
	}
	epoch1Key, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate epoch 1 key: %v", err)
	}
	epoch2Key, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate epoch 2 key: %v", err)
	}
	if epoch0Key == epoch1Key || epoch0Key == epoch2Key || epoch1Key == epoch2Key {
		t.Fatal("generated GK020 epoch keys are not distinct")
	}
	return epoch0Key, epoch1Key, epoch2Key
}

func gk020SequentialRotationKeyInfo(t *testing.T, groupId, epoch0Key, epoch1Key, epoch2Key string) *GroupKeyInfo {
	t.Helper()

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

	if err := n.JoinGroupTopic(groupId, testGroupConfig(GroupTypeChat), &GroupKeyInfo{Key: epoch0Key, KeyEpoch: 0}); err != nil {
		t.Fatalf("JoinGroupTopic: %v", err)
	}
	n.UpdateGroupKey(groupId, &GroupKeyInfo{Key: epoch1Key, KeyEpoch: 1})

	beforeSecondUpdate := time.Now()
	n.UpdateGroupKey(groupId, &GroupKeyInfo{Key: epoch2Key, KeyEpoch: 2})
	afterSecondUpdate := time.Now()

	got := n.GetGroupKeyInfo(groupId)
	assertGK020SequentialRotationKeyInfo(t, got, epoch0Key, epoch1Key, epoch2Key, beforeSecondUpdate, afterSecondUpdate)
	return got
}

func assertGK020SequentialRotationKeyInfo(t *testing.T, got *GroupKeyInfo, epoch0Key, epoch1Key, epoch2Key string, beforeSecondUpdate, afterSecondUpdate time.Time) {
	t.Helper()

	if got == nil {
		t.Fatal("expected non-nil key info after sequential 0->1->2 update")
	}
	if got.Key != epoch2Key || got.KeyEpoch != 2 {
		t.Fatalf("expected current epoch 2 key, got epoch=%d key=%q", got.KeyEpoch, got.Key)
	}
	if got.PrevKey != epoch1Key || got.PrevKeyEpoch != 1 {
		t.Fatalf("expected previous epoch 1 key, got prevEpoch=%d prevKey=%q", got.PrevKeyEpoch, got.PrevKey)
	}
	if got.Key == epoch0Key || got.PrevKey == epoch0Key || got.KeyEpoch == 0 || got.PrevKeyEpoch == 0 {
		t.Fatalf("epoch 0 must not be stored after sequential 0->1->2 update: current epoch=%d key=%q prevEpoch=%d prevKey=%q", got.KeyEpoch, got.Key, got.PrevKeyEpoch, got.PrevKey)
	}
	minDeadline := beforeSecondUpdate.Add(KeyRotationGracePeriod - time.Second)
	maxDeadline := afterSecondUpdate.Add(KeyRotationGracePeriod + time.Second)
	if got.GraceDeadline.IsZero() {
		t.Fatal("expected live grace deadline after sequential 0->1->2 update")
	}
	if got.GraceDeadline.Before(minDeadline) || got.GraceDeadline.After(maxDeadline) {
		t.Fatalf("grace deadline %v outside expected second-rotation range [%v, %v]", got.GraceDeadline, minDeadline, maxDeadline)
	}
	if !time.Now().Before(got.GraceDeadline) {
		t.Fatalf("grace deadline %v is not live", got.GraceDeadline)
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

func TestSV003PublishBlockedUntilCurrentConfigAndKeyInstalled(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	oldGroupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate old group key: %v", err)
	}
	currentGroupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate current group key: %v", err)
	}

	n := startLocalNodeForMultiRelayTest(t)
	groupId := "sv003-pending-readd-current-config-key"
	senderPeerId := n.PeerId()
	initialConfig := &GroupConfig{
		Name:      "SV-003 initial",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderPeerId, Role: GroupRoleWriter, PublicKey: senderPubB64},
		},
		CreatedBy: "alice",
	}
	if err := n.JoinGroupTopic(groupId, initialConfig, &GroupKeyInfo{
		Key:      oldGroupKey,
		KeyEpoch: 1,
	}); err != nil {
		t.Fatalf("JoinGroupTopic: %v", err)
	}

	assertBlocked := func(label string) {
		t.Helper()
		msgID, peerCount, publishErr := n.PublishGroupMessage(
			groupId,
			senderPrivB64,
			senderPeerId,
			senderPubB64,
			"Charlie",
			label,
			"",
			nil,
		)
		if publishErr == nil {
			t.Fatalf("%s PublishGroupMessage succeeded before current config/key", label)
		}
		if msgID != "" || peerCount != 0 {
			t.Fatalf("%s PublishGroupMessage returned msgID=%q peerCount=%d, want empty/0", label, msgID, peerCount)
		}
	}

	n.UpdateGroupConfig(groupId, nil)
	n.UpdateGroupKey(groupId, &GroupKeyInfo{Key: currentGroupKey, KeyEpoch: 2})
	assertBlocked("SV-003 current key without config")

	readdConfig := &GroupConfig{
		Name:      "SV-003 readd current config",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: "alice", Role: GroupRoleAdmin, PublicKey: "alice-pub"},
			{PeerId: senderPeerId, Role: GroupRoleWriter, PublicKey: senderPubB64},
		},
		CreatedBy: "alice",
	}
	n.UpdateGroupConfig(groupId, readdConfig)
	n.UpdateGroupKey(groupId, nil)
	assertBlocked("SV-003 current config without key")

	n.UpdateGroupKey(groupId, &GroupKeyInfo{Key: currentGroupKey, KeyEpoch: 2})
	msgID, peerCount, publishErr := n.PublishGroupMessage(
		groupId,
		senderPrivB64,
		senderPeerId,
		senderPubB64,
		"Charlie",
		"SV-003 current config and key publish",
		"sv003-current-publish",
		nil,
	)
	if publishErr != nil {
		t.Fatalf("PublishGroupMessage after current config/key: %v", publishErr)
	}
	if msgID != "sv003-current-publish" {
		t.Fatalf("PublishGroupMessage msgID = %q, want sv003-current-publish", msgID)
	}
	if peerCount != 0 {
		t.Fatalf("local SV-003 publish peerCount = %d, want 0", peerCount)
	}
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

func TestKE004UpdateGroupKeySameEpochSameMaterialIsIdempotentAndKeepsEpoch3Delivery(t *testing.T) {
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

	nodeACapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

	groupId := "ke004-same-epoch-same-material-idempotent"
	senderPeerId := nodeA.PeerId()
	config := &GroupConfig{
		Name:      "KE004 Same Epoch Same Key Group",
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

	assertKE004Epoch3WithPrevEpoch2 := func(label string, got *GroupKeyInfo) {
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
	assertKE004Unchanged := func(label string, got, before *GroupKeyInfo) {
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
	assertKE004Epoch3WithPrevEpoch2("nodeA before duplicate update", beforeA)
	assertKE004Epoch3WithPrevEpoch2("nodeB before duplicate update", beforeB)

	nodeA.UpdateGroupKey(groupId, epoch3Info)
	nodeB.UpdateGroupKey(groupId, epoch3Info)

	afterDuplicateA := nodeA.GetGroupKeyInfo(groupId)
	afterDuplicateB := nodeB.GetGroupKeyInfo(groupId)
	assertKE004Unchanged("nodeA after duplicate update", afterDuplicateA, beforeA)
	assertKE004Unchanged("nodeB after duplicate update", afterDuplicateB, beforeB)

	connectLocalGroupNodes(t, nodeA, nodeB)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 3*time.Second)

	baselineB := len(nodeBCapture.snapshot())
	messageId := "ke004-epoch3-message"
	text := "KE004 epoch 3 delivery after duplicate same-key update"
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
		t.Fatalf("PublishGroupMessage after duplicate same-key update: %v", publishErr)
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
		t.Fatal("group:decryption_failed should not be emitted for epoch 3 delivery after duplicate same-key update")
	}
	assertKE004Unchanged("nodeB after epoch 3 delivery", nodeB.GetGroupKeyInfo(groupId), beforeB)
}

func TestKE005UpdateGroupKeyRejectsSameEpochDifferentMaterialAndKeepsEpoch3Delivery(t *testing.T) {
	testUpdateGroupKeyIgnoresSameEpochDifferentMaterialAndKeepsEpoch3Delivery(t, "ke005", "KE005")
}

func TestGL015UpdateGroupKeyIgnoresSameEpochDifferentMaterialAndKeepsEpoch3Delivery(t *testing.T) {
	testUpdateGroupKeyIgnoresSameEpochDifferentMaterialAndKeepsEpoch3Delivery(t, "gl015", "GL015")
}

func testUpdateGroupKeyIgnoresSameEpochDifferentMaterialAndKeepsEpoch3Delivery(t *testing.T, testPrefix string, label string) {
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

	groupId := testPrefix + "-same-epoch-different-material-keeps-current-delivery"
	senderPeerId := nodeA.PeerId()
	config := &GroupConfig{
		Name:      label + " Same Epoch Conflict Group",
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
	messageId := testPrefix + "-epoch3-message"
	text := label + " epoch 3 delivery after same-epoch K2 update"
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

func TestGroupKeyGraceChurnJoinGroupTopicPreservesIncomingGraceMetadata(t *testing.T) {
	currentKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate current group key: %v", err)
	}
	prevKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate previous group key: %v", err)
	}
	if currentKey == prevKey {
		t.Fatal("generated current and previous group keys are identical; test requires distinct material")
	}
	graceDeadline := time.Now().Add(KeyRotationGracePeriod)

	cases := []struct {
		name     string
		groupId  string
		keyInfo  *GroupKeyInfo
		validate func(t *testing.T, got *GroupKeyInfo)
	}{
		{
			name:    "live incoming grace survives join clone",
			groupId: "gkgc-join-preserves-live-grace",
			keyInfo: &GroupKeyInfo{
				Key:           currentKey,
				KeyEpoch:      2,
				PrevKey:       prevKey,
				PrevKeyEpoch:  1,
				GraceDeadline: graceDeadline,
			},
			validate: func(t *testing.T, got *GroupKeyInfo) {
				t.Helper()
				if got.Key != currentKey || got.KeyEpoch != 2 {
					t.Fatalf("current key state = epoch %d key %q, want epoch 2 key %q", got.KeyEpoch, got.Key, currentKey)
				}
				if got.PrevKey != prevKey || got.PrevKeyEpoch != 1 {
					t.Fatalf("previous key state = epoch %d key %q, want epoch 1 key %q", got.PrevKeyEpoch, got.PrevKey, prevKey)
				}
				if !got.GraceDeadline.Equal(graceDeadline) {
					t.Fatalf("GraceDeadline = %v, want exact incoming deadline %v", got.GraceDeadline, graceDeadline)
				}
			},
		},
		{
			name:    "no incoming grace stays empty",
			groupId: "gkgc-join-no-grace-empty",
			keyInfo: &GroupKeyInfo{Key: currentKey, KeyEpoch: 2},
			validate: func(t *testing.T, got *GroupKeyInfo) {
				t.Helper()
				if got.Key != currentKey || got.KeyEpoch != 2 {
					t.Fatalf("current key state = epoch %d key %q, want epoch 2 key %q", got.KeyEpoch, got.Key, currentKey)
				}
				if got.PrevKey != "" {
					t.Fatalf("PrevKey = %q, want empty", got.PrevKey)
				}
				if got.PrevKeyEpoch != 0 {
					t.Fatalf("PrevKeyEpoch = %d, want 0", got.PrevKeyEpoch)
				}
				if !got.GraceDeadline.IsZero() {
					t.Fatalf("GraceDeadline = %v, want zero", got.GraceDeadline)
				}
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
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

			if err := n.JoinGroupTopic(tc.groupId, testGroupConfig(GroupTypeChat), tc.keyInfo); err != nil {
				t.Fatalf("JoinGroupTopic: %v", err)
			}

			got := n.GetGroupKeyInfo(tc.groupId)
			if got == nil {
				t.Fatal("expected non-nil key info after join")
			}
			tc.validate(t, got)
		})
	}
}

func TestGK016HandleGroupSubscriptionDecryptsEpoch0PreviousKeyDuringFirstRotationGrace(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	_, receiverPubB64 := generateEd25519KeyPair(t)
	epoch0Key, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate epoch 0 key: %v", err)
	}
	epoch1Key, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate epoch 1 key: %v", err)
	}

	nodeACapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

	groupId := "gk016-first-rotation-delivery"
	senderPeerId := nodeA.PeerId()
	config := &GroupConfig{
		Name:      "GK016 First Rotation Delivery",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderPeerId, Role: GroupRoleAdmin, PublicKey: senderPubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: receiverPubB64},
		},
		CreatedBy: senderPeerId,
	}

	if err := nodeA.JoinGroupTopic(groupId, config, &GroupKeyInfo{Key: epoch0Key, KeyEpoch: 0}); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, config, &GroupKeyInfo{Key: epoch0Key, KeyEpoch: 0}); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}
	nodeB.UpdateGroupKey(groupId, &GroupKeyInfo{Key: epoch1Key, KeyEpoch: 1})
	if got := nodeB.GetGroupKeyInfo(groupId); got == nil {
		t.Fatal("nodeB GetGroupKeyInfo after rotation = nil")
	} else if got.PrevKey != epoch0Key || got.PrevKeyEpoch != 0 || got.GraceDeadline.IsZero() {
		t.Fatalf("nodeB previous grace state = prevKey %q prevEpoch %d deadline %v, want epoch 0 previous key with live deadline", got.PrevKey, got.PrevKeyEpoch, got.GraceDeadline)
	}

	connectLocalGroupNodes(t, nodeA, nodeB)

	text := "epoch 0 still decrypts during first rotation grace"
	envelopeJSON := buildTestEnvelope(
		t,
		groupId,
		senderPeerId,
		senderPrivB64,
		senderPubB64,
		epoch0Key,
		0,
		text,
	)
	publishRawGroupEnvelope(t, nodeA, groupId, envelopeJSON)

	received := waitForCollectedEvent(t, nodeBCapture, "group_message:received", 5*time.Second)
	if got := received["groupId"]; got != groupId {
		t.Fatalf("groupId = %v, want %q", got, groupId)
	}
	if got := received["senderId"]; got != senderPeerId {
		t.Fatalf("senderId = %v, want %q", got, senderPeerId)
	}
	if got := received["text"]; got != text {
		t.Fatalf("text = %v, want %q", got, text)
	}
	if got, ok := received["keyEpoch"].(float64); !ok || int(got) != 0 {
		t.Fatalf("keyEpoch = %v, want 0", received["keyEpoch"])
	}
	if hasCollectedEventName(nodeBCapture.snapshot(), "group:decryption_failed") {
		t.Fatal("group:decryption_failed should not be emitted for epoch 0 during first rotation grace")
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
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

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
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

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

func TestGK017GroupTopicValidatorEmitsBadSignatureOrEpochAfterGraceDeadline(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	_, receiverPubB64 := generateEd25519KeyPair(t)
	prevKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate previous group key: %v", err)
	}
	currentKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate current group key: %v", err)
	}

	nodeACapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

	groupId := "gk017-prev-epoch-expired-live-validator"
	senderPeerId := nodeA.PeerId()
	config := &GroupConfig{
		Name:      "GK017 Expired Live Validator",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderPeerId, Role: GroupRoleAdmin, PublicKey: senderPubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: receiverPubB64},
		},
		CreatedBy: senderPeerId,
	}

	if err := nodeA.JoinGroupTopic(groupId, config, &GroupKeyInfo{Key: prevKey, KeyEpoch: 1}); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, config, &GroupKeyInfo{Key: prevKey, KeyEpoch: 1}); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}
	nodeB.UpdateGroupKey(groupId, &GroupKeyInfo{Key: currentKey, KeyEpoch: 2})
	nodeB.groupKeys[groupId].GraceDeadline = time.Now().Add(-time.Second)

	connectLocalGroupNodes(t, nodeA, nodeB)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 3*time.Second)
	waitForGroupTopicPeerCount(t, nodeB, groupId, 1, 3*time.Second)

	envelopeJSON := buildTestEnvelope(
		t,
		groupId,
		senderPeerId,
		senderPrivB64,
		senderPubB64,
		prevKey,
		1,
		"stale previous epoch should reject after grace",
	)
	baseline := len(nodeBCapture.snapshot())
	publishRawGroupEnvelope(t, nodeA, groupId, envelopeJSON)

	waitForCollectedValidationReject(t, nodeBCapture, baseline, "bad_signature_or_epoch", 1, 5*time.Second)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, `"event":"group_message:received"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, `"event":"group_reaction:received"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, `"event":"group:decryption_failed"`, 500*time.Millisecond)
}

func TestGK018HandleGroupSubscriptionReceivesCurrentEpochAfterGraceDeadline(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	_, receiverPubB64 := generateEd25519KeyPair(t)
	prevKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate previous group key: %v", err)
	}
	currentKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate current group key: %v", err)
	}
	if currentKey == prevKey {
		t.Fatal("generated current and previous group keys are identical; test requires distinct material")
	}

	nodeACapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

	groupId := "gk018-current-epoch-expired-live"
	senderPeerId := nodeA.PeerId()
	config := &GroupConfig{
		Name:      "GK018 Current Epoch Expired Live",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderPeerId, Role: GroupRoleAdmin, PublicKey: senderPubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: receiverPubB64},
		},
		CreatedBy: senderPeerId,
	}

	if err := nodeA.JoinGroupTopic(groupId, config, &GroupKeyInfo{Key: prevKey, KeyEpoch: 1}); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, config, &GroupKeyInfo{Key: prevKey, KeyEpoch: 1}); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}
	nodeA.UpdateGroupKey(groupId, &GroupKeyInfo{Key: currentKey, KeyEpoch: 2})
	nodeB.UpdateGroupKey(groupId, &GroupKeyInfo{Key: currentKey, KeyEpoch: 2})
	nodeB.groupKeys[groupId].GraceDeadline = time.Now().Add(-time.Second)

	connectLocalGroupNodes(t, nodeA, nodeB)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 3*time.Second)
	waitForGroupTopicPeerCount(t, nodeB, groupId, 1, 3*time.Second)

	text := "current epoch stays live after previous grace"
	envelopeJSON := buildTestEnvelope(
		t,
		groupId,
		senderPeerId,
		senderPrivB64,
		senderPubB64,
		currentKey,
		2,
		text,
	)
	baseline := len(nodeBCapture.snapshot())
	publishRawGroupEnvelope(t, nodeA, groupId, envelopeJSON)

	received := waitForCollectedEventAfter(t, nodeBCapture, baseline, "group_message:received", 5*time.Second)
	if got, _ := received["groupId"].(string); got != groupId {
		t.Fatalf("received groupId = %q, want %q", got, groupId)
	}
	if got, _ := received["senderId"].(string); got != senderPeerId {
		t.Fatalf("received senderId = %q, want %q", got, senderPeerId)
	}
	if got, _ := received["text"].(string); got != text {
		t.Fatalf("received text = %q, want %q", got, text)
	}
	if got, ok := received["keyEpoch"].(float64); !ok || int(got) != 2 {
		t.Fatalf("received keyEpoch = %v, want 2", received["keyEpoch"])
	}

	assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, `"event":"group:validation_rejected"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, `"event":"group:decryption_failed"`, 500*time.Millisecond)
}

func TestGK019HandleGroupSubscriptionDirectJumpReceivesAllowedEpochsOnly(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	_, receiverPubB64 := generateEd25519KeyPair(t)
	epoch0Key, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate epoch 0 key: %v", err)
	}
	epoch1Key, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate epoch 1 key: %v", err)
	}
	epoch2Key, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate epoch 2 key: %v", err)
	}

	nodeACapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

	groupId := "gk019-direct-jump-live"
	senderPeerId := nodeA.PeerId()
	config := &GroupConfig{
		Name:      "GK019 Direct Jump Live",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderPeerId, Role: GroupRoleAdmin, PublicKey: senderPubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: receiverPubB64},
		},
		CreatedBy: senderPeerId,
	}

	if err := nodeA.JoinGroupTopic(groupId, config, &GroupKeyInfo{Key: epoch0Key, KeyEpoch: 0}); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, config, &GroupKeyInfo{Key: epoch0Key, KeyEpoch: 0}); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}
	before := time.Now()
	nodeA.UpdateGroupKey(groupId, &GroupKeyInfo{Key: epoch2Key, KeyEpoch: 2})
	nodeB.UpdateGroupKey(groupId, &GroupKeyInfo{Key: epoch2Key, KeyEpoch: 2})
	after := time.Now()
	assertGK019DirectJumpKeyInfo(t, nodeB.GetGroupKeyInfo(groupId), epoch0Key, epoch1Key, epoch2Key, before, after)

	connectLocalGroupNodes(t, nodeA, nodeB)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 3*time.Second)
	waitForGroupTopicPeerCount(t, nodeB, groupId, 1, 3*time.Second)
	if err := nodeA.pubsub.UnregisterTopicValidator(GroupTopicPrefix + groupId); err != nil {
		t.Fatalf("nodeA unregister local validator before GK019 raw publish: %v", err)
	}

	epoch0Text := "direct jump still accepts epoch 0 grace"
	epoch0Envelope := buildTestEnvelope(t, groupId, senderPeerId, senderPrivB64, senderPubB64, epoch0Key, 0, epoch0Text)
	baseline := len(nodeBCapture.snapshot())
	publishRawGroupEnvelope(t, nodeA, groupId, epoch0Envelope)

	received := waitForCollectedEventAfter(t, nodeBCapture, baseline, "group_message:received", 5*time.Second)
	if got, _ := received["groupId"].(string); got != groupId {
		t.Fatalf("epoch 0 received groupId = %q, want %q", got, groupId)
	}
	if got, _ := received["senderId"].(string); got != senderPeerId {
		t.Fatalf("epoch 0 received senderId = %q, want %q", got, senderPeerId)
	}
	if got, _ := received["text"].(string); got != epoch0Text {
		t.Fatalf("epoch 0 received text = %q, want %q", got, epoch0Text)
	}
	if got, ok := received["keyEpoch"].(float64); !ok || int(got) != 0 {
		t.Fatalf("epoch 0 received keyEpoch = %v, want 0", received["keyEpoch"])
	}

	epoch1Envelope := buildTestEnvelope(t, groupId, senderPeerId, senderPrivB64, senderPubB64, epoch1Key, 1, "direct jump must reject skipped epoch 1")
	baseline = len(nodeBCapture.snapshot())
	publishRawGroupEnvelope(t, nodeA, groupId, epoch1Envelope)

	waitForCollectedValidationReject(t, nodeBCapture, baseline, "bad_signature_or_epoch", 1, 5*time.Second)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, `"event":"group_message:received"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, `"event":"group_reaction:received"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, `"event":"group:decryption_failed"`, 500*time.Millisecond)

	epoch2Text := "direct jump accepts current epoch 2"
	epoch2Envelope := buildTestEnvelope(t, groupId, senderPeerId, senderPrivB64, senderPubB64, epoch2Key, 2, epoch2Text)
	baseline = len(nodeBCapture.snapshot())
	publishRawGroupEnvelope(t, nodeA, groupId, epoch2Envelope)

	received = waitForCollectedEventAfter(t, nodeBCapture, baseline, "group_message:received", 5*time.Second)
	if got, _ := received["groupId"].(string); got != groupId {
		t.Fatalf("epoch 2 received groupId = %q, want %q", got, groupId)
	}
	if got, _ := received["senderId"].(string); got != senderPeerId {
		t.Fatalf("epoch 2 received senderId = %q, want %q", got, senderPeerId)
	}
	if got, _ := received["text"].(string); got != epoch2Text {
		t.Fatalf("epoch 2 received text = %q, want %q", got, epoch2Text)
	}
	if got, ok := received["keyEpoch"].(float64); !ok || int(got) != 2 {
		t.Fatalf("epoch 2 received keyEpoch = %v, want 2", received["keyEpoch"])
	}
	assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, `"event":"group:validation_rejected"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, `"event":"group:decryption_failed"`, 500*time.Millisecond)
}

func TestGK020HandleGroupSubscriptionSequentialRotationsReceivesAllowedEpochsOnly(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	_, receiverPubB64 := generateEd25519KeyPair(t)
	epoch0Key, epoch1Key, epoch2Key := gk020GenerateDistinctEpochKeys(t)

	nodeACapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

	groupId := "gk020-sequential-rotations-live"
	senderPeerId := nodeA.PeerId()
	config := &GroupConfig{
		Name:      "GK020 Sequential Rotations Live",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderPeerId, Role: GroupRoleAdmin, PublicKey: senderPubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: receiverPubB64},
		},
		CreatedBy: senderPeerId,
	}

	if err := nodeA.JoinGroupTopic(groupId, config, &GroupKeyInfo{Key: epoch0Key, KeyEpoch: 0}); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, config, &GroupKeyInfo{Key: epoch0Key, KeyEpoch: 0}); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}
	nodeA.UpdateGroupKey(groupId, &GroupKeyInfo{Key: epoch1Key, KeyEpoch: 1})
	nodeB.UpdateGroupKey(groupId, &GroupKeyInfo{Key: epoch1Key, KeyEpoch: 1})
	beforeSecondUpdate := time.Now()
	nodeA.UpdateGroupKey(groupId, &GroupKeyInfo{Key: epoch2Key, KeyEpoch: 2})
	nodeB.UpdateGroupKey(groupId, &GroupKeyInfo{Key: epoch2Key, KeyEpoch: 2})
	afterSecondUpdate := time.Now()
	assertGK020SequentialRotationKeyInfo(t, nodeB.GetGroupKeyInfo(groupId), epoch0Key, epoch1Key, epoch2Key, beforeSecondUpdate, afterSecondUpdate)

	connectLocalGroupNodes(t, nodeA, nodeB)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 3*time.Second)
	waitForGroupTopicPeerCount(t, nodeB, groupId, 1, 3*time.Second)
	if err := nodeA.pubsub.UnregisterTopicValidator(GroupTopicPrefix + groupId); err != nil {
		t.Fatalf("nodeA unregister local validator before GK020 raw publish: %v", err)
	}

	epoch0Envelope := buildTestEnvelope(t, groupId, senderPeerId, senderPrivB64, senderPubB64, epoch0Key, 0, "sequential rotation rejects too-old epoch 0")
	baseline := len(nodeBCapture.snapshot())
	publishRawGroupEnvelope(t, nodeA, groupId, epoch0Envelope)

	waitForCollectedValidationReject(t, nodeBCapture, baseline, "bad_signature_or_epoch", 0, 5*time.Second)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, `"event":"group_message:received"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, `"event":"group_reaction:received"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, `"event":"group:decryption_failed"`, 500*time.Millisecond)

	epoch1Text := "sequential rotation accepts immediate previous epoch 1"
	epoch1Envelope := buildTestEnvelope(t, groupId, senderPeerId, senderPrivB64, senderPubB64, epoch1Key, 1, epoch1Text)
	baseline = len(nodeBCapture.snapshot())
	publishRawGroupEnvelope(t, nodeA, groupId, epoch1Envelope)

	received := waitForCollectedEventAfter(t, nodeBCapture, baseline, "group_message:received", 5*time.Second)
	if got, _ := received["groupId"].(string); got != groupId {
		t.Fatalf("epoch 1 received groupId = %q, want %q", got, groupId)
	}
	if got, _ := received["senderId"].(string); got != senderPeerId {
		t.Fatalf("epoch 1 received senderId = %q, want %q", got, senderPeerId)
	}
	if got, _ := received["text"].(string); got != epoch1Text {
		t.Fatalf("epoch 1 received text = %q, want %q", got, epoch1Text)
	}
	if got, ok := received["keyEpoch"].(float64); !ok || int(got) != 1 {
		t.Fatalf("epoch 1 received keyEpoch = %v, want 1", received["keyEpoch"])
	}
	assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, `"event":"group:validation_rejected"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, `"event":"group:decryption_failed"`, 500*time.Millisecond)

	epoch2Text := "sequential rotation accepts current epoch 2"
	epoch2Envelope := buildTestEnvelope(t, groupId, senderPeerId, senderPrivB64, senderPubB64, epoch2Key, 2, epoch2Text)
	baseline = len(nodeBCapture.snapshot())
	publishRawGroupEnvelope(t, nodeA, groupId, epoch2Envelope)

	received = waitForCollectedEventAfter(t, nodeBCapture, baseline, "group_message:received", 5*time.Second)
	if got, _ := received["groupId"].(string); got != groupId {
		t.Fatalf("epoch 2 received groupId = %q, want %q", got, groupId)
	}
	if got, _ := received["senderId"].(string); got != senderPeerId {
		t.Fatalf("epoch 2 received senderId = %q, want %q", got, senderPeerId)
	}
	if got, _ := received["text"].(string); got != epoch2Text {
		t.Fatalf("epoch 2 received text = %q, want %q", got, epoch2Text)
	}
	if got, ok := received["keyEpoch"].(float64); !ok || int(got) != 2 {
		t.Fatalf("epoch 2 received keyEpoch = %v, want 2", received["keyEpoch"])
	}
	assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, `"event":"group:validation_rejected"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, `"event":"group:decryption_failed"`, 500*time.Millisecond)
}

func TestGK021GroupTopicValidatorRejectsRemovalEpochPackageAndAcceptsReaddEpoch(t *testing.T) {
	oldPriv, oldPub := generateEd25519KeyPair(t)
	freshPriv, freshPub := generateEd25519KeyPair(t)
	_, receiverPub := generateEd25519KeyPair(t)
	prevKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate previous group key: %v", err)
	}
	currentKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate current group key: %v", err)
	}
	if currentKey == prevKey {
		t.Fatal("generated current and previous group keys are identical; test requires distinct material")
	}

	groupId := "gk021-readd-key-epoch-validator"
	charliePeerId := "member-charlie"
	oldDevice := GroupMemberDevice{
		DeviceId:               "charlie-device-removed-e1",
		TransportPeerId:        "charlie-transport-removed-e1",
		DeviceSigningPublicKey: oldPub,
		KeyPackageId:           "kp-charlie-removed-e1",
		Status:                 "active",
	}
	freshDevice := GroupMemberDevice{
		DeviceId:               "charlie-device-readd-e2",
		TransportPeerId:        "charlie-transport-readd-e2",
		DeviceSigningPublicKey: freshPub,
		KeyPackageId:           "kp-charlie-readd-e2",
		Status:                 "active",
	}
	if oldDevice.DeviceId == freshDevice.DeviceId ||
		oldDevice.DeviceSigningPublicKey == freshDevice.DeviceSigningPublicKey ||
		oldDevice.KeyPackageId == freshDevice.KeyPackageId {
		t.Fatal("GK-021 fixture must use distinct old and fresh device credentials")
	}

	readdConfig := &GroupConfig{
		Name:      "GK-021",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{
				PeerId:    "member-bob",
				Role:      GroupRoleWriter,
				PublicKey: receiverPub,
			},
			{
				PeerId:    charliePeerId,
				Role:      GroupRoleWriter,
				PublicKey: "member-charlie-public-key",
				Devices:   []GroupMemberDevice{freshDevice},
			},
		},
		CreatedBy: "member-bob",
	}
	keyInfo := buildGroupKeyInfoWithGrace(
		currentKey,
		2,
		prevKey,
		1,
		time.Now().Add(KeyRotationGracePeriod),
	)

	staleEnvelopeJSON := buildTestDeviceEnvelope(
		t,
		groupId,
		charliePeerId,
		oldDevice.DeviceId,
		oldDevice.TransportPeerId,
		oldDevice.DeviceSigningPublicKey,
		oldDevice.KeyPackageId,
		oldPriv,
		oldPub,
		prevKey,
		1,
		"GK-021 stale removal epoch package",
	)
	if result := validateGroupEnvelopeForTransportPeer(
		staleEnvelopeJSON,
		groupId,
		readdConfig,
		keyInfo,
		oldDevice.TransportPeerId,
	); result != "reject:unbound_device" {
		t.Fatalf("expected reject:unbound_device for stale E1 removed package during live grace, got %s", result)
	}

	staleSameActiveEnvelopeJSON := buildTestDeviceEnvelope(
		t,
		groupId,
		charliePeerId,
		freshDevice.DeviceId,
		freshDevice.TransportPeerId,
		freshDevice.DeviceSigningPublicKey,
		oldDevice.KeyPackageId,
		freshPriv,
		freshPub,
		prevKey,
		1,
		"GK-021 stale removal epoch package on re-add device",
	)
	if result := validateGroupEnvelopeForTransportPeer(
		staleSameActiveEnvelopeJSON,
		groupId,
		readdConfig,
		keyInfo,
		freshDevice.TransportPeerId,
	); result != "reject:unbound_device" {
		t.Fatalf("expected reject:unbound_device for stale E1 package on current re-add device during live grace, got %s", result)
	}

	freshEnvelopeJSON := buildTestDeviceEnvelope(
		t,
		groupId,
		charliePeerId,
		freshDevice.DeviceId,
		freshDevice.TransportPeerId,
		freshDevice.DeviceSigningPublicKey,
		freshDevice.KeyPackageId,
		freshPriv,
		freshPub,
		currentKey,
		2,
		"GK-021 fresh re-add epoch package",
	)
	if result := validateGroupEnvelopeForTransportPeer(
		freshEnvelopeJSON,
		groupId,
		readdConfig,
		keyInfo,
		freshDevice.TransportPeerId,
	); result != "accept" {
		t.Fatalf("expected accept for fresh E2 re-add package, got %s", result)
	}
}

func TestGK021HandleGroupSubscriptionRejectsRemovalEpochPackageAndReceivesReaddEpoch(t *testing.T) {
	freshPriv, freshPub := generateEd25519KeyPair(t)
	_, receiverPub := generateEd25519KeyPair(t)
	prevKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate previous group key: %v", err)
	}
	currentKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate current group key: %v", err)
	}
	if currentKey == prevKey {
		t.Fatal("generated current and previous group keys are identical; test requires distinct material")
	}

	nodeACapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

	groupId := "gk021-readd-key-epoch-live"
	charliePeerId := "member-charlie-gk021"
	oldKeyPackageId := "kp-charlie-removed-e1"
	freshDevice := GroupMemberDevice{
		DeviceId:               "charlie-device-readd-e2",
		TransportPeerId:        nodeA.PeerId(),
		DeviceSigningPublicKey: freshPub,
		KeyPackageId:           "kp-charlie-readd-e2",
		Status:                 "active",
	}
	if oldKeyPackageId == freshDevice.KeyPackageId {
		t.Fatal("GK-021 live fixture must use distinct old and fresh key packages")
	}
	config := &GroupConfig{
		Name:      "GK-021 Live",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{
				PeerId:    nodeB.PeerId(),
				Role:      GroupRoleWriter,
				PublicKey: receiverPub,
			},
			{
				PeerId:    charliePeerId,
				Role:      GroupRoleWriter,
				PublicKey: "member-charlie-public-key",
				Devices:   []GroupMemberDevice{freshDevice},
			},
		},
		CreatedBy: nodeB.PeerId(),
	}
	keyInfo := &GroupKeyInfo{Key: currentKey, KeyEpoch: 2}
	if err := nodeA.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}
	for _, n := range []*Node{nodeA, nodeB} {
		n.groupKeys[groupId].PrevKey = prevKey
		n.groupKeys[groupId].PrevKeyEpoch = 1
		n.groupKeys[groupId].GraceDeadline = time.Now().Add(KeyRotationGracePeriod)
	}

	connectLocalGroupNodes(t, nodeA, nodeB)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 3*time.Second)
	waitForGroupTopicPeerCount(t, nodeB, groupId, 1, 3*time.Second)
	if err := nodeA.pubsub.UnregisterTopicValidator(GroupTopicPrefix + groupId); err != nil {
		t.Fatalf("nodeA unregister local validator before GK021 raw publish: %v", err)
	}

	staleEnvelopeJSON := buildTestDeviceEnvelope(
		t,
		groupId,
		charliePeerId,
		freshDevice.DeviceId,
		freshDevice.TransportPeerId,
		freshDevice.DeviceSigningPublicKey,
		oldKeyPackageId,
		freshPriv,
		freshPub,
		prevKey,
		1,
		"GK-021 stale removal epoch package on re-add device should reject",
	)
	baseline := len(nodeBCapture.snapshot())
	publishRawGroupEnvelope(t, nodeA, groupId, staleEnvelopeJSON)

	waitForCollectedValidationReject(t, nodeBCapture, baseline, "unbound_device", 1, 5*time.Second)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, `"event":"group_message:received"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, `"event":"group_reaction:received"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, `"event":"group:decryption_failed"`, 500*time.Millisecond)

	freshText := "GK-021 fresh re-add epoch package should deliver"
	freshEnvelopeJSON := buildTestDeviceEnvelope(
		t,
		groupId,
		charliePeerId,
		freshDevice.DeviceId,
		freshDevice.TransportPeerId,
		freshDevice.DeviceSigningPublicKey,
		freshDevice.KeyPackageId,
		freshPriv,
		freshPub,
		currentKey,
		2,
		freshText,
	)
	baseline = len(nodeBCapture.snapshot())
	publishRawGroupEnvelope(t, nodeA, groupId, freshEnvelopeJSON)

	received := waitForCollectedEventAfter(t, nodeBCapture, baseline, "group_message:received", 5*time.Second)
	if got, _ := received["groupId"].(string); got != groupId {
		t.Fatalf("received groupId = %q, want %q", got, groupId)
	}
	if got, _ := received["senderId"].(string); got != charliePeerId {
		t.Fatalf("received senderId = %q, want %q", got, charliePeerId)
	}
	if got, _ := received["text"].(string); got != freshText {
		t.Fatalf("received text = %q, want %q", got, freshText)
	}
	if got, ok := received["keyEpoch"].(float64); !ok || int(got) != 2 {
		t.Fatalf("received keyEpoch = %v, want 2", received["keyEpoch"])
	}
	assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, `"event":"group:validation_rejected"`, 500*time.Millisecond)
	assertNoCollectedEventContainingAfter(t, nodeBCapture, baseline, `"event":"group:decryption_failed"`, 500*time.Millisecond)
}
