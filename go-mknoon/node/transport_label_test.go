package node

import (
	"bytes"
	"context"
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
	input  *bytes.Reader
	output bytes.Buffer
	conn   network.Conn
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
func (s *stubTransportStream) Close() error                { return nil }
func (s *stubTransportStream) CloseRead() error            { return nil }
func (s *stubTransportStream) CloseWrite() error           { return nil }
func (s *stubTransportStream) Reset() error                { return nil }
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
