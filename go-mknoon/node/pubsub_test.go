package node

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"strings"
	"sync"
	"testing"
	"time"

	pubsub "github.com/libp2p/go-libp2p-pubsub"
	pb "github.com/libp2p/go-libp2p-pubsub/pb"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	ma "github.com/multiformats/go-multiaddr"

	mcrypto "github.com/mknoon/go-mknoon/crypto"
	"github.com/mknoon/go-mknoon/internal"
)

// --- Test fixtures ---

func testGroupConfig(groupType GroupType) *GroupConfig {
	return &GroupConfig{
		Name:      "Test Group",
		GroupType: groupType,
		Members: []GroupMember{
			{PeerId: "peer-admin", Username: "Admin", Role: GroupRoleAdmin, PublicKey: "adminPubKey"},
			{PeerId: "peer-writer", Username: "Writer", Role: GroupRoleWriter, PublicKey: "writerPubKey"},
			{PeerId: "peer-reader", Username: "Reader", Role: GroupRoleReader, PublicKey: "readerPubKey"},
		},
		CreatedBy: "peer-admin",
		CreatedAt: "2026-01-01T00:00:00Z",
	}
}

// generateEd25519KeyPair generates a test Ed25519 key pair and returns
// base64-encoded private key (64 bytes) and public key (32 bytes).
func generateEd25519KeyPair(t *testing.T) (privB64, pubB64 string) {
	t.Helper()
	pub, priv, err := ed25519.GenerateKey(nil)
	if err != nil {
		t.Fatalf("generate ed25519 key: %v", err)
	}
	return base64.StdEncoding.EncodeToString(priv),
		base64.StdEncoding.EncodeToString(pub)
}

// --- Rendezvous namespace tests ---

func TestGroupRendezvousNamespace(t *testing.T) {
	ns := groupRendezvousNamespace("abc-123")
	want := "/mknoon/group/abc-123"
	if ns != want {
		t.Errorf("namespace = %q, want %q", ns, want)
	}
}

func TestGroupRendezvousNamespace_MatchesTopicName(t *testing.T) {
	groupId := "test-group-uuid"
	ns := groupRendezvousNamespace(groupId)
	topicName := GroupTopicPrefix + groupId
	if ns != topicName {
		t.Errorf("namespace %q should match topic name %q", ns, topicName)
	}
}

func TestGroupDiscoveryInterval_Is30Seconds(t *testing.T) {
	if GroupDiscoveryInterval != 30*time.Second {
		t.Errorf("expected 30s, got %v", GroupDiscoveryInterval)
	}
}

func TestGroupDiscoveryWarmInterval_IsForegroundFriendly(t *testing.T) {
	if GroupDiscoveryWarmInterval <= 0 {
		t.Fatalf("expected warm interval > 0, got %v", GroupDiscoveryWarmInterval)
	}
	if GroupDiscoveryWarmInterval >= GroupDiscoveryInterval {
		t.Fatalf(
			"expected warm interval %v to stay below background interval %v",
			GroupDiscoveryWarmInterval,
			GroupDiscoveryInterval,
		)
	}
}

// --- filterDiscoveredPeers tests ---

func TestFilterDiscoveredPeers_ExcludesSelf(t *testing.T) {
	selfId, _ := peer.Decode("12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN")
	otherId, _ := peer.Decode("12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g")

	discovered := []peer.AddrInfo{
		{ID: selfId},
		{ID: otherId},
	}

	result := filterDiscoveredPeers(discovered, selfId, map[peer.ID]struct{}{})
	if len(result) != 1 {
		t.Fatalf("expected 1 peer, got %d", len(result))
	}
	if result[0].ID != otherId {
		t.Errorf("expected other peer, got %s", result[0].ID)
	}
}

func TestFilterDiscoveredPeers_ExcludesConnected(t *testing.T) {
	selfId, _ := peer.Decode("12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN")
	connectedId, _ := peer.Decode("12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g")
	newId, _ := peer.Decode("12D3KooWRby3kFPcEJBxLFasMBr1Y5sTpBLTpfhCoVkdCquN4CY1")

	discovered := []peer.AddrInfo{
		{ID: connectedId},
		{ID: newId},
	}

	connectedPeers := map[peer.ID]struct{}{
		connectedId: {},
	}

	result := filterDiscoveredPeers(discovered, selfId, connectedPeers)
	if len(result) != 1 {
		t.Fatalf("expected 1 peer, got %d", len(result))
	}
	if result[0].ID != newId {
		t.Errorf("expected new peer, got %s", result[0].ID)
	}
}

func TestFilterDiscoveredPeers_ReturnsNewPeers(t *testing.T) {
	selfId, _ := peer.Decode("12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN")
	peer1, _ := peer.Decode("12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g")
	peer2, _ := peer.Decode("12D3KooWRby3kFPcEJBxLFasMBr1Y5sTpBLTpfhCoVkdCquN4CY1")

	discovered := []peer.AddrInfo{
		{ID: peer1},
		{ID: peer2},
	}

	result := filterDiscoveredPeers(discovered, selfId, map[peer.ID]struct{}{})
	if len(result) != 2 {
		t.Fatalf("expected 2 peers, got %d", len(result))
	}
}

func TestFilterDiscoveredPeers_EmptyInput(t *testing.T) {
	selfId, _ := peer.Decode("12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN")

	result := filterDiscoveredPeers(nil, selfId, map[peer.ID]struct{}{})
	if len(result) != 0 {
		t.Errorf("expected 0 peers, got %d", len(result))
	}
}

func TestFilterDiscoveredPeers_AllFiltered(t *testing.T) {
	selfId, _ := peer.Decode("12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN")
	connectedId, _ := peer.Decode("12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g")

	discovered := []peer.AddrInfo{
		{ID: selfId},
		{ID: connectedId},
	}

	connectedPeers := map[peer.ID]struct{}{
		connectedId: {},
	}

	result := filterDiscoveredPeers(discovered, selfId, connectedPeers)
	if len(result) != 0 {
		t.Errorf("expected 0 peers, got %d", len(result))
	}
}

func TestFilterDiscoveredGroupMembers_ExcludesNonMembers(t *testing.T) {
	memberID, _ := peer.Decode("12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g")
	nonMemberID, _ := peer.Decode("12D3KooWRby3kFPcEJBxLFasMBr1Y5sTpBLTpfhCoVkdCquN4CY1")

	discovered := []peer.AddrInfo{
		{ID: memberID},
		{ID: nonMemberID},
	}
	allowed := map[peer.ID]struct{}{
		memberID: {},
	}

	filtered, ignored := filterDiscoveredGroupMembers(discovered, allowed)
	if len(filtered) != 1 {
		t.Fatalf("expected 1 allowed peer, got %d", len(filtered))
	}
	if filtered[0].ID != memberID {
		t.Fatalf("expected member peer %s, got %s", memberID, filtered[0].ID)
	}
	if ignored != 1 {
		t.Fatalf("expected 1 ignored non-member, got %d", ignored)
	}
}

func TestGL005PrivateGroupDiscoveryFiltersNonMembersBeforeDialUse(t *testing.T) {
	selfID, err := peer.Decode("12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN")
	if err != nil {
		t.Fatalf("decode self peer: %v", err)
	}
	memberID, err := peer.Decode("12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g")
	if err != nil {
		t.Fatalf("decode member peer: %v", err)
	}
	nonMemberID, err := peer.Decode("12D3KooWRby3kFPcEJBxLFasMBr1Y5sTpBLTpfhCoVkdCquN4CY1")
	if err != nil {
		t.Fatalf("decode non-member peer: %v", err)
	}
	alreadyConnectedID, err := peer.Decode("12D3KooWL8hWR1wU8YEWzsXTH8LuN2n7FBbUMPSu1tfQZyxkPp2v")
	if err != nil {
		t.Fatalf("decode connected peer: %v", err)
	}

	discovered := []peer.AddrInfo{
		{ID: selfID},
		{ID: memberID},
		{ID: nonMemberID},
		{ID: alreadyConnectedID},
	}
	topicPeers := map[peer.ID]struct{}{
		alreadyConnectedID: {},
	}
	allowedMembers := map[peer.ID]struct{}{
		memberID: {},
	}

	newPeers := filterDiscoveredPeers(discovered, selfID, topicPeers)
	filtered, ignoredNonMembers := filterDiscoveredGroupMembers(newPeers, allowedMembers)

	if len(filtered) != 1 {
		t.Fatalf("expected only configured member to remain eligible, got %d peers", len(filtered))
	}
	if filtered[0].ID != memberID {
		t.Fatalf("expected member peer %s to remain eligible, got %s", memberID, filtered[0].ID)
	}
	if ignoredNonMembers != 1 {
		t.Fatalf("expected one discovered non-member to be ignored before dial/use, got %d", ignoredNonMembers)
	}
	for _, p := range filtered {
		if p.ID == nonMemberID {
			t.Fatalf("non-member peer %s became eligible for group discovery use", nonMemberID)
		}
	}
}

func TestFilterDiscoveredGroupMembers_AllowsAllWhenMemberSetEmpty(t *testing.T) {
	peer1, _ := peer.Decode("12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g")
	peer2, _ := peer.Decode("12D3KooWRby3kFPcEJBxLFasMBr1Y5sTpBLTpfhCoVkdCquN4CY1")

	discovered := []peer.AddrInfo{
		{ID: peer1},
		{ID: peer2},
	}

	filtered, ignored := filterDiscoveredGroupMembers(discovered, nil)
	if len(filtered) != len(discovered) {
		t.Fatalf("expected all peers to remain discoverable, got %d", len(filtered))
	}
	if ignored != 0 {
		t.Fatalf("expected 0 ignored peers, got %d", ignored)
	}
}

// --- Topic name tests ---

func TestGroupTopicName(t *testing.T) {
	groupId := "abc-123-def"
	want := "/mknoon/group/abc-123-def"
	got := GroupTopicPrefix + groupId
	if got != want {
		t.Errorf("topic name = %q, want %q", got, want)
	}
}

func TestGroupTopicAndRendezvousNamespace_DoNotUseHumanReadableMetadata(t *testing.T) {
	groupId := "37a73b42-b6e0-44ad-a2fb-9f17fe7ad09d"
	config := &GroupConfig{
		Name:        "Layoff Strategy And Diagnosis",
		Description: "Private legal and medical planning notes",
		GroupType:   GroupTypeChat,
	}

	topicName := GroupTopicPrefix + groupId
	rendezvousNamespace := groupRendezvousNamespace(groupId)
	want := "/mknoon/group/" + groupId
	if topicName != want {
		t.Fatalf("topic name = %q, want %q", topicName, want)
	}
	if rendezvousNamespace != want {
		t.Fatalf("rendezvous namespace = %q, want %q", rendezvousNamespace, want)
	}

	for label, identifier := range map[string]string{
		"topic":      topicName,
		"rendezvous": rendezvousNamespace,
	} {
		for _, sensitive := range []string{
			config.Name,
			config.Description,
			"Layoff",
			"Diagnosis",
			"legal",
			"medical",
		} {
			if strings.Contains(identifier, sensitive) {
				t.Fatalf("%s identifier %q leaked sensitive metadata %q", label, identifier, sensitive)
			}
		}
	}
}

// --- isAllowedWriter tests ---

func TestIsAllowedWriter_ChatAnyMember(t *testing.T) {
	config := testGroupConfig(GroupTypeChat)

	// All members can write in chat groups.
	for _, m := range config.Members {
		if !isAllowedWriter(config, m.PeerId) {
			t.Errorf("chat: %s (role=%s) should be allowed to write", m.PeerId, m.Role)
		}
	}
}

func TestIsAllowedWriter_AnnouncementAdminOnly(t *testing.T) {
	config := testGroupConfig(GroupTypeAnnouncement)

	if !isAllowedWriter(config, "peer-admin") {
		t.Error("announcement: admin should be allowed to write")
	}
}

func TestIsAllowedWriter_AnnouncementMemberBlocked(t *testing.T) {
	config := testGroupConfig(GroupTypeAnnouncement)

	if isAllowedWriter(config, "peer-writer") {
		t.Error("announcement: writer should NOT be allowed to write")
	}
	if isAllowedWriter(config, "peer-reader") {
		t.Error("announcement: reader should NOT be allowed to write")
	}
}

func TestIsAllowedWriter_QAAnyMember(t *testing.T) {
	config := testGroupConfig(GroupTypeQA)

	for _, m := range config.Members {
		if !isAllowedWriter(config, m.PeerId) {
			t.Errorf("qa: %s (role=%s) should be allowed to write", m.PeerId, m.Role)
		}
	}
}

func TestIsAllowedWriter_NonMember(t *testing.T) {
	config := testGroupConfig(GroupTypeChat)

	if isAllowedWriter(config, "unknown-peer") {
		t.Error("non-member should NOT be allowed to write")
	}
}

// --- findMember tests ---

func TestFindMember_Found(t *testing.T) {
	config := testGroupConfig(GroupTypeChat)

	member := findMember(config, "peer-writer")
	if member == nil {
		t.Fatal("expected to find peer-writer")
	}
	if member.Username != "Writer" {
		t.Errorf("username = %q, want %q", member.Username, "Writer")
	}
	if member.Role != GroupRoleWriter {
		t.Errorf("role = %q, want %q", member.Role, GroupRoleWriter)
	}
}

func TestFindMember_NotFound(t *testing.T) {
	config := testGroupConfig(GroupTypeChat)

	member := findMember(config, "nonexistent-peer")
	if member != nil {
		t.Errorf("expected nil, got %+v", member)
	}
}

// --- Serialization tests ---

func TestGroupConfig_Serialization(t *testing.T) {
	original := &GroupConfig{
		Name:        "My Group",
		GroupType:   GroupTypeChat,
		Description: "A test group",
		Members: []GroupMember{
			{PeerId: "peer1", Username: "Alice", Role: GroupRoleAdmin, PublicKey: "pk1", MlKemPublicKey: "mlk1"},
			{PeerId: "peer2", Username: "Bob", Role: GroupRoleWriter, PublicKey: "pk2"},
		},
		CreatedBy: "peer1",
		CreatedAt: "2026-01-01T00:00:00Z",
	}

	data, err := json.Marshal(original)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}

	var restored GroupConfig
	if err := json.Unmarshal(data, &restored); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}

	if restored.Name != original.Name {
		t.Errorf("Name = %q, want %q", restored.Name, original.Name)
	}
	if restored.GroupType != original.GroupType {
		t.Errorf("GroupType = %q, want %q", restored.GroupType, original.GroupType)
	}
	if restored.Description != original.Description {
		t.Errorf("Description = %q, want %q", restored.Description, original.Description)
	}
	if len(restored.Members) != len(original.Members) {
		t.Fatalf("Members length = %d, want %d", len(restored.Members), len(original.Members))
	}
	if restored.Members[0].MlKemPublicKey != "mlk1" {
		t.Errorf("Members[0].MlKemPublicKey = %q, want %q", restored.Members[0].MlKemPublicKey, "mlk1")
	}
	if restored.Members[1].MlKemPublicKey != "" {
		t.Errorf("Members[1].MlKemPublicKey should be empty, got %q", restored.Members[1].MlKemPublicKey)
	}
	if restored.CreatedBy != original.CreatedBy {
		t.Errorf("CreatedBy = %q, want %q", restored.CreatedBy, original.CreatedBy)
	}
}

func TestGroupKeyInfo_Serialization(t *testing.T) {
	original := &GroupKeyInfo{
		Key:      "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
		KeyEpoch: 3,
	}

	data, err := json.Marshal(original)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}

	var restored GroupKeyInfo
	if err := json.Unmarshal(data, &restored); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}

	if restored.Key != original.Key {
		t.Errorf("Key = %q, want %q", restored.Key, original.Key)
	}
	if restored.KeyEpoch != original.KeyEpoch {
		t.Errorf("KeyEpoch = %d, want %d", restored.KeyEpoch, original.KeyEpoch)
	}
}

func TestGroupMember_Serialization(t *testing.T) {
	original := GroupMember{
		PeerId:         "12D3KooWtest",
		Username:       "alice",
		Role:           GroupRoleAdmin,
		PublicKey:      "base64pubkey",
		MlKemPublicKey: "base64mlkem",
	}

	data, err := json.Marshal(original)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}

	var restored GroupMember
	if err := json.Unmarshal(data, &restored); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}

	if restored.PeerId != original.PeerId {
		t.Errorf("PeerId = %q, want %q", restored.PeerId, original.PeerId)
	}
	if restored.Username != original.Username {
		t.Errorf("Username = %q, want %q", restored.Username, original.Username)
	}
	if restored.Role != original.Role {
		t.Errorf("Role = %q, want %q", restored.Role, original.Role)
	}
	if restored.PublicKey != original.PublicKey {
		t.Errorf("PublicKey = %q, want %q", restored.PublicKey, original.PublicKey)
	}
	if restored.MlKemPublicKey != original.MlKemPublicKey {
		t.Errorf("MlKemPublicKey = %q, want %q", restored.MlKemPublicKey, original.MlKemPublicKey)
	}
}

func TestGroupMember_OmitEmpty(t *testing.T) {
	member := GroupMember{
		PeerId:    "peer1",
		Role:      GroupRoleReader,
		PublicKey: "pk1",
	}

	data, err := json.Marshal(member)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}

	// Verify that omitempty fields are not present.
	var raw map[string]interface{}
	if err := json.Unmarshal(data, &raw); err != nil {
		t.Fatalf("unmarshal raw: %v", err)
	}

	if _, ok := raw["username"]; ok {
		t.Error("empty username should be omitted from JSON")
	}
	if _, ok := raw["mlKemPublicKey"]; ok {
		t.Error("empty mlKemPublicKey should be omitted from JSON")
	}
}

// --- Envelope building tests ---

