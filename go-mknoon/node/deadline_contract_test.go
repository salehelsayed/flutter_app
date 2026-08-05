package node

import (
	"bytes"
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/core/protocol"
)

const r3ChatEnvelope = `{"type":"chat_message","payload":{"id":"r3-deadline"}}`

type r3ScriptedStream struct {
	input              *bytes.Reader
	output             bytes.Buffer
	events             []string
	deadlines          []time.Time
	deadlineErrors     []error
	writeErr           error
	readErr            error
	closeWriteErr      error
	closeErr           error
	writeCalls         int
	closeCount         int
	closeWriteCount    int
	resetCount         int
	onFrameWriteFinish func()
}

func newR3ScriptedStream(t *testing.T, reply string) *r3ScriptedStream {
	t.Helper()
	framedReply := new(bytes.Buffer)
	if err := writeFrame(framedReply, []byte(reply)); err != nil {
		t.Fatalf("frame scripted reply: %v", err)
	}
	return &r3ScriptedStream{input: bytes.NewReader(framedReply.Bytes())}
}

func (s *r3ScriptedStream) Read(p []byte) (int, error) {
	s.events = append(s.events, "read")
	if s.readErr != nil {
		return 0, s.readErr
	}
	return s.input.Read(p)
}

func (s *r3ScriptedStream) Write(p []byte) (int, error) {
	s.events = append(s.events, "write")
	s.writeCalls++
	if s.writeErr != nil {
		return 0, s.writeErr
	}
	n, err := s.output.Write(p)
	if err == nil && s.writeCalls == 2 && s.onFrameWriteFinish != nil {
		s.onFrameWriteFinish()
	}
	return n, err
}

func (s *r3ScriptedStream) Close() error {
	s.events = append(s.events, "close")
	s.closeCount++
	return s.closeErr
}

func (s *r3ScriptedStream) CloseRead() error { return nil }

func (s *r3ScriptedStream) CloseWrite() error {
	s.events = append(s.events, "closeWrite")
	s.closeWriteCount++
	return s.closeWriteErr
}

func (s *r3ScriptedStream) Reset() error {
	s.events = append(s.events, "reset")
	s.resetCount++
	return nil
}

func (s *r3ScriptedStream) SetDeadline(deadline time.Time) error {
	s.events = append(s.events, "deadline")
	index := len(s.deadlines)
	s.deadlines = append(s.deadlines, deadline)
	if index < len(s.deadlineErrors) {
		return s.deadlineErrors[index]
	}
	return nil
}

func (s *r3ScriptedStream) SetReadDeadline(time.Time) error  { return nil }
func (s *r3ScriptedStream) SetWriteDeadline(time.Time) error { return nil }
func (s *r3ScriptedStream) ID() string                       { return "r3-scripted-stream" }
func (s *r3ScriptedStream) Protocol() protocol.ID            { return ChatProtocol }
func (s *r3ScriptedStream) SetProtocol(protocol.ID) error    { return nil }
func (s *r3ScriptedStream) Stat() network.Stats              { return network.Stats{} }
func (s *r3ScriptedStream) Conn() network.Conn               { return nil }
func (s *r3ScriptedStream) Scope() network.StreamScope       { return nil }

func startR3DeadlineNode(t *testing.T) (*Node, peer.ID) {
	t.Helper()
	n := NewNode()
	n.hermeticLocalNetworkForTests = true
	if _, err := n.Start(NodeConfig{
		PrivateKeyHex:  generateTestKey(t),
		RelayAddresses: []string{},
		AutoRegister:   false,
	}); err != nil {
		t.Fatalf("Start: %v", err)
	}
	t.Cleanup(func() { n.Stop() })
	return n, newR3PeerID(t)
}

func newR3PeerID(t *testing.T) peer.ID {
	t.Helper()
	privateKey, _, err := crypto.GenerateEd25519Key(rand.Reader)
	if err != nil {
		t.Fatalf("GenerateEd25519Key: %v", err)
	}
	pid, err := peer.IDFromPrivateKey(privateKey)
	if err != nil {
		t.Fatalf("IDFromPrivateKey: %v", err)
	}
	return pid
}

func r3RelayAddress(pid peer.ID, port int) string {
	return fmt.Sprintf("/ip4/127.0.0.1/tcp/%d/p2p/%s", port, pid)
}

func firstR3Event(events []string, want string) int {
	for index, event := range events {
		if event == want {
			return index
		}
	}
	return -1
}

func secondR3Event(events []string, want string) int {
	found := false
	for index, event := range events {
		if event != want {
			continue
		}
		if found {
			return index
		}
		found = true
	}
	return -1
}

