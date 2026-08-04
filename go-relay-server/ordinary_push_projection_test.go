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

// Plan 316 fixtures: ciphertext-bearing envelopes routed through the three
// ordinary send sites, sized per-case. Same-package tests deliberately reuse
// the production budget functions (pushDataSize / messageFitsProviderBudgets /
// providerEquivalentPayloadSize) to assert fixture premises.

func ordinaryChatCiphertextEnvelope(kemLen, cipherLen int) string {
	return fmt.Sprintf(
		`{"type":"chat_message","version":"2","id":"chat-mid-1","encrypted":{"kem":"%s","ciphertext":"%s","nonce":"nonce-1"}}`,
		strings.Repeat("k", kemLen),
		strings.Repeat("c", cipherLen),
	)
}

func ordinaryGroupCiphertextEnvelope(cipherLen int) string {
	return fmt.Sprintf(
		`{"version":"3","type":"group_message","groupId":"88888888-8888-4888-8888-888888888888","messageId":"group-mid-1","senderId":"author","keyEpoch":7,"encrypted":{"ciphertext":"%s","nonce":"n1"}}`,
		strings.Repeat("c", cipherLen),
	)
}

func ordinaryDirectReactionEnvelope(kemLen, cipherLen int) string {
	return fmt.Sprintf(
		`{"type":"message_reaction","version":"2","eventId":"evt-1","action":"add","targetMessageId":"msg-1","senderPeerId":"reactor-peer","encrypted":{"kem":"%s","ciphertext":"%s","nonce":"nn"}}`,
		strings.Repeat("k", kemLen),
		strings.Repeat("c", cipherLen),
	)
}

func ordinaryPushService(platform string) (*PushService, *recordingPushSender) {
	tokens := newMemoryPushTokenStore()
	tokens.RegisterToken("recipient", "recipient-token", platform,
		directReactionCapability, groupReactionCapability)
	push := NewPushServiceWithBackend(tokens)
	push.retryDelays = []time.Duration{0, 0}
	recorder := newRecordingPushSender()
	push.sender = recorder.Send
	return push, recorder
}

// sentRoutingString reads a routing key from the platform copy the projected
// message actually carries: the FCM data map when present, else the APNs
// CustomData copy — mirroring how recipients (and the strict-fallback rescue)
// consume post-projection messages.
func sentRoutingString(msg *messaging.Message, key string) string {
	if value, ok := msg.Data[key]; ok {
		return value
	}
	if msg.APNS != nil && msg.APNS.Payload != nil {
		if value, ok := msg.APNS.Payload.CustomData[key].(string); ok {
			return value
		}
	}
	return ""
}

func sentRoutingHas(msg *messaging.Message, key string) bool {
	if _, ok := msg.Data[key]; ok {
		return true
	}
	if msg.APNS != nil && msg.APNS.Payload != nil {
		if _, ok := msg.APNS.Payload.CustomData[key]; ok {
			return true
		}
	}
	return false
}

func apnsCustomDataAsStringMap(msg *messaging.Message) map[string]string {
	result := map[string]string{}
	if msg.APNS == nil || msg.APNS.Payload == nil {
		return result
	}
	for key, value := range msg.APNS.Payload.CustomData {
		if text, ok := value.(string); ok {
			result[key] = text
		}
	}
	return result
}

func wholeMessageMarshalLen(t *testing.T, msg *messaging.Message) int {
	t.Helper()
	raw, err := json.Marshal(msg)
	if err != nil {
		t.Fatalf("marshal captured message: %v", err)
	}
	return len(raw)
}