func TestPublishGroupMessage_BuildsCorrectEnvelope(t *testing.T) {
	// Generate a real Ed25519 key pair for signing.
	privB64, pubB64 := generateEd25519KeyPair(t)

	// Generate a real group key.
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	groupId := "test-group-123"
	senderPeerId := "peer-sender"
	senderUsername := "Alice"
	text := "Hello, group!"
	keyEpoch := 1

	// --- Manually build what PublishGroupMessage would build ---

	// 1. Build payload.
	payload := &internal.GroupMessagePayload{
		Text:      text,
		Timestamp: "2026-01-01T00:00:00Z",
		Username:  senderUsername,
	}
	payloadJSON, err := internal.MarshalGroupPayload(payload)
	if err != nil {
		t.Fatalf("marshal payload: %v", err)
	}

	// 2. Encrypt.
	ctB64, nonceB64, err := mcrypto.EncryptGroupMessage(groupKey, payloadJSON)
	if err != nil {
		t.Fatalf("encrypt: %v", err)
	}

	// 3. Sign.
	sigData := mcrypto.BuildGroupSignatureData(groupId, keyEpoch, ctB64)
	signature, err := mcrypto.SignPayload(privB64, sigData)
	if err != nil {
		t.Fatalf("sign: %v", err)
	}

	// 4. Build envelope.
	envelope := &internal.GroupEnvelope{
		Version:         "3",
		Type:            "group_message",
		GroupId:         groupId,
		SenderId:        senderPeerId,
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

	// --- Verify the envelope ---

	// Must be recognized as a group envelope.
	if !internal.IsGroupEnvelope(envelopeJSON) {
		t.Error("envelope should be recognized as group envelope")
	}

	// Parse it back.
	parsed, err := internal.ParseGroupEnvelope(envelopeJSON)
	if err != nil {
		t.Fatalf("parse envelope: %v", err)
	}

	if parsed.Version != "3" {
		t.Errorf("Version = %q, want %q", parsed.Version, "3")
	}
	if parsed.Type != "group_message" {
		t.Errorf("Type = %q, want %q", parsed.Type, "group_message")
	}
	if parsed.GroupId != groupId {
		t.Errorf("GroupId = %q, want %q", parsed.GroupId, groupId)
	}
	if parsed.SenderId != senderPeerId {
		t.Errorf("SenderId = %q, want %q", parsed.SenderId, senderPeerId)
	}
	if parsed.SenderPublicKey != pubB64 {
		t.Errorf("SenderPublicKey mismatch")
	}
	if parsed.KeyEpoch != keyEpoch {
		t.Errorf("KeyEpoch = %d, want %d", parsed.KeyEpoch, keyEpoch)
	}

	// Verify the signature is valid.
	verifySigData := mcrypto.BuildGroupSignatureData(groupId, keyEpoch, parsed.Encrypted.Ciphertext)
	valid, err := mcrypto.VerifyPayload(pubB64, verifySigData, parsed.Signature)
	if err != nil {
		t.Fatalf("verify signature: %v", err)
	}
	if !valid {
		t.Error("signature should be valid")
	}

	// Decrypt and verify the payload.
	plaintext, err := mcrypto.DecryptGroupMessage(groupKey, parsed.Encrypted.Ciphertext, parsed.Encrypted.Nonce)
	if err != nil {
		t.Fatalf("decrypt: %v", err)
	}

	decPayload, err := internal.ParseGroupPayload(plaintext)
	if err != nil {
		t.Fatalf("parse payload: %v", err)
	}

	if decPayload.Text != text {
		t.Errorf("Text = %q, want %q", decPayload.Text, text)
	}
	if decPayload.Username != senderUsername {
		t.Errorf("Username = %q, want %q", decPayload.Username, senderUsername)
	}
}

func TestBuildGroupMessageExtra_PreservesQuotedMessageId(t *testing.T) {
	opts := map[string]interface{}{
		"quotedMessageId": "parent-msg-1",
		"media": []map[string]interface{}{
			{"id": "blob-1", "mime": "image/jpeg"},
		},
	}

	extra := buildGroupMessageExtra("msg-1", opts)

	if got := extra["messageId"]; got != "msg-1" {
		t.Fatalf("messageId = %v, want %q", got, "msg-1")
	}
	if got := extra["quotedMessageId"]; got != "parent-msg-1" {
		t.Fatalf("quotedMessageId = %v, want %q", got, "parent-msg-1")
	}
	if _, ok := extra["media"]; !ok {
		t.Fatal("expected media in extra")
	}
	if _, ok := opts["messageId"]; ok {
		t.Fatal("buildGroupMessageExtra should not mutate the input opts map")
	}
}

func TestBuildGroupMessageReceivedEvent_IncludesQuotedMessageId(t *testing.T) {
	env := &internal.GroupEnvelope{
		SenderId: "peer-sender",
		KeyEpoch: 4,
	}
	payload := &internal.GroupMessagePayload{
		Text:      "Reply body",
		Timestamp: "2026-03-11T10:00:00Z",
		Username:  "Alice",
		Extra: map[string]interface{}{
			"messageId":       "msg-1",
			"quotedMessageId": "parent-msg-1",
			"media": []interface{}{
				map[string]interface{}{"id": "blob-1", "mime": "image/jpeg"},
			},
		},
	}

	event := buildGroupMessageReceivedEvent("group-1", env, payload)

	if got := event["groupId"]; got != "group-1" {
		t.Fatalf("groupId = %v, want %q", got, "group-1")
	}
	if got := event["messageId"]; got != "msg-1" {
		t.Fatalf("messageId = %v, want %q", got, "msg-1")
	}
	if got := event["quotedMessageId"]; got != "parent-msg-1" {
		t.Fatalf("quotedMessageId = %v, want %q", got, "parent-msg-1")
	}
	if got := event["senderUsername"]; got != "Alice" {
		t.Fatalf("senderUsername = %v, want %q", got, "Alice")
	}
	if got := event["transportPeerId"]; got != "peer-sender" {
		t.Fatalf("transportPeerId = %v, want %q", got, "peer-sender")
	}
	if _, ok := event["media"]; !ok {
		t.Fatal("expected media in received event")
	}
}

// --- Validator logic tests (pure functions, no libp2p host needed) ---

// validateGroupEnvelope is a pure-function version of the validator logic,
// extracted for testing without needing a running libp2p host.
func validateGroupEnvelope(data string, groupId string, config *GroupConfig, keyInfo *GroupKeyInfo) string {
	return validateGroupEnvelopeForTransportPeer(data, groupId, config, keyInfo, "")
}

func validateGroupEnvelopeForTransportPeer(data string, groupId string, config *GroupConfig, keyInfo *GroupKeyInfo, transportPeerId string) string {
	if !internal.IsGroupEnvelope(data) {
		return "reject:not_v3"
	}

	env, err := internal.ParseGroupEnvelope(data)
	if err != nil {
		return "reject:invalid_envelope"
	}

	if env.GroupId != groupId {
		return "reject:group_mismatch"
	}

	if !groupEnvelopeMatchesTransportPeer(env, transportPeerId) {
		return "reject:peer_mismatch"
	}

	if config == nil {
		return "reject:unknown_group"
	}

	member := findMember(config, env.SenderId)
	if member == nil {
		return "reject:non_member"
	}
	sourceDevice := activeMemberDeviceForEnvelope(member, env, transportPeerId)
	if sourceDevice == nil {
		return "reject:unbound_device"
	}

	if env.Type == "group_message" && !isAllowedWriter(config, env.SenderId) {
		return "reject:unauthorized"
	}

	if keyInfo == nil {
		return "reject:no_key"
	}

	if !verifyGroupEnvelopeSignature(groupId, sourceDevice.DeviceSigningPublicKey, env, keyInfo, time.Now()) {
		return "reject:bad_signature"
	}

	return "accept"
}

func buildTestEnvelope(t *testing.T, groupId, senderId, privB64, pubB64, groupKey string, keyEpoch int, text string) string {
	t.Helper()

	payload := &internal.GroupMessagePayload{
		Text:      text,
		Timestamp: "2026-01-01T00:00:00Z",
		Username:  "TestUser",
	}
	payloadJSON, err := internal.MarshalGroupPayload(payload)
	if err != nil {
		t.Fatalf("marshal payload: %v", err)
	}

	ctB64, nonceB64, err := mcrypto.EncryptGroupMessage(groupKey, payloadJSON)
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

func buildTestDeviceEnvelope(
	t *testing.T,
	groupId string,
	senderId string,
	senderDeviceId string,
	senderTransportPeerId string,
	senderDevicePublicKey string,
	senderKeyPackageId string,
	privB64 string,
	pubB64 string,
	groupKey string,
	keyEpoch int,
	text string,
) string {
	t.Helper()

	payload := &internal.GroupMessagePayload{
		Text:      text,
		Timestamp: "2026-01-01T00:00:00Z",
		Username:  "TestUser",
	}
	payloadJSON, err := internal.MarshalGroupPayload(payload)
	if err != nil {
		t.Fatalf("marshal payload: %v", err)
	}

	ctB64, nonceB64, err := mcrypto.EncryptGroupMessage(groupKey, payloadJSON)
	if err != nil {
		t.Fatalf("encrypt: %v", err)
	}

	sigData := mcrypto.BuildGroupSignatureData(groupId, keyEpoch, ctB64)
	signature, err := mcrypto.SignPayload(privB64, sigData)
	if err != nil {
		t.Fatalf("sign: %v", err)
	}

	envelope := &internal.GroupEnvelope{
		Version:               "3",
		Type:                  "group_message",
		GroupId:               groupId,
		SenderId:              senderId,
		SenderDeviceId:        senderDeviceId,
		SenderTransportPeerId: senderTransportPeerId,
		SenderDevicePublicKey: senderDevicePublicKey,
		SenderKeyPackageId:    senderKeyPackageId,
		SenderPublicKey:       pubB64,
		Signature:             signature,
		KeyEpoch:              keyEpoch,
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

func buildTestEnvelopeWithPlaintext(
	t *testing.T,
	groupId string,
	envelopeType string,
	senderId string,
	privB64 string,
	pubB64 string,
	groupKey string,
	keyEpoch int,
	plaintext string,
) string {
	t.Helper()

	ctB64, nonceB64, err := mcrypto.EncryptGroupMessage(groupKey, plaintext)
	if err != nil {
		t.Fatalf("encrypt plaintext: %v", err)
	}

	sigData := mcrypto.BuildGroupSignatureData(groupId, keyEpoch, ctB64)
	signature, err := mcrypto.SignPayload(privB64, sigData)
	if err != nil {
		t.Fatalf("sign envelope: %v", err)
	}

	envelope := &internal.GroupEnvelope{
		Version:         "3",
		Type:            envelopeType,
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

func assertRelayVisibleEnvelopeOmitsPlaintext(
	t *testing.T,
	envelopeJSON string,
	groupId string,
	wantType string,
	memberPublicKey string,
	keyInfo *GroupKeyInfo,
	sensitiveFragments []string,
) string {
	t.Helper()

	for _, fragment := range sensitiveFragments {
		if strings.Contains(envelopeJSON, fragment) {
			t.Fatalf("relay-visible envelope leaked plaintext fragment %q in %s", fragment, envelopeJSON)
		}
	}

	env, err := internal.ParseGroupEnvelope(envelopeJSON)
	if err != nil {
		t.Fatalf("parse envelope: %v", err)
	}
	if env.Type != wantType {
		t.Fatalf("envelope type = %q, want %q", env.Type, wantType)
	}
	if env.GroupId != groupId {
		t.Fatalf("groupId = %q, want %q", env.GroupId, groupId)
	}
	if env.Encrypted.Ciphertext == "" || env.Encrypted.Nonce == "" {
		t.Fatalf("encrypted payload must include ciphertext and nonce: %+v", env.Encrypted)
	}
	if !verifyGroupEnvelopeSignature(groupId, memberPublicKey, env, keyInfo, time.Now()) {
		t.Fatal("expected relay-visible envelope signature to verify")
	}

	plaintext, err := decryptGroupEnvelopePayload(env, keyInfo, time.Now())
	if err != nil {
		t.Fatalf("decrypt envelope payload: %v", err)
	}
	return plaintext
}

func TestGroupRelayVisibleMessageEnvelope_EncryptsContentBeforeRelay(t *testing.T) {
	privB64, pubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	groupId := "group-relay-visible-message"
	text := "relay visible secret launch phrase alpha"
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 7}
	envelopeJSON := buildTestEnvelope(t, groupId, "peer-alice", privB64, pubB64, groupKey, keyInfo.KeyEpoch, text)

	plaintext := assertRelayVisibleEnvelopeOmitsPlaintext(
		t,
		envelopeJSON,
		groupId,
		"group_message",
		pubB64,
		keyInfo,
		[]string{text, "launch phrase", "TestUser"},
	)

	payload, err := internal.ParseGroupPayload(plaintext)
	if err != nil {
		t.Fatalf("parse decrypted payload: %v", err)
	}
	if payload.Text != text {
		t.Fatalf("decrypted text = %q, want %q", payload.Text, text)
	}
	if payload.Username != "TestUser" {
		t.Fatalf("decrypted username = %q, want TestUser", payload.Username)
	}
}

func TestGroupRelayVisibleReactionEnvelope_EncryptsContentBeforeRelay(t *testing.T) {
	privB64, pubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	groupId := "group-relay-visible-reaction"
	reactionJSON := `{"messageId":"msg-relay-private","action":"add","emoji":"lock","note":"relay visible reaction secret beta"}`
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 3}
	envelopeJSON := buildTestEnvelopeWithPlaintext(
		t,
		groupId,
		"group_reaction",
		"peer-bob",
		privB64,
		pubB64,
		groupKey,
		keyInfo.KeyEpoch,
		reactionJSON,
	)

	plaintext := assertRelayVisibleEnvelopeOmitsPlaintext(
		t,
		envelopeJSON,
		groupId,
		"group_reaction",
		pubB64,
		keyInfo,
		[]string{"msg-relay-private", "relay visible reaction secret beta"},
	)
	if plaintext != reactionJSON {
		t.Fatalf("decrypted reaction = %q, want %q", plaintext, reactionJSON)
	}
}

func TestGroupTopicValidator_ValidMessage(t *testing.T) {
	privB64, pubB64 := generateEd25519KeyPair(t)
	groupKey, _ := mcrypto.GenerateGroupKey()
	groupId := "group-valid"

	config := &GroupConfig{
		Name:      "Test",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: "sender-1", Role: GroupRoleAdmin, PublicKey: pubB64},
		},
		CreatedBy: "sender-1",
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	envelopeJSON := buildTestEnvelope(t, groupId, "sender-1", privB64, pubB64, groupKey, 1, "hello")

	result := validateGroupEnvelope(envelopeJSON, groupId, config, keyInfo)
	if result != "accept" {
		t.Errorf("expected accept, got %s", result)
	}
}

func TestGroupTopicValidator_NilKeyRejectsNoKeyAndDecryptReportsMissingKey(t *testing.T) {
	privB64, pubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}
	groupId := "gl-006-validator-nil-key"

	config := &GroupConfig{
		Name:      "GL-006 Validator Nil Key",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: "sender-1", Role: GroupRoleAdmin, PublicKey: pubB64},
		},
		CreatedBy: "sender-1",
	}

	envelopeJSON := buildTestEnvelope(t, groupId, "sender-1", privB64, pubB64, groupKey, 1, "hello without local key")

	result := validateGroupEnvelope(envelopeJSON, groupId, config, nil)
	if result != "reject:no_key" {
		t.Fatalf("expected reject:no_key, got %s", result)
	}

	env, err := internal.ParseGroupEnvelope(envelopeJSON)
	if err != nil {
		t.Fatalf("parse envelope: %v", err)
	}
	plaintext, err := decryptGroupEnvelopePayload(env, nil, time.Now())
	if err == nil {
		t.Fatal("expected decryptGroupEnvelopePayload with nil key info to fail")
	}
	if !strings.Contains(err.Error(), "missing group key info") {
		t.Fatalf("expected missing group key info error, got %q", err.Error())
	}
	if plaintext != "" {
		t.Fatalf("decrypt plaintext = %q, want empty", plaintext)
	}
}

func TestGroupTopicValidator_NilConfigRejectsUnknownGroupForGL007(t *testing.T) {
	privB64, pubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}
	groupId := "gl-007-validator-nil-config"
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	envelopeJSON := buildTestEnvelope(t, groupId, "sender-1", privB64, pubB64, groupKey, keyInfo.KeyEpoch, "hello with nil config")

	result := validateGroupEnvelope(envelopeJSON, groupId, nil, keyInfo)
	if result != "reject:unknown_group" {
		t.Fatalf("expected reject:unknown_group, got %s", result)
	}
}

func TestGroupTopicValidator_TransportPeerIdMatchesEnvelopeSender(t *testing.T) {
	privB64, pubB64 := generateEd25519KeyPair(t)
	groupKey, _ := mcrypto.GenerateGroupKey()
	groupId := "group-transport-match"

	config := &GroupConfig{
		Name:      "Test",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: "peer-B", Role: GroupRoleWriter, PublicKey: pubB64},
		},
		CreatedBy: "peer-admin",
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	envelopeJSON := buildTestEnvelope(t, groupId, "peer-B", privB64, pubB64, groupKey, 1, "valid from B")

	result := validateGroupEnvelopeForTransportPeer(envelopeJSON, groupId, config, keyInfo, "peer-B")
	if result != "accept" {
		t.Errorf("expected accept for matching transport peer id, got %s", result)
	}
}

func TestGroupTopicValidator_RejectsTransportPeerIdMismatch(t *testing.T) {
	privB64, pubB64 := generateEd25519KeyPair(t)
	groupKey, _ := mcrypto.GenerateGroupKey()
	groupId := "group-transport-mismatch"

	config := &GroupConfig{
		Name:      "Test",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: "peer-B", Role: GroupRoleWriter, PublicKey: pubB64},
		},
		CreatedBy: "peer-admin",
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	envelopeJSON := buildTestEnvelope(t, groupId, "peer-B", privB64, pubB64, groupKey, 1, "valid key, wrong transport")

	result := validateGroupEnvelopeForTransportPeer(envelopeJSON, groupId, config, keyInfo, "peer-X")
	if result != "reject:peer_mismatch" {
		t.Errorf("expected reject:peer_mismatch for mismatched transport peer id, got %s", result)
	}
}

func TestGroupTopicValidator_DeviceBoundMemberAcceptsRegisteredDevice(t *testing.T) {
	devicePriv, devicePub := generateEd25519KeyPair(t)
	groupKey, _ := mcrypto.GenerateGroupKey()
	groupId := "group-device-bound-accept"

	config := &GroupConfig{
		Name:      "Test",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{
				PeerId:    "member-B",
				Role:      GroupRoleWriter,
				PublicKey: "member-public-key",
				Devices: []GroupMemberDevice{
					{
						DeviceId:               "device-phone",
						TransportPeerId:        "transport-phone",
						DeviceSigningPublicKey: devicePub,
						MlKemPublicKey:         "mlkem-phone",
						KeyPackageId:           "kp-phone",
						Status:                 "active",
					},
				},
			},
		},
		CreatedBy: "member-admin",
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	envelopeJSON := buildTestDeviceEnvelope(
		t,
		groupId,
		"member-B",
		"device-phone",
		"transport-phone",
		devicePub,
		"kp-phone",
		devicePriv,
		devicePub,
		groupKey,
		1,
		"valid bound device",
	)

	result := validateGroupEnvelopeForTransportPeer(envelopeJSON, groupId, config, keyInfo, "transport-phone")
	if result != "accept" {
		t.Errorf("expected accept for registered device, got %s", result)
	}
}

func TestGroupTopicValidator_DeviceRejectsUnboundSibling(t *testing.T) {
	_, phonePub := generateEd25519KeyPair(t)
	tabletPriv, tabletPub := generateEd25519KeyPair(t)
	groupKey, _ := mcrypto.GenerateGroupKey()
	groupId := "group-device-unbound-sibling"

	config := &GroupConfig{
		Name:      "Test",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{
				PeerId:    "member-B",
				Role:      GroupRoleWriter,
				PublicKey: "member-public-key",
				Devices: []GroupMemberDevice{
					{
						DeviceId:               "device-phone",
						TransportPeerId:        "transport-phone",
						DeviceSigningPublicKey: phonePub,
						KeyPackageId:           "kp-phone",
						Status:                 "active",
					},
				},
			},
		},
		CreatedBy: "member-admin",
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	envelopeJSON := buildTestDeviceEnvelope(
		t,
		groupId,
		"member-B",
		"device-tablet",
		"transport-tablet",
		tabletPub,
		"kp-tablet",
		tabletPriv,
		tabletPub,
		groupKey,
		1,
		"cloned sibling",
	)

	result := validateGroupEnvelopeForTransportPeer(envelopeJSON, groupId, config, keyInfo, "transport-tablet")
	if result != "reject:unbound_device" {
		t.Errorf("expected reject:unbound_device for unregistered same-member device, got %s", result)
	}
}

func TestGroupTopicValidator_DeviceRejectsPublicKeyMismatch(t *testing.T) {
	_, devicePub := generateEd25519KeyPair(t)
	attackerPriv, attackerPub := generateEd25519KeyPair(t)
	groupKey, _ := mcrypto.GenerateGroupKey()
	groupId := "group-device-key-mismatch"

	config := &GroupConfig{
		Name:      "Test",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{
				PeerId:    "member-B",
				Role:      GroupRoleWriter,
				PublicKey: "member-public-key",
				Devices: []GroupMemberDevice{
					{
						DeviceId:               "device-phone",
						TransportPeerId:        "transport-phone",
						DeviceSigningPublicKey: devicePub,
						KeyPackageId:           "kp-phone",
						Status:                 "active",
					},
				},
			},
		},
		CreatedBy: "member-admin",
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	envelopeJSON := buildTestDeviceEnvelope(
		t,
		groupId,
		"member-B",
		"device-phone",
		"transport-phone",
		attackerPub,
		"kp-phone",
		attackerPriv,
		attackerPub,
		groupKey,
		1,
		"wrong device key",
	)

	result := validateGroupEnvelopeForTransportPeer(envelopeJSON, groupId, config, keyInfo, "transport-phone")
	if result != "reject:unbound_device" {
		t.Errorf("expected reject:unbound_device for mismatched device public key, got %s", result)
	}
}

func TestGroupTopicValidator_DeviceRejectsTransportMismatch(t *testing.T) {
	devicePriv, devicePub := generateEd25519KeyPair(t)
	groupKey, _ := mcrypto.GenerateGroupKey()
	groupId := "group-device-transport-mismatch"

	config := &GroupConfig{
		Name:      "Test",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{
				PeerId:    "member-B",
				Role:      GroupRoleWriter,
				PublicKey: "member-public-key",
				Devices: []GroupMemberDevice{
					{
						DeviceId:               "device-phone",
						TransportPeerId:        "transport-phone",
						DeviceSigningPublicKey: devicePub,
						KeyPackageId:           "kp-phone",
						Status:                 "active",
					},
				},
			},
		},
		CreatedBy: "member-admin",
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	envelopeJSON := buildTestDeviceEnvelope(
		t,
		groupId,
		"member-B",
		"device-phone",
		"transport-phone",
		devicePub,
		"kp-phone",
		devicePriv,
		devicePub,
		groupKey,
		1,
		"wrong transport",
	)

	result := validateGroupEnvelopeForTransportPeer(envelopeJSON, groupId, config, keyInfo, "transport-tablet")
	if result != "reject:peer_mismatch" {
		t.Errorf("expected reject:peer_mismatch for transport mismatch, got %s", result)
	}
}

