package main

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"reflect"
	"sort"
	"strings"
	"testing"
	"time"

	"firebase.google.com/go/v4/messaging"
	"github.com/alicebob/miniredis/v2"
)

const testCanonicalGroupReactionHandlerID = "55555555-5555-4555-8555-555555555555"

type signedGroupReactionFixture struct {
	groupID       string
	accountPeerID string
	transportID   string
	publicKey     ed25519.PublicKey
	privateKey    ed25519.PrivateKey
}

func newSignedGroupReactionFixture(t *testing.T, groupID, accountPeerID, transportID string) signedGroupReactionFixture {
	t.Helper()
	publicKey, privateKey, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatalf("generate fixture signing key: %v", err)
	}
	return signedGroupReactionFixture{
		groupID:       groupID,
		accountPeerID: accountPeerID,
		transportID:   transportID,
		publicKey:     publicKey,
		privateKey:    privateKey,
	}
}

func (f signedGroupReactionFixture) envelope(
	t *testing.T,
	transitionID,
	action,
	baseMessageID,
	targetMessageID string,
	replayRecipients,
	notificationRecipients []string,
) string {
	t.Helper()
	replayRecipients = append([]string{}, replayRecipients...)
	sort.Strings(replayRecipients)
	notificationRecipients = append([]string{}, notificationRecipients...)
	sort.Strings(notificationRecipients)
	replayHash := groupReactionPeerSetHash(replayRecipients)
	base := map[string]interface{}{
		"kind":                  "group_offline_replay",
		"version":               1,
		"groupId":               f.groupID,
		"payloadType":           "group_reaction",
		"keyEpoch":              7,
		"messageId":             baseMessageID,
		"senderPeerId":          f.accountPeerID,
		"senderDeviceId":        f.transportID,
		"senderTransportPeerId": f.transportID,
		"senderPublicKey":       base64.StdEncoding.EncodeToString(f.publicKey),
		"recipientPeerIds":      replayRecipients,
		"recipientSetHash":      replayHash,
		"ciphertext":            "ciphertext-" + transitionID,
		"nonce":                 "nonce-" + transitionID,
		"signatureAlgorithm":    "ed25519",
		"signedPayload":         `{"kind":"group_offline_replay"}`,
		"signature":             "opaque-base-signature-" + transitionID,
	}
	baseJSON, err := canonicalGroupReactionJSON(base)
	if err != nil {
		t.Fatalf("canonical base envelope: %v", err)
	}
	baseHash := sha256Hex(baseJSON)
	extensionSignedFields := map[string]interface{}{
		"kind":                                  "group_reaction_notification",
		"version":                               1,
		"transitionId":                          transitionID,
		"action":                                action,
		"targetMessageId":                       targetMessageID,
		"reactorPeerId":                         f.accountPeerID,
		"reactorTransportPeerId":                f.transportID,
		"replayRecipientSetHash":                replayHash,
		"notificationRecipientTransportPeerIds": notificationRecipients,
		"baseEnvelopeHash":                      baseHash,
	}
	signedPayload, err := canonicalGroupReactionJSON(extensionSignedFields)
	if err != nil {
		t.Fatalf("canonical notification extension: %v", err)
	}
	extension := make(map[string]interface{}, len(extensionSignedFields)+2)
	for key, value := range extensionSignedFields {
		if key != "kind" {
			extension[key] = value
		}
	}
	extension["signatureAlgorithm"] = "ed25519"
	extension["signedPayload"] = signedPayload
	extension["signature"] = base64.StdEncoding.EncodeToString(
		ed25519.Sign(f.privateKey, []byte(signedPayload)),
	)
	base["notificationExtension"] = extension
	encoded, err := canonicalGroupReactionJSON(base)
	if err != nil {
		t.Fatalf("canonical group reaction envelope: %v", err)
	}
	return encoded
}

