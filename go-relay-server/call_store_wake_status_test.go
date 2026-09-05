package main

import (
	"context"
	"errors"
	"testing"
	"time"
)

// The store receipt reports what became of the wake, so a caller can ring
// back as soon as the callee's device was alerted (a headless Android callee
// never signals `ringing` before it is answered) and can see a failed or
// absent wake instead of waiting for the invite to expire.
func TestCallStoreReceiptReportsTheWakeOutcome(t *testing.T) {
	now := time.Unix(1_800_000_000, 0).UTC()

	dispatched := &callTestWakeDispatcher{}
	service, _ := callTestService(t, now, dispatched)
	sender := callTestPeerID(t)
	recipient := callTestPeerID(t)
	authorizeCallFixture(t, service, now, sender, recipient)
	receipt := callTestStoreEvent(t, service, now, sender, recipient, callTestMessageA)
	if receipt.WakeStatus != CallWakeStatusDispatched || len(dispatched.routes) != 1 {
		t.Fatalf("dispatched wake receipt = %q routes=%d, want dispatched/1", receipt.WakeStatus, len(dispatched.routes))
	}

	failing := &callTestWakeDispatcher{err: errors.New("provider down")}
	service, _ = callTestService(t, now, failing)
	sender = callTestPeerID(t)
	recipient = callTestPeerID(t)
	authorizeCallFixture(t, service, now, sender, recipient)
	receipt = callTestStoreEvent(t, service, now, sender, recipient, callTestMessageA)
	if receipt.WakeStatus != CallWakeStatusFailed {
		t.Fatalf("failed wake receipt = %q, want failed", receipt.WakeStatus)
	}

	// An attached iOS recipient gets no wake at all: the receipt says so.
	attached := &callTestWakeDispatcher{}
	service, _ = callTestService(t, now, attached)
	sender = callTestPeerID(t)
	recipient = callTestPeerID(t)
	authorizeIOSCallFixture(t, service, now, sender, recipient)
	callTestStoreEvent(t, service, now, sender, recipient, callTestMessageA)
	callTestDrain(t, service, recipient, callTestMessageA)
	receipt = callTestStoreEvent(t, service, now, sender, recipient, callTestMessageB)
	if receipt.WakeStatus != "" || len(attached.routes) != 1 {
		t.Fatalf("attached recipient wake receipt = %q routes=%d, want empty/1", receipt.WakeStatus, len(attached.routes))
	}
	_ = context.Background()
}
