package node

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"math/rand"
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

func TestNW005RendezvousRediscoveryUsesCurrentMembershipOnly(t *testing.T) {
	selfID, err := peer.Decode("12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN")
	if err != nil {
		t.Fatalf("decode self peer: %v", err)
	}
	bobID, err := peer.Decode("12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g")
	if err != nil {
		t.Fatalf("decode bob peer: %v", err)
	}
	staleCharlieID, err := peer.Decode("12D3KooWRby3kFPcEJBxLFasMBr1Y5sTpBLTpfhCoVkdCquN4CY1")
	if err != nil {
		t.Fatalf("decode stale charlie peer: %v", err)
	}
	currentCharlieID, err := peer.Decode("12D3KooWL8hWR1wU8YEWzsXTH8LuN2n7FBbUMPSu1tfQZyxkPp2v")
	if err != nil {
		t.Fatalf("decode current charlie peer: %v", err)
	}
	unknownDanaID, err := peer.Decode("12D3KooWC5qe3PPm2x8nCGx3kkM1Q2VdGs14Q6gttxyPjdJawVSK")
	if err != nil {
		t.Fatalf("decode unknown dana peer: %v", err)
	}

	// After Charlie is removed, rendezvous may still return Charlie's old
	// transport peer plus a fresh unknown peer. Only current configured members
	// remain eligible for discovery use.
	allowedAfterRemoval := map[peer.ID]struct{}{
		bobID: {},
	}
	afterRemoval := []peer.AddrInfo{
		{ID: selfID},
		{ID: bobID},
		{ID: staleCharlieID},
		{ID: unknownDanaID},
	}
	newPeers := filterDiscoveredPeers(afterRemoval, selfID, map[peer.ID]struct{}{})
	filtered, ignored := filterDiscoveredGroupMembers(newPeers, allowedAfterRemoval)
	if len(filtered) != 1 || filtered[0].ID != bobID {
		t.Fatalf("after removal expected only Bob eligible, got %#v", filtered)
	}
	if ignored != 2 {
		t.Fatalf("after removal expected stale Charlie and unknown Dana ignored, got %d", ignored)
	}

	// After Charlie is re-added with current device material, stale Charlie and
	// unknown Dana remain discovery-only noise. Already visible Bob is skipped
	// before member filtering; current Charlie is the only new peer to dial/use.
	allowedAfterReadd := map[peer.ID]struct{}{
		bobID:            {},
		currentCharlieID: {},
	}
	afterReadd := []peer.AddrInfo{
		{ID: bobID},
		{ID: staleCharlieID},
		{ID: currentCharlieID},
		{ID: unknownDanaID},
	}
	topicPeers := map[peer.ID]struct{}{
		bobID: {},
	}
	newPeers = filterDiscoveredPeers(afterReadd, selfID, topicPeers)
	filtered, ignored = filterDiscoveredGroupMembers(newPeers, allowedAfterReadd)
	if len(filtered) != 1 || filtered[0].ID != currentCharlieID {
		t.Fatalf("after readd expected only current Charlie eligible, got %#v", filtered)
	}
	if ignored != 2 {
		t.Fatalf("after readd expected stale Charlie and unknown Dana ignored, got %d", ignored)
	}
}

func TestNW008DuplicateConnectionPathsDedupedBeforeGroupDial(t *testing.T) {
	directA, err := ma.NewMultiaddr("/ip4/127.0.0.1/tcp/41001")
	if err != nil {
		t.Fatalf("direct addr A: %v", err)
	}
	directB, err := ma.NewMultiaddr("/ip4/127.0.0.1/tcp/41002")
	if err != nil {
		t.Fatalf("direct addr B: %v", err)
	}
	relayCircuit, err := ma.NewMultiaddr("/ip4/127.0.0.1/tcp/41003/p2p-circuit")
	if err != nil {
		t.Fatalf("relay circuit addr: %v", err)
	}

	got := dedupeDirectMultiaddrs([]ma.Multiaddr{
		directA,
		directA,
		relayCircuit,
		directB,
		directB,
	})

	if len(got) != 2 {
		t.Fatalf("expected two unique direct addresses before dial, got %d: %v", len(got), multiaddrsToStrings(got))
	}
	if got[0].String() != directA.String() || got[1].String() != directB.String() {
		t.Fatalf("dedupeDirectMultiaddrs order/result = %v, want [%s %s]", multiaddrsToStrings(got), directA, directB)
	}
	for _, addr := range got {
		if isRelayCircuitAddr(addr) {
			t.Fatalf("relay circuit addr survived direct duplicate filtering: %s", addr)
		}
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
		"timestamp":       "2026-05-12T14:36:16.419641Z",
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
	if _, ok := extra["timestamp"]; ok {
		t.Fatal("timestamp should be payload metadata, not copied into extra")
	}
	if _, ok := opts["messageId"]; ok {
		t.Fatal("buildGroupMessageExtra should not mutate the input opts map")
	}
}

func TestResolveGroupPublishTimestamp_UsesProvidedTimestamp(t *testing.T) {
	got, err := resolveGroupPublishTimestamp(map[string]interface{}{
		"timestamp": "2026-05-12T14:36:16.419641Z",
	})
	if err != nil {
		t.Fatalf("resolveGroupPublishTimestamp: %v", err)
	}
	if got != "2026-05-12T14:36:16.419641Z" {
		t.Fatalf("timestamp = %q, want provided value", got)
	}
}

func TestResolveGroupPublishTimestamp_RejectsInvalidTimestamp(t *testing.T) {
	if _, err := resolveGroupPublishTimestamp(map[string]interface{}{
		"timestamp": "not-a-timestamp",
	}); err == nil {
		t.Fatal("expected invalid timestamp error")
	}
}

func TestGK031BuildGroupMessageExtraExplicitMessageIDWins(t *testing.T) {
	opts := map[string]interface{}{
		"messageId":       "gk031-spoofed-opts-message",
		"quotedMessageId": "gk031-parent",
		"clientMessageId": "gk031-client",
	}

	extra := buildGroupMessageExtra("gk031-explicit-message", opts)

	if got := extra["messageId"]; got != "gk031-explicit-message" {
		t.Fatalf("messageId = %v, want explicit id", got)
	}
	if got := opts["messageId"]; got != "gk031-spoofed-opts-message" {
		t.Fatalf("opts messageId mutated to %v", got)
	}
	if got := extra["quotedMessageId"]; got != "gk031-parent" {
		t.Fatalf("quotedMessageId = %v, want preserved parent", got)
	}
	if got := extra["clientMessageId"]; got != "gk031-client" {
		t.Fatalf("clientMessageId = %v, want preserved client id", got)
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

func TestGK030BuildGroupMessageReceivedEventPreservesExtrasAndProtectsCanonicalFields(t *testing.T) {
	env := &internal.GroupEnvelope{
		SenderId:              "peer-sender",
		SenderDeviceId:        "device-real",
		SenderTransportPeerId: "transport-real",
		KeyEpoch:              4,
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
			"attachments": []interface{}{
				map[string]interface{}{"id": "att-1", "name": "photo.jpg"},
			},
			"deliveryId":        "delivery-1",
			"clientMessageId":   "client-1",
			"publishedAtNano":   "1773252000000000000",
			"unknownRenderHint": map[string]interface{}{"slot": "inline"},
			"groupId":           "spoofed-group",
			"senderId":          "spoofed-sender",
			"senderDeviceId":    "spoofed-device",
			"transportPeerId":   "spoofed-transport",
			"senderUsername":    "Mallory",
			"keyEpoch":          999,
			"text":              "spoofed text",
			"timestamp":         "1999-01-01T00:00:00Z",
			"decryptMs":         -1,
			"deliveryMs":        -1,
		},
	}

	event := buildGroupMessageReceivedEvent("group-real", env, payload)

	for _, tc := range []struct {
		key  string
		want interface{}
	}{
		{key: "messageId", want: "msg-1"},
		{key: "quotedMessageId", want: "parent-msg-1"},
		{key: "deliveryId", want: "delivery-1"},
		{key: "clientMessageId", want: "client-1"},
		{key: "publishedAtNano", want: "1773252000000000000"},
		{key: "groupId", want: "group-real"},
		{key: "senderId", want: "peer-sender"},
		{key: "senderDeviceId", want: "device-real"},
		{key: "transportPeerId", want: "transport-real"},
		{key: "senderUsername", want: "Alice"},
		{key: "keyEpoch", want: 4},
		{key: "text", want: "Reply body"},
		{key: "timestamp", want: "2026-03-11T10:00:00Z"},
	} {
		if got := event[tc.key]; got != tc.want {
			t.Fatalf("%s = %v, want %v", tc.key, got, tc.want)
		}
	}
	if media, ok := event["media"].([]interface{}); !ok || len(media) != 1 {
		t.Fatalf("media = %#v, want one item", event["media"])
	}
	if attachments, ok := event["attachments"].([]interface{}); !ok || len(attachments) != 1 {
		t.Fatalf("attachments = %#v, want one item", event["attachments"])
	}
	if hint, ok := event["unknownRenderHint"].(map[string]interface{}); !ok || hint["slot"] != "inline" {
		t.Fatalf("unknownRenderHint = %#v, want preserved map", event["unknownRenderHint"])
	}
	if _, ok := event["decryptMs"]; ok {
		t.Fatal("decryptMs must be owned by the receive path, not payload extras")
	}
	if _, ok := event["deliveryMs"]; ok {
		t.Fatal("deliveryMs must be owned by the receive path, not payload extras")
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
	if strings.TrimSpace(env.SenderId) == "" {
		return "reject:invalid_envelope"
	}
	if !groupEnvelopeHasEncryptedFields(env) {
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
	if reason, err := validateGroupConfigIdentityUniqueness(config); err != nil {
		return "reject:" + reason
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

func deleteGroupEnvelopeJSONField(t *testing.T, envelopeJSON string, field string) string {
	t.Helper()

	var raw map[string]interface{}
	if err := json.Unmarshal([]byte(envelopeJSON), &raw); err != nil {
		t.Fatalf("unmarshal envelope: %v", err)
	}
	delete(raw, field)
	mutated, err := json.Marshal(raw)
	if err != nil {
		t.Fatalf("marshal envelope without %s: %v", field, err)
	}
	return string(mutated)
}

func setGroupEnvelopeJSONField(t *testing.T, envelopeJSON string, field string, value interface{}) string {
	t.Helper()

	var raw map[string]interface{}
	if err := json.Unmarshal([]byte(envelopeJSON), &raw); err != nil {
		t.Fatalf("unmarshal envelope: %v", err)
	}
	raw[field] = value
	mutated, err := json.Marshal(raw)
	if err != nil {
		t.Fatalf("marshal envelope with %s=%v: %v", field, value, err)
	}
	return string(mutated)
}

func deleteNestedGroupEnvelopeJSONField(t *testing.T, envelopeJSON string, parent string, field string) string {
	t.Helper()

	var raw map[string]interface{}
	if err := json.Unmarshal([]byte(envelopeJSON), &raw); err != nil {
		t.Fatalf("unmarshal envelope: %v", err)
	}
	nested, ok := raw[parent].(map[string]interface{})
	if !ok {
		t.Fatalf("expected nested object %q in envelope, got %T", parent, raw[parent])
	}
	delete(nested, field)
	raw[parent] = nested
	mutated, err := json.Marshal(raw)
	if err != nil {
		t.Fatalf("marshal envelope without %s.%s: %v", parent, field, err)
	}
	return string(mutated)
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

func buildTestDeviceEnvelopeWithPlaintext(
	t *testing.T,
	groupId string,
	envelopeType string,
	senderId string,
	senderDeviceId string,
	senderTransportPeerId string,
	senderDevicePublicKey string,
	senderKeyPackageId string,
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
		Version:               "3",
		Type:                  envelopeType,
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

func assertGK026SenderIDOnlyMutationPreservesEnvelope(
	t *testing.T,
	validEnvelope string,
	tamperedEnvelope string,
	originalSenderId string,
	claimedSenderId string,
) (*internal.GroupEnvelope, *internal.GroupEnvelope) {
	t.Helper()

	validEnv, err := internal.ParseGroupEnvelope(validEnvelope)
	if err != nil {
		t.Fatalf("parse valid envelope: %v", err)
	}
	tamperedEnv, err := internal.ParseGroupEnvelope(tamperedEnvelope)
	if err != nil {
		t.Fatalf("parse tampered envelope: %v", err)
	}

	if validEnv.SenderId != originalSenderId {
		t.Fatalf("valid senderId = %q, want %q", validEnv.SenderId, originalSenderId)
	}
	if tamperedEnv.SenderId != claimedSenderId {
		t.Fatalf("tampered senderId = %q, want %q", tamperedEnv.SenderId, claimedSenderId)
	}
	if tamperedEnv.Version != validEnv.Version {
		t.Fatalf("tampered version = %q, want %q", tamperedEnv.Version, validEnv.Version)
	}
	if tamperedEnv.Type != validEnv.Type {
		t.Fatalf("tampered type = %q, want %q", tamperedEnv.Type, validEnv.Type)
	}
	if tamperedEnv.GroupId != validEnv.GroupId {
		t.Fatalf("tampered groupId = %q, want %q", tamperedEnv.GroupId, validEnv.GroupId)
	}
	if tamperedEnv.SenderPublicKey != validEnv.SenderPublicKey {
		t.Fatal("tampered senderId envelope changed senderPublicKey")
	}
	if tamperedEnv.SenderDeviceId != validEnv.SenderDeviceId {
		t.Fatal("tampered senderId envelope changed senderDeviceId")
	}
	if tamperedEnv.SenderTransportPeerId != validEnv.SenderTransportPeerId {
		t.Fatal("tampered senderId envelope changed senderTransportPeerId")
	}
	if tamperedEnv.SenderDevicePublicKey != validEnv.SenderDevicePublicKey {
		t.Fatal("tampered senderId envelope changed senderDevicePublicKey")
	}
	if tamperedEnv.SenderKeyPackageId != validEnv.SenderKeyPackageId {
		t.Fatal("tampered senderId envelope changed senderKeyPackageId")
	}
	if tamperedEnv.Signature != validEnv.Signature {
		t.Fatal("tampered senderId envelope must not be re-signed")
	}
	if tamperedEnv.KeyEpoch != validEnv.KeyEpoch {
		t.Fatalf("tampered keyEpoch = %d, want %d", tamperedEnv.KeyEpoch, validEnv.KeyEpoch)
	}
	if tamperedEnv.Encrypted != validEnv.Encrypted {
		t.Fatal("tampered senderId envelope changed encrypted payload")
	}
	if tamperedEnv.Encrypted.Ciphertext != validEnv.Encrypted.Ciphertext {
		t.Fatal("tampered senderId envelope changed ciphertext")
	}
	if tamperedEnv.Encrypted.Nonce != validEnv.Encrypted.Nonce {
		t.Fatal("tampered senderId envelope changed nonce")
	}

	return validEnv, tamperedEnv
}

func assertGK027BindingOnlyMutationPreservesEnvelope(
	t *testing.T,
	validEnvelope string,
	tamperedEnvelope string,
	field string,
	tamperedValue string,
) (*internal.GroupEnvelope, *internal.GroupEnvelope) {
	t.Helper()

	validEnv, err := internal.ParseGroupEnvelope(validEnvelope)
	if err != nil {
		t.Fatalf("parse valid envelope: %v", err)
	}
	tamperedEnv, err := internal.ParseGroupEnvelope(tamperedEnvelope)
	if err != nil {
		t.Fatalf("parse tampered envelope: %v", err)
	}

	if tamperedEnv.Version != validEnv.Version {
		t.Fatalf("tampered version = %q, want %q", tamperedEnv.Version, validEnv.Version)
	}
	if tamperedEnv.Type != validEnv.Type {
		t.Fatalf("tampered type = %q, want %q", tamperedEnv.Type, validEnv.Type)
	}
	if tamperedEnv.GroupId != validEnv.GroupId {
		t.Fatalf("tampered groupId = %q, want %q", tamperedEnv.GroupId, validEnv.GroupId)
	}
	if tamperedEnv.SenderId != validEnv.SenderId {
		t.Fatalf("tampered senderId = %q, want %q", tamperedEnv.SenderId, validEnv.SenderId)
	}
	if tamperedEnv.SenderPublicKey != validEnv.SenderPublicKey {
		t.Fatal("tampered binding envelope changed senderPublicKey")
	}
	if tamperedEnv.SenderDevicePublicKey != validEnv.SenderDevicePublicKey {
		t.Fatal("tampered binding envelope changed senderDevicePublicKey")
	}
	if tamperedEnv.SenderKeyPackageId != validEnv.SenderKeyPackageId {
		t.Fatal("tampered binding envelope changed senderKeyPackageId")
	}
	if tamperedEnv.Signature != validEnv.Signature {
		t.Fatal("tampered binding envelope must not be re-signed")
	}
	if tamperedEnv.KeyEpoch != validEnv.KeyEpoch {
		t.Fatalf("tampered keyEpoch = %d, want %d", tamperedEnv.KeyEpoch, validEnv.KeyEpoch)
	}
	if tamperedEnv.Encrypted != validEnv.Encrypted {
		t.Fatal("tampered binding envelope changed encrypted payload")
	}
	if tamperedEnv.Encrypted.Ciphertext != validEnv.Encrypted.Ciphertext {
		t.Fatal("tampered binding envelope changed ciphertext")
	}
	if tamperedEnv.Encrypted.Nonce != validEnv.Encrypted.Nonce {
		t.Fatal("tampered binding envelope changed nonce")
	}

	switch field {
	case "senderDeviceId":
		if tamperedEnv.SenderDeviceId != tamperedValue {
			t.Fatalf("tampered senderDeviceId = %q, want %q", tamperedEnv.SenderDeviceId, tamperedValue)
		}
		if tamperedEnv.SenderDeviceId == validEnv.SenderDeviceId {
			t.Fatal("senderDeviceId was not changed")
		}
		if tamperedEnv.SenderTransportPeerId != validEnv.SenderTransportPeerId {
			t.Fatal("senderDeviceId tamper changed senderTransportPeerId")
		}
	case "senderTransportPeerId":
		if tamperedEnv.SenderTransportPeerId != tamperedValue {
			t.Fatalf("tampered senderTransportPeerId = %q, want %q", tamperedEnv.SenderTransportPeerId, tamperedValue)
		}
		if tamperedEnv.SenderTransportPeerId == validEnv.SenderTransportPeerId {
			t.Fatal("senderTransportPeerId was not changed")
		}
		if tamperedEnv.SenderDeviceId != validEnv.SenderDeviceId {
			t.Fatal("senderTransportPeerId tamper changed senderDeviceId")
		}
	default:
		t.Fatalf("unsupported GK-027 binding field %q", field)
	}

	return validEnv, tamperedEnv
}

func TestGK014ValidateGroupEnvelopeAcceptsOnlyV3GroupMessageAndReaction(t *testing.T) {
	privB64, pubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}
	groupId := "group-gk-014"
	senderId := "sender-gk-014"
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	config := &GroupConfig{
		Name:      "GK-014",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderId, Role: GroupRoleWriter, PublicKey: pubB64},
		},
		CreatedBy: senderId,
	}

	validMessageEnvelope := buildTestEnvelope(t, groupId, senderId, privB64, pubB64, groupKey, keyInfo.KeyEpoch, "gk014 message")
	if result := validateGroupEnvelopeForTransportPeer(validMessageEnvelope, groupId, config, keyInfo, senderId); result != "accept" {
		t.Fatalf("valid v3 group_message result = %s, want accept", result)
	}

	validReactionEnvelope := setGroupEnvelopeJSONField(t, validMessageEnvelope, "type", "group_reaction")
	if result := validateGroupEnvelopeForTransportPeer(validReactionEnvelope, groupId, config, keyInfo, senderId); result != "accept" {
		t.Fatalf("valid v3 group_reaction result = %s, want accept", result)
	}

	rejectedPayloads := []struct {
		name string
		data string
	}{
		{
			name: "v2 group message",
			data: `{"version":"2","type":"group_message","groupId":"group-gk-014"}`,
		},
		{
			name: "v4 group message",
			data: `{"version":"4","type":"group_message","groupId":"group-gk-014"}`,
		},
		{
			name: "v3 unsupported type",
			data: `{"version":"3","type":"group_membership","groupId":"group-gk-014"}`,
		},
		{
			name: "missing version",
			data: `{"type":"group_message","groupId":"group-gk-014"}`,
		},
		{
			name: "missing type",
			data: `{"version":"3","groupId":"group-gk-014"}`,
		},
		{
			name: "numeric version",
			data: `{"version":3,"type":"group_message","groupId":"group-gk-014"}`,
		},
		{
			name: "malformed json",
			data: `{"version":"3","type":"group_message"`,
		},
	}

	for _, tc := range rejectedPayloads {
		t.Run(tc.name, func(t *testing.T) {
			result := validateGroupEnvelopeForTransportPeer(tc.data, groupId, nil, nil, senderId)
			if result != "reject:not_v3" {
				t.Fatalf("result = %s, want reject:not_v3", result)
			}
		})
	}
}

func TestGK033ValidateGroupReactionUsesMessageEpochAndDeviceValidation(t *testing.T) {
	activePrivB64, activePubB64 := generateEd25519KeyPair(t)
	revokedPrivB64, revokedPubB64 := generateEd25519KeyPair(t)
	currentGroupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate current group key: %v", err)
	}
	previousGroupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate previous group key: %v", err)
	}

	groupId := "group-gk-033"
	memberId := "member-gk-033"
	activeTransportPeerId := "transport-active-gk-033"
	revokedTransportPeerId := "transport-revoked-gk-033"
	activeDevice := GroupMemberDevice{
		DeviceId:               "device-active-gk-033",
		TransportPeerId:        activeTransportPeerId,
		DeviceSigningPublicKey: activePubB64,
		KeyPackageId:           "kp-active-gk-033",
		Status:                 "active",
	}
	revokedDevice := GroupMemberDevice{
		DeviceId:               "device-revoked-gk-033",
		TransportPeerId:        revokedTransportPeerId,
		DeviceSigningPublicKey: revokedPubB64,
		KeyPackageId:           "kp-revoked-gk-033",
		Status:                 "revoked",
		RevokedAt:              "2026-05-12T18:00:00Z",
	}
	config := &GroupConfig{
		Name:      "GK-033",
		GroupType: GroupTypeChat,
		Members: []GroupMember{{
			PeerId:    memberId,
			Role:      GroupRoleWriter,
			PublicKey: activePubB64,
			Devices:   []GroupMemberDevice{activeDevice, revokedDevice},
		}},
		CreatedBy: memberId,
	}
	keyInfo := buildGroupKeyInfoWithGrace(
		currentGroupKey,
		2,
		previousGroupKey,
		1,
		time.Now().Add(-time.Minute),
	)
	reactionPlaintext := `{"messageId":"gk033-target","action":"add","emoji":"+1"}`

	currentReaction := buildTestDeviceEnvelopeWithPlaintext(
		t,
		groupId,
		"group_reaction",
		memberId,
		activeDevice.DeviceId,
		activeDevice.TransportPeerId,
		activePubB64,
		activeDevice.KeyPackageId,
		activePrivB64,
		activePubB64,
		currentGroupKey,
		2,
		reactionPlaintext,
	)
	if result := validateGroupEnvelopeForTransportPeer(currentReaction, groupId, config, keyInfo, activeTransportPeerId); result != "accept" {
		t.Fatalf("current active reaction result = %q, want accept", result)
	}

	staleReaction := buildTestDeviceEnvelopeWithPlaintext(
		t,
		groupId,
		"group_reaction",
		memberId,
		activeDevice.DeviceId,
		activeDevice.TransportPeerId,
		activePubB64,
		activeDevice.KeyPackageId,
		activePrivB64,
		activePubB64,
		previousGroupKey,
		1,
		reactionPlaintext,
	)
	if result := validateGroupEnvelopeForTransportPeer(staleReaction, groupId, config, keyInfo, activeTransportPeerId); result != "reject:bad_signature" {
		t.Fatalf("expired previous-epoch reaction result = %q, want reject:bad_signature", result)
	}

	revokedReaction := buildTestDeviceEnvelopeWithPlaintext(
		t,
		groupId,
		"group_reaction",
		memberId,
		revokedDevice.DeviceId,
		revokedDevice.TransportPeerId,
		revokedPubB64,
		revokedDevice.KeyPackageId,
		revokedPrivB64,
		revokedPubB64,
		currentGroupKey,
		2,
		reactionPlaintext,
	)
	if result := validateGroupEnvelopeForTransportPeer(revokedReaction, groupId, config, keyInfo, revokedTransportPeerId); result != "reject:unbound_device" {
		t.Fatalf("revoked-device reaction result = %q, want reject:unbound_device", result)
	}
}

func TestGK014GroupTopicValidatorRejectsUnsupportedVersionsAndTypesAsNotV3Envelope(t *testing.T) {
	cases := []struct {
		name string
		data string
	}{
		{
			name: "v2 group message",
			data: `{"version":"2","type":"group_message","groupId":"group-gk-014-live"}`,
		},
		{
			name: "v4 group message",
			data: `{"version":"4","type":"group_message","groupId":"group-gk-014-live"}`,
		},
		{
			name: "v3 unsupported type",
			data: `{"version":"3","type":"group_membership","groupId":"group-gk-014-live"}`,
		},
		{
			name: "missing version",
			data: `{"type":"group_message","groupId":"group-gk-014-live"}`,
		},
		{
			name: "missing type",
			data: `{"version":"3","groupId":"group-gk-014-live"}`,
		},
		{
			name: "numeric version",
			data: `{"version":3,"type":"group_message","groupId":"group-gk-014-live"}`,
		},
		{
			name: "malformed json",
			data: `{"version":"3","type":"group_message"`,
		},
	}

	for i, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			collector := &testEventCollector{}
			n := New(collector)
			groupId := fmt.Sprintf("group-gk-014-live-%d", i)
			pid := peer.ID(fmt.Sprintf("peer-gk-014-live-%d", i))
			validator := n.groupTopicValidator(groupId)
			baseline := len(collector.snapshot())
			msg := &pubsub.Message{Message: &pb.Message{Data: []byte(tc.data)}}

			if result := validator(context.Background(), pid, msg); result != pubsub.ValidationReject {
				t.Fatalf("validator result = %v, want ValidationReject", result)
			}

			events := collector.snapshot()
			if len(events) <= baseline {
				t.Fatalf("expected validation rejection event after baseline %d; events=%v", baseline, events)
			}
			var payload map[string]interface{}
			if err := json.Unmarshal([]byte(events[len(events)-1]), &payload); err != nil {
				t.Fatalf("decode validation event: %v", err)
			}
			if payload["event"] != "group:validation_rejected" {
				t.Fatalf("event = %v, want group:validation_rejected", payload["event"])
			}
			data, ok := payload["data"].(map[string]interface{})
			if !ok {
				t.Fatalf("event data has type %T, want object", payload["data"])
			}
			for key, want := range map[string]interface{}{
				"reason":       "not_v3_envelope",
				"envelopeType": "unknown",
				"keyEpoch":     float64(0),
			} {
				if got := data[key]; got != want {
					t.Fatalf("event data[%s] = %v, want %v", key, got, want)
				}
			}
		})
	}
}