func waitForGroupReactionPushes(t *testing.T, recorder *recordingPushSender, count int) {
	t.Helper()
	deadline := time.After(2 * time.Second)
	for recorder.SendCallCount() < count {
		select {
		case <-recorder.sentSignal:
		case <-deadline:
			t.Fatalf("push calls = %d, want %d", recorder.SendCallCount(), count)
		}
	}
}

func assertNoAdditionalGroupReactionPush(t *testing.T, recorder *recordingPushSender, count int) {
	t.Helper()
	select {
	case <-recorder.sentSignal:
		if recorder.SendCallCount() > count {
			t.Fatalf("push calls = %d, want %d", recorder.SendCallCount(), count)
		}
	case <-time.After(125 * time.Millisecond):
	}
	if recorder.SendCallCount() != count {
		t.Fatalf("push calls = %d, want %d", recorder.SendCallCount(), count)
	}
}

func TestGroupReactionPushProjectsOnlyTheRecipientPlatformPayload(t *testing.T) {
	const groupID = "39c80392-964e-4235-b1b7-5243947962c0"
	reactorAccount := "12D3KooW" + strings.Repeat("a", 44)
	reactorTransport := "12D3KooW" + strings.Repeat("b", 44)
	authorTransport := "12D3KooW" + strings.Repeat("c", 44)
	fixture := newSignedGroupReactionFixture(
		t,
		groupID,
		reactorAccount,
		reactorTransport,
	)
	envelope := fixture.envelope(
		t,
		"group-reaction:1783871932846448:transition",
		"add",
		"group-reaction:1783871932846448:state",
		"4f5a669d-9bae-43c9-9301-3de410e155ac",
		[]string{reactorTransport, authorTransport},
		[]string{authorTransport},
	)
	metadata, recognized, valid := extractGroupReactionPushMetadata(
		envelope,
		groupID,
		reactorTransport,
		[]string{reactorTransport, authorTransport},
	)
	if !recognized || !valid {
		t.Fatal("realistic group reaction fixture must validate")
	}
	var inflated map[string]interface{}
	if err := json.Unmarshal([]byte(envelope), &inflated); err != nil {
		t.Fatal(err)
	}
	inflated["ciphertext"] = strings.Repeat("c", 452)
	inflatedEnvelope, err := canonicalGroupReactionJSON(inflated)
	if err != nil {
		t.Fatal(err)
	}

	build := func() *messaging.Message {
		return buildGroupReactionPushMessage(
			"provider-token",
			groupID,
			inflatedEnvelope,
			metadata,
		)
	}
	full := build()
	fullWire, err := json.Marshal(full)
	if err != nil {
		t.Fatal(err)
	}
	if len(fullWire) <= 4096 {
		t.Fatalf("fixture wire bytes = %d, want cross-platform duplication over 4096", len(fullWire))
	}

	android := projectGroupReactionPushMessageForPlatform(build(), "android")
	androidWire, err := json.Marshal(android)
	if err != nil {
		t.Fatal(err)
	}
	if android.APNS != nil || android.Android == nil || android.Data == nil {
		t.Fatalf("Android projection retained cross-platform payload: %#v", android)
	}
	if len(androidWire) >= len(fullWire) || len(androidWire) > 4096 {
		t.Fatalf("Android wire bytes = %d, full = %d", len(androidWire), len(fullWire))
	}

	ios := projectGroupReactionPushMessageForPlatform(build(), "ios")
	iosWire, err := json.Marshal(ios)
	if err != nil {
		t.Fatal(err)
	}
	if ios.Android != nil || ios.APNS == nil || ios.Data != nil {
		t.Fatalf("iOS projection retained cross-platform payload: %#v", ios)
	}
	aps := ios.APNS.Payload.Aps
	if aps == nil || aps.Alert == nil || aps.Alert.Title != reactionPushTitle ||
		aps.Alert.Body != reactionPushBody || !aps.MutableContent ||
		aps.ThreadID != groupID {
		t.Fatalf("iOS group reaction fallback = %#v", aps)
	}
	if collapseID := ios.APNS.Headers["apns-collapse-id"]; collapseID == "" || len(collapseID) > 64 {
		t.Fatalf("iOS group reaction collapse identity = %q", collapseID)
	}
	if len(iosWire) >= len(fullWire) || len(iosWire) > 4096 {
		t.Fatalf("iOS wire bytes = %d, full = %d", len(iosWire), len(fullWire))
	}
}

