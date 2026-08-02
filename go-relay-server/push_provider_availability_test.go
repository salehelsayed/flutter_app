package main

import (
	"bytes"
	"context"
	"log"
	"strings"
	"testing"
	"time"

	"github.com/prometheus/client_golang/prometheus/testutil"
)

func TestPushProviderUnavailableIsNotCountedAsSuccess(t *testing.T) {
	tokens := newMemoryPushTokenStore()
	tokens.RegisterToken("recipient", "recipient-token", "android")
	push := NewPushServiceWithBackend(tokens)
	push.retryDelays = []time.Duration{0, 0}

	// NewPushServiceWithBackend deliberately leaves both delivery seams nil.
	// That must be a preflight refusal, not a successful no-op send.
	if push.sender != nil || push.client != nil {
		t.Fatal("fixture requires both push providers to be unavailable")
	}

	unavailable := pushSentCounter.WithLabelValues("provider_unavailable")
	success := pushSentCounter.WithLabelValues("success")
	beforeUnavailable := testutil.ToFloat64(unavailable)
	beforeSuccess := testutil.ToFloat64(success)

	journal := &bytes.Buffer{}
	previousWriter := log.Writer()
	log.SetOutput(journal)
	t.Cleanup(func() { log.SetOutput(previousWriter) })

	push.SendNotification(
		context.Background(),
		"recipient",
		"sender",
		`{"type":"chat_message","version":"2","id":"provider-unavailable","encrypted":{"kem":"kem","ciphertext":"ciphertext","nonce":"nonce"}}`,
	)

	if delta := testutil.ToFloat64(unavailable) - beforeUnavailable; delta != 1 {
		t.Fatalf("provider_unavailable delta = %v, want 1", delta)
	}
	if delta := testutil.ToFloat64(success) - beforeSuccess; delta != 0 {
		t.Fatalf("success delta = %v, want 0", delta)
	}
	if tokens.LookupToken("recipient") == nil {
		t.Fatal("provider absence must not evict a registered token")
	}
	if got := journal.String(); !strings.Contains(got, "provider unavailable") || strings.Contains(got, "attempt") {
		t.Fatalf("journal = %q, want one provider-unavailable preflight with no send/retry attempts", got)
	}
}

func TestPushProviderUnavailablePrecedesInvalidPayloadAccounting(t *testing.T) {
	tokens := newMemoryPushTokenStore()
	tokens.RegisterToken("recipient", "recipient-token", "android")
	push := NewPushServiceWithBackend(tokens)

	unavailable := pushSentCounter.WithLabelValues("provider_unavailable")
	invalidPayload := pushSentCounter.WithLabelValues("invalid_payload")
	beforeUnavailable := testutil.ToFloat64(unavailable)
	beforeInvalidPayload := testutil.ToFloat64(invalidPayload)

	// Empty sender routing makes the unusable-envelope fallback nil. Provider
	// readiness is nevertheless the authoritative preflight result: no delivery
	// implementation exists to inspect or send any payload.
	push.SendNotification(
		context.Background(),
		"recipient",
		"",
		`{"type":"chat_message","version":"2","id":"provider-unavailable-invalid","encrypted":{"ciphertext":"missing-routing-and-nonce"}}`,
	)

	if delta := testutil.ToFloat64(unavailable) - beforeUnavailable; delta != 1 {
		t.Fatalf("provider_unavailable delta = %v, want 1", delta)
	}
	if delta := testutil.ToFloat64(invalidPayload) - beforeInvalidPayload; delta != 0 {
		t.Fatalf("invalid_payload delta = %v, want 0", delta)
	}
}

func TestPushProviderUnavailableOwnsResultForUnusableEnvelopeFallback(t *testing.T) {
	tokens := newMemoryPushTokenStore()
	tokens.RegisterToken("recipient", "recipient-token", "android")
	push := NewPushServiceWithBackend(tokens)

	unavailable := pushSentCounter.WithLabelValues("provider_unavailable")
	legacyFallbackResult := pushSentCounter.WithLabelValues("unusable_envelope_fallback")
	fallbackClassification := pushFallbackCounter.WithLabelValues("unusable_envelope_fallback")
	beforeUnavailable := testutil.ToFloat64(unavailable)
	beforeLegacyFallbackResult := testutil.ToFloat64(legacyFallbackResult)
	beforeFallbackClassification := testutil.ToFloat64(fallbackClassification)

	push.SendNotification(
		context.Background(),
		"recipient",
		"sender",
		`{"type":"chat_message","version":"2","id":"provider-unavailable-fallback","encrypted":{"kem":"kem","ciphertext":"ciphertext-without-a-nonce"}}`,
	)

	if delta := testutil.ToFloat64(unavailable) - beforeUnavailable; delta != 1 {
		t.Fatalf("provider_unavailable delta = %v, want 1", delta)
	}
	if delta := testutil.ToFloat64(legacyFallbackResult) - beforeLegacyFallbackResult; delta != 0 {
		t.Fatalf("unusable fallback send-result delta = %v, want 0", delta)
	}
	if delta := testutil.ToFloat64(fallbackClassification) - beforeFallbackClassification; delta != 1 {
		t.Fatalf("unusable fallback classification delta = %v, want 1", delta)
	}
}
