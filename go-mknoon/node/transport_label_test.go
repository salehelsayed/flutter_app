package node

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/core/protocol"
	ma "github.com/multiformats/go-multiaddr"
)

type stubStreamConn struct {
	remotePeer      peer.ID
	localMultiaddr  ma.Multiaddr
	remoteMultiaddr ma.Multiaddr
}

func (c *stubStreamConn) Close() error { return nil }
func (c *stubStreamConn) ID() string   { return "stub-conn" }
func (c *stubStreamConn) NewStream(context.Context) (network.Stream, error) {
	return nil, nil
}
func (c *stubStreamConn) GetStreams() []network.Stream { return nil }
func (c *stubStreamConn) IsClosed() bool               { return false }
func (c *stubStreamConn) LocalPeer() peer.ID           { return "" }
func (c *stubStreamConn) RemotePeer() peer.ID          { return c.remotePeer }
func (c *stubStreamConn) RemotePublicKey() crypto.PubKey {
	return nil
}
func (c *stubStreamConn) ConnState() network.ConnectionState {
	return network.ConnectionState{}
}
func (c *stubStreamConn) LocalMultiaddr() ma.Multiaddr  { return c.localMultiaddr }
func (c *stubStreamConn) RemoteMultiaddr() ma.Multiaddr { return c.remoteMultiaddr }
func (c *stubStreamConn) Stat() network.ConnStats       { return network.ConnStats{} }
func (c *stubStreamConn) Scope() network.ConnScope      { return nil }

type stubTransportStream struct {
	input      *bytes.Reader
	output     bytes.Buffer
	conn       network.Conn
	resetCount int
	closeCount int
}

func newStubTransportStream(
	t *testing.T,
	payload []byte,
	remotePeerID string,
	remoteMultiaddr string,
) *stubTransportStream {
	t.Helper()

	frame := new(bytes.Buffer)
	if err := writeFrame(frame, payload); err != nil {
		t.Fatalf("write frame: %v", err)
	}

	remotePeer, err := peer.Decode(remotePeerID)
	if err != nil {
		t.Fatalf("decode remote peer: %v", err)
	}

	remoteAddr, err := ma.NewMultiaddr(remoteMultiaddr)
	if err != nil {
		t.Fatalf("new remote multiaddr: %v", err)
	}

	localAddr, err := ma.NewMultiaddr("/ip4/127.0.0.1/tcp/4001")
	if err != nil {
		t.Fatalf("new local multiaddr: %v", err)
	}

	return &stubTransportStream{
		input: bytes.NewReader(frame.Bytes()),
		conn: &stubStreamConn{
			remotePeer:      remotePeer,
			localMultiaddr:  localAddr,
			remoteMultiaddr: remoteAddr,
		},
	}
}

func (s *stubTransportStream) Read(p []byte) (int, error)  { return s.input.Read(p) }
func (s *stubTransportStream) Write(p []byte) (int, error) { return s.output.Write(p) }
func (s *stubTransportStream) Close() error {
	s.closeCount++
	return nil
}
func (s *stubTransportStream) CloseRead() error  { return nil }
func (s *stubTransportStream) CloseWrite() error { return nil }
func (s *stubTransportStream) Reset() error {
	s.resetCount++
	return nil
}
func (s *stubTransportStream) SetDeadline(time.Time) error { return nil }
func (s *stubTransportStream) SetReadDeadline(time.Time) error {
	return nil
}
func (s *stubTransportStream) SetWriteDeadline(time.Time) error {
	return nil
}
func (s *stubTransportStream) ID() string            { return "stub-stream" }
func (s *stubTransportStream) Protocol() protocol.ID { return ChatProtocol }
func (s *stubTransportStream) SetProtocol(protocol.ID) error {
	return nil
}
func (s *stubTransportStream) Stat() network.Stats        { return network.Stats{} }
func (s *stubTransportStream) Conn() network.Conn         { return s.conn }
func (s *stubTransportStream) Scope() network.StreamScope { return nil }

type directConfirmCallback struct {
	node            *Node
	confirmResults  []bool
	callWakeReceipt string
	delay           time.Duration
}

