package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"testing"
	"time"

	"firebase.google.com/go/v4/messaging"
	"github.com/alicebob/miniredis/v2"
)

func thoughtDeliveryEnvelope(t *testing.T, envelope string, fields map[string]interface{}) string {
	t.Helper()
	var decoded map[string]interface{}
	if err := json.Unmarshal([]byte(envelope), &decoded); err != nil {
		t.Fatal(err)
	}
	for key, value := range fields {
		if value == nil {
			delete(decoded, key)
		} else {
			decoded[key] = value
		}
	}
	encoded, err := json.Marshal(decoded)
	if err != nil {
		t.Fatal(err)
	}
	return string(encoded)
}

func TestThoughtNotificationProviderDeadlineFollowsAuthoredLifetime(t *testing.T) {
	now := time.Date(2026, 11, 8, 12, 0, 0, 0, time.UTC)
	deadline := now.Add(30 * time.Second)
	for _, platform := range []string{"android", "ios"} {
		for _, fixture := range thoughtNotificationPushCases() {
			t.Run(platform+"/"+fixture.name, func(t *testing.T) {
				push, recorder := ordinaryPushService(platform)
				push.now = func() time.Time { return now }
				envelope := thoughtDeliveryEnvelope(t, fixture.envelope, map[string]interface{}{
					"created_at": deadline.Add(-24 * time.Hour).Format(time.RFC3339Nano),
				})
				push.SendNotification(context.Background(), "recipient", "authenticated-sender", envelope)
				if got := recorder.SendCallCount(); got != 1 {
					t.Fatalf("provider attempts = %d, want one unexpired Thought", got)
				}
				sent := recorder.LastMessage()
				if got := sentRoutingString(sent, "expires_at"); got != deadline.Format(time.RFC3339Nano) {
					t.Errorf("routing expiry = %q, want authored deadline %q", got, deadline.Format(time.RFC3339Nano))
				}
				if platform == "android" {
					if sent.Android == nil || sent.Android.TTL == nil || *sent.Android.TTL != 30*time.Second {
						t.Fatalf("Android config = %#v, want 30-second remaining Thought TTL", sent.Android)
					}
				} else if sent.APNS == nil || sent.APNS.Headers["apns-expiration"] != strconv.FormatInt(deadline.Unix(), 10) {
					t.Fatalf("APNs config = %#v, want authored Thought expiration", sent.APNS)
				}
				if !messageFitsProviderBudgets(sent) {
					t.Fatal("expiry metadata exceeded the provider payload budget")
				}
			})
		}
	}
}

func TestThoughtNotificationExpiredBeforeDispatchDoesNotReachProvider(t *testing.T) {
	now := time.Date(2026, 11, 8, 12, 0, 0, 0, time.UTC)
	for _, platform := range []string{"android", "ios"} {
		for _, opaque := range []bool{false, true} {
			for _, fixture := range thoughtNotificationPushCases() {
				t.Run(fmt.Sprintf("%s/opaque_%t/%s", platform, opaque, fixture.name), func(t *testing.T) {
					push, recorder := ordinaryPushService(platform)
					push.now = func() time.Time { return now }
					if opaque {
						if err := push.tokenBackend.RegisterToken("recipient", "recipient-token", platform, opaqueWakeCapability); err != nil {
							t.Fatal(err)
						}
					}
					envelope := thoughtDeliveryEnvelope(t, fixture.envelope, map[string]interface{}{
						"created_at": now.Add(-24 * time.Hour).Format(time.RFC3339Nano),
					})
					push.SendNotification(context.Background(), "recipient", "authenticated-sender", envelope)
					if got := recorder.SendCallCount(); got != 0 {
						t.Fatalf("expired Thought reached provider %d times", got)
					}
					if opaque {
						if err := push.mailboxDirty(context.Background(), plan367Route(t, push.tokenBackend, "recipient")); err != nil {
							t.Fatal(err)
						}
						if got := recorder.SendCallCount(); got != 1 {
							t.Fatalf("independent mixed-mailbox wake attempts = %d, want 1", got)
						}
					}
				})
			}
		}
	}
}

