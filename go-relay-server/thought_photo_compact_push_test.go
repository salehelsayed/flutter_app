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

const thoughtPhotoCompactCiphertext = "compact-photo-ciphertext"

func thoughtPhotoCompactEncryptedJSON(ciphertext string) string {
	return fmt.Sprintf(`{"kem":%q,"ciphertext":%q,"nonce":"compact-nonce"}`,
		strings.Repeat("p", 1500), ciphertext)
}

func thoughtPhotoPushEnvelope(fullCiphertextBytes int, compactBlock string) string {
	optional := ""
	if compactBlock != "" {
		optional = `,"push_encrypted":` + compactBlock
	}
	return fmt.Sprintf(`{"type":"post_create","version":"2","event_id":"thought-photo-event","sender_peer_id":"peer-sender","post_id":"thought-photo-post","encrypted":{"kem":%q,"ciphertext":%q,"nonce":"full-nonce"}%s}`,
		strings.Repeat("k", 1500), strings.Repeat("f", fullCiphertextBytes), optional)
}

// Construct the full candidate before the production budget veto, so each
// regression case proves which existing limit forces its generic fallback.
func thoughtPhotoFullCandidate(t *testing.T, envelope string) *messaging.Message {
	t.Helper()
	data := map[string]string{
		"type": "post_create", "sender_id": "peer-sender",
		"message_id": "thought-photo-event", "post_id": "thought-photo-post",
	}
	if !addChatEncryptedPushData(data, envelope) {
		t.Fatal("fixture requires a valid canonical encrypted block")
	}
	return buildCiphertextOnlyPushMessage("recipient-token", data, "peer-sender", messaging.ApsAlert{
		Title: postCreatePushTitle, Body: postCreatePushBody,
	})
}

func assertThoughtPhotoCompactIOSPush(t *testing.T, sent *messaging.Message) {
	t.Helper()
	if sent == nil || sent.APNS == nil || sent.APNS.Payload == nil || sent.APNS.Payload.Aps == nil {
		t.Fatalf("iOS push = %#v, want an APNs alert", sent)
	}
	aps := sent.APNS.Payload.Aps
	if !aps.MutableContent {
		t.Fatal("oversized full photo with a fitting compact block must retain ciphertext and request NSE processing; got generic mutable-content=0")
	}
	if !aps.ContentAvailable || aps.Alert == nil || aps.Alert.Title != postCreatePushTitle || aps.Alert.Body != postCreatePushBody {
		t.Fatalf("compact aps = %#v, want the existing generic alert with content-available", aps)
	}
	if sent.APNS.Headers["apns-priority"] != "10" || sent.APNS.Headers["apns-push-type"] != "alert" {
		t.Fatalf("compact APNs headers = %#v, want priority 10 alert", sent.APNS.Headers)
	}
	if sent.Data != nil || sent.Android != nil || sent.Notification != nil {
		t.Fatalf("compact iOS push retained a duplicate or visible-copy platform field: %#v", sent)
	}
	want := map[string]string{
		"type": "post_create", "sender_id": "peer-sender",
		"message_id": "thought-photo-event", "post_id": "thought-photo-post",
		"envelope_version": "2", "kem": strings.Repeat("p", 1500),
		"ciphertext": thoughtPhotoCompactCiphertext, "nonce": "compact-nonce",
	}
	gotJSON, _ := json.Marshal(apnsCustomDataAsStringMap(sent))
	wantJSON, _ := json.Marshal(want)
	if string(gotJSON) != string(wantJSON) {
		t.Fatalf("compact APNs data = %s, want %s", gotJSON, wantJSON)
	}
	if !messageFitsProviderBudgets(sent) || pushDataSize(want) > maxPushDataBytes {
		t.Fatal("selected compact ciphertext exceeds the incumbent provider/data budgets")
	}
}