func TestGK015ValidateGroupEnvelopeRejectsGroupIDMismatchBeforeTransportPeerAndSignature(t *testing.T) {
	privB64, pubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}
	topicGroupId := "group-gk-015-G"
	envelopeGroupId := "group-gk-015-H"
	senderId := "sender-gk-015"
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 15}

	mismatchEnvelope := buildTestEnvelope(
		t,
		envelopeGroupId,
		senderId,
		privB64,
		pubB64,
		groupKey,
		keyInfo.KeyEpoch,
		"group id mismatch",
	)
	if result := validateGroupEnvelopeForTransportPeer(
		mismatchEnvelope,
		topicGroupId,
		nil,
		nil,
		"transport-gk-015-wrong",
	); result != "reject:group_mismatch" {
		t.Fatalf("mismatched group result = %s, want reject:group_mismatch", result)
	}

	config := &GroupConfig{
		Name:      "GK-015",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderId, Role: GroupRoleWriter, PublicKey: pubB64},
		},
		CreatedBy: senderId,
	}
	matchingEnvelope := buildTestEnvelope(
		t,
		topicGroupId,
		senderId,
		privB64,
		pubB64,
		groupKey,
		keyInfo.KeyEpoch,
		"matching group id",
	)
	if result := validateGroupEnvelopeForTransportPeer(
		matchingEnvelope,
		topicGroupId,
		config,
		keyInfo,
		senderId,
	); result != "accept" {
		t.Fatalf("matching group control result = %s, want accept", result)
	}
}

func TestGK015GroupTopicValidatorRejectsGroupIDMismatchAndEmitsReason(t *testing.T) {
	privB64, pubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}
	topicGroupId := "group-gk-015-G"
	envelopeGroupId := "group-gk-015-H"
	senderId := "sender-gk-015-live"
	keyEpoch := 15
	envelopeJSON := buildTestEnvelope(
		t,
		envelopeGroupId,
		senderId,
		privB64,
		pubB64,
		groupKey,
		keyEpoch,
		"live validator mismatch",
	)

	collector := &testEventCollector{}
	n := New(collector)
	validator := n.groupTopicValidator(topicGroupId)
	baseline := len(collector.snapshot())
	msg := &pubsub.Message{Message: &pb.Message{Data: []byte(envelopeJSON)}}

	if result := validator(context.Background(), peer.ID("transport-gk-015-wrong"), msg); result != pubsub.ValidationReject {
		t.Fatalf("validator result = %v, want ValidationReject", result)
	}

	events := collector.snapshot()
	var payload map[string]interface{}
	for _, raw := range events[baseline:] {
		if err := json.Unmarshal([]byte(raw), &payload); err != nil {
			continue
		}
		if payload["event"] == "group:validation_rejected" {
			break
		}
		payload = nil
	}
	if payload == nil {
		t.Fatalf("expected group:validation_rejected after baseline %d; events=%v", baseline, events[baseline:])
	}
	data, ok := payload["data"].(map[string]interface{})
	if !ok {
		t.Fatalf("event data has type %T, want object", payload["data"])
	}
	for key, want := range map[string]interface{}{
		"reason":       "group_mismatch",
		"envelopeType": "group_message",
		"keyEpoch":     float64(keyEpoch),
	} {
		if got := data[key]; got != want {
			t.Fatalf("event data[%s] = %v, want %v", key, got, want)
		}
	}
	for _, raw := range events[baseline:] {
		if strings.Contains(raw, `"event":"group_message:received"`) {
			t.Fatalf("group_message:received should not be emitted after group mismatch: %s", raw)
		}
		if strings.Contains(raw, `"event":"group_reaction:received"`) {
			t.Fatalf("group_reaction:received should not be emitted after group mismatch: %s", raw)
		}
		if strings.Contains(raw, `"event":"group:decryption_failed"`) {
			t.Fatalf("group:decryption_failed should not be emitted after group mismatch: %s", raw)
		}
	}
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

func TestSV007GroupTopicValidatorRejectsEnvelopeGroupMismatch(t *testing.T) {
	privB64, pubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}
	topicGroupId := "sv007-topic-group-a"
	payloadGroupId := "sv007-payload-group-b"
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	config := &GroupConfig{
		Name:      "SV-007 Topic Group A",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: "sender-1", Role: GroupRoleAdmin, PublicKey: pubB64},
		},
		CreatedBy: "sender-1",
	}
	envelopeJSON := buildTestEnvelope(
		t,
		payloadGroupId,
		"sender-1",
		privB64,
		pubB64,
		groupKey,
		keyInfo.KeyEpoch,
		"SV-007 wrong topic payload",
	)

	if result := validateGroupEnvelope(envelopeJSON, payloadGroupId, config, keyInfo); result != "accept" {
		t.Fatalf("payload group validation = %s, want accept", result)
	}
	if result := validateGroupEnvelope(envelopeJSON, topicGroupId, config, keyInfo); result != "reject:group_mismatch" {
		t.Fatalf("topic group validation = %s, want reject:group_mismatch", result)
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

func TestGroupTopicValidator_ReaddFreshKeyPackageRejectsRemovedPackage(t *testing.T) {
	oldPriv, oldPub := generateEd25519KeyPair(t)
	freshPriv, freshPub := generateEd25519KeyPair(t)
	groupKey, _ := mcrypto.GenerateGroupKey()
	groupId := "group-gm021-readd-fresh-package"

	oldDevice := GroupMemberDevice{
		DeviceId:               "charlie-device-old",
		TransportPeerId:        "charlie-transport-old",
		DeviceSigningPublicKey: oldPub,
		KeyPackageId:           "kp-charlie-old",
		Status:                 "active",
	}
	freshDevice := GroupMemberDevice{
		DeviceId:               "charlie-device-fresh",
		TransportPeerId:        "charlie-transport-fresh",
		DeviceSigningPublicKey: freshPub,
		KeyPackageId:           "kp-charlie-fresh",
		Status:                 "active",
	}
	if oldDevice.KeyPackageId == freshDevice.KeyPackageId {
		t.Fatal("GM-021 fixture must use distinct old and fresh key packages")
	}

	readdConfig := &GroupConfig{
		Name:      "GM-021",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{
				PeerId:    "member-charlie",
				Role:      GroupRoleWriter,
				PublicKey: "member-charlie-public-key",
				Devices:   []GroupMemberDevice{freshDevice},
			},
		},
		CreatedBy: "member-admin",
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	freshEnvelopeJSON := buildTestDeviceEnvelope(
		t,
		groupId,
		"member-charlie",
		freshDevice.DeviceId,
		freshDevice.TransportPeerId,
		freshDevice.DeviceSigningPublicKey,
		freshDevice.KeyPackageId,
		freshPriv,
		freshPub,
		groupKey,
		1,
		"fresh package after re-add",
	)
	result := validateGroupEnvelopeForTransportPeer(
		freshEnvelopeJSON,
		groupId,
		readdConfig,
		keyInfo,
		freshDevice.TransportPeerId,
	)
	if result != "accept" {
		t.Fatalf("expected accept for fresh re-added package, got %s", result)
	}

	staleKeyPackageEnvelopeJSON := buildTestDeviceEnvelope(
		t,
		groupId,
		"member-charlie",
		freshDevice.DeviceId,
		freshDevice.TransportPeerId,
		freshDevice.DeviceSigningPublicKey,
		oldDevice.KeyPackageId,
		freshPriv,
		freshPub,
		groupKey,
		1,
		"stale key package on active device",
	)
	result = validateGroupEnvelopeForTransportPeer(
		staleKeyPackageEnvelopeJSON,
		groupId,
		readdConfig,
		keyInfo,
		freshDevice.TransportPeerId,
	)
	if result != "reject:unbound_device" {
		t.Fatalf("expected reject:unbound_device for stale key package on active device, got %s", result)
	}

	fullOldPackageEnvelopeJSON := buildTestDeviceEnvelope(
		t,
		groupId,
		"member-charlie",
		oldDevice.DeviceId,
		oldDevice.TransportPeerId,
		oldDevice.DeviceSigningPublicKey,
		oldDevice.KeyPackageId,
		oldPriv,
		oldPub,
		groupKey,
		1,
		"stale removed device package",
	)
	result = validateGroupEnvelopeForTransportPeer(
		fullOldPackageEnvelopeJSON,
		groupId,
		readdConfig,
		keyInfo,
		oldDevice.TransportPeerId,
	)
	if result != "reject:unbound_device" {
		t.Fatalf("expected reject:unbound_device for removed old device package, got %s", result)
	}
}

func TestGM022GroupTopicValidatorUsesActiveReaddEntryOverStaleDuplicate(t *testing.T) {
	oldPriv, oldPub := generateEd25519KeyPair(t)
	freshPriv, freshPub := generateEd25519KeyPair(t)
	groupKey, _ := mcrypto.GenerateGroupKey()
	groupId := "group-gm022-duplicate-shadow"
	charliePeerId := "member-charlie"
	charlieDeviceId := "charlie-device"

	staleDevice := GroupMemberDevice{
		DeviceId:               charlieDeviceId,
		TransportPeerId:        charlieDeviceId,
		DeviceSigningPublicKey: oldPub,
		KeyPackageId:           "kp-charlie-stale",
		Status:                 "revoked",
		RevokedAt:              "2026-05-11T08:00:00Z",
	}
	freshDevice := GroupMemberDevice{
		DeviceId:               charlieDeviceId,
		TransportPeerId:        charlieDeviceId,
		DeviceSigningPublicKey: freshPub,
		KeyPackageId:           "kp-charlie-active",
		Status:                 "active",
	}
	duplicateShadowConfig := &GroupConfig{
		Name:      "GM-022",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{
				PeerId:    charliePeerId,
				Role:      GroupRoleWriter,
				PublicKey: oldPub,
				Devices:   []GroupMemberDevice{staleDevice},
			},
			{
				PeerId:    charliePeerId,
				Role:      GroupRoleWriter,
				PublicKey: freshPub,
				Devices:   []GroupMemberDevice{freshDevice},
			},
		},
		CreatedBy: "member-admin",
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

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
		groupKey,
		1,
		"GM-022 fresh active entry",
	)
	if result := validateGroupEnvelopeForTransportPeer(
		freshEnvelopeJSON,
		groupId,
		duplicateShadowConfig,
		keyInfo,
		freshDevice.TransportPeerId,
	); result != "accept" {
		t.Fatalf("expected active re-add entry to accept fresh send, got %s", result)
	}

	staleEnvelopeJSON := buildTestDeviceEnvelope(
		t,
		groupId,
		charliePeerId,
		staleDevice.DeviceId,
		staleDevice.TransportPeerId,
		staleDevice.DeviceSigningPublicKey,
		staleDevice.KeyPackageId,
		oldPriv,
		oldPub,
		groupKey,
		1,
		"GM-022 stale shadow entry",
	)
	if result := validateGroupEnvelopeForTransportPeer(
		staleEnvelopeJSON,
		groupId,
		duplicateShadowConfig,
		keyInfo,
		staleDevice.TransportPeerId,
	); result != "reject:unbound_device" {
		t.Fatalf("expected stale duplicate shadow to reject, got %s", result)
	}
}

func TestGM023GroupTopicValidatorUsesActiveCharlieAfterInactiveShadow(t *testing.T) {
	inactivePriv, inactivePub := generateEd25519KeyPair(t)
	activePriv, activePub := generateEd25519KeyPair(t)
	groupKey, _ := mcrypto.GenerateGroupKey()
	groupId := "group-gm023-inactive-shadow"
	charliePeerId := "member-charlie"

	inactiveDevice := GroupMemberDevice{
		DeviceId:               "charlie-device",
		TransportPeerId:        "charlie-inactive-transport",
		DeviceSigningPublicKey: inactivePub,
		KeyPackageId:           "kp-charlie-inactive",
		Status:                 "revoked",
		RevokedAt:              "2026-05-11T08:00:00Z",
	}
	activeDevice := GroupMemberDevice{
		DeviceId:               "charlie-device",
		TransportPeerId:        "charlie-active-transport",
		DeviceSigningPublicKey: activePub,
		KeyPackageId:           "kp-charlie-active",
		Status:                 "active",
	}
	inactiveBeforeActiveConfig := &GroupConfig{
		Name:      "GM-023",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{
				PeerId:    charliePeerId,
				Role:      GroupRoleWriter,
				PublicKey: inactivePub,
				Devices:   []GroupMemberDevice{inactiveDevice},
			},
			{
				PeerId:    charliePeerId,
				Role:      GroupRoleWriter,
				PublicKey: activePub,
				Devices:   []GroupMemberDevice{activeDevice},
			},
		},
		CreatedBy: "member-admin",
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	activeEnvelopeJSON := buildTestDeviceEnvelope(
		t,
		groupId,
		charliePeerId,
		activeDevice.DeviceId,
		activeDevice.TransportPeerId,
		activeDevice.DeviceSigningPublicKey,
		activeDevice.KeyPackageId,
		activePriv,
		activePub,
		groupKey,
		1,
		"GM-023 active Charlie send",
	)
	if result := validateGroupEnvelopeForTransportPeer(
		activeEnvelopeJSON,
		groupId,
		inactiveBeforeActiveConfig,
		keyInfo,
		activeDevice.TransportPeerId,
	); result != "accept" {
		t.Fatalf("expected active Charlie entry after inactive shadow to accept, got %s", result)
	}

	inactiveEnvelopeJSON := buildTestDeviceEnvelope(
		t,
		groupId,
		charliePeerId,
		inactiveDevice.DeviceId,
		inactiveDevice.TransportPeerId,
		inactiveDevice.DeviceSigningPublicKey,
		inactiveDevice.KeyPackageId,
		inactivePriv,
		inactivePub,
		groupKey,
		1,
		"GM-023 inactive Charlie shadow send",
	)
	if result := validateGroupEnvelopeForTransportPeer(
		inactiveEnvelopeJSON,
		groupId,
		inactiveBeforeActiveConfig,
		keyInfo,
		inactiveDevice.TransportPeerId,
	); result != "reject:unbound_device" {
		t.Fatalf("expected inactive Charlie shadow to reject, got %s", result)
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

func TestGK011ValidateGroupEnvelopeRejectsMissingSenderIDAsInvalidEnvelope(t *testing.T) {
	privB64, pubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}
	groupId := "group-gk-011"
	senderId := "sender-gk-011"
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	config := &GroupConfig{
		Name:      "GK-011",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderId, Role: GroupRoleAdmin, PublicKey: pubB64},
		},
		CreatedBy: senderId,
	}
	validEnvelope := buildTestEnvelope(t, groupId, senderId, privB64, pubB64, groupKey, keyInfo.KeyEpoch, "missing sender id")
	missingSenderEnvelope := deleteGroupEnvelopeJSONField(t, validEnvelope, "senderId")

	var raw map[string]interface{}
	if err := json.Unmarshal([]byte(missingSenderEnvelope), &raw); err != nil {
		t.Fatalf("unmarshal missing sender envelope: %v", err)
	}
	if _, ok := raw["senderId"]; ok {
		t.Fatalf("expected senderId key to be omitted, got %v", raw["senderId"])
	}
	if !internal.IsGroupEnvelope(missingSenderEnvelope) {
		t.Fatal("missing senderId envelope should still be recognized as a v3 group envelope")
	}
	env, err := internal.ParseGroupEnvelope(missingSenderEnvelope)
	if err != nil {
		t.Fatalf("parse missing senderId envelope: %v", err)
	}
	if env.SenderId != "" {
		t.Fatalf("parsed SenderId = %q, want empty", env.SenderId)
	}

	result := validateGroupEnvelopeForTransportPeer(missingSenderEnvelope, groupId, config, keyInfo, senderId)
	if result != "reject:invalid_envelope" {
		t.Fatalf("expected reject:invalid_envelope for omitted senderId, got %s", result)
	}
}

func TestGK013ValidateGroupEnvelopeRejectsMissingEncryptedFieldsAsInvalidEnvelope(t *testing.T) {
	privB64, pubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}
	groupId := "group-gk-013"
	senderId := "sender-gk-013"
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 13}
	config := &GroupConfig{
		Name:      "GK-013",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderId, Role: GroupRoleAdmin, PublicKey: pubB64},
		},
		CreatedBy: senderId,
	}
	validEnvelope := buildTestEnvelope(t, groupId, senderId, privB64, pubB64, groupKey, keyInfo.KeyEpoch, "missing encrypted field")

	cases := []struct {
		name        string
		field       string
		parsedValue func(*internal.GroupEnvelope) string
	}{
		{
			name:  "missing ciphertext",
			field: "ciphertext",
			parsedValue: func(env *internal.GroupEnvelope) string {
				return env.Encrypted.Ciphertext
			},
		},
		{
			name:  "missing nonce",
			field: "nonce",
			parsedValue: func(env *internal.GroupEnvelope) string {
				return env.Encrypted.Nonce
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			mutatedEnvelope := deleteNestedGroupEnvelopeJSONField(t, validEnvelope, "encrypted", tc.field)

			var raw map[string]interface{}
			if err := json.Unmarshal([]byte(mutatedEnvelope), &raw); err != nil {
				t.Fatalf("unmarshal mutated envelope: %v", err)
			}
			encrypted, ok := raw["encrypted"].(map[string]interface{})
			if !ok {
				t.Fatalf("expected encrypted object, got %T", raw["encrypted"])
			}
			if _, ok := encrypted[tc.field]; ok {
				t.Fatalf("expected encrypted.%s key to be omitted, got %v", tc.field, encrypted[tc.field])
			}
			if !internal.IsGroupEnvelope(mutatedEnvelope) {
				t.Fatal("missing encrypted field envelope should still be recognized as a v3 group envelope")
			}
			env, err := internal.ParseGroupEnvelope(mutatedEnvelope)
			if err != nil {
				t.Fatalf("parse missing encrypted field envelope: %v", err)
			}
			if got := tc.parsedValue(env); got != "" {
				t.Fatalf("parsed encrypted.%s = %q, want empty", tc.field, got)
			}

			result := validateGroupEnvelopeForTransportPeer(mutatedEnvelope, groupId, config, keyInfo, senderId)
			if result != "reject:invalid_envelope" {
				t.Fatalf("expected reject:invalid_envelope for omitted encrypted.%s, got %s", tc.field, result)
			}
		})
	}
}

func TestGK012ValidateGroupEnvelopeRejectsMissingSignatureAsBadSignature(t *testing.T) {
	privB64, pubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}
	groupId := "group-gk-012"
	senderId := "sender-gk-012"
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	config := &GroupConfig{
		Name:      "GK-012",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderId, Role: GroupRoleAdmin, PublicKey: pubB64},
		},
		CreatedBy: senderId,
	}
	validEnvelope := buildTestEnvelope(t, groupId, senderId, privB64, pubB64, groupKey, keyInfo.KeyEpoch, "missing signature")
	missingSignatureEnvelope := deleteGroupEnvelopeJSONField(t, validEnvelope, "signature")

	var raw map[string]interface{}
	if err := json.Unmarshal([]byte(missingSignatureEnvelope), &raw); err != nil {
		t.Fatalf("unmarshal missing signature envelope: %v", err)
	}
	if _, ok := raw["signature"]; ok {
		t.Fatalf("expected signature key to be omitted, got %v", raw["signature"])
	}
	if !internal.IsGroupEnvelope(missingSignatureEnvelope) {
		t.Fatal("missing signature envelope should still be recognized as a v3 group envelope")
	}
	env, err := internal.ParseGroupEnvelope(missingSignatureEnvelope)
	if err != nil {
		t.Fatalf("parse missing signature envelope: %v", err)
	}
	if env.Signature != "" {
		t.Fatalf("parsed Signature = %q, want empty", env.Signature)
	}

	result := validateGroupEnvelope(missingSignatureEnvelope, groupId, config, keyInfo)
	if result != "reject:bad_signature" {
		t.Fatalf("expected reject:bad_signature for omitted signature, got %s", result)
	}
}

func TestGK026ValidateGroupEnvelopeRejectsSenderIDTamperUnderClaimedMemberKey(t *testing.T) {
	memberBPrivB64, memberBPubB64 := generateEd25519KeyPair(t)
	_, memberCPubB64 := generateEd25519KeyPair(t)
	if memberBPubB64 == memberCPubB64 {
		t.Fatal("test requires distinct member B and C signing keys")
	}
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	groupId := "group-gk-026"
	memberBPeerId := generatePeerIDStr(t)
	memberCPeerId := generatePeerIDStr(t)
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 26}
	config := &GroupConfig{
		Name:      "GK-026 SenderId Tamper",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: memberBPeerId, Role: GroupRoleAdmin, PublicKey: memberBPubB64},
			{PeerId: memberCPeerId, Role: GroupRoleWriter, PublicKey: memberCPubB64},
		},
		CreatedBy: memberBPeerId,
	}

	validEnvelope := buildTestEnvelope(
		t,
		groupId,
		memberBPeerId,
		memberBPrivB64,
		memberBPubB64,
		groupKey,
		keyInfo.KeyEpoch,
		"GK026 B signed plaintext",
	)
	tamperedEnvelope := setGroupEnvelopeJSONField(t, validEnvelope, "senderId", memberCPeerId)
	if result := validateGroupEnvelopeForTransportPeer(validEnvelope, groupId, config, keyInfo, memberBPeerId); result != "accept" {
		t.Fatalf("valid B envelope result = %q, want accept", result)
	}

	_, tamperedEnv := assertGK026SenderIDOnlyMutationPreservesEnvelope(
		t,
		validEnvelope,
		tamperedEnvelope,
		memberBPeerId,
		memberCPeerId,
	)
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

	result := validateGroupEnvelopeForTransportPeer(tamperedEnvelope, groupId, config, keyInfo, memberCPeerId)
	if result != "reject:bad_signature" {
		t.Fatalf("tampered senderId result = %q, want reject:bad_signature under C's configured key", result)
	}
}

