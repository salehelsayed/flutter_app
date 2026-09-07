package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"firebase.google.com/go/v4/messaging"
	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"
)

const richTestPeer = "text-retry-recipient"
const richTestSender = "text-retry-sender"

func newAndroidRichTestFixture(t *testing.T, encrypted bool) *wakeOutcomeTestFixture {
	t.Helper()
	prefix := "android-rich:" + t.Name() + ":"
	var server *miniredis.Miniredis
	var tokens *redisPushTokenBackend
	if encrypted {
		server, tokens, _ = plan367NewEncryptedFixture(t, prefix)
	} else {
		server = miniredis.RunT(t)
		tokens = newRedisPushTokenBackend(newTestRedisClient(t, server), prefix)
	}
	if encrypted {
		plan367RegisterEncrypted(t, tokens, richTestPeer, "private-provider-token", "android")
	} else if err := tokens.RegisterToken(richTestPeer, "private-provider-token", "android"); err != nil {
		t.Fatal(err)
	}
	now := time.Now()
	server.SetTime(now)
	state := newRedisWakeOutcomeStore(tokens.client, prefix)
	state.now = func() time.Time { return now }
	inboxBackend := newRedisInboxBackend(tokens.client, prefix, 64)
	inboxBackend.now = func() time.Time { return now }
	inboxBackend.wakeOutcomes = state
	groupBackend := newRedisGroupInboxBackend(tokens.client, prefix, 64, groupMessageTTL)
	groupBackend.wakeOutcomes = state
	push := NewPushServiceWithBackend(tokens)
	push.retryDelays = []time.Duration{0, 0}
	inbox := NewInboxStoreWithBackendAndCapacity(inboxBackend, push, 64)
	inbox.SetWakeOutcomeAdmissionEnabled(true)
	inbox.SetAckCustodyAdmissionEnabled(true)
	inbox.SetGroupContentPushEnabled(true)
	group := NewGroupInboxStoreWithBackend(groupBackend)
	group.SetPush(push)
	group.SetWakeOutcomeAdmissionEnabled(true)
	return &wakeOutcomeTestFixture{redis: server, pushBackend: tokens, push: push, state: state, inboxBackend: inboxBackend, groupBackend: groupBackend, inbox: inbox, group: group, now: now}
}

