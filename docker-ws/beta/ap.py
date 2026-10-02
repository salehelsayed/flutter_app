#!/usr/bin/env python3
"""Tiny W3C WebDriver client for the private Appium server (r34_appium_server.sh, port 4725) driving the USB iPhones.

Usage: ap.py <phone> <command> [args]
  phone: 11 or 13
  open                         create a session (noReset, keeps app data); id saved in ap_sessions.json
  close                        delete the session
  shot <name>                  screenshot -> artifacts/beta-20260928/r2o-shots/<name>_<phone>.png
  src [regex]                  page source; with a regex, only matching element lines (compact)
  find <predicate>             first element matching an iOS predicate: prints id, label, rect
  tap <predicate>              tap the first match
  tapxy <x> <y>                tap a point
  type <predicate> <text>      type into the first match
  hold <predicate> <ms>        press and hold (long press) the first match
  swipe <x1> <y1> <x2> <y2> [ms]
  key <text>                   type text into the focused element (W3C key actions)
  app <activate|terminate|background|state> [secs]
  wait <predicate> [secs]      wait until an element matching the predicate exists
"""
import base64
import json
import os
import re
import sys
import time
import urllib.request

BASE = "http://host.docker.internal:4725"
HERE = os.path.dirname(os.path.abspath(__file__))
STORE = os.path.join(HERE, "ap_sessions.json")
SHOTS = os.path.join(HERE, "..", "..", "artifacts", "beta-20260928", "r2o-shots")
BUNDLE = "com.mknoon.app"
PHONES = {
    "11": {"udid": "00008030-001A6D2801BB802E", "name": "iPhone 11", "port": 8111},
    "13": {"udid": "00008110-00184D622289801E", "name": "iPhone 13", "port": 8113},
}


