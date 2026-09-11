package main

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/prometheus/client_golang/prometheus/testutil"
	"github.com/redis/go-redis/v9"
)

// A completed durable wake already remembers the event. Capacity fallback and
// a route gaining durable-wake support must share the provider's event memory
// too, while accepting a new inbox custody row after the old row was ACKed.
func TestDirectNotificationWakeReplayAfterAckDoesNotResendIOS(t *testing.T) {
	for _, scenario := range []string{"delayed_completed", "capacity_fallback", "rich_then_delayed"} {
		t.Run(scenario, func(t *testing.T) {
			const recipient = "direct-wake-replay-recipient"
			const sender = "direct-wake-replay-sender"
			const messageID = "direct-wake-replay-message"
			fixture := newWakeOutcomeTestFixture(t, "direct-wake-replay:"+scenario+":")
			recorder := newRecordingPushSender()
			fixture.push.sender = recorder.Send
			register := func(durable bool) {
				t.Helper()
				var capabilities []string
				if durable {
					capabilities = []string{opaqueWakeCapability, wakeOutcomeCapability}
				}
				plan367RegisterEncrypted(t, fixture.pushBackend, recipient, "direct-wake-ios-token", "ios", capabilities...)
			}
			register(scenario != "rich_then_delayed")
			if scenario == "capacity_fallback" {
				records := make(map[string]redisWakeOutcomeRecord, wakeOutcomePerPeerCapacity)
				for index := 0; index < wakeOutcomePerPeerCapacity; index++ {
					records[fmt.Sprintf("%064x", index+1)] = redisWakeOutcomeRecord{
						State: wakeOutcomeStateCompleted, Revision: 1,
						ExpiresAtMs: fixture.now.Add(wakeOutcomeRetention).UnixMilli(), Policy: wakeOutcomePolicyNone,
					}
				}
				if _, err := fixture.state.client.TxPipelined(context.Background(), func(pipe redis.Pipeliner) error {
					return queueWakeOutcomeHash(context.Background(), pipe, fixture.state.stateKey(recipient), records)
				}); err != nil {
					t.Fatalf("fill durable wake capacity: %v", err)
				}
			}
			// messageId is the legacy spelling accepted by durable direct wake
			// correlation; id is the ordinary encrypted chat identity.
			envelope := fmt.Sprintf(`{"type":"chat_message","version":"2","id":%q,"messageId":%q,"senderPeerId":%q,"encrypted":{"kem":"kem","ciphertext":"original-ciphertext","nonce":"nonce"}}`, messageID, messageID, sender)
			store := func(id string) {
				t.Helper()
				result, err := fixture.inbox.Store(recipient, inboxMessage{
					ID: id, From: sender, Message: envelope, Timestamp: fixture.now.UnixMilli(),
				})
				if err != nil || result != InboxStoreResultStored {
					t.Fatalf("store %s: result=%q err=%v", id, result, err)
				}
			}
			runDue := func() {
				t.Helper()
				due := fixture.now.Add(wakeOutcomeDebounce)
				coordinator := newWakeOutcomeCoordinator(fixture.state, fixture.push.sendWakeOutcomeThroughGateway, func() time.Time { return due })
				coordinator.sendGroup = fixture.push.sendGroupWakeOutcomeThroughGateway
				coordinator.sendDirect = fixture.push.sendDirectWakeOutcomeThroughGateway
				if err := coordinator.RunDue(context.Background()); err != nil {
					t.Fatalf("run due direct wake: %v", err)
				}
			}
			store("original-custody")
			runDue()
			waitForWakeProviderCalls(t, recorder, 1)
			select {
			case <-recorder.sentSignal:
			case <-time.After(2 * time.Second):
				t.Fatal("first provider attempt did not complete")
			}
			if removed, err := fixture.inbox.Ack(recipient, []string{"original-custody"}); err != nil || removed != 1 {
				t.Fatalf("ACK original: removed=%d err=%v", removed, err)
			}
			if scenario == "rich_then_delayed" {
				register(true)
			}
			suppressedBefore := testutil.ToFloat64(pushSentCounter.WithLabelValues("direct_admission_suppressed"))
			store("replayed-custody")
			runDue()
			pending, _ := fixture.inbox.RetrievePendingWithMeta(recipient, 10)
			if len(pending) != 1 || pending[0].ID != "replayed-custody" || pending[0].Message != envelope {
				t.Fatalf("replay must retain exact delivery custody: %#v", pending)
			}
			// Capacity fallback is the only asynchronous dispatch in this leg.
			if scenario == "capacity_fallback" {
				deadline := time.NewTimer(2 * time.Second)
				defer deadline.Stop()
				tick := time.NewTicker(time.Millisecond)
				defer tick.Stop()
				for testutil.ToFloat64(pushSentCounter.WithLabelValues("direct_admission_suppressed")) <= suppressedBefore {
					select {
					case <-recorder.sentSignal:
						t.Fatalf("ACKed old message generated another iOS notification via capacity fallback: provider attempts=%d", recorder.SendCallCount())
					case <-tick.C:
					case <-deadline.C:
						t.Fatal("capacity replay neither completed admission suppression nor reached the provider")
					}
				}
			}
			if calls := recorder.SendCallCount(); calls != 1 {
				t.Fatalf("ACKed old message generated another iOS notification via %s: provider attempts=%d, want 1", scenario, calls)
			}
		})
	}
}