func TestGroupInboxStore_ReactionAddPushesAllAuthorDevicesOnly(t *testing.T) {
	const (
		groupID     = "group-reaction-author-only"
		reactorID   = "peer-reactor-account"
		reactorTxID = "peer-reactor-transport"
		authorOne   = "peer-author-device-1"
		authorTwo   = "peer-author-device-2"
		bystander   = "peer-bystander-device"
	)
	fixture := newSignedGroupReactionFixture(t, groupID, reactorID, reactorTxID)
	tokens := newMemoryPushTokenStore()
	for _, peerID := range []string{authorOne, authorTwo, bystander} {
		tokens.RegisterToken(peerID, "token-"+peerID, "android", groupReactionCapability)
	}
	push := NewPushServiceWithBackend(tokens)
	recorder := newRecordingPushSender()
	push.sender = recorder.Send
	store := NewGroupInboxStore(500, 7*24*time.Hour)
	store.SetPush(push)
	store.SetGroupReactionPushEnabled(true)
	replayRecipients := []string{authorOne, authorTwo, bystander}
	add := fixture.envelope(
		t,
		"transition-add-1",
		"add",
		"state-add-1",
		"target-message-1",
		replayRecipients,
		[]string{authorOne, authorTwo},
	)
	if err := store.StoreWithPushRecipients(groupID, reactorTxID, add, replayRecipients); err != nil {
		t.Fatalf("store ADD reaction: %v", err)
	}
	waitForGroupReactionPushes(t, recorder, 2)

	wantTokens := map[string]bool{"token-" + authorOne: true, "token-" + authorTwo: true}
	for _, message := range recorder.Messages() {
		if !wantTokens[message.Token] {
			t.Fatalf("unexpected reaction push token %q", message.Token)
		}
		if message.Data["type"] != "group_reaction" ||
			message.Data["event_id"] != "transition-add-1" ||
			message.Data["target_message_id"] != "target-message-1" ||
			message.Data["capability_version"] != groupReactionCapability {
			t.Fatalf("typed group reaction data = %#v", message.Data)
		}
		if message.Notification != nil || message.Android == nil ||
			message.Android.Priority != "high" || message.Android.Notification != nil {
			t.Fatalf("Android group reaction push must be high-priority data-only: %#v", message)
		}
		if message.APNS != nil {
			t.Fatalf("Android-targeted push retained APNs payload: %#v", message.APNS)
		}
		// Plan 309 D1(b): group reactions are non-collapsible on Android — a
		// collapse key (per-group OR per-event) discards concurrent reactions.
		if collapseID := message.Android.CollapseKey; collapseID != "" {
			t.Fatalf("group reaction Android push must omit CollapseKey; got %q", collapseID)
		}
		delete(wantTokens, message.Token)
	}
	if len(wantTokens) != 0 {
		t.Fatalf("missing author-device pushes: %#v", wantTokens)
	}
	for _, peerID := range replayRecipients {
		if got := store.RetrieveAuthorized(groupID, 0, peerID); len(got) != 1 {
			t.Fatalf("replay custody for %s = %d, want 1", peerID, len(got))
		}
	}

	remove := fixture.envelope(
		t,
		"transition-remove-1",
		"remove",
		"state-remove-1",
		"target-message-1",
		replayRecipients,
		[]string{authorOne, authorTwo},
	)
	if err := store.StoreWithPushRecipients(groupID, reactorTxID, remove, replayRecipients); err != nil {
		t.Fatalf("store REMOVE reaction: %v", err)
	}
	legacy := fmt.Sprintf(
		`{"kind":"group_offline_replay","version":1,"groupId":%q,"payloadType":"group_reaction","messageId":"legacy-state","senderTransportPeerId":%q,"recipientPeerIds":[%q],"ciphertext":"legacy-ciphertext","nonce":"legacy-nonce"}`,
		groupID,
		reactorTxID,
		authorOne,
	)
	if err := store.StoreWithPushRecipients(groupID, reactorTxID, legacy, []string{authorOne}); err != nil {
		t.Fatalf("store legacy reaction: %v", err)
	}
	assertNoAdditionalGroupReactionPush(t, recorder, 2)
}

