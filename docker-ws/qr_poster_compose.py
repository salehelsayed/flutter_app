#!/usr/bin/env python3
"""Place a QR PNG at the left of a 1280x960 white poster for the emulator imagefile camera.
   python3 docker-ws/qr_poster_compose.py <qr.png> <poster.png>"""
import sys
from PIL import Image
qr = Image.open(sys.argv[1]).convert("RGB")
side = 560
qr = qr.resize((side, side), Image.NEAREST)
p = Image.new("RGB", (1280, 960), "white")
p.paste(qr, (60, (960 - side) // 2))
p.save(sys.argv[2])
print("poster ok")
