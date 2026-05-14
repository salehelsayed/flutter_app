package node

import (
	"bytes"
	"context"
	"encoding/json"
	"log"
	"strings"
	"sync"
	"testing"
	"time"

	pubsub "github.com/libp2p/go-libp2p-pubsub"
	pb "github.com/libp2p/go-libp2p-pubsub/pb"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"

	mcrypto "github.com/mknoon/go-mknoon/crypto"
	"github.com/mknoon/go-mknoon/internal"
)

func TestLP002UnauthorizedRawPubSubRejectsBeforeAcceptAndForward(t *testing.T) {
	runRemovedPeerRawPubSubRejectsBeforeAcceptAndForward(t, "lp002", "LP002")
}

func TestRP017RemovedPeerContinuedPublishesAreRejectedBeforeAcceptAndForward(t *testing.T) {
	runRemovedPeerRawPubSubRejectsBeforeAcceptAndForward(t, "rp017", "RP017")
}

func TestGA002NonMemberCannotPublishValidEnvelope(t *testing.T) {
	nonMemberPriv, nonMemberPub := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeX := startLocalNodeForMultiRelayTest(t)
	nodeACapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)

	groupId := "ga002-non-member-publish"
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	currentConfig := &GroupConfig{
		Name:      "GA002 Current Private Chat",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: "nodeAPubKey"},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: "nodeBPubKey"},
		},
		CreatedBy: nodeA.PeerId(),
	}
	stalePublisherConfig := &GroupConfig{
		Name:      "GA002 Stale Publisher View",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeX.PeerId(), Role: GroupRoleWriter, PublicKey: nonMemberPub},
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: "nodeAPubKey"},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: "nodeBPubKey"},
		},
		CreatedBy: nodeA.PeerId(),
	}

	if err := nodeX.JoinGroupTopic(groupId, stalePublisherConfig, keyInfo); err != nil {
		t.Fatalf("nodeX JoinGroupTopic: %v", err)
	}
	if err := nodeA.JoinGroupTopic(groupId, currentConfig, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, currentConfig, keyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}

	connectLocalGroupNodes(t, nodeX, nodeA)
	connectLocalGroupNodes(t, nodeX, nodeB)
	connectLocalGroupNodes(t, nodeA, nodeB)
	waitForGroupTopicPeerCount(t, nodeX, groupId, 2, 3*time.Second)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 2, 3*time.Second)
	waitForGroupTopicPeerCount(t, nodeB, groupId, 2, 3*time.Second)

	plaintextMarker := "ga002-non-member-plaintext"
	envelopeJSON := buildTestEnvelopeWithPlaintext(
		t,
		groupId,
		"group_message",
		nodeX.PeerId(),
		nonMemberPriv,
		nonMemberPub,
		groupKey,
		keyInfo.KeyEpoch,
		`{"text":"`+plaintextMarker+`","timestamp":"2026-05-12T19:34:10Z"}`,
	)

	if result := validateGroupEnvelopeForTransportPeer(envelopeJSON, groupId, currentConfig, keyInfo, nodeX.PeerId()); result != "reject:non_member" {
		t.Fatalf("pure validator = %s, want reject:non_member", result)
	}

	baselineA := len(nodeACapture.snapshot())
	baselineB := len(nodeBCapture.snapshot())
	publishRawGroupEnvelope(t, nodeX, groupId, envelopeJSON)

	waitForCollectedValidationReject(t, nodeACapture, baselineA, "non_member", keyInfo.KeyEpoch, 5*time.Second)
	waitForCollectedValidationReject(t, nodeBCapture, baselineB, "non_member", keyInfo.KeyEpoch, 5*time.Second)

	for _, check := range []struct {
		label     string
		collector *testEventCollector
		baseline  int
	}{
		{label: "node A", collector: nodeACapture, baseline: baselineA},
		{label: "node B", collector: nodeBCapture, baseline: baselineB},
	} {
		for _, forbidden := range []string{
			`"event":"group_message:received"`,
			`"event":"group_reaction:received"`,
			`"event":"group:decryption_failed"`,
			`"event":"group:payload_parse_failed"`,
			plaintextMarker,
		} {
			t.Run(check.label+"/"+forbidden, func(t *testing.T) {
				assertNoCollectedEventContainingAfter(t, check.collector, check.baseline, forbidden, 500*time.Millisecond)
			})
		}
	}
}