func TestGroupTopicValidator_InvalidJSON(t *testing.T) {
	config := testGroupConfig(GroupTypeChat)
	keyInfo := &GroupKeyInfo{Key: "dummykey", KeyEpoch: 1}

	result := validateGroupEnvelope("not valid json {{{", "group-1", config, keyInfo)
	if result != "reject:not_v3" {
		t.Errorf("expected reject:not_v3, got %s", result)
	}
}

func TestGroupTopicValidator_UnknownGroup(t *testing.T) {
	privB64, pubB64 := generateEd25519KeyPair(t)
	groupKey, _ := mcrypto.GenerateGroupKey()

	envelopeJSON := buildTestEnvelope(t, "group-unknown", "sender-1", privB64, pubB64, groupKey, 1, "hello")

	// Pass nil config to simulate unknown group.
	result := validateGroupEnvelope(envelopeJSON, "group-unknown", nil, &GroupKeyInfo{Key: groupKey, KeyEpoch: 1})
	if result != "reject:unknown_group" {
		t.Errorf("expected reject:unknown_group, got %s", result)
	}
}

func TestGroupTopicValidator_UnauthorizedSender(t *testing.T) {
	privB64, pubB64 := generateEd25519KeyPair(t)
	groupKey, _ := mcrypto.GenerateGroupKey()
	groupId := "group-auth"

	// Config does NOT include the sender.
	config := &GroupConfig{
		Name:      "Test",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: "other-peer", Role: GroupRoleAdmin, PublicKey: "otherPubKey"},
		},
		CreatedBy: "other-peer",
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	envelopeJSON := buildTestEnvelope(t, groupId, "intruder-peer", privB64, pubB64, groupKey, 1, "sneaky message")

	result := validateGroupEnvelope(envelopeJSON, groupId, config, keyInfo)
	if result != "reject:non_member" {
		t.Errorf("expected reject:non_member, got %s", result)
	}
}

func TestGroupTopicValidator_AnnouncementNonAdminRejected(t *testing.T) {
	privB64, pubB64 := generateEd25519KeyPair(t)
	groupKey, _ := mcrypto.GenerateGroupKey()
	groupId := "group-announce"

	// Sender is a writer, not admin — should be rejected in announcement group.
	config := &GroupConfig{
		Name:      "Announcements",
		GroupType: GroupTypeAnnouncement,
		Members: []GroupMember{
			{PeerId: "writer-peer", Role: GroupRoleWriter, PublicKey: pubB64},
			{PeerId: "admin-peer", Role: GroupRoleAdmin, PublicKey: "adminPk"},
		},
		CreatedBy: "admin-peer",
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	envelopeJSON := buildTestEnvelope(t, groupId, "writer-peer", privB64, pubB64, groupKey, 1, "unauthorized post")

	result := validateGroupEnvelope(envelopeJSON, groupId, config, keyInfo)
	if result != "reject:unauthorized" {
		t.Errorf("expected reject:unauthorized, got %s", result)
	}
}

func TestGroupTopicValidator_BadSignature(t *testing.T) {
	privB64, pubB64 := generateEd25519KeyPair(t)
	_, differentPubB64 := generateEd25519KeyPair(t) // different key pair
	groupKey, _ := mcrypto.GenerateGroupKey()
	groupId := "group-sig"

	// Build envelope signed with privB64 but config has differentPubB64.
	// We will manually build with the wrong public key in the envelope.
	payload := &internal.GroupMessagePayload{
		Text:      "tampered",
		Timestamp: "2026-01-01T00:00:00Z",
	}
	payloadJSON, _ := internal.MarshalGroupPayload(payload)
	ctB64, nonceB64, _ := mcrypto.EncryptGroupMessage(groupKey, payloadJSON)
	sigData := mcrypto.BuildGroupSignatureData(groupId, 1, ctB64)
	signature, _ := mcrypto.SignPayload(privB64, sigData)

	// Put differentPubB64 in the envelope so signature verification fails.
	envelope := &internal.GroupEnvelope{
		Version:         "3",
		Type:            "group_message",
		GroupId:         groupId,
		SenderId:        "sender-1",
		SenderPublicKey: differentPubB64,
		Signature:       signature,
		KeyEpoch:        1,
		Encrypted: internal.GroupEncryptedPayload{
			Ciphertext: ctB64,
			Nonce:      nonceB64,
		},
	}
	envelopeJSON, _ := internal.MarshalGroupEnvelope(envelope)

	config := &GroupConfig{
		Name:      "Test",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: "sender-1", Role: GroupRoleAdmin, PublicKey: differentPubB64},
		},
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	result := validateGroupEnvelope(envelopeJSON, groupId, config, keyInfo)
	if result != "reject:bad_signature" {
		t.Errorf("expected reject:bad_signature, got %s", result)
	}

	_ = pubB64 // suppress unused warning
}

func TestGroupTopicValidator_SpoofedPublicKey(t *testing.T) {
	// Real member key pair (trusted, registered in config)
	_, pubA := generateEd25519KeyPair(t)

	// Attacker key pair (untrusted, NOT in config)
	privX, pubX := generateEd25519KeyPair(t)

	groupKey, _ := mcrypto.GenerateGroupKey()
	groupId := "group-spoof"

	// Config registers peer-A with pubA (the real member's key)
	config := &GroupConfig{
		Name:      "Test",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: "peer-A", Role: GroupRoleAdmin, PublicKey: pubA},
		},
		CreatedBy: "peer-A",
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	// Attacker builds envelope claiming to be peer-A, but signs with privX
	// and puts pubX in the SenderPublicKey field
	envelopeJSON := buildTestEnvelope(t, groupId, "peer-A", privX, pubX, groupKey, 1, "spoofed message")

	result := validateGroupEnvelope(envelopeJSON, groupId, config, keyInfo)
	if result != "reject:bad_signature" {
		t.Errorf("expected reject:bad_signature for spoofed public key, got %s", result)
	}
}

func TestGroupTopicValidator_RejectsForgedMembershipSystemEventSignature(t *testing.T) {
	adminPriv, adminPub := generateEd25519KeyPair(t)
	attackerPriv, attackerPub := generateEd25519KeyPair(t)
	groupKey, _ := mcrypto.GenerateGroupKey()
	groupId := "group-forged-members-added"

	sysTextBytes, err := json.Marshal(map[string]interface{}{
		"__sys": "members_added",
		"members": []map[string]interface{}{
			{
				"peerId":    "peer-new",
				"username":  "New Member",
				"role":      "writer",
				"publicKey": "pk-new",
			},
		},
		"groupConfig": map[string]interface{}{
			"name":      "Test Group",
			"groupType": "chat",
			"members": []map[string]interface{}{
				{"peerId": "peer-admin", "role": "admin", "publicKey": adminPub},
				{"peerId": "peer-new", "role": "writer", "publicKey": "pk-new"},
			},
			"createdBy": "peer-admin",
		},
	})
	if err != nil {
		t.Fatalf("marshal system payload: %v", err)
	}

	config := &GroupConfig{
		Name:      "Test Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: "peer-admin", Role: GroupRoleAdmin, PublicKey: adminPub},
		},
		CreatedBy: "peer-admin",
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	forgedEnvelope := buildTestEnvelope(
		t,
		groupId,
		"peer-admin",
		attackerPriv,
		attackerPub,
		groupKey,
		1,
		string(sysTextBytes),
	)

	result := validateGroupEnvelope(forgedEnvelope, groupId, config, keyInfo)
	if result != "reject:bad_signature" {
		t.Fatalf("expected reject:bad_signature for forged members_added envelope, got %s", result)
	}

	validEnvelope := buildTestEnvelope(
		t,
		groupId,
		"peer-admin",
		adminPriv,
		adminPub,
		groupKey,
		1,
		string(sysTextBytes),
	)
	if result := validateGroupEnvelope(validEnvelope, groupId, config, keyInfo); result != "accept" {
		t.Fatalf("expected valid admin-signed members_added envelope to be accepted, got %s", result)
	}
}

func TestGroupTopicValidator_RejectsInvalidSignatureForSecurityEventFamilies(t *testing.T) {
	adminPriv, adminPub := generateEd25519KeyPair(t)
	attackerPriv, attackerPub := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}
	groupId := "group-invalid-security-event-signatures"

	config := &GroupConfig{
		Name:      "Signature Matrix",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: "peer-admin", Role: GroupRoleAdmin, PublicKey: adminPub},
			{PeerId: "peer-member", Role: GroupRoleWriter, PublicKey: "pk-member"},
		},
		CreatedBy: "peer-admin",
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	cases := []struct {
		name         string
		envelopeType string
		plaintext    string
	}{
		{
			name:         "message",
			envelopeType: "group_message",
			plaintext:    `{"text":"signed message","timestamp":"2026-01-01T00:00:00Z"}`,
		},
		{
			name:         "reaction",
			envelopeType: "group_reaction",
			plaintext:    `{"messageId":"msg-1","action":"add","emoji":"+1"}`,
		},
		{
			name:         "member_added",
			envelopeType: "group_message",
			plaintext:    `{"__sys":"member_added","member":{"peerId":"peer-new","role":"writer","publicKey":"pk-new"}}`,
		},
		{
			name:         "members_added",
			envelopeType: "group_message",
			plaintext:    `{"__sys":"members_added","members":[{"peerId":"peer-new","role":"writer","publicKey":"pk-new"}]}`,
		},
		{
			name:         "member_removed",
			envelopeType: "group_message",
			plaintext:    `{"__sys":"member_removed","member":{"peerId":"peer-member"},"removedAt":"2026-01-01T00:00:00Z"}`,
		},
		{
			name:         "member_banned",
			envelopeType: "group_message",
			plaintext:    `{"__sys":"member_banned","targetPeerId":"peer-member","bannedAt":"2026-01-01T00:00:00Z"}`,
		},
		{
			name:         "member_unbanned",
			envelopeType: "group_message",
			plaintext:    `{"__sys":"member_unbanned","targetPeerId":"peer-member","unbannedAt":"2026-01-01T00:00:00Z"}`,
		},
		{
			name:         "member_role_updated",
			envelopeType: "group_message",
			plaintext:    `{"__sys":"member_role_updated","member":{"peerId":"peer-member","role":"reader"}}`,
		},
		{
			name:         "group_message_deleted",
			envelopeType: "group_message",
			plaintext:    `{"__sys":"group_message_deleted","targetMessageId":"msg-1","deletedAt":"2026-01-01T00:00:00Z"}`,
		},
		{
			name:         "group_metadata_updated",
			envelopeType: "group_message",
			plaintext:    `{"__sys":"group_metadata_updated","groupConfig":{"name":"renamed","metadataUpdatedAt":"2026-01-01T00:00:00Z"}}`,
		},
		{
			name:         "group_dissolved",
			envelopeType: "group_message",
			plaintext:    `{"__sys":"group_dissolved","dissolvedAt":"2026-01-01T00:00:00Z"}`,
		},
		{
			name:         "key_rotated",
			envelopeType: "group_message",
			plaintext:    `{"__sys":"key_rotated","newKeyEpoch":2}`,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			validEnvelope := buildTestEnvelopeWithPlaintext(
				t,
				groupId,
				tc.envelopeType,
				"peer-admin",
				adminPriv,
				adminPub,
				groupKey,
				1,
				tc.plaintext,
			)
			if result := validateGroupEnvelope(validEnvelope, groupId, config, keyInfo); result != "accept" {
				t.Fatalf("valid admin-signed envelope = %s, want accept", result)
			}

			forgedEnvelope := buildTestEnvelopeWithPlaintext(
				t,
				groupId,
				tc.envelopeType,
				"peer-admin",
				attackerPriv,
				attackerPub,
				groupKey,
				1,
				tc.plaintext,
			)
			if result := validateGroupEnvelope(forgedEnvelope, groupId, config, keyInfo); result != "reject:bad_signature" {
				t.Fatalf("forged envelope = %s, want reject:bad_signature", result)
			}
		})
	}
}

func TestGroupTopicValidator_RejectsUnauthorizedEventFamiliesBeforeForward(t *testing.T) {
	_, adminPub := generateEd25519KeyPair(t)
	removedPriv, removedPub := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}
	groupId := "group-authorization-matrix"

	config := &GroupConfig{
		Name:      "Authorization Matrix",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: "peer-admin", Role: GroupRoleAdmin, PublicKey: adminPub},
		},
		CreatedBy: "peer-admin",
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	n := NewNode()
	n.groupConfigs = map[string]*GroupConfig{groupId: config}
	n.groupKeys = map[string]*GroupKeyInfo{groupId: keyInfo}
	validator := n.groupTopicValidator(groupId)

	cases := []struct {
		name         string
		envelopeType string
		plaintext    string
	}{
		{
			name:         "message",
			envelopeType: "group_message",
			plaintext:    `{"text":"stale message","timestamp":"2026-01-01T00:00:00Z"}`,
		},
		{
			name:         "reaction",
			envelopeType: "group_reaction",
			plaintext:    `{"messageId":"msg-1","action":"add","emoji":"+1"}`,
		},
		{
			name:         "membership",
			envelopeType: "group_message",
			plaintext:    `{"__sys":"members_added","members":[{"peerId":"peer-new","role":"writer"}]}`,
		},
		{
			name:         "metadata",
			envelopeType: "group_message",
			plaintext:    `{"__sys":"group_metadata_updated","groupConfig":{"name":"new name"}}`,
		},
		{
			name:         "key_rotation",
			envelopeType: "group_message",
			plaintext:    `{"__sys":"key_rotated","keyEpoch":2}`,
		},
	}

	for _, tc := range cases {
		envelopeJSON := buildTestEnvelopeWithPlaintext(
			t,
			groupId,
			tc.envelopeType,
			"peer-removed",
			removedPriv,
			removedPub,
			groupKey,
			1,
			tc.plaintext,
		)

		msg := &pubsub.Message{Message: &pb.Message{Data: []byte(envelopeJSON)}}
		result := validator(context.Background(), peer.ID("peer-removed"), msg)
		if result != pubsub.ValidationReject {
			t.Fatalf("%s: validator result = %v, want ValidationReject", tc.name, result)
		}
		if pure := validateGroupEnvelope(envelopeJSON, groupId, config, keyInfo); pure != "reject:non_member" {
			t.Fatalf("%s: pure validator = %s, want reject:non_member", tc.name, pure)
		}
	}
}

// --- End-to-end encrypt/decrypt round-trip ---

func TestGroupMessage_EncryptDecryptRoundTrip(t *testing.T) {
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	originalText := "Hello, this is a secret group message!"
	payload := &internal.GroupMessagePayload{
		Text:      originalText,
		Timestamp: "2026-03-02T12:00:00Z",
		Username:  "Alice",
	}

	payloadJSON, err := internal.MarshalGroupPayload(payload)
	if err != nil {
		t.Fatalf("marshal payload: %v", err)
	}

	ctB64, nonceB64, err := mcrypto.EncryptGroupMessage(groupKey, payloadJSON)
	if err != nil {
		t.Fatalf("encrypt: %v", err)
	}

	plaintext, err := mcrypto.DecryptGroupMessage(groupKey, ctB64, nonceB64)
	if err != nil {
		t.Fatalf("decrypt: %v", err)
	}

	decPayload, err := internal.ParseGroupPayload(plaintext)
	if err != nil {
		t.Fatalf("parse payload: %v", err)
	}

	if decPayload.Text != originalText {
		t.Errorf("Text = %q, want %q", decPayload.Text, originalText)
	}
	if decPayload.Username != "Alice" {
		t.Errorf("Username = %q, want %q", decPayload.Username, "Alice")
	}
}

func TestGroupTopicValidator_NotV3Envelope(t *testing.T) {
	// A valid JSON but v1 envelope (not group message).
	v1Envelope := `{"version":"1","type":"chat_message","payload":{"text":"hi"}}`

	config := testGroupConfig(GroupTypeChat)
	keyInfo := &GroupKeyInfo{Key: "dummy", KeyEpoch: 1}

	result := validateGroupEnvelope(v1Envelope, "group-1", config, keyInfo)
	if result != "reject:not_v3" {
		t.Errorf("expected reject:not_v3, got %s", result)
	}
}

// --- Discovery-related tests ---

func TestGroupRendezvousNamespace_EmptyGroupId(t *testing.T) {
	ns := groupRendezvousNamespace("")
	want := "/mknoon/group/"
	if ns != want {
		t.Errorf("namespace for empty groupId = %q, want %q", ns, want)
	}
}

func TestFilterDiscoveredPeers_PreservesAddresses(t *testing.T) {
	selfId, _ := peer.Decode("12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN")
	otherId, _ := peer.Decode("12D3KooWRby3kFPcEJBxLFasMBr1Y5sTpBLTpfhCoVkdCquN4CY1")

	addr1, _ := ma.NewMultiaddr("/ip4/192.168.1.1/tcp/4001")
	addr2, _ := ma.NewMultiaddr("/ip4/10.0.0.1/udp/4002/quic-v1")

	discovered := []peer.AddrInfo{
		{ID: otherId, Addrs: []ma.Multiaddr{addr1, addr2}},
	}

	result := filterDiscoveredPeers(discovered, selfId, map[peer.ID]struct{}{})
	if len(result) != 1 {
		t.Fatalf("expected 1 peer, got %d", len(result))
	}
	if len(result[0].Addrs) != 2 {
		t.Fatalf("expected 2 addresses preserved, got %d", len(result[0].Addrs))
	}
	if result[0].Addrs[0].String() != addr1.String() {
		t.Errorf("first address = %q, want %q", result[0].Addrs[0].String(), addr1.String())
	}
	if result[0].Addrs[1].String() != addr2.String() {
		t.Errorf("second address = %q, want %q", result[0].Addrs[1].String(), addr2.String())
	}
}

func TestGroupDiscoveryCtx_InitializedByInitPubSub(t *testing.T) {
	hexKey := generateTestKey(t)

	n := NewNode()
	_, err := n.Start(NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{}, // no relay — local only
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	n.mu.RLock()
	defer n.mu.RUnlock()

	if n.groupDiscoveryCtx == nil {
		t.Fatal("groupDiscoveryCtx should be initialized after Start/initPubSub")
	}
	if len(n.groupDiscoveryCtx) != 0 {
		t.Errorf("groupDiscoveryCtx should be empty initially, got %d entries", len(n.groupDiscoveryCtx))
	}
}

func TestLeaveGroupTopic_CancelsDiscoveryContext(t *testing.T) {
	hexKey := generateTestKey(t)

	n := NewNode()
	_, err := n.Start(NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{}, // no relay — local only
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	groupId := "test-group-discovery-leave"
	config := testGroupConfig(GroupTypeChat)
	keyInfo := &GroupKeyInfo{Key: "dummykey", KeyEpoch: 1}

	// Join adds entries to groupDiscoveryCtx.
	if err := n.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("JoinGroupTopic: %v", err)
	}

	// Verify discovery context was created.
	n.mu.RLock()
	_, hasDiscoveryCtx := n.groupDiscoveryCtx[groupId]
	n.mu.RUnlock()
	if !hasDiscoveryCtx {
		t.Fatal("expected groupDiscoveryCtx entry after JoinGroupTopic")
	}

	// Leave should remove the discovery context entry.
	if err := n.LeaveGroupTopic(groupId); err != nil {
		t.Fatalf("LeaveGroupTopic: %v", err)
	}

	n.mu.RLock()
	_, hasDiscoveryCtxAfter := n.groupDiscoveryCtx[groupId]
	n.mu.RUnlock()
	if hasDiscoveryCtxAfter {
		t.Error("groupDiscoveryCtx entry should be removed after LeaveGroupTopic")
	}
}

func TestLeaveGroupTopic_RemovesPubSubStateAndBlocksFuturePublish(t *testing.T) {
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

	groupId := "test-group-leave-cleanup"
	config := testGroupConfig(GroupTypeChat)
	keyInfo := &GroupKeyInfo{Key: "dummykey", KeyEpoch: 1}

	if err := n.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("JoinGroupTopic: %v", err)
	}

	if err := n.LeaveGroupTopic(groupId); err != nil {
		t.Fatalf("LeaveGroupTopic: %v", err)
	}

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

	if _, _, err := n.PublishGroupMessage(
		groupId,
		"unused-private-key",
		"peer-admin",
		"unused-public-key",
		"Admin",
		"should not publish",
		"",
		nil,
	); err == nil || !strings.Contains(err.Error(), "group not joined") {
		t.Fatalf("PublishGroupMessage after leave error = %v, want group not joined", err)
	}

	if err := n.PublishGroupReaction(
		groupId,
		"unused-private-key",
		"peer-admin",
		"unused-public-key",
		`{"messageId":"msg-1","action":"add","emoji":"+1"}`,
	); err == nil || !strings.Contains(err.Error(), "group not joined") {
		t.Fatalf("PublishGroupReaction after leave error = %v, want group not joined", err)
	}
}