// TC-01 — android projection strips APNS on both ordinary lanes; the FCM leg
// is byte-identical to the un-projected build's.
func TestRelayNotificationClosure_OrdinaryPushAndroidProjectionStripsApns(t *testing.T) {
	envelopeChat := ordinaryChatCiphertextEnvelope(400, 600)
	envelopeGroup := ordinaryGroupCiphertextEnvelope(600)

	push, recorder := ordinaryPushService("android")
	push.SendNotification(context.Background(), "recipient", "sender-peer", envelopeChat)
	push.SendGroupNotification(
		context.Background(),
		"recipient",
		"88888888-8888-4888-8888-888888888888",
		"12D3KooWSenderTransport",
		"group-mid-1",
		envelopeGroup,
	)

	messages := recorder.Messages()
	if len(messages) != 2 {
		t.Fatalf("send calls = %d, want 2", len(messages))
	}
	unprojectedChat := buildPushMessage("recipient-token", "sender-peer", envelopeChat)
	unprojectedGroup := buildGroupPushMessage(
		"recipient-token",
		"88888888-8888-4888-8888-888888888888",
		"12D3KooWSenderTransport",
		"group-mid-1",
		envelopeGroup,
	)
	for index, pair := range []struct {
		sent, unprojected *messaging.Message
	}{{messages[0], unprojectedChat}, {messages[1], unprojectedGroup}} {
		if pair.sent.APNS != nil {
			t.Fatalf("message %d: android-projected APNS = %#v, want nil", index, pair.sent.APNS)
		}
		sentData, _ := json.Marshal(pair.sent.Data)
		wantData, _ := json.Marshal(pair.unprojected.Data)
		if string(sentData) != string(wantData) {
			t.Fatalf("message %d: android Data diverged from un-projected build", index)
		}
	}
}

// TC-02 — ios projection drops Android AND the duplicate Data map when the
// APNs CustomData copy is present; CustomData stays marshal-equal.
func TestRelayNotificationClosure_OrdinaryPushIosProjectionDropsDuplicateData(t *testing.T) {
	envelope := ordinaryChatCiphertextEnvelope(400, 600)
	push, recorder := ordinaryPushService("ios")
	push.SendNotification(context.Background(), "recipient", "sender-peer", envelope)

	if got := recorder.SendCallCount(); got != 1 {
		t.Fatalf("send calls = %d, want 1", got)
	}
	sent := recorder.Messages()[0]
	if sent.Android != nil {
		t.Fatalf("ios-projected Android = %#v, want nil", sent.Android)
	}
	if sent.Data != nil {
		t.Fatalf("ios-projected Data = %#v, want nil (CustomData authoritative)", sent.Data)
	}
	unprojected := buildPushMessage("recipient-token", "sender-peer", envelope)
	sentCustom, _ := json.Marshal(sent.APNS.Payload.CustomData)
	wantCustom, _ := json.Marshal(unprojected.APNS.Payload.CustomData)
	if string(sentCustom) != string(wantCustom) {
		t.Fatalf("ios CustomData diverged from un-projected build")
	}
}

// TC-03 — the mid-band class: each un-projected leg passes the relay budget
// while json.Marshal of the whole un-projected message exceeds 4096; the
// EMITTED message must marshal <= 4096 and keep the ciphertext route.
func TestRelayNotificationClosure_OrdinaryPushMidBandFitsCombinedLimit(t *testing.T) {
	envelope := ordinaryChatCiphertextEnvelope(1400, 1500)

	unprojected := buildPushMessage("recipient-token", "sender-peer", envelope)
	sizes, err := providerEquivalentPayloadSize(unprojected)
	if err != nil {
		t.Fatalf("premise sizing failed: %v", err)
	}
	if sizes.FCM > maxProviderPayloadBytes || sizes.APNS > maxProviderPayloadBytes {
		t.Fatalf("fixture premise broken: legs FCM=%d APNS=%d must each be <= %d",
			sizes.FCM, sizes.APNS, maxProviderPayloadBytes)
	}
	if whole := wholeMessageMarshalLen(t, unprojected); whole <= 4096 {
		t.Fatalf("fixture premise broken: un-projected whole marshal = %d, want > 4096", whole)
	}
	if unprojected.Data["preview_unavailable"] == "1" {
		t.Fatalf("fixture premise broken: pre-check downgraded the envelope")
	}

	for _, platform := range []string{"android", "ios"} {
		push, recorder := ordinaryPushService(platform)
		push.SendNotification(context.Background(), "recipient", "sender-peer", envelope)
		if got := recorder.SendCallCount(); got != 1 {
			t.Fatalf("%s: send calls = %d, want 1", platform, got)
		}
		sent := recorder.Messages()[0]
		if whole := wholeMessageMarshalLen(t, sent); whole > 4096 {
			t.Fatalf("%s: emitted whole marshal = %d, want <= 4096", platform, whole)
		}
		if platform == "android" && sent.Data["preview_unavailable"] == "1" {
			t.Fatalf("android: mid-band downgraded to preview_unavailable")
		}
	}
}