func TestGA006SenderTransportPeerMismatchRejects(t *testing.T) {
	privB, pubB := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeX := startLocalNodeForMultiRelayTest(t)
	nodeACapture := &testEventCollector{}
	nodeA := startLocalNodeForMultiRelayTestWithCollector(t, nodeACapture)
	nodeB := startLocalNodeForMultiRelayTest(t)

	groupId := "ga006-sender-transport-peer-mismatch"
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	currentConfig := &GroupConfig{
		Name:      "GA006 Current Private Chat",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: "nodeAPubKey"},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: pubB},
		},
		CreatedBy: nodeA.PeerId(),
	}
	publisherConfig := &GroupConfig{
		Name:      "GA006 Publisher View",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeX.PeerId(), Role: GroupRoleWriter, PublicKey: "nodeXPubKey"},
			{PeerId: nodeA.PeerId(), Role: GroupRoleAdmin, PublicKey: "nodeAPubKey"},
			{PeerId: nodeB.PeerId(), Role: GroupRoleWriter, PublicKey: pubB},
		},
		CreatedBy: nodeA.PeerId(),
	}

	if err := nodeX.JoinGroupTopic(groupId, publisherConfig, keyInfo); err != nil {
		t.Fatalf("nodeX JoinGroupTopic: %v", err)
	}
	if err := nodeA.JoinGroupTopic(groupId, currentConfig, keyInfo); err != nil {
		t.Fatalf("nodeA JoinGroupTopic: %v", err)
	}

	connectLocalGroupNodes(t, nodeX, nodeA)
	waitForGroupTopicPeerCount(t, nodeX, groupId, 1, 3*time.Second)
	waitForGroupTopicPeerCount(t, nodeA, groupId, 1, 3*time.Second)

	plaintextMarker := "ga006-transport-peer-mismatch"
	envelopeJSON := buildTestEnvelopeWithPlaintext(
		t,
		groupId,
		"group_message",
		nodeB.PeerId(),
		privB,
		pubB,
		groupKey,
		keyInfo.KeyEpoch,
		`{"text":"`+plaintextMarker+`","timestamp":"2026-05-12T20:01:00Z"}`,
	)
	if result := validateGroupEnvelopeForTransportPeer(envelopeJSON, groupId, currentConfig, keyInfo, nodeB.PeerId()); result != "accept" {
		t.Fatalf("pure validator from B transport = %s, want accept", result)
	}
	if result := validateGroupEnvelopeForTransportPeer(envelopeJSON, groupId, currentConfig, keyInfo, nodeX.PeerId()); result != "reject:peer_mismatch" {
		t.Fatalf("pure validator from X transport = %s, want reject:peer_mismatch", result)
	}

	if err := nodeX.pubsub.UnregisterTopicValidator(GroupTopicPrefix + groupId); err != nil {
		t.Fatalf("nodeX unregister local validator before GA006 raw publish: %v", err)
	}

	baselineA := len(nodeACapture.snapshot())
	publishRawGroupEnvelope(t, nodeX, groupId, envelopeJSON)
	waitForCollectedValidationReject(t, nodeACapture, baselineA, "peer_mismatch", keyInfo.KeyEpoch, 5*time.Second)

	for _, forbidden := range []string{
		`"event":"group_message:received"`,
		`"event":"group_reaction:received"`,
		`"event":"group:decryption_failed"`,
		`"event":"group:payload_parse_failed"`,
		plaintextMarker,
	} {
		t.Run("peer mismatch rejected/"+forbidden, func(t *testing.T) {
			assertNoCollectedEventContainingAfter(t, nodeACapture, baselineA, forbidden, 500*time.Millisecond)
		})
	}
}

