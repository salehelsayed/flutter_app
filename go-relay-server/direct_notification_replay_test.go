package main

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"testing"
	"time"

	"firebase.google.com/go/v4/messaging"
	"github.com/alicebob/miniredis/v2"
	"github.com/prometheus/client_golang/prometheus/testutil"
)

// A custody ACK permits the sender to store the same ciphertext again. That
// delivery contract must not turn a previously accepted iOS alert into a new
// user-visible message notification, including after rebuilding Redis clients.
func TestDirectNotificationReplayAfterAckDoesNotResendIOS(t *testing.T) {
	for _, testCase := range []struct {
		name      string
		redis     bool
		protected bool
		restart   bool
	}{
		{name: "memory_legacy"},
		{name: "redis_legacy", redis: true},
		{name: "redis_protected", redis: true, protected: true},
		{name: "redis_legacy_after_restart", redis: true, restart: true},
		{name: "redis_protected_after_restart", redis: true, protected: true, restart: true},
	} {
		t.Run(testCase.name, func(t *testing.T) {
			const recipient = "direct-replay-recipient"
			const sender = "direct-replay-sender"
			const messageID = "previously-notified-original-message"
			prefix := "direct-notification-replay:" + t.Name() + ":"
			var server *miniredis.Miniredis
			if testCase.redis {
				server = miniredis.RunT(t)
			}
			memoryInbox := newMemoryInboxBackend()
			memoryTokens := newMemoryPushTokenStore()
			recorder := newRecordingPushSender()
			newLayer := func() *InboxStore {
				var backend InboxBackend = memoryInbox
				var tokens PushTokenBackend = memoryTokens
				if testCase.redis {
					client := newTestRedisClient(t, server)
					backend = newRedisInboxBackend(client, prefix, 10)
					tokens = newRedisPushTokenBackend(client, prefix)
				}
				if err := tokens.RegisterToken(recipient, "direct-replay-ios-token", "ios"); err != nil {
					t.Fatalf("register iOS recipient: %v", err)
				}
				push := NewPushServiceWithBackend(tokens)
				if testCase.redis {
					push.directMessageDispatchAdmission = newRedisDirectMessageDispatchAdmissionBackend(
						tokens.(*redisPushTokenBackend).client, prefix, directMessageDispatchAdmissionTTL,
					)
				}
				push.sender = recorder.Send
				inbox := NewInboxStoreWithBackendAndCapacity(backend, push, 10)
				inbox.SetAckCustodyAdmissionEnabled(testCase.protected)
				return inbox
			}
			inbox := newLayer()
			envelope := ackCustodyTextEnvelope(messageID, sender, "same-original-ciphertext")
			store := func(timestamp int64) inboxMessage {
				t.Helper()
				entry := inboxMessage{From: sender, Message: envelope, Timestamp: timestamp}
				var result InboxStoreResult
				var err error
				if testCase.protected {
					result, _, err = inbox.StoreAckCustody(recipient, entry, ackCustodyDirectTextKind)
				} else {
					result, err = inbox.Store(recipient, entry)
				}
				if err != nil || result != InboxStoreResultStored {
					t.Fatalf("custody must accept first store and replay after ACK: result=%q err=%v", result, err)
				}
				var pending []inboxMessage
				if testCase.protected {
					pending, _, err = inbox.RetrieveAckCustodyPending(recipient, 10)
				} else {
					pending, _ = inbox.RetrievePendingWithMeta(recipient, 10)
				}
				if err != nil || len(pending) != 1 || pending[0].Message != envelope {
					t.Fatalf("reliable delivery must retain exact ciphertext: count=%d err=%v", len(pending), err)
				}
				return pending[0]
			}
			original := store(time.Now().Add(-24 * time.Hour).UnixMilli())
			select {
			case <-recorder.sentSignal:
			case <-time.After(2 * time.Second):
				t.Fatal("first direct message did not reach the provider")
			}
			firstPush := recorder.LastMessage()
			if firstPush.APNS == nil || sentRoutingString(firstPush, "message_id") != messageID {
				t.Fatal("first provider attempt did not carry the original iOS message identity")
			}
			var removed int
			var err error
			if testCase.protected {
				removed, err = inbox.AckAckCustody(recipient, []string{original.ID})
			} else {
				removed, err = inbox.Ack(recipient, []string{original.ID})
			}
			if err != nil || removed != 1 {
				t.Fatalf("ACK original custody: removed=%d err=%v", removed, err)
			}
			if testCase.restart {
				inbox = newLayer()
			}
			suppressedBefore := testutil.ToFloat64(pushSentCounter.WithLabelValues("direct_admission_suppressed"))
			replayed := store(time.Now().UnixMilli())
			if replayed.ID == original.ID {
				t.Fatal("replay did not exercise a new relay custody row")
			}
			deadline := time.NewTimer(2 * time.Second)
			defer deadline.Stop()
			tick := time.NewTicker(time.Millisecond)
			defer tick.Stop()
			for testutil.ToFloat64(pushSentCounter.WithLabelValues("direct_admission_suppressed")) <= suppressedBefore {
				select {
				case <-recorder.sentSignal:
					t.Fatalf("same acknowledged message generated a second iOS alert: provider attempts=%d", recorder.SendCallCount())
				case <-tick.C:
				case <-deadline.C:
					t.Fatal("replay neither completed notification suppression nor reached the provider")
				}
			}
			if got := recorder.SendCallCount(); got != 1 {
				t.Fatalf("provider attempts=%d, want one notification for the original logical message", got)
			}
		})
	}
}

