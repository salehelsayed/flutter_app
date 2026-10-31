#!/usr/bin/env python3
"""iPhone swipe-kill during the translator download: tap Download on Wi-Fi, poll the progress label, at >= start GB
open the App Switcher (slow swipe up from bottom edge + hold) and fling the centre card up, then report app state.
No screenshots.   AP_BASE=... tr129_ios_swipekill.py <13|11> <trace-out> [start_gb=0.6]"""
import os, re, sys, time
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "beta"))
import ap
phone, outp = sys.argv[1], sys.argv[2]; start = float(sys.argv[3]) if len(sys.argv) > 3 else 0.6
out = open(outp, "a")
def log(m):
    l = f"{time.strftime('%H:%M:%S', time.gmtime())} {m}"; print(l, flush=True); out.write(l + "\n"); out.flush()
def labels():
    x = ap.req("GET", f"/session/{ap.sid(phone)}/source")
    return [l for l in re.findall(r'label="([^"]*)"', x)]
def prog():
    for l in labels():
        m = re.search(r"([\d.]+) of 2\.6 GB", l)
        if m: return l, float(m.group(1))
    return None, None
def drag(pts, hold_ms=0):
    acts = [{"type": "pointerMove", "duration": 0, "x": pts[0][0], "y": pts[0][1]}, {"type": "pointerDown", "button": 0}]
    for (x, y, d) in pts[1:]: acts.append({"type": "pointerMove", "duration": d, "x": x, "y": y})
    if hold_ms: acts.append({"type": "pause", "duration": hold_ms})
    acts.append({"type": "pointerUp", "button": 0})
    ap.req("POST", f"/session/{ap.sid(phone)}/actions", {"actions": [{"type": "pointer", "id": "f1", "parameters": {"pointerType": "touch"}, "actions": acts}]})
def state():
    return ap.req("POST", f"/session/{ap.sid(phone)}/execute/sync", {"script": "mobile: queryAppState", "args": [{"bundleId": ap.BUNDLE}]})
e = ap.el(phone, 'label == "Download on Wi-Fi"'); ap.req("POST", f"/session/{ap.sid(phone)}/element/{e}/click", {}); log("tapped Download on Wi-Fi")
t0 = time.time(); g = None
while time.time() - t0 < 240:
    l, g = prog(); log(f"pre {l}")
    if g is not None and g >= start: break
    time.sleep(1)
log(f"KILL START at {g} GB")
drag([(195, 840), (195, 700, 150), (195, 520, 450)], hold_ms=900)   # open App Switcher
time.sleep(1.5)
log(f"after switcher gesture state={state()}")
drag([(195, 430), (195, 60, 180)])   # fling centre card up
time.sleep(2)
log(f"after card fling state={state()}")
