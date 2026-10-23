//go:build integration

package main

import (
	"context"
	"testing"
	"time"
)

func TestDirectTextCheckpointHoldsCommittedRedisCustodyUntilRelease(t *testing.T) {
	fixture, err := startDirectMediaDeviceFixture(t.TempDir(), "127.0.0.1", directMediaDeviceFixtureOptions{textSendCheckpoint: true})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if err := fixture.Close(); err != nil {
			t.Error(err)
		}
	})
	gate := fixture.textCheckpoint
	t.Cleanup(gate.releaseHeld)
	fixture.stores.Inbox.SetAckCustodyAdmissionEnabled(true)
	const recipient = "fixture-recipient"
	message := ackCustodyTextEnvelope("checkpoint-message", "fixture-sender", "opaque")
	if err := gate.arm(directTextCheckpointHash(recipient)); err != nil {
		t.Fatal(err)
	}
	type outcome struct {
		result InboxStoreResult
		err    error
	}
	done := make(chan outcome, 1)
	go func() {
		result, _, err := fixture.stores.Inbox.StoreAckCustody(recipient, inboxMessage{From: "fixture-sender", Message: message, Timestamp: time.Now().UnixMilli()}, ackCustodyDirectTextKind)
		done <- outcome{result, err}
	}()
	deadline := time.Now().Add(2 * time.Second)
	for !gate.snapshot().Held && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	if !gate.snapshot().Held {
		t.Fatal("real committed-store checkpoint was not reached")
	}
	if got := fixture.stores.InboxBackend.Count(recipient); got != 1 {
		t.Fatalf("committed custody count = %d", got)
	}
	if got := fixture.stores.Inbox.CountAckCustody(recipient); got != 1 {
		t.Fatalf("protected custody count = %d", got)
	}
	if gate.snapshot().MessageSHA256 != directTextCheckpointHash("checkpoint-message") {
		t.Fatal("wrong logical identity held")
	}
	select {
	case <-done:
		t.Fatal("store acknowledged before checkpoint release")
	default:
	}
	gate.releaseHeld()
	select {
	case result := <-done:
		if result.err != nil || result.result != InboxStoreResultStored {
			t.Fatal("released real store did not return stored")
		}
	case <-time.After(2 * time.Second):
		t.Fatal("release did not unblock the owned store")
	}
	if got := fixture.stores.InboxBackend.Count(recipient); got != 1 {
		t.Fatal("release changed committed custody")
	}
	if err := gate.arm(directTextCheckpointHash(recipient)); err == nil {
		t.Fatal("one-shot checkpoint unexpectedly rearmed")
	}
}

func TestDirectTextCheckpointCancellationCannotUndoCommittedCustody(t *testing.T) {
	fixture, err := startDirectMediaDeviceFixture(t.TempDir(), "127.0.0.1", directMediaDeviceFixtureOptions{})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if err := fixture.Close(); err != nil {
			t.Error(err)
		}
	})
	base, ok := fixture.stores.InboxBackend.(*redisInboxBackend)
	if !ok {
		t.Fatal("fixture must use the production Redis backend")
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	gate := newDirectTextSendCheckpoint(ctx)
	backend := &directTextCheckpointRedisBackend{redisInboxBackend: base, gate: gate}
	const recipient = "fixture-cancel-recipient"
	if err := gate.arm(directTextCheckpointHash(recipient)); err != nil {
		t.Fatal(err)
	}
	message := ackCustodyTextEnvelope("cancel-message", "fixture-sender", "opaque")
	dedupeKey, eligible := extractAckCustodyDedupeKeyForRecipient(ackCustodyDirectTextKind, message, "fixture-sender", recipient)
	if !eligible {
		t.Fatal("protected direct-text fixture must be eligible")
	}
	done := make(chan error, 1)
	go func() {
		_, _, err := backend.StoreAckCustody(recipient, inboxMessage{From: "fixture-sender", Message: message, Timestamp: time.Now().UnixMilli()}, dedupeKey)
		done <- err
	}()
	deadline := time.Now().Add(2 * time.Second)
	for !gate.snapshot().Held && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	if !gate.snapshot().Held {
		t.Fatal("checkpoint not reached")
	}
	cancel()
	select {
	case err := <-done:
		if err == nil {
			t.Fatal("cancelled checkpoint unexpectedly acknowledged")
		}
	case <-time.After(2 * time.Second):
		t.Fatal("cancelled checkpoint leaked its writer")
	}
	if got := base.Count(recipient); got != 1 {
		t.Fatal("cancellation undid committed custody")
	}
	if got := base.CountAckCustody(recipient); got != 1 {
		t.Fatal("cancellation undid protected custody")
	}
}
