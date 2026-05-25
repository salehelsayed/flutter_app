package main

import (
	"encoding/json"
	"fmt"
	"reflect"
	"strings"
	"testing"
	"time"
)

func opaqueGroupReplayEnvelope(messageID string) string {
	return fmt.Sprintf(
		`{"kind":"group_offline_replay","version":1,"payloadType":"group_message","keyEpoch":4,"messageId":"%s","ciphertext":"opaque-ciphertext-%s","nonce":"opaque-nonce-%s"}`,
		messageID,
		messageID,
		messageID,
	)
}

type recordingGroupInboxBackend struct {
	lastRecipientPeerIds []string
	messages             []groupInboxMessage
}

func (b *recordingGroupInboxBackend) Store(groupId string, from string, message string) error {
	return fmt.Errorf("legacy Store should not be called")
}

func (b *recordingGroupInboxBackend) StoreWithRecipients(
	groupId string,
	from string,
	message string,
	recipientPeerIds []string,
) error {
	b.lastRecipientPeerIds = append([]string(nil), recipientPeerIds...)
	b.messages = append(b.messages, groupInboxMessage{
		From:             from,
		Message:          message,
		Timestamp:        time.Now().UnixMilli(),
		ID:               fmt.Sprintf("%d", len(b.messages)+1),
		RecipientPeerIds: append([]string(nil), recipientPeerIds...),
	})
	return nil
}

func (b *recordingGroupInboxBackend) RetrieveSince(groupId string, sinceTimestamp int64) []groupInboxMessage {
	result := make([]groupInboxMessage, 0, len(b.messages))
	for _, message := range b.messages {
		if sinceTimestamp > 0 && message.Timestamp <= sinceTimestamp {
			continue
		}
		result = append(result, message)
	}
	return result
}

func (b *recordingGroupInboxBackend) RetrieveCursor(groupId string, cursor string, limit int) ([]groupInboxMessage, string, []groupInboxHistoryGap) {
	if limit <= 0 {
		return nil, "", nil
	}
	messages := b.RetrieveSince(groupId, 0)
	if len(messages) > limit {
		return messages[:limit], messages[limit-1].ID, nil
	}
	return messages, "", nil
}

func (b *recordingGroupInboxBackend) Prune() {}

func (b *recordingGroupInboxBackend) Stats() (groups int, totalMessages int) {
	if len(b.messages) == 0 {
		return 0, 0
	}
	return 1, len(b.messages)
}

func TestGroupInboxBackendContractRequiresRecipientStore(t *testing.T) {
	backendType := reflect.TypeOf((*GroupInboxBackend)(nil)).Elem()

	storeWithRecipients, ok := backendType.MethodByName("StoreWithRecipients")
	if !ok {
		t.Fatal("GroupInboxBackend must require StoreWithRecipients")
	}
	wantType := reflect.TypeOf(func(string, string, string, []string) error { return nil })
	if storeWithRecipients.Type != wantType {
		t.Fatalf("StoreWithRecipients type = %v, want %v", storeWithRecipients.Type, wantType)
	}

	if _, ok := backendType.MethodByName("Store"); ok {
		t.Fatal("GroupInboxBackend must not expose legacy Store without recipient ACLs")
	}
}

func TestGroupInboxStorePassesRecipientACLToBackendContract(t *testing.T) {
	backend := &recordingGroupInboxBackend{}
	store := NewGroupInboxStoreWithBackend(backend)

	if err := store.StoreWithPushRecipients(
		"group-acl-contract",
		"peer-a",
		"msg-acl-contract",
		[]string{"peer-b", "", "peer-b", "peer-c"},
	); err != nil {
		t.Fatalf("StoreWithPushRecipients: %v", err)
	}

	wantRecipients := []string{"peer-b", "peer-c"}
	if !reflect.DeepEqual(backend.lastRecipientPeerIds, wantRecipients) {
		t.Fatalf("backend recipients = %#v, want %#v", backend.lastRecipientPeerIds, wantRecipients)
	}

	for _, peerId := range wantRecipients {
		messages := store.RetrieveAuthorized("group-acl-contract", 0, peerId)
		if len(messages) != 1 {
			t.Fatalf("RetrieveAuthorized(%q) returned %d message(s), want 1", peerId, len(messages))
		}
	}
	if messages := store.RetrieveAuthorized("group-acl-contract", 0, "peer-d"); len(messages) != 0 {
		t.Fatalf("unauthorized peer retrieved %#v, want none", messages)
	}
}

