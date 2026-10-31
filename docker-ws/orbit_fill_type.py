#!/usr/bin/env python3
"""Type any Unicode text (Arabic, German, emoji) into the focused field of an emulator that uses io.appium.settings/.UnicodeIME.
   orbit_fill_type.py <serial> <text>"""
import base64
import os
import subprocess
import sys
import time

serial, text = sys.argv[1], sys.argv[2]
env = dict(os.environ, ADB_SERVER_SOCKET=os.environ.get("ADB_SERVER_SOCKET", "tcp:host.docker.internal:5037"))


def tokens(s):
    """IMAP modified UTF-7 tokens; each token is safe to send on its own."""
    out, run = [], ""
    for ch in s + "\0":
        if ch != "\0" and not (0x20 <= ord(ch) < 0x7f):
            run += ch
            continue
        if run:
            b = base64.b64encode(run.encode("utf-16-be")).decode().rstrip("=").replace("/", ",")
            out.append("&" + b + "-")
            run = ""
        if ch == "\0":
            break
        out.append("&-" if ch == "&" else ("%s" if ch == " " else ch))
    return out


def adb(*a):
    subprocess.run(["adb", "-s", serial, *a], env=env, check=True)


for verb in ("enable", "set"):
    subprocess.run(["adb", "-s", serial, "shell", "ime", verb, "io.appium.settings/.UnicodeIME"], env=env, capture_output=True)
buf = ""
for t in tokens(text):
    if len(buf) + len(t) > 40:
        adb("shell", "input text '" + buf.replace("'", "'\\''") + "'")
        time.sleep(0.4)
        buf = ""
    buf += t
if buf:
    adb("shell", "input text '" + buf.replace("'", "'\\''") + "'")
print("typed", len(text), "chars")
