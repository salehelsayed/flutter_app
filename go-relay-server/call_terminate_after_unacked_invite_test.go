package main

import (
	"context"
	"testing"
	"time"
)

// A caller that hangs up on a callee still ringing from the mailbox stores
// the terminate behind the unacknowledged invite (plan 400 fix 3). A callee
// that never acknowledged the invite (Android headless admission evaluates
// without acking) must still retrieve both rows when the terminate's wake
// arrives; an empty page here leaves the callee ringing until expiry
// (device 2026-09-05 15:50Z).
func TestCallRetrieveReturnsTerminateBehindAnUnackedInvite(t *testing.T) {
	now := time.Unix(1_800_000_000, 0).UTC()
	dispatcher := &callTestWakeDispatcher{}
	service, _ := callTestService(t, now, dispatcher)
	sender := callTestPeerID(t)
	recipient := callTestPeerID(t)
	authorizeCallFixture(t, service, now, sender, recipient)

	callTestStoreEvent(t, service, now, sender, recipient, callTestMessageA)
	if len(dispatcher.routes) != 1 {
		t.Fatalf("invite wake routes = %d, want 1", len(dispatcher.routes))
	}
	// The callee retrieves and presents natively without acknowledging.
	first, err := service.Retrieve(context.Background(), recipient, CallRetrieveRequest{CallHandle: callTestHandleA, Limit: 8})
	if err != nil || len(first.Events) != 1 {
		t.Fatalf("first Retrieve = %d events, err %v; want 1", len(first.Events), err)
	}
	callTestStoreEvent(t, service, now, sender, recipient, callTestMessageB)
	if len(dispatcher.routes) != 2 {
		t.Fatalf("terminate wake routes = %d, want 2", len(dispatcher.routes))
	}
	second, err := service.Retrieve(context.Background(), recipient, CallRetrieveRequest{CallHandle: callTestHandleA, Limit: 8})
	if err != nil {
		t.Fatalf("second Retrieve: %v", err)
	}
	got := make([]string, 0, len(second.Events))
	for _, event := range second.Events {
		got = append(got, event.MessageID)
	}
	if len(got) != 2 || got[0] != callTestMessageA || got[1] != callTestMessageB {
		t.Fatalf("second Retrieve message ids = %v, want [%s %s]", got, callTestMessageA, callTestMessageB)
	}
}