func TestR3Deadline_CommitReserveExceedsReceiverAndIsTypeScoped(t *testing.T) {
	if CommittedAckReserve != 3*time.Second {
		t.Fatalf("CommittedAckReserve = %v, want exactly 3s", CommittedAckReserve)
	}
	if DirectConfirmTimeout >= CommittedAckReserve {
		t.Fatalf("DirectConfirmTimeout = %v, must be below reserve %v", DirectConfirmTimeout, CommittedAckReserve)
	}

	tests := []struct {
		name     string
		typeName string
		want     bool
	}{
		{name: "chat", typeName: "chat_message", want: true},
		{name: "reaction", typeName: "message_reaction", want: true},
		{name: "deletion", typeName: "message_deletion", want: true},
		{name: "contact request", typeName: "contact_request", want: true},
		{name: "introduction", typeName: "introduction", want: false},
		{name: "delivery receipt", typeName: "delivery_receipt", want: false},
		{name: "control", typeName: "profile_update", want: false},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			message := []byte(fmt.Sprintf(`{"type":%q}`, tc.typeName))
			if got := requiresCommittedAckReserve(message); got != tc.want {
				t.Fatalf("requiresCommittedAckReserve(%q) = %v, want %v", tc.typeName, got, tc.want)
			}
		})
	}
	if requiresCommittedAckReserve([]byte(`{"type":`)) {
		t.Fatal("malformed envelopes must retain the immediate/default command deadline")
	}
}

func TestR3Deadline_PrewriteAdmissionIsTypeScoped(t *testing.T) {
	start := time.Unix(1_800_000_000, 0)
	tests := []struct {
		name            string
		message         string
		timeout         time.Duration
		wantAdmitted    bool
		wantPrewriteFor time.Duration
		wantReserved    bool
	}{
		{name: "chat exactly reserve", message: r3ChatEnvelope, timeout: 3000 * time.Millisecond},
		{name: "chat one millisecond above reserve", message: r3ChatEnvelope, timeout: 3001 * time.Millisecond, wantAdmitted: true, wantPrewriteFor: time.Millisecond, wantReserved: true},
		{name: "two second introduction", message: `{"type":"introduction"}`, timeout: 2 * time.Second, wantAdmitted: true, wantPrewriteFor: 2 * time.Second},
		{name: "default contact request", message: `{"type":"contact_request"}`, timeout: SendTimeout, wantAdmitted: true, wantPrewriteFor: SendTimeout - CommittedAckReserve, wantReserved: true},
		{name: "default reaction", message: `{"type":"message_reaction"}`, timeout: SendTimeout, wantAdmitted: true, wantPrewriteFor: SendTimeout - CommittedAckReserve, wantReserved: true},
		{name: "immediate receipt", message: `{"type":"delivery_receipt"}`, timeout: 2 * time.Second, wantAdmitted: true, wantPrewriteFor: 2 * time.Second},
		{name: "opaque control", message: `not-json`, timeout: 2 * time.Second, wantAdmitted: true, wantPrewriteFor: 2 * time.Second},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			deadlines, admitted := deadlinesForMessage(start, tc.timeout, []byte(tc.message))
			if admitted != tc.wantAdmitted {
				t.Fatalf("admitted = %v, want %v", admitted, tc.wantAdmitted)
			}
			if !admitted {
				return
			}
			if got := deadlines.prewrite.Sub(start); got != tc.wantPrewriteFor {
				t.Fatalf("pre-write allowance = %v, want %v", got, tc.wantPrewriteFor)
			}
			if deadlines.command.Sub(start) != tc.timeout {
				t.Fatalf("command allowance = %v, want %v", deadlines.command.Sub(start), tc.timeout)
			}
			if deadlines.reserved != tc.wantReserved {
				t.Fatalf("reserved = %v, want %v", deadlines.reserved, tc.wantReserved)
			}
		})
	}

	t.Run("expiry during open resets without writing", func(t *testing.T) {
		n, target := startR3DeadlineNode(t)
		stream := newR3ScriptedStream(t, `{"ack":true}`)
		n.openChatStreamHook = func(ctx context.Context, _ host.Host, _ peer.ID) (network.Stream, error) {
			<-ctx.Done()
			return stream, nil
		}

		_, err := n.SendMessageWithTransport(
			target.String(),
			r3ChatEnvelope,
			int((CommittedAckReserve+10*time.Millisecond)/time.Millisecond),
		)
		if err == nil {
			t.Fatal("expected expiry after open to fail before the write")
		}
		if stream.output.Len() != 0 || stream.writeCalls != 0 {
			t.Fatalf("expired-open stream wrote %d bytes in %d calls", stream.output.Len(), stream.writeCalls)
		}
		if stream.resetCount != 1 {
			t.Fatalf("reset count = %d, want 1", stream.resetCount)
		}
	})
}

