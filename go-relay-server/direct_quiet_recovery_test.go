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
)

func assertQuietRecoveryPush(t *testing.T, message *messaging.Message, platform string) {
	t.Helper()
	if message.Notification != nil || len(message.Data) != 3 || message.Data["quietRecovery"] != "1" || message.Data["v"] != "1" || message.Data["w"] != "1" {
		t.Fatalf("quiet wake contains visible or nonfixed material: %#v", message)
	}
	if platform == "ios" {
		if message.APNS == nil || message.APNS.Headers["apns-push-type"] != "background" || message.APNS.Headers["apns-priority"] != "5" {
			t.Fatalf("quiet iOS wake is not background priority 5: %#v", message.APNS)
		}
		raw, err := json.Marshal(message.APNS.Payload)
		if err != nil || string(raw) != `{"aps":{"content-available":1}}` {
			t.Fatalf("quiet iOS wake includes presentation: %s (%v)", raw, err)
		}
	} else if message.APNS != nil || message.Android == nil || message.Android.Notification != nil {
		t.Fatalf("quiet Android wake includes presentation: %#v", message)
	}
}

func TestQuietRecoveryCustodyRestartAndExplicitRetry(t *testing.T) {
	for _, platform := range []string{"ios", "android"} {
		for _, mode := range []string{"memory", "redis", "protected"} {
			t.Run(platform+"/"+mode, func(t *testing.T) {
				protected := mode == "protected"
				f := newDirectReplayProviderFixture(t, mode != "memory", platform)
				var backend InboxBackend = newMemoryInboxBackend()
				if f.redis != nil {
					backend = newRedisInboxBackend(newTestRedisClient(t, f.redis), f.prefix, 10)
				}
				inbox := NewInboxStoreWithBackendAndCapacity(backend, f.push, 10)
				inbox.SetAckCustodyAdmissionEnabled(protected)
				entry := inboxMessage{From: "sender-a", Message: ackCustodyTextEnvelope("three-day-backlog", "sender-a", "original-ciphertext"), Timestamp: time.Now().UnixMilli(), QuietRecovery: true, SuppressNotification: true}
				stored := custodyOnlyStoreForTest(t, inbox, "recipient-a", entry, protected)
				waitForWakeProviderCalls(t, f.recorder, 1)
				assertQuietRecoveryPush(t, f.recorder.LastMessage(), platform)
				if !stored.QuietRecovery {
					t.Fatal("quiet transport disposition was not stored")
				}
				originalID, originalTimestamp := stored.ID, stored.Timestamp
				if f.redis != nil {
					f.push = f.newPush()
					backend = newRedisInboxBackend(newTestRedisClient(t, f.redis), f.prefix, 10)
					inbox = NewInboxStoreWithBackendAndCapacity(backend, f.push, 10)
					inbox.SetAckCustodyAdmissionEnabled(protected)
				}
				storeAgain := func() {
					t.Helper()
					var result InboxStoreResult
					var err error
					if protected {
						result, _, err = inbox.StoreAckCustody("recipient-a", entry, ackCustodyDirectTextKind)
					} else {
						result, err = inbox.Store("recipient-a", entry)
					}
					if err != nil || result != InboxStoreResultDuplicate {
						t.Fatalf("duplicate custody: %q %v", result, err)
					}
				}
				storeAgain()
				pending, _ := inbox.RetrievePendingWithMeta("recipient-a", 10)
				if len(pending) != 1 || !pending[0].QuietRecovery || pending[0].ID != originalID || pending[0].Timestamp != originalTimestamp || pending[0].Message != entry.Message {
					t.Fatalf("duplicate/restart changed immutable delivery: %#v", pending)
				}
				// A rich adapter selected before the quiet store is fenced, including
				// on Android where ordinary iOS admission does not apply.
				f.push.sendStoredNotification(context.Background(), "recipient-a", entry.From, entry.Message, originalID)
				if got := f.recorder.SendCallCount(); got != 1 {
					t.Fatalf("quiet duplicate generated visible wake: %d", got)
				}
				identity, _ := newDirectMessageDispatchAdmissionIdentity("recipient-a", entry.From, entry.Message)
				lease, acquired, err := f.push.directMessageDispatchAdmission.TryAcquire(context.Background(), identity)
				if err != nil || !acquired {
					t.Fatalf("quiet recovery consumed visible admission: %t %v", acquired, err)
				}
				if err := f.push.directMessageDispatchAdmission.Release(context.Background(), lease); err != nil {
					t.Fatal(err)
				}
				entry.QuietRecovery, entry.SuppressNotification = false, false
				storeAgain()
				waitForWakeProviderCalls(t, f.recorder, 2)
				if f.recorder.LastMessage().Data["quietRecovery"] != "" {
					t.Fatal("explicit retry remained quiet")
				}
				pending, _ = inbox.RetrievePendingWithMeta("recipient-a", 10)
				if len(pending) != 1 || pending[0].QuietRecovery || pending[0].ID != originalID {
					t.Fatalf("manual retry failed to restore normal disposition: %#v", pending)
				}
				custodyOnlyAckForTest(t, inbox, "recipient-a", originalID, protected)
			})
		}
	}
}