func TestGroupInboxHandler_ReactionHintBindsAuthenticatedSenderAndExactRecipientSet(t *testing.T) {
	tokens := newMemoryPushTokenStore()
	push := NewPushServiceWithBackend(tokens)
	recorder := newRecordingPushSender()
	push.sender = recorder.Send
	groupInbox := NewGroupInboxStore(500, 7*24*time.Hour)
	groupInbox.SetPush(push)
	groupInbox.SetGroupReactionPushEnabled(true)
	inbox := NewInboxStore(push)
	env := setupInboxStreamEnv(t, inbox, groupInbox)

	remotePeer := env.sender.ID().String()
	recipientPeer := env.recipient.ID().String()
	tokens.RegisterToken(recipientPeer, "recipient-token", "android", groupReactionCapability)
	fixture := newSignedGroupReactionFixture(t, testCanonicalGroupReactionHandlerID, "reactor-account", remotePeer)

	store := func(message string, recipients []string) inboxResponse {
		t.Helper()
		stream, err := env.sender.NewStream(context.Background(), env.server.ID(), InboxProtocol)
		if err != nil {
			t.Fatalf("open stream: %v", err)
		}
		defer stream.Close()
		sendInboxReq(t, stream, inboxRequest{
			Action:           "group_store",
			GroupId:          testCanonicalGroupReactionHandlerID,
			From:             remotePeer,
			Message:          message,
			RecipientPeerIds: recipients,
		})
		return recvInboxResp(t, stream)
	}

	valid := fixture.envelope(
		t,
		"handler-transition-valid",
		"add",
		"handler-state-valid",
		"handler-target",
		[]string{recipientPeer},
		[]string{recipientPeer},
	)
	if response := store(valid, []string{recipientPeer}); response.Status != "OK" {
		t.Fatalf("valid group_store response = %#v", response)
	}
	waitForGroupReactionPushes(t, recorder, 1)

	setMismatch := fixture.envelope(
		t,
		"handler-transition-set-mismatch",
		"add",
		"handler-state-set-mismatch",
		"handler-target",
		[]string{recipientPeer},
		[]string{recipientPeer},
	)
	if response := store(setMismatch, []string{recipientPeer, "peer-extra"}); response.Status != "OK" {
		t.Fatalf("set-mismatch silent custody response = %#v", response)
	}

	wrongTransportFixture := newSignedGroupReactionFixture(
		t,
		testCanonicalGroupReactionHandlerID,
		"reactor-account",
		"forged-transport",
	)
	wrongSender := wrongTransportFixture.envelope(
		t,
		"handler-transition-wrong-sender",
		"add",
		"handler-state-wrong-sender",
		"handler-target",
		[]string{recipientPeer},
		[]string{recipientPeer},
	)
	if response := store(wrongSender, []string{recipientPeer}); response.Status != "OK" {
		t.Fatalf("sender-mismatch silent custody response = %#v", response)
	}
	assertNoAdditionalGroupReactionPush(t, recorder, 1)
	if got := len(groupInbox.Retrieve(testCanonicalGroupReactionHandlerID, 0)); got != 3 {
		t.Fatalf("stored handler reactions = %d, want 3", got)
	}
}

