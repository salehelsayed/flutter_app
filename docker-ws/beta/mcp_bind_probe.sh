#!/bin/bash
# Read-only: how adb listens on the Mac, and which Python tool installers exist.
lsof -nP -iTCP:5037 -sTCP:LISTEN 2>/dev/null | head -3
echo "uv: $(command -v uv || ls ~/.local/bin/uv 2>/dev/null || echo none)"
echo "pipx: $(command -v pipx || echo none)"
echo "python3: $(command -v python3) $(python3 --version 2>&1)"
