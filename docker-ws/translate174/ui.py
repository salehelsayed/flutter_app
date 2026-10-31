#!/usr/bin/env python3
# ui.py <serial> dump [outfile] | tap <regex> | has <regex>
import os, re, subprocess, sys
os.environ.setdefault("ADB_SERVER_SOCKET", "tcp:host.docker.internal:5037")
def adb(s, *a, t=40):
    return subprocess.run(["adb", "-s", s, *a], capture_output=True, text=True, timeout=t).stdout
def nodes(s):
    xml = adb(s, "exec-out", "uiautomator", "dump", "/dev/tty")
    out = []
    for m in re.finditer(r'<node [^>]*>', xml):
        n = m.group(0)
        lab = " ".join(x for x in re.findall(r'(?:text|content-desc)="([^"]*)"', n) if x)
        b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', n)
        if lab and b:
            x1, y1, x2, y2 = map(int, b.groups())
            out.append(((x1 + x2) // 2, (y1 + y2) // 2, lab.replace("&#10;", " / ")))
    return out
s, cmd = sys.argv[1], sys.argv[2]
ns = nodes(s)
if cmd == "dump":
    txt = "\n".join(f"{x},{y}\t | {l}" for x, y, l in ns)
    print(txt)
    if len(sys.argv) > 3: open(sys.argv[3], "w").write(txt + "\n")
elif cmd in ("tap", "has"):
    hit = [n for n in ns if re.search(sys.argv[3], n[2])]
    if not hit: print("NOT FOUND", sys.argv[3]); sys.exit(1)
    x, y, l = hit[0]
    if cmd == "tap": adb(s, "shell", "input", "tap", str(x), str(y))
    print(cmd, x, y, l)
