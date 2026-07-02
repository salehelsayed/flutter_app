package main

import (
	"context"
	"encoding/json"
	"fmt"
	"reflect"
	"sort"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/protocol"
)

// NET-REL-07 frozen-contract test for the relay's wire surface.
//
// The relay is a single shared host hard-coded into every shipped app binary
// (go-mknoon/node/config.go) with NO version negotiation: protocol IDs are
// exact-match strings, no client uses DisallowUnknownFields, and clients
// exact-match the `status` string values. A breaking relay change therefore
// hits 100% of un-updated clients instantly. This test FREEZES the served
// protocol IDs, the response JSON keys, and the status string values so an
// accidental rename/removal/retype fails CI.
//
// SAFE vs BREAKING (NET-REL-07): ADDING a new protocol ID, response key, or
// status value is backward-compatible — but it is intentionally still caught
// here so a human consciously updates the frozen set below and confirms the
// change is additive (not a disguised rename). RENAMING/REMOVING/RETYPING any
// existing one is BREAKING and must go via the multi-relay migration path.
//
// Negative control (NET-REL-07 requirement, verified by mutation at build time):
// bumping a protocol-ID constant (e.g. InboxProtocol -> /mknoon/inbox/1.1.0),
// renaming a json tag (e.g. `json:"messages"` -> `json:"msgs"`), or renaming a
// status literal (e.g. "OK" -> "SUCCESS") turns the corresponding test RED.

// TestProtocolIDContract_Frozen pins the libp2p protocol IDs the relay serves
// (registered at main.go via SetStreamHandler). These exact strings are
// mirrored in go-mknoon/node/config.go and opened with no fallback.
func TestProtocolIDContract_Frozen(t *testing.T) {
	frozen := map[string]string{
		"rendezvous": "/canvas/rendezvous/1.0.0",
		"inbox":      "/mknoon/inbox/1.0.0",
		"media":      "/mknoon/media/1.0.0",
	}
	served := map[string]protocol.ID{
		"rendezvous": RendezvousProtocol,
		"inbox":      InboxProtocol,
		"media":      MediaProtocol,
	}

	// Every frozen ID must still be served verbatim.
	for name, want := range frozen {
		got, ok := served[name]
		if !ok {
			t.Fatalf("protocol %q dropped from served set — BREAKING per NET-REL-07", name)
		}
		if string(got) != want {
			t.Fatalf(
				"BREAKING protocol-ID change: %s = %q, frozen contract requires %q "+
					"(hits all un-updated clients; use the multi-relay migration path)",
				name, string(got), want,
			)
		}
	}
	// And nothing was added without updating this contract (forces conscious review).
	if len(served) != len(frozen) {
		t.Fatalf(
			"served protocol-ID count = %d, frozen = %d — a protocol was added/removed; "+
				"update the frozen set and confirm it is additive (NET-REL-07)",
			len(served), len(frozen),
		)
	}
}

// TestResponseKeyContract_Frozen pins the exact set of JSON keys the relay's
// inboxResponse can emit. Old clients zero-fill missing keys and ignore unknown
// ones, so a RENAME silently gives every un-updated client an empty value.
func TestResponseKeyContract_Frozen(t *testing.T) {
	// Fully populate every field so omitempty does not hide a key.
	presenceAge := int64(1200)
	resp := inboxResponse{
		Status:        "OK",
		Error:         "e",
		StoreStatus:   "stored",
		ExpiresAtMs:   1,
		Occupancy:     2,
		Capacity:      3,
		Messages:      []inboxMessage{{}},
		HasMore:       true,
		Acked:         1,
		GroupMessages: []groupInboxMessage{{}},
		NextCursor:    "c",
		HistoryGaps:   []groupInboxHistoryGap{{}},
		GroupId:       "g",
		GapId:         "gap",
		SourcePeerId:  "p",
		RangeHash:     "r",
		HeadMessageId: "h",
		// FDC-08 presence_get additive keys (consciously registered below).
		Presence: "reachable",
		AgeMs:    &presenceAge,
	}

	data, err := json.Marshal(resp)
	if err != nil {
		t.Fatalf("marshal inboxResponse: %v", err)
	}
	var decoded map[string]json.RawMessage
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("unmarshal inboxResponse keys: %v", err)
	}

	got := make([]string, 0, len(decoded))
	for k := range decoded {
		got = append(got, k)
	}
	sort.Strings(got)

	frozen := []string{
		"acked",
		"ageMs", // FDC-08 presence_get (additive)
		"capacity",
		"error",
		"expiresAtMs",
		"gapId",
		"groupId",
		"groupMessages",
		"hasMore",
		"headMessageId",
		"historyGaps",
		"messages",
		"nextCursor",
		"occupancy",
		"presence", // FDC-08 presence_get (additive)
		"rangeHash",
		"sourcePeerId",
		"status",
		"storeStatus",
	}
	sort.Strings(frozen)

	if !reflect.DeepEqual(got, frozen) {
		t.Fatalf(
			"inboxResponse JSON keys changed.\n got:    %v\n frozen: %v\n"+
				"A RENAME/REMOVE is BREAKING per NET-REL-07 (old clients get empty values). "+
				"If you ADDED a key (safe), mirror it in the frozen set above.",
			got, frozen,
		)
	}
}

