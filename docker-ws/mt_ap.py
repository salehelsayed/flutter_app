#!/usr/bin/env python3
"""Fix proofs (2026-10-23, px + emu + sim): tiny W3C client for the private Appium server on port 4725.

Run on the Mac: host-run python3 docker-ws/st_ap.py <px|sim> <command> [args]
  open | close | src [regex] | find <sel> | tap <sel> | type <sel> <text> | clear <sel>
  tapxy <x> <y> | swipe <x1> <y1> <x2> <y2> [ms] | back | shot <name> | wait <sel> [secs]
  app <activate|terminate|state> | ime <empty|swiftkey>
Selectors: px uses text:<t>, textc:<t> (contains), desc:<d>, descc:<d>, id:<res-id>, xp:<xpath>.
           sim uses an iOS predicate string.
"""
import base64
import json
import os
import re
import subprocess
import sys
import time
import urllib.request

BASE = "http://127.0.0.1:4725"
HERE = os.path.dirname(os.path.abspath(__file__))
STORE = os.path.join(HERE, "mt_ap_sessions.json")
SHOTS = os.path.join(HERE, "..", ".codex-test-logs", "move-terminal-20261024T0029Z", "shots")
PX_SERIAL = "21071FDF600CSC"
SERIALS = {"px": "21071FDF600CSC", "emu": "emulator-5560"}
PORTS = {"px": 8231, "emu": 8232}
PX_PKG = "com.mknoon.sims.t011"
SIM_UDID = "F83C694C-90FE-45B7-8C01-AF14B865DC71"
SIM_BUNDLE = "com.mknoon.app"
IMES = {"empty": "io.appium.settings/.EmptyIME", "swiftkey": "com.touchtype.swiftkey/com.touchtype.KeyboardService"}


def req(method, path, body=None, timeout=600):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(BASE + path, data=data, method=method, headers={"Content-Type": "application/json"})
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
        raise SystemExit(f"no session for {phone}")
    return s


def locator(phone, sel):
    if phone == "sim":
        return {"using": "-ios predicate string", "value": sel}
    kind, _, v = sel.partition(":")
    if kind == "text":
        return {"using": "xpath", "value": f'//*[@text="{v}"]'}
    if kind == "textc":
        return {"using": "xpath", "value": f'//*[contains(@text,"{v}")]'}
    if kind == "desc":
        return {"using": "xpath", "value": f'//*[@content-desc="{v}"]'}
    if kind == "descc":
        return {"using": "xpath", "value": f'//*[contains(@content-desc,"{v}")]'}
    if kind == "id":
        return {"using": "id", "value": v}
    if kind == "xp":
        return {"using": "xpath", "value": v}
    raise SystemExit("bad selector")


def el(phone, sel):
    return list(req("POST", f"/session/{sid(phone)}/element", locator(phone, sel)).values())[0]


def pointer(phone, moves):
    req("POST", f"/session/{sid(phone)}/actions", {"actions": [{
        "type": "pointer", "id": "f1", "parameters": {"pointerType": "touch"}, "actions": moves}]})


