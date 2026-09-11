package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"testing"
	"time"

	"firebase.google.com/go/v4/messaging"
	"github.com/prometheus/client_golang/prometheus/testutil"
)

func custodyOnlyStoreForTest(t *testing.T, inbox *InboxStore, recipient string, entry inboxMessage, protected bool) inboxMessage {
	t.Helper()
	var result InboxStoreResult
	var stored inboxMessage
	var err error
	if protected {
		result, stored, err = inbox.StoreAckCustody(recipient, entry, ackCustodyDirectTextKind)
	} else {
		result, err = inbox.Store(recipient, entry)
		pending, _ := inbox.RetrievePendingWithMeta(recipient, 10)
		for _, candidate := range pending {
			if candidate.Message == entry.Message {
				stored = candidate
			}
		}
	}
	if err != nil || result != InboxStoreResultStored || stored.ID == "" || stored.Message != entry.Message {
		t.Fatalf("store preserved custody: result=%q stored=%#v err=%v", result, stored, err)
	}
	return stored
}

func custodyOnlyAckForTest(t *testing.T, inbox *InboxStore, recipient, custodyID string, protected bool) {
	t.Helper()
	var removed int
	var err error
	if protected {
		removed, err = inbox.AckAckCustody(recipient, []string{custodyID})
	} else {
		removed, err = inbox.Ack(recipient, []string{custodyID})
	}
	if err != nil || removed != 1 {
		t.Fatalf("ACK custody: removed=%d err=%v", removed, err)
	}
}

func TestDirectNotificationCustodyOnlyHistoricalReplayAcrossRedisRestart(t *testing.T) {
	for _, protected := range []bool{false, true} {
		t.Run(fmt.Sprintf("protected=%t", protected), func(t *testing.T) {
			const recipient, sender = "recipient-a", "sender-a"
			f := newDirectReplayProviderFixture(t, true, "ios")
			newInbox := func(push *PushService) *InboxStore {
				backend := newRedisInboxBackend(newTestRedisClient(t, f.redis), f.prefix, 10)
				inbox := NewInboxStoreWithBackendAndCapacity(backend, push, 10)
				inbox.SetAckCustodyAdmissionEnabled(protected)
				return inbox
			}
			inbox := newInbox(nil)
			oldEnvelope := ackCustodyTextEnvelope("historical-original", sender, "historical-ciphertext")
			oldEntry := inboxMessage{From: sender, Message: oldEnvelope, Timestamp: time.Now().Add(-30 * time.Hour).UnixMilli()}
			oldCustody := custodyOnlyStoreForTest(t, inbox, recipient, oldEntry, protected)
			// Exact pre-guard gateway adapter: accepted alert, no admission history.
			route, err := f.push.selectPushRoute(recipient, "")
			if err != nil || route == nil {
				t.Fatalf("historical route: %v", err)
			}
			f.push.sendSelectedPushThroughGateway(context.Background(), recipient, *route, "",
				func() *messaging.Message { return buildPushMessage("", sender, oldEnvelope) })
			custodyOnlyAckForTest(t, inbox, recipient, oldCustody.ID, protected)
			f.push = f.newPush()
			inbox = newInbox(f.push)
			newEntry := inboxMessage{From: sender, Message: ackCustodyTextEnvelope("new-original", sender, "new-ciphertext"), Timestamp: time.Now().UnixMilli()}
			newCustody := custodyOnlyStoreForTest(t, inbox, recipient, newEntry, protected)
			waitForWakeProviderCalls(t, f.recorder, 2)
			custodyOnlyAckForTest(t, inbox, recipient, newCustody.ID, protected)
			oldEntry.Timestamp = time.Now().UnixMilli()
			oldEntry.SuppressNotification = true
			replayed := custodyOnlyStoreForTest(t, inbox, recipient, oldEntry, protected)
			if replayed.ID == oldCustody.ID {
				t.Fatal("historical recovery did not acquire new custody")
			}
			// This exact claim must survive a second relay restart, so even an
			// already-scheduled unhinted provider adapter cannot repeat the old alert.
			f.push = f.newPush()
			f.push.sendStoredNotification(context.Background(), recipient, sender, oldEnvelope, "delayed-old-custody")
			if got := f.recorder.SendCallCount(); got != 2 {
				t.Fatalf("provider calls=%d, want only historical original and genuinely new message", got)
			}
			// Neither authored age, sender/recipient reuse, nor an edit is a reason
			// to lose an unhinted notification.
			f.push.sendStoredNotification(context.Background(), recipient, sender,
				ackCustodyTextEnvelope("old-undelivered", sender, "previously-undelivered"), "old-undelivered-custody")
			f.push.sendStoredNotification(context.Background(), "recipient-b", sender, oldEnvelope, "other-recipient")
			f.push.sendStoredNotification(context.Background(), recipient, "sender-b", oldEnvelope, "other-sender")
			f.push.sendStoredNotification(context.Background(), recipient, sender,
				ackCustodyEditEnvelope("historical-original", "fresh-edit-event", sender, "edited-ciphertext"), "edit-custody")
			f.push.sendStoredNotification(context.Background(), recipient, sender,
				ackCustodyTextEnvelope("historical-original", sender, "legacy-edited-ciphertext"), "legacy-edit-custody")
			if got := f.recorder.SendCallCount(); got != 7 {
				t.Fatalf("preserved notifications=%d, want 7", got)
			}
		})
	}
}