func TestThoughtPhotoCompactPush_IOSSelectsCompactOnlyAfterFullBudgetFailure(t *testing.T) {
	for _, tc := range []struct {
		name            string
		ciphertextBytes int
		dataOverBudget  bool
	}{
		{"full_data_and_platform_oversized", 6000, true},
		{"full_platform_oversized_data_still_fits", 2100, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			envelope := thoughtPhotoPushEnvelope(tc.ciphertextBytes, thoughtPhotoCompactEncryptedJSON(thoughtPhotoCompactCiphertext))
			full := thoughtPhotoFullCandidate(t, envelope)
			if got := pushDataSize(full.Data) > maxPushDataBytes; got != tc.dataOverBudget {
				t.Fatalf("fixture full data size = %d, over-budget=%v, want %v", pushDataSize(full.Data), got, tc.dataOverBudget)
			}
			if messageFitsProviderBudgets(full) {
				t.Fatal("fixture full photo must exceed an existing complete platform budget")
			}
			push, recorder := ordinaryPushService("ios")
			push.SendNotification(context.Background(), "recipient", "peer-sender", envelope)
			if got := recorder.SendCallCount(); got != 1 {
				t.Fatalf("provider calls = %d, want 1", got)
			}
			assertThoughtPhotoCompactIOSPush(t, recorder.LastMessage())
		})
	}
}

func TestThoughtPhotoCompactPush_FittingFullCiphertextRemainsAuthoritative(t *testing.T) {
	for _, compact := range []string{
		thoughtPhotoCompactEncryptedJSON(thoughtPhotoCompactCiphertext),
		`{"kem":"malformed"}`,
		thoughtPhotoCompactEncryptedJSON(strings.Repeat("c", 6000)),
	} {
		t.Run(fmt.Sprintf("compact_bytes_%d", len(compact)), func(t *testing.T) {
			push, recorder := ordinaryPushService("ios")
			envelope := thoughtPhotoPushEnvelope(100, compact)
			full := thoughtPhotoFullCandidate(t, envelope)
			if !messageFitsProviderBudgets(full) || pushDataSize(full.Data) > maxPushDataBytes {
				t.Fatal("fixture full ciphertext must fit both incumbent budgets")
			}
			push.SendNotification(context.Background(), "recipient", "peer-sender", envelope)
			want := projectPushMessageForPlatform(full, "ios")
			gotJSON, _ := json.Marshal(recorder.LastMessage())
			wantJSON, _ := json.Marshal(want)
			if string(gotJSON) != string(wantJSON) {
				t.Fatalf("fitting full ciphertext replaced or changed: got %s, want %s", gotJSON, wantJSON)
			}
		})
	}
}

func TestThoughtPhotoCompactPush_InvalidOrLegacyEnvelopeKeepsGenericFallback(t *testing.T) {
	validCompact := thoughtPhotoCompactEncryptedJSON(thoughtPhotoCompactCiphertext)
	oversized := thoughtPhotoPushEnvelope(6000, validCompact)
	cases := []struct {
		name     string
		envelope string
	}{
		{"old_envelope_without_compact", thoughtPhotoPushEnvelope(6000, "")},
		{"missing_full", strings.Replace(oversized, `"encrypted":`, `"not_encrypted":`, 1)},
		{"malformed_full", strings.Replace(oversized, `"kem":`, `"not_kem":`, 1)},
		{"missing_post_id", strings.Replace(oversized, `"post_id":`, `"not_post_id":`, 1)},
		{"compact_not_object", thoughtPhotoPushEnvelope(6000, `"not-a-block"`)},
		{"compact_missing_kem", thoughtPhotoPushEnvelope(6000, `{"ciphertext":"c","nonce":"n"}`)},
		{"compact_non_string_nonce", thoughtPhotoPushEnvelope(6000, `{"kem":"k","ciphertext":"c","nonce":7}`)},
		{"compact_blank_ciphertext", thoughtPhotoPushEnvelope(6000, `{"kem":"k","ciphertext":"  ","nonce":"n"}`)},
		{"compact_data_oversized", thoughtPhotoPushEnvelope(6000, thoughtPhotoCompactEncryptedJSON(strings.Repeat("c", 6000)))},
		{"compact_platform_oversized", thoughtPhotoPushEnvelope(6000, thoughtPhotoCompactEncryptedJSON(strings.Repeat("c", 2100)))},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			push, recorder := ordinaryPushService("ios")
			push.SendNotification(context.Background(), "recipient", "peer-sender", tc.envelope)
			if got := recorder.SendCallCount(); got != 1 {
				t.Fatalf("provider calls = %d, want 1 generic alert", got)
			}
			sent := recorder.LastMessage()
			if sent.APNS == nil || sent.APNS.Payload == nil || sent.APNS.Payload.Aps.MutableContent {
				t.Fatal("invalid/legacy compact photo must retain generic mutable-content=0")
			}
			if sentRoutingHas(sent, "ciphertext") || sentRoutingHas(sent, "kem") || sentRoutingHas(sent, "nonce") ||
				sentRoutingString(sent, "body") != postCreatePushBody {
				t.Fatalf("invalid/legacy photo changed the generic fallback: %#v", sent)
			}
		})
	}
}

