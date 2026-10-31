#!/usr/bin/env python3
"""Pixel UI helper for device tests (container adb). Usage:
  px_ui.py dump            -> list visible text/content-desc with centers
  px_ui.py tap <substr>    -> tap first node whose text/desc contains substr
  px_ui.py has <substr>    -> exit 0 if present
"""
import os, re, subprocess, sys, xml.etree.ElementTree as ET
S = os.environ.get("PX_SERIAL", "21071FDF600CSC")
os.environ.setdefault("ADB_SERVER_SOCKET", "tcp:host.docker.internal:5037")
def adb(*a, t=60):
    return subprocess.run(["timeout", str(t), "adb", "-s", S, *a], capture_output=True, text=True).stdout
def nodes():
    adb("shell", "rm", "-f", "/sdcard/px_ui.xml")
    adb("shell", "uiautomator", "dump", "/sdcard/px_ui.xml", t=90)
    x = adb("shell", "cat", "/sdcard/px_ui.xml")
    x = x[x.find("<?xml"):] if "<?xml" in x else x
    out = []
    try:
        root = ET.fromstring(x)
    except ET.ParseError:
        return out
    for n in root.iter("node"):
        label = (n.get("text") or "") + ("" if not n.get("content-desc") else " | " + n.get("content-desc"))
        m = re.findall(r"\d+", n.get("bounds", ""))
        if label.strip() and len(m) == 4:
            x1, y1, x2, y2 = map(int, m)
            out.append((label.replace("\n", " / "), (x1 + x2) // 2, (y1 + y2) // 2))
    return out
cmd = sys.argv[1]
if cmd == "dump":
    for l, cx, cy in nodes(): print(f"{cx},{cy}\t{l}")
elif cmd in ("tap", "has"):
    sub = sys.argv[2]; idx = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    hits = [n for n in nodes() if sub in n[0]]
    if len(hits) <= idx: print("NOT FOUND", sub); sys.exit(1)
    l, cx, cy = hits[idx]
    if cmd == "tap": adb("shell", "input", "tap", str(cx), str(cy)); print("tapped", cx, cy, l[:80])
    else: print("found", cx, cy, l[:80])