func TestThoughtNotificationRetryKeepsAbsoluteDeadline(t *testing.T) {
	for _, platform := range []string{"android", "ios"} {
		for _, advance := range []time.Duration{7 * time.Second, 30 * time.Second} {
			t.Run(fmt.Sprintf("%s/advance_%s", platform, advance), func(t *testing.T) {
				now := time.Date(2026, 11, 8, 12, 0, 0, 0, time.UTC)
				deadline := now.Add(30 * time.Second)
				push, recorder := ordinaryPushService(platform)
				push.now = func() time.Time { return now }
				push.retryDelays = []time.Duration{0}
				var observedTTLs []time.Duration
				recorder.onSend = func(_ context.Context, sent *messaging.Message) (string, error) {
					if sent.Android != nil && sent.Android.TTL != nil {
						observedTTLs = append(observedTTLs, *sent.Android.TTL)
					}
					if sent.APNS != nil && sent.APNS.Headers["apns-expiration"] != strconv.FormatInt(deadline.Unix(), 10) {
						t.Errorf("provider retry moved or omitted authored expiry: %#v", sent.APNS.Headers)
					}
					if recorder.SendCallCount() == 1 {
						now = now.Add(advance)
						return "", errors.New("temporary provider outage")
					}
					return "accepted", nil
				}
				envelope := thoughtDeliveryEnvelope(t, postCreatePushFixtureWithPostID, map[string]interface{}{
					"created_at": deadline.Add(-24 * time.Hour).Format(time.RFC3339Nano),
				})
				push.SendNotification(context.Background(), "recipient", "authenticated-sender", envelope)
				want := 2
				if advance == 30*time.Second {
					want = 1
				}
				if got := recorder.SendCallCount(); got != want {
					t.Fatalf("provider attempts = %d, want %d before absolute expiry", got, want)
				}
				if platform == "android" {
					if len(observedTTLs) != want || observedTTLs[0] != 30*time.Second ||
						(want == 2 && observedTTLs[1] != 23*time.Second) {
						t.Fatalf("provider TTLs = %v, want decreasing remaining lifetime", observedTTLs)
					}
				}
			})
		}
	}
}

func TestThoughtNotificationLegacyTimestampAndFutureClockCompatibility(t *testing.T) {
	now := time.Date(2026, 11, 8, 12, 0, 0, 0, time.UTC)
	for _, platform := range []string{"android", "ios"} {
		for _, createdAt := range []interface{}{nil, "invalid-timestamp", 123, now.Add(48 * time.Hour).Format(time.RFC3339Nano)} {
			t.Run(fmt.Sprintf("%s/created_%v", platform, createdAt), func(t *testing.T) {
				push, recorder := ordinaryPushService(platform)
				push.now = func() time.Time { return now }
				envelope := thoughtDeliveryEnvelope(t, postCreatePushFixtureWithPostID, map[string]interface{}{"created_at": createdAt})
				push.SendNotification(context.Background(), "recipient", "authenticated-sender", envelope)
				if got := recorder.SendCallCount(); got != 1 {
					t.Fatalf("compatible Thought provider attempts = %d, want 1", got)
				}
				sent := recorder.LastMessage()
				if createdAt == now.Add(48*time.Hour).Format(time.RFC3339Nano) {
					if sentRoutingString(sent, "expires_at") != now.Add(24*time.Hour).Format(time.RFC3339Nano) {
						t.Fatal("future sender clock must not extend recipient lifetime beyond 24 hours")
					}
				} else if sentRoutingHas(sent, "expires_at") ||
					(sent.Android != nil && sent.Android.TTL != nil) ||
					(sent.APNS != nil && sent.APNS.Headers["apns-expiration"] != "") {
					t.Fatal("missing or malformed legacy timestamp gained an invented deadline")
				}
			})
		}
	}
}

func TestThoughtNotificationAndroidFallbackRetainsRecipientPolicyAuthority(t *testing.T) {
	for _, fixture := range thoughtNotificationPushCases()[1:] {
		t.Run(fixture.name, func(t *testing.T) {
			push, recorder := ordinaryPushService("android")
			envelope := thoughtDeliveryEnvelope(t, fixture.envelope, map[string]interface{}{"created_at": nil})
			push.SendNotification(context.Background(), "recipient", "authenticated-sender", envelope)
			if got := recorder.SendCallCount(); got != 1 {
				t.Fatalf("routing fallback provider attempts = %d, want 1", got)
			}
			sent := recorder.LastMessage()
			if sent.Notification != nil || sent.Android == nil || sent.Android.Notification != nil {
				t.Errorf("Thought fallback can bypass archived-contact policy through provider auto-display: %#v", sent)
			}
			if sent.Data["type"] != "post_create" || sent.Data["sender_id"] != "authenticated-sender" {
				t.Errorf("routing fallback cannot resolve recipient's archived-contact policy: %#v", sent.Data)
			}
			if sent.Data["message_id"] == "" || sent.Data["ciphertext"] != "" {
				t.Errorf("generic fallback lost event identity or retained oversized ciphertext: %#v", sent.Data)
			}
		})
	}
}