func runRemovedPeerRawPubSubRejectsBeforeAcceptAndForward(t *testing.T, idPrefix, label string) {
	removedPriv, removedPub := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	nodeX := startLocalNodeForMultiRelayTest(t)
	nodeBCapture := &testEventCollector{}
	nodeB := startLocalNodeForMultiRelayTestWithCollector(t, nodeBCapture)
	nodeCCapture := &testEventCollector{}
	nodeC := startLocalNodeForMultiRelayTestWithCollector(t, nodeCCapture)

	groupId := idPrefix + "-raw-pubsub-forward"
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	currentConfig := &GroupConfig{
		Name:      label + " Current Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeB.PeerId(), Role: GroupRoleAdmin, PublicKey: "nodeBPubKey"},
			{PeerId: nodeC.PeerId(), Role: GroupRoleWriter, PublicKey: "nodeCPubKey"},
		},
		CreatedBy: nodeB.PeerId(),
	}
	staleConfig := &GroupConfig{
		Name:      label + " Stale Group",
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: nodeX.PeerId(), Role: GroupRoleAdmin, PublicKey: removedPub},
			{PeerId: nodeB.PeerId(), Role: GroupRoleAdmin, PublicKey: "nodeBPubKey"},
			{PeerId: nodeC.PeerId(), Role: GroupRoleWriter, PublicKey: "nodeCPubKey"},
		},
		CreatedBy: nodeX.PeerId(),
	}

	if err := nodeX.JoinGroupTopic(groupId, staleConfig, keyInfo); err != nil {
		t.Fatalf("nodeX JoinGroupTopic: %v", err)
	}
	if err := nodeB.JoinGroupTopic(groupId, currentConfig, keyInfo); err != nil {
		t.Fatalf("nodeB JoinGroupTopic: %v", err)
	}
	if err := nodeC.JoinGroupTopic(groupId, currentConfig, keyInfo); err != nil {
		t.Fatalf("nodeC JoinGroupTopic: %v", err)
	}

	connectLocalGroupNodes(t, nodeX, nodeB)
	connectLocalGroupNodes(t, nodeB, nodeC)
	waitForGroupTopicPeerCount(t, nodeX, groupId, 1, 3*time.Second)
	waitForGroupTopicPeerCount(t, nodeB, groupId, 2, 3*time.Second)
	waitForGroupTopicPeerCount(t, nodeC, groupId, 1, 3*time.Second)

	nodeCID, err := peer.Decode(nodeC.PeerId())
	if err != nil {
		t.Fatalf("decode node C peer ID: %v", err)
	}
	if got := nodeX.Host().Network().Connectedness(nodeCID); got == network.Connected {
		t.Fatal("node X must not be directly connected to node C; C absence would not prove B suppressed forwarding")
	}

	logs := captureLP002ValidatorLogs(t)
	cases := []struct {
		name         string
		envelopeType string
		plaintext    string
	}{
		{
			name:         "message",
			envelopeType: "group_message",
			plaintext:    `{"text":"` + idPrefix + ` unauthorized message","timestamp":"2026-04-30T00:00:00Z"}`,
		},
		{
			name:         "reaction",
			envelopeType: "group_reaction",
			plaintext:    `{"messageId":"msg-` + idPrefix + `","action":"add","emoji":"+1"}`,
		},
		{
			name:         "membership",
			envelopeType: "group_message",
			plaintext:    `{"__sys":"members_added","members":[{"peerId":"` + idPrefix + `-new","role":"writer"}]}`,
		},
		{
			name:         "metadata",
			envelopeType: "group_message",
			plaintext:    `{"__sys":"group_metadata_updated","groupConfig":{"name":"` + idPrefix + ` renamed"}}`,
		},
		{
			name:         "key_rotation",
			envelopeType: "group_message",
			plaintext:    `{"__sys":"key_rotated","newKeyEpoch":2}`,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			resetLP002RejectDiagnostics(nodeB, nodeC)
			beforeRejects := countLP002RejectLogs(logs.String(), "non_member")
			envelopeJSON := buildTestEnvelopeWithPlaintext(
				t,
				groupId,
				tc.envelopeType,
				nodeX.PeerId(),
				removedPriv,
				removedPub,
				groupKey,
				keyInfo.KeyEpoch,
				tc.plaintext,
			)

			publishRawGroupEnvelope(t, nodeX, groupId, envelopeJSON)
			waitForLP002RejectLogCount(t, logs, "non_member", beforeRejects+1, 2*time.Second)
			time.Sleep(400 * time.Millisecond)

			afterRejects := countLP002RejectLogs(logs.String(), "non_member")
			if got := afterRejects - beforeRejects; got != 1 {
				t.Fatalf("validator reject diagnostics after publish = %d, want exactly 1 from node B only; logs:\n%s", got, logs.String())
			}
			assertLP002NoAcceptedGroupEvents(t, "node B", nodeBCapture)
			assertLP002NoAcceptedGroupEvents(t, "node C", nodeCCapture)
		})
	}
}