func TestGroupInboxStoreStoreHelperUsesSenderACL(t *testing.T) {
	store := NewGroupInboxStore(500, 7*24*time.Hour)

	if err := store.Store("group-store-helper", "peer-a", "msg-helper"); err != nil {
		t.Fatalf("Store: %v", err)
	}

	messages := store.Retrieve("group-store-helper", 0)
	if len(messages) != 1 {
		t.Fatalf("messages = %d, want 1", len(messages))
	}
	wantRecipients := []string{"peer-a"}
	if !reflect.DeepEqual(messages[0].RecipientPeerIds, wantRecipients) {
		t.Fatalf("RecipientPeerIds = %#v, want %#v", messages[0].RecipientPeerIds, wantRecipients)
	}
}

func TestMemoryGroupInboxBackendStoreHelperUsesSenderACL(t *testing.T) {
	backend := newMemoryGroupInboxBackend(500, 7*24*time.Hour)

	if err := backend.Store("group-memory-helper", "peer-a", "msg-helper"); err != nil {
		t.Fatalf("Store: %v", err)
	}

	messages := backend.RetrieveSince("group-memory-helper", 0)
	if len(messages) != 1 {
		t.Fatalf("messages = %d, want 1", len(messages))
	}
	wantRecipients := []string{"peer-a"}
	if !reflect.DeepEqual(messages[0].RecipientPeerIds, wantRecipients) {
		t.Fatalf("RecipientPeerIds = %#v, want %#v", messages[0].RecipientPeerIds, wantRecipients)
	}
}

// =============================================================================
// Phase 2: Shared Relay Control State — Group Inbox Store tests
// =============================================================================

func TestGroupInboxStore_PreservesOpaqueReplayEnvelopeAcrossInstances(t *testing.T) {
	backend := newMemoryGroupInboxBackend(500, 7*24*time.Hour)
	storeA := NewGroupInboxStoreWithBackend(backend)
	storeB := NewGroupInboxStoreWithBackend(backend)

	envelope1 := opaqueGroupReplayEnvelope("msg-opaque-001")
	envelope2 := opaqueGroupReplayEnvelope("msg-opaque-002")

	if err := storeA.Store("group-opaque", "peer-1", envelope1); err != nil {
		t.Fatalf("Store envelope1: %v", err)
	}
	if err := storeA.Store("group-opaque", "peer-1", envelope2); err != nil {
		t.Fatalf("Store envelope2: %v", err)
	}

	msgs := storeB.Retrieve("group-opaque", 0)
	if len(msgs) != 2 {
		t.Fatalf("expected 2 opaque replay envelopes, got %d", len(msgs))
	}
	if msgs[0].Message != envelope1 {
		t.Fatalf("first message = %q, want exact envelope %q", msgs[0].Message, envelope1)
	}
	if msgs[1].Message != envelope2 {
		t.Fatalf("second message = %q, want exact envelope %q", msgs[1].Message, envelope2)
	}
}