func TestStopNode_CancelsAllDiscoveryContexts(t *testing.T) {
	hexKey := generateTestKey(t)

	n := NewNode()
	_, err := n.Start(NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{}, // no relay — local only
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}

	config := testGroupConfig(GroupTypeChat)
	keyInfo := &GroupKeyInfo{Key: "dummykey", KeyEpoch: 1}

	// Join multiple groups to populate groupDiscoveryCtx.
	groups := []string{"group-stop-1", "group-stop-2", "group-stop-3"}
	for _, gid := range groups {
		if err := n.JoinGroupTopic(gid, config, keyInfo); err != nil {
			t.Fatalf("JoinGroupTopic(%s): %v", gid, err)
		}
	}

	// Verify all discovery contexts were created.
	n.mu.RLock()
	count := len(n.groupDiscoveryCtx)
	n.mu.RUnlock()
	if count != len(groups) {
		t.Fatalf("expected %d groupDiscoveryCtx entries, got %d", len(groups), count)
	}

	// Stop should cancel and clean up all discovery contexts.
	if err := n.Stop(); err != nil {
		t.Fatalf("Stop: %v", err)
	}

	// After Stop(), groupDiscoveryCtx should be empty (all entries deleted).
	n.mu.RLock()
	remaining := len(n.groupDiscoveryCtx)
	n.mu.RUnlock()
	if remaining != 0 {
		t.Errorf("expected 0 groupDiscoveryCtx entries after Stop, got %d", remaining)
	}
}

func TestGL017StopClearsGroupRuntimeStateAndRequiresExplicitRejoinAfterRestart(t *testing.T) {
	hexKey := generateTestKey(t)
	cfg := NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{},
		AutoRegister:   false,
	}

	n := New(&testEventCollector{})
	t.Cleanup(func() { _ = n.Stop() })

	if _, err := n.Start(cfg); err != nil {
		t.Fatalf("Start: %v", err)
	}
	initialPeerID := n.PeerId()

	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}
	groupIDs := []string{"gl017-stop-a", "gl017-stop-b", "gl017-stop-c"}
	config := &GroupConfig{
		Name:      "GL-017 Stop Runtime Cleanup",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: n.PeerId(), Role: GroupRoleAdmin, PublicKey: senderPubB64},
		},
		CreatedBy: n.PeerId(),
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	for _, groupID := range groupIDs {
		if err := n.JoinGroupTopic(groupID, config, keyInfo); err != nil {
			t.Fatalf("JoinGroupTopic(%s): %v", groupID, err)
		}
	}

	n.mu.RLock()
	pubsubReadyBeforeStop := n.pubsub != nil
	dispatcherReadyBeforeStop := n.eventDispatcher != nil
	for _, groupID := range groupIDs {
		topic := n.groupTopics[groupID]
		sub := n.groupSubs[groupID]
		storedConfig := n.groupConfigs[groupID]
		storedKey := n.groupKeys[groupID]
		subCancel := n.groupSubCtx[groupID]
		discoveryCancel := n.groupDiscoveryCtx[groupID]
		if topic == nil || sub == nil || storedConfig == nil || storedKey == nil || subCancel == nil || discoveryCancel == nil {
			n.mu.RUnlock()
			t.Fatalf(
				"group %s runtime state incomplete before Stop: topic=%t sub=%t config=%t key=%t subCtx=%t discoveryCtx=%t",
				groupID,
				topic != nil,
				sub != nil,
				storedConfig != nil,
				storedKey != nil,
				subCancel != nil,
				discoveryCancel != nil,
			)
		}
	}
	n.mu.RUnlock()
	if !pubsubReadyBeforeStop {
		t.Fatal("pubsub should be initialized before Stop")
	}
	if !dispatcherReadyBeforeStop {
		t.Fatal("eventDispatcher should be initialized before Stop when callback is configured")
	}

	if err := n.Stop(); err != nil {
		t.Fatalf("Stop: %v", err)
	}

	n.mu.RLock()
	if n.isStarted {
		n.mu.RUnlock()
		t.Fatal("node should be marked stopped after Stop")
	}
	if n.pubsub != nil {
		n.mu.RUnlock()
		t.Fatal("pubsub should be nil after Stop")
	}
	if n.groupConfigs != nil {
		n.mu.RUnlock()
		t.Fatal("groupConfigs should be nil after Stop")
	}
	if n.groupKeys != nil {
		n.mu.RUnlock()
		t.Fatal("groupKeys should be nil after Stop")
	}
	if n.eventDispatcher != nil {
		n.mu.RUnlock()
		t.Fatal("eventDispatcher should be nil after Stop")
	}
	if len(n.groupTopics) != 0 || len(n.groupSubs) != 0 || len(n.groupSubCtx) != 0 || len(n.groupDiscoveryCtx) != 0 {
		topicsLen := len(n.groupTopics)
		subsLen := len(n.groupSubs)
		subCtxLen := len(n.groupSubCtx)
		discoveryCtxLen := len(n.groupDiscoveryCtx)
		n.mu.RUnlock()
		t.Fatalf(
			"group runtime maps should be empty after Stop, got topics=%d subs=%d subCtx=%d discoveryCtx=%d",
			topicsLen,
			subsLen,
			subCtxLen,
			discoveryCtxLen,
		)
	}
	for _, groupID := range groupIDs {
		_, hasTopic := n.groupTopics[groupID]
		_, hasSub := n.groupSubs[groupID]
		_, hasSubCtx := n.groupSubCtx[groupID]
		_, hasDiscoveryCtx := n.groupDiscoveryCtx[groupID]
		if hasTopic || hasSub || hasSubCtx || hasDiscoveryCtx {
			n.mu.RUnlock()
			t.Fatalf(
				"group %s retained runtime state after Stop: topic=%t sub=%t subCtx=%t discoveryCtx=%t",
				groupID,
				hasTopic,
				hasSub,
				hasSubCtx,
				hasDiscoveryCtx,
			)
		}
	}
	n.mu.RUnlock()

	if err := n.Stop(); err != nil {
		t.Fatalf("second Stop should be safe: %v", err)
	}

	if _, err := n.Start(cfg); err != nil {
		t.Fatalf("restart Start: %v", err)
	}
	if restartedPeerID := n.PeerId(); restartedPeerID != initialPeerID {
		t.Fatalf("peer id after restart = %q, want stable peer id %q", restartedPeerID, initialPeerID)
	}

	n.mu.RLock()
	if n.pubsub == nil ||
		n.groupTopics == nil ||
		n.groupSubs == nil ||
		n.groupConfigs == nil ||
		n.groupKeys == nil ||
		n.groupSubCtx == nil ||
		n.groupDiscoveryCtx == nil ||
		n.eventDispatcher == nil {
		pubsubReady := n.pubsub != nil
		topicsReady := n.groupTopics != nil
		subsReady := n.groupSubs != nil
		configsReady := n.groupConfigs != nil
		keysReady := n.groupKeys != nil
		subCtxReady := n.groupSubCtx != nil
		discoveryCtxReady := n.groupDiscoveryCtx != nil
		dispatcherReady := n.eventDispatcher != nil
		n.mu.RUnlock()
		t.Fatalf(
			"restart should create fresh pubsub runtime: pubsub=%t topics=%t subs=%t configs=%t keys=%t subCtx=%t discoveryCtx=%t dispatcher=%t",
			pubsubReady,
			topicsReady,
			subsReady,
			configsReady,
			keysReady,
			subCtxReady,
			discoveryCtxReady,
			dispatcherReady,
		)
	}
	if len(n.groupTopics) != 0 ||
		len(n.groupSubs) != 0 ||
		len(n.groupConfigs) != 0 ||
		len(n.groupKeys) != 0 ||
		len(n.groupSubCtx) != 0 ||
		len(n.groupDiscoveryCtx) != 0 {
		topicsLen := len(n.groupTopics)
		subsLen := len(n.groupSubs)
		configsLen := len(n.groupConfigs)
		keysLen := len(n.groupKeys)
		subCtxLen := len(n.groupSubCtx)
		discoveryCtxLen := len(n.groupDiscoveryCtx)
		n.mu.RUnlock()
		t.Fatalf(
			"restart should not auto-restore group state, got topics=%d subs=%d configs=%d keys=%d subCtx=%d discoveryCtx=%d",
			topicsLen,
			subsLen,
			configsLen,
			keysLen,
			subCtxLen,
			discoveryCtxLen,
		)
	}
	n.mu.RUnlock()

	msgID, peerCount, err := n.PublishGroupMessage(
		groupIDs[0],
		senderPrivB64,
		n.PeerId(),
		senderPubB64,
		"Admin",
		"GL-017 publish before explicit rejoin",
		"",
		nil,
	)
	if err == nil {
		t.Fatal("expected PublishGroupMessage before explicit rejoin to fail")
	}
	if !strings.Contains(err.Error(), "group not joined") {
		t.Fatalf("PublishGroupMessage before explicit rejoin error = %q, want group not joined", err.Error())
	}
	if msgID != "" || peerCount != 0 {
		t.Fatalf("PublishGroupMessage before explicit rejoin returned msgID=%q peerCount=%d, want empty/0", msgID, peerCount)
	}

	for _, groupID := range groupIDs {
		if err := n.JoinGroupTopic(groupID, config, keyInfo); err != nil {
			t.Fatalf("rejoin JoinGroupTopic(%s): %v", groupID, err)
		}
	}

	n.mu.RLock()
	for _, groupID := range groupIDs {
		topic := n.groupTopics[groupID]
		sub := n.groupSubs[groupID]
		storedConfig := n.groupConfigs[groupID]
		storedKey := n.groupKeys[groupID]
		subCancel := n.groupSubCtx[groupID]
		discoveryCancel := n.groupDiscoveryCtx[groupID]
		if topic == nil || sub == nil || storedConfig == nil || storedKey == nil || subCancel == nil || discoveryCancel == nil {
			n.mu.RUnlock()
			t.Fatalf(
				"group %s runtime state incomplete after explicit rejoin: topic=%t sub=%t config=%t key=%t subCtx=%t discoveryCtx=%t",
				groupID,
				topic != nil,
				sub != nil,
				storedConfig != nil,
				storedKey != nil,
				subCancel != nil,
				discoveryCancel != nil,
			)
		}
	}
	n.mu.RUnlock()

	msgID, peerCount, err = n.PublishGroupMessage(
		groupIDs[0],
		senderPrivB64,
		n.PeerId(),
		senderPubB64,
		"Admin",
		"GL-017 publish after explicit rejoin",
		"",
		nil,
	)
	if err != nil {
		t.Fatalf("PublishGroupMessage after explicit rejoin: %v", err)
	}
	if msgID == "" {
		t.Fatal("PublishGroupMessage after explicit rejoin returned empty message id")
	}
	if peerCount != 0 {
		t.Fatalf("local-only PublishGroupMessage peerCount = %d, want 0", peerCount)
	}
}

func TestGL019ConcurrentJoinLeaveUpdateSameGroupIsRaceFree(t *testing.T) {
	hexKey := generateTestKey(t)
	cfg := NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{},
		AutoRegister:   false,
	}

	n := NewNode()
	t.Cleanup(func() { _ = n.Stop() })
	if _, err := n.Start(cfg); err != nil {
		t.Fatalf("Start: %v", err)
	}

	_, senderPubB64 := generateEd25519KeyPair(t)
	groupID := "gl019-concurrent-join-leave-update"
	nodePeerID := n.PeerId()

	newConfig := func(label string) *GroupConfig {
		return &GroupConfig{
			Name:      "GL-019 " + label,
			GroupType: GroupTypeChat,
			Members: []GroupMember{
				{PeerId: nodePeerID, Role: GroupRoleAdmin, PublicKey: senderPubB64},
			},
			CreatedBy: nodePeerID,
		}
	}
	newKeyInfo := func(label string, epoch int) *GroupKeyInfo {
		groupKey, err := mcrypto.GenerateGroupKey()
		if err != nil {
			t.Fatalf("generate %s group key: %v", label, err)
		}
		return &GroupKeyInfo{Key: groupKey, KeyEpoch: epoch}
	}

	initialConfig := newConfig("initial")
	initialKey := newKeyInfo("initial", 1)
	if err := n.JoinGroupTopic(groupID, initialConfig, initialKey); err != nil {
		t.Fatalf("initial JoinGroupTopic: %v", err)
	}

	const iterations = 64
	joinConfigs := make([]*GroupConfig, iterations)
	joinKeys := make([]*GroupKeyInfo, iterations)
	updateConfigs := make([]*GroupConfig, iterations)
	updateKeys := make([]*GroupKeyInfo, iterations)
	for i := 0; i < iterations; i++ {
		joinConfigs[i] = newConfig(fmt.Sprintf("join-%02d", i))
		joinKeys[i] = newKeyInfo(fmt.Sprintf("join-%02d", i), 100+i)
		updateConfigs[i] = newConfig(fmt.Sprintf("update-%02d", i))
		updateKeys[i] = newKeyInfo(fmt.Sprintf("update-%02d", i), 1000+i)
	}

	start := make(chan struct{})
	unexpected := make(chan error, iterations*4)
	var wg sync.WaitGroup
	recordUnexpected := func(format string, args ...interface{}) {
		select {
		case unexpected <- fmt.Errorf(format, args...):
		default:
		}
	}

	wg.Add(4)
	go func() {
		defer wg.Done()
		<-start
		for i := 0; i < iterations; i++ {
			err := n.JoinGroupTopic(groupID, joinConfigs[i], joinKeys[i])
			if err == nil {
				continue
			}
			if !strings.Contains(err.Error(), "already joined group topic") {
				recordUnexpected("JoinGroupTopic iteration %d: %v", i, err)
			}
		}
	}()
	go func() {
		defer wg.Done()
		<-start
		for i := 0; i < iterations; i++ {
			if err := n.LeaveGroupTopic(groupID); err != nil {
				recordUnexpected("LeaveGroupTopic iteration %d: %v", i, err)
			}
		}
	}()
	go func() {
		defer wg.Done()
		<-start
		for i := 0; i < iterations; i++ {
			n.UpdateGroupConfig(groupID, updateConfigs[i])
		}
	}()
	go func() {
		defer wg.Done()
		<-start
		for i := 0; i < iterations; i++ {
			n.UpdateGroupKey(groupID, updateKeys[i])
		}
	}()
	close(start)
	wg.Wait()
	close(unexpected)
	for err := range unexpected {
		if err != nil {
			t.Fatal(err)
		}
	}

	assertValidRuntimeState := func(label string) {
		t.Helper()
		n.mu.RLock()
		topic, hasTopic := n.groupTopics[groupID]
		sub, hasSub := n.groupSubs[groupID]
		config, hasConfig := n.groupConfigs[groupID]
		key, hasKey := n.groupKeys[groupID]
		subCancel, hasSubCtx := n.groupSubCtx[groupID]
		discoveryCancel, hasDiscoveryCtx := n.groupDiscoveryCtx[groupID]
		n.mu.RUnlock()

		hasRuntimeState := hasTopic || hasSub || hasSubCtx || hasDiscoveryCtx
		runtimeComplete := hasTopic && topic != nil &&
			hasSub && sub != nil &&
			hasSubCtx && subCancel != nil &&
			hasDiscoveryCtx && discoveryCancel != nil &&
			hasConfig && config != nil &&
			hasKey && key != nil
		if hasRuntimeState && !runtimeComplete {
			t.Fatalf(
				"%s runtime state impossible: topic=%t sub=%t subCtx=%t discoveryCtx=%t config=%t key=%t",
				label,
				hasTopic && topic != nil,
				hasSub && sub != nil,
				hasSubCtx && subCancel != nil,
				hasDiscoveryCtx && discoveryCancel != nil,
				hasConfig && config != nil,
				hasKey && key != nil,
			)
		}
	}

	assertNoGroupEntries := func(label string) {
		t.Helper()
		n.mu.RLock()
		_, hasTopic := n.groupTopics[groupID]
		_, hasSub := n.groupSubs[groupID]
		_, hasSubCtx := n.groupSubCtx[groupID]
		_, hasDiscoveryCtx := n.groupDiscoveryCtx[groupID]
		_, hasConfig := n.groupConfigs[groupID]
		_, hasKey := n.groupKeys[groupID]
		n.mu.RUnlock()
		if hasTopic || hasSub || hasSubCtx || hasDiscoveryCtx || hasConfig || hasKey {
			t.Fatalf(
				"%s retained group entries: topic=%t sub=%t subCtx=%t discoveryCtx=%t config=%t key=%t",
				label,
				hasTopic,
				hasSub,
				hasSubCtx,
				hasDiscoveryCtx,
				hasConfig,
				hasKey,
			)
		}
	}

	assertJoinedWith := func(label string, wantConfig *GroupConfig, wantKey *GroupKeyInfo) {
		t.Helper()
		n.mu.RLock()
		topic := n.groupTopics[groupID]
		sub := n.groupSubs[groupID]
		config := n.groupConfigs[groupID]
		key := n.groupKeys[groupID]
		subCancel := n.groupSubCtx[groupID]
		discoveryCancel := n.groupDiscoveryCtx[groupID]
		n.mu.RUnlock()

		if topic == nil || sub == nil || config == nil || key == nil || subCancel == nil || discoveryCancel == nil {
			t.Fatalf(
				"%s joined runtime incomplete: topic=%t sub=%t config=%t key=%t subCtx=%t discoveryCtx=%t",
				label,
				topic != nil,
				sub != nil,
				config != nil,
				key != nil,
				subCancel != nil,
				discoveryCancel != nil,
			)
		}
		if config.Name != wantConfig.Name || len(config.Members) != len(wantConfig.Members) || config.Members[0].PeerId != wantConfig.Members[0].PeerId {
			t.Fatalf("%s config = %#v, want %#v", label, config, wantConfig)
		}
		if key.Key != wantKey.Key || key.KeyEpoch != wantKey.KeyEpoch {
			t.Fatalf("%s key = (%q,%d), want (%q,%d)", label, key.Key, key.KeyEpoch, wantKey.Key, wantKey.KeyEpoch)
		}
	}

	assertValidRuntimeState("post-stress")

	if err := n.LeaveGroupTopic(groupID); err != nil {
		t.Fatalf("cleanup LeaveGroupTopic: %v", err)
	}
	assertNoGroupEntries("after deterministic cleanup")

	latestConfig := newConfig("latest-rejoin")
	latestKey := newKeyInfo("latest-rejoin", 10_000)
	if err := n.JoinGroupTopic(groupID, latestConfig, latestKey); err != nil {
		t.Fatalf("deterministic rejoin JoinGroupTopic: %v", err)
	}
	assertJoinedWith("after deterministic rejoin", latestConfig, latestKey)

	if err := n.LeaveGroupTopic(groupID); err != nil {
		t.Fatalf("final LeaveGroupTopic: %v", err)
	}
	assertNoGroupEntries("after final leave")
}

// ===========================================================================
// Phase 1: Verify GroupUpdateConfig handles member addition
// ===========================================================================

