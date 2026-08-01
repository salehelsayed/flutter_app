package main

import (
	"testing"
	"time"
)

// Plan 318 TC-318-10: gate-reachable closure over the single containment
// predicate (groupInboxMessageAuthorizedForPeer) that authorizes all three
// group retrieval verbs. Relay denial is silent filtering, so every negative
// below reads zero from a store proven non-empty by the paired positive.
func TestRelayNotificationClosure_GroupCustodyAclVerbs(t *testing.T) {
	store := NewGroupInboxStore(100, time.Hour)
	const groupId = "group-acl-verbs"

	mustStore := func(id string, recipients []string) {
		t.Helper()
		if err := store.StoreWithPushRecipients(
			groupId, "peer-alice", opaqueGroupReplayEnvelope(id), recipients,
		); err != nil {
			t.Fatalf("StoreWithPushRecipients(%s): %v", id, err)
		}
	}
	mustStore("msg-acl-1", []string{"peer-bob"})
	mustStore("msg-acl-2", []string{"peer-bob"})

	retrieveCount := func(peer string) int {
		return len(store.RetrieveAuthorized(groupId, 0, peer))
	}
	if got := retrieveCount("peer-bob"); got != 2 {
		t.Fatalf("recipient RetrieveAuthorized = %d, want 2", got)
	}
	if got := retrieveCount("peer-alice"); got != 2 {
		t.Fatalf("sender RetrieveAuthorized = %d, want 2 (From is always authorized)", got)
	}
	if got := retrieveCount("peer-eve"); got != 0 {
		t.Fatalf("absent-peer RetrieveAuthorized = %d, want 0 from a non-empty store", got)
	}

	bobPage, bobCursor, _ := store.RetrieveWithCursorAuthorized(groupId, "", 1, "peer-bob")
	if len(bobPage) != 1 || bobCursor == "" {
		t.Fatalf("recipient cursor page = %d messages, cursor %q; want 1 message and a non-empty cursor", len(bobPage), bobCursor)
	}
	evePage, eveCursor, _ := store.RetrieveWithCursorAuthorized(groupId, "", 1, "peer-eve")
	if len(evePage) != 0 || eveCursor != "" {
		t.Fatalf("absent-peer cursor page = %d messages, cursor %q; want 0 and empty", len(evePage), eveCursor)
	}

	bobRange, _, _ := store.RetrieveHistoryRepairRangeAuthorized(groupId, "", "", 10, "peer-bob")
	if len(bobRange) != 2 {
		t.Fatalf("recipient history-repair range = %d, want 2", len(bobRange))
	}
	eveRange, _, _ := store.RetrieveHistoryRepairRangeAuthorized(groupId, "", "", 10, "peer-eve")
	if len(eveRange) != 0 {
		t.Fatalf("absent-peer history-repair range = %d, want 0 from a non-empty store", len(eveRange))
	}
}
