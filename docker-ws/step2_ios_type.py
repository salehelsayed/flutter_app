#!/usr/bin/env python3
"""Type a fixture file into the iPhone Mknoon composer through the ap.py session, read the field value back,
print MATCH/MISMATCH (no payload). With --send also tap the send button.  step2_ios_type.py <13> <file> [--send]"""
import sys, os, time
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "beta"))
import ap
phone, path = sys.argv[1], sys.argv[2]
payload = open(path, encoding="utf-8").read().rstrip("\n")
s = ap.sid(phone)
e = ap.el(phone, "type IN {'XCUIElementTypeTextView','XCUIElementTypeTextField'}")
ap.req("POST", f"/session/{s}/element/{e}/click", {})
time.sleep(1)
ap.req("POST", f"/session/{s}/element/{e}/value", {"text": payload})
time.sleep(1)
got = ap.req("GET", f"/session/{s}/element/{e}/attribute/value") or ""
print("MATCH" if got == payload else f"MISMATCH len={len(got)} want={len(payload)}")
if "--send" in sys.argv and got == payload:
    b = ap.el(phone, "label BEGINSWITH 'Send'")
    ap.req("POST", f"/session/{s}/element/{b}/click", {})
    print("SENT", time.strftime("%H:%M:%S", time.gmtime()))
