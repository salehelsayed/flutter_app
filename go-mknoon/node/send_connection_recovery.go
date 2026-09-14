package node

import (
	"context"
	"errors"
	"time"

	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/p2p/protocol/ping"
	multistream "github.com/multiformats/go-multistream"
)

type sendConnectionCheck struct {
	done chan struct{} // non-nil only while an existing send owns the check
}

func isSendTimeout(err error) bool {
	var timeout interface{ Timeout() bool }
	return errors.Is(err, context.DeadlineExceeded) || (errors.As(err, &timeout) && timeout.Timeout())
}

// A deadline is evidence about an operation, not the shared connection. Leave
// the expired operation's budget alone and let the next existing retry check
// this exact connection before reusing it. No retry or background work starts
// here. Object identity (not peer ID or a restart-reusable Conn.ID) fences owners.
func (n *Node) noteSendTimeout(ctx context.Context, h host.Host, conn network.Conn, err error) {
	if conn == nil || !isSendTimeout(err) || errors.Is(ctx.Err(), context.Canceled) || conn.IsClosed() {
		return
	}
	n.mu.RLock()
	defer n.mu.RUnlock()
	if n.host != h || n.ctx == nil || n.ctx.Err() != nil {
		return
	}
	n.sendConnectionsMu.Lock()
	defer n.sendConnectionsMu.Unlock()
	n.pruneSendConnectionsLocked()
	if n.sendConnections == nil {
		n.sendConnections = make(map[network.Conn]*sendConnectionCheck)
	}
	if n.sendConnections[conn] == nil {
		n.sendConnections[conn] = &sendConnectionCheck{}
	}
}

// BasicHost.NewStream hides its connection on identify/negotiation errors.
// An unchanged sole candidate is only a suspect, never grounds for closure.
// A changed/ambiguous snapshot retains the ordinary conservative retry path.
func (n *Node) noteSendOpenTimeout(ctx context.Context, h host.Host, pid peer.ID, before []network.Conn, s network.Stream, err error) {
	if err == nil {
		return
	}
	if s != nil {
		n.noteSendTimeout(ctx, h, s.Conn(), err)
		return
	}
	after := h.Network().ConnsToPeer(pid)
	if len(before) == 1 && len(after) == 1 && before[0] == after[0] {
		n.noteSendTimeout(ctx, h, before[0], err)
	}
}

func (n *Node) pruneSendConnectionsLocked() {
	for conn, check := range n.sendConnections {
		if conn.IsClosed() && check.done == nil {
			delete(n.sendConnections, conn)
		}
	}
}

func (n *Node) checkSendConnections(ctx context.Context, h host.Host, pid peer.ID) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	n.mu.RLock()
	current := n.host == h && n.ctx != nil && n.ctx.Err() == nil
	n.mu.RUnlock()
	if !current {
		return context.Canceled
	}
	// Take a single deadline for the whole check phase, even with several
	// suspect connections. Leave at least half of the existing operation's
	// remaining budget for its normal open/dial/write path.
	deadline, ok := ctx.Deadline()
	if !ok {
		return nil
	}
	checkDeadline := time.Now().Add(time.Until(deadline) / 2)
	for _, conn := range h.Network().ConnsToPeer(pid) {
		if err := n.checkSendConnection(ctx, h, conn, checkDeadline); err != nil {
			return err
		}
	}
	return ctx.Err()
}

func (n *Node) checkSendConnection(ctx context.Context, h host.Host, conn network.Conn, deadline time.Time) error {
	n.sendConnectionsMu.Lock()
	n.pruneSendConnectionsLocked()
	check := n.sendConnections[conn]
	if check == nil || !time.Now().Before(deadline) || ctx.Err() != nil {
		n.sendConnectionsMu.Unlock()
		return ctx.Err()
	}
	if check.done != nil {
		done := check.done
		n.sendConnectionsMu.Unlock()
		waitCtx, cancel := context.WithDeadline(ctx, deadline)
		defer cancel()
		select {
		case <-done:
			return ctx.Err()
		case <-waitCtx.Done():
			// A longer-lived owner must not consume this operation's I/O
			// reserve. It keeps the single probe; this waiter can proceed.
			return ctx.Err()
		}
	}
	done := make(chan struct{})
	check.done = done
	n.sendConnectionsMu.Unlock()

	probeCtx, cancel := context.WithDeadline(ctx, deadline)
	responsive, unresponsive := checkSendConnectionResponse(probeCtx, conn)
	cancel()
	// Cancellation, shutdown, and a replaced host revoke the checking owner's
	// authority. Close only its captured connection, never a peer or successor.
	n.mu.RLock()
	if unresponsive && ctx.Err() == nil && n.host == h && n.ctx != nil && n.ctx.Err() == nil && !conn.IsClosed() {
		_ = conn.Close()
	}
	n.mu.RUnlock()
	n.sendConnectionsMu.Lock()
	if n.sendConnections[conn] == check {
		if responsive || conn.IsClosed() {
			delete(n.sendConnections, conn)
		} else {
			check.done = nil // inconclusive: retain for a later retry
		}
	}
	close(done)
	n.sendConnectionsMu.Unlock()
	return ctx.Err()
}

type sendResponseStream struct {
	network.Stream
	received    int
	written     int
	writeFailed bool
}

func (s *sendResponseStream) Read(p []byte) (int, error) {
	n, err := s.Stream.Read(p)
	s.received += n
	return n, err
}

func (s *sendResponseStream) Write(p []byte) (int, error) {
	n, err := s.Stream.Write(p)
	s.written += n
	s.writeFailed = s.writeFailed || err != nil || n != len(p)
	return n, err
}

// Use the pinned multistream handshake on an admitted, independent stream of
// the suspect connection. Even an unsupported protocol response proves traffic
// returned; do not wait for an application handler (including a ping handler).
// Unlike ping.Ping(host, peer), Conn.NewStream cannot dial or select a sibling.
// Stream admission/resource errors and resets remain inconclusive. Retirement
// requires a written request and no response through the bounded read deadline.
func checkSendConnectionResponse(ctx context.Context, conn network.Conn) (responsive, unresponsive bool) {
	if ctx.Err() != nil || conn.IsClosed() {
		return false, false
	}
	s, err := conn.NewStream(network.WithAllowLimitedConn(ctx, "send-recovery"))
	if err != nil {
		return false, false
	}
	defer s.Reset()
	if err := s.SetProtocol(ping.ID); err != nil {
		return false, false
	}
	deadline, _ := ctx.Deadline()
	if err := s.SetDeadline(deadline); err != nil {
		return false, false
	}
	resetDone := make(chan struct{})
	stopReset := context.AfterFunc(ctx, func() { _ = s.Reset(); close(resetDone) })
	defer func() {
		if !stopReset() {
			<-resetDone
		}
	}()
	observed := &sendResponseStream{Stream: s}
	// SelectProtoOrFail joins its bounded writer before returning; counters
	// are read only after that join. Reset also releases partial negotiation.
	err = multistream.SelectProtoOrFail(ping.ID, observed)
	return observed.received > 0, observed.received == 0 && observed.written > 0 && !observed.writeFailed &&
		(isSendTimeout(err) || errors.Is(ctx.Err(), context.DeadlineExceeded))
}
