"""B13: after an ACK read timeout on a relayed (limited) connection, probe that exact connection; if it is
unresponsive (e.g. the relay circuit still points at a killed receiver process), close it and resend once within
the caller's remaining budget. Direct connections keep the 359f6fca7 behavior (never closed on timeout).
Receivers treat a repeated message id as duplicate. [roots...]"""
import pathlib, sys
rel = 'go-mknoon/node/node.go'
edits = [
("""func (n *Node) SendMessageWithNotificationPolicy(peerIdStr string, message string, timeoutMs int, quietRecovery bool) (resultValue SendMessageResult, resultErr error) {
	d := &connectionDiagnostics{}
""", """// staleRelayProbeTimeout bounds the one responsiveness probe run after an ACK
// read timeout on a relayed connection.
const staleRelayProbeTimeout = 2 * time.Second

func (n *Node) SendMessageWithNotificationPolicy(peerIdStr string, message string, timeoutMs int, quietRecovery bool) (SendMessageResult, error) {
	started := n.sendNow()
	result, err := n.sendMessageAttempt(peerIdStr, message, timeoutMs, quietRecovery, true)
	if err != nil || result.Acked || !result.staleRelayCircuitClosed {
		return result, err
	}
	timeout := SendTimeout
	if timeoutMs > 0 {
		timeout = time.Duration(timeoutMs) * time.Millisecond
	}
	remaining := timeout - n.sendNow().Sub(started)
	if remaining <= CommittedAckReserve {
		return result, err
	}
	// The written frame went into a relay circuit whose far end no longer
	// answers, so it was never received. A receiver treats a repeated message
	// id as a duplicate, which keeps this single resend idempotent.
	log.Printf("[SEND] stale_relay_circuit_closed resending_once remaining_ms=%d", remaining.Milliseconds())
	retry, retryErr := n.sendMessageAttempt(peerIdStr, message, int(remaining.Milliseconds()), quietRecovery, false)
	retry.ConnectionDiagnostics = append(result.ConnectionDiagnostics, retry.ConnectionDiagnostics...)
	return retry, retryErr
}

func (n *Node) sendMessageAttempt(peerIdStr string, message string, timeoutMs int, quietRecovery bool, allowStaleRelayRetry bool) (resultValue SendMessageResult, resultErr error) {
	d := &connectionDiagnostics{}
"""),
("""		_ = s.Reset()
		n.noteSendTimeout(commandCtx, h, s.Conn(), err)
		writtenResult.AckWaitMs = ackWaitMs
		return writtenResult, nil
""", """		_ = s.Reset()
		if allowStaleRelayRetry && n.closeUnresponsiveRelayConn(commandCtx, h, s.Conn()) {
			writtenResult.staleRelayCircuitClosed = true
		} else {
			n.noteSendTimeout(commandCtx, h, s.Conn(), err)
		}
		writtenResult.AckWaitMs = ackWaitMs
		return writtenResult, nil
"""),
("""	AckWaitMs             int64
	ConnectionDiagnostics []ConnectionDiagnostic
}
""", """	AckWaitMs             int64
	ConnectionDiagnostics []ConnectionDiagnostic

	// staleRelayCircuitClosed reports that the ACK wait failed on a relayed
	// connection that then failed its responsiveness probe and was closed.
	staleRelayCircuitClosed bool
}
"""),
]
rel2 = 'go-mknoon/node/send_connection_recovery.go'
FUNC = """
// closeUnresponsiveRelayConn probes a relayed (limited) connection once after an
// ACK read timeout and closes it only if it is unresponsive. A relay keeps a
// circuit to a killed peer process open until its idle timeout, so the next
// send would otherwise reuse it. Direct connections are never closed here.
func (n *Node) closeUnresponsiveRelayConn(ctx context.Context, h host.Host, conn network.Conn) bool {
	if conn == nil || conn.IsClosed() || !conn.Stat().Limited || ctx.Err() != nil {
		return false
	}
	probeCtx, cancel := context.WithTimeout(ctx, staleRelayProbeTimeout)
	_, unresponsive := checkSendConnectionResponse(probeCtx, conn)
	cancel()
	if !unresponsive || ctx.Err() != nil {
		return false
	}
	n.mu.RLock()
	defer n.mu.RUnlock()
	if n.host != h || n.ctx == nil || n.ctx.Err() != nil || conn.IsClosed() {
		return false
	}
	_ = conn.Close()
	return true
}
"""
roots = sys.argv[1:] or ['/Volumes/CrucialX9/flutter_app', '/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree']
for root in roots:
    p = pathlib.Path(root, rel); s = p.read_text()
    if 'sendMessageAttempt' in s:
        print('already', root); continue
    for old, new in edits:
        assert s.count(old) == 1, (root, old[:70]); s = s.replace(old, new)
    p.write_text(s)
    p2 = pathlib.Path(root, rel2); s2 = p2.read_text()
    if 'closeUnresponsiveRelayConn' not in s2:
        p2.write_text(s2.rstrip('\n') + '\n' + FUNC)
    print('patched', root)
