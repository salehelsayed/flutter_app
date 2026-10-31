#!/usr/bin/env python3
"""Minimal UiAutomator2 client for the private Appium on :4725 (Android, used where adb input cannot type Unicode).
Never prints payloads. Session ids in docker-ws/step2_and_sessions.json.
  step2_and_ap.py <serial> open|close
  step2_and_ap.py <serial> setfile <file>       set chat_composer text from file, read back, print MATCH/MISMATCH
  step2_and_ap.py <serial> tapdesc <content-desc>
  step2_and_ap.py <serial> src <file>          save page source
  step2_and_ap.py <serial> texts               content-desc/text of all nodes (page source)
"""
import json, os, re, sys, html, urllib.request
BASE = "http://host.docker.internal:4725"
STORE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "step2_and_sessions.json")

def req(m, p, b=None, t=300):
    r = urllib.request.Request(BASE + p, data=json.dumps(b).encode() if b is not None else None, method=m,
                               headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(r, timeout=t) as x:
            return json.loads(x.read() or b"{}").get("value")
    except urllib.error.HTTPError as e:
        v = json.loads(e.read() or b"{}").get("value", {})
        raise SystemExit(f"ERROR {e.code}: {v.get('error')}: {str(v.get('message'))[:200]}")

def store():
    try: return json.load(open(STORE))
    except Exception: return {}

serial, cmd, args = sys.argv[1], sys.argv[2], sys.argv[3:]
if cmd == "open":
    v = req("POST", "/session", {"capabilities": {"alwaysMatch": {"platformName": "Android", "appium:automationName": "UiAutomator2",
        "appium:udid": serial, "appium:noReset": True, "appium:skipDeviceInitialization": True, "appium:autoLaunch": False,
        "appium:newCommandTimeout": 900}}})
    s = store(); s[serial] = v["sessionId"]; json.dump(s, open(STORE, "w")); print("session", v["sessionId"]); sys.exit()
sid = store().get(serial) or sys.exit("no session")
if cmd == "close":
    req("DELETE", f"/session/{sid}"); s = store(); s.pop(serial, None); json.dump(s, open(STORE, "w")); print("closed"); sys.exit()
def find(using, value):
    return list(req("POST", f"/session/{sid}/element", {"using": using, "value": value}).values())[0]
if cmd == "setfile":
    payload = open(args[0], encoding="utf-8").read().rstrip("\n")
    e = find("-android uiautomator", 'new UiSelector().resourceId("chat_composer")')
    req("POST", f"/session/{sid}/element/{e}/click", {})
    req("POST", f"/session/{sid}/element/{e}/clear", {})
    req("POST", f"/session/{sid}/element/{e}/value", {"text": payload})
    got = req("GET", f"/session/{sid}/element/{e}/text")
    print("MATCH" if got == payload else f"MISMATCH len={len(got)} want={len(payload)}")
elif cmd == "tapdesc":
    e = find("accessibility id", args[0]); req("POST", f"/session/{sid}/element/{e}/click", {}); print("tapped", args[0])
elif cmd == "texts":
    src = req("GET", f"/session/{sid}/source")
    for m in re.finditer(r'(content-desc|text)="([^"]{1,300})"', src):
        print(m.group(1) + '="' + m.group(2) + '"')
elif cmd == "src":
    open(args[0], "w", encoding="utf-8").write(req("GET", f"/session/{sid}/source"))
    print("saved")
elif cmd == "tapstarts":
    e = find("-android uiautomator", 'new UiSelector().descriptionStartsWith("%s")' % args[0])
    req("POST", f"/session/{sid}/element/{e}/click", {}); print("tapped", args[0])