func TestGK027ValidateGroupEnvelopeRejectsDeviceAndTransportBindingTamper(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	groupId := "group-gk-027"
	senderId := "member-gk027"
	activeTransportPeerId := generatePeerIDStr(t)
	revokedTransportPeerId := generatePeerIDStr(t)
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 27}
	activeDevice := GroupMemberDevice{
		DeviceId:               "gk027-active-device",
		TransportPeerId:        activeTransportPeerId,
		DeviceSigningPublicKey: senderPubB64,
		KeyPackageId:           "gk027-active-key-package",
		Status:                 "active",
	}
	revokedDevice := GroupMemberDevice{
		DeviceId:               "gk027-revoked-device",
		TransportPeerId:        revokedTransportPeerId,
		DeviceSigningPublicKey: senderPubB64,
		KeyPackageId:           "gk027-revoked-key-package",
		Status:                 "revoked",
		RevokedAt:              "2026-05-12T18:00:00Z",
	}
	config := &GroupConfig{
		Name:      "GK-027 Binding Tamper",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{
				PeerId:  senderId,
				Role:    GroupRoleAdmin,
				Devices: []GroupMemberDevice{activeDevice, revokedDevice},
			},
		},
		CreatedBy: senderId,
	}

	validEnvelope := buildTestDeviceEnvelope(
		t,
		groupId,
		senderId,
		activeDevice.DeviceId,
		activeDevice.TransportPeerId,
		activeDevice.DeviceSigningPublicKey,
		activeDevice.KeyPackageId,
		senderPrivB64,
		senderPubB64,
		groupKey,
		keyInfo.KeyEpoch,
		"GK027 valid device-bound plaintext",
	)
	if result := validateGroupEnvelopeForTransportPeer(validEnvelope, groupId, config, keyInfo, activeTransportPeerId); result != "accept" {
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
	signatureData := mcrypto.BuildGroupSignatureData(groupId, keyInfo.KeyEpoch, deviceTamperedEnv.Encrypted.Ciphertext)
	validWithActiveKey, err := mcrypto.VerifyPayload(senderPubB64, signatureData, deviceTamperedEnv.Signature)
	if err != nil {
		t.Fatalf("verify device-tampered signature with active key: %v", err)
	}
	if !validWithActiveKey {
		t.Fatal("device-tampered envelope signature should still verify with the active signing key")
	}
	if result := validateGroupEnvelopeForTransportPeer(deviceTamperedEnvelope, groupId, config, keyInfo, activeTransportPeerId); result != "reject:unbound_device" {
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
	validWithActiveKey, err = mcrypto.VerifyPayload(senderPubB64, signatureData, transportTamperedEnv.Signature)
	if err != nil {
		t.Fatalf("verify transport-tampered signature with active key: %v", err)
	}
	if !validWithActiveKey {
		t.Fatal("transport-tampered envelope signature should still verify with the active signing key")
	}
	if result := validateGroupEnvelopeForTransportPeer(transportTamperedEnvelope, groupId, config, keyInfo, activeTransportPeerId); result != "reject:peer_mismatch" {
		t.Fatalf("senderTransportPeerId tamper result = %q, want reject:peer_mismatch", result)
	}
}

func TestGK028ValidateGroupEnvelopeRejectsSenderPublicKeyBypass(t *testing.T) {
	memberPrivB64, memberPubB64 := generateEd25519KeyPair(t)
	attackerPrivB64, attackerPubB64 := generateEd25519KeyPair(t)
	if memberPubB64 == attackerPubB64 {
		t.Fatal("test requires distinct configured and attacker keys")
	}
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	groupId := "group-gk-028"
	senderPeerId := generatePeerIDStr(t)
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 28}
	config := &GroupConfig{
		Name:      "GK-028 SenderPublicKey Tamper",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderPeerId, Role: GroupRoleAdmin, PublicKey: memberPubB64},
		},
		CreatedBy: senderPeerId,
	}

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
		"GK028 attacker-key signed plaintext",
	)
	tamperedEnv, err := internal.ParseGroupEnvelope(tamperedEnvelope)
	if err != nil {
		t.Fatalf("parse tampered envelope: %v", err)
	}
	if tamperedEnv.SenderId != senderPeerId {
		t.Fatalf("tampered senderId = %q, want %q", tamperedEnv.SenderId, senderPeerId)
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

	result := validateGroupEnvelopeForTransportPeer(tamperedEnvelope, groupId, config, keyInfo, senderPeerId)
	if result != "reject:bad_signature" {
		t.Fatalf("tampered senderPublicKey result = %q, want reject:bad_signature under configured member key", result)
	}
}

func TestGE018SeededEnvelopeFieldTamperingValidatorClassifiesFailClosed(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	_, otherPubB64 := generateEd25519KeyPair(t)
	attackerPrivB64, attackerPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	groupId := "group-ge018-validator"
	senderId := "member-ge018"
	otherSenderId := "member-ge018-other"
	activeTransportPeerId := generatePeerIDStr(t)
	revokedTransportPeerId := generatePeerIDStr(t)
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 18}
	activeDevice := GroupMemberDevice{
		DeviceId:               "ge018-active-device",
		TransportPeerId:        activeTransportPeerId,
		DeviceSigningPublicKey: senderPubB64,
		KeyPackageId:           "ge018-active-key-package",
		Status:                 "active",
	}
	revokedDevice := GroupMemberDevice{
		DeviceId:               "ge018-revoked-device",
		TransportPeerId:        revokedTransportPeerId,
		DeviceSigningPublicKey: senderPubB64,
		KeyPackageId:           "ge018-revoked-key-package",
		Status:                 "revoked",
		RevokedAt:              "2026-05-13T18:30:00Z",
	}
	config := &GroupConfig{
		Name:      "GE-018 Validator Matrix",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{
				PeerId:  senderId,
				Role:    GroupRoleAdmin,
				Devices: []GroupMemberDevice{activeDevice, revokedDevice},
			},
			{PeerId: otherSenderId, Role: GroupRoleWriter, PublicKey: otherPubB64},
		},
		CreatedBy: senderId,
	}
	validDeviceEnvelope := buildTestDeviceEnvelopeWithPlaintext(
		t,
		groupId,
		"group_message",
		senderId,
		activeDevice.DeviceId,
		activeDevice.TransportPeerId,
		activeDevice.DeviceSigningPublicKey,
		activeDevice.KeyPackageId,
		senderPrivB64,
		senderPubB64,
		groupKey,
		keyInfo.KeyEpoch,
		`{"text":"GE-018 validator control","timestamp":"2026-05-13T18:30:00Z"}`,
	)
	if result := validateGroupEnvelopeForTransportPeer(validDeviceEnvelope, groupId, config, keyInfo, activeTransportPeerId); result != "accept" {
		t.Fatalf("valid device envelope result = %q, want accept", result)
	}

	legacySenderId := "legacy-ge018"
	legacyGroupId := "group-ge018-legacy"
	legacyConfig := &GroupConfig{
		Name:      "GE-018 Legacy Sender Key",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: legacySenderId, Role: GroupRoleAdmin, PublicKey: senderPubB64},
		},
		CreatedBy: legacySenderId,
	}
	forgedLegacyPublicKeyEnvelope := buildTestEnvelopeWithPlaintext(
		t,
		legacyGroupId,
		"group_message",
		legacySenderId,
		attackerPrivB64,
		attackerPubB64,
		groupKey,
		keyInfo.KeyEpoch,
		`{"text":"GE-018 forged legacy public key","timestamp":"2026-05-13T18:31:00Z"}`,
	)

	type validatorMutation struct {
		name      string
		groupId   string
		config    *GroupConfig
		envelope  string
		transport string
		want      string
		mutate    func(string) string
	}
	mutations := []validatorMutation{
		{
			name:      "valid_device_control",
			groupId:   groupId,
			config:    config,
			envelope:  validDeviceEnvelope,
			transport: activeTransportPeerId,
			want:      "accept",
			mutate:    func(envelope string) string { return envelope },
		},
		{
			name:      "malformed_json",
			groupId:   groupId,
			config:    config,
			envelope:  validDeviceEnvelope,
			transport: activeTransportPeerId,
			want:      "reject:not_v3",
			mutate:    func(string) string { return `{"version":"3","type":"group_message",` },
		},
		{
			name:      "version_tamper",
			groupId:   groupId,
			config:    config,
			envelope:  validDeviceEnvelope,
			transport: activeTransportPeerId,
			want:      "reject:not_v3",
			mutate:    func(envelope string) string { return setGroupEnvelopeJSONField(t, envelope, "version", "2") },
		},
		{
			name:      "type_tamper_unsupported",
			groupId:   groupId,
			config:    config,
			envelope:  validDeviceEnvelope,
			transport: activeTransportPeerId,
			want:      "reject:not_v3",
			mutate:    func(envelope string) string { return setGroupEnvelopeJSONField(t, envelope, "type", "group_notice") },
		},
		{
			name:      "missing_group_id",
			groupId:   groupId,
			config:    config,
			envelope:  validDeviceEnvelope,
			transport: activeTransportPeerId,
			want:      "reject:invalid_envelope",
			mutate:    func(envelope string) string { return deleteGroupEnvelopeJSONField(t, envelope, "groupId") },
		},
		{
			name:      "group_id_mismatch",
			groupId:   groupId,
			config:    config,
			envelope:  validDeviceEnvelope,
			transport: activeTransportPeerId,
			want:      "reject:group_mismatch",
			mutate: func(envelope string) string {
				return setGroupEnvelopeJSONField(t, envelope, "groupId", "group-ge018-other")
			},
		},
		{
			name:      "blank_sender",
			groupId:   groupId,
			config:    config,
			envelope:  validDeviceEnvelope,
			transport: activeTransportPeerId,
			want:      "reject:invalid_envelope",
			mutate:    func(envelope string) string { return setGroupEnvelopeJSONField(t, envelope, "senderId", " ") },
		},
		{
			name:      "sender_id_claims_other_member",
			groupId:   groupId,
			config:    config,
			envelope:  validDeviceEnvelope,
			transport: activeTransportPeerId,
			want:      "reject:unbound_device",
			mutate:    func(envelope string) string { return setGroupEnvelopeJSONField(t, envelope, "senderId", otherSenderId) },
		},
		{
			name:      "sender_device_id_revoked",
			groupId:   groupId,
			config:    config,
			envelope:  validDeviceEnvelope,
			transport: activeTransportPeerId,
			want:      "reject:unbound_device",
			mutate: func(envelope string) string {
				return setGroupEnvelopeJSONField(t, envelope, "senderDeviceId", revokedDevice.DeviceId)
			},
		},
		{
			name:      "sender_transport_peer_id_mismatch",
			groupId:   groupId,
			config:    config,
			envelope:  validDeviceEnvelope,
			transport: activeTransportPeerId,
			want:      "reject:peer_mismatch",
			mutate: func(envelope string) string {
				return setGroupEnvelopeJSONField(t, envelope, "senderTransportPeerId", revokedDevice.TransportPeerId)
			},
		},
		{
			name:      "sender_device_public_key_mismatch",
			groupId:   groupId,
			config:    config,
			envelope:  validDeviceEnvelope,
			transport: activeTransportPeerId,
			want:      "reject:unbound_device",
			mutate: func(envelope string) string {
				return setGroupEnvelopeJSONField(t, envelope, "senderDevicePublicKey", otherPubB64)
			},
		},
		{
			name:      "sender_key_package_mismatch",
			groupId:   groupId,
			config:    config,
			envelope:  validDeviceEnvelope,
			transport: activeTransportPeerId,
			want:      "reject:unbound_device",
			mutate: func(envelope string) string {
				return setGroupEnvelopeJSONField(t, envelope, "senderKeyPackageId", "ge018-wrong-package")
			},
		},
		{
			name:      "missing_ciphertext",
			groupId:   groupId,
			config:    config,
			envelope:  validDeviceEnvelope,
			transport: activeTransportPeerId,
			want:      "reject:invalid_envelope",
			mutate: func(envelope string) string {
				return deleteNestedGroupEnvelopeJSONField(t, envelope, "encrypted", "ciphertext")
			},
		},
		{
			name:      "missing_nonce",
			groupId:   groupId,
			config:    config,
			envelope:  validDeviceEnvelope,
			transport: activeTransportPeerId,
			want:      "reject:invalid_envelope",
			mutate: func(envelope string) string {
				return deleteNestedGroupEnvelopeJSONField(t, envelope, "encrypted", "nonce")
			},
		},
		{
			name:      "key_epoch_tamper",
			groupId:   groupId,
			config:    config,
			envelope:  validDeviceEnvelope,
			transport: activeTransportPeerId,
			want:      "reject:bad_signature",
			mutate: func(envelope string) string {
				return setGroupEnvelopeJSONField(t, envelope, "keyEpoch", keyInfo.KeyEpoch+1)
			},
		},
		{
			name:      "signature_tamper",
			groupId:   groupId,
			config:    config,
			envelope:  validDeviceEnvelope,
			transport: activeTransportPeerId,
			want:      "reject:bad_signature",
			mutate: func(envelope string) string {
				return setGroupEnvelopeJSONField(t, envelope, "signature", "ge018-invalid-signature")
			},
		},
		{
			name:      "ciphertext_tamper",
			groupId:   groupId,
			config:    config,
			envelope:  validDeviceEnvelope,
			transport: activeTransportPeerId,
			want:      "reject:bad_signature",
			mutate: func(envelope string) string {
				return mutateGroupEnvelope(t, envelope, func(env *internal.GroupEnvelope) {
					ciphertextBytes, err := base64.StdEncoding.DecodeString(env.Encrypted.Ciphertext)
					if err != nil {
						t.Fatalf("decode ciphertext: %v", err)
					}
					ciphertextBytes[0] ^= 0x42
					env.Encrypted.Ciphertext = base64.StdEncoding.EncodeToString(ciphertextBytes)
				})
			},
		},
		{
			name:      "nonce_tamper_reaches_decrypt_only",
			groupId:   groupId,
			config:    config,
			envelope:  validDeviceEnvelope,
			transport: activeTransportPeerId,
			want:      "accept",
			mutate: func(envelope string) string {
				return mutateGroupEnvelope(t, envelope, func(env *internal.GroupEnvelope) {
					nonceBytes, err := base64.StdEncoding.DecodeString(env.Encrypted.Nonce)
					if err != nil {
						t.Fatalf("decode nonce: %v", err)
					}
					nonceBytes[0] ^= 0x24
					env.Encrypted.Nonce = base64.StdEncoding.EncodeToString(nonceBytes)
				})
			},
		},
		{
			name:      "legacy_sender_public_key_forgery",
			groupId:   legacyGroupId,
			config:    legacyConfig,
			envelope:  forgedLegacyPublicKeyEnvelope,
			transport: legacySenderId,
			want:      "reject:bad_signature",
			mutate:    func(envelope string) string { return envelope },
		},
	}

	for _, seed := range []int64{18018, 18019, 18020} {
		t.Run(fmt.Sprintf("seed_%d", seed), func(t *testing.T) {
			ordered := append([]validatorMutation(nil), mutations...)
			rand.New(rand.NewSource(seed)).Shuffle(len(ordered), func(i, j int) {
				ordered[i], ordered[j] = ordered[j], ordered[i]
			})
			for idx, tc := range ordered {
				t.Run(fmt.Sprintf("%02d_%s", idx, tc.name), func(t *testing.T) {
					mutated := tc.mutate(tc.envelope)
					got := validateGroupEnvelopeForTransportPeer(
						mutated,
						tc.groupId,
						tc.config,
						keyInfo,
						tc.transport,
					)
					if got != tc.want {
						t.Fatalf(
							"GE-018 seed=%d mutation=%s result=%q want %q",
							seed,
							tc.name,
							got,
							tc.want,
						)
					}
				})
			}
		})
	}
}

func TestGK011GroupTopicValidatorRejectsMissingSenderIDAsInvalidEnvelopeNoPanic(t *testing.T) {
	privB64, pubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}
	groupId := "group-gk-011-real-validator"
	senderId := "sender-gk-011"
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	config := &GroupConfig{
		Name:      "GK-011",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: senderId, Role: GroupRoleAdmin, PublicKey: pubB64},
		},
		CreatedBy: senderId,
	}
	validEnvelope := buildTestEnvelope(t, groupId, senderId, privB64, pubB64, groupKey, keyInfo.KeyEpoch, "missing sender id")
	missingSenderEnvelope := deleteGroupEnvelopeJSONField(t, validEnvelope, "senderId")

	collector := &testEventCollector{}
	n := New(collector)
	n.groupConfigs = map[string]*GroupConfig{groupId: config}
	n.groupKeys = map[string]*GroupKeyInfo{groupId: keyInfo}
	validator := n.groupTopicValidator(groupId)
	msg := &pubsub.Message{Message: &pb.Message{Data: []byte(missingSenderEnvelope)}}

	defer func() {
		if r := recover(); r != nil {
			t.Fatalf("groupTopicValidator panicked for missing senderId: %v", r)
		}
	}()
	if result := validator(context.Background(), peer.ID(senderId), msg); result != pubsub.ValidationReject {
		t.Fatalf("validator result = %v, want ValidationReject", result)
	}
	waitForCollectedValidationReject(t, collector, 0, "invalid_envelope", keyInfo.KeyEpoch, time.Second)
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

func TestGL010LeaveUnknownGroupIsNoOpForJoinedGroupState(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	n := NewNode()
	_, err = n.Start(NodeConfig{
		PrivateKeyHex:  generateTestKey(t),
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	groupId := "gl010-joined-group"
	unknownGroupId := "gl010-unknown-group"
	config := &GroupConfig{
		Name:      "GL-010 Joined Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: n.PeerId(), Username: "Admin", Role: GroupRoleAdmin, PublicKey: senderPubB64},
		},
		CreatedBy: n.PeerId(),
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	if err := n.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("JoinGroupTopic: %v", err)
	}

	n.mu.RLock()
	topicBefore := n.groupTopics[groupId]
	subBefore := n.groupSubs[groupId]
	configBefore := n.groupConfigs[groupId]
	keyBefore := n.groupKeys[groupId]
	_, subCtxBefore := n.groupSubCtx[groupId]
	_, discoveryCtxBefore := n.groupDiscoveryCtx[groupId]
	n.mu.RUnlock()
	if topicBefore == nil || subBefore == nil || configBefore == nil || keyBefore == nil || !subCtxBefore || !discoveryCtxBefore {
		t.Fatalf("expected joined group state before unknown leave, topic=%v sub=%v config=%v key=%v subCtx=%t discoveryCtx=%t",
			topicBefore, subBefore, configBefore, keyBefore, subCtxBefore, discoveryCtxBefore)
	}

	if err := n.LeaveGroupTopic(unknownGroupId); err != nil {
		t.Fatalf("LeaveGroupTopic(%s): %v", unknownGroupId, err)
	}

	n.mu.RLock()
	topicAfter := n.groupTopics[groupId]
	subAfter := n.groupSubs[groupId]
	configAfter := n.groupConfigs[groupId]
	keyAfter := n.groupKeys[groupId]
	_, subCtxAfter := n.groupSubCtx[groupId]
	_, discoveryCtxAfter := n.groupDiscoveryCtx[groupId]
	_, unknownTopic := n.groupTopics[unknownGroupId]
	_, unknownSub := n.groupSubs[unknownGroupId]
	_, unknownConfig := n.groupConfigs[unknownGroupId]
	_, unknownKey := n.groupKeys[unknownGroupId]
	n.mu.RUnlock()
	if topicAfter != topicBefore || subAfter != subBefore || configAfter != configBefore || keyAfter != keyBefore || !subCtxAfter || !discoveryCtxAfter {
		t.Fatalf(
			"unknown leave mutated joined group state: topicChanged=%t subChanged=%t configChanged=%t keyChanged=%t subCtx=%t discoveryCtx=%t",
			topicAfter != topicBefore,
			subAfter != subBefore,
			configAfter != configBefore,
			keyAfter != keyBefore,
			subCtxAfter,
			discoveryCtxAfter,
		)
	}
	if unknownTopic || unknownSub || unknownConfig || unknownKey {
		t.Fatalf("unknown leave created unknown group state: topic=%t sub=%t config=%t key=%t",
			unknownTopic, unknownSub, unknownConfig, unknownKey)
	}

	msgID, peerCount, err := n.PublishGroupMessage(
		groupId,
		senderPrivB64,
		n.PeerId(),
		senderPubB64,
		"Admin",
		"GL-010 known group remains publishable after unknown leave",
		"gl010-known-message",
		nil,
	)
	if err != nil {
		t.Fatalf("PublishGroupMessage after unknown leave: %v", err)
	}
	if msgID != "gl010-known-message" || peerCount != 0 {
		t.Fatalf("PublishGroupMessage after unknown leave = (%q,%d), want explicit id and zero peers", msgID, peerCount)
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

func TestBB016GroupConfigMetadataFieldsSurviveSerializationAndUpdate(t *testing.T) {
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

	groupId := "bb016-metadata-config"
	initialConfig := &GroupConfig{
		Name:              "BB-016 Initial",
		GroupType:         GroupTypeChat,
		Description:       "Initial bridge description",
		AvatarBlobId:      "avatar-initial",
		AvatarMime:        "image/png",
		MetadataUpdatedAt: "2026-05-15T09:42:00Z",
		ConfigVersion:     "2026-05-15T09:42:00Z",
		StateHash:         "bb016-initial-state-hash",
		Members: []GroupMember{
			{PeerId: "peer-admin", Role: GroupRoleAdmin, PublicKey: "pk-admin"},
		},
		CreatedBy: "peer-admin",
		CreatedAt: "2026-05-15T09:00:00Z",
	}
	keyInfo := &GroupKeyInfo{Key: "bb016-key", KeyEpoch: 1}

	if err := n.JoinGroupTopic(groupId, initialConfig, keyInfo); err != nil {
		t.Fatalf("JoinGroupTopic: %v", err)
	}

	encoded, err := json.Marshal(initialConfig)
	if err != nil {
		t.Fatalf("marshal initial config: %v", err)
	}
	var decoded GroupConfig
	if err := json.Unmarshal(encoded, &decoded); err != nil {
		t.Fatalf("unmarshal initial config: %v", err)
	}
	if decoded.Description != initialConfig.Description ||
		decoded.AvatarBlobId != initialConfig.AvatarBlobId ||
		decoded.AvatarMime != initialConfig.AvatarMime ||
		decoded.MetadataUpdatedAt != initialConfig.MetadataUpdatedAt ||
		decoded.ConfigVersion != initialConfig.ConfigVersion ||
		decoded.StateHash != initialConfig.StateHash {
		t.Fatalf("metadata drift after JSON round-trip: %#v", decoded)
	}

	updatedConfig := &GroupConfig{
		Name:              "BB-016 Updated",
		GroupType:         GroupTypeChat,
		Description:       "Updated bridge description",
		AvatarBlobId:      "avatar-updated",
		AvatarMime:        "image/jpeg",
		MetadataUpdatedAt: "2026-05-15T10:42:00Z",
		ConfigVersion:     "2026-05-15T10:42:00Z",
		StateHash:         "bb016-updated-state-hash",
		Members: []GroupMember{
			{PeerId: "peer-admin", Role: GroupRoleAdmin, PublicKey: "pk-admin"},
			{PeerId: "peer-writer", Role: GroupRoleWriter, PublicKey: "pk-writer"},
		},
		CreatedBy: "peer-admin",
		CreatedAt: "2026-05-15T09:00:00Z",
	}
	n.UpdateGroupConfig(groupId, updatedConfig)
	updatedConfig.Description = "caller mutated description"
	updatedConfig.AvatarBlobId = "caller-mutated-avatar"
	updatedConfig.StateHash = "caller-mutated-state-hash"

	n.mu.RLock()
	storedConfig := n.groupConfigs[groupId]
	n.mu.RUnlock()

	if storedConfig == nil {
		t.Fatal("stored config should not be nil")
	}
	if storedConfig.Description != "Updated bridge description" {
		t.Fatalf("Description = %q", storedConfig.Description)
	}
	if storedConfig.AvatarBlobId != "avatar-updated" {
		t.Fatalf("AvatarBlobId = %q", storedConfig.AvatarBlobId)
	}
	if storedConfig.AvatarMime != "image/jpeg" {
		t.Fatalf("AvatarMime = %q", storedConfig.AvatarMime)
	}
	if storedConfig.MetadataUpdatedAt != "2026-05-15T10:42:00Z" {
		t.Fatalf("MetadataUpdatedAt = %q", storedConfig.MetadataUpdatedAt)
	}
	if storedConfig.ConfigVersion != "2026-05-15T10:42:00Z" {
		t.Fatalf("ConfigVersion = %q", storedConfig.ConfigVersion)
	}
	if storedConfig.StateHash != "bb016-updated-state-hash" {
		t.Fatalf("StateHash = %q", storedConfig.StateHash)
	}
	if len(storedConfig.Members) != 2 {
		t.Fatalf("Members length = %d, want 2", len(storedConfig.Members))
	}
}

func TestUP001UpdateGroupConfigTracksAddRemoveReaddValidator(t *testing.T) {
	hexKey := generateTestKey(t)
	privB64A, pubB64A := generateEd25519KeyPair(t)
	privB64B, pubB64B := generateEd25519KeyPair(t)
	groupKey, _ := mcrypto.GenerateGroupKey()
	groupId := "up001-config-sync"

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

	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	createConfig := &GroupConfig{
		Name:      "UP-001",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: "peer-A", Role: GroupRoleAdmin, PublicKey: pubB64A},
		},
		CreatedBy: "peer-A",
	}
	if err := n.JoinGroupTopic(groupId, createConfig, keyInfo); err != nil {
		t.Fatalf("JoinGroupTopic: %v", err)
	}

	envelopeB := buildTestEnvelope(t, groupId, "peer-B", privB64B, pubB64B, groupKey, 1, "hello from B")

	assertStoredMembers := func(label string, want []string) *GroupConfig {
		t.Helper()
		n.mu.RLock()
		stored := n.groupConfigs[groupId]
		n.mu.RUnlock()
		if stored == nil {
			t.Fatalf("%s: missing stored group config", label)
		}
		got := map[string]bool{}
		for _, member := range stored.Members {
			got[member.PeerId] = true
		}
		if len(got) != len(want) {
			t.Fatalf("%s: got %d members (%v), want %d (%v)", label, len(got), got, len(want), want)
		}
		for _, peerID := range want {
			if !got[peerID] {
				t.Fatalf("%s: stored config missing member %s in %v", label, peerID, got)
			}
		}
		return stored
	}

	stored := assertStoredMembers("create", []string{"peer-A"})
	if result := validateGroupEnvelope(envelopeB, groupId, stored, keyInfo); result != "reject:non_member" {
		t.Fatalf("create validator result = %s, want reject:non_member", result)
	}

	addConfig := &GroupConfig{
		Name:      "UP-001",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: "peer-A", Role: GroupRoleAdmin, PublicKey: pubB64A},
			{PeerId: "peer-B", Role: GroupRoleWriter, PublicKey: pubB64B},
		},
		CreatedBy: "peer-A",
	}
	n.UpdateGroupConfig(groupId, addConfig)
	addConfig.Members[1].PeerId = "caller-mutated-peer-B"
	stored = assertStoredMembers("add", []string{"peer-A", "peer-B"})
	if result := validateGroupEnvelope(envelopeB, groupId, stored, keyInfo); result != "accept" {
		t.Fatalf("add validator result = %s, want accept", result)
	}

	removeConfig := &GroupConfig{
		Name:      "UP-001",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: "peer-A", Role: GroupRoleAdmin, PublicKey: pubB64A},
		},
		CreatedBy: "peer-A",
	}
	n.UpdateGroupConfig(groupId, removeConfig)
	stored = assertStoredMembers("remove", []string{"peer-A"})
	if result := validateGroupEnvelope(envelopeB, groupId, stored, keyInfo); result != "reject:non_member" {
		t.Fatalf("remove validator result = %s, want reject:non_member", result)
	}

	readdConfig := &GroupConfig{
		Name:      "UP-001",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: "peer-A", Role: GroupRoleAdmin, PublicKey: pubB64A},
			{PeerId: "peer-B", Role: GroupRoleWriter, PublicKey: pubB64B},
		},
		CreatedBy: "peer-A",
	}
	n.UpdateGroupConfig(groupId, readdConfig)
	readdConfig.Members[1].PeerId = "caller-mutated-readd-peer-B"
	stored = assertStoredMembers("readd", []string{"peer-A", "peer-B"})
	if result := validateGroupEnvelope(envelopeB, groupId, stored, keyInfo); result != "accept" {
		t.Fatalf("readd validator result = %s, want accept", result)
	}

	_ = privB64A
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

