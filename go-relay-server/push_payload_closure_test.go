package main

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"testing"
	"time"

	"firebase.google.com/go/v4/messaging"
)

const (
	closureDirectGroupID       = "66666666-6666-4666-8666-666666666666"
	closureDiscussionGroupID   = "77777777-7777-4777-8777-777777777777"
	closureAnnouncementGroupID = "88888888-8888-4888-8888-888888888888"
)

func TestRelayNotificationClosure_NormalGroupProjectionsUseAuthenticatedTransport(t *testing.T) {
	tests := []struct {
		name      string
		groupID   string
		messageID string
		envelope  string
	}{
		{
			name:      "v1 discussion",
			groupID:   closureDiscussionGroupID,
			messageID: "v1-message",
			envelope:  `{"kind":"group_offline_replay","version":1,"payloadType":"group_message","keyEpoch":7,"messageId":"v1-message","ciphertext":"v1-ct","nonce":"v1-nonce","senderId":"forged-account"}`,
		},
		{
			name:      "v3 discussion",
			groupID:   closureDirectGroupID,
			messageID: "v3-message",
			envelope:  `{"version":"3","type":"group_message","groupId":"66666666-6666-4666-8666-666666666666","messageId":"v3-message","senderId":"forged-account","senderPublicKey":"pub","signature":"sig","keyEpoch":7,"encrypted":{"ciphertext":"v3-ct","nonce":"v3-nonce"}}`,
		},
		{
			name:      "announcement shared route",
			groupID:   closureAnnouncementGroupID,
			messageID: "announcement-message",
			envelope:  `{"version":"3","type":"group_message","groupId":"88888888-8888-4888-8888-888888888888","messageId":"announcement-message","senderId":"forged-admin-account","senderPublicKey":"pub","signature":"sig","keyEpoch":7,"encrypted":{"ciphertext":"announcement-ct","nonce":"announcement-nonce"}}`,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			msg := buildGroupPushMessage(
				"fcm-token",
				tc.groupID,
				"12D3KooWAuthenticatedDeviceTransport",
				tc.messageID,
				tc.envelope,
			)
			if msg == nil {
				t.Fatal("normal group projection was refused")
			}
			if got := msg.Data["sender_transport_peer_id"]; got != "12D3KooWAuthenticatedDeviceTransport" {
				t.Fatalf("sender_transport_peer_id = %q", got)
			}
			if _, ok := msg.Data["sender_id"]; ok {
				t.Fatalf("authenticated device transport must never be labeled sender_id: %#v", msg.Data)
			}
			assertAPNSCustomString(t, msg, "sender_transport_peer_id", "12D3KooWAuthenticatedDeviceTransport")
			if _, ok := msg.APNS.Payload.CustomData["sender_id"]; ok {
				t.Fatalf("APNS custom data mislabeled authenticated transport: %#v", msg.APNS.Payload.CustomData)
			}
			assertProviderPayloadWithinBudget(t, msg)
		})
	}
}