func (c *directConfirmCallback) OnEvent(jsonStr string) {
	if c.node == nil {
		return
	}

	var payload struct {
		Event string                 `json:"event"`
		Data  map[string]interface{} `json:"data"`
	}
	if err := json.Unmarshal([]byte(jsonStr), &payload); err != nil {
		return
	}
	if payload.Event != "message:received" {
		return
	}

	nonce, _ := payload.Data["confirmNonce"].(string)
	if nonce == "" {
		return
	}
	if c.delay > 0 {
		time.Sleep(c.delay)
	}
	for _, ok := range c.confirmResults {
		if c.callWakeReceipt != "" {
			c.node.ResolveDirectConfirmWithReceipt(nonce, ok, c.callWakeReceipt)
		} else {
			c.node.ResolveDirectConfirm(nonce, ok)
		}
	}
}

func newDeferredAckTestNode(
	t *testing.T,
	cb EventCallback,
	timeout time.Duration,
) *Node {
	t.Helper()

	n := New(cb)
	n.peerId = "self-peer"
	n.isStarted = true
	n.directConfirmTimeoutOverride = timeout
	n.eventDispatcher = NewEventDispatcher(cb, 16)
	t.Cleanup(func() {
		n.eventDispatcher.Stop()
	})
	return n
}

func chatEnvelopeForTest(t *testing.T, id string) []byte {
	t.Helper()
	envelope := map[string]interface{}{
		"type":    "chat_message",
		"version": "1",
		"payload": map[string]interface{}{
			"id":             id,
			"text":           "hello",
			"senderPeerId":   generatePeerIDStr(t),
			"senderUsername": "Alice",
			"timestamp":      time.Now().UTC().Format(time.RFC3339Nano),
		},
	}
	raw, err := json.Marshal(envelope)
	if err != nil {
		t.Fatalf("json.Marshal(chatEnvelope): %v", err)
	}
	return raw
}

func ackPayloadFromStream(t *testing.T, stream *stubTransportStream) string {
	t.Helper()
	reply, err := readFrame(bytes.NewReader(stream.output.Bytes()))
	if err != nil {
		t.Fatalf("readFrame(ack): %v", err)
	}
	return string(reply)
}

// contactRequestEnvelopeForTest builds a minimal type=="contact_request" v2
// envelope. The Go node never decrypts it — shouldDeferDirectAck inspects only
// the envelope "type" — so the encrypted body is a deliberate stub; this
// exercises the defer/ack-wait wire behaviour, not Dart-side decryption.
func contactRequestEnvelopeForTest(t *testing.T, msgId string) []byte {
	t.Helper()
	envelope := map[string]interface{}{
		"type":    "contact_request",
		"version": "2",
		"msgId":   msgId,
		"ts":      time.Now().UTC().Format(time.RFC3339Nano),
		"encrypted": map[string]interface{}{
			"ephemeralPublicKey": "stub",
			"ciphertext":         "stub",
			"nonce":              "stub",
		},
	}
	raw, err := json.Marshal(envelope)
	if err != nil {
		t.Fatalf("json.Marshal(contactRequestEnvelope): %v", err)
	}
	return raw
}

func TestHandleIncomingMessage_EmitsDirectTransportForNonCircuitStream(t *testing.T) {
	collector := &testEventCollector{}
	n := New(collector)
	n.peerId = "self-peer"

	stream := newStubTransportStream(
		t,
		[]byte(`{"id":"msg-direct","text":"hello"}`),
		generatePeerIDStr(t),
		"/ip4/192.168.1.55/tcp/4001",
	)

	n.handleIncomingMessage(stream)

	data := waitForCollectedEvent(t, collector, "message:received", time.Second)
	if got := data["transport"]; got != "direct" {
		t.Fatalf("expected direct transport, got %v", got)
	}
}