func TestLP002UnauthorizedRejectDiagnosticsArePrivacySafeAndRateLimited(t *testing.T) {
	removedPriv, removedPub := generateEd25519KeyPair(t)
	otherPriv, otherPub := generateEd25519KeyPair(t)
	adminPriv, adminPub := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	groupId := "lp002-sensitive-group-id-should-not-log"
	groupName := "LP002 Sensitive Group Name Should Not Log"
	config := &GroupConfig{
		Name:      groupName,
		GroupType: GroupTypeChat,
		Members: []GroupMember{
			{PeerId: "lp002-admin", Role: GroupRoleAdmin, PublicKey: adminPub},
		},
		CreatedBy: "lp002-admin",
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	n := NewNode()
	n.groupConfigs = map[string]*GroupConfig{groupId: config}
	n.groupKeys = map[string]*GroupKeyInfo{groupId: keyInfo}
	now := time.Date(2026, 4, 30, 21, 0, 0, 0, time.UTC)
	n.pubsubRejectDiagNow = func() time.Time { return now }
	validator := n.groupTopicValidator(groupId)
	logs := captureLP002ValidatorLogs(t)

	plaintext := `{"text":"LP002-PLAINTEXT-SENTINEL","timestamp":"2026-04-30T00:00:00Z","username":"LP002-DIAGNOSTIC-USER"}`
	senderId := generatePeerIDStr(t)
	senderPeerID, err := peer.Decode(senderId)
	if err != nil {
		t.Fatalf("decode sender peer ID: %v", err)
	}
	envelopeJSON := buildTestEnvelopeWithPlaintext(t, groupId, "group_message", senderId, removedPriv, removedPub, groupKey, keyInfo.KeyEpoch, plaintext)
	msg := &pubsub.Message{Message: &pb.Message{Data: []byte(envelopeJSON)}}

	for i := 0; i < 5; i++ {
		if result := validator(context.Background(), senderPeerID, msg); result != pubsub.ValidationReject {
			t.Fatalf("validator result %d = %v, want ValidationReject", i, result)
		}
	}

	if got := countLP002RejectLogs(logs.String(), "non_member"); got != 1 {
		t.Fatalf("repeated rejects emitted %d diagnostics, want 1 within rate-limit window; logs:\n%s", got, logs.String())
	}

	env, err := internal.ParseGroupEnvelope(envelopeJSON)
	if err != nil {
		t.Fatalf("parse envelope: %v", err)
	}
	assertLP002LogsOmitSensitive(t, logs, []string{
		plaintext,
		"LP002-PLAINTEXT-SENTINEL",
		"LP002-DIAGNOSTIC-USER",
		groupId,
		groupName,
		senderId,
		removedPub,
		removedPriv,
		adminPub,
		adminPriv,
		env.Signature,
		env.Encrypted.Ciphertext,
		env.Encrypted.Nonce,
		"/ip4/127.0.0.1/tcp/4001/p2p/" + senderId,
	})
	for _, marker := range []string{
		"authorization reject",
		"reason=non_member",
		"groupHash=",
		"senderHash=",
		"transportPeerHash=",
	} {
		if !strings.Contains(logs.String(), marker) {
			t.Fatalf("diagnostic missing useful marker %q in logs:\n%s", marker, logs.String())
		}
	}

	otherSenderId := generatePeerIDStr(t)
	otherSenderPeerID, err := peer.Decode(otherSenderId)
	if err != nil {
		t.Fatalf("decode other sender peer ID: %v", err)
	}
	otherEnvelopeJSON := buildTestEnvelopeWithPlaintext(t, groupId, "group_message", otherSenderId, otherPriv, otherPub, groupKey, keyInfo.KeyEpoch, plaintext)
	otherMsg := &pubsub.Message{Message: &pb.Message{Data: []byte(otherEnvelopeJSON)}}
	otherEnv, err := internal.ParseGroupEnvelope(otherEnvelopeJSON)
	if err != nil {
		t.Fatalf("parse other envelope: %v", err)
	}
	if result := validator(context.Background(), otherSenderPeerID, otherMsg); result != pubsub.ValidationReject {
		t.Fatalf("different sender validator result = %v, want ValidationReject", result)
	}
	if got := countLP002RejectLogs(logs.String(), "non_member"); got != 2 {
		t.Fatalf("different sender should emit its first diagnostic; got %d diagnostics; logs:\n%s", got, logs.String())
	}

	now = now.Add(pubsubAuthorizationRejectDiagnosticWindow + time.Nanosecond)
	if result := validator(context.Background(), senderPeerID, msg); result != pubsub.ValidationReject {
		t.Fatalf("post-window validator result = %v, want ValidationReject", result)
	}
	if got := countLP002RejectLogs(logs.String(), "non_member"); got != 3 {
		t.Fatalf("same sender after rate-limit window should emit again; got %d diagnostics; logs:\n%s", got, logs.String())
	}
	assertLP002LogsOmitSensitive(t, logs, []string{
		otherSenderId,
		otherPub,
		otherPriv,
		otherEnv.Signature,
		otherEnv.Encrypted.Ciphertext,
		otherEnv.Encrypted.Nonce,
		"/ip4/127.0.0.1/tcp/4001/p2p/" + otherSenderId,
	})
}

func TestGO005ValidationRejectDiagnosticsAreRateLimitedByReasonGroupSenderTransport(t *testing.T) {
	collector := &testEventCollector{}
	n := NewNode()
	n.peerId = "go005-local-peer"
	n.eventCallback = collector

	now := time.Date(2026, 5, 14, 7, 30, 0, 0, time.UTC)
	n.pubsubRejectDiagNow = func() time.Time { return now }
	logs := captureLP002ValidatorLogs(t)

	pidA := peer.ID("go005-transport-a")
	pidB := peer.ID("go005-transport-b")
	envA := &internal.GroupEnvelope{
		SenderId: "go005-sender-a",
		Type:     "group_message",
		KeyEpoch: 7,
	}
	envB := &internal.GroupEnvelope{
		SenderId: "go005-sender-b",
		Type:     "group_message",
		KeyEpoch: 7,
	}

	for i := 0; i < 50; i++ {
		n.logPubSubValidationReject("non_member", "go005-group-a", pidA, envA)
	}
	assertGO005ValidationRejectTotals(t, collector, map[string]int{"non_member": 1})
	if got := countLP002RejectLogs(logs.String(), "non_member"); got != 1 {
		t.Fatalf("repeated same-key rejects emitted %d non_member logs, want 1; logs:\n%s", got, logs.String())
	}

	n.logPubSubValidationReject("non_member", "go005-group-a", pidB, envA)
	n.logPubSubValidationReject("non_member", "go005-group-a", pidA, envB)
	n.logPubSubValidationReject("non_member", "go005-group-b", pidA, envA)
	n.logPubSubValidationReject("missing_key", "go005-group-a", pidA, envA)
	for i := 0; i < 10; i++ {
		n.logPubSubValidationReject("missing_key", "go005-group-a", pidA, envA)
	}

	assertGO005ValidationRejectTotals(t, collector, map[string]int{
		"non_member":  4,
		"missing_key": 1,
	})
	if got := countLP002RejectLogs(logs.String(), "non_member"); got != 4 {
		t.Fatalf("non_member logs after distinct transport/sender/group = %d, want 4; logs:\n%s", got, logs.String())
	}
	if got := countLP002RejectLogs(logs.String(), "missing_key"); got != 1 {
		t.Fatalf("repeated same-key missing_key rejects emitted %d logs, want 1; logs:\n%s", got, logs.String())
	}

	now = now.Add(pubsubAuthorizationRejectDiagnosticWindow + time.Nanosecond)
	n.logPubSubValidationReject("non_member", "go005-group-a", pidA, envA)
	assertGO005ValidationRejectTotals(t, collector, map[string]int{
		"non_member":  5,
		"missing_key": 1,
	})
	if got := countLP002RejectLogs(logs.String(), "non_member"); got != 5 {
		t.Fatalf("same diagnostic key after rate-limit window emitted %d non_member logs, want 5 total; logs:\n%s", got, logs.String())
	}
}

func TestER001InvalidSignatureDiagnosticsArePrivacySafeAndActionable(t *testing.T) {
	adminPriv, adminPub := generateEd25519KeyPair(t)
	attackerPriv, attackerPub := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	groupId := "er001-sensitive-group-id-should-not-log"
	groupName := "ER001 Sensitive Group Name Should Not Log"
	adminPeerId := generatePeerIDStr(t)
	localPeerId := generatePeerIDStr(t)
	adminPID, err := peer.Decode(adminPeerId)
	if err != nil {
		t.Fatalf("decode admin peer ID: %v", err)
	}

	collector := &testEventCollector{}
	n := NewNode()
	n.peerId = localPeerId
	n.eventCallback = collector
	n.groupConfigs = map[string]*GroupConfig{
		groupId: {
			Name:      groupName,
			GroupType: GroupTypeChat,
			Members: []GroupMember{
				{PeerId: adminPeerId, Role: GroupRoleAdmin, PublicKey: adminPub},
			},
			CreatedBy: adminPeerId,
		},
	}
	keyInfo := &GroupKeyInfo{Key: groupKey, KeyEpoch: 1}
	n.groupKeys = map[string]*GroupKeyInfo{groupId: keyInfo}
	now := time.Date(2026, 5, 1, 7, 30, 0, 0, time.UTC)
	n.pubsubRejectDiagNow = func() time.Time { return now }

	validator := n.groupTopicValidator(groupId)
	logs := captureLP002ValidatorLogs(t)
	cases := []struct {
		name         string
		envelopeType string
		plaintext    string
	}{
		{
			name:         "message",
			envelopeType: "group_message",
			plaintext:    `{"text":"ER001-PLAINTEXT-SENTINEL","timestamp":"2026-05-01T00:00:00Z"}`,
		},
		{
			name:         "reaction",
			envelopeType: "group_reaction",
			plaintext:    `{"messageId":"ER001-MSG-SENTINEL","action":"add","emoji":"+1"}`,
		},
		{
			name:         "member_added",
			envelopeType: "group_message",
			plaintext:    `{"__sys":"member_added","member":{"peerId":"ER001-NEW-PEER-SENTINEL","role":"writer","publicKey":"ER001-NEW-PK-SENTINEL"}}`,
		},
		{
			name:         "members_added",
			envelopeType: "group_message",
			plaintext:    `{"__sys":"members_added","members":[{"peerId":"ER001-NEW-PEER-SENTINEL","role":"writer","publicKey":"ER001-NEW-PK-SENTINEL"}]}`,
		},
		{
			name:         "member_removed",
			envelopeType: "group_message",
			plaintext:    `{"__sys":"member_removed","member":{"peerId":"ER001-REMOVED-PEER-SENTINEL"},"removedAt":"2026-05-01T00:00:00Z"}`,
		},
		{
			name:         "member_role_updated",
			envelopeType: "group_message",
			plaintext:    `{"__sys":"member_role_updated","member":{"peerId":"ER001-ROLE-PEER-SENTINEL","role":"reader"}}`,
		},
		{
			name:         "group_metadata_updated",
			envelopeType: "group_message",
			plaintext:    `{"__sys":"group_metadata_updated","groupConfig":{"name":"ER001-METADATA-SENTINEL","metadataUpdatedAt":"2026-05-01T00:00:00Z"}}`,
		},
		{
			name:         "group_dissolved",
			envelopeType: "group_message",
			plaintext:    `{"__sys":"group_dissolved","dissolvedAt":"2026-05-01T00:00:00Z","reason":"ER001-DISSOLVE-SENTINEL"}`,
		},
		{
			name:         "key_rotated",
			envelopeType: "group_message",
			plaintext:    `{"__sys":"key_rotated","newKeyEpoch":2,"debug":"ER001-KEY-SENTINEL"}`,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			beforeRejects := countLP002RejectLogs(logs.String(), "bad_signature_or_epoch")
			beforeEvents := len(collector.snapshot())
			envelopeJSON := buildTestEnvelopeWithPlaintext(
				t,
				groupId,
				tc.envelopeType,
				adminPeerId,
				attackerPriv,
				attackerPub,
				groupKey,
				keyInfo.KeyEpoch,
				tc.plaintext,
			)
			env, err := internal.ParseGroupEnvelope(envelopeJSON)
			if err != nil {
				t.Fatalf("parse envelope: %v", err)
			}
			msg := &pubsub.Message{Message: &pb.Message{Data: []byte(envelopeJSON)}}

			if result := validator(context.Background(), adminPID, msg); result != pubsub.ValidationReject {
				t.Fatalf("validator result = %v, want ValidationReject", result)
			}
			if got := countLP002RejectLogs(logs.String(), "bad_signature_or_epoch") - beforeRejects; got != 1 {
				t.Fatalf("diagnostic logs added = %d, want 1; logs:\n%s", got, logs.String())
			}

			events := collector.snapshot()
			if got := len(events) - beforeEvents; got != 1 {
				t.Fatalf("diagnostic events added = %d, want 1; events:\n%s", got, strings.Join(events, "\n"))
			}
			var payload map[string]interface{}
			if err := json.Unmarshal([]byte(events[len(events)-1]), &payload); err != nil {
				t.Fatalf("decode diagnostic event: %v", err)
			}
			if payload["event"] != "group:validation_rejected" {
				t.Fatalf("event = %v, want group:validation_rejected", payload["event"])
			}
			data, ok := payload["data"].(map[string]interface{})
			if !ok {
				t.Fatalf("event data has type %T, want object", payload["data"])
			}
			for key, want := range map[string]interface{}{
				"reason":       "bad_signature_or_epoch",
				"envelopeType": tc.envelopeType,
				"keyEpoch":     float64(keyInfo.KeyEpoch),
			} {
				if got := data[key]; got != want {
					t.Fatalf("event data[%s] = %v, want %v", key, got, want)
				}
			}
			for _, key := range []string{"groupHash", "senderHash", "transportPeerHash", "localPeerHash"} {
				value, ok := data[key].(string)
				if !ok || len(value) != pubsubAuthorizationRejectHashLength {
					t.Fatalf("event data[%s] = %v, want %d-char hash", key, data[key], pubsubAuthorizationRejectHashLength)
				}
			}

			eventJSON := events[len(events)-1]
			assertLP002LogsOmitSensitive(t, logs, []string{
				tc.plaintext,
				"ER001-PLAINTEXT-SENTINEL",
				"ER001-MSG-SENTINEL",
				"ER001-NEW-PEER-SENTINEL",
				"ER001-NEW-PK-SENTINEL",
				"ER001-REMOVED-PEER-SENTINEL",
				"ER001-ROLE-PEER-SENTINEL",
				"ER001-METADATA-SENTINEL",
				"ER001-DISSOLVE-SENTINEL",
				"ER001-KEY-SENTINEL",
				groupId,
				groupName,
				adminPeerId,
				localPeerId,
				adminPub,
				adminPriv,
				attackerPub,
				attackerPriv,
				env.Signature,
				env.Encrypted.Ciphertext,
				env.Encrypted.Nonce,
				"/ip4/127.0.0.1/tcp/4001/p2p/" + adminPeerId,
			})
			for _, fragment := range []string{
				tc.plaintext,
				groupId,
				groupName,
				adminPeerId,
				localPeerId,
				adminPub,
				adminPriv,
				attackerPub,
				attackerPriv,
				env.Signature,
				env.Encrypted.Ciphertext,
				env.Encrypted.Nonce,
			} {
				if fragment != "" && strings.Contains(eventJSON, fragment) {
					t.Fatalf("diagnostic event leaked sensitive fragment %q in %s", fragment, eventJSON)
				}
			}

			now = now.Add(pubsubAuthorizationRejectDiagnosticWindow + time.Nanosecond)
		})
	}
}

