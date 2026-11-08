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
	"github.com/prometheus/client_golang/prometheus/testutil"
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
		if fixture.name == "fallback_without_post_id" {
			// Covered separately below: supported clients cannot render this
			// legacy shape locally, so it must retain provider-owned display.
			continue
		}
		t.Run(fixture.name, func(t *testing.T) {
			push, recorder := ordinaryPushService("android")
			envelope := thoughtDeliveryEnvelope(t, fixture.envelope, map[string]interface{}{"created_at": nil})
			push.SendNotification(context.Background(), "recipient", "authenticated-sender", envelope)
			if got := recorder.SendCallCount(); got != 1 {
				t.Fatalf("routing fallback provider attempts = %d, want 1", got)
			}
			sent := recorder.LastMessage()
			if strings.TrimSpace(sent.Data["post_id"]) == "" {
				t.Fatal("data-only Thought fallback has no post_id for the app's route parser")
			}
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

func TestThoughtNotificationAndroidLegacyFallbackHasDisplayOwner(t *testing.T) {
	for _, postID := range []interface{}{nil, "", " \t "} {
		t.Run(fmt.Sprintf("post_id_%v", postID), func(t *testing.T) {
			push, recorder := ordinaryPushService("android")
			push.now = postCreatePushFixtureNow
			envelope := thoughtDeliveryEnvelope(t, postCreatePushFixture, map[string]interface{}{"post_id": postID})
			push.SendNotification(context.Background(), "recipient", "authenticated-sender", envelope)
			if recorder.SendCallCount() != 1 {
				t.Fatal("legacy Thought must retain its provider dispatch")
			}
			sent := recorder.LastMessage()
			// NotificationRouteTarget.fromRemoteMessageData rejects post_create
			// without a nonblank post_id, and the background fallback then declines
			// display. A legacy envelope therefore needs the provider display owner.
			appCanRender := sent.Data["type"] == "post_create" && strings.TrimSpace(sent.Data["post_id"]) != ""
			providerCanRender := sent.Notification != nil || (sent.Android != nil && sent.Android.Notification != nil)
			if appCanRender || !providerCanRender {
				t.Fatalf("legacy Thought display ownership: app=%t provider=%t, want provider-owned delivery", appCanRender, providerCanRender)
			}
			if sent.Android == nil || sent.Android.Notification == nil ||
				sent.Android.Notification.ChannelID != postCreatePushChannelID ||
				sent.Android.Notification.Title != postCreatePushTitle ||
				sent.Android.Notification.Body != postCreatePushBody {
				t.Fatal("legacy fallback changed the existing Thought channel or visible copy")
			}
		})
	}
}

func TestThoughtNotificationExpiryMetadataPreservesProviderBudget(t *testing.T) {
	// Find a full block close enough to the existing budget that the additive
	// deadline must trigger the same full/compact/generic selection as ciphertext.
	var envelope string
	for size := 16; size <= maxProviderPayloadBytes; size += 16 {
		candidate := thoughtPhotoPushEnvelope(size, thoughtPhotoCompactEncryptedJSON(thoughtPhotoCompactCiphertext))
		full := thoughtPhotoFullCandidate(t, candidate)
		if !messageFitsProviderBudgets(full) || pushDataSize(full.Data) > maxPushDataBytes {
			break
		}
		envelope = candidate
	}
	if envelope == "" {
		t.Fatal("fixture did not find a fitting full ciphertext")
	}
	now := time.Date(2026, 11, 8, 12, 0, 0, 123456789, time.UTC)
	envelope = thoughtDeliveryEnvelope(t, envelope, map[string]interface{}{
		"created_at": now.Add(-23 * time.Hour).Format(time.RFC3339Nano),
	})
	for _, platform := range []string{"android", "ios"} {
		t.Run(platform, func(t *testing.T) {
			push, recorder := ordinaryPushService(platform)
			push.now = func() time.Time { return now }
			push.SendNotification(context.Background(), "recipient", "peer-sender", envelope)
			if recorder.SendCallCount() != 1 {
				t.Fatal("budget fallback must retain one provider attempt")
			}
			sent := recorder.LastMessage()
			wantCiphertext := ""
			if platform == "ios" {
				wantCiphertext = thoughtPhotoCompactCiphertext
			}
			if got := sentRoutingString(sent, "ciphertext"); got != wantCiphertext {
				t.Fatalf("expiry was omitted from ciphertext budget selection: ciphertext bytes=%d, want %d", len(got), len(wantCiphertext))
			}
			if !messageFitsProviderBudgets(sent) || sentRoutingString(sent, "expires_at") == "" {
				t.Fatal("selected fallback must retain expiry inside the provider budget")
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
			push, recorder := ordinaryPushService("ios")
			newLayer := func(backend InboxBackend) *InboxStore {
				if redisBackend, ok := backend.(*redisInboxBackend); ok {
					tokens := newRedisPushTokenBackend(redisBackend.client, redisBackend.prefix)
					if err := tokens.RegisterToken("recipient", "recipient-token", "ios"); err != nil {
						t.Fatal(err)
					}
					push = NewPushServiceWithBackend(tokens)
					push.directMessageDispatchAdmission = newRedisDirectMessageDispatchAdmissionBackend(
						redisBackend.client, redisBackend.prefix, directMessageDispatchAdmissionTTL,
					)
				}
				push.now = postCreatePushFixtureNow
				push.sender = recorder.Send
				return NewInboxStoreWithBackendAndCapacity(backend, push, 20)
			}
			inbox := newLayer(backend)
			envelope := thoughtDeliveryEnvelope(t, postCreatePushFixtureWithPostID, map[string]interface{}{"event_id": "stable-thought-event"})
			entry := inboxMessage{From: "authenticated-sender", Message: envelope, Timestamp: time.Now().UnixMilli()}
			if result, err := inbox.Store("recipient", entry); err != nil || result != InboxStoreResultStored {
				t.Fatalf("initial store = %q, %v", result, err)
			}
			select {
			case <-recorder.sentSignal:
			case <-time.After(2 * time.Second):
				t.Fatal("initial Thought did not reach the provider")
			}
			original, _ := inbox.RetrievePendingWithMeta("recipient", 10)
			if len(original) != 1 || original[0].Message != envelope {
				t.Fatal("initial custody did not retain exact encrypted envelope")
			}
			// The sender never received the first ACK. An independently reopened
			// Redis client must find both custody and provider-admission history.
			inbox = newLayer(reopen())
			entry.Timestamp++
			if result, err := inbox.Store("recipient", entry); err != nil || result != InboxStoreResultDuplicate {
				t.Errorf("ambiguous-store retry = %q, %v; want duplicate", result, err)
			}
			pending, _ := inbox.RetrievePendingWithMeta("recipient", 10)
			if len(pending) != 1 || pending[0].ID != original[0].ID || pending[0].Message != envelope {
				t.Fatalf("ambiguous-store retry changed custody: %#v", pending)
			}
			if removed, err := inbox.Ack("recipient", []string{original[0].ID}); err != nil || removed != 1 {
				t.Fatalf("ACK = %d, %v", removed, err)
			}
			suppressedBefore := testutil.ToFloat64(pushSentCounter.WithLabelValues("direct_admission_suppressed"))
			if result, err := inbox.Store("recipient", entry); err != nil || result != InboxStoreResultStored {
				t.Fatalf("completed ACK must retain historical re-store contract: %q, %v", result, err)
			}
			restored, _ := inbox.RetrievePendingWithMeta("recipient", 10)
			if len(restored) != 1 || restored[0].ID == original[0].ID || restored[0].Message != envelope {
				t.Fatalf("post-ACK retry did not retain fresh custody for the original ciphertext: %#v", restored)
			}
			// Wait for the existing admission outcome, not a quiet timeout: the
			// asynchronous post-ACK dispatch must actually finish suppression.
			deadline := time.NewTimer(2 * time.Second)
			defer deadline.Stop()
			tick := time.NewTicker(time.Millisecond)
			defer tick.Stop()
			for testutil.ToFloat64(pushSentCounter.WithLabelValues("direct_admission_suppressed")) <= suppressedBefore {
				select {
				case <-recorder.sentSignal:
					t.Fatalf("acknowledged Thought alerted again: provider attempts=%d", recorder.SendCallCount())
				case <-tick.C:
				case <-deadline.C:
					t.Fatal("post-ACK retry did not finish provider admission")
				}
			}
			if got := recorder.SendCallCount(); got != 1 {
				t.Fatalf("provider attempts=%d, want one alert across ambiguous and post-ACK retries", got)
			}
		})
	}
}

func TestThoughtNotificationReplayAdmissionPreservesIdentityBoundaries(t *testing.T) {
	for _, useRedis := range []bool{false, true} {
		t.Run(fmt.Sprintf("redis_%t", useRedis), func(t *testing.T) {
			fixture := newDirectReplayProviderFixture(t, useRedis, "ios")
			fixture.push.now = postCreatePushFixtureNow
			envelope := thoughtDeliveryEnvelope(t, postCreatePushFixtureWithPostID, map[string]interface{}{"event_id": "shared-event"})
			for index, tc := range []struct {
				name, recipient, sender, message string
				want                             int
			}{
				{"original", "recipient-a", "sender-a", envelope, 1},
				{"same event retry", "recipient-a", "sender-a", envelope, 1},
				{"same event freshly encrypted", "recipient-a", "sender-a", thoughtDeliveryEnvelope(t, envelope, map[string]interface{}{
					"encrypted": map[string]string{"kem": "new-kem", "ciphertext": "new-ciphertext", "nonce": "new-nonce"},
				}), 1},
				{"different authenticated sender", "recipient-a", "sender-b", envelope, 2},
				{"different recipient", "recipient-b", "sender-a", envelope, 3},
				{"different Thought event", "recipient-a", "sender-a", thoughtDeliveryEnvelope(t, envelope, map[string]interface{}{"event_id": "next-event"}), 4},
				{"chat target shares raw event id", "recipient-a", "sender-a", directChatCustodyEnvelope("shared-event", ""), 5},
				{"chat edit shares raw event id", "recipient-a", "sender-a", directChatCustodyEnvelope("target", "shared-event"), 6},
			} {
				fixture.push.sendStoredNotification(context.Background(), tc.recipient, tc.sender, tc.message, fmt.Sprintf("new-custody-%d", index))
				if got := fixture.recorder.SendCallCount(); got != tc.want {
					t.Fatalf("%s: provider attempts=%d, want %d", tc.name, got, tc.want)
				}
			}
			if directNotificationCustodyOnly("recipient-a", inboxMessage{From: "sender-a", Message: envelope, SuppressNotification: true}) {
				t.Fatal("Thought provider admission expanded chat-only custody recovery policy")
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
