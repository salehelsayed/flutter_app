#!/usr/bin/env python3
"""Pixel Wi-Fi-off resume try for the private translator download (Settings > Media & storage row visible).
  tr129_px_resume_try.py <trace-out> [start_gb=0.8] [off_secs=35] [after_secs=90]
Taps Get if shown, waits until progress >= start_gb, disables Wi-Fi for off_secs, re-enables, keeps tracing."""
import os, re, subprocess, sys, time
S = os.environ.get("PX_SERIAL", "21071FDF600CSC")
os.environ.setdefault("ADB_SERVER_SOCKET", "tcp:host.docker.internal:5037")
HERE = os.path.dirname(os.path.abspath(__file__))
out = open(sys.argv[1], "a"); start = float(sys.argv[2]) if len(sys.argv) > 2 else 0.8
off = int(sys.argv[3]) if len(sys.argv) > 3 else 35; after = int(sys.argv[4]) if len(sys.argv) > 4 else 90
def log(m):
    l = f"{time.strftime('%H:%M:%S', time.gmtime())} {m}"; print(l, flush=True); out.write(l + "\n"); out.flush()
def row():
    d = subprocess.run(["python3", f"{HERE}/px_ui.py", "dump"], capture_output=True, text=True, timeout=120).stdout
    return " ".join(l.split("|", 1)[-1].strip() for l in d.splitlines() if re.search(r"GB|Get|Remove|Pause|Resume|Wi-Fi|Waiting|Retry|Failed|Paused", l) and "Wi-Fi + cellular" not in l and not re.search(r"\| (Off|Wi-Fi)$", l))
def gb(r):
    m = re.search(r"([\d.]+) of 2\.6 GB", r); return float(m.group(1)) if m else None
def adb(*a): subprocess.run(["timeout", "30", "adb", "-s", S, *a], capture_output=True)
r = row(); log("start " + r)
if "Get" in r.split():
    subprocess.run(["python3", f"{HERE}/px_ui.py", "tap", "Get"], timeout=120); log("tapped Get")
t0 = time.time()
while time.time() - t0 < 300:
    r = row(); g = gb(r); log("pre " + r)
    if "Download on Wi-Fi" in r:
        subprocess.run(["python3", f"{HERE}/px_ui.py", "tap", "Download on Wi-Fi"], timeout=120); log("tapped Download on Wi-Fi")
    if g is not None and g >= start: break
adb("shell", "svc", "wifi", "disable"); log(f"WIFI OFF at {g} GB")
t1 = time.time()
while time.time() - t1 < off: log("off " + row())
adb("shell", "svc", "wifi", "enable"); log("WIFI ON")
t2 = time.time()
while time.time() - t2 < after:
    r = row(); log("post " + r)
    if "Remove" in r: break
