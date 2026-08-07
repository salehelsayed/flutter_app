package main

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/libp2p/go-libp2p/core/host"
)

func sendInboxAction(
	t *testing.T,
	from host.Host,
	server host.Host,
	req inboxRequest,
) inboxResponse {
	t.Helper()
	stream, err := from.NewStream(context.Background(), server.ID(), InboxProtocol)
	if err != nil {
		t.Fatalf("open %s stream: %v", req.Action, err)
	}
	defer stream.Close()
	sendInboxReq(t, stream, req)
	return recvInboxResp(t, stream)
}

func TestRelayNotificationClosure_AckCustodyRetrievalAndAckIsolation(t *testing.T) {
	t.Run("global_fifo_coalescing_and_legacy_isolation", func(t *testing.T) {
		server := miniredis.RunT(t)
		backend := newAckCustodyRedisBackend(t, server, "ack-retrieve:", 10)
		const (
			peerID = "peer-recipient"
			sender = "peer-sender"
		)
		base := time.Now().Add(-time.Hour)

		legacyOldest := inboxMessage{
			ID:        "relay-legacy-oldest",
			From:      sender,
			Message:   "legacy-only-oldest",
			Timestamp: base.Add(time.Second).UnixMilli(),
		}
		if result, err := backend.Store(peerID, legacyOldest); err != nil || result != InboxStoreResultStored {
			t.Fatalf("store oldest legacy-only = (%q, %v)", result, err)
		}
		protectedFirst := inboxMessage{
			ID:        "relay-protected-first",
			From:      sender,
			Message:   ackCustodyTextEnvelope("protected-first", sender, "first"),
			Timestamp: base.Add(2 * time.Second).UnixMilli(),
		}
		requireAckCustodyBackendStore(
			t,
			backend,
			peerID,
			protectedFirst,
			directInboxTargetIDDedupePrefix+"protected-first",
			InboxStoreResultStored,
		)
		legacyMiddle := inboxMessage{
			ID:        "relay-legacy-middle",
			From:      sender,
			Message:   "legacy-only-middle",
			Timestamp: base.Add(3 * time.Second).UnixMilli(),
		}
		if result, err := backend.Store(peerID, legacyMiddle); err != nil || result != InboxStoreResultStored {
			t.Fatalf("store middle legacy-only = (%q, %v)", result, err)
		}
		protectedLast := inboxMessage{
			ID:        "relay-protected-last",
			From:      sender,
			Message:   ackCustodyTextEnvelope("protected-last", sender, "last"),
			Timestamp: base.Add(4 * time.Second).UnixMilli(),
		}
		requireAckCustodyBackendStore(
			t,
			backend,
			peerID,
			protectedLast,
			directInboxTargetIDDedupePrefix+"protected-last",
			InboxStoreResultStored,
		)

		logical, hasMore, err := backend.RetrieveAckCustodyPending(peerID, 10)
		if err != nil || hasMore {
			t.Fatalf("RetrieveAckCustodyPending = (%d, %v, %v)", len(logical), hasMore, err)
		}
		wantIDs := []string{
			legacyOldest.ID,
			protectedFirst.ID,
			legacyMiddle.ID,
			protectedLast.ID,
		}
		if len(logical) != len(wantIDs) {
			t.Fatalf("logical rows = %d, want %d: %#v", len(logical), len(wantIDs), logical)
		}
		for i, wantID := range wantIDs {
			if logical[i].ID != wantID {
				t.Fatalf("global FIFO[%d] = %q, want %q", i, logical[i].ID, wantID)
			}
		}

		// The legacy destructive read can consume legacy-only rows and both
		// shadows, but it has no key path to the protected authority.
		legacyPhysical, legacyHasMore := backend.Retrieve(peerID, 10)
		if legacyHasMore || len(legacyPhysical) != 4 {
			t.Fatalf("legacy destructive page = (%d, %v), want 4 physical legacy rows", len(legacyPhysical), legacyHasMore)
		}
		if backend.Count(peerID) != 0 || backend.CountAckCustody(peerID) != 2 {
			t.Fatalf("after legacy read: legacy=%d protected=%d, want 0/2", backend.Count(peerID), backend.CountAckCustody(peerID))
		}

		protectedOnly, _, err := backend.RetrieveAckCustodyPending(peerID, 10)
		if err != nil || len(protectedOnly) != 2 {
			t.Fatalf("protected replay after destructive legacy read = (%d, %v)", len(protectedOnly), err)
		}

		// A same-ID but byte/sender-mismatched legacy row is not an exact
		// shadow and therefore remains a separate logical result.
		mismatched := inboxMessage{
			ID:        protectedFirst.ID,
			From:      "peer-other",
			Message:   "mismatched-legacy-copy",
			Timestamp: base.Add(2500 * time.Millisecond).UnixMilli(),
		}
		if result, err := backend.Store(peerID, mismatched); err != nil || result != InboxStoreResultStored {
			t.Fatalf("store mismatched legacy row = (%q, %v)", result, err)
		}
		withMismatch, _, err := backend.RetrieveAckCustodyPending(peerID, 10)
		if err != nil || len(withMismatch) != 3 {
			t.Fatalf("mismatched-ID union = (%d, %v), want 3 logical rows", len(withMismatch), err)
		}

		acked, err := backend.AckAckCustody(peerID, []string{
			protectedFirst.ID,
			protectedFirst.ID,
			"",
			"unknown",
		})
		if err != nil || acked != 1 {
			t.Fatalf("logical ACK = (%d, %v), want one unique ID", acked, err)
		}
		remaining, _, err := backend.RetrieveAckCustodyPending(peerID, 10)
		if err != nil || len(remaining) != 1 || remaining[0].ID != protectedLast.ID {
			t.Fatalf("remaining after cross-lane ACK = (%#v, %v), want protected-last only", remaining, err)
		}
	})

	t.Run("real_handler_contract_and_oversized_prefix_progress", func(t *testing.T) {
		server := miniredis.RunT(t)
		backend := newAckCustodyRedisBackend(t, server, "ack-handler-page:", 10)
		inbox := NewInboxStoreWithBackendAndCapacity(backend, nil, 10)
		inbox.SetAckCustodyAdmissionEnabled(true)
		groupInbox := NewGroupInboxStore(500, 7*24*time.Hour)
		env := setupInboxStreamEnv(t, inbox, groupInbox)
		recipient := env.recipient.ID().String()
		sender := env.sender.ID().String()
		for _, req := range []inboxRequest{
			{Action: ackCustodyRetrievePendingAction},
			{Action: ackCustodyAckAction, EntryIds: []string{"entry"}, CustodyContract: "mutated"},
		} {
			invalid := sendInboxAction(t, env.recipient, env.server, req)
			if invalid.Status != "ERROR" ||
				invalid.ErrorCode != ackCustodyErrorIneligible ||
				invalid.CustodyContract != "" {
				t.Fatalf("invalid %s contract response = %#v", req.Action, invalid)
			}
		}

		// Store through the real handler, then prove legacy destructive retrieve
		// consumes only the shadow and the protected action still redelivers.
		storeResp := sendAckCustodyStoreRequest(
			t,
			env,
			recipient,
			ackCustodyDirectTextKind,
			ackCustodyContract,
			ackCustodyTextEnvelope("handler-isolation", sender, "cipher"),
		)
		if storeResp.Status != "OK" || storeResp.CustodyContract != ackCustodyContract {
			t.Fatalf("handler protected store = %#v", storeResp)
		}
		legacyResp := sendInboxAction(t, env.recipient, env.server, inboxRequest{
			Action: "retrieve",
			Limit:  50,
		})
		if legacyResp.Status != "OK" || len(legacyResp.Messages) != 1 {
			t.Fatalf("legacy shadow retrieve = %#v", legacyResp)
		}
		protectedResp := sendInboxAction(t, env.recipient, env.server, inboxRequest{
			Action:          ackCustodyRetrievePendingAction,
			Limit:           50,
			CustodyContract: ackCustodyContract,
		})
		if protectedResp.Status != "OK" ||
			protectedResp.CustodyContract != ackCustodyContract ||
			len(protectedResp.Messages) != 1 {
			t.Fatalf("protected redelivery after legacy destructive read = %#v", protectedResp)
		}
		ackResp := sendInboxAction(t, env.recipient, env.server, inboxRequest{
			Action:          ackCustodyAckAction,
			EntryIds:        []string{protectedResp.Messages[0].ID},
			CustodyContract: ackCustodyContract,
		})
		if ackResp.Status != "OK" || ackResp.Acked != 1 || ackResp.CustodyContract != ackCustodyContract {
			t.Fatalf("protected handler ACK = %#v", ackResp)
		}

		largeCiphertext := strings.Repeat("x", 70_000)
		base := time.Now().Add(-time.Minute)
		largeRows := []struct {
			row       inboxMessage
			protected bool
		}{
			{row: inboxMessage{
				ID:        "large-first",
				From:      sender,
				Message:   ackCustodyTextEnvelope("large-first", sender, largeCiphertext+"1"),
				Timestamp: base.UnixMilli(),
			}},
			{row: inboxMessage{
				ID:        "large-second",
				From:      sender,
				Message:   ackCustodyTextEnvelope("large-second", sender, largeCiphertext+"2"),
				Timestamp: base.Add(time.Second).UnixMilli(),
			}, protected: true},
			{row: inboxMessage{
				ID:        "large-third",
				From:      sender,
				Message:   ackCustodyTextEnvelope("large-third", sender, largeCiphertext+"3"),
				Timestamp: base.Add(2 * time.Second).UnixMilli(),
			}},
			{row: inboxMessage{
				ID:        "large-fourth",
				From:      sender,
				Message:   ackCustodyTextEnvelope("large-fourth", sender, largeCiphertext+"4"),
				Timestamp: base.Add(3 * time.Second).UnixMilli(),
			}, protected: true},
		}
		for _, fixture := range largeRows {
			if fixture.protected {
				requireAckCustodyBackendStore(
					t,
					backend,
					recipient,
					fixture.row,
					directInboxTargetIDDedupePrefix+extractMessageId(fixture.row.Message),
					InboxStoreResultStored,
				)
				continue
			}
			if result, err := backend.Store(recipient, fixture.row); err != nil || result != InboxStoreResultStored {
				t.Fatalf("store oversized legacy-only row = (%q, %v)", result, err)
			}
		}

		seen := make([]string, 0, len(largeRows))
		seenProtected := false
		seenLegacyOnly := false
		for index := range largeRows {
			page := sendInboxAction(t, env.recipient, env.server, inboxRequest{
				Action:          ackCustodyRetrievePendingAction,
				Limit:           50,
				CustodyContract: ackCustodyContract,
			})
			if page.Status != "OK" || page.CustodyContract != ackCustodyContract || len(page.Messages) != 1 {
				t.Fatalf("oversized fitted page = %#v, want one logical prefix", page)
			}
			if wantHasMore := index < len(largeRows)-1; page.HasMore != wantHasMore {
				t.Fatalf("oversized page %d hasMore = %v, want %v", index, page.HasMore, wantHasMore)
			}
			entryID := page.Messages[0].ID
			seen = append(seen, entryID)
			if largeRows[index].protected {
				seenProtected = true
			} else {
				seenLegacyOnly = true
			}
			ack := sendInboxAction(t, env.recipient, env.server, inboxRequest{
				Action:          ackCustodyAckAction,
				EntryIds:        []string{entryID},
				CustodyContract: ackCustodyContract,
			})
			if ack.Status != "OK" || ack.Acked != 1 {
				t.Fatalf("oversized prefix ACK = %#v", ack)
			}
		}
		for index, fixture := range largeRows {
			if seen[index] != fixture.row.ID {
				t.Fatalf("oversized prefix order = %v, want stable alternating-lane FIFO", seen)
			}
		}
		if !seenProtected || !seenLegacyOnly {
			t.Fatalf("oversized drains did not expose both lanes: protected=%v legacyOnly=%v", seenProtected, seenLegacyOnly)
		}
		final := sendInboxAction(t, env.recipient, env.server, inboxRequest{
			Action:          ackCustodyRetrievePendingAction,
			Limit:           50,
			CustodyContract: ackCustodyContract,
		})
		if final.Status != "NO_MESSAGES" || final.CustodyContract != ackCustodyContract {
			t.Fatalf("final protected drain = %#v", final)
		}
	})
}