func TestR3Deadline_MessageRecoveryReusesPrewriteDeadline(t *testing.T) {
	n, target := startR3DeadlineNode(t)
	stream := newR3ScriptedStream(t, `{"ack":true}`)
	var observedDeadlines []time.Time
	var allowLimited []bool
	openCalls := 0
	n.openChatStreamHook = func(ctx context.Context, _ host.Host, _ peer.ID) (network.Stream, error) {
		openCalls++
		deadline, ok := ctx.Deadline()
		if !ok {
			t.Fatal("chat open context has no deadline")
		}
		observedDeadlines = append(observedDeadlines, deadline)
		allowed, _ := network.GetAllowLimitedConn(ctx)
		allowLimited = append(allowLimited, allowed)
		if openCalls == 1 {
			return nil, fmt.Errorf("failed to open stream: %w", context.DeadlineExceeded)
		}
		return stream, nil
	}
	recoverCalls := 0
	n.recoverPeerForSendHook = func(ctx context.Context, _ host.Host, _ peer.ID, _ string) error {
		recoverCalls++
		deadline, ok := ctx.Deadline()
		if !ok {
			t.Fatal("recovery context has no deadline")
		}
		observedDeadlines = append(observedDeadlines, deadline)
		return nil
	}

	result, err := n.SendMessageWithTransport(target.String(), r3ChatEnvelope, 5000)
	if err != nil {
		t.Fatalf("SendMessageWithTransport: %v", err)
	}
	if !result.Acked {
		t.Fatal("recovered send was not acknowledged")
	}
	if openCalls != 2 || recoverCalls != 1 {
		t.Fatalf("open/recovery calls = %d/%d, want 2/1", openCalls, recoverCalls)
	}
	if len(observedDeadlines) != 3 {
		t.Fatalf("observed %d deadlines, want 3", len(observedDeadlines))
	}
	for index, deadline := range observedDeadlines[1:] {
		if !deadline.Equal(observedDeadlines[0]) {
			t.Fatalf("deadline %d = %v, want exact %v", index+1, deadline, observedDeadlines[0])
		}
	}
	for index, allowed := range allowLimited {
		if !allowed {
			t.Fatalf("open attempt %d did not allow limited connections", index+1)
		}
	}
}

func TestR3Deadline_RelayRecoveryCandidatesShareDeadline(t *testing.T) {
	relayOne := newR3PeerID(t)
	relayTwo := newR3PeerID(t)
	topologies := []struct {
		name      string
		addresses []string
	}{
		{
			name: "one relay two addresses",
			addresses: []string{
				r3RelayAddress(relayOne, 19101),
				r3RelayAddress(relayOne, 19102),
			},
		},
		{
			name: "two relays one address",
			addresses: []string{
				r3RelayAddress(relayOne, 19103),
				r3RelayAddress(relayTwo, 19104),
			},
		},
	}
	for _, tc := range topologies {
		t.Run(tc.name, func(t *testing.T) {
			n, target := startR3DeadlineNode(t)
			n.mu.Lock()
			n.relayAddresses = append([]string(nil), tc.addresses...)
			n.mu.Unlock()

			commandDeadline := time.Now().Add(time.Second)
			ctx, cancel := context.WithDeadline(n.ctx, commandDeadline)
			defer cancel()
			var observed []time.Time
			n.connectPeerForSendHook = func(ctx context.Context, _ host.Host, ai peer.AddrInfo) error {
				deadline, ok := ctx.Deadline()
				if !ok {
					t.Fatal("relay candidate context has no deadline")
				}
				observed = append(observed, deadline)
				if len(ai.Addrs) != 1 {
					t.Fatalf("candidate has %d circuit addresses, want 1", len(ai.Addrs))
				}
				allowed, _ := network.GetAllowLimitedConn(ctx)
				if !allowed {
					t.Fatal("relay recovery candidate did not allow limited connections")
				}
				return errors.New("scripted relay connect failure")
			}

			if err := n.recoverPeerForSendWithContext(ctx, n.Host(), target, target.String()); err == nil {
				t.Fatal("expected all scripted relay candidates to fail")
			}
			if len(observed) != 2 {
				t.Fatalf("candidate attempts = %d, want 2", len(observed))
			}
			for index, got := range observed {
				if !got.Equal(commandDeadline) {
					t.Fatalf("candidate deadline %d = %v, want exact %v", index+1, got, commandDeadline)
				}
			}
		})
	}

	t.Run("expired context stops before another useful candidate", func(t *testing.T) {
		n, target := startR3DeadlineNode(t)
		n.mu.Lock()
		n.relayAddresses = []string{
			r3RelayAddress(relayOne, 19105),
			r3RelayAddress(relayTwo, 19106),
		}
		n.mu.Unlock()
		ctx, cancel := context.WithTimeout(n.ctx, 10*time.Millisecond)
		defer cancel()
		attempts := 0
		n.connectPeerForSendHook = func(ctx context.Context, _ host.Host, _ peer.AddrInfo) error {
			attempts++
			<-ctx.Done()
			return ctx.Err()
		}
		if err := n.recoverPeerForSendWithContext(ctx, n.Host(), target, target.String()); err == nil {
			t.Fatal("expected expired recovery to fail")
		}
		if attempts != 1 {
			t.Fatalf("useful candidate attempts = %d, want 1", attempts)
		}
	})
}