func TestRelayNotificationClosure_OversizedDirectGroupAndAnnouncementStayRoutable(t *testing.T) {
	bigCiphertext := strings.Repeat("c", 6000)
	bigKEM := strings.Repeat("k", 1500)
	direct := buildPushMessage(
		"fcm-token",
		"12D3KooWDirectTransport",
		fmt.Sprintf(`{"type":"chat_message","version":"2","id":"direct-media","encrypted":{"kem":%q,"ciphertext":%q,"nonce":"n"}}`, bigKEM, bigCiphertext),
	)

	groups := []*messaging.Message{
		buildGroupPushMessage(
			"fcm-token",
			closureDiscussionGroupID,
			"12D3KooWGroupTransport",
			"group-media",
			fmt.Sprintf(`{"kind":"group_offline_replay","version":1,"payloadType":"group_message","keyEpoch":7,"messageId":"group-media","ciphertext":%q,"nonce":"n"}`, bigCiphertext),
		),
		buildGroupPushMessage(
			"fcm-token",
			closureAnnouncementGroupID,
			"12D3KooWAnnouncementTransport",
			"announcement-media",
			fmt.Sprintf(`{"version":"3","type":"group_message","groupId":%q,"messageId":"announcement-media","senderId":"forged-admin","keyEpoch":7,"encrypted":{"ciphertext":%q,"nonce":"n"}}`, closureAnnouncementGroupID, bigCiphertext),
		),
	}

	assertRoutingOnlyOversizedMessage(t, direct, "new_message")
	if direct.Data["sender_id"] != "12D3KooWDirectTransport" {
		t.Fatalf("direct sender route = %q", direct.Data["sender_id"])
	}
	for _, msg := range groups {
		assertRoutingOnlyOversizedMessage(t, msg, "group_message")
		if msg.Data["sender_transport_peer_id"] == "" {
			t.Fatal("oversized group route lost authenticated sender transport")
		}
		if _, ok := msg.Data["sender_id"]; ok {
			t.Fatalf("oversized group route mislabeled transport: %#v", msg.Data)
		}
		assertAPNSCustomString(t, msg, "sender_transport_peer_id", msg.Data["sender_transport_peer_id"])
		if _, ok := msg.APNS.Payload.CustomData["sender_id"]; ok {
			t.Fatalf("oversized APNS route mislabeled transport: %#v", msg.APNS.Payload.CustomData)
		}
	}
}

func TestRelayNotificationClosure_ProviderBoundaryUsesCompleteSerializedPayloads(t *testing.T) {
	lastNormal, firstFallback := findDirectProviderBoundary(t)
	if lastNormal.Data["preview_unavailable"] == "1" {
		t.Fatal("boundary predecessor unexpectedly used generic fallback")
	}
	if firstFallback.Data["preview_unavailable"] != "1" {
		t.Fatal("first over-budget message did not use generic fallback")
	}
	assertProviderPayloadWithinBudget(t, lastNormal)
	assertProviderPayloadWithinBudget(t, firstFallback)

	groupNormal, groupFallback := findGroupProviderBoundary(t)
	if groupNormal.Data["preview_unavailable"] == "1" || groupFallback.Data["preview_unavailable"] != "1" {
		t.Fatalf("group boundary did not transition normal->fallback: %#v / %#v", groupNormal.Data, groupFallback.Data)
	}
	assertProviderPayloadWithinBudget(t, groupNormal)
	assertProviderPayloadWithinBudget(t, groupFallback)
}

func TestRelayNotificationClosure_GroupStoreProjectsRemoteTransportNotEnvelopeSender(t *testing.T) {
	tokenStore := newMemoryPushTokenStore()
	push := NewPushServiceWithBackend(tokenStore)
	recorder := newRecordingPushSender()
	push.sender = recorder.Send
	groupInbox := NewGroupInboxStore(500, 7*24*time.Hour)
	groupInbox.SetPush(push)
	inbox := NewInboxStore(push)
	env := setupInboxStreamEnv(t, inbox, groupInbox)

	remoteTransport := env.sender.ID().String()
	recipient := env.recipient.ID().String()
	tokenStore.RegisterToken(recipient, "recipient-token", "android")

	stream, err := env.sender.NewStream(context.Background(), env.server.ID(), InboxProtocol)
	if err != nil {
		t.Fatalf("open group_store stream: %v", err)
	}
	defer stream.Close()
	sendInboxReq(t, stream, inboxRequest{
		Action:  "group_store",
		GroupId: closureDiscussionGroupID,
		From:    remoteTransport,
		Message: `{"version":"3","type":"group_message","groupId":"77777777-7777-4777-8777-777777777777","messageId":"auth-transport-message","senderId":"forged-account-sender","keyEpoch":7,"encrypted":{"ciphertext":"ct","nonce":"n"}}`,
		RecipientPeerIds: []string{
			remoteTransport,
			recipient,
		},
	})
	if resp := recvInboxResp(t, stream); resp.Status != "OK" {
		t.Fatalf("group_store response = %#v", resp)
	}

	select {
	case <-recorder.sentSignal:
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for group push")
	}
	msg := recorder.LastMessage()
	if msg == nil || msg.Data["sender_transport_peer_id"] != remoteTransport {
		t.Fatalf("push transport = %#v, want authenticated remote %q", msg, remoteTransport)
	}
	if _, ok := msg.Data["sender_id"]; ok {
		t.Fatalf("forged envelope sender became relay sender_id: %#v", msg.Data)
	}
}

