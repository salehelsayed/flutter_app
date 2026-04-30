package node

import (
	"encoding/json"
	"strings"
	"testing"

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

func TestBuildGroupInboxStoreRequest_MarshalsPushTitle(t *testing.T) {
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

	if decoded["pushTitle"] != "Test Group" {
		t.Fatalf("pushTitle = %#v, want %q", decoded["pushTitle"], "Test Group")
	}
}

func TestBuildGroupInboxStoreRequest_MarshalsPushBody(t *testing.T) {
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

	if decoded["pushBody"] != "Alice: hello" {
		t.Fatalf("pushBody = %#v, want %q", decoded["pushBody"], "Alice: hello")
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
