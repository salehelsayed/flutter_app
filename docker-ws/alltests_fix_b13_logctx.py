"""Add transport/attempt context to the B13 resend log line. [roots...]"""
import pathlib, sys
rel = 'go-mknoon/node/node.go'
old = 'log.Printf("[SEND] stale_relay_circuit_closed resending_once remaining_ms=%d", remaining.Milliseconds())'
new = 'log.Printf("[SEND] stale_relay_circuit_closed resending_once transport=%s ack_wait_ms=%d remaining_ms=%d", result.Transport, result.AckWaitMs, remaining.Milliseconds())'
for root in (sys.argv[1:] or ['/Volumes/CrucialX9/flutter_app']):
    p = pathlib.Path(root, rel); s = p.read_text()
    if new in s: print('already', root); continue
    assert s.count(old) == 1, root; p.write_text(s.replace(old, new)); print('patched', root)