type directReplayProviderFixture struct {
	push     *PushService
	recorder *recordingPushSender
	tokens   PushTokenBackend
	redis    *miniredis.Miniredis
	prefix   string
}

func newDirectReplayProviderFixture(t *testing.T, useRedis bool, platform string) *directReplayProviderFixture {
	t.Helper()
	f := &directReplayProviderFixture{
		recorder: newRecordingPushSender(),
		tokens:   newMemoryPushTokenStore(),
		prefix:   "direct-notification-replay:" + t.Name() + ":",
	}
	if useRedis {
		f.redis = miniredis.RunT(t)
		f.tokens = newRedisPushTokenBackend(newTestRedisClient(t, f.redis), f.prefix)
	}
	for _, recipient := range []string{"recipient-a", "recipient-b"} {
		if err := f.tokens.RegisterToken(recipient, "token-for-"+recipient, platform); err != nil {
			t.Fatalf("register route: %v", err)
		}
	}
	f.push = f.newPush()
	return f
}

func (f *directReplayProviderFixture) newPush() *PushService {
	push := NewPushServiceWithBackend(f.tokens)
	if f.redis != nil {
		push.directMessageDispatchAdmission = newRedisDirectMessageDispatchAdmissionBackend(
			f.tokens.(*redisPushTokenBackend).client, f.prefix, directMessageDispatchAdmissionTTL,
		)
	}
	push.sender = f.recorder.Send
	push.retryDelays = []time.Duration{0, 0}
	return push
}