def main():
    phone, cmd, args = sys.argv[1], sys.argv[2], sys.argv[3:]
    if cmd == "open":
        if phone in SERIALS:
            caps = {"platformName": "Android", "appium:automationName": "UiAutomator2", "appium:udid": SERIALS[phone],
                    "appium:appPackage": PX_PKG, "appium:appActivity": "com.mknoon.app.MainActivity",
                    "appium:noReset": True, "appium:autoLaunch": False, "appium:newCommandTimeout": 3600,
                    "appium:systemPort": PORTS[phone]}
        else:
            caps = {"platformName": "iOS", "appium:automationName": "XCUITest", "appium:udid": SIM_UDID,
                    "appium:deviceName": "T011-receiver", "appium:bundleId": SIM_BUNDLE, "appium:noReset": True,
                    "appium:wdaLaunchTimeout": 420000, "appium:wdaLocalPort": 8120,
                    "appium:newCommandTimeout": 3600, "appium:autoLaunch": False}
        v = req("POST", "/session", {"capabilities": {"alwaysMatch": caps}}, timeout=900)
        s = sessions(); s[phone] = v["sessionId"]; json.dump(s, open(STORE, "w"))
        print("session open")
    elif cmd == "close":
        try:
            req("DELETE", f"/session/{sid(phone)}")
        finally:
            s = sessions(); s.pop(phone, None); json.dump(s, open(STORE, "w"))
        print("closed")
    elif cmd == "shot":
        os.makedirs(SHOTS, exist_ok=True)
        f = os.path.join(SHOTS, f"{args[0]}_{phone}.png")
        open(f, "wb").write(base64.b64decode(req("GET", f"/session/{sid(phone)}/screenshot")))
        print(os.path.abspath(f))
    elif cmd == "src":
        x = req("GET", f"/session/{sid(phone)}/source")
        for line in x.splitlines():
            m = dict(re.findall(r'([\w-]+)="([^"]*)"', line))
            if phone in SERIALS:
                t, d = m.get("text", ""), m.get("content-desc", "")
                if not (t or d or m.get("clickable") == "true"):
                    continue
                row = f'{m.get("class", "?").split(".")[-1]} | {t} | {d} | {m.get("bounds", "")} | clk={m.get("clickable", "")}'
            else:
                if "type=" not in line:
                    continue
                row = f'{m.get("type", "?").replace("XCUIElementType", "")} | {m.get("name", "")} | {m.get("label", "")} | {m.get("value", "")} | {m.get("x")},{m.get("y")} {m.get("width")}x{m.get("height")} | {m.get("visible", "")}'
            if not args or re.search(args[0], row):
                print(row)
    elif cmd in ("find", "tap", "type", "clear"):
        e = el(phone, args[0])
        if cmd == "find":
            r = req("GET", f"/session/{sid(phone)}/element/{e}/rect")
            print("found", r)
        elif cmd == "tap":
            req("POST", f"/session/{sid(phone)}/element/{e}/click", {}); print("tapped")
        elif cmd == "clear":
            req("POST", f"/session/{sid(phone)}/element/{e}/clear", {}); print("cleared")
        else:
            req("POST", f"/session/{sid(phone)}/element/{e}/value", {"text": args[1]}); print("typed")
    elif cmd == "tapxy":
        pointer(phone, [{"type": "pointerMove", "duration": 0, "x": int(args[0]), "y": int(args[1])},
                        {"type": "pointerDown", "button": 0}, {"type": "pause", "duration": 80},
                        {"type": "pointerUp", "button": 0}]); print("tapped")
    elif cmd == "swipe":
        ms = int(args[4]) if len(args) > 4 else 300
        pointer(phone, [{"type": "pointerMove", "duration": 0, "x": int(args[0]), "y": int(args[1])},
                        {"type": "pointerDown", "button": 0},
                        {"type": "pointerMove", "duration": ms, "x": int(args[2]), "y": int(args[3])},
                        {"type": "pointerUp", "button": 0}]); print("swiped")
    elif cmd == "back":
        req("POST", f"/session/{sid(phone)}/back", {}); print("back")
    elif cmd == "wait":
        secs = float(args[1]) if len(args) > 1 else 30
        end = time.time() + secs
        while time.time() < end:
            if req("POST", f"/session/{sid(phone)}/elements", locator(phone, args[0])):
                print("found"); return
            time.sleep(1)
        print("NOT FOUND"); sys.exit(1)
    elif cmd == "app":
        a = args[0]
        if phone in SERIALS:
            key = {"activate": "activateApp", "terminate": "terminateApp", "state": "queryAppState"}[a]
            print(req("POST", f"/session/{sid(phone)}/execute/sync", {"script": f"mobile: {key}", "args": [{"appId": PX_PKG}]}))
        else:
            key = {"activate": "activateApp", "terminate": "terminateApp", "state": "queryAppState"}[a]
            print(req("POST", f"/session/{sid(phone)}/execute/sync", {"script": f"mobile: {key}", "args": [{"bundleId": SIM_BUNDLE}]}))
    elif cmd == "clip":
        txt = open(args[0]).read() if os.path.exists(args[0]) else args[0]
        req("POST", f"/session/{sid(phone)}/appium/device/set_clipboard",
            {"content": base64.b64encode(txt.encode()).decode(), "contentType": "plaintext"})
        print("clipboard set len", len(txt))
    elif cmd == "getclip":
        v = req("POST", f"/session/{sid(phone)}/appium/device/get_clipboard", {"contentType": "plaintext"})
        txt = base64.b64decode(v or "").decode()
        fd = os.open(args[0], os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600); os.write(fd, txt.encode()); os.close(fd)
        print("clipboard saved len", len(txt))
    elif cmd == "longpress":
        r = req("GET", f"/session/{sid(phone)}/element/{el(phone, args[0])}/rect")
        x, y = int(r["x"] + r["width"] / 2), int(r["y"] + r["height"] / 2)
        pointer(phone, [{"type": "pointerMove", "duration": 0, "x": x, "y": y}, {"type": "pointerDown", "button": 0},
                        {"type": "pause", "duration": 1200}, {"type": "pointerUp", "button": 0}]); print("longpressed")
    elif cmd == "startthen":
        # Tap Start transfer, poll for the in-progress Cancel transfer button, then cancel or force-stop the owned source.
        mode = args[0]
        t0 = time.time()
        req("POST", f"/session/{sid(phone)}/element/{el(phone, 'desc:Start transfer')}/click", {})
        print("start tapped", time.strftime("%H:%M:%S", time.gmtime()))
        loc = locator(phone, "desc:Cancel transfer")
        found = None
        while time.time() - t0 < 60:
            r = req("POST", f"/session/{sid(phone)}/elements", loc)
            if r:
                found = list(r[0].values())[0]
                break
        if not found:
            print("NO CANCEL BUTTON SEEN"); sys.exit(1)
        print("in-progress seen after %.1fs" % (time.time() - t0), time.strftime("%H:%M:%S", time.gmtime()))
        if mode == "cancel":
            # Flutter rebuilds the progress panel on every stage change, so re-find on a stale reference.
            for _ in range(20):
                try:
                    req("POST", f"/session/{sid(phone)}/element/{found}/click", {})
                    print("cancel tapped", time.strftime("%H:%M:%S", time.gmtime()))
                    break
                except SystemExit as e:
                    r = req("POST", f"/session/{sid(phone)}/elements", loc)
                    if not r:
                        print("cancel button gone:", e); sys.exit(1)
                    found = list(r[0].values())[0]
        else:
            out = subprocess.run(["adb", "-s", SERIALS[phone], "shell", "am", "force-stop", PX_PKG], capture_output=True, text=True)
            print("force-stop sent", time.strftime("%H:%M:%S", time.gmtime()), out.returncode)
    elif cmd == "getclip":
        v = req("POST", f"/session/{sid(phone)}/appium/device/get_clipboard", {"contentType": "plaintext"})
        txt = base64.b64decode(v or "").decode(errors="replace")
        open(args[0], "w").write(txt)
        print("clipboard saved len", len(txt))
    elif cmd == "ime":
        out = subprocess.run(["adb", "-s", SERIALS.get(phone, PX_SERIAL), "shell", "ime", "set", IMES[args[0]]], capture_output=True, text=True)
        print(out.stdout.strip() or out.stderr.strip())
    else:
        raise SystemExit("usage")


if __name__ == "__main__":
    main()
