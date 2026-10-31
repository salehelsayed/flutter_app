#!/usr/bin/env python3
"""Crop a QR from a screenshot by bounds and place it on a 1280x960 white camera poster.
   python3 docker-ws/qr_crop_poster.py <screen.png> <x1> <y1> <x2> <y2> <poster.png>"""
import sys
from PIL import Image
s, x1, y1, x2, y2, out = sys.argv[1], *map(int, sys.argv[2:6]), sys.argv[6]
qr = Image.open(s).convert("RGB").crop((x1, y1, x2, y2)).resize((560, 560), Image.NEAREST)
p = Image.new("RGB", (1280, 960), "white"); p.paste(qr, (60, 200)); p.save(out); print("poster ok")