func TestDirectNotificationReplayIdentityIsolationAndLegacyEditsIOS(t *testing.T) {
	for _, useRedis := range []bool{false, true} {
		t.Run(fmt.Sprintf("redis=%t", useRedis), func(t *testing.T) {
			f := newDirectReplayProviderFixture(t, useRedis, "ios")
			original := ackCustodyTextEnvelope("shared-id", "sender-a", "original-ciphertext")
			legacyEdit := ackCustodyTextEnvelope("shared-id", "sender-a", "edited-ciphertext")
			for index, testCase := range []struct {
				name      string
				recipient string
				sender    string
				envelope  string
				wantCalls int
			}{
				{"original", "recipient-a", "sender-a", original, 1},
				{"exact replay", "recipient-a", "sender-a", original, 1},
				{"equivalent ciphertext serialization", "recipient-a", "sender-a", `{"encrypted":{"nonce":"nonce","ciphertext":"original-ciphertext","kem":"kem"},"senderPeerId":"sender-a","id":"shared-id","version":"2","type":"chat_message"}`, 1},
				{"legacy edit changes original ciphertext", "recipient-a", "sender-a", legacyEdit, 2},
				{"exact legacy edit replay", "recipient-a", "sender-a", legacyEdit, 2},
				{"separate recipient", "recipient-b", "sender-a", original, 3},
				// The claimed envelope sender is unchanged. Admission must use the
				// actual authenticated sender supplied to the provider adapter.
				{"separate authenticated sender", "recipient-a", "sender-b", original, 4},
				{"new message", "recipient-a", "sender-a", ackCustodyTextEnvelope("new-message", "sender-a", "original-ciphertext"), 5},
				{"event id shares original raw id", "recipient-a", "sender-a", ackCustodyEditEnvelope("another-target", "shared-id", "sender-a", "event-ciphertext"), 6},
				{"same explicit event replay", "recipient-a", "sender-a", ackCustodyEditEnvelope("another-target", "shared-id", "sender-a", "event-ciphertext"), 6},
			} {
				f.push.sendStoredNotification(context.Background(), testCase.recipient, testCase.sender,
					testCase.envelope, fmt.Sprintf("new-custody-%d", index))
				if got := f.recorder.SendCallCount(); got != testCase.wantCalls {
					t.Fatalf("%s: provider attempts=%d, want %d", testCase.name, got, testCase.wantCalls)
				}
			}
		})
	}
}

func TestDirectNotificationReplayFailedProviderCanRetryIOS(t *testing.T) {
	for _, useRedis := range []bool{false, true} {
		t.Run(fmt.Sprintf("redis=%t", useRedis), func(t *testing.T) {
			f := newDirectReplayProviderFixture(t, useRedis, "ios")
			envelope := ackCustodyTextEnvelope("failed-then-recovered", "sender-a", "ciphertext")
			f.recorder.onSend = func(context.Context, *messaging.Message) (string, error) {
				return "", errors.New("temporary provider outage")
			}
			f.push.sendStoredNotification(context.Background(), "recipient-a", "sender-a", envelope, "failed-custody")
			if got := f.recorder.SendCallCount(); got != 3 {
				t.Fatalf("exhausted provider attempts=%d, want incumbent three attempts", got)
			}
			f.recorder.onSend = nil
			f.push.sendStoredNotification(context.Background(), "recipient-a", "sender-a", envelope, "recovery-custody")
			if got := f.recorder.SendCallCount(); got != 4 {
				t.Fatalf("healthy recovery attempts=%d, want one additional accepted attempt", got)
			}
			f.push.sendStoredNotification(context.Background(), "recipient-a", "sender-a", envelope, "replay-custody")
			if got := f.recorder.SendCallCount(); got != 4 {
				t.Fatalf("accepted recovery replayed: provider attempts=%d, want 4", got)
			}
		})
	}
}

func TestDirectNotificationReplayConcurrentIOSDispatchIsAdmittedOnce(t *testing.T) {
	for _, useRedis := range []bool{false, true} {
		t.Run(fmt.Sprintf("redis=%t", useRedis), func(t *testing.T) {
			f := newDirectReplayProviderFixture(t, useRedis, "ios")
			envelope := ackCustodyTextEnvelope("concurrent-original", "sender-a", "ciphertext")
			entered := make(chan struct{})
			release := make(chan struct{})
			var enterOnce sync.Once
			var releaseOnce sync.Once
			defer releaseOnce.Do(func() { close(release) })
			f.recorder.onSend = func(context.Context, *messaging.Message) (string, error) {
				enterOnce.Do(func() { close(entered) })
				<-release
				return "accepted", nil
			}
			completed := make(chan struct{}, 5)
			send := func(push *PushService, index int) {
				push.sendStoredNotification(context.Background(), "recipient-a", "sender-a", envelope,
					fmt.Sprintf("concurrent-custody-%d", index))
				completed <- struct{}{}
			}
			go send(f.push, 0)
			select {
			case <-entered:
			case <-time.After(2 * time.Second):
				t.Fatal("first provider attempt did not start")
			}
			for index := 1; index <= 4; index++ {
				push := f.push
				if useRedis {
					// Independent services contend on the same durable claim.
					push = f.newPush()
				}
				go send(push, index)
			}
			for index := 0; index < 4; index++ {
				select {
				case <-completed:
				case <-time.After(2 * time.Second):
					t.Fatalf("replay entered or waited on the held provider call: attempts=%d", f.recorder.SendCallCount())
				}
			}
			if got := f.recorder.SendCallCount(); got != 1 {
				t.Fatalf("concurrent provider attempts=%d, want 1", got)
			}
			releaseOnce.Do(func() { close(release) })
			select {
			case <-completed:
			case <-time.After(2 * time.Second):
				t.Fatal("accepted initial send did not finish")
			}
		})
	}
}