func TestGroupReactionTransitionMemoryAndRedis(t *testing.T) {
	const (
		groupID   = "group-transition"
		from      = "reactor-transport"
		stateAdd  = "deterministic-add-state"
		stateDrop = "deterministic-remove-state"
	)
	fixture := newSignedGroupReactionFixture(t, groupID, "reactor-account", from)
	recipients := []string{"recipient-transport"}
	envelopes := []string{
		fixture.envelope(t, "transition-1", "add", stateAdd, "target-1", recipients, recipients),
		fixture.envelope(t, "transition-2", "remove", stateDrop, "target-1", recipients, nil),
		fixture.envelope(t, "transition-3", "add", stateAdd, "target-1", recipients, recipients),
	}
	for index, envelope := range envelopes {
		wantTransitionID := fmt.Sprintf("transition-%d", index+1)
		if got := extractMessageId(envelope); got != wantTransitionID {
			t.Fatalf("custody identity %d = %q, want %q", index, got, wantTransitionID)
		}
	}

	t.Run("memory", func(t *testing.T) {
		backend := newMemoryGroupInboxBackend(500, 7*24*time.Hour)
		for index, envelope := range envelopes {
			result, err := backend.StoreWithRecipients(groupID, from, envelope, recipients)
			if err != nil || result != GroupInboxStoreResultStored {
				t.Fatalf("store transition %d = %q, %v", index, result, err)
			}
		}
		result, err := backend.StoreWithRecipients(groupID, from, envelopes[2], recipients)
		if err != nil || result != GroupInboxStoreResultDuplicate {
			t.Fatalf("exact retry = %q, %v; want duplicate", result, err)
		}
		if got := len(backend.RetrieveSince(groupID, 0)); got != 3 {
			t.Fatalf("memory transition rows = %d, want 3", got)
		}
	})

	t.Run("redis", func(t *testing.T) {
		server := miniredis.RunT(t)
		backendA := newRedisGroupInboxBackend(newTestRedisClient(t, server), "group-transition:", 500, 7*24*time.Hour)
		backendB := newRedisGroupInboxBackend(newTestRedisClient(t, server), "group-transition:", 500, 7*24*time.Hour)
		for index, envelope := range envelopes {
			result, err := backendA.StoreWithRecipients(groupID, from, envelope, recipients)
			if err != nil || result != GroupInboxStoreResultStored {
				t.Fatalf("store transition %d = %q, %v", index, result, err)
			}
		}
		result, err := backendB.StoreWithRecipients(groupID, from, envelopes[2], recipients)
		if err != nil || result != GroupInboxStoreResultDuplicate {
			t.Fatalf("exact retry = %q, %v; want duplicate", result, err)
		}
		if got := len(backendB.RetrieveSince(groupID, 0)); got != 3 {
			t.Fatalf("redis transition rows = %d, want 3", got)
		}
	})
}

