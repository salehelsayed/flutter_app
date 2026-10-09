#!/usr/bin/env python3
"""Activate any app on the USB iPhone 13 through the private Appium session (ap.py 13 open first).
Usage: ios_app.py <bundleId>     e.g. com.apple.Preferences, com.mknoon.app
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import ap  # noqa: E402

bundle = sys.argv[1]
ap.req("POST", f"/session/{ap.sid('13')}/execute/sync",
       {"script": "mobile: activateApp", "args": [{"bundleId": bundle}]})
print("activated", bundle)