func TestRelayNotificationClosure_GroupStoreRejectsNonCanonicalAndOverlongIDs(t *testing.T) {
	push := NewPushServiceWithBackend(newMemoryPushTokenStore())
	inbox := NewInboxStore(push)
	groupInbox := NewGroupInboxStore(500, 7*24*time.Hour)
	env := setupInboxStreamEnv(t, inbox, groupInbox)

	for _, groupID := range []string{
		"legacy-group-id",
		strings.ToUpper("abcdefab-cdef-4abc-8def-abcdefabcdef"),
		strings.Repeat("a", maxPushDataBytes+1),
		"00000000-0000-0000-0000-000000000000",
	} {
		stream, err := env.sender.NewStream(context.Background(), env.server.ID(), InboxProtocol)
		if err != nil {
			t.Fatalf("open group_store stream: %v", err)
		}
		sendInboxReq(t, stream, inboxRequest{
			Action:           "group_store",
			GroupId:          groupID,
			From:             env.sender.ID().String(),
			Message:          `{"kind":"group_offline_replay","messageId":"bad-group"}`,
			RecipientPeerIds: []string{env.recipient.ID().String()},
		})
		resp := recvInboxResp(t, stream)
		stream.Close()
		if resp.Status != "ERROR" || resp.Error != "invalid groupId" {
			t.Fatalf("groupId %q response = %#v", groupID, resp)
		}
		if stored := groupInbox.Retrieve(groupID, 0); len(stored) != 0 {
			t.Fatalf("invalid groupId %q stored %d messages", groupID, len(stored))
		}
	}
}

func TestRelayNotificationClosure_RequiredGroupRoutingThatCannotFitIsRefused(t *testing.T) {
	msg := buildGroupPushMessage(
		"fcm-token",
		strings.Repeat("g", maxProviderPayloadBytes+1),
		"12D3KooWAuthenticatedDeviceTransport",
		"message-id",
		`{"kind":"group_offline_replay","version":1,"payloadType":"group_message","keyEpoch":7,"messageId":"message-id","ciphertext":"ct","nonce":"n"}`,
	)
	if msg != nil {
		t.Fatalf("unbounded required group routing produced a provider payload: %#v", msg.Data)
	}
}