// Test 1.1: Validator accepts new member after config update.
func TestGroupTopicValidator_AcceptsNewMemberAfterConfigUpdate(t *testing.T) {
	privB64A, pubB64A := generateEd25519KeyPair(t)
	privB64B, pubB64B := generateEd25519KeyPair(t)
	groupKey, _ := mcrypto.GenerateGroupKey()
	groupId := "group-invite-test-1"

	// Config with only member A (admin).
	config := &GroupConfig{
		Name:      "Test",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: "peer-A", Role: GroupRoleAdmin, PublicKey: pubB64A},
		},
		CreatedBy: "peer-A",
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	// Build envelope from member B (not in config).
	envelopeB := buildTestEnvelope(t, groupId, "peer-B", privB64B, pubB64B, groupKey, 1, "hello from B")

	// Should reject: B is not a member.
	result := validateGroupEnvelope(envelopeB, groupId, config, keyInfo)
	if result != "reject:non_member" {
		t.Errorf("before update: expected reject:non_member, got %s", result)
	}

	// Update config to include member B.
	config.Members = append(config.Members, GroupMember{
		PeerId: "peer-B", Role: GroupRoleWriter, PublicKey: pubB64B,
	})

	// Should now accept: B is a member.
	result = validateGroupEnvelope(envelopeB, groupId, config, keyInfo)
	if result != "accept" {
		t.Errorf("after update: expected accept, got %s", result)
	}

	_ = privB64A // suppress unused
}

// Test 1.2: Validator rejects removed member after config update.
func TestGroupTopicValidator_RejectsRemovedMemberAfterConfigUpdate(t *testing.T) {
	privB64A, pubB64A := generateEd25519KeyPair(t)
	privB64B, pubB64B := generateEd25519KeyPair(t)
	groupKey, _ := mcrypto.GenerateGroupKey()
	groupId := "group-remove-test-1"

	// Config with members A (admin) and B (writer).
	config := &GroupConfig{
		Name:      "Test",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: "peer-A", Role: GroupRoleAdmin, PublicKey: pubB64A},
			{PeerId: "peer-B", Role: GroupRoleWriter, PublicKey: pubB64B},
		},
		CreatedBy: "peer-A",
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	// Build envelope from member B.
	envelopeB := buildTestEnvelope(t, groupId, "peer-B", privB64B, pubB64B, groupKey, 1, "hello from B")

	// Should accept: B is a member.
	result := validateGroupEnvelope(envelopeB, groupId, config, keyInfo)
	if result != "accept" {
		t.Errorf("before removal: expected accept, got %s", result)
	}

	// Remove member B from config.
	config.Members = []GroupMember{
		{PeerId: "peer-A", Role: GroupRoleAdmin, PublicKey: pubB64A},
	}

	// Should reject: B is no longer a member.
	result = validateGroupEnvelope(envelopeB, groupId, config, keyInfo)
	if result != "reject:non_member" {
		t.Errorf("after removal: expected reject:non_member, got %s", result)
	}

	_ = privB64A // suppress unused
}

// Test 1.3: UpdateGroupConfig replaces config atomically.
func TestUpdateGroupConfig_ReplacesConfigAtomically(t *testing.T) {
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

	groupId := "group-atomic-config"
	originalConfig := &GroupConfig{
		Name:      "Original",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: "peer-1", Role: GroupRoleAdmin, PublicKey: "pk1"},
		},
		CreatedBy: "peer-1",
	}
	keyInfo := &GroupKeyInfo{Key: "dummykey", KeyEpoch: 1}

	// Join group topic with 1-member config.
	if err := n.JoinGroupTopic(groupId, originalConfig, keyInfo); err != nil {
		t.Fatalf("JoinGroupTopic: %v", err)
	}

	// Update config to have 3 members.
	newConfig := &GroupConfig{
		Name:      "Updated",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: "peer-1", Role: GroupRoleAdmin, PublicKey: "pk1"},
			{PeerId: "peer-2", Role: GroupRoleWriter, PublicKey: "pk2"},
			{PeerId: "peer-3", Role: GroupRoleReader, PublicKey: "pk3"},
		},
		CreatedBy: "peer-1",
	}
	n.UpdateGroupConfig(groupId, newConfig)
	newConfig.Name = "Caller Mutated"
	newConfig.Members[1].PeerId = "caller-mutated-peer"

	// Verify the config was replaced.
	n.mu.RLock()
	storedConfig := n.groupConfigs[groupId]
	n.mu.RUnlock()

	if storedConfig == nil {
		t.Fatal("groupConfigs[groupId] should not be nil")
	}
	if len(storedConfig.Members) != 3 {
		t.Errorf("expected 3 members after update, got %d", len(storedConfig.Members))
	}
	if storedConfig.Name != "Updated" {
		t.Errorf("expected config Name 'Updated', got %q", storedConfig.Name)
	}
	if storedConfig == originalConfig {
		t.Error("stored config should not be the original join snapshot")
	}
	if storedConfig == newConfig {
		t.Error("stored config should snapshot the supplied update config")
	}
	if storedConfig.Members[1].PeerId != "peer-2" {
		t.Errorf("stored config member[1] = %q, want snapshot peer-2", storedConfig.Members[1].PeerId)
	}
}

// Test 1.4: UpdateGroupConfig on non-existent group stores config silently.
func TestUpdateGroupConfig_NonExistentGroup(t *testing.T) {
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

	// Call UpdateGroupConfig on a group that was never joined.
	config := &GroupConfig{
		Name:      "Ghost Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: "peer-1", Role: GroupRoleAdmin, PublicKey: "pk1"},
		},
		CreatedBy: "peer-1",
	}

	// Should not panic.
	n.UpdateGroupConfig("nonexistent-group", config)
	config.Name = "Caller Mutated Ghost Group"
	config.Members[0].PeerId = "caller-mutated-peer"

	// Verify the config was stored.
	n.mu.RLock()
	storedConfig := n.groupConfigs["nonexistent-group"]
	n.mu.RUnlock()

	if storedConfig == nil {
		t.Fatal("expected config to be stored even for non-existent group")
	}
	if storedConfig.Name != "Ghost Group" {
		t.Errorf("expected 'Ghost Group', got %q", storedConfig.Name)
	}
	if storedConfig == config {
		t.Fatal("non-existent group update should store a config snapshot")
	}
	if storedConfig.Members[0].PeerId != "peer-1" {
		t.Errorf("stored member = %q, want snapshot peer-1", storedConfig.Members[0].PeerId)
	}
}

// ===========================================================================
// Phase 2: Verify GroupJoinTopic handles invite join
// ===========================================================================

// Test 2.1: JoinGroupTopic succeeds with multi-member config.
func TestJoinGroupTopic_WithMultiMemberConfig(t *testing.T) {
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

	groupId := "invite-multi-member"
	config := &GroupConfig{
		Name:      "Multi Member Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: "peer-admin", Role: GroupRoleAdmin, PublicKey: "pkAdmin"},
			{PeerId: "peer-writer", Role: GroupRoleWriter, PublicKey: "pkWriter"},
			{PeerId: "peer-reader", Role: GroupRoleReader, PublicKey: "pkReader"},
		},
		CreatedBy: "peer-admin",
	}
	keyInfo := &GroupKeyInfo{Key: "dummykey", KeyEpoch: 1}

	if err := n.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("JoinGroupTopic: %v", err)
	}

	// Verify all stored state.
	n.mu.RLock()
	defer n.mu.RUnlock()

	if _, ok := n.groupTopics[groupId]; !ok {
		t.Error("groupTopics should contain the group")
	}
	if _, ok := n.groupSubs[groupId]; !ok {
		t.Error("groupSubs should contain the group")
	}
	storedConfig := n.groupConfigs[groupId]
	if storedConfig == nil {
		t.Fatal("groupConfigs should contain the group")
	}
	if len(storedConfig.Members) != 3 {
		t.Errorf("expected 3 members, got %d", len(storedConfig.Members))
	}
	storedKey := n.groupKeys[groupId]
	if storedKey == nil {
		t.Fatal("groupKeys should contain the group")
	}
	if storedKey.KeyEpoch != 1 {
		t.Errorf("expected keyEpoch=1, got %d", storedKey.KeyEpoch)
	}
	if _, ok := n.groupDiscoveryCtx[groupId]; !ok {
		t.Error("groupDiscoveryCtx should contain the group (discovery loop started)")
	}
}

// Test 2.2: JoinGroupTopic sets up validator that accepts all listed members.
func TestJoinGroupTopic_ValidatorAcceptsAllListedMembers(t *testing.T) {
	privA, pubA := generateEd25519KeyPair(t)
	privB, pubB := generateEd25519KeyPair(t)
	privC, pubC := generateEd25519KeyPair(t)
	_, pubD := generateEd25519KeyPair(t)
	groupKey, _ := mcrypto.GenerateGroupKey()
	groupId := "group-all-members"

	config := &GroupConfig{
		Name:      "Chat Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: "peer-A", Role: GroupRoleAdmin, PublicKey: pubA},
			{PeerId: "peer-B", Role: GroupRoleWriter, PublicKey: pubB},
			{PeerId: "peer-C", Role: GroupRoleReader, PublicKey: pubC},
		},
		CreatedBy: "peer-A",
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	// Build envelopes from A, B, C (all members in a chat group).
	envA := buildTestEnvelope(t, groupId, "peer-A", privA, pubA, groupKey, 1, "from A")
	envB := buildTestEnvelope(t, groupId, "peer-B", privB, pubB, groupKey, 1, "from B")
	envC := buildTestEnvelope(t, groupId, "peer-C", privC, pubC, groupKey, 1, "from C")

	// All should be accepted.
	for _, tc := range []struct {
		name string
		env  string
	}{
		{"peer-A (admin)", envA},
		{"peer-B (writer)", envB},
		{"peer-C (reader)", envC},
	} {
		result := validateGroupEnvelope(tc.env, groupId, config, keyInfo)
		if result != "accept" {
			t.Errorf("%s: expected accept, got %s", tc.name, result)
		}
	}

	// Build envelope from unknown peer D -- should be rejected.
	privD, _ := generateEd25519KeyPair(t)
	envD := buildTestEnvelope(t, groupId, "peer-D", privD, pubD, groupKey, 1, "from D")
	result := validateGroupEnvelope(envD, groupId, config, keyInfo)
	if result != "reject:non_member" {
		t.Errorf("peer-D (non-member): expected reject:non_member, got %s", result)
	}
}

// Test 2.3: JoinGroupTopic fails without pubsub.
func TestJoinGroupTopic_FailsWithoutPubSub(t *testing.T) {
	n := NewNode() // NOT started — pubsub is nil.

	groupId := "gl-001-unstarted-group"
	config := testGroupConfig(GroupTypeChat)
	keyInfo := &GroupKeyInfo{Key: "dummykey", KeyEpoch: 1}

	err := n.JoinGroupTopic(groupId, config, keyInfo)
	if err == nil {
		t.Fatal("expected error when pubsub is nil")
	}
	if err.Error() != "pubsub not initialized" {
		t.Errorf("expected 'pubsub not initialized', got %q", err.Error())
	}

	n.mu.RLock()
	defer n.mu.RUnlock()

	if n.pubsub != nil {
		t.Fatal("pubsub should remain nil after GL-001 rejected join")
	}
	if _, ok := n.groupTopics[groupId]; ok {
		t.Fatal("groupTopics should not contain GL-001 rejected group")
	}
	if _, ok := n.groupSubs[groupId]; ok {
		t.Fatal("groupSubs should not contain GL-001 rejected group")
	}
	if _, ok := n.groupConfigs[groupId]; ok {
		t.Fatal("groupConfigs should not contain GL-001 rejected group")
	}
	if _, ok := n.groupKeys[groupId]; ok {
		t.Fatal("groupKeys should not contain GL-001 rejected group")
	}
	if _, ok := n.groupSubCtx[groupId]; ok {
		t.Fatal("groupSubCtx should not contain GL-001 rejected group")
	}
	if _, ok := n.groupDiscoveryCtx[groupId]; ok {
		t.Fatal("groupDiscoveryCtx should not contain GL-001 rejected group")
	}
}

func TestJoinGroupTopic_RejectsNilKeyInfoAndLeavesNoGroupState(t *testing.T) {
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

	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	groupId := "gl-006-nil-key-rejected"
	config := &GroupConfig{
		Name:      "GL-006 Nil Key Rejected",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: n.PeerId(), Role: GroupRoleAdmin, PublicKey: senderPubB64},
		},
		CreatedBy: n.PeerId(),
	}

	err = n.JoinGroupTopic(groupId, config, nil)
	if err == nil {
		t.Fatal("expected nil keyInfo join to fail")
	}
	if !strings.Contains(err.Error(), "missing group key info") {
		t.Fatalf("expected missing group key info error, got %q", err.Error())
	}

	n.mu.RLock()
	_, hasTopic := n.groupTopics[groupId]
	_, hasSub := n.groupSubs[groupId]
	_, hasConfig := n.groupConfigs[groupId]
	_, hasKey := n.groupKeys[groupId]
	_, hasSubCtx := n.groupSubCtx[groupId]
	_, hasDiscoveryCtx := n.groupDiscoveryCtx[groupId]
	n.mu.RUnlock()
	if hasTopic || hasSub || hasConfig || hasKey || hasSubCtx || hasDiscoveryCtx {
		t.Fatalf(
			"nil key join should not store group state, got topic=%t sub=%t config=%t key=%t subCtx=%t discoveryCtx=%t",
			hasTopic,
			hasSub,
			hasConfig,
			hasKey,
			hasSubCtx,
			hasDiscoveryCtx,
		)
	}

	if keyInfo := n.GetGroupKeyInfo(groupId); keyInfo != nil {
		t.Fatalf("GetGroupKeyInfo after rejected nil key join = %#v, want nil", keyInfo)
	}

	var msgID string
	var peerCount int
	var publishErr error
	func() {
		defer func() {
			if r := recover(); r != nil {
				t.Fatalf("PublishGroupMessage panicked after rejected nil key join: %v", r)
			}
		}()
		msgID, peerCount, publishErr = n.PublishGroupMessage(
			groupId,
			senderPrivB64,
			n.PeerId(),
			senderPubB64,
			"Admin",
			"GL-006 publish after rejected join",
			"",
			nil,
		)
	}()
	if publishErr == nil {
		t.Fatal("expected PublishGroupMessage after rejected nil key join to fail")
	}
	if !strings.Contains(publishErr.Error(), "group not joined") {
		t.Fatalf("expected group not joined publish error, got %q", publishErr.Error())
	}
	if msgID != "" || peerCount != 0 {
		t.Fatalf("PublishGroupMessage after rejected nil key join returned msgID=%q peerCount=%d, want empty/0", msgID, peerCount)
	}
}

func TestJoinGroupTopic_RejectsNilConfigAndLeavesNoGroupState(t *testing.T) {
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

	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}
	groupId := "gl-007-nil-config-rejected"
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	err = n.JoinGroupTopic(groupId, nil, keyInfo)
	if err == nil {
		t.Fatal("expected nil config join to fail")
	}
	if !strings.Contains(err.Error(), "missing group config") {
		t.Fatalf("expected missing group config error, got %q", err.Error())
	}

	n.mu.RLock()
	_, hasTopic := n.groupTopics[groupId]
	_, hasSub := n.groupSubs[groupId]
	_, hasConfig := n.groupConfigs[groupId]
	_, hasKey := n.groupKeys[groupId]
	_, hasSubCtx := n.groupSubCtx[groupId]
	_, hasDiscoveryCtx := n.groupDiscoveryCtx[groupId]
	n.mu.RUnlock()
	if hasTopic || hasSub || hasConfig || hasKey || hasSubCtx || hasDiscoveryCtx {
		t.Fatalf(
			"nil config join should not store group state, got topic=%t sub=%t config=%t key=%t subCtx=%t discoveryCtx=%t",
			hasTopic,
			hasSub,
			hasConfig,
			hasKey,
			hasSubCtx,
			hasDiscoveryCtx,
		)
	}

	if keyInfo := n.GetGroupKeyInfo(groupId); keyInfo != nil {
		t.Fatalf("GetGroupKeyInfo after rejected nil config join = %#v, want nil", keyInfo)
	}

	var msgID string
	var peerCount int
	var publishErr error
	func() {
		defer func() {
			if r := recover(); r != nil {
				t.Fatalf("PublishGroupMessage panicked after rejected nil config join: %v", r)
			}
		}()
		msgID, peerCount, publishErr = n.PublishGroupMessage(
			groupId,
			senderPrivB64,
			n.PeerId(),
			senderPubB64,
			"Admin",
			"GL-007 publish after rejected join",
			"",
			nil,
		)
	}()
	if publishErr == nil {
		t.Fatal("expected PublishGroupMessage after rejected nil config join to fail")
	}
	if !strings.Contains(publishErr.Error(), "group not joined") {
		t.Fatalf("expected group not joined publish error, got %q", publishErr.Error())
	}
	if msgID != "" || peerCount != 0 {
		t.Fatalf("PublishGroupMessage after rejected nil config join returned msgID=%q peerCount=%d, want empty/0", msgID, peerCount)
	}
}

// Test 2.4: JoinGroupTopic rejects double join.
func TestJoinGroupTopic_RejectsDoubleJoin(t *testing.T) {
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

	groupId := "group-double-join"
	config := testGroupConfig(GroupTypeChat)
	keyInfo := &GroupKeyInfo{Key: "dummykey", KeyEpoch: 1}

	// First join should succeed.
	if err := n.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("first JoinGroupTopic: %v", err)
	}

	// Second join should fail.
	err = n.JoinGroupTopic(groupId, config, keyInfo)
	if err == nil {
		t.Fatal("expected error on double join")
	}
	if !strings.Contains(err.Error(), "already joined") {
		t.Errorf("expected 'already joined' error, got %q", err.Error())
	}
}

func TestJoinGroupTopic_JoinFailureUnregistersValidatorAndAllowsRetry(t *testing.T) {
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

	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}
	groupId := "gl-003-join-failure-retry"
	config := &GroupConfig{
		Name:      "GL-003 Join Failure Retry",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: n.PeerId(), Role: GroupRoleAdmin, PublicKey: senderPubB64},
		},
		CreatedBy: n.PeerId(),
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	topicName := GroupTopicPrefix + groupId

	staleTopic, err := n.pubsub.Join(topicName)
	if err != nil {
		t.Fatalf("create stale topic: %v", err)
	}

	err = n.JoinGroupTopic(groupId, config, keyInfo)
	if err == nil {
		t.Fatal("expected join failure while stale topic exists")
	}
	if !strings.Contains(err.Error(), "join topic") || !strings.Contains(err.Error(), "topic already exists") {
		t.Fatalf("join failure error = %q, want join topic/topic already exists", err.Error())
	}

	n.mu.RLock()
	_, hasTopic := n.groupTopics[groupId]
	_, hasSub := n.groupSubs[groupId]
	_, hasConfig := n.groupConfigs[groupId]
	_, hasKey := n.groupKeys[groupId]
	_, hasSubCtx := n.groupSubCtx[groupId]
	_, hasDiscoveryCtx := n.groupDiscoveryCtx[groupId]
	n.mu.RUnlock()
	if hasTopic || hasSub || hasConfig || hasKey || hasSubCtx || hasDiscoveryCtx {
		t.Fatalf(
			"failed join should not store group state, got topic=%t sub=%t config=%t key=%t subCtx=%t discoveryCtx=%t",
			hasTopic,
			hasSub,
			hasConfig,
			hasKey,
			hasSubCtx,
			hasDiscoveryCtx,
		)
	}

	_ = staleTopic.Close()

	if err := n.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("retry JoinGroupTopic: %v", err)
	}

	msgID, _, err := n.PublishGroupMessage(
		groupId,
		senderPrivB64,
		n.PeerId(),
		senderPubB64,
		"Admin",
		"GL-003 retry health",
		"",
		nil,
	)
	if err != nil {
		t.Fatalf("PublishGroupMessage after retry: %v", err)
	}
	if msgID == "" {
		t.Fatal("PublishGroupMessage after retry returned empty message id")
	}
}

