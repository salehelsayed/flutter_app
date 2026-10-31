#!/usr/bin/env python3
"""Type a Unicode text file into the focused Android field through io.appium.settings/.AppiumIME
(modified UTF-7 over `adb input text`), restore the original IME, then compare the field with the file.
Never prints the payload. Usage: step2_type_unicode.py <serial> <file> [--clear]
Prints MATCH or MISMATCH len=.. want=.. (and the first differing index)."""
import base64, html, os, re, subprocess, sys, time

serial, path = sys.argv[1], sys.argv[2]
env = dict(os.environ, ADB_SERVER_SOCKET=os.environ.get("ADB_SERVER_SOCKET", "tcp:host.docker.internal:5037"))
payload = open(path, encoding="utf-8").read().rstrip("\n")


def adb(*a):
    return subprocess.run(["adb", "-s", serial, *a], env=env, capture_output=True, text=True).stdout


def mutf7(s):
    out, buf = [], []
    def flush():
        if buf:
            b = "".join(buf).encode("utf-16-be")
            out.append("&" + base64.b64encode(b).decode().rstrip("=").replace("/", ",") + "-")
            buf.clear()
    for ch in s:
        if 0x20 <= ord(ch) <= 0x7e:
            flush()
            out.append("&-" if ch == "&" else ch)
        else:
            buf.append(ch)
    flush()
    return "".join(out)


orig = adb("shell", "settings get secure default_input_method").strip()
adb("shell", "ime enable io.appium.settings/.AppiumIME")
adb("shell", "ime set io.appium.settings/.AppiumIME")
time.sleep(1.5)
if "--clear" in sys.argv:
    adb("shell", "input keycombination 113 123")
    adb("shell", "input keyevent " + " ".join(["67"] * 400))
cps = list(payload)
i, CH = 0, 12
while i < len(cps):
    chunk = "".join(cps[i:i + CH]); i += CH
    enc = mutf7(chunk).replace(" ", "%s").replace("'", "'\\''")
    adb("shell", f"input text '{enc}'")
    time.sleep(0.15)
time.sleep(1)
adb("shell", f"ime set {orig}")
print("ime restored", orig.split("/")[0])
adb("shell", "rm -f /sdcard/u.xml")
adb("shell", "uiautomator dump /sdcard/u.xml")
x = adb("shell", "cat /sdcard/u.xml")
m = re.search(r'text="([^"]*)"[^>]*class="android.widget.EditText"', x)
got = html.unescape(m.group(1)) if m else ""
if got != payload:
    d = next((k for k, (a, b) in enumerate(zip(got, payload)) if a != b), min(len(got), len(payload)))
    print(f"first diff at {d}")
print("MATCH" if got == payload else f"MISMATCH len={len(got)} want={len(payload)}")
