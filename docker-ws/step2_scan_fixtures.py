#!/usr/bin/env python3
"""Scroll an open Mknoon chat upward page by page and collect every bubble label that contains a fixture.
  step2_scan_fixtures.py <android-serial|ios13> <pages> <out.txt> <fixture>...
Output lines: fixture | role prefix | suffix (time/transport) | page.  No payload text is written."""
import html, os, re, subprocess, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + "/beta")
dev, pages, out, fxs = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4:]
F = [(os.path.basename(f).split('.')[0], open(f, encoding="utf-8").read().rstrip("\n")) for f in fxs]
H = os.path.dirname(os.path.abspath(__file__))
env = dict(os.environ, ADB_SERVER_SOCKET="tcp:host.docker.internal:5037")
def source():
    tmp = "/tmp/claude-501/-workspace/22b600bc-30a8-40f5-8f72-cbdad6b4916a/scratchpad/scan_src.xml"
    if dev == "ios13":
        s = subprocess.run(["python3", f"{H}/beta/ap.py", "13", "src"], capture_output=True, text=True, timeout=180).stdout
    else:
        subprocess.run(["python3", f"{H}/step2_and_ap.py", dev, "src", tmp], capture_output=True, timeout=180, env=env)
        s = open(tmp, encoding="utf-8").read()
    return s
def swipe():
    if dev == "ios13":
        subprocess.run(["python3", f"{H}/beta/ap.py", "13", "swipe", "200", "250", "200", "650", "400"], capture_output=True, timeout=90)
    else:
        subprocess.run(["adb", "-s", dev, "shell", "input", "swipe", "540", "900", "540", "1600", "400"], env=env, timeout=60)
    time.sleep(1.5)
seen = {}
for p in range(pages):
    s = source()
    labels = []
    for m in re.finditer(r'(?:label|content-desc)="([^"]*)"', s):
        l = html.unescape(m.group(1))
        if l not in labels: labels.append(l)
    for l in labels:
        best = None
        for name, fx in F:
            if fx in l and (best is None or len(fx) > len(best[1])): best = (name, fx)
        if best:
            j = l.find(best[1]); key = (best[0], l[:j], l[j + len(best[1]):])
            seen.setdefault(key, p)
    swipe()
with open(out, "w") as o:
    for (n, pre, suf), p in sorted(seen.items()):
        o.write(f"{n} | {pre!r} | {suf!r} | page{p}\n")
print(open(out).read())
