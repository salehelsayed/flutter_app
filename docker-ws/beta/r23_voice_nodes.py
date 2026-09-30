#!/usr/bin/env python3
"""Print every UI node that is a voice message bubble (text/accessibility contains 'Voice message'),
with its full text, from a `maestro hierarchy` dump. Usage: r23_voice_nodes.py <ui.json>"""
import json, sys
raw = open(sys.argv[1]).read()
i = raw.find("{")
if i < 0:
    print("NO HIERARCHY"); sys.exit(0)
root = json.loads(raw[i:])
hits = []
def walk(n):
    a = n.get("attributes", {})
    t = " | ".join(x for x in (a.get("accessibilityText"), a.get("text"), a.get("hintText")) if x)
    if "Voice message" in t or "voice message" in t:
        hits.append((a.get("bounds", ""), t.replace("\n", " / ")))
    for c in n.get("children", []):
        walk(c)
walk(root)
for b, t in hits:
    print("%-24s %s" % (b, t[:160]))
print("voice nodes: %d" % len(hits))