func TestR3Deadline_RendezvousCandidatesShareCommandDeadline(t *testing.T) {
	relayOne := newR3PeerID(t)
	relayTwo := newR3PeerID(t)
	topologies := []struct {
		name      string
		addresses []string
	}{
		{
			name: "one relay two addresses",
			addresses: []string{
				r3RelayAddress(relayOne, 19201),
				r3RelayAddress(relayOne, 19202),
			},
		},
		{
			name: "two relays one address",
			addresses: []string{
				r3RelayAddress(relayOne, 19203),
				r3RelayAddress(relayTwo, 19204),
			},
		},
	}
	for _, tc := range topologies {
		t.Run(tc.name, func(t *testing.T) {
			n, _ := startR3DeadlineNode(t)
			var openDeadlines []time.Time
			var streams []*r3ScriptedStream
			n.rendezvousStreamOpenHook = func(ctx context.Context, _ host.Host, _ peer.ID) (network.Stream, error) {
				deadline, ok := ctx.Deadline()
				if !ok {
					t.Fatal("rendezvous open context has no deadline")
				}
				openDeadlines = append(openDeadlines, deadline)
				stream := newR3ScriptedStream(t, "")
				stream.deadlineErrors = []error{errors.New("scripted deadline install failure")}
				streams = append(streams, stream)
				return stream, nil
			}

			if _, err := n.RendezvousDiscoverWithTimeout("r3-deadline", tc.addresses, 1000); err == nil {
				t.Fatal("expected deadline-install failures across all candidates")
			}
			if len(openDeadlines) != 2 || len(streams) != 2 {
				t.Fatalf("open attempts/streams = %d/%d, want 2/2", len(openDeadlines), len(streams))
			}
			for index, stream := range streams {
				if !openDeadlines[index].Equal(openDeadlines[0]) {
					t.Fatalf("open deadline %d = %v, want exact %v", index+1, openDeadlines[index], openDeadlines[0])
				}
				if len(stream.deadlines) != 1 || !stream.deadlines[0].Equal(openDeadlines[0]) {
					t.Fatalf("stream deadline %d = %v, want exact %v", index+1, stream.deadlines, openDeadlines[0])
				}
				if stream.resetCount != 1 || stream.closeCount != 0 {
					t.Fatalf("stream %d cleanup reset/close = %d/%d, want 1/0", index+1, stream.resetCount, stream.closeCount)
				}
			}
		})
	}
}

