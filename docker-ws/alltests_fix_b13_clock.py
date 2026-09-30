"""Keep sendNow() call order unchanged (tests script it): measure the resend budget with the monotonic clock. [roots...]"""
import pathlib, sys
rel = 'go-mknoon/node/node.go'
edits = [("\tstarted := n.sendNow()\n\tresult, err := n.sendMessageAttempt(", "\tstarted := time.Now()\n\tresult, err := n.sendMessageAttempt("),
         ("\tremaining := timeout - n.sendNow().Sub(started)\n", "\tremaining := timeout - time.Since(started)\n")]
for root in (sys.argv[1:] or ['/Volumes/CrucialX9/flutter_app']):
    p = pathlib.Path(root, rel); s = p.read_text()
    for o, nw in edits:
        if nw in s: continue
        assert s.count(o) == 1, (root, o); s = s.replace(o, nw)
    p.write_text(s); print('patched', root)