func TestGI035GroupInboxStorePersistsEncryptedEnvelopeWithoutPlaintext(t *testing.T) {
	backend := newMemoryGroupInboxBackend(500, 7*24*time.Hour)
	store := NewGroupInboxStoreWithBackend(backend)

	message := `{"kind":"group_offline_replay","version":1,"payloadType":"group_message","keyEpoch":4,"messageId":"gi035-private","senderPeerId":"peer-a","recipientSetHash":"hash-gi035","ciphertext":"opaque-ciphertext-gi035","nonce":"opaque-nonce-gi035","signatureAlgorithm":"ed25519","signedPayload":"signed-gi035","signature":"sig-gi035"}`
	sensitiveFragments := []string{
		"GI-035 private body alpha",
		"gi035-media-key-secret-beta",
		"gi035-media-url-secret-gamma",
		"gi035-delivery-secret-delta",
		"pushTitle",
		"pushBody",
	}

	if err := store.StoreWithPushRecipients(
		"group-gi-035",
		"peer-a",
		message,
		[]string{"peer-b"},
	); err != nil {
		t.Fatalf("StoreWithPushRecipients: %v", err)
	}

	messages, nextCursor, historyGaps := store.RetrieveWithCursorAuthorized(
		"group-gi-035",
		"",
		50,
		"peer-b",
	)
	if nextCursor != "" {
		t.Fatalf("nextCursor = %q, want empty", nextCursor)
	}
	if len(historyGaps) != 0 {
		t.Fatalf("historyGaps = %#v, want none", historyGaps)
	}
	if len(messages) != 1 {
		t.Fatalf("messages = %#v, want one stored envelope", messages)
	}
	if messages[0].Message != message {
		t.Fatalf("stored message = %q, want exact encrypted envelope %q", messages[0].Message, message)
	}
	if messages[0].From != "peer-a" {
		t.Fatalf("from = %q, want peer-a", messages[0].From)
	}

	rawStored, err := json.Marshal(messages[0])
	if err != nil {
		t.Fatalf("marshal stored message: %v", err)
	}
	raw := string(rawStored)
	for _, fragment := range sensitiveFragments {
		if strings.Contains(raw, fragment) {
			t.Fatalf("stored relay message leaked plaintext fragment %q in %s", fragment, raw)
		}
	}

	var storedEnvelope map[string]json.RawMessage
	if err := json.Unmarshal([]byte(messages[0].Message), &storedEnvelope); err != nil {
		t.Fatalf("unmarshal stored envelope: %v", err)
	}
	for _, forbiddenKey := range []string{"text", "media", "mediaKey", "mediaUrl", "deliveryId"} {
		if _, ok := storedEnvelope[forbiddenKey]; ok {
			t.Fatalf("stored envelope contains plaintext key %q: %s", forbiddenKey, messages[0].Message)
		}
	}
	if _, ok := storedEnvelope["ciphertext"]; !ok {
		t.Fatalf("stored envelope missing ciphertext: %s", messages[0].Message)
	}
	if _, ok := storedEnvelope["nonce"]; !ok {
		t.Fatalf("stored envelope missing nonce: %s", messages[0].Message)
	}
}

// TestGroupInboxStore_RetrieveBySinceTimestampAcrossInstances proves that
// messages stored through one GroupInboxStore instance are visible via
// sinceTimestamp filtering on another instance sharing the same backend.
func TestGroupInboxStore_RetrieveBySinceTimestampAcrossInstances(t *testing.T) {
	backend := newMemoryGroupInboxBackend(500, 7*24*time.Hour)
	storeA := NewGroupInboxStoreWithBackend(backend)
	storeB := NewGroupInboxStoreWithBackend(backend)

	// Store first message through A.
	storeA.Store("group-1", "peer-1", "msg-old")

	// Record a timestamp boundary.
	time.Sleep(2 * time.Millisecond)
	sinceTs := time.Now().UnixMilli()
	time.Sleep(2 * time.Millisecond)

	// Store second message through A.
	storeA.Store("group-1", "peer-1", "msg-new")

	// Retrieve from B with sinceTimestamp.
	msgs := storeB.Retrieve("group-1", sinceTs)
	if len(msgs) != 1 {
		t.Fatalf("expected 1 message since timestamp from B, got %d", len(msgs))
	}
	if msgs[0].Message != "msg-new" {
		t.Fatalf("expected 'msg-new', got %q", msgs[0].Message)
	}

	// Retrieve all from B (sinceTimestamp=0).
	allMsgs := storeB.Retrieve("group-1", 0)
	if len(allMsgs) != 2 {
		t.Fatalf("expected 2 total messages from B, got %d", len(allMsgs))
	}
}

// TestGroupInboxStore_PruneUsesSharedBackendTTL proves that pruning on
// one store instance removes expired messages visible to another instance.
func TestGroupInboxStore_PruneUsesSharedBackendTTL(t *testing.T) {
	backend := newMemoryGroupInboxBackend(500, 50*time.Millisecond)
	storeA := NewGroupInboxStoreWithBackend(backend)
	storeB := NewGroupInboxStoreWithBackend(backend)

	// Store through A.
	storeA.Store("group-1", "peer-1", "will expire")

	// Verify visible through B.
	msgs := storeB.Retrieve("group-1", 0)
	if len(msgs) != 1 {
		t.Fatalf("expected 1 message before TTL, got %d", len(msgs))
	}

	// Wait for TTL to expire.
	time.Sleep(100 * time.Millisecond)

	// Prune through instance A.
	storeA.Prune()

	// Verify gone from instance B.
	msgs = storeB.Retrieve("group-1", 0)
	if len(msgs) != 0 {
		t.Fatalf("expected 0 messages after TTL prune from B, got %d", len(msgs))
	}

	// Stats should be consistent.
	gA, mA := storeA.Stats()
	gB, mB := storeB.Stats()
	if gA != gB || mA != mB {
		t.Fatalf("stats mismatch: A(%d/%d) vs B(%d/%d)", gA, mA, gB, mB)
	}
}