func TestThoughtPhotoCompactPush_AndroidAndUnknownStayByteEquivalent(t *testing.T) {
	for _, platform := range []string{"android", "unknown", ""} {
		for _, fullBytes := range []int{100, 6000} {
			t.Run(fmt.Sprintf("%s/full_%d", platform, fullBytes), func(t *testing.T) {
				push, recorder := ordinaryPushService(platform)
				withCompact := thoughtPhotoPushEnvelope(fullBytes, thoughtPhotoCompactEncryptedJSON(thoughtPhotoCompactCiphertext))
				withoutCompact := thoughtPhotoPushEnvelope(fullBytes, "")
				push.SendNotification(context.Background(), "recipient", "peer-sender", withCompact)
				want := projectPushMessageForPlatform(buildPushMessage("recipient-token", "peer-sender", withoutCompact), platform)
				gotJSON, _ := json.Marshal(recorder.LastMessage())
				wantJSON, _ := json.Marshal(want)
				if string(gotJSON) != string(wantJSON) {
					t.Fatalf("%q platform changed with optional compact block: got %s, want %s", platform, gotJSON, wantJSON)
				}
			})
		}
	}
}

func TestThoughtPhotoCompactPush_StoredRetryPreservesCanonicalCustodyAndACK(t *testing.T) {
	envelope := thoughtPhotoPushEnvelope(6000, thoughtPhotoCompactEncryptedJSON(thoughtPhotoCompactCiphertext))
	push, recorder := ordinaryPushService("ios")
	push.retryDelays = []time.Duration{0}
	recorder.onSend = func(context.Context, *messaging.Message) (string, error) {
		if recorder.SendCallCount() == 1 {
			return "", fmt.Errorf("temporary provider outage")
		}
		return "photo-provider-id", nil
	}
	inbox := NewInboxStore(push)
	result, err := inbox.Store("recipient", inboxMessage{
		From: "peer-sender", Message: envelope, Timestamp: time.Now().UnixMilli(),
	})
	if err != nil || result != InboxStoreResultStored {
		t.Fatalf("store canonical photo: result=%q error=%v", result, err)
	}
	pending, _ := inbox.RetrievePendingWithMeta("recipient", 10)
	if len(pending) != 1 || pending[0].Message != envelope || pending[0].ID == "" {
		t.Fatalf("stored photo changed: %#v", pending)
	}
	tc395WaitForProviderCalls(t, recorder, 2)
	for _, sent := range recorder.Messages() {
		if collapse, ok := tc395APNSCollapseID(sent); !ok || collapse != pending[0].ID {
			t.Fatalf("photo retry collapse ID = %q present=%v, want custody %q", collapse, ok, pending[0].ID)
		}
	}
	removed, err := inbox.Ack("recipient", []string{pending[0].ID})
	if err != nil || removed != 1 || inbox.Count("recipient") != 0 {
		t.Fatalf("photo custody ACK: removed=%d remaining=%d error=%v", removed, inbox.Count("recipient"), err)
	}
	for _, sent := range recorder.Messages() {
		assertThoughtPhotoCompactIOSPush(t, sent)
	}
}