def req(method, path, body=None, timeout=600):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(BASE + path, data=data, method=method,
                               headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(r, timeout=timeout) as resp:
            return json.loads(resp.read() or b"{}").get("value")
    except urllib.error.HTTPError as e:
        v = json.loads(e.read() or b"{}").get("value", {})
        raise SystemExit(f"ERROR {e.code}: {v.get('error')}: {str(v.get('message'))[:300]}")


def sessions():
    try:
        return json.load(open(STORE))
    except (OSError, ValueError):
        return {}


def sid(phone):
    s = sessions().get(phone)
    if not s:
        raise SystemExit(f"no session for iPhone {phone}; run: ap.py {phone} open")
    return s


def el(phone, pred):
    v = req("POST", f"/session/{sid(phone)}/element", {"using": "-ios predicate string", "value": pred})
    return list(v.values())[0]


def tapxy(phone, x, y):
    req("POST", f"/session/{sid(phone)}/actions", {"actions": [{
        "type": "pointer", "id": "f1", "parameters": {"pointerType": "touch"},
        "actions": [{"type": "pointerMove", "duration": 0, "x": int(x), "y": int(y)},
                    {"type": "pointerDown", "button": 0}, {"type": "pause", "duration": 80},
                    {"type": "pointerUp", "button": 0}]}]})


def main():
    phone, cmd, args = sys.argv[1], sys.argv[2], sys.argv[3:]
    p = PHONES[phone]
    if cmd == "open":
        caps = {"platformName": "iOS", "appium:automationName": "XCUITest", "appium:udid": p["udid"],
                "appium:deviceName": p["name"], "appium:bundleId": BUNDLE, "appium:noReset": True,
                "appium:xcodeOrgId": "397R9Q4WMX", "appium:xcodeSigningId": "Apple Development",
                "appium:updatedWDABundleId": "com.facebook.WebDriverAgentRunner",
                "appium:wdaLaunchTimeout": 420000, "appium:wdaLocalPort": p["port"],
                "appium:newCommandTimeout": 3600, "appium:autoLaunch": False}
        v = req("POST", "/session", {"capabilities": {"alwaysMatch": caps}}, timeout=900)
        s = sessions(); s[phone] = v["sessionId"]; json.dump(s, open(STORE, "w"))
        print("session", v["sessionId"])
    elif cmd == "close":
        req("DELETE", f"/session/{sid(phone)}")
        s = sessions(); s.pop(phone, None); json.dump(s, open(STORE, "w")); print("closed")
    elif cmd == "shot":
        os.makedirs(SHOTS, exist_ok=True)
        f = os.path.join(SHOTS, f"{args[0]}_{phone}.png")
        open(f, "wb").write(base64.b64decode(req("GET", f"/session/{sid(phone)}/screenshot")))
        print(os.path.abspath(f))
    elif cmd == "src":
        x = req("GET", f"/session/{sid(phone)}/source")
        if not args:
            print(x)
            return
        for line in x.splitlines():
            if re.search(args[0], line):
                m = {k: v for k, v in re.findall(r'(\w+)="([^"]*)"', line)}
                print(m.get("type", "?").replace("XCUIElementType", ""), "|", m.get("name", ""), "|",
                      m.get("label", ""), "|", m.get("value", ""), "|",
                      f'{m.get("x")},{m.get("y")} {m.get("width")}x{m.get("height")}', "|", m.get("visible", ""))
    elif cmd in ("find", "tap", "type", "hold"):
        e = el(phone, args[0])
        if cmd == "find":
            r = req("GET", f"/session/{sid(phone)}/element/{e}/rect")
            lab = req("GET", f"/session/{sid(phone)}/element/{e}/attribute/label")
            print(e, "|", lab, "|", r)
        elif cmd == "tap":
            req("POST", f"/session/{sid(phone)}/element/{e}/click", {}); print("tapped")
        elif cmd == "type":
            req("POST", f"/session/{sid(phone)}/element/{e}/value", {"text": args[1]}); print("typed")
        else:
            r = req("GET", f"/session/{sid(phone)}/element/{e}/rect")
            cx, cy = r["x"] + r["width"] / 2, r["y"] + r["height"] / 2
            req("POST", f"/session/{sid(phone)}/actions", {"actions": [{
                "type": "pointer", "id": "f1", "parameters": {"pointerType": "touch"},
                "actions": [{"type": "pointerMove", "duration": 0, "x": int(cx), "y": int(cy)},
                            {"type": "pointerDown", "button": 0}, {"type": "pause", "duration": int(args[1])},
                            {"type": "pointerUp", "button": 0}]}]}, timeout=int(args[1]) // 1000 + 120)
            print("held", args[1], "ms")
    elif cmd == "tapxy":
        tapxy(phone, args[0], args[1]); print("tapped")
    elif cmd == "swipe":
        ms = int(args[4]) if len(args) > 4 else 300
        req("POST", f"/session/{sid(phone)}/actions", {"actions": [{
            "type": "pointer", "id": "f1", "parameters": {"pointerType": "touch"},
            "actions": [{"type": "pointerMove", "duration": 0, "x": int(args[0]), "y": int(args[1])},
                        {"type": "pointerDown", "button": 0},
                        {"type": "pointerMove", "duration": ms, "x": int(args[2]), "y": int(args[3])},
                        {"type": "pointerUp", "button": 0}]}]}); print("swiped")
    elif cmd == "key":
        acts = []
        for ch in args[0]:
            acts += [{"type": "keyDown", "value": ch}, {"type": "keyUp", "value": ch}]
        req("POST", f"/session/{sid(phone)}/actions", {"actions": [{"type": "key", "id": "k1", "actions": acts}]})
        print("keys sent")
    elif cmd == "app":
        a = args[0]
        if a == "state":
            print(req("POST", f"/session/{sid(phone)}/execute/sync",
                      {"script": "mobile: queryAppState", "args": [{"bundleId": BUNDLE}]}))
        elif a == "background":
            req("POST", f"/session/{sid(phone)}/execute/sync",
                {"script": "mobile: backgroundApp", "args": [{"seconds": float(args[1]) if len(args) > 1 else -1}]})
            print("backgrounded")
        else:
            req("POST", f"/session/{sid(phone)}/execute/sync",
                {"script": f"mobile: {a}App", "args": [{"bundleId": BUNDLE}]}); print(a + "d")
    elif cmd == "wait":
        end = time.time() + (float(args[1]) if len(args) > 1 else 30)
        while time.time() < end:
            v = req("POST", f"/session/{sid(phone)}/elements", {"using": "-ios predicate string", "value": args[0]})
            if v:
                print("found after", round(time.time() - end + (float(args[1]) if len(args) > 1 else 30), 1), "s")
                return
            time.sleep(1)
        print("NOT FOUND")
        sys.exit(1)


if __name__ == "__main__":
    main()
