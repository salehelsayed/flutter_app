#!/usr/bin/env python3
"""Relaunch Mknoon on an iPhone with a launch-only language override, or plain.   AP_BASE=... tr129_ios_launch_lang.py <11|13> <de|none>"""
import os, sys, time
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "beta"))
import ap
ph, lang = sys.argv[1], sys.argv[2]
ex = lambda s, a: ap.req("POST", f"/session/{ap.sid(ph)}/execute/sync", {"script": s, "args": [a]})
ex("mobile: terminateApp", {"bundleId": ap.BUNDLE}); time.sleep(1)
a = {"bundleId": ap.BUNDLE}
if lang != "none": a["arguments"] = ["-AppleLanguages", f"({lang})"]
ex("mobile: launchApp", a); time.sleep(3)
print("launched", lang, "state", ex("mobile: queryAppState", {"bundleId": ap.BUNDLE}))
