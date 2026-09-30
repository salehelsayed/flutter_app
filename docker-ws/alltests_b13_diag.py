"""Log-only diagnostic for B13 (live_not_acked): when the ACK read fails after a successful write, log which
connection was used (transport, whether relayed, age since opened, closed state). No behavior change.
Usage: [roots...] (default both checkouts)."""
import pathlib, sys
rel = 'go-mknoon/node/node.go'
old = """	if err != nil {
		// Message was written but ACK read failed
		_ = s.Reset()
		n.noteSendTimeout(commandCtx, h, s.Conn(), err)
"""
new = """	if err != nil {
		// Message was written but ACK read failed
		if conn := s.Conn(); conn != nil {
			// Diagnostic only: identify a reused connection whose remote
			// process may already be gone (relayed QUIC keeps it open).
			log.Printf("[SEND] ack_read_failed transport=%s limited=%t conn_age_ms=%d conn_closed=%t ack_wait_ms=%d",
				transport, conn.Stat().Limited,
				time.Since(conn.Stat().Opened).Milliseconds(), conn.IsClosed(),
				time.Since(ackStart).Milliseconds())
		}
		_ = s.Reset()
		n.noteSendTimeout(commandCtx, h, s.Conn(), err)
"""
roots = sys.argv[1:] or ['/Volumes/CrucialX9/flutter_app', '/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree']
for root in roots:
    p = pathlib.Path(root, rel); s = p.read_text()
    if 'ack_read_failed transport=' in s:
        print('already', root); continue
    assert s.count(old) == 1, root
    p.write_text(s.replace(old, new)); print('patched', root)