func TestGroupReactionCapabilityRolloutAndRollback(t *testing.T) {
	const (
		groupID   = "group-capability-rollout"
		from      = "reactor-transport"
		recipient = "author-transport"
	)
	fixture := newSignedGroupReactionFixture(t, groupID, "reactor-account", from)
	tokens := newMemoryPushTokenStore()
	push := NewPushServiceWithBackend(tokens)
	recorder := newRecordingPushSender()
	push.sender = recorder.Send
	store := NewGroupInboxStore(500, 7*24*time.Hour)
	store.SetPush(push)

	storeEvent := func(eventID string) {
		t.Helper()
		envelope := fixture.envelope(
			t,
			eventID,
			"add",
			"state-"+eventID,
			"target-rollout",
			[]string{recipient},
			[]string{recipient},
		)
		if err := store.StoreWithPushRecipients(groupID, from, envelope, []string{recipient}); err != nil {
			t.Fatalf("store %s: %v", eventID, err)
		}
	}

	tokens.RegisterToken(recipient, "capable-token", "ios", groupReactionCapability)
	storeEvent("rollout-flag-off")
	assertNoAdditionalGroupReactionPush(t, recorder, 0)

	store.SetGroupReactionPushEnabled(true)
	tokens.RegisterToken(recipient, "legacy-token", "ios", directReactionCapability)
	storeEvent("rollout-incapable")
	assertNoAdditionalGroupReactionPush(t, recorder, 0)

	tokens.RegisterToken(
		recipient,
		"group-capable-token",
		"ios",
		directReactionCapability,
		groupReactionCapability,
	)
	storeEvent("rollout-enabled")
	waitForGroupReactionPushes(t, recorder, 1)

	store.SetGroupReactionPushEnabled(false)
	storeEvent("rollout-disabled-again")
	assertNoAdditionalGroupReactionPush(t, recorder, 1)
	if got := len(store.Retrieve(groupID, 0)); got != 4 {
		t.Fatalf("rollout custody rows = %d, want 4", got)
	}

	t.Setenv(groupReactionPushEnabledEnv, "")
	if loadGroupReactionPushEnabledFromEnv() {
		t.Fatal("group reaction push flag must default off")
	}
	t.Setenv(groupReactionPushEnabledEnv, "true")
	if !loadGroupReactionPushEnabledFromEnv() {
		t.Fatal("explicit group reaction flag must enable rollout")
	}
}

func TestGroupReactionExtensionRequiresSortedNotificationRecipients(t *testing.T) {
	fixture := newSignedGroupReactionFixture(t, "group-sorted", "reactor", "reactor-transport")
	replay := []string{"author-a", "author-b"}
	message := fixture.envelope(t, "sorted-event", "add", "state", "target", replay, replay)
	var envelope map[string]interface{}
	if err := json.Unmarshal([]byte(message), &envelope); err != nil {
		t.Fatal(err)
	}
	extension := envelope["notificationExtension"].(map[string]interface{})
	extension["notificationRecipientTransportPeerIds"] = []interface{}{"author-b", "author-a"}
	tampered, err := canonicalGroupReactionJSON(envelope)
	if err != nil {
		t.Fatal(err)
	}
	_, recognized, valid := extractGroupReactionPushMetadata(tampered, "", "", nil)
	if !recognized || valid {
		t.Fatalf("sorted-recipient validation = recognized:%v valid:%v", recognized, valid)
	}
}

func TestGroupReactionExtensionRejectsBaseTamperAndBadSignature(t *testing.T) {
	fixture := newSignedGroupReactionFixture(t, "group-tamper", "reactor", "reactor-transport")
	original := fixture.envelope(
		t,
		"tamper-event",
		"add",
		"tamper-state",
		"tamper-target",
		[]string{"author-device"},
		[]string{"author-device"},
	)
	tests := []struct {
		name   string
		mutate func(map[string]interface{})
	}{
		{
			name: "base envelope hash",
			mutate: func(envelope map[string]interface{}) {
				envelope["ciphertext"] = "tampered-ciphertext"
			},
		},
		{
			name: "extension signature",
			mutate: func(envelope map[string]interface{}) {
				extension := envelope["notificationExtension"].(map[string]interface{})
				extension["signature"] = base64.StdEncoding.EncodeToString(make([]byte, ed25519.SignatureSize))
			},
		},
	}
	for _, testCase := range tests {
		t.Run(testCase.name, func(t *testing.T) {
			var envelope map[string]interface{}
			if err := json.Unmarshal([]byte(original), &envelope); err != nil {
				t.Fatal(err)
			}
			testCase.mutate(envelope)
			tampered, err := canonicalGroupReactionJSON(envelope)
			if err != nil {
				t.Fatal(err)
			}
			_, recognized, valid := extractGroupReactionPushMetadata(tampered, "", "", nil)
			if !recognized || valid {
				t.Fatalf("tamper classification = recognized:%v valid:%v", recognized, valid)
			}
		})
	}
}