func thoughtCustodyBackend(t *testing.T, kind string) (InboxBackend, func() InboxBackend) {
	t.Helper()
	if kind == "redis" {
		server := miniredis.RunT(t)
		reopen := func() InboxBackend {
			return newRedisInboxBackend(newTestRedisClient(t, server), "thought-custody:", 20)
		}
		return reopen(), reopen
	}
	var backend InboxBackend = newMemoryInboxBackend()
	if kind == "limited_memory" {
		backend = newMemoryInboxBackendWithLimits(20)
	}
	return backend, func() InboxBackend { return backend }
}

func TestThoughtCustodyAmbiguousStoreRetryUsesStableEventIdentity(t *testing.T) {
	for _, kind := range []string{"memory", "limited_memory", "redis"} {
		t.Run(kind, func(t *testing.T) {
			backend, reopen := thoughtCustodyBackend(t, kind)
			envelope := thoughtDeliveryEnvelope(t, postCreatePushFixtureWithPostID, map[string]interface{}{"event_id": "stable-thought-event"})
			entry := inboxMessage{From: "authenticated-sender", Message: envelope, Timestamp: time.Now().UnixMilli()}
			if result, err := backend.Store("recipient", entry); err != nil || result != InboxStoreResultStored {
				t.Fatalf("initial store = %q, %v", result, err)
			}
			original, _ := backend.RetrievePending("recipient", 10)
			if len(original) != 1 || original[0].Message != envelope {
				t.Fatal("initial custody did not retain exact encrypted envelope")
			}
			// The sender never received the first ACK. An independently reopened
			// Redis client must find the event in durable custody before re-alerting.
			backend = reopen()
			entry.Timestamp++
			if result, err := backend.Store("recipient", entry); err != nil || result != InboxStoreResultDuplicate {
				t.Errorf("ambiguous-store retry = %q, %v; want duplicate", result, err)
			}
			pending, _ := backend.RetrievePending("recipient", 10)
			if len(pending) != 1 || pending[0].ID != original[0].ID || pending[0].Message != envelope {
				t.Fatalf("ambiguous-store retry changed custody: %#v", pending)
			}
			if removed, err := backend.Ack("recipient", []string{original[0].ID}); err != nil || removed != 1 {
				t.Fatalf("ACK = %d, %v", removed, err)
			}
			if result, err := backend.Store("recipient", entry); err != nil || result != InboxStoreResultStored {
				t.Fatalf("completed ACK must retain historical re-store contract: %q, %v", result, err)
			}
		})
	}
}

func TestThoughtCustodyIdentityPreservesSenderRecipientAndEventKinds(t *testing.T) {
	for _, kind := range []string{"memory", "limited_memory", "redis"} {
		t.Run(kind, func(t *testing.T) {
			backend, _ := thoughtCustodyBackend(t, kind)
			envelope := thoughtDeliveryEnvelope(t, postCreatePushFixtureWithPostID, map[string]interface{}{"event_id": "shared-id"})
			for _, tc := range []struct {
				name, recipient, sender, message string
				want                             InboxStoreResult
			}{
				{"original", "recipient", "sender-a", envelope, InboxStoreResultStored},
				{"same recipient and event, different authenticated sender", "recipient", "sender-b", envelope, InboxStoreResultStored},
				{"different recipient", "recipient-b", "sender-a", envelope, InboxStoreResultStored},
				{"chat target", "recipient", "sender-a", directChatCustodyEnvelope("shared-id", ""), InboxStoreResultStored},
				{"chat edit event", "recipient", "sender-a", directChatCustodyEnvelope("target", "shared-id"), InboxStoreResultStored},
				{"deletion event", "recipient", "sender-a", ackCustodyDeletionEnvelope("shared-id", "sender-a", "c"), InboxStoreResultStored},
				{"reaction event", "recipient", "sender-a", strings.Replace(ordinaryDirectReactionEnvelope(1, 1), "evt-1", "shared-id", 1), InboxStoreResultStored},
				{"different Thought event for same post", "recipient", "sender-a", thoughtDeliveryEnvelope(t, envelope, map[string]interface{}{"event_id": "another-event"}), InboxStoreResultStored},
				{"retraction keeps separate event kind", "recipient", "sender-a", thoughtDeliveryEnvelope(t, envelope, map[string]interface{}{"type": "post_retract"}), InboxStoreResultStored},
				{"first sender retry", "recipient", "sender-a", envelope, InboxStoreResultDuplicate},
				{"second sender retry", "recipient", "sender-b", envelope, InboxStoreResultDuplicate},
			} {
				result, err := backend.Store(tc.recipient, inboxMessage{From: tc.sender, Message: tc.message, Timestamp: time.Now().UnixMilli()})
				if err != nil || result != tc.want {
					t.Errorf("%s: store = %q, %v; want %q", tc.name, result, err, tc.want)
				}
			}
		})
	}
}