func TestDirectNotificationCustodyOnlySkipsWakeAdmissionAndCapacityFallback(t *testing.T) {
	for _, platform := range []string{"ios", "android"} {
		for _, protected := range []bool{false, true} {
			t.Run(fmt.Sprintf("%s/protected=%t", platform, protected), func(t *testing.T) {
				f := newWakeOutcomeTestFixture(t, "custody-only-wake:"+t.Name()+":")
				const recipient, sender = "wake-recipient", "wake-sender"
				plan367RegisterEncrypted(t, f.pushBackend, recipient, "wake-token", platform, opaqueWakeCapability, wakeOutcomeCapability)
				f.inbox.SetAckCustodyAdmissionEnabled(protected)
				recorder := newRecordingPushSender()
				f.push.sender = recorder.Send
				f.push.directMessageDispatchAdmission = newRedisDirectMessageDispatchAdmissionBackend(f.pushBackend.client, f.state.prefix, directMessageDispatchAdmissionTTL)
				envelope := fmt.Sprintf(`{"type":"chat_message","version":"2","id":"original","messageId":"original","senderPeerId":%q,"encrypted":{"kem":"kem","ciphertext":"ciphertext","nonce":"nonce"}}`, sender)
				if protected {
					// The protected schema deliberately rejects the legacy messageId
					// alias. Its selected-route fallback must still remain quiet.
					envelope = ackCustodyTextEnvelope("original", sender, "ciphertext")
				}
				entry := inboxMessage{From: sender, Message: envelope, Timestamp: f.now.UnixMilli(), SuppressNotification: true}
				custodyOnlyStoreForTest(t, f.inbox, recipient, entry, protected)
				if exists := f.redis.Exists(f.state.stateKey(recipient)); exists {
					t.Fatal("custody-only recovery created a durable wake obligation")
				}
				// Exercise the legacy preflight/capacity adapters directly with the
				// same transient policy, including a route selected before storage.
				route, err := f.push.selectPushRoute(recipient, "")
				if err != nil || route == nil {
					t.Fatalf("wake route: %v", err)
				}
				f.inbox.launchStoredDirectPushAfterPreflight(recipient, entry, wakeOutcomePreflightFallback{kind: wakeOutcomePreflightSelectedRoute, producer: wakeOutcomeProducerDirectMessage, route: *route})
				f.inbox.launchDirectPushForWakeAdmission(recipient, entry, wakeOutcomeAdmission{route: *route, policy: wakeOutcomePolicyNone})
				coordinator := newWakeOutcomeCoordinator(f.state, f.push.sendWakeOutcomeThroughGateway, func() time.Time { return f.now.Add(wakeOutcomeDebounce) })
				coordinator.sendDirect = f.push.sendDirectWakeOutcomeThroughGateway
				if err := coordinator.RunDue(context.Background()); err != nil {
					t.Fatal(err)
				}
				if got := recorder.SendCallCount(); got != 0 {
					t.Fatalf("custody-only provider calls=%d, want 0", got)
				}
			})
		}
	}
}

