package node

import (
	"strings"
	"testing"
	"time"

	mcrypto "github.com/mknoon/go-mknoon/crypto"
	"github.com/mknoon/go-mknoon/internal"
)

// udmeRotateKeys joins a node at epoch 0 then sequentially rotates it through
// the supplied per-epoch keys (epoch index == slice index + 1 for the rotated
// keys; index 0 is the join epoch). It returns the started node and the
// concrete group id used so callers can publish/decrypt against the ring.
func udmeStartNodeWithRotations(t *testing.T, groupId string, epochKeys []string) *Node {
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
	t.Cleanup(func() { n.Stop() })

	if err := n.JoinGroupTopic(groupId, testGroupConfig(GroupTypeChat), &GroupKeyInfo{Key: epochKeys[0], KeyEpoch: 0}); err != nil {
		t.Fatalf("JoinGroupTopic: %v", err)
	}
	for epoch := 1; epoch < len(epochKeys); epoch++ {
		n.UpdateGroupKey(groupId, &GroupKeyInfo{Key: epochKeys[epoch], KeyEpoch: epoch})
	}
	return n
}

func udmeGenerateDistinctKeys(t *testing.T, count int) []string {
	t.Helper()
	keys := make([]string, count)
	seen := map[string]bool{}
	for i := 0; i < count; i++ {
		k, err := mcrypto.GenerateGroupKey()
		if err != nil {
			t.Fatalf("generate group key %d: %v", i, err)
		}
		if seen[k] {
			t.Fatalf("generated duplicate group key at index %d", i)
		}
		seen[k] = true
		keys[i] = k
	}
	return keys
}

// TestUDME_DecryptAcceptsThirdOldestEpochStillInRing proves the retained ring
// keeps more than one prior epoch: after 0 -> 1 -> 2, an envelope at epoch 0
// (the third-oldest) still decrypts regardless of GraceDeadline. The pre-ring
// code only retained PrevKey (epoch 1) and dropped epoch 0.
func TestUDME_DecryptAcceptsThirdOldestEpochStillInRing(t *testing.T) {
	priv, pub := generateEd25519KeyPair(t)
	keys := udmeGenerateDistinctKeys(t, 3)
	groupId := "udme-third-oldest-still-in-ring"
	senderId := "peer-udme-third-oldest"

	n := udmeStartNodeWithRotations(t, groupId, keys)
	keyInfo := n.GetGroupKeyInfo(groupId)
	if keyInfo == nil {
		t.Fatal("expected non-nil key info after sequential rotations")
	}
	// Force the clock-based grace to be irrelevant: even an expired deadline must
	// not gate a held epoch on the receive path.
	keyInfo.GraceDeadline = time.Now().Add(-time.Hour)

	text := "epoch 0 third-oldest still decrypts from the ring"
	envelopeJSON := buildTestEnvelope(t, groupId, senderId, priv, pub, keys[0], 0, text)
	env, err := internal.ParseGroupEnvelope(envelopeJSON)
	if err != nil {
		t.Fatalf("parse envelope: %v", err)
	}

	plaintext, err := decryptGroupEnvelopePayload(env, keyInfo, time.Now())
	if err != nil {
		t.Fatalf("expected epoch 0 to decrypt from retained ring, got: %v", err)
	}
	if !strings.Contains(plaintext, text) {
		t.Fatalf("plaintext %q does not contain %q", plaintext, text)
	}

	// Epoch 1 (the immediate previous) must also still decrypt.
	text1 := "epoch 1 also decrypts from the ring"
	env1JSON := buildTestEnvelope(t, groupId, senderId, priv, pub, keys[1], 1, text1)
	env1, err := internal.ParseGroupEnvelope(env1JSON)
	if err != nil {
		t.Fatalf("parse epoch 1 envelope: %v", err)
	}
	plaintext1, err := decryptGroupEnvelopePayload(env1, keyInfo, time.Now())
	if err != nil {
		t.Fatalf("expected epoch 1 to decrypt from retained ring, got: %v", err)
	}
	if !strings.Contains(plaintext1, text1) {
		t.Fatalf("epoch 1 plaintext %q does not contain %q", plaintext1, text1)
	}
}

// TestUDME_ValidatorAcceptsHeldOldEpochAfterGraceExpired flips the polarity of
// the old deadline-negative reject: a held prior epoch is accepted by the
// validator even when GraceDeadline is in the past, because receive anchors to
// keys held, not the clock.
func TestUDME_ValidatorAcceptsHeldOldEpochAfterGraceExpired(t *testing.T) {
	priv, pub := generateEd25519KeyPair(t)
	prevKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate previous group key: %v", err)
	}
	currentKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate current group key: %v", err)
	}

	groupId := "udme-held-old-epoch-after-grace-expired"
	senderId := "peer-udme-held-old"
	config := &GroupConfig{
		Name:      "UDME Held Old Epoch After Grace",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderId, Role: GroupRoleAdmin, PublicKey: pub},
		},
		CreatedBy: senderId,
	}
	envelope := buildTestEnvelope(t, groupId, senderId, priv, pub, prevKey, 1, "held prev epoch after expiry")

	expiredGrace := buildGroupKeyInfoWithGrace(
		currentKey,
		2,
		prevKey,
		1,
		time.Now().Add(-time.Second),
	)
	if result := validateGroupEnvelope(envelope, groupId, config, expiredGrace); result != "accept" {
		t.Fatalf("expected held previous epoch accept after grace deadline, got %s", result)
	}
}

