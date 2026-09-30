#!/bin/bash
# Read-only: appium-mcp CLI transport options; mcp-proxy's dependency versions.
. "$(dirname "$0")/beta_env.sh"
A="$HOME/tools/mcp/node_modules/.bin/appium-mcp"
echo "--- appium-mcp --help"; timeout 20 "$A" --help 2>&1 | head -40
R="$HOME/tools/mcp/node_modules/appium-mcp/README.md"
echo "--- README transport lines"; grep -niE "transport|--port|--host|httpStream|streamable|sse|bind|127\.0\.0\.1|0\.0\.0\.0" "$R" | head -30
P="$HOME/.local/share/uv/tools/mcp-proxy/bin/python"
echo "--- mcp-proxy venv versions"; "$P" -c "import importlib.metadata as m; print('mcp-proxy', m.version('mcp-proxy'), 'mcp', m.version('mcp'))"