func awaitAndroidRich(t *testing.T, description string, predicate func() bool) {
	t.Helper()
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		if predicate() {
			return
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatalf("timed out waiting for %s", description)
}

func richTestAdmission(t *testing.T, f *wakeOutcomeTestFixture, event string) wakeOutcomeAdmission {
	t.Helper()
	route, err := f.push.selectPushRoute(richTestPeer, "")
	if err != nil || route == nil {
		t.Fatalf("route unavailable: %v", err)
	}
	draft := &messaging.Message{Data: map[string]string{"type": "new_message", "sender_id": richTestSender, "message_id": event, "envelope_version": "2", "kem": "k", "ciphertext": "c", "nonce": "n"}}
	admission, ok := f.push.newAndroidRichAdmission(richTestPeer, *route, draft, f.now.UnixMilli(), f.now.Add(24*time.Hour).UnixMilli())
	if !ok {
		t.Fatal("Android rich admission rejected")
	}
	return admission
}

func storeRichTestAdmission(t *testing.T, f *wakeOutcomeTestFixture, a wakeOutcomeAdmission) wakeOutcomeAdmissionStatus {
	t.Helper()
	_, status, err := f.inboxBackend.StoreWithWakeOutcome(richTestPeer, inboxMessage{ID: a.correlation, From: richTestSender, Message: wakeOutcomeDirectEnvelope(a.correlation), Timestamp: f.now.UnixMilli()}, a)
	if err != nil {
		t.Fatal(err)
	}
	return status
}

func richTestCoordinator(f *wakeOutcomeTestFixture, now time.Time) *wakeOutcomeCoordinator {
	// Recreate state and provider service from storage; the original request and
	// any in-memory payload are unavailable to this restarted coordinator.
	state := newRedisWakeOutcomeStore(f.pushBackend.client, f.state.prefix)
	state.now = func() time.Time { return now }
	push := NewPushServiceWithBackend(f.pushBackend)
	push.retryDelays = []time.Duration{0, 0}
	push.sender = f.push.sender
	coordinator := newWakeOutcomeCoordinator(state, nil, state.nowTime)
	coordinator.sendAndroidRich = func(ctx context.Context, claim wakeOutcomeClaim) pushDeliveryResult {
		return push.sendAndroidRichRecovery(ctx, state, claim)
	}
	return coordinator
}

func requireRichTerminal(t *testing.T, f *wakeOutcomeTestFixture, correlation string) {
	t.Helper()
	ctx := context.Background()
	if value, err := f.state.client.Get(ctx, f.state.androidRichCompletedKey(richTestPeer, correlation)).Result(); err != nil || value != "1" {
		t.Fatalf("completion marker missing: value=%q err=%v", value, err)
	}
	if f.state.client.Exists(ctx, f.state.androidRichMaterialKey(richTestPeer, correlation)).Val() != 0 {
		t.Fatal("terminal job retained ciphertext material")
	}
	if f.state.client.HExists(ctx, f.state.stateKey(richTestPeer), correlation).Val() {
		t.Fatal("terminal job retained active capacity")
	}
	if f.state.client.ZScore(ctx, f.state.dueKey(), wakeOutcomeDueMember(richTestPeer, correlation)).Err() != redis.Nil {
		t.Fatal("terminal job remains due")
	}
}

// The original RED exhausted all three sends and never retried the retained
// direct/group message. Recovery now requires no duplicate, new message, or
// recipient reopen, and survives loss of message custody and process state.
func TestRelayNotificationClosure_TextAutomaticRecoveryAfterProviderExhaustion(t *testing.T) {
	for _, encrypted := range []bool{false, true} {
		for _, lane := range []string{"direct", "protected-direct", "group", "strict-group"} {
			t.Run(fmt.Sprintf("encrypted=%t/%s", encrypted, lane), func(t *testing.T) {
				f := newAndroidRichTestFixture(t, encrypted)
				var healthy atomic.Bool
				var calls atomic.Int32
				f.push.sender = func(_ context.Context, msg *messaging.Message) (string, error) {
					calls.Add(1)
					if msg.Android == nil || msg.Android.Priority != "high" || msg.Notification != nil || msg.APNS != nil {
						t.Error("Android recovery must retain high-priority data-only transport")
					}
					expected := "new_message"
					if lane == "group" || lane == "strict-group" {
						expected = "group_message"
					}
					if msg.Data["type"] != expected {
						t.Errorf("wrong producer %q", msg.Data["type"])
					}
					if !healthy.Load() {
						return "", errors.New("temporary provider outage")
					}
					return "accepted", nil
				}
				message := wakeOutcomeDirectEnvelope("ordinary-text-original")
				if lane == "protected-direct" {
					message = fmt.Sprintf(`{"type":"chat_message","version":"2","id":"ordinary-text-original","senderPeerId":%q,"encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}}`, richTestSender)
				}
				if lane == "group" {
					message = `{"kind":"group_offline_replay","version":1,"payloadType":"group_message","keyEpoch":7,"messageId":"ordinary-text-original","ciphertext":"gc","nonce":"gn"}`
				}
				if lane == "strict-group" {
					signed := newTC364GroupContentFixture(t, "group-content-recovery", "logical-author", richTestSender)
					event := "gr1:" + strings.Repeat("a", 32) + ":00000000000000000001:" + strings.Repeat("b", 32)
					message = signed.envelope(t, "group_message", event, "", []string{richTestPeer}, "recovery")
				}
				entry := inboxMessage{ID: "custody-original", From: richTestSender, Message: message, Timestamp: f.now.UnixMilli()}
				store := func() {
					t.Helper()
					var err error
					switch lane {
					case "group":
						err = f.group.StoreWithPushRecipients(testCanonicalGroupPushID, richTestSender, message, []string{richTestPeer})
					case "strict-group":
						_, _, err = f.inbox.StoreAckCustody(richTestPeer, entry, ackCustodyGroupContentKind)
					case "protected-direct":
						_, _, err = f.inbox.StoreAckCustody(richTestPeer, entry, ackCustodyDirectTextKind)
					default:
						_, err = f.inbox.Store(richTestPeer, entry)
					}
					if err != nil {
						t.Fatalf("store %s: %v", lane, err)
					}
				}
				store()
				var correlation string
				awaitAndroidRich(t, "durable retry after exactly three failed provider attempts", func() bool {
					rows := f.state.client.HGetAll(context.Background(), f.state.stateKey(richTestPeer)).Val()
					for key, raw := range rows {
						record, err := decodeRedisWakeOutcomeRecord(raw)
						if err == nil && record.State == wakeOutcomeStatePending && record.RetryCount == 1 {
							correlation = key
							return true
						}
					}
					return false
				})
				if calls.Load() != 3 {
					t.Fatalf("initial attempts=%d, want3", calls.Load())
				}
				if f.state.client.Exists(context.Background(), f.state.androidRichMaterialKey(richTestPeer, correlation)).Val() != 1 {
					t.Fatal("failed notification lost retained material")
				}
				switch lane {
				case "direct":
					if n, err := f.inbox.Ack(richTestPeer, []string{entry.ID}); err != nil || n != 1 {
						t.Fatalf("ACK=%d/%v", n, err)
					}
				case "protected-direct", "strict-group":
					if n, err := f.inbox.AckAckCustody(richTestPeer, []string{entry.ID}); err != nil || n != 1 {
						t.Fatalf("protected ACK=%d/%v", n, err)
					}
				}
				healthy.Store(true)
				coordinator := richTestCoordinator(f, f.now.Add(2*time.Second))
				ctx, cancel := context.WithCancel(context.Background())
				coordinator.Start(ctx)
				awaitAndroidRich(t, "automatic retry after restart and ACK", func() bool {
					return f.state.client.Exists(context.Background(), f.state.androidRichCompletedKey(richTestPeer, correlation)).Val() == 1
				})
				cancel()
				coordinator.runMu.Lock()
				coordinator.runMu.Unlock()
				requireRichTerminal(t, f, correlation)
				if calls.Load() != 4 {
					t.Fatalf("recovery attempts=%d, want one additional accepted send", calls.Load())
				}
				store()
				if err := richTestCoordinator(f, f.now.Add(time.Minute)).RunDue(context.Background()); err != nil {
					t.Fatal(err)
				}
				if calls.Load() != 4 {
					t.Fatalf("duplicate after ACK/completion resubmitted: %d", calls.Load())
				}
				requireRichTerminal(t, f, correlation)
			})
		}
	}
}

func TestAndroidRichRecoveryTerminalCapacityAndReplayHorizon(t *testing.T) {
	f := newAndroidRichTestFixture(t, false)
	pending := richTestAdmission(t, f, "pending-during-burst")
	storeRichTestAdmission(t, f, pending)
	var first wakeOutcomeAdmission
	for index := 0; index < wakeOutcomePerPeerCapacity+8; index++ {
		a := richTestAdmission(t, f, fmt.Sprintf("accepted-%d", index))
		if index == 0 {
			first = a
		}
		if got := storeRichTestAdmission(t, f, a); got != wakeOutcomeAdmissionAndroidRich {
			t.Fatalf("event%d admission=%s", index, got)
		}
		claim, ok, err := f.state.claimOne(wakeOutcomeDueMember(richTestPeer, a.correlation), f.now)
		if err != nil || !ok {
			t.Fatalf("claim=%t/%v", ok, err)
		}
		if err := f.state.settle(claim, pushDeliveryAccepted, f.now.Add(time.Hour)); err != nil {
			t.Fatal(err)
		}
	}
	if count := f.state.client.HLen(context.Background(), f.state.stateKey(richTestPeer)).Val(); count != 1 {
		t.Fatalf("active slots after burst=%d, want pending only", count)
	}
	if requireWakeOutcomeRecord(t, f.state, richTestPeer, pending.correlation).State != wakeOutcomeStatePending {
		t.Fatal("pending job evicted")
	}
	requireRichTerminal(t, f, first.correlation)
	// Custody separately evicted this entry after64 messages. The marker remains
	// exact across restart, with no recreation of active state or retained payload.
	fresh := newRedisWakeOutcomeStore(f.pushBackend.client, f.state.prefix)
	fresh.now = f.state.now
	f.inboxBackend.wakeOutcomes = fresh
	if got := storeRichTestAdmission(t, f, first); got != wakeOutcomeAdmissionSuppressed {
		t.Fatalf("evicted custody replay=%s", got)
	}
	ttl := f.state.client.PTTL(context.Background(), f.state.androidRichCompletedKey(richTestPeer, first.correlation)).Val()
	if ttl > 23*time.Hour || ttl < 23*time.Hour-time.Second {
		t.Fatalf("completion extends original expiry: %s", ttl)
	}
	if status, err := fresh.complete(richTestPeer, first.correlation); err != nil || status != wakeOutcomeCompletionIdempotent {
		t.Fatalf("restart completion=%s/%v", status, err)
	}
	requireRichTerminal(t, f, first.correlation)
}

func TestAndroidRichRecoveryCurrentTokenRotationAndPermanentStop(t *testing.T) {
	for _, encrypted := range []bool{false, true} {
		for _, mode := range []string{"transient-rotation", "permanent-old-token-rotation", "permanent-current-token"} {
			t.Run(fmt.Sprintf("encrypted=%t/%s", encrypted, mode), func(t *testing.T) {
				f := newAndroidRichTestFixture(t, encrypted)
				a := richTestAdmission(t, f, "rotating-event")
				storeRichTestAdmission(t, f, a)
				var calls int
				f.push.retryDelays = nil
				f.push.sender = func(_ context.Context, msg *messaging.Message) (string, error) {
					calls++
					if calls == 1 {
						if mode != "permanent-current-token" {
							if encrypted {
								plan367RegisterEncrypted(t, f.pushBackend, richTestPeer, "rotated-provider-token", "android")
							} else if err := f.pushBackend.RegisterToken(richTestPeer, "rotated-provider-token", "android"); err != nil {
								t.Error(err)
							}
						}
						if mode == "transient-rotation" {
							return "", errors.New("temporarily unavailable")
						}
						return "", errors.New("registration-token-not-registered")
					}
					if msg.Token != "rotated-provider-token" {
						t.Error("retry did not resolve current token")
					}
					return "accepted", nil
				}
				coordinator := newWakeOutcomeCoordinator(f.state, nil, f.state.nowTime)
				coordinator.sendAndroidRich = func(ctx context.Context, c wakeOutcomeClaim) pushDeliveryResult {
					return f.push.sendAndroidRichRecovery(ctx, f.state, c)
				}
				if err := coordinator.RunDue(context.Background()); err != nil {
					t.Fatal(err)
				}
				if mode == "permanent-current-token" {
					requireRichTerminal(t, f, a.correlation)
					if route, err := f.pushBackend.LookupRoute(richTestPeer); err != nil || route != nil {
						t.Fatalf("permanent current token retained=%t/%v", route != nil, err)
					}
				} else {
					if requireWakeOutcomeRecord(t, f.state, richTestPeer, a.correlation).RetryCount != 1 {
						t.Fatal("rotation did not remain retryable")
					}
					if err := richTestCoordinator(f, f.now.Add(2*time.Second)).RunDue(context.Background()); err != nil {
						t.Fatal(err)
					}
					requireRichTerminal(t, f, a.correlation)
					if calls != 2 {
						t.Fatalf("rotation calls=%d", calls)
					}
				}
				if err := richTestCoordinator(f, f.now.Add(time.Hour)).RunDue(context.Background()); err != nil {
					t.Fatal(err)
				}
				want := 2
				if mode == "permanent-current-token" {
					want = 1
				}
				if calls != want {
					t.Fatalf("terminal job resubmitted: %d", calls)
				}
			})
		}
	}
}

func TestAndroidRichRecoveryRejectsUnsafeMaterialAndRoutes(t *testing.T) {
	for _, mutation := range []string{"missing", "digest", "recipient", "plaintext", "unknown-field", "trailing-json", "expired", "ios-rotation", "opaque-rotation"} {
		t.Run(mutation, func(t *testing.T) {
			f := newAndroidRichTestFixture(t, true)
			a := richTestAdmission(t, f, "private-logical-id")
			storeRichTestAdmission(t, f, a)
			claim, ok, err := f.state.claimOne(wakeOutcomeDueMember(richTestPeer, a.correlation), f.now)
			if err != nil || !ok {
				t.Fatalf("claim=%t/%v", ok, err)
			}
			var material androidRichPushMaterial
			if err := json.Unmarshal(a.androidRichMaterial, &material); err != nil {
				t.Fatal(err)
			}
			raw := append([]byte(nil), a.androidRichMaterial...)
			switch mutation {
			case "missing":
				f.state.client.Del(context.Background(), f.state.androidRichMaterialKey(richTestPeer, a.correlation))
			case "digest":
				raw = []byte(`{}`)
			case "recipient":
				material.RecipientHash = androidRichRecipientHash("different-recipient")
				raw, _ = json.Marshal(material)
			case "plaintext":
				material.Data["body"] = "private preview must never pass"
				raw, _ = json.Marshal(material)
			case "unknown-field":
				raw = append(raw[:len(raw)-1], []byte(`,"providerToken":"private-token"}`)...)
			case "trailing-json":
				raw = append(raw, []byte(` {}`)...)
			case "expired":
				material.ExpiresAtMs = f.now.UnixMilli()
				raw, _ = json.Marshal(material)
			case "ios-rotation":
				plan367RegisterEncrypted(t, f.pushBackend, richTestPeer, "ios-token", "ios")
			case "opaque-rotation":
				plan367RegisterEncrypted(t, f.pushBackend, richTestPeer, "opaque-token", "android", opaqueWakeCapability, wakeOutcomeCapability)
			}
			if mutation != "missing" {
				f.state.client.Set(context.Background(), f.state.androidRichMaterialKey(richTestPeer, a.correlation), raw, time.Hour)
			}
			if mutation != "digest" {
				claim.androidRichDigest = androidRichMaterialDigest(raw)
			}
			calls := 0
			f.push.sender = func(context.Context, *messaging.Message) (string, error) { calls++; return "accepted", nil }
			result := f.push.sendAndroidRichRecovery(context.Background(), f.state, claim)
			expected := pushDeliveryRetryable
			if mutation == "ios-rotation" {
				expected = pushDeliverySuppressed
			}
			if result != expected || calls != 0 {
				t.Fatalf("unsafe %s result=%s calls=%d", mutation, result, calls)
			}
		})
	}
}

func TestAndroidRichRecoveryAdmissionAtomicAndCompletionFailClosed(t *testing.T) {
	for _, corruption := range []string{"due-type", "completion-type", "completion-value", "material-validation", "route-rotation"} {
		t.Run(corruption, func(t *testing.T) {
			f := newAndroidRichTestFixture(t, false)
			a := richTestAdmission(t, f, "atomic-event")
			ctx := context.Background()
			switch corruption {
			case "due-type":
				f.state.client.Set(ctx, f.state.dueKey(), "wrong-type", time.Hour)
			case "completion-type":
				f.state.client.RPush(ctx, f.state.androidRichCompletedKey(richTestPeer, a.correlation), "1")
			case "completion-value":
				f.state.client.Set(ctx, f.state.androidRichCompletedKey(richTestPeer, a.correlation), "corrupt", time.Hour)
			case "material-validation":
				a.androidRichMaterial = []byte(`{}`)
			case "route-rotation":
				f.pushBackend.RegisterToken(richTestPeer, "new-token", "android")
			}
			_, _, err := f.inboxBackend.StoreWithWakeOutcome(richTestPeer, inboxMessage{ID: "atomic", From: richTestSender, Message: wakeOutcomeDirectEnvelope("atomic"), Timestamp: f.now.UnixMilli()}, a)
			if err == nil {
				t.Fatal("invalid admission committed")
			}
			if f.inbox.Count(richTestPeer) != 0 || f.state.client.HLen(ctx, f.state.stateKey(richTestPeer)).Val() != 0 || f.state.client.Exists(ctx, f.state.androidRichMaterialKey(richTestPeer, a.correlation)).Val() != 0 {
				t.Fatal("failed admission partially committed custody/material/state")
			}
		})
	}
	t.Run("settlement failure keeps claimed material", func(t *testing.T) {
		f := newAndroidRichTestFixture(t, false)
		a := richTestAdmission(t, f, "settlement")
		storeRichTestAdmission(t, f, a)
		claim, ok, err := f.state.claimOne(wakeOutcomeDueMember(richTestPeer, a.correlation), f.now)
		if !ok || err != nil {
			t.Fatal(err)
		}
		f.redis.SetError("injected storage unavailable")
		err = f.state.settle(claim, pushDeliveryAccepted, f.now)
		f.redis.SetError("")
		if err == nil {
			t.Fatal("failed Redis settlement reported accepted")
		}
		if record := requireWakeOutcomeRecord(t, f.state, richTestPeer, a.correlation); record.State != wakeOutcomeStateClaimed {
			t.Fatal("failed settlement lost claim")
		}
		if f.state.client.Exists(context.Background(), f.state.androidRichMaterialKey(richTestPeer, a.correlation)).Val() != 1 {
			t.Fatal("failed settlement deleted retry material")
		}
		if err := f.state.settle(claim, pushDeliveryAccepted, f.now); err != nil {
			t.Fatal(err)
		}
		requireRichTerminal(t, f, a.correlation)
	})
	t.Run("receiver completion preserves active provider claim", func(t *testing.T) {
		f := newAndroidRichTestFixture(t, false)
		a := richTestAdmission(t, f, "receiver-pending")
		storeRichTestAdmission(t, f, a)
		if status, err := f.state.complete(richTestPeer, a.correlation); err != nil || status != wakeOutcomeCompletionRecorded {
			t.Fatalf("complete=%s/%v", status, err)
		}
		requireRichTerminal(t, f, a.correlation)
		b := richTestAdmission(t, f, "receiver-claimed")
		storeRichTestAdmission(t, f, b)
		_, ok, err := f.state.claimOne(wakeOutcomeDueMember(richTestPeer, b.correlation), f.now)
		if !ok || err != nil {
			t.Fatal(err)
		}
		if status, err := f.state.complete(richTestPeer, b.correlation); err != nil || status != wakeOutcomeCompletionClaimed {
			t.Fatalf("complete claimed=%s/%v", status, err)
		}
		if f.state.client.Exists(context.Background(), f.state.androidRichMaterialKey(richTestPeer, b.correlation)).Val() != 1 {
			t.Fatal("receiver completion stole in-flight material")
		}
	})
}

func TestAndroidRichRecoveryProviderDeadlineAndCancellation(t *testing.T) {
	for _, mode := range []string{"deadline", "parent-cancellation"} {
		t.Run(mode, func(t *testing.T) {
			f := newAndroidRichTestFixture(t, false)
			a := richTestAdmission(t, f, "stalled-provider")
			storeRichTestAdmission(t, f, a)
			var calls atomic.Int32
			f.push.sender = func(ctx context.Context, _ *messaging.Message) (string, error) {
				calls.Add(1)
				deadline, ok := ctx.Deadline()
				if !ok || time.Until(deadline) > wakeOutcomeProviderTimeout {
					t.Error("provider lost bounded coordinator deadline")
				}
				<-ctx.Done()
				return "", ctx.Err()
			}
			ctx := context.Background()
			cancel := func() {}
			if mode == "parent-cancellation" {
				ctx, cancel = context.WithTimeout(ctx, 20*time.Millisecond)
			}
			defer cancel()
			start := time.Now()
			if err := richTestCoordinator(f, f.now).RunDue(ctx); err != nil {
				t.Fatal(err)
			}
			if elapsed := time.Since(start); elapsed > wakeOutcomeProviderTimeout+time.Second {
				t.Fatalf("stalled provider blocked worker for %s", elapsed)
			}
			if record := requireWakeOutcomeRecord(t, f.state, richTestPeer, a.correlation); record.State != wakeOutcomeStatePending || record.RetryCount != 1 {
				t.Fatalf("deadline lost durable retry: %#v", record)
			}
			f.push.sender = func(context.Context, *messaging.Message) (string, error) { return "accepted", nil }
			if err := richTestCoordinator(f, f.now.Add(2*time.Second)).RunDue(context.Background()); err != nil {
				t.Fatal(err)
			}
			requireRichTerminal(t, f, a.correlation)
		})
	}
}

func TestAndroidRichRecoveryExpiryPrivacyAndConcurrentClaim(t *testing.T) {
	t.Run("bounded ciphertext custody expires without provider send", func(t *testing.T) {
		f := newAndroidRichTestFixture(t, false)
		a := richTestAdmission(t, f, "expiring")
		storeRichTestAdmission(t, f, a)
		raw := f.state.client.Get(context.Background(), f.state.androidRichMaterialKey(richTestPeer, a.correlation)).Val()
		if strings.Contains(raw, "private-provider-token") || strings.Contains(raw, "notification") || strings.Contains(raw, "preview text") {
			t.Fatal("snapshot retained bearer/plain preview")
		}
		f.redis.FastForward(25 * time.Hour)
		calls := 0
		f.push.sender = func(context.Context, *messaging.Message) (string, error) { calls++; return "accepted", nil }
		if err := richTestCoordinator(f, f.now.Add(25*time.Hour)).RunDue(context.Background()); err != nil {
			t.Fatal(err)
		}
		if calls != 0 || f.state.client.Exists(context.Background(), f.state.androidRichMaterialKey(richTestPeer, a.correlation)).Val() != 0 || f.state.client.ZCard(context.Background(), f.state.dueKey()).Val() != 0 {
			t.Fatal("expired job retained material or submitted")
		}
	})
	t.Run("two relay workers share one exact provider claim", func(t *testing.T) {
		f := newAndroidRichTestFixture(t, false)
		a := richTestAdmission(t, f, "concurrent")
		storeRichTestAdmission(t, f, a)
		var calls atomic.Int32
		f.push.sender = func(context.Context, *messaging.Message) (string, error) { calls.Add(1); return "accepted", nil }
		done := make(chan error, 2)
		for i := 0; i < 2; i++ {
			go func() { done <- richTestCoordinator(f, f.now).RunDue(context.Background()) }()
		}
		for i := 0; i < 2; i++ {
			if err := <-done; err != nil {
				t.Fatal(err)
			}
		}
		if calls.Load() != 1 {
			t.Fatalf("concurrent accepted sends=%d", calls.Load())
		}
		requireRichTerminal(t, f, a.correlation)
	})
}

func TestAndroidRichRecoveryAllCustodyTransactionsFailTogether(t *testing.T) {
	for _, lane := range []string{"direct", "protected", "group"} {
		t.Run(lane, func(t *testing.T) {
			f := newAndroidRichTestFixture(t, false)
			a := richTestAdmission(t, f, "atomic-custody")
			ctx := context.Background()
			if err := f.state.client.Set(ctx, f.state.dueKey(), "invalid-index", time.Hour).Err(); err != nil {
				t.Fatal(err)
			}
			entry := inboxMessage{ID: "atomic", From: richTestSender, Message: wakeOutcomeDirectEnvelope("atomic"), Timestamp: f.now.UnixMilli()}
			var err error
			switch lane {
			case "direct":
				_, _, err = f.inboxBackend.StoreWithWakeOutcome(richTestPeer, entry, a)
			case "protected":
				_, _, _, err = f.inboxBackend.StoreAckCustodyWithWakeOutcome(richTestPeer, entry, "atomic-dedupe", a)
			case "group":
				_, _, err = f.groupBackend.StoreWithRecipientsAndWakeOutcomes("atomic-group", richTestSender, entry.Message, []string{richTestPeer}, []wakeOutcomeAdmission{a})
			}
			if err == nil {
				t.Fatal("invalid due index accepted custody transaction")
			}
			for _, key := range []string{f.inboxBackend.key(richTestPeer), f.inboxBackend.ackCustodyKey(richTestPeer), f.groupBackend.key("atomic-group"), f.state.stateKey(richTestPeer), f.state.androidRichMaterialKey(richTestPeer, a.correlation)} {
				if f.state.client.Exists(ctx, key).Val() != 0 {
					t.Fatal("failed transaction committed custody or recovery state")
				}
			}
		})
	}
}

func TestAndroidRichRecoveryPreservesProviderSizeFallback(t *testing.T) {
	f := newAndroidRichTestFixture(t, false)
	a := richTestAdmission(t, f, "provider-size-rescue")
	storeRichTestAdmission(t, f, a)
	calls := 0
	f.push.sender = func(_ context.Context, msg *messaging.Message) (string, error) {
		calls++
		if calls == 1 {
			return "", errors.New("payload too large")
		}
		if msg.Data["preview_unavailable"] != "1" || msg.Data["ciphertext"] != "" || msg.Data["type"] != "new_message" || msg.Data["sender_id"] != richTestSender {
			t.Error("size fallback lost safe routing-only rescue")
		}
		return "accepted", nil
	}
	if err := richTestCoordinator(f, f.now).RunDue(context.Background()); err != nil {
		t.Fatal(err)
	}
	if calls != 2 {
		t.Fatalf("provider size rescue calls=%d, want one original and one bounded rescue", calls)
	}
	requireRichTerminal(t, f, a.correlation)
}
