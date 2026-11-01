#!/usr/bin/env python3
"""Tiny W3C WebDriver client for the private Appium server (port 4725) driving one Android target (UiAutomator2).

Usage: apa.py <serial> <command> [args]
  open                         create a session (noReset, no autolaunch); id saved in apa_sessions.json
  close                        delete the session
  pkg                          current package
  shot <dest.png>              screenshot, only when com.mknoon.app is the current package
  src [regex]                  page source; with a regex, compact matching element lines (desc | text | bounds)
  find <desc-substring>        first element whose content-desc contains the text: prints desc and rect
  tap <desc-substring>         tap the center of that element
  tapxy <x> <y>
  swipe <x1> <y1> <x2> <y2> [ms]
  hold_swipe <x1> <y1> <x2> <y2> <move-ms> <hold-ms>   press, move, keep holding, release
  pinch <cx> <cy> <from-gap> <to-gap> [ms]             two-finger vertical pinch (to<from) or spread (to>from)
  back
  type <text>                  type <text> into the focused field (unicode ok; tap the field first)
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
STORE = os.path.join(HERE, "apa_sessions.json")
PKG = "com.mknoon.app"


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


def sid(serial):
    try:
        return json.load(open(STORE))[serial]
    except (OSError, ValueError, KeyError):
        raise SystemExit(f"no session for {serial}; run: apa.py {serial} open")


def actions(s, fingers):
    try:
        req("POST", f"/session/{s}/actions", {"actions": [
            {"type": "pointer", "id": f"f{i}", "parameters": {"pointerType": "touch"}, "actions": a}
            for i, a in enumerate(fingers)]}, timeout=180)
    finally:
        # A rejected chain leaves pointers down and every later chain fails until they are released.
        urllib.request.urlopen(urllib.request.Request(BASE + f"/session/{s}/actions", method="DELETE"), timeout=60)


def nodes(s):
    x = req("GET", f"/session/{s}/source")
    out = []
    for line in x.splitlines():
        m = dict(re.findall(r'([\w-]+)="([^"]*)"', line))
        d, t = m.get("content-desc", ""), m.get("text", "")
        if d or t or m.get("resource-id", "").startswith("orbit."):
            out.append((d, t, m.get("bounds", ""), m.get("resource-id", "")))
    return out


def center(b):
    x1, y1, x2, y2 = map(int, re.findall(r"\d+", b))
    return (x1 + x2) // 2, (y1 + y2) // 2


def main():
    serial, cmd, args = sys.argv[1], sys.argv[2], sys.argv[3:]
    if cmd == "open":
        caps = {"platformName": "Android", "appium:automationName": "UiAutomator2", "appium:udid": serial,
                "appium:noReset": True, "appium:autoLaunch": False, "appium:newCommandTimeout": 3600,
                "appium:systemPort": 8231 + (int(serial[9:]) - 5552 if re.fullmatch(r"emulator-\d+", serial) else 0), "appium:disableWindowAnimation": False,
                "appium:settings[waitForIdleTimeout]": 0}
        v = req("POST", "/session", {"capabilities": {"alwaysMatch": caps}}, timeout=600)
        try:
            st = json.load(open(STORE))
        except (OSError, ValueError):
            st = {}
        st[serial] = v["sessionId"]
        json.dump(st, open(STORE, "w"))
        req("POST", f"/session/{v['sessionId']}/appium/settings",
            {"settings": {"waitForIdleTimeout": 0, "ignoreUnimportantViews": False}})
        print("session", v["sessionId"])
        return
    s = sid(serial)
    if cmd == "close":
        req("DELETE", f"/session/{s}")
        st = json.load(open(STORE)); st.pop(serial, None); json.dump(st, open(STORE, "w")); print("closed")
    elif cmd == "pkg":
        print(req("GET", f"/session/{s}/appium/device/current_package"))
    elif cmd == "shot":
        if req("GET", f"/session/{s}/appium/device/current_package") != PKG:
            raise SystemExit("NOT MKNOON FOREGROUND, no screenshot")
        open(args[0], "wb").write(base64.b64decode(req("GET", f"/session/{s}/screenshot")))
        print("saved", args[0])
    elif cmd == "src":
        for d, t, b, rid in nodes(s):
            rid = re.sub(r"(face\.12D3KooW)(\w{4})\w+", r"face.\2", rid)
            line = f"{d.replace(chr(10), ' / ')} | {t} | {b} | {rid}"
            if not args or re.search(args[0], line):
                print(line)
    elif cmd in ("find", "tap"):
        for d, t, b, rid in nodes(s):
            if args[0] in d or args[0] in t:
                if cmd == "find":
                    print(d.replace("\n", " / "), "|", t, "|", b)
                else:
                    x, y = center(b)
                    actions(s, [[{"type": "pointerMove", "duration": 0, "x": x, "y": y},
                                 {"type": "pointerDown", "button": 0}, {"type": "pause", "duration": 80},
                                 {"type": "pointerUp", "button": 0}]])
                    print("tapped", d.replace("\n", " / ")[:60], "at", x, y)
                return
        print("NOT FOUND:", args[0]); sys.exit(3)
    elif cmd == "tapxy":
        x, y = int(args[0]), int(args[1])
        actions(s, [[{"type": "pointerMove", "duration": 0, "x": x, "y": y},
                     {"type": "pointerDown", "button": 0}, {"type": "pause", "duration": 80},
                     {"type": "pointerUp", "button": 0}]]); print("tapped", x, y)
    elif cmd == "swipe":
        ms = int(args[4]) if len(args) > 4 else 300
        actions(s, [[{"type": "pointerMove", "duration": 0, "x": int(args[0]), "y": int(args[1])},
                     {"type": "pointerDown", "button": 0},
                     {"type": "pointerMove", "duration": ms, "x": int(args[2]), "y": int(args[3])},
                     {"type": "pointerUp", "button": 0}]]); print("swiped")
    elif cmd == "hold_swipe":
        actions(s, [[{"type": "pointerMove", "duration": 0, "x": int(args[0]), "y": int(args[1])},
                     {"type": "pointerDown", "button": 0},
                     {"type": "pointerMove", "duration": int(args[4]), "x": int(args[2]), "y": int(args[3])},
                     {"type": "pause", "duration": int(args[5])},
                     {"type": "pointerUp", "button": 0}]]); print("held swipe")
    elif cmd == "pinch":
        cx, cy, a, b = map(int, args[:4]); ms = int(args[4]) if len(args) > 4 else 400
        f = lambda sign: [{"type": "pointerMove", "duration": 0, "x": cx, "y": cy + sign * a // 2},
                          {"type": "pointerDown", "button": 0},
                          {"type": "pointerMove", "duration": ms, "x": cx, "y": cy + sign * b // 2},
                          {"type": "pointerUp", "button": 0}]
        actions(s, [f(-1), f(1)]); print("pinched", a, "->", b)
    elif cmd == "back":
        req("POST", f"/session/{s}/back", {}); print("back")
    elif cmd == "type":
        # Flutter ignores ACTION_SET_TEXT; "mobile: type" goes through the IME into the focused field (tap it first).
        req("POST", f"/session/{s}/execute/sync", {"script": "mobile: type", "args": [{"text": args[0]}]}); print("typed", len(args[0]), "chars")
    else:
        raise SystemExit("unknown command")


if __name__ == "__main__":
    main()
