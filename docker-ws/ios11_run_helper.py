#!/usr/bin/env python3
"""Helpers for the group open delay runs on the iPhone 11 (uses the ap.py session).
  park                 bring the WDA runner (blank screen) to front so Mknoon goes to background
  keepalive <secs>     tap the WDA runner screen every 30 s for <secs> (only while the runner is in front)
  active               print the active app bundle id
  ncenter              swipe down from the top left to open Notification Center (no screenshots)
  tapnote <regex>      tap the first notification cell whose label matches regex (label not printed)
  watch <token> <secs> poll Mknoon page source until a StaticText contains token; prints UTC times
"""
import json, re, sys, time, datetime
sys.path.insert(0, __import__("os").path.join(__import__("os").path.dirname(__file__), "beta"))
import ap
P = "11"
RUNNER = "com.facebook.WebDriverAgentRunner.xctrunner"
def now(): return datetime.datetime.utcnow().strftime("%H:%M:%S.%f")[:-3] + "Z"
def ex(script, args=None): return ap.req("POST", f"/session/{ap.sid(P)}/execute/sync", {"script": script, "args": [args or {}]})
def active(): return (ex("mobile: activeAppInfo") or {}).get("bundleId")
def swipe(x1, y1, x2, y2, ms=400):
    ap.req("POST", f"/session/{ap.sid(P)}/actions", {"actions": [{"type": "pointer", "id": "f1", "parameters": {"pointerType": "touch"},
        "actions": [{"type": "pointerMove", "duration": 0, "x": x1, "y": y1}, {"type": "pointerDown", "button": 0},
                    {"type": "pointerMove", "duration": ms, "x": x2, "y": y2}, {"type": "pointerUp", "button": 0}]}]})
cmd, a = sys.argv[1], sys.argv[2:]
if cmd == "park":
    ex("mobile: activateApp", {"bundleId": RUNNER}); time.sleep(2); print(now(), "active", active())
elif cmd == "active":
    print(now(), active())
elif cmd == "keepalive":
    end = time.time() + float(a[0])
    while time.time() < end:
        b = active()
        if b != RUNNER: print(now(), "STOP active is", b); sys.exit(2)
        ap.tapxy(P, 207, 450); time.sleep(30)
    print(now(), "keepalive done")
elif cmd == "ncenter":
    swipe(60, 2, 60, 600); time.sleep(2); print(now(), "ncenter swiped")
elif cmd == "tapnote":
    src = ap.req("GET", f"/session/{ap.sid(P)}/source")
    cells = []
    for line in src.splitlines():
        m = dict(re.findall(r'(\w+)="([^"]*)"', line))
        if re.search(a[0], m.get("label", "")) and m.get("type", "").endswith(("Cell", "Button", "Other")) and m.get("visible") == "true":
            cells.append(m)
    if not cells: print(now(), "NO MATCH"); sys.exit(3)
    c = cells[0]; x = int(c["x"]) + int(c["width"]) // 2; y = int(c["y"]) + int(c["height"]) // 2
    ap.tapxy(P, x, y); print(now(), "tapped notification", c["type"].replace("XCUIElementType", ""), f"matches={len(cells)}")
elif cmd == "watch":
    tok, end = a[0], time.time() + float(a[1])
    while time.time() < end:
        t0 = now()
        try: src = ap.req("GET", f"/session/{ap.sid(P)}/source", timeout=60)
        except SystemExit as e: print(t0, "src error", str(e)[:80]); time.sleep(1); continue
        toks = tok.split(",")
        found = [t for t in toks if any(t.lower() in l.lower() and "StaticText" in l for l in src.splitlines())]
        hdr = re.findall(r'StaticText[^>]*label="(DelayG[0-9])"', src)
        print(t0, "->", now(), "found", ",".join(found) or "-", "hdr", ",".join(sorted(set(hdr))) or "-")
        if len(a) > 2 and found and set(a[2].split(",")) <= set(found): break