func TestHandleIncomingMessage_EmitsRelayTransportForCircuitStream(t *testing.T) {
	collector := &testEventCollector{}
	n := New(collector)
	n.peerId = "self-peer"
	remotePeerID := generatePeerIDStr(t)
	relayPeerID := generatePeerIDStr(t)

	stream := newStubTransportStream(
		t,
		[]byte(`{"id":"msg-relay","text":"hello"}`),
		remotePeerID,
		fmt.Sprintf(
			"/ip4/203.0.113.10/tcp/4001/p2p/%s/p2p-circuit/p2p/%s",
			relayPeerID,
			remotePeerID,
		),
	)

	n.handleIncomingMessage(stream)

	data := waitForCollectedEvent(t, collector, "message:received", time.Second)
	if got := data["transport"]; got != "relay" {
		t.Fatalf("expected relay transport, got %v", got)
	}
}

func TestHandleIncomingMessage_BindsAuthenticatedRemotePeerAndClassifiedTransport(t *testing.T) {
	tests := []struct {
		name          string
		circuit       bool
		wantTransport string
	}{
		{
			name:          "direct stream",
			wantTransport: "direct",
		},
		{
			name:          "relay stream",
			circuit:       true,
			wantTransport: "relay",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			collector := &testEventCollector{}
			n := New(collector)
			n.peerId = "authenticated-recipient"
			remotePeerID := generatePeerIDStr(t)
			remoteMultiaddr := "/ip4/192.168.1.55/tcp/4001"
			if tc.circuit {
				remoteMultiaddr = fmt.Sprintf(
					"/ip4/203.0.113.10/tcp/4001/p2p/%s/p2p-circuit/p2p/%s",
					generatePeerIDStr(t),
					remotePeerID,
				)
			}
			forgedEnvelope := []byte(
				`{"type":"introduction","from":"forged-peer","transport":"wifi","payload":{"senderPeerId":"forged-peer"}}`,
			)
			stream := newStubTransportStream(
				t,
				forgedEnvelope,
				remotePeerID,
				remoteMultiaddr,
			)

			n.handleIncomingMessage(stream)

			data := waitForCollectedEvent(
				t,
				collector,
				"message:received",
				time.Second,
			)
			if got := data["from"]; got != remotePeerID {
				t.Fatalf("event from = %v, want authenticated remote peer %q", got, remotePeerID)
			}
			if got := data["transport"]; got != tc.wantTransport {
				t.Fatalf("event transport = %v, want stream classification %q", got, tc.wantTransport)
			}
			if got := data["content"]; got != string(forgedEnvelope) {
				t.Fatalf("event content = %v, want original forged envelope diagnostics", got)
			}
			if got := data["to"]; got != "authenticated-recipient" {
				t.Fatalf("event to = %v, want receiver-owned peer id", got)
			}
		})
	}
}

func TestHandleIncomingMessage_DeferredDirectAck_WritesAckAfterConfirm(t *testing.T) {
	cb := &directConfirmCallback{confirmResults: []bool{true}}
	n := newDeferredAckTestNode(t, cb, 50*time.Millisecond)
	cb.node = n

	stream := newStubTransportStream(
		t,
		chatEnvelopeForTest(t, "msg-deferred-ack"),
		generatePeerIDStr(t),
		"/ip4/192.168.1.55/tcp/4001",
	)

	n.handleIncomingMessage(stream)

	if got := ackPayloadFromStream(t, stream); got != `{"ack":true}` {
		t.Fatalf("expected ack payload, got %q", got)
	}
	if stream.resetCount != 0 {
		t.Fatalf("expected no stream reset on confirmed ack, got %d", stream.resetCount)
	}
}

