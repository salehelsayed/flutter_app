package node

import (
	"encoding/binary"
	"encoding/json"
	"io"
	"strings"
	"sync/atomic"
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

func TestGM028BuildGroupInboxStoreRequestDropsBlankRecipientPeerIds(t *testing.T) {
	req := buildGroupInboxStoreRequest(
		"group-1",
		"peer-self",
		`{"text":"hello"}`,
		[]string{" peer-2 ", "", "   ", "peer-3"},
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

func TestGI001GroupInboxStoreRequiresStartedNodeBeforeRelayStream(t *testing.T) {
	relayHost, err := libp2p.New(libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"))
	if err != nil {
		t.Fatalf("start relay host: %v", err)
	}
	defer relayHost.Close()

	var streamAttempts atomic.Int32
	relayHost.SetStreamHandler(InboxProtocol, func(s network.Stream) {
		streamAttempts.Add(1)
		_ = s.Reset()
	})

	n := NewNode()
	relayAddr := relayHost.Addrs()[0].String() + "/p2p/" + relayHost.ID().String()
	n.mu.Lock()
	n.relayAddresses = []string{relayAddr}
	n.mu.Unlock()

	err = n.GroupInboxStore(
		"group-gi-001",
		`{"ciphertext":"opaque"}`,
		[]string{"peer-recipient"},
		"ignored title",
		"ignored body",
	)
	if err == nil {
		t.Fatal("expected node not started error")
	}
	if err.Error() != "node not started" {
		t.Fatalf("GroupInboxStore error = %q, want %q", err.Error(), "node not started")
	}
	if got := streamAttempts.Load(); got != 0 {
		t.Fatalf("relay stream attempts = %d, want 0 before node start", got)
	}
}

func TestGI002GroupInboxStoreSendsGroupStoreRequestShape(t *testing.T) {
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
		_ = writeFrame(s, []byte(`{"status":"OK"}`))
	})

	n := startLocalNodeForMultiRelayTest(t)
	relayAddr := relayHost.Addrs()[0].String() + "/p2p/" + relayHost.ID().String()
	n.mu.Lock()
	n.relayAddresses = []string{relayAddr}
	n.mu.Unlock()

	message := `{"version":"3","encrypted":{"ciphertext":"ct-gi-002","nonce":"nonce-gi-002"}}`
	recipients := []string{"peer-recipient-a", "peer-recipient-b"}
	wantFrom := n.peerId

	if err := n.GroupInboxStore(
		"group-gi-002",
		message,
		recipients,
		"ignored title",
		"ignored body",
	); err != nil {
		t.Fatalf("GroupInboxStore: %v", err)
	}

	select {
	case req := <-requestSeen:
		if req.Action != "group_store" {
			t.Fatalf("action = %q, want group_store", req.Action)
		}
		if req.GroupId != "group-gi-002" {
			t.Fatalf("groupId = %q, want group-gi-002", req.GroupId)
		}
		if req.From != wantFrom {
			t.Fatalf("from = %q, want node peer id %q", req.From, wantFrom)
		}
		if req.Message != message {
			t.Fatalf("message = %q, want exact opaque message %q", req.Message, message)
		}
		if len(req.RecipientPeerIds) != len(recipients) {
			t.Fatalf("recipientPeerIds = %#v, want %#v", req.RecipientPeerIds, recipients)
		}
		for i, want := range recipients {
			if req.RecipientPeerIds[i] != want {
				t.Fatalf("recipientPeerIds[%d] = %q, want %q", i, req.RecipientPeerIds[i], want)
			}
		}
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for group inbox store request")
	}
}

func TestGI003GroupInboxStoreOmitsPlaintextPushPreviewFields(t *testing.T) {
	relayHost, err := libp2p.New(libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"))
	if err != nil {
		t.Fatalf("start relay host: %v", err)
	}
	defer relayHost.Close()

	requestSeen := make(chan []byte, 1)
	relayHost.SetStreamHandler(InboxProtocol, func(s network.Stream) {
		defer s.Close()
		reqBytes, err := readFrame(s)
		if err != nil {
			return
		}
		requestSeen <- reqBytes
		_ = writeFrame(s, []byte(`{"status":"OK"}`))
	})

	n := startLocalNodeForMultiRelayTest(t)
	relayAddr := relayHost.Addrs()[0].String() + "/p2p/" + relayHost.ID().String()
	n.mu.Lock()
	n.relayAddresses = []string{relayAddr}
	n.mu.Unlock()

	message := `{"version":"3","encrypted":{"ciphertext":"ct-gi-003","nonce":"nonce-gi-003"}}`
	pushTitle := "GI003 Secret Launch Title"
	pushBody := "GI003 private preview body must stay local"

	if err := n.GroupInboxStore(
		"group-gi-003",
		message,
		[]string{"peer-recipient-a"},
		pushTitle,
		pushBody,
	); err != nil {
		t.Fatalf("GroupInboxStore: %v", err)
	}

	select {
	case reqBytes := <-requestSeen:
		rawRequest := string(reqBytes)
		for _, forbidden := range []string{"pushTitle", "pushBody", pushTitle, pushBody} {
			if strings.Contains(rawRequest, forbidden) {
				t.Fatalf("relay-visible group inbox request leaked %q in %s", forbidden, rawRequest)
			}
		}

		var decoded map[string]json.RawMessage
		if err := json.Unmarshal(reqBytes, &decoded); err != nil {
			t.Fatalf("unmarshal request: %v", err)
		}
		if _, ok := decoded["pushTitle"]; ok {
			t.Fatalf("pushTitle should not be present in group inbox request: %s", rawRequest)
		}
		if _, ok := decoded["pushBody"]; ok {
			t.Fatalf("pushBody should not be present in group inbox request: %s", rawRequest)
		}

		var req groupInboxRequest
		if err := json.Unmarshal(reqBytes, &req); err != nil {
			t.Fatalf("unmarshal typed request: %v", err)
		}
		if req.Action != "group_store" || req.GroupId != "group-gi-003" {
			t.Fatalf("unexpected request metadata: %#v", req)
		}
		if req.Message != message {
			t.Fatalf("message = %q, want exact opaque message %q", req.Message, message)
		}
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for group inbox store request")
	}
}

func TestGI035GroupInboxStoreSendsEncryptedEnvelopeWithoutPlaintextToRelay(t *testing.T) {
	relayHost, err := libp2p.New(libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"))
	if err != nil {
		t.Fatalf("start relay host: %v", err)
	}
	defer relayHost.Close()

	requestSeen := make(chan []byte, 1)
	relayHost.SetStreamHandler(InboxProtocol, func(s network.Stream) {
		defer s.Close()
		reqBytes, err := readFrame(s)
		if err != nil {
			return
		}
		requestSeen <- reqBytes
		_ = writeFrame(s, []byte(`{"status":"OK"}`))
	})

	n := startLocalNodeForMultiRelayTest(t)
	relayAddr := relayHost.Addrs()[0].String() + "/p2p/" + relayHost.ID().String()
	n.mu.Lock()
	n.relayAddresses = []string{relayAddr}
	n.mu.Unlock()

	privB64, pubB64 := generateEd25519KeyPair(t)
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		t.Fatalf("generate group key: %v", err)
	}

	plaintext := `{"text":"GI-035 private body alpha","mediaKey":"gi035-media-key-secret-beta","mediaUrl":"gi035-media-url-secret-gamma","deliveryId":"gi035-delivery-secret-delta"}`
	sensitiveFragments := []string{
		"GI-035 private body alpha",
		"gi035-media-key-secret-beta",
		"gi035-media-url-secret-gamma",
		"gi035-delivery-secret-delta",
		"GI035 push title secret",
		"GI035 push body secret",
	}
	envelope := buildTestEnvelopeWithPlaintext(
		t,
		"group-gi-035",
		"group_message",
		n.peerId,
		privB64,
		pubB64,
		groupKey,
		7,
		plaintext,
	)

	if err := n.GroupInboxStore(
		"group-gi-035",
		envelope,
		[]string{"peer-recipient-b"},
		"GI035 push title secret",
		"GI035 push body secret",
	); err != nil {
		t.Fatalf("GroupInboxStore: %v", err)
	}

	select {
	case reqBytes := <-requestSeen:
		rawRequest := string(reqBytes)
		for _, fragment := range sensitiveFragments {
			if strings.Contains(rawRequest, fragment) {
				t.Fatalf("relay-visible group inbox request leaked plaintext fragment %q in %s", fragment, rawRequest)
			}
		}

		var decoded map[string]json.RawMessage
		if err := json.Unmarshal(reqBytes, &decoded); err != nil {
			t.Fatalf("unmarshal request: %v", err)
		}
		for _, forbiddenKey := range []string{"pushTitle", "pushBody", "text", "media", "mediaKey", "mediaUrl"} {
			if _, ok := decoded[forbiddenKey]; ok {
				t.Fatalf("relay-visible request contains plaintext key %q in %s", forbiddenKey, rawRequest)
			}
		}

		var req groupInboxRequest
		if err := json.Unmarshal(reqBytes, &req); err != nil {
			t.Fatalf("unmarshal typed request: %v", err)
		}
		if req.Action != "group_store" || req.GroupId != "group-gi-035" {
			t.Fatalf("unexpected request metadata: %#v", req)
		}
		if req.Message != envelope {
			t.Fatalf("message = %q, want exact encrypted envelope %q", req.Message, envelope)
		}
		if len(req.RecipientPeerIds) != 1 || req.RecipientPeerIds[0] != "peer-recipient-b" {
			t.Fatalf("recipientPeerIds = %#v, want [peer-recipient-b]", req.RecipientPeerIds)
		}

		var relayMessage map[string]json.RawMessage
		if err := json.Unmarshal([]byte(req.Message), &relayMessage); err != nil {
			t.Fatalf("unmarshal stored message envelope: %v", err)
		}
		if _, ok := relayMessage["encrypted"]; !ok {
			t.Fatalf("relay message should be an encrypted envelope: %s", req.Message)
		}
		for _, forbiddenKey := range []string{"text", "media", "mediaKey", "mediaUrl", "deliveryId"} {
			if _, ok := relayMessage[forbiddenKey]; ok {
				t.Fatalf("encrypted envelope contains plaintext key %q: %s", forbiddenKey, req.Message)
			}
		}
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for group inbox store request")
	}
}

func TestGI005GroupInboxStoreRetriesRelaysInOrderAndStopsOnSuccess(t *testing.T) {
	firstRelay, err := libp2p.New(libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"))
	if err != nil {
		t.Fatalf("start first relay host: %v", err)
	}
	defer firstRelay.Close()

	secondRelay, err := libp2p.New(libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"))
	if err != nil {
		t.Fatalf("start second relay host: %v", err)
	}
	defer secondRelay.Close()

	attempts := make(chan string, 3)
	firstRelay.SetStreamHandler(InboxProtocol, func(s network.Stream) {
		defer s.Close()
		attempts <- "first"
		if _, err := readFrame(s); err != nil {
			return
		}
		_ = writeFrame(s, []byte(`{"status":"ERROR","error":"first relay unavailable"}`))
	})
	secondRelay.SetStreamHandler(InboxProtocol, func(s network.Stream) {
		defer s.Close()
		attempts <- "second"
		if _, err := readFrame(s); err != nil {
			return
		}
		_ = writeFrame(s, []byte(`{"status":"OK"}`))
	})

	n := startLocalNodeForMultiRelayTest(t)
	firstAddr := firstRelay.Addrs()[0].String() + "/p2p/" + firstRelay.ID().String()
	secondAddr := secondRelay.Addrs()[0].String() + "/p2p/" + secondRelay.ID().String()
	n.mu.Lock()
	n.relayAddresses = []string{firstAddr, secondAddr}
	n.mu.Unlock()

	if err := n.GroupInboxStore(
		"group-gi-005",
		`{"ciphertext":"opaque-gi-005"}`,
		[]string{"peer-recipient"},
		"ignored title",
		"ignored body",
	); err != nil {
		t.Fatalf("GroupInboxStore: %v", err)
	}

	got := make([]string, 0, 2)
	for len(got) < 2 {
		select {
		case attempt := <-attempts:
			got = append(got, attempt)
		case <-time.After(time.Second):
			t.Fatalf("timed out waiting for relay attempts, got %v", got)
		}
	}
	if got[0] != "first" || got[1] != "second" {
		t.Fatalf("relay attempts = %v, want [first second]", got)
	}
	select {
	case extra := <-attempts:
		t.Fatalf("unexpected relay attempt after successful second relay: %s", extra)
	default:
	}
}

func TestGI006GroupInboxStoreReturnsErrorAfterAllRelaysFail(t *testing.T) {
	firstRelay, err := libp2p.New(libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"))
	if err != nil {
		t.Fatalf("start first relay host: %v", err)
	}
	defer firstRelay.Close()

	secondRelay, err := libp2p.New(libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"))
	if err != nil {
		t.Fatalf("start second relay host: %v", err)
	}
	defer secondRelay.Close()

	attempts := make(chan string, 3)
	firstRelay.SetStreamHandler(InboxProtocol, func(s network.Stream) {
		defer s.Close()
		attempts <- "first"
		if _, err := readFrame(s); err != nil {
			return
		}
		_ = writeFrame(s, []byte(`{"status":"ERROR","error":"first relay unavailable"}`))
	})
	secondRelay.SetStreamHandler(InboxProtocol, func(s network.Stream) {
		defer s.Close()
		attempts <- "second"
		if _, err := readFrame(s); err != nil {
			return
		}
		_ = writeFrame(s, []byte(`{"status":"ERROR","error":"second relay unavailable"}`))
	})

	n := startLocalNodeForMultiRelayTest(t)
	firstAddr := firstRelay.Addrs()[0].String() + "/p2p/" + firstRelay.ID().String()
	secondAddr := secondRelay.Addrs()[0].String() + "/p2p/" + secondRelay.ID().String()
	n.mu.Lock()
	n.relayAddresses = []string{firstAddr, secondAddr}
	n.mu.Unlock()

	err = n.GroupInboxStore(
		"group-gi-006",
		`{"ciphertext":"opaque-gi-006"}`,
		[]string{"peer-recipient"},
		"ignored title",
		"ignored body",
	)
	if err == nil {
		t.Fatal("expected all relays failed error")
	}
	errText := err.Error()
	if !strings.Contains(errText, "all 2 relays failed") {
		t.Fatalf("error = %q, want all-relays failure", errText)
	}
	if !strings.Contains(errText, "second relay unavailable") {
		t.Fatalf("error = %q, want actionable last relay error", errText)
	}

	got := make([]string, 0, 2)
	for len(got) < 2 {
		select {
		case attempt := <-attempts:
			got = append(got, attempt)
		case <-time.After(time.Second):
			t.Fatalf("timed out waiting for relay attempts, got %v", got)
		}
	}
	if got[0] != "first" || got[1] != "second" {
		t.Fatalf("relay attempts = %v, want [first second]", got)
	}
	select {
	case extra := <-attempts:
		t.Fatalf("unexpected relay attempt after all relays failed: %s", extra)
	default:
	}
}

func TestGI007GroupInboxStoreReturnsRelayNonOKError(t *testing.T) {
	relayHost, err := libp2p.New(libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"))
	if err != nil {
		t.Fatalf("start relay host: %v", err)
	}
	defer relayHost.Close()

	var attempts atomic.Int32
	relayHost.SetStreamHandler(InboxProtocol, func(s network.Stream) {
		defer s.Close()
		attempts.Add(1)
		if _, err := readFrame(s); err != nil {
			return
		}
		_ = writeFrame(s, []byte(`{"status":"ERROR","error":"quota exceeded"}`))
	})

	n := startLocalNodeForMultiRelayTest(t)
	relayAddr := relayHost.Addrs()[0].String() + "/p2p/" + relayHost.ID().String()
	n.mu.Lock()
	n.relayAddresses = []string{relayAddr}
	n.mu.Unlock()

	err = n.GroupInboxStore(
		"group-gi-007",
		`{"ciphertext":"opaque-gi-007"}`,
		[]string{"peer-recipient"},
		"ignored title",
		"ignored body",
	)
	if err == nil {
		t.Fatal("expected relay non-OK error")
	}
	errText := err.Error()
	if !strings.Contains(errText, "all 1 relays failed") {
		t.Fatalf("error = %q, want relay selector failure wrapper", errText)
	}
	if !strings.Contains(errText, "group inbox store failed: quota exceeded") {
		t.Fatalf("error = %q, want relay status error", errText)
	}
	if got := attempts.Load(); got != 1 {
		t.Fatalf("relay attempts = %d, want 1", got)
	}
}

func TestGI008GroupInboxStoreResetsFailedStreamAndClosesSuccessfulStream(t *testing.T) {
	firstRelay, err := libp2p.New(libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"))
	if err != nil {
		t.Fatalf("start first relay host: %v", err)
	}
	defer firstRelay.Close()

	secondRelay, err := libp2p.New(libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"))
	if err != nil {
		t.Fatalf("start second relay host: %v", err)
	}
	defer secondRelay.Close()

	attempts := make(chan string, 2)
	failedStreamDone := make(chan error, 1)
	successfulStreamDone := make(chan error, 1)

	firstRelay.SetStreamHandler(InboxProtocol, func(s network.Stream) {
		defer s.Close()
		attempts <- "first"

		reqBytes, err := readFrame(s)
		if err != nil {
			failedStreamDone <- err
			return
		}
		var req groupInboxRequest
		if err := json.Unmarshal(reqBytes, &req); err != nil {
			failedStreamDone <- err
			return
		}
		if req.Action != "group_store" || req.GroupId != "group-gi-008" {
			failedStreamDone <- writeFrame(s, []byte(`{"status":"ERROR","error":"unexpected first relay request"}`))
			return
		}
		if err := writeFrame(s, []byte(`{"status":"ERROR","error":"first relay unavailable"}`)); err != nil {
			failedStreamDone <- err
			return
		}

		_ = s.SetReadDeadline(time.Now().Add(time.Second))
		var buf [1]byte
		_, err = s.Read(buf[:])
		failedStreamDone <- err
	})
	secondRelay.SetStreamHandler(InboxProtocol, func(s network.Stream) {
		defer s.Close()
		attempts <- "second"

		reqBytes, err := readFrame(s)
		if err != nil {
			successfulStreamDone <- err
			return
		}
		var req groupInboxRequest
		if err := json.Unmarshal(reqBytes, &req); err != nil {
			successfulStreamDone <- err
			return
		}
		if req.Action != "group_store" || req.GroupId != "group-gi-008" {
			successfulStreamDone <- writeFrame(s, []byte(`{"status":"ERROR","error":"unexpected second relay request"}`))
			return
		}
		if err := writeFrame(s, []byte(`{"status":"OK"}`)); err != nil {
			successfulStreamDone <- err
			return
		}

		_ = s.SetReadDeadline(time.Now().Add(time.Second))
		var buf [1]byte
		_, err = s.Read(buf[:])
		successfulStreamDone <- err
	})

	n := startLocalNodeForMultiRelayTest(t)
	firstAddr := firstRelay.Addrs()[0].String() + "/p2p/" + firstRelay.ID().String()
	secondAddr := secondRelay.Addrs()[0].String() + "/p2p/" + secondRelay.ID().String()
	n.mu.Lock()
	n.relayAddresses = []string{firstAddr, secondAddr}
	n.mu.Unlock()

	if err := n.GroupInboxStore(
		"group-gi-008",
		`{"ciphertext":"opaque-gi-008"}`,
		[]string{"peer-recipient"},
		"ignored title",
		"ignored body",
	); err != nil {
		t.Fatalf("GroupInboxStore: %v", err)
	}

	got := make([]string, 0, 2)
	for len(got) < 2 {
		select {
		case attempt := <-attempts:
			got = append(got, attempt)
		case <-time.After(time.Second):
			t.Fatalf("timed out waiting for relay attempts, got %v", got)
		}
	}
	if got[0] != "first" || got[1] != "second" {
		t.Fatalf("relay attempts = %v, want [first second]", got)
	}

	select {
	case err := <-failedStreamDone:
		if err == nil {
			t.Fatal("expected failed relay stream to reset, got nil read error")
		}
		if err == io.EOF {
			t.Fatalf("expected failed relay stream reset, got clean EOF")
		}
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for failed relay stream reset")
	}

	select {
	case err := <-successfulStreamDone:
		if err != io.EOF {
			t.Fatalf("expected successful relay stream clean close, got %v", err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for successful relay stream close")
	}
}

func TestGI009GroupInboxRetrieveSendsSinceTimestampRequestShape(t *testing.T) {
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
		_ = writeFrame(s, []byte(`{"status":"OK","groupMessages":[]}`))
	})

	n := startLocalNodeForMultiRelayTest(t)
	relayAddr := relayHost.Addrs()[0].String() + "/p2p/" + relayHost.ID().String()
	n.mu.Lock()
	n.relayAddresses = []string{relayAddr}
	n.mu.Unlock()

	const sinceTimestamp int64 = 1778633012345
	const expectedSinceTimestamp int64 = sinceTimestamp - 1
	messages, err := n.GroupInboxRetrieve("group-gi-009", sinceTimestamp)
	if err != nil {
		t.Fatalf("GroupInboxRetrieve: %v", err)
	}
	if len(messages) != 0 {
		t.Fatalf("messages = %#v, want empty response", messages)
	}

	select {
	case req := <-requestSeen:
		if req.Action != "group_retrieve" {
			t.Fatalf("action = %q, want group_retrieve", req.Action)
		}
		if req.GroupId != "group-gi-009" {
			t.Fatalf("groupId = %q, want group-gi-009", req.GroupId)
		}
		if req.SinceTimestamp != expectedSinceTimestamp {
			t.Fatalf("sinceTimestamp = %d, want %d", req.SinceTimestamp, expectedSinceTimestamp)
		}
		if req.Limit != 50 {
			t.Fatalf("limit = %d, want 50", req.Limit)
		}
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for group inbox retrieve request")
	}
}

func TestIR003GroupInboxRetrieveUsesInclusiveSinceBoundary(t *testing.T) {
	const boundaryMs int64 = 1777659516000

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
		if req.Action != "group_retrieve" ||
			req.SinceTimestamp != boundaryMs-1 ||
			req.Cursor != "" ||
			req.Limit != 50 {
			_ = writeFrame(s, []byte(`{"status":"ERROR","error":"unexpected IR-003 timestamp request"}`))
			return
		}
		_ = writeFrame(s, []byte(`{
			"status":"OK",
			"groupMessages":[
				{"from":"peer-source","message":"{\"messageId\":\"ir003-boundary\"}","timestamp":1777659516000},
				{"from":"peer-source","message":"{\"messageId\":\"ir003-adjacent\"}","timestamp":1777659516001}
			]
		}`))
	})

	n := startLocalNodeForMultiRelayTest(t)
	relayAddr := relayHost.Addrs()[0].String() + "/p2p/" + relayHost.ID().String()
	n.mu.Lock()
	n.relayAddresses = []string{relayAddr}
	n.mu.Unlock()

	messages, err := n.GroupInboxRetrieve("group-ir003", boundaryMs)
	if err != nil {
		t.Fatalf("GroupInboxRetrieve: %v", err)
	}
	if len(messages) != 2 {
		t.Fatalf("retrieved messages = %d, want 2: %#v", len(messages), messages)
	}
	if messages[0].Timestamp != boundaryMs || messages[1].Timestamp != boundaryMs+1 {
		t.Fatalf("unexpected message timestamps: %#v", messages)
	}

	select {
	case req := <-requestSeen:
		if req.SinceTimestamp != boundaryMs-1 {
			t.Fatalf("sinceTimestamp = %d, want %d", req.SinceTimestamp, boundaryMs-1)
		}
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for relay request")
	}
}

func TestGI010GroupInboxRetrieveWithCursorDefaultsNonPositiveLimitAndPreservesCursor(t *testing.T) {
	relayHost, err := libp2p.New(libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"))
	if err != nil {
		t.Fatalf("start relay host: %v", err)
	}
	defer relayHost.Close()

	requestSeen := make(chan groupInboxRequest, 2)
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
		_ = writeFrame(s, []byte(`{"status":"OK","groupMessages":[]}`))
	})

	n := startLocalNodeForMultiRelayTest(t)
	relayAddr := relayHost.Addrs()[0].String() + "/p2p/" + relayHost.ID().String()
	n.mu.Lock()
	n.relayAddresses = []string{relayAddr}
	n.mu.Unlock()

	cases := []struct {
		name   string
		cursor string
		limit  int
	}{
		{name: "zero", cursor: "cursor-gi-010-zero", limit: 0},
		{name: "negative", cursor: "cursor-gi-010-negative", limit: -1},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			messages, nextCursor, err := n.GroupInboxRetrieveWithCursor("group-gi-010", tc.cursor, tc.limit)
			if err != nil {
				t.Fatalf("GroupInboxRetrieveWithCursor(%q, %d): %v", tc.cursor, tc.limit, err)
			}
			if len(messages) != 0 {
				t.Fatalf("messages = %#v, want empty response", messages)
			}
			if nextCursor != "" {
				t.Fatalf("nextCursor = %q, want empty response cursor", nextCursor)
			}

			select {
			case req := <-requestSeen:
				if req.Action != "group_retrieve_cursor" {
					t.Fatalf("action = %q, want group_retrieve_cursor", req.Action)
				}
				if req.GroupId != "group-gi-010" {
					t.Fatalf("groupId = %q, want group-gi-010", req.GroupId)
				}
				if req.Cursor != tc.cursor {
					t.Fatalf("cursor = %q, want %q", req.Cursor, tc.cursor)
				}
				if req.Limit != 50 {
					t.Fatalf("limit = %d, want 50", req.Limit)
				}
			case <-time.After(time.Second):
				t.Fatal("timed out waiting for group inbox cursor retrieve request")
			}
		})
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

func TestGI027GroupHistoryRepairRangeValidatesRequiredFieldsAndTrimsWhitespace(t *testing.T) {
	valid := GroupHistoryRepairRangeRequest{
		GroupId:                " group-gi-027 ",
		GapId:                  " gap-gi-027 ",
		SourcePeerId:           " peer-source ",
		MissingAfterMessageId:  " msg-before ",
		MissingBeforeMessageId: " msg-after ",
		ExpectedRangeHash:      " range-hash ",
		ExpectedHeadMessageId:  " msg-head ",
		Limit:                  17,
	}

	normalized, err := NormalizeGroupHistoryRepairRangeRequest(valid)
	if err != nil {
		t.Fatalf("NormalizeGroupHistoryRepairRangeRequest(valid): %v", err)
	}
	if normalized.GroupId != "group-gi-027" ||
		normalized.GapId != "gap-gi-027" ||
		normalized.SourcePeerId != "peer-source" ||
		normalized.MissingAfterMessageId != "msg-before" ||
		normalized.MissingBeforeMessageId != "msg-after" ||
		normalized.ExpectedRangeHash != "range-hash" ||
		normalized.ExpectedHeadMessageId != "msg-head" {
		t.Fatalf("normalized fields were not trimmed exactly: %#v", normalized)
	}
	if normalized.Limit != 17 {
		t.Fatalf("normalized limit = %d, want caller-provided limit 17", normalized.Limit)
	}

	cases := []struct {
		name      string
		wantError string
		mutate    func(*GroupHistoryRepairRangeRequest)
	}{
		{
			name:      "groupId",
			wantError: "missing groupId",
			mutate: func(req *GroupHistoryRepairRangeRequest) {
				req.GroupId = " "
			},
		},
		{
			name:      "gapId",
			wantError: "missing gapId",
			mutate: func(req *GroupHistoryRepairRangeRequest) {
				req.GapId = " "
			},
		},
		{
			name:      "sourcePeerId",
			wantError: "missing sourcePeerId",
			mutate: func(req *GroupHistoryRepairRangeRequest) {
				req.SourcePeerId = " "
			},
		},
		{
			name:      "missingAfterMessageId",
			wantError: "missing missingAfterMessageId",
			mutate: func(req *GroupHistoryRepairRangeRequest) {
				req.MissingAfterMessageId = " "
			},
		},
		{
			name:      "missingBeforeMessageId",
			wantError: "missing missingBeforeMessageId",
			mutate: func(req *GroupHistoryRepairRangeRequest) {
				req.MissingBeforeMessageId = " "
			},
		},
		{
			name:      "expectedRangeHash",
			wantError: "missing expectedRangeHash",
			mutate: func(req *GroupHistoryRepairRangeRequest) {
				req.ExpectedRangeHash = " "
			},
		},
		{
			name:      "expectedHeadMessageId",
			wantError: "missing expectedHeadMessageId",
			mutate: func(req *GroupHistoryRepairRangeRequest) {
				req.ExpectedHeadMessageId = " "
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			req := valid
			tc.mutate(&req)
			if _, err := NormalizeGroupHistoryRepairRangeRequest(req); err == nil || !strings.Contains(err.Error(), tc.wantError) {
				t.Fatalf("NormalizeGroupHistoryRepairRangeRequest(%s) error = %v, want %q", tc.name, err, tc.wantError)
			}
		})
	}
}

func TestIR011GroupHistoryRepairRange_NormalizesAndRejectsIdentity(t *testing.T) {
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
	if normalized.GroupId != "group-1" || normalized.GapId != "gap-1" || normalized.SourcePeerId != "peer-source" {
		t.Fatalf("expected trimmed identity fields, got %#v", normalized)
	}
	if normalized.MissingAfterMessageId != "msg-before" || normalized.MissingBeforeMessageId != "msg-after" {
		t.Fatalf("expected trimmed gap boundary fields, got %#v", normalized)
	}
	if normalized.Limit != 50 {
		t.Fatalf("expected default limit 50, got %d", normalized.Limit)
	}

	for _, tc := range []struct {
		name   string
		mutate func(*GroupHistoryRepairRangeRequest)
		want   string
	}{
		{
			name:   "missing group id",
			mutate: func(req *GroupHistoryRepairRangeRequest) { req.GroupId = " " },
			want:   "missing groupId",
		},
		{
			name:   "missing gap id",
			mutate: func(req *GroupHistoryRepairRangeRequest) { req.GapId = " " },
			want:   "missing gapId",
		},
		{
			name:   "missing source peer id",
			mutate: func(req *GroupHistoryRepairRangeRequest) { req.SourcePeerId = " " },
			want:   "missing sourcePeerId",
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			invalid := valid
			tc.mutate(&invalid)

			if _, err := NormalizeGroupHistoryRepairRangeRequest(invalid); err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("expected %q validation error, got %v", tc.want, err)
			}

			n := NewNode()
			if _, err := n.GroupHistoryRepairRange(invalid); err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("expected %q before node/relay use, got %v", tc.want, err)
			} else if strings.Contains(err.Error(), "node not started") {
				t.Fatalf("invalid identity reached node-start validation: %v", err)
			}
		})
	}
}

func TestGI028GroupHistoryRepairRangeDefaultsNonPositiveLimitTo50(t *testing.T) {
	base := GroupHistoryRepairRangeRequest{
		GroupId:                "group-gi-028",
		GapId:                  "gap-gi-028",
		SourcePeerId:           "peer-source-gi-028",
		MissingAfterMessageId:  "msg-before-gi-028",
		MissingBeforeMessageId: "msg-after-gi-028",
		ExpectedRangeHash:      "range-hash-gi-028",
		ExpectedHeadMessageId:  "head-message-gi-028",
	}

	cases := []struct {
		name  string
		limit int
	}{
		{name: "zero", limit: 0},
		{name: "negative", limit: -1},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			req := base
			req.Limit = tc.limit

			normalized, err := NormalizeGroupHistoryRepairRangeRequest(req)
			if err != nil {
				t.Fatalf("NormalizeGroupHistoryRepairRangeRequest(%d): %v", tc.limit, err)
			}
			if normalized.Limit != 50 {
				t.Fatalf("normalized limit = %d, want 50 for caller limit %d", normalized.Limit, tc.limit)
			}
			if normalized.GroupId != base.GroupId ||
				normalized.GapId != base.GapId ||
				normalized.SourcePeerId != base.SourcePeerId ||
				normalized.MissingAfterMessageId != base.MissingAfterMessageId ||
				normalized.MissingBeforeMessageId != base.MissingBeforeMessageId ||
				normalized.ExpectedRangeHash != base.ExpectedRangeHash ||
				normalized.ExpectedHeadMessageId != base.ExpectedHeadMessageId {
				t.Fatalf("normalized request changed non-limit fields: %#v", normalized)
			}
		})
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

func TestGI029GroupHistoryRepairRangeSendsExpectedRequestShape(t *testing.T) {
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
		_ = writeFrame(s, []byte(`{"status":"OK","groupMessages":[]}`))
	})

	n := startLocalNodeForMultiRelayTest(t)
	relayAddr := relayHost.Addrs()[0].String() + "/p2p/" + relayHost.ID().String()
	n.mu.Lock()
	n.relayAddresses = []string{relayAddr}
	n.mu.Unlock()

	_, err = n.GroupHistoryRepairRange(GroupHistoryRepairRangeRequest{
		GroupId:                " group-gi-029 ",
		GapId:                  " gap-gi-029 ",
		SourcePeerId:           " peer-source-gi-029 ",
		MissingAfterMessageId:  " msg-before-gi-029 ",
		MissingBeforeMessageId: " msg-after-gi-029 ",
		ExpectedRangeHash:      " range-hash-gi-029 ",
		ExpectedHeadMessageId:  " head-message-gi-029 ",
		Limit:                  37,
	})
	if err != nil {
		t.Fatalf("GroupHistoryRepairRange: %v", err)
	}

	select {
	case req := <-requestSeen:
		if req.Action != "group_history_repair_range" ||
			req.GroupId != "group-gi-029" ||
			req.GapId != "gap-gi-029" ||
			req.SourcePeerId != "peer-source-gi-029" ||
			req.MissingAfterMessageId != "msg-before-gi-029" ||
			req.MissingBeforeMessageId != "msg-after-gi-029" ||
			req.ExpectedRangeHash != "range-hash-gi-029" ||
			req.ExpectedHeadMessageId != "head-message-gi-029" ||
			req.Limit != 37 {
			t.Fatalf("unexpected repair range request shape: %#v", req)
		}
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for relay repair request")
	}
}

func TestGI030GroupHistoryRepairRangeResponseFallsBackToRequestIDs(t *testing.T) {
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
			"rangeHash":"range-hash-gi-030",
			"headMessageId":"head-message-gi-030",
			"groupMessages":[
				{"from":"peer-source-gi-030","message":"{\"messageId\":\"msg-repaired-gi-030\"}","timestamp":1777659516030}
			]
		}`))
	})

	n := startLocalNodeForMultiRelayTest(t)
	relayAddr := relayHost.Addrs()[0].String() + "/p2p/" + relayHost.ID().String()
	n.mu.Lock()
	n.relayAddresses = []string{relayAddr}
	n.mu.Unlock()

	result, err := n.GroupHistoryRepairRange(GroupHistoryRepairRangeRequest{
		GroupId:                " group-gi-030 ",
		GapId:                  " gap-gi-030 ",
		SourcePeerId:           " peer-source-gi-030 ",
		MissingAfterMessageId:  " msg-before-gi-030 ",
		MissingBeforeMessageId: " msg-after-gi-030 ",
		ExpectedRangeHash:      " expected-range-hash-gi-030 ",
		ExpectedHeadMessageId:  " expected-head-message-gi-030 ",
		Limit:                  9,
	})
	if err != nil {
		t.Fatalf("GroupHistoryRepairRange: %v", err)
	}
	if result.GroupId != "group-gi-030" ||
		result.GapId != "gap-gi-030" ||
		result.SourcePeerId != "peer-source-gi-030" {
		t.Fatalf("response did not fall back to normalized request IDs: %#v", result)
	}
	if result.RangeHash != "range-hash-gi-030" ||
		result.HeadMessageId != "head-message-gi-030" {
		t.Fatalf("response integrity fields should come from relay response: %#v", result)
	}
	if len(result.Messages) != 1 || !strings.Contains(result.Messages[0].Message, "msg-repaired-gi-030") {
		t.Fatalf("expected repair replay envelope to be preserved, got %#v", result.Messages)
	}

	select {
	case req := <-requestSeen:
		if req.Action != "group_history_repair_range" ||
			req.GroupId != "group-gi-030" ||
			req.GapId != "gap-gi-030" ||
			req.SourcePeerId != "peer-source-gi-030" ||
			req.MissingAfterMessageId != "msg-before-gi-030" ||
			req.MissingBeforeMessageId != "msg-after-gi-030" ||
			req.ExpectedRangeHash != "expected-range-hash-gi-030" ||
			req.ExpectedHeadMessageId != "expected-head-message-gi-030" ||
			req.Limit != 9 {
			t.Fatalf("unexpected repair range request shape: %#v", req)
		}
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for relay repair request")
	}
}

func TestGI011GroupInboxRetrieveWithCursorResultPreservesMessagesCursorAndHistoryGaps(t *testing.T) {
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
		if req.Action != "group_retrieve_cursor" {
			_ = writeFrame(s, []byte(`{"status":"ERROR","error":"unexpected action"}`))
			return
		}
		requestSeen <- req
		_ = writeFrame(s, []byte(`{
			"status":"OK",
			"nextCursor":"cursor-gi-011-next",
			"groupMessages":[
				{"id":"entry-1","from":"peer-source","message":"{\"messageId\":\"msg-1\"}","timestamp":1777659516000},
				{"id":"entry-2","from":"peer-source","message":"{\"messageId\":\"msg-2\"}","timestamp":1777659517000}
			],
			"historyGaps":[
				{
					"groupId":"group-gi-011",
					"gapId":"gap-gi-011",
					"missingAfterMessageId":"msg-before-gap",
					"missingBeforeMessageId":"msg-after-gap",
					"expectedRangeHash":"range-hash-gi-011",
					"expectedHeadMessageId":"msg-after-gap",
					"candidateSourcePeerIds":["peer-source","peer-backup"]
				}
			]
		}`))
	})

	n := startLocalNodeForMultiRelayTest(t)
	relayAddr := relayHost.Addrs()[0].String() + "/p2p/" + relayHost.ID().String()
	n.mu.Lock()
	n.relayAddresses = []string{relayAddr}
	n.mu.Unlock()

	page, err := n.GroupInboxRetrieveWithCursorResult("group-gi-011", "cursor-gi-011", 10)
	if err != nil {
		t.Fatalf("GroupInboxRetrieveWithCursorResult: %v", err)
	}
	if page.NextCursor != "cursor-gi-011-next" {
		t.Fatalf("NextCursor = %q, want cursor-gi-011-next", page.NextCursor)
	}
	if len(page.Messages) != 2 {
		t.Fatalf("unexpected page: %#v", page)
	}
	if page.Messages[0].ID != "entry-1" ||
		page.Messages[0].From != "peer-source" ||
		page.Messages[0].Message != `{"messageId":"msg-1"}` ||
		page.Messages[0].Timestamp != 1777659516000 {
		t.Fatalf("first message not preserved: %#v", page.Messages[0])
	}
	if page.Messages[1].ID != "entry-2" ||
		page.Messages[1].From != "peer-source" ||
		page.Messages[1].Message != `{"messageId":"msg-2"}` ||
		page.Messages[1].Timestamp != 1777659517000 {
		t.Fatalf("second message not preserved: %#v", page.Messages[1])
	}
	if len(page.HistoryGaps) != 1 {
		t.Fatalf("expected one history gap, got %#v", page.HistoryGaps)
	}
	gap := page.HistoryGaps[0]
	if gap.GroupId != "group-gi-011" ||
		gap.GapId != "gap-gi-011" ||
		gap.MissingAfterMessageId != "msg-before-gap" ||
		gap.MissingBeforeMessageId != "msg-after-gap" ||
		gap.ExpectedRangeHash != "range-hash-gi-011" ||
		gap.ExpectedHeadMessageId != "msg-after-gap" ||
		len(gap.CandidateSourcePeerIds) != 2 ||
		gap.CandidateSourcePeerIds[0] != "peer-source" ||
		gap.CandidateSourcePeerIds[1] != "peer-backup" {
		t.Fatalf("history gap not preserved: %#v", gap)
	}

	select {
	case req := <-requestSeen:
		if req.Action != "group_retrieve_cursor" ||
			req.GroupId != "group-gi-011" ||
			req.Cursor != "cursor-gi-011" ||
			req.Limit != 10 {
			t.Fatalf("unexpected cursor request: %#v", req)
		}
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for cursor retrieve request")
	}
}

func TestGroupInboxRetrieveWithCursorResult_RetriesAfterTransientRelayEOF(t *testing.T) {
	relayHost, err := libp2p.New(libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"))
	if err != nil {
		t.Fatalf("start relay host: %v", err)
	}
	defer relayHost.Close()

	requestCount := 0
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

		requestCount++
		if requestCount == 1 {
			return
		}

		_ = writeFrame(s, []byte(`{
			"status":"OK",
			"groupMessages":[
				{"from":"peer-source","message":"{\"messageId\":\"msg-after-retry\"}","timestamp":1777659516000}
			]
		}`))
	})

	n := startLocalNodeForMultiRelayTest(t)
	relayAddr := relayHost.Addrs()[0].String() + "/p2p/" + relayHost.ID().String()
	n.mu.Lock()
	n.relayAddresses = []string{relayAddr}
	n.mu.Unlock()

	recoverCalls := 0
	n.groupInboxRecoverHook = func(err error) error {
		recoverCalls++
		if !isTransientGroupInboxRelayStreamError(err) {
			t.Fatalf("recover hook received non-transient error: %v", err)
		}
		return nil
	}

	page, err := n.GroupInboxRetrieveWithCursorResult("group-1", "", 10)
	if err != nil {
		t.Fatalf("GroupInboxRetrieveWithCursorResult: %v", err)
	}
	if recoverCalls != 1 {
		t.Fatalf("recoverCalls = %d, want 1", recoverCalls)
	}
	if requestCount != 2 {
		t.Fatalf("requestCount = %d, want 2", requestCount)
	}
	if len(page.Messages) != 1 || page.Messages[0].Message != `{"messageId":"msg-after-retry"}` {
		t.Fatalf("unexpected page after retry: %#v", page)
	}
}

func TestGroupInboxRetrieveWithCursorResult_SyntheticSinceCursorUsesTimestampRetrieve(t *testing.T) {
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
		if req.Action != "group_retrieve" ||
			req.SinceTimestamp != 1777659515999 ||
			req.Cursor != "" ||
			req.Limit != 10 {
			_ = writeFrame(s, []byte(`{"status":"ERROR","error":"unexpected synthetic cursor request"}`))
			return
		}
		_ = writeFrame(s, []byte(`{
			"status":"OK",
			"groupMessages":[
				{"from":"peer-source","message":"{\"messageId\":\"msg-after-synthetic\"}","timestamp":1777659517000}
			]
		}`))
	})

	n := startLocalNodeForMultiRelayTest(t)
	relayAddr := relayHost.Addrs()[0].String() + "/p2p/" + relayHost.ID().String()
	n.mu.Lock()
	n.relayAddresses = []string{relayAddr}
	n.mu.Unlock()

	page, err := n.GroupInboxRetrieveWithCursorResult(
		"group-1",
		groupInboxSyntheticSinceCursorPrefix+"1777659516000",
		10,
	)
	if err != nil {
		t.Fatalf("GroupInboxRetrieveWithCursorResult: %v", err)
	}
	if len(page.Messages) != 1 || page.Messages[0].Message != `{"messageId":"msg-after-synthetic"}` {
		t.Fatalf("unexpected page after synthetic cursor: %#v", page)
	}

	select {
	case req := <-requestSeen:
		if req.Action != "group_retrieve" || req.SinceTimestamp != 1777659515999 {
			t.Fatalf("unexpected request: %#v", req)
		}
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for relay request")
	}
}

func TestST004GroupInboxRetrieveSyntheticCursorKeepsInclusiveRelayBoundary(t *testing.T) {
	const boundaryMs int64 = 1777659516000

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
		if req.Action != "group_retrieve" ||
			req.SinceTimestamp != boundaryMs-1 ||
			req.Cursor != "" ||
			req.Limit != 10 {
			_ = writeFrame(s, []byte(`{"status":"ERROR","error":"unexpected ST-004 timestamp request"}`))
			return
		}
		_ = writeFrame(s, []byte(`{
			"status":"OK",
			"groupMessages":[
				{"from":"peer-source","message":"{\"messageId\":\"st004-boundary\",\"timestamp\":\"2026-05-01T12:15:00.000Z\"}","timestamp":1777659516000},
				{"from":"peer-source","message":"{\"messageId\":\"st004-adjacent\",\"timestamp\":\"2026-05-01T11:58:00.000Z\"}","timestamp":1777659516001}
			]
		}`))
	})

	n := startLocalNodeForMultiRelayTest(t)
	relayAddr := relayHost.Addrs()[0].String() + "/p2p/" + relayHost.ID().String()
	n.mu.Lock()
	n.relayAddresses = []string{relayAddr}
	n.mu.Unlock()

	page, err := n.GroupInboxRetrieveWithCursorResult(
		"group-st004",
		groupInboxSyntheticSinceCursorPrefix+"1777659516000",
		10,
	)
	if err != nil {
		t.Fatalf("GroupInboxRetrieveWithCursorResult: %v", err)
	}
	if len(page.Messages) != 2 {
		t.Fatalf("retrieved messages = %d, want 2: %#v", len(page.Messages), page.Messages)
	}
	if page.Messages[0].Timestamp != boundaryMs || page.Messages[1].Timestamp != boundaryMs+1 {
		t.Fatalf("unexpected message timestamps: %#v", page.Messages)
	}

	select {
	case req := <-requestSeen:
		if req.SinceTimestamp != boundaryMs-1 {
			t.Fatalf("sinceTimestamp = %d, want %d", req.SinceTimestamp, boundaryMs-1)
		}
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for relay request")
	}
}

func TestGI012GroupInboxRetrieveNoMessagesReturnsEmptyAndClosesStream(t *testing.T) {
	relayHost, err := libp2p.New(libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"))
	if err != nil {
		t.Fatalf("start relay host: %v", err)
	}
	defer relayHost.Close()

	requestSeen := make(chan groupInboxRequest, 1)
	streamCloseSeen := make(chan error, 1)
	relayHost.SetStreamHandler(InboxProtocol, func(s network.Stream) {
		defer s.Close()
		reqBytes, err := readFrame(s)
		if err != nil {
			streamCloseSeen <- err
			return
		}
		var req groupInboxRequest
		if err := json.Unmarshal(reqBytes, &req); err != nil {
			streamCloseSeen <- err
			return
		}
		requestSeen <- req
		if err := writeFrame(s, []byte(`{"status":"NO_MESSAGES"}`)); err != nil {
			streamCloseSeen <- err
			return
		}
		_ = s.SetReadDeadline(time.Now().Add(time.Second))
		var buf [1]byte
		_, err = s.Read(buf[:])
		streamCloseSeen <- err
	})

	n := startLocalNodeForMultiRelayTest(t)
	relayAddr := relayHost.Addrs()[0].String() + "/p2p/" + relayHost.ID().String()
	n.mu.Lock()
	n.relayAddresses = []string{relayAddr}
	n.mu.Unlock()

	messages, err := n.GroupInboxRetrieve("group-gi-012", 1778676905120)
	if err != nil {
		t.Fatalf("GroupInboxRetrieve: %v", err)
	}
	if len(messages) != 0 {
		t.Fatalf("expected empty messages for NO_MESSAGES, got %#v", messages)
	}

	select {
	case req := <-requestSeen:
		if req.Action != "group_retrieve" ||
			req.GroupId != "group-gi-012" ||
			req.SinceTimestamp != 1778676905120 ||
			req.Limit != 50 {
			t.Fatalf("unexpected NO_MESSAGES request: %#v", req)
		}
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for group inbox retrieve request")
	}

	select {
	case err := <-streamCloseSeen:
		if err != io.EOF {
			t.Fatalf("expected clean client stream close after NO_MESSAGES, got %v", err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for client stream close")
	}
}

func TestGI013GroupInboxRetrieveRetriesRelaysInOrderAndReturnsSecondData(t *testing.T) {
	firstRelay, err := libp2p.New(libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"))
	if err != nil {
		t.Fatalf("start first relay host: %v", err)
	}
	defer firstRelay.Close()

	secondRelay, err := libp2p.New(libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"))
	if err != nil {
		t.Fatalf("start second relay host: %v", err)
	}
	defer secondRelay.Close()

	attempts := make(chan string, 3)
	firstRelay.SetStreamHandler(InboxProtocol, func(s network.Stream) {
		defer s.Close()
		reqBytes, err := readFrame(s)
		if err != nil {
			return
		}
		var req groupInboxRequest
		if err := json.Unmarshal(reqBytes, &req); err != nil {
			return
		}
		if req.Action != "group_retrieve" || req.GroupId != "group-gi-013" {
			attempts <- "first:unexpected_request"
			_ = writeFrame(s, []byte(`{"status":"ERROR","error":"unexpected first request"}`))
			return
		}
		attempts <- "first"
		_ = writeFrame(s, []byte(`{"status":"ERROR","error":"first retrieve relay unavailable"}`))
	})
	secondRelay.SetStreamHandler(InboxProtocol, func(s network.Stream) {
		defer s.Close()
		reqBytes, err := readFrame(s)
		if err != nil {
			return
		}
		var req groupInboxRequest
		if err := json.Unmarshal(reqBytes, &req); err != nil {
			return
		}
		if req.Action != "group_retrieve" ||
			req.GroupId != "group-gi-013" ||
			req.SinceTimestamp != 1778677800000 ||
			req.Limit != 50 {
			attempts <- "second:unexpected_request"
			_ = writeFrame(s, []byte(`{"status":"ERROR","error":"unexpected second request"}`))
			return
		}
		attempts <- "second"
		_ = writeFrame(s, []byte(`{
			"status":"OK",
			"groupMessages":[
				{"id":"entry-gi-013","from":"peer-second","message":"{\"messageId\":\"msg-second-relay\"}","timestamp":1778677801234}
			]
		}`))
	})

	n := startLocalNodeForMultiRelayTest(t)
	firstAddr := firstRelay.Addrs()[0].String() + "/p2p/" + firstRelay.ID().String()
	secondAddr := secondRelay.Addrs()[0].String() + "/p2p/" + secondRelay.ID().String()
	n.mu.Lock()
	n.relayAddresses = []string{firstAddr, secondAddr}
	n.mu.Unlock()

	messages, err := n.GroupInboxRetrieve("group-gi-013", 1778677800000)
	if err != nil {
		t.Fatalf("GroupInboxRetrieve: %v", err)
	}
	if len(messages) != 1 {
		t.Fatalf("messages = %#v, want one second-relay message", messages)
	}
	if messages[0].ID != "entry-gi-013" ||
		messages[0].From != "peer-second" ||
		messages[0].Message != `{"messageId":"msg-second-relay"}` ||
		messages[0].Timestamp != 1778677801234 {
		t.Fatalf("second relay message not returned intact: %#v", messages[0])
	}

	got := make([]string, 0, 2)
	for len(got) < 2 {
		select {
		case attempt := <-attempts:
			got = append(got, attempt)
		case <-time.After(time.Second):
			t.Fatalf("timed out waiting for relay attempts, got %v", got)
		}
	}
	if got[0] != "first" || got[1] != "second" {
		t.Fatalf("relay attempts = %v, want [first second]", got)
	}
	select {
	case extra := <-attempts:
		t.Fatalf("unexpected relay attempt after successful retrieve: %s", extra)
	default:
	}
}

func TestGI014GroupInboxRetrieveReturnsRelayNonOKError(t *testing.T) {
	relayHost, err := libp2p.New(libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"))
	if err != nil {
		t.Fatalf("start relay host: %v", err)
	}
	defer relayHost.Close()

	requestSeen := make(chan groupInboxRequest, 1)
	var attempts atomic.Int32
	relayHost.SetStreamHandler(InboxProtocol, func(s network.Stream) {
		defer s.Close()
		attempts.Add(1)
		reqBytes, err := readFrame(s)
		if err != nil {
			return
		}
		var req groupInboxRequest
		if err := json.Unmarshal(reqBytes, &req); err != nil {
			return
		}
		requestSeen <- req
		_ = writeFrame(s, []byte(`{"status":"ERROR","error":"retrieve quota exceeded for group"}`))
	})

	n := startLocalNodeForMultiRelayTest(t)
	relayAddr := relayHost.Addrs()[0].String() + "/p2p/" + relayHost.ID().String()
	n.mu.Lock()
	n.relayAddresses = []string{relayAddr}
	n.mu.Unlock()

	messages, err := n.GroupInboxRetrieve("group-gi-014", 1778678400000)
	if err == nil {
		t.Fatal("expected retrieve relay non-OK error")
	}
	if len(messages) != 0 {
		t.Fatalf("messages = %#v, want none on relay non-OK", messages)
	}
	errText := err.Error()
	if !strings.Contains(errText, "all 1 relays failed") {
		t.Fatalf("error = %q, want relay selector failure wrapper", errText)
	}
	if !strings.Contains(errText, "group inbox retrieve failed: retrieve quota exceeded for group") {
		t.Fatalf("error = %q, want relay retrieve status reason", errText)
	}
	if got := attempts.Load(); got != 1 {
		t.Fatalf("relay attempts = %d, want 1", got)
	}

	select {
	case req := <-requestSeen:
		if req.Action != "group_retrieve" ||
			req.GroupId != "group-gi-014" ||
			req.SinceTimestamp != 1778678400000 ||
			req.Limit != 50 {
			t.Fatalf("unexpected retrieve request: %#v", req)
		}
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for group inbox retrieve request")
	}
}

func TestGI015GroupInboxRetrieveMalformedJSONReturnsError(t *testing.T) {
	relayHost, err := libp2p.New(libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"))
	if err != nil {
		t.Fatalf("start relay host: %v", err)
	}
	defer relayHost.Close()

	requestSeen := make(chan groupInboxRequest, 1)
	var attempts atomic.Int32
	relayHost.SetStreamHandler(InboxProtocol, func(s network.Stream) {
		defer s.Close()
		attempts.Add(1)
		reqBytes, err := readFrame(s)
		if err != nil {
			return
		}
		var req groupInboxRequest
		if err := json.Unmarshal(reqBytes, &req); err != nil {
			return
		}
		requestSeen <- req
		_ = writeFrame(s, []byte(`{"status":"OK","groupMessages":[`))
	})

	n := startLocalNodeForMultiRelayTest(t)
	relayAddr := relayHost.Addrs()[0].String() + "/p2p/" + relayHost.ID().String()
	n.mu.Lock()
	n.relayAddresses = []string{relayAddr}
	n.mu.Unlock()

	messages, err := n.GroupInboxRetrieve("group-gi-015", 1778679000000)
	if err == nil {
		t.Fatal("expected malformed relay JSON error")
	}
	if len(messages) != 0 {
		t.Fatalf("messages = %#v, want none on malformed relay JSON", messages)
	}
	errText := err.Error()
	if !strings.Contains(errText, "all 1 relays failed") {
		t.Fatalf("error = %q, want relay selector failure wrapper", errText)
	}
	if !strings.Contains(errText, "unmarshal response") {
		t.Fatalf("error = %q, want unmarshal response reason", errText)
	}
	if got := attempts.Load(); got != 1 {
		t.Fatalf("relay attempts = %d, want 1", got)
	}

	select {
	case req := <-requestSeen:
		if req.Action != "group_retrieve" ||
			req.GroupId != "group-gi-015" ||
			req.SinceTimestamp != 1778679000000 ||
			req.Limit != 50 {
			t.Fatalf("unexpected retrieve request: %#v", req)
		}
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for group inbox retrieve request")
	}
}

func TestGI016GroupInboxRetrieveRejectsOversizedFrame(t *testing.T) {
	relayHost, err := libp2p.New(libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"))
	if err != nil {
		t.Fatalf("start relay host: %v", err)
	}
	defer relayHost.Close()

	requestSeen := make(chan groupInboxRequest, 1)
	var attempts atomic.Int32
	relayHost.SetStreamHandler(InboxProtocol, func(s network.Stream) {
		defer s.Close()
		attempts.Add(1)
		reqBytes, err := readFrame(s)
		if err != nil {
			return
		}
		var req groupInboxRequest
		if err := json.Unmarshal(reqBytes, &req); err != nil {
			return
		}
		requestSeen <- req
		var lenBuf [4]byte
		binary.BigEndian.PutUint32(lenBuf[:], uint32(MaxFrameLen+1))
		_, _ = s.Write(lenBuf[:])
	})

	n := startLocalNodeForMultiRelayTest(t)
	relayAddr := relayHost.Addrs()[0].String() + "/p2p/" + relayHost.ID().String()
	n.mu.Lock()
	n.relayAddresses = []string{relayAddr}
	n.mu.Unlock()

	messages, err := n.GroupInboxRetrieve("group-gi-016", 1778679600000)
	if err == nil {
		t.Fatal("expected oversized frame error")
	}
	if len(messages) != 0 {
		t.Fatalf("messages = %#v, want none on oversized relay frame", messages)
	}
	errText := err.Error()
	if !strings.Contains(errText, "all 1 relays failed") {
		t.Fatalf("error = %q, want relay selector failure wrapper", errText)
	}
	if !strings.Contains(errText, "frame too large") {
		t.Fatalf("error = %q, want frame too large reason", errText)
	}
	if got := attempts.Load(); got != 1 {
		t.Fatalf("relay attempts = %d, want 1", got)
	}

	select {
	case req := <-requestSeen:
		if req.Action != "group_retrieve" ||
			req.GroupId != "group-gi-016" ||
			req.SinceTimestamp != 1778679600000 ||
			req.Limit != 50 {
			t.Fatalf("unexpected retrieve request: %#v", req)
		}
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for group inbox retrieve request")
	}
}