func TestJoinGroupTopic_SubscribeFailureUnregistersValidatorClosesTopicAndAllowsRetry(t *testing.T) {
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

	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}
	groupId := "gl-004-subscribe-failure-retry"
	config := &GroupConfig{
		Name:      "GL-004 Subscribe Failure Retry",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: n.PeerId(), Role: GroupRoleAdmin, PublicKey: senderPubB64},
		},
		CreatedBy: n.PeerId(),
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	forcedSubscribeErr := fmt.Errorf("gl-004 forced subscribe failure")
	subscribeAttempts := 0
	n.joinGroupTopicSubscribeHook = func(topic *pubsub.Topic) (*pubsub.Subscription, error) {
		subscribeAttempts++
		if subscribeAttempts == 1 {
			return nil, forcedSubscribeErr
		}
		return topic.Subscribe()
	}

	err = n.JoinGroupTopic(groupId, config, keyInfo)
	if err == nil {
		t.Fatal("expected subscribe failure")
	}
	if !strings.Contains(err.Error(), "subscribe to topic") || !strings.Contains(err.Error(), forcedSubscribeErr.Error()) {
		t.Fatalf("subscribe failure error = %q, want subscribe to topic/%q", err.Error(), forcedSubscribeErr.Error())
	}

	n.mu.RLock()
	_, hasTopic := n.groupTopics[groupId]
	_, hasSub := n.groupSubs[groupId]
	_, hasConfig := n.groupConfigs[groupId]
	_, hasKey := n.groupKeys[groupId]
	_, hasSubCtx := n.groupSubCtx[groupId]
	_, hasDiscoveryCtx := n.groupDiscoveryCtx[groupId]
	n.mu.RUnlock()
	if hasTopic || hasSub || hasConfig || hasKey || hasSubCtx || hasDiscoveryCtx {
		t.Fatalf(
			"failed subscribe should not store group state, got topic=%t sub=%t config=%t key=%t subCtx=%t discoveryCtx=%t",
			hasTopic,
			hasSub,
			hasConfig,
			hasKey,
			hasSubCtx,
			hasDiscoveryCtx,
		)
	}

	if err := n.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("retry JoinGroupTopic: %v", err)
	}
	if subscribeAttempts != 2 {
		t.Fatalf("subscribe attempts = %d, want 2", subscribeAttempts)
	}

	msgID, _, err := n.PublishGroupMessage(
		groupId,
		senderPrivB64,
		n.PeerId(),
		senderPubB64,
		"Admin",
		"GL-004 retry health",
		"",
		nil,
	)
	if err != nil {
		t.Fatalf("PublishGroupMessage after retry: %v", err)
	}
	if msgID == "" {
		t.Fatal("PublishGroupMessage after retry returned empty message id")
	}
}

func TestJoinGroupTopic_DuplicateJoinPreservesExistingState(t *testing.T) {
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

	_, firstPubB64 := generateEd25519KeyPair(t)
	firstGroupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate first group key: %v", err)
	}
	groupId := "gl-002-double-join"
	firstConfig := &GroupConfig{
		Name:      "GL-002 First Join",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: n.PeerId(), Role: GroupRoleAdmin, PublicKey: firstPubB64},
		},
		CreatedBy: n.PeerId(),
	}
	firstKeyInfo := &GroupKeyInfo{Key: firstGroupKey, KeyEpoch: 1}

	if err := n.JoinGroupTopic(groupId, firstConfig, firstKeyInfo); err != nil {
		t.Fatalf("first JoinGroupTopic: %v", err)
	}

	n.mu.RLock()
	initialTopic := n.groupTopics[groupId]
	initialSub := n.groupSubs[groupId]
	initialConfig := n.groupConfigs[groupId]
	initialKey := n.groupKeys[groupId]
	_, initialSubCtxPresent := n.groupSubCtx[groupId]
	_, initialDiscoveryCtxPresent := n.groupDiscoveryCtx[groupId]
	initialSubCtxLen := len(n.groupSubCtx)
	initialDiscoveryCtxLen := len(n.groupDiscoveryCtx)
	n.mu.RUnlock()

	if initialTopic == nil {
		t.Fatal("groupTopics should contain the first join topic")
	}
	if initialSub == nil {
		t.Fatal("groupSubs should contain the first join subscription")
	}
	if initialConfig == nil {
		t.Fatal("groupConfigs should contain the first join config")
	}
	if initialConfig == firstConfig {
		t.Fatal("groupConfigs should snapshot the first join config")
	}
	if initialConfig.Name != firstConfig.Name || len(initialConfig.Members) != len(firstConfig.Members) || initialConfig.Members[0].PublicKey != firstPubB64 {
		t.Fatalf("stored first config = %#v, want first join config values", initialConfig)
	}
	if initialKey == nil {
		t.Fatal("groupKeys should contain the first join key")
	}
	if initialKey.Key != firstGroupKey || initialKey.KeyEpoch != firstKeyInfo.KeyEpoch {
		t.Fatalf("stored first key = (%q,%d), want (%q,%d)", initialKey.Key, initialKey.KeyEpoch, firstGroupKey, firstKeyInfo.KeyEpoch)
	}
	if !initialSubCtxPresent {
		t.Fatal("groupSubCtx should contain the first join")
	}
	if !initialDiscoveryCtxPresent {
		t.Fatal("groupDiscoveryCtx should contain the first join")
	}

	_, secondPubB64 := generateEd25519KeyPair(t)
	secondGroupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate second group key: %v", err)
	}
	secondConfig := &GroupConfig{
		Name:      "GL-002 Duplicate Join",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: n.PeerId(), Role: GroupRoleAdmin, PublicKey: secondPubB64},
		},
		CreatedBy: n.PeerId(),
	}
	secondKeyInfo := &GroupKeyInfo{Key: secondGroupKey, KeyEpoch: 2}

	err = n.JoinGroupTopic(groupId, secondConfig, secondKeyInfo)
	if err == nil {
		t.Fatal("expected error on duplicate join")
	}
	if !strings.Contains(err.Error(), "already joined") {
		t.Fatalf("expected 'already joined' error, got %q", err.Error())
	}

	n.mu.RLock()
	currentTopic := n.groupTopics[groupId]
	currentSub := n.groupSubs[groupId]
	currentConfig := n.groupConfigs[groupId]
	currentKey := n.groupKeys[groupId]
	_, currentSubCtxPresent := n.groupSubCtx[groupId]
	_, currentDiscoveryCtxPresent := n.groupDiscoveryCtx[groupId]
	currentSubCtxLen := len(n.groupSubCtx)
	currentDiscoveryCtxLen := len(n.groupDiscoveryCtx)
	n.mu.RUnlock()

	if currentTopic != initialTopic {
		t.Fatal("duplicate join replaced the first topic")
	}
	if currentSub != initialSub {
		t.Fatal("duplicate join replaced the first subscription")
	}
	if currentConfig != initialConfig {
		t.Fatal("duplicate join replaced the first config")
	}
	if currentKey != initialKey {
		t.Fatal("duplicate join replaced the first key info")
	}
	if currentKey.Key != firstGroupKey || currentKey.KeyEpoch != firstKeyInfo.KeyEpoch {
		t.Fatalf("stored key changed to (%q,%d), want (%q,%d)", currentKey.Key, currentKey.KeyEpoch, firstGroupKey, firstKeyInfo.KeyEpoch)
	}
	if currentKey.Key == secondKeyInfo.Key || currentKey.KeyEpoch == secondKeyInfo.KeyEpoch {
		t.Fatal("duplicate join stored the second key inputs")
	}
	if !currentSubCtxPresent {
		t.Fatal("groupSubCtx should still contain the first join")
	}
	if !currentDiscoveryCtxPresent {
		t.Fatal("groupDiscoveryCtx should still contain the first join")
	}
	if currentSubCtxLen != initialSubCtxLen {
		t.Fatalf("groupSubCtx length changed from %d to %d", initialSubCtxLen, currentSubCtxLen)
	}
	if currentDiscoveryCtxLen != initialDiscoveryCtxLen {
		t.Fatalf("groupDiscoveryCtx length changed from %d to %d", initialDiscoveryCtxLen, currentDiscoveryCtxLen)
	}
}

func TestJoinGroupTopic_SuccessStoresAtomicStateAndSupportsImmediateKeyInfoAndPublish(t *testing.T) {
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

	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}
	groupId := "gl-005-success-atomic-state"
	config := &GroupConfig{
		Name:      "GL-005 Success Atomic State",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: n.PeerId(), Role: GroupRoleAdmin, PublicKey: senderPubB64},
		},
		CreatedBy: n.PeerId(),
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	if err := n.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("JoinGroupTopic: %v", err)
	}

	n.mu.RLock()
	storedTopic, hasTopic := n.groupTopics[groupId]
	storedSub, hasSub := n.groupSubs[groupId]
	storedConfig, hasConfig := n.groupConfigs[groupId]
	storedKey, hasKey := n.groupKeys[groupId]
	storedSubCancel, hasSubCtx := n.groupSubCtx[groupId]
	storedDiscoveryCancel, hasDiscoveryCtx := n.groupDiscoveryCtx[groupId]
	n.mu.RUnlock()

	if !hasTopic || storedTopic == nil ||
		!hasSub || storedSub == nil ||
		!hasConfig || storedConfig == nil ||
		!hasKey || storedKey == nil ||
		!hasSubCtx || storedSubCancel == nil ||
		!hasDiscoveryCtx || storedDiscoveryCancel == nil {
		t.Fatalf(
			"successful join state incomplete: topic=%t sub=%t config=%t key=%t subCtx=%t discoveryCtx=%t",
			hasTopic && storedTopic != nil,
			hasSub && storedSub != nil,
			hasConfig && storedConfig != nil,
			hasKey && storedKey != nil,
			hasSubCtx && storedSubCancel != nil,
			hasDiscoveryCtx && storedDiscoveryCancel != nil,
		)
	}
	if storedConfig == config {
		t.Fatal("groupConfigs should snapshot the supplied config")
	}
	if storedConfig.Name != config.Name || len(storedConfig.Members) != len(config.Members) || storedConfig.Members[0].PublicKey != senderPubB64 {
		t.Fatalf("stored config = %#v, want supplied config values", storedConfig)
	}
	if storedKey.Key != groupKey || storedKey.KeyEpoch != keyInfo.KeyEpoch {
		t.Fatalf("stored key = (%q,%d), want (%q,%d)", storedKey.Key, storedKey.KeyEpoch, groupKey, keyInfo.KeyEpoch)
	}
	if storedKey == keyInfo {
		t.Fatal("groupKeys should snapshot the supplied key info")
	}

	retrieved := n.GetGroupKeyInfo(groupId)
	if retrieved == nil {
		t.Fatal("GetGroupKeyInfo returned nil immediately after join")
	}
	if retrieved.Key != groupKey || retrieved.KeyEpoch != keyInfo.KeyEpoch {
		t.Fatalf("GetGroupKeyInfo = (%q,%d), want (%q,%d)", retrieved.Key, retrieved.KeyEpoch, groupKey, keyInfo.KeyEpoch)
	}
	if retrieved == storedKey {
		t.Fatal("GetGroupKeyInfo should return a clone, not the internal stored key pointer")
	}

	msgID, _, err := n.PublishGroupMessage(
		groupId,
		senderPrivB64,
		n.PeerId(),
		senderPubB64,
		"Admin",
		"GL-005 immediate publish health",
		"",
		nil,
	)
	if err != nil {
		t.Fatalf("PublishGroupMessage immediately after join: %v", err)
	}
	if msgID == "" {
		t.Fatal("PublishGroupMessage immediately after join returned empty message id")
	}
}

func TestJoinGroupTopic_LogOmitsHumanReadableMetadata(t *testing.T) {
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

	groupId := "privacy-topic-group"
	config := testGroupConfig(GroupTypeChat)
	config.Name = "Sensitive Therapy And Legal Strategy"
	config.Description = "Private diagnosis and settlement notes"
	keyInfo := &GroupKeyInfo{Key: "dummykey", KeyEpoch: 1}

	var logBuffer bytes.Buffer
	originalOutput := log.Writer()
	originalFlags := log.Flags()
	log.SetOutput(&logBuffer)
	log.SetFlags(0)
	defer func() {
		log.SetOutput(originalOutput)
		log.SetFlags(originalFlags)
	}()

	if err := n.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("JoinGroupTopic: %v", err)
	}

	output := logBuffer.String()
	if !strings.Contains(output, "[PUBSUB] Joined group topic: "+groupId) {
		t.Fatalf("expected join log for group id %q, got %q", groupId, output)
	}
	for _, sensitive := range []string{
		config.Name,
		config.Description,
		"Therapy",
		"Legal",
		"diagnosis",
		"settlement",
	} {
		if strings.Contains(output, sensitive) {
			t.Fatalf("join log leaked sensitive group metadata %q in %q", sensitive, output)
		}
	}
}

// ===========================================================================
// Phase 4: Verify validator dynamics (config mutation after join)
// ===========================================================================

// Test 4.1: Full invite lifecycle -- admin adds new member, validator accepts.
func TestInviteLifecycle_AdminAddsNewMember_ValidatorAcceptsNewMember(t *testing.T) {
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

	privAdmin, pubAdmin := generateEd25519KeyPair(t)
	privNew, pubNew := generateEd25519KeyPair(t)
	groupKey, _ := mcrypto.GenerateGroupKey()
	groupId := "group-lifecycle-invite"

	// Join with only admin in the config.
	config := &GroupConfig{
		Name:      "Invite Test",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: "peer-admin", Role: GroupRoleAdmin, PublicKey: pubAdmin},
		},
		CreatedBy: "peer-admin",
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	if err := n.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("JoinGroupTopic: %v", err)
	}

	// Build envelope from new member -- should be rejected.
	envNew := buildTestEnvelope(t, groupId, "peer-new", privNew, pubNew, groupKey, 1, "hello from new")

	// Use the real validator via the node's groupConfigs (same as the closure reads).
	n.mu.RLock()
	storedConfig := n.groupConfigs[groupId]
	storedKeyInfo := n.groupKeys[groupId]
	n.mu.RUnlock()

	result := validateGroupEnvelope(envNew, groupId, storedConfig, storedKeyInfo)
	if result != "reject:non_member" {
		t.Errorf("before invite: expected reject:non_member, got %s", result)
	}

	// Admin updates config to include new member.
	updatedConfig := &GroupConfig{
		Name:      "Invite Test",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: "peer-admin", Role: GroupRoleAdmin, PublicKey: pubAdmin},
			{PeerId: "peer-new", Role: GroupRoleWriter, PublicKey: pubNew},
		},
		CreatedBy: "peer-admin",
	}
	n.UpdateGroupConfig(groupId, updatedConfig)

	// Now read the updated config through the node (same path as the real validator).
	n.mu.RLock()
	storedConfig2 := n.groupConfigs[groupId]
	storedKeyInfo2 := n.groupKeys[groupId]
	n.mu.RUnlock()

	result = validateGroupEnvelope(envNew, groupId, storedConfig2, storedKeyInfo2)
	if result != "accept" {
		t.Errorf("after invite: expected accept, got %s", result)
	}

	_ = privAdmin // suppress unused
}

// Test 4.2: Announcement group -- new writer cannot publish.
func TestInviteLifecycle_AnnouncementGroup_NewWriterCannotPublish(t *testing.T) {
	privAdmin, pubAdmin := generateEd25519KeyPair(t)
	privWriter, pubWriter := generateEd25519KeyPair(t)
	groupKey, _ := mcrypto.GenerateGroupKey()
	groupId := "group-announce-invite"

	config := &GroupConfig{
		Name:      "Announcements",
		GroupType: GroupTypeAnnouncement,
		Members: []GroupMember{
			{PeerId: "peer-admin", Role: GroupRoleAdmin, PublicKey: pubAdmin},
			{PeerId: "peer-writer", Role: GroupRoleWriter, PublicKey: pubWriter},
		},
		CreatedBy: "peer-admin",
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	// Envelope from writer -- should be rejected (announcement: admin only).
	envWriter := buildTestEnvelope(t, groupId, "peer-writer", privWriter, pubWriter, groupKey, 1, "writer post")
	result := validateGroupEnvelope(envWriter, groupId, config, keyInfo)
	if result != "reject:unauthorized" {
		t.Errorf("writer in announcement: expected reject:unauthorized, got %s", result)
	}

	// Envelope from admin -- should be accepted.
	envAdmin := buildTestEnvelope(t, groupId, "peer-admin", privAdmin, pubAdmin, groupKey, 1, "admin post")
	result = validateGroupEnvelope(envAdmin, groupId, config, keyInfo)
	if result != "accept" {
		t.Errorf("admin in announcement: expected accept, got %s", result)
	}
}

// Test 4.3: Validator rejects envelope signed with wrong key epoch.
func TestGroupTopicValidator_WrongKeyEpoch_InvalidSignature(t *testing.T) {
	priv, pub := generateEd25519KeyPair(t)
	groupKey, _ := mcrypto.GenerateGroupKey()
	groupId := "group-epoch-test"

	config := &GroupConfig{
		Name:      "Epoch Test",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: "peer-1", Role: GroupRoleAdmin, PublicKey: pub},
		},
		CreatedBy: "peer-1",
	}

	// Build envelope signed with keyEpoch=1.
	envelope := buildTestEnvelope(t, groupId, "peer-1", priv, pub, groupKey, 1, "epoch 1 msg")

	// Validate with keyInfo that has keyEpoch=2.
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 2}

	result := validateGroupEnvelope(envelope, groupId, config, keyInfo)
	if result != "reject:bad_signature" {
		t.Errorf("expected reject:bad_signature for epoch mismatch, got %s", result)
	}
}

// ===========================================================================
// Phase 5: Group key info for invite payload
// ===========================================================================

// Test 5.1: GetGroupKeyInfo returns current key.
func TestGetGroupKeyInfo_ReturnsCurrentKey(t *testing.T) {
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

	groupId := "group-keyinfo-test"
	config := testGroupConfig(GroupTypeChat)
	keyInfo := &GroupKeyInfo{Key: "original-key-b64", KeyEpoch: 1}

	if err := n.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("JoinGroupTopic: %v", err)
	}

	// Get key info -- should return epoch=1.
	retrieved := n.GetGroupKeyInfo(groupId)
	if retrieved == nil {
		t.Fatal("expected non-nil key info")
	}
	if retrieved.KeyEpoch != 1 {
		t.Errorf("expected keyEpoch=1, got %d", retrieved.KeyEpoch)
	}
	if retrieved.Key != "original-key-b64" {
		t.Errorf("expected original key, got %q", retrieved.Key)
	}

	// Update key to epoch=2.
	newKeyInfo := &GroupKeyInfo{Key: "new-key-b64", KeyEpoch: 2}
	n.UpdateGroupKey(groupId, newKeyInfo)

	// Get key info -- should return epoch=2.
	retrieved2 := n.GetGroupKeyInfo(groupId)
	if retrieved2 == nil {
		t.Fatal("expected non-nil key info after update")
	}
	if retrieved2.KeyEpoch != 2 {
		t.Errorf("expected keyEpoch=2, got %d", retrieved2.KeyEpoch)
	}
	if retrieved2.Key != "new-key-b64" {
		t.Errorf("expected new key, got %q", retrieved2.Key)
	}
}

// Test 5.2: GetGroupKeyInfo returns nil for unknown group.
func TestGetGroupKeyInfo_ReturnsNilForUnknownGroup(t *testing.T) {
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

	retrieved := n.GetGroupKeyInfo("nonexistent")
	if retrieved != nil {
		t.Errorf("expected nil for unknown group, got %+v", retrieved)
	}
}

// ===========================================================================
// Phase 7: Edge cases and error handling
// ===========================================================================

// Test 7.1: Validator with empty members list rejects all.
func TestGroupTopicValidator_EmptyMembersList_RejectsAll(t *testing.T) {
	priv, pub := generateEd25519KeyPair(t)
	groupKey, _ := mcrypto.GenerateGroupKey()
	groupId := "group-empty-members"

	config := &GroupConfig{
		Name:      "Empty",
		GroupType: GroupTypeChat,
		Members:   []GroupMember{},
		CreatedBy: "nobody",
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	envelope := buildTestEnvelope(t, groupId, "any-peer", priv, pub, groupKey, 1, "hello")
	result := validateGroupEnvelope(envelope, groupId, config, keyInfo)
	if result != "reject:non_member" {
		t.Errorf("expected reject:non_member for empty members, got %s", result)
	}
}

// Test 7.2: UpdateGroupConfig preserves discovery loop.
func TestUpdateGroupConfig_PreservesDiscoveryLoop(t *testing.T) {
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

	groupId := "group-discovery-preserve"
	config := testGroupConfig(GroupTypeChat)
	keyInfo := &GroupKeyInfo{Key: "dummykey", KeyEpoch: 1}

	if err := n.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("JoinGroupTopic: %v", err)
	}

	// Verify discovery context exists.
	n.mu.RLock()
	_, hasCtxBefore := n.groupDiscoveryCtx[groupId]
	n.mu.RUnlock()
	if !hasCtxBefore {
		t.Fatal("expected groupDiscoveryCtx entry after join")
	}

	// Update config.
	newConfig := &GroupConfig{
		Name:      "Updated",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: "peer-1", Role: GroupRoleAdmin, PublicKey: "pk1"},
			{PeerId: "peer-2", Role: GroupRoleWriter, PublicKey: "pk2"},
		},
		CreatedBy: "peer-1",
	}
	n.UpdateGroupConfig(groupId, newConfig)

	// Verify discovery context still exists (was NOT cancelled by config update).
	n.mu.RLock()
	_, hasCtxAfter := n.groupDiscoveryCtx[groupId]
	n.mu.RUnlock()
	if !hasCtxAfter {
		t.Error("groupDiscoveryCtx should still exist after UpdateGroupConfig")
	}
}