func TestRelayNotificationClosure_ProviderTooLargeGetsOneStrictFallback(t *testing.T) {
	tests := []struct {
		name               string
		fallbackShouldFail bool
	}{
		{name: "fallback succeeds"},
		{name: "fallback failure is not retried", fallbackShouldFail: true},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			tokens := newMemoryPushTokenStore()
			tokens.RegisterToken("recipient", "recipient-token", "android")
			push := NewPushServiceWithBackend(tokens)
			push.retryDelays = []time.Duration{0, 0, 0}
			recorder := newRecordingPushSender()
			push.sender = recorder.Send
			recorder.onSend = func(_ context.Context, _ *messaging.Message) (string, error) {
				if recorder.SendCallCount() == 1 || tc.fallbackShouldFail {
					return "", fmt.Errorf("messaging/invalid-argument: Message is too large. The maximum is 4K (4096 bytes)")
				}
				return "fallback-message-id", nil
			}

			push.SendNotification(
				context.Background(),
				"recipient",
				"12D3KooWProviderTransport",
				`{"type":"chat_message","version":"2","id":"provider-size-message","encrypted":{"kem":"kem","ciphertext":"ciphertext","nonce":"nonce"}}`,
			)

			if got := recorder.SendCallCount(); got != 2 {
				t.Fatalf("provider send calls = %d, want exactly original + one strict fallback", got)
			}
			messages := recorder.Messages()
			strict := messages[1]
			if strict.Data["preview_unavailable"] != "1" || strict.Data["sender_id"] == "" {
				t.Fatalf("strict fallback routing = %#v", strict.Data)
			}
			if _, ok := strict.Data["message_id"]; ok {
				t.Fatalf("strict provider fallback retained optional message_id: %#v", strict.Data)
			}
			assertProviderPayloadWithinBudget(t, strict)
		})
	}

	t.Run("announcement fallback keeps authenticated group route", func(t *testing.T) {
		tokens := newMemoryPushTokenStore()
		tokens.RegisterToken("recipient", "recipient-token", "ios")
		push := NewPushServiceWithBackend(tokens)
		push.retryDelays = []time.Duration{0, 0, 0}
		recorder := newRecordingPushSender()
		push.sender = recorder.Send
		recorder.onSend = func(_ context.Context, _ *messaging.Message) (string, error) {
			if recorder.SendCallCount() == 1 {
				return "", fmt.Errorf("messaging/invalid-argument: Message is too large. The maximum is 4K (4096 bytes)")
			}
			return "fallback-message-id", nil
		}

		push.SendGroupNotification(
			context.Background(),
			"recipient",
			closureAnnouncementGroupID,
			"12D3KooWAuthenticatedAnnouncementTransport",
			"announcement-provider-size",
			`{"version":"3","type":"group_message","groupId":"88888888-8888-4888-8888-888888888888","messageId":"announcement-provider-size","senderId":"forged-admin","keyEpoch":7,"encrypted":{"ciphertext":"ct","nonce":"n"}}`,
		)

		if got := recorder.SendCallCount(); got != 2 {
			t.Fatalf("announcement provider send calls = %d, want original + one strict fallback", got)
		}
		strict := recorder.Messages()[1]
		if strict.Data["type"] != "group_message" ||
			strict.Data["groupId"] != closureAnnouncementGroupID ||
			strict.Data["sender_transport_peer_id"] != "12D3KooWAuthenticatedAnnouncementTransport" ||
			strict.Data["preview_unavailable"] != "1" || len(strict.Data) != 4 {
			t.Fatalf("strict announcement routing = %#v", strict.Data)
		}
		if _, ok := strict.Data["sender_id"]; ok {
			t.Fatalf("strict announcement route mislabeled transport: %#v", strict.Data)
		}
		assertAPNSCustomString(t, strict, "sender_transport_peer_id", "12D3KooWAuthenticatedAnnouncementTransport")
		assertProviderPayloadWithinBudget(t, strict)
	})
}

func TestRelayNotificationClosure_CanonicalGroupIDContract(t *testing.T) {
	if !isCanonicalGroupID(closureDiscussionGroupID) {
		t.Fatal("production UUIDv4 group ID was rejected")
	}
	for _, value := range []string{
		"",
		"legacy-group",
		strings.ToUpper("abcdefab-cdef-4abc-8def-abcdefabcdef"),
		"77777777-7777-1777-8777-777777777777",
		"00000000-0000-0000-0000-000000000000",
	} {
		if isCanonicalGroupID(value) {
			t.Fatalf("noncanonical group ID accepted: %q", value)
		}
	}
}