// TC-04 — visible-copy routes (no CustomData) KEEP Data on ios so tap-routing
// keys survive, and the alert stays intact on the same message.
func TestRelayNotificationClosure_OrdinaryPushIosVisibleRouteKeepsData(t *testing.T) {
	envelope := `{"type":"group_invite","version":"2","id":"invite-1","senderPeerId":"peer-from","senderUsername":"Alice","groupId":"group-1","groupName":"Book Club","encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}}`
	push, recorder := ordinaryPushService("ios")
	push.SendNotification(context.Background(), "recipient", "peer-from", envelope)

	sent := recorder.Messages()[0]
	if sent.Android != nil {
		t.Fatalf("ios-projected Android = %#v, want nil", sent.Android)
	}
	if sent.Data == nil || sent.Data["type"] != "group_invite" || sent.Data["groupId"] != "group-1" {
		t.Fatalf("visible-route Data lost on ios: %#v", sent.Data)
	}
	if sent.APNS == nil || sent.APNS.Payload == nil || sent.APNS.Payload.Aps == nil ||
		sent.APNS.Payload.Aps.Alert == nil {
		t.Fatalf("visible-route APNs alert lost on ios")
	}
}

// TC-05 — the 1:1 reaction lane projects per platform, and its builder now
// refuses an envelope whose single marshalled leg exceeds the provider budget.
func TestRelayNotificationClosure_OrdinaryPushDirectReactionProjected(t *testing.T) {
	envelope := ordinaryDirectReactionEnvelope(400, 600)

	for _, tc := range []struct {
		platform string
		check    func(t *testing.T, sent *messaging.Message)
	}{
		{"android", func(t *testing.T, sent *messaging.Message) {
			if sent.APNS != nil {
				t.Fatalf("android reaction kept APNS: %#v", sent.APNS)
			}
			if sent.Data["event_id"] != "evt-1" {
				t.Fatalf("android reaction Data lost: %#v", sent.Data)
			}
		}},
		{"ios", func(t *testing.T, sent *messaging.Message) {
			if sent.Android != nil || sent.Data != nil {
				t.Fatalf("ios reaction kept Android/Data: %#v / %#v", sent.Android, sent.Data)
			}
			assertAPNSCustomString(t, sent, "event_id", "evt-1")
		}},
	} {
		push, recorder := ordinaryPushService(tc.platform)
		push.SendReactionNotification(context.Background(), "recipient", "reactor-peer", envelope)
		if got := recorder.SendCallCount(); got != 1 {
			t.Fatalf("%s: send calls = %d, want 1", tc.platform, got)
		}
		tc.check(t, recorder.Messages()[0])
	}

	// Over-budget sub-case: raw data cap passes (<=4000) while the marshalled
	// FCM leg exceeds maxProviderPayloadBytes -> the builder must refuse (nil).
	overBudget := ordinaryDirectReactionEnvelope(1400, 2350)
	probe := buildReactionPushMessage("recipient-token", "reactor-peer", overBudget)
	if probe != nil {
		rawData := map[string]string{}
		for key, value := range probe.Data {
			rawData[key] = value
		}
		if pushDataSize(rawData) > maxPushDataBytes {
			t.Fatalf("fixture premise broken: raw data size exceeds the data cap")
		}
		sizes, err := providerEquivalentPayloadSize(probe)
		if err != nil || sizes.FCM <= maxProviderPayloadBytes {
			t.Fatalf("fixture premise broken: FCM leg = %d err=%v, want > %d",
				sizes.FCM, err, maxProviderPayloadBytes)
		}
		t.Fatalf("over-budget reaction envelope built a message; want nil (reaction_invalid)")
	}
}

