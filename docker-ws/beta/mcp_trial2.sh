#!/bin/bash
# Start appium-mcp (httpStream) on a test port, wait up to 120 s for it to listen,
# report the listen address and startup time, then stop it.
set -u
. "$(dirname "$0")/beta_env.sh"
LOG="$HOME/tools/mcp/trial"; mkdir -p "$LOG"
t0=$(date +%s)
APPIUM_MCP_ON_CLIENT_DISCONNECT=skip "$HOME/tools/mcp/node_modules/.bin/appium-mcp" --httpStream --port=18932 > "$LOG/appium.log" 2>&1 &
A=$!
for i in $(seq 1 120); do
  lsof -nP -iTCP:18932 -sTCP:LISTEN >/dev/null 2>&1 && break
  kill -0 $A 2>/dev/null || break
  sleep 1
done
echo "after $(( $(date +%s) - t0 )) s:"
lsof -nP -iTCP:18932 -sTCP:LISTEN 2>/dev/null | tail -n +2
echo "--- appium log"; tail -8 "$LOG/appium.log"
kill $A 2>/dev/null; sleep 1; echo "stopped"
