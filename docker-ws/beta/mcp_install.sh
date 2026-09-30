#!/bin/bash
# Install supergateway (stdio -> HTTP bridge) and appium-mcp into ~/tools/mcp
# (user-owned prefix, pinned versions), then print their CLI options.
set -u
. "$(dirname "$0")/beta_env.sh"
mkdir -p "$HOME/tools/mcp"
cd "$HOME/tools/mcp" || exit 1
npm install --prefix "$HOME/tools/mcp" --no-fund --no-audit supergateway@4.0.0 appium-mcp@1.95.0 > install.log 2>&1
echo "npm rc=$? (log: ~/tools/mcp/install.log)"; tail -3 install.log
BIN="$HOME/tools/mcp/node_modules/.bin"
ls "$BIN" | grep -iE "supergateway|appium" | tr '\n' ' '; echo
echo "--- supergateway --help"
"$BIN/supergateway" --help 2>&1 | head -60
