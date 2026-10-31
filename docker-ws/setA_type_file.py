#!/usr/bin/env python3
"""Type a private payload (EmptyIME during typing, original IME restored) file into the focused Android field in 24-char chunks (never prints the payload).
Usage: setA_type_file.py <serial> <file>  -> then compares the field text with the file and prints MATCH or MISMATCH."""
import os, re, subprocess, sys, time

serial, path = sys.argv[1], sys.argv[2]
env = dict(os.environ, ADB_SERVER_SOCKET=os.environ.get("ADB_SERVER_SOCKET", "tcp:host.docker.internal:5037"))
payload = open(path).read().strip()


def adb(*a):
    return subprocess.run(["adb", "-s", serial, *a], env=env, capture_output=True, text=True).stdout


orig_ime = adb("shell", "settings get secure default_input_method").strip()
adb("shell", "ime set io.appium.settings/.EmptyIME")  # no autocorrect/autospace while typing JSON
time.sleep(1)
adb("shell", "input keycombination 113 123")  # ctrl+end, then delete any old text
adb("shell", "input keyevent " + " ".join(["67"] * 900))
adb("shell", "input keyevent " + " ".join(["112"] * 900))
for i in range(0, len(payload), 24):
    chunk = payload[i:i + 24].replace(" ", "%s").replace("'", "'\\''")
    adb("shell", f"input text '{chunk}'")
    time.sleep(0.3)
adb("shell", f"ime set {orig_ime}")
print("ime restored", orig_ime.split("/")[0])
adb("shell", "rm -f /sdcard/u.xml")
adb("shell", "uiautomator dump /sdcard/u.xml")
x = adb("shell", "cat /sdcard/u.xml")
import html
m = re.search(r"text=(?:\"([^\"]*)\"|'([^']*)')[^>]*class=\"android.widget.EditText\"", x)
got = html.unescape(m.group(1) or m.group(2)) if m else ""
if got != payload and got:
    d = next((i for i, (a, b) in enumerate(zip(got, payload)) if a != b), min(len(got), len(payload)))
    print(f"first diff at {d}")
print("MATCH" if got == payload else f"MISMATCH len={len(got)} want={len(payload)}")