func TestQuietRecoveryPendingWakeRemainsSuppressedAfterAckAndRestart(t *testing.T) {
	f := newWakeOutcomeTestFixture(t, "quiet-recovery-pending:")
	const recipient, sender = "recipient-a", "sender-a"
	plan367RegisterEncrypted(t, f.pushBackend, recipient, "push-token", "ios", opaqueWakeCapability, wakeOutcomeCapability)
	recorder := newRecordingPushSender()
	f.push.sender = recorder.Send
	envelope := fmt.Sprintf(`{"type":"chat_message","version":"2","id":"old","messageId":"old","senderPeerId":%q,"encrypted":{"kem":"kem","ciphertext":"ciphertext","nonce":"nonce"}}`, sender)
	entry := inboxMessage{ID: "retained-custody", From: sender, Message: envelope, Timestamp: f.now.UnixMilli()}
	if result, err := f.inbox.Store(recipient, entry); err != nil || result != InboxStoreResultStored {
		t.Fatalf("initial store %q %v", result, err)
	}
	if recorder.SendCallCount() != 0 {
		t.Fatal("fixture did not create a delayed obligation")
	}
	entry.QuietRecovery, entry.SuppressNotification = true, true
	if result, err := f.inbox.Store(recipient, entry); err != nil || result != InboxStoreResultDuplicate {
		t.Fatalf("quiet duplicate %q %v", result, err)
	}
	pending, _ := f.inbox.RetrievePendingWithMeta(recipient, 10)
	if len(pending) != 1 || !pending[0].QuietRecovery {
		t.Fatal("quiet duplicate sidecar was lost")
	}
	if removed, err := f.inbox.Ack(recipient, []string{entry.ID}); err != nil || removed != 1 {
		t.Fatalf("ACK %d %v", removed, err)
	}
	// Recreate provider+inbox ownership: no process-local suppression is needed.
	push := NewPushServiceWithBackend(f.pushBackend)
	push.sender = recorder.Send
	NewInboxStoreWithBackendAndCapacity(newRedisInboxBackend(newTestRedisClient(t, f.redis), f.state.prefix, 10), push, 10)
	coordinator := newWakeOutcomeCoordinator(f.state, push.sendWakeOutcomeThroughGateway, func() time.Time { return f.now.Add(wakeOutcomeDebounce) })
	coordinator.sendDirect = push.sendDirectWakeOutcomeThroughGateway
	if err := coordinator.RunDue(context.Background()); err != nil {
		t.Fatal(err)
	}
	if recorder.SendCallCount() != 0 {
		t.Fatal("previous delayed visible wake escaped quiet recovery after ACK/restart")
	}
}

