package node

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
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
	node           *Node
	confirmResults []bool
	delay          time.Duration
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
		c.node.ResolveDirectConfirm(nonce, ok)
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

func TestHandleIncomingMessage_DeferredDirectAck_FalseConfirmDoesNotAck(t *testing.T) {
	cb := &directConfirmCallback{confirmResults: []bool{false}}
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
