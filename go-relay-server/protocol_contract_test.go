package main

import (
	"context"
	"encoding/json"
	"fmt"
	"reflect"
	"sort"
	"sync"
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

// TestMediaCustodyAdditiveWireContract freezes Plan 346's protected-media
// fields as an additive extension of /mknoon/media/1.0.0. Legacy clients omit
// all custody fields and continue to use the existing actions; strict clients
// require every proof discriminator below and must never infer custody from a
// broad legacy OK response.
func TestMediaCustodyAdditiveWireContract(t *testing.T) {
	if got, want := string(MediaProtocol), "/mknoon/media/1.0.0"; got != want {
		t.Fatalf("media protocol = %q, want frozen %q", got, want)
	}

	request := mediaRequest{
		Action:          "upload_custody_v1",
		ID:              "blob-contract",
		To:              "recipient",
		Owner:           "profile-owner",
		Size:            17,
		Mime:            "application/octet-stream",
		AllowedPeers:    []string{"allowed"},
		CustodyKind:     "direct_media_blob_v1",
		CustodyContract: "ack_or_expiry_v1",
		ContentHash:     "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
		ExpiresAtMs:     1234,
	}
	assertJSONKeySet(t, "media request", request, []string{
		"action",
		"allowedPeers",
		"contentHash",
		"custodyContract",
		"custodyKind",
		"expiresAtMs",
		"id",
		"mime",
		"owner",
		"size",
		"to",
	})

	response := mediaResponse{
		Status:          "OK",
		Error:           "error",
		ErrorCode:       "MEDIA_CUSTODY_INELIGIBLE",
		ID:              "blob-contract",
		Mime:            "application/octet-stream",
		Size:            17,
		Blobs:           []*mediaMeta{{ID: "legacy"}},
		CustodyKind:     "direct_media_blob_v1",
		CustodyContract: "ack_or_expiry_v1",
		ContentHash:     "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
		ExpiresAtMs:     1234,
		StoreStatus:     "stored",
		AckStatus:       "acked",
	}
	assertJSONKeySet(t, "media response", response, []string{
		"ackStatus",
		"blobs",
		"contentHash",
		"custodyContract",
		"custodyKind",
		"error",
		"errorCode",
		"expiresAtMs",
		"id",
		"mime",
		"size",
		"status",
		"storeStatus",
	})

	legacyRequest, err := json.Marshal(mediaRequest{
		Action: "upload",
		ID:     "legacy",
		To:     "recipient",
		Size:   1,
		Mime:   "image/jpeg",
	})
	if err != nil {
		t.Fatalf("marshal legacy media request: %v", err)
	}
	for _, forbidden := range []string{
		"custodyKind", "custodyContract", "contentHash", "expiresAtMs",
	} {
		if json.Valid(legacyRequest) && stringContainsJSONKey(legacyRequest, forbidden) {
			t.Fatalf("legacy media request unexpectedly emits %q: %s", forbidden, legacyRequest)
		}
	}

	legacyResponse, err := json.Marshal(mediaResponse{Status: "OK", ID: "legacy"})
	if err != nil {
		t.Fatalf("marshal legacy media response: %v", err)
	}
	for _, forbidden := range []string{
		"errorCode", "custodyKind", "custodyContract", "contentHash",
		"expiresAtMs", "storeStatus", "ackStatus",
	} {
		if stringContainsJSONKey(legacyResponse, forbidden) {
			t.Fatalf("legacy media response unexpectedly emits %q: %s", forbidden, legacyResponse)
		}
	}
}

func assertJSONKeySet(t *testing.T, name string, value interface{}, want []string) {
	t.Helper()
	data, err := json.Marshal(value)
	if err != nil {
		t.Fatalf("marshal %s: %v", name, err)
	}
	var decoded map[string]json.RawMessage
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("decode %s: %v", name, err)
	}
	got := make([]string, 0, len(decoded))
	for key := range decoded {
		got = append(got, key)
	}
	sort.Strings(got)
	sort.Strings(want)
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("%s JSON keys changed: got %v, want %v", name, got, want)
	}
}

func stringContainsJSONKey(data []byte, key string) bool {
	var decoded map[string]json.RawMessage
	if err := json.Unmarshal(data, &decoded); err != nil {
		return false
	}
	_, ok := decoded[key]
	return ok
}