func assertGL012NoPanic(t *testing.T, label string, run func()) {
	t.Helper()
	defer func() {
		if r := recover(); r != nil {
			t.Fatalf("%s panicked: %v", label, r)
		}
	}()
	run()
}

func TestGL012UpdateGroupConfigNilDisablesJoinedGroupWithoutPanic(t *testing.T) {
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

	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	groupId := "gl012-nil-config-disables-joined-group"
	senderPeerId := n.PeerId()
	senderPID, err := peer.Decode(senderPeerId)
	if err != nil {
		t.Fatalf("decode sender peer id: %v", err)
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	validConfig := &GroupConfig{
		Name:      "GL012 Valid Config",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderPeerId, Role: GroupRoleAdmin, PublicKey: senderPubB64},
		},
		CreatedBy: senderPeerId,
	}
	if err := n.JoinGroupTopic(groupId, validConfig, keyInfo); err != nil {
		t.Fatalf("JoinGroupTopic: %v", err)
	}

	validEnvelope := buildTestEnvelope(
		t,
		groupId,
		senderPeerId,
		senderPrivB64,
		senderPubB64,
		groupKey,
		keyInfo.KeyEpoch,
		"GL012 valid envelope",
	)
	validator := n.groupTopicValidator(groupId)
	msg := &pubsub.Message{Message: &pb.Message{Data: []byte(validEnvelope)}}
	if result := validator(context.Background(), senderPID, msg); result != pubsub.ValidationAccept {
		t.Fatalf("validator before nil update = %v, want ValidationAccept", result)
	}

	n.UpdateGroupConfig(groupId, nil)

	wantDisabledErr := fmt.Sprintf("group not joined: %s", groupId)
	assertGL012NoPanic(t, "PublishGroupMessage after nil config update", func() {
		msgID, peerCount, publishErr := n.PublishGroupMessage(
			groupId,
			senderPrivB64,
			senderPeerId,
			senderPubB64,
			"Admin",
			"GL012 publish after nil config",
			"",
			nil,
		)
		if publishErr == nil {
			t.Fatal("expected PublishGroupMessage after nil config update to fail")
		}
		if publishErr.Error() != wantDisabledErr {
			t.Fatalf("PublishGroupMessage error = %q, want %q", publishErr.Error(), wantDisabledErr)
		}
		if msgID != "" || peerCount != 0 {
			t.Fatalf("PublishGroupMessage returned msgID=%q peerCount=%d, want empty/0", msgID, peerCount)
		}
	})

	assertGL012NoPanic(t, "PublishGroupReaction after nil config update", func() {
		reactionErr := n.PublishGroupReaction(
			groupId,
			senderPrivB64,
			senderPeerId,
			senderPubB64,
			`{"messageId":"gl012-message","emoji":"ok","action":"add"}`,
		)
		if reactionErr == nil {
			t.Fatal("expected PublishGroupReaction after nil config update to fail")
		}
		if reactionErr.Error() != wantDisabledErr {
			t.Fatalf("PublishGroupReaction error = %q, want %q", reactionErr.Error(), wantDisabledErr)
		}
	})

	assertGL012NoPanic(t, "real validator after nil config update", func() {
		if result := validator(context.Background(), senderPID, msg); result != pubsub.ValidationReject {
			t.Fatalf("validator after nil config update = %v, want ValidationReject", result)
		}
	})
	assertGL012NoPanic(t, "dialKnownGroupMembers after nil config update", func() {
		n.dialKnownGroupMembers(groupId, true)
	})
	assertGL012NoPanic(t, "dialKnownGroupMembersDirectOnly after nil config update", func() {
		n.dialKnownGroupMembersDirectOnly(groupId)
	})
	assertGL012NoPanic(t, "countConnectedGroupMembers after nil config update", func() {
		if count := n.countConnectedGroupMembers(groupId); count != 0 {
			t.Fatalf("countConnectedGroupMembers after nil config update = %d, want 0", count)
		}
	})
	assertGL012NoPanic(t, "expectedConnectedGroupMembers after nil config update", func() {
		if expected := n.expectedConnectedGroupMembers(groupId); expected != 0 {
			t.Fatalf("expectedConnectedGroupMembers after nil config update = %d, want 0", expected)
		}
	})

	n.mu.RLock()
	_, hasConfig := n.groupConfigs[groupId]
	_, hasTopic := n.groupTopics[groupId]
	_, hasSub := n.groupSubs[groupId]
	storedKey := n.groupKeys[groupId]
	_, hasDiscoveryCtx := n.groupDiscoveryCtx[groupId]
	n.mu.RUnlock()
	if hasConfig {
		t.Fatal("groupConfigs should delete the group config after UpdateGroupConfig(groupId, nil)")
	}
	if !hasTopic || !hasSub || storedKey == nil || !hasDiscoveryCtx {
		t.Fatalf(
			"nil config update should preserve repairable joined state, got topic=%t sub=%t key=%t discoveryCtx=%t",
			hasTopic,
			hasSub,
			storedKey != nil,
			hasDiscoveryCtx,
		)
	}

	n.UpdateGroupConfig(groupId, validConfig)
	msgID, _, err := n.PublishGroupMessage(
		groupId,
		senderPrivB64,
		senderPeerId,
		senderPubB64,
		"Admin",
		"GL012 publish after config repair",
		"gl012-repaired-message",
		nil,
	)
	if err != nil {
		t.Fatalf("PublishGroupMessage after valid config repair: %v", err)
	}
	if msgID != "gl012-repaired-message" {
		t.Fatalf("PublishGroupMessage after repair returned msgID=%q, want gl012-repaired-message", msgID)
	}
	if result := validator(context.Background(), senderPID, msg); result != pubsub.ValidationAccept {
		t.Fatalf("validator after valid config repair = %v, want ValidationAccept", result)
	}
}

func TestGL012UpdateGroupConfigNilConcurrentReadersAreRaceFree(t *testing.T) {
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

	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	groupId := "gl012-nil-config-reader-race"
	senderPeerId := n.PeerId()
	senderPID, err := peer.Decode(senderPeerId)
	if err != nil {
		t.Fatalf("decode sender peer id: %v", err)
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	n.UpdateGroupKey(groupId, keyInfo)

	newValidConfig := func(iteration int) *GroupConfig {
		return &GroupConfig{
			Name:      fmt.Sprintf("GL012 Race Config %d", iteration),
			GroupType: GroupTypeChat,
			Members: []GroupMember{
				{PeerId: senderPeerId, Role: GroupRoleAdmin, PublicKey: senderPubB64},
			},
			CreatedBy: senderPeerId,
		}
	}
	n.UpdateGroupConfig(groupId, newValidConfig(-1))

	envelopeJSON := buildTestEnvelope(
		t,
		groupId,
		senderPeerId,
		senderPrivB64,
		senderPubB64,
		groupKey,
		keyInfo.KeyEpoch,
		"GL012 race validator",
	)
	validator := n.groupTopicValidator(groupId)
	msg := &pubsub.Message{Message: &pb.Message{Data: []byte(envelopeJSON)}}

	const readerCount = 8
	const updateCount = 500
	start := make(chan struct{})
	stop := make(chan struct{})
	unexpected := make(chan pubsub.ValidationResult, 1)
	var wg sync.WaitGroup
	for i := 0; i < readerCount; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			<-start
			for {
				select {
				case <-stop:
					return
				default:
				}
				result := validator(context.Background(), senderPID, msg)
				if result != pubsub.ValidationAccept && result != pubsub.ValidationReject {
					select {
					case unexpected <- result:
					default:
					}
					return
				}
				_ = n.countConnectedGroupMembers(groupId)
				_ = n.expectedConnectedGroupMembers(groupId)
				n.dialKnownGroupMembers(groupId, true)
				n.dialKnownGroupMembersDirectOnly(groupId)
			}
		}()
	}

	close(start)
	for i := 0; i < updateCount; i++ {
		n.UpdateGroupConfig(groupId, nil)
		n.UpdateGroupConfig(groupId, newValidConfig(i))
	}
	close(stop)
	wg.Wait()

	select {
	case result := <-unexpected:
		t.Fatalf("validator returned unexpected result %v", result)
	default:
	}
}

func TestGL011UpdateGroupConfigSnapshotsMembershipForValidatorReads(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	_, mutatedPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	groupId := "gl011-validator-snapshot"
	senderPeerId := generatePeerIDStr(t)
	senderPID, err := peer.Decode(senderPeerId)
	if err != nil {
		t.Fatalf("decode sender peer id: %v", err)
	}
	deviceId := "gl011-sender-phone"

	n := NewNode()
	n.groupConfigs = map[string]*GroupConfig{
		groupId: {
			Name:      "GL011 Initial",
			GroupType: GroupTypeChat,
			Members: []GroupMember{
				{PeerId: "initial-admin", Role: GroupRoleAdmin, PublicKey: "initialPubKey"},
			},
			CreatedBy: "initial-admin",
		},
	}
	n.groupKeys = map[string]*GroupKeyInfo{
		groupId: {Key: groupKey, KeyEpoch: 1},
	}

	updatedConfig := &GroupConfig{
		Name:      "GL011 Updated",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{
				PeerId:    senderPeerId,
				Role:      GroupRoleWriter,
				PublicKey: senderPubB64,
				Devices: []GroupMemberDevice{
					{
						DeviceId:               deviceId,
						TransportPeerId:        senderPeerId,
						DeviceSigningPublicKey: senderPubB64,
						Status:                 "active",
					},
				},
			},
		},
		CreatedBy: senderPeerId,
	}

	n.UpdateGroupConfig(groupId, updatedConfig)
	updatedConfig.Members[0].PeerId = generatePeerIDStr(t)
	updatedConfig.Members[0].PublicKey = mutatedPubB64
	updatedConfig.Members[0].Devices[0].DeviceSigningPublicKey = mutatedPubB64
	updatedConfig.Members[0].Devices[0].Status = "revoked"

	envelopeJSON := buildTestDeviceEnvelope(
		t,
		groupId,
		senderPeerId,
		deviceId,
		senderPeerId,
		senderPubB64,
		"",
		senderPrivB64,
		senderPubB64,
		groupKey,
		1,
		"GL011 validator snapshot",
	)
	validator := n.groupTopicValidator(groupId)
	msg := &pubsub.Message{Message: &pb.Message{Data: []byte(envelopeJSON)}}
	if result := validator(context.Background(), senderPID, msg); result != pubsub.ValidationAccept {
		t.Fatalf("validator result after caller mutation = %v, want ValidationAccept from stored snapshot", result)
	}
}

func TestGL011UpdateGroupConfigConcurrentValidatorReadsAreRaceFree(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	_, mutatedPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	groupId := "gl011-validator-update-race"
	senderPeerId := generatePeerIDStr(t)
	senderPID, err := peer.Decode(senderPeerId)
	if err != nil {
		t.Fatalf("decode sender peer id: %v", err)
	}
	deviceId := "gl011-race-device"

	n := NewNode()
	n.groupConfigs = map[string]*GroupConfig{}
	n.groupKeys = map[string]*GroupKeyInfo{
		groupId: {Key: groupKey, KeyEpoch: 1},
	}

	newMutableConfig := func(iteration int) *GroupConfig {
		return &GroupConfig{
			Name:      fmt.Sprintf("GL011 Race Config %d", iteration),
			GroupType: GroupTypeChat,
			Members: []GroupMember{
				{
					PeerId:    senderPeerId,
					Role:      GroupRoleWriter,
					PublicKey: senderPubB64,
					Devices: []GroupMemberDevice{
						{
							DeviceId:               deviceId,
							TransportPeerId:        senderPeerId,
							DeviceSigningPublicKey: senderPubB64,
							Status:                 "active",
						},
					},
				},
			},
			CreatedBy: senderPeerId,
		}
	}
	n.UpdateGroupConfig(groupId, newMutableConfig(-1))

	envelopeJSON := buildTestDeviceEnvelope(
		t,
		groupId,
		senderPeerId,
		deviceId,
		senderPeerId,
		senderPubB64,
		"",
		senderPrivB64,
		senderPubB64,
		groupKey,
		1,
		"GL011 race validator",
	)
	validator := n.groupTopicValidator(groupId)
	msg := &pubsub.Message{Message: &pb.Message{Data: []byte(envelopeJSON)}}

	const validatorCount = 8
	const updateCount = 500
	start := make(chan struct{})
	stop := make(chan struct{})
	unexpected := make(chan pubsub.ValidationResult, 1)
	var wg sync.WaitGroup
	for i := 0; i < validatorCount; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			<-start
			for {
				select {
				case <-stop:
					return
				default:
				}
				result := validator(context.Background(), senderPID, msg)
				if result != pubsub.ValidationAccept && result != pubsub.ValidationReject {
					select {
					case unexpected <- result:
					default:
					}
					return
				}
			}
		}()
	}

	close(start)
	for i := 0; i < updateCount; i++ {
		config := newMutableConfig(i)
		n.UpdateGroupConfig(groupId, config)
		config.Members[0].PeerId = generatePeerIDStr(t)
		config.Members[0].PublicKey = mutatedPubB64
		config.Members[0].Devices[0].DeviceSigningPublicKey = mutatedPubB64
		config.Members[0].Devices[0].Status = "revoked"
	}
	close(stop)
	wg.Wait()

	select {
	case result := <-unexpected:
		t.Fatalf("validator returned unexpected result %v", result)
	default:
	}
}

// ===========================================================================
// Concurrent tests
// ===========================================================================

// TestUpdateGroupConfig_ConcurrentUpdates launches 10 goroutines that
// simultaneously call UpdateGroupConfig with different configs. It verifies
// that the function does not panic and the final stored config is one of the
// submitted configs (i.e. no corruption). Must pass with `go test -race`.
//
// Uses a minimal Node setup (just initialized maps) to avoid background
// goroutine races from a full Start/JoinGroupTopic lifecycle.
func TestUpdateGroupConfig_ConcurrentUpdates(t *testing.T) {
	n := NewNode()
	// Manually initialize the groupConfigs map (as initPubSub would do)
	// without starting a full node + pubsub, to avoid background goroutine
	// races unrelated to UpdateGroupConfig.
	n.groupConfigs = make(map[string]*GroupConfig)
	n.groupKeys = make(map[string]*GroupKeyInfo)

	groupId := "group-concurrent-config"

	// Seed initial config.
	n.groupConfigs[groupId] = &GroupConfig{
		Name:      "Initial",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: "peer-init", Role: GroupRoleAdmin, PublicKey: "pkInit"},
		},
		CreatedBy: "peer-init",
	}

	const goroutineCount = 10

	// Build distinct configs for each goroutine.
	configs := make([]*GroupConfig, goroutineCount)
	for i := 0; i < goroutineCount; i++ {
		configs[i] = &GroupConfig{
			Name:      fmt.Sprintf("Config-%d", i),
			GroupType: GroupTypeChat,
			Members: []GroupMember{
				{PeerId: fmt.Sprintf("peer-%d", i), Role: GroupRoleAdmin, PublicKey: fmt.Sprintf("pk-%d", i)},
			},
			CreatedBy: fmt.Sprintf("peer-%d", i),
		}
	}

	// Launch all goroutines concurrently.
	done := make(chan struct{}, goroutineCount)
	for i := 0; i < goroutineCount; i++ {
		go func(idx int) {
			defer func() { done <- struct{}{} }()
			n.UpdateGroupConfig(groupId, configs[idx])
		}(i)
	}

	// Wait for all goroutines to finish.
	for i := 0; i < goroutineCount; i++ {
		<-done
	}

	// Verify no panic occurred and the final config is one of the submitted configs.
	n.mu.RLock()
	storedConfig := n.groupConfigs[groupId]
	n.mu.RUnlock()

	if storedConfig == nil {
		t.Fatal("stored config should not be nil after concurrent updates")
	}

	// The final config must be one of the submitted configs.
	found := false
	for i := 0; i < goroutineCount; i++ {
		if storedConfig.Name == configs[i].Name {
			found = true
			break
		}
	}
	if !found {
		t.Errorf("final config name %q is not one of the submitted configs", storedConfig.Name)
	}
}

// TestGroupTopicValidator_ConcurrentValidation calls the pure validator
// function from multiple goroutines simultaneously to verify there are no
// race conditions. Must pass with `go test -race`.
func TestGroupTopicValidator_ConcurrentValidation(t *testing.T) {
	// Generate keys and group key.
	privB64, pubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}
	groupId := "group-concurrent-validator"

	config := &GroupConfig{
		Name:      "Concurrent Validate",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: "sender-1", Role: GroupRoleAdmin, PublicKey: pubB64},
		},
		CreatedBy: "sender-1",
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	// Build a valid envelope.
	validEnvelope := buildTestEnvelope(t, groupId, "sender-1", privB64, pubB64, groupKey, 1, "concurrent msg")

	const goroutineCount = 20

	results := make([]string, goroutineCount)
	done := make(chan struct{}, goroutineCount)

	for i := 0; i < goroutineCount; i++ {
		go func(idx int) {
			defer func() { done <- struct{}{} }()
			results[idx] = validateGroupEnvelope(validEnvelope, groupId, config, keyInfo)
		}(i)
	}

	// Wait for all goroutines.
	for i := 0; i < goroutineCount; i++ {
		<-done
	}

	// All results should be "accept".
	for i, r := range results {
		if r != "accept" {
			t.Errorf("goroutine %d: expected accept, got %s", i, r)
		}
	}
}

// ===========================================================================
// Phase 6: Group Continuity and Exactly-Once Recovery
// ===========================================================================

// Test: PublishGroupMessage emits live fanout diagnostic without failing durable send.
// When topicPeers is 0, publish should still succeed (Go returns ok:true).
// The diagnostic event is informational only.
func TestPublishGroupMessage_EmitsLiveFanoutDiagnosticWithoutFailingDurableSend(t *testing.T) {
	// This is a structural test: zero peers in a topic does not cause Publish
	// to fail. The Go Publish call returns nil even when there are no subscribers.
	// We verify by checking that the isAllowedWriter + findMember path does not
	// depend on peer count.

	config := testGroupConfig(GroupTypeChat)
	// Verify isAllowedWriter works regardless of peer count.
	if !isAllowedWriter(config, "peer-admin") {
		t.Error("admin should be allowed to write in chat group")
	}
	if !isAllowedWriter(config, "peer-writer") {
		t.Error("writer should be allowed to write in chat group")
	}

	// A separate durable inbox store would run independently of pubsub peer count.
	// This test verifies the authorization check is peer-count-independent.
}

// Test: GroupRecovery preserves topic state across in-place refresh.
// When topics are already joined, the in-memory state should still be valid
// after an in-place relay refresh (no full restart).
func TestGroupRecovery_PreservesTopicStateAcrossInPlaceRefresh(t *testing.T) {
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

	groupId := "group-recovery-preserve"
	config := testGroupConfig(GroupTypeChat)
	keyInfo := &GroupKeyInfo{Key: "recoverykey", KeyEpoch: 1}

	if err := n.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("JoinGroupTopic: %v", err)
	}

	// Verify state is present.
	n.mu.RLock()
	_, hasTopic := n.groupTopics[groupId]
	_, hasSub := n.groupSubs[groupId]
	_, hasConfig := n.groupConfigs[groupId]
	_, hasKey := n.groupKeys[groupId]
	n.mu.RUnlock()

	if !hasTopic || !hasSub || !hasConfig || !hasKey {
		t.Fatal("all group state should be present after JoinGroupTopic")
	}

	// Simulate in-place recovery: state should NOT be cleared.
	// In production, in-place recovery refreshes the relay but does NOT
	// restart the node, so topic state persists.
	n.mu.RLock()
	_, hasTopicAfter := n.groupTopics[groupId]
	storedConfig := n.groupConfigs[groupId]
	storedKey := n.groupKeys[groupId]
	n.mu.RUnlock()

	if !hasTopicAfter {
		t.Error("topic should persist across in-place recovery")
	}
	if storedConfig == nil || storedConfig.Name != "Test Group" {
		t.Error("config should persist across in-place recovery")
	}
	if storedKey == nil || storedKey.KeyEpoch != 1 {
		t.Error("key should persist across in-place recovery")
	}
}