func assertRoutingOnlyOversizedMessage(t *testing.T, msg *messaging.Message, wantType string) {
	t.Helper()
	if msg == nil {
		t.Fatal("oversized message was refused despite bounded required routing")
	}
	if msg.Data["type"] != wantType || msg.Data["preview_unavailable"] != "1" {
		t.Fatalf("oversized route = %#v", msg.Data)
	}
	if msg.Notification != nil || msg.Android == nil || msg.Android.Notification != nil {
		t.Fatal("Android oversized fallback must remain routing-only")
	}
	if msg.APNS == nil || msg.APNS.Payload == nil || msg.APNS.Payload.Aps == nil || msg.APNS.Payload.Aps.Alert == nil {
		t.Fatal("APNS oversized fallback must remain alert-class")
	}
	if !msg.APNS.Payload.Aps.MutableContent {
		t.Fatal("APNS oversized fallback must remain NSE-reachable for recipient policy")
	}
	if msg.Data["ciphertext"] != "" || msg.Data["nonce"] != "" || msg.Data["kem"] != "" {
		t.Fatalf("oversized fallback leaked encrypted payload: %#v", msg.Data)
	}
	assertProviderPayloadWithinBudget(t, msg)
}

func assertProviderPayloadWithinBudget(t *testing.T, msg *messaging.Message) {
	t.Helper()
	sizes, err := providerEquivalentPayloadSize(msg)
	if err != nil {
		t.Fatalf("provider payload marshal: %v", err)
	}
	if sizes.FCM > maxProviderPayloadBytes || sizes.APNS > maxProviderPayloadBytes {
		t.Fatalf("provider payload sizes = FCM %d, APNS %d; budget %d", sizes.FCM, sizes.APNS, maxProviderPayloadBytes)
	}
	if msg.APNS != nil && msg.APNS.Payload != nil {
		encoded, err := json.Marshal(msg.APNS.Payload)
		if err != nil {
			t.Fatalf("marshal full APNS payload: %v", err)
		}
		if len(encoded) != sizes.APNS {
			t.Fatalf("APNS measurement = %d, actual serialized payload = %d", sizes.APNS, len(encoded))
		}
	}
}

func findDirectProviderBoundary(t *testing.T) (*messaging.Message, *messaging.Message) {
	t.Helper()
	var previous *messaging.Message
	for size := 1; size <= maxPushDataBytes*2; size++ {
		msg := buildPushMessage(
			"fcm-token",
			"12D3KooWBoundaryDirect",
			fmt.Sprintf(`{"type":"chat_message","version":"2","id":"direct-boundary","encrypted":{"kem":"kem","ciphertext":%q,"nonce":"nonce"}}`, strings.Repeat("c", size)),
		)
		if msg == nil {
			t.Fatal("direct boundary required routing was refused")
		}
		if msg.Data["preview_unavailable"] == "1" {
			if previous == nil {
				t.Fatal("direct boundary had no normal predecessor")
			}
			return previous, msg
		}
		previous = msg
	}
	t.Fatal("direct provider boundary not found")
	return nil, nil
}

func findGroupProviderBoundary(t *testing.T) (*messaging.Message, *messaging.Message) {
	t.Helper()
	var previous *messaging.Message
	for size := 1; size <= maxPushDataBytes*2; size++ {
		msg := buildGroupPushMessage(
			"fcm-token",
			closureDiscussionGroupID,
			"12D3KooWBoundaryGroup",
			"group-boundary",
			fmt.Sprintf(`{"kind":"group_offline_replay","version":1,"payloadType":"group_message","keyEpoch":7,"messageId":"group-boundary","ciphertext":%q,"nonce":"nonce"}`, strings.Repeat("c", size)),
		)
		if msg == nil {
			t.Fatal("group boundary required routing was refused")
		}
		if msg.Data["preview_unavailable"] == "1" {
			if previous == nil {
				t.Fatal("group boundary had no normal predecessor")
			}
			return previous, msg
		}
		previous = msg
	}
	t.Fatal("group provider boundary not found")
	return nil, nil
}
