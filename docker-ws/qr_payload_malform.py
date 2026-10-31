#!/usr/bin/env python3
"""Copy a private QR payload with one string field ('un' by default) turned into a number. Never prints the payload.
   python3 docker-ws/qr_payload_malform.py <in.private.txt> <out.private.txt> [field]"""
import json, sys
raw = open(sys.argv[1]).read()
field = sys.argv[3] if len(sys.argv) > 3 else "un"
start = raw.index("{")
prefix, body = raw[:start], json.loads(raw[start:])
print("keys=" + ",".join(sorted(body.keys())) + " prefix_len=%d" % len(prefix))
body[field] = 12345
open(sys.argv[2], "w").write(prefix + json.dumps(body, separators=(",", ":")))
print("malformed field=" + field)