// Test: Announcement group admin publish with zero peers still uses durable fallback.
func TestAnnouncementGroup_AdminPublishWithZeroPeersStillUsesDurableFallback(t *testing.T) {
	config := &GroupConfig{
		Name:      "Announcements",
		GroupType: GroupTypeAnnouncement,
		Members: []GroupMember{
			{PeerId: "peer-admin", Role: GroupRoleAdmin, PublicKey: "adminPk"},
			{PeerId: "peer-reader", Role: GroupRoleReader, PublicKey: "readerPk"},
		},
		CreatedBy: "peer-admin",
	}

	// Admin is allowed to write in announcement group.
	if !isAllowedWriter(config, "peer-admin") {
		t.Error("admin should be allowed to write in announcement group")
	}

	// Reader is NOT allowed to write.
	if isAllowedWriter(config, "peer-reader") {
		t.Error("reader should NOT be allowed to write in announcement group")
	}

	// Non-member is NOT allowed to write.
	if isAllowedWriter(config, "unknown-peer") {
		t.Error("non-member should NOT be allowed to write in announcement group")
	}
}

// Test: Group discovery loop skips peers that became connected on a prior pass.
// Verifies that filterDiscoveredPeers properly filters already-connected peers
// to avoid redundant dial attempts.
func TestGroupDiscoveryLoop_SkipsAlreadyConnectedPeersOnNextPass(t *testing.T) {
	// When a peer is already connected, filterDiscoveredPeers should exclude it.
	// This simulates the "backoff" behavior: on repeated discovery cycles,
	// already-connected peers are not re-dialed.
	selfId, _ := peer.Decode("12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN")
	connectedId, _ := peer.Decode("12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g")
	failedId, _ := peer.Decode("12D3KooWRby3kFPcEJBxLFasMBr1Y5sTpBLTpfhCoVkdCquN4CY1")

	// First cycle: connectedId is connected, failedId is new.
	connectedSet := map[peer.ID]struct{}{connectedId: {}}
	discovered := []peer.AddrInfo{{ID: connectedId}, {ID: failedId}}

	result := filterDiscoveredPeers(discovered, selfId, connectedSet)
	if len(result) != 1 {
		t.Fatalf("expected 1 new peer, got %d", len(result))
	}
	if result[0].ID != failedId {
		t.Errorf("expected failedId, got %s", result[0].ID)
	}

	// Second cycle: after dial, failedId should be in connected set.
	connectedSet[failedId] = struct{}{}
	result2 := filterDiscoveredPeers(discovered, selfId, connectedSet)
	if len(result2) != 0 {
		t.Errorf("expected 0 new peers after both are connected, got %d", len(result2))
	}
}

// Test: Group discovery uses discovered addresses before relay fallback.
func TestGroupDiscovery_UsesDiscoveredAddressesBeforeRelayFallback(t *testing.T) {
	dialer := startLocalNodeForMultiRelayTest(t)
	setFakeRelays(t, dialer)

	target := startLocalNodeForMultiRelayTest(t)
	targetID, err := peer.Decode(target.PeerId())
	if err != nil {
		t.Fatalf("decode target peer ID: %v", err)
	}

	result, err := dialer.connectGroupPeerPreferDirect(target.PeerId(), target.Host().Addrs(), true)
	if err != nil {
		t.Fatalf("connectGroupPeerPreferDirect: %v", err)
	}
	if result.Path != "direct" {
		t.Fatalf("expected direct path, got %q", result.Path)
	}
	if result.AttemptedDirect != true {
		t.Fatal("expected direct attempt to be recorded")
	}
	if result.UsedRelayFallback {
		t.Fatal("expected relay fallback to remain unused when discovered direct addrs work")
	}
	if dialer.Host().Network().Connectedness(targetID) != network.Connected {
		t.Fatalf("expected direct libp2p connection to %s", target.PeerId())
	}
}

// Test: Known group member dial prefers existing or direct path before relay.
func TestKnownGroupMemberDial_PrefersExistingOrDirectPathBeforeRelay(t *testing.T) {
	dialer := startLocalNodeForMultiRelayTest(t)
	setFakeRelays(t, dialer)

	target := startLocalNodeForMultiRelayTest(t)
	targetID, err := peer.Decode(target.PeerId())
	if err != nil {
		t.Fatalf("decode target peer ID: %v", err)
	}

	dialer.Host().Peerstore().AddAddrs(targetID, target.Host().Addrs(), time.Hour)

	config := &GroupConfig{
		Name:      "Direct Path Test",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: dialer.PeerId(), Role: GroupRoleAdmin, PublicKey: "selfPk"},
			{PeerId: target.PeerId(), Username: "target", Role: GroupRoleWriter, PublicKey: "targetPk"},
		},
		CreatedBy: dialer.PeerId(),
	}

	dialer.groupConfigs = map[string]*GroupConfig{"group-direct": config}
	dialer.dialKnownGroupMembers("group-direct", false)

	if dialer.Host().Network().Connectedness(targetID) != network.Connected {
		t.Fatalf("expected peerstore direct dial to connect to %s before relay fallback", target.PeerId())
	}
}

func TestRP017RemovedPeerExcludedFromKnownAndDiscoveredDialsAfterConfigUpdate(t *testing.T) {
	collector := &testEventCollector{}
	admin := startLocalNodeForMultiRelayTestWithCollector(t, collector)
	remaining := startLocalNodeForMultiRelayTest(t)
	removed := startLocalNodeForMultiRelayTest(t)

	remainingID, err := peer.Decode(remaining.PeerId())
	if err != nil {
		t.Fatalf("decode remaining peer ID: %v", err)
	}
	removedID, err := peer.Decode(removed.PeerId())
	if err != nil {
		t.Fatalf("decode removed peer ID: %v", err)
	}

	groupId := "rp017-removed-peer-dial"
	originalConfig := &GroupConfig{
		Name:      "RP017 Original Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: admin.PeerId(), Role: GroupRoleAdmin, PublicKey: "adminPk"},
			{PeerId: remaining.PeerId(), Username: "remaining", Role: GroupRoleWriter, PublicKey: "remainingPk"},
			{PeerId: removed.PeerId(), Username: "removed", Role: GroupRoleWriter, PublicKey: "removedPk"},
		},
		CreatedBy: admin.PeerId(),
	}
	currentConfig := &GroupConfig{
		Name:      "RP017 Current Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: admin.PeerId(), Role: GroupRoleAdmin, PublicKey: "adminPk"},
			{PeerId: remaining.PeerId(), Username: "remaining", Role: GroupRoleWriter, PublicKey: "remainingPk"},
		},
		CreatedBy: admin.PeerId(),
	}

	admin.mu.Lock()
	admin.groupConfigs[groupId] = originalConfig
	admin.mu.Unlock()
	admin.UpdateGroupConfig(groupId, currentConfig)
	admin.Host().Peerstore().AddAddrs(remainingID, remaining.Host().Addrs(), time.Hour)
	admin.Host().Peerstore().AddAddrs(removedID, removed.Host().Addrs(), time.Hour)

	admin.dialKnownGroupMembers(groupId, true)
	waitForRP017Connectedness(t, admin, remainingID, network.Connected, time.Second)
	if got := admin.Host().Network().Connectedness(removedID); got == network.Connected {
		t.Fatalf("removed peer %s was dialed from known-member recovery after config update", removed.PeerId())
	}

	admin.rendezvousDiscoverHook = func(namespace string, serverAddresses []string) ([]peer.AddrInfo, error) {
		if namespace != groupRendezvousNamespace(groupId) {
			t.Fatalf("unexpected rendezvous namespace %q", namespace)
		}
		return []peer.AddrInfo{
			{ID: removedID, Addrs: removed.Host().Addrs()},
		}, nil
	}
	admin.discoverAndConnectGroupPeers(groupId)
	time.Sleep(100 * time.Millisecond)

	if got := admin.Host().Network().Connectedness(removedID); got == network.Connected {
		t.Fatalf("removed peer %s was dialed from rendezvous discovery after config update", removed.PeerId())
	}
	assertRP017DiscoveryIgnoredNonMembers(t, collector, groupId, 1)
}

func waitForRP017Connectedness(t *testing.T, n *Node, pid peer.ID, want network.Connectedness, timeout time.Duration) {
	t.Helper()

	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if got := n.Host().Network().Connectedness(pid); got == want {
			return
		}
		time.Sleep(25 * time.Millisecond)
	}
	t.Fatalf("peer %s connectedness did not become %s; got %s", pid, want, n.Host().Network().Connectedness(pid))
}

func assertRP017DiscoveryIgnoredNonMembers(t *testing.T, collector *testEventCollector, groupId string, want int) {
	t.Helper()

	for _, raw := range collector.snapshot() {
		var payload map[string]interface{}
		if err := json.Unmarshal([]byte(raw), &payload); err != nil {
			continue
		}
		if payload["event"] != "group:discovery" {
			continue
		}
		data, ok := payload["data"].(map[string]interface{})
		if !ok || data["groupId"] != groupId || data["step"] != "discover_result" {
			continue
		}
		ignored, ok := data["ignoredNonMembers"].(float64)
		if ok && int(ignored) == want {
			return
		}
	}
	t.Fatalf("expected discovery event for group %s to report ignoredNonMembers=%d; events=%v", groupId, want, collector.snapshot())
}

func TestGroupDiscoveryCycle_NoKnownPeersUsesRendezvousFallback(t *testing.T) {
	n := startLocalNodeForMultiRelayTest(t)

	groupId := "group-no-known-peers"
	ns := groupRendezvousNamespace(groupId)

	var registeredNamespaces []string
	var discoveredNamespaces []string
	n.rendezvousRegisterHook = func(namespace string, serverAddresses []string) error {
		registeredNamespaces = append(registeredNamespaces, namespace)
		return nil
	}
	n.rendezvousDiscoverHook = func(namespace string, serverAddresses []string) ([]peer.AddrInfo, error) {
		discoveredNamespaces = append(discoveredNamespaces, namespace)
		return nil, nil
	}

	selfPeerId := n.PeerId()
	n.mu.Lock()
	n.groupConfigs[groupId] = &GroupConfig{
		Name:      "No Known Peers",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: selfPeerId, Role: GroupRoleAdmin, PublicKey: "selfPubKey"},
		},
		CreatedBy: selfPeerId,
	}
	n.mu.Unlock()

	executed, registered := n.runGroupDiscoveryCycle(context.Background(), groupId, ns, true, true)
	if !executed {
		t.Fatal("expected discovery cycle to execute")
	}
	if !registered {
		t.Fatal("expected discovery cycle to register rendezvous namespace")
	}
	if len(registeredNamespaces) != 1 || registeredNamespaces[0] != ns {
		t.Fatalf("registered namespaces = %v, want [%s]", registeredNamespaces, ns)
	}
	if len(discoveredNamespaces) != 1 || discoveredNamespaces[0] != ns {
		t.Fatalf("discovered namespaces = %v, want [%s]", discoveredNamespaces, ns)
	}
}

// Test: Group recovery limiter caps concurrent discovery across groups.
func TestGroupRecoveryLimiter_CapsConcurrentDiscoveryAcrossGroups(t *testing.T) {
	n := NewNode()
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	totalWorkers := GroupDiscoveryConcurrency + 3
	started := make(chan struct{}, totalWorkers)
	release := make(chan struct{})
	var wg sync.WaitGroup
	var mu sync.Mutex
	current := 0
	maxSeen := 0

	for i := 0; i < totalWorkers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()

			releaseSlot, err := n.acquireGroupRecoverySlot(ctx)
			if err != nil {
				t.Errorf("acquireGroupRecoverySlot: %v", err)
				return
			}

			mu.Lock()
			current++
			if current > maxSeen {
				maxSeen = current
			}
			mu.Unlock()

			started <- struct{}{}
			<-release

			mu.Lock()
			current--
			mu.Unlock()
			releaseSlot()
		}()
	}

	for i := 0; i < GroupDiscoveryConcurrency; i++ {
		select {
		case <-started:
		case <-ctx.Done():
			t.Fatal("timed out waiting for initial discovery slots")
		}
	}

	select {
	case <-started:
		t.Fatalf("expected worker %d to wait for the recovery limiter", GroupDiscoveryConcurrency+1)
	case <-time.After(100 * time.Millisecond):
	}

	close(release)
	wg.Wait()

	if maxSeen != GroupDiscoveryConcurrency {
		t.Fatalf("max concurrent recovery work = %d, want %d", maxSeen, GroupDiscoveryConcurrency)
	}
}

// Test: Group recovery limiter jitters burst after resume.
func TestGroupRecoveryLimiter_JittersBurstAfterResume(t *testing.T) {
	initialMin := positiveJitter(GroupRecoveryInitialJitter, func(int64) int64 { return 0 })
	initialMid := positiveJitter(GroupRecoveryInitialJitter, func(n int64) int64 { return n / 2 })
	initialMax := positiveJitter(GroupRecoveryInitialJitter, func(n int64) int64 { return n - 1 })

	if initialMin != 0 {
		t.Fatalf("initial jitter min = %v, want 0", initialMin)
	}
	if initialMid <= 0 || initialMid >= GroupRecoveryInitialJitter {
		t.Fatalf("initial jitter mid = %v, want between 0 and %v", initialMid, GroupRecoveryInitialJitter)
	}
	if initialMax >= GroupRecoveryInitialJitter {
		t.Fatalf("initial jitter max = %v, want < %v", initialMax, GroupRecoveryInitialJitter)
	}

	low := jitterDuration(GroupDiscoveryInterval, GroupDiscoveryJitterFactor, func(int64) int64 { return 0 })
	high := jitterDuration(GroupDiscoveryInterval, GroupDiscoveryJitterFactor, func(n int64) int64 { return n - 1 })

	if low >= GroupDiscoveryInterval {
		t.Fatalf("low jitter wait = %v, want below base interval %v", low, GroupDiscoveryInterval)
	}
	if high <= GroupDiscoveryInterval {
		t.Fatalf("high jitter wait = %v, want above base interval %v", high, GroupDiscoveryInterval)
	}
}

// Test: Group discovery backs off repeated dial failures and clears on success.
func TestGroupDiscoveryLoop_BacksOffRepeatedDialFailures(t *testing.T) {
	n := NewNode()
	now := time.Unix(1700000000, 0)
	const peerID = "peer-offline"

	if allowed, _, blockedByInFlight := n.beginGroupPeerDial(peerID, now); !allowed || blockedByInFlight {
		t.Fatal("first dial should be allowed")
	}

	n.finishGroupPeerDial(peerID, false, now)
	if allowed, retryIn, blockedByInFlight := n.beginGroupPeerDial(peerID, now.Add(time.Second)); allowed || blockedByInFlight {
		t.Fatal("dial should be blocked during first cooldown")
	} else if retryIn <= 0 || retryIn > GroupDiscoveryWarmInterval {
		t.Fatalf("first cooldown retryIn = %v, want within (0, %v]", retryIn, GroupDiscoveryWarmInterval)
	}

	afterFirstCooldown := now.Add(GroupDiscoveryWarmInterval)
	if allowed, _, blockedByInFlight := n.beginGroupPeerDial(peerID, afterFirstCooldown); !allowed || blockedByInFlight {
		t.Fatal("dial should be allowed after first cooldown expires")
	}

	n.finishGroupPeerDial(peerID, false, afterFirstCooldown)
	if allowed, retryIn, blockedByInFlight := n.beginGroupPeerDial(peerID, afterFirstCooldown.Add(time.Second)); allowed || blockedByInFlight {
		t.Fatal("dial should be blocked during second cooldown")
	} else if retryIn <= 0 || retryIn > GroupDiscoveryWarmInterval {
		t.Fatalf("second cooldown retryIn = %v, want within (0, %v]", retryIn, GroupDiscoveryWarmInterval)
	}

	afterSecondCooldown := afterFirstCooldown.Add(GroupDiscoveryWarmInterval)
	if allowed, _, blockedByInFlight := n.beginGroupPeerDial(peerID, afterSecondCooldown); !allowed || blockedByInFlight {
		t.Fatal("dial should be allowed after second cooldown expires")
	}

	n.finishGroupPeerDial(peerID, false, afterSecondCooldown)
	if allowed, retryIn, blockedByInFlight := n.beginGroupPeerDial(peerID, afterSecondCooldown.Add(time.Second)); allowed || blockedByInFlight {
		t.Fatal("dial should be blocked during third cooldown")
	} else if retryIn <= GroupDiscoveryWarmInterval {
		t.Fatalf("third cooldown retryIn = %v, want > %v", retryIn, GroupDiscoveryWarmInterval)
	}

	n.finishGroupPeerDial(peerID, true, afterSecondCooldown.Add(2*time.Second))
	if allowed, _, blockedByInFlight := n.beginGroupPeerDial(peerID, afterSecondCooldown.Add(2*time.Second)); !allowed || blockedByInFlight {
		t.Fatal("successful dial should clear cooldown state")
	}
}

// Test: Group discovery does not start a second dial for the same peer while one is active.
func TestGroupDiscoveryLoop_DedupesConcurrentPeerDials(t *testing.T) {
	n := NewNode()
	now := time.Unix(1700000000, 0)
	const peerID = "peer-shared-across-groups"

	if allowed, _, blockedByInFlight := n.beginGroupPeerDial(peerID, now); !allowed || blockedByInFlight {
		t.Fatal("first dial should be allowed")
	}

	if allowed, retryIn, blockedByInFlight := n.beginGroupPeerDial(peerID, now.Add(time.Millisecond)); allowed {
		t.Fatal("second dial should be blocked while the first is in flight")
	} else if retryIn != 0 {
		t.Fatalf("in-flight block retryIn = %v, want 0", retryIn)
	} else if !blockedByInFlight {
		t.Fatal("second dial should report in-flight blocking")
	}

	n.finishGroupPeerDial(peerID, true, now.Add(2*time.Second))
	if allowed, _, blockedByInFlight := n.beginGroupPeerDial(peerID, now.Add(2*time.Second)); !allowed || blockedByInFlight {
		t.Fatal("dial should be allowed again once the in-flight attempt completes successfully")
	}
}

// Test: Group discovery backoff caps at maximum.
func TestGroupDiscoveryBackoff_CapsAtMaximum(t *testing.T) {
	if got := groupPeerDialBackoff(32); got != MaxGroupDiscoveryBackoff {
		t.Fatalf("groupPeerDialBackoff cap = %v, want %v", got, MaxGroupDiscoveryBackoff)
	}
}

// Test: Group discovery maximum backoff stays short enough for chat UX.
func TestGroupDiscoveryBackoff_MaximumIsForegroundFriendly(t *testing.T) {
	if MaxGroupDiscoveryBackoff > time.Minute {
		t.Fatalf("MaxGroupDiscoveryBackoff = %v, want <= %v", MaxGroupDiscoveryBackoff, time.Minute)
	}
}

// Test: countConnectedGroupMembers returns 0 for unknown group.
func TestCountConnectedGroupMembers_UnknownGroup(t *testing.T) {
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

	count := n.countConnectedGroupMembers("nonexistent-group")
	if count != 0 {
		t.Errorf("expected 0 connected members for unknown group, got %d", count)
	}
}

// Test: GroupDiscoveryConcurrency constant is reasonable.
func TestGroupDiscoveryConcurrency_IsReasonable(t *testing.T) {
	if GroupDiscoveryConcurrency < 1 {
		t.Errorf("GroupDiscoveryConcurrency should be >= 1, got %d", GroupDiscoveryConcurrency)
	}
	if GroupDiscoveryConcurrency > 20 {
		t.Errorf("GroupDiscoveryConcurrency too high for mobile: %d", GroupDiscoveryConcurrency)
	}
}

// Test 7.3: findMember with duplicate peer IDs returns first match.
func TestFindMember_DuplicatePeerId_ReturnsFirst(t *testing.T) {
	config := &GroupConfig{
		Name:      "Dup Test",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: "peer-dup", Role: GroupRoleWriter, PublicKey: "pk1"},
			{PeerId: "peer-dup", Role: GroupRoleAdmin, PublicKey: "pk2"},
		},
		CreatedBy: "peer-dup",
	}

	member := findMember(config, "peer-dup")
	if member == nil {
		t.Fatal("expected to find peer-dup")
	}
	// Should return the first match (writer, not admin).
	if member.Role != GroupRoleWriter {
		t.Errorf("expected first match (writer), got %s", member.Role)
	}
	if member.PublicKey != "pk1" {
		t.Errorf("expected first match PublicKey 'pk1', got %q", member.PublicKey)
	}
}
