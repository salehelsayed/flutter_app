#!/usr/bin/env python3
"""Print the labelled nodes of a Maestro hierarchy dump: text / a11y / id + bounds."""
import json, sys

def walk(n, out):
    a = n.get("attributes", {})
    t = (a.get("text") or "").strip(); acc = (a.get("accessibilityText") or "").strip()
    rid = (a.get("resource-id") or "").strip(); hint = (a.get("hintText") or "").strip()
    if 'inputmethod' in rid or 'systemui' in rid or 'scroll bar' in acc:
        pass
    elif t or acc or rid or hint:
        out.append(f'{a.get("bounds","")}\ttext={t!r} a11y={acc!r} id={rid!r} hint={hint!r} click={a.get("clickable","")}')
    for c in n.get("children", []):
        walk(c, out)

for p in sys.argv[1:]:
    raw = open(p).read(); i = raw.find("{")
    out = []; walk(json.loads(raw[i:]), out)
    print(f"=== {p} ({len(out)} labelled)"); print("\n".join(out))