func TestHandleIncomingMessage_DeferredDirectAck_WritesBoundCallWakeReceipt(t *testing.T) {
	const receipt = "cwh-v1:epoch-3:generation-5:commit-9f8e7d"
	cb := &directConfirmCallback{
		confirmResults:  []bool{true},
		callWakeReceipt: receipt,
	}
	n := newDeferredAckTestNode(t, cb, 50*time.Millisecond)
	cb.node = n

	stream := newStubTransportStream(
		t,
		chatEnvelopeForTest(t, "msg-call-wake-receipt"),
		generatePeerIDStr(t),
		"/ip4/192.168.1.55/tcp/4001",
	)

	n.handleIncomingMessage(stream)

	got := ackPayloadFromStream(t, stream)
	if got != `{"ack":true,"callWakeReceipt":"cwh-v1:epoch-3:generation-5:commit-9f8e7d"}` {
		t.Fatalf("ACK did not preserve the exact call-wake receipt: %q", got)
	}
	if !isAffirmativeAckFrame([]byte(got)) {
		t.Fatal("receipt-bearing ACK must remain affirmative for new and legacy senders")
	}
}

func TestHandleIncomingMessage_DeferredDirectAck_OmitsInvalidCallWakeReceipt(t *testing.T) {
	tests := []struct {
		name    string
		receipt string
	}{
		{name: "control character", receipt: "commit\nforged"},
		{name: "oversized", receipt: strings.Repeat("a", directConfirmCallWakeReceiptMaxBytes+1)},
		{name: "invalid UTF-8", receipt: string([]byte{0xff})},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			cb := &directConfirmCallback{
				confirmResults:  []bool{true},
				callWakeReceipt: tc.receipt,
			}
			n := newDeferredAckTestNode(t, cb, 50*time.Millisecond)
			cb.node = n

			stream := newStubTransportStream(
				t,
				chatEnvelopeForTest(t, "msg-invalid-call-wake-receipt"),
				generatePeerIDStr(t),
				"/ip4/192.168.1.55/tcp/4001",
			)

			n.handleIncomingMessage(stream)

			if got := ackPayloadFromStream(t, stream); got != `{"ack":true}` {
				t.Fatalf("invalid receipt must preserve the generic ACK, got %q", got)
			}
		})
	}
}

func TestHandleIncomingMessage_DeferredDirectAck_FalseConfirmDoesNotAck(t *testing.T) {
	cb := &directConfirmCallback{
		confirmResults:  []bool{false},
		callWakeReceipt: "commit-must-not-be-written",
	}
	n := newDeferredAckTestNode(t, cb, 50*time.Millisecond)
	cb.node = n

	stream := newStubTransportStream(
		t,
		chatEnvelopeForTest(t, "msg-false-confirm"),
		generatePeerIDStr(t),
		"/ip4/192.168.1.55/tcp/4001",
	)

	n.handleIncomingMessage(stream)

	if stream.output.Len() != 0 {
		t.Fatalf("expected no ack bytes on false confirm, got %d", stream.output.Len())
	}
	if stream.resetCount == 0 {
		t.Fatal("expected stream reset when confirm resolves false")
	}
}

func TestHandleIncomingMessage_DeferredDirectAck_TimesOutWithoutConfirm(t *testing.T) {
	collector := &testEventCollector{}
	n := newDeferredAckTestNode(t, collector, 20*time.Millisecond)

	stream := newStubTransportStream(
		t,
		chatEnvelopeForTest(t, "msg-timeout"),
		generatePeerIDStr(t),
		"/ip4/192.168.1.55/tcp/4001",
	)

	n.handleIncomingMessage(stream)

	if stream.output.Len() != 0 {
		t.Fatalf("expected no ack bytes after timeout, got %d", stream.output.Len())
	}
	if stream.resetCount == 0 {
		t.Fatal("expected stream reset when deferred direct ack times out")
	}
}

// newClassifierStubStream builds a stub stream whose Conn() rides the given
// remote multiaddr. NOTE: stubStreamConn.Stat() returns an empty
// network.ConnStats, so conn.Stat().Limited is ALWAYS false for this stub.
// These tests therefore exercise classifyStreamTransport's MULTIADDR mapping
// ONLY; they are NOT proof of a real relay->direct upgrade. The Limited==true
// half (a genuinely relay-routed connection) is covered by I1-NC using a real
// NW002 circuit conn (see holepunch_negative_control_test.go).
func newClassifierStubStream(t *testing.T, remoteMultiaddr string) *stubTransportStream {
	t.Helper()
	return newStubTransportStream(
		t,
		[]byte(`{"id":"classify","text":"x"}`),
		generatePeerIDStr(t),
		remoteMultiaddr,
	)
}