func TestQuietRecoveryWireAuthorityAndImmutableRetrieval(t *testing.T) {
	for _, mode := range []string{"legacy_sidecar", "protected_sidecar", "legacy_action", "protected_action"} {
		t.Run(mode, func(t *testing.T) {
			protected := strings.HasPrefix(mode, "protected")
			f := newDirectReplayProviderFixture(t, true, "ios")
			backend := newRedisInboxBackend(newTestRedisClient(t, f.redis), f.prefix, 10)
			inbox := NewInboxStoreWithBackendAndCapacity(backend, f.push, 10)
			inbox.SetAckCustodyAdmissionEnabled(protected)
			env := setupInboxStreamEnv(t, inbox, NewGroupInboxStore(10, groupMessageTTL))
			recipient, sender := env.recipient.ID().String(), env.sender.ID().String()
			if err := f.tokens.RegisterToken(recipient, "wire-token", "ios"); err != nil {
				t.Fatal(err)
			}
			envelope := ackCustodyTextEnvelope("old-original", sender, "ciphertext")
			request := inboxRequest{Action: "store", To: recipient, From: "forged", Message: envelope, QuietRecovery: true, SuppressNotification: true}
			if protected {
				request.Action, request.CustodyKind, request.CustodyContract = ackCustodyStoreAction, ackCustodyDirectTextKind, ackCustodyContract
			}
			if strings.HasSuffix(mode, "action") {
				request.Action = "store_quiet_v1"
				if protected {
					request.Action = "store_custody_quiet_v1"
				}
				// The action itself selects the required policy. A forgotten
				// optional sidecar cannot quietly change the operation's meaning.
				request.QuietRecovery, request.SuppressNotification = false, false
			}
			stream, err := env.sender.NewStream(context.Background(), env.server.ID(), InboxProtocol)
			if err != nil {
				t.Fatal(err)
			}
			defer stream.Close()
			sendInboxReq(t, stream, request)
			response := recvInboxResp(t, stream)
			if response.Status != "OK" {
				t.Fatalf("wire store: %#v", response)
			}
			waitForWakeProviderCalls(t, f.recorder, 1)
			assertQuietRecoveryPush(t, f.recorder.LastMessage(), "ios")
			pending, _ := inbox.RetrievePendingWithMeta(recipient, 10)
			if len(pending) != 1 || !pending[0].QuietRecovery || pending[0].From != sender || pending[0].Message != envelope {
				t.Fatalf("wire quiet custody: %#v", pending)
			}
			raw, _ := json.Marshal(pending[0])
			if !strings.Contains(string(raw), `"quietRecovery":true`) || strings.Contains(string(raw), "suppressNotification") {
				t.Fatalf("retrieved sidecar contract: %s", raw)
			}
			identity, _ := newDirectMessageDispatchAdmissionIdentity(recipient, "forged", envelope)
			if quiet, err := backend.DirectQuietRecovery(context.Background(), identity.storageKey()); err != nil || quiet {
				t.Fatalf("forged sender contaminated policy: %t %v", quiet, err)
			}
		})
	}
}

