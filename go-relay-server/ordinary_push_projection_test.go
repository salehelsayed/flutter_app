package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"firebase.google.com/go/v4/messaging"
	"github.com/prometheus/client_golang/prometheus/testutil"
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

type retainingRevokedPushRouteBackend struct {
	PushTokenBackend
}

func (b *retainingRevokedPushRouteBackend) RevokeIfCurrent(pushRouteLease) (bool, error) {
	return true, nil
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

type tc395PreflightCapableInboxBackend struct {
	InboxBackend
}

func (b *tc395PreflightCapableInboxBackend) StoreWithWakeOutcome(
	_ string,
	_ inboxMessage,
	_ wakeOutcomeAdmission,
) (InboxStoreResult, wakeOutcomeAdmissionStatus, error) {
	return "", "", fmt.Errorf("TC-395-01 fixture unexpectedly admitted a wake outcome")
}

func tc395GroupInviteEnvelope(inviteID string) string {
	return fmt.Sprintf(
		`{"type":"group_invite","version":"2","id":%q,"senderPeerId":"peer-from","senderUsername":"Alice","groupId":"group-395","groupName":"Book Club","encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}}`,
		inviteID,
	)
}

func tc396DirectMessageEnvelope(messageID string) string {
	return fmt.Sprintf(
		`{"type":"chat_message","version":"2","id":%q,"senderPeerId":"peer-from","encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}}`,
		messageID,
	)
}

func tc395WaitForProviderCalls(
	t *testing.T,
	recorder *recordingPushSender,
	want int,
) {
	t.Helper()
	timer := time.NewTimer(2 * time.Second)
	defer timer.Stop()
	for recorder.SendCallCount() < want {
		select {
		case <-recorder.sentSignal:
		case <-timer.C:
			t.Fatalf("provider sends = %d, want %d", recorder.SendCallCount(), want)
		}
	}
	if got := recorder.SendCallCount(); got != want {
		t.Fatalf("provider sends = %d, want exactly %d", got, want)
	}
}

func tc395APNSCollapseID(message *messaging.Message) (string, bool) {
	if message == nil || message.APNS == nil || message.APNS.Headers == nil {
		return "", false
	}
	value, ok := message.APNS.Headers["apns-collapse-id"]
	return value, ok
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

func TestGroupInviteAndroidNotificationTagKnownVector(t *testing.T) {
	const want = "mknoon_group_invite_ed9a409a17e30f392210675cde7ed859"
	if got := groupInviteAndroidNotificationTag(" group-1 ", " invite-1 "); got != want {
		t.Fatalf("group-invite Android tag = %q, want %q", got, want)
	}
}

func TestGroupInviteAndroidNotificationTagSeparatesInvites(t *testing.T) {
	first := groupInviteAndroidNotificationTag("group-1", "invite-1")
	second := groupInviteAndroidNotificationTag("group-1", "invite-2")
	if first == "" || second == "" {
		t.Fatalf("group-invite Android tags must be non-empty: %q / %q", first, second)
	}
	if first == second {
		t.Fatalf("distinct invite IDs collapsed to one Android tag: %q", first)
	}
}

func TestGroupInviteAndroidNotificationTagProjectionPreservesPlatforms(t *testing.T) {
	envelope := `{"type":"group_invite","version":"2","id":"invite-1","senderPeerId":"peer-from","senderUsername":"Alice","groupId":"group-1","groupName":"Book Club","encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}}`
	unprojected := buildPushMessage("recipient-token", "peer-from", envelope)
	wantTag := groupInviteAndroidNotificationTag("group-1", "invite-1")
	if unprojected.Android == nil || unprojected.Android.Notification == nil ||
		unprojected.Android.Notification.Tag != wantTag {
		t.Fatalf("unprojected Android tag = %#v, want %q", unprojected.Android, wantTag)
	}

	android := projectPushMessageForPlatform(unprojected, "android")
	if android.APNS != nil {
		t.Fatalf("Android projection retained APNS: %#v", android.APNS)
	}
	if android.Android == nil || android.Android.Notification == nil ||
		android.Android.Notification.Tag != wantTag {
		t.Fatalf("Android projection lost group-invite tag: %#v", android.Android)
	}
	androidData, _ := json.Marshal(android.Data)
	wantData, _ := json.Marshal(unprojected.Data)
	if string(androidData) != string(wantData) {
		t.Fatalf("Android projection changed group-invite Data")
	}

	ios := projectPushMessageForPlatform(unprojected, "ios")
	if ios.Android != nil {
		t.Fatalf("iOS projection retained Android config: %#v", ios.Android)
	}
	iosData, _ := json.Marshal(ios.Data)
	if string(iosData) != string(wantData) {
		t.Fatalf("iOS projection changed group-invite Data")
	}
	iosAPNS, _ := json.Marshal(ios.APNS)
	wantAPNS, _ := json.Marshal(unprojected.APNS)
	if string(iosAPNS) != string(wantAPNS) {
		t.Fatalf("iOS projection changed group-invite APNS")
	}

	contact := buildPushMessage(
		"recipient-token",
		"peer-from",
		`{"type":"contact_request","id":"contact-1","senderUsername":"Alice"}`,
	)
	if contact.Android == nil || contact.Android.Notification == nil {
		t.Fatalf("contact fixture missing Android notification: %#v", contact.Android)
	}
	if contact.Android.Notification.Tag != "" {
		t.Fatalf("non-group-invite Android tag = %q, want empty", contact.Android.Notification.Tag)
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

// TC-395-01 — only a stored rich iOS group invite carries the relay custody
// row ID as its bounded APNs collapse identity. Provider retries reuse that ID;
// ACK followed by a new custody for the same invite produces a new identity.
func TestRelayNotificationClosure_GroupInviteCustodyRetryCollapse(t *testing.T) {
	const (
		recipient = "tc395-recipient"
		sender    = "tc395-sender"
	)
	invite := tc395GroupInviteEnvelope("tc395-invite")

	t.Run("normal stored rich retries reuse custody and a new row differs", func(t *testing.T) {
		tokens := newMemoryPushTokenStore()
		if err := tokens.RegisterToken(recipient, "tc395-ios-token", "ios"); err != nil {
			t.Fatalf("register iOS route: %v", err)
		}
		push := NewPushServiceWithBackend(tokens)
		push.retryDelays = []time.Duration{0}
		recorder := newRecordingPushSender()
		recorder.onSend = func(context.Context, *messaging.Message) (string, error) {
			if recorder.SendCallCount() == 1 {
				return "", fmt.Errorf("temporary provider outage")
			}
			return "tc395-provider-id", nil
		}
		push.sender = recorder.Send
		inbox := NewInboxStore(push)

		stored, err := inbox.Store(recipient, inboxMessage{
			From:      sender,
			Message:   invite,
			Timestamp: time.Now().UnixMilli(),
		})
		if err != nil || stored != InboxStoreResultStored {
			t.Fatalf("store custody A: result=%q err=%v", stored, err)
		}
		pending, _ := inbox.RetrievePendingWithMeta(recipient, 10)
		if len(pending) != 1 || strings.TrimSpace(pending[0].ID) == "" {
			t.Fatalf("pending custody A = %#v, want one generated ID", pending)
		}
		custodyA := pending[0].ID
		tc395WaitForProviderCalls(t, recorder, 2)
		for index, sent := range recorder.Messages()[:2] {
			if got, ok := tc395APNSCollapseID(sent); !ok || got != custodyA {
				t.Fatalf("custody A attempt %d collapse ID = %q present=%v, want %q", index+1, got, ok, custodyA)
			}
		}

		removed, err := inbox.Ack(recipient, []string{custodyA})
		if err != nil || removed != 1 {
			t.Fatalf("ACK custody A: removed=%d err=%v", removed, err)
		}
		stored, err = inbox.Store(recipient, inboxMessage{
			From:      sender,
			Message:   invite,
			Timestamp: time.Now().Add(time.Millisecond).UnixMilli(),
		})
		if err != nil || stored != InboxStoreResultStored {
			t.Fatalf("store custody B: result=%q err=%v", stored, err)
		}
		pending, _ = inbox.RetrievePendingWithMeta(recipient, 10)
		if len(pending) != 1 || strings.TrimSpace(pending[0].ID) == "" {
			t.Fatalf("pending custody B = %#v, want one generated ID", pending)
		}
		custodyB := pending[0].ID
		if custodyB == custodyA {
			t.Fatalf("new custody reused ID %q", custodyA)
		}
		tc395WaitForProviderCalls(t, recorder, 3)
		if got, ok := tc395APNSCollapseID(recorder.Messages()[2]); !ok || got != custodyB {
			t.Fatalf("custody B collapse ID = %q present=%v, want %q", got, ok, custodyB)
		}
	})

	t.Run("preflight-selected stored rich path keeps generated custody", func(t *testing.T) {
		tokens := newMemoryPushTokenStore()
		if err := tokens.RegisterToken(recipient, "tc395-preflight-token", "ios"); err != nil {
			t.Fatalf("register preflight route: %v", err)
		}
		push := NewPushServiceWithBackend(tokens)
		recorder := newRecordingPushSender()
		push.sender = recorder.Send
		backend := &tc395PreflightCapableInboxBackend{InboxBackend: newMemoryInboxBackend()}
		inbox := NewInboxStoreWithBackend(backend, push)
		inbox.SetWakeOutcomeAdmissionEnabled(true)

		stored, err := inbox.Store(recipient, inboxMessage{
			From:      sender,
			Message:   invite,
			Timestamp: time.Now().UnixMilli(),
		})
		if err != nil || stored != InboxStoreResultStored {
			t.Fatalf("preflight-selected store: result=%q err=%v", stored, err)
		}
		pending, _ := inbox.RetrievePendingWithMeta(recipient, 10)
		if len(pending) != 1 || strings.TrimSpace(pending[0].ID) == "" {
			t.Fatalf("preflight pending = %#v, want one generated custody", pending)
		}
		tc395WaitForProviderCalls(t, recorder, 1)
		if got, ok := tc395APNSCollapseID(recorder.Messages()[0]); !ok || got != pending[0].ID {
			t.Fatalf("preflight collapse ID = %q present=%v, want %q", got, ok, pending[0].ID)
		}
	})

	t.Run("custody header is bounded and exact-iOS only", func(t *testing.T) {
		cases := []struct {
			name       string
			platform   string
			custodyID  string
			wantAPNS   bool
			wantHeader bool
		}{
			{name: "trimmed empty iOS custody", platform: "ios", custodyID: "   ", wantAPNS: true},
			{name: "over-64-byte iOS custody", platform: "ios", custodyID: strings.Repeat("é", 33), wantAPNS: true},
			{name: "android", platform: "android", custodyID: "tc395-android-custody"},
			{name: "unknown platform", platform: "web", custodyID: "tc395-unknown-custody", wantAPNS: true},
		}
		for _, tc := range cases {
			t.Run(tc.name, func(t *testing.T) {
				tokens := newMemoryPushTokenStore()
				if err := tokens.RegisterToken(recipient, "tc395-bounds-token", tc.platform); err != nil {
					t.Fatalf("register %q route: %v", tc.platform, err)
				}
				push := NewPushServiceWithBackend(tokens)
				recorder := newRecordingPushSender()
				push.sender = recorder.Send
				inbox := NewInboxStore(push)
				inbox.launchStoredDirectPush(recipient, inboxMessage{
					ID:        tc.custodyID,
					From:      sender,
					Message:   invite,
					Timestamp: time.Now().UnixMilli(),
				})
				tc395WaitForProviderCalls(t, recorder, 1)
				sent := recorder.Messages()[0]
				if (sent.APNS != nil) != tc.wantAPNS {
					t.Fatalf("APNS present = %v, want %v", sent.APNS != nil, tc.wantAPNS)
				}
				if got, ok := tc395APNSCollapseID(sent); ok != tc.wantHeader {
					t.Fatalf("collapse ID = %q present=%v, want present=%v", got, ok, tc.wantHeader)
				}
			})
		}
	})

	t.Run("public non-invite and opaque paths stay unchanged", func(t *testing.T) {
		t.Run("public group invite has no custody header", func(t *testing.T) {
			push, recorder := ordinaryPushService("ios")
			push.SendNotification(context.Background(), "recipient", sender, invite)
			if got, ok := tc395APNSCollapseID(recorder.Messages()[0]); ok {
				t.Fatalf("public group invite collapse ID = %q, want absent", got)
			}
		})

		t.Run("stored contact request has no custody header", func(t *testing.T) {
			tokens := newMemoryPushTokenStore()
			if err := tokens.RegisterToken(recipient, "tc395-chat-token", "ios"); err != nil {
				t.Fatalf("register chat route: %v", err)
			}
			push := NewPushServiceWithBackend(tokens)
			recorder := newRecordingPushSender()
			push.sender = recorder.Send
			inbox := NewInboxStore(push)
			inbox.launchStoredDirectPush(recipient, inboxMessage{
				ID:        "tc395-contact-custody",
				From:      sender,
				Message:   `{"type":"contact_request","id":"tc395-contact","senderUsername":"Alice"}`,
				Timestamp: time.Now().UnixMilli(),
			})
			tc395WaitForProviderCalls(t, recorder, 1)
			if got, ok := tc395APNSCollapseID(recorder.Messages()[0]); ok {
				t.Fatalf("stored contact collapse ID = %q, want absent", got)
			}
		})

		t.Run("opaque wake retains mailbox collapse identity", func(t *testing.T) {
			tokens := newMemoryPushTokenStore()
			if err := tokens.RegisterToken(
				recipient,
				"tc395-opaque-token",
				"ios",
				opaqueWakeCapability,
			); err != nil {
				t.Fatalf("register opaque route: %v", err)
			}
			push := NewPushServiceWithBackend(tokens)
			recorder := newRecordingPushSender()
			push.sender = recorder.Send
			inbox := NewInboxStore(push)
			stored, err := inbox.Store(recipient, inboxMessage{
				ID:        "tc395-opaque-custody",
				From:      sender,
				Message:   invite,
				Timestamp: time.Now().UnixMilli(),
			})
			if err != nil || stored != InboxStoreResultStored {
				t.Fatalf("opaque store: result=%q err=%v", stored, err)
			}
			tc395WaitForProviderCalls(t, recorder, 1)
			if got, ok := tc395APNSCollapseID(recorder.Messages()[0]); !ok || got != "mailbox" {
				t.Fatalf("opaque collapse ID = %q present=%v, want mailbox", got, ok)
			}
		})
	})
}

// TC-396-04 — stored rich iOS direct messages share their durable inbox-row
// identity with APNs collapse. A provider retry of one row is stable, while a
// new row remains independently deliverable. Other route/platform owners keep
// their incumbent projection and all header mutation remains clone-on-write.
func TestRelayNotificationClosure_DirectMessageCustodyRetryCollapse(t *testing.T) {
	const (
		recipient = "tc396-recipient"
		sender    = "tc396-sender"
	)

	t.Run("normal stored rich retries reuse custody and a new row differs", func(t *testing.T) {
		tokens := newMemoryPushTokenStore()
		if err := tokens.RegisterToken(recipient, "tc396-ios-token", "ios"); err != nil {
			t.Fatalf("register iOS route: %v", err)
		}
		push := NewPushServiceWithBackend(tokens)
		push.retryDelays = []time.Duration{0}
		recorder := newRecordingPushSender()
		recorder.onSend = func(context.Context, *messaging.Message) (string, error) {
			if recorder.SendCallCount() == 1 {
				return "", fmt.Errorf("temporary provider outage")
			}
			return "tc396-provider-id", nil
		}
		push.sender = recorder.Send
		inbox := NewInboxStore(push)

		stored, err := inbox.Store(recipient, inboxMessage{
			From:      sender,
			Message:   tc396DirectMessageEnvelope("tc396-message-a"),
			Timestamp: time.Now().UnixMilli(),
		})
		if err != nil || stored != InboxStoreResultStored {
			t.Fatalf("store custody A: result=%q err=%v", stored, err)
		}
		pending, _ := inbox.RetrievePendingWithMeta(recipient, 10)
		if len(pending) != 1 || strings.TrimSpace(pending[0].ID) != pending[0].ID ||
			len([]byte(pending[0].ID)) == 0 || len([]byte(pending[0].ID)) > 64 {
			t.Fatalf("pending custody A = %#v, want one trimmed nonempty <=64-byte ID", pending)
		}
		custodyA := pending[0].ID
		tc395WaitForProviderCalls(t, recorder, 2)
		for index, sent := range recorder.Messages()[:2] {
			if got, ok := tc395APNSCollapseID(sent); !ok || got != custodyA {
				t.Fatalf("custody A attempt %d collapse ID = %q present=%v, want %q", index+1, got, ok, custodyA)
			}
			if sentRoutingString(sent, "type") != "new_message" ||
				!sentRoutingHas(sent, "kem") || !sentRoutingHas(sent, "ciphertext") ||
				!sentRoutingHas(sent, "nonce") {
				t.Fatalf("custody A attempt %d lost encrypted rich route: %#v", index+1, sent)
			}
		}

		removed, err := inbox.Ack(recipient, []string{custodyA})
		if err != nil || removed != 1 {
			t.Fatalf("ACK custody A: removed=%d err=%v", removed, err)
		}
		stored, err = inbox.Store(recipient, inboxMessage{
			From:      sender,
			Message:   tc396DirectMessageEnvelope("tc396-message-b"),
			Timestamp: time.Now().Add(time.Millisecond).UnixMilli(),
		})
		if err != nil || stored != InboxStoreResultStored {
			t.Fatalf("store custody B: result=%q err=%v", stored, err)
		}
		pending, _ = inbox.RetrievePendingWithMeta(recipient, 10)
		if len(pending) != 1 || strings.TrimSpace(pending[0].ID) == "" {
			t.Fatalf("pending custody B = %#v, want one generated ID", pending)
		}
		custodyB := pending[0].ID
		if custodyB == custodyA {
			t.Fatalf("new custody reused ID %q", custodyA)
		}
		tc395WaitForProviderCalls(t, recorder, 3)
		if got, ok := tc395APNSCollapseID(recorder.Messages()[2]); !ok || got != custodyB {
			t.Fatalf("custody B collapse ID = %q present=%v, want %q", got, ok, custodyB)
		}
	})

	t.Run("collapse bounds are byte-exact and header mutation is clone-on-write", func(t *testing.T) {
		original := buildPushMessage(
			"tc396-token",
			sender,
			tc396DirectMessageEnvelope("tc396-clone-message"),
		)
		projected := projectStoredDirectPushMessageForPlatform(
			original,
			" iOS ",
			"  tc396-trimmed-custody  ",
		)
		if got, ok := tc395APNSCollapseID(projected); !ok || got != "tc396-trimmed-custody" {
			t.Fatalf("trimmed collapse ID = %q present=%v", got, ok)
		}
		if got, ok := tc395APNSCollapseID(original); ok {
			t.Fatalf("original inherited collapse ID %q", got)
		}
		if projected == original || projected.APNS == original.APNS {
			t.Fatal("stored projection reused mutable message/APNS owner")
		}
		projected.APNS.Headers["apns-priority"] = "5"
		if got := original.APNS.Headers["apns-priority"]; got != "10" {
			t.Fatalf("projected header mutation changed original priority to %q", got)
		}
		if original.Android == nil || original.Data == nil || projected.Android != nil || projected.Data != nil {
			t.Fatalf("clone projection changed platform ownership: original=%#v projected=%#v", original, projected)
		}

		for _, tc := range []struct {
			name       string
			custodyID  string
			wantHeader bool
		}{
			{name: "exactly 64 ASCII bytes", custodyID: strings.Repeat("a", 64), wantHeader: true},
			{name: "trimmed empty", custodyID: "   "},
			{name: "65 ASCII bytes", custodyID: strings.Repeat("b", 65)},
			{name: "66 UTF-8 bytes", custodyID: strings.Repeat("é", 33)},
		} {
			t.Run(tc.name, func(t *testing.T) {
				candidate := projectStoredDirectPushMessageForPlatform(original, "ios", tc.custodyID)
				if got, ok := tc395APNSCollapseID(candidate); ok != tc.wantHeader {
					t.Fatalf("collapse ID = %q present=%v, want present=%v", got, ok, tc.wantHeader)
				}
			})
		}
	})

	t.Run("group invite behavior is preserved", func(t *testing.T) {
		invite := buildPushMessage(
			"tc396-invite-token",
			sender,
			tc395GroupInviteEnvelope("tc396-invite"),
		)
		projected := projectStoredDirectPushMessageForPlatform(
			invite,
			"ios",
			" tc396-invite-custody ",
		)
		if got, ok := tc395APNSCollapseID(projected); !ok || got != "tc396-invite-custody" {
			t.Fatalf("group-invite collapse ID = %q present=%v", got, ok)
		}
	})

	t.Run("Android unknown public contact reaction group and opaque paths stay unchanged", func(t *testing.T) {
		direct := buildPushMessage(
			"tc396-route-token",
			sender,
			tc396DirectMessageEnvelope("tc396-route-message"),
		)

		android := projectStoredDirectPushMessageForPlatform(direct, "android", "tc396-android-custody")
		if android.APNS != nil || android.Android == nil || android.Data["type"] != "new_message" {
			t.Fatalf("Android direct projection changed: %#v", android)
		}
		if got, ok := tc395APNSCollapseID(android); ok {
			t.Fatalf("Android projection gained collapse ID %q", got)
		}

		unknown := projectStoredDirectPushMessageForPlatform(direct, "web", "tc396-web-custody")
		if unknown.APNS == nil || unknown.Android == nil || unknown.Data["type"] != "new_message" {
			t.Fatalf("unknown platform stopped failing open: %#v", unknown)
		}
		if got, ok := tc395APNSCollapseID(unknown); ok {
			t.Fatalf("unknown projection gained collapse ID %q", got)
		}

		publicPush, publicRecorder := ordinaryPushService("ios")
		publicPush.SendNotification(
			context.Background(),
			"recipient",
			sender,
			tc396DirectMessageEnvelope("tc396-public-message"),
		)
		if got, ok := tc395APNSCollapseID(publicRecorder.Messages()[0]); ok {
			t.Fatalf("public direct send gained collapse ID %q", got)
		}

		contact := projectStoredDirectPushMessageForPlatform(
			buildPushMessage(
				"tc396-contact-token",
				sender,
				`{"type":"contact_request","id":"tc396-contact","senderUsername":"Alice"}`,
			),
			"ios",
			"tc396-contact-custody",
		)
		if sentRoutingString(contact, "type") != "contact_request" {
			t.Fatalf("contact route changed: %#v", contact)
		}
		if got, ok := tc395APNSCollapseID(contact); ok {
			t.Fatalf("contact request gained collapse ID %q", got)
		}

		reactionBase := buildReactionPushMessage(
			"tc396-reaction-token",
			"reactor-peer",
			ordinaryDirectReactionEnvelope(8, 16),
		)
		wantReactionCollapse, ok := tc395APNSCollapseID(reactionBase)
		if !ok || !strings.HasPrefix(wantReactionCollapse, "reaction:") {
			t.Fatalf("reaction fixture collapse ID = %q present=%v", wantReactionCollapse, ok)
		}
		reaction := projectStoredDirectPushMessageForPlatform(
			reactionBase,
			"ios",
			"tc396-reaction-custody",
		)
		if reaction == nil || sentRoutingString(reaction, "type") != "message_reaction" {
			t.Fatalf("reaction route changed: %#v", reaction)
		}
		if got, ok := tc395APNSCollapseID(reaction); !ok || got != wantReactionCollapse {
			t.Fatalf("reaction collapse ID = %q present=%v, want %q", got, ok, wantReactionCollapse)
		}

		groupPush, groupRecorder := ordinaryPushService("ios")
		groupPush.SendGroupNotification(
			context.Background(),
			"recipient",
			"88888888-8888-4888-8888-888888888888",
			sender,
			"tc396-group-message",
			ordinaryGroupCiphertextEnvelope(16),
		)
		if got, ok := tc395APNSCollapseID(groupRecorder.Messages()[0]); !ok || got != boundedGroupMessageIdentity("tc396-group-message") {
			t.Fatalf("group push collapse ID = %q present=%v, want per-message identity", got, ok)
		}

		tokens := newMemoryPushTokenStore()
		if err := tokens.RegisterToken(
			recipient,
			"tc396-opaque-token",
			"ios",
			opaqueWakeCapability,
		); err != nil {
			t.Fatalf("register opaque route: %v", err)
		}
		opaquePush := NewPushServiceWithBackend(tokens)
		opaqueRecorder := newRecordingPushSender()
		opaquePush.sender = opaqueRecorder.Send
		opaqueInbox := NewInboxStore(opaquePush)
		stored, err := opaqueInbox.Store(recipient, inboxMessage{
			ID:        "tc396-opaque-custody",
			From:      sender,
			Message:   tc396DirectMessageEnvelope("tc396-opaque-message"),
			Timestamp: time.Now().UnixMilli(),
		})
		if err != nil || stored != InboxStoreResultStored {
			t.Fatalf("opaque store: result=%q err=%v", stored, err)
		}
		tc395WaitForProviderCalls(t, opaqueRecorder, 1)
		if got, ok := tc395APNSCollapseID(opaqueRecorder.Messages()[0]); !ok || got != "mailbox" {
			t.Fatalf("opaque collapse ID = %q present=%v, want mailbox", got, ok)
		}
	})
}

// TC-397-01 — every rich iOS group-message send derives one bounded collapse
// identity from the canonical message ID. Provider retries reuse it, distinct
// messages remain independent, and routing-only fallbacks use the same seam.
// Android and unknown routes deliberately remain non-collapsible.
func TestRelayNotificationClosure_GroupMessageRetryCollapse(t *testing.T) {
	const (
		groupID = "39739739-7397-4397-8397-397397397397"
		sender  = "tc397-sender-transport"
	)
	envelope := ordinaryGroupCiphertextEnvelope(16)

	t.Run("ordinary iOS retry is stable and distinct messages differ", func(t *testing.T) {
		tokens := newMemoryPushTokenStore()
		if err := tokens.RegisterToken("recipient", "tc397-ios-token", "ios"); err != nil {
			t.Fatalf("register iOS route: %v", err)
		}
		push := NewPushServiceWithBackend(tokens)
		push.retryDelays = []time.Duration{0}
		recorder := newRecordingPushSender()
		recorder.onSend = func(context.Context, *messaging.Message) (string, error) {
			if recorder.SendCallCount() == 1 {
				return "", fmt.Errorf("temporary provider outage")
			}
			return "tc397-provider-id", nil
		}
		push.sender = recorder.Send

		push.SendGroupNotification(
			context.Background(),
			"recipient",
			groupID,
			sender,
			"tc397-message-a",
			envelope,
		)
		if got := recorder.SendCallCount(); got != 2 {
			t.Fatalf("message A sends = %d, want retry pair", got)
		}
		attempts := recorder.Messages()
		identityA, ok := tc395APNSCollapseID(attempts[0])
		if !ok || identityA == "" || len([]byte(identityA)) > 64 {
			t.Fatalf("message A collapse ID = %q present=%v, want bounded identity", identityA, ok)
		}
		if retryIdentity, retryOK := tc395APNSCollapseID(attempts[1]); !retryOK || retryIdentity != identityA {
			t.Fatalf("retry collapse ID = %q present=%v, want %q", retryIdentity, retryOK, identityA)
		}

		push.SendGroupNotification(
			context.Background(),
			"recipient",
			groupID,
			sender,
			"tc397-message-b",
			envelope,
		)
		identityB, ok := tc395APNSCollapseID(recorder.Messages()[2])
		if !ok || identityB == "" || identityB == identityA {
			t.Fatalf("message B collapse ID = %q present=%v, want distinct from %q", identityB, ok, identityA)
		}
	})

	t.Run("strict and routing-only iOS call sites share the identity seam", func(t *testing.T) {
		tokens := newMemoryPushTokenStore()
		if err := tokens.RegisterToken("recipient", "tc397-ios-token", "ios"); err != nil {
			t.Fatalf("register iOS route: %v", err)
		}
		push := NewPushServiceWithBackend(tokens)
		recorder := newRecordingPushSender()
		push.sender = recorder.Send
		route, err := push.selectPushRoute("recipient", "")
		if err != nil || route == nil {
			t.Fatalf("select strict route: route=%#v err=%v", route, err)
		}

		push.sendGroupContentNotificationForRoute(
			context.Background(),
			"recipient",
			*route,
			groupContentPushMetadata{
				GroupID:               groupID,
				SenderTransportPeerID: sender,
				MessageID:             "tc397-strict-message",
				PayloadType:           groupContentPayloadTypeMessage,
			},
			`{"kind":"group_offline_replay","version":1,"payloadType":"group_message","groupId":"39739739-7397-4397-8397-397397397397","messageId":"tc397-strict-message","senderTransportPeerId":"tc397-sender-transport","keyEpoch":7,"ciphertext":"gc","nonce":"gn"}`,
		)
		strict := recorder.Messages()[0]
		strictIdentity, ok := tc395APNSCollapseID(strict)
		if !ok || strictIdentity == "" || len([]byte(strictIdentity)) > 64 {
			t.Fatalf("strict collapse ID = %q present=%v, want bounded identity", strictIdentity, ok)
		}

		push.SendGroupNotification(
			context.Background(),
			"recipient",
			groupID,
			sender,
			"tc397-routing-only-message",
			"not-json",
		)
		routingOnly := recorder.Messages()[1]
		if !sentRoutingHas(routingOnly, "preview_unavailable") {
			t.Fatalf("routing-only fixture did not preserve preview_unavailable: %#v", routingOnly)
		}
		routingIdentity, ok := tc395APNSCollapseID(routingOnly)
		if !ok || routingIdentity == "" || routingIdentity == strictIdentity {
			t.Fatalf("routing-only collapse ID = %q present=%v, want distinct identity", routingIdentity, ok)
		}
	})

	t.Run("blank iOS Android and unknown routes remain headerless", func(t *testing.T) {
		cases := []struct {
			name      string
			platform  string
			messageID string
		}{
			{name: "blank iOS identity", platform: "ios", messageID: "  "},
			{name: "Android", platform: "android", messageID: "tc397-android-message"},
			{name: "unknown", platform: "web", messageID: "tc397-unknown-message"},
		}
		for _, tc := range cases {
			t.Run(tc.name, func(t *testing.T) {
				push, recorder := ordinaryPushService(tc.platform)
				push.SendGroupNotification(
					context.Background(),
					"recipient",
					groupID,
					sender,
					tc.messageID,
					envelope,
				)
				if got, ok := tc395APNSCollapseID(recorder.Messages()[0]); ok {
					t.Fatalf("%s route gained collapse ID %q", tc.platform, got)
				}
			})
		}
	})
}

func TestRelayNotificationClosure_GroupMessageDispatchAttribution(t *testing.T) {
	type metricKey struct{ source, result string }
	metricKeys := []metricKey{
		{"group_inbox", "accepted"},
		{"group_inbox", "failed"},
		{"group_content", "accepted"},
		{"group_content", "failed"},
	}
	snapshot := func() map[metricKey]float64 {
		values := make(map[metricKey]float64, len(metricKeys))
		for _, key := range metricKeys {
			values[key] = testutil.ToFloat64(
				groupMessageDispatchCounter.WithLabelValues(key.source, key.result),
			)
		}
		return values
	}
	assertDeltas := func(t *testing.T, before map[metricKey]float64, want metricKey) {
		t.Helper()
		for _, key := range metricKeys {
			wantDelta := float64(0)
			if key == want {
				wantDelta = 1
			}
			got := testutil.ToFloat64(
				groupMessageDispatchCounter.WithLabelValues(key.source, key.result),
			) - before[key]
			if got != wantDelta {
				t.Fatalf("TC-398-05 dispatch attribution metric %v delta = %v, want %v", key, got, wantDelta)
			}
		}
	}

	t.Run("ordinary iOS accepted carries only the inbox claim", func(t *testing.T) {
		before := snapshot()
		push, recorder := ordinaryPushService("ios")
		push.SendGroupNotification(
			context.Background(), "recipient",
			"88888888-8888-4888-8888-888888888888",
			"tc398-sender-transport", "tc398-message",
			ordinaryGroupCiphertextEnvelope(16),
		)
		if got := recorder.SendCallCount(); got != 1 {
			t.Fatalf("provider calls = %d, want 1", got)
		}
		message := recorder.Messages()[0]
		assertAPNSCustomString(t, message, groupMessageDispatchClaimKey, groupMessageDispatchClaimInbox)
		if message.Data != nil {
			t.Fatalf("iOS group projection retained top-level data: %#v", message.Data)
		}
		assertDeltas(t, before, metricKey{"group_inbox", "accepted"})
	})

	t.Run("strict iOS accepted carries only the content claim", func(t *testing.T) {
		before := snapshot()
		tokens := newMemoryPushTokenStore()
		if err := tokens.RegisterToken("recipient", "tc398-ios-token", "ios"); err != nil {
			t.Fatalf("register token: %v", err)
		}
		push := NewPushServiceWithBackend(tokens)
		recorder := newRecordingPushSender()
		push.sender = recorder.Send
		route, err := push.selectPushRoute("recipient", "")
		if err != nil || route == nil {
			t.Fatalf("select route = %#v, %v", route, err)
		}
		push.sendGroupContentNotificationForRoute(
			context.Background(), "recipient", *route,
			groupContentPushMetadata{
				GroupID:               "88888888-8888-4888-8888-888888888888",
				SenderTransportPeerID: "tc398-sender-transport",
				MessageID:             "tc398-strict-message",
				PayloadType:           groupContentPayloadTypeMessage,
			},
			ordinaryGroupCiphertextEnvelope(16),
		)
		message := recorder.Messages()[0]
		assertAPNSCustomString(t, message, groupMessageDispatchClaimKey, groupMessageDispatchClaimContent)
		if message.Data != nil {
			t.Fatalf("strict iOS group projection retained top-level data: %#v", message.Data)
		}
		assertDeltas(t, before, metricKey{"group_content", "accepted"})
	})

	t.Run("provider retry remains one accepted logical dispatch", func(t *testing.T) {
		before := snapshot()
		push, recorder := ordinaryPushService("ios")
		push.retryDelays = []time.Duration{0}
		recorder.onSend = func(context.Context, *messaging.Message) (string, error) {
			if recorder.SendCallCount() == 1 {
				return "", fmt.Errorf("temporary provider outage")
			}
			return "tc398-provider-id", nil
		}
		push.SendGroupNotification(
			context.Background(), "recipient",
			"88888888-8888-4888-8888-888888888888",
			"tc398-sender-transport", "tc398-retry-message",
			ordinaryGroupCiphertextEnvelope(16),
		)
		if got := recorder.SendCallCount(); got != 2 {
			t.Fatalf("provider retry calls = %d, want 2", got)
		}
		assertDeltas(t, before, metricKey{"group_inbox", "accepted"})
	})

	t.Run("terminal provider failure is one failed logical dispatch", func(t *testing.T) {
		before := snapshot()
		push, recorder := ordinaryPushService("ios")
		push.retryDelays = nil
		recorder.onSend = func(context.Context, *messaging.Message) (string, error) {
			return "", fmt.Errorf("terminal provider outage")
		}
		push.SendGroupNotification(
			context.Background(), "recipient",
			"88888888-8888-4888-8888-888888888888",
			"tc398-sender-transport", "tc398-failed-message",
			ordinaryGroupCiphertextEnvelope(16),
		)
		if got := recorder.SendCallCount(); got != 1 {
			t.Fatalf("terminal provider calls = %d, want 1", got)
		}
		assertDeltas(t, before, metricKey{"group_inbox", "failed"})
	})

	t.Run("pre-gateway route lookup failure emits no terminal result", func(t *testing.T) {
		before := snapshot()
		backend := &plan368BackendProbe{delegate: newMemoryPushTokenStore()}
		backend.lookup = func(int, string) (*pushRouteLease, error) {
			return nil, fmt.Errorf("route lookup unavailable")
		}
		push := NewPushServiceWithBackend(backend)
		recorder := newRecordingPushSender()
		push.sender = recorder.Send
		push.SendGroupNotification(
			context.Background(), "recipient",
			"88888888-8888-4888-8888-888888888888",
			"tc398-sender-transport", "tc398-route-failure",
			ordinaryGroupCiphertextEnvelope(16),
		)
		if got := recorder.SendCallCount(); got != 0 {
			t.Fatalf("route failure provider calls = %d, want 0", got)
		}
		for _, key := range metricKeys {
			got := testutil.ToFloat64(
				groupMessageDispatchCounter.WithLabelValues(key.source, key.result),
			) - before[key]
			if got != 0 {
				t.Fatalf("pre-gateway metric %v delta = %v, want 0", key, got)
			}
		}
	})

	t.Run("Android projection has no Plan 398 claim", func(t *testing.T) {
		before := snapshot()
		push, recorder := ordinaryPushService("android")
		push.SendGroupNotification(
			context.Background(), "recipient",
			"88888888-8888-4888-8888-888888888888",
			"tc398-sender-transport", "tc398-android-message",
			ordinaryGroupCiphertextEnvelope(16),
		)
		message := recorder.Messages()[0]
		if message.APNS != nil || sentRoutingHas(message, groupMessageDispatchClaimKey) {
			t.Fatalf("Android projection leaked Plan 398 claim: %#v", message)
		}
		assertDeltas(t, before, metricKey{"group_inbox", "accepted"})
	})
}

func TestRelayNotificationClosure_GroupMessageProviderDispatchAdmission(t *testing.T) {
	const (
		recipient = "tc398-admission-recipient"
		groupID   = "39810000-0000-4000-8000-000000000001"
		messageID = "tc398-admission-message"
		sender    = "tc398-admission-sender"
	)
	envelope := ordinaryGroupCiphertextEnvelope(16)

	t.Run("rich iOS exact cross-adapter duplicate reaches the provider once", func(t *testing.T) {
		tokens := newMemoryPushTokenStore()
		if err := tokens.RegisterToken(recipient, "tc398-admission-ios-token", "ios"); err != nil {
			t.Fatalf("register iOS route: %v", err)
		}
		push := NewPushServiceWithBackend(tokens)
		push.retryDelays = nil
		recorder := newRecordingPushSender()
		push.sender = recorder.Send
		var journal []groupMessageProviderAttemptJournalRecord
		push.journalGroupMessageProviderAttempt = func(record groupMessageProviderAttemptJournalRecord) {
			journal = append(journal, record)
		}
		inboxAcceptedBefore := testutil.ToFloat64(
			groupMessageDispatchCounter.WithLabelValues("group_inbox", "accepted"),
		)
		contentAcceptedBefore := testutil.ToFloat64(
			groupMessageDispatchCounter.WithLabelValues("group_content", "accepted"),
		)
		contentSuppressedBefore := testutil.ToFloat64(
			groupMessageDispatchCounter.WithLabelValues("group_content", "suppressed"),
		)

		push.SendGroupNotification(
			context.Background(), recipient, groupID, sender, messageID, envelope,
		)
		route, err := push.selectPushRoute(recipient, "")
		if err != nil || route == nil {
			t.Fatalf("select content route: route=%#v err=%v", route, err)
		}
		push.sendGroupContentNotificationForRoute(
			context.Background(), recipient, *route,
			groupContentPushMetadata{
				GroupID:               groupID,
				SenderTransportPeerID: sender,
				MessageID:             messageID,
				PayloadType:           groupContentPayloadTypeMessage,
			},
			envelope,
		)

		if got := recorder.SendCallCount(); got != 1 {
			t.Fatalf("exact cross-adapter provider sends = %d, want 1", got)
		}
		if got := len(journal); got != 1 {
			t.Fatalf("exact cross-adapter provider journal rows = %d, want 1", got)
		}
		if delta := testutil.ToFloat64(
			groupMessageDispatchCounter.WithLabelValues("group_inbox", "accepted"),
		) - inboxAcceptedBefore; delta != 1 {
			t.Fatalf("inbox accepted delta = %v, want 1", delta)
		}
		if delta := testutil.ToFloat64(
			groupMessageDispatchCounter.WithLabelValues("group_content", "accepted"),
		) - contentAcceptedBefore; delta != 0 {
			t.Fatalf("duplicate content accepted delta = %v, want 0", delta)
		}
		if delta := testutil.ToFloat64(
			groupMessageDispatchCounter.WithLabelValues("group_content", "suppressed"),
		) - contentSuppressedBefore; delta != 1 {
			t.Fatalf("duplicate content suppressed delta = %v, want 1", delta)
		}
	})

	t.Run("opaque-capability iOS exact cross-adapter duplicate reaches the provider once", func(t *testing.T) {
		tokens := newMemoryPushTokenStore()
		if err := tokens.RegisterToken(
			recipient,
			"tc398-admission-opaque-handle",
			"ios",
			opaqueWakeCapability,
		); err != nil {
			t.Fatalf("register opaque iOS route: %v", err)
		}
		push := NewPushServiceWithBackend(tokens)
		push.retryDelays = nil
		recorder := newRecordingPushSender()
		push.sender = recorder.Send
		inboxAcceptedBefore := testutil.ToFloat64(
			groupMessageDispatchCounter.WithLabelValues("group_inbox", "accepted"),
		)
		contentAcceptedBefore := testutil.ToFloat64(
			groupMessageDispatchCounter.WithLabelValues("group_content", "accepted"),
		)
		contentSuppressedBefore := testutil.ToFloat64(
			groupMessageDispatchCounter.WithLabelValues("group_content", "suppressed"),
		)

		route, err := push.selectPushRoute(recipient, "")
		if err != nil || route == nil {
			t.Fatalf("select opaque route: route=%#v err=%v", route, err)
		}
		push.SendGroupNotification(
			context.Background(), recipient, groupID, sender, messageID, envelope, *route,
		)
		push.sendGroupContentNotificationForRoute(
			context.Background(), recipient, *route,
			groupContentPushMetadata{
				GroupID:               groupID,
				SenderTransportPeerID: sender,
				MessageID:             messageID,
				PayloadType:           groupContentPayloadTypeMessage,
			},
			envelope,
		)

		if got := recorder.SendCallCount(); got != 1 {
			t.Fatalf("opaque exact cross-adapter provider sends = %d, want 1", got)
		}
		if delta := testutil.ToFloat64(
			groupMessageDispatchCounter.WithLabelValues("group_inbox", "accepted"),
		) - inboxAcceptedBefore; delta != 1 {
			t.Fatalf("opaque inbox accepted delta = %v, want 1", delta)
		}
		if delta := testutil.ToFloat64(
			groupMessageDispatchCounter.WithLabelValues("group_content", "accepted"),
		) - contentAcceptedBefore; delta != 0 {
			t.Fatalf("opaque duplicate content accepted delta = %v, want 0", delta)
		}
		if delta := testutil.ToFloat64(
			groupMessageDispatchCounter.WithLabelValues("group_content", "suppressed"),
		) - contentSuppressedBefore; delta != 1 {
			t.Fatalf("opaque duplicate content suppressed delta = %v, want 1", delta)
		}
	})

	t.Run("recipient group and canonical message are independent key dimensions", func(t *testing.T) {
		const otherRecipient = "tc398-admission-other-recipient"
		tokens := newMemoryPushTokenStore()
		for peerID, token := range map[string]string{
			recipient:      "tc398-admission-primary-token",
			otherRecipient: "tc398-admission-other-token",
		} {
			if err := tokens.RegisterToken(peerID, token, "ios"); err != nil {
				t.Fatalf("register %s: %v", peerID, err)
			}
		}
		push := NewPushServiceWithBackend(tokens)
		push.retryDelays = nil
		recorder := newRecordingPushSender()
		push.sender = recorder.Send

		push.SendGroupNotification(context.Background(), recipient, groupID, sender, messageID, envelope)
		push.SendGroupNotification(context.Background(), recipient, groupID, sender, messageID, envelope)
		push.SendGroupNotification(context.Background(), recipient, "39810000-0000-4000-8000-000000000002", sender, messageID, envelope)
		push.SendGroupNotification(context.Background(), otherRecipient, groupID, sender, messageID, envelope)
		push.SendGroupNotification(context.Background(), recipient, groupID, sender, "tc398-admission-message-2", envelope)

		if got := recorder.SendCallCount(); got != 4 {
			t.Fatalf("provider sends across one duplicate and three independent identities = %d, want 4", got)
		}
	})

	t.Run("transient retries remain inside the one admitted logical dispatch", func(t *testing.T) {
		tokens := newMemoryPushTokenStore()
		if err := tokens.RegisterToken(recipient, "tc398-admission-retry-token", "ios"); err != nil {
			t.Fatalf("register retry route: %v", err)
		}
		push := NewPushServiceWithBackend(tokens)
		push.retryDelays = []time.Duration{0}
		recorder := newRecordingPushSender()
		recorder.onSend = func(context.Context, *messaging.Message) (string, error) {
			if recorder.SendCallCount() == 1 {
				return "", fmt.Errorf("temporary provider outage")
			}
			return "projects/test/messages/tc398-admission-provider", nil
		}
		push.sender = recorder.Send
		var journal []groupMessageProviderAttemptJournalRecord
		push.journalGroupMessageProviderAttempt = func(record groupMessageProviderAttemptJournalRecord) {
			journal = append(journal, record)
		}

		push.SendGroupNotification(context.Background(), recipient, groupID, sender, messageID, envelope)
		route, err := push.selectPushRoute(recipient, "")
		if err != nil || route == nil {
			t.Fatalf("select duplicate route: route=%#v err=%v", route, err)
		}
		push.sendGroupContentNotificationForRoute(
			context.Background(), recipient, *route,
			groupContentPushMetadata{
				GroupID:               groupID,
				SenderTransportPeerID: sender,
				MessageID:             messageID,
				PayloadType:           groupContentPayloadTypeMessage,
			},
			envelope,
		)

		if got := recorder.SendCallCount(); got != 2 {
			t.Fatalf("provider calls = %d, want the admitted retry pair only", got)
		}
		if got := len(journal); got != 2 {
			t.Fatalf("provider journal rows = %d, want the admitted retry pair only", got)
		}
		attempts := recorder.Messages()
		firstCollapse, firstOK := tc395APNSCollapseID(attempts[0])
		secondCollapse, secondOK := tc395APNSCollapseID(attempts[1])
		if !firstOK || !secondOK || firstCollapse == "" || secondCollapse != firstCollapse {
			t.Fatalf("retry collapse identities = (%q,%v) (%q,%v), want one stable identity", firstCollapse, firstOK, secondCollapse, secondOK)
		}
	})

	t.Run("concurrent duplicate is suppressed while the admitted provider send is in flight", func(t *testing.T) {
		tokens := newMemoryPushTokenStore()
		if err := tokens.RegisterToken(recipient, "tc398-admission-concurrent-token", "ios"); err != nil {
			t.Fatalf("register concurrent route: %v", err)
		}
		push := NewPushServiceWithBackend(tokens)
		push.retryDelays = nil
		providerEntered := make(chan struct{})
		releaseProvider := make(chan struct{})
		var providerCalls atomic.Int32
		push.sender = func(context.Context, *messaging.Message) (string, error) {
			call := providerCalls.Add(1)
			if call == 1 {
				close(providerEntered)
				<-releaseProvider
			}
			return "projects/test/messages/tc398-admission-concurrent", nil
		}
		route, err := push.selectPushRoute(recipient, "")
		if err != nil || route == nil {
			t.Fatalf("select concurrent route: route=%#v err=%v", route, err)
		}

		ordinaryDone := make(chan struct{})
		go func() {
			push.SendGroupNotification(context.Background(), recipient, groupID, sender, messageID, envelope, *route)
			close(ordinaryDone)
		}()
		select {
		case <-providerEntered:
		case <-time.After(2 * time.Second):
			t.Fatal("admitted provider send did not enter")
		}

		duplicateDone := make(chan struct{})
		go func() {
			push.sendGroupContentNotificationForRoute(
				context.Background(), recipient, *route,
				groupContentPushMetadata{
					GroupID:               groupID,
					SenderTransportPeerID: sender,
					MessageID:             messageID,
					PayloadType:           groupContentPayloadTypeMessage,
				},
				envelope,
			)
			close(duplicateDone)
		}()
		select {
		case <-duplicateDone:
		case <-time.After(2 * time.Second):
			t.Fatal("concurrent duplicate did not terminate at admission")
		}
		if got := providerCalls.Load(); got != 1 {
			t.Fatalf("in-flight exact duplicate entered provider: calls=%d want 1", got)
		}
		close(releaseProvider)
		select {
		case <-ordinaryDone:
		case <-time.After(2 * time.Second):
			t.Fatal("admitted provider send did not finish")
		}
	})

	t.Run("definitive provider rejection releases only after the admitted attempt fails", func(t *testing.T) {
		tokens := newMemoryPushTokenStore()
		if err := tokens.RegisterToken(recipient, "tc398-admission-release-token", "ios"); err != nil {
			t.Fatalf("register release route: %v", err)
		}
		backend := &retainingRevokedPushRouteBackend{PushTokenBackend: tokens}
		push := NewPushServiceWithBackend(backend)
		push.retryDelays = nil
		recorder := newRecordingPushSender()
		recorder.onSend = func(context.Context, *messaging.Message) (string, error) {
			if recorder.SendCallCount() == 1 {
				return "", fmt.Errorf("registration-token-not-registered")
			}
			return "projects/test/messages/tc398-admission-after-release", nil
		}
		push.sender = recorder.Send
		route, err := push.selectPushRoute(recipient, "")
		if err != nil || route == nil {
			t.Fatalf("select release route: route=%#v err=%v", route, err)
		}

		push.SendGroupNotification(context.Background(), recipient, groupID, sender, messageID, envelope, *route)
		push.sendGroupContentNotificationForRoute(
			context.Background(), recipient, *route,
			groupContentPushMetadata{
				GroupID:               groupID,
				SenderTransportPeerID: sender,
				MessageID:             messageID,
				PayloadType:           groupContentPayloadTypeMessage,
			},
			envelope,
		)
		if got := recorder.SendCallCount(); got != 2 {
			t.Fatalf("provider calls across definitive rejection and later adapter = %d, want 2", got)
		}
	})

	t.Run("preflight-selected opaque group wake retains exact identity", func(t *testing.T) {
		tokens := newMemoryPushTokenStore()
		if err := tokens.RegisterToken(
			recipient,
			"tc398-admission-preflight-opaque",
			"ios",
			opaqueWakeCapability,
		); err != nil {
			t.Fatalf("register preflight opaque route: %v", err)
		}
		push := NewPushServiceWithBackend(tokens)
		push.retryDelays = nil
		recorder := newRecordingPushSender()
		push.sender = recorder.Send
		route, err := push.selectPushRoute(recipient, "")
		if err != nil || route == nil {
			t.Fatalf("select preflight opaque route: route=%#v err=%v", route, err)
		}

		result := push.sendGroupOpaqueWakeThroughGateway(
			context.Background(), recipient, groupID, messageID, *route, wakeOutcomePolicyNone,
		)
		if result != pushDeliveryAccepted {
			t.Fatalf("preflight opaque result = %q, want accepted", result)
		}
		push.sendGroupContentNotificationForRoute(
			context.Background(), recipient, *route,
			groupContentPushMetadata{
				GroupID:               groupID,
				SenderTransportPeerID: sender,
				MessageID:             messageID,
				PayloadType:           groupContentPayloadTypeMessage,
			},
			envelope,
		)
		if got := recorder.SendCallCount(); got != 1 {
			t.Fatalf("preflight opaque plus exact content duplicate provider calls = %d, want 1", got)
		}
	})
}

func TestRelayNotificationClosure_GroupMessageProviderProvenance(t *testing.T) {
	const (
		firstDispatchID  = "11111111-1111-4111-8111-111111111111"
		secondDispatchID = "22222222-2222-4222-8222-222222222222"
		messageID        = "tc398-provider-provenance-message"
		providerName     = "projects/mknoon-test/messages/0:1787612345678901%abcdefabcdefabcd"
		providerID       = "0:1787612345678901%abcdefabcdefabcd"
	)

	t.Run("one logical dispatch keeps one correlation across retry and provider receipt", func(t *testing.T) {
		push, recorder := ordinaryPushService("ios")
		generated := []string{firstDispatchID, secondDispatchID}
		generatorCalls := 0
		push.newGroupMessageDispatchID = func() (string, error) {
			value := generated[generatorCalls]
			generatorCalls++
			return value, nil
		}
		var journal []groupMessageProviderAttemptJournalRecord
		push.journalGroupMessageProviderAttempt = func(record groupMessageProviderAttemptJournalRecord) {
			journal = append(journal, record)
		}
		recorder.onSend = func(context.Context, *messaging.Message) (string, error) {
			if recorder.SendCallCount() == 1 {
				return "", fmt.Errorf("temporary provider outage")
			}
			return providerName, nil
		}

		push.SendGroupNotification(
			context.Background(), "recipient",
			"88888888-8888-4888-8888-888888888888",
			"tc398-sender-transport", messageID,
			ordinaryGroupCiphertextEnvelope(16),
		)

		if generatorCalls != 1 {
			t.Fatalf("dispatch ID generator calls = %d, want 1", generatorCalls)
		}
		attempts := recorder.Messages()
		if len(attempts) != 2 {
			t.Fatalf("provider attempts = %d, want 2", len(attempts))
		}
		collapse := boundedGroupMessageIdentity(messageID)
		for index, attempt := range attempts {
			if got := sentRoutingString(attempt, groupMessageDispatchIDKey); got != firstDispatchID {
				t.Fatalf("attempt %d dispatch ID = %q, want stable %q", index+1, got, firstDispatchID)
			}
			if got := sentRoutingString(attempt, groupMessageCollapseClaimKey); got != collapse {
				t.Fatalf("attempt %d collapse claim = %q, want %q", index+1, got, collapse)
			}
			if got, ok := tc395APNSCollapseID(attempt); !ok || got != collapse {
				t.Fatalf("attempt %d APNs collapse = %q present=%v, want %q", index+1, got, ok, collapse)
			}
		}
		if len(journal) != 2 {
			t.Fatalf("provider journal rows = %d, want 2", len(journal))
		}
		for index, row := range journal {
			if row.Schema != groupMessageProviderAttemptJournalSchema ||
				row.Source != string(groupMessageDispatchSourceInbox) ||
				row.Provenance != groupMessageProviderProvenanceComplete ||
				row.DispatchCorrelationSha256 != sha256Hex(firstDispatchID) ||
				row.ClaimedCollapseIdentifierSha256 != sha256Hex(collapse) ||
				row.ProviderAttempt != index+1 || row.AttemptKind != groupMessageProviderAttemptPrimary {
				t.Fatalf("provider journal row %d = %#v", index+1, row)
			}
		}
		if journal[0].Outcome != groupMessageProviderOutcomeRetryable ||
			journal[0].FirebaseResponseNameSha256 != "" || journal[0].ProviderMessageIDSha256 != "" {
			t.Fatalf("retry journal row = %#v", journal[0])
		}
		if journal[1].Outcome != groupMessageProviderOutcomeAccepted ||
			journal[1].FirebaseResponseNameSha256 != sha256Hex(providerName) ||
			journal[1].ProviderMessageIDSha256 != sha256Hex(providerID) {
			t.Fatalf("accepted journal row = %#v", journal[1])
		}

		recorder.onSend = nil
		push.retryDelays = nil
		push.SendGroupNotification(
			context.Background(), "recipient",
			"88888888-8888-4888-8888-888888888888",
			"tc398-sender-transport", messageID+"-second",
			ordinaryGroupCiphertextEnvelope(16),
		)
		if generatorCalls != 2 {
			t.Fatalf("second logical dispatch generator calls = %d, want 2", generatorCalls)
		}
		latest := recorder.Messages()[2]
		if got := sentRoutingString(latest, groupMessageDispatchIDKey); got != secondDispatchID {
			t.Fatalf("second logical dispatch ID = %q, want %q", got, secondDispatchID)
		}
		secondCollapse := boundedGroupMessageIdentity(messageID + "-second")
		if got := sentRoutingString(latest, groupMessageCollapseClaimKey); got != secondCollapse || got == collapse {
			t.Fatalf("second logical collapse = %q, want distinct %q", got, secondCollapse)
		}
	})

	t.Run("invalid provenance fails open without raw leakage", func(t *testing.T) {
		push, recorder := ordinaryPushService("ios")
		push.retryDelays = nil
		push.newGroupMessageDispatchID = func() (string, error) {
			return "not-a-canonical-dispatch-id", nil
		}
		var journal []groupMessageProviderAttemptJournalRecord
		push.journalGroupMessageProviderAttempt = func(record groupMessageProviderAttemptJournalRecord) {
			journal = append(journal, record)
		}

		push.SendGroupNotification(
			context.Background(), "recipient",
			"88888888-8888-4888-8888-888888888888",
			"tc398-sender-transport", messageID,
			ordinaryGroupCiphertextEnvelope(16),
		)

		if recorder.SendCallCount() != 1 {
			t.Fatalf("invalid provenance provider calls = %d, want delivery to continue once", recorder.SendCallCount())
		}
		message := recorder.Messages()[0]
		if sentRoutingHas(message, groupMessageDispatchIDKey) || sentRoutingHas(message, groupMessageCollapseClaimKey) {
			t.Fatalf("invalid provenance leaked into provider payload: %#v", message)
		}
		if len(journal) != 1 || journal[0].Provenance != groupMessageProviderProvenanceUnavailable ||
			journal[0].DispatchCorrelationSha256 != "" || journal[0].ClaimedCollapseIdentifierSha256 != "" ||
			journal[0].Outcome != groupMessageProviderOutcomeAccepted {
			t.Fatalf("invalid provenance journal = %#v", journal)
		}
	})

	t.Run("Android projection never carries iOS provenance", func(t *testing.T) {
		push, recorder := ordinaryPushService("android")
		push.newGroupMessageDispatchID = func() (string, error) { return firstDispatchID, nil }
		var journal []groupMessageProviderAttemptJournalRecord
		push.journalGroupMessageProviderAttempt = func(record groupMessageProviderAttemptJournalRecord) {
			journal = append(journal, record)
		}
		push.SendGroupNotification(
			context.Background(), "recipient",
			"88888888-8888-4888-8888-888888888888",
			"tc398-sender-transport", messageID,
			ordinaryGroupCiphertextEnvelope(16),
		)
		message := recorder.Messages()[0]
		if message.APNS != nil || sentRoutingHas(message, groupMessageDispatchIDKey) ||
			sentRoutingHas(message, groupMessageCollapseClaimKey) {
			t.Fatalf("Android projection leaked iOS provenance: %#v", message)
		}
		if len(journal) != 0 {
			t.Fatalf("Android produced iOS provider provenance rows: %#v", journal)
		}
	})
}

// TC-398-09 — one logical iOS group dispatch keeps its complete provenance
// tuple across a stale-route re-selection, a transient provider retry, and the
// strict provider-size fallback. The retained provider journal exposes only
// hashes of the dispatch, collapse, and Firebase receipt identities.
func TestRelayNotificationClosure_TC39809StrictFallbackProvenancePrivacy(t *testing.T) {
	const (
		dispatchID   = "39800000-0000-4000-8000-000000000009"
		messageID    = "tc398-09-strict-fallback-message"
		providerName = "projects/mknoon-test/messages/0:1787698765432109%3983983983983983"
		providerID   = "0:1787698765432109%3983983983983983"
	)

	tokens := newMemoryPushTokenStore()
	if err := tokens.RegisterToken("recipient", "tc398-09-stale-token", "ios"); err != nil {
		t.Fatalf("register initial iOS route: %v", err)
	}
	backend := &plan368BackendProbe{delegate: tokens}
	backend.resolve = func(call int, route pushRouteLease) (*resolvedPushTarget, error) {
		if call == 1 {
			if err := tokens.RegisterToken("recipient", "tc398-09-refreshed-token", "ios"); err != nil {
				t.Fatalf("refresh iOS route: %v", err)
			}
			return nil, ErrPushRouteStale
		}
		return tokens.ResolveRoute(route)
	}

	push := NewPushServiceWithBackend(backend)
	push.retryDelays = []time.Duration{0}
	generatorCalls := 0
	push.newGroupMessageDispatchID = func() (string, error) {
		generatorCalls++
		return dispatchID, nil
	}
	recorder := newRecordingPushSender()
	recorder.onSend = func(context.Context, *messaging.Message) (string, error) {
		switch recorder.SendCallCount() {
		case 1:
			return "", fmt.Errorf("temporary provider outage")
		case 2:
			return "", fmt.Errorf("messaging/invalid-argument: Message is too large. The maximum is 4K (4096 bytes)")
		default:
			return providerName, nil
		}
	}
	push.sender = recorder.Send

	var journalRows []groupMessageProviderAttemptJournalRecord
	var journal bytes.Buffer
	previousWriter := log.Writer()
	log.SetOutput(&journal)
	t.Cleanup(func() { log.SetOutput(previousWriter) })
	push.journalGroupMessageProviderAttempt = func(record groupMessageProviderAttemptJournalRecord) {
		journalRows = append(journalRows, record)
		defaultGroupMessageProviderAttemptJournal(record)
	}

	push.SendGroupNotification(
		context.Background(),
		"recipient",
		"88888888-8888-4888-8888-888888888888",
		"tc398-09-sender-transport",
		messageID,
		ordinaryGroupCiphertextEnvelope(16),
	)

	if !canonicalGroupMessageDispatchID(dispatchID) {
		t.Fatalf("fixture dispatch ID is not canonical lowercase UUIDv4: %q", dispatchID)
	}
	if generatorCalls != 1 {
		t.Fatalf("dispatch ID generator calls = %d, want one logical dispatch", generatorCalls)
	}
	lookups, resolves, revokes := backend.counts()
	if lookups != 2 || resolves != 2 || revokes != 0 {
		t.Fatalf("route gateway calls lookup/resolve/revoke = %d/%d/%d, want 2/2/0", lookups, resolves, revokes)
	}

	attempts := recorder.Messages()
	if len(attempts) != 3 {
		t.Fatalf("provider attempts = %d, want retry pair plus strict fallback", len(attempts))
	}
	collapse := boundedGroupMessageIdentity(messageID)
	for index, attempt := range attempts {
		if attempt.Token != "tc398-09-refreshed-token" {
			t.Fatalf("attempt %d token did not use refreshed route", index+1)
		}
		assertAPNSCustomString(t, attempt, groupMessageDispatchClaimKey, groupMessageDispatchClaimInbox)
		assertAPNSCustomString(t, attempt, groupMessageDispatchIDKey, dispatchID)
		assertAPNSCustomString(t, attempt, groupMessageCollapseClaimKey, collapse)
		if got, ok := tc395APNSCollapseID(attempt); !ok || got != collapse {
			t.Fatalf("attempt %d APNs collapse = %q present=%v, want exact claim %q", index+1, got, ok, collapse)
		}
		if _, leaked := attempt.Data[groupMessageDispatchIDKey]; leaked {
			t.Fatalf("attempt %d leaked dispatch ID into top-level Data: %#v", index+1, attempt.Data)
		}
		if _, leaked := attempt.Data[groupMessageCollapseClaimKey]; leaked {
			t.Fatalf("attempt %d leaked collapse claim into top-level Data: %#v", index+1, attempt.Data)
		}
	}

	if len(journalRows) != 3 {
		t.Fatalf("provider journal rows = %d, want one per provider attempt", len(journalRows))
	}
	wantKinds := []string{
		groupMessageProviderAttemptPrimary,
		groupMessageProviderAttemptPrimary,
		groupMessageProviderAttemptStrictFallback,
	}
	wantOutcomes := []string{
		groupMessageProviderOutcomeRetryable,
		groupMessageProviderOutcomePayloadTooLarge,
		groupMessageProviderOutcomeAccepted,
	}
	for index, row := range journalRows {
		if row.Schema != groupMessageProviderAttemptJournalSchema ||
			row.Source != string(groupMessageDispatchSourceInbox) ||
			row.Provenance != groupMessageProviderProvenanceComplete ||
			row.DispatchCorrelationSha256 != sha256Hex(dispatchID) ||
			row.ClaimedCollapseIdentifierSha256 != sha256Hex(collapse) ||
			row.ProviderAttempt != index+1 || row.AttemptKind != wantKinds[index] ||
			row.Outcome != wantOutcomes[index] {
			t.Fatalf("provider journal row %d = %#v", index+1, row)
		}
	}
	for index, row := range journalRows[:2] {
		if row.FirebaseResponseNameSha256 != "" || row.ProviderMessageIDSha256 != "" {
			t.Fatalf("failed provider attempt %d retained a receipt: %#v", index+1, row)
		}
	}
	accepted := journalRows[2]
	if accepted.FirebaseResponseNameSha256 != sha256Hex(providerName) ||
		accepted.ProviderMessageIDSha256 != sha256Hex(providerID) {
		t.Fatalf("strict fallback receipt hashes = %#v", accepted)
	}

	journalText := journal.String()
	if got := strings.Count(journalText, "[GROUP_MESSAGE_PROVIDER_ATTEMPT]"); got != 3 {
		t.Fatalf("provider journal line count = %d, want 3: %q", got, journalText)
	}
	for _, hash := range []string{
		sha256Hex(dispatchID),
		sha256Hex(collapse),
		sha256Hex(providerName),
		sha256Hex(providerID),
	} {
		if !strings.Contains(journalText, hash) {
			t.Fatalf("provider journal omitted required hash %q: %q", hash, journalText)
		}
	}
	for _, raw := range []string{
		dispatchID,
		collapse,
		groupMessageDispatchClaimInbox,
		providerName,
		providerID,
	} {
		if strings.Contains(journalText, raw) {
			t.Fatalf("provider journal leaked raw provenance value %q: %q", raw, journalText)
		}
	}
}

func TestRelayNotificationClosure_FirebaseProviderMessageIDNormalization(t *testing.T) {
	tests := []struct {
		name string
		raw  string
		want string
	}{
		{"canonical", "projects/mknoon/messages/0:1787612345678901%abcdefabcdefabcd", "0:1787612345678901%abcdefabcdefabcd"},
		{"empty", "", ""},
		{"missing project", "projects//messages/provider-id", ""},
		{"extra segment", "projects/mknoon/messages/provider-id/extra", ""},
		{"wrong resource", "projects/mknoon/topics/provider-id", ""},
		{"surrounding whitespace", " projects/mknoon/messages/provider-id ", ""},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := normalizedFirebaseProviderMessageID(tc.raw); got != tc.want {
				t.Fatalf("normalized provider ID = %q, want %q", got, tc.want)
			}
		})
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