// U2: the classifier maps a /p2p-circuit remote multiaddr to "relay" and a
// plain /ip4 remote multiaddr to "direct".
func TestClassifyStreamTransport_CircuitToNonCircuitFlipsRelayToDirect(t *testing.T) {
	remotePeerID := generatePeerIDStr(t)
	relayPeerID := generatePeerIDStr(t)

	circuit := newClassifierStubStream(
		t,
		fmt.Sprintf(
			"/ip4/203.0.113.10/tcp/4001/p2p/%s/p2p-circuit/p2p/%s",
			relayPeerID,
			remotePeerID,
		),
	)
	if got := classifyStreamTransport(circuit); got != "relay" {
		t.Fatalf("circuit stream classifyStreamTransport = %q, want relay", got)
	}
	// Stub Stat() is empty => Limited is always false here; this is label
	// mapping only, not upgrade proof.
	if circuit.Conn().Stat().Limited {
		t.Fatal("stub conn unexpectedly reported Limited=true; stub Stat() should be empty")
	}

	direct := newClassifierStubStream(t, "/ip4/192.168.1.55/tcp/4001")
	if got := classifyStreamTransport(direct); got != "direct" {
		t.Fatalf("non-circuit stream classifyStreamTransport = %q, want direct", got)
	}
}

// U2-mixed: mixed-conn race guard. WithAllowLimitedConn means a stream can ride
// either a circuit conn or a direct conn even when both exist to the same peer.
// classifyStreamTransport must classify purely from the STREAM'S OWN conn
// multiaddr — so a stream whose conn is non-circuit is "direct" regardless of a
// separately-existing circuit conn. Guards the real mislabel/double-count false
// positive. Stub-level; pairs with I1-NC for the Limited==true real-conn half.
func TestClassifyStreamTransport_MixedConns_UsesStreamOwnConn(t *testing.T) {
	remotePeerID := generatePeerIDStr(t)
	relayPeerID := generatePeerIDStr(t)

	// A circuit conn to the same peer also exists "conceptually" — represented
	// here as an independent stream we do NOT pass to the classifier. The
	// classifier only ever sees the stream handed to it.
	circuitSibling := newClassifierStubStream(
		t,
		fmt.Sprintf(
			"/ip4/203.0.113.10/tcp/4001/p2p/%s/p2p-circuit/p2p/%s",
			relayPeerID,
			remotePeerID,
		),
	)
	if got := classifyStreamTransport(circuitSibling); got != "relay" {
		t.Fatalf("sanity: circuit sibling should classify relay, got %q", got)
	}

	// The stream under test rides a NON-circuit conn to the SAME remote peer.
	directStream := newStubTransportStream(
		t,
		[]byte(`{"id":"mixed","text":"x"}`),
		remotePeerID,
		"/ip4/192.168.1.55/tcp/4001",
	)
	// Force the same remote peer ID onto the direct stream's conn so the only
	// distinguishing factor is the conn's own multiaddr, not the peer.
	if sc, ok := directStream.conn.(*stubStreamConn); ok {
		decoded, err := peer.Decode(remotePeerID)
		if err != nil {
			t.Fatalf("decode remote peer: %v", err)
		}
		sc.remotePeer = decoded
	}

	if got := classifyStreamTransport(directStream); got != "direct" {
		t.Fatalf("mixed-conn: stream over non-circuit conn = %q, want direct (must use stream's own conn, not the circuit sibling)", got)
	}
}