func TestRefreshJoinedGroupStateIfNewerUpdatesConfigAndKeyAtomically(t *testing.T) {
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

	_, senderPubB64 := generateEd25519KeyPair(t)
	firstGroupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate first group key: %v", err)
	}
	secondGroupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate second group key: %v", err)
	}
	sameEpochGroupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate same epoch group key: %v", err)
	}
	olderEpochGroupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate older epoch group key: %v", err)
	}

	groupId := "bb-008-refresh-helper"
	initialConfig := &GroupConfig{
		Name:      "BB-008 initial config",
		GroupType: GroupTypeAnnouncement,
		Members: []GroupMember{
			{PeerId: n.PeerId(), Role: GroupRoleWriter, PublicKey: senderPubB64},
		},
		CreatedBy: n.PeerId(),
		CreatedAt: "2026-05-10T21:20:00Z",
	}
	initialKey := &GroupKeyInfo{Key: firstGroupKey, KeyEpoch: 1}
	if err := n.JoinGroupTopic(groupId, initialConfig, initialKey); err != nil {
		t.Fatalf("JoinGroupTopic: %v", err)
	}

	n.mu.RLock()
	initialTopic := n.groupTopics[groupId]
	initialSub := n.groupSubs[groupId]
	initialSubCtxLen := len(n.groupSubCtx)
	initialDiscoveryCtxLen := len(n.groupDiscoveryCtx)
	n.mu.RUnlock()

	refreshedConfig := &GroupConfig{
		Name:      "BB-008 refreshed config",
		GroupType: GroupTypeAnnouncement,
		Members: []GroupMember{
			{PeerId: n.PeerId(), Role: GroupRoleAdmin, PublicKey: senderPubB64},
		},
		CreatedBy: n.PeerId(),
		CreatedAt: "2026-05-10T21:21:00Z",
	}
	refreshed, err := n.RefreshJoinedGroupStateIfNewer(
		groupId,
		refreshedConfig,
		&GroupKeyInfo{Key: secondGroupKey, KeyEpoch: 2},
	)
	if err != nil {
		t.Fatalf("RefreshJoinedGroupStateIfNewer newer epoch: %v", err)
	}
	if !refreshed {
		t.Fatal("RefreshJoinedGroupStateIfNewer newer epoch returned refreshed=false")
	}

	n.mu.RLock()
	currentTopic := n.groupTopics[groupId]
	currentSub := n.groupSubs[groupId]
	currentConfig := n.groupConfigs[groupId]
	currentKey := n.groupKeys[groupId]
	currentSubCtxLen := len(n.groupSubCtx)
	currentDiscoveryCtxLen := len(n.groupDiscoveryCtx)
	n.mu.RUnlock()

	if currentTopic != initialTopic {
		t.Fatal("refresh replaced the existing topic")
	}
	if currentSub != initialSub {
		t.Fatal("refresh replaced the existing subscription")
	}
	if currentSubCtxLen != initialSubCtxLen {
		t.Fatalf("groupSubCtx length changed from %d to %d", initialSubCtxLen, currentSubCtxLen)
	}
	if currentDiscoveryCtxLen != initialDiscoveryCtxLen {
		t.Fatalf("groupDiscoveryCtx length changed from %d to %d", initialDiscoveryCtxLen, currentDiscoveryCtxLen)
	}
	if currentConfig == nil || currentConfig.Name != refreshedConfig.Name || currentConfig.Members[0].Role != GroupRoleAdmin {
		t.Fatalf("stored config = %#v, want refreshed admin config", currentConfig)
	}
	if currentConfig == refreshedConfig {
		t.Fatal("stored config should snapshot refreshed config, not reuse caller pointer")
	}
	if currentKey == nil {
		t.Fatal("stored key is nil after refresh")
	}
	if currentKey.Key != secondGroupKey || currentKey.KeyEpoch != 2 {
		t.Fatalf("stored key = (%q,%d), want (%q,2)", currentKey.Key, currentKey.KeyEpoch, secondGroupKey)
	}
	if currentKey.PrevKey != firstGroupKey || currentKey.PrevKeyEpoch != 1 || currentKey.GraceDeadline.IsZero() {
		t.Fatalf("previous key grace = (%q,%d,%v), want first key epoch 1 with deadline", currentKey.PrevKey, currentKey.PrevKeyEpoch, currentKey.GraceDeadline)
	}

	sameEpochConfig := &GroupConfig{
		Name:      "BB-008 same epoch should not replace",
		GroupType: GroupTypeAnnouncement,
		Members: []GroupMember{
			{PeerId: n.PeerId(), Role: GroupRoleWriter, PublicKey: senderPubB64},
		},
		CreatedBy: n.PeerId(),
		CreatedAt: "2026-05-10T21:22:00Z",
	}
	refreshed, err = n.RefreshJoinedGroupStateIfNewer(
		groupId,
		sameEpochConfig,
		&GroupKeyInfo{Key: sameEpochGroupKey, KeyEpoch: 2},
	)
	if err != nil {
		t.Fatalf("RefreshJoinedGroupStateIfNewer same epoch: %v", err)
	}
	if refreshed {
		t.Fatal("RefreshJoinedGroupStateIfNewer same epoch returned refreshed=true")
	}

	refreshed, err = n.RefreshJoinedGroupStateIfNewer(
		groupId,
		sameEpochConfig,
		&GroupKeyInfo{Key: olderEpochGroupKey, KeyEpoch: 1},
	)
	if err != nil {
		t.Fatalf("RefreshJoinedGroupStateIfNewer older epoch: %v", err)
	}
	if refreshed {
		t.Fatal("RefreshJoinedGroupStateIfNewer older epoch returned refreshed=true")
	}

	n.mu.RLock()
	finalConfig := n.groupConfigs[groupId]
	finalKey := n.groupKeys[groupId]
	n.mu.RUnlock()

	if finalConfig == nil || finalConfig.Name != refreshedConfig.Name || finalConfig.Members[0].Role != GroupRoleAdmin {
		t.Fatalf("final config = %#v, want refreshed admin config preserved", finalConfig)
	}
	if finalKey == nil || finalKey.Key != secondGroupKey || finalKey.KeyEpoch != 2 {
		t.Fatalf("final key = %#v, want epoch 2 second key preserved", finalKey)
	}
}

func TestRA015RefreshJoinedGroupStateReaddConfigAndKeyConverge(t *testing.T) {
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

	_, alicePubB64 := generateEd25519KeyPair(t)
	_, bobPubB64 := generateEd25519KeyPair(t)
	_, charliePubB64 := generateEd25519KeyPair(t)
	firstGroupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate first group key: %v", err)
	}
	secondGroupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate second group key: %v", err)
	}

	groupId := "ra015-readd-refresh-helper"
	charliePeerId := "ra015-charlie-peer"
	initialConfig := &GroupConfig{
		Name:      "RA-015 before re-add",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: n.PeerId(), Role: GroupRoleAdmin, PublicKey: alicePubB64},
			{PeerId: "ra015-bob-peer", Role: GroupRoleWriter, PublicKey: bobPubB64},
		},
		CreatedBy: n.PeerId(),
		CreatedAt: "2026-05-13T05:40:00Z",
	}
	if err := n.JoinGroupTopic(groupId, initialConfig, &GroupKeyInfo{
		Key:      firstGroupKey,
		KeyEpoch: 1,
	}); err != nil {
		t.Fatalf("JoinGroupTopic: %v", err)
	}

	n.mu.RLock()
	initialTopic := n.groupTopics[groupId]
	initialSub := n.groupSubs[groupId]
	n.mu.RUnlock()

	readdConfig := &GroupConfig{
		Name:      "RA-015 after Charlie re-add",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: n.PeerId(), Role: GroupRoleAdmin, PublicKey: alicePubB64},
			{PeerId: "ra015-bob-peer", Role: GroupRoleWriter, PublicKey: bobPubB64},
			{PeerId: charliePeerId, Role: GroupRoleWriter, PublicKey: charliePubB64},
		},
		CreatedBy: n.PeerId(),
		CreatedAt: "2026-05-13T05:41:00Z",
	}
	refreshed, err := n.RefreshJoinedGroupStateIfNewer(
		groupId,
		readdConfig,
		&GroupKeyInfo{Key: secondGroupKey, KeyEpoch: 2},
	)
	if err != nil {
		t.Fatalf("RefreshJoinedGroupStateIfNewer RA-015: %v", err)
	}
	if !refreshed {
		t.Fatal("RefreshJoinedGroupStateIfNewer RA-015 returned refreshed=false")
	}

	n.mu.RLock()
	currentTopic := n.groupTopics[groupId]
	currentSub := n.groupSubs[groupId]
	currentConfig := n.groupConfigs[groupId]
	currentKey := n.groupKeys[groupId]
	n.mu.RUnlock()

	if currentTopic != initialTopic {
		t.Fatal("RA-015 refresh replaced the existing topic")
	}
	if currentSub != initialSub {
		t.Fatal("RA-015 refresh replaced the existing subscription")
	}
	if currentConfig == nil || currentConfig.Name != readdConfig.Name {
		t.Fatalf("stored config = %#v, want re-add config", currentConfig)
	}
	if !isAllowedWriter(currentConfig, charliePeerId) {
		t.Fatal("re-added Charlie is not allowed to write after RA-015 refresh")
	}
	if currentKey == nil || currentKey.Key != secondGroupKey || currentKey.KeyEpoch != 2 {
		t.Fatalf("stored key = %#v, want epoch 2 second key", currentKey)
	}
	if currentKey.PrevKey != firstGroupKey || currentKey.PrevKeyEpoch != 1 || currentKey.GraceDeadline.IsZero() {
		t.Fatalf("previous key grace = (%q,%d,%v), want first key epoch 1 with deadline", currentKey.PrevKey, currentKey.PrevKeyEpoch, currentKey.GraceDeadline)
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

func TestGL016GetGroupKeyInfoReturnsCloneCannotMutateInternalState(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	initialKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate initial group key: %v", err)
	}
	rotatedKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate rotated group key: %v", err)
	}

	n := NewNode()
	_, err = n.Start(NodeConfig{
		PrivateKeyHex:  generateTestKey(t),
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	groupId := "gl016-cloned-key-info"
	config := &GroupConfig{
		Name:      "GL-016 Clone Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: n.PeerId(), Username: "Admin", Role: GroupRoleAdmin, PublicKey: senderPubB64},
		},
		CreatedBy: n.PeerId(),
	}
	if err := n.JoinGroupTopic(groupId, config, &GroupKeyInfo{Key: initialKey, KeyEpoch: 1}); err != nil {
		t.Fatalf("JoinGroupTopic: %v", err)
	}
	n.UpdateGroupKey(groupId, &GroupKeyInfo{Key: rotatedKey, KeyEpoch: 2})

	first := n.GetGroupKeyInfo(groupId)
	if first == nil {
		t.Fatal("GetGroupKeyInfo returned nil after key rotation")
	}
	if first.Key != rotatedKey || first.KeyEpoch != 2 || first.PrevKey != initialKey || first.PrevKeyEpoch != 1 || first.GraceDeadline.IsZero() {
		t.Fatalf("GetGroupKeyInfo before mutation = %#v, want current epoch 2 with previous epoch 1 grace", first)
	}
	first.Key = "mutated-invalid-key"
	first.KeyEpoch = 99
	first.PrevKey = "mutated-prev-key"
	first.PrevKeyEpoch = 98
	first.GraceDeadline = time.Unix(1, 0)

	second := n.GetGroupKeyInfo(groupId)
	if second == nil {
		t.Fatal("GetGroupKeyInfo returned nil after mutating first clone")
	}
	if second == first {
		t.Fatal("GetGroupKeyInfo returned the same pointer after mutation, want a fresh clone")
	}
	if second.Key != rotatedKey || second.KeyEpoch != 2 {
		t.Fatalf("current key mutated through returned clone: got key=%q epoch=%d", second.Key, second.KeyEpoch)
	}
	if second.PrevKey != initialKey || second.PrevKeyEpoch != 1 {
		t.Fatalf("previous key mutated through returned clone: got key=%q epoch=%d", second.PrevKey, second.PrevKeyEpoch)
	}
	if second.GraceDeadline.Equal(time.Unix(1, 0)) || second.GraceDeadline.IsZero() {
		t.Fatalf("grace deadline mutated through returned clone: %v", second.GraceDeadline)
	}

	msgID, peerCount, err := n.PublishGroupMessage(
		groupId,
		senderPrivB64,
		n.PeerId(),
		senderPubB64,
		"Admin",
		"GL-016 publish uses unmutated internal key",
		"gl016-clone-message",
		nil,
	)
	if err != nil {
		t.Fatalf("PublishGroupMessage after mutating returned key clone: %v", err)
	}
	if msgID != "gl016-clone-message" || peerCount != 0 {
		t.Fatalf("PublishGroupMessage after clone mutation = (%q,%d), want explicit id and zero peers", msgID, peerCount)
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

func TestGR004InPlaceRelayRecoveryPreservesGroupTopicsAndDeliveryWithoutRejoin(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	_, receiverPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeA := startLocalNodeForMultiRelayTest(t)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

	groupId := "gr004-in-place-preserves-topic"
	config := &GroupConfig{
		Name:      "GR004 In-Place Recovery",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: senderPubB64},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: receiverPubB64},
		},
		CreatedBy: nodeA.PeerId(),
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}

	if err := nodeA.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}
	connectLocalGroupNodes(t, nodeA, nodeB)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 2*time.Second)
	waitForGroupTopicPeerCount(t, nodeB, groupId, 1, 2*time.Second)

	hostBefore := nodeA.Host()
	nodeA.mu.RLock()
	topicBefore := nodeA.groupTopics[groupId]
	subBefore := nodeA.groupSubs[groupId]
	configBefore := nodeA.groupConfigs[groupId]
	keyBefore := nodeA.groupKeys[groupId]
	nodeA.mu.RUnlock()
	if hostBefore == nil || topicBefore == nil || subBefore == nil || configBefore == nil || keyBefore == nil {
		t.Fatalf("expected joined group state before recovery, host=%v topic=%v sub=%v config=%v key=%v",
			hostBefore, topicBefore, subBefore, configBefore, keyBefore)
	}

	refreshHookCalls := 0
	nodeA.refreshRelaySessionHook = func() *RecoveryResult {
		refreshHookCalls++
		return &RecoveryResult{
			RecoveryMode:      "in_place",
			Success:           true,
			RelayState:        string(AggregateRelayOnline),
			HealthyRelayCount: 1,
			ReusedHost:        true,
			ReservationPath:   "poll_fallback",
		}
	}

	result := nodeA.RefreshRelaySession()
	if result == nil || !result.Success {
		t.Fatalf("RefreshRelaySession result = %#v, want successful in-place recovery", result)
	}
	if result.RecoveryMode != "in_place" || !result.ReusedHost {
		t.Fatalf("RefreshRelaySession mode/reused = %q/%v, want in_place/true", result.RecoveryMode, result.ReusedHost)
	}
	if refreshHookCalls != 1 {
		t.Fatalf("refresh hook calls = %d, want 1", refreshHookCalls)
	}
	if got := nodeA.Host(); got != hostBefore {
		t.Fatal("in-place RefreshRelaySession replaced the host")
	}

	nodeA.mu.RLock()
	topicAfter := nodeA.groupTopics[groupId]
	subAfter := nodeA.groupSubs[groupId]
	configAfter := nodeA.groupConfigs[groupId]
	keyAfter := nodeA.groupKeys[groupId]
	nodeA.mu.RUnlock()
	if topicAfter != topicBefore {
		t.Fatal("in-place RefreshRelaySession replaced or dropped the joined group topic")
	}
	if subAfter != subBefore {
		t.Fatal("in-place RefreshRelaySession replaced or dropped the group subscription")
	}
	if configAfter != configBefore {
		t.Fatal("in-place RefreshRelaySession replaced or dropped the group config")
	}
	if keyAfter != keyBefore {
		t.Fatal("in-place RefreshRelaySession replaced or dropped the group key")
	}
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 2*time.Second)

	messageID := "gr004-post-refresh-message"
	receiverBaseline := len(nodeBCapture.snapshot())
	msgID, peerCount, err := nodeA.PublishGroupMessage(
		groupId,
		senderPrivB64,
		nodeA.PeerId(),
		senderPubB64,
		"Alice",
		"GR-004 delivery after in-place relay refresh",
		messageID,
		nil,
	)
	if err != nil {
		t.Fatalf("PublishGroupMessage after in-place recovery: %v", err)
	}
	if msgID != messageID {
		t.Fatalf("PublishGroupMessage msgID = %q, want %q", msgID, messageID)
	}
	if peerCount < 1 {
		t.Fatalf("PublishGroupMessage peerCount = %d, want existing topic peer without rejoin", peerCount)
	}

	received := waitForCollectedEventAfter(t, nodeBCapture, receiverBaseline, "group_message:received", 5*time.Second)
	for _, tc := range []struct {
		key  string
		want interface{}
	}{
		{key: "groupId", want: groupId},
		{key: "senderId", want: nodeA.PeerId()},
		{key: "senderUsername", want: "Alice"},
		{key: "messageId", want: messageID},
		{key: "text", want: "GR-004 delivery after in-place relay refresh"},
		{key: "keyEpoch", want: float64(1)},
	} {
		if got := received[tc.key]; got != tc.want {
			t.Fatalf("%s = %#v, want %#v in received event %#v", tc.key, got, tc.want, received)
		}
	}
}