func TestGA026ValidationRejectDiagnosticsArePrivacySafeForAllReasons(t *testing.T) {
	transportPeerId := generatePeerIDStr(t)
	localPeerId := generatePeerIDStr(t)
	transportPID, err := peer.Decode(transportPeerId)
	if err != nil {
		t.Fatalf("decode transport peer ID: %v", err)
	}

	groupId := "ga026-sensitive-group-id-must-not-leak"
	envGroupId := "ga026-sensitive-envelope-group-id-must-not-leak"
	senderId := "ga026-sensitive-sender-id-must-not-leak"
	env := &internal.GroupEnvelope{
		Version:               "3",
		Type:                  "group_message",
		GroupId:               envGroupId,
		MessageId:             "ga026-sensitive-message-id-must-not-leak",
		SenderId:              senderId,
		SenderDeviceId:        "ga026-sensitive-device-id-must-not-leak",
		SenderTransportPeerId: transportPeerId,
		SenderDevicePublicKey: "ga026-sensitive-device-public-key-must-not-leak",
		SenderKeyPackageId:    "ga026-sensitive-key-package-id-must-not-leak",
		SenderPublicKey:       "ga026-sensitive-sender-public-key-must-not-leak",
		Signature:             "ga026-sensitive-signature-must-not-leak",
		KeyEpoch:              26,
		Encrypted: internal.GroupEncryptedPayload{
			Ciphertext: "ga026-sensitive-ciphertext-must-not-leak",
			Nonce:      "ga026-sensitive-nonce-must-not-leak",
		},
	}

	collector := &testEventCollector{}
	n := New(collector)
	n.peerId = localPeerId
	now := time.Date(2026, 5, 13, 21, 30, 0, 0, time.UTC)
	n.pubsubRejectDiagNow = func() time.Time { return now }
	logs := captureLP002ValidatorLogs(t)

	cases := []struct {
		reason       string
		env          *internal.GroupEnvelope
		wantSender   string
		wantType     string
		wantKeyEpoch float64
	}{
		{reason: "not_v3_envelope", env: nil, wantSender: "", wantType: "unknown", wantKeyEpoch: 0},
		{reason: "invalid_envelope", env: env, wantSender: senderId, wantType: "group_message", wantKeyEpoch: 26},
		{reason: "group_mismatch", env: env, wantSender: senderId, wantType: "group_message", wantKeyEpoch: 26},
		{reason: "peer_mismatch", env: env, wantSender: senderId, wantType: "group_message", wantKeyEpoch: 26},
		{reason: "unknown_group", env: env, wantSender: senderId, wantType: "group_message", wantKeyEpoch: 26},
		{reason: "ambiguous_signing_key", env: env, wantSender: senderId, wantType: "group_message", wantKeyEpoch: 26},
		{reason: "ambiguous_transport_peer", env: env, wantSender: senderId, wantType: "group_message", wantKeyEpoch: 26},
		{reason: "non_member", env: env, wantSender: senderId, wantType: "group_message", wantKeyEpoch: 26},
		{reason: "unbound_device", env: env, wantSender: senderId, wantType: "group_message", wantKeyEpoch: 26},
		{reason: "unauthorized_writer", env: env, wantSender: senderId, wantType: "group_message", wantKeyEpoch: 26},
		{reason: "missing_key", env: env, wantSender: senderId, wantType: "group_message", wantKeyEpoch: 26},
		{reason: "bad_signature_or_epoch", env: env, wantSender: senderId, wantType: "group_message", wantKeyEpoch: 26},
	}

	for _, tc := range cases {
		t.Run(tc.reason, func(t *testing.T) {
			beforeEvents := len(collector.snapshot())
			beforeLogs := countLP002RejectLogs(logs.String(), tc.reason)
			n.logPubSubValidationReject(tc.reason, groupId, transportPID, tc.env)
			now = now.Add(pubsubAuthorizationRejectDiagnosticWindow + time.Nanosecond)

			if got := countLP002RejectLogs(logs.String(), tc.reason) - beforeLogs; got != 1 {
				t.Fatalf("diagnostic logs added for %s = %d, want 1; logs:\n%s", tc.reason, got, logs.String())
			}

			events := collector.snapshot()
			if got := len(events) - beforeEvents; got != 1 {
				t.Fatalf("diagnostic events added for %s = %d, want 1; events:\n%s", tc.reason, got, strings.Join(events, "\n"))
			}

			var payload map[string]interface{}
			if err := json.Unmarshal([]byte(events[len(events)-1]), &payload); err != nil {
				t.Fatalf("decode diagnostic event: %v", err)
			}
			if payload["event"] != "group:validation_rejected" {
				t.Fatalf("event = %v, want group:validation_rejected", payload["event"])
			}
			data, ok := payload["data"].(map[string]interface{})
			if !ok {
				t.Fatalf("event data has type %T, want object", payload["data"])
			}

			assertGA026DiagnosticKeys(t, data)
			if got := data["reason"]; got != tc.reason {
				t.Fatalf("event reason = %v, want %s", got, tc.reason)
			}
			if got := data["envelopeType"]; got != tc.wantType {
				t.Fatalf("event envelopeType = %v, want %s", got, tc.wantType)
			}
			if got := data["keyEpoch"]; got != tc.wantKeyEpoch {
				t.Fatalf("event keyEpoch = %v, want %v", got, tc.wantKeyEpoch)
			}
			assertGA026DiagnosticHash(t, data, "groupHash", pubsubAuthorizationRejectHash(groupId))
			assertGA026DiagnosticHash(t, data, "senderHash", pubsubAuthorizationRejectHash(tc.wantSender))
			assertGA026DiagnosticHash(t, data, "transportPeerHash", pubsubAuthorizationRejectHash(transportPeerId))
			assertGA026DiagnosticHash(t, data, "localPeerHash", pubsubAuthorizationRejectHash(localPeerId))
		})
	}

	rawEvents := strings.Join(collector.snapshot(), "\n")
	rawLogs := logs.String()
	assertGA026DiagnosticsOmitSensitive(t, rawEvents, rawLogs, []string{
		groupId,
		envGroupId,
		senderId,
		transportPeerId,
		localPeerId,
		env.MessageId,
		env.SenderDeviceId,
		env.SenderDevicePublicKey,
		env.SenderKeyPackageId,
		env.SenderPublicKey,
		env.Signature,
		env.Encrypted.Ciphertext,
		env.Encrypted.Nonce,
		"GA026 plaintext marker must not leak",
	})
	for _, label := range []string{"groupHash=", "senderHash=", "transportPeerHash=", "localPeerHash="} {
		if !strings.Contains(rawLogs, label) {
			t.Fatalf("diagnostic logs missing %s; logs:\n%s", label, rawLogs)
		}
	}
}