// TestGroupInboxStore_FailoverDoesNotDuplicateMessages proves that when
// messages are stored through one instance and retrieved through another
// (simulating failover), no messages are duplicated.
func TestGroupInboxStore_FailoverDoesNotDuplicateMessages(t *testing.T) {
	backend := newMemoryGroupInboxBackend(500, 7*24*time.Hour)
	storeA := NewGroupInboxStoreWithBackend(backend)
	storeB := NewGroupInboxStoreWithBackend(backend)

	// Store 3 messages through A.
	for i := 0; i < 3; i++ {
		storeA.Store("group-1", "peer-1", fmt.Sprintf("msg-%d", i))
	}

	// Retrieve all from B (simulating failover — A goes down, B takes over).
	msgs := storeB.Retrieve("group-1", 0)
	if len(msgs) != 3 {
		t.Fatalf("expected 3 messages, got %d", len(msgs))
	}

	// Verify no duplicates: messages are distinct.
	seen := make(map[string]bool)
	for _, m := range msgs {
		if seen[m.Message] {
			t.Fatalf("duplicate message detected: %q", m.Message)
		}
		seen[m.Message] = true
	}

	// Retrieve again from A — messages should still be there (non-destructive).
	msgs2 := storeA.Retrieve("group-1", 0)
	if len(msgs2) != 3 {
		t.Fatalf("expected 3 messages on second retrieve from A, got %d", len(msgs2))
	}
}

// =============================================================================
// Phase 6: Group Continuity — Exactly-Once Cursor Pagination
// =============================================================================

// TestGroupInboxStore_CursorPaginationExactOnceAcrossPages proves that
// cursor-based pagination delivers every message exactly once, even when
// paginating across multiple pages with varying page sizes.
func TestGroupInboxStore_CursorPaginationExactOnceAcrossPages(t *testing.T) {
	backend := newMemoryGroupInboxBackend(500, 7*24*time.Hour)
	store := NewGroupInboxStoreWithBackend(backend)

	// Store 25 messages.
	for i := 0; i < 25; i++ {
		store.Store("group-exact", "peer-1", fmt.Sprintf("msg-%03d", i))
		time.Sleep(1 * time.Millisecond)
	}

	// Paginate with page size 7 (25 / 7 = 3 full pages + 1 partial).
	var allMessages []groupInboxMessage
	cursor := ""
	pageCount := 0
	for {
		msgs, nextCursor, _ := store.RetrieveWithCursor("group-exact", cursor, 7)
		if len(msgs) == 0 {
			break
		}
		allMessages = append(allMessages, msgs...)
		pageCount++
		if nextCursor == "" {
			break
		}
		cursor = nextCursor
	}

	// Exactly 25 messages across all pages.
	if len(allMessages) != 25 {
		t.Fatalf("expected 25 messages total, got %d (across %d pages)", len(allMessages), pageCount)
	}

	// Verify order is FIFO and no duplicates.
	seen := make(map[string]bool)
	for i, m := range allMessages {
		expected := fmt.Sprintf("msg-%03d", i)
		if m.Message != expected {
			t.Fatalf("message %d: expected %q, got %q", i, expected, m.Message)
		}
		if seen[m.ID] {
			t.Fatalf("duplicate message ID detected at position %d: %q", i, m.ID)
		}
		seen[m.ID] = true
	}

	// Re-paginating from the beginning should return the same messages.
	var secondPass []groupInboxMessage
	cursor = ""
	for {
		msgs, nextCursor, _ := store.RetrieveWithCursor("group-exact", cursor, 10)
		if len(msgs) == 0 {
			break
		}
		secondPass = append(secondPass, msgs...)
		if nextCursor == "" {
			break
		}
		cursor = nextCursor
	}

	if len(secondPass) != 25 {
		t.Fatalf("second pass: expected 25 messages, got %d", len(secondPass))
	}
	for i, m := range secondPass {
		if m.ID != allMessages[i].ID {
			t.Fatalf("second pass message %d: ID mismatch %q vs %q", i, m.ID, allMessages[i].ID)
		}
	}
}

