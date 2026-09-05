package main

import (
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
)

// The wake outcome is opt-in on the wire: clients decode store responses
// strictly, so a relay must never surface `wake` to a client that did not ask.
func TestCallStoreResponseCarriesTheWakeOutcomeOnlyWhenAsked(t *testing.T) {
	server := miniredis.RunT(t)
	now := time.Unix(1_801_750_000, 0).UTC()
	dispatcher := &callTestWakeDispatcher{}
	service := NewCallControlService(
		newRedisCallControlStore(newTestRedisClient(t, server), "wake-receipt-handler:"),
		dispatcher,
		func() time.Time { return now },
	)
	fixture := newCallHandlerFixture(t, service)
	recipient := fixture.recipient.ID().String()
	sender := fixture.client.ID().String()
	authorizeCallFixture(t, service, now, sender, recipient)

	legacy := callHandlerRoundTrip(t, fixture, fixture.client, map[string]any{
		"action": "call_store_v1", "to": recipient, "callHandle": callTestHandleA,
		"messageId": callTestMessageA, "envelope": "encrypted-a",
		"expiresAtMs": now.Add(45 * time.Second).UnixMilli(), "wakeHandle": callTestWake,
	})
	if legacy["status"] != "OK" || legacy["storeStatus"] != "stored" {
		t.Fatalf("legacy store response = %#v", legacy)
	}
	if _, present := legacy["wake"]; present {
		t.Fatalf("legacy client must not see a wake field: %#v", legacy)
	}
	if len(dispatcher.routes) != 1 {
		t.Fatalf("legacy store wakes = %d, want 1", len(dispatcher.routes))
	}

	asked := callHandlerRoundTrip(t, fixture, fixture.client, map[string]any{
		"action": "call_store_v1", "to": recipient, "callHandle": callTestHandleA,
		"messageId": callTestMessageB, "envelope": "encrypted-b",
		"expiresAtMs": now.Add(45 * time.Second).UnixMilli(), "wakeHandle": callTestWake,
		"wakeReceipt": true,
	})
	if asked["status"] != "OK" || asked["wake"] != "dispatched" {
		t.Fatalf("opt-in store response = %#v, want wake dispatched", asked)
	}
}