func TestQuietRecoveryLegacyReceiverRetainsQuietRowsAndDrainsNormalRows(t *testing.T) {
	for _, action := range []string{"retrieve", "retrieve_pending", "retrieve_custody_pending_v1"} {
		t.Run(action, func(t *testing.T) {
			f := newDirectReplayProviderFixture(t, true, "ios")
			backend := newRedisInboxBackend(newTestRedisClient(t, f.redis), f.prefix, 10)
			inbox := NewInboxStoreWithBackendAndCapacity(backend, nil, 10)
			inbox.SetAckCustodyAdmissionEnabled(true)
			env := setupInboxStreamEnv(t, inbox, NewGroupInboxStore(10, groupMessageTTL))
			recipient, sender := env.recipient.ID().String(), env.sender.ID().String()
			for _, quiet := range []bool{true, false} {
				entry := inboxMessage{From: sender, Message: ackCustodyTextEnvelope(fmt.Sprint(quiet), sender, "immutable"), Timestamp: time.Now().UnixMilli(), QuietRecovery: quiet}
				if _, _, err := inbox.StoreAckCustody(recipient, entry, ackCustodyDirectTextKind); err != nil {
					t.Fatal(err)
				}
			}
			fetch := func(capable bool) inboxResponse {
				s, err := env.recipient.NewStream(context.Background(), env.server.ID(), InboxProtocol)
				if err != nil {
					t.Fatal(err)
				}
				defer s.Close()
				sendInboxReq(t, s, inboxRequest{Action: action, Limit: 1, CustodyContract: ackCustodyContract, QuietRecovery: capable})
				return recvInboxResp(t, s)
			}
			legacy := fetch(false)
			if legacy.Status != "OK" || len(legacy.Messages) != 1 || legacy.Messages[0].QuietRecovery || legacy.HasMore {
				t.Fatalf("old receiver got quiet content or a stuck page: %+v", legacy)
			}
			if action != "retrieve" {
				if _, err := inbox.AckAckCustody(recipient, []string{legacy.Messages[0].ID}); err != nil {
					t.Fatal(err)
				}
			}
			upgraded := fetch(true)
			if upgraded.Status != "OK" || len(upgraded.Messages) != 1 || !upgraded.Messages[0].QuietRecovery || upgraded.Messages[0].From != sender {
				t.Fatalf("quiet row was lost before receiver upgrade: %+v", upgraded)
			}
		})
	}
}

func TestQuietRecoveryMemoryPaginationDoesNotDiscardHiddenRows(t *testing.T) {
	for name, backend := range map[string]InboxBackend{"memory": newMemoryInboxBackend(), "limited": newMemoryInboxBackendWithLimits(10)} {
		t.Run(name, func(t *testing.T) {
			inbox := NewInboxStoreWithBackendAndCapacity(backend, nil, 10)
			for _, quiet := range []bool{true, false} {
				if _, err := inbox.Store("recipient", inboxMessage{From: "sender", Message: ackCustodyTextEnvelope(fmt.Sprint(quiet), "sender", "immutable"), QuietRecovery: quiet, Timestamp: time.Now().UnixMilli()}); err != nil {
					t.Fatal(err)
				}
			}
			page, more := inbox.RetrievePendingWithMeta("recipient", 1, false)
			if len(page) != 1 || page[0].QuietRecovery || more {
				t.Fatalf("legacy pending page: %+v more=%v", page, more)
			}
			page, more = inbox.RetrieveWithMeta("recipient", 1, false)
			if len(page) != 1 || page[0].QuietRecovery || more || inbox.Count("recipient") != 1 {
				t.Fatalf("destructive read discarded quiet custody: %+v more=%v", page, more)
			}
			page, more = inbox.RetrievePendingWithMeta("recipient", 1, true)
			if len(page) != 1 || !page[0].QuietRecovery || more {
				t.Fatalf("upgraded pending page: %+v more=%v", page, more)
			}
		})
	}
}