func assertGA026DiagnosticKeys(t *testing.T, data map[string]interface{}) {
	t.Helper()

	allowed := map[string]struct{}{
		"reason":            {},
		"groupHash":         {},
		"senderHash":        {},
		"transportPeerHash": {},
		"localPeerHash":     {},
		"envelopeType":      {},
		"keyEpoch":          {},
	}
	if len(data) != len(allowed) {
		t.Fatalf("event data keys = %v, want only %v", data, allowed)
	}
	for key := range data {
		if _, ok := allowed[key]; !ok {
			t.Fatalf("event data contains disallowed key %q in %v", key, data)
		}
	}
}

func assertGA026DiagnosticHash(t *testing.T, data map[string]interface{}, key, want string) {
	t.Helper()

	got, ok := data[key].(string)
	if !ok {
		t.Fatalf("event data[%s] = %v (%T), want string", key, data[key], data[key])
	}
	if got != want {
		t.Fatalf("event data[%s] = %q, want %q", key, got, want)
	}
	if got == "none" {
		return
	}
	if len(got) != pubsubAuthorizationRejectHashLength {
		t.Fatalf("event data[%s] = %q, want %d-char truncated hash", key, got, pubsubAuthorizationRejectHashLength)
	}
	for _, r := range got {
		if !strings.ContainsRune("0123456789abcdef", r) {
			t.Fatalf("event data[%s] = %q, want lowercase hex hash", key, got)
		}
	}
}

