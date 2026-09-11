package main

import (
	"context"
	"fmt"
	"reflect"
	"testing"
	"time"

	"firebase.google.com/go/v4/messaging"
)

// This overlay-only regression models the deployment boundary, not a broken
// Redis service. Its first historical send follows committed HEAD's exact
// pre-guard adapter: sendSelectedPushThroughGateway without an admission key.
// Custody and provider operations are driven synchronously to isolate identity
// retention from goroutine scheduling. Production/test source stays unchanged.
func TestDirectNotificationPredeploymentHistoryGap(t *testing.T) {
	for _, historicalAdmission := range []bool{false, true} {
		name := "predeployment_history_missing"
		if historicalAdmission {
			name = "control_historical_admission_retained"
		}
		t.Run(name, func(t *testing.T) {
			const recipient = "recipient-a"
			const sender = "sender-a"
			const oldMessageID = "old-authored-before-deployment"
			const newMessageID = "genuinely-new-message"
			f := newDirectReplayProviderFixture(t, true, "ios")
			redisClient := f.tokens.(*redisPushTokenBackend).client
			backend := newRedisInboxBackend(redisClient, f.prefix, 10)
			inbox := NewInboxStoreWithBackendAndCapacity(backend, nil, 10)
			oldEnvelope := ackCustodyTextEnvelope(oldMessageID, sender, "same-original-ciphertext")
			newEnvelope := ackCustodyTextEnvelope(newMessageID, sender, "genuinely-new-ciphertext")
			sequence := 0
			store := func(envelope string, receivedAt time.Time) string {
				t.Helper()
				sequence++
				custodyID := fmt.Sprintf("custody-%d", sequence)
				result, err := inbox.Store(recipient, inboxMessage{
					ID: custodyID, From: sender, Message: envelope, Timestamp: receivedAt.UnixMilli(),
				})
				if err != nil || result != InboxStoreResultStored {
					t.Fatalf("store custody %s: result=%q err=%v", custodyID, result, err)
				}
				return custodyID
			}
			ack := func(custodyID string) {
				t.Helper()
				removed, err := inbox.Ack(recipient, []string{custodyID})
				if err != nil || removed != 1 {
					t.Fatalf("ACK custody %s: removed=%d err=%v", custodyID, removed, err)
				}
			}
			providerIDs := func() []string {
				ids := make([]string, 0, f.recorder.SendCallCount())
				for _, message := range f.recorder.Messages() {
					ids = append(ids, sentRoutingString(message, "message_id"))
				}
				return ids
			}

			// The old message really reached the provider and its delivery custody
			// was ACKed before the replay guard's deployment.
			oldCustody := store(oldEnvelope, time.Now().Add(-30*time.Hour))
			if historicalAdmission {
				f.push.sendStoredNotification(context.Background(), recipient, sender, oldEnvelope, oldCustody)
			} else {
				route, err := f.push.selectPushRoute(recipient, "")
				if err != nil || route == nil {
					t.Fatalf("select historical route: err=%v", err)
				}
				result := f.push.sendSelectedPushThroughGateway(
					context.Background(), recipient, *route, "",
					func() *messaging.Message { return buildPushMessage("", sender, oldEnvelope) },
					func(message *messaging.Message, platform string) *messaging.Message {
						return projectStoredDirectPushMessageForPlatform(message, platform, oldCustody)
					},
				)
				if result != pushDeliveryAccepted {
					t.Fatalf("historical provider acceptance=%v, want accepted", result)
				}
			}
			if got := providerIDs(); !reflect.DeepEqual(got, []string{oldMessageID}) {
				t.Fatalf("historical provider IDs=%v", got)
			}
			ack(oldCustody)

			// Deploy/restart with the real durable admission backend and the same
			// Redis data. No history migration currently seeds the missing claim.
			f.push = f.newPush()
			newCustody := store(newEnvelope, time.Now())
			f.push.sendStoredNotification(context.Background(), recipient, sender, newEnvelope, newCustody)
			ack(newCustody)
			replayCustody := store(oldEnvelope, time.Now())
			f.push.sendStoredNotification(context.Background(), recipient, sender, oldEnvelope, replayCustody)
			ack(replayCustody)
			afterFirstReplay := providerIDs()
			t.Logf("provider sequence after new message and old replay: %v", afterFirstReplay)

			// The first post-deployment replay seeds an admission claim: a further
			// identical replay is then suppressed even in the failing scenario.
			repeatedCustody := store(oldEnvelope, time.Now())
			f.push.sendStoredNotification(context.Background(), recipient, sender, oldEnvelope, repeatedCustody)
			if got := providerIDs(); !reflect.DeepEqual(got, afterFirstReplay) {
				t.Fatalf("subsequent identical replay escaped populated admission: before=%v after=%v", afterFirstReplay, got)
			}
			t.Log("subsequent identical replay suppressed after admission became populated")
			want := []string{oldMessageID, newMessageID}
			if !reflect.DeepEqual(afterFirstReplay, want) {
				t.Fatalf("predeployment notification must remain historical: provider sequence=%v, want=%v", afterFirstReplay, want)
			}
		})
	}
}