// TestStatusValueContract_Frozen drives the REAL inbox stream handler over a
// mocknet and asserts the exact `status` strings clients exact-match: a valid
// store -> "OK", an empty retrieve -> "NO_MESSAGES", a malformed request ->
// "ERROR". Renaming any literal in the handler turns this RED.
func TestStatusValueContract_Frozen(t *testing.T) {
	push := NewPushServiceWithBackend(newMemoryPushTokenStore())
	inbox := NewInboxStore(push)
	groupInbox := NewGroupInboxStore(500, 7*24*time.Hour)
	env := setupInboxStreamEnv(t, inbox, groupInbox)

	recipientPeer := env.recipient.ID().String()

	open := func(from host.Host) network.Stream {
		t.Helper()
		stream, err := from.NewStream(context.Background(), env.server.ID(), InboxProtocol)
		if err != nil {
			t.Fatalf("open inbox stream: %v", err)
		}
		return stream
	}

	// store (valid) -> "OK"
	storeStream := open(env.sender)
	sendInboxReq(t, storeStream, inboxRequest{
		Action:  "store",
		To:      recipientPeer,
		From:    env.sender.ID().String(),
		Message: `{"type":"contract_probe","id":"c1"}`,
	})
	if resp := recvInboxResp(t, storeStream); resp.Status != "OK" {
		t.Fatalf("store status = %q, frozen contract requires %q (NET-REL-07)", resp.Status, "OK")
	}
	storeStream.Close()

	// retrieve (intruder has nothing stored) -> "NO_MESSAGES"
	emptyStream := open(env.intruder)
	sendInboxReq(t, emptyStream, inboxRequest{Action: "retrieve"})
	if resp := recvInboxResp(t, emptyStream); resp.Status != "NO_MESSAGES" {
		t.Fatalf("empty retrieve status = %q, frozen contract requires %q (NET-REL-07)", resp.Status, "NO_MESSAGES")
	}
	emptyStream.Close()

	// store (missing required fields) -> "ERROR"
	badStream := open(env.sender)
	sendInboxReq(t, badStream, inboxRequest{Action: "store"}) // no To / Message
	if resp := recvInboxResp(t, badStream); resp.Status != "ERROR" {
		t.Fatalf("malformed store status = %q, frozen contract requires %q (NET-REL-07)", resp.Status, "ERROR")
	}
	badStream.Close()
}