func assertGA026DiagnosticsOmitSensitive(t *testing.T, rawEvents, rawLogs string, fragments []string) {
	t.Helper()

	for _, fragment := range fragments {
		if fragment == "" {
			continue
		}
		if strings.Contains(rawEvents, fragment) {
			t.Fatalf("GA-026 diagnostic event leaked sensitive fragment %q in events: %s", fragment, rawEvents)
		}
		if strings.Contains(rawLogs, fragment) {
			t.Fatalf("GA-026 diagnostic log leaked sensitive fragment %q in logs: %s", fragment, rawLogs)
		}
	}
}

type lp002LogBuffer struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (b *lp002LogBuffer) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.Write(p)
}

func (b *lp002LogBuffer) String() string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.String()
}

func captureLP002ValidatorLogs(t *testing.T) *lp002LogBuffer {
	t.Helper()

	buf := &lp002LogBuffer{}
	previousOutput := log.Writer()
	previousFlags := log.Flags()
	log.SetOutput(buf)
	log.SetFlags(0)
	t.Cleanup(func() {
		log.SetOutput(previousOutput)
		log.SetFlags(previousFlags)
	})
	return buf
}

func resetLP002RejectDiagnostics(nodes ...*Node) {
	for _, n := range nodes {
		n.pubsubRejectDiagMu.Lock()
		n.pubsubRejectDiagLast = make(map[string]time.Time)
		n.pubsubRejectDiagMu.Unlock()
	}
}