func TestGroupReactionCanonicalRecipientSetIsStable(t *testing.T) {
	got := canonicalGroupReactionPeerIDs([]string{" peer-b ", "peer-a", "peer-b"})
	want := []string{"peer-a", "peer-b"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("canonical recipients = %#v, want %#v", got, want)
	}
}

// Plan 309 TC-07 (D1(b)): group-reaction pushes must not carry an FCM collapse
// key at all — the per-group key silently discarded concurrent reactions, and
// per-event keys hit FCM's four-collapse-key cap. Matches the ordinary
// group-message builders, which set no CollapseKey.
func TestRelayNotificationClosure_GroupReactionCollapseKeyOmittedForAndroid(t *testing.T) {
	envelope := `{"kind":"group_offline_replay","version":1,"payloadType":"group_reaction","keyEpoch":1,"messageId":"m-1","ciphertext":"cipher","nonce":"n"}`
	build := func(transition string) *messaging.Message {
		return buildGroupReactionPushMessage(
			"provider-token",
			"group-collapse-verbs",
			envelope,
			groupReactionPushMetadata{
				Action:                 "add",
				TransitionID:           transition,
				TargetMessageID:        "target-1",
				ReactorPeerID:          "peer-reactor",
				ReactorTransportPeerID: "peer-reactor",
			},
		)
	}
	first := build("group-reaction:1:transition")
	second := build("group-reaction:2:transition")
	if first == nil || second == nil {
		t.Fatal("builder returned nil for a valid add reaction")
	}
	if first.Android.CollapseKey != "" || second.Android.CollapseKey != "" {
		t.Fatalf(
			"Android.CollapseKey must be omitted for group reactions; got %q / %q",
			first.Android.CollapseKey,
			second.Android.CollapseKey,
		)
	}
}

// Plan 309 TC-08, INVERTED per the resolved D1b (2026-08-01, industry
// practice): apns-collapse-id is per-EVENT — distinct reactions are never
// merged in transit (closing the iOS half of C2); the id only dedupes
// provider retries of the same event, and ThreadID keeps the visual grouping.
// Mirrors the 1:1 reaction lane's boundedReactionEventIdentity.
func TestRelayNotificationClosure_GroupReactionApnsCollapseIdRemainsPerGroup(t *testing.T) {
	envelope := `{"kind":"group_offline_replay","version":1,"payloadType":"group_reaction","keyEpoch":1,"messageId":"m-2","ciphertext":"cipher","nonce":"n"}`
	build := func(transition string) *messaging.Message {
		return buildGroupReactionPushMessage(
			"provider-token",
			"group-collapse-verbs",
			envelope,
			groupReactionPushMetadata{
				Action:                 "add",
				TransitionID:           transition,
				TargetMessageID:        "target-1",
				ReactorPeerID:          "peer-reactor",
				ReactorTransportPeerID: "peer-reactor",
			},
		)
	}
	first := build("group-reaction:1:transition")
	second := build("group-reaction:2:transition")
	if first == nil || second == nil {
		t.Fatal("builder returned nil for a valid add reaction")
	}
	firstID := first.APNS.Headers["apns-collapse-id"]
	secondID := second.APNS.Headers["apns-collapse-id"]
	if firstID != boundedReactionEventIdentity("group-reaction:1:transition") ||
		secondID != boundedReactionEventIdentity("group-reaction:2:transition") {
		t.Fatalf("apns-collapse-id must be the per-event identity; got %q / %q", firstID, secondID)
	}
	if firstID == secondID {
		t.Fatal("distinct reaction events must never share an apns-collapse-id")
	}
	for _, id := range []string{firstID, secondID} {
		if id == "" || len(id) > 64 {
			t.Fatalf("apns-collapse-id out of bounds: %q", id)
		}
	}
	if first.Android.CollapseKey != "" {
		t.Fatal("Android reaction pushes must stay non-collapsible")
	}
}