func TestR3Deadline_PostWriteAckDeadlineAndOrder(t *testing.T) {
	n, target := startR3DeadlineNode(t)
	tests := []struct {
		name          string
		timeout       time.Duration
		writeComplete time.Duration
		wantAckAt     time.Duration
	}{
		{name: "reserve caps early write", timeout: 10 * time.Second, writeComplete: time.Second, wantAckAt: 4 * time.Second},
		{name: "command caps defensive late completion", timeout: 4 * time.Second, writeComplete: 2 * time.Second, wantAckAt: 4 * time.Second},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			start := time.Now().Add(100 * time.Millisecond)
			calls := 0
			n.sendNowHook = func() time.Time {
				calls++
				if calls <= 2 {
					return start
				}
				return start.Add(tc.writeComplete)
			}
			stream := newR3ScriptedStream(t, `{"ack":true}`)
			n.openChatStreamHook = func(context.Context, host.Host, peer.ID) (network.Stream, error) {
				return stream, nil
			}

			result, err := n.SendMessageWithTransport(
				target.String(),
				r3ChatEnvelope,
				int(tc.timeout/time.Millisecond),
			)
			if err != nil {
				t.Fatalf("SendMessageWithTransport: %v", err)
			}
			if !result.Acked {
				t.Fatal("scripted affirmative ACK was not preserved")
			}
			if len(stream.deadlines) != 2 {
				t.Fatalf("installed deadlines = %d, want 2", len(stream.deadlines))
			}
			wantPrewrite := start.Add(tc.timeout - CommittedAckReserve)
			if !stream.deadlines[0].Equal(wantPrewrite) {
				t.Fatalf("pre-write deadline = %v, want %v", stream.deadlines[0], wantPrewrite)
			}
			wantAck := start.Add(tc.wantAckAt)
			if !stream.deadlines[1].Equal(wantAck) {
				t.Fatalf("ACK deadline = %v, want %v", stream.deadlines[1], wantAck)
			}

			secondDeadline := secondR3Event(stream.events, "deadline")
			completeWrite := secondR3Event(stream.events, "write")
			closeWrite := firstR3Event(stream.events, "closeWrite")
			read := firstR3Event(stream.events, "read")
			close := firstR3Event(stream.events, "close")
			if completeWrite < 0 || secondDeadline <= completeWrite || closeWrite <= secondDeadline || read <= closeWrite || close <= read {
				t.Fatalf("lifecycle order = %v, want write -> deadline -> CloseWrite -> read -> Close", stream.events)
			}
			if stream.writeCalls != 2 {
				t.Fatalf("post-write deadline was not installed after the complete frame write: %v", stream.events)
			}
		})
	}
}

func TestR3Deadline_StreamCleanupMatchesOutcome(t *testing.T) {
	n, target := startR3DeadlineNode(t)
	tests := []struct {
		name               string
		reply              string
		deadlineErrors     []error
		writeErr           error
		closeWriteErr      error
		readErr            error
		closeErr           error
		wantGoError        bool
		wantAcked          bool
		wantReadableResult bool
		wantClose          int
		wantReset          int
	}{
		{name: "pre-write deadline failure", deadlineErrors: []error{errors.New("pre-write deadline")}, wantGoError: true, wantReset: 1},
		{name: "write failure", writeErr: errors.New("write"), wantGoError: true, wantReset: 1},
		{name: "post-write deadline failure", deadlineErrors: []error{nil, errors.New("ACK deadline")}, wantReset: 1},
		{name: "half-close failure", closeWriteErr: errors.New("close write"), wantReset: 1},
		{name: "ACK read failure", readErr: errors.New("read ACK"), wantReset: 1},
		{name: "readable negative ACK", reply: `{"ack":false}`, wantReadableResult: true, wantClose: 1},
		{name: "readable affirmative ACK", reply: `{"ack":true}`, wantReadableResult: true, wantAcked: true, wantClose: 1},
		{name: "negative ACK close failure", reply: `{"ack":false}`, closeErr: errors.New("close"), wantReadableResult: true, wantClose: 1, wantReset: 1},
		{name: "affirmative ACK close failure", reply: `{"ack":true}`, closeErr: errors.New("close"), wantReadableResult: true, wantAcked: true, wantClose: 1, wantReset: 1},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			n.sendNowHook = nil
			stream := newR3ScriptedStream(t, tc.reply)
			stream.deadlineErrors = tc.deadlineErrors
			stream.writeErr = tc.writeErr
			stream.closeWriteErr = tc.closeWriteErr
			stream.readErr = tc.readErr
			stream.closeErr = tc.closeErr
			n.openChatStreamHook = func(context.Context, host.Host, peer.ID) (network.Stream, error) {
				return stream, nil
			}

			result, err := n.SendMessageWithTransport(target.String(), r3ChatEnvelope, 5000)
			if (err != nil) != tc.wantGoError {
				t.Fatalf("error = %v, wantGoError=%v", err, tc.wantGoError)
			}
			if result.Acked != tc.wantAcked {
				t.Fatalf("Acked = %v, want %v", result.Acked, tc.wantAcked)
			}
			if tc.wantReadableResult && result.Reply != tc.reply {
				t.Fatalf("Reply = %q, want readable frame %q", result.Reply, tc.reply)
			}
			if stream.closeCount != tc.wantClose || stream.resetCount != tc.wantReset {
				t.Fatalf("close/reset = %d/%d, want %d/%d; events=%v", stream.closeCount, stream.resetCount, tc.wantClose, tc.wantReset, stream.events)
			}
			if !tc.wantGoError && !tc.wantReadableResult && result.Transport != "direct" {
				t.Fatalf("post-write failure lost written transport evidence: %+v", result)
			}
			if tc.wantGoError && stream.closeCount != 0 {
				t.Fatalf("transport failure closed normally: events=%v", stream.events)
			}
		})
	}
}