func TestQuietRecoveryFailuresNeverCreateAlertFallbackOrPoisonHistory(t *testing.T) {
	f := newDirectReplayProviderFixture(t, true, "ios")
	backend := newRedisInboxBackend(newTestRedisClient(t, f.redis), f.prefix, 10)
	inbox := NewInboxStoreWithBackendAndCapacity(backend, f.push, 10)
	inbox.SetAckCustodyAdmissionEnabled(true)
	entry := inboxMessage{From: "sender-a", Message: ackCustodyTextEnvelope("failed-store", "sender-a", "ciphertext"), Timestamp: time.Now().UnixMilli(), QuietRecovery: true, SuppressNotification: true}
	backend.ackCustodyBeforeCommit = func() error { return errors.New("injected storage failure") }
	if _, _, err := inbox.StoreAckCustody("recipient-a", entry, ackCustodyDirectTextKind); err == nil {
		t.Fatal("failed custody accepted")
	}
	identity, _ := newDirectMessageDispatchAdmissionIdentity("recipient-a", entry.From, entry.Message)
	if quiet, err := backend.DirectQuietRecovery(context.Background(), identity.storageKey()); err != nil || quiet {
		t.Fatalf("failed store changed policy %t %v", quiet, err)
	}
	if f.recorder.SendCallCount() != 0 {
		t.Fatal("failed store sent a wake")
	}
	f.recorder.err = errors.New("message too big")
	f.push.sendQuietRecoveryWake(context.Background(), "recipient-a")
	if f.recorder.SendCallCount() != 1 {
		t.Fatalf("size error generated a visible fallback: calls=%d", f.recorder.SendCallCount())
	}
	assertQuietRecoveryPush(t, f.recorder.LastMessage(), "ios")
	if _, err := buildQuietRecoveryPush("unknown"); !errors.Is(err, errOpaqueWakeUnsupportedPlatform) {
		t.Fatalf("unknown platform: %v", err)
	}
}

func TestQuietRecoveryFencesRetainedAndroidRichMaterial(t *testing.T) {
	f := newDirectReplayProviderFixture(t, true, "android")
	backend := newRedisInboxBackend(newTestRedisClient(t, f.redis), f.prefix, 10)
	inbox := NewInboxStoreWithBackendAndCapacity(backend, f.push, 10)
	entry := inboxMessage{From: "sender-a", Message: ackCustodyTextEnvelope("android-retained", "sender-a", "ciphertext"), Timestamp: time.Now().UnixMilli(), QuietRecovery: true}
	custodyOnlyStoreForTest(t, inbox, "recipient-a", entry, false)
	waitForWakeProviderCalls(t, f.recorder, 1)
	data := buildPushMessage("", entry.From, entry.Message).Data
	material := androidRichPushMaterial{Version: 1, RecipientHash: androidRichRecipientHash("recipient-a"), Correlation: strings.Repeat("a", 64), ExpiresAtMs: time.Now().Add(time.Hour).UnixMilli(), Data: data}
	if result := f.push.sendAndroidRichMaterial(context.Background(), "recipient-a", material); result != pushDeliverySuppressed {
		t.Fatalf("legacy rich recovery result %q", result)
	}
	if f.recorder.SendCallCount() != 1 {
		t.Fatal("retained Android material created an alert")
	}
}

func TestQuietRecoveryStoreFencesConcurrentUnstartedProviderAttempt(t *testing.T) {
	f := newDirectReplayProviderFixture(t, true, "ios")
	backend := newRedisInboxBackend(newTestRedisClient(t, f.redis), f.prefix, 10)
	inbox := NewInboxStoreWithBackendAndCapacity(backend, f.push, 10)
	inbox.SetAckCustodyAdmissionEnabled(true)
	entry := inboxMessage{From: "sender-a", Message: ackCustodyTextEnvelope("concurrent-recovery", "sender-a", "ciphertext"), Timestamp: time.Now().UnixMilli(), QuietRecovery: true}
	commitReady, releaseCommit := make(chan struct{}), make(chan struct{})
	backend.ackCustodyBeforeCommit = func() error { close(commitReady); <-releaseCommit; return nil }
	storeDone := make(chan error, 1)
	go func() {
		_, _, err := inbox.StoreAckCustody("recipient-a", entry, ackCustodyDirectTextKind)
		storeDone <- err
	}()
	select {
	case <-commitReady:
	case err := <-storeDone:
		t.Fatalf("store did not reach the commit boundary: %v", err)
	case <-time.After(2 * time.Second):
		t.Fatal("store did not reach the commit boundary")
	}
	providerDone := make(chan struct{})
	go func() {
		defer close(providerDone)
		f.push.sendStoredNotification(context.Background(), "recipient-a", entry.From, entry.Message, "previously-selected")
	}()
	identity, _ := newDirectMessageDispatchAdmissionIdentity("recipient-a", entry.From, entry.Message)
	deadline := time.After(2 * time.Second)
	tick := time.NewTicker(time.Millisecond)
	defer tick.Stop()
	for {
		directRecoveryDispatchLocks.Lock()
		lock := directRecoveryDispatchLocks.entries[identity.storageKey()]
		waiting := lock != nil && lock.references == 2
		directRecoveryDispatchLocks.Unlock()
		if waiting {
			break
		}
		select {
		case <-deadline:
			close(releaseCommit)
			t.Fatal("provider did not wait behind exact custody transaction")
		case <-tick.C:
		}
	}
	if f.recorder.SendCallCount() != 0 {
		close(releaseCommit)
		t.Fatal("provider began before quiet disposition committed")
	}
	close(releaseCommit)
	select {
	case err := <-storeDone:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("quiet store did not finish")
	}
	select {
	case <-providerDone:
	case <-time.After(2 * time.Second):
		t.Fatal("fenced provider did not finish")
	}
	waitForWakeProviderCalls(t, f.recorder, 1)
	assertQuietRecoveryPush(t, f.recorder.LastMessage(), "ios")
}

