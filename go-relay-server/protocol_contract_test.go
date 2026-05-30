package main

import (
	"context"
	"encoding/json"
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
	resp := inboxResponse{
		Status:        "OK",
		Error:         "e",
		StoreStatus:   "stored",
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
		"error",
		"gapId",
		"groupId",
		"groupMessages",
		"hasMore",
		"headMessageId",
		"historyGaps",
		"messages",
		"nextCursor",
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
