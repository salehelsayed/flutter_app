#!/bin/bash
# Install mcp-proxy (stdio -> SSE/streamable HTTP, bindable host) with uv; drop the
# unused supergateway; show mcp-proxy options and the appium-mcp README essentials.
set -u
uv tool install mcp-proxy > "$HOME/tools/mcp/mcp-proxy-install.log" 2>&1; echo "uv rc=$?"; tail -2 "$HOME/tools/mcp/mcp-proxy-install.log"
MP=$(command -v mcp-proxy || echo "$HOME/.local/bin/mcp-proxy"); echo "mcp-proxy at $MP ($("$MP" --version 2>&1 | tail -1))"
npm uninstall --prefix "$HOME/tools/mcp" --no-fund --no-audit supergateway > /dev/null 2>&1; echo "supergateway removed rc=$?"
echo "--- mcp-proxy --help"; "$MP" --help 2>&1 | head -70
R="$HOME/tools/mcp/node_modules/appium-mcp/README.md"
echo "--- appium-mcp README (headings + env/config lines)"
grep -nE "^#|APPIUM|appium --|npx|capabilit|env|server|4723|port" "$R" | head -70
