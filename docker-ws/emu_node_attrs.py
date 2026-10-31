#!/usr/bin/env python3
"""Read-only: print checkable/checked/enabled attributes of UI nodes whose label contains a substring.
  emu_node_attrs.py <serial> <substr>"""
import subprocess, sys, re, html
S, sub = sys.argv[1], sys.argv[2]
def adb(*a): return subprocess.run(["timeout", "90", "adb", "-s", S, *a], capture_output=True, text=True).stdout
adb("shell", "uiautomator", "dump", "/sdcard/na.xml")
x = adb("shell", "cat", "/sdcard/na.xml")
for n in re.findall(r"<node [^>]*>", x):
    a = dict(re.findall(r'([\w-]+)="([^"]*)"', n))
    label = html.unescape(a.get("text", "") + " | " + a.get("content-desc", ""))
    if sub in label:
        print(label.replace("\n", " / ")[:90], {k: a.get(k) for k in ("class", "checkable", "checked", "enabled", "clickable", "bounds")})
