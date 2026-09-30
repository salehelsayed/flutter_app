#!/usr/bin/env python3
"""One-line signature of a Runner-*.ips crash report: app build, exception, top faulting frames, BONSOIR flag."""
import json, sys
raw = open(sys.argv[1]).read()
head, body = raw.split("\n", 1)
h, b = json.loads(head), json.loads(body)
imgs = b.get("usedImages", [])


def nm(f):
    i = f.get("imageIndex")
    return (imgs[i].get("name") or imgs[i].get("path", "?").split("/")[-1]) if i is not None and i < len(imgs) else "?"


ft = b.get("faultingThread", 0)
th = b["threads"][ft]
frames = [nm(f) + ":" + f.get("symbol", "?")[:70] for f in th.get("frames", [])]
text = " ".join(frames).lower()
flag = "BONSOIR" if ("bonsoir" in text or "dnsservice" in text) else "other"
ex = b.get("exception", {})
print(flag, h.get("app_version"), ex.get("type"), ex.get("signal"), "queue=%s" % th.get("queue"), "|",
      " <- ".join(frames[:5]))