// TestUDME_RingEvictsBeyondK_OldestRejected bounds retention: after K+1 (=6)
// rotations the evicted oldest epoch fails decrypt, while the K most-recent
// held epochs still decrypt. K == RetainedEpochKeys.
func TestUDME_RingEvictsBeyondK_OldestRejected(t *testing.T) {
	priv, pub := generateEd25519KeyPair(t)
	// epochs 0..K  => K+1 distinct epochs. After K+1 rotations the oldest
	// (epoch 0) is evicted; epochs 1..K (K epochs) remain.
	total := RetainedEpochKeys + 1
	keys := udmeGenerateDistinctKeys(t, total)
	groupId := "udme-ring-evicts-beyond-k"
	senderId := "peer-udme-evict"

	n := udmeStartNodeWithRotations(t, groupId, keys)
	keyInfo := n.GetGroupKeyInfo(groupId)
	if keyInfo == nil {
		t.Fatal("expected non-nil key info after K+1 rotations")
	}
	keyInfo.GraceDeadline = time.Now().Add(-time.Hour)

	// Oldest epoch 0 must be evicted -> fail closed.
	evictedJSON := buildTestEnvelope(t, groupId, senderId, priv, pub, keys[0], 0, "evicted oldest epoch 0")
	evicted, err := internal.ParseGroupEnvelope(evictedJSON)
	if err != nil {
		t.Fatalf("parse evicted envelope: %v", err)
	}
	if plaintext, err := decryptGroupEnvelopePayload(evicted, keyInfo, time.Now()); err == nil {
		t.Fatalf("expected evicted epoch 0 to fail decrypt, got plaintext %q", plaintext)
	} else if !strings.Contains(err.Error(), "no group key available for epoch 0") {
		t.Fatalf("decrypt error = %q, want no group key available for epoch 0", err.Error())
	}

	// The K most-recent epochs (1..K) must all decrypt.
	for epoch := 1; epoch <= RetainedEpochKeys; epoch++ {
		text := "retained recent epoch decrypts"
		envJSON := buildTestEnvelope(t, groupId, senderId, priv, pub, keys[epoch], epoch, text)
		env, err := internal.ParseGroupEnvelope(envJSON)
		if err != nil {
			t.Fatalf("parse epoch %d envelope: %v", epoch, err)
		}
		plaintext, err := decryptGroupEnvelopePayload(env, keyInfo, time.Now())
		if err != nil {
			t.Fatalf("expected retained epoch %d to decrypt, got: %v", epoch, err)
		}
		if !strings.Contains(plaintext, text) {
			t.Fatalf("epoch %d plaintext %q does not contain %q", epoch, plaintext, text)
		}
	}
}

// TestUDME_ConfigurableGrace_DefaultTenMin_OverrideHonored locks the
// configurable grace accessor: unset -> default (~10 min) governs the
// GraceDeadline stamped on rotation; explicit override is honored.
func TestUDME_ConfigurableGrace_DefaultTenMin_OverrideHonored(t *testing.T) {
	// Default is ~10 min and bounded above 1 min so a config flip is observable.
	if KeyRotationGracePeriod < 5*time.Minute {
		t.Fatalf("default KeyRotationGracePeriod = %v, want >= 5m", KeyRotationGracePeriod)
	}

	// Unset config -> default.
	var unset *NodeConfig
	if got := unset.EffectiveKeyRotationGracePeriod(); got != KeyRotationGracePeriod {
		t.Fatalf("nil config EffectiveKeyRotationGracePeriod = %v, want default %v", got, KeyRotationGracePeriod)
	}
	zero := &NodeConfig{}
	if got := zero.EffectiveKeyRotationGracePeriod(); got != KeyRotationGracePeriod {
		t.Fatalf("zero config EffectiveKeyRotationGracePeriod = %v, want default %v", got, KeyRotationGracePeriod)
	}
	override := &NodeConfig{KeyRotationGracePeriod: 1 * time.Second}
	if got := override.EffectiveKeyRotationGracePeriod(); got != time.Second {
		t.Fatalf("override EffectiveKeyRotationGracePeriod = %v, want 1s", got)
	}

	// Default path: GraceDeadline stamped on rotation falls in [now+default, now+default+slack].
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

	groupId := "udme-configurable-grace-default"
	if err := n.JoinGroupTopic(groupId, testGroupConfig(GroupTypeChat), &GroupKeyInfo{Key: "key-A", KeyEpoch: 1}); err != nil {
		t.Fatalf("JoinGroupTopic: %v", err)
	}
	before := time.Now()
	n.UpdateGroupKey(groupId, &GroupKeyInfo{Key: "key-B", KeyEpoch: 2})
	after := time.Now()

	got := n.GetGroupKeyInfo(groupId)
	if got == nil {
		t.Fatal("expected non-nil key info after update")
	}
	minDeadline := before.Add(KeyRotationGracePeriod - time.Second)
	maxDeadline := after.Add(KeyRotationGracePeriod + time.Second)
	if got.GraceDeadline.Before(minDeadline) || got.GraceDeadline.After(maxDeadline) {
		t.Fatalf("grace deadline %v outside expected default range [%v, %v]", got.GraceDeadline, minDeadline, maxDeadline)
	}

	// Override path: a node configured with a 1s grace stamps a ~1s deadline.
	hexKey2 := generateTestKey(t)
	n2 := NewNode()
	_, err = n2.Start(NodeConfig{
		PrivateKeyHex:          hexKey2,
		RelayAddresses:         []string{},
		AutoRegister:           false,
		KeyRotationGracePeriod: 1 * time.Second,
	})
	if err != nil {
		t.Fatalf("Start n2: %v", err)
	}
	defer n2.Stop()

	groupId2 := "udme-configurable-grace-override"
	if err := n2.JoinGroupTopic(groupId2, testGroupConfig(GroupTypeChat), &GroupKeyInfo{Key: "key-A", KeyEpoch: 1}); err != nil {
		t.Fatalf("n2 JoinGroupTopic: %v", err)
	}
	before2 := time.Now()
	n2.UpdateGroupKey(groupId2, &GroupKeyInfo{Key: "key-B", KeyEpoch: 2})
	after2 := time.Now()

	got2 := n2.GetGroupKeyInfo(groupId2)
	if got2 == nil {
		t.Fatal("expected non-nil key info after override update")
	}
	minD2 := before2.Add(1*time.Second - 500*time.Millisecond)
	maxD2 := after2.Add(1*time.Second + 500*time.Millisecond)
	if got2.GraceDeadline.Before(minD2) || got2.GraceDeadline.After(maxD2) {
		t.Fatalf("override grace deadline %v outside expected range [%v, %v]", got2.GraceDeadline, minD2, maxD2)
	}
}