func countLP002RejectLogs(logs, reason string) int {
	return strings.Count(logs, "Validator: authorization reject reason="+reason)
}

func assertGO005ValidationRejectTotals(t *testing.T, collector *testEventCollector, want map[string]int) {
	t.Helper()

	got := make(map[string]int)
	for _, raw := range collector.snapshot() {
		var payload map[string]interface{}
		if err := json.Unmarshal([]byte(raw), &payload); err != nil {
			t.Fatalf("decode emitted event %q: %v", raw, err)
		}
		if payload["event"] != "group:validation_rejected" {
			t.Fatalf("unexpected event in GO-005 collector: %s", raw)
		}
		data, ok := payload["data"].(map[string]interface{})
		if !ok {
			t.Fatalf("validation_rejected event missing data object: %s", raw)
		}
		reason, ok := data["reason"].(string)
		if !ok || reason == "" {
			t.Fatalf("validation_rejected event missing reason: %s", raw)
		}
		got[reason]++
	}

	for reason, wantCount := range want {
		if got[reason] != wantCount {
			t.Fatalf("validation_rejected count for %s = %d, want %d; all counts=%v", reason, got[reason], wantCount, got)
		}
	}
	for reason, gotCount := range got {
		if _, ok := want[reason]; !ok {
			t.Fatalf("unexpected validation_rejected reason %s count=%d; all counts=%v", reason, gotCount, got)
		}
	}
}

func waitForLP002RejectLogCount(t *testing.T, logs *lp002LogBuffer, reason string, want int, timeout time.Duration) {
	t.Helper()

	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if countLP002RejectLogs(logs.String(), reason) >= want {
			return
		}
		time.Sleep(25 * time.Millisecond)
	}
	t.Fatalf("timed out waiting for %d %q reject diagnostics; got %d logs:\n%s", want, reason, countLP002RejectLogs(logs.String(), reason), logs.String())
}

func assertLP002LogsOmitSensitive(t *testing.T, logs *lp002LogBuffer, fragments []string) {
	t.Helper()

	snapshot := logs.String()
	for _, fragment := range fragments {
		if fragment != "" && strings.Contains(snapshot, fragment) {
			t.Fatalf("diagnostic leaked sensitive fragment %q in logs:\n%s", fragment, snapshot)
		}
	}
}

func assertLP002NoAcceptedGroupEvents(t *testing.T, label string, collector *testEventCollector) {
	t.Helper()

	for _, raw := range collector.snapshot() {
		for _, forbidden := range []string{
			`"event":"group_message:received"`,
			`"event":"group_reaction:received"`,
			`"event":"group:payload_parse_failed"`,
			`"event":"group:decryption_failed"`,
		} {
			if strings.Contains(raw, forbidden) {
				t.Fatalf("%s emitted forbidden LP-002 event %s in %s", label, forbidden, raw)
			}
		}
	}
}