// TC-06 — platform-string robustness: mixed-case values normalize and project;
// unknown/empty values fail open to today's dual-copy shape.
func TestRelayNotificationClosure_OrdinaryPushPlatformNormalization(t *testing.T) {
	envelope := ordinaryChatCiphertextEnvelope(400, 600)
	unprojected := buildPushMessage("recipient-token", "sender-peer", envelope)

	for _, tc := range []struct {
		platform  string
		projected bool
	}{
		{"iOS", true},
		{" ANDROID ", true},
		{"web", false},
		{"", false},
	} {
		push, recorder := ordinaryPushService(tc.platform)
		push.SendNotification(context.Background(), "recipient", "sender-peer", envelope)
		sent := recorder.Messages()[0]
		if tc.projected {
			if sent.Android != nil && sent.APNS != nil {
				t.Fatalf("platform %q: expected projection, got dual-copy", tc.platform)
			}
			continue
		}
		sentRaw, _ := json.Marshal(sent)
		wantRaw, _ := json.Marshal(unprojected)
		if string(sentRaw) != string(wantRaw) {
			t.Fatalf("platform %q: fail-open shape diverged from dual-copy", tc.platform)
		}
	}
}

// TC-09 — an ios-projected CHAT push that the provider still rejects for size
// must be rescued by the strict routing fallback (routing sourced from the
// APNs CustomData copy once Data is projected away).
func TestRelayNotificationClosure_OrdinaryPushIosProjectedRejectionStillRescues(t *testing.T) {
	envelope := ordinaryChatCiphertextEnvelope(400, 600)
	push, recorder := ordinaryPushService("ios")
	recorder.onSend = func(_ context.Context, _ *messaging.Message) (string, error) {
		if recorder.SendCallCount() == 1 {
			return "", fmt.Errorf("messaging/invalid-argument: Message is too large. The maximum is 4K (4096 bytes)")
		}
		return "fallback-id", nil
	}

	push.SendNotification(context.Background(), "recipient", "sender-peer", envelope)

	if got := recorder.SendCallCount(); got != 2 {
		t.Fatalf("send calls = %d, want original + strict fallback", got)
	}
	strict := recorder.Messages()[1]
	if strict.Data["type"] != "new_message" ||
		strict.Data["sender_id"] != "sender-peer" ||
		strict.Data["preview_unavailable"] != "1" {
		t.Fatalf("strict fallback routing = %#v", strict.Data)
	}
}

// TC-10 — the ios reaction push carries the FULL routing set in the APNs
// CustomData copy (the invariant the relocated inbox_test assertions pin).
func TestRelayNotificationClosure_OrdinaryPushIosReactionRoutingInCustomData(t *testing.T) {
	envelope := ordinaryDirectReactionEnvelope(400, 600)
	push, recorder := ordinaryPushService("ios")
	push.SendReactionNotification(context.Background(), "recipient", "reactor-peer", envelope)

	sent := recorder.Messages()[0]
	for key, want := range map[string]string{
		"type":              "message_reaction",
		"sender_id":         "reactor-peer",
		"event_id":          "evt-1",
		"target_message_id": "msg-1",
		"action":            "add",
	} {
		assertAPNSCustomString(t, sent, key, want)
	}
}