func TestGI017GroupInboxStoreAuthorizedCursorPaginationReturns120MessagesExactlyOnce(t *testing.T) {
	backend := newMemoryGroupInboxBackend(200, 7*24*time.Hour)
	store := NewGroupInboxStoreWithBackend(backend)

	for i := 0; i < 120; i++ {
		message := fmt.Sprintf("gi017-msg-%03d", i)
		if err := store.StoreWithPushRecipients(
			"group-gi-017",
			"peer-a",
			message,
			[]string{"peer-b"},
		); err != nil {
			t.Fatalf("StoreWithPushRecipients(%d): %v", i, err)
		}
	}

	var allMessages []groupInboxMessage
	cursor := ""
	pageCount := 0
	for {
		messages, nextCursor, _ := store.RetrieveWithCursorAuthorized(
			"group-gi-017",
			cursor,
			50,
			"peer-b",
		)
		if len(messages) == 0 {
			break
		}
		if len(messages) > 50 {
			t.Fatalf("page %d returned %d messages, want <= 50", pageCount+1, len(messages))
		}
		allMessages = append(allMessages, messages...)
		pageCount++
		if nextCursor == "" {
			break
		}
		cursor = nextCursor
	}

	if pageCount != 3 {
		t.Fatalf("page count = %d, want 3", pageCount)
	}
	if len(allMessages) != 120 {
		t.Fatalf("message count = %d, want 120", len(allMessages))
	}

	seenIDs := map[string]bool{}
	for i, message := range allMessages {
		wantMessage := fmt.Sprintf("gi017-msg-%03d", i)
		if message.Message != wantMessage {
			t.Fatalf("message[%d] = %q, want %q", i, message.Message, wantMessage)
		}
		if message.From != "peer-a" {
			t.Fatalf("message[%d].From = %q, want peer-a", i, message.From)
		}
		if !groupInboxMessageAuthorizedForPeer(message, "peer-b") {
			t.Fatalf("message[%d] is not authorized for peer-b: %#v", i, message)
		}
		if seenIDs[message.ID] {
			t.Fatalf("duplicate message ID at index %d: %q", i, message.ID)
		}
		seenIDs[message.ID] = true
	}

	unauthorized, nextCursor, _ := store.RetrieveWithCursorAuthorized(
		"group-gi-017",
		"",
		50,
		"peer-c",
	)
	if len(unauthorized) != 0 || nextCursor != "" {
		t.Fatalf("unauthorized retrieve = (%d, %q), want empty", len(unauthorized), nextCursor)
	}
}

// TestGroupInboxStore_CursorPaginationStableAcrossInstances proves that
// cursor-based pagination works across different store instances and
// delivers messages in stable order without duplication or omission.
func TestGroupInboxStore_CursorPaginationStableAcrossInstances(t *testing.T) {
	backend := newMemoryGroupInboxBackend(500, 7*24*time.Hour)
	storeA := NewGroupInboxStoreWithBackend(backend)
	storeB := NewGroupInboxStoreWithBackend(backend)

	// Store 10 messages through A.
	for i := 0; i < 10; i++ {
		storeA.Store("group-1", "peer-1", fmt.Sprintf("msg-%02d", i))
		time.Sleep(1 * time.Millisecond)
	}

	// Paginate through B with page size 3.
	var allMessages []groupInboxMessage
	cursor := ""
	pageCount := 0
	for {
		msgs, nextCursor, _ := storeB.RetrieveWithCursor("group-1", cursor, 3)
		if len(msgs) == 0 {
			break
		}
		allMessages = append(allMessages, msgs...)
		pageCount++
		if nextCursor == "" {
			break
		}
		cursor = nextCursor
	}

	// Should have collected all 10 messages.
	if len(allMessages) != 10 {
		t.Fatalf("expected 10 messages total across pages, got %d", len(allMessages))
	}

	// Verify order is preserved (FIFO).
	for i, m := range allMessages {
		expected := fmt.Sprintf("msg-%02d", i)
		if m.Message != expected {
			t.Fatalf("message %d: expected %q, got %q", i, expected, m.Message)
		}
	}

	// Verify no duplicates.
	seen := make(map[string]bool)
	for _, m := range allMessages {
		if seen[m.ID] {
			t.Fatalf("duplicate message ID detected: %q", m.ID)
		}
		seen[m.ID] = true
	}
}
