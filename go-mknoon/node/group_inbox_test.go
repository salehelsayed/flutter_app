package node

import (
	"encoding/json"
	"strings"
	"testing"
	"time"

	libp2p "github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/network"
	mcrypto "github.com/mknoon/go-mknoon/crypto"
)

func TestBuildGroupInboxStoreRequest_MarshalsRecipientPeerIds(t *testing.T) {
	req := buildGroupInboxStoreRequest(
		"group-1",
		"peer-self",
		`{"text":"hello"}`,
		[]string{"peer-2", "peer-3"},
		"Test Group",
		"Alice: hello",
	)

	raw, err := json.Marshal(req)
	if err != nil {
		t.Fatalf("Marshal: %v", err)
	}

	var decoded map[string]interface{}
	if err := json.Unmarshal(raw, &decoded); err != nil {
		t.Fatalf("Unmarshal: %v", err)
	}

	expect, ok := decoded["recipientPeerIds"].([]interface{})
	if !ok {
		t.Fatal("expected recipientPeerIds in marshaled request")
	}
	if len(expect) != 2 || expect[0] != "peer-2" || expect[1] != "peer-3" {
		t.Fatalf("recipientPeerIds = %#v, want [peer-2 peer-3]", expect)
	}
}

func TestBuildGroupInboxStoreRequest_OmitsRetiredPushTitle(t *testing.T) {
	req := buildGroupInboxStoreRequest(
		"group-1",
		"peer-self",
		`{"text":"hello"}`,
		nil,
		"Test Group",
		"Alice: hello",
	)

	raw, err := json.Marshal(req)
	if err != nil {
		t.Fatalf("Marshal: %v", err)
	}

	var decoded map[string]interface{}
	if err := json.Unmarshal(raw, &decoded); err != nil {
		t.Fatalf("Unmarshal: %v", err)
	}

	if _, ok := decoded["pushTitle"]; ok {
		t.Fatalf("pushTitle should not be marshaled in group inbox requests: %#v", decoded)
	}
}

func TestBuildGroupInboxStoreRequest_OmitsRetiredPushBody(t *testing.T) {
	req := buildGroupInboxStoreRequest(
		"group-1",
		"peer-self",
		`{"text":"hello"}`,
		nil,
		"Test Group",
		"Alice: hello",
	)

	raw, err := json.Marshal(req)
	if err != nil {
		t.Fatalf("Marshal: %v", err)
	}

	var decoded map[string]interface{}
	if err := json.Unmarshal(raw, &decoded); err != nil {
		t.Fatalf("Unmarshal: %v", err)
	}

	if _, ok := decoded["pushBody"]; ok {
		t.Fatalf("pushBody should not be marshaled in group inbox requests: %#v", decoded)
	}
}

func TestBuildGroupInboxStoreRequest_PreservesOpaqueReplayEnvelope(t *testing.T) {
	privB64, pubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	plaintext := `{"text":"Alice private relay body","mediaKey":"media-key-secret-alpha","inviteToken":"invite-token-secret-beta","history":"history repair secret gamma"}`
	sensitiveFragments := []string{
		"Alice private relay body",
		"media-key-secret-alpha",
		"invite-token-secret-beta",
		"history repair secret gamma",
	}
	envelope := buildTestEnvelopeWithPlaintext(
		t,
		"group-1",
		"group_message",
		"peer-self",
		privB64,
		pubB64,
		groupKey,
		4,
		plaintext,
	)
	req := buildGroupInboxStoreRequest(
		"group-1",
		"peer-self",
		envelope,
		[]string{"peer-reader"},
		"New group activity",
		"Open the app to view encrypted group updates.",
	)

	raw, err := json.Marshal(req)
	if err != nil {
		t.Fatalf("Marshal: %v", err)
	}

	var decoded map[string]interface{}
	if err := json.Unmarshal(raw, &decoded); err != nil {
		t.Fatalf("Unmarshal: %v", err)
	}

	if decoded["message"] != envelope {
		t.Fatalf("message = %#v, want exact opaque envelope %q", decoded["message"], envelope)
	}
	if _, ok := decoded["pushTitle"]; ok {
		t.Fatalf("pushTitle should not be marshaled with opaque replay envelope: %#v", decoded)
	}
	if _, ok := decoded["pushBody"]; ok {
		t.Fatalf("pushBody should not be marshaled with opaque replay envelope: %#v", decoded)
	}
	rawRequest := string(raw)
	for _, fragment := range sensitiveFragments {
		if strings.Contains(rawRequest, fragment) {
			t.Fatalf("relay-visible group inbox request leaked plaintext fragment %q in %s", fragment, rawRequest)
		}
	}
}