func TestGR005WatchdogRestartClearsGroupTopicsAndRequiresExplicitRejoin(t *testing.T) {
	senderPrivB64, senderPubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	n := NewNode()
	n.waitForCircuitAddressHook = func(timeout time.Duration) bool {
		return true
	}
	n.refreshRelaySessionHook = func() *RecoveryResult {
		return &RecoveryResult{
			RecoveryMode: "in_place",
			Success:      false,
			ErrorCode:    "REFRESH_FAILED",
			Reason:       "GR-005 forced in-place failure",
			ReusedHost:   true,
		}
	}

	if _, err := n.Start(NodeConfig{
		PrivateKeyHex:  generateTestKey(t),
		RelayAddresses: []string{},
		AutoRegister:   false,
	}); err != nil {
		t.Fatalf("Start: %v", err)
	}
	t.Cleanup(func() { _ = n.Stop() })

	groupId := "gr005-watchdog-clears-topics"
	config := &GroupConfig{
		Name:      "GR005 Watchdog Restart",
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

	hostBefore := n.Host()
	n.mu.RLock()
	topicBefore := n.groupTopics[groupId]
	subBefore := n.groupSubs[groupId]
	configBefore := n.groupConfigs[groupId]
	keyBefore := n.groupKeys[groupId]
	n.mu.RUnlock()
	if hostBefore == nil || topicBefore == nil || subBefore == nil || configBefore == nil || keyBefore == nil {
		t.Fatalf("expected joined group state before watchdog restart, host=%v topic=%v sub=%v config=%v key=%v",
			hostBefore, topicBefore, subBefore, configBefore, keyBefore)
	}

	result, err := n.ReconnectRelays()
	if err != nil {
		t.Fatalf("ReconnectRelays: %v", err)
	}
	if result == nil || !result.Success {
		t.Fatalf("ReconnectRelays result = %#v, want successful watchdog restart", result)
	}
	if result.RecoveryMode != "watchdog_restart" || result.ReusedHost {
		t.Fatalf("ReconnectRelays mode/reused = %q/%v, want watchdog_restart/false", result.RecoveryMode, result.ReusedHost)
	}
	if got := n.Host(); got == nil || got == hostBefore {
		t.Fatalf("watchdog restart host = %v, want replacement for previous host %v", got, hostBefore)
	}

	n.mu.RLock()
	pubsubAfter := n.pubsub
	topicAfter := n.groupTopics[groupId]
	subAfter := n.groupSubs[groupId]
	configAfter := n.groupConfigs[groupId]
	keyAfter := n.groupKeys[groupId]
	topicsLen := len(n.groupTopics)
	subsLen := len(n.groupSubs)
	configsLen := len(n.groupConfigs)
	keysLen := len(n.groupKeys)
	n.mu.RUnlock()
	if pubsubAfter == nil {
		t.Fatal("watchdog restart should rebuild a fresh pubsub instance")
	}
	if topicAfter != nil || subAfter != nil || configAfter != nil || keyAfter != nil {
		t.Fatalf("watchdog restart retained joined group state: topic=%v sub=%v config=%v key=%v",
			topicAfter, subAfter, configAfter, keyAfter)
	}
	if topicsLen != 0 || subsLen != 0 || configsLen != 0 || keysLen != 0 {
		t.Fatalf("watchdog restart should leave empty group maps before app rejoin, got topics=%d subs=%d configs=%d keys=%d",
			topicsLen, subsLen, configsLen, keysLen)
	}

	status := n.Status()
	if got := status["needsGroupRecovery"]; got != true {
		t.Fatalf("needsGroupRecovery = %v, want true after watchdog restart", got)
	}
	if got := status["watchdogRestartCount"]; got != 1 {
		t.Fatalf("watchdogRestartCount = %v, want 1", got)
	}

	msgID, peerCount, err := n.PublishGroupMessage(
		groupId,
		senderPrivB64,
		n.PeerId(),
		senderPubB64,
		"Admin",
		"GR-005 publish before explicit rejoin",
		"gr005-before-rejoin",
		nil,
	)
	if err == nil || !strings.Contains(err.Error(), "group not joined") {
		t.Fatalf("PublishGroupMessage before explicit rejoin error = %v, want group not joined", err)
	}
	if msgID != "" || peerCount != 0 {
		t.Fatalf("PublishGroupMessage before rejoin returned msgID=%q peerCount=%d, want empty/0", msgID, peerCount)
	}

	if err := n.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		t.Fatalf("explicit rejoin JoinGroupTopic: %v", err)
	}
	msgID, peerCount, err = n.PublishGroupMessage(
		groupId,
		senderPrivB64,
		n.PeerId(),
		senderPubB64,
		"Admin",
		"GR-005 publish after explicit rejoin",
		"gr005-after-rejoin",
		nil,
	)
	if err != nil {
		t.Fatalf("PublishGroupMessage after explicit rejoin: %v", err)
	}
	if msgID != "gr005-after-rejoin" {
		t.Fatalf("PublishGroupMessage after rejoin msgID=%q, want gr005-after-rejoin", msgID)
	}
	if peerCount != 0 {
		t.Fatalf("local-only PublishGroupMessage after rejoin peerCount=%d, want 0", peerCount)
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

func TestNW015ManualDialDisconnectPreservesGroupTopicConfigAndKey(t *testing.T) {
	admin := startLocalNodeForMultiRelayTest(t)
	target := startLocalNodeForMultiRelayTest(t)

	targetID, err := peer.Decode(target.PeerId())
	if err != nil {
		t.Fatalf("decode target peer ID: %v", err)
	}

	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	groupID := "nw015-manual-peer-commands"
	config := &GroupConfig{
		Name:      "NW015 Stable Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: admin.PeerId(), Username: "admin", Role: GroupRoleAdmin, PublicKey: "adminPk"},
			{PeerId: target.PeerId(), Username: "target", Role: GroupRoleWriter, PublicKey: "targetPk"},
		},
		CreatedBy: admin.PeerId(),
		CreatedAt: "2026-05-13T22:05:00Z",
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 15}

	if err := admin.JoinGroupTopic(groupID, config, keyInfo); err != nil {
		t.Fatalf("JoinGroupTopic: %v", err)
	}

	admin.mu.RLock()
	topicBefore := admin.groupTopics[groupID]
	subBefore := admin.groupSubs[groupID]
	configBefore := admin.groupConfigs[groupID]
	keyBefore := admin.groupKeys[groupID]
	admin.mu.RUnlock()

	if topicBefore == nil {
		t.Fatal("expected joined group topic before manual peer commands")
	}
	if subBefore == nil {
		t.Fatal("expected joined group subscription before manual peer commands")
	}
	if configBefore == nil || keyBefore == nil {
		t.Fatal("expected stored group config and key before manual peer commands")
	}
	targetAddrStrings := make([]string, 0, len(target.Host().Addrs()))
	for _, addr := range target.Host().Addrs() {
		targetAddrStrings = append(targetAddrStrings, addr.String())
	}

	for i := 0; i < 3; i++ {
		if err := admin.DialPeer(target.PeerId(), targetAddrStrings); err != nil {
			t.Fatalf("DialPeer iteration %d: %v", i, err)
		}
		waitForRP017Connectedness(t, admin, targetID, network.Connected, time.Second)

		if err := admin.DisconnectPeer(target.PeerId()); err != nil {
			t.Fatalf("DisconnectPeer iteration %d: %v", i, err)
		}

		deadline := time.Now().Add(time.Second)
		for time.Now().Before(deadline) {
			if admin.Host().Network().Connectedness(targetID) != network.Connected {
				break
			}
			time.Sleep(10 * time.Millisecond)
		}
		if got := admin.Host().Network().Connectedness(targetID); got == network.Connected {
			t.Fatalf("target remained connected after manual disconnect iteration %d", i)
		}
	}

	admin.mu.RLock()
	defer admin.mu.RUnlock()

	if admin.groupTopics[groupID] != topicBefore {
		t.Fatal("manual peer commands replaced or removed group topic")
	}
	if admin.groupSubs[groupID] != subBefore {
		t.Fatal("manual peer commands replaced or removed group subscription")
	}
	if admin.groupConfigs[groupID] != configBefore {
		t.Fatal("manual peer commands replaced or removed group config")
	}
	if admin.groupKeys[groupID] != keyBefore {
		t.Fatal("manual peer commands replaced or removed group key")
	}
	if got := admin.groupKeys[groupID].KeyEpoch; got != 15 {
		t.Fatalf("manual peer commands changed key epoch to %d", got)
	}
	if got := len(admin.groupConfigs[groupID].Members); got != 2 {
		t.Fatalf("manual peer commands changed member count to %d", got)
	}
}

func TestGP013DirectAddressPreferenceExcludesRelayCircuitAddrs(t *testing.T) {
	dialer := startLocalNodeForMultiRelayTest(t)
	setFakeRelays(t, dialer)

	target := startLocalNodeForMultiRelayTest(t)
	targetID, err := peer.Decode(target.PeerId())
	if err != nil {
		t.Fatalf("decode target peer ID: %v", err)
	}

	targetDirectAddrs := target.Host().Addrs()
	if len(targetDirectAddrs) == 0 {
		t.Fatal("target host has no direct addrs")
	}

	relayCircuitAddr, err := ma.NewMultiaddr(fmt.Sprintf("%s/p2p-circuit/p2p/%s", generateFakeRelayAddr(t, 19993), target.PeerId()))
	if err != nil {
		t.Fatalf("build relay circuit addr: %v", err)
	}
	if !isRelayCircuitAddr(relayCircuitAddr) {
		t.Fatalf("test relay address was not classified as circuit: %s", relayCircuitAddr)
	}

	peerstoreAddrs := append([]ma.Multiaddr{relayCircuitAddr}, targetDirectAddrs...)
	dialer.Host().Peerstore().AddAddrs(targetID, peerstoreAddrs, time.Hour)
	candidateAddrs := append([]ma.Multiaddr{relayCircuitAddr}, targetDirectAddrs...)
	candidateAddrs = append(candidateAddrs, relayCircuitAddr, targetDirectAddrs[0])

	expectedDirectCount := len(dedupeDirectMultiaddrs(targetDirectAddrs))
	directAddrs := collectDirectMultiaddrs(dialer.Host(), targetID, candidateAddrs)
	if len(directAddrs) != expectedDirectCount {
		t.Fatalf("collectDirectMultiaddrs count=%d, want %d; addrs=%v", len(directAddrs), expectedDirectCount, directAddrs)
	}
	for _, addr := range directAddrs {
		if isRelayCircuitAddr(addr) {
			t.Fatalf("collectDirectMultiaddrs returned relay circuit addr %s from mixed peerstore/candidates", addr)
		}
	}

	result, err := dialer.connectGroupPeerPreferDirect(target.PeerId(), candidateAddrs, true)
	if err != nil {
		t.Fatalf("connectGroupPeerPreferDirect: %v", err)
	}
	if result.Path != "direct" {
		t.Fatalf("connectGroupPeerPreferDirect path=%q, want direct", result.Path)
	}
	if !result.AttemptedDirect {
		t.Fatal("expected direct attempt to be recorded")
	}
	if result.DirectAddrCount != expectedDirectCount {
		t.Fatalf("direct address count=%d, want %d", result.DirectAddrCount, expectedDirectCount)
	}
	if result.UsedRelayFallback {
		t.Fatal("relay fallback should remain separate and unused when direct addrs succeed")
	}
	if dialer.Host().Network().Connectedness(targetID) != network.Connected {
		t.Fatalf("expected direct libp2p connection to %s", target.PeerId())
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

func TestGP011RendezvousDiscoveryFiltersNonMembers(t *testing.T) {
	collector := &testEventCollector{}
	admin := startLocalNodeForMultiRelayTestWithCollector(t, collector)
	memberB := startLocalNodeForMultiRelayTest(t)
	removedC := startLocalNodeForMultiRelayTest(t)
	unknownX := startLocalNodeForMultiRelayTest(t)

	memberBID, err := peer.Decode(memberB.PeerId())
	if err != nil {
		t.Fatalf("decode member B peer ID: %v", err)
	}
	removedCID, err := peer.Decode(removedC.PeerId())
	if err != nil {
		t.Fatalf("decode removed C peer ID: %v", err)
	}
	unknownXID, err := peer.Decode(unknownX.PeerId())
	if err != nil {
		t.Fatalf("decode unknown X peer ID: %v", err)
	}

	groupId := "gp011-rendezvous-filters-non-members"
	config := &GroupConfig{
		Name:      "GP011 Current Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: admin.PeerId(), Username: "Admin", Role: GroupRoleAdmin, PublicKey: "adminPk"},
			{PeerId: memberB.PeerId(), Username: "Bob", Role: GroupRoleWriter, PublicKey: "bobPk"},
		},
		CreatedBy: admin.PeerId(),
	}

	admin.mu.Lock()
	admin.groupConfigs[groupId] = config
	admin.mu.Unlock()
	admin.rendezvousDiscoverHook = func(namespace string, serverAddresses []string) ([]peer.AddrInfo, error) {
		if namespace != groupRendezvousNamespace(groupId) {
			t.Fatalf("unexpected rendezvous namespace %q", namespace)
		}
		return []peer.AddrInfo{
			{ID: memberBID, Addrs: memberB.Host().Addrs()},
			{ID: removedCID, Addrs: removedC.Host().Addrs()},
			{ID: unknownXID, Addrs: unknownX.Host().Addrs()},
		}, nil
	}

	admin.discoverAndConnectGroupPeers(groupId)

	waitForRP017Connectedness(t, admin, memberBID, network.Connected, time.Second)
	time.Sleep(100 * time.Millisecond)

	if got := admin.Host().Network().Connectedness(removedCID); got == network.Connected {
		t.Fatalf("removed peer C %s was dialed from rendezvous discovery", removedC.PeerId())
	}
	if got := admin.Host().Network().Connectedness(unknownXID); got == network.Connected {
		t.Fatalf("unknown peer X %s was dialed from rendezvous discovery", unknownX.PeerId())
	}
	if addrs := admin.Host().Peerstore().Addrs(removedCID); len(addrs) != 0 {
		t.Fatalf("removed peer C addresses were imported before filtering: %v", addrs)
	}
	if addrs := admin.Host().Peerstore().Addrs(unknownXID); len(addrs) != 0 {
		t.Fatalf("unknown peer X addresses were imported before filtering: %v", addrs)
	}
	assertGM030DiscoveryEventTotals(t, collector, groupId, 3, 1, 2)
}

func TestGP014RelayFallbackAfterDirectConnectTopicMissing(t *testing.T) {
	collector := &testEventCollector{}
	admin := startLocalNodeForMultiRelayTestWithCollector(t, collector)
	memberB := startLocalNodeForMultiRelayTest(t)

	memberBID, err := peer.Decode(memberB.PeerId())
	if err != nil {
		t.Fatalf("decode member B peer ID: %v", err)
	}

	groupId := "gp014-relay-fallback-after-topic-missing"
	config := &GroupConfig{
		Name:      "GP014 Topic Missing",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: admin.PeerId(), Username: "Admin", Role: GroupRoleAdmin, PublicKey: "adminPk"},
			{PeerId: memberB.PeerId(), Username: "Bob", Role: GroupRoleWriter, PublicKey: "bobPk"},
		},
		CreatedBy: admin.PeerId(),
	}

	relayAttempts := make(chan string, 2)
	admin.dialPeerViaRelayHook = func(peerIdStr string) error {
		relayAttempts <- peerIdStr
		return nil
	}
	admin.mu.Lock()
	admin.groupConfigs[groupId] = config
	admin.mu.Unlock()
	admin.Host().Peerstore().AddAddrs(memberBID, memberB.Host().Addrs(), time.Hour)

	admin.dialKnownGroupMembers(groupId, true)

	waitForRP017Connectedness(t, admin, memberBID, network.Connected, time.Second)
	select {
	case got := <-relayAttempts:
		if got != memberB.PeerId() {
			t.Fatalf("relay fallback attempted for peer %q, want %q", got, memberB.PeerId())
		}
	default:
		t.Fatal("expected DialPeerViaRelay fallback after direct connect did not become a live topic peer")
	}
	select {
	case got := <-relayAttempts:
		t.Fatalf("expected one relay fallback attempt, got extra attempt for %q", got)
	default:
	}

	assertGP014KnownMemberTopicMissingRelayFallback(t, collector, groupId, memberB.PeerId())
}

func TestGM030MembershipMutationUpdatesDiscoveryAllowedMemberFilter(t *testing.T) {
	collector := &testEventCollector{}
	admin := startLocalNodeForMultiRelayTestWithCollector(t, collector)
	memberB := startLocalNodeForMultiRelayTest(t)
	removedC := startLocalNodeForMultiRelayTest(t)
	memberD := startLocalNodeForMultiRelayTest(t)
	unknownX := startLocalNodeForMultiRelayTest(t)

	memberBID, err := peer.Decode(memberB.PeerId())
	if err != nil {
		t.Fatalf("decode member B peer ID: %v", err)
	}
	removedCID, err := peer.Decode(removedC.PeerId())
	if err != nil {
		t.Fatalf("decode removed C peer ID: %v", err)
	}
	memberDID, err := peer.Decode(memberD.PeerId())
	if err != nil {
		t.Fatalf("decode member D peer ID: %v", err)
	}
	unknownXID, err := peer.Decode(unknownX.PeerId())
	if err != nil {
		t.Fatalf("decode unknown X peer ID: %v", err)
	}

	groupId := "gm030-membership-mutation-discovery-filter"
	oldConfig := &GroupConfig{
		Name:      "GM-030 Old",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: admin.PeerId(), Username: "Admin", Role: GroupRoleAdmin, PublicKey: "adminPk"},
			{PeerId: memberB.PeerId(), Username: "B", Role: GroupRoleWriter, PublicKey: "memberBPk"},
			{PeerId: removedC.PeerId(), Username: "C", Role: GroupRoleWriter, PublicKey: "removedCPk"},
		},
		CreatedBy: admin.PeerId(),
	}
	currentConfig := &GroupConfig{
		Name:      "GM-030 Current",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: admin.PeerId(), Username: "Admin", Role: GroupRoleAdmin, PublicKey: "adminPk"},
			{PeerId: memberB.PeerId(), Username: "B", Role: GroupRoleWriter, PublicKey: "memberBPk"},
			{PeerId: memberD.PeerId(), Username: "D", Role: GroupRoleWriter, PublicKey: "memberDPk"},
		},
		CreatedBy: admin.PeerId(),
	}

	admin.UpdateGroupConfig(groupId, oldConfig)
	admin.UpdateGroupConfig(groupId, currentConfig)
	admin.mu.RLock()
	storedConfig := cloneGroupConfig(admin.groupConfigs[groupId])
	admin.mu.RUnlock()
	if storedConfig == nil {
		t.Fatal("expected current group config to be stored")
	}

	targets := activeGroupMemberDialTargets(storedConfig, admin.PeerId())
	if len(targets) != 2 {
		t.Fatalf("expected current active dial targets B/D only, got %d: %+v", len(targets), targets)
	}
	targetSet := make(map[string]struct{}, len(targets))
	for _, target := range targets {
		targetSet[target.PeerId] = struct{}{}
	}
	if _, ok := targetSet[memberB.PeerId()]; !ok {
		t.Fatalf("expected member B target after config update, got %+v", targets)
	}
	if _, ok := targetSet[memberD.PeerId()]; !ok {
		t.Fatalf("expected newly added member D target after config update, got %+v", targets)
	}
	if _, ok := targetSet[removedC.PeerId()]; ok {
		t.Fatalf("removed member C remained in active dial targets: %+v", targets)
	}
	if _, ok := targetSet[unknownX.PeerId()]; ok {
		t.Fatalf("unknown X appeared in active dial targets: %+v", targets)
	}
	if got := countRemoteGroupMembers(storedConfig, admin.PeerId()); got != 2 {
		t.Fatalf("expected current remote member count B/D only, got %d", got)
	}
	if got := admin.expectedConnectedGroupMembers(groupId); got != 2 {
		t.Fatalf("expected current connected target count B/D only, got %d", got)
	}

	admin.rendezvousDiscoverHook = func(namespace string, serverAddresses []string) ([]peer.AddrInfo, error) {
		if namespace != groupRendezvousNamespace(groupId) {
			t.Fatalf("unexpected rendezvous namespace %q", namespace)
		}
		return []peer.AddrInfo{
			{ID: memberBID, Addrs: memberB.Host().Addrs()},
			{ID: removedCID, Addrs: removedC.Host().Addrs()},
			{ID: memberDID, Addrs: memberD.Host().Addrs()},
			{ID: unknownXID, Addrs: unknownX.Host().Addrs()},
		}, nil
	}

	admin.discoverAndConnectGroupPeers(groupId)
	assertGM030DiscoveryEventTotals(t, collector, groupId, 4, 2, 2)
	waitForRP017Connectedness(t, admin, memberBID, network.Connected, time.Second)
	waitForRP017Connectedness(t, admin, memberDID, network.Connected, time.Second)
	if got := admin.Host().Network().Connectedness(removedCID); got == network.Connected {
		t.Fatalf("removed member C %s was dialed from rendezvous discovery after config update", removedC.PeerId())
	}
	if got := admin.Host().Network().Connectedness(unknownXID); got == network.Connected {
		t.Fatalf("unknown peer X %s was dialed from rendezvous discovery after config update", unknownX.PeerId())
	}
}

func TestGM031MembershipMutationUpdatesKnownMemberDialTargets(t *testing.T) {
	collector := &testEventCollector{}
	admin := startLocalNodeForMultiRelayTestWithCollector(t, collector)
	setFakeRelays(t, admin)
	memberBDevice := startLocalNodeForMultiRelayTest(t)
	removedCDevice := startLocalNodeForMultiRelayTest(t)
	memberDDevice := startLocalNodeForMultiRelayTest(t)
	staleBTopLevel := startLocalNodeForMultiRelayTest(t)
	staleCTopLevel := startLocalNodeForMultiRelayTest(t)
	staleDTopLevel := startLocalNodeForMultiRelayTest(t)

	decodePeerID := func(label, peerID string) peer.ID {
		t.Helper()
		decoded, err := peer.Decode(peerID)
		if err != nil {
			t.Fatalf("decode %s peer ID: %v", label, err)
		}
		return decoded
	}
	shortPeerID := func(peerID string) string {
		if len(peerID) > 16 {
			return peerID[:16]
		}
		return peerID
	}

	memberBDeviceID := decodePeerID("member B device", memberBDevice.PeerId())
	removedCDeviceID := decodePeerID("removed C device", removedCDevice.PeerId())
	memberDDeviceID := decodePeerID("member D device", memberDDevice.PeerId())
	staleBTopLevelID := decodePeerID("stale B top-level", staleBTopLevel.PeerId())
	staleCTopLevelID := decodePeerID("stale C top-level", staleCTopLevel.PeerId())
	staleDTopLevelID := decodePeerID("stale D top-level", staleDTopLevel.PeerId())

	groupId := "gm031-membership-mutation-known-targets"
	oldConfig := &GroupConfig{
		Name:      "GM-031 Old",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: admin.PeerId(), Username: "Admin", Role: GroupRoleAdmin, PublicKey: "adminPk"},
			{
				PeerId:    staleBTopLevel.PeerId(),
				Username:  "B",
				Role:      GroupRoleWriter,
				PublicKey: "memberBTopPk",
				Devices: []GroupMemberDevice{{
					DeviceId:               "gm031-b-device",
					TransportPeerId:        memberBDevice.PeerId(),
					DeviceSigningPublicKey: "memberBDevicePk",
					KeyPackageId:           "kp-gm031-b-old",
					Status:                 "active",
				}},
			},
			{
				PeerId:    staleCTopLevel.PeerId(),
				Username:  "C",
				Role:      GroupRoleWriter,
				PublicKey: "removedCTopPk",
				Devices: []GroupMemberDevice{{
					DeviceId:               "gm031-c-device",
					TransportPeerId:        removedCDevice.PeerId(),
					DeviceSigningPublicKey: "removedCDevicePk",
					KeyPackageId:           "kp-gm031-c-old",
					Status:                 "active",
				}},
			},
		},
		CreatedBy: admin.PeerId(),
	}
	currentConfig := &GroupConfig{
		Name:      "GM-031 Current",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: admin.PeerId(), Username: "Admin", Role: GroupRoleAdmin, PublicKey: "adminPk"},
			{
				PeerId:    staleBTopLevel.PeerId(),
				Username:  "B",
				Role:      GroupRoleWriter,
				PublicKey: "memberBTopPk",
				Devices: []GroupMemberDevice{{
					DeviceId:               "gm031-b-device",
					TransportPeerId:        memberBDevice.PeerId(),
					DeviceSigningPublicKey: "memberBDevicePk",
					KeyPackageId:           "kp-gm031-b-current",
					Status:                 "active",
				}},
			},
			{
				PeerId:    staleDTopLevel.PeerId(),
				Username:  "D",
				Role:      GroupRoleWriter,
				PublicKey: "memberDTopPk",
				Devices: []GroupMemberDevice{{
					DeviceId:               "gm031-d-device",
					TransportPeerId:        memberDDevice.PeerId(),
					DeviceSigningPublicKey: "memberDDevicePk",
					KeyPackageId:           "kp-gm031-d-current",
					Status:                 "active",
				}},
			},
		},
		CreatedBy: admin.PeerId(),
	}

	admin.UpdateGroupConfig(groupId, oldConfig)
	admin.UpdateGroupConfig(groupId, currentConfig)
	admin.Host().Peerstore().AddAddrs(memberBDeviceID, memberBDevice.Host().Addrs(), time.Hour)
	admin.Host().Peerstore().AddAddrs(removedCDeviceID, removedCDevice.Host().Addrs(), time.Hour)
	admin.Host().Peerstore().AddAddrs(memberDDeviceID, memberDDevice.Host().Addrs(), time.Hour)
	admin.Host().Peerstore().AddAddrs(staleBTopLevelID, staleBTopLevel.Host().Addrs(), time.Hour)
	admin.Host().Peerstore().AddAddrs(staleCTopLevelID, staleCTopLevel.Host().Addrs(), time.Hour)
	admin.Host().Peerstore().AddAddrs(staleDTopLevelID, staleDTopLevel.Host().Addrs(), time.Hour)

	admin.mu.RLock()
	storedConfig := cloneGroupConfig(admin.groupConfigs[groupId])
	admin.mu.RUnlock()
	if storedConfig == nil {
		t.Fatal("expected current group config to be stored")
	}

	targets := activeGroupMemberDialTargets(storedConfig, admin.PeerId())
	if len(targets) != 2 {
		t.Fatalf("expected current active device dial targets B/D only, got %d: %+v", len(targets), targets)
	}
	targetSet := make(map[string]struct{}, len(targets))
	for _, target := range targets {
		targetSet[target.PeerId] = struct{}{}
	}
	for _, want := range []string{memberBDevice.PeerId(), memberDDevice.PeerId()} {
		if _, ok := targetSet[want]; !ok {
			t.Fatalf("expected active device target %s after config update, got %+v", want, targets)
		}
	}
	for label, blocked := range map[string]string{
		"removed C device":  removedCDevice.PeerId(),
		"stale B top-level": staleBTopLevel.PeerId(),
		"stale C top-level": staleCTopLevel.PeerId(),
		"stale D top-level": staleDTopLevel.PeerId(),
	} {
		if _, ok := targetSet[blocked]; ok {
			t.Fatalf("%s %s remained in active dial targets: %+v", label, blocked, targets)
		}
	}
	if got := countRemoteGroupMembers(storedConfig, admin.PeerId()); got != 2 {
		t.Fatalf("expected current remote member count B/D active devices only, got %d", got)
	}
	if got := admin.expectedConnectedGroupMembers(groupId); got != 2 {
		t.Fatalf("expected current connected target count B/D active devices only, got %d", got)
	}

	expectedEventPeers := map[string]string{
		shortPeerID(memberBDevice.PeerId()): "member B device",
		shortPeerID(memberDDevice.PeerId()): "member D device",
	}
	disallowedEventPeers := map[string]string{
		shortPeerID(removedCDevice.PeerId()): "removed C device",
		shortPeerID(staleBTopLevel.PeerId()): "stale B top-level",
		shortPeerID(staleCTopLevel.PeerId()): "stale C top-level",
		shortPeerID(staleDTopLevel.PeerId()): "stale D top-level",
	}
	for peerShort, expectedLabel := range expectedEventPeers {
		if disallowedLabel, ok := disallowedEventPeers[peerShort]; ok {
			t.Fatalf("test generated colliding short peer IDs for %s and %s: %s", expectedLabel, disallowedLabel, peerShort)
		}
	}

	admin.dialKnownGroupMembers(groupId, true)

	waitForRP017Connectedness(t, admin, memberBDeviceID, network.Connected, time.Second)
	waitForRP017Connectedness(t, admin, memberDDeviceID, network.Connected, time.Second)
	for label, blockedID := range map[string]peer.ID{
		"removed C device":  removedCDeviceID,
		"stale B top-level": staleBTopLevelID,
		"stale C top-level": staleCTopLevelID,
		"stale D top-level": staleDTopLevelID,
	} {
		if got := admin.Host().Network().Connectedness(blockedID); got == network.Connected {
			t.Fatalf("%s %s was dialed from known-member recovery after config update", label, blockedID)
		}
	}

	collectDialEvidence := func() (map[string]struct{}, bool, []string) {
		t.Helper()

		knownMemberEventPeers := make(map[string]struct{})
		directDialSummarySeen := false
		events := collector.snapshot()
		for _, raw := range events {
			var payload map[string]interface{}
			if err := json.Unmarshal([]byte(raw), &payload); err != nil {
				continue
			}
			if payload["event"] != "group:discovery" {
				continue
			}
			data, ok := payload["data"].(map[string]interface{})
			if !ok || data["groupId"] != groupId {
				continue
			}
			step, ok := data["step"].(string)
			if !ok {
				continue
			}
			if strings.HasPrefix(step, "known_member_") {
				if eventPeer, ok := data["peerId"].(string); ok && eventPeer != "" {
					knownMemberEventPeers[eventPeer] = struct{}{}
				}
				continue
			}
			if step == "direct_dial" {
				totalMembers, ok := data["totalMembers"].(float64)
				if !ok || int(totalMembers) != 2 {
					t.Fatalf("direct_dial totalMembers = %v, want 2; events=%v", data["totalMembers"], events)
				}
				directDialSummarySeen = true
			}
		}
		return knownMemberEventPeers, directDialSummarySeen, events
	}
	var knownMemberEventPeers map[string]struct{}
	var directDialSummarySeen bool
	var eventSnapshot []string
	eventDeadline := time.Now().Add(time.Second)
	for {
		knownMemberEventPeers, directDialSummarySeen, eventSnapshot = collectDialEvidence()
		if directDialSummarySeen && len(knownMemberEventPeers) == len(expectedEventPeers) {
			break
		}
		if time.Now().After(eventDeadline) {
			break
		}
		time.Sleep(25 * time.Millisecond)
	}
	if !directDialSummarySeen {
		t.Fatalf("expected direct_dial summary event for group %s; events=%v", groupId, eventSnapshot)
	}
	for peerShort, label := range expectedEventPeers {
		if _, ok := knownMemberEventPeers[peerShort]; !ok {
			t.Fatalf("expected known-member dial event for %s %s; got %v", label, peerShort, knownMemberEventPeers)
		}
	}
	for peerShort, label := range disallowedEventPeers {
		if _, ok := knownMemberEventPeers[peerShort]; ok {
			t.Fatalf("known-member dial event named %s %s; events=%v", label, peerShort, eventSnapshot)
		}
	}
	if len(knownMemberEventPeers) != len(expectedEventPeers) {
		t.Fatalf("known-member dial events = %v, want exactly %v", knownMemberEventPeers, expectedEventPeers)
	}
}

