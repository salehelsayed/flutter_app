#!/usr/bin/env python3
"""Check which private fixture texts appear in UI labels of a page-source dump (iOS XML or Android source).
Prints per fixture: exact hit, hit after removing bidi controls, and the extra chars around it (as code points). No payload output.
  step2_label_check.py <source.xml> <fixture.txt>..."""
import html, re, sys
src = open(sys.argv[1], encoding="utf-8").read()
labels = [html.unescape(m.group(2)) for m in re.finditer(r'(label|content-desc|text|value|name)="([^"]*)"', src)]
BIDI = dict.fromkeys(list(range(0x202A, 0x202F)) + list(range(0x2066, 0x206A)) + [0x200E, 0x200F, 0x061C])
for f in sys.argv[2:]:
    fx = open(f, encoding="utf-8").read().rstrip("\n")
    exact = [l for l in labels if fx in l]
    loose = [l for l in labels if fx in l.translate(BIDI)]
    info = ""
    if loose:
        l = loose[0]; i = l.find(fx) if fx in l else -1
        ctrl = sorted({hex(ord(c)) for c in l if ord(c) in BIDI})
        info = f"labelLen={len(l)} bidiCtrls={ctrl}"
    print(f"{f.rsplit('/',1)[-1]}: exact={len(exact)} afterBidiStrip={len(loose)} {info}")
