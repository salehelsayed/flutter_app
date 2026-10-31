#!/usr/bin/env python3
"""Enter the iPhone 11 passcode on the iOS passcode screen by tapping its digit keys (ap.py session).
Reads IPHONE11_PIN from /workspace/.env; never prints, logs or passes it on a command line.
Usage: AP_BASE=... python3 calls31_unlock11.py      -> prints 'unlocked' / 'still locked' / 'no keypad'"""
import json, os, sys, time, urllib.request
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "beta"))
import ap  # noqa: E402
pin = None
for line in open("/workspace/.env"):
    if line.startswith("IPHONE11_PIN="):
        pin = line.split("=", 1)[1].strip().strip('"').strip("'")
if not pin:
    print("no pin"); sys.exit(2)
s = ap.sid("11")
try:
    ap.req("POST", f"/session/{s}/execute/sync", {"script": "mobile: unlock", "args": []})  # wakes the screen, then times out on a passcode phone
except SystemExit:
    pass
def find(label):
    v = ap.req("POST", f"/session/{s}/elements", {"using": "-ios predicate string", "value": f"label == '{label}' AND (type == 'XCUIElementTypeKey' OR type == 'XCUIElementTypeButton')"})
    return v[0][list(v[0].keys())[0]] if v else None
time.sleep(0.5)
for d in pin:
    e = find(d)
    if not e:
        print("no keypad"); sys.exit(3)
    r = ap.req("GET", f"/session/{s}/element/{e}/rect")
    ap.tapxy("11", int(r["x"] + r["width"] / 2), int(r["y"] + r["height"] / 2))
    time.sleep(0.3)
time.sleep(2)
v = ap.req("POST", f"/session/{s}/execute/sync", {"script": "mobile: isLocked", "args": []})
print("still locked" if v else "unlocked")