// TestHandleIncomingMessage_DirectAckContract_AttachesConfirmNonce pins the
// Go->Dart wire contract that doc 118's live-direct notification path depends on
// (plan 120 phase G5). Go attaches the "confirmNonce" string key to the
// "message:received" event for an incoming direct chat_message when
// EnableDeferredDirectAck is true (the default). Dart's ChatMessage.fromJson
// reads that exact key (lib/features/p2p/domain/models/chat_message.dart) to
// drive the deferred-ack->notify path. This guard fails if Go renames/drops the
// key, changes the type=="chat_message" gate, or flips the default-true flag.
// The shared wire key is "confirmNonce" and the event is "message:received".
func TestHandleIncomingMessage_DirectAckContract_AttachesConfirmNonce(t *testing.T) {
	// Default-flag guard: a flip of the default to false silently bypasses the
	// whole deferred-ack contract on real devices (feature_flags.go).
	if !DefaultFeatureFlags().EnableDeferredDirectAck {
		t.Fatal("DefaultFeatureFlags().EnableDeferredDirectAck must default to true; flipping it bypasses the confirmNonce contract Dart relies on")
	}

	// Positive case: deferred ack enabled (default) => message:received carries
	// a non-empty "confirmNonce" string. Use a plain collector (no confirm) and
	// a short timeout; we assert on the event emitted BEFORE the confirm wait.
	collector := &testEventCollector{}
	n := newDeferredAckTestNode(t, collector, 50*time.Millisecond)

	stream := newStubTransportStream(
		t,
		chatEnvelopeForTest(t, "msg-contract"),
		generatePeerIDStr(t),
		"/ip4/192.168.1.55/tcp/4001",
	)

	n.handleIncomingMessage(stream)

	data := waitForCollectedEvent(t, collector, "message:received", time.Second)
	raw, present := data["confirmNonce"]
	if !present {
		t.Fatalf("expected message:received to carry exactly the \"confirmNonce\" key (the Go->Dart wire contract); event data: %v", data)
	}
	nonce, ok := raw.(string)
	if !ok {
		t.Fatalf("expected confirmNonce to be a string, got %T", raw)
	}
	if nonce == "" {
		// Intentionally NOT asserting the UUID value — only non-emptiness — so
		// the guard stays deterministic / non-flaky.
		t.Fatal("expected confirmNonce to be a non-empty string")
	}

	// Negative control: with EnableDeferredDirectAck=false the same
	// chat_message emits message:received with NO confirmNonce key. This pins
	// the gate (the flag), not merely the presence of the key.
	negCollector := &testEventCollector{}
	negNode := newDeferredAckTestNode(t, negCollector, 50*time.Millisecond)
	flags := DefaultFeatureFlags()
	flags.EnableDeferredDirectAck = false
	negNode.featureFlags = &flags

	negStream := newStubTransportStream(
		t,
		chatEnvelopeForTest(t, "msg-contract-disabled"),
		generatePeerIDStr(t),
		"/ip4/192.168.1.55/tcp/4001",
	)

	negNode.handleIncomingMessage(negStream)

	negData := waitForCollectedEvent(t, negCollector, "message:received", time.Second)
	if _, exists := negData["confirmNonce"]; exists {
		t.Fatalf("expected NO confirmNonce key when EnableDeferredDirectAck=false, but it was present: %v", negData["confirmNonce"])
	}
}

// F7: the stage-before-ack machinery must also defer the wire ack for
// message_reaction / message_deletion, not only chat_message — otherwise Go
// ACKs (and the relay deletes) the reaction/deletion before Dart durably
// commits it, losing it on a kill in that window. There is NO existing test
// asserting shouldDeferDirectAck==true for these types (the negative control
// above only pins the FLAG for chat_message).
func TestShouldDeferDirectAck_ReactionAndDeletion(t *testing.T) {
	cb := &testEventCollector{}
	n := newDeferredAckTestNode(t, cb, 50*time.Millisecond)

	envelopeOfType := func(typ string) []byte {
		raw, err := json.Marshal(map[string]interface{}{"type": typ, "version": "1"})
		if err != nil {
			t.Fatalf("json.Marshal(%s): %v", typ, err)
		}
		return raw
	}

	cases := []struct {
		typ  string
		want bool
	}{
		{"chat_message", true},     // control: already deferred
		{"message_reaction", true}, // F7: must now defer
		{"message_deletion", true}, // F7: must now defer
		{"introduction", false},    // legitimately fire-and-forget
		{"contact_request", true},  // 171 TC-01: now deferred (cold-receiver durability)
	}
	for _, tc := range cases {
		got := n.shouldDeferDirectAck(envelopeOfType(tc.typ))
		if got != tc.want {
			t.Errorf("shouldDeferDirectAck(type=%q) = %v, want %v", tc.typ, got, tc.want)
		}
	}
}