func TestDirectNotificationCustodyOnlyWirePolicyAndSenderAuthority(t *testing.T) {
	for _, protected := range []bool{false, true} {
		t.Run(fmt.Sprintf("protected=%t", protected), func(t *testing.T) {
			f := newDirectReplayProviderFixture(t, true, "ios")
			backend := newRedisInboxBackend(newTestRedisClient(t, f.redis), f.prefix, 10)
			inbox := NewInboxStoreWithBackendAndCapacity(backend, f.push, 10)
			inbox.SetAckCustodyAdmissionEnabled(protected)
			env := setupInboxStreamEnv(t, inbox, NewGroupInboxStore(10, groupMessageTTL))
			recipient, sender := env.recipient.ID().String(), env.sender.ID().String()
			if err := f.tokens.RegisterToken(recipient, "wire-ios-token", "ios"); err != nil {
				t.Fatal(err)
			}
			envelope := ackCustodyTextEnvelope("wire-old-original", sender, "wire-ciphertext")
			request := inboxRequest{Action: "store", To: recipient, From: "forged-sender", Message: envelope, SuppressNotification: true}
			if protected {
				request.Action = ackCustodyStoreAction
				request.CustodyKind, request.CustodyContract = ackCustodyDirectTextKind, ackCustodyContract
			}
			stream, err := env.sender.NewStream(context.Background(), env.server.ID(), InboxProtocol)
			if err != nil {
				t.Fatal(err)
			}
			defer stream.Close()
			sendInboxReq(t, stream, request)
			response := recvInboxResp(t, stream)
			if response.Status != "OK" || response.StoreStatus != string(InboxStoreResultStored) || response.ExpiresAtMs <= 0 {
				t.Fatalf("wire custody response=%#v", response)
			}
			key := backend.key(recipient)
			if protected {
				key = backend.ackCustodyKey(recipient)
			}
			raw, err := backend.client.LRange(context.Background(), key, 0, -1).Result()
			if err != nil || len(raw) != 1 {
				t.Fatalf("persisted custody: count=%d err=%v", len(raw), err)
			}
			var stored inboxMessage
			if err := json.Unmarshal([]byte(raw[0]), &stored); err != nil {
				t.Fatal(err)
			}
			if stored.From != sender || stored.Message != envelope || stored.SuppressNotification || strings.Contains(raw[0], "suppressNotification") {
				t.Fatalf("immutable custody or sender authority changed: %s", raw[0])
			}
			f.push.sendStoredNotification(context.Background(), recipient, sender, envelope, "delayed-wire-custody")
			if got := f.recorder.SendCallCount(); got != 0 {
				t.Fatalf("wire-hinted old message reached provider %d times", got)
			}
			// A supplied `from` must not seed somebody else's identity.
			f.push.sendStoredNotification(context.Background(), recipient, "forged-sender", envelope, "other-owner")
			if got := f.recorder.SendCallCount(); got != 1 {
				t.Fatalf("forged request sender affected admission identity: calls=%d", got)
			}
		})
	}
}

func TestDirectNotificationCustodyOnlyFailuresAndEligibility(t *testing.T) {
	f := newDirectReplayProviderFixture(t, true, "ios")
	backend := newRedisInboxBackend(newTestRedisClient(t, f.redis), f.prefix, 10)
	inbox := NewInboxStoreWithBackendAndCapacity(backend, f.push, 10)
	inbox.SetAckCustodyAdmissionEnabled(true)
	entry := inboxMessage{From: "sender-a", Message: ackCustodyTextEnvelope("hinted-original", "sender-a", "ciphertext"), Timestamp: time.Now().UnixMilli(), SuppressNotification: true}
	f.push.directMessageDispatchAdmission = directReplayUnavailableAdmissionBackend{}
	before := testutil.ToFloat64(pushSentCounter.WithLabelValues("direct_custody_only_history_unavailable"))
	custodyOnlyStoreForTest(t, inbox, "recipient-a", entry, true)
	if got := testutil.ToFloat64(pushSentCounter.WithLabelValues("direct_custody_only_history_unavailable")); got != before+1 {
		t.Fatal("history backend failure was not distinguished from successful seeding")
	}
	if got := f.recorder.SendCallCount(); got != 0 {
		t.Fatalf("history failure ignored explicit no-notification policy: calls=%d", got)
	}
	f.push = f.newPush()
	inbox.push = f.push
	backend.ackCustodyBeforeCommit = func() error { return errors.New("custody unavailable") }
	failed := entry
	failed.Message = ackCustodyTextEnvelope("failed-custody", "sender-a", "ciphertext")
	if _, _, err := inbox.StoreAckCustody("recipient-a", failed, ackCustodyDirectTextKind); err == nil {
		t.Fatal("custody store failure was swallowed")
	}
	backend.ackCustodyBeforeCommit = nil
	f.push.sendStoredNotification(context.Background(), "recipient-a", failed.From, failed.Message, "healthy-retry")
	if got := f.recorder.SendCallCount(); got != 1 {
		t.Fatalf("failed custody seeded notification suppression: calls=%d", got)
	}
	for _, envelope := range []string{
		ackCustodyEditEnvelope("target", "genuine-edit", "sender-a", "edit-ciphertext"),
		`{"type":"chat_message","id":"invalid-original"}`,
		`{"type":"group_message","messageId":"group-original"}`,
	} {
		candidate := entry
		candidate.Message = envelope
		if directNotificationCustodyOnly("recipient-a", candidate) {
			t.Fatalf("hint escaped narrow initial-direct eligibility: %s", envelope)
		}
	}
	edit := entry
	edit.Message = ackCustodyEditEnvelope("target", "genuine-edit", "sender-a", "edit-ciphertext")
	custodyOnlyStoreForTest(t, inbox, "recipient-a", edit, false)
	waitForWakeProviderCalls(t, f.recorder, 2)
}