// TestUDME_CloneDeepCopiesRing proves GetGroupKeyInfo hands out a deep copy of
// the ring so callers cannot mutate stored state (data-race / aliasing guard).
func TestUDME_CloneDeepCopiesRing(t *testing.T) {
	keys := udmeGenerateDistinctKeys(t, 3)
	groupId := "udme-clone-deep-copies-ring"
	n := udmeStartNodeWithRotations(t, groupId, keys)

	got := n.GetGroupKeyInfo(groupId)
	if got == nil || len(got.Keys) == 0 {
		t.Fatalf("expected non-empty ring, got %#v", got)
	}
	// Mutate the returned ring; the stored copy must be unaffected.
	got.Keys[0].Key = "tampered"
	got.Keys[0].KeyEpoch = 999

	again := n.GetGroupKeyInfo(groupId)
	if again == nil || len(again.Keys) == 0 {
		t.Fatalf("expected non-empty ring on re-read, got %#v", again)
	}
	if again.Keys[0].Key == "tampered" || again.Keys[0].KeyEpoch == 999 {
		t.Fatalf("stored ring was mutated by caller: head=%#v", again.Keys[0])
	}
}

// TestUDME_ForgedSignatureStillRejectedAcrossRing is a SECURITY guard: a
// held-epoch envelope whose signature does not verify must still be rejected
// even though the epoch is in the ring. The wider held-key window must never
// accept forged ciphertext.
func TestUDME_ForgedSignatureStillRejectedAcrossRing(t *testing.T) {
	priv, pub := generateEd25519KeyPair(t)
	keys := udmeGenerateDistinctKeys(t, 3)
	groupId := "udme-forged-sig-rejected"
	senderId := "peer-udme-forged"
	config := &GroupConfig{
		Name:      "UDME Forged Signature",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderId, Role: GroupRoleAdmin, PublicKey: pub},
		},
		CreatedBy: senderId,
	}

	n := udmeStartNodeWithRotations(t, groupId, keys)
	keyInfo := n.GetGroupKeyInfo(groupId)
	if keyInfo == nil {
		t.Fatal("expected non-nil key info")
	}

	// Build a valid epoch-0 envelope, then corrupt its signature.
	envelope := buildTestEnvelope(t, groupId, senderId, priv, pub, keys[0], 0, "forged at held epoch 0")
	forged := mutateGroupEnvelope(t, envelope, func(env *internal.GroupEnvelope) {
		// keep epoch 0 but break the signature by rewriting ciphertext without
		// re-signing under the right key... mutateGroupEnvelope re-signs, so
		// instead corrupt the signature field directly below.
	})
	forgedEnv, err := internal.ParseGroupEnvelope(forged)
	if err != nil {
		t.Fatalf("parse forged envelope: %v", err)
	}
	forgedEnv.Signature = "AAAA" + forgedEnv.Signature

	member := config.Members[0]
	if verifyGroupEnvelopeSignature(groupId, member.PublicKey, forgedEnv, keyInfo, time.Now()) {
		t.Fatal("forged signature at a held ring epoch must NOT verify")
	}
}
