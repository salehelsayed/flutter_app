package main

import (
	"fmt"
	"testing"
	"time"
)

func directChatCustodyEnvelope(targetID, eventID string) string {
	eventField := ""
	if eventID != "" {
		eventField = fmt.Sprintf(`,"eventId":%q`, eventID)
	}
	return fmt.Sprintf(
		`{"type":"chat_message","version":"2","id":%q%s,"senderPeerId":"peer-sender","encrypted":{"kem":"k","ciphertext":%q,"nonce":"n"}}`,
		targetID,
		eventField,
		"ciphertext-"+eventID,
	)
}

func requireDirectInboxBackendResult(
	t *testing.T,
	backend InboxBackend,
	peerID string,
	message string,
	want InboxStoreResult,
) {
	t.Helper()

	got, err := backend.Store(peerID, inboxMessage{
		From:      "peer-sender",
		Message:   message,
		Timestamp: time.Now().UnixMilli(),
	})
	if err != nil {
		t.Fatalf("Store() error: %v", err)
	}
	if got != want {
		t.Fatalf("Store() result = %q, want %q", got, want)
	}
}

func assertDirectChatEditDedupeOrder(
	t *testing.T,
	backend InboxBackend,
	order []string,
) {
	t.Helper()

	const peerID = "peer-recipient"
	for _, message := range order {
		requireDirectInboxBackendResult(
			t,
			backend,
			peerID,
			message,
			InboxStoreResultStored,
		)
	}

	// An exact replay of an edit retains the established duplicate result.
	requireDirectInboxBackendResult(
		t,
		backend,
		peerID,
		order[1],
		InboxStoreResultDuplicate,
	)
	if got := backend.Count(peerID); got != 3 {
		t.Fatalf("pending direct inbox rows = %d, want 3", got)
	}
}

func TestMemoryDirectInboxChatEditsUseDistinctEventCustodyKeysInCrossedOrders(t *testing.T) {
	initial := directChatCustodyEnvelope("target-1", "")
	// Deliberately reuse the target string as one event ID. The target/event
	// namespaces, not just different UUID values, must prevent this collision.
	editA := directChatCustodyEnvelope("target-1", "target-1")
	editB := directChatCustodyEnvelope("target-1", "edit-event-b")

	tests := []struct {
		name  string
		order []string
	}{
		{name: "initial then edits", order: []string{initial, editA, editB}},
		{name: "edits then initial", order: []string{editB, editA, initial}},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			assertDirectChatEditDedupeOrder(t, newMemoryInboxBackend(), tc.order)
		})
	}
}

func TestLimitedMemoryDirectInboxEditDedupeSurvivesCapacityRebuild(t *testing.T) {
	backend := newMemoryInboxBackendWithLimits(2)
	const peerID = "peer-recipient"
	initial := directChatCustodyEnvelope("target-limited", "")
	editA := directChatCustodyEnvelope("target-limited", "limited-edit-a")
	editB := directChatCustodyEnvelope("target-limited", "limited-edit-b")

	requireDirectInboxBackendResult(t, backend, peerID, initial, InboxStoreResultStored)
	requireDirectInboxBackendResult(t, backend, peerID, editA, InboxStoreResultStored)
	// Evicts initial and rebuilds the cached custody-key set before appending B.
	requireDirectInboxBackendResult(t, backend, peerID, editB, InboxStoreResultStored)
	requireDirectInboxBackendResult(t, backend, peerID, editA, InboxStoreResultDuplicate)

	// The evicted target key must not survive the rebuild.
	requireDirectInboxBackendResult(t, backend, peerID, initial, InboxStoreResultStored)
	if got := backend.Count(peerID); got != 2 {
		t.Fatalf("pending limited inbox rows = %d, want 2", got)
	}
}

func TestMemoryDirectInboxEditDedupeSurvivesAckRebuild(t *testing.T) {
	backend := newMemoryInboxBackend()
	const peerID = "peer-recipient"
	initial := directChatCustodyEnvelope("target-ack", "")
	editA := directChatCustodyEnvelope("target-ack", "ack-edit-a")
	editB := directChatCustodyEnvelope("target-ack", "ack-edit-b")

	requireDirectInboxBackendResult(t, backend, peerID, initial, InboxStoreResultStored)
	requireDirectInboxBackendResult(t, backend, peerID, editA, InboxStoreResultStored)
	requireDirectInboxBackendResult(t, backend, peerID, editB, InboxStoreResultStored)

	pending, _ := backend.RetrievePending(peerID, 10)
	if len(pending) != 3 {
		t.Fatalf("pending before ack = %d, want 3", len(pending))
	}
	if removed, err := backend.Ack(peerID, []string{pending[0].ID}); err != nil || removed != 1 {
		t.Fatalf("Ack(initial) = %d, %v; want 1, nil", removed, err)
	}
	requireDirectInboxBackendResult(t, backend, peerID, editA, InboxStoreResultDuplicate)

	if removed, err := backend.Ack(peerID, []string{pending[1].ID}); err != nil || removed != 1 {
		t.Fatalf("Ack(edit A) = %d, %v; want 1, nil", removed, err)
	}
	requireDirectInboxBackendResult(t, backend, peerID, editA, InboxStoreResultStored)
}

func TestDirectInboxLegacyChatEditWithoutEventIDKeepsTargetSemantics(t *testing.T) {
	initial := directChatCustodyEnvelope("legacy-target", "")
	legacyEdit := `{"type":"chat_message","version":"2","id":"legacy-target","editedAt":"2026-08-07T10:00:00Z","senderPeerId":"peer-sender","encrypted":{"kem":"k","ciphertext":"legacy-edit","nonce":"n"}}`

	for _, tc := range []struct {
		name  string
		first string
		next  string
	}{
		{name: "initial then legacy edit", first: initial, next: legacyEdit},
		{name: "legacy edit then initial", first: legacyEdit, next: initial},
	} {
		t.Run(tc.name, func(t *testing.T) {
			backend := newMemoryInboxBackend()
			requireDirectInboxBackendResult(t, backend, "peer-recipient", tc.first, InboxStoreResultStored)
			requireDirectInboxBackendResult(t, backend, "peer-recipient", tc.next, InboxStoreResultDuplicate)
		})
	}
}

func TestDirectInboxEditEventDoesNotChangePushTargetMessageID(t *testing.T) {
	message := directChatCustodyEnvelope("push-target", "push-edit-event")

	if got := extractMessageId(message); got != "push-target" {
		t.Fatalf("extractMessageId() = %q, want target ID", got)
	}
	metadata := extractChatPushMetadata(message)
	if !metadata.ShouldNotify || metadata.RouteType != "new_message" {
		t.Fatalf("chat push metadata routing changed: %#v", metadata)
	}
	if metadata.MessageID != "push-target" {
		t.Fatalf("push message_id = %q, want target ID", metadata.MessageID)
	}
	if got := extractDirectInboxDedupeKey(message); got != directInboxEditEventIDDedupePrefix+"push-edit-event" {
		t.Fatalf("direct inbox dedupe key = %q, want edit event key", got)
	}
}