// TestResponseKeyContract_Frozen pins the exact set of JSON keys the relay's
// inboxResponse can emit. Old clients zero-fill missing keys and ignore unknown
// ones, so a RENAME silently gives every un-updated client an empty value.
func TestResponseKeyContract_Frozen(t *testing.T) {
	// Fully populate every field so omitempty does not hide a key.
	presenceAge := int64(1200)
	resp := inboxResponse{
		Status:          "OK",
		Error:           "e",
		ErrorCode:       "E",
		StoreStatus:     "stored",
		CustodyContract: ackCustodyContract,
		ExpiresAtMs:     1,
		Occupancy:       2,
		Capacity:        3,
		Messages:        []inboxMessage{{}},
		HasMore:         true,
		Acked:           1,
		GroupMessages:   []groupInboxMessage{{}},
		NextCursor:      "c",
		HistoryGaps:     []groupInboxHistoryGap{{}},
		GroupId:         "g",
		GapId:           "gap",
		SourcePeerId:    "p",
		RangeHash:       "r",
		HeadMessageId:   "h",
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
		"custodyContract", // Plan 344 additive protected-custody proof
		"error",
		"errorCode", // Plan 344 additive machine-readable failure class
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

// causalAckCustodyBackend is deliberately test-only. It models the optional
// protected lane without changing the production memory backend contract.
// The production handler discovers this capability only for the additive
// custody actions; legacy Store/Retrieve/Ack remain delegated to InboxBackend.
type causalAckCustodyBackend struct {
	InboxBackend
	mu        sync.Mutex
	capacity  int
	protected map[string][]inboxMessage
}

func newCausalAckCustodyBackend(capacity int) *causalAckCustodyBackend {
	return &causalAckCustodyBackend{
		InboxBackend: newMemoryInboxBackendWithLimits(capacity),
		capacity:     capacity,
		protected:    make(map[string][]inboxMessage),
	}
}

func (b *causalAckCustodyBackend) StoreAckCustody(
	peerID string,
	entry inboxMessage,
	_ string,
) (InboxStoreResult, inboxMessage, error) {
	b.mu.Lock()
	defer b.mu.Unlock()

	entries := b.protected[peerID]
	if len(entries) >= b.capacity {
		return InboxStoreResultRejectedFull, inboxMessage{}, nil
	}
	entry = ensureInboxMessageID(entry)
	b.protected[peerID] = append(entries, entry)
	return InboxStoreResultStored, entry, nil
}

func (b *causalAckCustodyBackend) RetrieveAckCustodyPending(
	peerID string,
	limit int,
) ([]inboxMessage, bool, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	entries := append([]inboxMessage(nil), b.protected[peerID]...)
	if limit < len(entries) {
		return entries[:limit], true, nil
	}
	return entries, false, nil
}

func (b *causalAckCustodyBackend) AckAckCustody(string, []string) (int, error) {
	return 0, nil
}

func (b *causalAckCustodyBackend) CountAckCustody(peerID string) int {
	b.mu.Lock()
	defer b.mu.Unlock()
	return len(b.protected[peerID])
}

func (b *causalAckCustodyBackend) AckCustodyStats() (int, int) {
	b.mu.Lock()
	defer b.mu.Unlock()
	peers := 0
	total := 0
	for _, entries := range b.protected {
		if len(entries) == 0 {
			continue
		}
		peers++
		total += len(entries)
	}
	return peers, total
}

// TestRelayNotificationClosure_AckCustodyActionRejectsFullWithoutEviction is
// TC-344-01's causal runtime RED. The raw additive action compiles against the
// frozen protocol on baseline, where it deterministically reaches the
// "Unknown action" response. Once implemented, a full protected lane must
// reject the newest distinct obligation and retain the previously accepted
// entry byte-for-byte.
func TestRelayNotificationClosure_AckCustodyActionRejectsFullWithoutEviction(t *testing.T) {
	t.Setenv("DIRECT_INBOX_ACK_CUSTODY_ADMISSION_ENABLED", "true")

	backend := newCausalAckCustodyBackend(1)
	inbox := NewInboxStoreWithBackendAndCapacity(backend, nil, 1)
	groupInbox := NewGroupInboxStore(500, 7*24*time.Hour)
	env := setupInboxStreamEnv(t, inbox, groupInbox)

	recipientPeer := env.recipient.ID().String()
	senderPeer := env.sender.ID().String()
	originalEnvelope := fmt.Sprintf(
		`{"type":"chat_message","version":"2","id":"protected-oldest","senderPeerId":%q,"encrypted":{"kem":"k","ciphertext":"old","nonce":"n"}}`,
		senderPeer,
	)
	original := inboxMessage{
		ID:        "relay-protected-oldest",
		From:      senderPeer,
		Message:   originalEnvelope,
		Timestamp: time.Now().UnixMilli(),
	}
	if result, _, err := backend.StoreAckCustody(
		recipientPeer,
		original,
		directInboxTargetIDDedupePrefix+"protected-oldest",
	); err != nil || result != InboxStoreResultStored {
		t.Fatalf("seed protected lane = (%q, %v), want stored", result, err)
	}

	newEnvelope := fmt.Sprintf(
		`{"type":"chat_message","version":"2","id":"protected-newest","senderPeerId":%q,"encrypted":{"kem":"k","ciphertext":"new","nonce":"n"}}`,
		senderPeer,
	)
	request := map[string]interface{}{
		"action":          "store_custody_v1",
		"to":              recipientPeer,
		"message":         newEnvelope,
		"custodyKind":     "direct_text_v108",
		"custodyContract": "ack_or_expiry_v1",
	}
	requestBytes, err := json.Marshal(request)
	if err != nil {
		t.Fatalf("marshal raw custody request: %v", err)
	}

	stream, err := env.sender.NewStream(context.Background(), env.server.ID(), InboxProtocol)
	if err != nil {
		t.Fatalf("open custody stream: %v", err)
	}
	defer stream.Close()
	if err := writeFrame(stream, requestBytes); err != nil {
		t.Fatalf("write custody request: %v", err)
	}
	responseBytes, err := readFrame(stream)
	if err != nil {
		t.Fatalf("read custody response: %v", err)
	}
	var response map[string]interface{}
	if err := json.Unmarshal(responseBytes, &response); err != nil {
		t.Fatalf("decode custody response: %v", err)
	}
	if response["status"] != "ERROR" ||
		response["storeStatus"] != string(InboxStoreResultRejectedFull) ||
		response["errorCode"] != "INBOX_FULL" {
		t.Fatalf("full custody response = %#v, want ERROR/rejected_full/INBOX_FULL", response)
	}

	pending, hasMore, err := backend.RetrieveAckCustodyPending(recipientPeer, 10)
	if err != nil {
		t.Fatalf("retrieve protected lane: %v", err)
	}
	if hasMore || len(pending) != 1 || !reflect.DeepEqual(pending[0], original) {
		t.Fatalf("protected lane after rejection = (%#v, hasMore=%v), want original only", pending, hasMore)
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