// TC-331-14 — every current ciphertext-bearing relay producer retains its
// canonical outer identity through the platform projection boundary. Missing
// outer-ID recovery is therefore a test-only transport-mutation robustness
// case, not an ordinary relay payload shape.
func TestRelayNotificationClosure_DecryptablePayloadRetainsCanonicalOuterIdentity(t *testing.T) {
	const (
		groupID            = "33133133-1331-4331-8331-331331331331"
		reactorAccount     = "reactor-account"
		reactorTransport   = "reactor-transport"
		recipientTransport = "recipient-transport"
	)

	groupReactionFixture := newSignedGroupReactionFixture(
		t,
		groupID,
		reactorAccount,
		reactorTransport,
	)
	groupReactionEnvelope := groupReactionFixture.envelope(
		t,
		"group-event-1",
		"add",
		"group-base-1",
		"group-target-1",
		[]string{reactorTransport, recipientTransport},
		[]string{recipientTransport},
	)
	groupReactionMetadata, recognized, valid := extractGroupReactionPushMetadata(
		groupReactionEnvelope,
		groupID,
		reactorTransport,
		[]string{reactorTransport, recipientTransport},
	)
	if !recognized || !valid {
		t.Fatal("production-format group reaction fixture must validate")
	}

	cases := []struct {
		name               string
		canonicalKey       string
		canonicalID        string
		requiredCipherKeys []string
		build              func() *messaging.Message
	}{
		{
			name:               "direct message",
			canonicalKey:       "message_id",
			canonicalID:        "chat-mid-1",
			requiredCipherKeys: []string{"kem", "ciphertext", "nonce"},
			build: func() *messaging.Message {
				return buildPushMessage(
					"provider-token",
					"sender-peer",
					ordinaryChatCiphertextEnvelope(8, 16),
				)
			},
		},
		{
			name:               "group message",
			canonicalKey:       "message_id",
			canonicalID:        "group-mid-1",
			requiredCipherKeys: []string{"ciphertext", "nonce", "keyEpoch"},
			build: func() *messaging.Message {
				return buildGroupPushMessage(
					"provider-token",
					groupID,
					"sender-transport",
					"group-mid-1",
					ordinaryGroupCiphertextEnvelope(16),
				)
			},
		},
		{
			name:               "direct reaction",
			canonicalKey:       "event_id",
			canonicalID:        "evt-1",
			requiredCipherKeys: []string{"kem", "ciphertext", "nonce"},
			build: func() *messaging.Message {
				return buildReactionPushMessage(
					"provider-token",
					"reactor-peer",
					ordinaryDirectReactionEnvelope(8, 16),
				)
			},
		},
		{
			name:               "group reaction",
			canonicalKey:       "event_id",
			canonicalID:        "group-event-1",
			requiredCipherKeys: []string{"ciphertext", "nonce", "keyEpoch"},
			build: func() *messaging.Message {
				return buildGroupReactionPushMessage(
					"provider-token",
					groupID,
					groupReactionEnvelope,
					groupReactionMetadata,
				)
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			for _, platform := range []string{"android", "ios"} {
				t.Run(platform, func(t *testing.T) {
					projected := projectPushMessageForPlatform(tc.build(), platform)
					if projected == nil {
						t.Fatal("ciphertext-bearing producer returned nil")
					}
					if got := sentRoutingString(projected, tc.canonicalKey); got != tc.canonicalID {
						t.Fatalf("%s = %q, want %q", tc.canonicalKey, got, tc.canonicalID)
					}
					for _, key := range tc.requiredCipherKeys {
						if got := sentRoutingString(projected, key); got == "" {
							t.Fatalf("decryptable routing key %q was removed", key)
						}
					}
					if sentRoutingHas(projected, "preview_unavailable") {
						t.Fatal("decryptable fixture unexpectedly became a generic fallback")
					}
				})
			}
		})
	}
}