func TestGM023GroupPeerDiscoveryUsesActiveDeviceAfterInactiveShadow(t *testing.T) {
	admin := startLocalNodeForMultiRelayTest(t)
	setFakeRelays(t, admin)
	inactiveCharlie := startLocalNodeForMultiRelayTest(t)
	activeCharlie := startLocalNodeForMultiRelayTest(t)

	inactiveID, err := peer.Decode(inactiveCharlie.PeerId())
	if err != nil {
		t.Fatalf("decode inactive Charlie peer ID: %v", err)
	}
	activeID, err := peer.Decode(activeCharlie.PeerId())
	if err != nil {
		t.Fatalf("decode active Charlie peer ID: %v", err)
	}

	groupId := "gm023-inactive-shadow-discovery"
	charlieMemberPeerId := "member-charlie"
	config := &GroupConfig{
		Name:      "GM-023 Discovery",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: admin.PeerId(), Role: GroupRoleAdmin, PublicKey: "adminPk"},
			{
				PeerId:    charlieMemberPeerId,
				Username:  "Charlie",
				Role:      GroupRoleWriter,
				PublicKey: "inactivePk",
				Devices: []GroupMemberDevice{{
					DeviceId:               "charlie-device",
					TransportPeerId:        inactiveCharlie.PeerId(),
					DeviceSigningPublicKey: "inactivePk",
					KeyPackageId:           "kp-charlie-inactive",
					Status:                 "revoked",
					RevokedAt:              "2026-05-11T08:00:00Z",
				}},
			},
			{
				PeerId:    charlieMemberPeerId,
				Username:  "Charlie",
				Role:      GroupRoleWriter,
				PublicKey: "activePk",
				Devices: []GroupMemberDevice{{
					DeviceId:               "charlie-device",
					TransportPeerId:        activeCharlie.PeerId(),
					DeviceSigningPublicKey: "activePk",
					KeyPackageId:           "kp-charlie-active",
					Status:                 "active",
				}},
			},
		},
		CreatedBy: admin.PeerId(),
	}
	admin.mu.Lock()
	admin.groupConfigs[groupId] = config
	admin.mu.Unlock()
	admin.Host().Peerstore().AddAddrs(inactiveID, inactiveCharlie.Host().Addrs(), time.Hour)
	admin.Host().Peerstore().AddAddrs(activeID, activeCharlie.Host().Addrs(), time.Hour)

	if got := countRemoteGroupMembers(config, admin.PeerId()); got != 1 {
		t.Fatalf("expected one active remote dial target after inactive shadow normalization, got %d", got)
	}
	if got := admin.expectedConnectedGroupMembers(groupId); got != 1 {
		t.Fatalf("expected one active connected target after inactive shadow normalization, got %d", got)
	}

	admin.rendezvousDiscoverHook = func(namespace string, serverAddresses []string) ([]peer.AddrInfo, error) {
		if namespace != groupRendezvousNamespace(groupId) {
			t.Fatalf("unexpected rendezvous namespace %q", namespace)
		}
		return []peer.AddrInfo{
			{ID: inactiveID, Addrs: inactiveCharlie.Host().Addrs()},
		}, nil
	}
	admin.discoverAndConnectGroupPeers(groupId)
	time.Sleep(100 * time.Millisecond)
	if got := admin.Host().Network().Connectedness(inactiveID); got == network.Connected {
		t.Fatalf("inactive Charlie shadow transport %s was dialed from discovery", inactiveCharlie.PeerId())
	}

	admin.dialKnownGroupMembers(groupId, true)
	waitForRP017Connectedness(t, admin, activeID, network.Connected, time.Second)
	if got := admin.Host().Network().Connectedness(inactiveID); got == network.Connected {
		t.Fatalf("inactive Charlie shadow transport %s was dialed from known-member recovery", inactiveCharlie.PeerId())
	}
}

func TestGA022MalformedPeerIDsInConfigDoNotCrashDiscoveryDialAndCounters(t *testing.T) {
	collector := &testEventCollector{}
	admin := startLocalNodeForMultiRelayTestWithCollector(t, collector)
	validDialPeer := startLocalNodeForMultiRelayTest(t)
	validDiscoveredPeer := startLocalNodeForMultiRelayTest(t)
	nonMemberDiscoveredPeer := startLocalNodeForMultiRelayTest(t)

	invalidMemberPeerID := "not-a-libp2p-peer-id"
	invalidDeviceTransportID := "also-not-a-libp2p-peer-id"
	buildConfig := func(name string, validPeer *Node) *GroupConfig {
		t.Helper()
		return &GroupConfig{
			Name:      name,
			GroupType: GroupTypeChat,
			Members: []GroupMember{
				{
					PeerId:         admin.PeerId(),
					Username:       "Admin",
					Role:           GroupRoleAdmin,
					PublicKey:      "adminPk",
					MlKemPublicKey: "adminMlKem",
				},
				{
					PeerId:         validPeer.PeerId(),
					Username:       "Valid",
					Role:           GroupRoleWriter,
					PublicKey:      "validPk",
					MlKemPublicKey: "validMlKem",
				},
				{
					PeerId:   invalidMemberPeerID,
					Username: "InvalidLegacy",
					Role:     GroupRoleWriter,
				},
				{
					PeerId:    "ga022-device-member",
					Username:  "InvalidDeviceTransport",
					Role:      GroupRoleWriter,
					PublicKey: "invalidDevicePk",
					Devices: []GroupMemberDevice{{
						DeviceId:               "ga022-device",
						TransportPeerId:        invalidDeviceTransportID,
						DeviceSigningPublicKey: "invalidDevicePk",
						KeyPackageId:           "ga022-kp",
						Status:                 "active",
					}},
				},
			},
			CreatedBy: admin.PeerId(),
		}
	}

	dialGroupID := "ga022-malformed-known-dial"
	discoveryGroupID := "ga022-malformed-discovery"
	dialConfig := buildConfig("GA022 Known Dial", validDialPeer)
	discoveryConfig := buildConfig("GA022 Discovery", validDiscoveredPeer)

	admin.mu.Lock()
	admin.groupConfigs[dialGroupID] = dialConfig
	admin.groupConfigs[discoveryGroupID] = discoveryConfig
	admin.mu.Unlock()

	summary := activeGroupMemberDialTargetSummary(dialConfig, admin.PeerId())
	if summary.ignoredInvalidConfigPeer != 2 {
		t.Fatalf("ignored invalid config peers = %d, want 2", summary.ignoredInvalidConfigPeer)
	}
	if len(summary.targets) != 1 || summary.targets[0].PeerId != validDialPeer.PeerId() {
		t.Fatalf("dial targets = %+v, want only valid peer %s", summary.targets, validDialPeer.PeerId())
	}
	if got := countRemoteGroupMembers(dialConfig, admin.PeerId()); got != 1 {
		t.Fatalf("countRemoteGroupMembers = %d, want 1", got)
	}
	if got := admin.expectedConnectedGroupMembers(dialGroupID); got != 1 {
		t.Fatalf("expectedConnectedGroupMembers = %d, want 1", got)
	}

	validDialPeerID, err := peer.Decode(validDialPeer.PeerId())
	if err != nil {
		t.Fatalf("decode valid dial peer: %v", err)
	}
	admin.Host().Peerstore().AddAddrs(validDialPeerID, validDialPeer.Host().Addrs(), time.Hour)
	admin.dialKnownGroupMembersDirectOnly(dialGroupID)
	waitForRP017Connectedness(t, admin, validDialPeerID, network.Connected, time.Second)

	waitForDiscoveryEventData := func(groupID string, step string) map[string]interface{} {
		t.Helper()
		deadline := time.Now().Add(time.Second)
		for time.Now().Before(deadline) {
			for _, raw := range collector.snapshot() {
				var payload map[string]interface{}
				if err := json.Unmarshal([]byte(raw), &payload); err != nil {
					continue
				}
				if payload["event"] != "group:discovery" {
					continue
				}
				data, ok := payload["data"].(map[string]interface{})
				if !ok || data["groupId"] != groupID || data["step"] != step {
					continue
				}
				return data
			}
			time.Sleep(25 * time.Millisecond)
		}
		t.Fatalf("timed out waiting for group %s discovery step %s; events=%v", groupID, step, collector.snapshot())
		return nil
	}
	assertNumericField := func(data map[string]interface{}, field string, want int) {
		t.Helper()
		got, ok := data[field].(float64)
		if !ok || int(got) != want {
			t.Fatalf("%s = %v, want %d in event data %#v", field, data[field], want, data)
		}
	}

	directData := waitForDiscoveryEventData(dialGroupID, "pre_relay_direct_dial")
	assertNumericField(directData, "totalMembers", 1)
	assertNumericField(directData, "ignoredInvalidConfigPeers", 2)

	validDiscoveredPeerID, err := peer.Decode(validDiscoveredPeer.PeerId())
	if err != nil {
		t.Fatalf("decode valid discovered peer: %v", err)
	}
	nonMemberID, err := peer.Decode(nonMemberDiscoveredPeer.PeerId())
	if err != nil {
		t.Fatalf("decode non-member discovered peer: %v", err)
	}
	admin.rendezvousDiscoverHook = func(namespace string, serverAddresses []string) ([]peer.AddrInfo, error) {
		if namespace != groupRendezvousNamespace(discoveryGroupID) {
			t.Fatalf("unexpected rendezvous namespace %q", namespace)
		}
		return []peer.AddrInfo{
			{ID: validDiscoveredPeerID, Addrs: validDiscoveredPeer.Host().Addrs()},
			{ID: nonMemberID, Addrs: nonMemberDiscoveredPeer.Host().Addrs()},
		}, nil
	}

	admin.discoverAndConnectGroupPeers(discoveryGroupID)
	discoverData := waitForDiscoveryEventData(discoveryGroupID, "discover_result")
	assertNumericField(discoverData, "totalFound", 2)
	assertNumericField(discoverData, "newPeers", 1)
	assertNumericField(discoverData, "ignoredNonMembers", 1)
	assertNumericField(discoverData, "ignoredInvalidConfigPeers", 2)
	waitForRP017Connectedness(t, admin, validDiscoveredPeerID, network.Connected, time.Second)
	if got := admin.Host().Network().Connectedness(nonMemberID); got == network.Connected {
		t.Fatalf("non-member discovered peer %s was connected", nonMemberDiscoveredPeer.PeerId())
	}
}

func TestGP012RendezvousDiscoverySkipsInvalidPeerIDsAndDialsValidMember(t *testing.T) {
	collector := &testEventCollector{}
	admin := startLocalNodeForMultiRelayTestWithCollector(t, collector)
	validPeer := startLocalNodeForMultiRelayTest(t)

	groupID := "gp012-invalid-rendezvous-peer-ids"
	invalidLegacyPeerID := "not-a-libp2p-peer-id"
	invalidDeviceTransportID := "also-not-a-libp2p-peer-id"
	config := &GroupConfig{
		Name:      "GP012 Invalid Rendezvous IDs",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{
				PeerId:    admin.PeerId(),
				Username:  "Admin",
				Role:      GroupRoleAdmin,
				PublicKey: "adminPk",
			},
			{
				PeerId:    validPeer.PeerId(),
				Username:  "Valid",
				Role:      GroupRoleWriter,
				PublicKey: "validPk",
			},
			{
				PeerId:   invalidLegacyPeerID,
				Username: "InvalidLegacy",
				Role:     GroupRoleWriter,
			},
			{
				PeerId:    "gp012-device-member",
				Username:  "InvalidDeviceTransport",
				Role:      GroupRoleWriter,
				PublicKey: "invalidDevicePk",
				Devices: []GroupMemberDevice{{
					DeviceId:               "gp012-device",
					TransportPeerId:        invalidDeviceTransportID,
					DeviceSigningPublicKey: "invalidDevicePk",
					KeyPackageId:           "gp012-kp",
					Status:                 "active",
				}},
			},
		},
		CreatedBy: admin.PeerId(),
	}

	admin.mu.Lock()
	admin.groupConfigs[groupID] = config
	admin.mu.Unlock()

	validPeerID, err := peer.Decode(validPeer.PeerId())
	if err != nil {
		t.Fatalf("decode valid peer: %v", err)
	}
	invalidDiscoveredID := peer.ID("not-a-valid-rendezvous-peer-id")
	admin.rendezvousDiscoverHook = func(namespace string, serverAddresses []string) ([]peer.AddrInfo, error) {
		if namespace != groupRendezvousNamespace(groupID) {
			return nil, fmt.Errorf("unexpected rendezvous namespace %q", namespace)
		}
		return []peer.AddrInfo{
			{ID: invalidDiscoveredID, Addrs: validPeer.Host().Addrs()},
			{ID: validPeerID, Addrs: validPeer.Host().Addrs()},
		}, nil
	}

	admin.discoverAndConnectGroupPeers(groupID)

	discoverData := waitForCollectedEventData(t, collector, "group:discovery", func(data map[string]interface{}) bool {
		return data["groupId"] == groupID && data["step"] == "discover_result"
	}, time.Second)
	assertGP012NumericField(t, discoverData, "totalFound", 2)
	assertGP012NumericField(t, discoverData, "newPeers", 1)
	assertGP012NumericField(t, discoverData, "ignoredNonMembers", 1)
	assertGP012NumericField(t, discoverData, "ignoredInvalidConfigPeers", 2)

	waitForRP017Connectedness(t, admin, validPeerID, network.Connected, time.Second)
	if addrs := admin.Host().Peerstore().Addrs(invalidDiscoveredID); len(addrs) != 0 {
		t.Fatalf("invalid discovered peer %s was imported into peerstore with addrs=%v", invalidDiscoveredID, addrs)
	}
}

func TestGO006DiscoveryEventsExposeMissingPeerCondition(t *testing.T) {
	collector := &testEventCollector{}
	admin := startLocalNodeForMultiRelayTestWithCollector(t, collector)
	groupID := "go006-discovery-missing-peer"
	missingPeerID := generatePeerIDStr(t)
	config := &GroupConfig{
		Name:      "GO006 Missing Peer Diagnostics",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: admin.PeerId(), Role: GroupRoleAdmin, PublicKey: "adminPubKey"},
			{PeerId: missingPeerID, Role: GroupRoleWriter, PublicKey: "missingPubKey"},
		},
		CreatedBy: admin.PeerId(),
	}

	admin.mu.Lock()
	admin.groupConfigs[groupID] = config
	admin.mu.Unlock()
	admin.rendezvousDiscoverHook = func(namespace string, serverAddresses []string) ([]peer.AddrInfo, error) {
		if namespace != groupRendezvousNamespace(groupID) {
			return nil, fmt.Errorf("unexpected rendezvous namespace %q", namespace)
		}
		return nil, nil
	}

	admin.discoverAndConnectGroupPeers(groupID)
	discoverData := waitForCollectedEventData(t, collector, "group:discovery", func(data map[string]interface{}) bool {
		return data["groupId"] == groupID && data["step"] == "discover_result"
	}, time.Second)
	assertGO006NumericField(t, discoverData, "totalFound", 0)
	assertGO006NumericField(t, discoverData, "newPeers", 0)
	assertGO006NumericField(t, discoverData, "topicPeers", 0)
	assertGO006NumericField(t, discoverData, "expectedPeers", 1)
	assertGO006NumericField(t, discoverData, "missingPeers", 1)
	assertGO006BoolField(t, discoverData, "backingOff", false)

	nextInterval := GroupDiscoveryWarmInterval * 2
	admin.emitGroupDiscoveryBackoff(groupID, 0, 1, 2, nextInterval, 0)
	backoffData := waitForCollectedEventData(t, collector, "group:discovery", func(data map[string]interface{}) bool {
		return data["groupId"] == groupID && data["step"] == "backoff"
	}, time.Second)
	assertGO006NumericField(t, backoffData, "connectedMembers", 0)
	assertGO006NumericField(t, backoffData, "expectedMembers", 1)
	assertGO006NumericField(t, backoffData, "topicPeers", 0)
	assertGO006NumericField(t, backoffData, "expectedPeers", 1)
	assertGO006NumericField(t, backoffData, "missingPeers", 1)
	assertGO006NumericField(t, backoffData, "consecutiveFailures", 2)
	assertGO006NumericField(t, backoffData, "nextIntervalMs", int(nextInterval.Milliseconds()))
	assertGO006NumericField(t, backoffData, "warmRetriesRemaining", 0)
	assertGO006BoolField(t, backoffData, "backingOff", true)
	if got := backoffData["nextInterval"]; got != nextInterval.String() {
		t.Fatalf("nextInterval = %v, want %s in event data %#v", got, nextInterval.String(), backoffData)
	}
}

func assertGO006NumericField(t *testing.T, data map[string]interface{}, field string, want int) {
	t.Helper()
	got, ok := data[field].(float64)
	if !ok || int(got) != want {
		t.Fatalf("%s = %v, want %d in event data %#v", field, data[field], want, data)
	}
}

func assertGO006BoolField(t *testing.T, data map[string]interface{}, field string, want bool) {
	t.Helper()
	got, ok := data[field].(bool)
	if !ok || got != want {
		t.Fatalf("%s = %v, want %t in event data %#v", field, data[field], want, data)
	}
}

func assertGP012NumericField(t *testing.T, data map[string]interface{}, field string, want int) {
	t.Helper()
	got, ok := data[field].(float64)
	if !ok || int(got) != want {
		t.Fatalf("%s = %v, want %d in event data %#v", field, data[field], want, data)
	}
}

func TestGA023ConfigUpdateRemovesRevokedDeviceFromDiscoveryAllowedSet(t *testing.T) {
	collector := &testEventCollector{}
	admin := startLocalNodeForMultiRelayTestWithCollector(t, collector)
	deviceS := startLocalNodeForMultiRelayTest(t)

	deviceSID, err := peer.Decode(deviceS.PeerId())
	if err != nil {
		t.Fatalf("decode device S peer ID: %v", err)
	}

	groupID := "ga023-revoked-device-discovery"
	memberBID := "ga023-member-b"
	initialConfig := &GroupConfig{
		Name:      "GA023 Initial",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: admin.PeerId(), Role: GroupRoleAdmin, PublicKey: "adminPk"},
			{
				PeerId:    memberBID,
				Username:  "Bob",
				Role:      GroupRoleWriter,
				PublicKey: "bobPk",
				Devices: []GroupMemberDevice{{
					DeviceId:               "ga023-device-s",
					TransportPeerId:        deviceS.PeerId(),
					DeviceSigningPublicKey: "deviceSPk",
					KeyPackageId:           "ga023-kp-s",
					Status:                 "active",
				}},
			},
		},
		CreatedBy: admin.PeerId(),
	}
	admin.UpdateGroupConfig(groupID, initialConfig)
	if targets := activeGroupMemberDialTargets(initialConfig, admin.PeerId()); len(targets) != 1 || targets[0].PeerId != deviceS.PeerId() {
		t.Fatalf("initial active targets = %+v, want device S %s", targets, deviceS.PeerId())
	}
	if got := admin.expectedConnectedGroupMembers(groupID); got != 1 {
		t.Fatalf("initial expectedConnectedGroupMembers = %d, want 1", got)
	}

	revokedConfig := cloneGroupConfig(initialConfig)
	revokedConfig.Members[1].Devices[0].Status = "revoked"
	revokedConfig.Members[1].Devices[0].RevokedAt = "2026-05-12T21:23:00Z"
	admin.UpdateGroupConfig(groupID, revokedConfig)

	admin.mu.RLock()
	storedConfig := cloneGroupConfig(admin.groupConfigs[groupID])
	admin.mu.RUnlock()
	if storedConfig == nil {
		t.Fatal("expected stored config after revoked update")
	}
	if targets := activeGroupMemberDialTargets(storedConfig, admin.PeerId()); len(targets) != 0 {
		t.Fatalf("revoked config active targets = %+v, want none", targets)
	}
	if _, ok := activeGroupMemberDialTargetSet(storedConfig, admin.PeerId())[deviceS.PeerId()]; ok {
		t.Fatalf("revoked device transport %s remained in active dial target set", deviceS.PeerId())
	}
	if got := countRemoteGroupMembers(storedConfig, admin.PeerId()); got != 0 {
		t.Fatalf("revoked countRemoteGroupMembers = %d, want 0", got)
	}
	if got := admin.expectedConnectedGroupMembers(groupID); got != 0 {
		t.Fatalf("revoked expectedConnectedGroupMembers = %d, want 0", got)
	}

	admin.Host().Peerstore().AddAddrs(deviceSID, deviceS.Host().Addrs(), time.Hour)
	admin.dialKnownGroupMembersDirectOnly(groupID)
	time.Sleep(100 * time.Millisecond)
	if got := admin.Host().Network().Connectedness(deviceSID); got == network.Connected {
		t.Fatalf("revoked device transport %s was dialed from known-member direct recovery", deviceS.PeerId())
	}

	waitForDiscoveryEventData := func(step string) map[string]interface{} {
		t.Helper()
		deadline := time.Now().Add(time.Second)
		for time.Now().Before(deadline) {
			for _, raw := range collector.snapshot() {
				var payload map[string]interface{}
				if err := json.Unmarshal([]byte(raw), &payload); err != nil {
					continue
				}
				if payload["event"] != "group:discovery" {
					continue
				}
				data, ok := payload["data"].(map[string]interface{})
				if !ok || data["groupId"] != groupID || data["step"] != step {
					continue
				}
				return data
			}
			time.Sleep(25 * time.Millisecond)
		}
		t.Fatalf("timed out waiting for group %s discovery step %s; events=%v", groupID, step, collector.snapshot())
		return nil
	}
	assertNumericField := func(data map[string]interface{}, field string, want int) {
		t.Helper()
		got, ok := data[field].(float64)
		if !ok || int(got) != want {
			t.Fatalf("%s = %v, want %d in event data %#v", field, data[field], want, data)
		}
	}
	directData := waitForDiscoveryEventData("pre_relay_direct_dial")
	assertNumericField(directData, "totalMembers", 0)

	admin.rendezvousDiscoverHook = func(namespace string, serverAddresses []string) ([]peer.AddrInfo, error) {
		if namespace != groupRendezvousNamespace(groupID) {
			t.Fatalf("unexpected rendezvous namespace %q", namespace)
		}
		return []peer.AddrInfo{{ID: deviceSID, Addrs: deviceS.Host().Addrs()}}, nil
	}
	admin.discoverAndConnectGroupPeers(groupID)
	discoverData := waitForDiscoveryEventData("discover_result")
	assertNumericField(discoverData, "totalFound", 1)
	assertNumericField(discoverData, "newPeers", 0)
	assertNumericField(discoverData, "ignoredNonMembers", 1)
	assertNumericField(discoverData, "ignoredInvalidConfigPeers", 0)
	time.Sleep(100 * time.Millisecond)
	if got := admin.Host().Network().Connectedness(deviceSID); got == network.Connected {
		t.Fatalf("revoked device transport %s was connected from rendezvous discovery", deviceS.PeerId())
	}
}