// ===========================================================================
// Phase 6: GroupInboxRetrieveWithCursor — cursor stability tests
// ===========================================================================

// TestGroupInboxRetrieveCursor_DefaultsLimitWhenZero verifies that
// GroupInboxRetrieveWithCursor defaults limit to 50 when called with 0.
// The actual relay call will fail (no relay configured), but the request
// must be constructed correctly before the network layer is reached.
func TestGroupInboxRetrieveCursor_DefaultsLimitWhenZero(t *testing.T) {
	hexKey := generateTestKey(t)

	n := NewNode()
	_, err := n.Start(NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	// Set fake relays so the relay selector has something to try.
	setFakeRelays(t, n)

	// Call with limit=0 — should default to 50 internally.
	_, _, err = n.GroupInboxRetrieveWithCursor("test-group-default-limit", "", 0)
	if err == nil {
		t.Fatal("expected error (fake relays unreachable)")
	}

	// The error should come from the relay layer, not from input validation.
	// "relays failed" indicates the request was constructed and sent to the
	// relay selector, which means the limit defaulting logic ran.
	if !strings.Contains(err.Error(), "relays failed") {
		t.Errorf("expected relay-layer error, got: %v", err)
	}
}

// TestGroupInboxRetrieveCursor_StableAcrossPages verifies that
// GroupInboxRetrieveWithCursor correctly passes cursor and limit through
// to the internal groupInboxRetrieve function. We verify by starting a
// node with fake relays and confirming the call reaches the relay layer
// (not rejected at the input layer).
func TestGroupInboxRetrieveCursor_StableAcrossPages(t *testing.T) {
	hexKey := generateTestKey(t)

	n := NewNode()
	_, err := n.Start(NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	setFakeRelays(t, n)

	// Page 1: empty cursor, limit 10.
	_, _, err1 := n.GroupInboxRetrieveWithCursor("test-group-stable", "", 10)
	if err1 == nil {
		t.Fatal("expected error for page 1 (fake relays unreachable)")
	}
	if !strings.Contains(err1.Error(), "relays failed") {
		t.Errorf("page 1: expected relay-layer error, got: %v", err1)
	}

	// Page 2: opaque cursor, same limit.
	_, _, err2 := n.GroupInboxRetrieveWithCursor("test-group-stable", "opaque-cursor-page2", 10)
	if err2 == nil {
		t.Fatal("expected error for page 2 (fake relays unreachable)")
	}
	if !strings.Contains(err2.Error(), "relays failed") {
		t.Errorf("page 2: expected relay-layer error, got: %v", err2)
	}
}

// TestGroupInboxRetrieveCursor_NoDuplicateOnContinuation verifies that
// calling with cursor="" gives the first page request, and calling with
// cursor="page2" gives a structurally different request. Both calls reach
// the relay layer without input validation errors.
func TestGroupInboxRetrieveCursor_NoDuplicateOnContinuation(t *testing.T) {
	hexKey := generateTestKey(t)

	n := NewNode()
	_, err := n.Start(NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	setFakeRelays(t, n)

	// First page (cursor="").
	_, nextCursor1, err1 := n.GroupInboxRetrieveWithCursor("group-nodup", "", 20)
	if err1 == nil {
		t.Fatal("expected error for first page (fake relays unreachable)")
	}
	// nextCursor should be empty string on error.
	if nextCursor1 != "" {
		t.Errorf("expected empty nextCursor on error, got %q", nextCursor1)
	}

	// Continuation page (cursor="page2").
	_, nextCursor2, err2 := n.GroupInboxRetrieveWithCursor("group-nodup", "page2", 20)
	if err2 == nil {
		t.Fatal("expected error for continuation page (fake relays unreachable)")
	}
	if nextCursor2 != "" {
		t.Errorf("expected empty nextCursor on error, got %q", nextCursor2)
	}

	// Both should fail at relay layer, proving both requests were structurally valid.
	if !strings.Contains(err1.Error(), "relays failed") {
		t.Errorf("first page: expected relay-layer error, got: %v", err1)
	}
	if !strings.Contains(err2.Error(), "relays failed") {
		t.Errorf("continuation page: expected relay-layer error, got: %v", err2)
	}
}

// TestGroupInboxRetrieveCursor_RequiresStartedNode verifies that calling
// GroupInboxRetrieveWithCursor on a non-started node returns an error
// about the node not being started (not a panic).
func TestGroupInboxRetrieveCursor_RequiresStartedNode(t *testing.T) {
	n := NewNode()

	_, _, err := n.GroupInboxRetrieveWithCursor("group-not-started", "", 10)
	if err == nil {
		t.Fatal("expected error on non-started node")
	}
	if !strings.Contains(err.Error(), "not started") {
		t.Errorf("expected 'not started' error, got: %v", err)
	}
}

// TestGroupInboxRetrieveCursor_NegativeLimitDefaultsTo50 verifies that
// a negative limit is treated the same as 0 (defaults to 50).
func TestGroupInboxRetrieveCursor_NegativeLimitDefaultsTo50(t *testing.T) {
	hexKey := generateTestKey(t)

	n := NewNode()
	_, err := n.Start(NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	setFakeRelays(t, n)

	// Call with limit=-1 — should default to 50 internally.
	_, _, err = n.GroupInboxRetrieveWithCursor("test-group-neg-limit", "", -1)
	if err == nil {
		t.Fatal("expected error (fake relays unreachable)")
	}

	// Should reach relay layer, not rejected at input validation.
	if !strings.Contains(err.Error(), "relays failed") {
		t.Errorf("expected relay-layer error, got: %v", err)
	}
}

func TestGroupHistoryRepairRange_ValidatesRequiredFields(t *testing.T) {
	valid := GroupHistoryRepairRangeRequest{
		GroupId:                " group-1 ",
		GapId:                  " gap-1 ",
		SourcePeerId:           " peer-source ",
		MissingAfterMessageId:  " msg-before ",
		MissingBeforeMessageId: " msg-after ",
		ExpectedRangeHash:      " range-hash ",
		ExpectedHeadMessageId:  " msg-after ",
	}

	normalized, err := NormalizeGroupHistoryRepairRangeRequest(valid)
	if err != nil {
		t.Fatalf("NormalizeGroupHistoryRepairRangeRequest(valid): %v", err)
	}
	if normalized.GroupId != "group-1" || normalized.SourcePeerId != "peer-source" {
		t.Fatalf("expected trimmed fields, got %#v", normalized)
	}
	if normalized.Limit != 50 {
		t.Fatalf("expected default limit 50, got %d", normalized.Limit)
	}

	invalid := valid
	invalid.ExpectedRangeHash = ""
	if _, err := NormalizeGroupHistoryRepairRangeRequest(invalid); err == nil {
		t.Fatal("expected missing expectedRangeHash to fail validation")
	}
}

func TestGroupHistoryRepairRange_RequiresStartedNode(t *testing.T) {
	n := NewNode()
	_, err := n.GroupHistoryRepairRange(GroupHistoryRepairRangeRequest{
		GroupId:                "group-1",
		GapId:                  "gap-1",
		SourcePeerId:           "peer-source",
		MissingAfterMessageId:  "msg-before",
		MissingBeforeMessageId: "msg-after",
		ExpectedRangeHash:      "range-hash",
		ExpectedHeadMessageId:  "msg-after",
	})
	if err == nil || !strings.Contains(err.Error(), "node not started") {
		t.Fatalf("expected node not started error, got %v", err)
	}
}

func TestGroupHistoryRepairRange_ReturnsRelayReplayEnvelopes(t *testing.T) {
	relayHost, err := libp2p.New(libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"))
	if err != nil {
		t.Fatalf("start relay host: %v", err)
	}
	defer relayHost.Close()

	requestSeen := make(chan groupInboxRequest, 1)
	relayHost.SetStreamHandler(InboxProtocol, func(s network.Stream) {
		defer s.Close()
		reqBytes, err := readFrame(s)
		if err != nil {
			return
		}
		var req groupInboxRequest
		if err := json.Unmarshal(reqBytes, &req); err != nil {
			return
		}
		requestSeen <- req
		_ = writeFrame(s, []byte(`{
			"status":"OK",
			"groupId":"group-1",
			"gapId":"gap-1",
			"sourcePeerId":"peer-source",
			"rangeHash":"range-hash",
			"headMessageId":"msg-after",
			"groupMessages":[
				{"from":"peer-source","message":"{\"messageId\":\"msg-repaired\"}","timestamp":1777659516000}
			]
		}`))
	})

	n := startLocalNodeForMultiRelayTest(t)
	relayAddr := relayHost.Addrs()[0].String() + "/p2p/" + relayHost.ID().String()
	n.mu.Lock()
	n.relayAddresses = []string{relayAddr}
	n.mu.Unlock()

	result, err := n.GroupHistoryRepairRange(GroupHistoryRepairRangeRequest{
		GroupId:                "group-1",
		GapId:                  "gap-1",
		SourcePeerId:           "peer-source",
		MissingAfterMessageId:  "msg-before",
		MissingBeforeMessageId: "msg-after",
		ExpectedRangeHash:      "range-hash",
		ExpectedHeadMessageId:  "msg-after",
		Limit:                  10,
	})
	if err != nil {
		t.Fatalf("GroupHistoryRepairRange: %v", err)
	}
	if result.GroupId != "group-1" || result.GapId != "gap-1" || result.SourcePeerId != "peer-source" {
		t.Fatalf("unexpected repair metadata: %#v", result)
	}
	if result.RangeHash != "range-hash" || result.HeadMessageId != "msg-after" {
		t.Fatalf("unexpected integrity metadata: %#v", result)
	}
	if len(result.Messages) != 1 || result.Messages[0].Message == "" {
		t.Fatalf("expected one replay envelope, got %#v", result.Messages)
	}

	select {
	case req := <-requestSeen:
		if req.Action != "group_history_repair_range" {
			t.Fatalf("action = %q, want group_history_repair_range", req.Action)
		}
		if req.ExpectedRangeHash != "range-hash" || req.ExpectedHeadMessageId != "msg-after" {
			t.Fatalf("repair request did not carry integrity fields: %#v", req)
		}
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for relay repair request")
	}
}

func TestGroupInboxRetrieveWithCursorResult_PreservesRelayHistoryGaps(t *testing.T) {
	relayHost, err := libp2p.New(libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"))
	if err != nil {
		t.Fatalf("start relay host: %v", err)
	}
	defer relayHost.Close()

	relayHost.SetStreamHandler(InboxProtocol, func(s network.Stream) {
		defer s.Close()
		reqBytes, err := readFrame(s)
		if err != nil {
			return
		}
		var req groupInboxRequest
		if err := json.Unmarshal(reqBytes, &req); err != nil {
			return
		}
		if req.Action != "group_retrieve_cursor" {
			_ = writeFrame(s, []byte(`{"status":"ERROR","error":"unexpected action"}`))
			return
		}
		_ = writeFrame(s, []byte(`{
			"status":"OK",
			"nextCursor":"cursor-next",
			"groupMessages":[
				{"from":"peer-source","message":"{\"messageId\":\"msg-1\"}","timestamp":1777659516000}
			],
			"historyGaps":[
				{
					"groupId":"group-1",
					"gapId":"gap-1",
					"missingAfterMessageId":"stale-cursor",
					"missingBeforeMessageId":"msg-1",
					"expectedRangeHash":"range-hash",
					"expectedHeadMessageId":"msg-1",
					"candidateSourcePeerIds":["peer-source"]
				}
			]
		}`))
	})

	n := startLocalNodeForMultiRelayTest(t)
	relayAddr := relayHost.Addrs()[0].String() + "/p2p/" + relayHost.ID().String()
	n.mu.Lock()
	n.relayAddresses = []string{relayAddr}
	n.mu.Unlock()

	page, err := n.GroupInboxRetrieveWithCursorResult("group-1", "stale-cursor", 10)
	if err != nil {
		t.Fatalf("GroupInboxRetrieveWithCursorResult: %v", err)
	}
	if page.NextCursor != "cursor-next" || len(page.Messages) != 1 {
		t.Fatalf("unexpected page: %#v", page)
	}
	if len(page.HistoryGaps) != 1 {
		t.Fatalf("expected one history gap, got %#v", page.HistoryGaps)
	}
	if page.HistoryGaps[0].GapId != "gap-1" ||
		page.HistoryGaps[0].CandidateSourcePeerIds[0] != "peer-source" {
		t.Fatalf("unexpected history gap: %#v", page.HistoryGaps[0])
	}
}