// TC-01 (plan 173) — TestStatusValueContract_FullInboxStoreStaysOK freezes the
// build-106 full-inbox contract over the REAL handler + the PRODUCTION default
// backend: a 1:1 store to a peer whose inbox is at maxMessagesPerPeer returns
// Status "OK" (oldest evicted, newest stored). Shipped clients treat any
// non-"OK" store as a hard failure with NO INBOX_FULL branch, so an OK->ERROR
// inversion here silently drops the NEWEST message for the whole installed
// base. This is the exact coverage gap that let the 2026-06-28 regression
// ship: the frozen contract only ever stored once and never filled an inbox.
func TestStatusValueContract_FullInboxStoreStaysOK(t *testing.T) {
	push := NewPushServiceWithBackend(newMemoryPushTokenStore())
	inbox := NewInboxStore(push) // production default backend + capacity
	groupInbox := NewGroupInboxStore(500, 7*24*time.Hour)
	env := setupInboxStreamEnv(t, inbox, groupInbox)

	recipientPeer := env.recipient.ID().String()

	store := func(id string) inboxResponse {
		t.Helper()
		stream, err := env.sender.NewStream(context.Background(), env.server.ID(), InboxProtocol)
		if err != nil {
			t.Fatalf("open store stream: %v", err)
		}
		defer stream.Close()
		sendInboxReq(t, stream, inboxRequest{
			Action:  "store",
			To:      recipientPeer,
			From:    env.sender.ID().String(),
			Message: `{"type":"contract_probe","id":"` + id + `"}`,
		})
		return recvInboxResp(t, stream)
	}

	for i := 0; i < maxMessagesPerPeer; i++ {
		if resp := store(fmt.Sprintf("cf-%d", i)); resp.Status != "OK" {
			t.Fatalf("fill store %d status = %q, want OK", i, resp.Status)
		}
	}

	full := store("cf-overflow")
	if full.Status != "OK" {
		t.Fatalf("full-inbox store status = %q, frozen contract requires %q (NET-REL-07: "+
			"old clients hard-fail any non-OK store; evict oldest instead)", full.Status, "OK")
	}
	if full.StoreStatus != string(InboxStoreResultStored) {
		t.Fatalf("full-inbox storeStatus = %q, want %q", full.StoreStatus, InboxStoreResultStored)
	}
	if full.Occupancy != maxMessagesPerPeer {
		t.Fatalf("full-inbox occupancy = %d, want %d (evict keeps the inbox at cap)",
			full.Occupancy, maxMessagesPerPeer)
	}
	if full.Capacity != maxMessagesPerPeer {
		t.Fatalf("full-inbox capacity = %d, want %d", full.Capacity, maxMessagesPerPeer)
	}

	// Oldest evicted, newest present: the FIFO head must now be cf-1.
	pendingStream, err := env.recipient.NewStream(context.Background(), env.server.ID(), InboxProtocol)
	if err != nil {
		t.Fatalf("open retrieve_pending stream: %v", err)
	}
	defer pendingStream.Close()
	sendInboxReq(t, pendingStream, inboxRequest{Action: "retrieve_pending", Limit: 1})
	head := recvInboxResp(t, pendingStream)
	if head.Status != "OK" || len(head.Messages) != 1 {
		t.Fatalf("retrieve_pending head = %#v, want OK with 1 message", head)
	}
	if got := extractMessageId(head.Messages[0].Message); got != "cf-1" {
		t.Fatalf("FIFO head after full-inbox store = %q, want cf-1 (cf-0 evicted, newest kept)", got)
	}
}

// TestPresenceGetIsAdditive (FDC-08 / NET-REL-07) proves the new `presence_get`
// action is purely additive: (a) it answers OK for a known peer, (b) every
// existing action keeps its exact status behaviour alongside it, and (c) an
// unknown action STILL returns the literal "Unknown action: <x>" string that
// new clients hitting an OLD relay degrade to `unknown` on. Renaming/removing an
// existing action while adding presence turns this RED.
func TestPresenceGetIsAdditive(t *testing.T) {
	push := NewPushServiceWithBackend(newMemoryPushTokenStore())
	inbox := NewInboxStore(push)
	groupInbox := NewGroupInboxStore(500, 7*24*time.Hour)
	env := setupInboxStreamEnv(t, inbox, groupInbox)

	open := func(from host.Host) network.Stream {
		t.Helper()
		stream, err := from.NewStream(context.Background(), env.server.ID(), InboxProtocol)
		if err != nil {
			t.Fatalf("open inbox stream: %v", err)
		}
		return stream
	}

	// (a) The new action works: the sender is socket-connected -> reachable.
	presenceStream := open(env.sender)
	sendInboxReq(t, presenceStream, inboxRequest{Action: "presence_get", To: env.sender.ID().String()})
	if resp := recvInboxResp(t, presenceStream); resp.Status != "OK" || resp.Presence == "" {
		t.Fatalf("presence_get response = %#v, want OK with a presence value", resp)
	}
	presenceStream.Close()

	// (b) Existing actions are untouched: a valid store still -> "OK".
	storeStream := open(env.sender)
	sendInboxReq(t, storeStream, inboxRequest{
		Action:  "store",
		To:      env.recipient.ID().String(),
		From:    env.sender.ID().String(),
		Message: `{"type":"chat_message","version":"1","payload":{"id":"additive-1","text":"hi"}}`,
	})
	if resp := recvInboxResp(t, storeStream); resp.Status != "OK" {
		t.Fatalf("store alongside presence_get = %q, want OK (existing action must be unchanged)", resp.Status)
	}
	storeStream.Close()

	// (c) The degrade path is intact: an unknown action still returns the exact
	// literal string old/new clients map to `unknown`.
	unknownStream := open(env.sender)
	sendInboxReq(t, unknownStream, inboxRequest{Action: "definitely_not_an_action"})
	resp := recvInboxResp(t, unknownStream)
	unknownStream.Close()
	if resp.Status != "ERROR" {
		t.Fatalf("unknown action status = %q, want ERROR", resp.Status)
	}
	if resp.Error != "Unknown action: definitely_not_an_action" {
		t.Fatalf("unknown action error = %q, want the frozen %q literal (NET-REL-07 degrade rides on it)",
			resp.Error, "Unknown action: definitely_not_an_action")
	}
}
