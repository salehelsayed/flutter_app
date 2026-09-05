package main

import (
	"context"
	"testing"
	"time"
)

// authorizeIOSCallFixture mirrors authorizeCallFixture for an iOS recipient
// whose only call token is a VoIP token.
func authorizeIOSCallFixture(
	t *testing.T,
	service *CallControlService,
	now time.Time,
	sender string,
	recipient string,
) {
	t.Helper()
	ctx := context.Background()
	if err := service.backend.SetEndpoint(ctx, CallEndpointRecord{
		Schema: CallEndpointSchema, Version: CallControlVersion,
		AccountPeerID: recipient, DevicePeerID: recipient,
		Capabilities: []string{"voice_call_v1"}, Platform: "ios",
		ExpiresAtMs: now.Add(time.Hour).UnixMilli(), PreferenceEpoch: 1,
		DeviceKeyEpoch: 1, RoutingHandle: callTestHandleA,
		Signature: []byte("fixture-authorized-outside-service"),
	}, now); err != nil {
		t.Fatalf("SetEndpoint fixture: %v", err)
	}
	if err := service.SetWakeHandle(ctx, recipient, CallWakeHandleRecord{
		AuthorizedSenderPeerID: sender,
		WakeHandle:             callTestWake,
		ExpiresAtMs:            now.Add(time.Hour).UnixMilli(),
	}); err != nil {
		t.Fatalf("SetWakeHandle: %v", err)
	}
	if err := service.SetCallToken(ctx, recipient,
		callTestIOSVoIPToken("ios-voip-call-token-fixture", now.Add(time.Hour), 1)); err != nil {
		t.Fatalf("SetCallToken voip: %v", err)
	}
}

func callTestStoreEvent(
	t *testing.T,
	service *CallControlService,
	now time.Time,
	sender string,
	recipient string,
	messageID string,
) CallStoreReceipt {
	t.Helper()
	receipt, err := service.Store(context.Background(), sender, CallStoreRequest{
		RecipientDevicePeerID: recipient,
		CallHandle:            callTestHandleA,
		MessageID:             messageID,
		Envelope:              []byte("encrypted-" + messageID),
		ExpiresAtMs:           now.Add(45 * time.Second).UnixMilli(),
		WakeHandle:            callTestWake,
	})
	if err != nil {
		t.Fatalf("Store %s: %v", messageID, err)
	}
	if receipt.StoreStatus != CallStoreStatusStored {
		t.Fatalf("Store %s status = %v, want stored", messageID, receipt.StoreStatus)
	}
	return receipt
}

func callTestDrain(t *testing.T, service *CallControlService, recipient string, want ...string) {
	t.Helper()
	ctx := context.Background()
	result, err := service.Retrieve(ctx, recipient, CallRetrieveRequest{CallHandle: callTestHandleA, Limit: 8})
	if err != nil {
		t.Fatalf("Retrieve: %v", err)
	}
	got := make([]string, 0, len(result.Events))
	for _, event := range result.Events {
		got = append(got, event.MessageID)
	}
	if len(got) != len(want) {
		t.Fatalf("Retrieve message ids = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("Retrieve message ids = %v, want %v", got, want)
		}
	}
	if len(want) == 0 {
		return
	}
	if acked, err := service.Ack(ctx, recipient, CallAckRequest{CallHandle: callTestHandleA, MessageIDs: want}); err != nil || acked != len(want) {
		t.Fatalf("Ack = (%d, %v), want %d", acked, err, len(want))
	}
}

// An iOS recipient that drained every earlier event of a call is attached to
// it: its runtime is live on that call and drains the mailbox itself. A VoIP
// wake for a later control event would force CallKit to present a brand-new
// incoming call (the "rings again after hang-up" ghost), so the relay must
// keep the event and skip the wake.
func TestCallStoreSkipsIOSVoIPWakeForAnAttachedRecipient(t *testing.T) {
	now := time.Unix(1_800_000_000, 0).UTC()
	dispatcher := &callTestWakeDispatcher{}
	service, _ := callTestService(t, now, dispatcher)
	sender := callTestPeerID(t)
	recipient := callTestPeerID(t)
	authorizeIOSCallFixture(t, service, now, sender, recipient)

	callTestStoreEvent(t, service, now, sender, recipient, callTestMessageA)
	if len(dispatcher.routes) != 1 || dispatcher.routes[0].Kind != CallTokenKindIOSVoIP {
		t.Fatalf("invite wake routes = %#v, want one VoIP wake", dispatcher.routes)
	}
	callTestDrain(t, service, recipient, callTestMessageA)

	callTestStoreEvent(t, service, now, sender, recipient, callTestMessageB)
	if len(dispatcher.routes) != 1 {
		t.Fatalf("attached recipient wake routes = %#v, want no second VoIP wake", dispatcher.routes)
	}
	// The event itself is still delivered through the mailbox.
	callTestDrain(t, service, recipient, callTestMessageB)
}

func TestCallStoreWakesIOSVoIPAgainWhileEarlierEventsAreUnread(t *testing.T) {
	now := time.Unix(1_800_000_000, 0).UTC()
	dispatcher := &callTestWakeDispatcher{}
	service, _ := callTestService(t, now, dispatcher)
	sender := callTestPeerID(t)
	recipient := callTestPeerID(t)
	authorizeIOSCallFixture(t, service, now, sender, recipient)

	callTestStoreEvent(t, service, now, sender, recipient, callTestMessageA)
	callTestStoreEvent(t, service, now, sender, recipient, callTestMessageB)
	if len(dispatcher.routes) != 2 {
		t.Fatalf("unread recipient wake routes = %#v, want two VoIP wakes", dispatcher.routes)
	}
	callTestDrain(t, service, recipient, callTestMessageA, callTestMessageB)
}

// Android data-only wakes never present anything by themselves, so the
// standard route keeps waking for every stored event.
func TestCallStoreKeepsWakingAndroidForAnAttachedRecipient(t *testing.T) {
	now := time.Unix(1_800_000_000, 0).UTC()
	dispatcher := &callTestWakeDispatcher{}
	service, _ := callTestService(t, now, dispatcher)
	sender := callTestPeerID(t)
	recipient := callTestPeerID(t)
	authorizeCallFixture(t, service, now, sender, recipient)

	callTestStoreEvent(t, service, now, sender, recipient, callTestMessageA)
	callTestDrain(t, service, recipient, callTestMessageA)
	callTestStoreEvent(t, service, now, sender, recipient, callTestMessageB)
	if len(dispatcher.routes) != 2 || dispatcher.routes[1].Kind != CallTokenKindStandard {
		t.Fatalf("android attached recipient wake routes = %#v, want two standard wakes", dispatcher.routes)
	}
}