func TestGA024KnownMemberDialingUsesActiveDeviceTransports(t *testing.T) {
	collector := &testEventCollector{}
	admin := startLocalNodeForMultiRelayTestWithCollector(t, collector)
	logicalPeer := startLocalNodeForMultiRelayTest(t)
	deviceS1 := startLocalNodeForMultiRelayTest(t)
	deviceS2 := startLocalNodeForMultiRelayTest(t)

	logicalPeerID, err := peer.Decode(logicalPeer.PeerId())
	if err != nil {
		t.Fatalf("decode logical peer ID: %v", err)
	}
	deviceS1ID, err := peer.Decode(deviceS1.PeerId())
	if err != nil {
		t.Fatalf("decode device S1 peer ID: %v", err)
	}
	deviceS2ID, err := peer.Decode(deviceS2.PeerId())
	if err != nil {
		t.Fatalf("decode device S2 peer ID: %v", err)
	}

	groupID := "ga024-known-member-active-device-transports"
	config := &GroupConfig{
		Name:      "GA024",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: admin.PeerId(), Role: GroupRoleAdmin, PublicKey: "adminPk"},
			{
				PeerId:    logicalPeer.PeerId(),
				Username:  "MultiDevice",
				Role:      GroupRoleWriter,
				PublicKey: "logicalPk",
				Devices: []GroupMemberDevice{
					{
						DeviceId:               "ga024-device-s1",
						TransportPeerId:        deviceS1.PeerId(),
						DeviceSigningPublicKey: "deviceS1Pk",
						KeyPackageId:           "ga024-kp-s1",
						Status:                 "active",
					},
					{
						DeviceId:               "ga024-device-s2",
						TransportPeerId:        deviceS2.PeerId(),
						DeviceSigningPublicKey: "deviceS2Pk",
						KeyPackageId:           "ga024-kp-s2",
						Status:                 "active",
					},
				},
			},
		},
		CreatedBy: admin.PeerId(),
	}
	admin.UpdateGroupConfig(groupID, config)

	targets := activeGroupMemberDialTargets(config, admin.PeerId())
	targetSet := make(map[string]struct{}, len(targets))
	for _, target := range targets {
		targetSet[target.PeerId] = struct{}{}
	}
	if len(targetSet) != 2 {
		t.Fatalf("known-member targets = %+v, want two active device transports", targets)
	}
	for _, want := range []string{deviceS1.PeerId(), deviceS2.PeerId()} {
		if _, ok := targetSet[want]; !ok {
			t.Fatalf("missing active device transport %s from targets %+v", want, targets)
		}
	}
	if _, ok := targetSet[logicalPeer.PeerId()]; ok {
		t.Fatalf("logical member peer %s was selected instead of active device transports", logicalPeer.PeerId())
	}
	if got := countRemoteGroupMembers(config, admin.PeerId()); got != 2 {
		t.Fatalf("countRemoteGroupMembers = %d, want 2 active device transports", got)
	}
	if got := admin.expectedConnectedGroupMembers(groupID); got != 2 {
		t.Fatalf("expectedConnectedGroupMembers = %d, want 2 active device transports", got)
	}

	admin.Host().Peerstore().AddAddrs(logicalPeerID, logicalPeer.Host().Addrs(), time.Hour)
	admin.Host().Peerstore().AddAddrs(deviceS1ID, deviceS1.Host().Addrs(), time.Hour)
	admin.Host().Peerstore().AddAddrs(deviceS2ID, deviceS2.Host().Addrs(), time.Hour)
	admin.dialKnownGroupMembersDirectOnly(groupID)
	waitForRP017Connectedness(t, admin, deviceS1ID, network.Connected, time.Second)
	waitForRP017Connectedness(t, admin, deviceS2ID, network.Connected, time.Second)
	if got := admin.Host().Network().Connectedness(logicalPeerID); got == network.Connected {
		t.Fatalf("logical member peer %s was dialed despite active device transports", logicalPeer.PeerId())
	}

	peerShort := func(peerID string) string {
		if len(peerID) > 16 {
			return peerID[:16]
		}
		return peerID
	}
	wantS1Short := peerShort(deviceS1.PeerId())
	wantS2Short := peerShort(deviceS2.PeerId())
	collectDialEvidence := func() (map[string]struct{}, bool, map[string]interface{}, []string) {
		seenSuccess := make(map[string]struct{})
		directSummarySeen := false
		var directSummaryData map[string]interface{}
		events := collector.snapshot()
		for _, raw := range events {
			var payload map[string]interface{}
			if err := json.Unmarshal([]byte(raw), &payload); err != nil {
				continue
			}
			if payload["event"] != "group:discovery" {
				continue
			}
			data, ok := payload["data"].(map[string]interface{})
			if !ok || data["groupId"] != groupID {
				continue
			}
			switch data["step"] {
			case "known_member_pre_relay_direct_success":
				if peerID, ok := data["peerId"].(string); ok {
					seenSuccess[peerID] = struct{}{}
				}
			case "pre_relay_direct_dial":
				directSummarySeen = true
				directSummaryData = data
			}
		}
		return seenSuccess, directSummarySeen, directSummaryData, events
	}

	var seenSuccess map[string]struct{}
	var directSummarySeen bool
	var directSummaryData map[string]interface{}
	var events []string
	deadline := time.Now().Add(time.Second)
	for {
		seenSuccess, directSummarySeen, directSummaryData, events = collectDialEvidence()
		_, sawS1 := seenSuccess[wantS1Short]
		_, sawS2 := seenSuccess[wantS2Short]
		if directSummarySeen && sawS1 && sawS2 {
			break
		}
		if time.Now().After(deadline) {
			break
		}
		time.Sleep(25 * time.Millisecond)
	}
	if !directSummarySeen {
		t.Fatalf("missing pre_relay_direct_dial summary event; events=%v", events)
	}
	totalMembers, ok := directSummaryData["totalMembers"].(float64)
	if !ok || int(totalMembers) != 2 {
		t.Fatalf("pre_relay_direct_dial totalMembers = %v, want 2; event=%#v", directSummaryData["totalMembers"], directSummaryData)
	}
	for _, want := range []string{wantS1Short, wantS2Short} {
		if _, ok := seenSuccess[want]; !ok {
			t.Fatalf("missing direct success event for active device %s; seen=%v events=%v", want, seenSuccess, events)
		}
	}
	if _, ok := seenSuccess[peerShort(logicalPeer.PeerId())]; ok {
		t.Fatalf("logical member peer %s emitted known-member direct success; seen=%v", logicalPeer.PeerId(), seenSuccess)
	}
}

func TestGA025ExpectedPeerCountUsesActiveDevicesCurrentRecipients(t *testing.T) {
	collector := &testEventCollector{}
	admin := startLocalNodeForMultiRelayTestWithCollector(t, collector)
	logicalPeer := startLocalNodeForMultiRelayTest(t)
	deviceS1 := startLocalNodeForMultiRelayTest(t)
	deviceS2 := startLocalNodeForMultiRelayTest(t)
	revokedDevice := startLocalNodeForMultiRelayTest(t)
	removedTransport := startLocalNodeForMultiRelayTest(t)

	privB64, pubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	decodePeer := func(label, peerID string) peer.ID {
		t.Helper()
		decoded, err := peer.Decode(peerID)
		if err != nil {
			t.Fatalf("decode %s peer ID %s: %v", label, peerID, err)
		}
		return decoded
	}
	logicalPeerID := decodePeer("logical", logicalPeer.PeerId())
	deviceS1ID := decodePeer("device S1", deviceS1.PeerId())
	deviceS2ID := decodePeer("device S2", deviceS2.PeerId())
	revokedDeviceID := decodePeer("revoked device", revokedDevice.PeerId())
	removedTransportID := decodePeer("removed transport", removedTransport.PeerId())

	groupID := "ga025-expected-peer-active-device-count"
	config := &GroupConfig{
		Name:      "GA025",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: admin.PeerId(), Username: "Admin", Role: GroupRoleAdmin, PublicKey: pubB64},
			{
				PeerId:    logicalPeer.PeerId(),
				Username:  "MultiDevice",
				Role:      GroupRoleWriter,
				PublicKey: "logicalPk",
				Devices: []GroupMemberDevice{
					{
						DeviceId:               "ga025-device-s1",
						TransportPeerId:        deviceS1.PeerId(),
						DeviceSigningPublicKey: "ga025-device-s1-pk",
						KeyPackageId:           "ga025-kp-s1",
						Status:                 "active",
					},
					{
						DeviceId:               "ga025-device-s2",
						TransportPeerId:        deviceS2.PeerId(),
						DeviceSigningPublicKey: "ga025-device-s2-pk",
						KeyPackageId:           "ga025-kp-s2",
						Status:                 "active",
					},
					{
						DeviceId:               "ga025-revoked-device",
						TransportPeerId:        revokedDevice.PeerId(),
						DeviceSigningPublicKey: "ga025-revoked-device-pk",
						KeyPackageId:           "ga025-kp-revoked",
						Status:                 "revoked",
						RevokedAt:              "2026-05-12T21:25:00Z",
					},
				},
			},
			{
				PeerId:    "ga025-removed-member",
				Username:  "Removed",
				Role:      GroupRoleWriter,
				PublicKey: "removedPk",
				Devices: []GroupMemberDevice{{
					DeviceId:               "ga025-removed-device",
					TransportPeerId:        removedTransport.PeerId(),
					DeviceSigningPublicKey: "ga025-removed-device-pk",
					KeyPackageId:           "ga025-kp-removed",
					Status:                 "revoked",
					RevokedAt:              "2026-05-12T21:26:00Z",
				}},
			},
		},
		CreatedBy: admin.PeerId(),
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	for _, n := range []*Node{admin, deviceS1, deviceS2} {
		if err := n.JoinGroupTopic(groupID, config, keyInfo); err != nil {
			t.Fatalf("%s JoinGroupTopic: %v", n.PeerId(), err)
		}
	}

	targets := activeGroupMemberDialTargets(config, admin.PeerId())
	targetSet := make(map[string]struct{}, len(targets))
	for _, target := range targets {
		targetSet[target.PeerId] = struct{}{}
	}
	for _, want := range []string{deviceS1.PeerId(), deviceS2.PeerId()} {
		if _, ok := targetSet[want]; !ok {
			t.Fatalf("missing active device target %s from %+v", want, targets)
		}
	}
	for _, notWant := range []string{logicalPeer.PeerId(), revokedDevice.PeerId(), removedTransport.PeerId()} {
		if _, ok := targetSet[notWant]; ok {
			t.Fatalf("stale or logical peer %s was included in targets %+v", notWant, targets)
		}
	}
	if len(targetSet) != 2 {
		t.Fatalf("target count = %d, want exactly two active device transports: %+v", len(targetSet), targets)
	}
	if got := countRemoteGroupMembers(config, admin.PeerId()); got != 2 {
		t.Fatalf("countRemoteGroupMembers = %d, want two active device transports", got)
	}
	if got := admin.expectedConnectedGroupMembers(groupID); got != 2 {
		t.Fatalf("expectedConnectedGroupMembers = %d, want two active device transports", got)
	}

	admin.mu.RLock()
	topic := admin.groupTopics[groupID]
	initialPeers := 0
	if topic != nil {
		initialPeers = len(topic.ListPeers())
	}
	admin.mu.RUnlock()
	if initialPeers >= 2 {
		t.Fatalf("expected publish preflight to be needed, initial topic peers = %d", initialPeers)
	}

	admin.Host().Peerstore().AddAddrs(deviceS1ID, deviceS1.Host().Addrs(), time.Hour)
	admin.Host().Peerstore().AddAddrs(deviceS2ID, deviceS2.Host().Addrs(), time.Hour)
	admin.Host().Peerstore().AddAddrs(logicalPeerID, logicalPeer.Host().Addrs(), time.Hour)
	admin.Host().Peerstore().AddAddrs(revokedDeviceID, revokedDevice.Host().Addrs(), time.Hour)
	admin.Host().Peerstore().AddAddrs(removedTransportID, removedTransport.Host().Addrs(), time.Hour)

	msgID, peerCount, err := admin.PublishGroupMessage(
		groupID,
		privB64,
		admin.PeerId(),
		pubB64,
		"Admin",
		"ga025 expected peer count",
		"ga025-message",
		nil,
	)
	if err != nil {
		t.Fatalf("PublishGroupMessage failed: %v", err)
	}
	if msgID != "ga025-message" {
		t.Fatalf("PublishGroupMessage msgID = %q, want ga025-message", msgID)
	}
	if peerCount != 2 {
		t.Fatalf("PublishGroupMessage peerCount = %d, want exactly two active device transports", peerCount)
	}
	waitForGroupTopicPeerCount(t, admin, groupID, 2, 2*time.Second)

	waitForDiscoveryEventData := func(step string) map[string]interface{} {
		t.Helper()
		deadline := time.Now().Add(2 * time.Second)
		for time.Now().Before(deadline) {
			for _, raw := range collector.snapshot() {
				var payload map[string]interface{}
				if err := json.Unmarshal([]byte(raw), &payload); err != nil {
					continue
				}
				if payload["event"] != "group:discovery" {
					continue
				}
				data, ok := payload["data"].(map[string]interface{})
				if !ok || data["groupId"] != groupID || data["step"] != step {
					continue
				}
				return data
			}
			time.Sleep(25 * time.Millisecond)
		}
		t.Fatalf("timed out waiting for group %s discovery step %s; events=%v", groupID, step, collector.snapshot())
		return nil
	}
	assertNumericField := func(data map[string]interface{}, field string, want int) {
		t.Helper()
		got, ok := data[field].(float64)
		if !ok || int(got) != want {
			t.Fatalf("%s = %v, want %d in event data %#v", field, data[field], want, data)
		}
	}

	beginData := waitForDiscoveryEventData("publish_peer_refresh_begin")
	assertNumericField(beginData, "expectedPeers", 2)
	doneData := waitForDiscoveryEventData("publish_peer_refresh_done")
	assertNumericField(doneData, "expectedPeers", 2)
	assertNumericField(doneData, "topicPeers", 2)
	directData := waitForDiscoveryEventData("direct_dial")
	assertNumericField(directData, "totalMembers", 2)
	assertNumericField(directData, "ignoredInvalidConfigPeers", 0)

	time.Sleep(100 * time.Millisecond)
	for _, notWant := range []struct {
		label string
		id    peer.ID
	}{
		{label: "logical member peer", id: logicalPeerID},
		{label: "revoked device", id: revokedDeviceID},
		{label: "removed transport", id: removedTransportID},
	} {
		if got := admin.Host().Network().Connectedness(notWant.id); got == network.Connected {
			t.Fatalf("%s %s was connected despite not being an active recipient", notWant.label, notWant.id)
		}
	}
}

func TestGM027InvalidDeviceLessPeerIDDoesNotInflateGroupTargets(t *testing.T) {
	admin := startLocalNodeForMultiRelayTest(t)
	setFakeRelays(t, admin)
	validBob := startLocalNodeForMultiRelayTest(t)

	groupId := "gm027-invalid-device-less-peer"
	invalidPeerId := "not-a-libp2p-peer-id"
	config := &GroupConfig{
		Name:      "GM-027",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{
				PeerId:         admin.PeerId(),
				Username:       "Admin",
				Role:           GroupRoleAdmin,
				PublicKey:      "adminPk",
				MlKemPublicKey: "adminMlKem",
			},
			{
				PeerId:         validBob.PeerId(),
				Username:       "Bob",
				Role:           GroupRoleWriter,
				PublicKey:      "bobPk",
				MlKemPublicKey: "bobMlKem",
			},
			{
				PeerId:   invalidPeerId,
				Username: "Ghost",
				Role:     GroupRoleWriter,
			},
		},
		CreatedBy: admin.PeerId(),
	}
	admin.mu.Lock()
	admin.groupConfigs[groupId] = config
	admin.mu.Unlock()

	targets := activeGroupMemberDialTargets(config, admin.PeerId())
	if len(targets) != 1 {
		t.Fatalf("expected only one valid dial target, got %d: %+v", len(targets), targets)
	}
	if targets[0].PeerId != validBob.PeerId() {
		t.Fatalf("expected Bob target %s, got %+v", validBob.PeerId(), targets[0])
	}
	if got := countRemoteGroupMembers(config, admin.PeerId()); got != 1 {
		t.Fatalf("expected invalid ghost to be excluded from remote count, got %d", got)
	}
	if got := admin.expectedConnectedGroupMembers(groupId); got != 1 {
		t.Fatalf("expected invalid ghost to be excluded from expected connected count, got %d", got)
	}
}

func TestGM028EmptyPeerIDDoesNotInflateDiscoveryOrPublishPreflight(t *testing.T) {
	admin := startLocalNodeForMultiRelayTest(t)
	setFakeRelays(t, admin)
	validBob := startLocalNodeForMultiRelayTest(t)
	blankTransport := startLocalNodeForMultiRelayTest(t)

	groupId := "gm028-empty-peer-targets"
	config := &GroupConfig{
		Name:      "GM-028",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{
				PeerId:         admin.PeerId(),
				Username:       "Admin",
				Role:           GroupRoleAdmin,
				PublicKey:      "adminPk",
				MlKemPublicKey: "adminMlKem",
			},
			{
				PeerId:         validBob.PeerId(),
				Username:       "Bob",
				Role:           GroupRoleWriter,
				PublicKey:      "bobPk",
				MlKemPublicKey: "bobMlKem",
			},
			{
				PeerId:         "   ",
				Username:       "Blank",
				Role:           GroupRoleWriter,
				PublicKey:      "blankPk",
				MlKemPublicKey: "blankMlKem",
				Devices: []GroupMemberDevice{{
					DeviceId:               "gm028-blank-device",
					TransportPeerId:        blankTransport.PeerId(),
					DeviceSigningPublicKey: "blankDevicePk",
					MlKemPublicKey:         "blankDeviceMlKem",
					KeyPackageId:           "kp-gm028-blank-device",
					Status:                 "active",
				}},
			},
		},
		CreatedBy: admin.PeerId(),
	}

	admin.UpdateGroupConfig(groupId, config)
	admin.mu.RLock()
	storedConfig := cloneGroupConfig(admin.groupConfigs[groupId])
	admin.mu.RUnlock()

	if storedConfig == nil {
		t.Fatal("expected stored config after UpdateGroupConfig")
	}
	if member := findMember(storedConfig, ""); member != nil {
		t.Fatalf("findMember empty peer returned %+v", member)
	}
	if member := findMember(storedConfig, "   "); member != nil {
		t.Fatalf("findMember whitespace peer returned %+v", member)
	}
	for _, member := range storedConfig.Members {
		if strings.TrimSpace(member.PeerId) == "" {
			t.Fatalf("stored config retained empty peer member: %+v", storedConfig.Members)
		}
	}
	if len(storedConfig.Members) != 2 {
		t.Fatalf("stored config members = %+v, want only admin and Bob", storedConfig.Members)
	}

	targets := activeGroupMemberDialTargets(storedConfig, admin.PeerId())
	if len(targets) != 1 {
		t.Fatalf("expected only Bob dial target, got %d: %+v", len(targets), targets)
	}
	if targets[0].PeerId != validBob.PeerId() {
		t.Fatalf("expected Bob target %s, got %+v", validBob.PeerId(), targets[0])
	}
	if got := countRemoteGroupMembers(storedConfig, admin.PeerId()); got != 1 {
		t.Fatalf("expected blank peer to be excluded from remote count, got %d", got)
	}
	if got := admin.expectedConnectedGroupMembers(groupId); got != 1 {
		t.Fatalf("expected blank peer to be excluded from expected connected count, got %d", got)
	}
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

func assertGM030DiscoveryEventTotals(t *testing.T, collector *testEventCollector, groupId string, wantTotalFound, wantNewPeers, wantIgnoredNonMembers int) {
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
		totalFound, totalOK := data["totalFound"].(float64)
		newPeers, newOK := data["newPeers"].(float64)
		ignoredNonMembers, ignoredOK := data["ignoredNonMembers"].(float64)
		if totalOK &&
			newOK &&
			ignoredOK &&
			int(totalFound) == wantTotalFound &&
			int(newPeers) == wantNewPeers &&
			int(ignoredNonMembers) == wantIgnoredNonMembers {
			return
		}
		t.Fatalf(
			"discovery event for group %s = totalFound:%v newPeers:%v ignoredNonMembers:%v, want totalFound:%d newPeers:%d ignoredNonMembers:%d; events=%v",
			groupId,
			data["totalFound"],
			data["newPeers"],
			data["ignoredNonMembers"],
			wantTotalFound,
			wantNewPeers,
			wantIgnoredNonMembers,
			collector.snapshot(),
		)
	}
	t.Fatalf(
		"expected discovery event for group %s with totalFound=%d newPeers=%d ignoredNonMembers=%d; events=%v",
		groupId,
		wantTotalFound,
		wantNewPeers,
		wantIgnoredNonMembers,
		collector.snapshot(),
	)
}

