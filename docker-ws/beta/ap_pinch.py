#!/usr/bin/env python3
"""Two-finger pinch/spread on a USB iPhone through the private Appium session saved by ap.py (W3C pointer actions).
   ap_pinch.py <11|13> <cx> <cy> <start-offset> <end-offset> [ms]
   start < end = spread (zoom in), start > end = pinch. Fingers move on the diagonal through (cx, cy), in points."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ap  # noqa: E402

phone, cx, cy, a, b = sys.argv[1], *map(int, sys.argv[2:6])
ms = int(sys.argv[6]) if len(sys.argv) > 6 else 600


def finger(fid, sign):
    return {"type": "pointer", "id": fid, "parameters": {"pointerType": "touch"}, "actions": [
        {"type": "pointerMove", "duration": 0, "x": cx + sign * a, "y": cy + sign * a},
        {"type": "pointerDown", "button": 0}, {"type": "pause", "duration": 100},
        {"type": "pointerMove", "duration": ms, "x": cx + sign * b, "y": cy + sign * b},
        {"type": "pause", "duration": 100}, {"type": "pointerUp", "button": 0}]}


ap.req("POST", f"/session/{ap.sid(phone)}/actions", {"actions": [finger("f1", -1), finger("f2", 1)]})
print("pinch", "spread" if b > a else "in", cx, cy, a, "->", b)