// TestHandleIncomingMessage_ContactRequest_AttachesConfirmNonce (171 TC-02)
// pins that a direct contact_request rides the SAME deferred-ack wire contract
// as chat_message: with EnableDeferredDirectAck=true (default), Go attaches a
// non-empty "confirmNonce" to the "message:received" event and does NOT write
// {"ack":true} until Dart resolves the confirm. On HEAD this fails because
// shouldDeferDirectAck excludes contact_request -> immediate ack, no nonce.
func TestHandleIncomingMessage_ContactRequest_AttachesConfirmNonce(t *testing.T) {
	if !DefaultFeatureFlags().EnableDeferredDirectAck {
		t.Fatal("EnableDeferredDirectAck must default to true for the contact_request deferred-ack contract")
	}

	// (a) deferred path: plain collector (no confirm) + short timeout. The
	// message:received event must carry a non-empty confirmNonce, and because
	// no confirm is resolved the ack must NOT be written (deferred until commit).
	collector := &testEventCollector{}
	n := newDeferredAckTestNode(t, collector, 50*time.Millisecond)

	stream := newStubTransportStream(
		t,
		contactRequestEnvelopeForTest(t, "cr-nonce"),
		generatePeerIDStr(t),
		"/ip4/192.168.1.55/tcp/4001",
	)

	n.handleIncomingMessage(stream)

	data := waitForCollectedEvent(t, collector, "message:received", time.Second)
	raw, present := data["confirmNonce"]
	if !present {
		t.Fatalf("expected contact_request message:received to carry a confirmNonce (deferred-ack contract); event data: %v", data)
	}
	nonce, ok := raw.(string)
	if !ok || nonce == "" {
		t.Fatalf("expected confirmNonce to be a non-empty string, got %T %v", raw, raw)
	}
	if stream.output.Len() != 0 {
		t.Fatalf("expected NO ack bytes before confirm for a deferred contact_request, got %d", stream.output.Len())
	}

	// (b) confirmed path: a real confirm releases the ack frame.
	cb := &directConfirmCallback{confirmResults: []bool{true}}
	n2 := newDeferredAckTestNode(t, cb, 50*time.Millisecond)
	cb.node = n2

	stream2 := newStubTransportStream(
		t,
		contactRequestEnvelopeForTest(t, "cr-confirm"),
		generatePeerIDStr(t),
		"/ip4/192.168.1.55/tcp/4001",
	)

	n2.handleIncomingMessage(stream2)

	if got := ackPayloadFromStream(t, stream2); got != `{"ack":true}` {
		t.Fatalf("expected ack payload after confirm, got %q", got)
	}
	if stream2.resetCount != 0 {
		t.Fatalf("expected no stream reset on confirmed contact_request ack, got %d", stream2.resetCount)
	}
}

func TestHandleIncomingMessage_DeferredDirectAck_IgnoresDuplicateConfirm(t *testing.T) {
	cb := &directConfirmCallback{confirmResults: []bool{true, false}}
	n := newDeferredAckTestNode(t, cb, 50*time.Millisecond)
	cb.node = n

	stream := newStubTransportStream(
		t,
		chatEnvelopeForTest(t, "msg-duplicate-confirm"),
		generatePeerIDStr(t),
		"/ip4/192.168.1.55/tcp/4001",
	)

	n.handleIncomingMessage(stream)

	if got := ackPayloadFromStream(t, stream); got != `{"ack":true}` {
		t.Fatalf("expected ack payload after first confirm, got %q", got)
	}
	n.pendingConfirmsMu.Lock()
	pending := len(n.pendingDirectConfirms)
	n.pendingConfirmsMu.Unlock()
	if pending != 0 {
		t.Fatalf("expected pending direct confirms to be cleaned up, got %d", pending)
	}
}