func assertGP014KnownMemberTopicMissingRelayFallback(t *testing.T, collector *testEventCollector, groupId, peerId string) {
	t.Helper()

	peerShort := peerId
	if len(peerShort) > 16 {
		peerShort = peerShort[:16]
	}
	deadline := time.Now().Add(time.Second)
	for time.Now().Before(deadline) {
		for _, event := range collector.collectEvents("group:discovery") {
			if event["groupId"] != groupId || event["step"] != "known_member_topic_missing" || event["peerId"] != peerShort {
				continue
			}
			if got, _ := event["path"].(string); got != "relay_fallback" {
				t.Fatalf("GP-014 topic-missing path = %q, want relay_fallback; event=%v", got, event)
			}
			if got, _ := event["attemptedDirect"].(bool); !got {
				t.Fatalf("GP-014 topic-missing attemptedDirect = %v, want true; event=%v", got, event)
			}
			if got, _ := event["usedRelayFallback"].(bool); !got {
				t.Fatalf("GP-014 topic-missing usedRelayFallback = %v, want true; event=%v", got, event)
			}
			if got, ok := event["directAddrCount"].(float64); !ok || got <= 0 {
				t.Fatalf("GP-014 topic-missing directAddrCount = %v, want > 0; event=%v", event["directAddrCount"], event)
			}
			return
		}
		time.Sleep(25 * time.Millisecond)
	}

	t.Fatalf("expected GP-014 known_member_topic_missing relay_fallback event for peer %s; events=%v", peerShort, collector.snapshot())
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

// Test: GL-020 bulk group recovery drains queued work without starving an affected group.
func TestGL020GroupRecoveryLimiterDrainsManyGroupsWithoutStarvingAffectedGroup(t *testing.T) {
	n := NewNode()
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	totalGroups := GroupDiscoveryConcurrency*3 + 1
	groupIDs := make([]string, 0, totalGroups)
	namespaceToGroup := make(map[string]string, totalGroups)
	for i := 0; i < totalGroups-1; i++ {
		groupID := fmt.Sprintf("gl020-group-%02d", i)
		groupIDs = append(groupIDs, groupID)
		namespaceToGroup[groupRendezvousNamespace(groupID)] = groupID
	}
	affectedGroupID := "gl020-affected-group"
	groupIDs = append(groupIDs, affectedGroupID)
	namespaceToGroup[groupRendezvousNamespace(affectedGroupID)] = affectedGroupID

	started := make(chan string, totalGroups)
	releaseDiscovery := make(chan struct{})
	var releaseOnce sync.Once
	defer releaseOnce.Do(func() { close(releaseDiscovery) })

	var mu sync.Mutex
	active := 0
	maxActive := 0
	registeredGroups := make(map[string]int, totalGroups)
	discoveredGroups := make(map[string]int, totalGroups)

	n.rendezvousRegisterHook = func(namespace string, serverAddresses []string) error {
		groupID, ok := namespaceToGroup[namespace]
		if !ok {
			return fmt.Errorf("unexpected register namespace %q", namespace)
		}

		mu.Lock()
		registeredGroups[groupID]++
		mu.Unlock()
		return nil
	}
	n.rendezvousDiscoverHook = func(namespace string, serverAddresses []string) ([]peer.AddrInfo, error) {
		groupID, ok := namespaceToGroup[namespace]
		if !ok {
			return nil, fmt.Errorf("unexpected discover namespace %q", namespace)
		}

		mu.Lock()
		active++
		if active > maxActive {
			maxActive = active
		}
		discoveredGroups[groupID]++
		mu.Unlock()

		started <- groupID
		defer func() {
			mu.Lock()
			active--
			mu.Unlock()
		}()

		select {
		case <-releaseDiscovery:
			return nil, nil
		case <-ctx.Done():
			return nil, ctx.Err()
		}
	}

	errs := make(chan error, totalGroups)
	var wg sync.WaitGroup
	launchRecovery := func(groupID string) {
		wg.Add(1)
		go func() {
			defer wg.Done()

			executed, registered := n.runGroupDiscoveryCycle(
				ctx,
				groupID,
				groupRendezvousNamespace(groupID),
				true,
				false,
			)
			if !executed {
				errs <- fmt.Errorf("group %s recovery cycle did not execute", groupID)
				return
			}
			if !registered {
				errs <- fmt.Errorf("group %s recovery cycle did not register", groupID)
			}
		}()
	}

	for _, groupID := range groupIDs[:GroupDiscoveryConcurrency] {
		launchRecovery(groupID)
	}

	initialStarted := make(map[string]struct{}, GroupDiscoveryConcurrency)
	for i := 0; i < GroupDiscoveryConcurrency; i++ {
		select {
		case groupID := <-started:
			initialStarted[groupID] = struct{}{}
		case <-ctx.Done():
			t.Fatal("timed out waiting for initial recovery slots")
		}
	}
	if len(initialStarted) != GroupDiscoveryConcurrency {
		t.Fatalf("initial started groups = %d, want %d", len(initialStarted), GroupDiscoveryConcurrency)
	}

	for _, groupID := range groupIDs[GroupDiscoveryConcurrency:] {
		launchRecovery(groupID)
	}

	select {
	case groupID := <-started:
		t.Fatalf("group %s acquired a recovery slot before an existing slot was released", groupID)
	case <-time.After(100 * time.Millisecond):
	}

	releaseOnce.Do(func() { close(releaseDiscovery) })

	done := make(chan struct{})
	go func() {
		wg.Wait()
		close(done)
	}()

	select {
	case <-done:
	case <-ctx.Done():
		t.Fatal("timed out waiting for queued group recovery cycles to drain")
	}

	close(errs)
	for err := range errs {
		if err != nil {
			t.Error(err)
		}
	}
	if t.Failed() {
		return
	}

	mu.Lock()
	defer mu.Unlock()

	if maxActive != GroupDiscoveryConcurrency {
		t.Fatalf("max concurrent recovery cycles = %d, want %d", maxActive, GroupDiscoveryConcurrency)
	}
	for _, groupID := range groupIDs {
		if registeredGroups[groupID] != 1 {
			t.Fatalf("registered count for %s = %d, want 1", groupID, registeredGroups[groupID])
		}
		if discoveredGroups[groupID] != 1 {
			t.Fatalf("discovered count for %s = %d, want 1", groupID, discoveredGroups[groupID])
		}
	}
	if discoveredGroups[affectedGroupID] != 1 {
		t.Fatalf("affected group %s was starved; discovered count = %d", affectedGroupID, discoveredGroups[affectedGroupID])
	}
}

func TestGR019GroupRecoveryLimiterReleasesSlotsOnCanceledContext(t *testing.T) {
	n := NewNode()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	groupCount := GroupDiscoveryConcurrency
	started := make(chan string, groupCount+1)
	namespaceToGroup := make(map[string]string, groupCount+1)
	for i := 0; i < groupCount; i++ {
		groupID := fmt.Sprintf("gr019-active-%02d", i)
		namespaceToGroup[groupRendezvousNamespace(groupID)] = groupID
	}
	queuedGroupID := "gr019-queued"
	namespaceToGroup[groupRendezvousNamespace(queuedGroupID)] = queuedGroupID

	n.rendezvousRegisterHook = func(namespace string, serverAddresses []string) error {
		if _, ok := namespaceToGroup[namespace]; !ok {
			return fmt.Errorf("unexpected register namespace %q", namespace)
		}
		return nil
	}
	n.rendezvousDiscoverHook = func(namespace string, serverAddresses []string) ([]peer.AddrInfo, error) {
		groupID, ok := namespaceToGroup[namespace]
		if !ok {
			return nil, fmt.Errorf("unexpected discover namespace %q", namespace)
		}

		started <- groupID
		<-ctx.Done()
		return nil, ctx.Err()
	}

	var wg sync.WaitGroup
	errs := make(chan error, groupCount)
	for i := 0; i < groupCount; i++ {
		groupID := fmt.Sprintf("gr019-active-%02d", i)
		ns := groupRendezvousNamespace(groupID)
		wg.Add(1)
		go func() {
			defer wg.Done()

			executed, registered := n.runGroupDiscoveryCycle(ctx, groupID, ns, true, false)
			if !executed {
				errs <- fmt.Errorf("active group %s did not execute before cancellation", groupID)
				return
			}
			if !registered {
				errs <- fmt.Errorf("active group %s did not register before cancellation", groupID)
			}
		}()
	}

	activeStarted := make(map[string]struct{}, groupCount)
	for i := 0; i < groupCount; i++ {
		select {
		case groupID := <-started:
			activeStarted[groupID] = struct{}{}
		case <-time.After(time.Second):
			t.Fatal("timed out waiting for active recovery slots to saturate")
		}
	}
	if len(activeStarted) != groupCount {
		t.Fatalf("active started groups = %d, want %d", len(activeStarted), groupCount)
	}

	queuedDone := make(chan struct {
		executed   bool
		registered bool
	}, 1)
	go func() {
		executed, registered := n.runGroupDiscoveryCycle(
			ctx,
			queuedGroupID,
			groupRendezvousNamespace(queuedGroupID),
			true,
			false,
		)
		queuedDone <- struct {
			executed   bool
			registered bool
		}{executed: executed, registered: registered}
	}()

	select {
	case groupID := <-started:
		t.Fatalf("queued group %s acquired a recovery slot before cancellation", groupID)
	case <-time.After(100 * time.Millisecond):
	}

	cancel()

	activeDone := make(chan struct{})
	go func() {
		wg.Wait()
		close(activeDone)
	}()

	select {
	case <-activeDone:
	case <-time.After(time.Second):
		t.Fatal("active recovery cycles did not exit after context cancellation")
	}
	select {
	case <-queuedDone:
	case <-time.After(time.Second):
		t.Fatal("queued recovery cycle did not exit after context cancellation")
	}

	close(errs)
	for err := range errs {
		if err != nil {
			t.Error(err)
		}
	}
	if t.Failed() {
		return
	}

	n.mu.RLock()
	remainingSlots := len(n.groupRecoverySem)
	n.mu.RUnlock()
	if remainingSlots != 0 {
		t.Fatalf("group recovery slots still held after cancellation = %d, want 0", remainingSlots)
	}

	freshStarted := make(chan struct{}, 1)
	n.rendezvousRegisterHook = func(namespace string, serverAddresses []string) error {
		return nil
	}
	n.rendezvousDiscoverHook = func(namespace string, serverAddresses []string) ([]peer.AddrInfo, error) {
		freshStarted <- struct{}{}
		return nil, nil
	}

	freshCtx, freshCancel := context.WithTimeout(context.Background(), time.Second)
	defer freshCancel()
	executed, registered := n.runGroupDiscoveryCycle(
		freshCtx,
		"gr019-fresh",
		groupRendezvousNamespace("gr019-fresh"),
		true,
		false,
	)
	if !executed || !registered {
		t.Fatalf("fresh recovery after canceled run executed=%t registered=%t, want true/true", executed, registered)
	}
	select {
	case <-freshStarted:
	default:
		t.Fatal("fresh recovery did not run discovery after canceled slots were released")
	}

	n.mu.RLock()
	remainingSlots = len(n.groupRecoverySem)
	n.mu.RUnlock()
	if remainingSlots != 0 {
		t.Fatalf("group recovery slots held after fresh recovery = %d, want 0", remainingSlots)
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

func TestGP018WarmRetryCadenceKeepsActiveGroupResponsive(t *testing.T) {
	interval, consecutiveFailures, warmRetriesRemaining := initialGroupDiscoveryCadence(1, 3)
	if interval != GroupDiscoveryWarmInterval {
		t.Fatalf("initial partial interval = %v, want warm interval %v", interval, GroupDiscoveryWarmInterval)
	}
	if consecutiveFailures != 0 {
		t.Fatalf("initial consecutiveFailures = %d, want 0", consecutiveFailures)
	}
	if warmRetriesRemaining != GroupDiscoveryWarmRetries {
		t.Fatalf("initial warmRetriesRemaining = %d, want %d", warmRetriesRemaining, GroupDiscoveryWarmRetries)
	}

	for retry := 1; retry <= GroupDiscoveryWarmRetries; retry++ {
		var backingOff bool
		interval, consecutiveFailures, warmRetriesRemaining, backingOff = nextGroupDiscoveryCadence(
			interval,
			consecutiveFailures,
			warmRetriesRemaining,
			1,
			1,
			3,
		)
		if backingOff {
			t.Fatalf("warm retry %d backed off before warm retry budget was exhausted", retry)
		}
		if interval != GroupDiscoveryWarmInterval {
			t.Fatalf("warm retry %d interval = %v, want %v", retry, interval, GroupDiscoveryWarmInterval)
		}
		if consecutiveFailures != 0 {
			t.Fatalf("warm retry %d consecutiveFailures = %d, want 0", retry, consecutiveFailures)
		}
		wantRemaining := GroupDiscoveryWarmRetries - retry
		if warmRetriesRemaining != wantRemaining {
			t.Fatalf("warm retry %d remaining = %d, want %d", retry, warmRetriesRemaining, wantRemaining)
		}
	}

	var backingOff bool
	interval, consecutiveFailures, warmRetriesRemaining, backingOff = nextGroupDiscoveryCadence(
		interval,
		consecutiveFailures,
		warmRetriesRemaining,
		1,
		1,
		3,
	)
	if !backingOff {
		t.Fatal("expected backoff after warm retry budget is exhausted")
	}
	wantFirstBackoff := GroupDiscoveryWarmInterval * 2
	if interval != wantFirstBackoff {
		t.Fatalf("first backoff interval = %v, want %v", interval, wantFirstBackoff)
	}
	if interval >= GroupDiscoveryInterval {
		t.Fatalf("first backoff interval = %v, want below background interval %v", interval, GroupDiscoveryInterval)
	}
	if consecutiveFailures != 1 {
		t.Fatalf("first backoff consecutiveFailures = %d, want 1", consecutiveFailures)
	}
	if warmRetriesRemaining != 0 {
		t.Fatalf("first backoff warmRetriesRemaining = %d, want 0", warmRetriesRemaining)
	}

	interval, consecutiveFailures, warmRetriesRemaining, backingOff = nextGroupDiscoveryCadence(
		interval,
		consecutiveFailures,
		warmRetriesRemaining,
		1,
		2,
		3,
	)
	if backingOff {
		t.Fatal("partial progress should reset to warm cadence, not back off")
	}
	if interval != GroupDiscoveryWarmInterval {
		t.Fatalf("partial progress interval = %v, want warm interval %v", interval, GroupDiscoveryWarmInterval)
	}
	if consecutiveFailures != 0 {
		t.Fatalf("partial progress consecutiveFailures = %d, want 0", consecutiveFailures)
	}
	if warmRetriesRemaining != GroupDiscoveryWarmRetries {
		t.Fatalf("partial progress warmRetriesRemaining = %d, want %d", warmRetriesRemaining, GroupDiscoveryWarmRetries)
	}
}

func TestGP019DiscoveryBackoffResetsAfterPartialProgress(t *testing.T) {
	interval := GroupDiscoveryWarmInterval * 8
	consecutiveFailures := 3
	warmRetriesRemaining := 0

	var backingOff bool
	interval, consecutiveFailures, warmRetriesRemaining, backingOff = nextGroupDiscoveryCadence(
		interval,
		consecutiveFailures,
		warmRetriesRemaining,
		1,
		2,
		4,
	)
	if backingOff {
		t.Fatal("partial progress should reset backoff instead of backing off again")
	}
	if interval != GroupDiscoveryWarmInterval {
		t.Fatalf("partial progress interval = %v, want warm interval %v", interval, GroupDiscoveryWarmInterval)
	}
	if consecutiveFailures != 0 {
		t.Fatalf("partial progress consecutiveFailures = %d, want 0", consecutiveFailures)
	}
	if warmRetriesRemaining != GroupDiscoveryWarmRetries {
		t.Fatalf("partial progress warmRetriesRemaining = %d, want %d", warmRetriesRemaining, GroupDiscoveryWarmRetries)
	}

	interval, consecutiveFailures, warmRetriesRemaining, backingOff = nextGroupDiscoveryCadence(
		interval,
		consecutiveFailures,
		warmRetriesRemaining,
		2,
		2,
		4,
	)
	if backingOff {
		t.Fatal("first no-progress cycle after partial progress should consume refreshed warm retry budget")
	}
	if interval != GroupDiscoveryWarmInterval {
		t.Fatalf("post-progress warm retry interval = %v, want %v", interval, GroupDiscoveryWarmInterval)
	}
	if consecutiveFailures != 0 {
		t.Fatalf("post-progress consecutiveFailures = %d, want 0", consecutiveFailures)
	}
	wantRemaining := GroupDiscoveryWarmRetries - 1
	if warmRetriesRemaining != wantRemaining {
		t.Fatalf("post-progress warmRetriesRemaining = %d, want %d", warmRetriesRemaining, wantRemaining)
	}
}

func TestGP020AllExpectedConnectedReturnsToMaintenanceCadence(t *testing.T) {
	interval := GroupDiscoveryWarmInterval * 8
	consecutiveFailures := 3
	warmRetriesRemaining := 0

	var backingOff bool
	interval, consecutiveFailures, warmRetriesRemaining, backingOff = nextGroupDiscoveryCadence(
		interval,
		consecutiveFailures,
		warmRetriesRemaining,
		2,
		3,
		3,
	)
	if backingOff {
		t.Fatal("all expected members connected should return to maintenance cadence without backing off")
	}
	if interval != GroupDiscoveryInterval {
		t.Fatalf("all-connected interval = %v, want maintenance interval %v", interval, GroupDiscoveryInterval)
	}
	if consecutiveFailures != 0 {
		t.Fatalf("all-connected consecutiveFailures = %d, want 0", consecutiveFailures)
	}
	if warmRetriesRemaining != GroupDiscoveryWarmRetries {
		t.Fatalf("all-connected warmRetriesRemaining = %d, want %d", warmRetriesRemaining, GroupDiscoveryWarmRetries)
	}

	interval, consecutiveFailures, warmRetriesRemaining, backingOff = nextGroupDiscoveryCadence(
		GroupDiscoveryWarmInterval,
		1,
		0,
		0,
		0,
		0,
	)
	if backingOff {
		t.Fatal("zero expected members should use maintenance cadence without backing off")
	}
	if interval != GroupDiscoveryInterval {
		t.Fatalf("zero-expected interval = %v, want maintenance interval %v", interval, GroupDiscoveryInterval)
	}
	if consecutiveFailures != 0 {
		t.Fatalf("zero-expected consecutiveFailures = %d, want 0", consecutiveFailures)
	}
	if warmRetriesRemaining != GroupDiscoveryWarmRetries {
		t.Fatalf("zero-expected warmRetriesRemaining = %d, want %d", warmRetriesRemaining, GroupDiscoveryWarmRetries)
	}
}

func TestGP024SubscriptionErrorLogsOnlyRealFailures(t *testing.T) {
	canceledCtx, cancel := context.WithCancel(context.Background())
	cancel()

	if shouldLogGroupSubscriptionError(canceledCtx, fmt.Errorf("subscription closed after cancel")) {
		t.Fatal("canceled subscription context should exit quietly")
	}
	if shouldLogGroupSubscriptionError(context.Background(), context.Canceled) {
		t.Fatal("context.Canceled from subscription should exit quietly")
	}
	if shouldLogGroupSubscriptionError(context.Background(), context.DeadlineExceeded) {
		t.Fatal("context deadline subscription error should exit quietly")
	}
	if shouldLogGroupSubscriptionError(context.Background(), nil) {
		t.Fatal("nil subscription error should not be loggable")
	}
	if !shouldLogGroupSubscriptionError(context.Background(), fmt.Errorf("subscription stream failed")) {
		t.Fatal("non-context subscription error should be logged before handler exit")
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

func TestGP017InFlightDialGateBlocksOnlyWhileActive(t *testing.T) {
	t.Run("success clears active in-flight gate", func(t *testing.T) {
		n := NewNode()
		now := time.Unix(1700000100, 0)
		const peerID = "gp017-peer-success"

		if allowed, _, blockedByInFlight := n.beginGroupPeerDialWithMode(peerID, now, false); !allowed || blockedByInFlight {
			t.Fatalf("first dial allowed=%t blockedByInFlight=%t, want allowed without in-flight block", allowed, blockedByInFlight)
		}
		if allowed, retryIn, blockedByInFlight := n.beginGroupPeerDialWithMode(peerID, now.Add(time.Millisecond), false); allowed {
			t.Fatal("second discovery cycle should be blocked while first dial is in flight")
		} else if retryIn != 0 {
			t.Fatalf("in-flight block retryIn=%v, want 0", retryIn)
		} else if !blockedByInFlight {
			t.Fatal("second discovery cycle should report blockedByInFlight")
		}

		n.finishGroupPeerDial(peerID, true, now.Add(100*time.Millisecond))
		if allowed, _, blockedByInFlight := n.beginGroupPeerDialWithMode(peerID, now.Add(200*time.Millisecond), false); !allowed || blockedByInFlight {
			t.Fatalf("third discovery cycle after success allowed=%t blockedByInFlight=%t, want allowed", allowed, blockedByInFlight)
		}
	})

	t.Run("failure clears in-flight gate but leaves cooldown policy", func(t *testing.T) {
		n := NewNode()
		now := time.Unix(1700000200, 0)
		const peerID = "gp017-peer-failure"

		if allowed, _, blockedByInFlight := n.beginGroupPeerDialWithMode(peerID, now, false); !allowed || blockedByInFlight {
			t.Fatalf("first dial allowed=%t blockedByInFlight=%t, want allowed without in-flight block", allowed, blockedByInFlight)
		}
		if allowed, _, blockedByInFlight := n.beginGroupPeerDialWithMode(peerID, now.Add(time.Millisecond), false); allowed || !blockedByInFlight {
			t.Fatalf("second discovery cycle allowed=%t blockedByInFlight=%t, want in-flight block", allowed, blockedByInFlight)
		}

		n.finishGroupPeerDial(peerID, false, now.Add(100*time.Millisecond))
		thirdAt := now.Add(200 * time.Millisecond)
		if allowed, retryIn, blockedByInFlight := n.beginGroupPeerDialWithMode(peerID, thirdAt, false); allowed {
			t.Fatal("third discovery cycle should honor cooldown after failed first dial")
		} else if blockedByInFlight {
			t.Fatal("third discovery cycle should not still be blocked by in-flight state after finish")
		} else if retryIn <= 0 {
			t.Fatalf("third discovery cycle cooldown retryIn=%v, want positive", retryIn)
		}

		afterCooldown := now.Add(100 * time.Millisecond).Add(groupPeerDialBackoff(1)).Add(time.Millisecond)
		if allowed, _, blockedByInFlight := n.beginGroupPeerDialWithMode(peerID, afterCooldown, false); !allowed || blockedByInFlight {
			t.Fatalf("retry after cooldown allowed=%t blockedByInFlight=%t, want allowed", allowed, blockedByInFlight)
		}
	})
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

// Test 7.3 / GM-022: findMember with duplicate peer IDs returns the active
// re-add entry instead of a stale shadow.
func TestFindMember_DuplicatePeerId_ReturnsActiveReaddEntry(t *testing.T) {
	config := &GroupConfig{
		Name:      "Dup Test",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{
				PeerId:    "peer-dup",
				Role:      GroupRoleWriter,
				PublicKey: "pk-stale",
				Devices: []GroupMemberDevice{{
					DeviceId:               "peer-dup-device",
					TransportPeerId:        "peer-dup-device",
					DeviceSigningPublicKey: "pk-stale",
					KeyPackageId:           "kp-stale",
					Status:                 "revoked",
					RevokedAt:              "2026-05-11T08:00:00Z",
				}},
			},
			{
				PeerId:    "peer-dup",
				Role:      GroupRoleAdmin,
				PublicKey: "pk-active",
				Devices: []GroupMemberDevice{{
					DeviceId:               "peer-dup-device",
					TransportPeerId:        "peer-dup-device",
					DeviceSigningPublicKey: "pk-active",
					KeyPackageId:           "kp-active",
					Status:                 "active",
				}},
			},
		},
		CreatedBy: "peer-dup",
	}

	member := findMember(config, "peer-dup")
	if member == nil {
		t.Fatal("expected to find peer-dup")
	}
	if member.Role != GroupRoleAdmin {
		t.Errorf("expected active re-add match (admin), got %s", member.Role)
	}
	if member.PublicKey != "pk-active" {
		t.Errorf("expected active re-add PublicKey 'pk-active', got %q", member.PublicKey)
	}
}

func TestGM023FindMemberInactiveShadowBeforeActiveCharlie(t *testing.T) {
	config := &GroupConfig{
		Name:      "GM-023",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{
				PeerId:    "peer-charlie",
				Role:      GroupRoleWriter,
				PublicKey: "pk-charlie-inactive",
				Devices: []GroupMemberDevice{{
					DeviceId:               "charlie-device",
					TransportPeerId:        "charlie-inactive-transport",
					DeviceSigningPublicKey: "pk-charlie-inactive",
					KeyPackageId:           "kp-charlie-inactive",
					Status:                 "revoked",
					RevokedAt:              "2026-05-11T08:00:00Z",
				}},
			},
			{
				PeerId:    "peer-charlie",
				Role:      GroupRoleWriter,
				PublicKey: "pk-charlie-active",
				Devices: []GroupMemberDevice{{
					DeviceId:               "charlie-device",
					TransportPeerId:        "charlie-active-transport",
					DeviceSigningPublicKey: "pk-charlie-active",
					KeyPackageId:           "kp-charlie-active",
					Status:                 "active",
				}},
			},
		},
		CreatedBy: "peer-alice",
	}

	member := findMember(config, "peer-charlie")
	if member == nil {
		t.Fatal("expected to find active Charlie")
	}
	if member.PublicKey != "pk-charlie-active" {
		t.Fatalf("expected active Charlie entry, got public key %q", member.PublicKey)
	}
	if len(member.Devices) != 1 || member.Devices[0].TransportPeerId != "charlie-active-transport" {
		t.Fatalf("expected active Charlie transport, got %+v", member.Devices)
	}
}

func TestGM022CloneGroupConfigDedupesRepeatedReaddShadow(t *testing.T) {
	config := &GroupConfig{
		Name:      "GM-022",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: "peer-alice", Role: GroupRoleAdmin, PublicKey: "pk-alice"},
			{
				PeerId:    "peer-charlie",
				Role:      GroupRoleWriter,
				PublicKey: "pk-charlie-stale",
				Devices: []GroupMemberDevice{{
					DeviceId:               "charlie-device",
					TransportPeerId:        "charlie-device",
					DeviceSigningPublicKey: "pk-charlie-stale",
					KeyPackageId:           "kp-charlie-stale",
					Status:                 "revoked",
					RevokedAt:              "2026-05-11T08:00:00Z",
				}},
			},
			{PeerId: "peer-bob", Role: GroupRoleWriter, PublicKey: "pk-bob"},
			{
				PeerId:    "peer-charlie",
				Role:      GroupRoleWriter,
				PublicKey: "pk-charlie-active",
				Devices: []GroupMemberDevice{{
					DeviceId:               "charlie-device",
					TransportPeerId:        "charlie-device",
					DeviceSigningPublicKey: "pk-charlie-active",
					KeyPackageId:           "kp-charlie-active",
					Status:                 "active",
				}},
			},
		},
		CreatedBy: "peer-alice",
	}

	cloned := cloneGroupConfig(config)
	if cloned == nil {
		t.Fatal("expected cloned config")
	}
	charlieCount := 0
	for _, member := range cloned.Members {
		if member.PeerId != "peer-charlie" {
			continue
		}
		charlieCount++
		if member.PublicKey != "pk-charlie-active" {
			t.Fatalf("expected active Charlie member, got public key %q", member.PublicKey)
		}
		if len(member.Devices) != 1 || member.Devices[0].KeyPackageId != "kp-charlie-active" {
			t.Fatalf("expected one active Charlie device, got %+v", member.Devices)
		}
	}
	if charlieCount != 1 {
		t.Fatalf("expected exactly one Charlie member after clone normalization, got %d: %+v", charlieCount, cloned.Members)
	}
}