func TestQuietRecoveryRouteRefreshCannotBecomeVisible(t *testing.T) {
	for _, permanentlyStale := range []bool{false, true} {
		t.Run(fmt.Sprint(permanentlyStale), func(t *testing.T) {
			f := newDirectReplayProviderFixture(t, false, "ios")
			probe := &plan368BackendProbe{delegate: f.tokens}
			probe.resolve = func(call int, route pushRouteLease) (*resolvedPushTarget, error) {
				if call == 1 || permanentlyStale {
					return nil, ErrPushRouteStale
				}
				return f.tokens.ResolveRoute(route)
			}
			f.push.tokenBackend = probe
			f.push.sendQuietRecoveryWake(context.Background(), "recipient-a")
			lookups, resolves, _ := probe.counts()
			if lookups != 2 || resolves != 2 {
				t.Fatalf("unbounded route reselection: %d %d", lookups, resolves)
			}
			if permanentlyStale {
				if f.recorder.SendCallCount() != 0 {
					t.Fatal("stale quiet route fell back to visible push")
				}
			} else {
				if f.recorder.SendCallCount() != 1 {
					t.Fatal("refreshed quiet wake missing")
				}
				assertQuietRecoveryPush(t, f.recorder.LastMessage(), "ios")
			}
		})
	}
}

type unavailableQuietRecoveryBackend struct{ InboxBackend }

func (unavailableQuietRecoveryBackend) DirectQuietRecovery(context.Context, string) (bool, error) {
	return false, errors.New("injected quiet policy read failure")
}

func TestQuietRecoveryPolicyReadFailureRetainsSenderObligation(t *testing.T) {
	f := newDirectReplayProviderFixture(t, false, "ios")
	backend := unavailableQuietRecoveryBackend{newMemoryInboxBackend()}
	inbox := NewInboxStoreWithBackendAndCapacity(backend, f.push, 10)
	entry := inboxMessage{From: "sender-a", Message: ackCustodyTextEnvelope("uncertain-policy", "sender-a", "ciphertext"), Timestamp: time.Now().UnixMilli()}
	if _, err := inbox.Store("recipient-a", entry); err == nil {
		t.Fatal("uncertain policy was acknowledged instead of remaining retryable")
	}
	if backend.Count("recipient-a") != 0 || f.recorder.SendCallCount() != 0 {
		t.Fatal("failed policy read changed custody or started provider work")
	}
	f.push.sendStoredNotification(context.Background(), "recipient-a", entry.From, entry.Message, "old-obligation")
	if f.recorder.SendCallCount() != 0 {
		t.Fatal("uncertain delayed policy fell through to an alert")
	}
}