func TestDirectNotificationReplayLeavesAndroidDispatchUnchanged(t *testing.T) {
	for _, useRedis := range []bool{false, true} {
		t.Run(fmt.Sprintf("redis=%t", useRedis), func(t *testing.T) {
			f := newDirectReplayProviderFixture(t, useRedis, "android")
			envelope := ackCustodyTextEnvelope("android-original", "sender-a", "ciphertext")
			for index := 0; index < 2; index++ {
				f.push.sendStoredNotification(context.Background(), "recipient-a", "sender-a", envelope,
					fmt.Sprintf("android-custody-%d", index))
			}
			if got := f.recorder.SendCallCount(); got != 2 {
				t.Fatalf("Android incumbent attempts=%d, want 2", got)
			}
			for _, sent := range f.recorder.Messages() {
				if sent.Android == nil || sent.APNS != nil {
					t.Fatal("Android platform projection changed")
				}
			}
		})
	}
}

func TestDirectNotificationReplayRedisAdmissionExpires(t *testing.T) {
	f := newDirectReplayProviderFixture(t, true, "ios")
	envelope := ackCustodyTextEnvelope("bounded-original", "sender-a", "ciphertext")
	f.push.sendStoredNotification(context.Background(), "recipient-a", "sender-a", envelope, "initial-custody")
	f.redis.FastForward(6 * 24 * time.Hour)
	f.push.sendStoredNotification(context.Background(), "recipient-a", "sender-a", envelope, "retained-custody")
	if got := f.recorder.SendCallCount(); got != 1 {
		t.Fatalf("accepted notification replayed inside seven-day horizon: attempts=%d", got)
	}
	f.redis.FastForward(2 * 24 * time.Hour)
	// Token lifetime is independent of notification admission expiry.
	if err := f.tokens.RegisterToken("recipient-a", "refreshed-token", "ios"); err != nil {
		t.Fatal(err)
	}
	f.push.sendStoredNotification(context.Background(), "recipient-a", "sender-a", envelope, "expired-custody")
	if got := f.recorder.SendCallCount(); got != 2 {
		t.Fatalf("expired admission retained indefinitely: attempts=%d", got)
	}
}

type directReplayUnavailableAdmissionBackend struct{}

func (directReplayUnavailableAdmissionBackend) TryAcquire(
	context.Context,
	groupMessageDispatchAdmissionIdentity,
) (groupMessageDispatchAdmissionLease, bool, error) {
	return groupMessageDispatchAdmissionLease{}, false, errors.New("notification admission unavailable")
}

func (directReplayUnavailableAdmissionBackend) Release(context.Context, groupMessageDispatchAdmissionLease) error {
	return errors.New("notification admission unavailable")
}

func TestDirectNotificationReplayAdmissionFailurePreservesIOSDelivery(t *testing.T) {
	f := newDirectReplayProviderFixture(t, false, "ios")
	f.push.directMessageDispatchAdmission = directReplayUnavailableAdmissionBackend{}
	envelope := ackCustodyTextEnvelope("admission-outage-original", "sender-a", "ciphertext")
	f.push.sendStoredNotification(context.Background(), "recipient-a", "sender-a", envelope, "admitted-custody")
	if got := f.recorder.SendCallCount(); got != 1 {
		t.Fatalf("notification admission failure lost the accepted message wake: provider attempts=%d, want 1", got)
	}
}
