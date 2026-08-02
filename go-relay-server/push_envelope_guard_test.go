package main

import (
	"testing"

	"firebase.google.com/go/v4/messaging"
	"github.com/prometheus/client_golang/prometheus/testutil"
)

func TestGroupPushFallsBackWhenEnvelopeUnusable(t *testing.T) {
	const (
		groupID = "88888888-8888-4888-8888-888888888888"
		sender  = "12D3KooWAuthenticatedTransport"
	)

	unusableFallback := pushFallbackCounter.WithLabelValues("unusable_envelope_fallback")
	oversizedFallback := pushFallbackCounter.WithLabelValues("oversized_fallback")
	beforeUnusable := testutil.ToFloat64(unusableFallback)
	beforeOversized := testutil.ToFloat64(oversizedFallback)

	msg := buildGroupPushMessage(
		"recipient-token",
		groupID,
		sender,
		"group-unusable",
		`{"version":"3","type":"group_message","groupId":"88888888-8888-4888-8888-888888888888","messageId":"group-unusable","keyEpoch":7,"encrypted":{"ciphertext":"ciphertext-without-a-nonce"}}`,
	)

	assertUnusableEnvelopeFallback(t, msg, map[string]string{
		"type":                     "group_message",
		"groupId":                  groupID,
		"sender_transport_peer_id": sender,
		"preview_unavailable":      "1",
	})
	if delta := testutil.ToFloat64(unusableFallback) - beforeUnusable; delta != 1 {
		t.Fatalf("unusable_envelope_fallback delta = %v, want 1", delta)
	}
	if delta := testutil.ToFloat64(oversizedFallback) - beforeOversized; delta != 0 {
		t.Fatalf("oversized_fallback delta = %v, want 0", delta)
	}
}

func TestChatPushFallsBackWhenEnvelopeUnusable(t *testing.T) {
	unusableFallback := pushFallbackCounter.WithLabelValues("unusable_envelope_fallback")
	oversizedFallback := pushFallbackCounter.WithLabelValues("oversized_fallback")
	beforeUnusable := testutil.ToFloat64(unusableFallback)
	beforeOversized := testutil.ToFloat64(oversizedFallback)

	msg := buildPushMessage(
		"recipient-token",
		"12D3KooWAuthenticatedTransport",
		`{"type":"chat_message","version":"2","id":"chat-unusable","encrypted":{"kem":"kem","ciphertext":"ciphertext-without-a-nonce"}}`,
	)

	assertUnusableEnvelopeFallback(t, msg, map[string]string{
		"type":                "new_message",
		"sender_id":           "12D3KooWAuthenticatedTransport",
		"preview_unavailable": "1",
	})
	if delta := testutil.ToFloat64(unusableFallback) - beforeUnusable; delta != 1 {
		t.Fatalf("unusable_envelope_fallback delta = %v, want 1", delta)
	}
	if delta := testutil.ToFloat64(oversizedFallback) - beforeOversized; delta != 0 {
		t.Fatalf("oversized_fallback delta = %v, want 0", delta)
	}
}

func TestGroupPushFallsBackWhenKeyEpochUnusable(t *testing.T) {
	const (
		groupID = "88888888-8888-4888-8888-888888888888"
		sender  = "12D3KooWAuthenticatedTransport"
	)

	for name, envelope := range map[string]string{
		"non-numeric": `{"version":"3","type":"group_message","groupId":"88888888-8888-4888-8888-888888888888","keyEpoch":"bogus","encrypted":{"ciphertext":"ciphertext","nonce":"nonce"}}`,
		"fractional":  `{"version":"3","type":"group_message","groupId":"88888888-8888-4888-8888-888888888888","keyEpoch":1.5,"encrypted":{"ciphertext":"ciphertext","nonce":"nonce"}}`,
		"zero":        `{"version":"3","type":"group_message","groupId":"88888888-8888-4888-8888-888888888888","keyEpoch":0,"encrypted":{"ciphertext":"ciphertext","nonce":"nonce"}}`,
		"negative":    `{"version":"3","type":"group_message","groupId":"88888888-8888-4888-8888-888888888888","keyEpoch":-1,"encrypted":{"ciphertext":"ciphertext","nonce":"nonce"}}`,
	} {
		t.Run(name, func(t *testing.T) {
			msg := buildGroupPushMessage(
				"recipient-token",
				groupID,
				sender,
				"group-invalid-epoch-"+name,
				envelope,
			)
			assertUnusableEnvelopeFallback(t, msg, map[string]string{
				"type":                     "group_message",
				"groupId":                  groupID,
				"sender_transport_peer_id": sender,
				"preview_unavailable":      "1",
			})
		})
	}
}

func assertUnusableEnvelopeFallback(t *testing.T, msg *messaging.Message, want map[string]string) {
	t.Helper()
	if msg == nil {
		t.Fatal("unusable envelope returned nil, want routable preview_unavailable fallback")
	}
	if msg.Data["preview_unavailable"] != "1" {
		t.Fatalf("preview_unavailable = %q, want 1; data=%#v", msg.Data["preview_unavailable"], msg.Data)
	}
	for key, value := range want {
		if got := msg.Data[key]; got != value {
			t.Fatalf("data[%q] = %q, want %q; data=%#v", key, got, value, msg.Data)
		}
	}
	for _, key := range []string{"kem", "ciphertext", "nonce", "keyEpoch"} {
		if _, ok := msg.Data[key]; ok {
			t.Fatalf("fallback retained encrypted field %q: %#v", key, msg.Data)
		}
	}
	if msg.APNS == nil || msg.APNS.Payload == nil {
		t.Fatal("fallback omitted APNS payload")
	}
	for key, value := range want {
		if got, ok := msg.APNS.Payload.CustomData[key].(string); !ok || got != value {
			t.Fatalf("APNS CustomData[%q] = %#v, want %q", key, msg.APNS.Payload.CustomData[key], value)
		}
	}
}
