#!/bin/bash
# Reinstall mcp-proxy with the MCP SDK pinned below 2, then start both MCP servers
# briefly on test ports and report the exact listen addresses. Stops them again.
set -u
. "$(dirname "$0")/beta_env.sh"
uv tool install --force mcp-proxy --with 'mcp<2' > "$HOME/tools/mcp/mcp-proxy-install.log" 2>&1; echo "uv rc=$?"
P="$HOME/.local/share/uv/tools/mcp-proxy/bin/python"
"$P" -c "import importlib.metadata as m; print('mcp-proxy', m.version('mcp-proxy'), 'mcp', m.version('mcp'))"
MP="$HOME/.local/bin/mcp-proxy"
"$MP" --help 2>&1 | grep -E "^\s+--(host|port|pass-environment|stateless|allow-origin|named-server)" | head -8
LOG="$HOME/tools/mcp/trial"; mkdir -p "$LOG"
"$MP" --host 127.0.0.1 --port 18931 --pass-environment -- maestro mcp --no-viewer > "$LOG/maestro.log" 2>&1 &
M=$!
APPIUM_MCP_ON_CLIENT_DISCONNECT=skip "$HOME/tools/mcp/node_modules/.bin/appium-mcp" --httpStream --port=18932 > "$LOG/appium.log" 2>&1 &
A=$!
sleep 15
echo "--- listening"
lsof -nP -iTCP:18931 -sTCP:LISTEN 2>/dev/null | tail -n +2
lsof -nP -iTCP:18932 -sTCP:LISTEN 2>/dev/null | tail -n +2
echo "--- maestro log"; tail -5 "$LOG/maestro.log"
echo "--- appium log"; tail -5 "$LOG/appium.log"
kill $M $A 2>/dev/null; sleep 1; pkill -f "port 18931" 2>/dev/null; pkill -f "port=18932" 2>/dev/null
echo "stopped"
